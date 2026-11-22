import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/fair_use.dart';
import '../core/theme.dart';
import '../core/timeline.dart';
import '../data/handoff_repo.dart';
import '../data/project.dart';
import 'widgets.dart';

/// Copyright & Fair Use assistant: measures the edit, keeps the source and
/// permission record, and lists what to check before uploading.
/// It gives rules of thumb, not legal advice, and has no way to hide
/// material from a platform's copyright checks.
class FairUseScreen extends StatefulWidget {
  const FairUseScreen({super.key, required this.project});

  final Project project;

  @override
  State<FairUseScreen> createState() => _FairUseScreenState();
}

class _FairUseScreenState extends State<FairUseScreen> {
  final _repo = HandoffRepo();
  Timeline _tl = const Timeline();
  FairUseRecord _rec = const FairUseRecord();
  final _src = TextEditingController();
  final _holder = TextEditingController();
  final _permNote = TextEditingController();
  bool _loading = true;
  String? _error;

  int get _pid => widget.project.id!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _src.dispose();
    _holder.dispose();
    _permNote.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      _tl = Timeline.decode(await _repo.getDoc(_pid, DocKind.timeline));
      _rec = FairUseRecord.decode(await _repo.getDoc(_pid, DocKind.fairUse));
      _src.text = _rec.sourceNote;
      _holder.text = _rec.rightsHolder;
      _permNote.text = _rec.permissionNote;
    } catch (e) {
      _error = 'ဖတ်လို့မရပါ: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save(FairUseRecord r) async {
    setState(() => _rec = r);
    try {
      await _repo.setDoc(_pid, DocKind.fairUse, r.encode());
    } catch (e) {
      if (mounted) setState(() => _error = 'သိမ်းလို့မရပါ: $e');
    }
  }

  FairUseRecord _withText() => _rec.copyWith(
        sourceNote: _src.text,
        rightsHolder: _holder.text,
        permissionNote: _permNote.text,
      );

  static String _min(int ms) {
    final s = (ms / 1000).round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    final cur = _withText();
    final report = evaluate(_tl, cur, sourceMs: p.videoDurationMs ?? 0);
    final m = report.metrics;
    final (riskLabel, riskColor) = switch (report.risk) {
      Risk.low => ('အန္တရာယ် နည်း (ခန့်မှန်းချက်)', DfColors.ok),
      Risk.medium => ('သတိထားရန် ရှိတယ်', DfColors.warn),
      Risk.high => ('အန္တရာယ် မြင့်', DfColors.danger),
    };

    return DfScaffold(
      appBar: AppBar(title: const Text('Copyright & Fair Use')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              children: [
                if (_error != null) ErrorBanner(_error!),
                Text(p.name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: riskColor.withValues(alpha: 0.7)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(riskLabel, style: TextStyle(color: riskColor, fontWeight: FontWeight.w600, fontSize: 16)),
                      const SizedBox(height: 6),
                      const Text(
                        'ဒါက တိုင်းလို့ရတာတွေပေါ်မှာ အခြေခံတဲ့ လမ်းညွှန်ချက်သာ ဖြစ်ပြီး ဥပဒေအကြံပေးမဟုတ်ပါ။ '
                        '“နည်း” လို့ပြတာက claim မလာဘူးဆိုတဲ့ အာမခံ မဟုတ်ပါ — ပိုင်ရှင်၊ ပလက်ဖောင်းက ဆုံးဖြတ်ပါတယ်။',
                        style: TextStyle(color: DfColors.muted, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                const SectionTitle('Edit ထဲက တိုင်းထားတာ'),
                if (_tl.pieces.isEmpty)
                  const Text('Studio editor မှာ ဗီဒီယိုအပိုင်း အရင်ထည့်ပါ။', style: TextStyle(color: DfColors.muted))
                else ...[
                  _Row('ထွက်မယ့် ဗီဒီယို အရှည်', _min(m.outputMs)),
                  _Row(
                    'မူရင်းကို ပြန်သုံးတဲ့ ပမာဏ',
                    m.sourceMs > 0 ? '${(m.reusedShare * 100).round()}%  (${_min(m.reusedMs)} / ${_min(m.sourceMs)})' : 'မူရင်း အရှည် မသိ',
                  ),
                  _Row('ကိုယ်ပိုင် narration ပါတဲ့ အချိန်', '${(m.narrationShare * 100).round()}%'),
                  _Row('Narration မပါဘဲ အရှည်ဆုံး', _min(m.longestBareMs)),
                  _Row('မူရင်းအသံ', '${(m.originalVolume * 100).round()}%'),
                ],
                const SectionTitle('Source နဲ့ ခွင့်ပြုချက် မှတ်တမ်း'),
                _Field(_src, 'မူရင်း ဘယ်ကရလဲ (platform, link, channel)', (_) => _save(_withText())),
                _Field(_holder, 'မူရင်း အကြောင်းအရာ ပိုင်ရှင်', (_) => _save(_withText())),
                const SizedBox(height: 4),
                DropdownButtonFormField<Permission>(
                  initialValue: _rec.permission,
                  decoration: const InputDecoration(labelText: 'ခွင့်ပြုချက် အခြေအနေ', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: Permission.none, child: Text('မရှိသေး')),
                    DropdownMenuItem(value: Permission.asked, child: Text('တောင်းထားတယ်၊ အဖြေမရသေး')),
                    DropdownMenuItem(value: Permission.granted, child: Text('ပိုင်ရှင်က ခွင့်ပြုထားတယ်')),
                    DropdownMenuItem(value: Permission.licensed, child: Text('Licence နဲ့ ရထားတယ်')),
                  ],
                  onChanged: (v) {
                    if (v != null) _save(_withText().copyWith(permission: v));
                  },
                ),
                const SizedBox(height: 8),
                _Field(_permNote, 'အထောက်အထား (link / ရက်စွဲ / licence အမည်)', (_) => _save(_withText())),
                const SectionTitle('တင်မယ့်အကြောင်း စစ်စာရင်း (ကိုယ်တိုင် အတည်ပြု)'),
                for (final c in fairUseChecklist)
                  if (!(c.key == 'music_ok' && _tl.music == null))
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _rec.checked(c.key),
                      onChanged: (v) => _save(_withText().copyWith(checks: {..._rec.checks, c.key: v ?? false})),
                      title: Text(c.text, style: const TextStyle(fontSize: 14)),
                      subtitle: Text(c.why, style: const TextStyle(color: DfColors.muted, fontSize: 12)),
                    ),
                const SectionTitle('တွေ့ရှိချက်'),
                if (report.findings.isEmpty)
                  const Text('သတိပေးစရာ မရှိပါ။', style: TextStyle(color: DfColors.ok))
                else
                  for (final f in report.findings)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            f.risk == Risk.high ? Icons.error_outline : Icons.warning_amber_rounded,
                            size: 18,
                            color: f.risk == Risk.high ? DfColors.danger : DfColors.warn,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(f.message, style: const TextStyle(fontSize: 13.5))),
                        ],
                      ),
                    ),
                const SectionTitle('Description ထဲ ထည့်စရာ စာသား'),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(gradient: DfGradients.glass, color: DfColors.surface.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(14), border: Border.all(color: DfColors.glassEdge)),
                  child: Text(uploadNote(cur, dramaTitle: p.dramaTitle), style: const TextStyle(fontSize: 13.5)),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: uploadNote(cur, dramaTitle: p.dramaTitle)));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copy လုပ်ပြီးပါပြီ')));
                    }
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy'),
                ),
                const SectionTitle('Claim ဝင်လာရင်'),
                const Text(
                  '• Claim က မှားယွင်းတယ်လို့ ယုံရင် ပလက်ဖောင်းရဲ့ dispute လမ်းကြောင်းနဲ့ အထောက်အထား (အပေါ်က မှတ်တမ်း) ပြပါ။\n'
                  '• မူရင်းပိုင်ရှင်ဆီ တိုက်ရိုက် ခွင့်တောင်းတာ အသေချာဆုံး လမ်းပါ။\n'
                  '• ဒီ app မှာ ပလက်ဖောင်း စစ်ဆေးမှုကို ရှောင်တဲ့ (flip၊ pitch ပြောင်း၊ ဖုံး) feature မပါပါ၊ နောက်လည်း မထည့်ပါ။',
                  style: TextStyle(color: DfColors.muted, fontSize: 13, height: 1.5),
                ),
              ],
            ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.k, this.v);
  final String k;
  final String v;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(k, style: const TextStyle(color: DfColors.muted, fontSize: 13.5))),
            Text(v, style: const TextStyle(fontSize: 13.5)),
          ],
        ),
      );
}

class _Field extends StatelessWidget {
  const _Field(this.c, this.label, this.onChanged);
  final TextEditingController c;
  final String label;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: c,
          onChanged: onChanged,
          minLines: 1,
          maxLines: 3,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        ),
      );
}
