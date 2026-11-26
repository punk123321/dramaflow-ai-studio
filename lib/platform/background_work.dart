import 'render_channel.dart';

/// Keeps the app alive (foreground notification + wake lock) while a long
/// network job is running — a link download on the backend, a Recap job, a
/// News video, a file coming back to the phone — so it goes on when the screen
/// turns off. Without it the phone stops the app's network a few minutes after
/// the screen goes dark and the polling just freezes.
///
/// Calls can overlap (a link download inside a Recap run), so the service is
/// only switched off when the last one ends. The Recap queue and the render
/// screens that call [RenderChannel.keepAlive] themselves are not counted here.
class BackgroundWork {
  BackgroundWork._();

  static int _active = 0;
  static String _title = '';
  static String _text = '';
  static int? _percent;
  static DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);

  /// How many jobs are holding the service right now (for tests).
  static int get active => _active;

  static Future<void> begin(String title, String text) async {
    _active++;
    _title = title;
    _text = text;
    _percent = null;
    _lastSent = DateTime.now();
    await RenderChannel.keepAlive(true, title: title, text: text);
  }

  /// Changes the notification text / progress. Rate-limited, because a download
  /// reports many times a second and each update re-posts the notification.
  static Future<void> update(String text, {int? percent}) async {
    if (_active == 0) return;
    final now = DateTime.now();
    final changedPct = percent != null && percent != _percent;
    if (text == _text && !changedPct) return;
    if (now.difference(_lastSent) < const Duration(seconds: 2) && !(changedPct && (percent - (_percent ?? -10)).abs() >= 5)) return;
    _text = text;
    _percent = percent ?? _percent;
    _lastSent = now;
    await RenderChannel.keepAlive(true, title: _title, text: text, percent: _percent);
  }

  static Future<void> end() async {
    if (_active == 0) return;
    _active--;
    if (_active == 0) {
      _percent = null;
      await RenderChannel.keepAlive(false);
    }
  }

  /// Runs [body] with the service held, and always lets go afterwards.
  static Future<T> run<T>(String title, String text, Future<T> Function() body) async {
    await begin(title, text);
    try {
      return await body();
    } finally {
      await end();
    }
  }
}
