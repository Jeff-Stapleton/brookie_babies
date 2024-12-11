import 'package:flutter/material.dart';

class HeaderTwoText extends StatelessWidget {
  const HeaderTwoText({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text, 
      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)
    );
  }
}