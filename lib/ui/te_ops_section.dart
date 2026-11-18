import 'package:flutter/material.dart';

import '../core/srt.dart';
import '../core/te_ai.dart';
import '../core/te_suggest.dart';
import '../core/theme.dart';
import '../core/transformative_plan.dart';
import '../data/handoff_repo.dart';
import '../data/project.dart';
import '../platform/gemini_open.dart';
import 'te_dialogs.dart';
import 'widgets.dart';

/// The Transformative Editor part of the merged editor: the list of edit
/// operations (cut, zoom, freeze, text, sound ...) with approve / reject /
/// edit / delete, adding at the preview position, Gemini copy-paste and the
/// quiet-stretch finder. The plan lives in the parent; every change goes
/// through [onPlan] (the parent saves it). The original video is never touched
/// and an operation only reaches the render once it is approved.
class TeOpsSection extends StatefulWidget {
  const TeOpsSection({
    super.key,
    required this.project,
    required this.plan,
    required this.posMs,
    required this.onPlan,
    required this.onSeek,
  });

  final Project project;
  final TransformativePlan plan;

  /// Preview position on the original video.
  final int posMs;
  final ValueChanged<TransformativePlan> onPlan;
  final ValueChanged<int> onSeek;

  @override
  State<TeOpsSection> createState() => _TeOpsSectionState();
}

class _TeOpsSectionState extends State<TeOpsSection> {
  final _repo = HandoffRepo();
  late final TextEditingController _instructions = TextEditingController(text: widget.plan.instructions);
  String? _msg;
  String? _err;

  int get _pid => widget.project.id!;
  int get _sourceMs => widget.project.videoDurationMs ?? 0;
  TransformativePlan get _plan => widget.plan;

  @override
  void dispose() {
    _instructions.dispose();
    super.dispose();
  }

  void _say(String? m, {String? error}) => setState(() {
        _msg = m;
        _err = error;
      });

  static String _t(int ms) {
    final sec = ms ~/ 1000;
    return '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _add() async {
    final s = widget.posMs / 1000;
    final op = await showDialog<TransformOp>(context: context, builder: (_) => TeOpDialog(startSec: s, endSec: s + 5));
    if (op == null) return;
    widget.onPlan(_plan.copyWith(ops: [..._plan.ops, op]));
    _say('ထည့်ပြီး — preview မှာ ${_t(op.startMs)} ဝန်းကျင်ကို ကြည့်ပါ');
  }

  Future<void> _edit(TransformOp o) async {
    final next = await showDialog<TransformOp>(context: context, builder: (_) => TeOpDialog(initial: o));
    if (next == null) return;
    widget.onPlan(_plan.replaceOp(next));
  }

  Future<String> _srtText() async {
    final studio = await _repo.getDoc(_pid, DocKind.studioSrt);
    if (studio != null && studio.trim().isNotEmpty) return studio;
    return await _repo.getDoc(_pid, DocKind.sourceSrt) ?? '';
  }

  Future<void> _openGemini() async {
    final prompt = buildTePrompt(
      projectName: widget.project.name,
      sourceMs: _sourceMs,
      subtitles: await _srtText(),
      instructions: _instructions.text,
      tools: _plan.enabledTools,
    );
    final msg = await openInGemini(prompt);
    if (mounted) _say(msg);
  }

  Future<void> _pasteReply() async {
    final reply = await showDialog<String>(context: context, builder: (_) => const TeReplyDialog());
    if (reply == null || reply.trim().isEmpty) return;
    final r = parseTeReply(reply, sourceMs: _sourceMs, idSeed: DateTime.now().millisecondsSinceEpoch);
    if (!mounted) return;
    if (r.error != null) {
      _say(null, error: r.error);
      return;
    }
    widget.onPlan(_plan.copyWith(ops: [..._plan.ops, ...r.ops]));
    _say('အကြံပြုချက် ${r.ops.length} ခု ထည့်ပြီး (စောင့်ဆိုင်း) — preview မှာ ကြည့်ပြီး ခွင့်ပြု/ပယ်ပါ။'
        '${r.rejected.isEmpty ? '' : '\nချန်ထားတာ ${r.rejected.length} ခု: ${r.rejected.take(5).join('; ')}'}');
  }

  Future<void> _findGaps() async {
    final ctrl = TextEditingController(text: '4');
    final secs = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('စာတန်းအကြား ရှာမယ်'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'အနည်းဆုံး ကြာချိန် (စက္ကန့်)', helperText: 'စာတန်း မပါတဲ့ ဒီထက်ရှည်တဲ့ နေရာတွေ'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('မလုပ်တော့ဘူး')),
          FilledButton(onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.trim())), child: const Text('ရှာမယ်')),
        ],
      ),
    );
    ctrl.dispose();
    if (secs == null || secs < 1) return;
    final src = await _srtText();
    if (!mounted) return;
    if (src.trim().isEmpty || _sourceMs <= 0) {
      _say(null, error: 'စာတန်း (SRT) နဲ့ ဗီဒီယိုအရှည် လိုပါတယ်');
      return;
    }
    final gaps = findSubtitleGaps(parseSrt(src).entries, sourceMs: _sourceMs, minGapMs: (secs * 1000).round());
    final props = gapProposals(gaps, idSeed: DateTime.now().millisecondsSinceEpoch);
    if (props.isEmpty) {
      _say('ဒီအတိုင်းအတာနဲ့ စာတန်းမပါတဲ့ နေရာ မတွေ့ပါ');
      return;
    }
    widget.onPlan(_plan.copyWith(ops: [..._plan.ops, ...props]));
    _say('Smart Cut အကြံပြုချက် ${props.length} ခု ထည့်ပြီး (စောင့်ဆိုင်း)။ စာတန်းမရှိတာကို ခန့်မှန်းတာသာ — preview မှာ ကြည့်ပြီး ခွင့်ပြုပါ။');
  }

  void _toggleTool(TransformTool tool, bool on) {
    final next = {..._plan.enabledTools};
    on ? next.add(tool) : next.remove(tool);
    widget.onPlan(_plan.copyWith(enabledTools: next));
  }

  Widget _opTile(TransformOp op) {
    final (label, color) = switch (op.status) {
      OpStatus.proposed => ('စောင့်ဆိုင်း', DfColors.warn),
      OpStatus.approved => ('ခွင့်ပြုပြီး', DfColors.ok),
      OpStatus.rejected => ('ပယ်ထား', DfColors.muted),
    };
    final here = op.status != OpStatus.rejected &&
        (op.startMs == op.endMs ? (widget.posMs >= op.startMs && widget.posMs < op.startMs + 1500) : (widget.posMs >= op.startMs && widget.posMs < op.endMs));
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: DfColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: here ? DfColors.accent : DfColors.line, width: here ? 1.6 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            onTap: () => widget.onSeek(op.startMs),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Row(
                children: [
                  Icon(Icons.play_circle_outline, size: 18, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${op.tool.title} · ${_t(op.startMs)}${op.endMs > op.startMs ? '–${_t(op.endMs)}' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(label, style: TextStyle(color: color, fontSize: 12)),
                ],
              ),
            ),
          ),
          if (op.source == OpSource.ai || op.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
              child: Text(
                [if (op.source == OpSource.ai) 'AI အကြံပြုချက်', if (op.note.isNotEmpty) op.note].join(' · '),
                style: const TextStyle(color: DfColors.muted, fontSize: 12.5),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (op.status != OpStatus.approved)
                  TextButton(onPressed: () => widget.onPlan(_plan.setOpStatus(op.id, OpStatus.approved)), child: const Text('ခွင့်ပြု')),
                if (op.status != OpStatus.rejected)
                  TextButton(onPressed: () => widget.onPlan(_plan.setOpStatus(op.id, OpStatus.rejected)), child: const Text('ပယ်')),
                TextButton(onPressed: () => _edit(op), child: const Text('ပြင်')),
                IconButton(
                  tooltip: 'ဖျက်',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => widget.onPlan(_plan.removeOp(op.id)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ops = [..._plan.ops]..sort((a, b) => a.startMs.compareTo(b.startMs));
    final pending = _plan.pendingOps.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_plan.fromNewerVersion)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('ဒီ Plan ကို app ဗားရှင်းအသစ်က ရေးထားတာ — မသိတဲ့ အချက်တွေကို မဖျက်ဘဲ ထိန်းထားမယ်။', style: TextStyle(color: DfColors.warn, fontSize: 12.5)),
          ),
        Wrap(spacing: 8, runSpacing: 4, children: [
          FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add, size: 18), label: const Text('ဒီအချိန်မှာ ထည့်')),
          OutlinedButton.icon(onPressed: _findGaps, icon: const Icon(Icons.content_cut, size: 18), label: const Text('ဖြတ်ဖို့ ရှာ')),
        ]),
        if (pending > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Expanded(child: Text('စောင့်ဆိုင်းနေတာ $pending ခု (ခွင့်ပြုမှ Render မှာ ပါမယ်)', style: const TextStyle(color: DfColors.warn, fontSize: 12.5))),
              TextButton(
                onPressed: () => widget.onPlan(_plan.copyWith(ops: [for (final o in _plan.ops) o.status == OpStatus.proposed ? o.withStatus(OpStatus.approved) : o])),
                child: const Text('အကုန် ခွင့်ပြု'),
              ),
            ]),
          ),
        const SizedBox(height: 8),
        if (ops.isEmpty)
          const Text('Effect မရှိသေးပါ။ Preview ကို လိုတဲ့နေရာ ရွှေ့ပြီး "ဒီအချိန်မှာ ထည့်" နှိပ်ပါ။', style: TextStyle(color: DfColors.muted, fontSize: 13)),
        for (final op in ops) _opTile(op),
        if (_msg != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_msg!, style: const TextStyle(color: DfColors.ok, fontSize: 13))),
        if (_err != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_err!, style: const TextStyle(color: DfColors.danger, fontSize: 13))),
        const SizedBox(height: 4),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: const Text('Gemini ကို အကြံတောင်း', style: TextStyle(fontWeight: FontWeight.w600)),
            children: [
              const InfoHint(
                'API key မလိုပါ။ Prompt ကို Gemini app မှာ paste၊ ပြန်ဖြေတာကို ဒီမှာ ထည့်ပါ။ အကြံပြုချက်တွေက "စောင့်ဆိုင်း" အဖြစ်သာ ဝင်မယ် — preview မှာ ကြည့်ပြီး ကိုယ်တိုင် ခွင့်ပြုမှသာ Render မှာ ပါမယ်။',
                label: 'ဘယ်လိုအလုပ်လုပ်လဲ',
              ),
              TextField(
                controller: _instructions,
                minLines: 2,
                maxLines: 5,
                onChanged: (v) => widget.onPlan(_plan.copyWith(instructions: v)),
                decoration: const InputDecoration(labelText: 'ကိုယ့်ညွှန်ကြားချက် (ဥပမာ - အရေးကြီးတဲ့ အပိုင်းကို Freeze လုပ်ပါ)'),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final t in TransformTool.values)
                  FilterChip(
                    label: Text(t.title, style: const TextStyle(fontSize: 12)),
                    selected: _plan.enabledTools.contains(t),
                    onSelected: (v) => _toggleTool(t, v),
                  ),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                OutlinedButton.icon(onPressed: _openGemini, icon: const Icon(Icons.open_in_new, size: 18), label: const Text('Gemini ဖွင့်')),
                OutlinedButton.icon(onPressed: _pasteReply, icon: const Icon(Icons.paste, size: 18), label: const Text('ပြန်ဖြေ ထည့်')),
              ]),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }
}
