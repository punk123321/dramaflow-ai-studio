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
