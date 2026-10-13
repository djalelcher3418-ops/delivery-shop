// إشعارات الهاتف: تظهر فقط والتطبيق في الخلفية أو الشاشة مطفأة.
// والتطبيق مفتوح تكفي نافذة العرض والرسائل القصيرة داخل التطبيق.
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final Notifier notify = Notifier();

class Notifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _foreground = true;
  AppLifecycleListener? _life;

  /// يُستدعى عند الضغط على إشعار، مع الحمولة (مثل chat:ORDER_ID)
  void Function(String payload)? onOpen;

  bool get inBackground => !_foreground;

  static const _updates = AndroidNotificationDetails(
    'updates',
    'تحديثات الطلبات',
    channelDescription: 'تحديثات طلبات المحل',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.message,
    visibility: NotificationVisibility.public,
  );

  Future<void> init() async {
    _life ??= AppLifecycleListener(onStateChange: (s) => _foreground = s == AppLifecycleState.resumed);
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
        onDidReceiveNotificationResponse: (r) {
          final p = r.payload;
          if (p != null && p.isNotEmpty) onOpen?.call(p);
        },
      );
      _ready = true;
    } catch (_) {}
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// يطلب إذن الإشعارات (أندرويد 13 فما فوق). يرجع true إذا كانت مسموحة.
  Future<bool> requestPermission() async {
    try {
      return await _android?.requestNotificationsPermission() ?? true;
    } catch (_) {
      return false;
    }
  }

  Future<bool?> enabled() async {
    try {
      return await _android?.areNotificationsEnabled();
    } catch (_) {
      return null;
    }
  }

  int _id(String key) => key.hashCode & 0x7fffffff;

  Future<void> _show(String key, String title, String body, AndroidNotificationDetails d, String payload) async {
    if (!_ready || _foreground) return;
    try {
      await _plugin.show(
        id: _id(key),
        title: title,
        body: body,
        notificationDetails: NotificationDetails(android: d),
        payload: payload,
      );
    } catch (_) {}
  }

  /// طلب جديد ينتظر القبول: يضيء الشاشة ويظهر فوق القفل مثل المكالمة
  Future<void> newOrder(String orderId, String title, String body) => _show(
        'order:$orderId',
        title,
        body,
        const AndroidNotificationDetails(
          'new_orders',
          'الطلبات الجديدة',
          channelDescription: 'طلب جديد وصل إلى محلك وينتظر القبول',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          visibility: NotificationVisibility.public,
        ),
        'order:$orderId',
      );

  Future<void> cancelOrder(String orderId) async {
    try {
      await _plugin.cancel(id: _id('order:$orderId'));
    } catch (_) {}
  }

  Future<void> update(String key, String title, String body, String payload) =>
      _show(key, title, body, _updates, payload);
}
