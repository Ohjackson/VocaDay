"""앱에 번들된 프롬프트(VocaDay/Resources/ExamPrompts)를 Gemini로 돌려 SPEC §6.3 검증 통과율을 본다.

앱(EnrichmentService)과 같은 방식으로 요청한다:
  system = en_word_system.txt, prompt = en_words_prompt.txt 의 ${...} 치환,
  responseSchema = en_word_schema.json, 검증 실패 시 <correction> 블록을 붙여 1회 재요청.

사용법 (docs/srs-port 에서):
  python3 tools/run_prompt_eval.py --dry-run                 # 키 없이 프롬프트 조립만 점검
  GEMINI_API_KEY=... python3 tools/run_prompt_eval.py         # samples 의 input 8개
  GEMINI_API_KEY=... python3 tools/run_prompt_eval.py --real 10   # 앱 번들 RealDataBackup.json 의 실제 단어 10개도
옵션: --model gemini-3.5-flash-lite  --thinking low
"""
import argparse, json, os, re, sys, time, urllib.request, urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
PORT = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(PORT))
PROMPTS = os.path.join(REPO, "VocaDay", "Resources", "ExamPrompts")

# validate_reference.py 의 validate() 를 그대로 쓴다 (파일 하단의 자체 테스트 코드는 실행하지 않음).
_src = open(os.path.join(PORT, "samples", "validate_reference.py"), encoding="utf-8").read()
_ns = {}
exec(_src.split("here = os.path")[0], _ns)
validate = _ns["validate"]


def read(name):
    return open(os.path.join(PROMPTS, name), encoding="utf-8").read()


def esc(v):
    return v.replace("<", "‹").replace(">", "›")


def substitute(template, values):
    return re.sub(r"\$\{([a-z_]+)\}", lambda m: values.get(m.group(1), m.group(0)), template)


# 앱의 ExamText.strippingPartOfSpeechMarkers / firstExampleLine 과 같은 전처리
POS_RE = re.compile(r"(?i)(?<![A-Za-z])(n|v|vt|vi|adj|adv|phr|prep|conj|pron|interj|int|idiom|aux)\.\s*")


def strip_pos(s):
    return POS_RE.sub("", s).strip()


def first_line(s):
    line = next((l.strip() for l in s.splitlines() if l.strip()), "")
    return re.sub(r"^\d+[.)]\s*", "", line)


def call_gemini(api_key, model, thinking, system, prompt, schema):
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
    body = {
        "systemInstruction": {"parts": [{"text": system}]},
        "contents": [{"role": "user", "parts": [{"text": prompt}]}],
        "generationConfig": {
            "responseMimeType": "application/json",
            "responseSchema": schema,
            "thinkingConfig": {"thinkingLevel": thinking},
            "maxOutputTokens": 4096,
        },
    }
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST",
                                 headers={"Content-Type": "application/json", "x-goog-api-key": api_key})
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            data = json.load(r)
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"HTTP {e.code}: {e.read().decode()[:300]}")
    parts = data["candidates"][0]["content"]["parts"]
    usage = data.get("usageMetadata", {})
    return "".join(p.get("text", "") for p in parts if not p.get("thought")), usage


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--model", default="gemini-3.5-flash-lite")
    ap.add_argument("--thinking", default="low")
    ap.add_argument("--real", type=int, default=0)
    args = ap.parse_args()

    system = read("en_word_system.txt")
    template = read("en_words_prompt.txt")
    schema = json.loads(read("en_word_schema.json"))

    samples = json.load(open(os.path.join(PORT, "samples", "sample_words.json"), encoding="utf-8"))
    cases = [("sample", s["input"]) for s in samples["valid"]]
    if args.real:
        backup = json.load(open(os.path.join(REPO, "VocaDay", "Resources", "RealDataBackup.json"), encoding="utf-8"))
        words = [w for d in backup["vocabularyDays"] for w in d["words"]][: args.real]
        cases += [("real", {"term": w["english"].strip(), "user_meaning_ko": strip_pos(w["meaningKo"]),
                            "user_example": first_line(w["exampleEn"])}) for w in words]

    if args.dry_run:
        for kind, inp in cases:
            p = substitute(template, {k: esc(v) for k, v in inp.items()})
            assert "${" not in p, "치환 안 된 변수"
            print(f"[{kind}] {inp['term']!r:24} meaning={inp['user_meaning_ko']!r} prompt={len(p)}자")
        print(f"system {len(system)}자, schema keys={list(schema['properties'])}")
        print("DRY RUN OK — 모든 ${...} 치환됨")
        return

    key = os.environ.get("GEMINI_API_KEY")
    if not key:
        sys.exit("GEMINI_API_KEY 가 없습니다. --dry-run 으로 조립만 점검할 수 있어요.")

    first_pass = after_fix = 0
    tokens = 0
    for kind, inp in cases:
        prompt = substitute(template, {k: esc(v) for k, v in inp.items()})
        errs, attempt_log = ["no response"], []
        for attempt in range(2):
            try:
                text, usage = call_gemini(key, args.model, args.thinking, system, prompt, schema)
                tokens += usage.get("totalTokenCount", 0)
                entry = json.loads(text)
                errs = validate(entry, inp["term"])
            except Exception as e:  # 네트워크·JSON 오류도 실패로 센다
                errs, entry = [f"error: {e}"], {}
            attempt_log.append(errs)
            if not errs:
                break
            msg = "\n".join(f"- [{c}]" for c in errs)
            prompt = f"{prompt}\n\n<correction>\nThe previous response failed these checks:\n{msg}\nRe-check every rule and return only the corrected JSON.\n</correction>"
            time.sleep(1)
        ok1 = not attempt_log[0]
        ok = not attempt_log[-1]
        first_pass += ok1
        after_fix += ok
        status = "PASS" if ok1 else ("FIXED" if ok else "FAIL")
        detail = "" if ok1 else f" 1차:{attempt_log[0]}" + ("" if len(attempt_log) < 2 else f" 2차:{attempt_log[1]}")
        print(f"{status:5} [{kind}] {inp['term']!r} → {entry.get('meaning_ko', '')!r} | {entry.get('cloze_sentence', '')}{detail}")

    n = len(cases)
    print(f"\n1차 통과 {first_pass}/{n} ({first_pass / n:.0%}), 교정 재요청 후 {after_fix}/{n} ({after_fix / n:.0%}), 총 토큰 {tokens}")


if __name__ == "__main__":
    main()
