import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../store.dart';
import '../ui.dart';
import 'shell.dart';

/// يصوّر أو يختار صورة ويصغّرها مثل الموقع، ويرجعها data URL (أو null إذا ألغى)
Future<String?> pickImage(BuildContext context, {double max = 480, int limit = 200000}) async {
  final src = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.photo_camera_rounded),
          title: const Text('صوّر الآن'),
          onTap: () => Navigator.pop(c, ImageSource.camera),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library_rounded),
          title: const Text('اختر من الصور'),
          onTap: () => Navigator.pop(c, ImageSource.gallery),
        ),
      ]),
    ),
  );
  if (src == null) return null;
  for (final q in [80, 65, 50, 40]) {
    final f = await ImagePicker().pickImage(source: src, maxWidth: max, maxHeight: max, imageQuality: q);
    if (f == null) return null;
    final data = 'data:image/jpeg;base64,${base64Encode(await f.readAsBytes())}';
    if (data.length <= limit || q == 40) return data;
    if (src == ImageSource.camera) return data; // لا نطلب التصوير مرة ثانية
  }
  return null;
}

class Thumb64 extends StatelessWidget {
  final String? data;
  final double size;
  final IconData icon;
  const Thumb64(this.data, {super.key, this.size = 58, this.icon = Icons.fastfood_rounded});

  @override
  Widget build(BuildContext context) {
    final bytes = dataUrlBytes(data);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: size,
        height: size,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: bytes == null
            ? Icon(icon, color: Theme.of(context).hintColor)
            : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
      ),
    );
  }
}

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});
  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final search = TextEditingController();
  String filter = 'all'; // all | on | off

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void _edit(BuildContext context, [Doc? p]) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductEditScreen(product: p)));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([app, search]),
      builder: (context, _) {
        final prods = app.products;
        final n = prods.where((p) => p['available'] == true).length;
        final hint = Theme.of(context).hintColor;
        final q = latinDigits(search.text.trim().toLowerCase());
        final shown = prods.where((p) {
          if (filter == 'on' && p['available'] != true) return false;
          if (filter == 'off' && p['available'] == true) return false;
          if (q.isEmpty) return true;
          return '${p['name'] ?? ''} ${p['section'] ?? ''}'.toLowerCase().contains(q);
        }).toList();
        // المنتجات مرتبة حسب القسم، فنضع عنوان القسم قبل أول منتج منه
        final rows = <Widget>[];
        String? sec;
        for (final p in shown) {
          final ps = '${p['section'] ?? ''}';
          if (ps != sec) {
            sec = ps;
            final count = shown.where((x) => '${x['section'] ?? ''}' == ps).length;
            rows.add(Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
              child: Text('${ps.isEmpty ? 'بدون قسم' : ps} ($count)',
                  style: TextStyle(color: hint, fontWeight: FontWeight.w700, fontSize: 13)),
            ));
          }
          rows.add(_ProductRow(p: p, onTap: () => _edit(context, p)));
        }
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _edit(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('منتج جديد'),
          ),
          body: ListView(padding: EdgeInsets.zero, children: [
            const ShopHeader(title: 'منتجاتي'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('$n من ${prods.length} منتجات متوفرة الآن', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('اضغط على المنتج لتعديل سعره أو صورته. أوقف المنتج الذي نفد ليظهر للزبون «نفد حالياً».',
                    style: TextStyle(color: hint, fontSize: 13)),
                const SizedBox(height: 12),
                if (prods.length > 5) ...[
                  TextField(
                    controller: search,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'ابحث عن منتج أو قسم',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: search.text.isEmpty
                          ? null
                          : IconButton(tooltip: 'مسح', onPressed: search.clear, icon: const Icon(Icons.close_rounded)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    for (final f in [('all', 'الكل (${prods.length})'), ('on', 'متوفر ($n)'), ('off', 'نفد (${prods.length - n})')])
                      ChoiceChip(
                        label: Text(f.$2),
                        selected: filter == f.$1,
                        onSelected: (_) => setState(() => filter = f.$1),
                      ),
                  ]),
                  const SizedBox(height: 4),
                ],
                if (!app.loadedProducts)
                  const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
                else if (prods.isEmpty)
                  const EmptyState(
                      icon: Icons.inventory_2_rounded,
                      title: 'لم تضف منتجات بعد',
                      text: 'أضف أول منتج ليظهر محلك للزبائن مع قائمته.')
                else if (shown.isEmpty)
                  const EmptyState(icon: Icons.search_off_rounded, title: 'لا توجد منتجات بهذا البحث')
                else
                  ...rows,
              ]),
            ),
          ]),
        );
      },
    );
  }
}

class _ProductRow extends StatelessWidget {
  final Doc p;
  final VoidCallback onTap;
  const _ProductRow({required this.p, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Box(
        padding: const EdgeInsets.all(10),
        onTap: onTap,
        child: Row(children: [
          Opacity(opacity: p['available'] == true ? 1 : 0.5, child: Thumb64(app.productImage(p))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${p['name'] ?? ''}', style: TextStyle(fontWeight: FontWeight.w700, color: p['available'] == true ? null : hint)),
              Text(
                '${optList(p['sizes']).isNotEmpty ? 'من ' : ''}${money(basePrice(p))} · '
                '${p['available'] == true ? 'متوفر' : 'نفد'}${hasOpts(p) ? ' · بخيارات' : ''}',
                style: TextStyle(color: hint, fontSize: 12),
              ),
            ]),
          ),
          Switch(value: p['available'] == true, onChanged: (_) => app.toggleProduct(p)),
        ]),
      ),
    );
  }
}

class ProductEditScreen extends StatefulWidget {
  final Doc? product;
  const ProductEditScreen({super.key, this.product});
  @override
  State<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  late final TextEditingController name, price, section, desc, sizes, extras;
  bool available = true, busy = false;
  String? img; // null = لا تغيير
  String errName = '', errPrice = '', errOpts = '', errForm = '';

  bool get editing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product ?? {};
    name = TextEditingController(text: '${p['name'] ?? ''}');
    price = TextEditingController(text: p['price'] != null ? '${p['price']}' : '');
    section = TextEditingController(text: '${p['section'] ?? (app.sections.isNotEmpty ? app.sections.first : '')}');
    desc = TextEditingController(text: '${p['desc'] ?? ''}');
    sizes = TextEditingController(text: optsToText(p['sizes']));
    extras = TextEditingController(text: optsToText(p['extras']));
    available = editing ? p['available'] == true : true;
  }

  @override
  void dispose() {
    for (final c in [name, price, section, desc, sizes, extras]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final n = name.text.trim();
    var pr = parseInt(price.text);
    final sz = parseOpts(sizes.text), ex = parseOpts(extras.text);
    if (sz.isNotEmpty && (pr == null || pr <= 0)) {
      pr = sz.map((x) => asInt(x['price'])).reduce((a, b) => a < b ? a : b);
      price.text = '$pr';
    }
    setState(() {
      errName = n.length < 2 ? 'اكتب اسم المنتج.' : '';
      errPrice = (pr == null || pr <= 0) ? 'اكتب السعر بالدينار، رقماً أكبر من صفر.' : '';
      errOpts = (sizes.text.trim().isNotEmpty && sz.isEmpty) || (extras.text.trim().isNotEmpty && ex.isEmpty)
          ? 'اكتب كل خيار في سطر: الاسم ثم السعر، مثل «كبير 800».'
          : '';
      errForm = '';
    });
    if (errName.isNotEmpty || errPrice.isNotEmpty || errOpts.isNotEmpty) return;
    setState(() => busy = true);
    final e = await app.saveProduct(
      editId: widget.product?['id'],
      name: n,
      price: pr!,
      section: section.text.trim(),
      desc: desc.text.trim(),
      sizes: sz,
      extras: ex,
      available: available,
      img: img,
    );
    if (!mounted) return;
    setState(() {
      busy = false;
      errForm = e;
    });
    if (e.isEmpty) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final shown = img != null ? (img!.isEmpty ? null : img) : (editing ? app.productImage(widget.product!) : null);
        return Scaffold(
          appBar: AppBar(title: Text(editing ? 'تعديل المنتج' : 'منتج جديد')),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 30), children: [
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () async {
                final d = await pickImage(context);
                if (d != null) setState(() => img = d);
              },
              child: Container(
                height: 180,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18),
                ),
                clipBehavior: Clip.antiAlias,
                child: dataUrlBytes(shown) != null
                    ? Image.memory(dataUrlBytes(shown)!, fit: BoxFit.cover, width: double.infinity)
                    : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.add_a_photo_rounded, size: 40, color: hint),
                        const SizedBox(height: 6),
                        Text('صوّر المنتج أو اختر صورة', style: TextStyle(color: hint)),
                      ]),
              ),
            ),
            if (shown != null)
              TextButton.icon(
                onPressed: () => setState(() => img = ''),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('إزالة الصورة'),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: name,
              decoration: InputDecoration(labelText: 'اسم المنتج', hintText: 'مثال: بيتزا', errorText: errName.isEmpty ? null : errName),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: price,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'السعر', suffixText: 'دج', errorText: errPrice.isEmpty ? null : errPrice),
            ),
            const SizedBox(height: 12),
            TextField(controller: section, decoration: const InputDecoration(labelText: 'القسم', hintText: 'مثال: الأطباق')),
            if (app.sections.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final s in app.sections)
                  ActionChip(label: Text(s), onPressed: () => setState(() => section.text = s)),
              ]),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: desc,
              maxLength: 140,
              decoration: const InputDecoration(labelText: 'وصف قصير (اختياري)', hintText: 'مثال: صلصة طماطم، جبن موزاريلا، زيتون'),
            ),
            const SizedBox(height: 8),
            Text('خيارات المنتج (اختياري)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: sizes,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'الأحجام — كل حجم في سطر مع سعره',
                hintText: 'صغير 400\nوسط 600\nكبير 800',
                helperText: 'إذا كتبت أحجاماً يختار الزبون واحداً منها، ويُستعمل سعره.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: extras,
              minLines: 2,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: 'الإضافات — كل إضافة في سطر مع سعرها',
                hintText: 'جبن إضافي 100\nصلصة حارة 0',
                helperText: 'يختار الزبون ما يشاء منها، ويُضاف سعرها.',
                errorText: errOpts.isEmpty ? null : errOpts,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: available,
              onChanged: (v) => setState(() => available = v),
              title: const Text('متوفر الآن', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('يظهر فوراً للزبائن في صفحة محلك'),
            ),
            if (errForm.isNotEmpty) Note(errForm, color: warn, icon: Icons.error_outline_rounded),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: busy ? null : _save,
              child: busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Text('حفظ المنتج'),
            ),
            if (editing) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
                onPressed: busy
                    ? null
                    : () async {
                        if (await confirm(context, 'حذف المنتج؟', 'يختفي «${widget.product!['name']}» من محلك نهائياً.', 'احذف')) {
                          final ok = await app.deleteProduct(widget.product!);
                          if (ok && context.mounted) Navigator.pop(context);
                        }
                      },
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('حذف المنتج'),
              ),
            ],
          ]),
        );
      },
    );
  }
}
