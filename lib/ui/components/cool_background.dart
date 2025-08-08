import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Animated gradient background designed to look vibrant while remaining subtle
/// enough for form readability. GPU-friendly (no shaders), works on iOS/Android.
class CoolBackground extends StatefulWidget {
  final Widget child;
  final double overlayOpacity; // dark overlay to ensure contrast
  final Duration speed;

  const CoolBackground({
    super.key,
    required this.child,
    this.overlayOpacity = 0.35,
    this.speed = const Duration(seconds: 20),
  });

  @override
  State<CoolBackground> createState() => _CoolBackgroundState();
}

// Brand-inspired variant: diagonal "slash" beams, subtle code grid, vignette.
// Keeps readability while reinforcing the product identity.
class SlashBackground extends StatelessWidget {
  final Widget child;
  final double overlayOpacity;
  final bool animate;
  final Duration speed;
  final bool showGrid;
  final bool showSlashes;

  const SlashBackground({
    super.key,
    required this.child,
    this.overlayOpacity = 0.35,
    this.animate = true,
    this.speed = const Duration(seconds: 14),
    this.showGrid = true,
    this.showSlashes = true,
  });

  @override
  Widget build(BuildContext context) {
    final base = Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-0.9, -1.0),
          end: Alignment(1.0, 0.8),
          colors: [
            Color(0xFF0B1020), // deep space
            Color(0xFF121735),
            Color(0xFF0E1226),
          ],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
    );

    final vignette = Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topCenter,
          radius: 1.2,
          colors: [
            Colors.transparent,
            Colors.black.withOpacity(0.35),
          ],
          stops: const [0.6, 1.0],
        ),
      ),
    );

    final grid = CustomPaint(
      painter: _GridPainter(
        color: const Color(0xFF7DD3FC).withOpacity(0.05), // cyan-300 faint
        spacing: 28,
        thickness: 1,
      ),
    );

    final slashes = _AnimatedSlashes(
      animate: animate,
      speed: speed,
      colorA: const Color(0xFF6366F1).withOpacity(0.35), // indigo glow
      colorB: const Color(0xFF22D3EE).withOpacity(0.25), // cyan glow
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        base,
        if (showGrid) grid,
        if (showSlashes) slashes,
        vignette,
        Container(color: Colors.black.withOpacity(overlayOpacity)),
        child,
      ],
    );
  }
}

class _AnimatedSlashes extends StatefulWidget {
  final bool animate;
  final Duration speed;
  final Color colorA;
  final Color colorB;

  const _AnimatedSlashes({
    required this.animate,
    required this.speed,
    required this.colorA,
    required this.colorB,
  });

  @override
  State<_AnimatedSlashes> createState() => _AnimatedSlashesState();
}

class _AnimatedSlashesState extends State<_AnimatedSlashes> with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.speed);
    if (widget.animate) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_c.value);
        // Two diagonal beams moving subtly across the screen to suggest a "slash"
        return Transform.rotate(
          angle: -0.52, // ~ -30 degrees
          alignment: Alignment.center,
          child: Stack(
            children: [
              _beam(
                context,
                offset: Offset(-MediaQuery.of(context).size.width * (0.2 + 0.05 * t), 0),
                widthFactor: 0.22,
                color: widget.colorA,
              ),
              _beam(
                context,
                offset: Offset(MediaQuery.of(context).size.width * (0.25 - 0.05 * t), 0),
                widthFactor: 0.18,
                color: widget.colorB,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _beam(BuildContext context, {required Offset offset, required double widthFactor, required Color color}) {
    final size = MediaQuery.of(context).size;
    final w = size.width * widthFactor;
    return Transform.translate(
      offset: offset,
      child: Container(
        width: w,
        height: size.height * 1.6,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.transparent,
              color,
              Colors.transparent,
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.35), blurRadius: 40, spreadRadius: 8),
          ],
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final Color color;
  final double spacing;
  final double thickness;

  _GridPainter({required this.color, required this.spacing, required this.thickness});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness;

    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.spacing != spacing || oldDelegate.thickness != thickness;
  }
}

class _CoolBackgroundState extends State<CoolBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _t;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.speed)
      ..repeat(reverse: true);
    _t = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Alignment _orbit(double phase, {double radius = 0.5}) {
    final angle = 2 * math.pi * phase;
    return Alignment(radius * math.cos(angle), radius * math.sin(angle));
    }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        // Animate gradient alignments very slowly to create a living background.
        final a1 = Alignment.lerp(
          const Alignment(-0.8, -0.9),
          _orbit(_t.value * 0.5 + 0.1, radius: 0.9),
          0.5,
        )!;
        final a2 = Alignment.lerp(
          const Alignment(0.9, -0.6),
          _orbit(_t.value * 0.6 + 0.4, radius: 0.8),
          0.5,
        )!;
        final a3 = Alignment.lerp(
          const Alignment(-0.6, 0.9),
          _orbit(_t.value * 0.7 + 0.7, radius: 0.85),
          0.5,
        )!;
        final lBegin = Alignment.lerp(
          const Alignment(-1, -0.3),
          _orbit(_t.value * 0.3 + 0.2, radius: 0.6),
          0.5,
        )!;
        final lEnd = Alignment.lerp(
          const Alignment(1, 0.4),
          _orbit(_t.value * 0.3 + 0.8, radius: 0.6),
          0.5,
        )!;

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: lBegin,
              end: lEnd,
              colors: const [
                Color(0xFF0F0C29),
                Color(0xFF302B63),
                Color(0xFF24243E),
              ],
              stops: const [0.0, 0.6, 1.0],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Soft neon blobs (radial gradients) for depth
              _RadialBlob(
                alignment: a1,
                color: const Color(0xFF6366F1).withOpacity(0.35), // indigo
                radius: 0.65,
              ),
              _RadialBlob(
                alignment: a2,
                color: const Color(0xFF22D3EE).withOpacity(0.28), // cyan
                radius: 0.55,
              ),
              _RadialBlob(
                alignment: a3,
                color: const Color(0xFFFB7185).withOpacity(0.25), // rose
                radius: 0.6,
              ),
              // Overlay to ensure readability
              Container(
                color: Colors.black.withOpacity(widget.overlayOpacity),
              ),
              // Content
              widget.child,
            ],
          ),
        );
      },
    );
  }
}

class _RadialBlob extends StatelessWidget {
  final Alignment alignment;
  final Color color;
  final double radius; // relative size

  const _RadialBlob({
    required this.alignment,
    required this.color,
    this.radius = 0.6,
  });

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: 1,
      heightFactor: 1,
      child: Align(
        alignment: alignment,
        child: Container(
          width: MediaQuery.of(context).size.shortestSide * (radius * 1.5 + 0.4),
          height: MediaQuery.of(context).size.shortestSide * (radius * 1.5 + 0.4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color,
                color.withOpacity(0.0),
              ],
              stops: const [0.0, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}
