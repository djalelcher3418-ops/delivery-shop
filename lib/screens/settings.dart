import 'package:flutter/material.dart';

import '../store.dart';
import '../ui.dart';
import 'products.dart';
import 'shell.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController min, prep, desc;
  String from = '', to = '';
  String? cover; // null = لا تغيير
  bool busy = false, geoBusy = false;
  String err = '', geoErr = '';

  @override
  void initState() {
    super.initState();
    final s = app.shop ?? {};
    final h = s['hours'] is Map ? s['hours'] as Map : const {};
    from = '${h['from'] ?? ''}';
    to = '${h['to'] ?? ''}';
    min = TextEditingController(text: asInt(s['minOrder']) > 0 ? '${s['minOrder']}' : '');
    prep = TextEditingController(text: asInt(s['prepMin']) > 0 ? '${s['prepMin']}' : '');
    desc = TextEditingController(text: '${s['desc'] ?? ''}');
  }

  @override
  void dispose() {
    min.dispose();
    prep.dispose();
    desc.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool isFrom) async {
    final cur = hm(isFrom ? from : to);
    final t = await showTimePicker(
      context: context,
      initialTime: cur == null ? TimeOfDay(hour: isFrom ? 8 : 22, minute: 0) : TimeOfDay(hour: cur ~/ 60, minute: cur % 60),
      builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t == null) return;
    setState(() {
      final v = '${two(t.hour)}:${two(t.minute)}';
      if (isFrom) {
        from = v;
      } else {
        to = v;
      }
    });
  }

  Future<void> _save() async {
    setState(() {
      busy = true;
      err = '';
    });
    final e = await app.saveSettings(
      from: from,
      to: to,
      minOrder: parseInt(min.text) ?? 0,
      prepMin: parseInt(prep.text) ?? 0,
      desc: desc.text.trim(),
      cover: cover,
    );
    if (!mounted) return;
    setState(() {
      busy = false;
      err = e;
      if (e.isEmpty) cover = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final s = app.shop ?? {};
        final hint = Theme.of(context).hintColor;
        final shown = cover != null ? (cover!.isEmpty ? null : cover) : app.coverImage();
        final hasLoc = s['lat'] != null;
        return ListView(padding: EdgeInsets.zero, children: [
          const ShopHeader(title: 'إعدادات المحل'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // صورة الغلاف
              Box(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('واجهة المحل', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      final d = await pickImage(context, max: 900, limit: 260000);
                      if (d != null) setState(() => cover = d);
                    },
                    child: Container(
                      height: 150,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: dataUrlBytes(shown) != null
                          ? Image.memory(dataUrlBytes(shown)!, fit: BoxFit.cover, width: double.infinity)
                          : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Icons.add_a_photo_rounded, size: 36, color: hint),
                              const SizedBox(height: 6),
                              Text('صورة الغلاف: واجهة المحل أو أشهر طبق', style: TextStyle(color: hint)),
                            ]),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    cover != null ? 'اضغط «حفظ» في الأسفل لحفظ الصورة.' : 'تظهر في أعلى بطاقة محلك، والمحلات بصور تُطلب أكثر.',
                    style: TextStyle(color: cover != null ? orange : hint, fontSize: 12, fontWeight: cover != null ? FontWeight.w700 : null),
                  ),
                  if (shown != null)
                    TextButton.icon(
                      onPressed: () => setState(() => cover = ''),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('إزالة الصورة'),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              // الموقع
              Box(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('موقع المحل', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('اضغط الزر وأنت داخل المحل. به نعرض طلباتك على أقرب موصّل، ويجد الموصّل المحل على الخريطة.',
                      style: TextStyle(color: hint, fontSize: 13)),
                  const SizedBox(height: 10),
                  if (hasLoc)
                    const Row(children: [
                      Icon(Icons.check_circle_rounded, color: brand, size: 18),
                      SizedBox(width: 6),
                      Text('موقع المحل محدد', style: TextStyle(color: brand, fontWeight: FontWeight.w600)),
                    ])
                  else
                    const Note('موقع المحل غير محدد بعد.', color: warn, icon: Icons.location_off_rounded),
                  const SizedBox(height: 10),
                  _LocButton(
                    primary: !hasLoc,
                    onPressed: geoBusy
                        ? null
                        : () async {
                            setState(() {
                              geoBusy = true;
                              geoErr = '';
                            });
                            final e = await app.saveLocation();
                            if (mounted) {
                              setState(() {
                                geoBusy = false;
                                geoErr = e;
                              });
                            }
                          },
                    label: geoBusy ? 'جارٍ تحديد الموقع…' : (hasLoc ? 'حدّث الموقع' : 'حدّد موقع المحل الآن'),
                  ),
                  if (geoErr.isNotEmpty) ...[const SizedBox(height: 8), Note(geoErr, color: warn, icon: Icons.error_outline_rounded)],
                ]),
              ),
              const SizedBox(height: 12),
              // الساعات والطلب
              Box(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('ساعات العمل والطلب', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickTime(true),
                        child: Text(from.isEmpty ? 'يفتح الساعة' : 'يفتح $from'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickTime(false),
                        child: Text(to.isEmpty ? 'يغلق الساعة' : 'يغلق $to'),
                      ),
                    ),
                  ]),
                  if (from.isNotEmpty || to.isNotEmpty)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        onPressed: () => setState(() {
                          from = '';
                          to = '';
                        }),
                        child: const Text('بدون ساعات (أتحكم بالمفتاح فقط)'),
                      ),
                    ),
                  Text('خارج هذه الساعات يرى الزبائن محلك مغلقاً حتى لو نسيت إغلاقه.', style: TextStyle(color: hint, fontSize: 12)),
                  const SizedBox(height: 14),
                  TextField(
                    controller: min,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'أقل مبلغ للطلب', suffixText: 'دج', hintText: '0'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: prep,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'وقت التحضير المعتاد', suffixText: 'دقيقة', hintText: '20'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: desc,
                    maxLength: 80,
                    decoration: const InputDecoration(labelText: 'جملة تعريفية (اختياري)', hintText: 'مثال: بيتزا على الحطب منذ 2010'),
                  ),
                  if (err.isNotEmpty) ...[Note(err, color: warn, icon: Icons.error_outline_rounded), const SizedBox(height: 10)],
                  FilledButton(
                    onPressed: busy ? null : _save,
                    child: busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : const Text('حفظ'),
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

class _LocButton extends StatelessWidget {
  final bool primary;
  final VoidCallback? onPressed;
  final String label;
  const _LocButton({required this.primary, required this.onPressed, required this.label});

  @override
  Widget build(BuildContext context) {
    const icon = Icon(Icons.my_location_rounded);
    return primary
        ? FilledButton.icon(onPressed: onPressed, icon: icon, label: Text(label))
        : OutlinedButton.icon(onPressed: onPressed, icon: icon, label: Text(label));
  }
}
