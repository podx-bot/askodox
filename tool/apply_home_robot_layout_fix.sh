#!/usr/bin/env bash
set -euo pipefail

TARGET="lib/features/home/presentation/home_screen.dart"
python3 - "$TARGET" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()
old = '''            child: Align(
              alignment: Alignment.topCenter,
              child: Transform.translate(
                offset: const Offset(0, -20),
                child: Column(
                  children: [
                    Container(
                      width: 5,
                      height: 18,
                      color: const Color(0xFF7285D9),
                    ),
                    Container(
                      width: 13,
                      height: 13,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF4B9CFF),
                        boxShadow: [
                          BoxShadow(color: Color(0xAA4B9CFF), blurRadius: 10),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),'''
new = '''            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                Positioned(
                  top: -20,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 5,
                        height: 18,
                        color: const Color(0xFF7285D9),
                      ),
                      Container(
                        width: 13,
                        height: 13,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF4B9CFF),
                          boxShadow: [
                            BoxShadow(color: Color(0xAA4B9CFF), blurRadius: 10),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),'''
if old not in s:
    if 'clipBehavior: Clip.none' in s and 'top: -20' in s:
        print('ASKODOX robot layout already fixed.')
        raise SystemExit(0)
    raise SystemExit('Expected ASKODOX robot antenna layout not found; refusing unsafe patch')
p.write_text(s.replace(old, new, 1))
print('ASKODOX robot antenna layout made overflow-safe.')
PY
