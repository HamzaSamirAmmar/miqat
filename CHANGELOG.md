# Changelog

All notable changes to Miqat are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project uses [Semantic Versioning](https://semver.org).

## [1.0.1] — 2026-09-25

### Fixed
- Close popover on unfocus (clicking outside, switching applications, or deactivation), matching macOS Control Center and Wi-Fi behavior
- Ensure the popover always reopens to a fresh schedule rather than retaining previous subscreen navigation (such as Location Chooser or Settings)

### Added
- Time-end reminders (off by default): a plain notification with the default
  sound a configurable number of minutes (5–90, default 30) before a prayer's
  window closes — Fajr ends at Shuruq, Dhuhr at Asr, Asr at Maghrib, Maghrib
  at Isha, and Isha at the next Fajr. Per-prayer toggles in Settings ›
  Reminders, localized in English and Arabic
- Duha (الضحى) reminder: a separate toggle with a fixed, non-configurable
  20-minute lead before Dhuhr — independent of the other reminders
- "Stop Adhan" action button on the adhan notification banner, localized in
  English and Arabic — silences the adhan without activating the app
- Location-aware default calculation method: the method picker now offers
  "Automatic", which follows the selected country's convention (e.g. Umm
  al-Qura in Saudi Arabia, ISNA in the US and Canada, Karachi in South Asia,
  Muslim World League in Syria and unlisted countries); an explicit pick
  overrides it, persists, and re-selecting "Automatic" returns to the
  country default
- Clearer location picker with three explicit modes — **City**,
  **Automatic**, **Coordinates** — and a "current location" card that shows
  which one is active. Automatic mode re-detects each time the Mac starts
  or wakes, so prayer times follow you when you travel
- City search in Arabic and by country: "الرباط", "مكه", "Syria", "سوريا",
  "Tripoli, Lebanon". Spelling variants (hamza, ta marbuta, harakat, a
  missing "ال") don't matter. City and country names follow the UI language
- Coordinates mode: live preview of the resolved place and time zone, and
  pasting "33.5138, 36.2765" from a maps app fills both fields

### Changed
- `scripts/build_cities.py` adds Arabic names from GeoNames alternate names

## [1.0.0] — 2026-09-24

### Added
- Live countdown to the next prayer in the macOS menu bar — three themes:
  *Icon* (mihrab glyph only, countdown in the tooltip), *Countdown* (`1:23`),
  and *Labeled* (`Asr 1:23`)
- Arabic & English interface with an in-app language switcher (System /
  English / العربية), localized prayers, calculation methods, and madhab,
  Arabic Hijri + Gregorian dates, and full right-to-left layout
- Today's full schedule — Fajr, Shuruq, Dhuhr, Asr, Maghrib, Isha — with the
  next prayer highlighted, Gregorian + Hijri date header, and the day rolling
  over at the *location's* midnight
- Location: auto-detect via CoreLocation (one-shot), offline city search over
  a bundled database of 12,386 cities (GeoNames, CC BY 4.0), or fully-offline
  manual coordinates with timezone inferred from the nearest notable city
- 12 calculation methods (MWL, Umm al-Qura, ISNA, Egyptian, Karachi, Dubai,
  Qatar, Kuwait, Moonsighting Committee, Singapore/Malaysia, Turkey, Tehran)
  and Asr madhab (Shafi / Hanafi)
- Prayer times computed locally with
  [adhan-swift](https://github.com/batoulapps/adhan-swift) — no internet
  required after picking a city
- Directional icons (chevrons, next-prayer marker) flip for RTL, layouts
  verified overflow-free in both languages
- Runs as a menu bar agent (`LSUIElement`) — no Dock icon
- Built-in "Start at Login" toggle (`SMAppService`, macOS 13+)
- 31 tests: reference times against the official Umm al-Qura timetable,
  place persistence round-trips, offline city search, localization key
  parity, and theme migration

### Fixed
- Location detection no longer crashes (a `Place` conforming to both
  `Codable` and `RawRepresentable` recursed infinitely while persisting)
