// Event codes, as main-site/js/p2p.js and the server make them: six characters from an alphabet
// with no vowels and nothing that reads as another (no 0, O, 1, I).
const codeAlphabet = 'BCDFGHJKLMNPQRSTVWXYZ23456789';
const codeLength = 6;

/// What someone typed, as a code: upper case, letters and digits only, at most [codeLength] long.
String normaliseCode(String? input) {
  String typedText;
  if (input == null) {
    typedText = '';
  } else {
    typedText = input;
  }
  final cleanedCode = typedText.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (cleanedCode.length > codeLength) {
    return cleanedCode.substring(0, codeLength);
  }
  return cleanedCode;
}

bool isValidCode(String? input) {
  final code = normaliseCode(input);
  return code.length == codeLength && code.split('').every(codeAlphabet.contains);
}

/// What the home page says for a code that isn't one.
const badCodeMessage = 'An event code is 6 letters and numbers, like BCD234.';
