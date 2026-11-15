// The Updates page reads each release's notes as announcements/release-notes-<version>.md writes
// them: a summary, then groups of titled items, with the Markdown taken out.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uwuhere/features/update/release_notes.dart';

void main() {
  for (final v in ['1.0.0', '1.0.1', '1.0.2', '1.0.3', '2.0.0', '2.0.1']) {
    test('$v: a summary and groups of titled items, the download table and install steps left out', () {
      final n = ReleaseNotes.parse(File('../announcements/release-notes-$v.md').readAsStringSync());
      expect(n.summary, isNotEmpty);
      expect(n.summary, isNot(contains('|')));
      expect(n.groups, isNotEmpty);
      for (final g in n.groups) {
        expect(g.items, isNotEmpty);
        for (final i in g.items) {
          expect(i.title, isNotEmpty);
          expect('${i.title}${i.text}', isNot(contains('**')));
          expect('${i.title}${i.text}', isNot(contains('`')));
          expect('${i.title}${i.text}', isNot(contains('](')));
        }
      }
    });
  }

  test('2.0.0: its three groups, in order', () {
    final n = ReleaseNotes.parse(File('../announcements/release-notes-2.0.0.md').readAsStringSync());
    expect(n.summary, startsWith("uwuHere's apps, rebuilt"));
    expect(n.groups.map((g) => g.title), ['Android app', 'Windows, macOS and Linux apps', 'Everywhere']);
    expect(n.groups.first.items.first.title, 'A real app');
  });
}
