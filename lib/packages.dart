import 'dart:developer';

import 'package:brookie_babies/bulleted_text.dart';
import 'package:brookie_babies/carousel.dart';
import 'package:flutter/material.dart';

class Packages extends StatelessWidget {
  const Packages({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        children: [
          Card(
            child: Column(
              children: [
                const Text('Basic'),
                const Text('\$25'),
                const BulletedText(text: "15 minutes session"),
                const BulletedText(text: "One individual"),
                const BulletedText(text: "5-10 edited photos"),
                ElevatedButton(onPressed: () => {log("click")}, child: const Text("Book Now"))
              ],
            ),
          ),
          Card(
            child: Column(
              children: [
                const Text('Premium'),
                const Text('\$50'),
                const BulletedText(text: "15 minutes session"),
                const BulletedText(text: "One individual"),
                const BulletedText(text: "5-10 edited photos"),
                ElevatedButton(onPressed: () => {log("click")}, child: const Text("Book Now"))
              ],
            ),
          ),
          Card(
            child: Column(
              children: [
                const Text('Ultimate'),
                const Text('\$99'),
                const BulletedText(text: "15 minutes session"),
                const BulletedText(text: "One individual"),
                const BulletedText(text: "5-10 edited photos"),
                ElevatedButton(onPressed: () => {log("click")}, child: const Text("Book Now"))
              ],
            ),
          )
        ],
      ),
    );
  }
}