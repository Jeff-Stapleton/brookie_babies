import 'package:brookie_babies/header_text.dart';
import 'package:brookie_babies/subheader_text.dart';
import 'package:flutter/material.dart';

class SessionCard extends StatelessWidget {
  const SessionCard({super.key, required this.sessionText, required this.onSessionSelected});

  final String sessionText;
  final VoidCallback onSessionSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25.0, vertical: 5.0),
      child: GestureDetector(
        onTap: onSessionSelected,
        child: Card(
          shape: const RoundedRectangleBorder(
            side: BorderSide(color: Colors.grey, width: 1.0),
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 150,
            child: Center(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SubheaderText(text: 'WED'),
                      HeaderText(text: '11')
                    ],
                  ),
                  const VerticalDivider(
                    width: 20,
                    thickness: 1,
                    indent: 20,
                    endIndent: 16,
                    color: Colors.grey,
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [Icon(Icons.schedule), SizedBox(width: 16), SubheaderText(text: '9:00 am - 9:30 am')]),
                      SizedBox(height: 16),
                      Row(children: [Icon(Icons.place), SizedBox(width: 16), SubheaderText(text: '10652 S Wild Rice Dr.')])
                    ],
                  ),
                  SizedBox(width: 16),
                  SubheaderText(text: 'Testing 1 2 3, Testing 1 2 3')
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
