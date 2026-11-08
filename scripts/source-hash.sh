#!/usr/bin/env bash
# Prints the SHA-256 of the source tree (what the zip ships), independent of build output and
# of git. Same command on the box and the Mac gives the same value for the same sources.
# Read-only; no sudo.
cd "$(dirname "$0")/.." || exit 1
find . -type f ! -path './.build/*' ! -path './build/*' ! -path './.git/*' ! -name 'SOURCE-SHA256.txt' ! -name '.DS_Store' \
  -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256 2>/dev/null | shasum -a 256 | cut -c1-64
