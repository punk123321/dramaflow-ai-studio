import 'dart:convert';

/// What this phone has sent today to the services behind Auto Recap. It is a
/// count made by the app itself, so it is only an estimate: the services keep
/// their own count (and may count retries or other apps' use of the same key).
class UsageLog {
  const UsageLog({this.day = '', this.gemini = 0, this.asrSeconds = 0, this.voices = 0});

  final String day;

  /// Requests the app asked the backend to make to Gemini (one per group).
  final int gemini;
  final int asrSeconds;

  /// Voice parts the backend made.
  final int voices;

  static String dayKey(DateTime t) => '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  /// The counts of [today]; a log of another day starts again from zero.
  UsageLog forDay(String today) => day == today ? this : UsageLog(day: today);

  UsageLog add(String today, {int gemini = 0, int asrSeconds = 0, int voices = 0}) {
    final base = forDay(today);
    return UsageLog(
      day: today,
      gemini: base.gemini + gemini,
      asrSeconds: base.asrSeconds + asrSeconds,
      voices: base.voices + voices,
    );
  }

  /// Whole minutes, a started minute counts (AssemblyAI bills by audio time).
  int get asrMinutes => (asrSeconds + 59) ~/ 60;

  bool get isEmpty => gemini == 0 && asrSeconds == 0 && voices == 0;

  String summary() => 'ဒီနေ့ ဒီဖုန်းက ပို့ခဲ့တာ (ခန့်မှန်း): Gemini $gemini ကြိမ်၊ AssemblyAI $asrMinutes မိနစ်၊ အသံ $voices ပိုင်း';

  String encode() => jsonEncode({'day': day, 'gemini': gemini, 'asr': asrSeconds, 'voices': voices});

  static UsageLog decode(String? s) {
    if (s == null || s.trim().isEmpty) return const UsageLog();
    try {
      final m = jsonDecode(s);
      if (m is! Map) return const UsageLog();
      int n(Object? v) => v is num && v >= 0 ? v.toInt() : 0;
      return UsageLog(day: m['day'] is String ? m['day'] as String : '', gemini: n(m['gemini']), asrSeconds: n(m['asr']), voices: n(m['voices']));
    } catch (_) {
      return const UsageLog();
    }
  }
}

/// Minutes (rounded up) of the sound that will go to AssemblyAI, for the
/// confirmation box. 0 when the length is not known.
int asrMinutesFor(int durationMs) => durationMs <= 0 ? 0 : (durationMs + 59999) ~/ 60000;
