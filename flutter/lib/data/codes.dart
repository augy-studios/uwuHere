// Event codes, as main-site/js/p2p.js and the server make them: six characters from an alphabet
// with no vowels and nothing that reads as another (no 0, O, 1, I).
const codeAlphabet = 'BCDFGHJKLMNPQRSTVWXYZ23456789';
const codeLength = 6;

String normaliseCode(String? input) {
  final s = (input ?? '').toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return s.length > codeLength ? s.substring(0, codeLength) : s;
}

bool isValidCode(String? input) {
  final code = normaliseCode(input);
  return code.length == codeLength && code.split('').every(codeAlphabet.contains);
}

/// What the home page says for a code that isn't one.
const badCodeMessage = 'An event code is 6 letters and numbers, like BCD234.';
