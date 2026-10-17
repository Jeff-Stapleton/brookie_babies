import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/utilities/utils.dart';
import 'package:brookie_babies/widgets/focus_ring.dart';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

/// A month of days for choosing when to book, where the chosen day takes the
/// shape of the logo's disc.
///
/// [TableCalendar] dressed in the design system: month view only, weeks start
/// on Sunday, days outside the month left blank.
class BookingCalendar extends StatefulWidget {
  const BookingCalendar({
    super.key,
    required this.firstDay,
    required this.lastDay,
    required this.today,
    required this.selectedDay,
    required this.onDaySelected,
    this.isOpen,
  });

  /// The bookable range. Days outside it can't be chosen.
  final DateTime firstDay;
  final DateTime lastDay;

  /// Ringed, so families can find their place in the month.
  final DateTime today;

  final DateTime? selectedDay;
  final ValueChanged<DateTime> onDaySelected;

  /// Whether a day in range has openings. Days without them look and act like
  /// past days.
  final bool Function(DateTime day)? isOpen;

  /// The card's widest; the days stay [BrookieSize.day] apart or more.
  static const maxWidth = 400.0;

  @override
  State<BookingCalendar> createState() => _BookingCalendarState();
}

class _BookingCalendarState extends State<BookingCalendar> {
  late DateTime _focusedDay = _clamp(widget.selectedDay ?? widget.firstDay);

  DateTime get _first => _date(widget.firstDay);
  DateTime get _last => _date(widget.lastDay);

  // TableCalendar hands out days as UTC midnights; compare in the same terms.
  static DateTime _date(DateTime day) => DateTime.utc(day.year, day.month, day.day);

  DateTime _clamp(DateTime day) {
    final date = _date(day);
    if (date.isBefore(_first)) return _first;
    if (date.isAfter(_last)) return _last;
    return date;
  }

  bool _isBookable(DateTime day) {
    final date = _date(day);
    return !date.isBefore(_first) && !date.isAfter(_last) && (widget.isOpen?.call(date) ?? true);
  }

  bool _isFirstMonth(DateTime month) => month.year == _first.year && month.month == _first.month;
  bool _isLastMonth(DateTime month) => month.year == _last.year && month.month == _last.month;

  void _showMonth(int offset) {
    setState(() => _focusedDay = _clamp(DateTime.utc(_focusedDay.year, _focusedDay.month + offset)));
  }

  void _select(DateTime day) {
    setState(() => _focusedDay = _clamp(day));
    widget.onDaySelected(_date(day));
  }

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    final weekday = BrookieType.small.copyWith(color: c.inkSoft);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: BookingCalendar.maxWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(BrookieRadius.md),
        ),
        child: LayoutBuilder(builder: (context, constraints) {
          // On the narrowest phones, trade card padding for full-size days.
          final roomy = constraints.maxWidth >= 7 * BrookieSize.day + 2 * BrookieSpace.s4 + 2;
          final side = roomy ? BrookieSpace.s4 : BrookieSpace.s2;
          return Padding(
            padding: EdgeInsets.fromLTRB(side, BrookieSpace.s3, side, BrookieSpace.s3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MonthHeader(
                  month: _focusedDay,
                  onPrevious: _isFirstMonth(_focusedDay) ? null : () => _showMonth(-1),
                  onNext: _isLastMonth(_focusedDay) ? null : () => _showMonth(1),
                ),
                const SizedBox(height: BrookieSpace.s2),
                TableCalendar<void>(
                  firstDay: _first,
                  lastDay: _last,
                  focusedDay: _focusedDay,
                  currentDay: widget.today,
                  // Our own header: the package's chevrons have no tooltips
                  // and no focus ring.
                  headerVisible: false,
                  calendarFormat: CalendarFormat.month,
                  availableCalendarFormats: const {CalendarFormat.month: 'Month'},
                  availableGestures: AvailableGestures.horizontalSwipe,
                  startingDayOfWeek: StartingDayOfWeek.sunday,
                  rowHeight: BrookieSize.day + BrookieSpace.s1,
                  daysOfWeekHeight: 28,
                  pageAnimationEnabled: !still,
                  pageAnimationDuration: kBrookieFadeDuration,
                  formatAnimationDuration: still ? Duration.zero : kBrookieFadeDuration,
                  formatAnimationCurve: Curves.easeOut,
                  enabledDayPredicate: _isBookable,
                  selectedDayPredicate: (day) => isSameDay(widget.selectedDay, day),
                  onDaySelected: (day, focusedDay) => _select(day),
                  onPageChanged: (focusedDay) => setState(() => _focusedDay = focusedDay),
                  // Past and closed days get their semantics too, so a screen
                  // reader hears them as unavailable rather than skipping them.
                  loadEventsForDisabledDays: true,
                  calendarStyle: const CalendarStyle(outsideDaysVisible: false, cellMargin: EdgeInsets.zero),
                  daysOfWeekStyle: DaysOfWeekStyle(
                    dowTextFormatter: (day, locale) => weekdayInitial(day),
                    weekdayStyle: weekday,
                    weekendStyle: weekday,
                  ),
                  calendarBuilders: CalendarBuilders<void>(
                    prioritizedBuilder: (context, day, focusedDay) => _DayDisc(
                      day: day,
                      bookable: _isBookable(day),
                      selected: isSameDay(widget.selectedDay, day),
                      today: isSameDay(widget.today, day),
                      onSelected: () => _select(day),
                    ),
                    // TableCalendar wraps each day in its own label and drops
                    // ours, so the state rides along on the marker layer.
                    markerBuilder: (context, day, events) => _DaySemantics(
                      bookable: _isBookable(day),
                      selected: isSameDay(widget.selectedDay, day),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

/// "October 2026" between the previous and next month buttons.
class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.month, required this.onPrevious, required this.onNext});

  final DateTime month;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    // The theme's icon buttons stay ink when disabled; past the booking
    // window they step back to ink-soft.
    final style = ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled) ? c.inkSoft : c.ink),
    );
    return Row(
      children: [
        IconButton(
          onPressed: onPrevious,
          tooltip: 'Previous month',
          style: style,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Text(
              formatMonth(month),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ),
        IconButton(
          onPressed: onNext,
          tooltip: 'Next month',
          style: style,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

/// One day: a 44px disc. Ink numerals for days with openings, ink-soft for the
/// rest, a fine ring for today, and butter with an ink ring when chosen.
class _DayDisc extends StatefulWidget {
  const _DayDisc({
    required this.day,
    required this.bookable,
    required this.selected,
    required this.today,
    required this.onSelected,
  });

  final DateTime day;
  final bool bookable;
  final bool selected;
  final bool today;
  final VoidCallback onSelected;

  @override
  State<_DayDisc> createState() => _DayDiscState();
}

class _DayDiscState extends State<_DayDisc> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    final selected = widget.selected;
    final bookable = widget.bookable;

    final Color fill;
    if (selected) {
      fill = c.butter;
    } else if (bookable && _hovered) {
      fill = c.surfaceSunk;
    } else {
      fill = Colors.transparent;
    }

    final Color numeral;
    if (selected) {
      numeral = c.onButter;
    } else {
      numeral = bookable ? c.ink : c.inkSoft;
    }

    // Taps reach TableCalendar's own gesture detector around this; the
    // detector here adds keyboard focus, Enter/Space and hover.
    return FocusableActionDetector(
      enabled: bookable,
      mouseCursor: bookable ? SystemMouseCursors.click : MouseCursor.defer,
      onShowHoverHighlight: (value) => setState(() => _hovered = value),
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onSelected();
          return null;
        }),
      },
      child: Center(
        child: FocusRing.circle(
          visible: _focused,
          child: AnimatedContainer(
            // Hover eases in; selection is instant.
            duration: selected || MediaQuery.disableAnimationsOf(context) ? Duration.zero : kBrookieStateDuration,
            width: BrookieSize.day,
            height: BrookieSize.day,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fill,
              border: Border.all(color: widget.today && !selected ? c.lineStrong : Colors.transparent),
              // Butter is nearly invisible on paper, so the chosen day also
              // gets a 1.5px ink ring.
              boxShadow: selected ? [BoxShadow(color: c.ink, spreadRadius: 1.5)] : null,
            ),
            child: Text(
              '${widget.day.day}',
              // Unavailable days are set lighter as well as softer.
              style: BrookieType.label.copyWith(
                color: numeral,
                fontWeight: bookable || selected ? null : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Puts a day's state on the node TableCalendar labels "Saturday, October
/// 24, 2026": a button, selected or not, unavailable for past days.
class _DaySemantics extends StatelessWidget {
  const _DaySemantics({required this.bookable, required this.selected});

  final bool bookable;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Semantics(button: true, enabled: bookable, selected: selected, child: const SizedBox.shrink());
  }
}
