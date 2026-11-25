import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/srt.dart';
import '../core/te_frames.dart';
import '../core/te_preview.dart';
import '../core/theme.dart';
import '../core/timeline.dart';
import '../core/timeline_window.dart';
import '../core/transformative_plan.dart';

/// Multi-track timeline on the ORIGINAL video's time: ruler, the video pieces
/// that are kept, subtitles, and one block per effect (overlapping effects
/// sit on separate rows). Tap or drag the ruler to move the playhead, tap a
/// block to select it. It only shows and selects; values are edited in the
/// panel under the preview.
class TeTimeline extends StatefulWidget {
  const TeTimeline({
    super.key,
    required this.durMs,
    required this.posMs,
    required this.playing,
    required this.ops,
    required this.subs,
    required this.pieces,
    required this.selectedId,
    required this.onSeek,
    required this.onSelect,
    this.onResize,
  });

  final int durMs;
  final int posMs;
  final bool playing;
  final List<TransformOp> ops;
  final List<SrtEntry> subs;
  final List<VideoPiece> pieces;
  final String? selectedId;
  final ValueChanged<int> onSeek;
  final ValueChanged<String> onSelect;

  /// Called while an edge of the selected effect is dragged (`save` false) and
  /// once when the finger lifts (`save` true).
  final void Function(TransformOp op, int startMs, int endMs, bool save)? onResize;

  @override
  State<TeTimeline> createState() => _TeTimelineState();
}

class _TeTimelineState extends State<TeTimeline> {
  final _sc = ScrollController();
  double _pps = 30; // pixels per second

  // Only the subtitle blocks near the visible part are built. The window is one
  // screen wide on each side; scrolling more than half a screen redraws it.
  double _viewW = 360;
  double _winOffset = 0;

  static const _ruler = 22.0;
  static const _minLenMs = 200;
  static const _handle = 22.0;

  // State of an edge drag.
  int _dragS = 0;
  int _dragE = 0;
  double _acc = 0;

  void _edge(TransformOp o, bool left, double dx, bool save) {
    final cb = widget.onResize;
    if (cb == null) return;
    final dur = widget.durMs > 0 ? widget.durMs : o.endMs;
    _acc += dx;
    final dMs = (_acc / _pps * 1000).round();
    var s = _dragS;
    var e = _dragE;
    if (left) {
      s = (_dragS + dMs).clamp(0, _dragE - _minLenMs);
    } else {
      e = (_dragE + dMs).clamp(_dragS + _minLenMs, math.max(dur, _dragS + _minLenMs));
    }
    cb(o, s, e, save);
  }

  /// Two grips on the edges of the selected effect; drag to make it shorter or longer.
  List<Widget> _grips(TransformOp o, double top) {
    if (widget.onResize == null || o.endMs - o.startMs < _minLenMs) return const [];
    final l = o.startMs / 1000 * _pps;
    final r = math.max(l + 30, o.endMs / 1000 * _pps);
    Widget grip(bool left) => Positioned(
          left: (left ? l : r) - _handle / 2,
          top: top,
          width: _handle,
          height: _row - 4,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) {
              _dragS = o.startMs;
              _dragE = o.endMs;
              _acc = 0;
            },
            onHorizontalDragUpdate: (d) => _edge(o, left, d.delta.dx, false),
            onHorizontalDragEnd: (_) => _edge(o, left, 0, true),
            child: Center(
              child: Container(
                width: 6,
                height: _row - 10,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(3), boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 3)]),
              ),
            ),
          ),
        );
    return [grip(true), grip(false)];
  }
  static const _row = 28.0;

  @override
  void initState() {
    super.initState();
    _sc.addListener(_onScroll);
  }

  void _onScroll() {
    if (!mounted || !_sc.hasClients) return;
    if ((_sc.offset - _winOffset).abs() > _viewW * 0.5) setState(() {});
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TeTimeline old) {
    super.didUpdateWidget(old);
    if (widget.playing && widget.posMs != old.posMs) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _follow());
    }
  }

  void _follow() {
    if (!mounted || !_sc.hasClients) return;
    final x = widget.posMs / 1000 * _pps;
    final vp = _sc.position.viewportDimension;
    if (x < _sc.offset || x > _sc.offset + vp - 30) {
      _sc.jumpTo((x - 40).clamp(0.0, _sc.position.maxScrollExtent).toDouble());
    }
  }

  void _seekX(double x) => widget.onSeek((x / _pps * 1000).round().clamp(0, widget.durMs).toInt());

  static Color _color(TransformTool t) => switch (t) {
        TransformTool.motionGraphics => const Color(0xFFFF9F43),
        TransformTool.cropReframe => const Color(0xFF14B8A6),
        TransformTool.colorGrade => const Color(0xFFE0B400),
        TransformTool.freezeFrame => const Color(0xFF5B8CFF),
        TransformTool.smartCut => const Color(0xFFE5484D),
        TransformTool.speedChange => const Color(0xFFB36BFF),
        TransformTool.blur => const Color(0xFF7C8DB5),
        TransformTool.mirrorFlip => const Color(0xFF9B7EDE),
        TransformTool.pictureInPicture => const Color(0xFFFF6B9D),
        TransformTool.soundDesign => const Color(0xFF3DDC84),
        TransformTool.splitScreen => const Color(0xFF22B8CF),
        _ => const Color(0xFF8E9AAF),
      };

  static String _short(TransformOp o) {
    switch (o.tool) {
      case TransformTool.motionGraphics:
        final t = o.params['text'];
        return switch (o.params['kind']) {
          'arrow' => '➜',
          'box' => 'Box',
          'circle' => 'Circle',
          'spot' => 'Spot',
          'frame' => (o.params['tpl'] is int ? frameTemplateById(o.params['tpl'] as int)?.name : null) ?? 'Border',
          'fade' => o.params['dir'] == 'in' ? 'Fade in' : (o.params['dir'] == 'out' ? 'Fade out' : 'Flash/Dip'),
          'vignette' => 'Vignette',
          'tint' => 'Tint',
          'bars' => 'Bars',
          'shade' => 'Shade',
          'blurBox' => 'Censor',
          _ => (t is String && t.isNotEmpty ? t : 'စာသား'),
        };
      case TransformTool.cropReframe:
        final z = o.params['zoom'];
        return z is num ? 'Zoom ×${z.toStringAsFixed(1)}' : 'Zoom';
      case TransformTool.colorGrade:
        return 'Filter';
      case TransformTool.speedChange:
        final sp = o.params['speed'];
        return sp is num ? 'Speed ×${sp.toStringAsFixed(sp == sp.roundToDouble() ? 0 : 2)}' : 'Speed';
      case TransformTool.blur:
        final bs = o.params['strength'];
        return bs is num ? 'Blur ${bs.toStringAsFixed(0)}' : 'Blur';
      case TransformTool.mirrorFlip:
        final h = o.params['horizontal'] == true;
        final v = o.params['vertical'] == true;
        return h && v ? 'Flip ↔↕' : (v ? 'Flip ↕' : 'Flip ↔');
      case TransformTool.freezeFrame:
        return 'Freeze';
      case TransformTool.smartCut:
        return 'Cut';
      case TransformTool.pictureInPicture:
        return 'Picture';
      case TransformTool.soundDesign:
        final n = o.params['name'];
        return n is String && n.isNotEmpty ? n : 'Sound';
      case TransformTool.splitScreen:
        return 'Split';
      default:
        return o.tool.title;
    }
  }

  int _tickStep() {
    for (final s in const [1, 2, 5, 10, 15, 30, 60, 120, 300]) {
      if (s * _pps >= 56) return s;
    }
    return 600;
  }

  Widget _block({required double left, required double width, required double top, required Color color, required String label, VoidCallback? onTap, bool selected = false, double opacity = 1, Color textColor = Colors.white}) {
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: _row - 4,
      child: IgnorePointer(
        ignoring: onTap == null,
        child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: opacity,
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
              border: selected ? Border.all(color: Colors.white, width: 2) : null,
            ),
            child: Text(label, maxLines: 1, overflow: TextOverflow.clip, style: TextStyle(fontSize: 11, color: textColor, fontWeight: FontWeight.w600)),
          ),
        ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dur = widget.durMs > 0 ? widget.durMs : 1000;
    final lanes = assignLanes(widget.ops);
    final base = _ruler + _row + _row;
    final height = base + lanes.count * _row + 6;
    final step = _tickStep();
    final secs = dur / 1000;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: DfGradients.glass,
        color: DfColors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DfColors.glassEdge),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
          child: Row(children: [
            const Text('Timeline', style: TextStyle(fontWeight: FontWeight.w600, color: DfColors.accent)),
            const Spacer(),
            IconButton(visualDensity: VisualDensity.compact, tooltip: 'ချုံ့', icon: const Icon(Icons.zoom_out, size: 20), onPressed: () => setState(() => _pps = math.max(8, _pps / 1.5))),
            IconButton(visualDensity: VisualDensity.compact, tooltip: 'ချဲ့', icon: const Icon(Icons.zoom_in, size: 20), onPressed: () => setState(() => _pps = math.min(160, _pps * 1.5))),
          ]),
        ),
        LayoutBuilder(builder: (ctx, bc) {
          final width = math.max(secs * _pps + 40, bc.maxWidth);
          _viewW = bc.maxWidth;
          _winOffset = _sc.hasClients ? _sc.offset : 0;
          final subFrom = ((_winOffset - _viewW) / _pps * 1000).floor();
          final subTo = ((_winOffset + 2 * _viewW) / _pps * 1000).ceil();
          return SizedBox(
            height: height,
            child: SingleChildScrollView(
              controller: _sc,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                height: height,
                child: Stack(children: [
                  // Tap on an empty place moves the playhead.
                  Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTapDown: (d) => _seekX(d.localPosition.dx))),
                  // Ruler: tap or drag.
                  Positioned(
                    left: 0,
                    top: 0,
                    width: width,
                    height: _ruler,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) => _seekX(d.localPosition.dx),
                      onHorizontalDragUpdate: (d) => _seekX(d.localPosition.dx),
                      child: Stack(children: [
                        for (var s = 0; s <= secs; s += step)
                          Positioned(
                            left: s * _pps + 3,
                            top: 3,
                            child: Text('${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 10, color: DfColors.muted)),
                          ),
                        for (var s = 0; s <= secs; s += step)
                          Positioned(left: s * _pps, top: 14, width: 1, height: 8, child: const ColoredBox(color: DfColors.line)),
                      ]),
                    ),
                  ),
                  // Video track: the pieces that are kept.
                  Positioned(left: 0, top: _ruler + 2, width: secs * _pps, height: _row - 4, child: DecoratedBox(decoration: BoxDecoration(color: DfColors.raise, borderRadius: BorderRadius.circular(6)))),
                  if (widget.pieces.isEmpty)
                    _block(left: 0, width: secs * _pps, top: _ruler + 2, color: const Color(0xFF2E6F8E), label: 'Video')
                  else
                    for (var i = 0; i < widget.pieces.length; i++)
                      if (!widget.pieces[i].freeze)
                        _block(
                          left: widget.pieces[i].startMs / 1000 * _pps,
                          width: math.max(4, (widget.pieces[i].endMs - widget.pieces[i].startMs) / 1000 * _pps),
                          top: _ruler + 2,
                          color: const Color(0xFF2E6F8E),
                          label: 'Video ${i + 1}',
                        ),
                  // Subtitle track.
                  for (final e in subsInWindow(widget.subs, subFrom, subTo))
                    _block(
                      left: e.startMs / 1000 * _pps,
                      width: math.max(4, (e.endMs - e.startMs) / 1000 * _pps),
                      top: _ruler + _row + 2,
                      color: const Color(0xFF5B3BE0),
                      label: e.text.replaceAll('\n', ' '),
                    ),
                  // Effect rows.
                  for (final o in widget.ops)
                    _block(
                      left: o.startMs / 1000 * _pps,
                      width: math.max(30, (o.endMs - o.startMs) / 1000 * _pps),
                      top: base + (lanes.lane[o.id] ?? 0) * _row + 2,
                      color: _color(o.tool),
                      label: _short(o),
                      selected: widget.selectedId == o.id,
                      opacity: o.status == OpStatus.approved ? 1 : (o.status == OpStatus.proposed ? 0.6 : 0.3),
                      textColor: o.tool == TransformTool.colorGrade ? Colors.black : Colors.white,
                      onTap: () {
                        widget.onSelect(o.id);
                        widget.onSeek(o.startMs);
                      },
                    ),
                  // Edge grips of the selected effect.
                  for (final o in widget.ops)
                    if (widget.selectedId == o.id) ..._grips(o, base + (lanes.lane[o.id] ?? 0) * _row + 2),
                  // Playhead.
                  Positioned(
                    left: widget.posMs / 1000 * _pps - 1,
                    top: 0,
                    bottom: 0,
                    width: 2,
                    child: const IgnorePointer(child: ColoredBox(color: Colors.white)),
                  ),
                ]),
              ),
            ),
          );
        }),
      ]),
    );
  }
}
