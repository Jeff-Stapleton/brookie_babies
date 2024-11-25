import 'dart:developer';

import 'package:brookie_babies/carousel.dart';
import 'package:brookie_babies/text_section.dart';
import 'package:flutter/material.dart';

class BulletedText extends StatelessWidget {
  const BulletedText({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '• ',
          style: TextStyle(fontSize: 18),
        ),
        Flexible(
          child: Text(
            text,
            style: TextStyle(fontSize: 16),
          ),
        ),
      ],
    );
  }
}