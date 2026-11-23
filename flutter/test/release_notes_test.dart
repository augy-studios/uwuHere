// The Updates page reads each release's notes as announcements/release-notes-<version>.md writes
// them: a summary, then groups of titled items, with the Markdown taken out.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uwuhere/features/update/release_notes.dart';

void main() {
  for (final version in ['1.0.0', '1.0.1', '1.0.2', '1.0.3', '2.0.0', '2.0.1', '2.0.4']) {
    test('$version: a summary and groups of titled items, the download table and install steps left out', () {
      final notes = ReleaseNotes.parse(File('../announcements/release-notes-$version.md').readAsStringSync());
      expect(notes.summary, isNotEmpty);
      expect(notes.summary, isNot(contains('|')));
      expect(notes.groups, isNotEmpty);
      for (final group in notes.groups) {
        expect(group.items, isNotEmpty);
        for (final item in group.items) {
          expect(item.title, isNotEmpty);
          expect('${item.title}${item.text}', isNot(contains('**')));
          expect('${item.title}${item.text}', isNot(contains('`')));
          expect('${item.title}${item.text}', isNot(contains('](')));
        }
      }
    });
  }

  test('2.0.0: its three groups, in order', () {
    final notes = ReleaseNotes.parse(File('../announcements/release-notes-2.0.0.md').readAsStringSync());
    expect(notes.summary, startsWith("uwuHere's apps, rebuilt"));
    final groupTitles = notes.groups.map((group) {
      return group.title;
    });
    expect(groupTitles, ['Android app', 'Windows, macOS and Linux apps', 'Everywhere']);
    expect(notes.groups.first.items.first.title, 'A real app');
  });
}
