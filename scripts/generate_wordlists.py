#!/usr/bin/env python3
"""
Generate sorted word lists for Drukar's mmap dictionary from:
- VESUM dict_corp_vis.txt (Ukrainian)
- SCOWL word lists (English)

Output: words_uk.txt, words_en.txt — sorted, one word per line, UTF-8.
"""

import os
import re
import sys
import urllib.request
import zipfile
import tempfile

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "Drukar", "Resources")


def process_vesum(input_path: str, output_path: str):
    """Extract unique word forms from VESUM dict_corp_vis.txt."""
    words = set()

    with open(input_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue

            stripped = line.lstrip()
            parts = stripped.split(None, 1)
            if not parts:
                continue

            word = parts[0]
            tags = parts[1] if len(parts) > 1 else ""

            # Skip entries marked as bad/erroneous
            if ":bad" in tags:
                continue

            # Skip interjections like "ааа", "а-а-а"
            if tags.startswith("intj") and len(word) > 3 and len(set(word.replace("-", ""))) <= 2:
                continue

            # Skip words with hyphens (compound words — our tokenizer splits on them)
            if "-" in word:
                continue

            # Must contain at least one Cyrillic letter
            if not any("\u0400" <= c <= "\u04FF" for c in word):
                continue

            # Skip single-char words (handled by hardcoded whitelist)
            if len(word) < 2:
                continue

            words.add(word.lower())

    sorted_words = sorted(words)

    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(sorted_words))
        f.write("\n")

    print(f"  UA: {len(sorted_words):,} unique word forms → {output_path}")
    return sorted_words


def process_scowl(output_path: str):
    """Download SCOWL and generate English word list."""
    scowl_url = "https://downloads.sourceforge.net/wordlist/scowl-2020.12.07.zip"

    with tempfile.TemporaryDirectory() as tmp_dir:
        zip_path = os.path.join(tmp_dir, "scowl.zip")
        print(f"  Downloading SCOWL...")
        urllib.request.urlretrieve(scowl_url, zip_path)

        with zipfile.ZipFile(zip_path, "r") as zf:
            zf.extractall(tmp_dir)

        words = set()
        scowl_dir = None
        for d in os.listdir(tmp_dir):
            if d.startswith("scowl-"):
                scowl_dir = os.path.join(tmp_dir, d, "final")
                break

        if not scowl_dir or not os.path.isdir(scowl_dir):
            # Try flat structure
            scowl_dir = os.path.join(tmp_dir, "final")

        if not os.path.isdir(scowl_dir):
            print(f"  ERROR: Cannot find SCOWL final/ directory in {tmp_dir}")
            print(f"  Contents: {os.listdir(tmp_dir)}")
            return []

        # Include sizes up to 70 (good coverage without obscure words)
        max_size = 70
        for filename in os.listdir(scowl_dir):
            # SCOWL files: english-words.10, english-words.20, etc.
            match = re.match(r"(english|american|british)[\w-]*\.(\d+)", filename)
            if match and int(match.group(2)) <= max_size:
                filepath = os.path.join(scowl_dir, filename)
                with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
                    for line in f:
                        word = line.strip()
                        if not word or "'" in word:
                            continue
                        if len(word) < 2:
                            continue
                        if not all(c.isalpha() for c in word):
                            continue
                        words.add(word.lower())

    sorted_words = sorted(words)

    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(sorted_words))
        f.write("\n")

    print(f"  EN: {len(sorted_words):,} unique word forms → {output_path}")
    return sorted_words


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print("Processing VESUM (Ukrainian)...")
    vesum_path = "/tmp/dict_corp_vis.txt"
    if not os.path.exists(vesum_path):
        print(f"  ERROR: {vesum_path} not found. Download it first:")
        print(f"  curl -sL https://github.com/brown-uk/dict_uk/releases/download/v6.7.5/dict_corp_vis.txt.bz2 | bunzip2 > {vesum_path}")
        sys.exit(1)

    ua_words = process_vesum(vesum_path, os.path.join(OUTPUT_DIR, "words_uk.txt"))

    print("\nProcessing SCOWL (English)...")
    en_words = process_scowl(os.path.join(OUTPUT_DIR, "words_en.txt"))

    # Summary
    print(f"\nSummary:")
    ua_path = os.path.join(OUTPUT_DIR, "words_uk.txt")
    en_path = os.path.join(OUTPUT_DIR, "words_en.txt")
    print(f"  words_uk.txt: {os.path.getsize(ua_path) / 1024 / 1024:.1f} MB, {len(ua_words):,} words")
    if en_words:
        print(f"  words_en.txt: {os.path.getsize(en_path) / 1024 / 1024:.1f} MB, {len(en_words):,} words")


if __name__ == "__main__":
    main()
