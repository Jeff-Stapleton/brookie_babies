import 'package:flutter/material.dart';

class HeaderFourText extends StatelessWidget {
  const HeaderFourText({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text, 
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
    );
  }
}