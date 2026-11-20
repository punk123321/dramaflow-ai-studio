import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../core/te_preview.dart';
import '../core/theme.dart';
import '../core/transformative_plan.dart';

/// The video on the whole screen (landscape), with the filter, crop, blur and
/// flip of the effects applied. Texts, arrows, pictures and subtitles are not
/// drawn here; the render is the real result. It plays the same controller as
/// the editor, so play, pause and the playhead stay in step with it.
class TeFullscreenPage extends StatefulWidget {
  const TeFullscreenPage({super.key, required this.controller, required this.ops, required this.durMs});

  final VideoPlayerController controller;
  final List<TransformOp> ops;
  final int durMs;

  @override
  State<TeFullscreenPage> createState() => _TeFullscreenPageState();
}

class _TeFullscreenPageState extends State<TeFullscreenPage> {
  bool _bars = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  String _t(int ms) {
    final s = ms ~/ 1000;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Widget _video(VideoPlayerValue v) {
    final pos = v.position.inMilliseconds;
    final ops = widget.ops;
    Widget video = VideoPlayer(widget.controller);
    final look = previewLook(ops, pos);
    final crop = previewCrop(ops, pos);
    final blur = previewBlur(ops, pos);
    final flip = previewFlip(ops, pos);
    if (look != null) video = ColorFiltered(colorFilter: ColorFilter.matrix(lookMatrix(look)), child: video);
    if (crop != null) {
      video = FractionalTranslation(
        translation: Offset((0.5 - crop.cx) * crop.zoom, (0.5 - crop.cy) * crop.zoom),
        child: Transform.scale(scale: crop.zoom, child: video),
      );
    }
    if (blur != null) video = ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: blur * 0.6, sigmaY: blur * 0.6), child: video);
    if (flip != null) video = Transform.scale(scaleX: flip.h ? -1.0 : 1.0, scaleY: flip.v ? -1.0 : 1.0, child: video);
    return ClipRect(
      child: AspectRatio(aspectRatio: v.aspectRatio == 0 ? 16 / 9 : v.aspectRatio, child: video),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _bars = !_bars),
        child: ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: c,
          builder: (context, v, _) {
            final dur = v.duration.inMilliseconds > 0 ? v.duration.inMilliseconds : widget.durMs;
            final pos = v.position.inMilliseconds.clamp(0, dur > 0 ? dur : 1).toInt();
            return Stack(fit: StackFit.expand, children: [
              Center(child: _video(v)),
              if (_bars)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 18, 12, 8),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xCC000000)]),
                    ),
                    child: Row(children: [
                      IconButton(
                        icon: Icon(v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 30),
                        onPressed: () => v.isPlaying ? c.pause() : c.play(),
                      ),
                      Text(_t(pos), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: pos.toDouble(),
                          max: dur > 0 ? dur.toDouble() : 1,
                          activeColor: DfColors.accent,
                          onChanged: dur > 0 ? (x) => c.seekTo(Duration(milliseconds: x.round())) : null,
                        ),
                      ),
                      Text(_t(dur), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      IconButton(
                        icon: const Icon(Icons.fullscreen_exit_rounded, color: Colors.white),
                        tooltip: 'ပြန်ထွက်',
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ]),
                  ),
                ),
              if (_bars)
                const Positioned(
                  top: 8,
                  left: 16,
                  child: Text('Filter / Crop / Blur / Flip ပဲ ပြတယ် · စာသား၊ overlay မပါ', style: TextStyle(color: Colors.white54, fontSize: 11)),
                ),
            ]);
          },
        ),
      ),
    );
  }
}
