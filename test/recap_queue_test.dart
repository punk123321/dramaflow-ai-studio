import 'package:flutter_test/flutter_test.dart';

import 'package:aistudio/core/recap_queue.dart';

RecapQueue _q(int n, {void Function()? onChange}) => RecapQueue(
      [for (var i = 1; i <= n; i++) QueueItem(projectId: i, title: 'Ep $i')],
      onChange: onChange,
      clock: () => DateTime(2026, 11, 22, 9, 5, 7),
    );

void main() {
  test('items run one after the other, steps are counted as done', () async {
    final q = _q(2);
    final order = <int>[];
    await q.run((it, ctx) async {
      order.add(it.projectId);
      ctx.step(QStep.subtitles, 'AssemblyAI');
      ctx.step(QStep.upload);
      ctx.step(QStep.ask, 'Gemini');
      ctx.progress(50, 'အပိုင်း 3');
      expect(it.progress, 50);
    });
    expect(order, [1, 2]);
    expect(q.count(QStatus.done), 2);
    final a = q.items.first;
    expect(a.doneSteps, {QStep.subtitles, QStep.upload, QStep.ask});
    expect(a.progress, 100);
    expect(q.running, isFalse);
    expect(q.hasUnfinished, isFalse);
  });

  test('a failed episode is recorded with its step and the next one goes on', () async {
    final q = _q(3);
    await q.run((it, ctx) async {
      ctx.step(QStep.subtitles);
      if (it.projectId == 2) {
        ctx.step(QStep.ask, 'Gemini');
        throw Exception('Gemini 429 quota');
      }
    });
    expect([for (final i in q.items) i.status], [QStatus.done, QStatus.failed, QStatus.done]);
    final bad = q.items[1];
    expect(bad.failedAt, QStep.ask);
    expect(bad.error, 'Gemini 429 quota'); // no "Exception:" prefix
    expect(bad.doneSteps, {QStep.subtitles});
    expect(q.hasUnfinished, isTrue);
    expect(q.logText(), contains('ERROR @ask: Gemini 429 quota'));
    expect(q.logText(), contains('09:05:07'));
  });

  test('skipped steps are shown as skipped, not as done', () async {
    final q = _q(1);
    await q.run((it, ctx) async {
      ctx.step(QStep.subtitles);
      ctx.skip(QStep.subtitles, 'စာတန်း ရှိပြီးသား');
      ctx.step(QStep.upload);
    });
    final a = q.items.single;
    expect(a.skipped.keys, [QStep.subtitles]);
    expect(a.doneSteps.contains(QStep.subtitles), isFalse);
    expect(a.doneSteps.contains(QStep.upload), isTrue);
  });

  test('cancel stops after the running episode; the rest stay waiting', () async {
    final q = _q(3);
    var cut = false;
    q.onCancel = () => cut = true;
    await q.run((it, ctx) async {
      ctx.step(QStep.upload);
      if (it.projectId == 1) {
        q.cancel();
        ctx.check(); // a step notices the stop
      }
    });
    expect(cut, isTrue);
    expect([for (final i in q.items) i.status], [QStatus.canceled, QStatus.waiting, QStatus.waiting]);
    expect(q.running, isFalse);
  });

  test('an error that comes from cutting the network off counts as stopped, not failed', () async {
    final q = _q(2);
    await q.run((it, ctx) async {
      ctx.step(QStep.ask);
      q.cancel();
      throw const FormatException('socket closed');
    });
    expect(q.items.first.status, QStatus.canceled);
    expect(q.items.first.error, '');
    expect(q.items[1].status, QStatus.waiting);
  });

  test('retryUnfinished resets failed and stopped items, keeps their log', () async {
    final q = _q(2);
    await q.run((it, ctx) async {
      ctx.step(QStep.ask);
      if (it.projectId == 1) throw Exception('x');
    });
    expect(q.retryUnfinished(), 1);
    final a = q.items.first;
    expect(a.status, QStatus.waiting);
    expect(a.error, '');
    expect(a.failedAt, isNull);
    expect(a.doneSteps, isEmpty);
    expect(a.log, isNotEmpty);
    var again = 0;
    await q.run((it, ctx) async {
      again++;
      ctx.step(QStep.save);
    });
    expect(again, 1); // only the reset one runs
    expect(q.count(QStatus.done), 2);
    expect(a.log.where((l) => l.contains('စတင်')).length, 2);
  });

  test('run is not re-entered while running, and onChange is called', () async {
    var changes = 0;
    final q = _q(1, onChange: () => changes++);
    var started = 0;
    final f1 = q.run((it, ctx) async {
      started++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    final f2 = q.run((it, ctx) async => started++);
    await Future.wait([f1, f2]);
    expect(started, 1);
    expect(changes, greaterThan(2));
  });

  test('cleanError strips exception prefixes', () {
    expect(cleanError(Exception('a b')), 'a b');
    expect(cleanError('HttpException: boom'), 'boom');
    expect(cleanError(const FormatException('bad')), 'bad');
    expect(cleanError(''), 'ဘာကြောင့်မှန်း မသိ');
  });
}
