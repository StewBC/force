#!/usr/bin/env python3
"""Read the fresh checked package/memory report produced by force_c64."""
import json
from c64_layout import ROOT
p=ROOT/'build/c64/memory-report.json'
a=json.loads(p.read_text())
print(f'Bootstrap: {a["bootstrap_bytes"]} bytes')
expanded=sum(c['expanded'] for c in a['chunks']);stored=sum(c['stored'] for c in a['chunks'])
print(f'Game: {stored} stored / {expanded} expanded; {expanded-stored} bytes saved before headers')
for name,c in a['collections'].items():
    print(f'{name}: collection {c["stored"]}/{c["capacity"]}; expanded records {c["expanded"]} / 597 each')
print(ROOT/'build/c64/memory-report.md')
