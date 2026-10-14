import 'package:flutter/material.dart';

import '../store.dart';
import '../ui.dart';
import 'reviews.dart';
import 'shell.dart';

const _weekdayShort = ['إثن', 'ثلا', 'أرب', 'خمي', 'جمع', 'سبت', 'أحد'];
const _weekday = ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];

/// عدد الطلبات بصيغة عربية سليمة
String ordersText(int n) {
  if (n == 0) return 'لا طلبات';
  if (n == 1) return 'طلب واحد';
  if (n == 2) return 'طلبان';
  if (n <= 10) return '$n طلبات';
  return '$n طلباً';
}

String _dayTitle(DateTime d) {
  final now = DateTime.now();
  final diff = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
  if (diff == 0) return 'اليوم';
  if (diff == 1) return 'أمس';
  return '${_weekday[d.weekday - 1]} ${d.day}/${d.month}';
}

/// الطلبات التي سلّمها المحل للموصّل (في الطريق أو مكتملة)
bool _sold(Doc o) => o['status'] == 'road' || o['status'] == 'done';

class SalesScreen extends StatelessWidget {
  const SalesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final theme = Theme.of(context);
        final hint = theme.hintColor;
        final now = DateTime.now();
        final days = [for (int i = 6; i >= 0; i--) DateTime(now.year, now.month, now.day - i)];
        final dues = List.filled(7, 0), counts = List.filled(7, 0);
        final t30 = startOfToday() - 29 * 86400000;
        final top = <String, ({int qty, int sum})>{};
        int rejected = 0, cancelled = 0;

        for (final o in app.orders) {
          final at = asInt(o['createdAtMs']);
          if (at >= t30) {
            if (o['status'] == 'rejected') rejected++;
            if (o['status'] == 'cancelled') cancelled++;
          }
          if (!_sold(o)) continue;
          final d = DateTime.fromMillisecondsSinceEpoch(at);
          final i = days.indexWhere((x) => x.year == d.year && x.month == d.month && x.day == d.day);
          if (i >= 0) {
            dues[i] += app.shopDue(o);
            counts[i]++;
          }
          if (at >= t30) {
            for (final it in itemsOf(o)) {
              final name = '${it['name'] ?? ''}';
              if (name.isEmpty) continue;
              final q = asInt(it['qty']);
              final prev = top[name] ?? (qty: 0, sum: 0);
              top[name] = (qty: prev.qty + q, sum: prev.sum + q * asInt(it['price']));
            }
          }
        }
        final weekDue = dues.fold<int>(0, (a, b) => a + b);
        final weekN = counts.fold<int>(0, (a, b) => a + b);
        final best = top.entries.toList()..sort((a, b) => b.value.qty.compareTo(a.value.qty));
        final pending = app.orders.where((o) => o['status'] == 'done' && o['settled'] == false).toList();

        // الزبائن: من طلب في آخر 30 يوماً، وهل كانت تلك أول مرة يطلب فيها من المحل
        final firstAt = <String, int>{};
        final active = <String>{};
        for (final o in app.orders) {
          final uid = '${o['customerUid'] ?? ''}';
          if (uid.isEmpty || !_sold(o)) continue;
          final at = asInt(o['createdAtMs']);
          firstAt[uid] = firstAt.containsKey(uid) ? (at < firstAt[uid]! ? at : firstAt[uid]!) : at;
          if (at >= t30) active.add(uid);
        }
        final newCust = active.where((u) => firstAt[u]! >= t30).length;
        final returning = active.length - newCust;

        return ListView(padding: EdgeInsets.zero, children: [
          const ShopHeader(title: 'المبيعات'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (!app.loadedOrders)
                const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
              else ...[
                Row(children: [
                  _Tile('اليوم', money(dues[6]), ordersText(counts[6])),
                  const SizedBox(width: 10),
                  _Tile('آخر 7 أيام', money(weekDue), weekN > 0 ? 'متوسط الطلب ${money(weekDue / weekN)}' : ordersText(0)),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  _Tile('زبائن آخر 30 يوماً', '${active.length}',
                      active.isEmpty ? 'لا زبائن بعد' : '$newCust جدد · $returning عادوا للطلب'),
                ]),
                const SizedBox(height: 12),
                Box(child: _WeekChart(days: days, values: dues, counts: counts)),
                if (pending.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Note(
                    'عند الموصّلين ولم يُسلَّم لك بعد: ${money(pending.fold<int>(0, (a, o) => a + app.shopDue(o)))} '
                    '(${ordersText(pending.length)}). يصلك مع تسوية الإدارة.',
                    color: warn,
                    icon: Icons.account_balance_wallet_rounded,
                  ),
                ],
                const SizedBox(height: 12),
                Box(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ReviewsScreen(
                      title: 'آراء زبائن محلك',
                      load: app.loadReviews,
                      starKey: 'shop',
                      barLight: const Color(0xFF1E8A66),
                      barDark: const Color(0xFF2FA67A),
                    ),
                  )),
                  child: Row(children: [
                    const Icon(Icons.reviews_rounded, color: star, size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('آراء الزبائن', style: TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                          asInt(app.shop?['ratingCount']) > 0
                              ? 'تقييمك ${(asInt(app.shop?['ratingSum']) / asInt(app.shop?['ratingCount'])).toStringAsFixed(1)} من ${asInt(app.shop?['ratingCount'])} تقييماً · اقرأ تعليقاتهم'
                              : 'لا تقييمات بعد',
                          style: TextStyle(color: hint, fontSize: 13),
                        ),
                      ]),
                    ),
                    const Icon(Icons.chevron_left_rounded),
                  ]),
                ),
                const SizedBox(height: 18),
                Text('الأكثر طلباً في آخر 30 يوماً', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                if (best.isEmpty)
                  const EmptyState(
                    icon: Icons.inventory_2_rounded,
                    title: 'لا مبيعات بعد',
                    text: 'عندما تسلّم طلبات للموصّلين تظهر هنا منتجاتك الأكثر طلباً.',
                  )
                else
                  Box(
                    child: Column(children: [
                      for (int i = 0; i < best.length && i < 5; i++) ...[
                        if (i > 0) const Divider(height: 16),
                        Row(children: [
                          CircleAvatar(
                            radius: 13,
                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                            child: Text('${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(best[i].key, style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text('بيعت ${best[i].value.qty} مرة', style: TextStyle(color: hint, fontSize: 12)),
                            ]),
                          ),
                          Text(money(best[i].value.sum), style: const TextStyle(fontWeight: FontWeight.w700)),
                        ]),
                      ],
                    ]),
                  ),
                if (rejected > 0 || cancelled > 0) ...[
                  const SizedBox(height: 12),
                  Text(
                    [
                      if (rejected > 0) 'رفضتَ ${ordersText(rejected)}',
                      if (cancelled > 0) 'ألغى الزبائن ${ordersText(cancelled)}',
                    ].join(' · ') +
                        ' في آخر 30 يوماً. الرفض الكثير يقلل ثقة الزبائن بمحلك.',
                    style: TextStyle(color: hint, fontSize: 13),
                  ),
                ],
              ],
            ]),
          ),
        ]);
      },
    );
  }
}

class _Tile extends StatelessWidget {
  final String label, value, sub;
  const _Tile(this.label, this.value, this.sub);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Box(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            Text(sub, style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
          ]),
        ),
      );
}

/// أعمدة مستحقات آخر 7 أيام. اضغط على عمود لترى مبلغه.
class _WeekChart extends StatefulWidget {
  final List<DateTime> days;
  final List<int> values, counts;
  const _WeekChart({required this.days, required this.values, required this.counts});
  @override
  State<_WeekChart> createState() => _WeekChartState();
}

class _WeekChartState extends State<_WeekChart> {
  int? picked; // null = اليوم

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final bar = dark ? const Color(0xFF2FA67A) : const Color(0xFF1E8A66);
    final hint = theme.hintColor;
    final n = widget.days.length;
    final sel = (picked ?? n - 1).clamp(0, n - 1);
    final top = widget.values.fold<int>(0, (m, v) => v > m ? v : m);
    const plotH = 110.0;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('مستحقاتك في آخر 7 أيام', style: theme.textTheme.titleMedium),
      const SizedBox(height: 2),
      Text('${_dayTitle(widget.days[sel])}: ${money(widget.values[sel])} · ${ordersText(widget.counts[sel])}',
          style: TextStyle(color: hint, fontSize: 13)),
      const SizedBox(height: 14),
      SizedBox(
        height: plotH + 30,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (int i = 0; i < n; i++)
            Expanded(
              child: Semantics(
                button: true,
                label: '${_dayTitle(widget.days[i])}: ${money(widget.values[i])}',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => picked = i),
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Container(
                        height: top == 0
                            ? 0
                            : (plotH * widget.values[i] / top).clamp(widget.values[i] > 0 ? 4.0 : 0.0, plotH),
                        decoration: BoxDecoration(
                          color: bar.withValues(alpha: i == sel ? 1 : 0.55),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ),
                    ),
                    Container(height: 1, color: theme.dividerColor),
                    const SizedBox(height: 4),
                    Text(
                      i == n - 1 ? 'اليوم' : _weekdayShort[widget.days[i].weekday - 1],
                      style: TextStyle(
                        fontSize: 11,
                        color: i == sel ? theme.colorScheme.onSurface : hint,
                        fontWeight: i == sel ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ]),
                ),
              ),
            ),
        ]),
      ),
      if (top == 0)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('لا مبيعات مسجّلة في هذه الأيام.', style: TextStyle(color: hint, fontSize: 12)),
        ),
    ]);
  }
}
