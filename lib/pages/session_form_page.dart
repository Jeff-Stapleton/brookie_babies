import 'dart:developer';

import 'package:brookie_babies/components/admin_frame.dart';
import 'package:brookie_babies/components/admin_gate.dart';
import 'package:brookie_babies/components/booking_calendar.dart';
import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/models/session_details.dart';
import 'package:brookie_babies/models/session_time.dart';
import 'package:brookie_babies/pages/admin_session_page.dart';
import 'package:brookie_babies/services/admin_service.dart';
import 'package:brookie_babies/services/app_services.dart';
import 'package:brookie_babies/services/photo_rules.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/utilities/utils.dart';
import 'package:brookie_babies/widgets/brookie_dialog.dart';
import 'package:brookie_babies/widgets/busy_button.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:brookie_babies/widgets/top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

typedef _Time = ({int hour, int minute});

/// Adds an ad hoc session (family, friends: no purchase), or edits
/// [session]. Adding one opens its page, ready for photos.
///
/// Every field is checked against what firestore.rules accept
/// ([SessionRules]) before anything is saved.
class SessionFormPage extends StatelessWidget {
  const SessionFormPage({super.key, this.session});

  /// The ad hoc session to edit; null to add one.
  final Booking? session;

  @override
  Widget build(BuildContext context) {
    final adding = session == null;
    return Scaffold(
      appBar: BrookieTopBar(title: adding ? 'Add a session' : 'Edit session', showAdminLink: false),
      body: AdminGate(child: _SessionForm(session: session)),
    );
  }
}

/// Why [name] can't be saved, or null if it can.
String? _nameProblem(String? name) {
  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty) return 'Enter who the session is for.';
  if (trimmed.length > SessionRules.nameMaxLength) {
    return 'Shorten the name to ${SessionRules.nameMaxLength} characters or fewer.';
  }
  return null;
}

String? _emailProblem(String? email) {
  final normalized = SessionRules.normalizeEmail(email ?? '');
  if (normalized.isEmpty) return 'Enter the email they use to sign in to Google.';
  if (!SessionRules.emailPattern.hasMatch(normalized)) {
    return 'That isn’t a whole email address. Check it, like name@gmail.com.';
  }
  return null;
}

String? _locationProblem(String? location) {
  if ((location?.trim().length ?? 0) <= SessionRules.locationMaxLength) return null;
  return 'Shorten the location to ${SessionRules.locationMaxLength} characters or fewer.';
}

String? _dateProblem(DateTime? date) => date == null ? 'Choose the day of the session.' : null;

/// One of the form's fields as the theme draws it, plus the danger edge
/// for a field that's both focused and wrong, which the theme leaves to
/// Material's underline.
InputDecoration _decoration(
  BuildContext context, {
  required String label,
  String? helper,
  String? errorText,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    labelText: label,
    helperText: helper,
    helperMaxLines: 3,
    errorText: errorText,
    errorMaxLines: 3,
    suffixIcon: suffixIcon,
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(BrookieRadius.sm),
      borderSide: BorderSide(color: BrookieColors.of(context).danger, width: 2),
    ),
  );
}

/// What's typed or chosen in a field: Jost, like the rest of the site's
/// controls (Material would set it in the reading face).
TextStyle? _inputStyle(BuildContext context) => Theme.of(context).textTheme.bodyMedium;

class _SessionForm extends StatefulWidget {
  const _SessionForm({required this.session});

  final Booking? session;

  @override
  State<_SessionForm> createState() => _SessionFormState();
}

class _SessionFormState extends State<_SessionForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.session?.name);
  late final _email = TextEditingController(text: widget.session?.email);
  late final _location = TextEditingController(text: widget.session?.location);
  final _nameFocus = FocusNode(debugLabel: 'Name');
  final _emailFocus = FocusNode(debugLabel: 'Email');
  final _dateFocus = FocusNode(debugLabel: 'Date');
  final _locationFocus = FocusNode(debugLabel: 'Location');

  // Sessions are only ever saved with one of these, but a name the form
  // doesn't offer would trip the dropdown, so it starts on "No package".
  late String? _package =
      SessionRules.packageNames.contains(widget.session?.packageName) ? widget.session!.packageName : null;
  late DateTime? _date = widget.session?.date;
  late _Time? _time = widget.session?.time;

  /// The start times offered: quarter hours from 6:00 am to 9:00 pm, and
  /// the session's own time if it's another.
  late final List<_Time> _times = () {
    final times = [
      for (var minutes = 6 * 60; minutes <= 21 * 60; minutes += 15) (hour: minutes ~/ 60, minute: minutes % 60),
    ];
    final current = widget.session?.time;
    if (current != null && !times.contains(current)) {
      times
        ..add(current)
        ..sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
    }
    return times;
  }();

  /// Once the admin has tried to save, each field is checked as it changes.
  bool _triedToSave = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _location.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    _dateFocus.dispose();
    _locationFocus.dispose();
    super.dispose();
  }

  Future<void> _chooseDate(FormFieldState<DateTime> field) async {
    final chosen = await showBrookieDialog<DateTime>(
      context,
      builder: (context) => _DateDialog(initial: _date, now: DateTime.now()),
    );
    if (chosen == null || !mounted) return;
    setState(() => _date = chosen);
    field.didChange(chosen);
  }

  /// Takes keyboard focus to the first field that needs fixing.
  void _focusFirstProblem() {
    final FocusNode? first;
    if (_nameProblem(_name.text) != null) {
      first = _nameFocus;
    } else if (_emailProblem(_email.text) != null) {
      first = _emailFocus;
    } else if (_dateProblem(_date) != null) {
      first = _dateFocus;
    } else if (_locationProblem(_location.text) != null) {
      first = _locationFocus;
    } else {
      first = null;
    }
    first?.requestFocus();
  }

  // The button stays enabled while saving (BusyButton), so keyboard focus
  // stays on it; another press does nothing.
  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _triedToSave = true;
      _error = null;
    });
    if (!_form.currentState!.validate()) {
      _focusFirstProblem();
      return;
    }
    final location = _location.text.trim();
    final details = SessionDetails(
      name: _name.text.trim(),
      email: SessionRules.normalizeEmail(_email.text),
      date: _date!,
      packageName: _package,
      time: _time,
      location: location.isEmpty ? null : location,
    );
    final session = widget.session;
    // A new email hands the photos to someone else.
    if (session != null && session.photosReady && details.email != session.email) {
      final oldEmail = session.email;
      final confirmed = await showBrookieConfirm(
        context,
        title: 'Change who can download?',
        message: oldEmail == null
            ? 'Anyone signed in with Google as ${details.email} will be able to download these photos.'
            : 'Anyone signed in with Google as ${details.email} will be able to download these photos, '
                'and $oldEmail won’t.',
        confirmLabel: 'Save changes',
      );
      if (!confirmed || !mounted) return;
    }

    final admin = AppServices.of(context).admin;
    setState(() => _saving = true);
    try {
      // Once saved, the form stays busy while it fades out.
      if (session == null) {
        final id = await admin.createSession(details);
        if (!mounted) return;
        // Straight on to its photos; back from there is Admin, not this form.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (context) => AdminSessionPage(sessionId: id)),
        );
      } else {
        await admin.updateSession(session, details);
        if (!mounted) return;
        // Back to the session. (With nothing below, it stays, saved.)
        final left = await Navigator.of(context).maybePop();
        if (!left && mounted) setState(() => _saving = false);
      }
    } catch (e) {
      if (e is! AdminException) log('Saving session ${session?.id ?? '(new)'} failed: $e');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is AdminException ? e.message : 'The session wasn’t saved. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final adding = widget.session == null;
    final error = _error;
    const gap = SizedBox(height: BrookieSpace.s5);
    return AdminFrame(
      maxWidth: BrookieSize.readingWidth,
      child: Form(
        key: _form,
        autovalidateMode: _triedToSave ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminHeading(adding ? 'Add a session' : 'Edit session', page: true),
            const SizedBox(height: BrookieSpace.s3),
            Text(
              'For family, friends and anyone not booked on the site. No payment needed.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: BrookieSpace.s6),
            TextFormField(
              controller: _name,
              focusNode: _nameFocus,
              style: _inputStyle(context),
              decoration: _decoration(
                context,
                label: 'Name',
                helper: 'Who it’s for, such as “The Harper family”.',
              ),
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              validator: _nameProblem,
            ),
            gap,
            TextFormField(
              controller: _email,
              focusNode: _emailFocus,
              style: _inputStyle(context),
              decoration: _decoration(context, label: 'Email', helper: 'The email they use to sign in to Google.'),
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              validator: _emailProblem,
            ),
            gap,
            DropdownButtonFormField<String?>(
              initialValue: _package,
              isExpanded: true,
              style: _inputStyle(context),
              decoration: _decoration(context, label: 'Package'),
              dropdownColor: BrookieColors.of(context).surface,
              // Material's grey otherwise; ink-soft like the date field's icon.
              iconEnabledColor: BrookieColors.of(context).inkSoft,
              borderRadius: BorderRadius.circular(BrookieRadius.sm),
              items: [
                const DropdownMenuItem(value: null, child: Text('No package')),
                for (final name in SessionRules.packageNames) DropdownMenuItem(value: name, child: Text(name)),
              ],
              onChanged: (value) => setState(() => _package = value),
            ),
            gap,
            FormField<DateTime>(
              initialValue: _date,
              validator: _dateProblem,
              builder: (field) => _DateField(
                value: field.value,
                errorText: field.errorText,
                focusNode: _dateFocus,
                onPressed: () => _chooseDate(field),
              ),
            ),
            gap,
            DropdownButtonFormField<_Time?>(
              initialValue: _time,
              isExpanded: true,
              style: _inputStyle(context),
              decoration: _decoration(context, label: 'Time'),
              dropdownColor: BrookieColors.of(context).surface,
              iconEnabledColor: BrookieColors.of(context).inkSoft,
              borderRadius: BorderRadius.circular(BrookieRadius.sm),
              // Five dozen times: a scrolling menu, not one taller than the window.
              menuMaxHeight: 360,
              items: [
                const DropdownMenuItem(value: null, child: Text('No time')),
                for (final time in _times)
                  DropdownMenuItem(value: time, child: Text(SessionTime.clockLabel(time.hour, time.minute))),
              ],
              onChanged: (value) => setState(() => _time = value),
            ),
            gap,
            TextFormField(
              controller: _location,
              focusNode: _locationFocus,
              style: _inputStyle(context),
              decoration: _decoration(context, label: 'Location (optional)'),
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _save(),
              validator: _locationProblem,
            ),
            const SizedBox(height: BrookieSpace.s6),
            Wrap(
              spacing: BrookieSpace.s3,
              runSpacing: BrookieSpace.s3,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                BusyButton(
                  label: adding ? 'Add session' : 'Save changes',
                  busyLabel: adding ? 'Adding session…' : 'Saving changes…',
                  busy: _saving,
                  kind: BusyButtonKind.filled,
                  onPressed: _save,
                ),
                TextButton(
                  onPressed: () => Navigator.maybePop(context),
                  child: const Text('Cancel'),
                ),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: BrookieSpace.s4),
              InlineMessage(message: error),
            ],
          ],
        ),
      ),
    );
  }
}

/// The session's day, shown like the form's other fields; pressing it (or
/// Enter or Space) opens the calendar.
class _DateField extends StatefulWidget {
  const _DateField({required this.value, required this.errorText, required this.focusNode, required this.onPressed});

  final DateTime? value;
  final String? errorText;
  final FocusNode focusNode;
  final VoidCallback onPressed;

  @override
  State<_DateField> createState() => _DateFieldState();
}

class _DateFieldState extends State<_DateField> {
  bool _hovered = false;

  void _open() {
    // Focused like a text field that's clicked, so focus comes back here
    // when the calendar closes.
    widget.focusNode.requestFocus();
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final open = CallbackAction<Intent>(onInvoke: (_) {
      _open();
      return null;
    });
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: FocusableActionDetector(
          focusNode: widget.focusNode,
          mouseCursor: SystemMouseCursors.click,
          onShowHoverHighlight: (value) => setState(() => _hovered = value),
          // The field's ink edge shows focus, as the text fields' does.
          onFocusChange: (focused) => setState(() {}),
          // On the web, Enter only activates buttons (ButtonActivateIntent).
          actions: {ActivateIntent: open, ButtonActivateIntent: open},
          child: GestureDetector(
            onTap: _open,
            behavior: HitTestBehavior.opaque,
            child: InputDecorator(
              decoration: _decoration(
                context,
                label: 'Date',
                errorText: widget.errorText,
                suffixIcon: Icon(Icons.event_outlined, color: BrookieColors.of(context).inkSoft),
              ),
              baseStyle: _inputStyle(context),
              isFocused: widget.focusNode.hasFocus,
              isHovering: _hovered,
              isEmpty: value == null,
              child: Text(value == null ? '' : formatDayShort(value, now: DateTime.now()), style: _inputStyle(context)),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Choose a date": a month calendar where any day from 2020 to a year
/// ahead can be chosen (sessions are often added after they happen), with
/// no openings to show.
class _DateDialog extends StatefulWidget {
  const _DateDialog({required this.initial, required this.now});

  final DateTime? initial;
  final DateTime now;

  @override
  State<_DateDialog> createState() => _DateDialogState();
}

class _DateDialogState extends State<_DateDialog> {
  // Opens on the session's day, or today: the calendar opens on that month.
  late DateTime _selected = widget.initial ?? DateTime(widget.now.year, widget.now.month, widget.now.day);

  @override
  Widget build(BuildContext context) {
    final now = widget.now;
    final initial = widget.initial;
    var first = DateTime(2020);
    var last = DateTime(now.year + 1, now.month, now.day);
    // A session dated outside the range keeps its day choosable.
    if (initial != null && initial.isBefore(first)) first = initial;
    if (initial != null && initial.isAfter(last)) last = initial;
    return BrookieDialog(
      title: 'Choose a date',
      content: [
        // As wide as the dialog allows, up to the calendar's widest.
        _UnmeasuredWidth(
          width: BookingCalendar.maxWidth,
          child: BookingCalendar(
            firstDay: first,
            lastDay: last,
            today: now,
            selectedDay: _selected,
            showOpenings: false,
            // The calendar hands back UTC midnights.
            onDaySelected: (day) => setState(() => _selected = DateTime(day.year, day.month, day.day)),
          ),
        ),
      ],
      dismissLabel: 'Cancel',
      action: FilledButton(
        onPressed: () => Navigator.of(context).pop(_selected),
        child: const Text('Use this date'),
      ),
    );
  }
}

/// Gives [child] (the calendar) [width] as its intrinsic width, and no
/// intrinsic height, without measuring it.
///
/// BrookieDialog fits itself to its content with IntrinsicWidth, which
/// can't measure the calendar: BookingCalendar and TableCalendar lay out
/// with LayoutBuilder. The calendar fills any width it's given, so its
/// widest stands in for a measurement; IntrinsicWidth only asks for the
/// height on the way to the width. The calendar's real layout is untouched.
class _UnmeasuredWidth extends SingleChildRenderObjectWidget {
  const _UnmeasuredWidth({required this.width, required super.child});

  final double width;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderUnmeasuredWidth(width);

  @override
  void updateRenderObject(BuildContext context, _RenderUnmeasuredWidth renderObject) => renderObject.width = width;
}

class _RenderUnmeasuredWidth extends RenderProxyBox {
  _RenderUnmeasuredWidth(this._width);

  double get width => _width;
  double _width;
  set width(double value) {
    if (value == _width) return;
    _width = value;
    markNeedsLayout();
  }

  @override
  double computeMinIntrinsicWidth(double height) => _width;

  @override
  double computeMaxIntrinsicWidth(double height) => _width;

  @override
  double computeMinIntrinsicHeight(double width) => 0;

  @override
  double computeMaxIntrinsicHeight(double width) => 0;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(Size(_width, 0));

  @override
  double? computeDryBaseline(BoxConstraints constraints, TextBaseline baseline) => null;
}
