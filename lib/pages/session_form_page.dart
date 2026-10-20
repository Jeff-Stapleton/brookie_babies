import 'dart:developer';
import 'dart:math' as math;

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
import 'package:brookie_babies/utilities/leave_warning.dart';
import 'package:brookie_babies/utilities/utils.dart';
import 'package:brookie_babies/widgets/brookie_dialog.dart';
import 'package:brookie_babies/widgets/busy_button.dart';
import 'package:brookie_babies/widgets/focus_ring.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:brookie_babies/widgets/top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

typedef _Time = ({int hour, int minute});

/// Adds an ad hoc session (family, friends: no purchase), or edits
/// [session]. Adding one opens its page, ready for photos.
///
/// Every field is checked against what firestore.rules accept
/// ([SessionRules]) before anything is saved.
class SessionFormPage extends StatelessWidget {
  const SessionFormPage({super.key, this.session, this.now});

  /// The ad hoc session to edit; null to add one.
  final Booking? session;

  /// The current time, which decides the calendar's today and range and how
  /// the chosen day reads. Defaults to the clock; tests pin it.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final adding = session == null;
    return Scaffold(
      // No way off the page from the account menu but signing out, which
      // asks first while there are changes to lose.
      appBar: BrookieTopBar(
        title: adding ? 'Add a session' : 'Edit session',
        showAdminLink: false,
        showSessionsLink: false,
      ),
      body: AdminGate(child: _SessionForm(session: session, now: now)),
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
  final googleProblem = SessionRules.googleEmailProblem(normalized);
  if (googleProblem != null) return googleProblem;
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
  const _SessionForm({required this.session, required this.now});

  final Booking? session;
  final DateTime? now;

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
  late final String? _startPackage =
      SessionRules.packageNames.contains(widget.session?.packageName) ? widget.session!.packageName : null;
  late String? _package = _startPackage;
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

  /// The new session's id, made on the first try to add it and used for
  /// every retry: a try that got no answer may still have been saved, and
  /// the same id never makes a second session.
  String? _newId;

  /// Once the admin has tried to save, each field is checked as it changes.
  bool _triedToSave = false;
  bool _saving = false;
  String? _error;

  /// Whether leaving would lose what's typed or chosen: on while any field
  /// differs from how the form started, until it's saved.
  bool _hasChanges = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    for (final text in [_name, _email, _location]) {
      text.addListener(_checkChanges);
    }
  }

  void _checkChanges() {
    final session = widget.session;
    final changed = !_saved &&
        (_name.text != (session?.name ?? '') ||
            _email.text != (session?.email ?? '') ||
            _location.text != (session?.location ?? '') ||
            _package != _startPackage ||
            _date != session?.date ||
            _time != session?.time);
    if (changed == _hasChanges) return;
    LeaveWarning.set(this, changed);
    setState(() => _hasChanges = changed);
  }

  /// Back (the top bar's, the browser's, Cancel) with changes to lose.
  Future<void> _confirmLeave() async {
    final leave = await showBrookieConfirm(
      context,
      title: 'Leave without saving?',
      message: widget.session == null
          ? 'The session you started adding will be lost.'
          : 'The changes you made to this session will be lost.',
      confirmLabel: 'Leave without saving',
      cancelLabel: 'Keep editing',
      destructive: true,
    );
    if (!leave || !mounted) return;
    // Navigator.pop leaves whatever PopScope says.
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    LeaveWarning.set(this, false);
    _name.dispose();
    _email.dispose();
    _location.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    _dateFocus.dispose();
    _locationFocus.dispose();
    super.dispose();
  }

  /// Read as it's needed: the form may stay open past midnight.
  DateTime get _now => widget.now ?? DateTime.now();

  Future<void> _chooseDate(FormFieldState<DateTime> field) async {
    final now = _now;
    final chosen = await showBrookieDialog<DateTime>(
      context,
      builder: (context) => _DateDialog(initial: _date, now: now),
    );
    if (chosen == null || !mounted) return;
    setState(() => _date = chosen);
    field.didChange(chosen);
    _checkChanges();
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
        final id = await admin.createSession(details, id: _newId ??= admin.newSessionId());
        if (!mounted) return;
        _markSaved();
        // Straight on to its photos; back from there is Admin, not this form.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (context) => AdminSessionPage(sessionId: id)),
        );
      } else {
        await admin.updateSession(session, details);
        if (!mounted) return;
        _markSaved();
        // Back to the session, past PopScope: nothing's left to lose. (With
        // nothing below, it stays, saved.)
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.pop();
        } else {
          setState(() => _saving = false);
        }
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

  void _markSaved() {
    _saved = true;
    _checkChanges();
  }

  @override
  Widget build(BuildContext context) {
    final adding = widget.session == null;
    final error = _error;
    const gap = SizedBox(height: BrookieSpace.s5);
    final form = AdminFrame(
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
              decoration: _decoration(
                context,
                label: 'Email',
                // The guest is matched by exact address. Google signs in a
                // Gmail address typed without its dots, but tells the app
                // the account's own, dots and all.
                helper: 'The email they use to sign in to Google. For Gmail, copy it exactly as it appears in '
                    'their Google account, dots included.',
              ),
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              validator: _emailProblem,
            ),
            gap,
            _Choice<String?>(
              label: 'Package',
              value: _package,
              options: [
                (value: null, label: 'No package'),
                for (final name in SessionRules.packageNames) (value: name, label: name),
              ],
              onChanged: (value) {
                setState(() => _package = value);
                _checkChanges();
              },
            ),
            gap,
            FormField<DateTime>(
              initialValue: _date,
              validator: _dateProblem,
              builder: (field) => _DateField(
                value: field.value,
                now: _now,
                errorText: field.errorText,
                focusNode: _dateFocus,
                onPressed: () => _chooseDate(field),
              ),
            ),
            gap,
            _Choice<_Time?>(
              label: 'Time',
              value: _time,
              // Five dozen times: a scrolling menu, not one taller than the window.
              menuMaxHeight: 360,
              options: [
                (value: null, label: 'No time'),
                for (final time in _times) (value: time, label: SessionTime.clockLabel(time.hour, time.minute)),
              ],
              onChanged: (value) {
                setState(() => _time = value);
                _checkChanges();
              },
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
    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmLeave();
      },
      child: form,
    );
  }
}

/// One of a [_Choice]'s options: what's saved, and what the admin reads.
typedef _Option<T> = ({T value, String label});

/// A field that opens a menu of [options] to choose one from (Package,
/// Time), shown like the form's other fields.
///
/// The menu is drawn like the account menu: no shadow (only photographs and
/// dialogs cast one), a line-strong edge, a ring on the option with keyboard
/// focus, and no animation. It works like a select on the web: Enter, Space
/// or an arrow key opens it on the chosen option; the arrow keys move
/// between options and wrap around, Home and End jump to the first and
/// last, and Enter chooses. Choosing, or Escape, closes it with focus back
/// on the field. Opened with a click or a tap, focus stays on the field.
class _Choice<T> extends StatefulWidget {
  const _Choice({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.menuMaxHeight = double.infinity,
  });

  final String label;
  final T value;
  final List<_Option<T>> options;
  final ValueChanged<T> onChanged;

  /// How tall the menu grows before it scrolls.
  final double menuMaxHeight;

  @override
  State<_Choice<T>> createState() => _ChoiceState<T>();
}

class _ChoiceState<T> extends State<_Choice<T>> {
  final _controller = MenuController();
  late final _fieldFocus = FocusNode(debugLabel: widget.label);
  late List<FocusNode> _optionFocus = _focusNodes();
  bool _hovered = false;

  List<FocusNode> _focusNodes() => [for (final option in widget.options) FocusNode(debugLabel: option.label)];

  @override
  void didUpdateWidget(_Choice<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options.length != widget.options.length) {
      _disposeOptionFocus();
      _optionFocus = _focusNodes();
    }
  }

  @override
  void dispose() {
    _fieldFocus.dispose();
    _disposeOptionFocus();
    super.dispose();
  }

  void _disposeOptionFocus() {
    for (final node in _optionFocus) {
      node.dispose();
    }
  }

  /// The chosen option's place in the menu (the first, if it isn't there).
  int get _chosen => math.max(0, widget.options.indexWhere((option) => option.value == widget.value));

  /// Opens the menu (if it isn't open) scrolled to the chosen option, and
  /// moves keyboard focus onto it if [focusChosen].
  void _open({required bool focusChosen}) {
    if (!_controller.isOpen) _controller.open();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.isOpen) return;
      final node = _optionFocus[_chosen];
      if (focusChosen) node.requestFocus();
      final option = node.context;
      if (option != null) Scrollable.ensureVisible(option, alignment: 0.5);
    });
  }

  /// A click or a tap: opens the menu, or closes it if it's open.
  void _toggle() {
    _fieldFocus.requestFocus();
    if (_controller.isOpen) {
      _controller.close();
    } else {
      _open(focusChosen: false);
    }
  }

  /// Moves focus [by] options, wrapping around at either end.
  void _move(int by) {
    final count = _optionFocus.length;
    final current = _optionFocus.indexWhere((node) => node.hasPrimaryFocus);
    final next = current < 0 ? (by > 0 ? 0 : count - 1) : (current + by) % count;
    requestFocusInView(_optionFocus[next]);
  }

  void _choose(T value) {
    _fieldFocus.requestFocus();
    if (value != widget.value) widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    final itemStyle = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered) ? c.surfaceSunk : Colors.transparent),
      foregroundColor: WidgetStatePropertyAll(c.ink),
      iconColor: WidgetStatePropertyAll(c.ink),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      // A real ring, like every other control, rather than a faint band.
      side: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused) ? brookieFocusSide(c.focus) : BorderSide.none),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(BrookieRadius.sm))),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: BrookieSpace.s3)),
      minimumSize: const WidgetStatePropertyAll(Size(0, kMinInteractiveDimension)),
      textStyle: WidgetStatePropertyAll(_inputStyle(context)),
      animationDuration: kBrookieStateDuration,
    );
    final open = CallbackAction<Intent>(onInvoke: (_) {
      _open(focusChosen: true);
      return null;
    });

    return LayoutBuilder(
      builder: (context, constraints) => MenuAnchor(
        controller: _controller,
        childFocusNode: _fieldFocus,
        // A click outside only closes the menu.
        consumeOutsideTap: true,
        crossAxisUnconstrained: false,
        alignmentOffset: const Offset(0, BrookieSpace.s1),
        style: MenuStyle(
          alignment: AlignmentDirectional.bottomStart,
          backgroundColor: WidgetStatePropertyAll(c.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          // No shadow, so the edge is what sets the menu apart from the
          // fields under it: an edge that carries meaning, so line-strong.
          elevation: const WidgetStatePropertyAll(0),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
          side: WidgetStatePropertyAll(BorderSide(color: c.lineStrong)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(BrookieRadius.md))),
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          visualDensity: VisualDensity.standard,
          // As wide as the field.
          minimumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, 0)),
          maximumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, widget.menuMaxHeight)),
        ),
        menuChildren: [
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
              const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
              const SingleActivator(LogicalKeyboardKey.home): () => requestFocusInView(_optionFocus.first),
              const SingleActivator(LogicalKeyboardKey.end): () => requestFocusInView(_optionFocus.last),
            },
            // The options sit in from the menu's edge so their focus ring
            // (2px out, past a 2px gap) isn't clipped.
            child: Padding(
              padding: const EdgeInsets.all(BrookieSpace.s2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, option) in widget.options.indexed)
                    MergeSemantics(
                      child: Semantics(
                        selected: option.value == widget.value,
                        child: MenuItemButton(
                          focusNode: _optionFocus[i],
                          // Hovering highlights a row; only the keyboard moves the ring.
                          requestFocusOnHover: false,
                          style: itemStyle,
                          trailingIcon: option.value == widget.value ? const Icon(Icons.check, size: 20) : null,
                          onPressed: () => _choose(option.value),
                          child: Text(option.label),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        builder: (context, controller, child) => CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowDown): () => _open(focusChosen: true),
            const SingleActivator(LogicalKeyboardKey.arrowUp): () => _open(focusChosen: true),
          },
          child: MergeSemantics(
            child: Semantics(
              button: true,
              expanded: controller.isOpen,
              child: FocusableActionDetector(
                focusNode: _fieldFocus,
                mouseCursor: SystemMouseCursors.click,
                onShowHoverHighlight: (value) => setState(() => _hovered = value),
                // The field's ink edge shows focus, as the text fields' does.
                onFocusChange: (focused) => setState(() {}),
                // On the web, Enter only activates buttons (ButtonActivateIntent).
                actions: {ActivateIntent: open, ButtonActivateIntent: open},
                child: GestureDetector(
                  onTap: _toggle,
                  behavior: HitTestBehavior.opaque,
                  child: InputDecorator(
                    decoration: _decoration(
                      context,
                      label: widget.label,
                      suffixIcon: Icon(Icons.arrow_drop_down, color: c.inkSoft),
                    ),
                    baseStyle: _inputStyle(context),
                    isFocused: _fieldFocus.hasFocus,
                    isHovering: _hovered,
                    child: Text(widget.options[_chosen].label, style: _inputStyle(context)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The session's day, shown like the form's other fields; pressing it (or
/// Enter or Space) opens the calendar.
class _DateField extends StatefulWidget {
  const _DateField({
    required this.value,
    required this.now,
    required this.errorText,
    required this.focusNode,
    required this.onPressed,
  });

  final DateTime? value;

  /// For how [value] reads (the year shows only when it isn't this one's).
  final DateTime now;
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
              child: Text(value == null ? '' : formatDayShort(value, now: widget.now), style: _inputStyle(context)),
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
