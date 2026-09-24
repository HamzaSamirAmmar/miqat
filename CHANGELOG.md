# Changelog

All notable changes to Miqat are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project uses [Semantic Versioning](https://semver.org).

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
