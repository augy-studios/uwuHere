// The site's small helpers (main-site/js/ui.js, host.js): times as the person's clock shows
// them, the big button's ink and label size, counting characters as the server does, and the CSV.
import 'dart:math' as math;

import 'package:flutter/material.dart';

String _two(int n) => n.toString().padLeft(2, '0');

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

DateTime? parseTime(String? iso) => iso == null || iso.isEmpty ? null : DateTime.tryParse(iso)?.toLocal();

/// "14:05" (the site's toLocaleTimeString with hour and minute; 24-hour, as en-GB writes it).
String formatTime(String? iso) {
  final d = parseTime(iso);
  return d == null ? '' : '${_two(d.hour)}:${_two(d.minute)}';
}

/// "16 Nov, 14:05".
String formatDateTime(String? iso) {
  final d = parseTime(iso);
  return d == null ? '' : '${d.day} ${_months[d.month - 1]}, ${_two(d.hour)}:${_two(d.minute)}';
}

/// "2026-11-16 14:05", the CSV's stamp.
String stamp(String? iso) {
  final d = parseTime(iso);
  return d == null ? '' : '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';
}

/// Code points, the way the server and the database count a limit.
int charCount(String value) => value.runes.length;

/// Black or white text for a host-chosen colour, whichever contrasts more (ui.js's inkFor).
Color inkFor(Color colour) {
  double channel(double c) => c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  final lum = 0.2126 * channel(colour.r) + 0.7152 * channel(colour.g) + 0.0722 * channel(colour.b);
  final withDark = (lum + 0.05) / (0.009 + 0.05);
  final withWhite = 1.05 / (lum + 0.05);
  return withDark >= withWhite ? const Color(0xFF121815) : Colors.white;
}

/// "#rrggbb" to a colour, or null.
Color? colourOf(String? hex) {
  final m = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(hex ?? '');
  if (m == null) return null;
  return Color(0xFF000000 | int.parse(m.group(1)!, radix: 16));
}

String hexOf(Color c) => '#${(c.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';

/// "#rrggbb" from what someone typed, or null. Takes 3 or 6 digits, # or not (colour-picker.js).
String? parseHex(String? text) {
  final m = RegExp(r'^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$').firstMatch((text ?? '').trim());
  if (m == null) return null;
  final d = m.group(1)!;
  final digits = d.length == 3 ? d.split('').map((c) => '$c$c').join() : d;
  return '#${digits.toLowerCase()}';
}

/// The big button's label size: short labels read large, the longest wrap at the smallest
/// (hereLabelSize, in the site's rem at 16 px).
double hereLabelSize(String label) {
  final n = charCount(label);
  if (n <= 8) return 33.6;
  if (n <= 14) return 27.2;
  return 22.4;
}

/// Input from another device or a person, as one line: control characters and runs of spaces
/// become one space. Null when it's longer than `max` (host.js's cleanLine).
String? cleanLine(Object? value, int max) {
  if (value is! String) return '';
  final clean = value.replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return charCount(clean) <= max ? clean : null;
}

/// join.js's cleanLine: spaces squeezed, no limit.
String squeeze(String? value) => (value ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

/// A CSV cell (host.js's csvCell). A cell that starts with = + - @ is a formula to a spreadsheet,
/// so it's defused with a leading apostrophe; names come from attendees.
String csvCell(Object? value) {
  var s = '${value ?? ''}';
  if (RegExp(r'^[=+\-@\t\r]').hasMatch(s)) s = "'$s";
  return RegExp(r'[",\r\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
}
