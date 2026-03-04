# SPDX-FileCopyrightText: 2026 Johannes Näder <git@pub.nextwelt.de>
#
# SPDX-License-Identifier: GPL-3.0-or-later

import json
import urllib.request
import urllib.parse
import time
import ssl

ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE

# Fetch Dresden data
with urllib.request.urlopen('https://kommisdd.dresden.de/net4/public/ogcapi/collections/L1113/items?limit=15') as resp:
    data = json.load(resp)

coords = []
for f in data['features'][:15]:
    lon, lat = f['geometry']['coordinates']
    coords.append((lat, lon))

print("=" * 80)
print("NOMINATIM RESPONSES")
print("=" * 80)

results = []
for i, (lat, lon) in enumerate(coords):
    url = f"https://nominatim.openstreetmap.org/reverse?lat={lat}&lon={lon}&format=json"
    req = urllib.request.Request(url, headers={'User-Agent': 'ParkLibre/1.0'})
    with urllib.request.urlopen(req, context=ssl_context) as resp:
        d = json.load(resp)
    
    display_name = d.get('display_name', 'ERROR')
    results.append(display_name)
    print(f"\n[{i+1}] {lat}, {lon}")
    print(f"    {display_name}")
    
    time.sleep(1.1)

print("\n" + "=" * 80)
print("PARSING RESULTS")
print("=" * 80)

for i, addr in enumerate(results):
    parts = addr.split(', ')
    print(f"\n[{i+1}] Parts: {parts}")
    print(f"    First 2: {parts[:2]}")
    print(f"    Last 5: {parts[-5:]}")
    
    # Last 5: bezirk, stadt, bundesland, plz, staat
    if len(parts) >= 5:
        bezirk = parts[-5] if parts[-5] else None
        stadt = parts[-4] if parts[-4] else None
        bundesland = parts[-3]
        plz = parts[-2]
        staat = parts[-1]
        print(f"    -> Bezirk: {bezirk}, Stadt: {stadt}, PLZ: {plz}")
    
    # First 1-2 fields for street
    if parts:
        first = parts[0]
        if first[0].isdigit():
            # Fall A: starts with number = house number
            hausnr = first
            strasse = parts[1] if len(parts) > 1 else ""
        else:
            # Fall B: no number at start
            strasse = parts[0]
            hausnr = ""
            if len(parts) > 1:
                strasse += " " + parts[1]
        print(f"    -> Straße: {strasse}, Nr: {hausnr}")
