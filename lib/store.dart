// Delivery — حالة تطبيق المحل والاتصال بـ Firebase (نفس قاعدة بيانات الموقع)
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import 'notify.dart';

typedef Doc = Map<String, dynamic>;

final ShopState app = ShopState();

const loginDomain = 'delivery-dz.com';
const arriveKm = 0.15; // الموصّل على بعد 150 م أو أقل = وصل إلى المحل
const offerMs = 60000; // مدة عرض الطلب على الموصّل قبل الانتقال للذي بعده
const freshMs = 3 * 60000; // الموصّل "متصل فعلاً" إذا وصل موقعه خلال آخر 3 دقائق
const retryMs = 2 * 60000; // إذا رفض الجميع: يُعاد العرض على الأقرب بعد دقيقتين

int asInt(dynamic v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);
double? asD(dynamic v) => v is num ? v.toDouble() : null;
int msOf(dynamic v) {
  if (v is Timestamp) return v.millisecondsSinceEpoch;
  if (v is num) return v.toInt();
  return DateTime.now().millisecondsSinceEpoch;
}

int nowMs() => DateTime.now().millisecondsSinceEpoch;

String latinDigits(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = ar.indexOf(ch);
    final j = fa.indexOf(ch);
    b.write(i >= 0 ? '$i' : (j >= 0 ? '$j' : ch));
  }
  return b.toString();
}

int? parseInt(String s) => int.tryParse(latinDigits(s).replaceAll(RegExp(r'[\s,.]'), ''));
String cleanPhone(String p) => latinDigits(p).replaceAll(RegExp(r'[\s.\-]'), '');
bool phoneOk(String p) => RegExp(r'^0[5-7]\d{8}$').hasMatch(p);

String fmt(num n) {
  final s = n.round().abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}


/// كتابة في Firestore: تُحفظ في الهاتف فوراً وتظهر في الشاشة، ثم تُرسل حين يتوفر الاتصال.
/// لا ننتظر رد الخادم أكثر من 8 ثوانٍ حتى لا تعلق الأزرار مع الشبكة الضعيفة.
/// ترجع true إذا أكّد الخادم، و false إذا بقيت تنتظر الاتصال.
Future<bool> queued(Future<void> write) async {
  try {
    await write.timeout(const Duration(seconds: 8));
    return true;
  } on TimeoutException {
    return false;
  }
}

const pendingNote = 'سيُرسل عند عودة الاتصال';

String money(num n) => '${fmt(n)} دج';
String two(int n) => n.toString().padLeft(2, '0');
String clock(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${two(d.hour)}:${two(d.minute)}';
}

String ago(int ms) {
  final m = (nowMs() - ms) ~/ 60000;
  if (m < 1) return 'الآن';
  if (m < 60) return 'منذ $m د';
  final h = m ~/ 60;
  if (h < 24) return 'منذ $h سا';
  return 'منذ ${h ~/ 24} يوم';
}

String schedText(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  final diff = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  final label = diff == 0 ? 'اليوم' : (diff == 1 ? 'غداً' : '${d.day}/${d.month}');
  return '$label ${clock(ms)}';
}

int startOfToday() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day).millisecondsSinceEpoch;
}

String kmText(double d) => d < 1 ? '${(d * 1000).round()} م' : '${d.toStringAsFixed(1)} كم';

double? km(double? aLat, double? aLng, double? bLat, double? bLng) {
  if (aLat == null || aLng == null || bLat == null || bLng == null) return null;
  const r = 6371.0;
  final dLa = (bLat - aLat) * math.pi / 180, dLo = (bLng - aLng) * math.pi / 180;
  final x = math.sin(dLa / 2) * math.sin(dLa / 2) +
      math.cos(aLat * math.pi / 180) * math.cos(bLat * math.pi / 180) * math.sin(dLo / 2) * math.sin(dLo / 2);
  return 2 * r * math.atan2(math.sqrt(x), math.sqrt(1 - x));
}

bool isAny(Doc o) => o['kind'] == 'any';

String optsText(Map i) {
  final a = <String>[];
  if ((i['size'] ?? '').toString().isNotEmpty) a.add('${i['size']}');
  final ex = i['extras'];
  if (ex is List && ex.isNotEmpty) a.add('+ ${ex.join('، ')}');
  if ((i['note'] ?? '').toString().isNotEmpty) a.add('«${i['note']}»');
  return a.join(' · ');
}

List<Map> itemsOf(Doc o) => (o['items'] is List) ? (o['items'] as List).whereType<Map>().toList() : <Map>[];

List<Doc> optList(dynamic v) =>
    v is List ? v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() : <Doc>[];
bool hasOpts(Doc p) => optList(p['sizes']).isNotEmpty || optList(p['extras']).isNotEmpty;
int basePrice(Doc p) {
  final s = optList(p['sizes']);
  if (s.isNotEmpty) return s.map((x) => asInt(x['price'])).reduce(math.min);
  return asInt(p['price']);
}

/// «صغير 300» ← {name:'صغير', price:300} — سطر لكل خيار (نفس قاعدة الموقع)
List<Doc> parseOpts(String txt) {
  final re = RegExp(r'^(.*?)[\s:=\-]*(\d+)\s*(دج|da)?$', caseSensitive: false);
  final out = <Doc>[];
  for (var l in txt.split(RegExp(r'\n|،|,'))) {
    l = latinDigits(l).trim();
    final m = re.firstMatch(l);
    if (m == null || m.group(1)!.trim().isEmpty) continue;
    final n = m.group(1)!.trim();
    out.add({'name': n.length > 40 ? n.substring(0, 40) : n, 'price': int.parse(m.group(2)!)});
    if (out.length >= 15) break;
  }
  return out;
}

String optsToText(dynamic a) => optList(a).map((x) => '${x['name']} ${x['price']}').join('\n');

int? hm(String? s) {
  if (s == null || !RegExp(r'^\d{1,2}:\d{2}$').hasMatch(s)) return null;
  final p = s.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

bool withinHours(Doc? s) {
  final h = s?['hours'];
  if (h is! Map) return true;
  final f = hm(h['from']), t = hm(h['to']);
  if (f == null || t == null) return true;
  final d = DateTime.now(), n = d.hour * 60 + d.minute;
  return f <= t ? (n >= f && n < t) : (n >= f || n < t);
}

String couponLabel(Doc c) => c['type'] == 'pct' ? 'خصم ${asInt(c['value'])}%' : 'خصم ${fmt(asInt(c['value']))} دج';

Uint8List? dataUrlBytes(String? d) {
  if (d == null) return null;
  final i = d.indexOf(',');
  try {
    return base64Decode(i >= 0 ? d.substring(i + 1) : d);
  } catch (_) {
    return null;
  }
}

String errText(Object e) {
  String code = '';
  if (e is FirebaseAuthException) code = 'auth/${e.code}';
  if (e is FirebaseException && e is! FirebaseAuthException) code = e.code;
  const m = {
    'auth/invalid-credential': 'رقم الهاتف أو كلمة السر غير صحيحة.',
    'auth/invalid-login-credentials': 'رقم الهاتف أو كلمة السر غير صحيحة.',
    'auth/wrong-password': 'رقم الهاتف أو كلمة السر غير صحيحة.',
    'auth/user-not-found': 'رقم الهاتف أو كلمة السر غير صحيحة.',
    'auth/invalid-email': 'رقم الهاتف غير صحيح.',
    'auth/too-many-requests': 'محاولات كثيرة. انتظر قليلاً ثم أعد المحاولة.',
    'auth/network-request-failed': 'لا يوجد اتصال بالإنترنت. تحقق من الشبكة وأعد المحاولة.',
    'permission-denied': 'ليست لديك صلاحية لهذه العملية.',
    'unavailable': 'لا يوجد اتصال بالخادم الآن. أعد المحاولة بعد قليل.',
    'not-found': 'لم نجد هذه البيانات. قد تكون حُذفت.',
  };
  return m[code] ?? 'حدث خطأ غير متوقع (${code.isEmpty ? e : code}).';
}

class ShopState extends ChangeNotifier {
  final auth = FirebaseAuth.instance;
  final fs = FirebaseFirestore.instance;
  final _player = AudioPlayer();

  bool ready = false;
  User? user;
  String role = ''; // '' | resolving | shop | unlinked | error
  String roleErr = '';
  String? shopId;

  Doc config = {};
  List<Doc> shops = [], products = [], coupons = [], couriers = [], orders = [];
  bool loadedOrders = false, loadedProducts = false, loadedCoupons = false, loadedCouriers = false;

  final List<StreamSubscription> _subs = [];
  Timer? _dispatchTimer, _ringTimer;
  StreamSubscription<Position>? _keepAlive;
  final Map<String, bool> _inflight = {};
  final Map<String, int> _dispSeen = {};
  final Map<String, String?> images = {}; // id:v -> data url (null = none)
  final Set<String> _newNotified = {}; // طلبات جديدة ظهر لها إشعار
  final Map<String, String> _dispatchSeen = {};
  final Set<String> _arrived = {}; // طلبات وصل موصّلها إلى المحل ونُبّه لها
  final Map<String, String> _statusSeen = {};
  void Function(String msg)? onToast;

  void toast(String m) => onToast?.call(m);

  Future<void> init() async {
    auth.authStateChanges().listen(_onUser);
    _dispatchTimer = Timer.periodic(const Duration(seconds: 4), (_) => _dispatchTick());
    _ringTimer = Timer.periodic(const Duration(seconds: 7), (_) => _ring());
  }

  // ---------------- auth ----------------
  Future<void> _onUser(User? u) async {
    _stopAll();
    stopKeepAlive();
    user = u;
    shopId = null;
    orders = [];
    products = [];
    coupons = [];
    couriers = [];
    loadedOrders = loadedProducts = loadedCoupons = loadedCouriers = false;
    role = '';
    roleErr = '';
    ready = true;
    if (u == null || u.isAnonymous) {
      if (u != null) role = 'unlinked';
      notifyListeners();
      return;
    }
    role = 'resolving';
    notifyListeners();
    try {
      final r = await fs.collection('users').doc(u.uid).get();
      final d = r.data();
      if (d != null && d['shopId'] != null && d['role'] != 'courier') {
        role = 'shop';
        shopId = '${d['shopId']}';
        _startShop();
      } else {
        role = 'unlinked';
      }
    } catch (e) {
      role = 'error';
      roleErr = errText(e);
    }
    notifyListeners();
  }

  Future<void> login(String phone, String pass) async {
    await auth.signInWithEmailAndPassword(email: '${cleanPhone(phone)}@$loginDomain', password: pass);
  }

  Future<void> logout() async {
    stopKeepAlive();
    await auth.signOut();
  }

  void _stopAll() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  Doc _doc(DocumentSnapshot<Map<String, dynamic>> d) {
    final x = Map<String, dynamic>.from(d.data() ?? {});
    x['id'] = d.id;
    x['createdAtMs'] = msOf(x['createdAt']);
    return x;
  }

  void _startShop() {
    final sid = shopId!;
    notify.requestPermission();
    _subs.add(fs.collection('shops').snapshots().listen((s) {
      shops = s.docs.map(_doc).toList();
      final me = shop;
      if (me != null && me['open'] == true && _keepAlive == null) startKeepAlive();
      if (me != null && me['open'] != true && _keepAlive != null) stopKeepAlive();
      notifyListeners();
    }, onError: (e) => toast(errText(e))));
    _subs.add(fs.collection('config').doc('platform').snapshots().listen((s) {
      config = s.data() ?? {};
      notifyListeners();
    }, onError: (_) {}));
    _subs.add(fs.collection('products').where('shopId', isEqualTo: sid).snapshots().listen((s) {
      products = s.docs.map(_doc).toList()
        ..sort((a, b) {
          final c = '${a['section'] ?? ''}'.compareTo('${b['section'] ?? ''}');
          return c != 0 ? c : asInt(a['pos']).compareTo(asInt(b['pos']));
        });
      loadedProducts = true;
      notifyListeners();
    }, onError: (e) => toast(errText(e))));
    _subs.add(fs.collection('coupons').where('shopId', isEqualTo: sid).snapshots().listen((s) {
      coupons = s.docs.map(_doc).toList()..sort((a, b) => asInt(b['createdAtMs']).compareTo(asInt(a['createdAtMs'])));
      loadedCoupons = true;
      notifyListeners();
    }, onError: (_) {}));
    _subs.add(fs.collection('couriers').snapshots().listen((s) {
      couriers = s.docs.map(_doc).toList();
      loadedCouriers = true;
      notifyListeners();
    }, onError: (_) {}));
    bool first = true;
    _subs.add(fs.collection('orders').where('shopId', isEqualTo: sid).snapshots().listen((s) {
      orders = s.docs.map(_doc).toList()..sort((a, b) => asInt(b['createdAtMs']).compareTo(asInt(a['createdAtMs'])));
      loadedOrders = true;
      if (!first) {
        final fresh = s.docChanges.where((c) => c.type == DocumentChangeType.added && c.doc.data()?['status'] == 'new').length;
        if (fresh > 0) toast(fresh > 1 ? 'وصلت $fresh طلبات جديدة' : 'طلب جديد وصل إلى محلك');
      }
      _notifyOrders(first);
      first = false;
      _ring();
      notifyListeners();
    }, onError: (e) => toast(errText(e))));
  }

  // إشعارات الهاتف (تظهر والتطبيق في الخلفية فقط)
  void _notifyOrders(bool first) {
    final stillNew = <String>{};
    for (final o in orders) {
      final id = '${o['id']}';
      if (o['status'] == 'new') {
        stillNew.add(id);
        if (_newNotified.add(id) && !first) {
          notify.newOrder(id, 'طلب جديد · ${money(shopDue(o))}',
              '${itemsOf(o).map((i) => '${asInt(i['qty'])}× ${i['name'] ?? ''}').join('، ')} · اضغط لتقبله');
        }
      }
      final d = '${o['dispatch'] ?? ''}', was = _dispatchSeen[id];
      _dispatchSeen[id] = d;
      if (!first && was != null && was != 'none' && d == 'none' && o['courierUid'] == null) {
        notify.update('nocourier:$id', 'لا يوجد موصّل متاح · طلب ${o['no'] ?? ''}',
            'سيُعرض تلقائياً على أول موصّل يتصل.', 'order:$id');
      }
    }
    // أُلغي طلب كان جديداً أو قيد التحضير (ألغاه الزبون أو الإدارة)
    for (final o in orders) {
      final id = '${o['id']}', st = '${o['status'] ?? ''}', was = _statusSeen[id];
      _statusSeen[id] = st;
      if (first || was == null || st != 'cancelled' || !['new', 'prep', 'ready'].contains(was)) continue;
      final title = 'أُلغي الطلب ${o['no'] ?? ''}';
      final body = was == 'new' ? 'ألغاه الزبون قبل أن تقبله.' : 'أوقف تحضيره ولا تسلّمه لأي موصّل.';
      toast('$title · $body');
      _beep();
      notify.update('cancel:$id', title, body, 'order:$id');
    }
    // الموصّل وصل إلى المحل
    for (final o in orders) {
      final id = '${o['id']}';
      if (!['prep', 'ready'].contains(o['status']) || o['courierUid'] == null) continue;
      final c = courierNear(o);
      if (c == null || c.km > arriveKm || !_arrived.add(id)) continue;
      if (first) continue;
      final msg = '${o['courierName'] ?? 'الموصّل'} وصل لاستلام الطلب ${o['no'] ?? ''}';
      toast(msg);
      _beep();
      notify.update('arrive:$id', 'الموصّل عند المحل', msg, 'order:$id');
    }
    for (final id in _newNotified.where((x) => !stillNew.contains(x)).toList()) {
      _newNotified.remove(id);
      notify.cancelOrder(id);
    }
  }

  // ---------------- derived ----------------
  Doc? get shop {
    for (final s in shops) {
      if (s['id'] == shopId) return s;
    }
    return null;
  }

  bool get isOpen => shop?['open'] == true;
  int shopDue(Doc o) => isAny(o) ? 0 : math.max(0, asInt(o['subtotal']) - asInt(o['discount']));
  List<Doc> byStatus(String st) => orders.where((o) => o['status'] == st).toList();
  List<Doc> get history => orders.where((o) => !['new', 'prep', 'ready'].contains(o['status'])).toList();
  int get newCount => orders.where((o) => o['status'] == 'new').length;

  Doc? product(String id) {
    for (final p in products) {
      if (p['id'] == id) return p;
    }
    return null;
  }

  List<String> get sections {
    final l = <String>[];
    for (final p in products) {
      final s = '${p['section'] ?? ''}';
      if (s.isNotEmpty && !l.contains(s)) l.add(s);
    }
    return l;
  }

  /// يجلب صورة من مجموعة images (نفس طريقة الموقع: data URL مضغوط)
  String? image(String id, bool has, dynamic v) {
    if (!has) return null;
    final key = '$id:${v ?? 0}';
    if (!images.containsKey(key)) {
      images[key] = null;
      fs.collection('images').doc(id).get().then((s) {
        images[key] = s.exists ? '${s.data()?['data'] ?? ''}' : null;
        notifyListeners();
      }).catchError((_) {});
    }
    return images[key];
  }

  String? productImage(Doc p) => image('${p['id']}', p['hasImg'] == true, p['imgV']);
  String? coverImage() {
    final s = shop;
    if (s == null) return null;
    return image('cover_${s['id']}', s['hasCover'] == true, s['coverV']);
  }

  /// بُعد الموصّل المعيَّن عن المحل ووقت وصوله التقريبي، من آخر موقع كتبه على الطلب (خلال 3 دقائق)
  ({double km, int min})? courierNear(Doc o) {
    if (o['courierUid'] == null || o['cAt'] == null || nowMs() - asInt(o['cAt']) > 3 * 60000) return null;
    final s = shop;
    final d = km(asD(s?['lat']), asD(s?['lng']), asD(o['cLat']), asD(o['cLng']));
    if (d == null) return null;
    return (km: d, min: math.max(1, (d / 0.33 * 1.3).round()));
  }

  // ---------------- alerts ----------------
  Future<void> _beep() async {
    try {
      await _player.stop();
      await _player.play(AssetSource('alert.wav'));
    } catch (_) {}
    HapticFeedback.mediumImpact();
  }

  Future<void> _ring() async {
    if (role != 'shop' || newCount == 0) return;
    try {
      await _player.stop();
      await _player.play(AssetSource('alert.wav'));
    } catch (_) {}
    HapticFeedback.heavyImpact();
  }

  // يبقي التطبيق حياً والشاشة مطفأة ما دام المحل مفتوحاً (إشعار ثابت)، لتصل الطلبات ويستمر توزيعها على الموصّلين
  Future<void> startKeepAlive() async {
    if (_keepAlive != null) return;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final settings = defaultTargetPlatform == TargetPlatform.android
          ? AndroidSettings(
              accuracy: LocationAccuracy.low,
              distanceFilter: 500,
              intervalDuration: const Duration(minutes: 5),
              foregroundNotificationConfig: const ForegroundNotificationConfig(
                notificationTitle: 'محلك مفتوح في Delivery',
                notificationText: 'تصلك الطلبات الجديدة حتى والشاشة مطفأة',
                enableWakeLock: true,
                setOngoing: true,
              ),
            )
          : const LocationSettings(accuracy: LocationAccuracy.low, distanceFilter: 500);
      _keepAlive = Geolocator.getPositionStream(locationSettings: settings).listen((_) {}, onError: (_) {});
    } catch (_) {}
  }

  void stopKeepAlive() {
    _keepAlive?.cancel();
    _keepAlive = null;
  }

  // ---------------- dispatcher: nearest courier first ----------------
  // نفس منطق الموقع: يعمل على هاتف المحل. لكل طلب مقبول بدون موصّل: يُعرض على أقرب موصّل متصل لم يرفضه،
  // وإذا رفض أو انتهت الدقيقة ينتقل للذي بعده.
  bool courierFresh(Doc c) => c['online'] == true && c['active'] != false && (nowMs() - asInt(c['seenAt'])) < freshMs;

  int _localAge(Doc o) {
    final k = '${o['id']}|${o['offerTo'] ?? ''}|${o['offerAt'] ?? 0}|${o['dispatch'] ?? ''}';
    _dispSeen.putIfAbsent(k, nowMs);
    return nowMs() - _dispSeen[k]!;
  }

  List<Doc> _rank(Doc o, List declined) {
    final s = shop;
    double? oLat = asD(s?['lat']), oLng = asD(s?['lng']);
    if (oLat == null) {
      oLat = asD(o['custLat']);
      oLng = asD(o['custLng']);
    }
    final l = couriers.where((c) => courierFresh(c) && !declined.contains(c['id'])).map((c) {
      return (c: c, d: km(oLat, oLng, asD(c['lat']), asD(c['lng'])));
    }).toList();
    l.sort((a, b) {
      if (a.d == null && b.d == null) return asInt(b.c['seenAt']).compareTo(asInt(a.c['seenAt']));
      if (a.d == null) return 1;
      if (b.d == null) return -1;
      return a.d!.compareTo(b.d!);
    });
    return l.map((x) => x.c).toList();
  }

  void _dispatchTick() {
    if (role != 'shop' || !loadedCouriers) return;
    for (final o in orders) {
      final id = '${o['id']}';
      if (!['prep', 'ready'].contains(o['status']) || o['courierUid'] != null || _inflight[id] == true || isAny(o)) continue;
      final age = _localAge(o);
      final expired = o['offerTo'] != null && age > offerMs;
      if (o['offerTo'] != null && !expired) continue;
      final declined = List.from((o['declined'] is List) ? o['declined'] as List : const []);
      if (expired && !declined.contains(o['offerTo'])) declined.add(o['offerTo']);
      final cands = _rank(o, declined);
      Map<String, dynamic> upd;
      if (cands.isNotEmpty) {
        upd = {'offerTo': cands.first['id'], 'offerAt': nowMs(), 'declined': declined, 'dispatch': 'searching'};
      } else if (o['dispatch'] == 'none' && !expired) {
        // رفض الجميع: بعد دقيقتين نبدأ من جديد من الأقرب
        if (!(declined.isNotEmpty && couriers.any(courierFresh) && age > retryMs)) continue;
        upd = {'offerTo': null, 'offerAt': null, 'declined': [], 'dispatch': 'searching'};
      } else {
        upd = {'offerTo': null, 'offerAt': nowMs(), 'declined': declined, 'dispatch': 'none'};
      }
      final ref = fs.collection('orders').doc(id);
      _inflight[id] = true;
      fs.runTransaction((t) async {
        final s = await t.get(ref);
        final x = s.data();
        if (x == null || x['courierUid'] != null || x['offerTo'] != o['offerTo'] || x['offerAt'] != o['offerAt']) return;
        t.update(ref, upd);
      }).catchError((_) {}).whenComplete(() => _inflight[id] = false);
    }
  }

  // ---------------- order actions ----------------
  Future<bool> setStatus(String id, String status, String okMsg, [Map<String, dynamic>? extra]) async {
    try {
      final sent = await queued(
          fs.collection('orders').doc(id).update({'status': status, 'updatedAt': FieldValue.serverTimestamp(), ...?extra}));
      toast(sent ? okMsg : '$okMsg · $pendingNote');
      return true;
    } catch (e) {
      toast(errText(e));
      return false;
    }
  }

  Future<bool> accept(String id) => setStatus(id, 'prep', 'قبلت الطلب · يُعرض الآن على أقرب موصّل',
      {'dispatch': 'searching', 'offerTo': null, 'offerAt': null, 'declined': [], 'prepAt': nowMs()});
  Future<bool> reject(String id) => setStatus(id, 'rejected', 'رُفض الطلب');
  Future<bool> markReady(String id) => setStatus(id, 'ready', 'الطلب جاهز، في انتظار الموصّل');
  /// كم دقيقة بقيت على جاهزية طلب قيد التحضير (سالب = متأخر). null إذا لم يبدأ التحضير.
  int? prepLeft(Doc o) {
    if (o['status'] != 'prep' || o['prepAt'] == null) return null;
    final s = shop;
    final prep = s != null && asInt(s['prepMin']) > 0 ? asInt(s['prepMin']) : 15;
    return ((asInt(o['prepAt']) + prep * 60000 - nowMs()) / 60000).ceil();
  }

  /// يؤخر وقت الجاهزية 10 دقائق. يرى الزبون وقت الوصول الجديد مباشرة،
  /// لأن تطبيقه يحسبه من وقت بدء التحضير (prepAt).
  Future<bool> delay(Doc o) async {
    final left = prepLeft(o) ?? 0;
    if (left > 45) {
      toast('الطلب متأخر كثيراً. اتصل بالزبون أو بالإدارة.');
      return false;
    }
    final base = math.max(asInt(o['prepAt'] ?? nowMs()), left < 0 ? nowMs() - _prepMs() : 0);
    try {
      final sent = await queued(
          fs.collection('orders').doc(o['id']).update({'prepAt': base + 10 * 60000, 'updatedAt': FieldValue.serverTimestamp()}));
      toast(sent ? 'أُبلغ الزبون أن طلبه يحتاج 10 دقائق إضافية' : 'سيُبلَّغ الزبون عند عودة الاتصال');
      return true;
    } catch (e) {
      toast(errText(e));
      return false;
    }
  }

  int _prepMs() {
    final s = shop;
    return (s != null && asInt(s['prepMin']) > 0 ? asInt(s['prepMin']) : 15) * 60000;
  }

  Future<bool> handed(String id) => setStatus(id, 'road', 'سُلّم الطلب للموصّل', {'pickedAt': nowMs()});

  // ---------------- shop actions ----------------
  Future<void> toggleOpen() async {
    final s = shop;
    if (s == null) return;
    final v = s['open'] != true;
    try {
      final sent = await queued(fs.collection('shops').doc(shopId).update({'open': v}));
      final msg = v ? 'محلك مفتوح ويستقبل الطلبات' : 'محلك مغلق الآن';
      toast(sent ? msg : '$msg · $pendingNote');
    } catch (e) {
      toast(errText(e));
    }
  }

  Future<String> saveLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return 'شغّل GPS في الهاتف ثم أعد المحاولة.';
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return 'رفضت إذن الموقع. اسمح به من إعدادات الهاتف › التطبيقات › Delivery محل › الأذونات.';
      }
      final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)));
      await fs.collection('shops').doc(shopId).update({
        'lat': double.parse(p.latitude.toStringAsFixed(6)),
        'lng': double.parse(p.longitude.toStringAsFixed(6)),
      });
      toast('حُفظ موقع المحل');
      return '';
    } catch (e) {
      return e is FirebaseException ? errText(e) : 'تعذّر تحديد الموقع. شغّل GPS ثم أعد المحاولة.';
    }
  }

  /// cover: null = لا تغيير، '' = إزالة، غير ذلك = صورة جديدة (data URL)
  Future<String> saveSettings(
      {required String from, required String to, required int minOrder, required int prepMin, required String desc, String? cover}) async {
    final s = shop;
    if (s == null) return 'المحل غير موجود.';
    if ((from.isNotEmpty) != (to.isNotEmpty)) return 'اختر ساعة الفتح وساعة الإغلاق معاً، أو اتركهما فارغتين.';
    final b = fs.batch();
    final upd = <String, dynamic>{
      'hours': from.isNotEmpty ? {'from': from, 'to': to} : null,
      'minOrder': minOrder,
      'prepMin': prepMin,
      'desc': desc.length > 80 ? desc.substring(0, 80) : desc,
    };
    final cid = 'cover_${s['id']}';
    if (cover != null) {
      if (cover.isNotEmpty) {
        final v = nowMs();
        b.set(fs.collection('images').doc(cid), {'shopId': s['id'], 'data': cover});
        upd['hasCover'] = true;
        upd['coverV'] = v;
        images['$cid:$v'] = cover;
      } else {
        if (s['hasCover'] == true) b.delete(fs.collection('images').doc(cid));
        upd['hasCover'] = false;
      }
    }
    b.update(fs.collection('shops').doc(s['id']), upd);
    try {
      await b.commit();
      toast('حُفظت إعدادات المحل');
      return '';
    } catch (e) {
      return errText(e);
    }
  }

  /// img: null = لا تغيير، '' = إزالة، غير ذلك = صورة جديدة
  Future<String> saveProduct({
    String? editId,
    required String name,
    required int price,
    required String section,
    required String desc,
    required List<Doc> sizes,
    required List<Doc> extras,
    required bool available,
    String? img,
  }) async {
    final old = editId == null ? null : product(editId);
    final ref = editId != null ? fs.collection('products').doc(editId) : fs.collection('products').doc();
    final imgChanged = img != null;
    final hasImg = imgChanged ? img.isNotEmpty : (old?['hasImg'] == true);
    final data = <String, dynamic>{
      'shopId': shopId,
      'name': name,
      'price': price,
      'section': section.isEmpty ? 'منتجات أخرى' : section,
      'available': available,
      'hasImg': hasImg,
      'desc': desc.length > 140 ? desc.substring(0, 140) : desc,
      'sizes': sizes,
      'extras': extras,
    };
    if (imgChanged) data['imgV'] = nowMs();
    if (editId == null) data['pos'] = nowMs();
    final b = fs.batch();
    if (editId != null) {
      b.update(ref, data);
    } else {
      b.set(ref, data);
    }
    if (imgChanged) {
      if (img.isNotEmpty) {
        b.set(fs.collection('images').doc(ref.id), {'shopId': shopId, 'data': img});
        images['${ref.id}:${data['imgV']}'] = img;
      } else if (old?['hasImg'] == true) {
        b.delete(fs.collection('images').doc(ref.id));
      }
    }
    try {
      await b.commit();
      toast(editId != null ? 'حُفظت التعديلات' : 'أُضيف «$name» إلى محلك');
      return '';
    } catch (e) {
      return errText(e);
    }
  }

  Future<void> toggleProduct(Doc p) async {
    try {
      if (!await queued(fs.collection('products').doc(p['id']).update({'available': p['available'] != true}))) {
        toast(pendingNote);
      }
    } catch (e) {
      toast(errText(e));
    }
  }

  Future<bool> deleteProduct(Doc p) async {
    final b = fs.batch();
    b.delete(fs.collection('products').doc(p['id']));
    if (p['hasImg'] == true) b.delete(fs.collection('images').doc(p['id']));
    try {
      await b.commit();
      toast('حُذف المنتج');
      return true;
    } catch (e) {
      toast(errText(e));
      return false;
    }
  }

  Future<String> addCoupon(
      {required String code, required String type, required int value, required int minOrder, int? until, required bool once}) async {
    if (!RegExp(r'^[A-Z0-9]{3,15}$').hasMatch(code)) return 'الرمز من 3 إلى 15 حرفاً لاتينياً أو رقماً، بدون فراغ.';
    if (coupons.any((c) => c['code'] == code)) return 'عندك عرض بنفس الرمز.';
    if (value <= 0) return 'اكتب قيمة الخصم.';
    if (type == 'pct' && value > 90) return 'أكبر نسبة 90%.';
    try {
      await fs.collection('coupons').add({
        'shopId': shopId,
        'code': code,
        'type': type,
        'value': value,
        'minOrder': minOrder,
        'until': until,
        'once': once,
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
        'createdAtMs': nowMs(),
      });
      toast('أُنشئ العرض $code ويظهر الآن للزبائن');
      return '';
    } catch (e) {
      return errText(e);
    }
  }

  Future<void> toggleCoupon(Doc c) async {
    try {
      await fs.collection('coupons').doc(c['id']).update({'active': c['active'] == false});
    } catch (e) {
      toast(errText(e));
    }
  }

  Future<void> deleteCoupon(Doc c) async {
    try {
      await fs.collection('coupons').doc(c['id']).delete();
      toast('حُذف العرض');
    } catch (e) {
      toast(errText(e));
    }
  }

  @override
  void dispose() {
    _dispatchTimer?.cancel();
    _ringTimer?.cancel();
    super.dispose();
  }
}
