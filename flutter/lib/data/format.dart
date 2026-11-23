// The site's small helpers (main-site/js/ui.js, host.js): times as the person's clock shows
// them, the big button's ink and label size, counting characters as the server does, and the CSV.
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A number as at least two digits: 7 -> "07".
String _twoDigits(int number) {
  return number.toString().padLeft(2, '0');
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// An ISO 8601 time from the server, on the person's own clock; null when there's none or it
/// can't be read.
DateTime? parseTime(String? isoTime) {
  if (isoTime == null || isoTime.isEmpty) {
    return null;
  }
  final parsed = DateTime.tryParse(isoTime);
  if (parsed == null) {
    return null;
  }
  return parsed.toLocal();
}

/// "14:05" (the site's toLocaleTimeString with hour and minute; 24-hour, as en-GB writes it).
String formatTime(String? isoTime) {
  final time = parseTime(isoTime);
  if (time == null) {
    return '';
  }
  return '${_twoDigits(time.hour)}:${_twoDigits(time.minute)}';
}

/// "16 Nov, 14:05".
String formatDateTime(String? isoTime) {
  final time = parseTime(isoTime);
  if (time == null) {
    return '';
  }
  return '${time.day} ${_months[time.month - 1]}, ${_twoDigits(time.hour)}:${_twoDigits(time.minute)}';
}

/// "2026-11-16 14:05", the CSV's stamp.
String stamp(String? isoTime) {
  final time = parseTime(isoTime);
  if (time == null) {
    return '';
  }
  return '${time.year}-${_twoDigits(time.month)}-${_twoDigits(time.day)} ${_twoDigits(time.hour)}:${_twoDigits(time.minute)}';
}

/// Code points, the way the server and the database count a limit.
int charCount(String value) {
  return value.runes.length;
}

/// Black or white text for a host-chosen colour, whichever contrasts more (ui.js's inkFor).
Color inkFor(Color colour) {
  // One colour channel (0 to 1) as linear light, the sRGB way, for the relative luminance below.
  double linearChannel(double channelValue) {
    if (channelValue <= 0.03928) {
      return channelValue / 12.92;
    }
    return math.pow((channelValue + 0.055) / 1.055, 2.4).toDouble();
  }

  final luminance = 0.2126 * linearChannel(colour.r) + 0.7152 * linearChannel(colour.g) + 0.0722 * linearChannel(colour.b);
  final contrastWithDark = (luminance + 0.05) / (0.009 + 0.05);
  final contrastWithWhite = 1.05 / (luminance + 0.05);
  if (contrastWithDark >= contrastWithWhite) {
    return const Color(0xFF121815);
  }
  return Colors.white;
}

/// "#rrggbb" to a colour, or null.
Color? colourOf(String? hex) {
  String hexText;
  if (hex == null) {
    hexText = '';
  } else {
    hexText = hex;
  }
  final match = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(hexText);
  if (match == null) {
    return null;
  }
  return Color(0xFF000000 | int.parse(match.group(1)!, radix: 16));
}

/// A colour as "#rrggbb", dropping its opacity.
String hexOf(Color colour) {
  return '#${(colour.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';
}

/// "#rrggbb" from what someone typed, or null. Takes 3 or 6 digits, # or not (colour-picker.js).
String? parseHex(String? text) {
  String typedText;
  if (text == null) {
    typedText = '';
  } else {
    typedText = text;
  }
  final match = RegExp(r'^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$').firstMatch(typedText.trim());
  if (match == null) {
    return null;
  }
  final matchedDigits = match.group(1)!;
  String digits;
  if (matchedDigits.length == 3) {
    // "ccf" is short for "ccccff": each digit doubled.
    digits = matchedDigits.split('').map((digit) {
      return '$digit$digit';
    }).join();
  } else {
    digits = matchedDigits;
  }
  return '#${digits.toLowerCase()}';
}

/// The big button's label size: short labels read large, the longest wrap at the smallest
/// (hereLabelSize, in the site's rem at 16 px).
double hereLabelSize(String label) {
  final labelLength = charCount(label);
  if (labelLength <= 8) {
    return 33.6;
  }
  if (labelLength <= 14) {
    return 27.2;
  }
  return 22.4;
}

/// Input from another device or a person, as one line: control characters and runs of spaces
/// become one space. Null when it's longer than `maximumLength` (host.js's cleanLine).
String? cleanLine(Object? value, int maximumLength) {
  if (value is! String) {
    return '';
  }
  final clean = value.replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (charCount(clean) <= maximumLength) {
    return clean;
  }
  return null;
}

/// join.js's cleanLine: spaces squeezed, no limit.
String squeeze(String? value) {
  String text;
  if (value == null) {
    text = '';
  } else {
    text = value;
  }
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// A CSV cell (host.js's csvCell). A cell that starts with = + - @ is a formula to a spreadsheet,
/// so it's defused with a leading apostrophe; names come from attendees.
String csvCell(Object? value) {
  String cellText;
  if (value == null) {
    cellText = '';
  } else {
    cellText = '$value';
  }
  if (RegExp(r'^[=+\-@\t\r]').hasMatch(cellText)) {
    cellText = "'$cellText";
  }
  // A comma, quote or line break would split the cell, so it's quoted, with its quotes doubled.
  if (RegExp(r'[",\r\n]').hasMatch(cellText)) {
    return '"${cellText.replaceAll('"', '""')}"';
  }
  return cellText;
}
