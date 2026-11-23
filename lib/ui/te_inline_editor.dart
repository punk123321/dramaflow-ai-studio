import 'package:flutter/material.dart';

import '../core/te_frames.dart';
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

  /// Length of a range effect in seconds; keeps the start.
  Widget _durationSlider() {
    final secs = ((_op.endMs - _op.startMs) / 1000).clamp(0.2, 5.0).toDouble();
    return Row(children: [
      const SizedBox(width: 92, child: Text('ကြာချိန်', style: TextStyle(fontSize: 12.5, color: DfColors.muted))),
      Expanded(
        child: Slider(
          value: secs,
          min: 0.2,
          max: 5.0,
          label: '${secs.toStringAsFixed(1)}s',
          onChanged: (v) => widget.onChange(_op.copyWith(endMs: _op.startMs + (v * 1000).round()), false),
          onChangeEnd: (_) => _save(),
        ),
      ),
      Text('${secs.toStringAsFixed(1)}s', style: const TextStyle(fontSize: 12.5)),
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

  /// Frame designs to switch between (the first one is the plain line / rainbow border).
  Widget _frameStrip() {
    final cur = _op.params['tpl'] is int ? _op.params['tpl'] as int : 0;
    Widget chip(String label, int id) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text(label, style: const TextStyle(fontSize: 12)),
            selected: cur == id,
            onSelected: (_) {
              final t = frameTemplateById(id);
              final next = {..._op.params};
              if (t == null) {
                next.remove('tpl');
              } else {
                next['tpl'] = id;
                next['grad'] = false;
                if (!t.usesColor) next['color'] = 0xFFFFFFFF;
              }
              widget.onChange(_op.copyWith(params: next), true);
            },
          ),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [chip('Plain', 0), for (final t in frameTemplates) chip(t.name, t.id)]),
    );
  }

  /// The colour swatches are shown for the plain border (not rainbow) and for the designs that take a colour.
  bool _frameUsesColor() {
    final id = _op.params['tpl'];
    if (id is int) return frameTemplateById(id)?.usesColor ?? false;
    return _op.params['grad'] != true;
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
        Widget preset(String label, double b, double c, [double s = 0]) => ActionChip(
              label: Text(label, style: const TextStyle(fontSize: 12)),
              onPressed: () => widget.onChange(_op.copyWith(params: {..._op.params, 'brightness': b, 'contrast': c, 'saturation': s}), true),
            );
        return [
          Wrap(spacing: 6, runSpacing: 2, children: [
            preset('မှောင် mood', -0.2, 0.25),
            preset('လင်း', 0.2, 0.0),
            preset('Contrast မြင့်', 0.0, 0.35),
            preset('ပျော့', 0.05, -0.25),
            preset('B&W', 0.0, 0.1, -1),
            preset('အရောင်ထင်', 0.0, 0.1, 0.5),
            preset('အရောင်မှိန်', 0.0, 0.0, -0.5),
          ]),
          _slider('အလင်း', 'brightness', 0.15, -0.6, 0.6),
          _slider('Contrast', 'contrast', 0.0, -0.6, 0.6),
          _slider('အရောင်အား (−1 = B&W)', 'saturation', 0.0, -1.0, 1.0),
        ];
      case TransformTool.speedChange:
        Widget sp(String label, double v) => ChoiceChip(
              label: Text(label, style: const TextStyle(fontSize: 12)),
              selected: _num('speed', 2.0) == v,
              onSelected: (_) => widget.onChange(_op.copyWith(params: {..._op.params, 'speed': v}), true),
            );
        return [
          const Text('Preview မှာ ဒီအပိုင်းရောက်ရင် အမြန်နှုန်း တကယ်ပြောင်းပြီး ပြမယ်။ ၁× မဟုတ်ရ၊ အသံ pitch မပြောင်းပါ', style: TextStyle(fontSize: 12.5, color: DfColors.muted)),
          Wrap(spacing: 6, runSpacing: 2, children: [sp('0.25×', 0.25), sp('0.5×', 0.5), sp('0.75×', 0.75), sp('1.5×', 1.5), sp('2×', 2.0), sp('3×', 3.0), sp('4×', 4.0)]),
          _slider('Speed ×', 'speed', 2.0, 0.25, 4.0),
        ];
      case TransformTool.blur:
        Widget bl(String label, double v) => ChoiceChip(
              label: Text(label, style: const TextStyle(fontSize: 12)),
              selected: _num('strength', 10.0) == v,
              onSelected: (_) => widget.onChange(_op.copyWith(params: {..._op.params, 'strength': v}), true),
            );
        return [
          const Text('ဒီအချိန်ပိုင်းတစ်ခုလုံး မှုန်ဝါးမယ်။ Preview က ခန့်မှန်းပြတာ၊ တကယ့်ပမာဏက Render မှာ ကြည့်ပါ', style: TextStyle(fontSize: 12.5, color: DfColors.muted)),
          Wrap(spacing: 6, runSpacing: 2, children: [bl('နည်း', 4), bl('အလယ်', 10), bl('များ', 25), bl('အရမ်း', 45)]),
          _slider('Blur', 'strength', 10.0, 0.5, 50.0),
        ];
      case TransformTool.mirrorFlip:
        Widget fl(String label, IconData icon, String key) => SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              secondary: Icon(icon, size: 20),
              title: Text(label, style: const TextStyle(fontSize: 13.5)),
              value: _op.params[key] == true,
              onChanged: (v) => widget.onChange(_op.copyWith(params: {..._op.params, key: v}), true),
            );
        return [
          const Text('ဒီအချိန်ပိုင်းကို လှန်ပြမယ်။ စာသား/စာတန်းတွေ မလှန်ပါ (ဗီဒီယိုပုံပဲ လှန်တယ်)', style: TextStyle(fontSize: 12.5, color: DfColors.muted)),
          fl('ဘယ်-ညာ', Icons.flip, 'horizontal'),
          fl('အပေါ်-အောက်', Icons.swap_vert, 'vertical'),
        ];
      case TransformTool.freezeFrame:
        return [_slider('ရပ်မယ့်စက္ကန့်', 'hold', 3.0, 0.5, 15.0)];
      case TransformTool.motionGraphics:
        final k = _op.params['kind'] is String ? _op.params['kind'] as String : 'label';
        final shape = k == 'box' || k == 'circle' || k == 'spot' || k == 'blurBox';
        Widget flag(String label, String key, {bool defaultOn = false}) => SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(label, style: const TextStyle(fontSize: 13.5)),
              value: defaultOn ? _op.params[key] != false : _op.params[key] == true,
              onChanged: (v) => widget.onChange(_op.copyWith(params: {..._op.params, key: v}), true),
            );
        Widget swatches(List<int> cs) => Wrap(spacing: 8, children: [
              for (final c in cs)
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
            ]);
        Widget chip(String label, VoidCallback f, {bool on = false}) => ChoiceChip(label: Text(label, style: const TextStyle(fontSize: 12)), selected: on, onSelected: (_) => f());
        final hint = switch (k) {
          'frame' => 'ဗီဒီယိုပတ်ပတ်လည် ဘောင် — အချိန်ကို timeline မှာ ညှိပါ',
          'spot' => 'အလယ်ခလုတ်နဲ့ ရွှေ့၊ ထောင့်က အစက်နဲ့ အကျယ်ညှိ — ကျန်တာ မှောင်သွားမယ်',
          'box' || 'circle' => 'ဆွဲရွှေ့၊ ထောင့်က အစက်နဲ့ အရွယ်ညှိ',
          'blurBox' => 'ဆင်ဆာဖြတ်ချင်တဲ့ နေရာကို စတုဂံနဲ့ ဖုံးမှုန်မယ်။ ဆွဲရွှေ့၊ ထောင့်က အစက်နဲ့ ချုံ့ချဲ့။ (ကိုယ့်ဗီဒီယိုထဲက ထိလွယ်တဲ့ အပိုင်းအတွက်ပဲ — တခြားသူရဲ့ watermark/logo ဖုံးဖို့ မသုံးပါနဲ့)',
          'fade' => 'ဗီဒီယိုစမှာ Fade in၊ အဆုံးမှာ Fade out၊ အလယ်မှာ Flash/Dip သုံးပါ',
          'vignette' => 'ဘေးအနားတွေ မှောင်စေတယ် (ရုပ်ရှင်ပုံစံ)',
          'tint' => 'အရောင်တစ်မျိုး ဗီဒီယိုပေါ် ဖော့ဖော့ တင်တယ် (နွေး/အေး/sepia)',
          'bars' => 'အပေါ်အောက် အမည်းတန်း (cinema)',
          'shade' => 'အစွန်းတစ်ဖက်ကို မှောင်စေပြီး စာတန်း ပိုဖတ်လို့ရစေတယ်',
          _ => 'Preview ပေါ်မှာ ဆွဲရွှေ့လို့ရတယ်',
        };
        return [
          if (k == 'label')
            TextField(
              controller: _text,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'စာသား / emoji'),
              onChanged: (v) => widget.onChange(_op.copyWith(params: {..._op.params, 'text': v}), true),
            ),
          if (k == 'label') flag('အရောင်ခြယ် နောက်ခံ (ခရမ်း→ပန်း)', 'grad'),
          Text(hint, style: const TextStyle(fontSize: 12.5, color: DfColors.muted)),
          if (k == 'frame') _frameStrip(),
          if (k == 'fade') ...[
            Wrap(spacing: 6, children: [
              chip('Fade in', () => widget.onChange(_op.copyWith(params: {..._op.params, 'dir': 'in'}), true), on: _op.params['dir'] == 'in'),
              chip('Fade out', () => widget.onChange(_op.copyWith(params: {..._op.params, 'dir': 'out'}), true), on: _op.params['dir'] == 'out'),
              chip('Flash / Dip', () => widget.onChange(_op.copyWith(params: {..._op.params, 'dir': 'dip'}), true), on: _op.params['dir'] != 'in' && _op.params['dir'] != 'out'),
            ]),
            _durationSlider(),
            swatches(const [0xFF000000, 0xFFFFFFFF, 0xFFFF1744]),
          ],
          if (k == 'vignette') _slider('အား', 'size', 0.6, 0.1, 0.95),
          if (k == 'tint') ...[
            Wrap(spacing: 6, runSpacing: 2, children: [
              chip('နွေး', () => widget.onChange(_op.copyWith(params: {..._op.params, 'color': 0xFFFF9800, 'size': 0.2}), true)),
              chip('အေး', () => widget.onChange(_op.copyWith(params: {..._op.params, 'color': 0xFF2196F3, 'size': 0.2}), true)),
              chip('Sepia', () => widget.onChange(_op.copyWith(params: {..._op.params, 'color': 0xFF8D6E63, 'size': 0.35}), true)),
              chip('အနီ', () => widget.onChange(_op.copyWith(params: {..._op.params, 'color': 0xFFFF1744, 'size': 0.2}), true)),
              chip('အစိမ်း', () => widget.onChange(_op.copyWith(params: {..._op.params, 'color': 0xFF00C853, 'size': 0.2}), true)),
            ]),
            _slider('အားပြင်း', 'size', 0.2, 0.03, 0.6),
            swatches(const [0xFFFF9800, 0xFF2196F3, 0xFF8D6E63, 0xFFFF1744, 0xFF00C853, 0xFF9C27B0, 0xFFFFFFFF]),
          ],
          if (k == 'bars') _slider('တန်းအမြင့်', 'size', 0.1, 0.03, 0.3),
          if (k == 'shade') ...[
            _slider('ပါတဲ့အကျယ်', 'size', 0.4, 0.1, 0.9),
            flag('အပေါ်ကနေ (ပိတ် = အောက်ကနေ)', 'top'),
          ],
          if (k == 'frame')
            _slider('အထူ', 'size', 0.012, 0.005, 0.05)
          else if (shape)
            _slider('အကျယ်', 'size', 0.4, 0.05, 0.95)
          else if (k == 'label' || k == 'arrow')
            _slider('အရွယ်', 'size', 0.06, 0.03, 0.4),
          if (shape) _slider('အမြင့်', 'ar', 0.5, 0.1, 3.0),
          if (k == 'blurBox') _slider('မှုန်ပမာဏ', 'strength', 25, 5, 60),
          if (k == 'blurBox') flag('ဘောင်လိုင်း ပြ (ပိတ် = မပြ၊ ရွေးထားချိန်ပဲ မြင်ရ)', 'edge', defaultOn: true),
          if (k == 'arrow') _slider('လှည့်', 'angle', 0, 0, 359, whole: true),
          if (k == 'box' || k == 'circle') flag('အတွင်း ဖြည့် (marker)', 'fill'),
          if (k == 'frame' && _op.params['tpl'] is! int) flag('သက်တန့်ရောင်စုံ', 'grad'),
          if (k == 'spot') flag('ဘဲဥပုံ (ပိတ် = လေးထောင့်)', 'round', defaultOn: true),
          if (k == 'label' || k == 'arrow' || k == 'box' || k == 'circle' || (k == 'frame' && _frameUsesColor())) swatches(_colors),
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
