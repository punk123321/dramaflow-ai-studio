/// Making the video on the Colab machine instead of the phone. The job is the same JSON the phone's own
/// renderer reads (see `buildRenderJob`); the backend (`render_core.py`) turns it into one ffmpeg command.
///
/// Stage 1 supports: cut pieces (in order), speed, flip, whole-picture blur, blur boxes (Censor), the
/// ORIGINAL sound, burned-in subtitles, size / fit (original, bars, crop), frame rate and bitrate.
/// Anything else in a job must be refused, so a video never comes out with something missing.
/// This list mirrors `unsupported()` in render_core.py; keep the two in step.
List<String> colabUnsupported(Map<String, Object?> job) {
  final why = <String>[];
  final raw = job['pieces'];
  final pieces = raw is List ? [for (final p in raw) if (p is Map) p] : <Map>[];
  if (pieces.isEmpty) return ['ဗီဒီယို အပိုင်း မရှိဘူး'];
  if (pieces.length > 400) why.add('အပိုင်း 400 ထက် မများရဘူး');
  num n(Object? v, [num d = 0]) => v is num ? v : d;
  var lastEnd = -1.0;
  for (final p in pieces) {
    final s = n(p['s']).toDouble();
    final e = n(p['e']).toDouble();
    if (e <= s) {
      why.add('အပိုင်းတစ်ခုရဲ့ အချိန် မမှန်ဘူး');
      break;
    }
    if (s < lastEnd) {
      why.add('အပိုင်းတွေ အစီအစဉ်မကျ / ထပ်နေလို့ Colab မှာ မရသေးဘူး (မူရင်းအချိန်အတိုင်း စီပါ)');
      break;
    }
    lastEnd = e;
  }
  if (pieces.any((p) => p['f'] != null && p['f'] != 0)) why.add('Freeze Frame');
  if (pieces.any((p) => p['c'] != null)) why.add('Crop / Zoom reframe');
  if (pieces.any((p) => n(p['z']) != 0)) why.add('Zoom in / out');
  if (pieces.any((p) => p['l'] != null)) why.add('Filter (အရောင်)');
  if (pieces.any((p) {
    final sp = n(p['sp'], 1.0);
    return sp < 0.25 || sp > 4.0;
  })) {
    why.add('Speed ၀.၂၅–၄ အပြင်ဘက်');
  }
  bool has(String k) {
    final v = job[k];
    if (v == null) return false;
    if (v is List) return v.isNotEmpty;
    if (v is Map) return v.isNotEmpty;
    return true;
  }

  final lanes = job['voiceLanes'];
  if (lanes is List && lanes.any((l) => l is List && l.isNotEmpty)) why.add('Narration အသံ (ဖုန်းထဲက အသံဖိုင်တွေကို Colab ဆီ မပို့ရသေးဘူး)');
  if (has('music')) why.add('Background music');
  if (has('overlays')) why.add('Overlay (စာသား / ပုံသဏ္ဌာန် / Fade / Border …)');
  if (has('splits')) why.add('Split Screen');
  if (has('logo')) why.add('Logo');
  if (has('corners')) why.add('ထောင့်စာသား');
  if (job['fit'] == 'blur') why.add('Blur background (fit)');
  final cens = job['censors'];
  if (cens is List && cens.length > 6) why.add('Blur box 6 ခုထက် များနေတယ်');
  return why;
}

/// The Studio request that makes [job] from [file], a video that is already in the backend's library.
/// Things that only mean something on the phone are left out.
Map<String, Object?> studioRenderRequest({required String file, required Map<String, Object?> job, String font = 'Padauk'}) => {
      'op': 'render',
      'file': file,
      'font': font,
      'job': {
        for (final e in job.entries)
          if (e.key != 'videoUri' && e.key != 'estimateBytes') e.key: e.value,
      },
    };

/// "Same file?" check between the project's video and the one picked in the backend's library. Only the size is
/// compared (the phone cannot read the backend's file). Null when the project's size is not known.
bool? sameVideoSize(int? projectBytes, int libraryBytes) {
  if (projectBytes == null || projectBytes <= 0) return null;
  return projectBytes == libraryBytes;
}
