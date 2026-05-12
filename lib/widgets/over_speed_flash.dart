import 'package:flutter/material.dart';

class OverSpeedFlash extends StatefulWidget {
  final int diff;

  const OverSpeedFlash({super.key, required this.diff});

  @override
  State<OverSpeedFlash> createState() => _OverSpeedFlashState();
}

class _OverSpeedFlashState extends State<OverSpeedFlash>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final opacity = 0.10 + (_controller.value * 0.18);
          return Container(
            color: Colors.red.withValues(alpha: opacity),
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 24, left: 16, right: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    'SLOW DOWN • +${widget.diff} km/h',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
