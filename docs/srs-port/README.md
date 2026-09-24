# english-srs-port — 단고초 SRS를 영어 단어장 앱으로 옮기기 위한 패키지

## 무엇을 넘기면 되나

영어 앱 레포에 이 폴더를 통째로 `docs/srs-port/`로 복사하고, `CLAUDE_CODE_KICKOFF.md`의 프롬프트를 붙여넣으면 된다.
Claude가 영어 앱의 모델·저장소·LLM 설정은 직접 조사하므로, **네가 따로 준비할 건 결정 3가지뿐**이다:
LLM 제공자(기본 Gemini), iCloud 동기화 여부, 최소 iOS 버전.

```
english-srs-port/
├── README.md                     ← 이 파일
├── CLAUDE_CODE_KICKOFF.md        ← 영어 앱 레포에서 Claude Code에 붙여넣을 시작 프롬프트
├── SPEC.md                       ← 구현 명세 (데이터 모델 / SRS / 세션 / 문제 4종 / 채점 / 보강 / 수락 기준)
├── prompts/
│   ├── en_word_system.txt        ← 단어 보강 system instruction
│   ├── en_words_prompt.txt       ← 단어 1개 보강 (${term} ${user_meaning_ko} ${user_example})
│   ├── en_word_schema.json       ← 구조화 출력 스키마 (Gemini responseSchema 형식)
│   ├── en_korean_to_english.txt  ← 한글 입력 → 영어 표제어
│   ├── en_backfill_prompt.txt    ← 기존 단어 10개씩 일괄 보강 (앱 내 API / 외부 AI 붙여넣기 겸용)
│   └── en_sentence_grading_prompt.txt ← (선택) 작문 채점
├── reference/                    ← 단고초 원본 코드 (SRSManager, SRSCardsViewModel, 세션 상태·검증 발췌, 일본어 프롬프트)
└── samples/
    ├── sample_words.json         ← 골든 데이터 8개 + 일부러 망가뜨린 7개
    └── validate_reference.py     ← SPEC §6.3 검증기 참조 구현 (python3 로 실행 → ALL GOOD)
```

## 설계 요점

| 항목 | 결정 |
|---|---|
| SRS | 원본과 수치 동일: 간격 `[0,1,1,2,2,4,7,13,30,40,50]`, 하루 100개, 틀리면 stage −1, 6시간 뒤 재도전, "학습일"은 세션을 완주해야 +1 |
| 채점 단위 | 단어 하나당 채점 문제 1개. 원본의 카드 스와이프 1회와 같은 의미 |
| 문제 유형 | stage에 따라 결정: 0 → 새 단어 카드 + 짝 맞추기, 1–2 → 빈칸 고르기, 3–5 → 빈칸 쓰기, 6+ → 한→영 쓰기 |
| 출제 대상 데이터 | 사용자 단어 **전체** (페이지 선택 없음). 오답 보기·짝 맞추기 채움 단어도 전체에서 뽑음 |
| 오답 보기 품질 | 각 단어의 활용형(`forms`)을 저장해 두고, 보기를 **정답과 같은 활용형**으로 맞춰 보여줌 (gave up ↔ turned down). 세션마다 LLM을 부를 필요 없음 |
| 사용자 데이터 우선 | 사용자가 적은 한국어 뜻이 있으면 그 의미로 예문을 만듦 (bank + "둑" → 강둑). 사용자가 적은 예문이 유효하면 그대로 씀 |
| 듀오링고 느낌 | 15문제 레슨 단위, 즉시 피드백, TTS, 틀린 문제는 세션 끝에 "오답 다시 풀기"로 한 번 더 (SRS 반영 X) |
| 보강 전 단어 | 뜻만 있어도 짝 맞추기 + 한→영 쓰기로 시험 가능 → 일괄 보강이 끝나기 전에도 바로 쓸 수 있음 |

## 프롬프트가 막아 주는 문제들

- `a <>` / `an <>` 때문에 관사로 답이 드러나는 문제 → 빈칸 앞 a/an 금지
- 정답이 문장 맨 앞이라 대문자로 답이 드러나는 문제 → 맨 앞 금지
- 예문에 같은 단어가 두 번 나와 답이 보이는 문제 → 중복 금지
- 구동사를 떼어 써서(gave it up) 빈칸이 두 개가 되는 문제 → 붙여 쓰기
- 뜻이 겹치는 단어(result/consequence)가 보기에 같이 나와 정답이 둘이 되는 문제 → `near_miss_synonyms`로 보기에서 제외
- 한→영 쓰기에서 동의어를 쓰면 무조건 틀리는 문제 → `near_miss_synonyms`면 벌점 없이 한 번 더 기회

## 원본에서 옮긴 것 / 새로 만든 것

- **그대로 옮김**: SRSManager 전체, 1차/재도전 결과 처리, 홈 버튼 3상태, 6시간 알림, LLM 검증 실패 → 교정 재요청 1회, 외부 AI 붙여넣기 일괄 저장
- **새로 만듦**: 문제 유형 배정(SessionPlanner), 입력 채점(AnswerGrader: 정규화·오타 1글자 허용·near miss), 세션 이어하기(`activeSessionJSON`), 활용형 기반 오답 보기 생성
