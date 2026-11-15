// What's new in a release, for the Updates page, from its notes on GitHub as
// announcements/release-notes-<version>.md writes them: the first paragraph as the summary, and
// under "## What's new" (or "What's fixed", "What's changed") each "###" heading as a group of its
// items, "- **Title**: text" as a title and its text. Plain text, the Markdown taken out. The same
// as notesOf() in sgbus-timings' main-site/api/_lib/release.js, done here so it reads the site's
// /api/app-release as it is.

class ReleaseItem {
  ReleaseItem(this.title, this.text);
  final String title;
  String text;
}

class ReleaseGroup {
  ReleaseGroup(this.title);
  final String title;
  final List<ReleaseItem> items = [];
}

class ReleaseNotes {
  ReleaseNotes(this.summary, this.groups);
  final String summary;
  final List<ReleaseGroup> groups;

  int get count => groups.fold(0, (n, g) => n + g.items.length);

  static String plain(String s) => s
      .replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m[1]!)
      .replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m[1]!)
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!)
      .replaceAllMapped(RegExp(r'(^|[\s(])_([^_]+)_(?=[\s).,:;]|$)'), (m) => '${m[1]}${m[2]}')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static ReleaseNotes parse(String? body) {
    final text = (body ?? '').replaceAll('\r\n', '\n');
    final first = text.trim().split(RegExp(r'\n\s*\n')).first;
    final summary = first.startsWith('#') || first.startsWith('|') ? '' : plain(first);
    final groups = <ReleaseGroup>[];
    final at = RegExp(r"^##\s+What.s (new|fixed|changed)\s*$", multiLine: true, caseSensitive: false).firstMatch(text);
    if (at != null) {
      ReleaseGroup? group;
      for (final line in text.substring(at.end).split('\n')) {
        if (RegExp(r'^##\s').hasMatch(line)) break;
        final head = RegExp(r'^###\s+(.+)').firstMatch(line);
        if (head != null) {
          groups.add(group = ReleaseGroup(plain(head[1]!)));
          continue;
        }
        final item = RegExp(r'^[-*]\s+(.+)').firstMatch(line);
        if (item != null) {
          if (group == null) groups.add(group = ReleaseGroup('What’s new'));
          final titled = RegExp(r'^\*\*(.+?)\*\*\s*[:.]?\s*(.*)$').firstMatch(item[1]!);
          group.items.add(
            titled != null ? ReleaseItem(plain(titled[1]!).replaceFirst(RegExp(r'[:.]$'), ''), plain(titled[2]!)) : ReleaseItem('', plain(item[1]!)),
          );
        } else if (group != null && group.items.isNotEmpty && RegExp(r'^\s+\S').hasMatch(line)) {
          // A line carried on, or a point under the item: part of the item.
          final last = group.items.last;
          last.text = '${last.text} ${plain(line.replaceFirst(RegExp(r'^\s*[-*]\s+'), ''))}'.trim();
        }
      }
    }
    return ReleaseNotes(summary, groups.where((g) => g.items.isNotEmpty).toList());
  }
}
