import 'package:brookie_babies/widgets/pricing_card.dart';
import 'package:flutter/material.dart';

class Packages extends StatelessWidget {
  const Packages({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(20),
      child: Wrap(
        spacing: 32, // Space between elements horizontally
        runSpacing: 16, // Space between elements vertically
        alignment: WrapAlignment.center, // Align the cards to the center
        children: [
          PricingCard(
            title: 'Basic', 
            price: "\$25", 
            bullets: ['15 minutes session', 'One individual', '5-10 edited photos']
          ),
          PricingCard(
            title: 'Premium', 
            price: "\$50", 
            bullets: ['15 minutes session', 'One individual', '5-10 edited photos']
          ),
          PricingCard(
            title: 'Ultimate', 
            price: "\$99", 
            bullets: ['15 minutes session', 'One individual', '5-10 edited photos']
          )
        ],
      ),
    );
  }
}