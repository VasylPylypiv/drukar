#!/bin/bash
# Decompress word list .gz files for Xcode bundle resources.
# Run before building: ./scripts/decompress_wordlists.sh

RESOURCES="$(dirname "$0")/../Drukar/Resources"

for gz in "$RESOURCES"/words_*.txt.gz; do
    txt="${gz%.gz}"
    if [ ! -f "$txt" ] || [ "$gz" -nt "$txt" ]; then
        echo "Decompressing $(basename "$gz")..."
        gunzip -k -f "$gz"
    fi
done
