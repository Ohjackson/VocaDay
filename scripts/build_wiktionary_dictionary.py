#!/usr/bin/env python3
"""한국어 위키낱말사전의 영어 항목 → VocaDay/Resources/WiktionaryEnKo.json

원본: https://kaikki.org/kowiktionary/raw-wiktextract-data.jsonl.gz
라이선스: CC BY-SA 4.0 (한국어 위키낱말사전 기여자). 다듬은 결과 파일도 같은 라이선스다.

사용: python3 scripts/build_wiktionary_dictionary.py <raw-wiktextract-data.jsonl.gz> <덤프 날짜 YYYY-MM-DD>

뜻 형식은 기본 단어장과 같고, 품사 안의 뜻은 "; "로 나눈다: "n. 기도; (법률) 청구 / v. 기도하다"
예문은 뜻마다 하나. 위키낱말사전에 없으면 앱 안의 번역된 문장(기본 단어장·책)에서 그 뜻이 번역에 나오는 것을 고른다.
앱 문장은 라이선스가 달라 VocaDay/Resources/MeaningExamples.json 에 따로 둔다. 이 파일은 저장소에 넣지 않는다.
"""
import gzip
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "VocaDay/Resources"
OUTPUT = RESOURCES / "WiktionaryEnKo.json"
EXAMPLES_OUTPUT = RESOURCES / "MeaningExamples.json"
CORPUS_BOOKS = ["toeic-long-001", "classic-ohenry-easy"]

POS = {
    "noun": "n.", "name": "n.", "num": "n.", "verb": "v.", "adj": "adj.", "adv": "adv.",
    "prep": "prep.", "pron": "pron.", "conj": "conj.", "intj": "interj.",
}
CATEGORY_POS = [("영어 동사", "v."), ("영어 형용사", "adj."), ("영어 부사", "adv."), ("영어 명사", "n.")]
SKIPPED_POS = {"suffix", "prefix", "symbol", "abbrev", "character", "letter"}
MAX_SENSES = 3  # 품사마다
MAX_GLOSS = 34  # 카드 두 줄
MAX_EXAMPLE_EN = 100
MAX_EXAMPLE_KO = 70
MAX_POS = 3

HANGUL = re.compile("[가-힣]")
KEY = re.compile(r"[a-z][a-z'’-]*(?: [a-z'’-]+)*\.?$")
# "enter의 과거형" 같은 활용형 설명. 원형으로 찾게 뺀다.
FORM_OF = re.compile(
    r"[A-Za-z]['’]?\s*(?:\([^)]*\))?(?:의|에 대한)\s*(?:\S+\s*){0,2}?(?:과거|현재\s*분사|현재 진행|분사|복수|[3삼]인칭|비교급|최상급|동명사|"
    r"줄임말|준말|약자|잘못된|다른 표기|다른 형태|이형|동의어|영국식|미국식|철자|동작)"
)
PLACEHOLDER = re.compile(r"뜻풀이가 필요|틀\(|rfdef|위키백과|알파벳|관련된 의미|관련하여$")
# 사전 뜻이 읽는 데 도움이 안 되는 말
REMOVED = {"the"}
# 문법·쓰임 표시. 뜻이 아니다.
USAGE = re.compile(
    r"^(?:타동사|자동사|타|자|자/타동사|구식|고어|가산|불가산|가산/불가산|가산 명사|불가산 명사|셀 수 있는 명사|셀 수 없는 명사|"
    r"격식|비격식|문어|구어|주로 .*|보통 .*|특히 .*형으로.*|복수|복수형.*|단수.*|수동태.*|명사 앞.*|.*용법.*|.*명사 앞에.*)$"
)


def drop_bracket(match):
    inner = match.group(1).strip()
    if not HANGUL.search(inner) or len(inner) > 14 or "참조" in inner or USAGE.match(inner) or USAGE.match(inner.split(",")[0].strip()):
        return " "
    return match.group(0)


def clean(gloss):
    text = gloss.replace("\n", " ").replace("'''", "").replace("''", "")
    if PLACEHOLDER.search(text) or FORM_OF.search(text):
        return []
    text = re.sub(r"\{\{[^}]*\}\}", " ", text)
    text = re.sub(r"<[^<>]*(?:>|$)|«[^»]*»|〈[^〉]*〉|〔[^〕]*〕", " ", text)
    # 부수[차]적인 → 부수적인, [주로 명사 앞에 씀] 사법의 → 사법의
    for _ in range(3):
        text = re.sub(r"\[[^\[\]]*\]", "", text)
    text = re.sub(r"[\[\]]", "", text)
    for _ in range(2):
        text = re.sub(r"\(([^()]*)\)", drop_bracket, text)
    if text.count("(") != text.count(")") or text.count("[") != text.count("]"):
        text = re.sub(r"[(\[][^)\]]*$", "", text)
    text = text.replace("・", "·")
    text = re.sub(r"[㉠-㉿]|^\s*\d+[.)]\s*", " ", text)
    text = re.sub(r"\s*/\s*", "·", text)
    parts = []
    for piece in re.split(r"[;；]|(?<=[가-힣)])[.。](?:\s+|$)|\|", text):
        piece = re.sub(r"\s+", " ", piece)
        piece = re.sub(r"\s+([,)])", r"\1", piece)
        piece = re.sub(r"\(\s+", "(", piece)
        piece = re.sub(r"(?:,\s*)+", ", ", piece)
        # 뒤에 붙은 영어 설명·전치사 ("… about")와 앞에 붙은 영어 ("~ (of something)")
        piece = re.sub(r"[\s,:]+[A-Za-z][A-Za-z ,.'’:-]*$", "", piece)
        piece = re.sub(r"^[A-Za-z][A-Za-z ,.'’:-]*[\s:]+(?=[가-힣(])", "", piece)
        piece = re.sub(r"(?:\.{2,}|…|～)\s*", "~", piece)
        piece = re.sub(r"~+\s*(?:(?:something|somebody|someone)\s+)?", "~", piece).strip(" ,.:·=-–—\"“”")
        if not piece.startswith("~"):
            # 한 글자 앞가지("임시의, 가~")는 물결표를 떼면 뜻이 되지 않는다.
            piece = re.sub(r",\s*[가-힣]\s*~+$", "", piece).rstrip("~ ")
        bare = re.sub(r"\([^()]*\)", "", piece)
        if not HANGUL.search(bare):
            continue
        if len(piece) > MAX_GLOSS:
            # 쉼표로 나눈 낱말 뜻이면 들어가는 데까지만, 긴 설명문이면 버린다.
            kept = ""
            for item in piece.split(", "):
                joined = f"{kept}, {item}" if kept else item
                if len(joined) > MAX_GLOSS:
                    break
                kept = joined
            piece = kept
        if piece:
            parts.append(piece)
    return parts


def guess_pos(entry, glosses):
    """품사가 없는 항목: 분류에 있으면 그것, 없으면 뜻의 끝 글자로 본다."""
    categories = entry.get("categories", [])
    for name, pos in CATEGORY_POS:
        if name in categories:
            return pos
    last = re.sub(r"\([^()]*\)", "", glosses[0]).strip()
    if last.endswith("다"):
        return "v."
    if re.search(r"(?:한|의|적인|운|진|된|찐|없는|있는)$", last):
        return "adj."
    return "n."


# MARK: 예문

WORD = re.compile(r"[A-Za-z][A-Za-z'’-]*")


def split_example(text):
    """"Are you serious? 진심이에요?" → 영어와 한국어. 나눌 수 없으면 None."""
    first = HANGUL.search(text)
    if not first:
        return None
    start = text.rfind(" ", 0, first.start()) + 1
    ends = [m.end() for m in re.finditer(r"[.?!][\"'”’)]*\s+", text[:start])]
    # 한국어가 영어 낱말·숫자로 시작할 때 ("… yesterday. NATO 정상 회의가 …")
    if ends and len(text[ends[-1]:start].split()) <= 3:
        start = ends[-1]
    return text[:start], text[start:]


def tidy_example(english, korean):
    english = re.sub(r"\s+", " ", english).strip(" :：=-–—→,;/")
    english = re.sub(r"^\((?!.*\)\s*\w)|^[·•*]\s*", "", english)
    korean = re.sub(r"\s+", " ", korean).strip(" :：=-–—→,;/")
    return english, korean


def mentions(word, english):
    """예문에 그 단어가 (변화형이라도) 나오는지."""
    lowered = english.lower().replace("’", "'")
    stem = word if len(word) <= 3 else word[:max(3, len(word) - 2)]
    return re.search(r"\b" + re.escape(stem), lowered) is not None or any(
        form in re.findall(r"[a-z']+", lowered) for form in FORMS.get(word, ())
    )


def usable(word, english, korean):
    return (
        not HANGUL.search(english)
        and HANGUL.search(korean)
        and len(WORD.findall(english)) >= 2
        and len(WORD.findall(korean)) <= 2
        and len(english) <= MAX_EXAMPLE_EN
        and len(korean) <= MAX_EXAMPLE_KO
        and not re.search(r"[{}\[\]<>|+…]|\.\.\.|https?:", english + korean)
        and english.count("(") == english.count(")")
        and korean.count("(") == korean.count(")")
        and mentions(word, english)
    )


def pick_example(word, examples):
    """문장(4~14 낱말)을 먼저, 없으면 짧은 구."""
    candidates = []
    for example in examples or []:
        ref = example.get("ref", "")
        # 출처가 따로 있는 인용문은 이용 조건을 알 수 없어 뺀다. VOA 는 공공 영역.
        if ref and "public domain" not in ref:
            continue
        text = example.get("text", "").replace("\n", " ")
        if example.get("translation"):
            pair = (text, example["translation"].replace("\n", " "))
        else:
            pair = split_example(text)
        if not pair:
            continue
        english, korean = tidy_example(*pair)
        if usable(word, english, korean):
            count = len(english.split())
            candidates.append((0 if 4 <= count <= 14 else 1, len(candidates), [english, korean]))
    return min(candidates)[2] if candidates else None


def load_forms():
    forms = {}
    for line in (RESOURCES / "Wordlists/NGSL.txt").read_text(encoding="utf-8").splitlines():
        if line and not line.startswith("#"):
            items = [item.strip().lower() for item in line.split(",")]
            forms.setdefault(items[0], items)
    return forms


def load_corpus():
    """앱 안의 번역된 문장과, 낱말 → 문장 번호."""
    pairs = [(w["exampleEn"], w["exampleKo"]) for w in json.loads((RESOURCES / "BundledWords.json").read_text(encoding="utf-8"))]

    def walk(node):
        if isinstance(node, dict):
            if isinstance(node.get("text"), str) and isinstance(node.get("translation"), str):
                pairs.append((node["text"], node["translation"]))
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    for name in CORPUS_BOOKS:
        walk(json.loads((RESOURCES / f"Books/{name}.json").read_text(encoding="utf-8")))
    index = {}
    for number, (english, _) in enumerate(pairs):
        for token in set(re.findall(r"[a-z'-]+", english.lower())):
            index.setdefault(token, []).append(number)
    return pairs, index


# 뜻이 아니라 흔한 말이라 번역에 우연히 나온다.
COMMON_STEMS = {"그리", "그러", "이러", "우리", "있는", "없는", "하는", "되는", "것이", "사람", "때문", "위하", "대하", "여러", "모든", "다른", "매우", "아주"}


def stems(sense):
    result = []
    for item in re.sub(r"\([^()]*\)", "", sense).split(","):
        item = item.strip(" ~")
        for suffix in ("시키다", "하다", "되다", "스러운", "하게", "으로", "적인", "한", "된", "의", "다", "히"):
            if item.endswith(suffix) and len(item) - len(suffix) >= 2:
                item = item[: -len(suffix)]
                break
        if len(item) >= 2 and " " not in item and item not in COMMON_STEMS:
            result.append(item)
    return result


DETERMINERS = set("a an the this that these those my your his her its our their each every no some any of for".split())
VERB_LEADS = set("to will can must may should would could might do does did not i we you they please who never".split())


def fits_position(pos, form, word, english):
    """앞 낱말로 본 품사. 명사 뜻에 동사로 쓰인 문장("will focus on")을 붙이지 않는다."""
    tokens = re.findall(r"[a-z'-]+", english.lower())
    place = tokens.index(form)
    before = tokens[place - 1] if place else ""
    if pos == "n.":
        plurals = {word, word + "s", word + "es", re.sub("y$", "ies", word), re.sub("fe?$", "ves", word)}
        # 문장 맨 앞의 원형은 명령문일 수 있다 ("Thank you …").
        return form in plurals and before not in VERB_LEADS and (place > 0 or form != word)
    if pos == "v.":
        return before not in DETERMINERS
    return True


def corpus_example(word, pos, sense, corpus, excluding=None):
    pairs, index = corpus
    roots = stems(sense)
    if not roots:
        return None
    pattern = re.compile(r"(?:^|[\s\"'“‘(])(?:" + "|".join(map(re.escape, roots)) + ")")
    for form in FORMS.get(word, [word]):
        for number in index.get(form, []):
            english, korean = pairs[number]
            if english != excluding and len(english) <= MAX_EXAMPLE_EN and pattern.search(korean) and fits_position(pos, form, word, english):
                return [english, korean]
    return None


def glossary_examples(corpus):
    """책 사전 뜻의 예문. 그 낱말이 처음 나온 본문 문장은 카드에서 방금 읽은 글이라 뺀다."""
    result = {}
    for path in sorted((RESOURCES / "Books").glob("*.json")):
        book = json.loads(path.read_text(encoding="utf-8"))
        for entry in book.get("glossary", []):
            word, first = entry["lemma"].lower(), entry.get("firstPosition")
            own = None
            if first:
                paragraph = book["chapters"][first["chapter"]]["paragraphs"][first["paragraph"]]
                own = paragraph["sentences"][first["sentence"]]["text"]
            for segment in entry["meaning"].split(" / "):
                match = re.match(r"(n|v|adj|adv|prep|pron|conj|interj)\. ", segment)
                pos = match.group(0).strip() if match else entry.get("partOfSpeech") or ""
                text = segment[match.end():] if match else segment
                found = corpus_example(word, pos, text, corpus, excluding=own)
                if found:
                    result.setdefault(word, {}).setdefault(text, found)
    return result


# MARK: 만들기

def make_sense(entry_sense):
    """뜻 하나의 글. 낱말 뜻을 쉼표로 이어 두 줄 안에 넣는다."""
    kept = ""
    for gloss in entry_sense.get("glosses", [])[-1:]:
        for part in clean(gloss):
            joined = f"{kept}, {part}" if kept else part
            if len(joined) > MAX_GLOSS:
                break
            kept = joined
    return kept


def choose_senses(senses):
    """첫 뜻은 늘 두고, 나머지는 예문이 있는 뜻을 먼저 고른다. 순서는 사전 그대로."""
    unique = []
    for text, example in senses:
        same = next((index for index, item in enumerate(unique) if text in item[0]), None)
        if same is None:
            unique.append((text, example))
        elif example and not unique[same][1]:
            unique[same] = (unique[same][0], example)
    order = sorted(range(len(unique)), key=lambda index: (index != 0, unique[index][1] is None, index))
    return [unique[index] for index in sorted(order[:MAX_SENSES])]


def main():
    source, dump_date = Path(sys.argv[1]), sys.argv[2]
    corpus = load_corpus()
    lower, proper = {}, {}
    with gzip.open(source, "rt", encoding="utf-8") as lines:
        for line in lines:
            entry = json.loads(line)
            if entry.get("lang_code") != "en" or entry["pos"] in SKIPPED_POS:
                continue
            word = entry["word"].replace("’", "'").strip()
            key = word.lower()
            # 대문자 약어(US, IT)는 낱말(us, it)과 겹치고, 낱글자는 뜻이 아니다.
            if not KEY.match(key) or (word.isupper() and len(word) > 1) or (len(word) == 1 and word not in ("a",)):
                continue
            senses = []
            for entry_sense in entry["senses"]:
                text = make_sense(entry_sense)
                if text:
                    senses.append((text, pick_example(key, entry_sense.get("examples"))))
            if not senses or key in REMOVED:
                continue
            glosses = [text for text, _ in senses]
            if " " in key:
                pos = ""  # 구절은 품사를 붙이지 않는다
            else:
                pos = POS.get(entry["pos"]) or guess_pos(entry, glosses)
                if pos == "n." and key.endswith("ly") and re.search(r"(?:으로|하게|히)$", glosses[0]):
                    pos = "adv."
                # 원본에 명사로 잘못 적힌 동사 ("모습을 바꾸게 하다")
                if pos == "n." and all(re.search(r"(?:하|시키|되)다$", gloss) for gloss in glosses):
                    pos = "v."
            target = lower if word == key else proper
            target.setdefault(key, {}).setdefault(pos, []).extend(senses)

    words, examples, app_examples = {}, {}, {}
    for key in sorted(set(lower) | set(proper)):
        lines = []
        for pos, senses in list((lower.get(key) or proper[key]).items())[:MAX_POS]:
            chosen = choose_senses(senses)
            for text, example in chosen:
                if example:
                    examples.setdefault(key, {})[text] = example
                elif pos in ("n.", "v.", "adj.", "adv."):
                    found = corpus_example(key, pos, text, corpus)
                    if found:
                        app_examples.setdefault(key, {})[text] = found
            lines.append(f"{pos} {'; '.join(text for text, _ in chosen)}".strip())
        words[key] = " / ".join(lines)

    glossary = glossary_examples(corpus)
    data = {
        "source": "한국어 위키낱말사전 (Korean Wiktionary), kaikki.org 추출",
        "sourceURL": "https://ko.wiktionary.org",
        "license": "CC BY-SA 4.0",
        "dumpDate": dump_date,
        "changes": "영어 항목의 뜻과 예문만 골라 짧게 다듬고 품사 약어를 붙였다.",
        "words": words,
        "examples": examples,
    }
    OUTPUT.write_text(compact(data), encoding="utf-8")
    EXAMPLES_OUTPUT.write_text(compact({"examples": app_examples, "glossary": glossary}), encoding="utf-8")
    for path, values in ((OUTPUT, examples), (EXAMPLES_OUTPUT, app_examples), (EXAMPLES_OUTPUT, glossary)):
        count = sum(len(value) for value in values.values())
        print(f"{path.relative_to(ROOT)}: {path.stat().st_size // 1024}KB, 예문 {count}개 ({len(values)} 단어)")
    print(f"{len(words)} words, 뜻 {sum(line.count('; ') + line.count(' / ') + 1 for line in words.values())}개")


def compact(data):
    """낱말마다 한 줄 (변경 내용을 비교하기 쉽게)."""
    out = []
    for key, value in data.items():
        if isinstance(value, dict):
            rows = ",\n".join(f"{json.dumps(k, ensure_ascii=False)}:{json.dumps(v, ensure_ascii=False)}" for k, v in value.items())
            out.append(f"{json.dumps(key)}:{{\n{rows}\n}}")
        else:
            out.append(f"{json.dumps(key)}:{json.dumps(value, ensure_ascii=False)}")
    return "{" + ",\n".join(out) + "}\n"


FORMS = load_forms()
main()
