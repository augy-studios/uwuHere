# Announcements

What's said about each release, one file per kind and version, as written. All of it in British
English (en-GB).

| File | Where it goes |
|---|---|
| `release-notes-<version>.md` | The GitHub release's description (release/README.md, "Publishing a version"). Its first paragraph is the summary. The Android app's Updates page shows that, and under `## What's new` (or `What's fixed`) a card for each `###` heading with its `- **Title**: text` lines, so keep to that shape |
| `announcement-<version>.md` | The UwU Apps Telegram channel, pasted as it is. Short lines, no Markdown: Telegram shows it plain. The first release of a version line opens with ✨NEW✨, every one after it with ✨UPDATE✨ |
| `play-release-notes-<version>.md` | Play Console's **Release notes** box, the block inside the code fence (GOOGLE-PLAY.md) |

Write all three for a release of the apps; a release that changes only the website needs just the
announcement.

`release-notes-1.0.0.md` to `release-notes-1.0.3.md` are the Capacitor app's descriptions as they
were published on GitHub, kept for the record. Their Telegram announcements weren't kept in the
repository, so there's none here for them.
