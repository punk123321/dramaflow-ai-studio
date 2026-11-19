import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../core/transformative_plan.dart';
import '../platform/audio_channel.dart';

/// Adds a new operation (starts approved, because the user made it) or edits
/// an existing one ([initial]; its status is kept). Times are on the ORIGINAL
/// video. [startSec]/[endSec] pre-fill a new operation, for example with the
/// current preview position.
class TeOpDialog extends StatefulWidget {
  const TeOpDialog({super.key, this.initial, this.startSec, this.endSec, this.tool});

  /// Tool pre-selected for a NEW operation.
  final TransformTool? tool;
  final TransformOp? initial;
  final double? startSec;
  final double? endSec;

  @override
  State<TeOpDialog> createState() => _TeOpDialogState();
}

class _TeOpDialogState extends State<TeOpDialog> {
  TransformTool _tool = TransformTool.freezeFrame;
  final _from = TextEditingController(text: '0');
  final _to = TextEditingController(text: '5');
  final _note = TextEditingController();
  double _zoom = 1.5;
  double _hold = 3.0;
  final _second = TextEditingController(text: '0');
  String _layout = 'leftRight';
  double _bright = 0.15;
  double _contrast = 0.0;
  String? _imgPath;
  double _isize = 0.25;
  AudioFile? _sound;
  double _svol = 0.8;
  String _kind = 'label';
  final _text = TextEditingController();
  double _mx = 0.5;
  double _my = 0.15;
  double _msize = 0.06;
  double _angle = 0;
  bool _bg = true;
  int _color = 0xFFFFEB3B;
  static const _colors = [0xFFFFFFFF, 0xFFFFEB3B, 0xFFFF5252, 0xFF69F0AE, 0xFF40C4FF];
  double _cx = 0.5;
  double _cy = 0.5;
  String? _err;

  /// Parameters of a box / circle / spot / frame effect. This dialog cannot
  /// edit those (use the sliders under the preview), so they are kept as they are.
  Map<String, Object?>? _keep;

  static String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  void initState() {
    super.initState();
    final o = widget.initial;
    if (o != null) {
      _tool = o.tool;
      _from.text = _num(o.startMs / 1000);
      _to.text = _num(o.endMs / 1000);
      _note.text = o.note;
      final p = o.params;
      double? d(String k) => p[k] is num ? (p[k] as num).toDouble() : null;
      switch (o.tool) {
        case TransformTool.freezeFrame:
          _hold = (d('hold') ?? _hold).clamp(0.5, 15.0).toDouble();
        case TransformTool.colorGrade:
          _bright = (d('brightness') ?? 0).clamp(-0.6, 0.6).toDouble();
          _contrast = (d('contrast') ?? 0).clamp(-0.6, 0.6).toDouble();
        case TransformTool.cropReframe:
          _zoom = (d('zoom') ?? _zoom).clamp(1.0, 3.0).toDouble();
          _cx = (d('cx') ?? 0.5).clamp(0.0, 1.0).toDouble();
          _cy = (d('cy') ?? 0.5).clamp(0.0, 1.0).toDouble();
        case TransformTool.splitScreen:
          _second.text = _num(d('second') ?? 0);
          _layout = p['layout'] == 'topBottom' ? 'topBottom' : 'leftRight';
        case TransformTool.motionGraphics:
          if (const {'box', 'circle', 'spot', 'frame'}.contains(p['kind'])) _keep = {...p};
          _kind = p['kind'] == 'arrow' ? 'arrow' : 'label';
          _text.text = p['text'] is String ? p['text'] as String : '';
          _mx = (d('x') ?? _mx).clamp(0.0, 1.0).toDouble();
          _my = (d('y') ?? _my).clamp(0.0, 1.0).toDouble();
          _msize = (d('size') ?? _msize).clamp(0.03, 0.4).toDouble();
          _angle = (d('angle') ?? 0).clamp(0.0, 359.0).toDouble();
          _bg = p['bg'] != false;
          if (p['color'] is int) _color = p['color'] as int;
        case TransformTool.soundDesign:
          final src = p['src'];
          final dur = p['dur'];
          if (src is String && dur is int) {
            _sound = AudioFile(source: src, durationMs: dur, sizeBytes: 0, name: p['name'] is String ? p['name'] as String : '');
          }
          _svol = (d('vol') ?? _svol).clamp(0.05, 1.0).toDouble();
        case TransformTool.pictureInPicture:
          _imgPath = p['path'] is String ? p['path'] as String : null;
          _mx = (d('x') ?? _mx).clamp(0.0, 1.0).toDouble();
          _my = (d('y') ?? _my).clamp(0.0, 1.0).toDouble();
          _isize = (d('size') ?? _isize).clamp(0.05, 0.6).toDouble();
        default:
          break;
      }
    } else {
      final t = widget.tool;
      if (t != null) _tool = t;
      final s = widget.startSec;
      if (s != null) {
        _from.text = _num(s);
        _to.text = _num(widget.endSec ?? s + 5);
      }
    }
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    _note.dispose();
    _text.dispose();
    _second.dispose();
    super.dispose();
  }

  bool get _point => _tool == TransformTool.freezeFrame || _tool == TransformTool.soundDesign;

  Future<void> _pickImage() async {
    try {
      final f = await AudioChannel.pickImage();
      if (f != null) setState(() => _imgPath = f);
    } catch (e) {
      setState(() => _err = 'ပုံ ရွေးမရပါ: $e');
    }
  }

  Future<void> _pickSound() async {
    try {
      final f = await AudioChannel.pickAudio();
      if (f != null) setState(() => _sound = f);
    } catch (e) {
      setState(() => _err = 'အသံဖိုင် ရွေးမရပါ: $e');
    }
  }

  Map<String, Object?> _params() {
    double r(double v) => double.parse(v.toStringAsFixed(2));
    switch (_tool) {
      case TransformTool.freezeFrame:
        return {'hold': double.parse(_hold.toStringAsFixed(1))};
      case TransformTool.pictureInPicture:
        final f = _imgPath;
        return f == null ? const {} : {'kind': 'image', 'path': f, 'x': r(_mx), 'y': r(_my), 'size': r(_isize), 'color': 0xFFFFFFFF};
      case TransformTool.soundDesign:
        final f = _sound;
        return f == null ? const {} : {'src': f.source, 'name': f.name, 'dur': f.durationMs, 'vol': r(_svol)};
      case TransformTool.splitScreen:
        return {'second': double.tryParse(_second.text.trim()) ?? -1, 'layout': _layout};
      case TransformTool.colorGrade:
        return {'brightness': r(_bright), 'contrast': r(_contrast)};
      case TransformTool.cropReframe:
        return {'zoom': r(_zoom), 'cx': r(_cx), 'cy': r(_cy)};
      case TransformTool.motionGraphics:
        final keep = _keep;
        if (keep != null) return keep;
        return {
          // Keeps extra values such as the colourful background.
          ...?widget.initial?.params,
          'kind': _kind,
          'x': r(_mx),
          'y': r(_my),
          'size': r(_msize),
          'color': _color,
          if (_kind == 'label') 'text': _text.text.trim(),
          if (_kind == 'label') 'bg': _bg,
          if (_kind == 'arrow') 'angle': _angle.roundToDouble(),
        };
      default:
        return const {};
    }
  }

  void _ok() {
    final a = double.tryParse(_from.text.trim());
    final b = _point ? a : double.tryParse(_to.text.trim());
    if (_tool == TransformTool.pictureInPicture && _imgPath == null) {
      setState(() => _err = 'ပုံ အရင်ရွေးပါ');
      return;
    }
    if (_tool == TransformTool.soundDesign && _sound == null) {
      setState(() => _err = 'အသံဖိုင် အရင်ရွေးပါ');
      return;
    }
    if (_tool == TransformTool.motionGraphics && _keep == null && _kind == 'label' && _text.text.trim().isEmpty) {
      setState(() => _err = 'Label စာသား ရေးပါ');
      return;
    }
    if (a == null || b == null || a < 0 || b < a) {
      setState(() => _err = 'စက္ကန့် မမှန်ပါ (စချိန် ≥ 0၊ ဆုံးချိန် ≥ စချိန်)');
      return;
    }
    final old = widget.initial;
    if (old != null) {
      Navigator.pop(
        context,
        old.copyWith(startMs: (a * 1000).round(), endMs: (b * 1000).round(), note: _note.text.trim(), params: _params()),
      );
      return;
    }
    Navigator.pop(
      context,
      TransformOp(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        tool: _tool,
        startMs: (a * 1000).round(),
        endMs: (b * 1000).round(),
        note: _note.text.trim(),
        params: _params(),
        status: OpStatus.approved,
      ),
    );
  }

  Widget _slider(String label, double v, double min, double max, void Function(double) set) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Slider(value: v, min: min, max: max, onChanged: (x) => setState(() => set(x))),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'လုပ်ဆောင်ချက် ထည့်မယ်' : 'လုပ်ဆောင်ချက် ပြင်မယ်'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<TransformTool>(
              initialValue: _tool,
              isExpanded: true,
              items: [for (final t in TransformTool.values) DropdownMenuItem(value: t, child: Text(t.title))],
              onChanged: widget.initial != null ? null : (v) => setState(() => _tool = v ?? _tool),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _from,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: _tool == TransformTool.freezeFrame ? 'ရပ်မယ့် အချိန် (စက္ကန့်)' : (_tool == TransformTool.soundDesign ? 'အသံစမယ့် အချိန် (စက္ကန့်)' : 'စချိန် (စက္ကန့်)')),
                  ),
                ),
                if (!_point) const SizedBox(width: 8),
                if (!_point)
                Expanded(
                  child: TextField(
                    controller: _to,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'ဆုံးချိန် (စက္ကန့်)'),
                  ),
                ),
              ],
            ),
            if (_tool == TransformTool.splitScreen) ...[
              const SizedBox(height: 4),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'leftRight', label: Text('ဘယ်|ညာ')),
                  ButtonSegment(value: 'topBottom', label: Text('အပေါ်|အောက်')),
                ],
                selected: {_layout},
                onSelectionChanged: (v) => setState(() => _layout = v.first),
              ),
              TextField(
                controller: _second,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'ဒုတိယပိုင်း စမယ့် အချိန် (မူရင်းဗီဒီယို၊ စက္ကန့်)'),
              ),
              const Text(
                'ပထမပိုင်းက edit ကို ဆက်ပြမယ်၊ ဒုတိယပိုင်းက မူရင်းဗီဒီယိုရဲ့ တခြားအချိန်ကနေ တစ်ပြိုင်နက် ပြမယ်။ ပုံနှစ်ခုက တစ်ဝက်အရွယ်ဖြစ်မယ်။ စမ်းသပ်ဆဲ — ဖုန်းမှာ မစမ်းရသေးပါ။ တခြားဗီဒီယိုဖိုင် ထည့်တာ မရသေးပါ။',
                style: TextStyle(color: DfColors.muted, fontSize: 12),
              ),
            ],
            if (_tool == TransformTool.colorGrade) ...[
              _slider('အလင်း ${(_bright * 100).round()}% (အနှုတ် = မှောင်)', _bright, -0.6, 0.6, (v) => _bright = v),
              _slider('Contrast ${(_contrast * 100).round()}%', _contrast, -0.6, 0.6, (v) => _contrast = v),
              const Text(
                'ဒါက ပုံသဏ္ဍာန်/mood ညှိဖို့ပါ (ဥပမာ ဇာတ်ရှိန်မြင့်တဲ့ နေရာကို မှောင်စေ၊ အလင်းဆွဲ)။ ပလက်ဖောင်း၏ မူပိုင်စစ်ဆေးမှုကို ရှောင်ဖို့ မဟုတ်ပါ၊ အဲဒီအတွက် မသုံးပါနဲ့။',
                style: TextStyle(color: DfColors.muted, fontSize: 12),
              ),
            ],
            if (_tool == TransformTool.pictureInPicture) ...[
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.image_outlined, size: 18),
                label: Text(_imgPath == null ? 'ပုံ ရွေးမယ်' : 'ပုံ ရွေးပြီး (ပြန်ရွေးလို့ရ)'),
              ),
              _slider('ဘယ်-ညာ ${(_mx * 100).round()}%', _mx, 0.0, 1.0, (v) => _mx = v),
              _slider('အပေါ်-အောက် ${(_my * 100).round()}%', _my, 0.0, 1.0, (v) => _my = v),
              _slider('အကျယ် ${(_isize * 100).round()}% (ဗီဒီယိုအကျယ်)', _isize, 0.05, 0.6, (v) => _isize = v),
              const Text(
                'ပုံတစ်ပုံကို ဗီဒီယိုပေါ် ထပ်ပြမယ်။ ဒုတိယဗီဒီယိုကို ထပ်တာ မရသေးပါ။ ကိုယ်ပိုင်/အသုံးပြုခွင့်ရှိတဲ့ ပုံသာ သုံးပါ။',
                style: TextStyle(color: DfColors.muted, fontSize: 12),
              ),
            ],
            if (_tool == TransformTool.soundDesign) ...[
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: _pickSound,
                icon: const Icon(Icons.audiotrack, size: 18),
                label: Text(_sound == null ? 'အသံဖိုင် ရွေးမယ်' : '${_sound!.name} · ${(_sound!.durationMs / 1000).toStringAsFixed(1)}s'),
              ),
              _slider('အသံ ${(_svol * 100).round()}%', _svol, 0.05, 1.0, (v) => _svol = v),
              const Text(
                'ကိုယ့်ဖုန်းထဲက အသံဖိုင်ကို သုံးမယ် (မူရင်းဖိုင် မပြောင်း)။ အချိန်ကို မူရင်းဗီဒီယိုအပေါ် တိုင်းထားတယ်။ အသံက ဗီဒီယိုအဆုံး မကျော်ရပါ။ ကိုယ်ပိုင်/အသုံးပြုခွင့်ရှိတဲ့ အသံသာ သုံးပါ။',
                style: TextStyle(color: DfColors.muted, fontSize: 12),
              ),
            ],
            if (_tool == TransformTool.motionGraphics && _keep != null)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'ဒီ effect ရဲ့ အရွယ်/အရောင်ကို preview အောက်က slider နဲ့ ညှိပါ။ ဒီမှာ အချိန်နဲ့ မှတ်ချက်ပဲ ပြင်လို့ရတယ်။',
                  style: TextStyle(color: DfColors.muted, fontSize: 12),
                ),
              ),
            if (_tool == TransformTool.motionGraphics && _keep == null) ...[
              const SizedBox(height: 4),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'label', label: Text('စာသား')),
                  ButtonSegment(value: 'arrow', label: Text('မြား')),
                ],
                selected: {_kind},
                onSelectionChanged: (v) => setState(() => _kind = v.first),
              ),
              if (_kind == 'label')
                TextField(
                  controller: _text,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Label စာသား'),
                ),
              _slider('ဘယ်-ညာ ${(_mx * 100).round()}%', _mx, 0.0, 1.0, (v) => _mx = v),
              _slider('အပေါ်-အောက် ${(_my * 100).round()}%', _my, 0.0, 1.0, (v) => _my = v),
              _slider('အရွယ်အစား ${(_msize * 100).round()}%', _msize, 0.03, 0.4, (v) => _msize = v),
              if (_kind == 'arrow') _slider('လှည့်ပုံ ${_angle.round()}° (0=ညာ၊ 90=အောက်)', _angle, 0, 359, (v) => _angle = v),
              if (_kind == 'label')
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('နောက်ခံ အမည်း', style: TextStyle(fontSize: 14)),
                  value: _bg,
                  onChanged: (v) => setState(() => _bg = v),
                ),
              Wrap(
                spacing: 8,
                children: [
                  for (final c in _colors)
                    GestureDetector(
                      onTap: () => setState(() => _color = c),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: Border.all(color: _color == c ? DfColors.accent : DfColors.line, width: _color == c ? 3 : 1),
                        ),
                      ),
                    ),
                ],
              ),
              const Text(
                'အချိန်ကို မူရင်းဗီဒီယိုအပေါ် တိုင်းထားတယ် — အပိုင်းဖြတ်၊ ရှေ့နောက်ရွှေ့ထားရင်လည်း အလိုက်သင့် လိုက်မယ်။',
                style: TextStyle(color: DfColors.muted, fontSize: 12),
              ),
            ],
            if (_tool == TransformTool.freezeFrame) ...[
              _slider('ရပ်မယ့် ကြာချိန် ${_hold.toStringAsFixed(1)} စက္ကန့်', _hold, 0.5, 15.0, (v) => _hold = v),
              const Text(
                'စချိန်ကနေ ပုံတစ်ပုံ ရပ်ပြမယ်။ ရပ်တဲ့အချိန်ကြောင့် နောက်ပိုင်း အချိန်တွေ နောက်ကျမယ် — Render screen မှာ edit အချိန်ကို ပြမယ်။',
                style: TextStyle(color: DfColors.muted, fontSize: 12),
              ),
            ],
            if (_tool == TransformTool.cropReframe) ...[
              _slider('Zoom ×${_zoom.toStringAsFixed(2)}', _zoom, 1.0, 3.0, (v) => _zoom = v),
              _slider('ဘယ်-ညာ ${(_cx * 100).round()}%', _cx, 0.0, 1.0, (v) => _cx = v),
              _slider('အပေါ်-အောက် ${(_cy * 100).round()}%', _cy, 0.0, 1.0, (v) => _cy = v),
              const Text(
                'အစွန်းတွေမှာ အလွတ်မပေါ်အောင် နေရာကို အလိုအလျောက် ညှိမယ်။',
                style: TextStyle(color: DfColors.muted, fontSize: 12),
              ),
            ],
            TextField(controller: _note, decoration: const InputDecoration(labelText: 'မှတ်ချက်')),
            if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: const TextStyle(color: DfColors.danger))),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('မလုပ်တော့ဘူး')),
        FilledButton(onPressed: _ok, child: Text(widget.initial == null ? 'ထည့်မယ်' : 'သိမ်းမယ်')),
      ],
    );
  }
}

class TeReplyDialog extends StatefulWidget {
  const TeReplyDialog({super.key});

  @override
  State<TeReplyDialog> createState() => _TeReplyDialogState();
}

class _TeReplyDialogState extends State<TeReplyDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Gemini ပြန်ဖြေချက်'),
      content: TextField(
        controller: _c,
        minLines: 6,
        maxLines: 12,
        decoration: const InputDecoration(hintText: 'ဒီမှာ paste လုပ်ပါ', border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            final d = await Clipboard.getData('text/plain');
            if (d?.text != null) setState(() => _c.text = d!.text!);
          },
          child: const Text('Paste'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('မလုပ်တော့ဘူး')),
        FilledButton(onPressed: () => Navigator.pop(context, _c.text), child: const Text('စစ်ပြီး ထည့်မယ်')),
      ],
    );
  }
}
