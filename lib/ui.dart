import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'store.dart';

// ألوان التصميم الجديد: أخضر نعناعي + أبيض + أسود
const brand = Color(0xFF4E9F82);
const brandDark = Color(0xFF2E7A5F);
const mint = Color(0xFFDCEFE7);
const mintSoft = Color(0xFFEEF7F3);
const ink = Color(0xFF161817);
const orange = Color(0xFFE8890C);
const star = Color(0xFFF2A516);
const info = Color(0xFF1D4E89);
const warn = Color(0xFFB45309);

const shopGradient = LinearGradient(
  begin: Alignment.topRight,
  end: Alignment.bottomLeft,
  colors: [Color(0xFF66B496), Color(0xFF4E9F82), Color(0xFF3A8A6D)],
);

List<BoxShadow> softShadow(BuildContext context) => Theme.of(context).brightness == Brightness.dark
    ? const []
    : [BoxShadow(color: const Color(0xFF1E4D3C).withValues(alpha: 0.08), blurRadius: 22, offset: const Offset(0, 8))];

class Box extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Border? border;
  final VoidCallback? onTap;
  const Box({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.color, this.border, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: border,
        boxShadow: softShadow(context),
      ),
      child: child,
    );
    if (onTap == null) return c;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(22), onTap: onTap, child: c),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color bg, fg;
  final IconData? icon;
  const Pill(this.text, {super.key, this.bg = const Color(0xFFEAF4EF), this.fg = const Color(0xFF3F5A4F), this.icon});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: dark ? fg.withValues(alpha: 0.22) : bg, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: dark ? Colors.white70 : fg), const SizedBox(width: 4)],
        Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: dark ? Colors.white : fg)),
      ]),
    );
  }
}

Pill statusPill(Doc o) {
  switch (o['status']) {
    case 'new':
      return const Pill('جديد', bg: Color(0xFFFCE9DC), fg: Color(0xFF8A3414));
    case 'prep':
      return const Pill('قيد التحضير', bg: Color(0xFFF6EED8), fg: Color(0xFF6E500F));
    case 'ready':
      return const Pill('جاهز', bg: Color(0xFFE3ECF7), fg: info);
    case 'road':
      return const Pill('مع الموصّل', bg: Color(0xFFE3ECF7), fg: info);
    case 'done':
      return const Pill('تم التوصيل', bg: Color(0xFFE2F1EA), fg: Color(0xFF0A5A41));
    case 'rejected':
      return const Pill('مرفوض');
    default:
      return const Pill('ملغى');
  }
}

class Line extends StatelessWidget {
  final String label, value;
  final bool bold;
  final Color? color;
  const Line(this.label, this.value, {super.key, this.bold = false, this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(
            child: Text(label,
                style: TextStyle(color: bold ? null : Theme.of(context).hintColor, fontWeight: bold ? FontWeight.w700 : null)),
          ),
          Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color, fontSize: bold ? 16 : 14)),
        ]),
      );
}

class Note extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;
  const Note(this.text, {super.key, this.color = info, this.icon = Icons.info_outline_rounded});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
        ]),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, text;
  const EmptyState({super.key, required this.icon, required this.title, this.text = ''});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Icon(icon, size: 32, color: Theme.of(context).hintColor),
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16), textAlign: TextAlign.center),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(text, style: TextStyle(color: Theme.of(context).hintColor), textAlign: TextAlign.center),
          ],
        ]),
      );
}

Future<void> callPhone(String p) async {
  if (p.isEmpty) return;
  await launchUrl(Uri(scheme: 'tel', path: p));
}

Future<void> openMaps(double lat, double lng) async {
  final u = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
  await launchUrl(u, mode: LaunchMode.externalApplication);
}

Future<bool> confirm(BuildContext context, String title, String body, String ok) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('تراجع')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r == true;
}

class BarItem {
  final IconData icon, active;
  final String label;
  final String? badge;
  const BarItem(this.icon, this.active, this.label, {this.badge});
}

/// شريط سفلي أبيض مدوّر (مثل تطبيق الزبون): الأيقونة المختارة داخل دائرة خضراء مرفوعة
class BottomBar extends StatelessWidget {
  final int index;
  final List<BarItem> items;
  final ValueChanged<int> onTap;
  const BottomBar({super.key, required this.index, required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hint = Theme.of(context).hintColor;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: dark ? const [] : [BoxShadow(color: const Color(0xFF1E4D3C).withValues(alpha: 0.10), blurRadius: 24, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(children: [
            for (int k = 0; k < items.length; k++)
              Expanded(
                child: Semantics(
                  selected: k == index,
                  button: true,
                  label: items[k].label,
                  child: InkResponse(
                    onTap: () => onTap(k),
                    radius: 36,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        width: k == index ? 46 : 40,
                        height: k == index ? 46 : 40,
                        transform: Matrix4.translationValues(0, k == index ? -6 : 0, 0),
                        decoration: BoxDecoration(
                          color: k == index ? brand : Colors.transparent,
                          shape: BoxShape.circle,
                          boxShadow: k == index ? [BoxShadow(color: brand.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 5))] : null,
                        ),
                        child: Badge(
                          isLabelVisible: items[k].badge != null,
                          label: Text(items[k].badge ?? ''),
                          child: Icon(k == index ? items[k].active : items[k].icon, color: k == index ? Colors.white : hint, size: 24),
                        ),
                      ),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 220),
                        style: TextStyle(
                          fontFamily: Theme.of(context).textTheme.bodySmall?.fontFamily,
                          fontSize: 11.5,
                          fontWeight: k == index ? FontWeight.w700 : FontWeight.w500,
                          color: k == index ? brand : hint,
                        ),
                        child: Text(items[k].label, maxLines: 1),
                      ),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
