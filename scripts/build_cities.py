#!/usr/bin/env python3
"""Builds Miqat/Resources/cities.json from the GeoNames cities database.

Source:  https://download.geonames.org/export/dump/cities15000.zip
License: GeoNames data is Creative Commons Attribution 4.0
         (https://creativecommons.org/licenses/by/4.0/) — keep the
         attribution in README.md when regenerating.

Filter:  cities with population >= MIN_POPULATION, kept as compact records
         {n name, a arabic name?, c country, la latitude, lo longitude,
          tz timezone, p population}, sorted by population (desc) then name.

Arabic:  names come from GeoNames alternateNamesV2 (isolanguage "ar"),
         preferring names flagged preferred/short and skipping colloquial
         or historic ones. The file is ~200 MB; set GEONAMES_DIR to a folder
         holding cities15000.zip and alternateNamesV2.zip to reuse downloads.

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
ALT_SOURCE = "https://download.geonames.org/export/dump/alternateNamesV2.zip"
LOCAL_DIR = os.environ.get("GEONAMES_DIR")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Miqat", "Resources", "cities.json")

# cities15000.txt columns (tab-separated) we care about:
# 0 geonameid, 1 name, 4 latitude, 5 longitude, 8 country code, 14 population, 17 timezone


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


def fetch(url: str) -> bytes:
    """Reads GEONAMES_DIR/<file> when present, else downloads."""
    if LOCAL_DIR:
        path = os.path.join(LOCAL_DIR, os.path.basename(url))
        if os.path.exists(path):
            print(f"Using local {path}")
            with open(path, "rb") as f:
                return f.read()
    print(f"Downloading {url} …")
    return download(url)


# Arab League members: untagged Arabic-script aliases there are Arabic, so
# they may stand in as the display name when no "ar"-tagged name exists.
ARAB_COUNTRIES = set("AE BH DJ DZ EG EH IQ JO KM KW LB LY MA MR OM PS QA SA SD SO SY TN YE".split())

# Letters used by Persian, Urdu, Kurdish, Pashto… but not Arabic. Aliases
# containing them are dropped so search stays Arabic.
NON_ARABIC_LETTERS = set("پچژگکیۀہےںٹڈڑۃەۆێڵڕۇۈۋېۅټځڅښږ")


def is_arabic(name: str) -> bool:
    has_arabic = any("\u0621" <= ch <= "\u064A" for ch in name)
    return has_arabic and not (set(name) & NON_ARABIC_LETTERS) and "(" not in name


def arabic_names(wanted: set) -> dict:
    """geonameid -> [Arabic names], best first. Ranking: preferred > short
    > plain, and "الX" over a bare "X"; colloquial and historic names are
    skipped."""
    archive = zipfile.ZipFile(io.BytesIO(fetch(ALT_SOURCE)))
    found = {}
    with archive.open("alternateNamesV2.txt") as raw:
        for line in io.TextIOWrapper(raw, encoding="utf-8"):
            cols = line.rstrip("\n").split("\t")
            if len(cols) < 8 or cols[2] != "ar" or cols[1] not in wanted:
                continue
            if cols[6] == "1" or cols[7] == "1":
                continue
            name = cols[3].strip()
            if not is_arabic(name):
                continue
            score = (cols[4] == "1") * 2 + (cols[5] == "1")
            found.setdefault(cols[1], []).append((score, name))

    result = {}
    for gid, entries in found.items():
        names = {name for _, name in entries}

        def rank(entry):
            score, name = entry
            has_article_twin = name.startswith("ال") and name[2:] in names
            return (-score, not has_article_twin)

        ordered = []
        for _, name in sorted(entries, key=rank):
            if name not in ordered:
                ordered.append(name)
        result[gid] = ordered
    return result


def main() -> int:
    payload = fetch(SOURCE)
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
            "id": cols[0],
            "n": cols[1],
            "c": cols[8],
            "la": latitude,
            "lo": longitude,
            "tz": cols[17],
            "p": population,
            "_aliases": [a for a in cols[3].split(",") if is_arabic(a)],
        })

    arabic = arabic_names({c["id"] for c in cities})
    for city in cities:
        tagged = arabic.get(city.pop("id"), [])
        aliases = city.pop("_aliases")
        if not tagged and city["c"] in ARAB_COUNTRIES and aliases:
            tagged = aliases[:1]
        if tagged:
            city["a"] = tagged[0]
        # Extra spellings for search only ("رباط" finds "الرباط").
        extra = [a for a in dict.fromkeys(tagged[1:] + aliases) if a != city.get("a")]
        if extra:
            city["x"] = extra[:4]
    named = sum("a" in c for c in cities)
    searchable = sum("a" in c or "x" in c for c in cities)
    print(f"Arabic: {named} display names, {searchable} searchable, of {len(cities)} cities")

    cities.sort(key=lambda c: (-c["p"], c["n"]))

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(cities, f, ensure_ascii=False, separators=(",", ":"))

    countries = {c["c"] for c in cities}
    print(f"Wrote {len(cities)} cities across {len(countries)} countries "
          f"({os.path.getsize(OUT) / 1024:.0f} KB) to {OUT}")

    morocco = [c["n"] for c in cities if c["c"] == "MA"]
    print(f"Sanity — Morocco ({len(morocco)}): {morocco[:12]}")
    for probe in ("Casablanca", "Istanbul", "Fès", "Fez", "Damascus", "Rabat"):
        match = next((c for c in cities if c["n"] == probe), None)
        print(f"Sanity — {probe}: {match}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
