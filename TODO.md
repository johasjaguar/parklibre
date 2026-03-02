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

---

## ❌ OFFEN - Priorität 1 (Kritisch)

### Bug #1 + #3: Berlin markers not visible on map
- **Expected:** Show 912 parking spots for Berlin on map
- **Symptom:** 
  - Berlin after switch: 912 Parkplätze in chip, but NO markers on map ❌
  - München: Works perfectly ✅
- **Root cause:** Unknown
- **Possible causes:**
  - Marker position outside visible map area
  - Coordinate parsing issue for Berlin
  - Marker layer not rendering correctly

---

## ❌ OFFEN - Priorität 2

### Test on Android device
- Current testing done on Linux desktop only
- Need to verify on actual mobile device

---

## Debugging-Notizen

### Observations:
1. München: Lädt 558 spots, alle Marker sichtbar ✅
2. Berlin nach Wechsel: Lädt 912 spots, Chip zeigt korrekt, ABER keine Marker ❌
3. Karte zeigt Berlin-Region (Zoom-Out zeigt München auch)
4. Koordinaten für Berlin kommen aus `gps_lat/gps_lon` Feldern

### Nächste Schritte für Debugging:
1. Debug-Ausgabe der Koordinaten beim Laden
2. Prüfen ob Marker außerhalb des sichtbaren Bereichs liegen
3. Karte initial auf Berlin Zentrum (52.52, 13.405) zoomen
4. Koordinaten-Format prüfen (sind es wirklich Lat/Lng?)
