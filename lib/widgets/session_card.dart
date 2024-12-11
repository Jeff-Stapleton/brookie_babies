import 'package:brookie_babies/widgets/header_four_text.dart';
import 'package:brookie_babies/widgets/header_one_text.dart';
import 'package:brookie_babies/widgets/subheader_text.dart';
import 'package:flutter/material.dart';

class SessionCard extends StatelessWidget {
  const SessionCard({super.key, required this.sessionDate, required this.sessionDescription, required this.onSessionSelected});

  final DateTime sessionDate;
  final String sessionDescription;
  final VoidCallback onSessionSelected;

  String getDayOfTheWeek(DateTime date) {
    List<String> weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    // `weekday` is 1-based
    return weekdays[date.weekday - 1]; 
  }


  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 8),
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
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16, horizontal: 64),
                child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      HeaderFourText(text: getDayOfTheWeek(sessionDate)),
                      HeaderOneText(text: sessionDate.day.toString())
                    ],
                  ),
                  const VerticalDivider(
                    width: 128,
                    thickness: 1,
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
                  SizedBox(width: 64),
                  SubheaderText(text: 'Testing 1 2 3, Testing 1 2 3')
                ],
              ),
              )
            ),
          ),
        ),
      ),
    );
  }
}
