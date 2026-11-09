import 'app_db.dart';
import 'drama.dart';

class DramaRepo {
  Future<List<Drama>> allDramas() async {
    final db = await AppDb.get();
    final rows = await db.query('dramas', orderBy: 'updated_at DESC');
    return rows.map(Drama.fromMap).toList();
  }

  Future<List<Episode>> allEpisodes() async {
    final db = await AppDb.get();
    final rows = await db.query('episodes', orderBy: 'drama_id ASC, number ASC');
    return rows.map(Episode.fromMap).toList();
  }

  Future<Drama> insertDrama(Drama d) async {
    final db = await AppDb.get();
    final id = await db.insert('dramas', d.toMap());
    return d.copyWith(id: id);
  }

  Future<void> updateDrama(Drama d) async {
    final db = await AppDb.get();
    await db.update('dramas', d.toMap(), where: 'id = ?', whereArgs: [d.id]);
  }

  /// Deletes the drama and its episodes. Projects stay, only their link to
  /// the drama is cleared. Video files are never touched.
  Future<void> deleteDrama(int id) async {
    final db = await AppDb.get();
    await db.transaction((txn) async {
      await txn.delete('episodes', where: 'drama_id = ?', whereArgs: [id]);
      await txn.update('projects', {'drama_id': null}, where: 'drama_id = ?', whereArgs: [id]);
      await txn.delete('dramas', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<Episode> insertEpisode(Episode e) async {
    final db = await AppDb.get();
    final id = await db.insert('episodes', e.toMap());
    return e.copyWith(id: id);
  }

  Future<void> updateEpisode(Episode e) async {
    final db = await AppDb.get();
    await db.update('episodes', e.toMap(), where: 'id = ?', whereArgs: [e.id]);
  }

  Future<void> deleteEpisode(int id) async {
    final db = await AppDb.get();
    await db.delete('episodes', where: 'id = ?', whereArgs: [id]);
  }
}
