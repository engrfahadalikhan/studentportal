import 'package:flutter/material.dart';

class CustomCard extends StatelessWidget {
  final Widget child;
  final Color? ringColor;
  final double ringWidth;
  final Color? hoverRingColor;

  const CustomCard({
    Key? key,
    required this.child,
    this.ringColor,
    this.ringWidth = 2,
    this.hoverRingColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ringColor ?? Colors.grey.shade100,
          width: ringWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
