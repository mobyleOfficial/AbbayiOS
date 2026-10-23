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

Trimmed real responses from archive.org and the LibriVox API, used by `LibriVoxClientTests`,
`LibriVoxClientDetailsTests` and `LibriVoxBookMappingTests`. Recorded 2026-10-23 unless noted. No
network access happens in tests.

| File | Source | Used for |
|---|---|---|
| `archive_search_wonderland.json` | `https://archive.org/advancedsearch.php?q=collection:librivoxaudio AND mediatype:audio AND (title:(wonderland*) OR creator:(wonderland*))&fl[]=identifier,title,creator,language,mediatype&sort[]=downloads desc&rows=50&page=1&output=json` | search results, title cleanup |
| `archive_popular.json` | `https://archive.org/advancedsearch.php?q=collection:librivoxaudio&fl[]=identifier,title,creator,language,mediatype&sort[]=downloads desc&rows=8&page=1&output=json` | popular filter |
| `archive_alice_metadata.json` | `https://archive.org/metadata/alice_in_wonderland_librivox` | matched path (with the Carroll feed), fallback ordering when LibriVox has no match |
| `librivox_author_carroll.json` | `https://librivox.org/api/feed/audiobooks/?format=json&extended=1&author=Carroll&limit=100&offset=0&fields={id,url_iarchive,sections,description}` | matched path: LibriVox id 200 lists `alice_in_wonderland_librivox` |
| `archive_1891_metadata.json` | `https://archive.org/metadata/1891_collection_bt_librivox` | fallback path (creator "Various") |
| `librivox_author_various.json` | `https://librivox.org/api/feed/audiobooks/?format=json&extended=1&author=Various&limit=100&offset=0&fields={id,url_iarchive,sections,description}` | fallback path: no entry for `1891_collection_bt_librivox` |
| `not_found.json` | `https://librivox.org/api/feed/audiobooks/?format=json&extended=1&title=^zzzqq` (HTTP 404, recorded 2026-10-21) | a LibriVox ID that no longer exists |

### Hand edits

- `archive_search_wonderland.json`: `docs` cut from 18 to the first 5. Nothing else changed.
- `archive_popular.json`: not edited. It is the popular query **without** the `mediatype:audio`
  clause the app sends, so it still holds the collection's non-book items
  (`LibrivoxM4bCollectionAudiobooksMain`, `thumbs12`) and exercises the client-side filter too.
- `archive_alice_metadata.json`, `archive_1891_metadata.json`: `files[]` cut to the `64Kbps MP3`
  entries (Alice: 12, sizes sum to 85,862,932 bytes; 1891: 10) plus a few unrelated files
  (Alice: `AliceInWonderland_librivox.m4b`, `wonderland_ch_01.mp3`, `__ia_thumb.jpg`; 1891:
  `__ia_thumb.jpg`) so matching by format and file name is exercised. The `reviews`, `simplelists`,
  `alternate_locations` and `workable_servers` keys were removed. `metadata` is unchanged.
- `librivox_author_carroll.json`: `books` cut from 47 to ids 200, 423 and 443, unmodified.
- `librivox_author_various.json`: `books` cut from 100 to ids 106 and 248, each cut to its first
  three sections. With fewer than 100 books the client stops after one page; the multi-page cap is
  tested with generated pages instead.
- `not_found.json`: not edited.

### Bundling

`project.yml` excludes `Fixtures/**` from the `AbbayTests` source group (it was `Fixtures/*`, which left files in
subfolders ungrouped and broke the resource references). XcodeGen flattens the folder, so tests load the JSON
from the bundle root via `TestFixtures.librivoxData(_:)`, which also tries a `LibriVox` subdirectory.
