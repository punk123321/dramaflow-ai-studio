import '../core/segments.dart';
import 'app_db.dart';

class SegmentRepo {
  Future<List<SegmentSpec>> load(int projectId) async {
    final db = await AppDb.get();
    final rows = await db.query(
      'video_segments',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'idx ASC',
    );
    return rows
        .map((r) => SegmentSpec(r['start_ms'] as int, r['end_ms'] as int))
        .toList();
  }

  /// Replaces the whole index of one project in a single transaction, so an
  /// interrupted save never leaves half an index behind.
  Future<void> replaceAll(int projectId, List<SegmentSpec> specs) async {
    final db = await AppDb.get();
    await db.transaction((txn) async {
      await txn.delete('video_segments', where: 'project_id = ?', whereArgs: [projectId]);
      for (var i = 0; i < specs.length; i++) {
        await txn.insert('video_segments', {
          'project_id': projectId,
          'idx': i + 1,
          'start_ms': specs[i].startMs,
          'end_ms': specs[i].endMs,
        });
      }
    });
  }

  Future<void> deleteFor(int projectId) async {
    final db = await AppDb.get();
    await db.delete('video_segments', where: 'project_id = ?', whereArgs: [projectId]);
  }
}
