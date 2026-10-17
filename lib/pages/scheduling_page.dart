import 'dart:developer';

import 'package:flutter/material.dart';

import 'package:table_calendar/table_calendar.dart';

import 'package:brookie_babies/components/account_button.dart';
import 'package:brookie_babies/components/session_list.dart';
import 'package:brookie_babies/components/sign_in_dialog.dart';
import 'package:brookie_babies/services/app_services.dart';
import 'package:brookie_babies/services/payment_links.dart';
import 'package:brookie_babies/utilities/utils.dart';

class SchedulingPage extends StatefulWidget {
  const SchedulingPage({super.key, required this.packageName});

  final String packageName;

  @override
  _SchedulingPageState createState() => _SchedulingPageState();
}

class _SchedulingPageState extends State<SchedulingPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  /// Opens the package's Stripe Payment Link, asking the visitor to sign in
  /// first so the payment can be matched to their account.
  Future<void> navigateCheckout() async {
    if (!kPaymentLinks.containsKey(widget.packageName)) {
      log('Unknown package type');
      return;
    }
    final services = AppServices.of(context);
    final user = services.auth.currentUser ?? await showSignInDialog(context);
    if (user == null || !mounted) return;

    final uri = paymentLinkUri(widget.packageName, uid: user.uid, email: user.email)!;
    // Same tab: after the sign-in dialog, opening a new tab is no longer part
    // of the tap, so the browser could block it as a popup.
    await services.openUrl(uri, webOnlyWindowName: '_self');
  }

  bool handleSelectedDayPredicate(DateTime day) {
    return isSameDay(_selectedDay, day);
  }

  void handleonDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!isSameDay(_selectedDay, selectedDay)) {
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
      });
    }
  }

  void handleonPageChanged(DateTime focusedDay) {
    _focusedDay = focusedDay;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick a Session Time'),
        actions: const [AccountButton(), SizedBox(width: 16)],
      ),
      body: Column(
        children: [
          TableCalendar(
            firstDay: kFirstDay,
            lastDay: kLastDay,
            focusedDay: _focusedDay,
            selectedDayPredicate: handleSelectedDayPredicate,
            onDaySelected: handleonDaySelected,
            onPageChanged: handleonPageChanged,
          ),
          Expanded(
            child: SessionList(sessionDate: _selectedDay ?? _focusedDay, onSessionSelected: navigateCheckout),
          ),
        ],
      ),
    );
  }
}