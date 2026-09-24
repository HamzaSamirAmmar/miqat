# Miqat

A tiny macOS menu bar app that shows how long remains until the next prayer:

```
Asr 1:23
```

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

## Features

- **Live countdown to the next prayer** in the menu bar, always visible
  - *Labeled* — `Asr 1:23`
  - *Compact* — `🕌 1:23`
- **Today's full schedule** — Fajr, Shuruq, Dhuhr, Asr, Maghrib, Isha — with
  the next prayer highlighted and the Gregorian + Hijri dates
- **Location** — auto-detected once via CoreLocation, or search any city with
  the built-in geocoder (no API keys)
- **12 calculation methods** — Muslim World League, Umm al-Qura (Makkah),
  ISNA, Egyptian, Karachi, Dubai, Qatar, Kuwait, Moonsighting Committee,
  Singapore/Malaysia, Turkey (Diyanet), Tehran
- **Asr madhab** — Shafi (Standard) or Hanafi
- Times computed **locally** with
  [adhan-swift](https://github.com/batoulapps/adhan-swift) (MIT) — works fully
  offline once your city is set; the day rolls over at the *location's*
  midnight, in the location's time zone

## Privacy

Location is used once to resolve your city and never leaves the Mac. City
search uses Apple's geocoder, which needs a brief network call — everything
else (time calculation, countdown) is pure local math.

## Credits

- Prayer time calculation:
  [adhan-swift](https://github.com/batoulapps/adhan-swift) by Batoul Apps
  (MIT), based on *Astronomical Algorithms* by Jean Meeus
- Reference test data: Umm al-Qura University official timetable
  (ummulqura.org.sa), as compiled in the adhan test suite

## Building

Requires Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
xcodegen generate
xcodebuild -project Miqat.xcodeproj -scheme Miqat build
```

Or via the Swift Package Manager (compiles the sources and runs the tests):

```sh
swift build
swift test
```

## License

[MIT](LICENSE)
