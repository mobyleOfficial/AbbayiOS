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
