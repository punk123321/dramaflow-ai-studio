/// A video file the app is holding in its own folder.
class RenderFile {
  const RenderFile({required this.path, required this.name, required this.sizeBytes, required this.modifiedMs, required this.partial});

  final String path;
  final String name;
  final int sizeBytes;
  final int modifiedMs;

  /// Still being written, or the render stopped before it was finished: not playable.
  final bool partial;
}

/// Finished videos of this project that are in the app's folder but not in the
/// export history (the "done" message never reached the screen, for example
/// because the phone killed the app during a very long render). Test pictures
/// are left out on purpose. Newest first.
List<RenderFile> orphanRenders(List<RenderFile> files, Set<String> knownPaths, {required String prefix}) {
  final out = [
    for (final f in files)
      if (!f.partial && !knownPaths.contains(f.path) && !f.name.contains('_sample_') && (prefix.isEmpty || f.name.startsWith(prefix))) f
  ];
  out.sort((a, b) => b.modifiedMs.compareTo(a.modifiedMs));
  return out;
}

/// Unfinished files of this project (a render that stopped before the end).
List<RenderFile> unfinishedRenders(List<RenderFile> files, {required String prefix}) =>
    [for (final f in files) if (f.partial && (prefix.isEmpty || f.name.startsWith(prefix))) f];

/// Length of the finished video that a render job will make, from the job's pieces
/// (a piece's 'sp' is its speed; a held still frame 'f' = 1 lasts end - start).
int jobDurationMs(Map<String, Object?> job) {
  final raw = job['pieces'];
  if (raw is! List) return 0;
  var total = 0.0;
  for (final p in raw) {
    if (p is! Map) continue;
    final s = p['s'];
    final e = p['e'];
    if (s is! num || e is! num || e <= s) continue;
    final sp = p['sp'];
    final speed = (sp is num && sp > 0) ? sp.toDouble() : 1.0;
    total += p['f'] == 1 ? (e - s).toDouble() : (e - s) / speed;
  }
  return total.round();
}

/// A render that was started and not yet seen finishing. It is written before the
/// render starts and removed when the app has recorded the result, so if the app
/// is killed (or the "done" message is lost) on a long render, the next start can
/// still pick the finished file up with the right project.
class PendingRender {
  const PendingRender({required this.projectId, required this.name, required this.height, required this.durationMs});

  final int projectId;
  final String name;
  final int height;
  final int durationMs;

  String encode() => '$projectId|$height|$durationMs|$name';

  static PendingRender? decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parts = raw.split('|');
    if (parts.length < 4) return null;
    final pid = int.tryParse(parts[0]);
    final h = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    final name = parts.sublist(3).join('|');
    if (pid == null || h == null || d == null || name.isEmpty) return null;
    return PendingRender(projectId: pid, name: name, height: h, durationMs: d);
  }
}

/// The finished file called [name] (not an unfinished one), or null.
RenderFile? findFinished(List<RenderFile> files, String name) {
  for (final f in files) {
    if (!f.partial && f.name == name) return f;
  }
  return null;
}

/// True when an unfinished file called [name] exists.
bool hasUnfinished(List<RenderFile> files, String name) => files.any((f) => f.partial && f.name == name);
