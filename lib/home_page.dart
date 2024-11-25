import 'package:brookie_babies/carousel.dart';
import 'package:brookie_babies/packages.dart';
import 'package:brookie_babies/text_section.dart';
import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            CarouselExample(),
            TextSection(),
            Packages()
          ],
        ),
      )
    );
  }
}
