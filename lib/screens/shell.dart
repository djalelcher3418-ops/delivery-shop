import 'package:flutter/material.dart';

import '../store.dart';
import '../ui.dart';
import 'coupons.dart';
import 'orders.dart';
import 'products.dart';
import 'sales.dart';
import 'settings.dart';

/// التبويب الحالي (يغيّره الضغط على إشعار طلب جديد)
final ValueNotifier<int> shopTab = ValueNotifier<int>(0);

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int get tab => shopTab.value;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([app, shopTab]),
      builder: (context, _) {
        final n = app.newCount;
        if (app.shop == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        return Scaffold(
          body: IndexedStack(index: tab, children: [
            const OrdersScreen(),
            const SalesScreen(),
            const ProductsScreen(),
            const CouponsScreen(),
            SettingsScreen(key: ValueKey(app.shopId)),
          ]),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (i) => shopTab.value = i,
            destinations: [
              NavigationDestination(
                icon: Badge(isLabelVisible: n > 0, label: Text('$n'), child: const Icon(Icons.receipt_long_outlined)),
                selectedIcon: Badge(isLabelVisible: n > 0, label: Text('$n'), child: const Icon(Icons.receipt_long_rounded)),
                label: 'الطلبات',
              ),
              const NavigationDestination(
                  icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart_rounded), label: 'المبيعات'),
              const NavigationDestination(
                  icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2_rounded), label: 'منتجاتي'),
              const NavigationDestination(
                  icon: Icon(Icons.local_offer_outlined), selectedIcon: Icon(Icons.local_offer_rounded), label: 'العروض'),
              const NavigationDestination(
                  icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: 'الإعدادات'),
            ],
          ),
        );
      },
    );
  }
}

/// رأس الصفحة: اسم المحل، مفتاح الفتح/الإغلاق، الخروج، وحالة المحل
class ShopHeader extends StatelessWidget {
  final String title;
  final Widget? bottom;
  const ShopHeader({super.key, required this.title, this.bottom});

  @override
  Widget build(BuildContext context) {
    final s = app.shop ?? {};
    final open = s['open'] == true;
    final inHours = withinHours(s);
    String status = !open
        ? 'المحل مغلق · لا تصل طلبات جديدة'
        : (inHours ? 'المحل مفتوح · يستقبل الطلبات' : 'مفتوح، لكنه خارج ساعات العمل · الزبائن يرونه مغلقاً');
    Widget chip(String t, {Color? bg, Color fg = Colors.white, IconData? icon}) => Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: bg ?? Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 6)],
            Flexible(child: Text(t, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13))),
          ]),
        );
    return Container(
      decoration: const BoxDecoration(gradient: shopGradient, borderRadius: BorderRadius.vertical(bottom: Radius.circular(28))),
      padding: EdgeInsets.fromLTRB(18, MediaQuery.of(context).padding.top + 14, 18, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(color: Colors.white70, fontSize: 13)),
              Text('${s['name'] ?? ''}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            ]),
          ),
          Transform.scale(
            scale: 1.15,
            child: Switch(
              value: open,
              activeThumbColor: Colors.white,
              activeTrackColor: const Color(0xFF3DBB8C),
              onChanged: (_) => app.toggleOpen(),
            ),
          ),
          IconButton(
            tooltip: 'الخروج',
            onPressed: () async {
              if (await confirm(context, 'تسجيل الخروج', 'لن تصلك تنبيهات الطلبات على هذا الهاتف.', 'خروج')) app.logout();
            },
            icon: const Icon(Icons.logout_rounded, color: Colors.white),
          ),
        ]),
        chip(status, icon: Icons.circle),
        if (s['lat'] == null) chip('حدّد موقع المحل من الإعدادات ليصلك أقرب موصّل', icon: Icons.location_on_rounded),
        if (s['active'] == false)
          chip('أوقفت الإدارة ظهور محلك للزبائن مؤقتاً', bg: const Color(0xFFFFF1DC), fg: const Color(0xFF8A4B00)),
        if (bottom != null) bottom!,
      ]),
    );
  }
}
