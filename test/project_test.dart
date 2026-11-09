import 'package:aistudio/core/format.dart';
import 'package:aistudio/core/stage.dart';
import 'package:aistudio/data/drama.dart';
import 'package:aistudio/data/project.dart';
import 'package:aistudio/data/video_info.dart';
import 'package:flutter_test/flutter_test.dart';

Project fresh() => const Project(
      name: 'Test',
      dramaTitle: 'ဇာတ်လမ်း',
      episode: 1,
      createdAt: 1000,
      updatedAt: 1000,
    );

void main() {
  test('new project starts at Video index with nothing done', () {
    final p = fresh();
    expect(p.doneCount, 0);
    expect(p.currentStage, Stage.videoIndex);
    expect(p.finished, false);
  });

  test('marking stages done moves the current stage forward', () {
    var p = fresh();
    p = p.withStage(Stage.videoIndex, true, 2000);
    p = p.withStage(Stage.copy, true, 3000);
    expect(p.isDone(Stage.videoIndex), true);
    expect(p.isDone(Stage.tts), false);
    expect(p.currentStage, Stage.tts);
    expect(p.doneCount, 2);
    expect(p.updatedAt, 3000);
  });

  test('un-marking a stage clears only that bit', () {
    var p = fresh();
    for (final s in Stage.values) {
      p = p.withStage(s, true, 1);
    }
    expect(p.finished, true);
    p = p.withStage(Stage.edit, false, 2);
    expect(p.isDone(Stage.edit), false);
    expect(p.doneCount, 5);
    expect(p.currentStage, Stage.edit);
  });

  test('map round trip keeps every field', () {
    final p = fresh().withStage(Stage.tts, true, 5);
    final back = Project.fromMap({...p.toMap(), 'id': 7});
    expect(back.id, 7);
    expect(back.name, p.name);
    expect(back.dramaTitle, p.dramaTitle);
    expect(back.doneMask, p.doneMask);
    expect(back.updatedAt, 5);
  });

  videoTests();

  test('formatWhen shows time today and a date otherwise', () {
    final now = DateTime(2026, 11, 8, 12, 0);
    final today = DateTime(2026, 11, 8, 9, 14).millisecondsSinceEpoch;
    final older = DateTime(2026, 11, 5, 9, 14).millisecondsSinceEpoch;
    expect(formatWhen(today, now: now), 'ယနေ့ 09:14');
    expect(formatWhen(older, now: now), '5/11/2026');
  });
}

void videoTests() {
  test('withVideo stores the video and clears the Video index stage only', () {
    var p = fresh();
    p = p.withStage(Stage.videoIndex, true, 2).withStage(Stage.copy, true, 3);
    const v = VideoInfo(
      uri: 'content://x/1',
      name: 'ep12.mp4',
      sizeBytes: 1288490188,
      durationMs: 2900000,
      width: 1920,
      height: 1080,
      thumbnailPath: '/data/t.jpg',
    );
    final q = p.withVideo(v, 9);
    expect(q.hasVideo, true);
    expect(q.videoName, 'ep12.mp4');
    expect(q.isDone(Stage.videoIndex), false);
    expect(q.isDone(Stage.copy), true);
    expect(q.updatedAt, 9);
  });

  test('video fields survive a map round trip', () {
    const v = VideoInfo(uri: 'content://x/1', name: 'a.mp4', sizeBytes: 5, durationMs: 1000, width: 1, height: 2);
    final p = fresh().withVideo(v, 5).copyWith(dramaId: 3);
    final back = Project.fromMap({...p.toMap(), 'id': 1});
    expect(back.sourceVideoUri, 'content://x/1');
    expect(back.videoDurationMs, 1000);
    expect(back.videoWidth, 1);
    expect(back.dramaId, 3);
  });

  test('copyWith keeps the video fields', () {
    const v = VideoInfo(uri: 'content://x/1', name: 'a.mp4', sizeBytes: 5, durationMs: 1000, width: 1, height: 2);
    final p = fresh().withVideo(v, 5).copyWith(name: 'Renamed');
    expect(p.name, 'Renamed');
    expect(p.videoName, 'a.mp4');
    expect(p.hasVideo, true);
  });

  test('drama status comes from episodes', () {
    expect(dramaStatus(const []), DramaStatus.none);
    expect(
      dramaStatus(const [Episode(dramaId: 1, number: 1, completed: true), Episode(dramaId: 1, number: 2)]),
      DramaStatus.ongoing,
    );
    expect(dramaStatus(const [Episode(dramaId: 1, number: 1, completed: true)]), DramaStatus.done);
  });
}
