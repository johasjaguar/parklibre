# SPDX-FileCopyrightText: 2026 Johannes Näder <git@pub.nextwelt.de>
#
# SPDX-License-Identifier: GPL-3.0-or-later

import json
import urllib.request
import ssl

ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE

# Test a few coordinates
coords = [
    (51.02948009055888, 13.742268570662187),
    (51.044549186051114, 13.758444170054375),
]

for lat, lon in coords:
    url = f"https://nominatim.openstreetmap.org/reverse?lat={lat}&lon={lon}&format=json"
    req = urllib.request.Request(url, headers={'User-Agent': 'ParkLibre/1.0'})
    with urllib.request.urlopen(req, context=ssl_context) as resp:
        d = json.load(resp)
    
    display_name = d.get('display_name', 'ERROR')
    parts = display_name.split(', ')
    
    print(f"Coords: {lat}, {lon}")
    print(f"Full address: {display_name}")
    print(f"Parts ({len(parts)}): {parts}")
    
    if len(parts) >= 5:
        plz = parts[-2]
        city = parts[-4]
        print(f"-> PLZ: {plz}, Stadt: {city}")
    else:
        print("-> NOT enough parts!")
    print()
