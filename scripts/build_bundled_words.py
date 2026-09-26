#!/usr/bin/env python3
"""docs/vocab/toeic_vocab_source.json → VocaDay/Resources/BundledWords.json

알파벳순 원본을 고정 시드로 한 번 섞어 '오늘의 새 단어' 순서를 만든다.
시드를 바꾸면 이미 사용 중인 사용자의 다음 단어 순서가 달라지니 바꾸지 않는다.
"""
import json
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "docs/vocab/toeic_vocab_source.json"
OUTPUT = ROOT / "VocaDay/Resources/BundledWords.json"
SEED = 20260926
KEYS = ["english", "meaningKo", "exampleEn", "exampleKo", "note", "toeicTag"]

# 원본에서 빈칸 문제가 안 만들어지던 항목 보정.
FIXES = {
    "have trouble-ing": {"english": "have trouble"},
    "overwhelming": {
        "exampleEn": "The new product received an overwhelming response from early customers.",
        "exampleKo": "새 제품은 초기 고객들로부터 압도적인 반응을 얻었다.",
        "note": "an overwhelming response/majority",
    },
}

words = json.loads(SOURCE.read_text(encoding="utf-8"))
for word in words:
    word.update(FIXES.get(word["english"], {}))
    assert list(word) == KEYS, word

seen = set()
for word in words:
    key = word["english"].strip().lower()
    assert key not in seen, f"duplicate: {key}"
    seen.add(key)

random.Random(SEED).shuffle(words)
OUTPUT.write_text(json.dumps(words, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
print(f"{len(words)} words → {OUTPUT.relative_to(ROOT)}")
