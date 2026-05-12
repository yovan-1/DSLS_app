import 'package:flutter/material.dart';
import 'dart:math' as math;

class SpeedometerWidget extends StatefulWidget {
  final int currentSpeed;
  final int recommendedSpeed;
  final Color color;
  final bool isTracking;
  final int animationDurationMs;

  const SpeedometerWidget({
    super.key,
    required this.currentSpeed,
    required this.recommendedSpeed,
    required this.color,
    required this.isTracking,
    this.animationDurationMs = 30,
  });

  @override
  State<SpeedometerWidget> createState() => _SpeedometerWidgetState();
}

class _SpeedometerWidgetState extends State<SpeedometerWidget> {
  int _animatedSpeed = 0;

  @override
  void didUpdateWidget(SpeedometerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentSpeed != widget.currentSpeed) {
      setState(() {
        _animatedSpeed = widget.currentSpeed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: _animatedSpeed, end: widget.currentSpeed),
      duration: Duration(milliseconds: widget.animationDurationMs),
      curve: Curves.easeOut,
      builder: (context, animatedSpeed, child) {
        return SizedBox(
          width: 280,
          height: 280,
          child: CustomPaint(
            painter: SpeedometerPainter(
              currentSpeed: animatedSpeed,
              recommendedSpeed: widget.recommendedSpeed,
              color: widget.color,
              isTracking: widget.isTracking,
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "$animatedSpeed",
                    style: TextStyle(
                      fontSize: 64,
                      fontWeight: FontWeight.bold,
                      color: widget.color,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    "km/h",
                    style: TextStyle(fontSize: 18, color: Colors.white54),
                  ),
                  SizedBox(height: 8),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: widget.color, width: 2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.flag, size: 16, color: widget.color),
                        SizedBox(width: 4),
                        Text(
                          "${widget.recommendedSpeed} km/h",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: widget.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class SpeedometerPainter extends CustomPainter {
  final int currentSpeed;
  final int recommendedSpeed;
  final Color color;
  final bool isTracking;

  SpeedometerPainter({
    required this.currentSpeed,
    required this.recommendedSpeed,
    required this.color,
    required this.isTracking,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 15;

    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    canvas.drawCircle(center, radius - 15, borderPaint);

    final bgPaint = Paint()
      ..color = Color(0xFF2A2A2A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 25
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi * 0.75,
      math.pi * 1.5,
      false,
      bgPaint,
    );

    final maxSpeed = 180.0;
    final speedRatio = (currentSpeed / maxSpeed).clamp(0.0, 1.0);
    final sweepAngle = math.pi * 1.5 * speedRatio;

    if (currentSpeed > 0) {
      final needlePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round;

      final needleStart = Offset(
        center.dx + (radius - 40) * math.cos(math.pi * 0.75 + sweepAngle - 0.1),
        center.dy + (radius - 40) * math.sin(math.pi * 0.75 + sweepAngle - 0.1),
      );
      final needleEnd = Offset(
        center.dx + (radius - 10) * math.cos(math.pi * 0.75 + sweepAngle),
        center.dy + (radius - 10) * math.sin(math.pi * 0.75 + sweepAngle),
      );
      canvas.drawLine(needleStart, needleEnd, needlePaint);

      final dotPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, 12, dotPaint);
    }

    final recRatio = (recommendedSpeed / maxSpeed).clamp(0.0, 1.0);
    final recAngle = math.pi * 0.75 + (math.pi * 1.5 * recRatio);
    final recPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final recStart = Offset(
      center.dx + (radius - 15) * math.cos(recAngle),
      center.dy + (radius - 15) * math.sin(recAngle),
    );
    final recEnd = Offset(
      center.dx + (radius + 12) * math.cos(recAngle),
      center.dy + (radius + 12) * math.sin(recAngle),
    );
    canvas.drawLine(recStart, recEnd, recPaint);

    for (int i = 0; i <= 6; i++) {
      final speed = (i * 30).toString();
      final angle = math.pi * 0.75 + (math.pi * 1.5 * i / 6);
      final textRadius = radius - 55;
      final textPos = Offset(
        center.dx + textRadius * math.cos(angle) - 12,
        center.dy + textRadius * math.sin(angle) - 12,
      );

      final textPainter = TextPainter(
        text: TextSpan(
          text: speed,
          style: TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, textPos);
    }
  }

  @override
  bool shouldRepaint(covariant SpeedometerPainter oldDelegate) {
    return oldDelegate.currentSpeed != currentSpeed ||
        oldDelegate.recommendedSpeed != recommendedSpeed ||
        oldDelegate.color != color ||
        oldDelegate.isTracking != isTracking;
  }
}
