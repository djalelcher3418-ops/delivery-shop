import 'package:flutter/material.dart';

import '../store.dart';
import '../ui.dart';
import 'products.dart';

/// يوميات (تختفي بعد 24 ساعة) وإعلانات (لعدة أيام) تظهر للزبائن في صفحة المحل
class PostsScreen extends StatelessWidget {
  const PostsScreen({super.key});

  static String leftText(int until) {
    final m = ((until - nowMs()) / 60000).ceil();
    if (m < 60) return 'ينتهي بعد $m د';
    final h = (m / 60).floor();
    if (h < 24) return 'ينتهي بعد $h سا';
    final d = (h / 24).ceil();
    return 'ينتهي بعد ${d == 1 ? 'يوم' : d == 2 ? 'يومين' : '$d أيام'}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final posts = app.posts;
        final hint = Theme.of(context).hintColor;
        return Scaffold(
          appBar: AppBar(title: const Text('يومياتي وإعلاناتي')),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 30), children: [
            const Note(
              'ما تنشره هنا يراه الزبائن في صفحة محلك، واليوميات تظهر أيضاً في أعلى الصفحة الرئيسية للتطبيق. '
              'اليومية تختفي وحدها بعد 24 ساعة، والإعلان يبقى المدة التي تختارها.',
              icon: Icons.campaign_rounded,
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: orange),
                  onPressed: () => _compose(context, 'story'),
                  icon: const Icon(Icons.add_a_photo_rounded),
                  label: const Text('يومية'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _compose(context, 'ad'),
                  icon: const Icon(Icons.campaign_rounded),
                  label: const Text('إعلان'),
                ),
              ),
            ]),
            const SizedBox(height: 18),
            Text('منشوراتك الآن (${posts.length})', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (posts.isEmpty)
              const EmptyState(
                icon: Icons.photo_library_outlined,
                title: 'لا توجد منشورات نشطة',
                text: 'انشر صورة طبق اليوم أو عرضاً خاصاً ليراه زبائنك.',
              )
            else
              for (final p in posts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Box(
                    padding: const EdgeInsets.all(10),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Thumb64(app.postImage(p), size: 64, icon: p['kind'] == 'story' ? Icons.auto_stories_rounded : Icons.campaign_rounded),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            p['kind'] == 'story'
                                ? const Pill('يومية', bg: Color(0xFFFFF1DC), fg: Color(0xFF8A4B00), icon: Icons.auto_stories_rounded)
                                : const Pill('إعلان', bg: Color(0xFFE3ECF7), fg: info, icon: Icons.campaign_rounded),
                            const SizedBox(width: 6),
                            Expanded(child: Text(leftText(asInt(p['until'])), style: TextStyle(color: hint, fontSize: 12))),
                          ]),
                          if ('${p['text'] ?? ''}'.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text('${p['text']}', maxLines: 3, overflow: TextOverflow.ellipsis),
                          ],
                        ]),
                      ),
                      IconButton(
                        tooltip: 'حذف',
                        onPressed: () async {
                          if (await confirm(context, 'حذف المنشور؟', 'لن يراه الزبائن بعد الآن.', 'حذف')) app.deletePost(p);
                        },
                        icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade700),
                      ),
                    ]),
                  ),
                ),
          ]),
        );
      },
    );
  }

  Future<void> _compose(BuildContext context, String kind) async {
    final story = kind == 'story';
    String? img;
    // اليومية تبدأ بالصورة غالباً
    if (story) {
      img = await pickImage(context, max: 900, limit: 350000);
      if (!context.mounted) return;
    }
    final text = TextEditingController();
    int days = 3;
    String err = '';
    bool busy = false;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => Padding(
          padding: EdgeInsets.fromLTRB(18, 0, 18, MediaQuery.of(c).viewInsets.bottom + 18),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(story ? 'يومية جديدة' : 'إعلان جديد', style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(story ? 'تظهر للزبائن 24 ساعة ثم تختفي.' : 'يظهر في صفحة محلك المدة التي تختارها.',
                  style: TextStyle(color: Theme.of(c).hintColor)),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  final x = await pickImage(c, max: 900, limit: 350000);
                  if (x != null) setS(() => img = x);
                },
                child: img == null
                    ? Container(
                        height: 90,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Theme.of(c).dividerColor),
                        ),
                        child: Center(
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.add_photo_alternate_rounded),
                            const SizedBox(width: 8),
                            Text(story ? 'أضف صورة' : 'أضف صورة (اختياري)'),
                          ]),
                        ),
                      )
                    : Stack(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.memory(dataUrlBytes(img)!, height: 200, width: double.infinity, fit: BoxFit.cover),
                        ),
                        PositionedDirectional(
                          top: 6,
                          end: 6,
                          child: CircleAvatar(
                            backgroundColor: Colors.black54,
                            child: IconButton(
                              tooltip: 'إزالة الصورة',
                              onPressed: () => setS(() => img = null),
                              icon: const Icon(Icons.close_rounded, color: Colors.white),
                            ),
                          ),
                        ),
                      ]),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: text,
                maxLines: 4,
                minLines: 2,
                maxLength: 300,
                decoration: InputDecoration(
                  labelText: story ? 'تعليق (اختياري)' : 'نص الإعلان',
                  hintText: story ? 'مثال: طبق اليوم: كسكسي بالخضر' : 'مثال: كل يوم جمعة توصيل مجاني للطلبات فوق 2000 دج',
                  errorText: err.isEmpty ? null : err,
                ),
              ),
              if (!story) ...[
                const SizedBox(height: 6),
                Text('مدة ظهور الإعلان', style: TextStyle(color: Theme.of(c).hintColor, fontSize: 13)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, children: [
                  for (final d in const [1, 3, 7, 14])
                    ChoiceChip(
                      label: Text(d == 1 ? 'يوم' : d == 3 ? '3 أيام' : d == 7 ? 'أسبوع' : 'أسبوعان'),
                      selected: days == d,
                      onSelected: (_) => setS(() => days = d),
                    ),
                ]),
              ],
              const SizedBox(height: 14),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: story ? orange : null),
                onPressed: busy
                    ? null
                    : () async {
                        setS(() {
                          busy = true;
                          err = '';
                        });
                        final e = await app.addPost(kind: kind, text: text.text, img: img, days: days);
                        if (e.isNotEmpty) {
                          setS(() {
                            busy = false;
                            err = e;
                          });
                          return;
                        }
                        if (c.mounted) Navigator.pop(c);
                      },
                child: Text(busy ? 'جارٍ النشر…' : 'انشر الآن'),
              ),
            ]),
          ),
        ),
      ),
    );
    text.dispose();
  }
}
