"""SPEC §6.3 로컬 검증의 참조 구현. Swift EntryValidator 를 만들 때 이 동작과 테스트 결과가 같아야 한다.
실행: python3 validate_reference.py  (sample_words.json 의 valid 는 전부 통과, invalid 는 전부 실패해야 함)"""
import json, re, copy, os

FORM_KEYS = ["base","past","past_participle","present_participle","third_person","plural","comparative","superlative"]
ALLOWED = {
    "noun": {"base","plural"},
    "verb": {"base","past","past_participle","present_participle","third_person"},
    "phrasal_verb": {"base","past","past_participle","present_participle","third_person"},
    "adjective": {"base","comparative","superlative"},
}
POS = ["noun","verb","adjective","adverb","phrasal_verb","idiom","preposition","conjunction","other"]
CEFR = ["A1","A2","B1","B2","C1","C2"]
HANGUL = re.compile(r"[가-힣]")

def norm(s):
    s = s.strip().lower().replace("’","'").replace("‘","'").replace("ʼ","'")
    s = re.sub(r"\s+"," ",s)
    return re.sub(r"[.,!?]+$","",s)

def words(s):
    return re.findall(r"[a-z'-]+", s.lower())

def contains_phrase(text_words, phrase):
    p = words(phrase); n = len(p)
    return sum(1 for i in range(len(text_words)-n+1) if text_words[i:i+n] == p)

def validate(e, requested_term):
    errs = []
    for f in ["term","pos","meaning_ko","example","example_ko","cloze_sentence","cloze_answer","cloze_form"]:
        if not str(e.get(f,"")).strip(): errs.append(f"empty:{f}")
    if errs: return errs
    if norm(e["term"]) != norm(requested_term): errs.append("term_mismatch")
    if e["pos"] not in POS: errs.append("pos")
    if e.get("cefr") not in CEFR: errs.append("cefr")
    cs, ans, ex = e["cloze_sentence"], e["cloze_answer"], e["example"]
    if cs.count("<>") != 1 or cs.replace("<>", ans) != ex: errs.append("restore")
    forms = e["forms"]
    if e["cloze_form"] != "other" and ans.lower() != forms.get(e["cloze_form"],"").lower(): errs.append("form")
    if not forms.get("base") or norm(forms["base"]) != norm(e["term"]): errs.append("base")
    allowed = ALLOWED.get(e["pos"], {"base"})
    if any(forms.get(k,"") for k in FORM_KEYS if k not in allowed): errs.append("forms_pos")
    before = cs.split("<>")[0]
    if not before.strip(): errs.append("first_word")
    prev = words(before)[-1:] 
    if prev in (["a"],["an"]): errs.append("article_hint")
    ex_words = words(ex)
    all_forms = {forms[k] for k in FORM_KEYS if forms.get(k)} | set(e.get("term_variants",[]))
    if sum(contains_phrase(ex_words, f) for f in all_forms if f.lower() != ans.lower()) + contains_phrase(ex_words, ans) > 1:
        errs.append("repeat")
    if not HANGUL.search(e["meaning_ko"]) or not HANGUL.search(e["example_ko"]): errs.append("hangul")
    if len(e["meaning_ko"]) > 20: errs.append("meaning_len")
    if len(e.get("disambiguation_ko","")) > 40: errs.append("disamb_len")
    if not (6 <= len(ex.split()) <= 22) or len(ex) > 200: errs.append("example_len")
    nm = [norm(x) for x in e.get("near_miss_synonyms",[])]
    if len(nm) > 4 or any(x in {norm(f) for f in all_forms} for x in nm): errs.append("near_miss")
    return errs

here = os.path.dirname(os.path.abspath(__file__))
data = json.load(open(os.path.join(here, "sample_words.json")))
base = {s["entry"]["term"]: s["entry"] for s in data["valid"]}
ok = True
for s in data["valid"]:
    r = validate(s["entry"], s["input"]["term"])
    print(("PASS " if not r else "FAIL ") + s["entry"]["term"], r or "")
    ok &= not r
for s in data["invalid"]:
    e = copy.deepcopy(base[s["entry_patch"]["term"]]); e.update(s["entry_patch"])
    r = validate(e, e["term"])
    expected = s["why"].split("(")[-1].rstrip(")")
    hit = expected in r
    print(("REJECT " if hit else "MISSED ") + s["why"], r)
    ok &= hit
print("ALL GOOD" if ok else "SOMETHING WRONG")
