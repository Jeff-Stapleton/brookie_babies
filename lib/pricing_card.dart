import 'dart:developer';

import 'package:brookie_babies/bulleted_list.dart';
import 'package:brookie_babies/header_text.dart';
import 'package:brookie_babies/subheader_text.dart';
import 'package:flutter/material.dart';

class PricingCard extends StatelessWidget {
  const PricingCard({super.key, required this.title, required this.price, required this.bullets});
  final String title;
  final String price;
  final List<String> bullets;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            HeaderText(text: title),
            SubheaderText(text: price),
            const SizedBox(height: 25),
            BulletedList(bullets: bullets),
            const SizedBox(height: 25),
            ElevatedButton(onPressed: () => {log("click")}, child: const Text("Book Now"))
          ],
        ),
      )
    );
  }

}