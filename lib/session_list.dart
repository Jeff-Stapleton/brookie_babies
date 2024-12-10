import 'package:brookie_babies/session_card.dart';
import 'package:flutter/material.dart';

class SessionList extends StatelessWidget {
  const SessionList({super.key, required this.onSessionSelected});

  final VoidCallback onSessionSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height - 396,
      child: SingleChildScrollView(
        child: Column(
          children: [
            SessionCard(sessionText: 'Session 1', onSessionSelected: onSessionSelected),
            SessionCard(sessionText: 'Session 2', onSessionSelected: onSessionSelected),
            SessionCard(sessionText: 'Session 3', onSessionSelected: onSessionSelected),
            SessionCard(sessionText: 'Session 4', onSessionSelected: onSessionSelected),
            SessionCard(sessionText: 'Session 5', onSessionSelected: onSessionSelected),
          ],
        ),
      ),
    );
  }
}
