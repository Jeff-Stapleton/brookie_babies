import 'package:flutter/material.dart';

class TextSection extends StatelessWidget {
  const TextSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            "CHOOSE YOUR PACKAGE"
            ),
          Text(
            textAlign: TextAlign.center,
            "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Proin pretium dui feugiat, molestie purus vel, iaculis nulla. Sed eu lacus rhoncus, euismod felis a, iaculis nibh. In lobortis quam vel interdum tincidunt."),
        ],
      ),
    );
  }
}