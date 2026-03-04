<!--
SPDX-FileCopyrightText: 2026 Johannes Näder <git@pub.nextwelt.de>

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
