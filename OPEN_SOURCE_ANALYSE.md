# Code-Analyse für Open-Source-Vorbereitung

**Datum:** 2026-03-04  
**Projekt:** ParkLibre (Flutter)  
**Analyst:** Senior Developer Perspective

---

## 1. Code-Qualität

### ✅ Bereits gut
- Alle 12 .dart-Dateien haben SPDX-Lizenz-Header
- Keine TODO/FIXME/HACK-Kommentare
- Keine hartcodierten Secrets/Keys

### ✅ Erledigt (2026-03-04)
- Widget-Test ersetzt durch einfachen App-Test
- Unused fields/classes/variables entfernt:
  - `_berlinCenter` entfernt
  - `_InfoRow` Klasse entfernt  
  - `duration` Variable entfernt
  - `locationModel` im FilterBottomSheet entfernt
  - Unnecessary null-check entfernt
  - Unused import `dart:convert` in parking_service.dart entfernt

### ✅ Ergebnis
```
flutter analyze
# Keine Warnings mehr! ✅
```

---

## 2. Testing & CI

### ❌ Problem
- Widget-Test war kaputt (referenzierte nicht-existente `MyApp`)
- Kein echter Unit-Test vorhanden

### ✅ Erledigt (2026-03-04)
- Widget-Test ersetzt durch einfachen App-Test
- Test läuft durch: `flutter test` ✓

### Empfehlung
1. Unit-Tests für Models schreiben (CityConfig, DisabledParkingSpot)
2. Service-Tests für API-Aufrufe (mit Mock)
3. CI-Pipeline einrichten:
   - GitHub Actions oder GitLab CI
   - `flutter analyze`
   - `flutter test`
   - `flutter build apk --release`

---

## 3. Sicherheit

### ✅ Bereits gut
- Keine API-Keys im Code
- Keine Secrets/Passwörter
- HTTPS für alle API-Aufrufe

### Hinweis
- Nominatim hat Rate-Limit (1 req/s) - aktuell handling via `sleep(1.1)` in Tests
- Für Production: Caching oder eigene Instanz erwägen

---

## 4. Lizenz-Compliance

### ✅ Bereits gut
- Alle .dart-Dateien: GPL-3.0-or-later Header
- LICENSES/ Verzeichnis existiert

### ❌ Fehlt für Debian-Standard
- `debian/copyright` Datei ODER
- `REUSE-TOML` Datei

### Empfehlung (REUSE-TOML)
```toml
version = 1
SPDX-PackageName = "parklibre"
SPDX-PackageDownloadLocation = "https://codeberg.org/jn/parklibre"

[[annotations]]
path = "**"
precedence = "aggregate"
SPDX-FileCopyrightText = "2026 Johannes Näder"
SPDX-License-Identifier = "GPL-3.0-or-later"
```

---

## 5. Projekt-Struktur Aufräumen

### ✅ Bereits in .gitignore
- build/
- .dart_tool/
- .pub-cache/

### ❌ Aufräumen
- `test_nominatim.py` - Debug-Skript → löschen oder in scripts/ verschieben
- `test_parsing.py` - Debug-Skript → löschen oder in scripts/ verschieben
- `scan_results.json` - Sicherheits-Scan → löschen
- `bom.json` - Bill of Materials → löschen

---

## 6. README.md

### ❌ Aktuell
Standard-Flutter-Template - nicht aussagekräftig

### Empfehlung
```markdown
# ParkLibre

Freie App für barrierefreie Parkplätze in deutschen Städten.

## Features
- Berlin, München, Dresden
- Adress-Suche mit Autocomplete
- Filterung nach Umkreis
- GPS-Standort

## Build

```bash
flutter pub get
flutter run
```

## Lizenz
GPL-3.0-or-later
```

---

## Zusammenfassung: Prioritäten

| Priorität | Aufgabe | Status |
|-----------|---------|--------|
| 1 | Widget-Test fixen | ✅ Erledigt |
| 2 | Unused Code entfernen | ✅ Erledigt |
| 3 | CI-Pipeline einrichten | Offen |
| 4 | REUSE-TOML erstellen | Offen |
| 5 | README.md verbessern | Offen |
| 6 | Debug-Dateien entfernen | Offen |

---

## Build-Befehle

```bash
# Analyse
flutter analyze

# Tests
flutter test

# Debug APK
flutter build apk --debug

# Release APK
flutter build apk --release
```
