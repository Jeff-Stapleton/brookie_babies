import 'package:brookie_babies/models/session_time.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/utilities/utils.dart';
import 'package:brookie_babies/widgets/session_slot.dart';
import 'package:flutter/material.dart';

/// The session times on [day], chosen like radio buttons, under the day's
/// name so the rows don't each repeat it.
class SessionList extends StatelessWidget {
  const SessionList({
    super.key,
    required this.day,
    required this.times,
    required this.selected,
    required this.onSelected,
    this.taken = const {},
  });

  final DateTime day;
  final List<SessionTime> times;
  final SessionTime? selected;
  final ValueChanged<SessionTime> onSelected;

  /// Times someone else has booked. Nothing fills this yet (bookings aren't
  /// written by the site); the state is ready for when they are.
  final Set<SessionTime> taken;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(formatDayHeading(day), style: Theme.of(context).textTheme.titleLarge),
        ),
        const SizedBox(height: BrookieSpace.s4),
        RadioGroup<SessionTime>(
          groupValue: selected,
          onChanged: (time) {
            if (time != null) onSelected(time);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, time) in times.indexed) ...[
                if (index > 0) const SizedBox(height: BrookieSpace.s2),
                SessionSlot(time: time, taken: taken.contains(time)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
