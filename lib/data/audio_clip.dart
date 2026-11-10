import 'app_db.dart';

enum ClipKind { tts, mic, imported }

class AudioClip {
  const AudioClip({
    this.id,
    required this.projectId,
    required this.chunkIdx,
    required this.kind,
    required this.label,
    required this.source,
    required this.durationMs,
    required this.sizeBytes,
    required this.createdAt,
  });

  final int? id;
  final int projectId;
  final int chunkIdx;
  final ClipKind kind;
  final String label;

  /// A file path inside the app (tts, mic) or a content:// link to the
  /// user's own file (imported). Imported audio is never copied or changed.
  final String source;
  final int durationMs;
  final int sizeBytes;
  final int createdAt;

  /// Only audio the app made itself may be deleted from disk.
  bool get ownsFile => kind != ClipKind.imported;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'project_id': projectId,
        'chunk_idx': chunkIdx,
        'kind': kind.name,
        'label': label,
        'source': source,
        'duration_ms': durationMs,
        'size_bytes': sizeBytes,
        'created_at': createdAt,
      };

  static AudioClip fromMap(Map<String, Object?> m) => AudioClip(
        id: m['id'] as int?,
        projectId: m['project_id'] as int,
        chunkIdx: m['chunk_idx'] as int,
        kind: ClipKind.values.firstWhere((k) => k.name == m['kind'], orElse: () => ClipKind.imported),
        label: m['label'] as String,
        source: m['source'] as String,
        durationMs: m['duration_ms'] as int,
        sizeBytes: m['size_bytes'] as int,
        createdAt: m['created_at'] as int,
      );
}

class AudioRepo {
  Future<List<AudioClip>> forProject(int projectId) async {
    final db = await AppDb.get();
    final rows = await db.query(
      'audio_clips',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'chunk_idx ASC, id ASC',
    );
    return rows.map(AudioClip.fromMap).toList();
  }

  Future<AudioClip> insert(AudioClip c) async {
    final db = await AppDb.get();
    final id = await db.insert('audio_clips', c.toMap());
    return AudioClip.fromMap({...c.toMap(), 'id': id});
  }

  Future<void> delete(int id) async {
    final db = await AppDb.get();
    await db.delete('audio_clips', where: 'id = ?', whereArgs: [id]);
  }
}
