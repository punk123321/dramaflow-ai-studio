import 'package:sqflite/sqflite.dart';

import 'app_db.dart';

/// Document kinds stored per project.
class DocKind {
  static const sourceSrt = 'source_srt';
  static const notes = 'notes';

  /// The subtitles being edited in the Subtitle Studio.
  static const studioSrt = 'studio_srt';

  /// The narration text that is turned into audio (Stage 3).
  static const script = 'script';

  /// The edit description (clips, voice, music, subtitle options) as JSON.
  static const timeline = 'timeline';

  /// Source, permission and fair-use checklist answers as JSON.
  static const fairUse = 'fair_use';

  /// Versioned Transformative Editor plan, separate from the existing timeline.
  static const transformativePlan = 'transformative_plan';

  /// Titles, description and hashtags written with Gemini (copy/paste).
  static const publishText = 'publish_text';

  /// Scenes found by Scene Recap, as JSON [[startMs, endMs], ...].
  static const scenePlan = 'scene_plan';
}

/// Source subtitles, name/term notes and the replies brought back from Gemini.
class HandoffRepo {
  Future<String?> getDoc(int projectId, String kind) async {
    final db = await AppDb.get();
    final rows = await db.query(
      'documents',
      where: 'project_id = ? AND kind = ?',
      whereArgs: [projectId, kind],
    );
    return rows.isEmpty ? null : rows.first['content'] as String;
  }

  Future<void> setDoc(int projectId, String kind, String content) async {
    final db = await AppDb.get();
    await db.insert(
      'documents',
      {
        'project_id': projectId,
        'kind': kind,
        'content': content,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<int, String>> results(int projectId, String task) async {
    final db = await AppDb.get();
    final rows = await db.query(
      'handoff_results',
      where: 'project_id = ? AND task = ?',
      whereArgs: [projectId, task],
    );
    return {for (final r in rows) r['chunk_idx'] as int: r['result'] as String};
  }

  /// Tasks that have saved results, with how many chunks each has.
  Future<Map<String, int>> resultTasks(int projectId) async {
    final db = await AppDb.get();
    final rows = await db.rawQuery(
      'SELECT task, COUNT(*) AS n FROM handoff_results WHERE project_id = ? GROUP BY task',
      [projectId],
    );
    return {for (final r in rows) r['task'] as String: r['n'] as int};
  }

  Future<void> saveResult(int projectId, String task, int chunk, String text) async {
    final db = await AppDb.get();
    await db.insert(
      'handoff_results',
      {'project_id': projectId, 'task': task, 'chunk_idx': chunk, 'result': text},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteResult(int projectId, String task, int chunk) async {
    final db = await AppDb.get();
    await db.delete(
      'handoff_results',
      where: 'project_id = ? AND task = ? AND chunk_idx = ?',
      whereArgs: [projectId, task, chunk],
    );
  }

  Future<void> clearResults(int projectId) async {
    final db = await AppDb.get();
    await db.delete('handoff_results', where: 'project_id = ?', whereArgs: [projectId]);
  }

  Future<void> copyProject(int from, int to) async {
    final db = await AppDb.get();
    await db.transaction((txn) async {
      final docs = await txn.query('documents', where: 'project_id = ?', whereArgs: [from]);
      for (final d in docs) {
        await txn.insert('documents', {...d, 'project_id': to});
      }
      final res = await txn.query('handoff_results', where: 'project_id = ?', whereArgs: [from]);
      for (final r in res) {
        await txn.insert('handoff_results', {...r, 'project_id': to});
      }
    });
  }
}
