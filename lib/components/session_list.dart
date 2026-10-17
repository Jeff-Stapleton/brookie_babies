import 'package:brookie_babies/widgets/session_card.dart';
import 'package:flutter/material.dart';

class SessionList extends StatelessWidget {
  const SessionList({super.key, required this.sessionDate, required this.onSessionSelected});

  final DateTime sessionDate;
  final VoidCallback onSessionSelected;

  @override
  Widget build(BuildContext context) {
    // Scrolls within whatever height the parent gives it (SchedulingPage wraps
    // it in Expanded), so six-week months don't overflow.
    return SingleChildScrollView(
      child: Column(
        children: [
          SessionCard(sessionDate: sessionDate, sessionDescription: '', onSessionSelected: onSessionSelected),
          SessionCard(sessionDate: sessionDate, sessionDescription: '', onSessionSelected: onSessionSelected),
          SessionCard(sessionDate: sessionDate, sessionDescription: '', onSessionSelected: onSessionSelected),
          SessionCard(sessionDate: sessionDate, sessionDescription: '', onSessionSelected: onSessionSelected),
          SessionCard(sessionDate: sessionDate, sessionDescription: '', onSessionSelected: onSessionSelected),
        ],
      ),
    );
  }
}
