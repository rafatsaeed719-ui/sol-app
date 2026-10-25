import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app.dart';

/// ألوان الأيقونات المجسمة (فاتح ← غامق)
class Tone {
  final Color light, dark;
  const Tone(this.light, this.dark);
}

const Tone tGold = Tone(Color(0xFFF3D88A), Color(0xFF9C7A2A));
const Tone tBlack = Tone(Color(0xFF4A4A4A), Color(0xFF0A0A0A));
const Tone tGreen = Tone(Color(0xFF58D68D), Color(0xFF145A32));
const Tone tRed = Tone(Color(0xFFF1948A), Color(0xFF922B21));
const Tone tBlue = Tone(Color(0xFF85C1E9), Color(0xFF1A5276));
const Tone tPurple = Tone(Color(0xFFC39BD3), Color(0xFF5B2C6F));
const Tone tOrange = Tone(Color(0xFFF8C471), Color(0xFFB9770E));
const Tone tTeal = Tone(Color(0xFF76D7C4), Color(0xFF0E6655));

/// أقرب درجة 3D للون عادي
Tone toneOf(Color c) {
  if (c == kSuccess) return tGreen;
  if (c == kDanger) return tRed;
  if (c == kAccent) return tGold;
  if (c == Colors.orange) return tOrange;
  if (c == Colors.blue) return tBlue;
  if (c == kPrimary) return tBlack;
  final h = HSLColor.fromColor(c);
  return Tone(h.withLightness(math.min(0.8, h.lightness + 0.25)).toColor(),
      h.withLightness(math.max(0.1, h.lightness - 0.2)).toColor());
}

/// أيقونة مجسمة: تدرج + لمعة + ظل، بتظهر بحركة وممكن تطفو بهدوء
class Icon3D extends StatefulWidget {
  final IconData icon;
  final double size;
  final Tone tone;
  final bool float; // حركة طفو مستمرة
  final bool circle;
  final int delayMs;
  const Icon3D(this.icon,
      {super.key,
      this.size = 44,
      this.tone = tGold,
      this.float = false,
      this.circle = false,
      this.delayMs = 0});

  @override
  State<Icon3D> createState() => _Icon3DState();
}

class _Icon3DState extends State<Icon3D> with TickerProviderStateMixin {
  late final AnimationController intro = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 750));
  AnimationController? floatC;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) intro.forward();
    });
    if (widget.float) {
      floatC = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))
        ..repeat();
    }
  }

  @override
  void dispose() {
    intro.dispose();
    floatC?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final t = widget.tone;
    final radius = widget.circle ? s / 2 : s * 0.28;
    final body = Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [t.light, t.dark],
        ),
        boxShadow: [
          BoxShadow(
              color: t.dark.withValues(alpha: 0.45),
              blurRadius: s * 0.22,
              offset: Offset(0, s * 0.12)),
          BoxShadow(
              color: Colors.white.withValues(alpha: 0.6),
              blurRadius: 1,
              offset: const Offset(-1, -1)),
        ],
      ),
      child: Stack(alignment: Alignment.center, children: [
        // اللمعة اللي فوق
        Positioned(
          top: s * 0.06,
          left: s * 0.12,
          right: s * 0.12,
          height: s * 0.42,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.55),
                  Colors.white.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
        Icon(widget.icon, size: s * 0.52, color: Colors.white, shadows: [
          Shadow(color: t.dark.withValues(alpha: 0.8), blurRadius: 4, offset: const Offset(0, 2)),
        ]),
      ]),
    );

    return AnimatedBuilder(
      animation: Listenable.merge([intro, if (floatC != null) floatC!]),
      builder: (context, child) {
        final v = Curves.elasticOut.transform(intro.value.clamp(0.0, 1.0));
        final f = floatC == null ? 0.0 : math.sin(floatC!.value * 2 * math.pi);
        return Opacity(
          opacity: intro.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, -2.5 * f),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.002)
                ..rotateY(0.18 * f)
                ..scale(0.4 + 0.6 * v),
              child: child,
            ),
          ),
        );
      },
      child: body,
    );
  }
}

/// بيظهر العنصر بحركة (طالع لفوق مع ظهور تدريجي)
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int delayMs;
  final double dy;
  const FadeSlideIn({super.key, required this.child, this.delayMs = 0, this.dy = 24});
  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 450));

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) c.forward();
    });
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, child) {
        final v = Curves.easeOutCubic.transform(c.value);
        return Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, widget.dy * (1 - v)), child: child),
        );
      },
      child: widget.child,
    );
  }
}

/// زرار بيتنطط لما تدوس عليه
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const Pressable({super.key, required this.child, this.onTap});
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool down = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => down = true),
      onTapCancel: () => setState(() => down = false),
      onTapUp: (_) => setState(() => down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: down ? 0.94 : 1,
        duration: const Duration(milliseconds: 120),
        child: widget.child,
      ),
    );
  }
}

/// أيقونة شريط التنقل: عادية، ولما تتختار تبقى مجسمة
NavigationDestination nav3D(IconData icon, String label, {Widget Function(Widget)? wrap}) {
  Widget w(Widget x) => wrap == null ? x : wrap(x);
  return NavigationDestination(
    icon: w(Icon(icon)),
    selectedIcon: w(Icon3D(icon, size: 34, tone: tGold, circle: true)),
    label: label,
  );
}

/// بيطفو لفوق ولتحت بهدوء (للوجو)
class Floating extends StatefulWidget {
  final Widget child;
  final double amount;
  const Floating({super.key, required this.child, this.amount = 6});
  @override
  State<Floating> createState() => _FloatingState();
}

class _FloatingState extends State<Floating> with SingleTickerProviderStateMixin {
  late final AnimationController c =
      AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, -widget.amount * Curves.easeInOut.transform(c.value)),
        child: child,
      ),
      child: widget.child,
    );
  }
}
