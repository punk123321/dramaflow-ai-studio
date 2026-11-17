import '../core/backup.dart';
import 'app_db.dart';

/// Reads all projects for a backup and writes restored ones as NEW projects.
/// Nothing that exists is changed or overwritten.
class BackupRepo {
  Future<List<BackupProject>> readAll() async {
    final db = await AppDb.get();
    final rows = await db.query('projects', orderBy: 'id');
    final out = <BackupProject>[];
    for (final r in rows) {
      final id = r['id'] as int;
      final docs = await db.query('documents', where: 'project_id = ?', whereArgs: [id]);
      final segs = await db.query('video_segments', where: 'project_id = ?', whereArgs: [id], orderBy: 'idx');
      final hand = await db.query('handoff_results', where: 'project_id = ?', whereArgs: [id]);
      out.add(BackupProject(
        project: {for (final c in projectColumns) c: r[c]},
        documents: {for (final d in docs) d['kind'] as String: d['content'] as String},
        segments: [for (final s in segs) {'idx': s['idx'], 'start_ms': s['start_ms'], 'end_ms': s['end_ms']}],
        handoff: [for (final h in hand) {'task': h['task'], 'chunk_idx': h['chunk_idx'], 'result': h['result']}],
      ));
    }
    return out;
  }

  /// Adds every project as a new one, in one transaction (all or nothing).
  Future<int> restore(List<BackupProject> items) async {
    final db = await AppDb.get();
    await db.transaction((txn) async {
      for (final b in items) {
        final row = {for (final c in projectColumns) c: b.project[c]};
        final id = await txn.insert('projects', row);
        for (final e in b.documents.entries) {
          await txn.insert('documents', {
            'project_id': id,
            'kind': e.key,
            'content': e.value,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          });
        }
        for (final s in b.segments) {
          await txn.insert('video_segments', {'project_id': id, ...s});
        }
        for (final h in b.handoff) {
          await txn.insert('handoff_results', {'project_id': id, ...h});
        }
      }
    });
    return items.length;
  }
}
