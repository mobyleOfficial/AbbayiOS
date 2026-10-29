# App Store listing

The App Store Connect listing for Abbay (app Apple ID 6826877030, bundle `com.edyuto.Abbay`).
It isn't part of the app bundle or the Xcode project.

The text files use fastlane `deliver`'s metadata layout, so they can be uploaded with
`bundle exec fastlane deliver --metadata_path StoreConfig --skip_binary_upload --skip_screenshots`
once an App Store Connect API key is set up (#111). Until then, copy and paste them by hand.

## Copy rules

- **Lead with free public-domain audiobooks:** LibriVox search, download, offline listening.
- **No Siri or CarPlay in the listing.** They work, but stay unadvertised until the device
  checks pass (#90, #201, #178). They appear only in the private review notes.
- **Every feature named must exist in the app.** There's no sleep timer, so it isn't claimed.
- **Both languages:** every text exists in `en-US` and `pt-BR`.
- **Apple's limits:**
  - name and subtitle: 30 characters each
  - promotional text: 170
  - keywords: 100, comma-separated
  - description: 4000

## Files

| File (per language) | App Store Connect field |
|---|---|
| `name.txt` | Name |
| `subtitle.txt` | Subtitle |
| `promotional_text.txt` | Promotional Text (editable without a new version) |
| `description.txt` | Description |
| `keywords.txt` | Keywords |
| `marketing_url.txt` / `support_url.txt` / `privacy_url.txt` | Marketing URL / Support URL / Privacy Policy URL |

These don't depend on language:
- `copyright.txt`
- `primary_category.txt` / `secondary_category.txt`
- `review_information/` (review notes and contact email)

## Settings that aren't text files

| Where | Answer | Why |
|---|---|---|
| App Privacy | **Data Not Collected** | The privacy policy: no accounts, analytics, ads or tracking |
| Export compliance | Nothing to upload | `ITSAppUsesNonExemptEncryption = NO` in `Info.plist`; HTTPS through the system is exempt |
| License agreement | Apple's standard EULA | No subscriptions or accounts |
| Content rights | Contains third-party content, has the rights | LibriVox recordings and texts are public domain |
| Price | Free, all territories | |

### Age rating

Abbay can play anything in the LibriVox catalogue, so the rating follows what the catalogue can contain:

| Question | Answer |
|---|---|
| Mature or Suggestive Themes | Infrequent |
| Horror/Fear Themes | Infrequent |
| Profanity or Crude Humour | Infrequent |
| Sexual Content or Nudity | Infrequent |
| Graphic Sexual Content and Nudity | None |
| Cartoon or Fantasy Violence | Infrequent |
| Realistic Violence | Infrequent |
| Prolonged Graphic or Sadistic Realistic Violence | None |
| Guns or Other Weapons | Infrequent |
| Everything else (gambling, drugs, medical, contests, user-generated content, messaging, web access, ads) | None / No |

The graphic categories stay at None: the app plays narrated literature with no explicit imagery, and
anything above None there would make the app 18+. The expected result is 13+.

## Screenshots

| Slot | Size | Required |
|---|---|---|
| iPhone with Dynamic Island (medium display) | 1206 × 2622 | **Yes** |
| iPhone with Dynamic Island (large display) | 1320 × 2868 | No (scaled from medium otherwise) |
| iPad 13-inch | 2064 × 2752 (portrait) | **Yes** (Abbay is universal since 1.2.0) |
| iPhone Duo, outer display | 1398 × 2034 | Not yet (from April 2027 with the iOS 27.1 SDK) |
| iPhone Duo, inner display | 2853 × 2007 (landscape) | Not yet |

Screenshots must have no alpha channel: upload JPEGs, or PNGs flattened to RGB.

The images are in `screenshots/<language>/`, named `<slot>_<n>-<screen>.jpg`:

- `iphone-6.3`: upload to "iPhone with Dynamic Island (medium display)"
- `iphone-6.9`: upload to "iPhone with Dynamic Island (large display)"
- `ipad-13`: upload to "iPad 13-inch"
- `duo-outer`: upload to the iPhone Duo outer display
- `duo-inner`: upload to the iPhone Duo inner display

The order is library (with Continue, the hero book playing), player, chapter list, LibriVox search,
then a book page. On the iPad and the unfolded Duo the player opens beside the library and the
chapters beside the player (the adaptive layout of 1.2.0 and 1.3.0).

- **en-US:** the English classics from the landing-page footage (*Pride and Prejudice* playing,
  Popular on LibriVox, *Dracula*'s page).
- **pt-BR:** a library of Brazilian books, the same as the landing page's Portuguese clips:
  - Machado de Assis, José de Alencar, Lima Barreto, Euclides da Cunha, Aluísio Azevedo, Raul Pompéia;
  - *Dom Casmurro* playing;
  - a search for "Machado de Assis";
  - *O Alienista*'s page.

The iPhone sets were captured from 1.0.1 (en-US) and 1.0.3 (pt-BR); their portrait layout hasn't
changed. The Duo and iPad sets are from 1.3.0, with `capture.sh`.

### Capturing

```bash
StoreConfig/screenshots/capture.sh <simulator-udid> <en-US|pt-BR> <slot> [library-udid]
```

- **What it does:** builds the app and its UI tests, copies the demo library from `[library-udid]`
  (a simulator whose Abbay holds it), sets a 9:41 status bar, and runs
  `StoreScreenshotsUITests/test_storeScreens`. The test drives the five screens and asks for each
  shot; the script takes it with `xcrun simctl io screenshot` and writes the JPEGs above.
- **Why `simctl`:** on the unfolded iPhone Duo, XCUITest's own screenshots show the dark outer
  display; `simctl` sees the inner one.
- **Libraries:** the English and Brazilian libraries live on the local simulators *Abbay-landing*
  and *Abbay-landing-pt* (built by downloading the books in the app). They aren't in the repo:
  they hold gigabytes of LibriVox audio.
- **The Duo's posture** is set by hand in DeviceHub (fold or unfold the simulator first); there is no
  `simctl` command for it.
- **iPad:** use a 13-inch iPad simulator; it opens the app full screen (a smaller one can open a
  window). The test allows Siri's permission alert on a fresh simulator.
- **Nothing is downloaded or deleted,** so a rerun starts from the same state.
