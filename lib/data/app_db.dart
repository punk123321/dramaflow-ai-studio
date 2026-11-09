import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Single local SQLite database. Everything stays on the phone.
///
/// Version 1: projects.
/// Version 2: video fields on projects, dramas, episodes, video_segments.
class AppDb {
  static Database? _db;

  static Future<Database> get() async {
    final existing = _db;
    if (existing != null) return existing;
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, 'dramaflow.db'),
      version: 2,
      onCreate: (db, version) async {
        await _createV1(db);
        await _upgradeToV2(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _upgradeToV2(db);
      },
    );
    _db = db;
    return db;
  }

  /// Closes and forgets the open database. Used by tests only.
  static Future<void> closeForTest() async {
    final d = _db;
    _db = null;
    if (d != null) await d.close();
  }

  static Future<void> _createV1(Database db) async {
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
  }

  static Future<void> _upgradeToV2(Database db) async {
    const columns = [
      'drama_id INTEGER',
      'video_name TEXT',
      'video_size INTEGER',
      'video_duration_ms INTEGER',
      'video_width INTEGER',
      'video_height INTEGER',
      'video_thumb TEXT',
    ];
    for (final c in columns) {
      await db.execute('ALTER TABLE projects ADD COLUMN $c');
    }
    await db.execute('''
CREATE TABLE dramas (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title_zh TEXT NOT NULL DEFAULT '',
  title_my TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '',
  season INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)''');
    await db.execute('''
CREATE TABLE episodes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  drama_id INTEGER NOT NULL,
  number INTEGER NOT NULL,
  duration_min INTEGER NOT NULL DEFAULT 0,
  source TEXT NOT NULL DEFAULT '',
  completed INTEGER NOT NULL DEFAULT 0
)''');
    await db.execute('''
CREATE TABLE video_segments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id INTEGER NOT NULL,
  idx INTEGER NOT NULL,
  start_ms INTEGER NOT NULL,
  end_ms INTEGER NOT NULL
)''');
    await db.execute('CREATE INDEX idx_segments_project ON video_segments(project_id)');
    await db.execute('CREATE INDEX idx_episodes_drama ON episodes(drama_id)');
  }
}
