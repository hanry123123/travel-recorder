#!/usr/bin/env python3
"""Regenerate the offline datum mask from Natural Earth's public-domain 10m GeoJSON."""
import argparse
import hashlib
import json
import pathlib

parser = argparse.ArgumentParser()
parser.add_argument('geojson', type=pathlib.Path)
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
data = json.loads(args.geojson.read_bytes())
feature = next(f for f in data['features'] if f['properties']['ADM0_A3'] == 'CHN')
assert feature['geometry']['type'] == 'MultiPolygon'
rings = [ring for polygon in feature['geometry']['coordinates'] for ring in polygon]
coordinates = '\n'.join(';'.join(f'{x:.6f},{y:.6f}' for x, y in ring) for ring in rings)
path = root/'Sources/Core/MainlandRegion.swift'
marker = '    // BEGIN GENERATED REGION DATA\n'
header = path.read_text().split(marker)[0] + marker
path.write_text(header + '    private static let data = """\n' + coordinates + '\n"""\n}\n')
print('rings:', len(rings), 'vertices:', sum(map(len, rings)), 'input sha256:', hashlib.sha256(args.geojson.read_bytes()).hexdigest())
