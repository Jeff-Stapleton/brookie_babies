import 'package:brookie_babies/uncontained_card.dart';
import 'package:flutter/material.dart';

class CarouselExample extends StatefulWidget {
  const CarouselExample({super.key});

  @override
  State<CarouselExample> createState() => _CarouselExampleState();
}

class _CarouselExampleState extends State<CarouselExample> {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 600),
        child: CarouselView(
          itemExtent: 1200,
          shrinkExtent: 200,
          children: List<Widget>.generate(20, (int index) {
            return UncontainedLayoutCard(index: index, label: 'Item $index');
          }),
        ),
      ),
    );
  }
}
