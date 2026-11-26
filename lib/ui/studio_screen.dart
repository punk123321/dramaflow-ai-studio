import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/news_video.dart';
import '../core/studio.dart';
import '../core/theme.dart';
import '../data/ai_settings_repo.dart';
import '../data/recap_backend_repo.dart';
import '../platform/audio_channel.dart';
import '../platform/background_work.dart';
import '../platform/handoff_channel.dart';
import '../platform/render_channel.dart';
import '../platform/studio_client.dart';
import 'widgets.dart';

/// Creator Studio: download videos you may use (YouTube, TikTok, Red Note, Bilibili ...), cut them into
/// parts, translate subtitles to Burmese, add CC / burned-in subtitles, zip, upload to your own YouTube
/// channel and bring the files to the phone. Everything heavy runs on the user's own backend (Colab).
/// The picture and sound of a video are never changed (no zoom, flip, colour or pitch changes).
class StudioScreen extends StatefulWidget {
  const StudioScreen({super.key});

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> {
  static const _tabs = ['Download', 'ဖြတ်', 'စာတန်း', 'YouTube'];
  static const _srcLangs = <(String, String)>[('auto', 'အလိုအလျောက်'), ('zh', 'တရုတ်'), ('en', 'အင်္ဂလိပ်'), ('ja', 'ဂျပန်'), ('ko', 'ကိုရီးယား'), ('th', 'ထိုင်း')];

  final _repo = RecapBackendRepo();
  NewsVideoSettings _s = const NewsVideoSettings();
  String _geminiKey = '';
  bool _loaded = false;
  final _connectC = TextEditingController();

  StudioLibrary _lib = const StudioLibrary();
  final _selected = <String>{};

  int _tab = 0;

  // download
  final _urlC = TextEditingController();
  String _quality = '720';
  String _speed = 'safe4';
  bool _playlist = false;
  final _itemsC = TextEditingController();
  String _subLang = 'auto';
  bool _alsoSubs = false;
  bool _autoSubs = false;

  // split
  String? _splitFile;
  bool _byRanges = false;
  final _countC = TextEditingController(text: '2');
  final _rangesC = TextEditingController();
  String _splitSrt = '';
  bool _reencode = false;

  // subtitles
  String? _subVideo;
  String? _subSrt;
  bool _gemini = false;
  String _srcLang = 'auto';
  String _subMode = 'soft';
  final _fontC = TextEditingController(text: 'Padauk');

  // youtube
  bool _rights = false;
  final _titleC = TextEditingController(text: '{name}');
  final _descC = TextEditingController();
  final _tagsC = TextEditingController();
  String _category = 'entertainment';
  String _privacy = 'private';
  bool _kids = false;
  String _thumb = '';
  bool _uploadCc = false;
  final _pasteC = TextEditingController();
  String _authUrl = '';

  // work in progress
  bool _busy = false;
  StudioJob? _job;
  String _jobId = '';
  String _jobTitle = '';
  String _transfer = '';
  StudioClient? _client;
  String? _msg;
  bool _err = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final s = await _repo.load();
    final g = await AiSettingsRepo().load();
    if (!mounted) return;
    setState(() {
      _s = s;
      _geminiKey = g.apiKey;
      _connectC.text = s.ready ? '${s.url}#${s.token}' : '';
      _loaded = true;
    });
    if (s.ready) await _refresh();
  }

  @override
  void dispose() {
    _client?.cancel();
    for (final c in [_connectC, _urlC, _itemsC, _countC, _rangesC, _fontC, _titleC, _descC, _tagsC, _pasteC]) {
      c.dispose();
    }
    super.dispose();
  }

  void _say(String m, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _msg = m;
      _err = error;
    });
  }

  Future<void> _saveBackend() async {
    final c = parseConnect(_connectC.text);
    if (c == null || c.token.isEmpty) {
      _say('Backend လိပ်စာ မမှန်ပါ။ Colab က ထုတ်ပေးတဲ့ "https://….trycloudflare.com#TOKEN" တစ်ကြောင်းလုံး ကူးထည့်ပါ။', error: true);
      return;
    }
    final next = _s.copyWith(url: c.url, token: c.token);
    await _repo.save(next);
    if (!mounted) return;
    setState(() => _s = next);
    await _refresh();
  }

  Future<void> _refresh() async {
    if (!_s.ready) return;
    try {
      final lib = await StudioClient(_s).library();
      if (!mounted) return;
      setState(() {
        _lib = lib;
        final names = {for (final f in lib.files) f.name};
        _selected.removeWhere((n) => !names.contains(n));
      });
    } on HttpException catch (e) {
      _say(e.message, error: true);
    } catch (e) {
      _say('Backend နဲ့ ချိတ်လို့မရဘူး: $e', error: true);
    }
  }

  // ---- running a job on the backend ----

  Future<void> _run(String title, Map<String, Object?> request) async {
    if (_busy) return;
    if (!_s.ready) {
      _say('Backend လိပ်စာ အရင်သိမ်းပါ', error: true);
      return;
    }
    final client = StudioClient(_s);
    _client = client;
    setState(() {
      _busy = true;
      _job = null;
      _jobId = '';
      _jobTitle = title;
      _msg = null;
      _err = false;
    });
    await BackgroundWork.begin('DramaFlow · $title', 'စတင်နေတယ်');
    try {
      final job = await client.run(request, (j) {
        BackgroundWork.update(j.stage, percent: j.progress);
        if (mounted) setState(() => _job = j);
      }, onId: (id) => _jobId = id);
      _finish(job);
    } on StudioCanceled {
      _say('ရပ်လိုက်ပြီ');
    } on HttpException catch (e) {
      _say(e.message, error: true);
    } catch (e) {
      _say('$e', error: true);
    } finally {
      _client = null;
      await BackgroundWork.end();
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  void _finish(StudioJob job) {
    if (!mounted) return;
    switch (job.state) {
      case StudioState.done:
        setState(() {
          _job = job;
          if (job.files.isNotEmpty) {
            _selected
              ..clear()
              ..addAll(job.files);
          }
        });
        final n = job.files.length;
        _say(job.links.isNotEmpty ? 'YouTube ပေါ် ${job.links.length} ပုဒ် တင်ပြီး' : (n > 0 ? 'ပြီးပြီ — ဖိုင် $n ခု Library ထဲ ရောက်ပြီ' : 'ပြီးပြီ'), error: job.errors.isNotEmpty);
      case StudioState.canceled:
        setState(() => _job = job);
        _say('ရပ်လိုက်ပြီ');
      case StudioState.error:
        setState(() => _job = null);
        _say(job.error.isEmpty ? 'မအောင်မြင်ဘူး' : job.error, error: true);
      default:
        break;
    }
  }

  Future<void> _control(String action) async {
    if (_jobId.isEmpty) {
      if (action == 'cancel') _client?.cancel();
      return;
    }
    try {
      await StudioClient(_s).control(_jobId, action);
    } on HttpException catch (e) {
      _say(e.message, error: true);
    } catch (e) {
      _say('$e', error: true);
    }
  }

  // ---- files ----

  List<String> get _videos => [for (final f in _lib.files) if (f.isVideo) f.name];
  List<String> get _srts => [for (final f in _lib.files) if (f.isSrt) f.name];
  List<String> get _images => [for (final f in _lib.files) if (f.isImage) f.name];

  Future<void> _uploadSrt() async {
    try {
      final p = await HandoffChannel.pickTextFile();
      if (p == null) return;
      final name = p.name.toLowerCase().endsWith('.srt') ? p.name : '${p.name}.srt';
      final bytes = Uint8List.fromList(utf8.encode(p.text));
      final stored = await StudioClient(_s).upload(name, bytes);
      await _refresh();
      if (mounted) setState(() => _selected.add(stored));
      _say('$stored တင်ပြီး');
    } on PlatformException catch (e) {
      _say('ဖိုင်ဖတ်လို့မရဘူး: ${e.message ?? e.code}', error: true);
    } on HttpException catch (e) {
      _say(e.message, error: true);
    } catch (e) {
      _say('$e', error: true);
    }
  }

  Future<void> _uploadThumb() async {
    try {
      final path = await AudioChannel.pickImage();
      if (path == null) return;
      final f = File(path);
      final ext = path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
      final stored = await StudioClient(_s).upload('thumb_${DateTime.now().millisecondsSinceEpoch}.$ext', await f.readAsBytes());
      await _refresh();
      if (mounted) setState(() => _thumb = stored);
      _say('Thumbnail တင်ပြီး ($stored)');
    } on HttpException catch (e) {
      _say(e.message, error: true);
    } catch (e) {
      _say('$e', error: true);
    }
  }

  static String _mime(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.srt')) return 'application/x-subrip';
    if (n.endsWith('.mp3')) return 'audio/mpeg';
    if (n.endsWith('.zip')) return 'application/zip';
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    if (n.endsWith('.mp4')) return 'video/mp4';
    return 'application/octet-stream';
  }

  /// Brings the chosen files to the phone: videos into the Gallery, the rest through the save dialog.
  Future<void> _fetch(List<String> names) async {
    if (_busy || names.isEmpty) return;
    final client = StudioClient(_s);
    _client = client;
    setState(() {
      _busy = true;
      _job = null;
      _jobTitle = 'ဖုန်းထဲ ယူနေတယ်';
      _msg = null;
      _err = false;
    });
    await BackgroundWork.begin('DramaFlow · ဖိုင် ဖုန်းထဲ ယူနေတယ်', 'စတင်နေတယ်');
    var ok = 0;
    final failed = <String>[];
    try {
      for (var i = 0; i < names.length; i++) {
        final name = names[i];
        final tmp = File('${Directory.systemTemp.path}/studio_${DateTime.now().millisecondsSinceEpoch}_${name.hashCode.abs()}');
        try {
          await client.downloadFile(name, tmp, (got, total) {
            final pct = total > 0 ? (got * 100 / total).round() : 0;
            BackgroundWork.update('ဖုန်းထဲ ယူနေတယ် (${i + 1}/${names.length})', percent: pct);
            if (mounted) setState(() => _transfer = '${i + 1}/${names.length} · $name · ${formatBytes(got)}${total > 0 ? ' / ${formatBytes(total)} ($pct%)' : ''}');
          });
          final lower = name.toLowerCase();
          if (lower.endsWith('.mp4')) {
            try {
              await RenderChannel.saveToGallery(tmp.path, name.substring(0, name.length - 4));
              ok++;
            } on PlatformException catch (e) {
              if (e.code != 'use_export') rethrow;
              if (await AudioChannel.export(tmp.path, name, _mime(name)) == true) ok++;
            }
          } else {
            if (await AudioChannel.export(tmp.path, name, _mime(name)) == true) ok++;
          }
        } on StudioCanceled {
          rethrow;
        } on HttpException catch (e) {
          failed.add('$name: ${e.message}');
        } on PlatformException catch (e) {
          failed.add('$name: ${e.message ?? e.code}');
        } finally {
          try {
            if (tmp.existsSync()) tmp.deleteSync();
          } catch (_) {}
        }
      }
      _say('ဖုန်းထဲ $ok/${names.length} ခု သိမ်းပြီး${ok > 0 ? ' (ဗီဒီယို = Gallery > Movies/DramaFlow)' : ''}${failed.isEmpty ? '' : '\n${failed.join('\n')}'}', error: failed.isNotEmpty);
    } on StudioCanceled {
      _say('ရပ်လိုက်ပြီ');
    } finally {
      _client = null;
      await BackgroundWork.end();
      if (mounted) {
        setState(() {
          _busy = false;
          _transfer = '';
        });
      }
    }
  }

  Future<void> _delete(List<String> names) async {
    if (names.isEmpty || _busy) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Library ထဲက ${names.length} ခု ဖျက်မလား?'),
        content: const Text('Backend (Colab) ပေါ်က ဖိုင်ကိုပဲ ဖျက်မယ်။ ဖုန်းထဲ ယူပြီးသားကို မထိပါဘူး။'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('မဖျက်ဘူး')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ဖျက်မယ်')),
        ],
      ),
    );
    if (yes != true) return;
    final failed = <String>[];
    for (final n in names) {
      try {
        await StudioClient(_s).delete(n);
      } catch (e) {
        failed.add(n);
      }
    }
    await _refresh();
    _say(failed.isEmpty ? 'ဖျက်ပြီး' : 'ဖျက်လို့မရတာ: ${failed.join(', ')}', error: failed.isNotEmpty);
  }

  // ---- YouTube login ----

  Future<void> _ytLink() async {
    try {
      final url = await StudioClient(_s).youtubeAuthLink();
      if (!mounted) return;
      setState(() => _authUrl = url);
      final opened = await HandoffChannel.openUrl(url);
      _say(opened ? 'Browser ပွင့်လာပြီ — Google နဲ့ login ဝင်၊ ခွင့်ပြု ပေးပါ။ နောက်ဆုံး ပေါ်လာတဲ့ "http://localhost/?code=…" လိပ်စာတစ်ခုလုံး (page မပွင့်လည်း ရတယ်) ကို အောက်မှာ ကူးထည့်ပါ' : 'Link ကို ကူးပြီး browser မှာ ဖွင့်ပါ');
    } on HttpException catch (e) {
      _say(e.message, error: true);
    } catch (e) {
      _say('$e', error: true);
    }
  }

  Future<void> _ytComplete() async {
    try {
      final ok = await StudioClient(_s).youtubeAuthComplete(_pasteC.text.trim());
      _pasteC.clear();
      await _refresh();
      _say(ok ? 'YouTube login ဝင်ပြီး ✓' : 'Login မအောင်မြင်ဘူး', error: !ok);
    } on HttpException catch (e) {
      _say(e.message, error: true);
    } catch (e) {
      _say('$e', error: true);
    }
  }

  Future<void> _ytUnlink() async {
    try {
      await StudioClient(_s).youtubeUnlink();
      await _refresh();
      _say('YouTube login ဖြုတ်ပြီး');
    } catch (e) {
      _say('$e', error: true);
    }
  }

  // ---- small widgets ----

  Widget _choice(String label, String value, List<(String, String)> choices, ValueChanged<String> onChanged) {
    final v = choices.any((c) => c.$1 == value) ? value : choices.first.$1;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: v,
            items: [for (final c in choices) DropdownMenuItem(value: c.$1, child: Text(c.$2, overflow: TextOverflow.ellipsis))],
            onChanged: _busy
                ? null
                : (x) {
                    if (x != null) setState(() => onChanged(x));
                  },
          ),
        ),
      ),
    );
  }

  /// A drop-down of library file names. With [optional] there is a first "none" entry whose value is ''.
  Widget _pick(String label, String? value, List<String> names, ValueChanged<String> onChanged, {bool optional = false, String none = 'မသုံးဘူး'}) {
    final v = (value != null && (names.contains(value) || (optional && value.isEmpty))) ? value : (optional ? '' : null);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: v,
            hint: const Text('Library ထဲက ရွေးပါ'),
            items: [
              if (optional) DropdownMenuItem(value: '', child: Text(none)),
              for (final n in names) DropdownMenuItem(value: n, child: Text(n, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: _busy
                ? null
                : (x) {
                    if (x != null) setState(() => onChanged(x));
                  },
          ),
        ),
      ),
    );
  }

  Widget _check(String label, bool value, ValueChanged<bool> onChanged) => CheckboxListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(label, style: const TextStyle(fontSize: 13.5)),
        value: value,
        onChanged: _busy ? null : (v) => setState(() => onChanged(v ?? false)),
      );

  Widget _field(TextEditingController c, String label, {String? hint, int lines = 1, TextInputType? type}) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextField(controller: c, enabled: !_busy, autocorrect: false, minLines: lines, maxLines: lines == 1 ? 1 : lines + 2, keyboardType: type, decoration: InputDecoration(labelText: label, hintText: hint)),
      );

  Widget _hint(String t) => Padding(padding: const EdgeInsets.only(top: 6), child: Text(t, style: const TextStyle(color: DfColors.muted, fontSize: 12.5)));

  // ---- cards ----

  Widget _connectCard() => DfCard(
        title: 'Backend ချိတ်',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Studio က သင့်ကိုယ်ပိုင် Colab backend ပေါ်မှာ အလုပ်လုပ်တယ်။ Recap notebook (Studio ပါတဲ့ version) ကို run ပြီး ထွက်လာတဲ့ URL#TOKEN ကို ထည့်ပါ။', style: TextStyle(color: DfColors.muted, fontSize: 12.5)),
          TextField(controller: _connectC, autocorrect: false, decoration: const InputDecoration(labelText: 'Backend  URL#TOKEN', hintText: 'https://….trycloudflare.com#TOKEN')),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: FilledButton(onPressed: _saveBackend, child: const Text('သိမ်း + ချိတ်'))),
        ]),
      );

  Widget _jobCard() {
    final j = _job;
    if (!_busy && j == null) return const SizedBox.shrink();
    final running = _busy;
    final isDownload = (j?.op ?? '') == 'download' || _jobTitle.contains('Download');
    final line = j == null ? '' : downloadLine(j);
    return DfCard(
      title: running ? _jobTitle : 'ရလဒ်',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (running) ...[
          if (_transfer.isNotEmpty)
            Text(_transfer, style: const TextStyle(fontSize: 12.5))
          else ...[
            LinearProgressIndicator(value: (j?.progress ?? 0) > 0 ? j!.progress / 100 : null),
            const SizedBox(height: 4),
            Text('${j?.stage ?? 'စတင်နေတယ်'}${j == null ? '' : ' (${j.progress}%)'}', style: const TextStyle(fontSize: 12.5)),
            if (line.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(line, style: const TextStyle(fontSize: 12.5, color: DfColors.muted))),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            if (isDownload && _transfer.isEmpty)
              OutlinedButton.icon(
                onPressed: () => _control(j?.paused == true ? 'resume' : 'pause'),
                icon: Icon(j?.paused == true ? Icons.play_arrow : Icons.pause, size: 18),
                label: Text(j?.paused == true ? 'ဆက်' : 'ခဏရပ်'),
              ),
            OutlinedButton.icon(
              onPressed: () => _transfer.isNotEmpty ? _client?.cancel() : _control('cancel'),
              icon: const Icon(Icons.stop, size: 18),
              label: const Text('ရပ်'),
            ),
          ]),
          _hint('Screen ပိတ်ထားလည်း ဆက်လုပ်မယ် (notification ပေါ်နေမယ်)။ App ကို swipe ပိတ်ရင်တော့ ဖုန်းဘက်က စောင့်တာ ရပ်မယ် — Backend ဘက်က job ဆက်သွားနိုင်တယ်။'),
        ] else if (j != null) ...[
          for (final f in j.files) Text('• $f', style: const TextStyle(fontSize: 13)),
          for (final l in j.links)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text(l.watch, style: const TextStyle(fontSize: 12.5, color: DfColors.accent)),
                if (l.note.isNotEmpty) Text(l.note, style: const TextStyle(fontSize: 12, color: DfColors.muted)),
                Wrap(spacing: 8, children: [
                  TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: l.watch)), child: const Text('Link ကူး')),
                  TextButton(onPressed: () => HandoffChannel.openUrl(l.watch), child: const Text('ဖွင့်')),
                  if (l.studio.isNotEmpty) TextButton(onPressed: () => HandoffChannel.openUrl(l.studio), child: const Text('YouTube Studio')),
                ]),
              ]),
            ),
          for (final n in j.notes) _hint('ℹ $n'),
          for (final e in j.errors) Padding(padding: const EdgeInsets.only(top: 4), child: Text('⚠ $e', style: const TextStyle(color: DfColors.danger, fontSize: 12.5))),
        ],
      ]),
    );
  }

  Widget _downloadTab() {
    final n = countLinks(_urlC.text);
    return DfCard(
      title: 'Link ကနေ ဆွဲ',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('ကိုယ်ပိုင် / ဆွဲခွင့်ရှိတဲ့ ဗီဒီယိုအတွက်ပဲ သုံးပါ။ Link အများကြီးကို တစ်ကြောင်းစီ (သို့) share စာသားအတိုင်း ထည့်လို့ရတယ်။', style: TextStyle(color: DfColors.muted, fontSize: 12.5)),
        _field(_urlC, 'Link (တစ်ခု သို့ အများကြီး)', hint: 'https://youtu.be/…\nhttps://v.douyin.com/…', lines: 3),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      final d = await Clipboard.getData(Clipboard.kTextPlain);
                      if (d?.text != null && mounted) setState(() => _urlC.text = _urlC.text.isEmpty ? d!.text! : '${_urlC.text}\n${d!.text!}');
                    },
              icon: const Icon(Icons.content_paste, size: 18),
              label: const Text('Paste'),
            ),
            if (_urlC.text.isNotEmpty)
              TextButton(onPressed: _busy ? null : () => setState(_urlC.clear), child: const Text('ဖျက်')),
            Text(n > 0 ? 'Link $n ခု' : '', style: const TextStyle(fontSize: 12, color: DfColors.muted)),
          ]),
        ),
        _choice('Quality', _quality, studioQualities, (v) => _quality = v),
        if (_quality != 'mp3' && _quality != 'srt') _choice('ဆွဲမြန်နှုန်း (aria2c ${_lib.aria2c ? 'ရှိ' : 'မရှိ'})', _speed, studioSpeeds, (v) => _speed = v),
        if (_quality != 'mp3' && _quality != 'srt') _hint('YouTube / TikTok / Red Note / Bilibili က လိုင်းများရင် 403 ပေးတတ်လို့ backend က အလိုအလျောက် 1 လိုင်းနဲ့ ဆွဲမယ်။'),
        _check('Playlist အကုန်ဆွဲ (ပိတ် = ဗီဒီယိုတစ်ပုဒ်ပဲ)', _playlist, (v) => _playlist = v),
        if (_playlist) _field(_itemsC, 'Playlist ထဲက ရွေးမယ့် အပိုင်း (မဖြည့်ရင် အကုန်)', hint: '4-7   သို့   4,6,8'),
        if (_quality != 'srt') _check('စာတန်းပါ ပါပါစေ (ရှိရင်)', _alsoSubs, (v) => _alsoSubs = v),
        if (_alsoSubs || _quality == 'srt') ...[
          _choice('စာတန်း ဘာသာစကား', _subLang, studioSubLangs, (v) => _subLang = v),
          if (_quality == 'srt') _check('စက်ကဖန်တီးတဲ့ (auto) စာတန်းလည်း ယူ', _autoSubs, (v) => _autoSubs = v),
        ],
        const SizedBox(height: 10),
        GradientButton(
          label: n > 1 ? 'Link $n ခု ဆွဲမယ်' : 'ဆွဲမယ်',
          icon: Icons.cloud_download_outlined,
          onPressed: (_busy || !_s.ready || _urlC.text.trim().isEmpty)
              ? null
              : () => _run(
                    'Download ဆွဲနေတယ်',
                    studioDownloadRequest(
                      urls: _urlC.text,
                      quality: _quality,
                      speed: _speed,
                      playlist: _playlist,
                      playlistItems: _itemsC.text,
                      subLangs: _subLang,
                      alsoSubtitles: _alsoSubs,
                      autoSubs: _autoSubs,
                    ),
                  ),
        ),
        _hint('YouTube က Colab ကို တားရင် Notebook Cell 5b မှာ cookies.txt တင်ပါ။'),
      ]),
    );
  }

  Widget _splitTab() => DfCard(
        title: 'ဗီဒီယို ဖြတ်',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _pick('ဗီဒီယို (Library ထဲက)', _splitFile, _videos, (v) => _splitFile = v),
          _check('အချိန်အပိုင်းအခြားကို ကိုယ်တိုင်ပေး (ပိတ် = အညီအမျှ ခွဲ)', _byRanges, (v) => _byRanges = v),
          if (_byRanges) _field(_rangesC, 'အပိုင်းများ', hint: '0:00-5:00\n5:00-12:30', lines: 3) else _field(_countC, 'အပိုင်းအရေအတွက်', type: TextInputType.number),
          _pick('စာတန်း (အပိုင်းအလိုက် ခွဲပေးမယ်)', _splitSrt, _srts, (v) => _splitSrt = v, optional: true),
          _check('Re-encode (အချိန်အတိအကျ၊ ပိုကြာတယ်)', _reencode, (v) => _reencode = v),
          _hint('မူရင်းဖိုင်ကို မပြင်ဘူး — အပိုင်းအသစ်တွေ ထွက်လာမယ်။ Re-encode မလုပ်ရင် အနီးဆုံး key frame မှာ ဖြတ်တယ်။'),
          const SizedBox(height: 10),
          GradientButton(
            label: 'ဖြတ်မယ်',
            icon: Icons.content_cut,
            onPressed: (_busy || _splitFile == null || !_videos.contains(_splitFile))
                ? null
                : () => _run(
                      'ဗီဒီယို ဖြတ်နေတယ်',
                      studioSplitRequest(
                        file: _splitFile!,
                        byRanges: _byRanges,
                        count: int.tryParse(_countC.text.trim()) ?? 2,
                        ranges: _rangesC.text,
                        srtFile: _splitSrt,
                        reencode: _reencode,
                      ),
                    ),
          ),
        ]),
      );

  Widget _subtitleTab() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DfCard(
          title: 'စာတန်း မြန်မာလို ဘာသာပြန်',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _pick('စာတန်းဖိုင် (.srt)', _subSrt, _srts, (v) => _subSrt = v),
            Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _busy ? null : _uploadSrt, icon: const Icon(Icons.upload_file, size: 18), label: const Text('ဖုန်းထဲက .srt တင်'))),
            _choice('မူရင်းဘာသာ', _srcLang, _srcLangs, (v) => _srcLang = v),
            _check('Gemini နဲ့ ပြန် (ပိတ် = အခမဲ့ Google Translate)', _gemini, (v) => _gemini = v),
            if (_gemini && _geminiKey.isEmpty) _hint('Gemini API key မထည့်ရသေးဘူး — Settings မှာ ထည့်ပါ။'),
            _hint('အချိန်တွေ မပြောင်းဘူး၊ စာသားပဲ ပြန်တယ်။ မပြန်နိုင်တဲ့ လိုင်းကို မူရင်းအတိုင်း ထားပြီး အရေအတွက် ပြောပြမယ်။ ရလဒ်က "_my.srt" အမည်နဲ့ ထွက်မယ်။'),
            const SizedBox(height: 10),
            GradientButton(
              label: 'ဘာသာပြန်မယ်',
              icon: Icons.translate,
              onPressed: (_busy || _subSrt == null || !_srts.contains(_subSrt) || (_gemini && _geminiKey.isEmpty))
                  ? null
                  : () => _run('စာတန်း ဘာသာပြန်နေတယ်', studioTranslateRequest(file: _subSrt!, gemini: _gemini, srcLang: _srcLang, geminiKey: _geminiKey, geminiModel: defaultTextModel)),
            ),
          ]),
        ),
        DfCard(
          title: 'ဗီဒီယိုထဲ စာတန်း ထည့်',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _pick('ဗီဒီယို', _subVideo, _videos, (v) => _subVideo = v),
            _choice('ပုံစံ', _subMode, const [('soft', 'Soft CC (ပိတ်/ဖွင့်လို့ရ၊ YouTube ကလည်း ဖတ်တယ်)'), ('hard', 'Hardsub (ပုံထဲ ရိုက်ထည့်)'), ('both', 'နှစ်မျိုးလုံး')], (v) => _subMode = v),
            if (_subMode != 'soft') _field(_fontC, 'ဖောင့် (မြန်မာစာအတွက် Padauk)'),
            _hint('Hardsub က ဗီဒီယိုကို ပြန်ရေးရလို့ ကြာတယ် (GPU runtime ရှိရင် မြန်တယ်)။ Soft CC က စက္ကန့်ပိုင်းပဲ။ မူရင်းဖိုင်ကို မပြင်ဘူး၊ "_cc.mp4" / "_hardsub.mp4" အသစ်ထွက်မယ်။'),
            const SizedBox(height: 10),
            GradientButton(
              label: 'စာတန်း ထည့်မယ်',
              icon: Icons.closed_caption_outlined,
              onPressed: (_busy || _subVideo == null || !_videos.contains(_subVideo) || _subSrt == null || !_srts.contains(_subSrt))
                  ? null
                  : () => _run('စာတန်း ထည့်နေတယ်', studioSubtitleRequest(file: _subVideo!, srtFile: _subSrt!, mode: _subMode, font: _fontC.text.trim().isEmpty ? 'Padauk' : _fontC.text.trim())),
            ),
          ]),
        ),
      ]);

  Widget _youtubeTab() {
    final vids = [for (final n in _selected) if (_videos.contains(n)) n];
    final ready = _lib.ytLinked && _rights && vids.isNotEmpty && !_busy;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DfCard(
        title: 'YouTube login',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_lib.ytLinked) ...[
            const Row(children: [Icon(Icons.check_circle, size: 18, color: DfColors.ok), SizedBox(width: 6), Text('Login ဝင်ပြီး')]),
            Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: _busy ? null : _ytUnlink, child: const Text('Login ဖြုတ်'))),
          ] else if (!_lib.ytSecret)
            const Text('Backend ပေါ်မှာ client_secret.json မရှိသေးဘူး — Notebook Cell 5c မှာ တင်ပါ (Google Cloud > YouTube Data API v3 > OAuth client "Desktop app")။', style: TextStyle(color: DfColors.muted, fontSize: 12.5))
          else ...[
            const Text('၁) "Login link" နှိပ်၊ browser မှာ Google နဲ့ ဝင်ပြီး ခွင့်ပြုပါ။ ၂) နောက်ဆုံး page မပွင့်ပေမဲ့ လိပ်စာဘားထဲက http://localhost/?code=… တစ်ခုလုံး ကူးပြီး အောက်မှာ ထည့်ပါ။', style: TextStyle(color: DfColors.muted, fontSize: 12.5)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              OutlinedButton(onPressed: _busy ? null : _ytLink, child: const Text('Login link')),
              if (_authUrl.isNotEmpty) TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: _authUrl)), child: const Text('Link ကူး')),
            ]),
            _field(_pasteC, 'Browser လိပ်စာ (http://localhost/?code=…)', hint: 'http://localhost/?code=4/0A…'),
            Align(alignment: Alignment.centerLeft, child: FilledButton(onPressed: _busy || _pasteC.text.trim().isEmpty ? null : _ytComplete, child: const Text('Login အတည်ပြု'))),
          ],
        ]),
      ),
      DfCard(
        title: 'YouTube ပေါ် တင်',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(vids.isEmpty ? 'အောက်က Library ထဲမှာ တင်မယ့် ဗီဒီယိုတွေကို အမှန်ခြစ်ပါ။' : 'တင်မယ့် ဗီဒီယို ${vids.length} ပုဒ်: ${vids.join(', ')}', style: const TextStyle(fontSize: 12.5)),
          _field(_titleC, 'ခေါင်းစဉ် template', hint: '{name} Part {n}/{total}'),
          _hint('{name} = ဖိုင်နာမည်၊ {n} = အစဉ်၊ {total} = စုစုပေါင်း'),
          _field(_descC, 'ဖော်ပြချက်', lines: 3),
          _field(_tagsC, 'Tags (comma ခြား)'),
          _choice('Category', _category, studioCategories, (v) => _category = v),
          _choice('Privacy', _privacy, studioPrivacy, (v) => _privacy = v),
          if (_privacy == 'public') _hint('Public ရွေးထားပေမဲ့ Google API project ကို audit မလုပ်ရသေးရင် YouTube က private ပဲ ထားတတ်တယ် — Studio လင့်ကနေ စစ်ပါ။'),
          _check('Made for kids', _kids, (v) => _kids = v),
          _check('Myanmar CC (_my.srt) ပါ တင်', _uploadCc, (v) => _uploadCc = v),
          _pick('Thumbnail', _thumb, _images, (v) => _thumb = v, optional: true, none: 'မထည့်ဘူး'),
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _busy ? null : _uploadThumb, icon: const Icon(Icons.image_outlined, size: 18), label: const Text('ဖုန်းထဲက ပုံ တင်'))),
          const Divider(),
          _check('ဒီဗီဒီယိုတွေက ကိုယ်ပိုင် (သို့) တင်ခွင့်ရှိတာ ဖြစ်ကြောင်း အတည်ပြုတယ်', _rights, (v) => _rights = v),
          _hint('တစ်ပါးသူရဲ့ ဗီဒီယိုကို သူ့ခွင့်ပြုချက်မရဘဲ ပြန်တင်ရင် copyright နဲ့ channel ပိတ်ခံရနိုင်တယ်။ တစ်ရက်ကို ၆ ပုဒ်လောက်ပဲ quota ရှိတယ်။'),
          const SizedBox(height: 8),
          GradientButton(
            label: vids.length > 1 ? 'YouTube ပေါ် ${vids.length} ပုဒ် တင်မယ်' : 'YouTube ပေါ် တင်မယ်',
            icon: Icons.upload,
            onPressed: !ready
                ? null
                : () => _run(
                      'YouTube တင်နေတယ်',
                      studioYoutubeRequest(
                        files: vids,
                        confirmRights: _rights,
                        privacy: _privacy,
                        titleTemplate: _titleC.text.trim().isEmpty ? '{name}' : _titleC.text.trim(),
                        description: _descC.text,
                        tags: _tagsC.text,
                        category: _category,
                        kids: _kids,
                        thumbnail: _thumb,
                        uploadCc: _uploadCc,
                      ),
                    ),
          ),
          if (!_lib.ytLinked) _hint('အပေါ်မှာ YouTube login အရင်ဝင်ပါ။'),
        ]),
      ),
    ]);
  }

  IconData _icon(StudioFile f) => switch (f.kind) {
        'video' => Icons.movie_outlined,
        'audio' => Icons.audiotrack_outlined,
        'srt' => Icons.subtitles_outlined,
        'image' => Icons.image_outlined,
        'zip' => Icons.folder_zip_outlined,
        _ => Icons.insert_drive_file_outlined,
      };

  Widget _libraryCard() {
    final sel = [for (final f in _lib.files) if (_selected.contains(f.name)) f.name];
    return DfCard(
      title: 'Library (Backend ပေါ်က ဖိုင်များ)${_lib.freeGb == null ? '' : ' · နေရာ ကျန် ${_lib.freeGb} GB'}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_lib.files.isEmpty) const Text('ဖိုင် မရှိသေးဘူး။ အပေါ်က Download နဲ့ စပါ။', style: TextStyle(color: DfColors.muted, fontSize: 12.5)),
        for (final f in _lib.files)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            secondary: Icon(_icon(f), size: 20, color: DfColors.muted),
            title: Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
            subtitle: Text(formatBytes(f.size), style: const TextStyle(fontSize: 11.5)),
            value: _selected.contains(f.name),
            onChanged: (v) => setState(() => v == true ? _selected.add(f.name) : _selected.remove(f.name)),
          ),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, children: [
          FilledButton.icon(onPressed: (_busy || sel.isEmpty) ? null : () => _fetch(sel), icon: const Icon(Icons.phone_android, size: 18), label: Text('ဖုန်းထဲ ယူ (${sel.length})')),
          OutlinedButton.icon(onPressed: (_busy || sel.isEmpty) ? null : () => _run('ZIP လုပ်နေတယ်', studioZipRequest(files: sel)), icon: const Icon(Icons.folder_zip_outlined, size: 18), label: const Text('ZIP')),
          OutlinedButton.icon(onPressed: (_busy || sel.isEmpty) ? null : () => _delete(sel), icon: const Icon(Icons.delete_outline, size: 18), label: const Text('ဖျက်')),
          TextButton(
            onPressed: _lib.files.isEmpty ? null : () => setState(() => _selected.length == _lib.files.length ? _selected.clear() : _selected.addAll([for (final f in _lib.files) f.name])),
            child: Text(_selected.length == _lib.files.length && _lib.files.isNotEmpty ? 'ရွေးထားတာ ဖြုတ်' : 'အကုန်ရွေး'),
          ),
        ]),
        const SizedBox(height: 6),
        const Text('Colab ကို ပိတ်ရင်/Runtime ပြန်စရင် ဒီဖိုင်တွေ ပျောက်မယ် — လိုတာကို "ဖုန်းထဲ ယူ" ထားပါ။ ဗီဒီယိုကို Gallery (Movies/DramaFlow) ထဲ သိမ်းမယ်။', style: TextStyle(color: DfColors.muted, fontSize: 12)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DfScaffold(
      appBar: AppBar(
        title: const Text('Creator Studio'),
        actions: [IconButton(tooltip: 'Library ပြန်ကြည့်', onPressed: _busy ? null : _refresh, icon: const Icon(Icons.refresh))],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
              const InfoHint('ကိုယ်ပိုင် / သုံးခွင့်ရှိတဲ့ ဗီဒီယိုအတွက်ပဲ။ ဗီဒီယိုရဲ့ ပုံ၊ အသံကို ပြောင်းလဲတာ (zoom, flip, အရောင်၊ pitch) မပါပါဘူး — ဖြတ်၊ စာတန်း၊ ZIP၊ တင် ပဲ လုပ်ပေးတယ်။ ဖိုင်တွေက Colab ပေါ်မှာ ရှိပြီး ဖုန်းထဲ "ယူ" မှ ရောက်မယ်။'),
              if (!_s.ready) _connectCard(),
              if (_msg != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: _err ? ErrorBanner(_msg!) : Text(_msg!, style: const TextStyle(color: DfColors.ok, fontSize: 13.5))),
              _jobCard(),
              Wrap(spacing: 8, children: [
                for (var i = 0; i < _tabs.length; i++) ChoiceChip(label: Text(_tabs[i]), selected: _tab == i, onSelected: (_) => setState(() => _tab = i)),
              ]),
              const SizedBox(height: 10),
              switch (_tab) {
                0 => _downloadTab(),
                1 => _splitTab(),
                2 => _subtitleTab(),
                _ => _youtubeTab(),
              },
              if (_s.ready) _libraryCard(),
            ]),
    );
  }
}
