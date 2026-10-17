import 'package:brookie_babies/models/session_time.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/focus_ring.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:flutter/material.dart';

/// One bookable time on the selected day, chosen like a radio button.
///
/// Put slots under a `RadioGroup<SessionTime>`, which holds the choice and
/// gives them radio semantics and arrow-key navigation. A [taken] slot can't
/// be chosen and says so.
class SessionSlot extends StatefulWidget {
  const SessionSlot({super.key, required this.time, this.taken = false});

  final SessionTime time;
  final bool taken;

  /// The location line. The street address goes to the family after they
  /// book, never on the public list.
  static const locationNote = 'Address sent after you book';

  @override
  State<SessionSlot> createState() => _SessionSlotState();
}

class _SessionSlotState extends State<SessionSlot> {
  final _focusNode = FocusNode(debugLabel: 'SessionSlot');
  bool? _wasSelected;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final group = RadioGroup.maybeOf<SessionTime>(context);
    // One node per slot, so a screen reader reads the time, the location and
    // the radio state together.
    return MergeSemantics(
      child: RawRadio<SessionTime>(
        value: widget.time,
        groupRegistry: group,
        enabled: !widget.taken && group != null,
        toggleable: false,
        focusNode: _focusNode,
        autofocus: false,
        mouseCursor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled) ? SystemMouseCursors.basic : SystemMouseCursors.click),
        builder: (context, radio) {
          final states = radio.states;
          final selected = !widget.taken && states.contains(WidgetState.selected);
          // Hover and focus ease in; selection is instant.
          final instant = selected != _wasSelected || MediaQuery.disableAnimationsOf(context);
          _wasSelected = selected;
          return _SlotBody(
            time: widget.time,
            taken: widget.taken,
            selected: selected,
            hovered: states.contains(WidgetState.hovered),
            focused: states.contains(WidgetState.focused),
            duration: instant ? Duration.zero : kBrookieStateDuration,
          );
        },
      ),
    );
  }
}

class _SlotBody extends StatelessWidget {
  const _SlotBody({
    required this.time,
    required this.taken,
    required this.selected,
    required this.hovered,
    required this.focused,
    required this.duration,
  });

  final SessionTime time;
  final bool taken;
  final bool selected;
  final bool hovered;
  final bool focused;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    final foreground = selected ? c.onButter : (taken ? c.inkSoft : c.ink);
    final secondary = selected ? c.onButter : c.inkSoft;

    final Color edge;
    if (selected || taken) {
      edge = Colors.transparent;
    } else {
      edge = hovered ? c.lineStrong : c.line;
    }

    return FocusRing(
      visible: focused,
      borderRadius: BrookieRadius.sm,
      child: AnimatedContainer(
        duration: duration,
        padding: const EdgeInsets.all(BrookieSpace.s4),
        decoration: BoxDecoration(
          color: selected ? c.butter : (taken ? c.surfaceSunk : c.surface),
          // The hairline stays (transparent) in every state so the content
          // never shifts.
          border: Border.all(color: edge),
          borderRadius: BorderRadius.circular(BrookieRadius.sm),
          // Butter is nearly invisible on paper, so the choice also gets a
          // 1.5px ink ring: a spread with no blur, not a shadow.
          boxShadow: selected ? [BoxShadow(color: c.ink, spreadRadius: 1.5)] : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(time.label, style: BrookieType.label.copyWith(color: foreground)),
                  const SizedBox(height: BrookieSpace.s1),
                  Row(
                    children: [
                      Icon(Icons.place_outlined, size: 16, color: secondary),
                      const SizedBox(width: BrookieSpace.s1),
                      Flexible(
                        child: Text(SessionSlot.locationNote, style: BrookieType.ui.copyWith(color: secondary)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: BrookieSpace.s3),
            if (taken) const StatusTag(label: 'Taken') else _RadioMark(selected: selected),
          ],
        ),
      ),
    );
  }
}

/// The radio circle at the end of a slot; filled when chosen.
class _RadioMark extends StatelessWidget {
  const _RadioMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: selected ? c.onButter : c.lineStrong, width: 1.5),
      ),
      child: selected
          ? DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, color: c.onButter),
              child: const SizedBox.square(dimension: 10),
            )
          : null,
    );
  }
}
