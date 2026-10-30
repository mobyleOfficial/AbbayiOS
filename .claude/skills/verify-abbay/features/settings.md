# Settings

`SettingsView` is a sheet opened by the library toolbar's gear (`library.toolbar.settings`). It
paints no backgrounds of its own (no `scrollContentBackground(.hidden)`, no `onyx` row fills,
#166 G7), so the system draws its grouped look: glass on iOS 26, the dark grouped list before. The root
(`AppRootView`) presents it, outside the part of the tree a language change rebuilds, so it stays
open while the language switches. Its model is `SettingsViewModel`; the settings themselves are
`AppSettings`, injected through `DependencyContainer.settings` and the SwiftUI environment, and
persisted through the storage layer's `KeyValueStoring` (`LocalStorage.preferences`, the app's
`UserDefaults`; `InMemoryKeyValueStore` in tests and under `-resetSettings`).

## Sub-features

- **playback:**
  - **Default speed for new books** (`settings.playback.defaultSpeed`): a page with the same
    `SpeedControlView` as the player's speed sheet. A book takes the default the first time it
    plays and keeps it as its own speed, so changing the default later only reaches books not yet
    played.
  - **Skip back / Skip forward** (`settings.playback.skipBack`, `settings.playback.skipForward`):
    menu pickers of 10, 15, 30 or 45 seconds (default 15). Each has `.id(language)`: a menu picker
    built from a `ForEach` otherwise kept its selected value ("15 segundos") in the old language
    after a switch (#179). They drive the player's two skip
    buttons (icon `gobackward.N` / `goforward.N`, label *Skip back N seconds*), and through
    `NowPlayingManager.setSkipIntervals` the lock screen's and CarPlay's skip commands
    (`preferredIntervals`) and their handlers.
- **downloads:**
  - **Large downloads on cellular** (`settings.downloads.cellular`): Ask (the per-book prompt, the
    default) / Always / Wi-Fi only (pt-BR *Downloads grandes no celular*: Perguntar / Sempre / Só
    Wi-Fi). An input to `CellularDownloadPolicy.decide(...preference:)`;
    applies only to books over `largeDownloadThreshold` (99 MB). Read when Download is tapped.
    The row is a whole-row `Menu` holding the picker, not a menu `Picker`: a Form put a menu
    picker's value on a line of its own under a label that didn't fit beside it (pt-BR, #189), and
    `LabeledContent` did the same. Now the value stays on the trailing side and the row is as tall as
    its neighbours; on an iPhone SE (3rd gen) the pt-BR label wraps onto two lines beside the value,
    like *Velocidade padrão para novos livros*. VoiceOver: label *Large downloads on cellular*, value
    the option. Verified by `SettingsUITests.test_cellularPicker_keepsItsValueBesideTheLabel` (en and
    pt-BR: label, value, and a row under 1.5 times *Space used*'s height).
  - **Space used** (`settings.downloads.spaceUsed`): the size of `LibriVoxIdentity.defaultRoot`,
    measured off the main thread each time the sheet opens (*Calculating…* until then). Sizes here
    (this row, the footer's 99 MB, the delete confirmation) are formatted by `ByteSize.text` in the
    in-app language (`AbbayBundle.locale`), not the device's (#152): `ByteCountFormatter` has no
    locale and always used the device's decimal separator.
  - **Delete finished downloads** (`settings.downloads.deleteFinished`): LibriVox books that are
    fully downloaded AND whose saved position is within 30 s of the end
    (`DownloadHousekeeping`). Disabled when there are none. Asks first (alert: Delete
    `settings.downloads.deleteConfirm` / Cancel `settings.downloads.deleteCancel`); deleting goes
    through `MediaListViewModel.deleteAudio`, the swipe-delete path, so the books leave the library
    with their files (a download-only delete would be re-downloaded by `restore()` at launch).
- **language:** an inline picker, *Padrão do sistema / English / Português (Brasil)*
  (`settings.language.{system,english,portuguese}`). `AbbayBundle.languageCode` points
  `Localizable` at that `.lproj`. Applies at once, no relaunch: the root re-identifies the tabs and
  the player (`.id(settings.language)`), and this sheet re-reads its strings. System-drawn strings
  (alert buttons the system owns, the search field's Cancel) and Siri phrases keep the device
  language. CarPlay's own strings follow the in-app language, also when it changes while connected
  (`.appLanguageDidChange`, see [carplay](carplay.md) *language*); the CarPlay system chrome is the
  device's.
  The choice is stored (`abbay.settings.language` in standard defaults) and applied at the next
  launch before anything draws. Only strings follow it: colors and spacing load from
  `AbbayBundle.resources`, the app bundle, because the `.lproj` holds no plists (#155: the next
  launch after choosing a language used to trap in `ConstantsProtocol`). **Evidence:** set the
  key, then cold-launch:
  `xcrun simctl spawn <udid> defaults write com.edyuto.Abbay abbay.settings.language -string pt-BR`;
  the library opens as *Biblioteca*, no crash report.
- **experimental** (iOS 26 and later only; earlier systems don't draw the section):
  **Read-along** (`settings.experimental.readAlong`, pt-BR *Leitura acompanhada*): a switch bound to
  `AppSettings.readAlongEnabled`, off by default. The footer says what it does: the text is made on
  the device from the audio, can get words wrong, nothing is sent, the microphone is never used,
  and iOS may download a language's speech model the first time. Switching it off deletes every
  transcript. Between Language and About. Value `"0"` / `"1"`.
- **about:**
  - **Privacy policy** (`settings.about.privacyPolicy`): https://mobyleapps.com/abbay/privacy-policy/
    in an `SFSafariViewController`.
  - **Version** (`settings.about.version`): `CFBundleShortVersionString (CFBundleVersion)`.
  - **LibriVox** (`settings.about.librivox`): librivox.org in Safari; the section footer credits
    LibriVox volunteers and the public domain.
  - **Open-source licenses** (`settings.about.licenses` → `settings.about.licenses.body`): Abbay
    ships no third-party code (no SPM packages; `Modules/NetworkProvider` is first-party; the
    Gemfile's tools are build-time only).
  - **About the developer** (`settings.about.developer`): a row that pushes a page with a short
    note (`settings.about.developer.body`: Abbay is free, no ads, no tracking; say hi) and a
    *Say hi on LinkedIn* button (`settings.about.linkedIn`) that opens `SettingsView.linkedInURL`
    (https://www.linkedin.com/in/edyuto) in the same in-app Safari as the privacy policy. pt-BR:
    *Sobre o desenvolvedor* / *Diga oi no LinkedIn*. Verified by
    `SettingsUITests.test_developerPage_showsItsTitleBodyAndButton` (button not tapped) and
    `SettingsValuesTests.test_linkedInURL_isTheDevelopersHTTPSProfile`.
  - **Siri & audio** (`settings.about.audioStatus`): *Working* or *Unavailable*, read from
    `LaunchStateFlag` (#115), with a plain-words explanation that Siri answers "Audio temporarily
    unavailable" until a book plays again.

## How to get to it (user POV)

Library tab → gear (top right) → Settings. **Done** closes it; so does a swipe down.

On iOS 27.1 (seen on the iPhone Duo, not on the iPhone 17 / iOS 27.0) the navigation bar hides
its title and Done while the form is scrolled down, and they come back at the top. That is the
system's, not the app's: a UI test scrolls back up before tapping `settings.done`
(`closeSettings()` in `SettingsUITests`). On the Duo the sheet's tree also carries a
`PopoverDismissRegion`; it is still a sheet (`.sheet` in `AppRootView`), drawn inset by 8 pt.

## Driving it with abbay-ctl

```bash
$B launch --seed-library --reset-settings
$B tap library.toolbar.settings && $B wait settings.done
$B tap settings.playback.skipForward && $B tap-label "30 seconds"
$B tap settings.done
$B tap library.row.0.title && $B wait player.transport.forward   # label "Skip forward 30 seconds"
$B tap settings.language.portuguese                               # nav title becomes "Ajustes"
```

**Verified** (`SettingsUITests`): `library.toolbar.settings` opens it; `settings.done`,
`settings.playback.{defaultSpeed,skipBack,skipForward}`,
`settings.downloads.{cellular,spaceUsed,deleteFinished}`, `settings.language.system`,
`settings.about.{privacyPolicy,version,librivox,licenses,developer,audioStatus}` and
`settings.about.licenses.body` resolve; on iOS 26+ `settings.experimental.readAlong` is off by
default, toggles, and its footer mentions the microphone (microfone in pt-BR)
(`test_experimental_*`); changing Skip forward relabels the player's forward
button; choosing Português switches Settings and the Library without a relaunch; on a pt-BR
device choosing English relabels both skip pickers to "15 seconds" at once
(`test_switchingLanguage_relabelsTheSkipPickers`).

**Implemented but unverified in UI tests:** the delete confirmation (seeded books are never
finished downloads, and the stub download manager writes nothing), the Safari pages, and
*Unavailable* in the audio row (no launch argument fails the audio session). Covered by
`SettingsViewModelTests`, `DownloadHousekeepingTests`, `AppSettingsTests`.

## Gotchas

- **`-resetSettings`** keeps settings in memory for that launch. Without it a UI test that changes
  the language or a skip amount leaks it into later launches (and into the unit-test host, which
  is the real app: `LocalizationTests` resets `AbbayBundle.languageCode` in `setUp` for that reason).
- **Per-book speeds are not in Core Data.** They live in `AppSettings` (`abbay.settings.bookSpeeds`),
  keyed by the book URL, and are dropped by `DeleteAudioUseCase`. A book re-added with the same URL
  (LibriVox identities are stable) starts from the default again. The key is the book's identity,
  the URL its row was saved under, so a book whose file moved keeps its speed; one saved under a
  moved file's resolved URL before #186 is moved to the row's URL on the first load
  (`MovedBookKeyMigration`, `AppSettings.moveSpeed(from:to:)`).
- **Skip amounts apply to the lock screen at launch**: `AppSettings.init` pushes them through
  `LiveSettingsEffects`, so they don't wait for a change in Settings.
