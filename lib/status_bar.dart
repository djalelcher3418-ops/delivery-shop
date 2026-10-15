// شريطا الحالة فوق كل الصفحات: «لا يوجد اتصال» و«نسخة جديدة متاحة»
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// رقم هذه النسخة، يمرّره البناء على GitHub (--dart-define=BUILD=رقم البناء). 0 = بناء محلي.
const appBuild = int.fromEnvironment('BUILD');
const _releasesApi = 'https://api.github.com/repos/djalelcher3418-ops/delivery-shop/releases/latest';

final AppStatus status = AppStatus();

class AppStatus extends ChangeNotifier {
  bool offline = false;
  int? newBuild;
  String? newUrl;
  bool updateDismissed = false;

  /// الإعفاء من تحسين البطارية: بدونه يقطع الهاتف الشبكة عن التطبيق في الخلفية فلا تصل التنبيهات
  static const _battery = MethodChannel('dz.delivery/battery');
  bool batteryOk = true, batteryDismissed = false;

  /// يحددها كل تطبيق: متى يحتاج العمل في الخلفية (الموصّل متصل، المحل مفتوح، للزبون طلب جارٍ)
  bool Function()? batteryRelevant;

  /// حالة التطبيق التي يتغير معها batteryRelevant، ليتحدّث الشريط
  Listenable? watch;

  bool get showBattery => !batteryOk && !batteryDismissed && (batteryRelevant?.call() ?? false);

  Future<void> checkBattery() async {
    try {
      batteryOk = await _battery.invokeMethod<bool>('isIgnoring') ?? true;
    } catch (_) {
      batteryOk = true; // هاتف لا يدعمها: لا نزعج المستخدم
    }
    notifyListeners();
  }

  Future<void> fixBattery() async {
    try {
      await _battery.invokeMethod('request');
    } catch (_) {}
  }

  void dismissBattery() {
    batteryDismissed = true;
    notifyListeners();
  }

  StreamSubscription? _net;
  Timer? _offTimer;
  int _lastCheck = 0;

  void start() {
    FirebaseAuth.instance.authStateChanges().listen((_) => _watchNet());
    _watchNet();
    checkUpdate();
    checkBattery();
    AppLifecycleListener(onResume: () {
      checkUpdate();
      checkBattery(); // بعد الرجوع من شاشة الإذن
    });
  }

  // Firestore يعلّم اللقطة بأنها «من الذاكرة» عندما ينقطع الاتصال بالخادم
  void _watchNet() {
    _net?.cancel();
    _net = FirebaseFirestore.instance
        .collection('config')
        .doc('platform')
        .snapshots(includeMetadataChanges: true)
        .listen((s) => _setOffline(s.metadata.isFromCache), onError: (_) {});
  }

  void _setOffline(bool fromCache) {
    if (fromCache) {
      // ننتظر قليلاً حتى لا يومض الشريط عند فتح التطبيق
      _offTimer ??= Timer(const Duration(seconds: 6), () {
        offline = true;
        notifyListeners();
      });
    } else {
      _offTimer?.cancel();
      _offTimer = null;
      if (offline) {
        offline = false;
        notifyListeners();
      }
    }
  }

  void dismissUpdate() {
    updateDismissed = true;
    notifyListeners();
  }

  Future<void> checkUpdate() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (appBuild == 0 || now - _lastCheck < 3600000) return;
    _lastCheck = now;
    try {
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final rq = await c.getUrl(Uri.parse(_releasesApi));
      rq.headers.set('Accept', 'application/vnd.github+json');
      rq.headers.set('User-Agent', 'delivery-dz');
      final rs = await rq.close().timeout(const Duration(seconds: 12));
      if (rs.statusCode != 200) {
        c.close();
        return;
      }
      final j = jsonDecode(await rs.transform(utf8.decoder).join()) as Map;
      final n = int.tryParse('${j['tag_name']}'.replaceFirst('build-', '')) ?? 0;
      final apk = (j['assets'] as List? ?? const []).cast<Map>().where((a) => '${a['name']}'.endsWith('.apk'));
      if (n > appBuild && apk.isNotEmpty) {
        newBuild = n;
        newUrl = '${apk.first['browser_download_url']}';
        notifyListeners();
      }
      c.close();
    } catch (_) {}
  }
}

/// يوضع في MaterialApp.builder فوق الصفحة الحالية
class StatusBars extends StatelessWidget {
  final Widget child;
  const StatusBars({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([status, if (status.watch != null) status.watch!]),
      builder: (context, _) {
        final showUpdate = status.newBuild != null && !status.updateDismissed;
        final showBattery = status.showBattery;
        final any = status.offline || showUpdate || showBattery;
        // الأشرطة تدفع الصفحة إلى الأسفل بدل أن تغطّي رأسها (وفيه مفاتيح مهمة).
        // البنية نفسها دائماً (مع أشرطة أو بدونها) حتى لا يُعاد بناء التطبيق كله عند ظهور شريط.
        final mq = MediaQuery.of(context);
        return ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Column(children: [
            if (any)
              Padding(
                padding: EdgeInsets.fromLTRB(12, mq.padding.top + 6, 12, 6),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (status.offline)
                    const _Bar(
                      color: Color(0xFF9A1C1C),
                      icon: Icons.wifi_off_rounded,
                      text: 'لا يوجد اتصال بالإنترنت · لن تصل الطلبات والتحديثات حتى يعود',
                    ),
                  if (showBattery) ...[
                    if (status.offline) const SizedBox(height: 6),
                    _Bar(
                      color: const Color(0xFF8A4B00),
                      icon: Icons.battery_alert_rounded,
                      text: 'اسمح للتطبيق بالعمل في الخلفية لتصلك التنبيهات والشاشة مطفأة',
                      action: 'سماح',
                      onAction: status.fixBattery,
                      onClose: status.dismissBattery,
                    ),
                  ],
                  if ((status.offline || showBattery) && showUpdate) const SizedBox(height: 6),
                  if (showUpdate)
                    _Bar(
                      color: const Color(0xFF1D4E89),
                      icon: Icons.system_update_rounded,
                      text: 'نسخة جديدة (${status.newBuild}) متاحة',
                      action: 'تنزيل',
                      onAction: () => launchUrl(Uri.parse(status.newUrl!), mode: LaunchMode.externalApplication),
                      onClose: status.dismissUpdate,
                    ),
                ]),
              ),
            Expanded(child: MediaQuery.removePadding(context: context, removeTop: any, child: child)),
          ]),
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction, onClose;
  const _Bar({required this.color, required this.icon, required this.text, this.action, this.onAction, this.onClose});

  @override
  Widget build(BuildContext context) => Material(
        color: color,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(12, action == null ? 10 : 4, 4, action == null ? 10 : 4),
          child: Row(children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            if (action != null)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: onAction,
                child: Text(action!, style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            if (onClose != null)
              // بدون tooltip: الشريط فوق الـ Navigator فلا يوجد Overlay للتلميح
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20, semanticLabel: 'لاحقاً'),
              ),
          ]),
        ),
      );
}
