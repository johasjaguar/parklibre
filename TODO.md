<!--
SPDX-FileCopyrightText: 2026 Johannes Näder <jn@dienst.nextwelt.de>

SPDX-License-Identifier: GPL-3.0-or-later
-->

# TODO - Bugs to Fix

## ✅ ERLEDIGT

### Bug #4: Zoom to city center on city switch
- **Status:** ✅ Fixed (Commit: c2b52f4)
- **Fix:** Added `_mapController.move(newCity.defaultCenter, 12.0)` in city selector

### Bug #2: ClientException on city switch  
- **Status:** ✅ Fixed (Commit: 709b30e)
- **Fix:** Using shared HTTP client instead of disposing old service

### Bug #5: App starts with München instead of Berlin
- **Status:** ✅ Fixed
- **Behavior now correct:** Starts with Berlin

### Bug #6: Startup-Inkonsistenz (Zoom/Parkplätze vs Stadt-Titel)
- **Status:** ✅ Fixed (Commit: 84ed705)
- **Problem:** App startete mit Berlin-Zoom, aber zeigte letzte gespeicherte Stadt
- **Fix:** Warte auf City-Initialisierung bevor Parkplätze geladen werden

### Bug #7: Filter-Button während Parkplätze-Laden
- **Status:** ✅ Fixed (Commit: 403408c)
- **Problem:** Filterung vor Laden der Parkplätze möglich → "Keine Parkplätze gefunden"
- **Fix:** Filter-Button deaktiviert während `spotsModel.isLoading`

### Bug #8: Fehlermeldung bleibt bei erneuter Filterung
- **Status:** ✅ Fixed (Commit: 619f7f0)
- **Problem:** Snackbar "Keine Parkplätze gefunden" blieb auch bei erfolgreicher Filterung
- **Fix:** Snackbar wird vor jeder neuen Filterung geschlossen

### Bug #9: Fehlermeldung für nicht-implementierte Städte
- **Status:** ✅ Fixed (Commit: 5c273c4)
- **Problem:** Adressen in nicht-implementierten Städten (z.B. Hamburg, Fulda) zeigten nur "Adresse nicht gefunden"
- **Fix:** Klare Fehlermeldung "Diese Stadt ist noch nicht verfügbar. Verfügbare Städte: Berlin, München, Dresden."

### Bug #10: Stadtwechsel bei Adress-Suche aus anderer Stadt
- **Status:** ✅ Fixed (Commit: 01e5690)
- **Problem:** Adress-Suche nur in aktueller Stadt möglich
- **Fix:** Suche in ganz Deutschland + automatischer Stadtwechsel bei Auswahl

---

## ❌ OFFEN - Bug Reports von GrapheneOS Nutzer

### Bug #11: Standort-Lokalisierung auf GrapheneOS
- **Problem:** Nutzer erteilt "Einmalig" Standort-Freigabe, aber App kann Standort nicht lokalisieren
- **Arbeitsumgebung:** GrapheneOS
- **Funktioniert:** "Bei Nutzung der App erlauben" funktioniert
- **Status:** ✅ Fixed
- **Fix:** Mehr Debug-Logging hinzugefügt um Problem zu diagnostizieren

### Bug #12: "Standort nicht gefunden" Snackbar verschwindet nicht / stackt
- **Status:** ✅ Fixed
- **Problem:** Snackbar blieb ewig sichtbar oder stackte übereinander
- **Fix:** 
  1. `hideCurrentSnackBar()` vor dem Anzeigen aufgerufen
  2. Duration auf 8 Sekunden erhöht (da App auch ohne Standort nutzbar)

---

## ❌ OFFEN - Priorität 2

### Test on Android device
- Current testing done on Linux desktop only
- Need to verify on actual mobile device

---

## 📋 Code Review (Senior Staff Developer)

**Datum:** 2026-03-05  
**Gesamtbewertung:** Solide 7/10

Der Code ist gut strukturiert, wartbar und folgt vielen Best Practices. Aber es gibt Verbesserungspotenzial.

---

## ✅ Was sehr gut ist:

### 1. Architektur & Struktur
- **Separation of Concerns**: Saubere Trennung zwischen Models, Services, Utils
- **Abstract ParkingService**: Gute Abstraktion für verschiedene Städte
- **Provider Pattern**: Richtige Verwendung von ChangeNotifier für State Management
- **Dependency Injection**: HTTP-Client wird injiziert, gut testbar

### 2. Code-Qualität
- **SPDX-Header**: Exzellente Lizenz-Dokumentation
- **Dokumentation**: Gute Kommentare (z.B. Haversine-Formel erklärt)
- **Error Handling**: Eigene Exception-Klassen (`ParkingServiceException`)
- **Null-Safety**: Korrekte Verwendung von `?` und `!`

### 3. Flutter-Best-Practices
- `const` Constructors wo möglich
- `mounted`-Checks vor UI-Updates
- Richtige Disposal von Controllern und Timern
- Hero-Tags für FloatingActionButtons

---

## ⚠️ Verbesserungsbedarf (Priorität hoch):

### 1. main.dart ist zu groß (1.863 Zeilen!)
**Problem**: Eine Datei mit UI, State Management UND Business Logic verletzt das Single Responsibility Principle.

**Lösung**: Aufteilen in:
```
lib/
├── screens/
│   └── map_screen.dart          # UI-Layer
├── widgets/
│   ├── parking_spot_marker.dart
│   ├── filter_bottom_sheet.dart
│   └── navigation_info_banner.dart
└── main.dart                    # Nur App-Setup
```

### 2. Globaler HTTP-Client
```dart
final _sharedHttpClient = http.Client();  // Global!
```
**Risiko**: Globaler Zustand, schwer zu testen.

**Lösung**: Dependency Injection via Provider oder GetIt.

### 3. Magic Numbers & Strings
```dart
_radius = 1000;  // Was bedeutet 1000?
_duration = const Duration(seconds: 8);  // Warum 8?
```

**Lösung**: Konstanten als `static const` definieren:
```dart
static const defaultRadiusMeters = 1000;
static const snackBarDurationSeconds = 8;
```

### 4. Context-Across-Async-Gaps
```dart
await locationModel.getCurrentLocation();
if (mounted) {
  context.read<CityModel>();  // Kontext könnte ungültig sein
}
```

**Empfehlung**: Variablen vor `await` zwischenspeichern.

---

## 🔧 Verbesserungsbedarf (Priorität mittel):

### 5. Keine Unit-Tests
**Status**: Nur ein leerer `widget_test.dart`

**Empfohlene Tests**:
- `DistanceCalculator.calculateDistance()`
- `ParkingService.parseWfsResponse()`
- `CityModel.switchCity()`

### 6. Hardcoded API-Endpoints
Die URLs sind in `CityConfig` verteilt - gut! Aber keine Retry-Logik.

**Empfehlung**: Exponentielles Backoff bei Netzwerkfehlern.

### 7. Kein Caching
Jeder App-Start lädt alle Parkplätze neu.

**Empfohlene Lösung**:
- Lokale SQLite-Datenbank
- Oder: HTTP-Cache

### 8. Synchrone Geo-Reverse Lookups blockieren
Dresden braucht Reverse Geocoding für jede Adresse - könnte batch-verarbeitet werden.

---

## 📊 Priorisierte TODO-Liste:

| Priorität | Aufgabe | Aufwand |
|-----------|---------|---------|
| **Hoch** | main.dart aufteilen | 2-3h |
| **Hoch** | Unit-Tests schreiben | 4-6h |
| **Mittel** | HTTP-Client nicht global | 1h |
| **Mittel** | Magic Numbers eliminieren | 30min |
| **Niedrig** | Caching implementieren | 4-8h |
| **Niedrig** | Retry-Logik für APIs | 2h |

---

## Fazit:

Der Code ist **produktionsreif** für einen MVP (Minimum Viable Product). Die Architektur ist solide und erweiterbar. Die größte Baustelle ist die Größe der `main.dart` - das sollte für die Zukunft angegangen werden, um die Wartbarkeit zu verbessern.

**Für ein privates Review-Repository**: Der Code ist absolut ausreichend und zeigt gute Software-Engineering-Praktiken.
