import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/assembly.dart';
import '../core/news_video.dart';
import '../core/recap_auto.dart';
import '../core/recap_queue.dart';
import '../core/segments.dart' show formatTime;
import '../core/theme.dart';
import '../core/source_link.dart';
import '../data/ai_settings_repo.dart';
import '../data/assembly_settings_repo.dart';
import '../data/recap_backend_repo.dart';
import '../data/project.dart';
import '../data/usage_repo.dart';
import '../data/handoff_repo.dart';
import '../platform/recap_episode_runner.dart';
import '../platform/render_channel.dart';
import '../state/project_store.dart';
import 'recap_step_bar.dart';
import 'widgets.dart';

/// Auto Video Recap for several episodes, one after the other. Each episode
/// goes through the same steps as the Auto card on the Video Recap screen; one
/// that fails is marked with its step and its reason, and the next one goes on.
class RecapQueueScreen extends StatefulWidget {
  const RecapQueueScreen({super.key});

  @override
  State<RecapQueueScreen> createState() => _RecapQueueScreenState();
}

class _RecapQueueScreenState extends State<RecapQueueScreen> {
  final _modelC = TextEditingController(text: defaultTextModel);
  final _selected = <int>{};

  NewsVideoSettings _backend = const NewsVideoSettings();
  String _geminiKey = '';
  AssemblySettings _asr = const AssemblySettings();
  String _fallback = '';
  bool _loaded = false;
  bool _useAsr = true;
  bool _makeVoice = true;
  // Scene Recap instead of Video Recap: what is chosen now / what the queue on screen was started with.
  bool _scenesMode = false;
  bool _queueScenes = false;
  DateTime _lastNotice = DateTime.fromMillisecondsSinceEpoch(0);
  String _voice = 'my-MM-ThihaNeural';

  RecapQueue? _queue;
  RecapEpisodeRunner? _runner;
  Map<int, Project> _byId = {};
  // projects that take their video from a link (project id -> link)
  Map<int, String> _links = {};
  String? _msg;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final b = await RecapBackendRepo().load();
    final g = await AiSettingsRepo().load();
    final a = await AssemblySettingsRepo().load();
    final fb = await UsageRepo().fallbackModel();
    await _loadLinks();
    if (!mounted) return;
    setState(() {
      _backend = b;
      _geminiKey = g.apiKey.trim();
      _asr = a;
      _fallback = fb;
      _loaded = true;
    });
  }

  /// The links of the projects, so a project with a link and no video file can be queued too.
  Future<void> _loadLinks() async {
    final out = <int, String>{};
    try {
      final h = HandoffRepo();
      for (final p in context.read<ProjectStore>().items) {
        final id = p.id;
        if (id == null) continue;
        final l = (await h.getDoc(id, DocKind.sourceLink) ?? '').trim();
        if (l.isNotEmpty) out[id] = l;
      }
    } catch (_) {} // the list then shows the projects with a video file only
    _links = out;
  }

  @override
  void dispose() {
    _queue?.cancel();
    _modelC.dispose();
    super.dispose();
  }

  bool get _ready => _backend.ready && _geminiKey.isNotEmpty;
  bool get _running => _queue?.running ?? false;

  Future<bool> _confirm(int n) async {
    final asrNote = _useAsr && _asr.hasKey ? '\nစာတန်းမရှိတဲ့ episode အတွက် ဗီဒီယိုထဲက အသံကို AssemblyAI ဆီ ပို့မယ် (credit ကုန်နိုင်တယ်)။' : '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Episode $n ခု စမလား?'),
        content: Text(
          '${_scenesMode ? 'တစ်ခုပြီးမှ တစ်ခု ဆက်သွားမယ်။ Episode တစ်ခုချင်းစီမှာ ဖုန်းက scene တွေကို ရှာပြီး ပုံတစ်ချပ်တွေ လုပ်မယ်၊ ပုံတွေကို သင့် Backend ဆီပို့မယ် (Google ဆီ တိုက်ရိုက် မပို့ဘူး၊ VPN မလိုဘူး)။ ဗီဒီယိုဖိုင်ပါတဲ့ project ပဲ ရတယ်။ ' : 'တစ်ခုပြီးမှ တစ်ခု ဆက်သွားမယ်။ ဗီဒီယိုတစ်ခုချင်းစီကို သင့် Gemini account ဆီ upload လုပ်မယ် (Wi-Fi သုံးပါ၊ data အများကြီးသုံးမယ်)။ link ပါတဲ့ project ကိုတော့ Backend က ဗီဒီယိုကို ကိုယ်တိုင်ဆွဲပြီး Gemini ဆီ တင်မယ် (ဖုန်းကနေ upload မလုပ်ဘူး၊ VPN မလိုဘူး)။ '}'
          'Gemini key ကို သင့် Backend ဆီ ပို့မယ်။ မူရင်းဗီဒီယိုကို မပြင်ဘူး။$asrNote\n\n'
          'လုပ်နေတုန်း notification ပြထားမယ် — Home ခလုတ်နဲ့ တခြား app သုံးလို့ရတယ်။ ဒါပေမဲ့ app ကို swipe ပိတ်ရင်၊ ဒါမှမဟုတ် ဖုန်းရဲ့ battery saver က ရပ်ရင် Queue ရပ်သွားမယ် (ပြန်လာပြီး "ပြန်လုပ်" နှိပ်ရင် ကျန်တာ ဆက်လုပ်မယ်)။',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('မလုပ်ဘူး')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('စမယ်')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _start(List<Project> chosen) async {
    if (!_ready) {
      setState(() => _msg = 'Backend (URL#TOKEN) နဲ့ Gemini key ကို အရင်ထည့်ပါ');
      return;
    }
    if (chosen.isEmpty) {
      setState(() => _msg = 'Episode တစ်ခုခု ရွေးပါ');
      return;
    }
    if (!await _confirm(chosen.length) || !mounted) return;
    final runner = RecapEpisodeRunner(QueueSettings(
      backend: _backend,
      geminiKey: _geminiKey,
      model: _modelC.text.trim().isEmpty ? defaultTextModel : _modelC.text.trim(),
      fallbackModel: _fallback,
      voice: _makeVoice ? _voice : '',
      useAsr: _useAsr,
      asr: _asr,
      scenes: _scenesMode,
    ));
    final q = RecapQueue(
      [for (final p in chosen) QueueItem(projectId: p.id!, title: '${p.dramaTitle} · အပိုင်း ${p.episode}')],
      onChange: () {
        if (mounted) setState(() {});
        _pushNotice();
      },
    )..onCancel = runner.cancelNow;
    setState(() {
      _msg = null;
      _queue = q;
      _runner = runner;
      _queueScenes = _scenesMode;
      _byId = {for (final p in chosen) p.id!: p};
    });
    await _runAll();
  }

  Future<void> _runAll() async {
    final q = _queue;
    final r = _runner;
    if (q == null || r == null) return;
    _lastNotice = DateTime.fromMillisecondsSinceEpoch(0);
    final n = queueNotice(q);
    await RenderChannel.keepAlive(true, title: _title, text: n.text, percent: n.percent);
    try {
      await q.run((item, ctx) {
        final p = _byId[item.projectId];
        if (p == null) throw const HttpException('Project မတွေ့တော့ဘူး');
        return r.run(p, ctx);
      });
    } finally {
      await RenderChannel.keepAlive(false);
    }
    if (!mounted) return;
    final failed = q.count(QStatus.failed);
    setState(() => _msg = q.canceled
        ? 'ရပ်လိုက်ပြီ။ ပြီး ${q.count(QStatus.done)} ခု'
        : failed == 0
            ? 'အကုန်ပြီးပြီ (${q.count(QStatus.done)} ခု)။ ရလဒ်တွေက project တစ်ခုချင်းရဲ့ Video Recap စာမျက်နှာမှာ ရှိတယ်။'
            : 'ပြီး ${q.count(QStatus.done)} ခု၊ မအောင် $failed ခု — အောက်မှာ အကြောင်းရင်း ကြည့်ပါ');
  }

  String get _title => _queueScenes ? 'DramaFlow · Scene Recap Queue' : 'DramaFlow · Recap Queue';

  /// Updates the background notification at most every 4 seconds, so the
  /// percent follows the work without flooding the phone with updates.
  void _pushNotice() {
    final q = _queue;
    if (q == null || !q.running) return;
    final now = DateTime.now();
    if (now.difference(_lastNotice).inSeconds < 4) return;
    _lastNotice = now;
    final n = queueNotice(q);
    RenderChannel.keepAlive(true, title: _title, text: n.text, percent: n.percent);
  }

  Future<void> _retry() async {
    final q = _queue;
    if (q == null || q.running) return;
    if (q.retryUnfinished() == 0) return;
    setState(() => _msg = null);
    await _runAll();
  }

  Future<void> _copyLog() async {
    final q = _queue;
    if (q == null) return;
    await Clipboard.setData(ClipboardData(text: q.logText()));
    if (mounted) setState(() => _msg = 'Log အကုန် ကူးပြီး — error ပေါ်ရင် ဒီ log ကို paste လုပ်ပြီး ပို့ပါ');
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return DfScaffold(appBar: AppBar(title: const Text('Recap Queue')), body: const Center(child: CircularProgressIndicator()));
    final all = context.watch<ProjectStore>().items.where((p) => p.id != null && (p.hasVideo || (!_scenesMode && _links.containsKey(p.id)))).toList()
      ..sort((a, b) {
        final c = a.dramaTitle.compareTo(b.dramaTitle);
        return c != 0 ? c : a.episode.compareTo(b.episode);
      });
    final q = _queue;
    return DfScaffold(
      appBar: AppBar(title: const Text('Recap Queue (Episode များ တန်းစီ)')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const InfoHint(
          'Episode အများကြီးကို Video Recap Auto (ဒါမှမဟုတ် Scene Recap Auto) နဲ့ တစ်ခုပြီးတစ်ခု လုပ်ပေးတယ်။ တစ်ခု မအောင်ရင် အဲဒီ episode ကို '
          'ဘယ်အဆင့်မှာ ဘာကြောင့် မအောင်လဲ မှတ်ထားပြီး နောက်တစ်ခုကို ဆက်သွားတယ်။ လုပ်နေတုန်း notification ပြထားလို့ တခြား app သုံးလို့ရတယ် (app ကို swipe ပိတ်ရင် ရပ်မယ်)။ '
          'Script ရှိပြီးသား project ကို မအစားထိုးဘူး။',
          label: 'ဘယ်လိုအလုပ်လုပ်လဲ',
        ),
        const SizedBox(height: 10),
        _settingsCard(),
        if (q == null || !q.running) _pickCard(all),
        if (_msg != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_msg!, style: const TextStyle(color: DfColors.warn, fontSize: 13))),
        if (q != null) ..._queueView(q),
      ]),
    );
  }

  Widget _settingsCard() {
    Widget line(bool ok, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(children: [
            Icon(ok ? Icons.check_circle : Icons.cancel, size: 16, color: ok ? DfColors.ok : DfColors.danger),
            const SizedBox(width: 6),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          ]),
        );
    return DfCard(
      title: 'ပြင်ဆင်မှု',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        line(_backend.ready, _backend.ready ? 'Backend ချိတ်ထား (${Uri.tryParse(_backend.url)?.host ?? ''})' : 'Backend မချိတ်ရသေးဘူး — Video Recap စာမျက်နှာ၏ Auto card မှာ URL#TOKEN ထည့်ပါ'),
        line(_geminiKey.isNotEmpty, _geminiKey.isNotEmpty ? 'Gemini key ရှိတယ်' : 'Gemini key မရှိဘူး — Settings မှာ ထည့်ပါ'),
        const SizedBox(height: 6),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Video Recap'), icon: Icon(Icons.movie_outlined, size: 16)),
            ButtonSegment(value: true, label: Text('Scene Recap'), icon: Icon(Icons.view_module_outlined, size: 16)),
          ],
          selected: {_scenesMode},
          onSelectionChanged: _running
              ? null
              : (v) => setState(() {
                    _scenesMode = v.first;
                    _selected.clear(); // Scene Recap cannot take a project that only has a link
                  }),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Text(
            _scenesMode
                ? 'Scene Recap: ဖုန်းက scene ခွဲ + ပုံတစ်ချပ်လုပ်ပြီး Backend ဆီပို့ (ဗီဒီယိုဖိုင် လိုတယ်၊ VPN မလိုဘူး)'
                : 'Video Recap: ဗီဒီယိုတစ်ခုလုံးကို Gemini က ကြည့်တယ် (ဖိုင်ဆိုရင် VPN လိုနိုင်တယ်၊ link ဆိုရင် မလို)',
            style: const TextStyle(fontSize: 12, color: DfColors.muted),
          ),
        ),
        TextField(
          controller: _modelC,
          autocorrect: false,
          enabled: !_running,
          decoration: const InputDecoration(labelText: 'Gemini model'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('စာတန်းမရှိရင် AssemblyAI နဲ့ ထုတ်'),
          subtitle: Text(_asr.hasKey ? 'ရှိပြီးသား စာတန်းကို မထိဘူး' : 'AssemblyAI key မရှိသေးဘူး (Settings)', style: const TextStyle(fontSize: 12)),
          value: _useAsr && _asr.hasKey,
          onChanged: (_running || !_asr.hasKey) ? null : (v) => setState(() => _useAsr = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('မြန်မာအသံပါ လုပ် (Edge TTS)'),
          value: _makeVoice,
          onChanged: _running ? null : (v) => setState(() => _makeVoice = v),
        ),
        if (_makeVoice)
          DropdownButton<String>(
            value: _voice,
            items: [for (final e in recapVoices.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: _running ? null : (v) => setState(() => _voice = v ?? _voice),
          ),
      ]),
    );
  }

  Widget _pickCard(List<Project> all) {
    final chosen = [for (final p in all) if (_selected.contains(p.id)) p];
    return DfCard(
      title: 'Episode ရွေး (ဗီဒီယိုဖိုင် သို့ link ရှိတာတွေပဲ)',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (all.isEmpty) const Text('ဗီဒီယိုဖိုင် / link ပါတဲ့ project မရှိသေးဘူး။ Project ဖန်တီးပြီး Stage 1 မှာ ဗီဒီယိုရွေးပါ၊ ဒါမှမဟုတ် Video Recap စာမျက်နှာမှာ link ထည့်ပါ။', style: TextStyle(color: DfColors.muted, fontSize: 13)),
        for (final p in all)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _selected.contains(p.id),
            onChanged: (v) => setState(() => v == true ? _selected.add(p.id!) : _selected.remove(p.id)),
            title: Text('${p.dramaTitle} · အပိုင်း ${p.episode}', style: const TextStyle(fontSize: 14)),
            subtitle: Text(_links.containsKey(p.id) ? '${p.name} · link: ${linkKindLabels[linkKindOf(_links[p.id]!)]}' : '${p.name} · ${formatTime(p.videoDurationMs ?? 0)}', style: const TextStyle(fontSize: 12)),
          ),
        if (all.isNotEmpty)
          Wrap(spacing: 8, runSpacing: 6, children: [
            OutlinedButton(onPressed: () => setState(() => _selected..clear()..addAll([for (final p in all) p.id!])), child: const Text('အကုန်ရွေး')),
            OutlinedButton(onPressed: _selected.isEmpty ? null : () => setState(_selected.clear), child: const Text('ရွေးထားတာ ဖယ်')),
            FilledButton.icon(
              onPressed: () => _start(chosen),
              icon: const Icon(Icons.playlist_play_rounded, size: 20),
              label: Text('Queue စမယ် (${chosen.length})'),
            ),
          ]),
      ]),
    );
  }

  List<Widget> _queueView(RecapQueue q) {
    final total = q.items.length;
    return [
      SectionTitle('Queue · ပြီး ${q.count(QStatus.done)}/$total${q.count(QStatus.failed) > 0 ? ' · မအောင် ${q.count(QStatus.failed)}' : ''}'),
      if (q.running) const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('လုပ်နေတယ် — notification ပြထားတယ် (app ကို swipe မပိတ်ပါနဲ့)', style: TextStyle(color: DfColors.warn, fontSize: 12.5))),
      for (final it in q.items) _itemCard(it),
      Wrap(spacing: 8, runSpacing: 6, children: [
        if (q.running) OutlinedButton.icon(onPressed: q.cancel, icon: const Icon(Icons.stop_rounded, size: 18), label: const Text('ရပ်မယ်')),
        if (!q.running && q.hasUnfinished) FilledButton.icon(onPressed: _retry, icon: const Icon(Icons.refresh, size: 18), label: const Text('မအောင်တာ/ကျန်တာ ပြန်လုပ်')),
        OutlinedButton.icon(onPressed: _copyLog, icon: const Icon(Icons.copy_rounded, size: 18), label: const Text('Log အကုန် ကူး')),
        if (!q.running) OutlinedButton(onPressed: () => setState(() { _queue = null; _runner = null; _msg = null; }), child: const Text('Queue အသစ်')),
      ]),
    ];
  }

  Widget _itemCard(QueueItem it) {
    final (label, color) = switch (it.status) {
      QStatus.waiting => ('စောင့်နေ', DfColors.muted),
      QStatus.running => ('လုပ်နေ', DfColors.accent),
      QStatus.done => ('ပြီး', DfColors.ok),
      QStatus.failed => ('မအောင်', DfColors.danger),
      QStatus.canceled => ('ရပ်ထား', DfColors.warn),
    };
    return DfCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(it.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
          Text(label, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        RecapStepBar(
          steps: _queueScenes ? sceneQSteps : videoQSteps,
          current: it.step,
          done: it.doneSteps,
          skipped: it.skipped.keys.toSet(),
          failed: it.status == QStatus.failed ? it.failedAt : null,
          running: it.status == QStatus.running,
        ),
        if (it.status == QStatus.running) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: it.progress > 0 ? it.progress / 100 : null),
          const SizedBox(height: 4),
          Text('${it.note}${it.progress > 0 ? ' · ${it.progress}%' : ''}', style: const TextStyle(fontSize: 12.5)),
        ],
        if (it.status == QStatus.failed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('✗ ${it.failedAt == null ? '' : '${qStepLabels[it.failedAt]} မှာ — '}${it.error}', style: const TextStyle(color: DfColors.danger, fontSize: 13)),
          ),
        if (it.skipped.isNotEmpty && it.status != QStatus.running)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text([for (final e in it.skipped.entries) '${qStepLabels[e.key]}: ${e.value}'].join('\n'), style: const TextStyle(color: DfColors.muted, fontSize: 12)),
          ),
        if (it.log.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Log', style: TextStyle(fontSize: 12.5, color: DfColors.muted)),
            children: [Align(alignment: Alignment.centerLeft, child: SelectableText(it.log.join('\n'), style: const TextStyle(fontSize: 11.5, height: 1.35)))],
          ),
      ]),
    );
  }
}
