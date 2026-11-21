import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/news_video.dart';
import '../core/srt.dart';
import '../core/theme.dart';
import '../data/ai_settings_repo.dart';
import '../data/news_video_repo.dart';
import '../platform/handoff_channel.dart';
import '../platform/news_video_client.dart';
import '../platform/render_channel.dart';
import 'widgets.dart';

/// Makes a 3 to 5 minute news video with the user's own backend (a Colab
/// notebook, tools/news_backend_colab.py). The script comes from Gemini with
/// Google Search, the voice from Edge TTS, the pictures or footage from Pixabay, Unsplash, Wikimedia Commons or Pexels, and the
/// backend joins them. Nothing is checked for truth here: read the script
/// before you publish a news video.
class NewsVideoScreen extends StatefulWidget {
  const NewsVideoScreen({super.key});

  @override
  State<NewsVideoScreen> createState() => _NewsVideoScreenState();
}

class _NewsVideoScreenState extends State<NewsVideoScreen> {
  static const _topics = [
    '2026 နောက်ဆုံးရ AI နည်းပညာနှင့် စမတ်ဖုန်း အပြောင်းအလဲများ',
    'UFC နှင့် ONE Championship နောက်ဆုံးရ ပွဲစဉ်သတင်းများ',
    'ကမ္ဘာ့စီးပွားရေးနှင့် ရွှေဈေး၊ ဒေါ်လာဈေး နောက်ဆုံးအခြေအနေ',
    'ကမ္ဘာတစ်ဝှမ်း ထူးခြားဆန်းကြယ် နောက်ဆုံးရ သတင်းတိုများ',
  ];

  final _repo = NewsVideoRepo();
  final _connectC = TextEditingController();
  final _stockC = TextEditingController();
  String _provider = 'wikimedia';
  final _topicC = TextEditingController();
  final _promptC = TextEditingController(text: newsPrompts['anchor']!.text);

  NewsVideoSettings _s = const NewsVideoSettings();
  String _geminiKey = '';
  bool _loaded = false;

  double _minutes = 4;
  String _ratio = '9:16';
  String _voice = 'my-MM-ThihaNeural';
  String _preset = 'anchor';
  bool _strict = true;
  final _sources = <String>{'Reuters', 'BBC News'};

  bool _running = false;
  NewsJob? _job;
  NewsJob? _result;
  String? _error;
  String? _msg;
  bool _saving = false;
  NewsVideoClient? _client;

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
      _provider = s.provider;
      _stockC.text = s.keys[s.provider] ?? '';
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _client?.cancel();
    _connectC.dispose();
    _stockC.dispose();
    _topicC.dispose();
    _promptC.dispose();
    super.dispose();
  }

  NewsVideoSettings _withStock(NewsVideoSettings base) {
    final keys = {...base.keys};
    final k = _stockC.text.trim();
    if (k.isEmpty) {
      keys.remove(_provider);
    } else {
      keys[_provider] = k;
    }
    return base.copyWith(provider: _provider, keys: keys);
  }

  Future<void> _saveBackend() async {
    final c = parseConnect(_connectC.text);
    if (c == null) {
      setState(() => _error = 'Backend လိပ်စာ မမှန်ပါ။ Colab က ထုတ်ပေးတဲ့ "https://….trycloudflare.com#TOKEN" တစ်ကြောင်းလုံး ကူးထည့်ပါ။');
      return;
    }
    final next = _withStock(_s.copyWith(url: c.url, token: c.token));
    await _repo.save(next);
    if (!mounted) return;
    setState(() {
      _s = next;
      _error = null;
      _msg = c.token.isEmpty ? 'သိမ်းပြီး (Token မပါဘူး၊ Colab ရဲ့ # နောက်က စာကိုပါ ထည့်ပါ)' : 'သိမ်းပြီး';
    });
    final ok = await NewsVideoClient(next).ping();
    if (mounted) setState(() => _msg = ok ? 'Backend နဲ့ ချိတ်မိပြီ ✓' : 'သိမ်းပြီး၊ ဒါပေမဲ့ Backend မဖြေဘူး (Colab run နေလား စစ်ပါ)');
  }

  Future<void> _start() async {
    final topic = _topicC.text.trim();
    if (topic.isEmpty) {
      setState(() => _error = 'သတင်းခေါင်းစဉ် အရင်ထည့်ပါ');
      return;
    }
    if (!_s.ready) {
      setState(() => _error = 'Backend လိပ်စာနဲ့ token ကို အရင်သိမ်းပါ');
      return;
    }
    if (_geminiKey.isEmpty) {
      setState(() => _error = 'Gemini API key မထည့်ရသေးဘူး။ Settings မှာ ထည့်ပါ');
      return;
    }
    // Use what is on screen now (provider and key), not only what was saved before.
    final eff = _withStock(_s);
    if (eff.provider != _s.provider || eff.stockKey != _s.stockKey) {
      await _repo.save(eff);
      _s = eff;
    }
    final client = NewsVideoClient(_s);
    _client = client;
    setState(() {
      _running = true;
      _error = null;
      _msg = null;
      _result = null;
      _job = null;
    });
    try {
      final job = await client.run(
        newsRequestJson(
          topic: topic,
          geminiKey: _geminiKey,
          stockProvider: _s.provider,
          stockKey: _s.stockKey,
          ratio: _ratio,
          minutes: _minutes,
          voice: _voice,
          sources: _sources.toList(),
          strict: _strict,
          prompt: _promptC.text.trim(),
        ),
        (j) {
          if (mounted) setState(() => _job = j);
        },
      );
      if (mounted) setState(() => _result = job);
    } on NewsVideoCanceled {
      if (mounted) setState(() => _msg = 'ရပ်လိုက်ပြီ (Backend မှာ job က ဆက်လုပ်နေနိုင်ပါတယ်)');
    } on HttpException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      _client = null;
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _saveVideo() async {
    final r = _result;
    if (r == null || r.downloadUrl.isEmpty) return;
    final client = NewsVideoClient(_s);
    _client = client;
    final tmp = File('${Directory.systemTemp.path}/news_${DateTime.now().millisecondsSinceEpoch}.mp4');
    setState(() {
      _saving = true;
      _error = null;
      _msg = 'ဗီဒီယို ဒေါင်းနေတယ် …';
    });
    try {
      await client.download(r.downloadUrl, tmp, (got, total) {
        if (mounted && total > 0) setState(() => _msg = 'ဗီဒီယို ဒေါင်းနေတယ် ${(got * 100 / total).round()}%');
      });
      final name = 'news_${DateTime.now().millisecondsSinceEpoch}';
      await RenderChannel.saveToGallery(tmp.path, name);
      if (mounted) setState(() => _msg = 'Gallery (Movies/DramaFlow) ထဲ သိမ်းပြီး');
    } on NewsVideoCanceled {
      if (mounted) setState(() => _msg = 'ရပ်လိုက်ပြီ');
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.code == 'use_export' ? 'ဒီ Android မှာ Gallery ထဲ တိုက်ရိုက်မသိမ်းနိုင်ဘူး' : 'သိမ်းလို့မရဘူး: ${e.message}');
    } on HttpException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      try {
        if (tmp.existsSync()) tmp.deleteSync();
      } catch (_) {}
      _client = null;
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveSrt() async {
    final r = _result;
    if (r == null) return;
    final srt = serializeSrt(scenesToSrt(r.scenes));
    try {
      final ok = await HandoffChannel.saveTextFile('news_${DateTime.now().millisecondsSinceEpoch}.srt', srt);
      if (ok == true && mounted) setState(() => _msg = 'SRT သိမ်းပြီး');
    } catch (e) {
      if (mounted) setState(() => _error = 'SRT သိမ်းလို့မရဘူး: $e');
    }
  }

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(top: 14, bottom: 6), child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)));

  @override
  Widget build(BuildContext context) {
    final job = _job;
    final result = _result;
    return DfScaffold(
      appBar: AppBar(title: const Text('News Video')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                DfCard(
                  title: 'Backend (Colab)',
                  margin: EdgeInsets.zero,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      _s.ready ? '✓ သိမ်းထား' : 'မထည့်ရသေးဘူး — repo ထဲက tools/news_backend_colab.py ကို Colab မှာ run ပြီး ထွက်လာတဲ့ တစ်ကြောင်းကို ကူးထည့်ပါ',
                      style: TextStyle(color: _s.ready ? DfColors.ok : DfColors.muted, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _connectC,
                      autocorrect: false,
                      enabled: !_running,
                      decoration: const InputDecoration(labelText: 'https://….trycloudflare.com#TOKEN'),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: ValueKey('prov$_provider'),
                      initialValue: _provider,
                      decoration: const InputDecoration(labelText: 'နောက်ခံ ပုံ/ဗီဒီယို ရင်းမြစ်'),
                      items: [for (final e in stockProviders.entries) DropdownMenuItem(value: e.key, child: Text(e.value.title))],
                      onChanged: _running
                          ? null
                          : (v) => setState(() {
                                _provider = v ?? _provider;
                                _stockC.text = _s.keys[_provider] ?? '';
                              }),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(stockProviders[_provider]!.note, style: const TextStyle(color: DfColors.muted, fontSize: 12)),
                    ),
                    if (stockProviders[_provider]!.needsKey) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _stockC,
                        obscureText: true,
                        autocorrect: false,
                        enabled: !_running,
                        decoration: InputDecoration(labelText: '${stockProviders[_provider]!.title} API key'),
                      ),
                    ],
                    const SizedBox(height: 8),
                    OutlinedButton.icon(onPressed: _running ? null : _saveBackend, icon: const Icon(Icons.link_rounded), label: const Text('သိမ်း + စစ်')),
                    const SizedBox(height: 6),
                    Text(
                      _geminiKey.isEmpty ? 'Gemini key: မထည့်ရသေးဘူး (Settings မှာ ထည့်ပါ)' : 'Gemini key: ✓ (Settings ထဲကဟာ သုံးမယ်၊ Backend ဆီ ပို့မယ်)',
                      style: TextStyle(color: _geminiKey.isEmpty ? DfColors.warn : DfColors.muted, fontSize: 12),
                    ),
                  ]),
                ),
                _label('၁။ သတင်းခေါင်းစဉ်'),
                TextField(controller: _topicC, enabled: !_running, minLines: 1, maxLines: 3, decoration: const InputDecoration(hintText: 'ခေါင်းစဉ် ရိုက်ထည့်ပါ …')),
                Wrap(spacing: 6, children: [
                  for (final t in _topics)
                    ActionChip(label: Text(t.length > 22 ? '${t.substring(0, 22)}…' : t, style: const TextStyle(fontSize: 11.5)), onPressed: _running ? null : () => setState(() => _topicC.text = t)),
                ]),
                _label('၂။ ကြာချိန် (၃–၅ မိနစ်)'),
                Wrap(spacing: 6, children: [
                  for (final m in const [3.0, 3.5, 4.0, 4.5, 5.0])
                    ChoiceChip(label: Text('${m.floor()}:${m == m.floorToDouble() ? '00' : '30'}'), selected: _minutes == m, onSelected: _running ? null : (_) => setState(() => _minutes = m)),
                ]),
                _label('၃။ အချိုးအစား နဲ့ အသံ'),
                Wrap(spacing: 6, children: [
                  ChoiceChip(label: const Text('9:16 Portrait'), selected: _ratio == '9:16', onSelected: _running ? null : (_) => setState(() => _ratio = '9:16')),
                  ChoiceChip(label: const Text('16:9 Landscape'), selected: _ratio == '16:9', onSelected: _running ? null : (_) => setState(() => _ratio = '16:9')),
                ]),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey('v$_voice'),
                  initialValue: _voice,
                  decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.record_voice_over_outlined, size: 20)),
                  items: [for (final e in newsVoices.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: _running ? null : (v) => setState(() => _voice = v ?? _voice),
                ),
                _label('၄။ သတင်းရင်းမြစ် (${_sources.length})'),
                for (final g in newsSourceGroups.entries) ...[
                  Text(g.key, style: const TextStyle(color: DfColors.muted, fontSize: 12)),
                  Wrap(spacing: 6, children: [
                    for (final s in g.value)
                      FilterChip(
                        label: Text(s, style: const TextStyle(fontSize: 12)),
                        selected: _sources.contains(s),
                        onSelected: _running
                            ? null
                            : (on) => setState(() {
                                  if (on) {
                                    _sources.add(s);
                                  } else if (_sources.length > 1) {
                                    _sources.remove(s);
                                  }
                                }),
                      ),
                  ]),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Strict grounding', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('Gemini ကို ရှာတွေ့တဲ့ အချက်ပဲ သုံးခိုင်းမယ်၊ မသေချာရင် ချန်ခိုင်းမယ်', style: TextStyle(fontSize: 12)),
                  value: _strict,
                  onChanged: _running ? null : (v) => setState(() => _strict = v),
                ),
                _label('၅။ Prompt'),
                Wrap(spacing: 6, children: [
                  for (final e in newsPrompts.entries)
                    ChoiceChip(
                      label: Text(e.value.title),
                      selected: _preset == e.key,
                      onSelected: _running
                          ? null
                          : (_) => setState(() {
                                _preset = e.key;
                                _promptC.text = e.value.text;
                              }),
                    ),
                ]),
                const SizedBox(height: 6),
                TextField(controller: _promptC, enabled: !_running, minLines: 5, maxLines: 12, style: const TextStyle(fontSize: 12.5)),
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('{{TOPIC}} {{SOURCES}} {{DURATION_MIN}} {{TARGET_WORDS}} {{SCENE_COUNT}} ကို Backend က ဖြည့်ပေးမယ်', style: TextStyle(color: DfColors.muted, fontSize: 11.5)),
                ),
                const SizedBox(height: 16),
                if (_running)
                  OutlinedButton.icon(onPressed: () => _client?.cancel(), icon: const Icon(Icons.stop_circle_outlined), label: const Text('ရပ်မယ်'))
                else
                  GradientButton(label: 'ဗီဒီယိုထုတ်မယ်', icon: Icons.bolt_rounded, onPressed: _start),
                if (_running) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: job == null || job.progress == 0 ? null : job.progress / 100),
                  const SizedBox(height: 4),
                  Text(job == null ? 'Backend ကို ခေါ်နေတယ် …' : '${job.stage} · ${job.progress}%', style: const TextStyle(fontSize: 13)),
                  const Text('Phone ကို မပိတ်ပါနဲ့၊ Colab ကိုလည်း ဖွင့်ထားပါ။ ၅-၁၅ မိနစ်ခန့် ကြာနိုင်ပါတယ်။', style: TextStyle(color: DfColors.muted, fontSize: 12)),
                ],
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: ErrorBanner(_error!)),
                if (_msg != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_msg!, style: const TextStyle(color: DfColors.ok, fontSize: 13))),
                if (result != null) ...[
                  const SizedBox(height: 14),
                  DfCard(
                    title: result.title.isEmpty ? 'ပြီးပြီ' : result.title,
                    margin: EdgeInsets.zero,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${result.scenes.length} scene · ${result.seconds.round() ~/ 60}:${(result.seconds.round() % 60).toString().padLeft(2, '0')}', style: const TextStyle(color: DfColors.muted, fontSize: 12.5)),
                      for (final w in result.warnings) Padding(padding: const EdgeInsets.only(top: 4), child: Text('⚠ $w', style: const TextStyle(color: DfColors.warn, fontSize: 12.5))),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 4, children: [
                        FilledButton.icon(onPressed: _saving ? null : _saveVideo, icon: const Icon(Icons.download_rounded), label: const Text('Gallery ထဲ သိမ်း')),
                        OutlinedButton.icon(onPressed: _saveSrt, icon: const Icon(Icons.subtitles_outlined), label: const Text('SRT သိမ်း')),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: result.scenes.map((s) => s.narration).join('\n\n')));
                            if (mounted) setState(() => _msg = 'ဇာတ်ညွှန်း ကူးပြီး');
                          },
                          icon: const Icon(Icons.copy_rounded),
                          label: const Text('ဇာတ်ညွှန်း ကူး'),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      const Text(
                        'AI ရေးထားတာမို့ တင်မယ့်အချိန်မတိုင်ခင် အချက်အလက်ကို ကိုယ်တိုင် စစ်ပါ။ စာတန်းကို မူရင်းဗီဒီယိုထဲ မထည့်ထားဘူး၊ SRT ကို Subtitle Studio ထဲ ထည့်ပြီး ကိုယ့် render နဲ့ ထည့်လို့ရပါတယ်။',
                        style: TextStyle(color: DfColors.muted, fontSize: 12),
                      ),
                      for (var i = 0; i < result.scenes.length; i++)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(gradient: DfGradients.glass, borderRadius: BorderRadius.circular(12), border: Border.all(color: DfColors.glassEdge)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Scene ${i + 1}${result.scenes[i].source.isEmpty ? '' : ' · ${result.scenes[i].source}'}', style: const TextStyle(color: DfColors.accent, fontWeight: FontWeight.w700, fontSize: 12)),
                            const SizedBox(height: 2),
                            Text(result.scenes[i].narration, style: const TextStyle(fontSize: 13, height: 1.45)),
                          ]),
                        ),
                    ]),
                  ),
                ],
              ],
            ),
    );
  }
}
