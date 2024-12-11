import 'dart:developer';

import 'package:flutter/material.dart';

import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utilities/utils.dart';
import '../components/session_list.dart';

class SchedulingPage extends StatefulWidget {
  const SchedulingPage({super.key, required this.packageName});

  final String packageName;

  @override
  _SchedulingPageState createState() => _SchedulingPageState();
}

class _SchedulingPageState extends State<SchedulingPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

Future<void> _navigateToUrl(String url) async {
  final Uri uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  } else {
    log('Could not launch $url');
  }
}

void navigateCheckout() {
  switch (widget.packageName) {
    case 'Basic':
      _navigateToUrl('https://buy.stripe.com/7sI7tD0KTfBedwccMM');
      break;
    case 'Premium':
      _navigateToUrl('https://buy.stripe.com/9AQ9BL9hpbkY4ZGeUV');
      break;
    case 'Ultimate':
      _navigateToUrl('https://buy.stripe.com/aEUcNXctB74IfEk002');
      break;
    default:
      log('Unknown package type');
  }
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
          SessionList(sessionDate: _selectedDay ?? _focusedDay, onSessionSelected: navigateCheckout),
        ],
      ),
    );
  }
}