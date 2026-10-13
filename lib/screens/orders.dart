import 'dart:async';

import 'package:flutter/material.dart';

import '../store.dart';
import '../ui.dart';
import 'shell.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  String tab = 'new';
  Timer? _clock; // يحدّث العدّ التنازلي للتحضير

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  static const tabs = [('new', 'جديدة'), ('prep', 'تحضير'), ('ready', 'جاهزة'), ('hist', 'السجل')];
  static const empty = {
    'new': 'لا توجد طلبات جديدة. عندما يطلب زبون من محلك يظهر طلبه هنا مع تنبيه صوتي.',
    'prep': 'لا توجد طلبات قيد التحضير.',
    'ready': 'لا توجد طلبات تنتظر الموصّل.',
    'hist': 'لم يكتمل أي طلب بعد.',
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final all = app.orders;
        final list = tab == 'hist' ? app.history : app.byStatus(tab);
        final t0 = startOfToday();
        final today = all.where((o) => o['createdAtMs'] >= t0 && ['done', 'road'].contains(o['status'])).toList();
        final pending = all.where((o) => o['status'] == 'done' && o['settled'] == false).toList();
        final s = app.shop ?? {};
        final rc = asInt(s['ratingCount']);
        final hint = Theme.of(context).hintColor;
        return ListView(padding: EdgeInsets.zero, children: [
          const ShopHeader(title: 'لوحة المحل'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Box(
                color: brand.withValues(alpha: 0.10),
                child: Row(children: [
                  Expanded(child: Text('مستحقاتك اليوم (${today.length} طلبات)', style: const TextStyle(fontWeight: FontWeight.w600))),
                  Text(money(today.fold<int>(0, (a, o) => a + app.shopDue(o))),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                ]),
              ),
              if (pending.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                  child: Text('عند الموصّلين ولم يُسلَّم لك بعد: ${money(pending.fold<int>(0, (a, o) => a + app.shopDue(o)))}',
                      style: TextStyle(color: hint, fontSize: 13)),
                ),
              if (rc > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                  child: Row(children: [
                    Text('تقييم محلك: ', style: TextStyle(color: hint, fontSize: 13)),
                    const Icon(Icons.star_rounded, color: star, size: 17),
                    Text((asInt(s['ratingSum']) / rc).toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(' ($rc)', style: TextStyle(color: hint, fontSize: 13)),
                  ]),
                ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  for (final t in tabs)
                    ButtonSegment(
                      value: t.$1,
                      label: Text(t.$1 == 'hist' ? t.$2 : '${t.$2} (${app.byStatus(t.$1).length})',
                          style: const TextStyle(fontSize: 13)),
                    ),
                ],
                selected: {tab},
                onSelectionChanged: (v) => setState(() => tab = v.first),
              ),
              const SizedBox(height: 10),
              if (!app.loadedOrders)
                const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
              else if (list.isEmpty)
                EmptyState(icon: Icons.receipt_long_rounded, title: 'لا شيء هنا', text: empty[tab]!)
              else
                for (final o in list) _OrderCard(o: o, showStatus: tab == 'hist'),
              const SizedBox(height: 20),
            ]),
          ),
        ]);
      },
    );
  }
}

class _OrderCard extends StatefulWidget {
  final Doc o;
  final bool showStatus;
  const _OrderCard({required this.o, required this.showStatus});
  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool busy = false;

  Future<void> _run(Future<bool> Function() f) async {
    setState(() => busy = true);
    await f();
    if (mounted) setState(() => busy = false);
  }

  Widget _dispatch(Doc o) {
    if (o['courierUid'] != null) {
      final ph = '${o['courierPhone'] ?? ''}';
      final near = ['prep', 'ready'].contains(o['status']) ? app.courierNear(o) : null;
      return InkWell(
        onTap: ph.isEmpty ? null : () => callPhone(ph),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.delivery_dining_rounded, color: info, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text('الموصّل: ${o['courierName'] ?? ''}${ph.isEmpty ? '' : ' · $ph'}',
                  style: const TextStyle(color: info, fontWeight: FontWeight.w600)),
            ),
            if (ph.isNotEmpty) const Icon(Icons.call_rounded, color: info, size: 18),
          ]),
          if (near != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: near.km <= arriveKm
                  ? const Pill('وصل إلى المحل', bg: Color(0xFFE2F1EA), fg: Color(0xFF0A5A41), icon: Icons.storefront_rounded)
                  : Pill('على بعد ${kmText(near.km)} · يصل خلال ~${near.min} د',
                      bg: const Color(0xFFE3ECF7), fg: info, icon: Icons.near_me_rounded),
            ),
        ]),
      );
    }
    if (!['prep', 'ready'].contains(o['status'])) return const SizedBox.shrink();
    if (o['dispatch'] == 'none') {
      return const Text('لا يوجد موصّل متاح الآن · يُعرض تلقائياً على أول موصّل يتصل',
          style: TextStyle(color: warn, fontWeight: FontWeight.w600, fontSize: 13));
    }
    return Row(children: [
      const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
      const SizedBox(width: 8),
      Text('يُعرض على أقرب موصّل…', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.o;
    final st = '${o['status']}';
    final hint = Theme.of(context).hintColor;
    final id = '${o['id']}';

    Widget? action;
    if (st == 'new') {
      action = Row(children: [
        Expanded(
          flex: 2,
          child: FilledButton(onPressed: busy ? null : () => _run(() => app.accept(id)), child: const Text('قبول الطلب')),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700, minimumSize: const Size(0, 54)),
            onPressed: busy
                ? null
                : () async {
                    if (await confirm(context, 'رفض الطلب ${o['no'] ?? ''}؟', 'سيُبلَّغ الزبون أن محلك رفض طلبه.', 'نعم، ارفض')) {
                      _run(() => app.reject(id));
                    }
                  },
            child: const Text('رفض'),
          ),
        ),
      ]);
    } else if (st == 'prep') {
      action = Row(children: [
        Expanded(
          flex: 3,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: orange),
            onPressed: busy ? null : () => _run(() => app.markReady(id)),
            child: const Text('الطلب جاهز للموصّل'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Tooltip(
            message: 'أحتاج 10 دقائق إضافية',
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 54), padding: EdgeInsets.zero),
              onPressed: busy ? null : () => _run(() => app.delay(o)),
              child: const Text('+10 د', textDirection: TextDirection.rtl),
            ),
          ),
        ),
      ]);
    } else if (st == 'ready') {
      action = FilledButton(
        style: FilledButton.styleFrom(backgroundColor: info),
        onPressed: busy ? null : () => _run(() => app.handed(id)),
        child: const Text('سلّمته للموصّل'),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Box(
        border: st == 'new' ? Border.all(color: orange, width: 2) : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(
                'طلب ${o['no'] ?? ''}${'${o['customerName'] ?? ''}'.isNotEmpty ? ' · ${o['customerName']}' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
            if (widget.showStatus) ...[statusPill(o), const SizedBox(width: 8)],
            Text(ago(asInt(o['createdAtMs'])), style: TextStyle(color: hint, fontSize: 12)),
          ]),
          if (app.prepLeft(o) != null) ...[
            const SizedBox(height: 6),
            Align(alignment: AlignmentDirectional.centerStart, child: _prepPill(app.prepLeft(o)!)),
          ],
          if (o['scheduledFor'] != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Pill('مجدول: يصل للزبون ${schedText(asInt(o['scheduledFor']))}',
                  bg: const Color(0xFFEDE7F6), fg: const Color(0xFF4A2B8A), icon: Icons.schedule_rounded),
            ),
          ],
          const SizedBox(height: 8),
          for (final i in itemsOf(o))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text.rich(TextSpan(style: const TextStyle(fontSize: 15), children: [
                TextSpan(text: '${asInt(i['qty'])}× ', style: const TextStyle(fontWeight: FontWeight.w800)),
                TextSpan(text: '${i['name'] ?? ''}'),
                if (optsText(i).isNotEmpty)
                  TextSpan(text: '  (${optsText(i)})', style: const TextStyle(color: Color(0xFFB45F06), fontSize: 13)),
              ])),
            ),
          if ('${o['note'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 6),
            Note('ملاحظة الزبون: ${o['note']}', color: orange, icon: Icons.sticky_note_2_rounded),
          ],
          if (asInt(o['discount']) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('كوبون ${o['coupon'] ?? ''}: خصم ${money(asInt(o['discount']))} على حسابك',
                  style: const TextStyle(color: brand, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          const SizedBox(height: 6),
          Text('${o['zoneName'] ?? ''} · ${o['address'] ?? ''}', style: TextStyle(color: hint, fontSize: 13)),
          const SizedBox(height: 6),
          _dispatch(o),
          const SizedBox(height: 4),
          Line('مستحقك من هذا الطلب', money(app.shopDue(o)), bold: true),
          if (action != null) ...[const SizedBox(height: 8), action],
        ]),
      ),
    );
  }
}

/// العدّ التنازلي لتحضير الطلب، بأيقونة ونص حتى لا يعتمد على اللون وحده
Widget _prepPill(int left) {
  if (left > 0) {
    return Pill('يجهز خلال $left د', bg: const Color(0xFFE3ECF7), fg: info, icon: Icons.timer_outlined);
  }
  if (left == 0) return const Pill('حان وقت جاهزيته', bg: Color(0xFFFFF1DC), fg: Color(0xFF8A4B00), icon: Icons.timer_rounded);
  return Pill('متأخر ${-left} د · الزبون ينتظر', bg: const Color(0xFFFCE4E4), fg: const Color(0xFF9A1C1C), icon: Icons.warning_amber_rounded);
}
