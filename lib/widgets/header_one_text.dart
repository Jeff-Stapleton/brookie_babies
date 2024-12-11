import 'package:flutter/material.dart';

class HeaderOneText extends StatelessWidget {
  const HeaderOneText({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text, 
      style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)
    );
  }
}