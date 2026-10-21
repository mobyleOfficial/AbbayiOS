# Test fixtures

## Christmastide.m4b

A real, chaptered m4b audiobook used to test metadata and chapter parsing against an actual
file rather than a hand-built `AudioModel`.

| | |
|---|---|
| Source | https://archive.org/details/christmastide__2204_librivox |
| Original file | `ChristmasTide_librivox.m4b` (unmodified, byte-for-byte) |
| Licence | **Public domain.** LibriVox recordings are released into the public domain, as are the underlying 19th-century texts. |
| Size | 6.5 MB |
| Duration | 831.6 s |

### Metadata

- title: `ChristmasTide_librivox`
- album: `Christmastide: Containing Four Famous Poems By Favorite American Poets`
- artist: `Various`
- artwork: none

### Chapters

Four chapters, distinct titles, contiguous with no gaps:

| # | start (s) | duration (s) |
|---|---|---|
| 0 | 0.000 | 144.015 |
| 1 | 144.015 | 143.997 |
| 2 | 288.012 | 223.009 |
| 3 | 511.021 | 320.602 |

### Why this file

Chapter coverage was the deciding factor. Most small LibriVox items are single-section works
with exactly one chapter, which leaves `currentChapter(for:)`, next/previous-chapter intents
and the CarPlay chapter list untestable. This one has four real chapters at a modest size.

Note the chapter locale is `und` (undetermined), which is typical for LibriVox m4b files.
`FileLoader.loadChapterMetadata` handles that by appending the asset's own locale from
`availableChapterLocales` to `Locale.preferredLanguages` before matching — without that step
the system's language matching returns zero chapters for this file. That behaviour is now
covered by `FileLoaderTests`, so the fixture guards it against regression.

## LibriVox/ (API fixtures)

Trimmed real responses from the LibriVox and archive.org APIs, used by `LibriVoxClientTests` and
`LibriVoxBookMappingTests`. All recorded 2026-10-21. No network access happens in tests.

| File | Source |
|---|---|
| `search_alice.json` | `https://librivox.org/api/feed/audiobooks/?format=json&extended=1&title=^alice` |
| `not_found.json` | `https://librivox.org/api/feed/audiobooks/?format=json&extended=1&title=^zzzqq` (HTTP 404, unmodified) |
| `archive_alice_metadata.json` | `https://archive.org/metadata/alice_in_wonderland_librivox` |

### Hand edits

- `search_alice.json`: trimmed from 23 books to LibriVox ids 200, 900 and 1122 (real entries, unmodified).
  Two entries were **added by hand** for the drop test, both copies of id 200:
  - id `9001`, title `Hand-edited: no archive URL`, with `url_iarchive` set to `""`.
  - id `9002`, title `Hand-edited: empty section listen_url`, with the second section's `listen_url` set to `""`.
- `archive_alice_metadata.json`: `files[]` cut to the 12 real `wonderland_ch_NN_64kb.mp3` entries (sizes sum to
  85,862,932 bytes) plus three unrelated files (`AliceInWonderland_librivox.m4b`, `wonderland_ch_01.mp3`,
  `__ia_thumb.jpg`) so matching by file name is exercised. The `reviews`, `simplelists`, `alternate_locations`
  and `workable_servers` keys were removed. Nothing else was changed.
- `not_found.json`: not edited.

### Bundling

`project.yml` excludes `Fixtures/**` from the `AbbayTests` source group (it was `Fixtures/*`, which left files in
subfolders ungrouped and broke the resource references). XcodeGen flattens the folder, so tests load the JSON
from the bundle root via `TestFixtures.librivoxData(_:)`, which also tries a `LibriVox` subdirectory.
