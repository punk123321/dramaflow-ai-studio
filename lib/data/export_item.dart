import 'app_db.dart';

/// One finished render. This table is also the export history.
class ExportItem {
  const ExportItem({
    this.id,
    required this.projectId,
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.durationMs,
    required this.height,
    required this.createdAt,
    this.inGallery = false,
  });

  final int? id;
  final int projectId;
  final String name;
  final String path;
  final int sizeBytes;
  final int durationMs;
  final int height;
  final int createdAt;
  final bool inGallery;

  ExportItem copyWith({bool? inGallery}) => ExportItem(
        id: id,
        projectId: projectId,
        name: name,
        path: path,
        sizeBytes: sizeBytes,
        durationMs: durationMs,
        height: height,
        createdAt: createdAt,
        inGallery: inGallery ?? this.inGallery,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'project_id': projectId,
        'name': name,
        'path': path,
        'size_bytes': sizeBytes,
        'duration_ms': durationMs,
        'height': height,
        'created_at': createdAt,
        'in_gallery': inGallery ? 1 : 0,
      };

  static ExportItem fromMap(Map<String, Object?> m) => ExportItem(
        id: m['id'] as int?,
        projectId: m['project_id'] as int,
        name: m['name'] as String,
        path: m['path'] as String,
        sizeBytes: m['size_bytes'] as int,
        durationMs: m['duration_ms'] as int,
        height: m['height'] as int,
        createdAt: m['created_at'] as int,
        inGallery: (m['in_gallery'] as int? ?? 0) == 1,
      );
}

class ExportRepo {
  Future<List<ExportItem>> forProject(int projectId) async {
    final db = await AppDb.get();
    final rows = await db.query('exports', where: 'project_id = ?', whereArgs: [projectId], orderBy: 'created_at DESC, id DESC');
    return rows.map(ExportItem.fromMap).toList();
  }

  Future<ExportItem> insert(ExportItem e) async {
    final db = await AppDb.get();
    final id = await db.insert('exports', e.toMap());
    return ExportItem.fromMap({...e.toMap(), 'id': id});
  }

  Future<void> markInGallery(int id) async {
    final db = await AppDb.get();
    await db.update('exports', {'in_gallery': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> delete(int id) async {
    final db = await AppDb.get();
    await db.delete('exports', where: 'id = ?', whereArgs: [id]);
  }
}
