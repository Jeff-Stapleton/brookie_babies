import 'package:flutter/material.dart';

class HeaderThreeText extends StatelessWidget {
  const HeaderThreeText({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text, 
      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)
    );
  }
}