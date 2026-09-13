#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""Enforce a consumer's explicit trust boundary over its Rust source tree."""
import argparse
from pathlib import Path
import re

CHEAT = re.compile(r'assume\(|admit\(|external_body|assume_specification|external_fn_specification|verifier::external\]')
UNSAFE = re.compile(r'\bunsafe\b')


def within(path, directories):
    return any(path.is_relative_to(d) for d in directories)


def violations(root, trusted=(), unverified=()):
    root = Path(root).resolve(strict=True)
    trusted = [Path(d).resolve(strict=True) for d in trusted]
    unverified = [Path(d).resolve(strict=True) for d in unverified]
    for source in sorted(root.rglob('*.rs')):
        path = source.resolve()
        if within(path, trusted):
            continue
        for number, line in enumerate(source.read_text().splitlines(), 1):
            if line.lstrip().startswith(('//', '*')):
                continue
            if CHEAT.search(line) or (UNSAFE.search(line) and not within(path, unverified)):
                yield f'{source}:{number}:{line}'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root')
    parser.add_argument('--trusted', action='append', default=[])
    parser.add_argument('--unverified', action='append', default=[])
    args = parser.parse_args()
    hits = list(violations(args.root, args.trusted, args.unverified))
    if hits:
        print('lint-trusted: forbidden code outside the declared trust boundary:')
        print('\n'.join(hits))
        return 1
    print('lint-trusted: clean' + (f' (unsafe exempt: {", ".join(args.unverified)})' if args.unverified else ''))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
