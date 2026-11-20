import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/stage.dart';
import '../core/theme.dart';
import '../data/project.dart';

/// Small drama "poster": the first character of the drama title on a gradient.
class Poster extends StatelessWidget {
  const Poster({super.key, required this.title, this.width = 44, this.height = 58});

  final String title;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = title.trim();
    final first = t.isEmpty ? '?' : t.characters.first;
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DfColors.line),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3B2A6E), Color(0xFF0F1D4A), Color(0xFF7A2A5A)],
        ),
      ),
      child: Text(first, style: TextStyle(fontSize: width * 0.42, color: Colors.white)),
    );
  }
}

/// Six segments, one per stage, filled in the stage's own color when done.
class StageBar extends StatelessWidget {
  const StageBar({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final s in Stage.values)
          Expanded(
            child: Container(
              height: 6,
              margin: EdgeInsets.only(right: s == Stage.save ? 0 : 4),
              decoration: BoxDecoration(
                color: project.isDone(s) ? s.color : DfColors.line,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
      ],
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Row(children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(gradient: DfGradients.aurora, borderRadius: BorderRadius.circular(4)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
      ]),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DfColors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DfColors.danger.withValues(alpha: 0.5)),
      ),
      child: Text(message, style: const TextStyle(color: DfColors.danger)),
    );
  }
}

/// The page background: the indigo gradient with three soft glows (violet,
/// cyan, pink) like an aurora. Drawn with gradients only, so it is cheap, and
/// opaque, so a page pushed over another page does not show it through.
class DfBackground extends StatelessWidget {
  const DfBackground({super.key, required this.child});

  final Widget child;

  static Widget _glow(Color c, double size, double alpha) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [c.withValues(alpha: alpha), c.withValues(alpha: 0)]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: DfGradients.page),
      child: Stack(children: [
        Positioned(left: -140, top: -120, child: _glow(DfColors.accent, 420, 0.34)),
        Positioned(right: -170, top: 230, child: _glow(DfColors.cyan, 380, 0.14)),
        Positioned(left: -150, bottom: -140, child: _glow(DfColors.pink, 400, 0.13)),
        Positioned.fill(child: child),
      ]),
    );
  }
}

/// Scaffold with the app's indigo page gradient behind it. The gradient is
/// opaque, so a page pushed over another page does not show it through.
class DfScaffold extends StatelessWidget {
  const DfScaffold({super.key, this.appBar, required this.body, this.floatingActionButton, this.bottomNavigationBar});

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) {
    return DfBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: appBar,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: bottomNavigationBar,
        body: body,
      ),
    );
  }
}

/// Wide violet gradient button, used for the main action of a page.
/// With `onPressed: null` it is shown dimmed and does nothing. It shrinks a
/// little while pressed and has a soft glow and a thin bright edge.
class GradientButton extends StatefulWidget {
  const GradientButton({super.key, required this.label, required this.icon, required this.onPressed});

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.onPressed != null;
    return Opacity(
      opacity: on ? 1 : 0.45,
      child: AnimatedScale(
        scale: _down && on ? 0.97 : 1,
        duration: const Duration(milliseconds: 110),
        child: GestureDetector(
          onTapDown: on ? (_) => setState(() => _down = true) : null,
          onTapUp: on ? (_) => setState(() => _down = false) : null,
          onTapCancel: on ? () => setState(() => _down = false) : null,
          child: Material(
            color: Colors.transparent,
            child: Ink(
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: DfGradients.primary,
                border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                boxShadow: on ? [BoxShadow(color: DfColors.accent.withValues(alpha: 0.42), blurRadius: 20, offset: const Offset(0, 8))] : null,
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: widget.onPressed,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(widget.icon, color: Colors.white),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rounded dark card used to group the parts of a studio page.
class DfCard extends StatelessWidget {
  const DfCard({super.key, required this.child, this.title, this.margin = const EdgeInsets.only(bottom: 12)});

  final Widget child;
  final String? title;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: DfGradients.glass,
        color: DfColors.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: DfColors.glassEdge),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(title!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          child,
        ],
      ),
    );
  }
}

/// One line of a checklist: green tick when [ok], grey circle otherwise.
class CheckLine extends StatelessWidget {
  const CheckLine(this.text, {super.key, required this.ok});

  final String text;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, size: 20, color: ok ? DfColors.ok : DfColors.muted),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}

/// Big circular progress with the percentage in the middle.
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.percent, this.size = 104});

  /// 0 means "no progress known yet" (the ring spins).
  final int percent;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: percent <= 0 ? null : percent / 100,
              strokeWidth: 10,
              strokeCap: StrokeCap.round,
              backgroundColor: DfColors.line,
              color: DfColors.ok,
            ),
          ),
          Text(percent <= 0 ? '…' : '$percent%', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// Long explanation that stays out of the way: one small line, tap to read it.
class InfoHint extends StatefulWidget {
  const InfoHint(this.text, {super.key, this.label = 'ရှင်းလင်းချက်'});

  final String text;
  final String label;

  @override
  State<InfoHint> createState() => _InfoHintState();
}

class _InfoHintState extends State<InfoHint> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _open = !_open),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.info_outline, size: 16, color: DfColors.muted),
                const SizedBox(width: 6),
                Text(widget.label, style: const TextStyle(color: DfColors.muted, fontSize: 12.5)),
                Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18, color: DfColors.muted),
              ],
            ),
            if (_open)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(widget.text, style: const TextStyle(color: DfColors.muted, fontSize: 12.5, height: 1.4)),
              ),
          ],
        ),
      ),
    );
  }
}

/// A frosted-glass panel: the page behind it is blurred. Use it for a few big
/// things (hero cards, sheets), not for every row of a long list.
class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = 24, this.blur = 18, this.tint});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [(tint ?? Colors.white).withValues(alpha: 0.16), (tint ?? Colors.white).withValues(alpha: 0.05)],
            ),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: DfColors.glassEdge),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A rounded square with a gradient of [color] and a soft glow, holding an icon.
class GlowChip extends StatelessWidget {
  const GlowChip({super.key, required this.icon, required this.color, this.size = 44});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        gradient: DfGradients.tile(color),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: size * 0.4, offset: Offset(0, size * 0.12))],
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.52),
    );
  }
}

/// Shrinks a little while it is pressed. Wrap tiles and chips in it.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.onTap, required this.child, this.radius = 22});

  final VoidCallback? onTap;
  final Widget child;
  final double radius;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _down ? 0.965 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: widget.child,
      ),
    );
  }
}

/// Fades and slides its child up when it first appears; later [index]es take
/// a little longer, so a grid of tiles comes in one after another.
class Reveal extends StatelessWidget {
  const Reveal({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + index * 90),
      curve: Curves.easeOutCubic,
      builder: (_, v, c) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, (1 - v) * 18), child: c),
      ),
      child: child,
    );
  }
}

/// Bottom navigation of the app: a dark glass bar; the chosen item grows into a
/// gradient pill that shows its name.
class DfNavBar extends StatelessWidget {
  const DfNavBar({super.key, required this.index, required this.onChanged, required this.items});

  final int index;
  final ValueChanged<int> onChanged;
  final List<({IconData icon, IconData activeIcon, String label})> items;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xF2141846), Color(0xFA0A0C26)]),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, -6))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          // Fixed height: the Scaffold gives the bar loose constraints, and a
          // Center inside would otherwise grow to the whole screen height.
          child: SizedBox(
            height: 48,
            child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: Pressable(
                    onTap: () => onChanged(i),
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        height: 44,
                        padding: EdgeInsets.symmetric(horizontal: i == index ? 14 : 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          gradient: i == index ? DfGradients.primary : null,
                          boxShadow: i == index ? [BoxShadow(color: DfColors.accent.withValues(alpha: 0.4), blurRadius: 14, offset: const Offset(0, 4))] : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(i == index ? items[i].activeIcon : items[i].icon, size: 22, color: i == index ? Colors.white : DfColors.muted),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeOutCubic,
                              child: i == index
                                  ? Padding(
                                      padding: const EdgeInsets.only(left: 6),
                                      child: Text(items[i].label, maxLines: 1, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
            ),
          ),
        ),
      ),
    );
  }
}
