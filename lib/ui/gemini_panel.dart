import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/prompts.dart';
import '../core/srt.dart';
import '../core/stage.dart';
import '../core/theme.dart';
import '../data/handoff_repo.dart';
import '../data/project.dart';
import '../platform/handoff_channel.dart';
import '../state/project_store.dart';

/// Stage 2: hand subtitle chunks to the Gemini app and bring the replies back.
/// There is no API. Text goes out by Android share or copy, and comes back by
/// paste or file import.
class GeminiPanel extends StatefulWidget {
  const GeminiPanel({super.key, required this.project});

  final Project project;

  @override
  State<GeminiPanel> createState() => _GeminiPanelState();
}

class _GeminiPanelState extends State<GeminiPanel> {
  final _repo = HandoffRepo();
  final _notes = TextEditingController();

  bool _loading = true;
  SrtParseResult _parsed = const SrtParseResult([], 0, 0);
  String _templateKey = templates.first.key;
  int _chunkChars = 6000;
  Map<int, String> _results = {};
  String? _msg;
  bool _msgError = false;

  int get _pid => widget.project.id!;
  PromptTemplate get _tpl => templateByKey(_templateKey);
  String get _task => '$_templateKey:$_chunkChars';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(GeminiPanel old) {
    super.didUpdateWidget(old);
    if (old.project.id != widget.project.id) _load();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final src = await _repo.getDoc(_pid, DocKind.sourceSrt) ?? '';
      final notes = await _repo.getDoc(_pid, DocKind.notes) ?? '';
      _parsed = parseSrt(src);
      _notes.text = notes;
      _results = await _repo.results(_pid, _task);
    } catch (e) {
      _say('ဖတ်လို့မရပါ: $e', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _say(String m, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _msg = m;
      _msgError = error;
    });
  }

  List<List<SrtEntry>> get _chunks => chunkEntries(_parsed.entries, maxChars: _chunkChars);

  String _payload(List<SrtEntry> chunk) =>
      _tpl.kind == TaskKind.srtToSrt ? serializeSrt(chunk) : entriesToPlain(chunk);

  String _promptFor(int i, List<List<SrtEntry>> chunks) => _tpl.build(PromptContext(
        chunkNumber: i + 1,
        chunkTotal: chunks.length,
        payload: _payload(chunks[i]),
        notes: _notes.text,
      ));

  Future<void> _setSource(String text) async {
    if (!looksLikeSrt(text)) {
      _say('ဒီစာသားက SRT ပုံစံ မဟုတ်ပါဘူး။ နံပါတ်၊ 00:00:01,000 --> 00:00:03,000 အချိန်၊ စာသား ပါရမယ်။', error: true);
      return;
    }
    final parsed = parseSrt(text);
    final normalized = serializeSrt(parsed.entries);
    await _repo.setDoc(_pid, DocKind.sourceSrt, normalized);
    await _repo.clearResults(_pid);
    if (!mounted) return;
    setState(() {
      _parsed = parsed;
      _results = {};
    });
    final issues = validateSrt(parsed.entries);
    _say('SRT ${parsed.entries.length} ကြောင်း ထည့်ပြီး'
        '${parsed.badBlocks > 0 ? ' · ဖတ်မရတဲ့ block ${parsed.badBlocks}' : ''}'
        '${parsed.missingIndexBlocks > 0 ? ' · နံပါတ်မပါတာ ${parsed.missingIndexBlocks} (အလိုအလျောက်ထည့်ပြီး)' : ''}'
        '${issues.isNotEmpty ? ' · သတိပြုစရာ ${issues.length}' : ''}');
  }

  Future<void> _importFile() async {
    try {
      final f = await HandoffChannel.pickTextFile();
      if (f == null) return;
      await _setSource(f.text);
    } catch (e) {
      _say('ဖိုင်ဖတ်လို့မရပါ: $e', error: true);
    }
  }

  Future<void> _pasteSource() async {
    final text = await _askText('SRT ကို ကူးထည့်ပါ', 'SRT စာသား ကူးထည့်');
    if (text != null) await _setSource(text);
  }

  Future<String?> _askText(String title, String hint) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: DfColors.surface,
      builder: (_) => _TextSheet(title: title, hint: hint),
    );
  }

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    _say('$what ကူးပြီးပါပြီ (${text.length} လုံး)');
  }

  Future<void> _share(String text) async {
    try {
      final r = await HandoffChannel.share(text);
      switch (r) {
        case ShareResult.gemini:
          _say('Gemini ကို ပို့ပြီး။ Gemini မှာ ဖြေပြီးရင် ဖြေချက်ကို copy လုပ်ပြီး ဒီကို ပြန်လာ "ရလဒ်ထည့်" နှိပ်ပါ။');
        case ShareResult.chooser:
          _say('Gemini app မတွေ့လို့ share ရွေးချယ်စရာကို ဖွင့်ပေးထားပါတယ်။ Gemini ကို ရွေးပါ။');
        case ShareResult.tooLarge:
          _say('စာသား ရှည်လွန်းတယ် (၂ သိန်းလုံးကျော်)။ chunk အရွယ်ကို သေးပါ။', error: true);
      }
    } catch (e) {
      _say('Share မရပါ။ "Prompt ကူး" ကိုသုံးပြီး Gemini ထဲ paste လုပ်ပါ။ ($e)', error: true);
    }
  }

  Future<void> _addResult(int i, List<SrtEntry> chunk) async {
    final raw = await _askText('Gemini ဖြေချက် (Chunk ${i + 1})', 'Gemini ရဲ့ ဖြေချက်ကို ကူးထည့်');
    if (raw == null || raw.trim().isEmpty) return;

    String toSave;
    if (_tpl.kind == TaskKind.srtToSrt) {
      final parsed = parseSrt(cleanModelReply(raw));
      if (parsed.entries.isEmpty) {
        _say('SRT အပိုင်းတစ်ခုမှ ဖတ်မရပါ။ Gemini ဖြေချက်တစ်ခုလုံးကို ကူးထည့်ထားလား စစ်ပါ။', error: true);
        return;
      }
      final rep = compareChunk(chunk, parsed);
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => _ReportDialog(report: rep, expected: chunk.length),
      );
      if (ok != true) return;
      toSave = serializeSrt(parsed.entries);
    } else {
      toSave = raw.trim();
    }
    await _repo.saveResult(_pid, _task, i, toSave);
    if (!mounted) return;
    setState(() => _results = {..._results, i: toSave});
    _say('Chunk ${i + 1} သိမ်းပြီး');
    await _maybeDone();
  }

  Future<void> _maybeDone() async {
    final total = _chunks.length;
    if (total == 0 || _results.length < total) return;
    final store = context.read<ProjectStore>();
    final p = store.current;
    if (p != null && !p.isDone(Stage.copy)) await store.setStageDone(p, Stage.copy, true);
  }

  Future<void> _removeResult(int i) async {
    await _repo.deleteResult(_pid, _task, i);
    if (!mounted) return;
    setState(() => _results = {..._results}..remove(i));
  }

  Future<void> _saveNotes() => _repo.setDoc(_pid, DocKind.notes, _notes.text);

  Future<void> _switch({String? key, int? chars}) async {
    setState(() {
      if (key != null) _templateKey = key;
      if (chars != null) _chunkChars = chars;
      _msg = null;
    });
    final r = await _repo.results(_pid, _task);
    if (mounted) setState(() => _results = r);
  }

  /// Final text of the current task: merged SRT or joined recap text.
  ({String text, int missing, int changed})? _finalOutput() {
    final chunks = _chunks;
    if (_results.isEmpty) return null;
    if (_tpl.kind == TaskKind.srtToSrt) {
      final replies = [for (final k in _results.keys.toList()..sort()) parseSrt(_results[k]!)];
      final m = mergeTranslated(_parsed.entries, replies);
      return (text: serializeSrt(m.entries), missing: m.missing.length, changed: m.changedTimes.length);
    }
    final parts = [for (var i = 0; i < chunks.length; i++) if (_results[i] != null) _results[i]!];
    return (text: parts.join('\n\n'), missing: chunks.length - parts.length, changed: 0);
  }

  Future<void> _saveFinal(String text) async {
    final name = _tpl.kind == TaskKind.srtToSrt
        ? '${widget.project.name}_$_templateKey.srt'
        : '${widget.project.name}_$_templateKey.txt';
    try {
      final r = await HandoffChannel.saveTextFile(name, text);
      if (r == true) _say('ဖိုင်သိမ်းပြီး');
    } catch (e) {
      _say('သိမ်းလို့မရပါ: $e', error: true);
    }
  }

  Future<void> _useAsSource(String text) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Source အသစ်လုပ်မလား?'),
        content: const Text('လက်ရှိ source SRT ကို အစားထိုးပြီး ယခင်ရလဒ်အားလုံး ရှင်းပစ်မယ်။ (ဥပမာ ဘာသာပြန်ပြီးသား SRT ကို recap ရေးဖို့ ပြန်သုံးချင်ရင်)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('မလုပ်ဘူး')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('လုပ်မယ်')),
        ],
      ),
    );
    if (ok == true) await _setSource(text);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
    }
    final chunks = _chunks;
    final hasSource = _parsed.entries.isNotEmpty;
    final fin = hasSource ? _finalOutput() : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'API မသုံးပါ။ Prompt+SRT chunk ကို Gemini app ကို ပို့၊ ဖြေချက်ကို ပြန်ကူးထည့်ပါ။ အချိန်နဲ့ နံပါတ်ကို source ကနေပဲ ယူတာမို့ မပျက်ပါဘူး။',
          style: TextStyle(color: DfColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 10),
        if (_msg != null)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (_msgError ? DfColors.danger : DfColors.ok).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(_msg!, style: const TextStyle(fontSize: 13)),
          ),
        _section('၁။ Source SRT'),
        if (hasSource)
          Text(
            '${_parsed.entries.length} ကြောင်း · ${formatSrtTime(_parsed.entries.last.endMs)} · '
            '${validateSrt(_parsed.entries).isEmpty ? 'ပြဿနာမတွေ့' : 'သတိပြုစရာ ${validateSrt(_parsed.entries).length}'}',
            style: const TextStyle(fontSize: 13),
          )
        else
          const Text('SRT မထည့်ရသေးပါ။', style: TextStyle(color: DfColors.muted, fontSize: 13)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(onPressed: _importFile, icon: const Icon(Icons.file_open, size: 18), label: const Text('ဖိုင်ကထည့်')),
          OutlinedButton.icon(onPressed: _pasteSource, icon: const Icon(Icons.paste, size: 18), label: const Text('ကူးထည့်')),
        ]),
        if (hasSource) ...[
          const SizedBox(height: 14),
          _section('၂။ လုပ်ငန်း'),
          DropdownButtonFormField<String>(
            initialValue: _templateKey,
            isExpanded: true,
            items: [for (final t in templates) DropdownMenuItem(value: t.key, child: Text(t.title, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => v == null ? null : _switch(key: v, chars: templateByKey(v).defaultChunkChars),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_tpl.hint, style: const TextStyle(color: DfColors.muted, fontSize: 12)),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            key: ValueKey('chars$_chunkChars'),
            initialValue: _chunkChars,
            decoration: const InputDecoration(labelText: 'Chunk အရွယ် (စာလုံးရေ)'),
            items: const [
              DropdownMenuItem(value: 3000, child: Text('3,000 (သေး)')),
              DropdownMenuItem(value: 4000, child: Text('4,000')),
              DropdownMenuItem(value: 6000, child: Text('6,000')),
              DropdownMenuItem(value: 12000, child: Text('12,000 (ကြီး)')),
            ],
            onChanged: (v) => v == null ? null : _switch(chars: v),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
            minLines: 2,
            maxLines: 5,
            onTapOutside: (_) => _saveNotes(),
            onEditingComplete: _saveNotes,
            decoration: const InputDecoration(
              labelText: 'နာမည်/စကားလုံး မှတ်ချက် (ရွေးချယ်)',
              hintText: '林凡 = လင်ဖန်း\n筑基 = ဇုတ်ကီ',
            ),
          ),
          const SizedBox(height: 14),
          _section('၃။ Chunk ${chunks.length} ခု · ရလဒ် ${_results.length}/${chunks.length}'),
          for (var i = 0; i < chunks.length; i++) _chunkCard(i, chunks),
          if (fin != null) ...[
            const SizedBox(height: 14),
            _section('၄။ ရလဒ်'),
            Text(
              _tpl.kind == TaskKind.srtToSrt
                  ? 'Merge လုပ်ပြီး ${_parsed.entries.length} ကြောင်း'
                      '${fin.missing > 0 ? ' · ဘာသာမပြန်ရသေးတာ ${fin.missing} (source စာသားကို ထားထား)' : ' · အားလုံးပြည့်စုံ'}'
                      '${fin.changed > 0 ? ' · Gemini က အချိန်ပြောင်းတာ ${fin.changed} (source အချိန်ကိုသုံး)' : ''}'
                  : 'Chunk ${_results.length}/${chunks.length} ပေါင်းထား (${fin.text.length} လုံး)',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 4, children: [
              FilledButton.tonalIcon(onPressed: () => _copy(fin.text, 'ရလဒ်'), icon: const Icon(Icons.copy, size: 18), label: const Text('ကူး')),
              FilledButton.tonalIcon(onPressed: () => _saveFinal(fin.text), icon: const Icon(Icons.save_alt, size: 18), label: const Text('ဖိုင်သိမ်း')),
              if (_tpl.kind == TaskKind.srtToSrt)
                OutlinedButton(onPressed: () => _useAsSource(fin.text), child: const Text('Source အသစ်လုပ်')),
            ]),
          ],
        ],
      ],
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w600, color: DfColors.accent)),
      );

  Widget _chunkCard(int i, List<List<SrtEntry>> chunks) {
    final c = chunks[i];
    final done = _results.containsKey(i);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: done ? DfColors.ok : DfColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, size: 18, color: done ? DfColors.ok : DfColors.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Chunk ${i + 1} / ${chunks.length} · #${c.first.index}–#${c.last.index} · ${c.length} ကြောင်း',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 2, children: [
            TextButton(onPressed: () => _copy(_promptFor(i, chunks), 'Prompt'), child: const Text('Prompt ကူး')),
            TextButton(onPressed: () => _share(_promptFor(i, chunks)), child: const Text('Gemini ကို ပို့')),
            TextButton(onPressed: () => _addResult(i, c), child: Text(done ? 'ရလဒ် ပြန်ထည့်' : 'ရလဒ်ထည့်')),
            if (done) TextButton(onPressed: () => _removeResult(i), child: const Text('ဖျက်')),
          ]),
        ],
      ),
    );
  }
}

class _TextSheet extends StatefulWidget {
  const _TextSheet({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  State<_TextSheet> createState() => _TextSheetState();
}

class _TextSheetState extends State<_TextSheet> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _fromClipboard() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text != null && mounted) setState(() => _c.text = d!.text!);
  }

  Future<void> _fromFile() async {
    try {
      final f = await HandoffChannel.pickTextFile();
      if (f != null && mounted) setState(() => _c.text = f.text);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          TextField(
            controller: _c,
            minLines: 6,
            maxLines: 10,
            decoration: InputDecoration(hintText: widget.hint),
          ),
          const SizedBox(height: 6),
          Text('${_c.text.length} လုံး', style: const TextStyle(color: DfColors.muted, fontSize: 12)),
          const SizedBox(height: 8),
          Row(children: [
            OutlinedButton(onPressed: _fromClipboard, child: const Text('Clipboard')),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _fromFile, child: const Text('ဖိုင်')),
            const Spacer(),
            FilledButton(onPressed: () => Navigator.pop(context, _c.text), child: const Text('အတည်ပြု')),
          ]),
        ],
      ),
    );
  }
}

class _ReportDialog extends StatelessWidget {
  const _ReportDialog({required this.report, required this.expected});

  final ChunkReport report;
  final int expected;

  String _list(List<int> l) => l.length <= 8 ? l.join(', ') : '${l.take(8).join(', ')} …(${l.length})';

  @override
  Widget build(BuildContext context) {
    final r = report;
    return AlertDialog(
      title: Text(r.clean ? 'ပြည့်စုံတယ် ✓' : 'စစ်ဆေးချက်'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ဖတ်ရတာ ${r.parsed} / ရှိရမယ့် $expected ကြောင်း'),
          if (r.missing.isNotEmpty) Text('ပျောက်နေတဲ့ နံပါတ်: ${_list(r.missing)}', style: const TextStyle(color: DfColors.warn)),
          if (r.extra.isNotEmpty) Text('ပိုနေတဲ့ နံပါတ်: ${_list(r.extra)}', style: const TextStyle(color: DfColors.warn)),
          if (r.changedTimes.isNotEmpty) Text('အချိန်ပြောင်းထားတာ: ${_list(r.changedTimes)}', style: const TextStyle(color: DfColors.warn)),
          if (r.badBlocks > 0) Text('ဖတ်မရတဲ့ block: ${r.badBlocks}', style: const TextStyle(color: DfColors.warn)),
          if (!r.clean) ...[
            const SizedBox(height: 8),
            const Text(
              'သိမ်းလို့ရပါတယ်။ Merge လုပ်တဲ့အခါ နံပါတ်၊ အချိန်ကို source ကနေပဲ ယူမယ်၊ ပျောက်တာတွေက source စာသားကို ထားမယ်။ ပြန်မေးချင်ရင် မသိမ်းဘဲ ပြန်သွားပါ။',
              style: TextStyle(color: DfColors.muted, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('မသိမ်းဘူး')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('သိမ်းမယ်')),
      ],
    );
  }
}
