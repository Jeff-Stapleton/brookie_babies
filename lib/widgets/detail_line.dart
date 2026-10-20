import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:flutter/material.dart';

/// One line of a session's details (its date, time or place), labelled by
/// an icon.
class DetailLine extends StatelessWidget {
  const DetailLine({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Centers the 20px icon on the text's 22px first line.
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 20, color: BrookieColors.of(context).inkSoft),
        ),
        const SizedBox(width: BrookieSpace.s2),
        Expanded(child: Text(text)),
      ],
    );
  }
}
