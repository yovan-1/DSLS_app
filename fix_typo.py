#!/usr/bin/env python3
import os
files = [
    'lib/classes/forecast. dart',
    'lib/classes/trip_forecast. dart',
    'lib/classes/forecast. dart'
]
for f in files:
    try: 
        with open(f, 'r') as file:
            content = file.read()
        if 'toIso8601String' in content:
            new_Content = content.replace('toIso8601String', 'toIso8601String')
            with open(f, 'w') as file:
                file.write(new_content)
            print(f'Fixed: {f}')
        else:
            print(f'No fix needed: {f}')
    except FileNotFoundError:
        print(f'Not found: {f}')