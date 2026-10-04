import 'package:flutter/services.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const _monthsFull = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

class GroupedAmountFormatter extends TextInputFormatter {
  const GroupedAmountFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text.replaceAll(',', '');
    if (raw.isEmpty) return const TextEditingValue(text: '');
    if (!RegExp(r'^\d*\.?\d{0,2}$').hasMatch(raw)) return oldValue;
    final dot = raw.indexOf('.');
    final whole = dot == -1 ? raw : raw.substring(0, dot);
    final fraction = dot == -1 ? '' : raw.substring(dot);
    final text = '${_groupDigits(whole)}$fraction';
    final end = newValue.selection.baseOffset.clamp(0, newValue.text.length);
    final digitsBefore = newValue.text.substring(0, end).replaceAll(',', '').length;
    var offset = 0;
    var seen = 0;
    while (offset < text.length && seen < digitsBefore) {
      if (text[offset] != ',') seen += 1;
      offset += 1;
    }
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

String _groupDigits(String whole) {
  if (whole.isEmpty) return '';
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
    buffer.write(whole[i]);
  }
  return buffer.toString();
}

String money(num value, {bool accounting = false}) {
  final negative = value < 0;
  final fixed = value.abs().toStringAsFixed(2).split('.');
  final whole = fixed[0];
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
    buffer.write(whole[i]);
  }
  final text = '$buffer.${fixed[1]}';
  if (!negative) return 'Rs. $text';
  if (accounting) return '-Rs. $text';
  return 'Rs. -$text';
}

String shortRange(DateTime from, DateTime to) {
  String part(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')} ${_months[value.month - 1]}';
  return '${part(from)} - ${part(to)}';
}

String longDay(DateTime value) =>
    '${_weekdays[value.weekday - 1]}, ${value.day} ${_monthsFull[value.month - 1]}';

String monthTitle(DateTime value) => '${_monthsFull[value.month - 1]} ${value.year}';

String stamp(DateTime value) {
  final now = DateTime.now();
  final today = now.year == value.year && now.month == value.month && now.day == value.day;
  final day = today
      ? 'Today, ${value.day} ${_months[value.month - 1]} ${value.year}'
      : '${value.day} ${_months[value.month - 1]} ${value.year}';
  return '$day  |  ${clock(value)}';
}

String clock(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  final suffix = value.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $suffix';
}

String syncedLabel(DateTime? synced) {
  if (synced == null) return 'Not synced yet';
  final seconds = DateTime.now().difference(synced).inSeconds;
  if (seconds < 15) return 'Last synced: Just now';
  if (seconds < 60) return 'Last synced: ${seconds}s ago';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return 'Last synced: ${minutes}m ago';
  return 'Last synced: ${minutes ~/ 60}h ago';
}

String monthKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}';
