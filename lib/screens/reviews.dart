import 'package:flutter/material.dart';

import '../store.dart';
import '../ui.dart';

/// آراء الزبائن: المتوسط وتوزيع النجوم ثم التعليقات، الأحدث أولاً
class ReviewsScreen extends StatefulWidget {
  final String title;

  /// يحمّل الآراء (كل رأي فيه starKey = عدد النجوم من 1 إلى 5)
  final Future<List<Doc>> Function() load;
  final String starKey;

  /// لون الأعمدة في الوضع الفاتح والداكن (مُتحقَّق من وضوحه على الخلفية)
  final Color barLight, barDark;
  const ReviewsScreen({
    super.key,
    required this.title,
    required this.load,
    required this.starKey,
    required this.barLight,
    required this.barDark,
  });
  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  List<Doc>? list;
  String err = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => err = '');
    try {
      final l = await widget.load();
      if (mounted) setState(() => list = l);
    } catch (e) {
      if (mounted) setState(() => err = errText(e));
    }
  }

  static String _date(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    // أيام تقويمية، لا كتل 24 ساعة
    final days = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
    if (days <= 0) return 'اليوم';
    if (days == 1) return 'أمس';
    if (days == 2) return 'منذ يومين';
    if (days <= 10) return 'منذ $days أيام';
    return '${d.day}/${d.month}/${d.year}';
  }

  static String _reviewsText(int n) {
    if (n == 1) return 'رأي واحد';
    if (n == 2) return 'رأيين';
    if (n <= 10) return '$n آراء';
    return '$n رأياً';
  }

  Widget _stars(int n, {double size = 16}) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (int i = 1; i <= 5; i++)
          Icon(i <= n ? Icons.star_rounded : Icons.star_border_rounded, size: size, color: star),
      ]);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = theme.hintColor;
    final l = list;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 30), children: [
          if (err.isNotEmpty)
            Note(err, color: Colors.red.shade700, icon: Icons.error_outline_rounded)
          else if (l == null)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else if (l.isEmpty)
            const EmptyState(icon: Icons.reviews_outlined, title: 'لا توجد آراء بعد', text: 'يقيّمك الزبائن بعد استلام طلباتهم.')
          else ...[
            _summary(context, l),
            const SizedBox(height: 18),
            Text(l.length > 60 ? 'آخر 60 رأياً' : 'آخر الآراء', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final r in l.take(60))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Box(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      _stars(asInt(r[widget.starKey])),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('${r['name'] ?? ''}'.isEmpty ? 'زبون' : '${r['name']}',
                            style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                      ),
                      Text(_date(asInt(r['createdAtMs'])), style: TextStyle(color: hint, fontSize: 12)),
                    ]),
                    if ('${r['comment'] ?? ''}'.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('${r['comment']}', style: const TextStyle(height: 1.45)),
                    ],
                  ]),
                ),
              ),
          ],
        ]),
      ),
    );
  }

  Widget _summary(BuildContext context, List<Doc> l) {
    final theme = Theme.of(context);
    final hint = theme.hintColor;
    final bar = theme.brightness == Brightness.dark ? widget.barDark : widget.barLight;
    final counts = List.filled(6, 0);
    for (final r in l) {
      final n = asInt(r[widget.starKey]).clamp(1, 5);
      counts[n]++;
    }
    final avg = l.fold<int>(0, (s, r) => s + asInt(r[widget.starKey]).clamp(1, 5)) / l.length;
    final top = counts.reduce((a, b) => a > b ? a : b);
    return Box(
      child: Row(children: [
        Column(children: [
          Text(avg.toStringAsFixed(1), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
          _stars(avg.round(), size: 14),
          const SizedBox(height: 2),
          Text('من ${_reviewsText(l.length)}', style: TextStyle(color: hint, fontSize: 12)),
        ]),
        const SizedBox(width: 18),
        Expanded(
          child: Column(children: [
            for (int n = 5; n >= 1; n--)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Semantics(
                  label: '$n نجوم: ${counts[n]}',
                  child: Row(children: [
                    SizedBox(width: 14, child: Text('$n', style: TextStyle(color: hint, fontSize: 12))),
                    const Icon(Icons.star_rounded, size: 12, color: star),
                    const SizedBox(width: 6),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (_, c) => Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Container(
                            height: 8,
                            width: top == 0 ? 0 : c.maxWidth * counts[n] / top,
                            decoration: BoxDecoration(color: bar, borderRadius: BorderRadius.circular(4)),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 26,
                      child: Text('${counts[n]}', textAlign: TextAlign.end, style: TextStyle(color: hint, fontSize: 12)),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}
