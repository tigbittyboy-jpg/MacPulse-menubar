#!/usr/bin/env python3
"""Register new Swift sources in the existing project without rewriting its settings."""
from pathlib import Path
import hashlib
import re
import sys

root = Path(__file__).resolve().parents[1]
project = root / 'MacPulse.xcodeproj/project.pbxproj'
text = project.read_text()

def identifier(value):
    return hashlib.sha1(value.encode()).hexdigest()[:24].upper()

missing = []
objects = []
references = []
for target, directory in [('app', 'Sources/MacPulse'), ('core', 'Sources/MacPulseCore'), ('tests', 'Tests/MacPulseCoreTests'), ('ui', 'Tests/MacPulseUITests')]:
    build_ids = []
    for path in sorted((root / directory).rglob('*.swift')):
        relative = path.relative_to(root).as_posix()
        if f'path = "{relative}";' in text:
            continue
        missing.append(relative)
        ref, build = identifier(relative), identifier(relative + 'build')
        references.append(ref)
        build_ids.append(build)
        objects += [f'{ref} = {{ isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{relative}"; sourceTree = SOURCE_ROOT; }};', f'{build} = {{ isa = PBXBuildFile; fileRef = {ref}; }};']
    if build_ids:
        phase = identifier(target + 'sources')
        pattern = rf'({phase} = .*?files = \()([^)]*)(\);)'
        text, count = re.subn(pattern, lambda m: m[1] + m[2] + ', ' + ', '.join(build_ids) + m[3], text)
        if count != 1:
            raise SystemExit(f'Could not identify {target} source phase')
if '--check' in sys.argv:
    if missing:
        raise SystemExit('Unregistered sources: ' + ', '.join(missing))
    print('All Swift sources are registered in the Xcode project.')
    raise SystemExit(0)
if references:
    main_group = identifier('main')
    pattern = rf'({main_group} = .*?children = \()([^)]*)(\);)'
    text, count = re.subn(pattern, lambda m: m[1] + m[2] + ', ' + ', '.join(references) + m[3], text)
    if count != 1:
        raise SystemExit('Could not identify main project group')
    text = text.replace('\n}; rootObject', '\n' + '\n'.join(objects) + '\n}; rootObject')
    project.write_text(text)
print(f'Registered {len(missing)} new Swift sources.')
