#!/usr/bin/env python3
"""Builds Miqat/Resources/cities.json from the GeoNames cities database.

Source:  https://download.geonames.org/export/dump/cities15000.zip
License: GeoNames data is Creative Commons Attribution 4.0
         (https://creativecommons.org/licenses/by/4.0/) — keep the
         attribution in README.md when regenerating.

Filter:  cities with population >= MIN_POPULATION, kept as compact records
         {n name, c country, la latitude, lo longitude, tz timezone, p population},
         sorted by population (desc) then name.

Run from anywhere:  python3 scripts/build_cities.py
"""

import io
import json
import os
import subprocess
import sys
import urllib.request
import zipfile

MIN_POPULATION = 50_000
SOURCE = "https://download.geonames.org/export/dump/cities15000.zip"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Miqat", "Resources", "cities.json")

# cities15000.txt columns (tab-separated) we care about:
# 1 name, 4 latitude, 5 longitude, 8 country code, 14 population, 17 timezone


def download(url: str) -> bytes:
    """curl first (uses the macOS system trust store — Python's framework
    build often lacks CA certs), urllib as fallback."""
    try:
        result = subprocess.run(["curl", "-fsSL", "--max-time", "120", url],
                                capture_output=True, check=True)
        return result.stdout
    except (OSError, subprocess.CalledProcessError):
        print("curl failed, falling back to urllib …")
        with urllib.request.urlopen(url, timeout=120) as response:
            return response.read()


def main() -> int:
    print(f"Downloading {SOURCE} …")
    payload = download(SOURCE)
    text = zipfile.ZipFile(io.BytesIO(payload)).read("cities15000.txt").decode("utf-8")

    cities = []
    for line in text.splitlines():
        cols = line.split("\t")
        try:
            population = int(cols[14])
            latitude = float(cols[4])
            longitude = float(cols[5])
        except (ValueError, IndexError):
            continue
        if population < MIN_POPULATION:
            continue
        cities.append({
            "n": cols[1],
            "c": cols[8],
            "la": latitude,
            "lo": longitude,
            "tz": cols[17],
            "p": population,
        })

    cities.sort(key=lambda c: (-c["p"], c["n"]))

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(cities, f, ensure_ascii=False, separators=(",", ":"))

    countries = {c["c"] for c in cities}
    print(f"Wrote {len(cities)} cities across {len(countries)} countries "
          f"({os.path.getsize(OUT) / 1024:.0f} KB) to {OUT}")

    morocco = [c["n"] for c in cities if c["c"] == "MA"]
    print(f"Sanity — Morocco ({len(morocco)}): {morocco[:12]}")
    for probe in ("Casablanca", "Istanbul", "Fès", "Fez"):
        match = next((c for c in cities if c["n"] == probe), None)
        print(f"Sanity — {probe}: {match}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
