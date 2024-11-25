import 'dart:developer';

import 'package:brookie_babies/carousel.dart';
import 'package:flutter/material.dart';

class TextSection extends StatelessWidget {
  const TextSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            "This is a Header"
            ),
          Text(
            textAlign: TextAlign.center,
            "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Proin pretium dui feugiat, molestie purus vel, iaculis nulla. Sed eu lacus rhoncus, euismod felis a, iaculis nibh. In lobortis quam vel interdum tincidunt. Quisque non lorem scelerisque, dictum ligula et, sollicitudin enim. Nam feugiat vitae velit ac venenatis. Sed faucibus rutrum nibh, at lobortis sem vehicula id. Nam id nunc ac ligula fermentum congue. Ut ut ullamcorper felis. Phasellus ac risus tristique est pulvinar aliquet. Donec nulla nibh, maximus ultricies augue sed, egestas imperdiet nulla. Mauris a mollis nisi, id porttitor enim."),
        ],
      ),
    );
  }
}