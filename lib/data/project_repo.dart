import 'app_db.dart';
import 'project.dart';

class ProjectRepo {
  Future<List<Project>> all() async {
    final db = await AppDb.get();
    final rows = await db.query('projects', orderBy: 'updated_at DESC');
    return rows.map(Project.fromMap).toList();
  }

  Future<Project> insert(Project project) async {
    final db = await AppDb.get();
    final id = await db.insert('projects', project.toMap());
    return project.copyWith(id: id);
  }

  Future<void> update(Project project) async {
    final db = await AppDb.get();
    await db.update(
      'projects',
      project.toMap(),
      where: 'id = ?',
      whereArgs: [project.id],
    );
  }

  /// Removes the project record and its video index. Original video files
  /// are never touched.
  Future<void> delete(int id) async {
    final db = await AppDb.get();
    await db.transaction((txn) async {
      await txn.delete('video_segments', where: 'project_id = ?', whereArgs: [id]);
      await txn.delete('documents', where: 'project_id = ?', whereArgs: [id]);
      await txn.delete('handoff_results', where: 'project_id = ?', whereArgs: [id]);
      await txn.delete('audio_clips', where: 'project_id = ?', whereArgs: [id]);
      await txn.delete('projects', where: 'id = ?', whereArgs: [id]);
    });
  }
}
