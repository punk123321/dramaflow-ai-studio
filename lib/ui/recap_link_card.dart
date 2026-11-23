import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/backend_kind.dart';
import '../core/news_video.dart';
import '../core/source_link.dart';
import '../core/theme.dart';
import '../data/ai_settings_repo.dart';
import '../data/handoff_repo.dart';
import '../data/recap_backend_repo.dart';
import '../platform/background_work.dart';
import '../platform/link_ingest.dart';
import '../platform/news_video_client.dart';
import '../platform/recap_client.dart';
import 'widgets.dart';

/// Video from a link (YouTube, TikTok, Red Note ...) instead of a video file.
/// The user's own backend downloads the video and puts it into the user's own
/// Gemini account, so the phone uploads nothing (no VPN needed for that).
/// The original is never touched; the link is only a source the user chose.
class RecapLinkCard extends StatefulWidget {
  const RecapLinkCard({super.key, required this.projectId, required this.onChanged});

  final int projectId;

  /// Called after the link was saved, cleared or checked: the link ('' = none)
  /// and what the backend answered for it (null = not checked yet).
  final void Function(String link, IngestInfo? info) onChanged;

  @override
  State<RecapLinkCard> createState() => _RecapLinkCardState();
}

class _RecapLinkCardState extends State<RecapLinkCard> {
  final _repo = RecapBackendRepo();
  final _linkC = TextEditingController();
  final _connectC = TextEditingController();
  late final LinkIngest _ingest = LinkIngest(HandoffRepo());

  NewsVideoSettings _s = const NewsVideoSettings();
  String _geminiKey = '';
  String _saved = '';
  IngestInfo? _info;
  bool _loaded = false;
  bool _running = false;
  String _stage = '';
  int _progress = 0;
  String? _msg;
  bool _err = false;
  RecapClient? _client;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final s = await _repo.load();
    final g = await AiSettingsRepo().load();
    final link = await _ingest.linkOf(widget.projectId);
    final info = link.isEmpty ? null : await _ingest.cached(widget.projectId, link);
    if (!mounted) return;
    setState(() {
      _s = s;
      _geminiKey = g.apiKey.trim();
      _saved = link;
      _info = info;
      _linkC.text = link;
      _connectC.text = s.ready ? '${s.url}#${s.token}' : '';
      _loaded = true;
    });
    widget.onChanged(link, info);
  }

  @override
  void dispose() {
    _client?.cancel();
    _linkC.dispose();
    _connectC.dispose();
    super.dispose();
  }

  void _say(String m, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _msg = m;
      _err = error;
    });
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text;
    if (t == null || t.trim().isEmpty) return;
    final l = extractLink(t);
    setState(() => _linkC.text = l ?? t.trim());
    if (l == null) _say('Paste လုပ်ထားတဲ့စာထဲ link (http…) မတွေ့ဘူး', error: true);
  }

  Future<void> _saveBackend() async {
    final c = parseConnect(_connectC.text);
    if (c == null || c.token.isEmpty) {
      _say('Backend လိပ်စာ မမှန်ပါ။ "https://….trycloudflare.com#TOKEN" ပုံစံ တစ်ကြောင်းလုံး ထည့်ပါ။', error: true);
      return;
    }
    final next = _s.copyWith(url: c.url, token: c.token);
    await _repo.save(next);
    if (!mounted) return;
    setState(() => _s = next);
    final svc = await NewsVideoClient(next).healthService();
    if (svc == null) {
      _say('သိမ်းပြီး၊ ဒါပေမဲ့ Backend မဖြေဘူး (Colab Cell ၅ run နေလား၊ URL မှန်လား စစ်ပါ)', error: true);
    } else if (backendKindOf(svc) == BackendKind.news) {
      _say(wrongBackendForRecap, error: true);
    } else {
      _say('Backend နဲ့ ချိတ်မိပြီ ✓');
    }
  }

  /// Saves the link and has the backend download it and put it into Gemini.
  Future<void> _go() async {
    final link = extractLink(_linkC.text);
    if (link == null) {
      _say('link မဟုတ်ဘူး — http:// သို့မဟုတ် https:// နဲ့စတဲ့ link (သို့) share စာသားတစ်ခုလုံး paste လုပ်ပါ', error: true);
      return;
    }
    if (!_s.ready) {
      _say('Backend လိပ်စာ + token ကို အရင်သိမ်းပါ', error: true);
      return;
    }
    if (_geminiKey.isEmpty) {
      _say('Gemini API key မထည့်ရသေးဘူး။ Settings မှာ ထည့်ပါ', error: true);
      return;
    }
    final client = RecapClient(_s);
    _client = client;
    setState(() {
      _running = true;
      _msg = null;
      _err = false;
      _stage = 'စတင်နေတယ်';
      _progress = 0;
      _linkC.text = link;
    });
    await BackgroundWork.begin('DramaFlow · link က ဗီဒီယို ဆွဲနေတယ်', 'စတင်နေတယ်');
    try {
      await _ingest.saveLink(widget.projectId, link);
      _saved = link;
      var subsNote = '';
      final info = await _ingest.ensure(
        projectId: widget.projectId,
        client: client,
        url: link,
        geminiKey: _geminiKey,
        onStage: (st, pct) {
          BackgroundWork.update(st, percent: pct);
          if (mounted) {
            setState(() {
              _stage = st;
              _progress = pct;
            });
          }
        },
        onSubs: (n, lang) => subsNote = 'စာတန်း $n ကြောင်းလည်း ပါလာပြီး သိမ်းပြီး${lang.isEmpty ? '' : ' ($lang)'}',
      );
      if (!mounted) return;
      setState(() => _info = info);
      widget.onChanged(link, info);
      _say('ရပြီ ✓ Gemini ဆီ ရောက်နေပြီ (${(info.durationMs / 60000).toStringAsFixed(1)} မိနစ်)${subsNote.isEmpty ? '' : '၊ $subsNote'}။ အောက်က Auto နဲ့ Recap စလို့ရပြီ');
    } on RecapCanceled {
      widget.onChanged(_saved, _info);
      _say('ရပ်လိုက်ပြီ (Backend မှာ ဆက်လုပ်နေနိုင်တယ်၊ link ကိုတော့ သိမ်းထားတယ်)');
    } on HttpException catch (e) {
      widget.onChanged(_saved, null);
      _say(e.message, error: true);
    } catch (e) {
      widget.onChanged(_saved, null);
      _say('$e', error: true);
    } finally {
      _client = null;
      await BackgroundWork.end();
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _clear() async {
    await _ingest.clear(widget.projectId);
    if (!mounted) return;
    setState(() {
      _saved = '';
      _info = null;
      _linkC.clear();
    });
    widget.onChanged('', null);
    _say('link ဖယ်ပြီး (ဗီဒီယိုဖိုင်ရှိရင် အဲဒါကို ပြန်သုံးမယ်)');
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final kind = _saved.isEmpty ? null : linkKindLabels[linkKindOf(_saved)];
    return DfCard(
      title: 'ဗီဒီယို link (YouTube / TikTok / Red Note)',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
          'ဗီဒီယိုဖိုင် upload မလုပ်ဘဲ link နဲ့ရတယ်။ Backend (Colab) က ဗီဒီယိုကို ဆွဲပြီး သင့် Gemini account ဆီ တင်ပေးတယ် — '
          'ဖုန်းက မတင်လို့ VPN မလိုဘူး။ မူရင်းကို မပြင်ဘူး၊ ဆွဲထားတဲ့ ယာယီ copy ကို တင်ပြီးတာနဲ့ ဖျက်တယ်။',
          style: TextStyle(color: DfColors.muted, fontSize: 12.5),
        ),
        const SizedBox(height: 8),
        if (!_s.ready) ...[
          TextField(
            controller: _connectC,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Recap Backend  URL#TOKEN', hintText: 'https://….trycloudflare.com#TOKEN'),
          ),
          const SizedBox(height: 6),
          Align(alignment: Alignment.centerLeft, child: OutlinedButton(onPressed: _saveBackend, child: const Text('Backend သိမ်း'))),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _linkC,
          enabled: !_running,
          autocorrect: false,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Link (သို့) share စာသားတစ်ခုလုံး', hintText: 'https://youtu.be/…  /  http://xhslink.com/…  /  https://vm.tiktok.com/…'),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, children: [
          OutlinedButton.icon(onPressed: _running ? null : _paste, icon: const Icon(Icons.content_paste, size: 18), label: const Text('Paste')),
          FilledButton.icon(
            onPressed: _running ? null : _go,
            icon: const Icon(Icons.cloud_download_outlined, size: 18),
            label: Text(_info != null && _info!.url == _saved ? 'ပြန်ဆွဲမယ်' : 'သိမ်း + Gemini ဆီ တင်'),
          ),
          if (_running) OutlinedButton(onPressed: () => _client?.cancel(), child: const Text('ရပ်')),
          if (_saved.isNotEmpty && !_running) TextButton(onPressed: _clear, child: const Text('link ဖယ်')),
        ]),
        if (_running) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: _progress > 0 ? _progress / 100 : null),
          const SizedBox(height: 4),
          Text('$_stage ($_progress%)', style: const TextStyle(fontSize: 12.5)),
        ],
        if (_info != null && !_running)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.check_circle, size: 16, color: DfColors.ok),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${kind ?? ''} · Gemini ဆီ ရောက်ပြီး · ${(_info!.durationMs / 60000).toStringAsFixed(1)} မိနစ်'
                  '${_info!.title.isEmpty ? '' : '\n${_info!.title}'}\n(Gemini က ဖိုင်ကို ၄၈ နာရီပဲ သိမ်းတယ်၊ ကျော်ရင် အလိုအလျောက် ပြန်ဆွဲမယ်)',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            ]),
          )
        else if (_saved.isNotEmpty && !_running)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('link သိမ်းထားပြီး (${kind ?? ''}) — Auto / Queue က လုပ်ချိန်မှာ ဆွဲမယ်၊ ဒါမှမဟုတ် အပေါ်က ခလုတ်နဲ့ အခု ဆွဲကြည့်ပါ', style: const TextStyle(color: DfColors.muted, fontSize: 12.5)),
          ),
        if (_msg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg!, style: TextStyle(color: _err ? DfColors.danger : DfColors.ok, fontSize: 13))),
        const SizedBox(height: 8),
        const Text(
          'သတိ: ကိုယ်တင်ခွင့်ရှိတဲ့ / ခွင့်ပြုထားတဲ့ ဗီဒီယိုကိုပဲ သုံးပါ (website စည်းမျဉ်း၊ copyright ကိုယ်တိုင်တာဝန်)။ '
          'YouTube / TikTok / Red Note တွေက Colab လို server ကို တားတတ်တယ် — မရရင် အကြောင်းရင်းပေါ်မယ်၊ ဗီဒီယိုဖိုင်ကို ပုံမှန်အတိုင်း ရွေးလို့ရတယ်။ '
          'Private / login လိုတဲ့ ဗီဒီယိုက မရဘူး။ စာတန်း (AssemblyAI) ထုတ်ဖို့ကတော့ ဗီဒီယိုဖိုင် လိုသေးတယ် — link သက်သက်ဆိုရင် Gemini က အသံကို ကိုယ်တိုင်နားထောင်တယ်။',
          style: TextStyle(color: DfColors.muted, fontSize: 11.5),
        ),
      ]),
    );
  }
}
