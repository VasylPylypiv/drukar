#!/usr/bin/env python3
"""
Download Leipzig corpus data and generate frequency JSON files for Drukar.

Output: ua_freq.json, en_freq.json — top 5000 words with logarithmic scores.
Score formula: log10(total_word_count / rank)

Leipzig corpus format (*_words.txt): Word_ID\tWord\tFrequency (tab-separated, desc by freq)
"""

import json
import math
import os
import re
import sys
import tarfile
import tempfile
import urllib.request

UA_CORPUS_URL = "https://downloads.wortschatz-leipzig.de/corpora/ukr_news_2024_1M.tar.gz"
EN_CORPUS_URL = "https://downloads.wortschatz-leipzig.de/corpora/eng_news_2024_1M.tar.gz"

TOP_N = 150000
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "Drukar", "Resources")


def download_and_extract_words(url: str, tmp_dir: str) -> str:
    """Download tar.gz, extract, return path to *_words.txt."""
    archive_path = os.path.join(tmp_dir, "corpus.tar.gz")
    print(f"  Downloading {url} ...")
    urllib.request.urlretrieve(url, archive_path)
    print(f"  Extracting ...")

    with tarfile.open(archive_path, "r:gz") as tar:
        tar.extractall(tmp_dir)

    for root, _, files in os.walk(tmp_dir):
        for f in files:
            if f.endswith("-words.txt"):
                return os.path.join(root, f)

    raise FileNotFoundError(f"No *_words.txt found in {url}")


def is_valid_word(word: str, language: str) -> bool:
    """Filter out numbers, punctuation, URLs, single chars that aren't meaningful."""
    if len(word) < 1:
        return False
    if any(c.isdigit() for c in word):
        return False
    if re.search(r'[.,:;!?@#$%^&*(){}[\]<>/\\|~`"\'+\-=_]', word):
        return False

    if language == "uk":
        # Must contain at least one Cyrillic letter
        if not any("\u0400" <= c <= "\u04FF" or "\u0500" <= c <= "\u052F" for c in word):
            return False
        # Skip words with Latin characters mixed in
        if any("a" <= c.lower() <= "z" for c in word):
            return False
    elif language == "en":
        # Must be all ASCII letters (allow apostrophe for contractions like "don't")
        if not all(c.isalpha() or c == "'" for c in word):
            return False
        if not any(c.isalpha() for c in word):
            return False

    return True


def process_words_file(words_path: str, language: str, top_n: int) -> dict:
    """
    Parse Leipzig *_words.txt (Word_ID, Word, Frequency) and return
    {word: score} for top N valid words.

    Score = log10(total_words_in_corpus / rank), where rank is 1-based
    position after filtering.
    """
    raw_words = []
    total_freq = 0

    with open(words_path, "r", encoding="utf-8") as f:
        for line in f:
            parts = line.strip().split("\t")
            if len(parts) < 3:
                continue
            word = parts[1]
            try:
                freq = int(parts[2])
            except ValueError:
                continue

            total_freq += freq
            if is_valid_word(word, language):
                raw_words.append((word.lower(), freq))

    # Deduplicate (lowercased) — keep highest frequency
    seen = {}
    for word, freq in raw_words:
        if word not in seen or freq > seen[word]:
            seen[word] = freq

    sorted_words = sorted(seen.items(), key=lambda x: -x[1])[:top_n]

    total_count = len(sorted_words)
    result = {}
    for rank, (word, freq) in enumerate(sorted_words, start=1):
        score = math.log10(total_count / rank)
        result[word] = round(score, 4)

    return result


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    for lang, url, filename in [
        ("uk", UA_CORPUS_URL, "ua_freq.json"),
        ("en", EN_CORPUS_URL, "en_freq.json"),
    ]:
        print(f"\nProcessing {lang.upper()} corpus...")
        with tempfile.TemporaryDirectory() as tmp_dir:
            try:
                words_path = download_and_extract_words(url, tmp_dir)
            except Exception as e:
                print(f"  ERROR downloading: {e}")
                print(f"  Trying fallback URL...")
                # Try previous year if 2024 not available
                fallback = url.replace("_2024_", "_2023_")
                try:
                    words_path = download_and_extract_words(fallback, tmp_dir)
                except Exception as e2:
                    print(f"  Fallback also failed: {e2}")
                    fallback2 = url.replace("_2024_", "_2022_")
                    words_path = download_and_extract_words(fallback2, tmp_dir)

            freq_dict = process_words_file(words_path, lang, TOP_N)

        output_path = os.path.join(OUTPUT_DIR, filename)
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(freq_dict, f, ensure_ascii=False, indent=None, separators=(",", ":"))

        print(f"  Wrote {len(freq_dict)} words to {output_path}")
        # Show top 20 as sanity check
        top20 = sorted(freq_dict.items(), key=lambda x: -x[1])[:20]
        print(f"  Top 20: {[w for w, _ in top20]}")
        # Show score range
        scores = list(freq_dict.values())
        print(f"  Score range: {min(scores):.4f} — {max(scores):.4f}")


if __name__ == "__main__":
    main()
