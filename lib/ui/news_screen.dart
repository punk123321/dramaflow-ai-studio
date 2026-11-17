import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/news.dart';
import '../core/theme.dart';
import '../data/handoff_repo.dart';
import '../data/news_repo.dart';
import '../platform/gemini_open.dart';
import '../platform/handoff_channel.dart';
import '../platform/news_client.dart';
import '../state/project_store.dart';
import 'widgets.dart';

/// News reader: headlines from the user's RSS feeds. Only the headline, link,
/// time and a short snippet are kept. Tapping a story opens a new layer with
/// the story page, from where a recap script can be made for a DramaFlow project.
class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  final _repo = NewsRepo();
  List<NewsFeed> _feeds = [];
  List<NewsItem> _items = [];
  Map<String, String> _errors = {};
  int _savedMs = 0;
  bool _loading = true;
  bool _refreshing = false;
  String _filter = ''; // feed category, '' = all

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _feeds = await _repo.feeds();
    final c = await _repo.cached();
    _items = c.items;
    _savedMs = c.savedMs;
    if (mounted) setState(() => _loading = false);
    if (_items.isEmpty) await _refresh();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    final r = await loadNews(_feeds);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (r.items.isNotEmpty) {
      _items = r.items;
      _savedMs = now;
      await _repo.saveCache(_items, now);
    }
    if (mounted) {
      setState(() {
        _errors = r.errors;
        _refreshing = false;
      });
    }
  }

  Future<void> _manage() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FeedManagerScreen()));
    _feeds = await _repo.feeds();
    if (mounted) setState(() {});
    await _refresh();
  }

  void _open(NewsItem it) {
    Navigator.of(context).push(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => NewsStoryScreen(item: it),
      transitionsBuilder: (_, a, __, child) => SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero).chain(CurveTween(curve: Curves.easeOutCubic)).animate(a),
        child: child,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cats = {for (final f in _feeds) if (f.category.isNotEmpty) f.category};
    final catByFeed = {for (final f in _feeds) f.id: f.category};
    final shown = _items.where((i) => _filter.isEmpty || catByFeed[i.feedId] == _filter).toList();
    final now = DateTime.now().millisecondsSinceEpoch;
    return Scaffold(
      appBar: AppBar(title: const Text('သတင်း'), actions: [
        IconButton(onPressed: _refreshing ? null : _refresh, icon: const Icon(Icons.refresh), tooltip: 'ပြန်ယူ'),
        IconButton(onPressed: _manage, icon: const Icon(Icons.rss_feed), tooltip: 'RSS စာရင်း'),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                if (_refreshing) const LinearProgressIndicator(),
                if (cats.isNotEmpty)
                  SizedBox(
                    height: 44,
                    child: ListView(scrollDirection: Axis.horizontal, children: [
                      for (final c in ['', ...cats])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(label: Text(c.isEmpty ? 'အားလုံး' : c), selected: _filter == c, onSelected: (_) => setState(() => _filter = c)),
                        ),
                    ]),
                  ),
                if (_errors.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('ဖတ်မရတဲ့ feed: ${_errors.entries.map((e) => '${e.key} (${e.value})').join('၊ ')}', style: const TextStyle(color: DfColors.warn, fontSize: 12)),
                  ),
                if (_savedMs > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('နောက်ဆုံး ပြန်ယူချိန် ${ageText(_savedMs, now)}', style: const TextStyle(color: DfColors.muted, fontSize: 12)),
                  ),
                if (shown.isEmpty && !_refreshing)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Text('သတင်း မရှိသေးပါ။ အပေါ်က RSS ခလုတ်နဲ့ feed စစ်/ထည့်ပါ၊ ပြီးရင် ပြန်ယူပါ။ အင်တာနက် လိုတယ်။', textAlign: TextAlign.center, style: TextStyle(color: DfColors.muted)),
                  ),
                for (final it in shown)
                  Card(
                    margin: const EdgeInsets.only(top: 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _open(it),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(it.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.5)),
                          if (it.snippet.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(it.snippet, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: DfColors.muted, fontSize: 13))),
                          const SizedBox(height: 6),
                          Text('${it.feedName}${ageText(it.publishedMs, now).isEmpty ? '' : ' · ${ageText(it.publishedMs, now)}'}', style: const TextStyle(color: DfColors.accent, fontSize: 12)),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ),
    );
  }
}

/// The layer that opens over the list when a story is tapped.
class NewsStoryScreen extends StatefulWidget {
  const NewsStoryScreen({super.key, required this.item});

  final NewsItem item;

  @override
  State<NewsStoryScreen> createState() => _NewsStoryScreenState();
}

class _NewsStoryScreenState extends State<NewsStoryScreen> {
  final _docs = HandoffRepo();
  final _article = TextEditingController();
  final _script = TextEditingController();
  String? _msg;
  bool _err = false;
  bool _busy = false;

  @override
  void dispose() {
    _article.dispose();
    _script.dispose();
    super.dispose();
  }

  void _say(String m, {bool error = false}) => setState(() {
        _msg = m;
        _err = error;
      });

  String _prompt() => buildNewsScriptPrompt(item: widget.item, articleText: _article.text);

  Future<void> _gemini() async {
    final m = await openInGemini(_prompt());
    _say(m);
  }

  Future<void> _copyPrompt() async {
    await Clipboard.setData(ClipboardData(text: _prompt()));
    _say('Prompt ကူးပြီး။');
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text?.replaceAll('```', '').trim();
    if (t != null && t.isNotEmpty) setState(() => _script.text = t);
  }

  Future<void> _openOriginal() async {
    final ok = await HandoffChannel.openUrl(widget.item.link);
    if (!ok) {
      await Clipboard.setData(ClipboardData(text: widget.item.link));
      _say('ဖွင့်မရလို့ link ကို ကူးထားတယ်။ browser မှာ paste လုပ်ပါ။', error: true);
    }
  }

  Future<void> _makeProject() async {
    final script = _script.text.trim();
    if (script.isEmpty) {
      _say('Script အရင် ထည့်ပါ (Gemini ဖြေချက် paste သို့ ကိုယ်တိုင်ရေး)။', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final store = context.read<ProjectStore>();
      final title = widget.item.title;
      await store.create(name: title.runes.length > 60 ? '${String.fromCharCodes(title.runes.take(60))}…' : title, dramaTitle: widget.item.feedName, episode: 1);
      final id = store.current?.id;
      if (id == null) throw StateError('project');
      await _docs.setDoc(id, DocKind.script, script);
      await _docs.setDoc(id, DocKind.notes, 'သတင်းရင်းမြစ်: ${widget.item.feedName}\n${widget.item.link}');
      _say('Project ဖန်တီးပြီး script သိမ်းပြီး။ Home မှာ project ကို ဖွင့်ပြီး အသံ (အဆင့် ၃)၊ ဗီဒီယို၊ ပုံတွေ ဆက်လုပ်ပါ။');
    } catch (e) {
      _say('Project မဖန်တီးနိုင်ပါ: $e', error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final now = DateTime.now().millisecondsSinceEpoch;
    final age = ageText(it.publishedMs, now);
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 200,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3B2A6E), Color(0xFF0F1D4A), Color(0xFF7A2A5A)])),
              alignment: Alignment.bottomLeft,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(it.feedName, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList.list(children: [
            Text(it.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.5)),
            const SizedBox(height: 6),
            Text('${it.feedName}${age.isEmpty ? '' : ' · $age'}', style: const TextStyle(color: DfColors.accent, fontSize: 13)),
            if (it.snippet.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(it.snippet, style: const TextStyle(color: DfColors.muted))),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              FilledButton.icon(onPressed: _openOriginal, icon: const Icon(Icons.open_in_new, size: 18), label: const Text('မူရင်းမှာ ဖတ်')),
            ]),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('App က ခေါင်းစဉ်၊ link နဲ့ စာတို အနည်းငယ်ပဲ ပြတာပါ။ သတင်းအပြည့်၊ ပုံ၊ ဗီဒီယိုကို မူရင်းဆိုက်ကနေ ကြည့်ပါ။ သူတို့ရဲ့ ပုံ/ဗီဒီယိုကို ဒီ app က မသုံးပါဘူး။', style: TextStyle(color: DfColors.muted, fontSize: 12)),
            ),
            const SectionTitle('Recap script'),
            TextField(
              controller: _article,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'မူရင်းသတင်း စာသား ကူးထည့် (မဖြစ်မနေ မဟုတ်၊ ပိုမှန်စေတယ်)'),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              FilledButton.icon(onPressed: _gemini, icon: const Icon(Icons.auto_awesome, size: 18), label: const Text('Gemini ဖွင့်မယ်')),
              OutlinedButton.icon(onPressed: _copyPrompt, icon: const Icon(Icons.copy, size: 18), label: const Text('Prompt ကူး')),
            ]),
            const SizedBox(height: 12),
            TextField(controller: _script, minLines: 4, maxLines: 10, decoration: const InputDecoration(labelText: 'Script (Gemini ဖြေချက် paste သို့ ကိုယ်တိုင်ရေး)')),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              OutlinedButton(onPressed: _paste, child: const Text('Paste')),
              FilledButton.icon(onPressed: _busy ? null : _makeProject, icon: const Icon(Icons.movie_creation_outlined, size: 18), label: const Text('Project ဖန်တီး + script သိမ်း')),
            ]),
            if (_msg != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_msg!, style: TextStyle(color: _err ? DfColors.danger : DfColors.ok, fontSize: 13))),
            const SizedBox(height: 24),
          ]),
        ),
      ]),
    );
  }
}

/// Add, switch off or remove RSS feeds.
class FeedManagerScreen extends StatefulWidget {
  const FeedManagerScreen({super.key});

  @override
  State<FeedManagerScreen> createState() => _FeedManagerScreenState();
}

class _FeedManagerScreenState extends State<FeedManagerScreen> {
  final _repo = NewsRepo();
  List<NewsFeed> _feeds = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _repo.feeds().then((f) {
      if (mounted) {
        setState(() {
          _feeds = f;
          _loading = false;
        });
      }
    });
  }

  Future<void> _save() => _repo.saveFeeds(_feeds);

  Future<void> _add() async {
    final name = TextEditingController();
    final url = TextEditingController();
    final cat = TextEditingController();
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('RSS feed ထည့်'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'နာမည်')),
              TextField(controller: url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'RSS link (https://...)')),
              TextField(controller: cat, decoration: const InputDecoration(labelText: 'အမျိုးအစား (မဖြစ်မနေ မဟုတ်)')),
              if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: DfColors.danger, fontSize: 12))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('မလုပ်တော့ဘူး')),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty) {
                  set(() => err = 'နာမည် ထည့်ပါ');
                } else if (!isHttpUrl(url.text)) {
                  set(() => err = 'https:// နဲ့ စတဲ့ link ထည့်ပါ');
                } else {
                  Navigator.pop(ctx, true);
                }
              },
              child: const Text('ထည့်'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      setState(() => _feeds = [..._feeds, NewsFeed(id: 'u${DateTime.now().millisecondsSinceEpoch}', name: name.text.trim(), url: url.text.trim(), category: cat.text.trim())]);
      await _save();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RSS စာရင်း'), actions: [IconButton(onPressed: _add, icon: const Icon(Icons.add), tooltip: 'ထည့်')]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              const Text(
                'အစပိုင်း စာရင်းက ကျွန်တော် မစစ်ရသေးတဲ့ feed လင့်တွေပါ၊ ဖုန်းမှာ ပွင့်လား ကြည့်ပါ။ မပွင့်ရင် ဖျက်ပါ၊ ကိုယ့် feed link ထည့်ပါ။ RSS ရဲ့ သုံးခွင့် စည်းကမ်းကိုလည်း သူ့ဆိုက်မှာ စစ်ပါ။',
                style: TextStyle(color: DfColors.muted, fontSize: 13),
              ),
              for (var i = 0; i < _feeds.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_feeds[i].name),
                  subtitle: Text('${_feeds[i].category.isEmpty ? '' : '${_feeds[i].category} · '}${_feeds[i].url}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                  leading: Switch(
                    value: _feeds[i].enabled,
                    onChanged: (v) async {
                      setState(() => _feeds[i] = _feeds[i].copyWith(enabled: v));
                      await _save();
                    },
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      setState(() => _feeds.removeAt(i));
                      await _save();
                    },
                  ),
                ),
              if (_feeds.isEmpty) const Padding(padding: EdgeInsets.only(top: 24), child: Text('Feed မရှိတော့ပါ။ + နဲ့ ထည့်ပါ။', style: TextStyle(color: DfColors.muted))),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () async {
                  final have = {for (final f in _feeds) f.id};
                  setState(() => _feeds = [..._feeds, for (final f in suggestedFeeds) if (!have.contains(f.id)) f]);
                  await _save();
                },
                child: const Text('အကြံပြုစာရင်း ပြန်ထည့်'),
              ),
            ]),
    );
  }
}
