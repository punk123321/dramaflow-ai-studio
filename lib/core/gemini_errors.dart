/// Burmese explanations of Gemini API errors. No network here, so it is tested.

bool _isLocation(String detail) {
  final d = detail.toLowerCase();
  return d.contains('location is not supported') || d.contains('user location');
}

const _locationText =
    'သင့်တည်နေရာ (IP) ကို Gemini API အတွက် Google က မခွင့်ပြုဘူး — VPN ဖွင့်ပြီး ပြန်စမ်းပါ။ '
    '(ဗီဒီယို upload က ဖုန်းကနေ Google ဆီ တိုက်ရိုက်သွားလို့ ဖြစ်တာ။ Scene Recap လို Backend (Colab) ကတဆင့် သွားတဲ့ အပိုင်းတွေကတော့ မထိခိုက်ဘူး)';

/// What went wrong with a Gemini upload call, in Burmese. [detail] is the
/// message the API sent (may be empty).
String geminiUploadHint(int code, String detail) {
  if (_isLocation(detail)) return _locationText;
  final why = switch (code) {
    400 => 'Gemini က ဗီဒီယိုကို လက်မခံဘူး (mp4/mov/webm/avi လို ပုံစံ လိုတယ်၊ mkv မရဘူး)',
    401 || 403 => 'API key မမှန်ဘူး (သို့) ခွင့်မရှိဘူး',
    429 => 'Gemini quota ပြည့်နေတယ် (နောက်မှ ပြန်စမ်း)',
    500 || 503 => 'Google ဘက် လူသုံးများနေတယ် (ခဏနေ ပြန်စမ်း)',
    _ => 'Gemini HTTP $code',
  };
  if (detail.isEmpty) return why;
  return '$why: ${detail.length > 160 ? detail.substring(0, 160) : detail}';
}

/// What the quick check before an upload found, or null when nothing stops
/// the upload (also null for errors that say nothing about the key or place,
/// so a busy server never blocks an upload that would have worked).
String? geminiPreflightProblem(int code, String detail) {
  if (code == 200) return null;
  if (_isLocation(detail)) return _locationText;
  final d = detail.toLowerCase();
  if ((code == 400 || code == 401 || code == 403) && (d.contains('api key') || d.contains('api_key') || d.contains('permission'))) {
    return 'API key မမှန်ဘူး (သို့) Gemini API ကို ခွင့်မပြုထားဘူး — Settings မှာ key ကို စစ်ပါ';
  }
  return null;
}
