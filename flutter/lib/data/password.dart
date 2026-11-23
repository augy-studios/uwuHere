// The live checklist under a host password field (main-site/js/password.js), which mirrors
// api/_lib/password.js, the final say: after NIST SP 800-63B-4, 14 characters or more, no rules
// about digits or symbols, and nothing predictable. The breach check only runs on the server.
// Change all three together.
import 'format.dart';

const passwordMinimumLength = 14;
const passwordMaximumLength = 128;

/// Sequences a password mustn't be a stretch of, forwards or backwards: the alphabet, the digits,
/// and rows and columns of a keyboard.
const _runs = [
  'abcdefghijklmnopqrstuvwxyz',
  '0123456789',
  'qwertyuiop',
  'asdfghjkl',
  'zxcvbnm',
  'qwertyuiopasdfghjklzxcvbnm',
  '1qaz2wsx3edc4rfv5tgb6yhn7ujm8ik9ol0p',
];

/// Lower case, letters and digits only (the site's NFKC step is left to the server: Dart has no
/// normaliser, and the checks here are advice).
String squash(String text) {
  return text.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
}

/// A short piece said over and over ("abab…", "123123…"), with at most a few characters after.
bool _isRepeat(String text) {
  return RegExp(r'^(.{1,6}?)\1+.{0,6}$', unicode: true).hasMatch(text);
}

/// Whether the text is a stretch of one of [_runs], forwards or backwards, wrapping round its end
/// ("yzabc" counts).
bool _isRun(String text) {
  if (text.length < 4) {
    return false;
  }
  for (final run in _runs) {
    final repeatedRun = run * ((text.length * 2 / run.length).ceil() + 2);
    final reversedRun = repeatedRun.split('').reversed.join();
    if (repeatedRun.contains(text) || reversedRun.contains(text)) {
      return true;
    }
  }
  return false;
}

class PasswordCheck {
  const PasswordCheck(this.ok, this.text);
  final bool ok;
  final String text;
}

class PasswordResult {
  const PasswordResult(this.checks);
  final List<PasswordCheck> checks;
  bool get ok {
    return checks.every((check) {
      return check.ok;
    });
  }
}

/// The checklist's three lines for a password as typed so far: its length, no repeat or run, and
/// none of the event's own words in it.
PasswordResult checkPassword(String password, {String title = '', String code = ''}) {
  final length = charCount(password);
  final plain = squash(password);
  final ownWords = ['uwuhere', squash(title), squash(code)].where((word) {
    return word.length >= 4;
  }).toList();
  final typed = length > 0;

  String lengthText;
  if (length > passwordMaximumLength) {
    lengthText = 'At most $passwordMaximumLength characters';
  } else if (length < passwordMinimumLength) {
    lengthText = '$passwordMinimumLength characters or more ($length so far)';
  } else {
    lengthText = '$passwordMinimumLength characters or more';
  }

  return PasswordResult([
    PasswordCheck(length >= passwordMinimumLength && length <= passwordMaximumLength, lengthText),
    PasswordCheck(typed && !_isRepeat(plain) && !_isRun(plain), 'Not a repeat or a run like 12345 or qwerty'),
    PasswordCheck(typed && !ownWords.any(plain.contains), "Leaves out the event's name and code"),
  ]);
}
