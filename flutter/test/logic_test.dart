// The logic ported from the site (main-site/js/*.js), checked against what the site's code gives
// for the same input: codes (p2p.js), the password checklist (password.js), the CSV's cells
// (host.js), the big button's ink and label size (ui.js), links (the app's own, links.dart), and
// the event's alert topic (app-notify.js).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uwuhere/app/links.dart';
import 'package:uwuhere/data/codes.dart';
import 'package:uwuhere/data/format.dart';
import 'package:uwuhere/data/password.dart';
import 'package:uwuhere/features/notify/host_alerts.dart';

void main() {
  test('codes: normalised as the site does, and only its alphabet', () {
    expect(normaliseCode(' bcd-234 '), 'BCD234');
    expect(normaliseCode('bcd2345678'), 'BCD234');
    expect(isValidCode('BCD234'), isTrue);
    expect(isValidCode('ABC123'), isFalse); // A, 1: not in the alphabet
    expect(isValidCode('BCD23'), isFalse);
  });

  test('password checklist: length, runs and repeats, the event\'s own words', () {
    expect(checkPassword('correct horse battery staple').ok, isTrue);
    expect(checkPassword('short').ok, isFalse);
    expect(checkPassword('qwertyuiopasdf').checks[1].ok, isFalse);
    expect(checkPassword('abababababababab').checks[1].ok, isFalse);
    expect(checkPassword('the weekly meetup is great', title: 'Weekly meetup').checks[2].ok, isFalse);
    expect(checkPassword('mango river lantern BCD234', code: 'BCD234').checks[2].ok, isFalse);
    expect(checkPassword('x' * 129).checks[0].text, 'At most 128 characters');
  });

  test('CSV cells: formulas defused, quotes and commas quoted', () {
    expect(csvCell('=SUM(A1)'), "'=SUM(A1)");
    expect(csvCell('+44 20'), "'+44 20");
    expect(csvCell('Tan, Alex'), '"Tan, Alex"');
    expect(csvCell('say "hi"'), '"say ""hi"""');
    expect(csvCell(null), '');
  });

  test('the big button: black or white ink, and the label size', () {
    expect(inkFor(const Color(0xFFCCFFCC)), const Color(0xFF121815));
    expect(inkFor(const Color(0xFF1A237E)), Colors.white);
    expect(hereLabelSize("I'm here"), 33.6);
    expect(hereLabelSize('Present and correct'), 22.4);
    expect(parseHex('ccf'), '#ccccff');
    expect(parseHex('#12AB3G'), isNull);
  });

  test('cleanLine: control characters and spaces squeezed, and the limit', () {
    expect(cleanLine('  Alex\n\tTan  ', 60), 'Alex Tan');
    expect(cleanLine('x' * 61, 60), isNull);
    expect(cleanLine(42, 60), '');
  });

  test('links: the site\'s pages, uwu://here/ and codes typed in', () {
    expect(parseLink('https://here.uwuapps.org/join?id=bcd234&tap=1763251200.abcdefgh.sig'), isA<LinkJoin>());
    final joinLink = parseLink('https://here.uwuapps.org/join?id=bcd234&tap=1763251200.abcdefgh.sig') as LinkJoin;
    expect(joinLink.code, 'BCD234');
    expect(joinLink.tap, '1763251200.abcdefgh.sig');
    expect((parseLink('uwu://here/host?id=BCD234') as LinkHost).code, 'BCD234');
    expect((parseLink('https://here.uwuapps.org/#join') as LinkHome).focus, 'join');
    expect(parseLink('https://here.uwuapps.org/privacy'), isA<LinkOut>());
    expect(parseLink('uwu://cue/'), isNull);
    expect((parseLink('BCD234') as LinkJoin).code, 'BCD234');
    expect(parseLink('/host?id=BCD234'), isA<LinkHost>());
  });

  test('an event\'s alert topic: uwuhere-host- and 40 hex digits of the host key\'s SHA-256', () {
    // The same as main-site/js/app-notify.js's hostTopic for this key.
    expect(HostAlerts.topic('abc'), 'uwuhere-host-ba7816bf8f01cfea414140de5dae2223b00361a3');
  });
}
