import 'package:aistudio/core/format.dart';
import 'package:aistudio/core/stage.dart';
import 'package:aistudio/data/project.dart';
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

  test('formatWhen shows time today and a date otherwise', () {
    final now = DateTime(2026, 11, 8, 12, 0);
    final today = DateTime(2026, 11, 8, 9, 14).millisecondsSinceEpoch;
    final older = DateTime(2026, 11, 5, 9, 14).millisecondsSinceEpoch;
    expect(formatWhen(today, now: now), 'ယနေ့ 09:14');
    expect(formatWhen(older, now: now), '5/11/2026');
  });
}
