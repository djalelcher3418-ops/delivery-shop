import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';
import 'package:image/image.dart' as im;

/// قصّ خلفية صورة المنتج على الهاتف نفسه (Google ML Kit، مجاني وبدون خادم).
/// يرجع صورة PNG شفافة كـ data URL، أو يرمي رسالة عربية مفهومة إذا فشل.
Future<String> cutBackground(String path) async {
  final seg = SubjectSegmenter(
    options: SubjectSegmenterOptions(
      enableForegroundBitmap: true,
      enableForegroundConfidenceMask: false,
      enableMultipleSubjects: SubjectResultOptions(enableConfidenceMask: false, enableSubjectBitmap: false),
    ),
  );
  Uint8List? png;
  try {
    final r = await seg.processImage(InputImage.fromFilePath(path));
    png = r.foregroundBitmap;
  } catch (e) {
    // أول مرة ينزّل الهاتف أداة القصّ من خدمات Google
    throw 'أداة قصّ الخلفية تُنزَّل الآن على هاتفك لأول مرة. تأكد من الإنترنت وحاول بعد دقيقة.';
  } finally {
    seg.close();
  }
  if (png == null || png.isEmpty) throw 'لم نجد المنتج في الصورة. صوّره وحده على خلفية واضحة.';
  final out = await Isolate.run(() => _shrink(png!));
  if (out == null) throw 'لم نجد المنتج في الصورة. صوّره وحده على خلفية واضحة.';
  return out;
}

/// يقصّ الفراغ الشفاف حول المنتج ويصغّر الصورة حتى تناسب قاعدة البيانات
String? _shrink(Uint8List bytes) {
  final src = im.decodeImage(bytes);
  if (src == null) return null;
  final t = im.trim(src, mode: im.TrimMode.transparent);
  if (t.width < 16 || t.height < 16) return null;
  for (final side in [420, 360, 300, 240]) {
    final r = t.width >= t.height
        ? im.copyResize(t, width: t.width > side ? side : t.width, interpolation: im.Interpolation.average)
        : im.copyResize(t, height: t.height > side ? side : t.height, interpolation: im.Interpolation.average);
    final d = 'data:image/png;base64,${base64Encode(im.encodePng(r, level: 9))}';
    if (d.length <= 320000) return d;
  }
  return null;
}
