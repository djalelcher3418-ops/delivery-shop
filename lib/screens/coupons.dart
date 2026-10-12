import 'package:flutter/material.dart';

import '../store.dart';
import '../ui.dart';
import 'shell.dart';

class CouponsScreen extends StatefulWidget {
  const CouponsScreen({super.key});
  @override
  State<CouponsScreen> createState() => _CouponsScreenState();
}

class _CouponsScreenState extends State<CouponsScreen> {
  final code = TextEditingController(), val = TextEditingController(), min = TextEditingController();
  String type = 'pct';
  DateTime? until;
  bool once = false, busy = false;
  String err = '';

  @override
  void dispose() {
    code.dispose();
    val.dispose();
    min.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    setState(() {
      busy = true;
      err = '';
    });
    final e = await app.addCoupon(
      code: code.text.trim().toUpperCase(),
      type: type,
      value: parseInt(val.text) ?? 0,
      minOrder: parseInt(min.text) ?? 0,
      until: until == null ? null : DateTime(until!.year, until!.month, until!.day, 23, 59, 59).millisecondsSinceEpoch,
      once: once,
    );
    if (!mounted) return;
    setState(() {
      busy = false;
      err = e;
      if (e.isEmpty) {
        code.clear();
        val.clear();
        min.clear();
        until = null;
        once = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final hint = Theme.of(context).hintColor;
        final used = <String, ({int n, int v})>{};
        for (final o in app.orders) {
          final cid = o['couponId'];
          if (cid != null && o['status'] != 'cancelled' && o['status'] != 'rejected') {
            final u = used['$cid'] ?? (n: 0, v: 0);
            used['$cid'] = (n: u.n + 1, v: u.v + asInt(o['discount']));
          }
        }
        return ListView(padding: EdgeInsets.zero, children: [
          const ShopHeader(title: 'العروض والكوبونات'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('أنشئ رمز خصم لزبائنك. يظهر عرضك في الصفحة الرئيسية وعلى بطاقة محلك، وقيمة الخصم تُخصم من مستحقك.',
                  style: TextStyle(color: hint, fontSize: 13)),
              const SizedBox(height: 12),
              if (!app.loadedCoupons)
                const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
              else if (app.coupons.isEmpty)
                const EmptyState(icon: Icons.local_offer_rounded, title: 'لا توجد عروض بعد', text: 'جرّب «خصم 10%» للطلبات من 1500 دج.')
              else
                for (final c in app.coupons)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Box(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              border: Border.all(color: brand, width: 1.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('${c['code']}',
                                textDirection: TextDirection.ltr,
                                style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1, color: brand)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(couponLabel(c), style: const TextStyle(fontWeight: FontWeight.w700))),
                          Switch(value: c['active'] != false, onChanged: (_) => app.toggleCoupon(c)),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (asInt(c['minOrder']) > 0) 'للطلبات من ${fmt(asInt(c['minOrder']))} دج',
                            if (c['once'] == true) 'مرة واحدة لكل زبون',
                            if (c['until'] != null)
                              (nowMs() > asInt(c['until'])
                                  ? 'انتهى'
                                  : 'حتى ${DateTime.fromMillisecondsSinceEpoch(asInt(c['until'])).day}/${DateTime.fromMillisecondsSinceEpoch(asInt(c['until'])).month}')
                            else
                              'بدون تاريخ انتهاء',
                          ].join(' · '),
                          style: TextStyle(color: hint, fontSize: 13),
                        ),
                        Row(children: [
                          Expanded(
                            child: Text(
                                'استُعمل ${used['${c['id']}']?.n ?? 0} مرة · خصم إجمالي ${money(used['${c['id']}']?.v ?? 0)}',
                                style: const TextStyle(fontSize: 13)),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                            onPressed: () async {
                              if (await confirm(context, 'حذف العرض ${c['code']}؟', 'لن يستطيع الزبائن استعماله بعد الآن.', 'احذف')) {
                                app.deleteCoupon(c);
                              }
                            },
                            child: const Text('حذف'),
                          ),
                        ]),
                      ]),
                    ),
                  ),
              const SizedBox(height: 14),
              Box(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('عرض جديد', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(
                    controller: code,
                    textDirection: TextDirection.ltr,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 15,
                    decoration: const InputDecoration(labelText: 'الرمز (حروف لاتينية وأرقام)', hintText: 'PIZZA10'),
                  ),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'pct', label: Text('نسبة %')),
                      ButtonSegment(value: 'fix', label: Text('مبلغ ثابت دج')),
                    ],
                    selected: {type},
                    onSelectionChanged: (v) => setState(() => type = v.first),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: val,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: 'القيمة', suffixText: type == 'pct' ? '%' : 'دج'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: min,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'أقل مبلغ للطلب', suffixText: 'دج'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final now = DateTime.now();
                      final d = await showDatePicker(
                          context: context, firstDate: now, lastDate: now.add(const Duration(days: 365)), initialDate: until ?? now);
                      setState(() => until = d);
                    },
                    icon: const Icon(Icons.event_rounded),
                    label: Text(until == null ? 'تاريخ الانتهاء (اختياري)' : 'ينتهي في ${until!.day}/${until!.month}/${until!.year}'),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: once,
                    onChanged: (v) => setState(() => once = v == true),
                    title: const Text('مرة واحدة لكل زبون'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  if (err.isNotEmpty) ...[Note(err, color: warn, icon: Icons.error_outline_rounded), const SizedBox(height: 10)],
                  FilledButton.icon(
                    onPressed: busy ? null : _add,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('أنشئ العرض'),
                  ),
                ]),
              ),
            ]),
          ),
        ]);
      },
    );
  }
}
