import 'package:flutter/material.dart';

class SubheaderText extends StatelessWidget {
  const SubheaderText({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text, 
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)
    );
  }
}