import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Single local SQLite database. Everything stays on the phone.
class AppDb {
  static Database? _db;

  static Future<Database> get() async {
    final existing = _db;
    if (existing != null) return existing;
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, 'dramaflow.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE projects (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  drama_title TEXT NOT NULL,
  episode INTEGER NOT NULL,
  done_mask INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'idle',
  source_video_uri TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)''');
      },
    );
    _db = db;
    return db;
  }
}
