/// A queue of episodes for Auto Video Recap. This file is only the bookkeeping:
/// which episode is on which step, what went wrong where, and the log. It has
/// no network, no database and no Flutter, so it is tested on its own. What
/// each step really does is in lib/platform/recap_episode_runner.dart.

/// The steps one episode goes through, in order.
enum QStep { subtitles, upload, ask, save, audio }

const qStepLabels = <QStep, String>{
  QStep.subtitles: 'စာတန်း',
  QStep.upload: 'Upload',
  QStep.ask: 'Gemini + အသံ',
  QStep.save: 'သိမ်း',
  QStep.audio: 'အသံ သိမ်း',
};

enum QStatus { waiting, running, done, failed, canceled }

/// Thrown by a step that noticed the queue was stopped.
class QueueCanceled implements Exception {
  const QueueCanceled();
}

/// An error text for the screen: no "Exception:" prefixes.
String cleanError(Object e) {
  var t = e.toString().trim();
  t = t.replaceFirst(RegExp(r'^[A-Za-z]*Exception:\s*'), '');
  return t.isEmpty ? 'ဘာကြောင့်မှန်း မသိ' : t;
}

class QueueItem {
  QueueItem({required this.projectId, required this.title});

  final int projectId;
  final String title;

  QStatus status = QStatus.waiting;

  /// The step that is running now, or the last one that ran.
  QStep? step;
  final Set<QStep> doneSteps = {};
  final Map<QStep, String> skipped = {};

  /// Short text of what the current step is doing, and 0..100 when known.
  String note = '';
  int progress = 0;

  /// Why the item failed and at which step.
  String error = '';
  QStep? failedAt;

  final List<String> log = [];

  void _reset() {
    status = QStatus.waiting;
    step = null;
    doneSteps.clear();
    skipped.clear();
    note = '';
    progress = 0;
    error = '';
    failedAt = null;
    // The log is kept: the history of earlier tries helps to find the cause.
  }
}

/// What a step runner gets to report progress through.
class QueueCtx {
  QueueCtx._(this._item, this._changed, this._isCanceled, this._clock);

  final QueueItem _item;
  final void Function() _changed;
  final bool Function() _isCanceled;
  final DateTime Function() _clock;

  bool get canceled => _isCanceled();

  /// Throws [QueueCanceled] when the queue was stopped.
  void check() {
    if (canceled) throw const QueueCanceled();
  }

  /// Enters step [s]; the step that was running before it counts as done.
  void step(QStep s, [String note = '']) {
    final prev = _item.step;
    if (prev != null && prev != s && !_item.skipped.containsKey(prev)) _item.doneSteps.add(prev);
    _item.step = s;
    _item.note = note;
    _item.progress = 0;
    log(note.isEmpty ? '▶ ${qStepLabels[s]}' : '▶ ${qStepLabels[s]}: $note');
    _changed();
  }

  void progress(int pct, String note) {
    _item.progress = pct.clamp(0, 100);
    _item.note = note;
    _changed();
  }

  /// A step that is not needed (for example subtitles already exist).
  void skip(QStep s, String why) {
    _item.skipped[s] = why;
    log('– ${qStepLabels[s]} ကျော်: $why');
    _changed();
  }

  void log(String m) {
    final t = _clock();
    String two(int v) => v.toString().padLeft(2, '0');
    _item.log.add('${two(t.hour)}:${two(t.minute)}:${two(t.second)} $m');
  }
}

typedef QueueExec = Future<void> Function(QueueItem item, QueueCtx ctx);

class RecapQueue {
  RecapQueue(this.items, {this.onChange, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final List<QueueItem> items;
  final void Function()? onChange;
  final DateTime Function() _clock;

  /// Called by [cancel], so the real network work can be cut off at once.
  void Function()? onCancel;

  bool _running = false;
  bool _canceled = false;

  bool get running => _running;
  bool get canceled => _canceled;

  int count(QStatus s) => items.where((i) => i.status == s).length;
  bool get hasUnfinished => items.any((i) => i.status == QStatus.waiting || i.status == QStatus.failed || i.status == QStatus.canceled);

  void _notify() => onChange?.call();

  /// Runs the waiting items one after the other. A failed episode is recorded
  /// and the next one goes on. Stops after [cancel].
  Future<void> run(QueueExec exec) async {
    if (_running) return;
    _running = true;
    _canceled = false;
    _notify();
    try {
      for (final it in items) {
        if (_canceled) break;
        if (it.status != QStatus.waiting) continue;
        it.status = QStatus.running;
        it.error = '';
        final ctx = QueueCtx._(it, _notify, () => _canceled, _clock);
        ctx.log('● ${it.title} စတင်');
        _notify();
        try {
          await exec(it, ctx);
          final last = it.step;
          if (last != null) it.doneSteps.add(last);
          it.status = QStatus.done;
          it.progress = 100;
          ctx.log('✓ ပြီး');
        } on QueueCanceled {
          it.status = QStatus.canceled;
          ctx.log('■ ရပ်လိုက်တယ်');
        } catch (e) {
          if (_canceled) {
            it.status = QStatus.canceled;
            ctx.log('■ ရပ်လိုက်တယ်');
          } else {
            it.status = QStatus.failed;
            it.failedAt = it.step;
            it.error = cleanError(e);
            ctx.log('✗ ${it.step == null ? '' : '${qStepLabels[it.step]}: '}${it.error}');
          }
        }
        _notify();
      }
    } finally {
      _running = false;
      _notify();
    }
  }

  void cancel() {
    if (!_running) return;
    _canceled = true;
    onCancel?.call();
    _notify();
  }

  /// Puts failed and stopped items back to waiting. Returns how many.
  int retryUnfinished() {
    var n = 0;
    for (final it in items) {
      if (it.status == QStatus.failed || it.status == QStatus.canceled) {
        it._reset();
        n++;
      }
    }
    if (n > 0) _notify();
    return n;
  }

  /// The whole log, to copy and send when something goes wrong.
  String logText() {
    final b = StringBuffer();
    for (final it in items) {
      b.writeln('== ${it.title} [${it.status.name}] ==');
      if (it.status == QStatus.failed) b.writeln('ERROR @${it.failedAt?.name ?? '-'}: ${it.error}');
      for (final l in it.log) {
        b.writeln(l);
      }
      b.writeln();
    }
    return b.toString().trimRight();
  }
}
