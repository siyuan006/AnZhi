import 'package:flutter/material.dart';

class NoticeCard extends StatelessWidget {
  const NoticeCard({
    super.key,
    required this.text,
    this.margin,
    this.radius = 12,
  });

  final String text;
  final EdgeInsetsGeometry? margin;
  final double radius;

  static const Color _background = Color(0xFFFFF6E5);
  static const Color _border = Color(0xFFFFE0A3);
  static const Color _iconColor = Color(0xFFB26A00);
  static const Color _textColor = Color(0xFF8A5300);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: _border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.info_outline_rounded,
            size: 17,
            color: _iconColor,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.55,
                color: _textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
