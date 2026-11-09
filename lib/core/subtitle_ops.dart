import 'srt.dart';

/// Editing operations for the Subtitle Studio. Pure Dart, no Flutter.
/// Every operation returns a NEW list and leaves the input untouched, so the
/// studio can keep an undo history.

List<SrtEntry> renumber(List<SrtEntry> e) =>
    [for (var i = 0; i < e.length; i++) SrtEntry(i + 1, e[i].startMs, e[i].endMs, e[i].text)];

List<SrtEntry> replaceEntry(List<SrtEntry> e, int pos, SrtEntry next) {
  final out = [...e];
  out[pos] = next;
  return out;
}

List<SrtEntry> deleteAt(List<SrtEntry> e, int pos) {
  final out = [...e]..removeAt(pos);
  return renumber(out);
}

/// Joins entry [pos] with the next one. The result starts when the first one
/// starts and ends when the second one ends.
List<SrtEntry> mergeWithNext(List<SrtEntry> e, int pos) {
  if (pos < 0 || pos >= e.length - 1) return e;
  final a = e[pos];
  final b = e[pos + 1];
  final text = [a.text.trim(), b.text.trim()].where((t) => t.isNotEmpty).join('\n');
  final out = [...e];
  out[pos] = SrtEntry(a.index, a.startMs, b.endMs > a.endMs ? b.endMs : a.endMs, text);
  out.removeAt(pos + 1);
  return renumber(out);
}

/// Splits entry [pos] at character offset [charPos] of its text. The time is
/// divided in proportion to the length of the two parts, and each part keeps
/// at least [minMs] when the entry is long enough.
List<SrtEntry> splitAt(List<SrtEntry> e, int pos, int charPos, {int minMs = 300}) {
  final x = e[pos];
  final cut = charPos.clamp(0, x.text.length);
  final left = x.text.substring(0, cut).trim();
  final right = x.text.substring(cut).trim();
  if (left.isEmpty || right.isEmpty) return e;
  final total = x.endMs - x.startMs;
  var mid = x.startMs + (total * left.length / (left.length + right.length)).round();
  if (total >= minMs * 2) {
    if (mid - x.startMs < minMs) mid = x.startMs + minMs;
    if (x.endMs - mid < minMs) mid = x.endMs - minMs;
  }
  final out = [...e];
  out[pos] = SrtEntry(x.index, x.startMs, mid, left);
  out.insert(pos + 1, SrtEntry(x.index + 1, mid, x.endMs, right));
  return renumber(out);
}

/// Moves every entry from position [from] on by [deltaMs] (may be negative).
/// Times never go below zero. If a move would push the first moved entry
/// before zero, the whole group moves only as far as possible, so spacing
/// between entries is preserved.
List<SrtEntry> shift(List<SrtEntry> e, int deltaMs, {int from = 0}) {
  if (e.isEmpty || from >= e.length) return e;
  var d = deltaMs;
  final minStart = e.skip(from).map((x) => x.startMs).reduce((a, b) => a < b ? a : b);
  if (minStart + d < 0) d = -minStart;
  return [
    for (var i = 0; i < e.length; i++)
      i < from ? e[i] : SrtEntry(e[i].index, e[i].startMs + d, e[i].endMs + d, e[i].text),
  ];
}

/// Trims an entry's end to the next entry's start when they overlap. Returns
/// the new list and how many entries were changed. An entry is left alone if
/// trimming would make it zero length.
({List<SrtEntry> entries, int fixed}) fixOverlaps(List<SrtEntry> e) {
  final out = [...e];
  var fixed = 0;
  for (var i = 0; i < out.length - 1; i++) {
    final a = out[i];
    final nextStart = out[i + 1].startMs;
    if (a.endMs > nextStart && nextStart > a.startMs) {
      out[i] = SrtEntry(a.index, a.startMs, nextStart, a.text);
      fixed++;
    }
  }
  return (entries: out, fixed: fixed);
}

/// 3723456 -> "01:02:03,456". Accepts "HH:MM:SS,mmm", "MM:SS,mmm", "SS,mmm"
/// and "." instead of ",". Returns null when it cannot be read.
int? parseSrtTime(String raw) {
  final m = RegExp(r'^\s*(?:(?:(\d{1,2}):)?(\d{1,2}):)?(\d{1,2})(?:[,.](\d{1,3}))?\s*$').firstMatch(raw);
  if (m == null) return null;
  final h = int.parse(m.group(1) ?? '0');
  final mi = int.parse(m.group(2) ?? '0');
  final s = int.parse(m.group(3)!);
  final f = int.parse((m.group(4) ?? '0').padRight(3, '0'));
  if (mi > 59 || s > 59) return null;
  return ((h * 60 + mi) * 60 + s) * 1000 + f;
}

// ---- problems ----

bool _isMyanmarMark(int c) =>
    (c >= 0x102B && c <= 0x103E) ||
    (c >= 0x1056 && c <= 0x1059) ||
    (c >= 0x105E && c <= 0x1060) ||
    (c >= 0x1062 && c <= 0x1064) ||
    (c >= 0x1067 && c <= 0x106D) ||
    (c >= 0x1071 && c <= 0x1074) ||
    (c >= 0x1082 && c <= 0x108D) ||
    c == 0x108F ||
    (c >= 0x109A && c <= 0x109D);

/// Number of characters a viewer reads: whitespace and Myanmar vowel signs,
/// medials and tone marks are not counted, so Burmese and Chinese text are
/// measured fairly.
int visibleLength(String s) {
  var n = 0;
  for (final c in s.runes) {
    if (c == 0x20 || c == 0x0A || c == 0x09 || c == 0x200B) continue;
    if (_isMyanmarMark(c)) continue;
    n++;
  }
  return n;
}

enum ProblemKind { empty, tooShort, tooFast, longLine, overlap, badRange }

class SubProblem {
  const SubProblem(this.pos, this.kind, this.message);

  /// Position in the list (0-based).
  final int pos;
  final ProblemKind kind;
  final String message;
}

List<SubProblem> findProblems(
  List<SrtEntry> e, {
  double maxCps = 17,
  int maxLine = 42,
  int minMs = 500,
}) {
  final out = <SubProblem>[];
  for (var i = 0; i < e.length; i++) {
    final x = e[i];
    final dur = x.endMs - x.startMs;
    final vis = visibleLength(x.text);
    if (dur <= 0) {
      out.add(SubProblem(i, ProblemKind.badRange, '#${x.index} ဆုံးချိန်က စချိန်ထက် နောက်မကျပါ'));
    } else {
      if (vis > 0 && dur < minMs) out.add(SubProblem(i, ProblemKind.tooShort, '#${x.index} ${dur}ms ပဲ ပြတယ် (တိုလွန်း)'));
      if (vis > 0 && vis / (dur / 1000) > maxCps) {
        out.add(SubProblem(i, ProblemKind.tooFast, '#${x.index} ဖတ်ရခက်တယ် (${(vis / (dur / 1000)).toStringAsFixed(1)} လုံး/စက္ကန့်)'));
      }
    }
    if (vis == 0) out.add(SubProblem(i, ProblemKind.empty, '#${x.index} စာသား မရှိပါ'));
    for (final line in x.text.split('\n')) {
      if (visibleLength(line) > maxLine) {
        out.add(SubProblem(i, ProblemKind.longLine, '#${x.index} စာကြောင်း ရှည်လွန်းတယ် (${visibleLength(line)} လုံး)'));
        break;
      }
    }
    if (i > 0 && x.startMs < e[i - 1].endMs) {
      out.add(SubProblem(i, ProblemKind.overlap, '#${e[i - 1].index} နဲ့ #${x.index} အချိန်ထပ်နေတယ်'));
    }
  }
  return out;
}

// ---- terminology ----

class Term {
  const Term(this.from, this.to);
  final String from;
  final String to;
}

/// Reads lines such as "林凡 = လင်ဖန်း", "a=b" or "a -> b". Lines without a
/// separator and lines starting with # are ignored.
List<Term> parseTerms(String raw) {
  final out = <Term>[];
  for (final line in raw.split(RegExp(r'\r?\n'))) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final m = RegExp(r'^(.+?)\s*(?:=|->|→|=>)\s*(.+)$').firstMatch(t);
    if (m == null) continue;
    final from = m.group(1)!.trim();
    final to = m.group(2)!.trim();
    if (from.isEmpty || to.isEmpty) continue;
    out.add(Term(from, to));
  }
  return out;
}

/// Replaces every term in every entry's text. Longer source terms are applied
/// first, so a short term never breaks a longer one. Numbers and times are not
/// touched. [replaced] is the number of replacements made.
({List<SrtEntry> entries, int replaced}) applyTerms(List<SrtEntry> e, List<Term> terms) {
  final sorted = [...terms]..sort((a, b) => b.from.length.compareTo(a.from.length));
  var count = 0;
  final out = <SrtEntry>[];
  for (final x in e) {
    var t = x.text;
    for (final term in sorted) {
      final n = term.from.allMapped(t);
      if (n > 0) {
        count += n;
        t = t.replaceAll(term.from, term.to);
      }
    }
    out.add(t == x.text ? x : x.withText(t));
  }
  return (entries: out, replaced: count);
}

extension on String {
  int allMapped(String text) {
    if (isEmpty) return 0;
    var n = 0;
    var i = 0;
    while (true) {
      final j = text.indexOf(this, i);
      if (j < 0) return n;
      n++;
      i = j + length;
    }
  }
}
