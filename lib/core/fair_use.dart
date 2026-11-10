import 'dart:convert';

import 'timeline.dart';

/// Copyright and fair-use helper. Pure Dart, no Flutter.
///
/// It does NOT decide what is legal. It measures what the edit really
/// contains (how much of the original is reused, how much is the maker's own
/// narration) and reminds the maker of the records worth keeping. It has no
/// feature that hides material from a platform's copyright checks, and it
/// never will.

enum Permission { none, asked, granted, licensed }

enum Risk { low, medium, high }

/// What the maker says about the source material.
class FairUseRecord {
  const FairUseRecord({
    this.sourceNote = '',
    this.rightsHolder = '',
    this.permission = Permission.none,
    this.permissionNote = '',
    this.checks = const {},
  });

  /// Where the original video came from (platform, link, channel).
  final String sourceNote;
  final String rightsHolder;
  final Permission permission;

  /// Link, e-mail date, licence name: whatever proves the permission.
  final String permissionNote;

  /// Checklist answers by key (see [fairUseChecklist]).
  final Map<String, bool> checks;

  bool checked(String key) => checks[key] ?? false;

  FairUseRecord copyWith({
    String? sourceNote,
    String? rightsHolder,
    Permission? permission,
    String? permissionNote,
    Map<String, bool>? checks,
  }) =>
      FairUseRecord(
        sourceNote: sourceNote ?? this.sourceNote,
        rightsHolder: rightsHolder ?? this.rightsHolder,
        permission: permission ?? this.permission,
        permissionNote: permissionNote ?? this.permissionNote,
        checks: checks ?? this.checks,
      );

  String encode() => jsonEncode({
        'v': 1,
        'src': sourceNote,
        'rh': rightsHolder,
        'perm': permission.index,
        'pn': permissionNote,
        'checks': checks,
      });

  static FairUseRecord decode(String? raw) {
    if (raw == null || raw.isEmpty) return const FairUseRecord();
    try {
      final m = jsonDecode(raw) as Map<String, Object?>;
      final p = m['perm'];
      final c = m['checks'];
      return FairUseRecord(
        sourceNote: (m['src'] as String?) ?? '',
        rightsHolder: (m['rh'] as String?) ?? '',
        permission: p is int && p >= 0 && p < Permission.values.length ? Permission.values[p] : Permission.none,
        permissionNote: (m['pn'] as String?) ?? '',
        checks: c is Map ? {for (final e in c.entries) e.key.toString(): e.value == true} : const {},
      );
    } catch (_) {
      return const FairUseRecord();
    }
  }
}

class CheckItem {
  const CheckItem(this.key, this.text, this.why);
  final String key;
  final String text;
  final String why;
}

/// Self-declared questions. Ticking one is the maker's own statement.
const fairUseChecklist = <CheckItem>[
  CheckItem('own_words', 'Narration ကို ကိုယ့်စကားနဲ့ ကိုယ်တိုင် ရေးထားတယ်',
      'မူရင်း စကားကို ကူးရေးထားရုံနဲ့ ကိုယ်ပိုင်ပါဝင်မှု မဖြစ်ပါ။'),
  CheckItem('commentary', 'ရှင်းပြချက်/ဝေဖန်ချက်/အကျဉ်းချုပ် ပါတယ် (ရိုးရိုး ပြန်ထုတ်ပြန်တာ မဟုတ်)',
      'ဗီဒီယိုကို အသစ်တစ်ခု ဖြစ်စေတဲ့ ကိုယ်ပိုင် ပါဝင်မှုက အရေးအကြီးဆုံးပါ။'),
  CheckItem('not_full', 'ဇာတ်လမ်းအပိုင်း အပြည့်ကို အစအဆုံး မတင်ထားဘူး',
      'အပြည့် ပြန်တင်တာက အန္တရာယ် အမြင့်ဆုံး ပုံစံပါ။'),
  CheckItem('no_remove', 'တခြားသူ watermark/logo ကို မဖျက်၊ မဖုံးထားဘူး',
      'ဒီ app က ဖျက်/ဖုံးတဲ့ feature မပေးပါ။ မူရင်းကို ပြင်ရင် ပြဿနာ ပိုကြီးပါတယ်။'),
  CheckItem('credit', 'မူရင်း ဖန်တီးသူ/ပလက်ဖောင်းကို ဖော်ပြထားမယ် (description ထဲ)',
      'ခွင့်ပြုချက် အစားထိုး မဟုတ်ပေမယ့် ရိုးသားမှု ပြတဲ့ အလေ့အထ ကောင်းပါ။'),
  CheckItem('music_ok', 'ထည့်တဲ့ background music ကို သုံးခွင့်ရှိတယ် (ကိုယ်ပိုင်/free licence)',
      'ဂီတမှာ သီးခြား copyright ရှိပါတယ်။'),
  CheckItem('records', 'Source နဲ့ ခွင့်ပြုချက် အထောက်အထားကို သိမ်းထားတယ်',
      'claim/dispute ဖြစ်ရင် ပြဖို့ လိုပါတယ်။'),
];

class FairUseMetrics {
  const FairUseMetrics({
    required this.outputMs,
    required this.sourceMs,
    required this.reusedMs,
    required this.narrationMs,
    required this.longestBareMs,
    required this.originalVolume,
  });

  final int outputMs;
  final int sourceMs;

  /// Distinct part of the original that is used (overlaps counted once).
  final int reusedMs;

  /// Output time covered by narration.
  final int narrationMs;

  /// Longest stretch of output with no narration.
  final int longestBareMs;
  final double originalVolume;

  double get reusedShare => sourceMs > 0 ? reusedMs / sourceMs : 0;
  double get narrationShare => outputMs > 0 ? narrationMs / outputMs : 0;
}

List<(int, int)> _union(List<(int, int)> raw) {
  final r = [...raw]..sort((a, b) => a.$1.compareTo(b.$1));
  final out = <(int, int)>[];
  for (final x in r) {
    if (x.$2 <= x.$1) continue;
    if (out.isNotEmpty && x.$1 <= out.last.$2) {
      if (x.$2 > out.last.$2) out[out.length - 1] = (out.last.$1, x.$2);
    } else {
      out.add(x);
    }
  }
  return out;
}

FairUseMetrics measure(Timeline t, {required int sourceMs}) {
  final out = t.videoMs;
  final reused = _union([for (final p in t.pieces) (p.startMs, p.endMs)])
      .fold<int>(0, (a, r) => a + (r.$2 - r.$1));
  final voices = _union([
    for (final v in t.voices) (v.offsetMs.clamp(0, out), v.endMs.clamp(0, out)),
  ]);
  final narr = voices.fold<int>(0, (a, r) => a + (r.$2 - r.$1));
  var longest = 0;
  var cursor = 0;
  for (final r in voices) {
    if (r.$1 - cursor > longest) longest = r.$1 - cursor;
    cursor = r.$2;
  }
  if (out - cursor > longest) longest = out - cursor;
  return FairUseMetrics(
    outputMs: out,
    sourceMs: sourceMs,
    reusedMs: reused,
    narrationMs: narr,
    longestBareMs: longest,
    originalVolume: t.originalVolume,
  );
}

class FairUseFinding {
  const FairUseFinding(this.risk, this.message);
  final Risk risk;
  final String message;
}

class FairUseReport {
  const FairUseReport(this.metrics, this.findings);
  final FairUseMetrics metrics;
  final List<FairUseFinding> findings;

  Risk get risk {
    var r = Risk.low;
    for (final f in findings) {
      if (f.risk == Risk.high) return Risk.high;
      if (f.risk == Risk.medium) r = Risk.medium;
    }
    return r;
  }
}

/// Rules of thumb only. A low result is NOT a guarantee: only the rights
/// holder, the platform or a court decides.
FairUseReport evaluate(Timeline t, FairUseRecord rec, {required int sourceMs}) {
  final m = measure(t, sourceMs: sourceMs);
  final f = <FairUseFinding>[];

  if (t.pieces.isEmpty) {
    f.add(const FairUseFinding(Risk.medium, 'Timeline ထဲမှာ ဗီဒီယို အပိုင်း မရှိသေးလို့ တိုင်းလို့ မရသေးပါ'));
    return FairUseReport(m, f);
  }

  if (m.sourceMs > 0) {
    if (m.reusedShare > 0.85) {
      f.add(FairUseFinding(Risk.high,
          'မူရင်းဗီဒီယို၏ ${(m.reusedShare * 100).round()}% ကို ပြန်သုံးထားတယ်။ အပြည့်နီးပါး ပြန်တင်တာနဲ့ တူပါတယ်'));
    } else if (m.reusedShare > 0.5) {
      f.add(FairUseFinding(Risk.medium,
          'မူရင်းဗီဒီယို၏ ${(m.reusedShare * 100).round()}% ကို သုံးထားတယ်။ အပိုင်းတွေ ပိုရွေးဖြတ်ဖို့ စဉ်းစားပါ'));
    }
  }

  if (t.voices.isEmpty) {
    f.add(const FairUseFinding(Risk.high, 'ကိုယ်ပိုင် narration မပါသေးပါ။ မူရင်းကို ပြန်ပြရုံသာ ဖြစ်နေပါတယ်'));
  } else if (m.narrationShare < 0.3) {
    f.add(FairUseFinding(Risk.medium,
        'ကိုယ်ပိုင် narration က ဗီဒီယို၏ ${(m.narrationShare * 100).round()}% သာ ရှိတယ်။ ရှင်းပြချက် ပိုထည့်ပါ'));
  }

  if (t.voices.isNotEmpty && m.longestBareMs > 60000) {
    f.add(FairUseFinding(Risk.medium,
        'Narration မပါဘဲ ဆက်တိုက် ${(m.longestBareMs / 1000).round()} စက္ကန့် ပြထားတဲ့ နေရာ ရှိတယ်'));
  }

  if (m.originalVolume > 0.5 && m.narrationShare < 0.6) {
    f.add(const FairUseFinding(Risk.medium, 'မူရင်းအသံကို ကျယ်ကျယ် ထားတယ်။ ကိုယ်ပိုင်အသံ အဓိကဖြစ်အောင် လျှော့ပါ'));
  }

  switch (rec.permission) {
    case Permission.none:
      f.add(const FairUseFinding(Risk.medium, 'မူရင်းပိုင်ရှင်ဆီက ခွင့်ပြုချက် မရှိသေးပါ (မှတ်တမ်း မရှိ)'));
    case Permission.asked:
      f.add(const FairUseFinding(Risk.medium, 'ခွင့်တောင်းထားပေမယ့် အဖြေ မရသေးပါ။ အဖြေမရမချင်း ခွင့်ပြုထားတယ်လို့ မယူဆပါနဲ့'));
    case Permission.granted:
    case Permission.licensed:
      if (rec.permissionNote.trim().isEmpty) {
        f.add(const FairUseFinding(Risk.medium, 'ခွင့်ပြုချက် ရှိတယ်လို့ ရွေးထားပေမယ့် အထောက်အထား (link/ရက်စွဲ) မရေးရသေးပါ'));
      }
  }

  if (rec.sourceNote.trim().isEmpty) {
    f.add(const FairUseFinding(Risk.medium, 'မူရင်း ဘယ်ကရတယ်ဆိုတာ မမှတ်ရသေးပါ'));
  }

  for (final c in fairUseChecklist) {
    if (c.key == 'music_ok' && t.music == null) continue;
    if (!rec.checked(c.key)) {
      f.add(FairUseFinding(Risk.medium, 'မအတည်ပြုရသေးပါ: ${c.text}'));
    }
  }
  return FairUseReport(m, f);
}

/// Text for the video description. Only states facts the maker confirmed.
String uploadNote(FairUseRecord rec, {required String dramaTitle}) {
  final b = StringBuffer();
  b.writeln('ဤဗီဒီယိုသည် "$dramaTitle" ကို ကိုယ်ပိုင် ရှင်းပြချက်/အကျဉ်းချုပ်နဲ့ တင်ပြထားခြင်း ဖြစ်ပါသည်။');
  if (rec.rightsHolder.trim().isNotEmpty) {
    b.writeln('မူရင်း အကြောင်းအရာ ပိုင်ရှင်: ${rec.rightsHolder.trim()}');
  }
  if (rec.sourceNote.trim().isNotEmpty) {
    b.writeln('မူရင်း ရင်းမြစ်: ${rec.sourceNote.trim()}');
  }
  if (rec.permission == Permission.granted || rec.permission == Permission.licensed) {
    if (rec.permissionNote.trim().isNotEmpty) b.writeln('ခွင့်ပြုချက်: ${rec.permissionNote.trim()}');
  }
  b.writeln('မူရင်း ဗီဒီယိုနဲ့ ဇာတ်ကောင်များ၏ မူပိုင်ခွင့်သည် ၎င်းတို့၏ ပိုင်ရှင်များထံတွင် ရှိပါသည်။');
  return b.toString().trim();
}
