String two(int n) => n < 10 ? '0$n' : '$n';

/// "ယနေ့ 09:14" for today, otherwise "8/11".
String formatWhen(int millis, {DateTime? now}) {
  final t = DateTime.fromMillisecondsSinceEpoch(millis);
  final n = now ?? DateTime.now();
  if (t.year == n.year && t.month == n.month && t.day == n.day) {
    return 'ယနေ့ ${two(t.hour)}:${two(t.minute)}';
  }
  return '${t.day}/${t.month}/${t.year}';
}
