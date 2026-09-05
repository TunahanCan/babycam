import 'package:flutter/material.dart';

/// Uses the active app locale and the device's explicit 24-hour preference.
String formatLocalTime(BuildContext context, DateTime time) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(time.toLocal()),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

/// Older history entries need a date as well as a clock time to be unambiguous.
String formatAlertTimestamp(BuildContext context, int timestampMs,
    {DateTime? now}) {
  final time = DateTime.fromMillisecondsSinceEpoch(timestampMs);
  final today = (now ?? DateTime.now()).toLocal();
  final clock = formatLocalTime(context, time);
  if (DateUtils.isSameDay(time, today)) return clock;
  final date = MaterialLocalizations.of(context).formatCompactDate(time);
  return '$date · $clock';
}
