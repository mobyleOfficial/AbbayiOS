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
| iPhone Duo, outer display | 1398 × 2034 | Not yet (from April 2027 with the iOS 27.1 SDK) |
| iPhone Duo, inner display | 2853 × 2007 (landscape) | Not yet |

Screenshots must have no alpha channel: upload JPEGs, or PNGs flattened to RGB.

The images are in `screenshots/<language>/`, named `<slot>_<n>-<screen>.jpg`:

- `iphone-6.3`: upload to "iPhone with Dynamic Island (medium display)"
- `iphone-6.9`: upload to "iPhone with Dynamic Island (large display)"
- `duo-outer`: upload to the iPhone Duo outer display. A retake after the clipped-grid fix is
  tracked in #251.
- `duo-inner`: upload to the iPhone Duo inner display

The order is library (with Continue), player, chapter list, LibriVox search, then book detail.

- **en-US:** captured from the 1.0.1 release build with the English classics from the landing-page footage (*Pride and Prejudice* playing, *Dracula*'s page).
- **pt-BR:** captured from the 1.0.3 release build with a library of Brazilian books, the same as the landing page's Portuguese clips:
  - Machado de Assis, José de Alencar, Lima Barreto, Euclides da Cunha, Aluísio Azevedo, Raul Pompéia;
  - *Dom Casmurro* playing;
  - a search for "Machado de Assis";
  - *O Alienista*'s page.

  The 6.3" set is native (iPhone 17); the 6.9" and Duo sets are from the same library copied to those simulators.
The capture tooling isn't in the repo yet (#252).
