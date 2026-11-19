import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/transformative_plan.dart';
import 'widgets.dart';

/// Edits the SELECTED effect right under the preview, so the picture stays
/// visible while a value changes (no dialog). Slider moves are reported with
/// `save: false` (preview updates at once) and the release with `save: true`.
class TeInlineEditor extends StatefulWidget {
  const TeInlineEditor({
    super.key,
    required this.op,
    required this.posMs,
    required this.onChange,
    required this.onStatus,
    required this.onDelete,
    required this.onClose,
    required this.onDetails,
  });

  final TransformOp op;
  final int posMs;
  final void Function(TransformOp op, bool save) onChange;
  final ValueChanged<OpStatus> onStatus;
  final VoidCallback onDelete;
  final VoidCallback onClose;
  final VoidCallback onDetails;

  @override
  State<TeInlineEditor> createState() => _TeInlineEditorState();
}

class _TeInlineEditorState extends State<TeInlineEditor> {
  late final TextEditingController _text = TextEditingController(
    text: widget.op.params['text'] is String ? widget.op.params['text'] as String : '',
  );
  String? _hint;

  static const _colors = [0xFFFFFFFF, 0xFFFFEB3B, 0xFFFF5252, 0xFF69F0AE, 0xFF40C4FF];

  TransformOp get _op => widget.op;
  bool get _point => _op.tool == TransformTool.freezeFrame || _op.tool == TransformTool.soundDesign;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  static String _t(int ms) {
    final s = ms / 1000;
    final m = s ~/ 60;
    final r = s - m * 60;
    return '$m:${r.toStringAsFixed(1).padLeft(4, '0')}';
  }

  double _num(String k, double d) {
    final v = _op.params[k];
    return v is num ? v.toDouble() : d;
  }

  void _live(String k, Object v) => widget.onChange(_op.copyWith(params: {..._op.params, k: v}), false);
  void _save() => widget.onChange(_op, true);

  Widget _slider(String label, String k, double d, double min, double max, {bool whole = false}) {
    final v = _num(k, d).clamp(min, max).toDouble();
    return Row(children: [
      SizedBox(width: 92, child: Text(label, style: const TextStyle(fontSize: 12.5, color: DfColors.muted))),
      Expanded(
        child: Slider(
          value: v,
          min: min,
          max: max,
          onChanged: (x) => _live(k, whole ? x.roundToDouble() : double.parse(x.toStringAsFixed(2))),
          onChangeEnd: (_) => _save(),
        ),
      ),
    ]);
  }

  void _setStart() {
    final pos = widget.posMs;
    if (_point) {
      widget.onChange(_op.copyWith(startMs: pos, endMs: pos), true);
      return;
    }
    widget.onChange(_op.copyWith(startMs: pos, endMs: pos < _op.endMs ? _op.endMs : pos + 2000), true);
  }

  void _setEnd() {
    final pos = widget.posMs;
    if (pos <= _op.startMs) {
      setState(() => _hint = 'ဆုံးချိန်က စချိန်ထက် နောက်မှ ဖြစ်ရမယ် — preview ကို ရှေ့ဆက်ရွှေ့ပါ');
      return;
    }
    setState(() => _hint = null);
    widget.onChange(_op.copyWith(endMs: pos), true);
  }

  List<Widget> _controls() {
    switch (_op.tool) {
      case TransformTool.cropReframe:
        return [
          const Text('Preview ကို လက်နှစ်ချောင်းနဲ့ ညှပ်ချဲ့၊ တစ်ချောင်းနဲ့ ဆွဲရွှေ့ပါ (ဒီ effect ရဲ့ အချိန်ထဲမှာ)', style: TextStyle(fontSize: 12.5, color: DfColors.muted)),
          _slider('Zoom ×', 'zoom', 1.5, 1.0, 3.0),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => widget.onChange(_op.copyWith(params: {..._op.params, 'zoom': 1.5, 'cx': 0.5, 'cy': 0.5}), true),
              child: const Text('အလယ်ပြန်ထား'),
            ),
          ),
        ];
      case TransformTool.colorGrade:
        Widget preset(String label, double b, double c) => ActionChip(
              label: Text(label, style: const TextStyle(fontSize: 12)),
              onPressed: () => widget.onChange(_op.copyWith(params: {..._op.params, 'brightness': b, 'contrast': c}), true),
            );
        return [
          Wrap(spacing: 6, runSpacing: 2, children: [
            preset('မှောင် mood', -0.2, 0.25),
            preset('လင်း', 0.2, 0.0),
            preset('Contrast မြင့်', 0.0, 0.35),
            preset('ပျော့', 0.05, -0.25),
          ]),
          _slider('အလင်း', 'brightness', 0.15, -0.6, 0.6),
          _slider('Contrast', 'contrast', 0.0, -0.6, 0.6),
        ];
      case TransformTool.freezeFrame:
        return [_slider('ရပ်မယ့်စက္ကန့်', 'hold', 3.0, 0.5, 15.0)];
      case TransformTool.motionGraphics:
        final k = _op.params['kind'] is String ? _op.params['kind'] as String : 'label';
        final shape = k == 'box' || k == 'circle' || k == 'spot';
        Widget flag(String label, String key, {bool defaultOn = false}) => SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(label, style: const TextStyle(fontSize: 13.5)),
              value: defaultOn ? _op.params[key] != false : _op.params[key] == true,
              onChanged: (v) => widget.onChange(_op.copyWith(params: {..._op.params, key: v}), true),
            );
        return [
          if (k == 'label')
            TextField(
              controller: _text,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'စာသား'),
              onChanged: (v) => widget.onChange(_op.copyWith(params: {..._op.params, 'text': v}), true),
            ),
          if (k == 'label') flag('အရောင်ခြယ် နောက်ခံ (ခရမ်း→ပန်း)', 'grad'),
          Text(
            switch (k) {
              'frame' => 'ဗီဒီယိုပတ်ပတ်လည် ဘောင် — အချိန်ကို timeline မှာ ညှိပါ',
              'spot' => 'အလယ်က ခလုတ်နဲ့ ရွှေ့၊ ထောင့်က အစက်နဲ့ အကျယ်ညှိ — ကျန်တာ မှောင်သွားမယ်',
              'box' || 'circle' => 'ဆွဲရွှေ့၊ ထောင့်က အစက်နဲ့ အရွယ်ညှိ',
              _ => 'Preview ပေါ်မှာ ဆွဲရွှေ့လို့ရတယ်',
            },
            style: const TextStyle(fontSize: 12.5, color: DfColors.muted),
          ),
          if (k == 'frame')
            _slider('အထူ', 'size', 0.012, 0.005, 0.05)
          else if (shape)
            _slider('အကျယ်', 'size', 0.4, 0.05, 0.95)
          else
            _slider('အရွယ်', 'size', 0.06, 0.03, 0.4),
          if (shape) _slider('အမြင့်', 'ar', 0.5, 0.1, 3.0),
          if (k == 'arrow') _slider('လှည့်', 'angle', 0, 0, 359, whole: true),
          if (k == 'frame') flag('သက်တန့်ရောင်စုံ', 'grad'),
          if (k == 'spot') flag('ဘဲဥပုံ (ပိတ် = လေးထောင့်)', 'round', defaultOn: true),
          if (k != 'spot' && !(k == 'frame' && _op.params['grad'] == true))
            Wrap(spacing: 8, children: [
              for (final c in _colors)
                GestureDetector(
                  onTap: () => widget.onChange(_op.copyWith(params: {..._op.params, 'color': c}), true),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(color: _op.params['color'] == c ? DfColors.accent : DfColors.line, width: _op.params['color'] == c ? 3 : 1),
                    ),
                  ),
                ),
            ]),
        ];
      case TransformTool.pictureInPicture:
        return [
          const Text('Preview ပေါ်မှာ ဆွဲရွှေ့လို့ရတယ်', style: TextStyle(fontSize: 12.5, color: DfColors.muted)),
          _slider('အကျယ်', 'size', 0.25, 0.05, 0.6),
        ];
      default:
        return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusColor) = switch (_op.status) {
      OpStatus.proposed => ('စောင့်ဆိုင်း', DfColors.warn),
      OpStatus.approved => ('ခွင့်ပြုပြီး', DfColors.ok),
      OpStatus.rejected => ('ပယ်ထား', DfColors.muted),
    };
    return DfCard(
      margin: const EdgeInsets.only(bottom: 12, top: 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.edit, size: 16, color: DfColors.accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${_op.tool.title} · ${_t(_op.startMs)}${_point ? '' : ' – ${_t(_op.endMs)}'}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 12)),
          IconButton(visualDensity: VisualDensity.compact, tooltip: 'ပိတ်', icon: const Icon(Icons.close, size: 18), onPressed: widget.onClose),
        ]),
        Wrap(spacing: 8, runSpacing: 4, children: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38)),
            onPressed: _setStart,
            child: Text(_point ? 'နေရာ ← ဒီနေရာ' : 'စချိန် ← ဒီနေရာ'),
          ),
          if (!_point)
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38)),
              onPressed: _setEnd,
              child: const Text('ဆုံးချိန် ← ဒီနေရာ'),
            ),
        ]),
        if (_hint != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_hint!, style: const TextStyle(color: DfColors.warn, fontSize: 12.5))),
        ..._controls(),
        Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (_op.status != OpStatus.approved) TextButton(onPressed: () => widget.onStatus(OpStatus.approved), child: const Text('ခွင့်ပြု')),
          if (_op.status != OpStatus.rejected) TextButton(onPressed: () => widget.onStatus(OpStatus.rejected), child: const Text('ပယ်')),
          TextButton(onPressed: widget.onDetails, child: const Text('အသေးစိတ်')),
          IconButton(visualDensity: VisualDensity.compact, tooltip: 'ဖျက်', icon: const Icon(Icons.delete_outline, size: 20), onPressed: widget.onDelete),
        ]),
      ]),
    );
  }
}
