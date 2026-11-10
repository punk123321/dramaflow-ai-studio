import 'package:aistudio/core/segments.dart';
import 'package:aistudio/data/app_db.dart';
import 'package:aistudio/data/audio_clip.dart';
import 'package:aistudio/data/drama.dart';
import 'package:aistudio/data/drama_repo.dart';
import 'package:aistudio/data/handoff_repo.dart';
import 'package:aistudio/data/project.dart';
import 'package:aistudio/data/project_repo.dart';
import 'package:aistudio/data/segment_repo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<String> _dbPath() async => p.join(await databaseFactory.getDatabasesPath(), 'dramaflow.db');

Future<void> _wipe() async {
  await AppDb.closeForTest();
  await databaseFactory.deleteDatabase(await _dbPath());
}

Project _project(String name, {int? dramaId}) => Project(
      name: name,
      dramaTitle: 'D',
      episode: 1,
      dramaId: dramaId,
      createdAt: 1,
      updatedAt: 1,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(_wipe);
  tearDownAll(_wipe);

  test('projects: insert, read back, update, delete', () async {
    final repo = ProjectRepo();
    final saved = await repo.insert(_project('A'));
    expect(saved.id, isNotNull);
    expect((await repo.all()).single.name, 'A');
    await repo.update(saved.copyWith(name: 'B', doneMask: 3));
    final read = (await repo.all()).single;
    expect(read.name, 'B');
    expect(read.doneMask, 3);
    await repo.delete(saved.id!);
    expect(await repo.all(), isEmpty);
  });

  test('segments: replaceAll swaps the whole index and keeps order', () async {
    final repo = SegmentRepo();
    await repo.replaceAll(1, const [SegmentSpec(0, 1000), SegmentSpec(1000, 2000), SegmentSpec(2000, 2500)]);
    expect((await repo.load(1)).length, 3);
    await repo.replaceAll(1, const [SegmentSpec(0, 500)]);
    expect(await repo.load(1), [const SegmentSpec(0, 500)]);
    await repo.replaceAll(2, const [SegmentSpec(10, 20)]);
    expect(await repo.load(1), [const SegmentSpec(0, 500)]);
    expect(await repo.load(2), [const SegmentSpec(10, 20)]);
  });

  test('deleting a project also removes its video index, not other projects', () async {
    final repo = ProjectRepo();
    final seg = SegmentRepo();
    final a = await repo.insert(_project('A'));
    final b = await repo.insert(_project('B'));
    await seg.replaceAll(a.id!, const [SegmentSpec(0, 1000)]);
    await seg.replaceAll(b.id!, const [SegmentSpec(0, 2000)]);
    await repo.delete(a.id!);
    expect(await seg.load(a.id!), isEmpty);
    expect(await seg.load(b.id!), [const SegmentSpec(0, 2000)]);
  });

  test('dramas: episodes are kept per drama, deleting a drama unlinks projects', () async {
    final dramas = DramaRepo();
    final projects = ProjectRepo();
    final d1 = await dramas.insertDrama(const Drama(titleZh: '斗破', titleMy: 'ဇာတ်လမ်း', createdAt: 1, updatedAt: 1));
    final d2 = await dramas.insertDrama(const Drama(titleZh: 'Other', createdAt: 1, updatedAt: 1));
    await dramas.insertEpisode(Episode(dramaId: d1.id!, number: 1, durationMin: 45, source: 'file'));
    await dramas.insertEpisode(Episode(dramaId: d1.id!, number: 2));
    await dramas.insertEpisode(Episode(dramaId: d2.id!, number: 1));
    final proj = await projects.insert(_project('P', dramaId: d1.id));

    var eps = await dramas.allEpisodes();
    expect(eps.length, 3);
    final first = eps.firstWhere((e) => e.dramaId == d1.id && e.number == 1);
    await dramas.updateEpisode(first.copyWith(completed: true));
    eps = await dramas.allEpisodes();
    expect(eps.firstWhere((e) => e.id == first.id).completed, true);

    await dramas.deleteDrama(d1.id!);
    expect((await dramas.allDramas()).map((d) => d.id), [d2.id]);
    expect((await dramas.allEpisodes()).every((e) => e.dramaId == d2.id), true);
    final after = (await projects.all()).single;
    expect(after.id, proj.id);
    expect(after.dramaId, isNull);
  });

  test('upgrade from database version 1 keeps old projects and adds the new tables', () async {
    final old = await databaseFactory.openDatabase(
      await _dbPath(),
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, v) async {
          await db.execute(
            "CREATE TABLE projects (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, "
            "drama_title TEXT NOT NULL, episode INTEGER NOT NULL, done_mask INTEGER NOT NULL DEFAULT 0, "
            "status TEXT NOT NULL DEFAULT 'idle', source_video_uri TEXT, "
            "created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)",
          );
        },
      ),
    );
    await old.insert('projects', {
      'name': 'Old',
      'drama_title': 'T',
      'episode': 4,
      'done_mask': 1,
      'status': 'idle',
      'created_at': 5,
      'updated_at': 6,
    });
    await old.close();

    final list = await ProjectRepo().all();
    expect(list.single.name, 'Old');
    expect(list.single.doneMask, 1);
    expect(list.single.videoName, isNull);
    expect(list.single.dramaId, isNull);

    final db = await AppDb.get();
    final tables = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
        .map((r) => r['name'])
        .toList();
    expect(tables, containsAll(['projects', 'dramas', 'episodes', 'video_segments', 'documents', 'handoff_results', 'audio_clips']));
  });

  test('handoff: documents and results are saved, replaced, copied and removed with the project', () async {
    final prepo = ProjectRepo();
    final h = HandoffRepo();
    final a = await prepo.insert(_project('A'));
    final id = a.id!;

    expect(await h.getDoc(id, DocKind.sourceSrt), isNull);
    await h.setDoc(id, DocKind.sourceSrt, 'one');
    await h.setDoc(id, DocKind.sourceSrt, 'two');
    expect(await h.getDoc(id, DocKind.sourceSrt), 'two');

    await h.saveResult(id, 'zh_my:6000', 0, 'မြန်မာ');
    await h.saveResult(id, 'zh_my:6000', 1, 'b');
    await h.saveResult(id, 'zh_my:6000', 1, 'c');
    await h.saveResult(id, 'recap_short:12000', 0, 'other task');
    expect(await h.results(id, 'zh_my:6000'), {0: 'မြန်မာ', 1: 'c'});
    expect((await h.results(id, 'recap_short:12000')).length, 1);

    await h.deleteResult(id, 'zh_my:6000', 0);
    expect((await h.results(id, 'zh_my:6000')).keys, [1]);

    final b = await prepo.insert(_project('B'));
    await h.copyProject(id, b.id!);
    expect(await h.getDoc(b.id!, DocKind.sourceSrt), 'two');
    expect((await h.results(b.id!, 'zh_my:6000')).keys, [1]);

    await prepo.delete(id);
    expect(await h.getDoc(id, DocKind.sourceSrt), isNull);
    expect(await h.results(id, 'zh_my:6000'), isEmpty);
    expect(await h.getDoc(b.id!, DocKind.sourceSrt), 'two');
  });

  test('upgrade v2 -> v3 keeps data and adds handoff tables', () async {
    final path = await _dbPath();
    final old = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, v) async {
          await db.execute(
            "CREATE TABLE projects (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, "
            "drama_title TEXT NOT NULL, episode INTEGER NOT NULL, done_mask INTEGER NOT NULL DEFAULT 0, "
            "status TEXT NOT NULL DEFAULT 'idle', source_video_uri TEXT, created_at INTEGER NOT NULL, "
            "updated_at INTEGER NOT NULL, drama_id INTEGER, video_name TEXT, video_size INTEGER, "
            "video_duration_ms INTEGER, video_width INTEGER, video_height INTEGER, video_thumb TEXT)",
          );
        },
      ),
    );
    await old.insert('projects', {
      'name': 'V2',
      'drama_title': 'T',
      'episode': 1,
      'created_at': 1,
      'updated_at': 1,
    });
    await old.close();

    final h = HandoffRepo();
    final id = (await ProjectRepo().all()).single.id!;
    await h.setDoc(id, DocKind.notes, 'n');
    expect(await h.getDoc(id, DocKind.notes), 'n');
    expect((await ProjectRepo().all()).single.name, 'V2');
  });

  test('audio clips: save, list in order, delete with the project', () async {
    final prepo = ProjectRepo();
    final arepo = AudioRepo();
    final a = await prepo.insert(_project('A'));
    final b = await prepo.insert(_project('B'));
    AudioClip clip(int pid, int chunk, ClipKind k) => AudioClip(
          projectId: pid,
          chunkIdx: chunk,
          kind: k,
          label: 'c$chunk',
          source: '/x/$chunk.wav',
          durationMs: 1500,
          sizeBytes: 100,
          createdAt: 1,
        );
    await arepo.insert(clip(a.id!, 2, ClipKind.tts));
    final first = await arepo.insert(clip(a.id!, 1, ClipKind.mic));
    await arepo.insert(clip(a.id!, 3, ClipKind.imported));
    await arepo.insert(clip(b.id!, 1, ClipKind.tts));
    expect(first.id, isNotNull);

    final list = await arepo.forProject(a.id!);
    expect(list.map((c) => c.chunkIdx), [1, 2, 3]);
    expect(list.map((c) => c.kind), [ClipKind.mic, ClipKind.tts, ClipKind.imported]);
    expect(list.first.ownsFile, isTrue);
    expect(list.last.ownsFile, isFalse);

    await arepo.delete(first.id!);
    expect((await arepo.forProject(a.id!)).length, 2);

    await prepo.delete(a.id!);
    expect(await arepo.forProject(a.id!), isEmpty);
    expect((await arepo.forProject(b.id!)).length, 1);
  });

  test('handoff: resultTasks counts saved chunks per task', () async {
    final h = HandoffRepo();
    final a = await ProjectRepo().insert(_project('A'));
    await h.saveResult(a.id!, 'zh_recap:12000', 0, 'x');
    await h.saveResult(a.id!, 'zh_recap:12000', 1, 'y');
    await h.saveResult(a.id!, 'yt_script:12000', 0, 'z');
    expect(await h.resultTasks(a.id!), {'zh_recap:12000': 2, 'yt_script:12000': 1});
  });
}
