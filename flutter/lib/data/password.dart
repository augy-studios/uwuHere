// The live checklist under a host password field (main-site/js/password.js), which mirrors
// api/_lib/password.js, the final say: after NIST SP 800-63B-4, 14 characters or more, no rules
// about digits or symbols, and nothing predictable. The breach check only runs on the server.
// Change all three together.
import 'format.dart';

const passwordMin = 14;
const passwordMax = 128;

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
String squash(String text) => text.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

bool _isRepeat(String text) => RegExp(r'^(.{1,6}?)\1+.{0,6}$', unicode: true).hasMatch(text);

bool _isRun(String text) {
  if (text.length < 4) return false;
  for (final run in _runs) {
    final loop = run * ((text.length * 2 / run.length).ceil() + 2);
    final back = loop.split('').reversed.join();
    if (loop.contains(text) || back.contains(text)) return true;
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
  bool get ok => checks.every((c) => c.ok);
}

PasswordResult checkPassword(String password, {String title = '', String code = ''}) {
  final length = charCount(password);
  final plain = squash(password);
  final own = ['uwuhere', squash(title), squash(code)].where((w) => w.length >= 4).toList();
  final typed = length > 0;
  return PasswordResult([
    PasswordCheck(
      length >= passwordMin && length <= passwordMax,
      length > passwordMax ? 'At most $passwordMax characters' : '$passwordMin characters or more${length < passwordMin ? ' ($length so far)' : ''}',
    ),
    PasswordCheck(typed && !_isRepeat(plain) && !_isRun(plain), 'Not a repeat or a run like 12345 or qwerty'),
    PasswordCheck(typed && !own.any(plain.contains), "Leaves out the event's name and code"),
  ]);
}
