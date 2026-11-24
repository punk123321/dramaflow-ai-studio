import '../data/export_item.dart';
import 'render_channel.dart';

/// Puts a finished part in the Gallery and, only when that really worked,
/// frees the phone's own copy (a long video made of many parts would otherwise
/// take twice the space and the later parts fail to save).
class PartSaver {
  PartSaver._();

  /// Null when the part is in the Gallery; otherwise a short Burmese reason.
  /// The app's own copy and its history entry are kept in that case, so it can
  /// still be saved by hand from the Save stage.
  static Future<String?> toGallery(ExportItem done, String name, {ExportRepo? repo, bool keepCopy = false}) async {
    try {
      await RenderChannel.saveToGallery(done.path, name);
    } catch (e) {
      return galleryFailText('$e');
    }
    final r = repo ?? ExportRepo();
    try {
      if (done.id != null) await r.markInGallery(done.id!);
      if (!keepCopy) {
        if (await RenderChannel.deleteRender(done.path) && done.id != null) await r.delete(done.id!);
      }
    } catch (_) {
      // The Gallery has it; a leftover copy is only wasted space.
    }
    return null;
  }
}

/// A short reason in Burmese for a failed Gallery save.
String galleryFailText(String raw) {
  final t = raw.toLowerCase();
  if (t.contains('use_export')) return 'ဒီ Android ဗားရှင်း (9 နဲ့ အောက်) မှာ Gallery ထဲ တိုက်ရိုက် မသိမ်းနိုင်ဘူး';
  if (t.contains('enospc') || t.contains('space') || t.contains('no space')) return 'ဖုန်းမှာ နေရာ မလောက်တော့ဘူး';
  if (t.contains('missing') || t.contains('gone')) return 'ဗီဒီယိုဖိုင် ပျောက်နေတယ်';
  return 'Gallery က လက်မခံဘူး (နေရာမလောက်တာ ဖြစ်နိုင်တယ်): ${raw.length > 80 ? raw.substring(0, 80) : raw}';
}

/// One line saved after a run of many parts, so the person who comes back later
/// (or the next day) can see how far it got and why it stopped.
String partsRunSummary({required int total, required int saved, required String what, String? stoppedAt, String? why}) {
  if (stoppedAt == null && saved == total) return '$what $saved ခု အားလုံး ထုတ်ပြီး Gallery ထဲ သိမ်းပြီး';
  final b = StringBuffer('$what $total ခုထဲက $saved ခု Gallery ထဲ သိမ်းပြီး');
  if (stoppedAt != null) b.write('၊ $stoppedAt မှာ ရပ်သွားတယ်');
  if (why != null && why.isNotEmpty) b.write(': $why');
  return b.toString();
}
