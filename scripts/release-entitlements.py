#!/usr/bin/env python3
"""Resolve the same App Group in both native release signatures."""
import pathlib, plistlib, sys
for source, name in [('Resources/Xcode-Duotlet.entitlements', 'app'),
                     ('Resources/Control/Xcode-DuotletControl.entitlements', 'control')]:
    data=plistlib.loads(pathlib.Path(source).read_bytes())
    data['com.apple.security.application-groups']=[sys.argv[1]]
    pathlib.Path(sys.argv[2], name+'.entitlements').write_bytes(plistlib.dumps(data))
