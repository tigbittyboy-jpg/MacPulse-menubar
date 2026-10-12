#!/usr/bin/env python3
"""Expose build diagnostics as GitHub annotations without changing command exit codes."""
import re
import sys
from pathlib import Path

def escape(value):
    return value.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')

seen = set()
for name in sys.argv[1:]:
    path = Path(name)
    if not path.exists():
        continue
    for line in path.read_text(errors='replace').splitlines():
        if 'error:' not in line or line in seen:
            continue
        seen.add(line)
        if len(seen) > 40:
            break
        match = re.match(r'(.+\.(?:swift|h|c)):(\d+):(?:\d+:)?\s*error:\s*(.*)', line)
        if match:
            file, number, message = match.groups()
            if '/MacPulse-menubar/' in file:
                file = file.split('/MacPulse-menubar/', 1)[1]
            print(f'::error file={escape(file)},line={number}::{escape(message)}')
        else:
            print('::error::' + escape(line))
