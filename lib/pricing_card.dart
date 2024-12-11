import 'dart:developer';

import 'package:brookie_babies/bulleted_list.dart';
import 'package:brookie_babies/header_two_text.dart';
import 'package:brookie_babies/scheduling_page.dart';
import 'package:brookie_babies/subheader_text.dart';
import 'package:flutter/material.dart';

class PricingCard extends StatelessWidget {
  const PricingCard({super.key, required this.title, required this.price, required this.bullets});
  final String title;
  final String price;
  final List<String> bullets;

  void navigateToHomePage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SchedulingPage(packageName: title,),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15), 
        side: const BorderSide(color: Colors.black12, width: 2)
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            HeaderTwoText(text: title),
            SubheaderText(text: price),
            const SizedBox(height: 35, width: 350),
            BulletedList(bullets: bullets),
            const SizedBox(height: 250, width: 350),
            ElevatedButton(
              onPressed: () => navigateToHomePage(context),
              child: const Text("Book Now")
            )
          ],
        ),
      )
    );
  }

}