import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/srt.dart';
import '../core/subtitle_ops.dart';
import '../core/theme.dart';
import '../data/handoff_repo.dart';
import '../data/project.dart';
import '../platform/handoff_channel.dart';

/// Phase 4: edit subtitles line by line. Works on a copy kept in the
/// database (documents / studio_srt). The source SRT from Stage 2 is never
/// changed here.
class SubtitleStudioScreen extends StatefulWidget {
  const SubtitleStudioScreen({super.key, required this.project});

  final Project project;

  @override
  State<SubtitleStudioScreen> createState() => _SubtitleStudioScreenState();
}

class _SubtitleStudioScreenState extends State<SubtitleStudioScreen> {
  final _repo = HandoffRepo();
  final _undo = <List<SrtEntry>>[];

  bool _loading = true;
  List<SrtEntry> _entries = [];
  int _selected = 0;
  bool _problemsOnly = false;
  String? _msg;
  String? _error;

  int get _pid => widget.project.id!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final studio = await _repo.getDoc(_pid, DocKind.studioSrt);
      final text = (studio != null && studio.trim().isNotEmpty) ? studio : await _repo.getDoc(_pid, DocKind.sourceSrt);
      if (text == null || text.trim().isEmpty) {
        _entries = [];
      } else {
        _entries = parseSrt(text).entries;
        if (studio == null) await _repo.setDoc(_pid, DocKind.studioSrt, serializeSrt(_entries));
      }
    } catch (e) {
      _error = 'ဖတ်လို့မရပါ: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _apply(List<SrtEntry> next, {String? msg}) async {
    _undo.add(_entries);
    if (_undo.length > 30) _undo.removeAt(0);
    setState(() {
      _entries = next;
      if (_selected >= next.length) _selected = next.isEmpty ? 0 : next.length - 1;
      _msg = msg;
      _error = null;
    });
    await _persist();
  }

  Future<void> _persist() async {
    try {
      await _repo.setDoc(_pid, DocKind.studioSrt, serializeSrt(_entries));
    } catch (e) {
      if (mounted) setState(() => _error = 'သိမ်းလို့မရပါ: $e');
    }
  }

  Future<void> _doUndo() async {
    if (_undo.isEmpty) return;
    setState(() {
      _entries = _undo.removeLast();
      if (_selected >= _entries.length) _selected = _entries.isEmpty ? 0 : _entries.length - 1;
      _msg = 'နောက်ပြန်ပြီး';
    });
    await _persist();
  }

  Future<void> _edit(int pos) async {
    setState(() => _selected = pos);
    final r = await showModalBottomSheet<_EditResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: DfColors.surface,
      builder: (_) => _EditSheet(entry: _entries[pos], hasNext: pos < _entries.length - 1),
    );
    if (r == null) return;
    var list = replaceEntry(_entries, pos, _entries[pos].withTextAndTime(r.text, r.startMs, r.endMs));
    switch (r.action) {
      case _EditAction.save:
        await _apply(list, msg: '#${_entries[pos].index} သိမ်းပြီး');
      case _EditAction.split:
        final cut = splitAt(list, pos, r.cursor);
        if (identical(cut, list)) {
          setState(() => _error = 'ခွဲဖို့ စာလုံးကြားမှာ cursor ထားပါ');
        } else {
          await _apply(cut, msg: 'ခွဲပြီး');
        }
      case _EditAction.merge:
        await _apply(mergeWithNext(list, pos), msg: 'ပေါင်းပြီး');
      case _EditAction.delete:
        await _apply(deleteAt(_entries, pos), msg: 'ဖျက်ပြီး');
    }
  }

  Future<void> _shiftDialog() async {
    final c = TextEditingController();
    var fromSelected = false;
    final r = await showDialog<({double sec, bool from})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('အချိန်ရွှေ့'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: c,
              keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
              decoration: const InputDecoration(labelText: 'စက္ကန့် (ဥပမာ 1.5 နောက်ရွှေ့၊ -2 ရှေ့ရွှေ့)'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: fromSelected,
              onChanged: (v) => set(() => fromSelected = v ?? false),
              title: Text('#${_entries.isEmpty ? 0 : _entries[_selected].index} ကနေစပြီး'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('မလုပ်ဘူး')),
            FilledButton(
              onPressed: () {
                final v = double.tryParse(c.text.trim().replaceAll(',', '.'));
                if (v != null) Navigator.pop(ctx, (sec: v, from: fromSelected));
              },
              child: const Text('ရွှေ့'),
            ),
          ],
        ),
      ),
    );
    c.dispose();
    if (r == null || r.sec == 0 || _entries.isEmpty) return;
    await _apply(shift(_entries, (r.sec * 1000).round(), from: r.from ? _selected : 0),
        msg: 'အချိန် ${r.sec > 0 ? '+' : ''}${r.sec} စက္ကန့် ရွှေ့ပြီး');
  }

  Future<void> _fixOverlaps() async {
    final r = fixOverlaps(_entries);
    if (r.fixed == 0) {
      setState(() => _msg = 'ထပ်နေတာ မရှိပါ');
      return;
    }
    await _apply(r.entries, msg: 'ထပ်နေတာ ${r.fixed} ခု ပြင်ပြီး');
  }

  Future<void> _editTerms() async {
    final current = await _repo.getDoc(_pid, DocKind.notes) ?? '';
    final c = TextEditingController(text: current);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('နာမည်/စကားလုံး စာရင်း'),
        content: TextField(
          controller: c,
          minLines: 5,
          maxLines: 10,
          decoration: const InputDecoration(hintText: '林凡 = လင်ဖန်း\nအဟောင်း = အသစ်'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('မလုပ်ဘူး')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('သိမ်း')),
        ],
      ),
    );
    final text = c.text;
    c.dispose();
    if (ok == true) {
      await _repo.setDoc(_pid, DocKind.notes, text);
      if (mounted) setState(() => _msg = 'စာရင်း သိမ်းပြီး (Gemini prompt မှာလည်း သုံးမယ်)');
    }
  }

  Future<void> _applyTerms() async {
    final terms = parseTerms(await _repo.getDoc(_pid, DocKind.notes) ?? '');
    if (terms.isEmpty) {
      setState(() => _error = 'စာရင်း မရှိသေးပါ။ အရင် "စာရင်းပြင်" မှာ "ရှေ့ = နောက်" ပုံစံနဲ့ ထည့်ပါ');
      return;
    }
    final r = applyTerms(_entries, terms);
    if (r.replaced == 0) {
      setState(() => _msg = 'အစားထိုးစရာ မတွေ့ပါ');
      return;
    }
    await _apply(r.entries, msg: 'အစားထိုး ${r.replaced} ခု ပြီး');
  }

  Future<void> _resetToSource() async {
    final src = await _repo.getDoc(_pid, DocKind.sourceSrt);
    if (src == null || src.trim().isEmpty) {
      setState(() => _error = 'Source SRT မရှိပါ');
      return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Source ကို ပြန်ယူမလား?'),
        content: const Text('ပြင်ထားတာတွေ ပျောက်မယ် (Undo နဲ့ ပြန်ယူလို့ရတယ်)။'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('မလုပ်ဘူး')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ပြန်ယူ')),
        ],
      ),
    );
    if (ok == true) await _apply(parseSrt(src).entries, msg: 'Source ပြန်ယူပြီး');
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: serializeSrt(_entries)));
    if (mounted) setState(() => _msg = 'SRT ကူးပြီး');
  }

  Future<void> _saveFile() async {
    try {
      final ok = await HandoffChannel.saveTextFile('${widget.project.name}.srt', serializeSrt(_entries));
      if (ok == true && mounted) setState(() => _msg = 'ဖိုင်သိမ်းပြီး');
    } catch (e) {
      if (mounted) setState(() => _error = 'သိမ်းလို့မရပါ: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final problems = findProblems(_entries);
    final bad = problems.map((p) => p.pos).toSet();
    final shown = _problemsOnly ? [for (var i = 0; i < _entries.length; i++) if (bad.contains(i)) i] : List<int>.generate(_entries.length, (i) => i);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subtitle Studio'),
        actions: [
          IconButton(onPressed: _undo.isEmpty ? null : _doUndo, icon: const Icon(Icons.undo), tooltip: 'နောက်ပြန်'),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'shift':
                  _shiftDialog();
                case 'overlap':
                  _fixOverlaps();
                case 'terms':
                  _applyTerms();
                case 'editTerms':
                  _editTerms();
                case 'copy':
                  _copyAll();
                case 'save':
                  _saveFile();
                case 'reset':
                  _resetToSource();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'shift', child: Text('အချိန်ရွှေ့')),
              PopupMenuItem(value: 'overlap', child: Text('ထပ်နေတာ ပြင်')),
              PopupMenuItem(value: 'terms', child: Text('စာရင်းအတိုင်း အစားထိုး')),
              PopupMenuItem(value: 'editTerms', child: Text('စာရင်းပြင်')),
              PopupMenuItem(value: 'copy', child: Text('SRT ကူး')),
              PopupMenuItem(value: 'save', child: Text('SRT ဖိုင်သိမ်း')),
              PopupMenuItem(value: 'reset', child: Text('Source ပြန်ယူ')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'SRT မရှိသေးပါ။ Recap Workflow အဆင့် ၂ မှာ SRT အရင်ထည့်ပါ။',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: DfColors.muted),
                    ),
                  ),
                )
              : Column(
                  children: [
                    _Preview(entry: _entries[_selected.clamp(0, _entries.length - 1)]),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                      child: Row(children: [
                        Expanded(
                          child: Text(
                            '${_entries.length} ကြောင်း · ပြဿနာ ${problems.length}',
                            style: const TextStyle(color: DfColors.muted, fontSize: 13),
                          ),
                        ),
                        FilterChip(
                          label: const Text('ပြဿနာရှိတာပဲ'),
                          selected: _problemsOnly,
                          onSelected: (v) => setState(() => _problemsOnly = v),
                        ),
                      ]),
                    ),
                    if (_msg != null || _error != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: (_error != null ? DfColors.danger : DfColors.ok).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(_error ?? _msg!, style: const TextStyle(fontSize: 13)),
                      ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                        itemCount: shown.length,
                        itemBuilder: (_, k) {
                          final i = shown[k];
                          final e = _entries[i];
                          final isBad = bad.contains(i);
                          return Card(
                            color: i == _selected ? DfColors.accent.withValues(alpha: 0.12) : DfColors.surface,
                            margin: const EdgeInsets.only(bottom: 6),
                            child: ListTile(
                              dense: true,
                              onTap: () => _edit(i),
                              leading: Text('${e.index}', style: const TextStyle(color: DfColors.muted)),
                              title: Text(e.text, maxLines: 3, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                '${formatSrtTime(e.startMs)} → ${formatSrtTime(e.endMs)}',
                                style: const TextStyle(fontSize: 12, color: DfColors.muted),
                              ),
                              trailing: isBad ? const Icon(Icons.warning_amber, color: DfColors.warn, size: 20) : null,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}

extension on SrtEntry {
  SrtEntry withTextAndTime(String t, int s, int e) => SrtEntry(index, s, e, t);
}

class _Preview extends StatelessWidget {
  const _Preview({required this.entry});

  final SrtEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      height: 96,
      width: double.infinity,
      alignment: Alignment.bottomCenter,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(10)),
      child: Text(
        entry.text,
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.4, shadows: [Shadow(blurRadius: 3, color: Colors.black)]),
      ),
    );
  }
}

enum _EditAction { save, split, merge, delete }

class _EditResult {
  const _EditResult(this.action, this.text, this.startMs, this.endMs, this.cursor);

  final _EditAction action;
  final String text;
  final int startMs;
  final int endMs;
  final int cursor;
}

class _EditSheet extends StatefulWidget {
  const _EditSheet({required this.entry, required this.hasNext});

  final SrtEntry entry;
  final bool hasNext;

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final _text = TextEditingController(text: widget.entry.text);
  late final _start = TextEditingController(text: formatSrtTime(widget.entry.startMs));
  late final _end = TextEditingController(text: formatSrtTime(widget.entry.endMs));
  String? _err;

  @override
  void dispose() {
    _text.dispose();
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  void _done(_EditAction a) {
    final s = parseSrtTime(_start.text);
    final e = parseSrtTime(_end.text);
    if (s == null || e == null) {
      setState(() => _err = 'အချိန်ပုံစံ မမှန်ပါ (00:01:02,500)');
      return;
    }
    if (a == _EditAction.save && e <= s) {
      setState(() => _err = 'ဆုံးချိန်က စချိန်ထက် နောက်ကျရမယ်');
      return;
    }
    final cur = _text.selection.baseOffset < 0 ? _text.text.length : _text.selection.baseOffset;
    Navigator.pop(context, _EditResult(a, _text.text, s, e, cur));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('#${widget.entry.index}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            TextField(controller: _text, minLines: 2, maxLines: 6),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: _start, decoration: const InputDecoration(labelText: 'စချိန်'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _end, decoration: const InputDecoration(labelText: 'ဆုံးချိန်'))),
            ]),
            if (_err != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_err!, style: const TextStyle(color: DfColors.danger, fontSize: 13))),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 4, children: [
              OutlinedButton(onPressed: () => _done(_EditAction.split), child: const Text('Cursor မှာ ခွဲ')),
              if (widget.hasNext) OutlinedButton(onPressed: () => _done(_EditAction.merge), child: const Text('နောက်ကြောင်းနဲ့ ပေါင်း')),
              OutlinedButton(onPressed: () => _done(_EditAction.delete), child: const Text('ဖျက်')),
            ]),
            const SizedBox(height: 8),
            FilledButton(onPressed: () => _done(_EditAction.save), child: const Text('သိမ်း')),
          ],
        ),
      ),
    );
  }
}
