import 'package:brookie_babies/widgets/bulleted_text.dart';
import 'package:flutter/material.dart';

class BulletedList extends StatelessWidget {
  const BulletedList({super.key, required this.bullets});
  final List<String> bullets;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // Ensures left alignment
      children: bullets.map((bullet) {
          return BulletedText(text: bullet);
        }).toList(),
    );
  }
}