# 영어 단어장 시험 모드 명세 (단고초 SRS 이식판)

> 대상: 기존 영어 단어장 앱. **단어장 보기 화면은 수정하지 않는다.** 이 문서는 "시험보기"만 다룬다.
> 원본: 단고초(일본어) `SRSManager`, `SRSCardsViewModel`, `HomeViewModel.sessionStatus`, `LLMService` (→ `reference/` 폴더).

---

## 0. 한 줄 요약

사용자가 넣은 **단어 전체**를 단고초와 똑같은 SRS(학습일 기반 간격표 + 6시간 뒤 재도전)로 스케줄링하고,
오늘 복습할 단어마다 **stage에 맞는 문제 1개**를 4가지 유형(짝 맞추기 / 빈칸 고르기 / 빈칸 쓰기 / 한→영 쓰기) 중에서 골라 듀오링고처럼 이어서 낸다.
보기(오답 선택지)와 짝 맞추기의 채움 단어는 **사용자 단어 전체**에서 뽑는다.

---

## 1. 데이터 모델

### 1.1 단어 (기존 엔티티에 필드 추가)

기존 영어 앱의 단어 엔티티를 **그대로 두고** 아래 필드만 추가한다. 이름이 이미 있으면 기존 이름에 매핑한다.

| 필드 | 타입 | 필수 | 설명 |
|---|---|---|---|
| `term` | String | ✅(기존) | 사용자가 넣은 표제어. 구동사·숙어는 띄어쓰기 포함 (`give up`) |
| `meaningKo` | String | ✅(기존) | 대표 한국어 뜻 1개. **사용자가 적은 뜻이 있으면 그것이 우선** |
| `pos` | String enum | 보강 | `noun, verb, adjective, adverb, phrasal_verb, idiom, preposition, conjunction, other` |
| `cefr` | String | 보강 | `A1`~`C2` (보기 난이도 맞추기용) |
| `disambiguationKo` | String | 보강 | 한→영 쓰기에서 다른 영어 단어와 헷갈리지 않게 하는 짧은 설명. 없으면 `""` |
| `formsJSON` | String(JSON) | 보강 | `{base, past, past_participle, present_participle, third_person, plural, comparative, superlative}` 해당 없는 키는 `""` |
| `termVariantsJSON` | String(JSON 배열) | 보강 | 표제어의 철자 변형 (`colour`, `e-mail`). 동의어 아님 |
| `example` | String | 보강 | 영어 예문 (사용자 예문이 있으면 그것) |
| `exampleKo` | String | 보강 | 예문 한국어 번역 |
| `clozeSentence` | String | 보강 | 예문에서 정답 부분만 `<>`로 바꾼 문장 |
| `clozeAnswer` | String | 보강 | `<>`에 들어가는 실제 표기 (`gave up`) |
| `clozeForm` | String enum | 보강 | `clozeAnswer`가 forms의 어느 키인지. `base, past, past_participle, present_participle, third_person, plural, comparative, superlative, other` |
| `clozeAcceptedJSON` | String(JSON 배열) | 보강 | 빈칸 쓰기에서 추가로 정답 인정하는 표기 (영/미 철자 등) |
| `nearMissJSON` | String(JSON 배열) | 보강 | 학습자가 이 뜻으로 쓸 법한 **다른** 영어 단어. 오답이 아닌 "다시 써보기" 처리용 |
| `enrichmentVersion` | Int16 | 보강 | 0 = 보강 안 됨. 프롬프트 버전이 오르면 재보강 대상 판단 |
| `needsEnrichment` | Bool | 보강 | 사용자가 `term`/`meaningKo`를 수정하면 true → 다음 기회에 재생성 |

> 보강(enrichment) 필드가 비어 있어도 시험은 돌아가야 한다. `term + meaningKo`만 있으면 **짝 맞추기·한→영 쓰기**는 가능하다 (§4.5 폴백).

### 1.2 SRS 카드 (단어와 1:1, 원본과 동일)

| 필드 | 타입 | 초기값 |
|---|---|---|
| `stage` | Int16 | 0 (0…10) |
| `nextLearningDay` | Int64 | 0 |
| `idkCount` | Int16 | 0 |

단어 생성 시 카드도 같이 만든다. 기존 단어는 마이그레이션에서 카드를 일괄 생성한다 (`stage 0, nextLearningDay 0`).
→ 마이그레이션 직후엔 모든 단어가 "오늘 복습"이 되지만 하루 상한(100개) 덕분에 자연스럽게 분산된다.

### 1.3 사용자 진행 상태 (원본 `UserProfile` / `UserSettings`와 동일 의미)

| 필드 | 설명 |
|---|---|
| `currentLearningDay: Int64` | **달력 날짜가 아니라 "학습을 끝낸 횟수"**. 세션을 완주해야 +1 |
| `srsSessionInProgress: Bool` | 1차 세션에서 틀린 게 있어 재도전 대기 중인지 |
| `srsFirstSessionCompletionTime: Date?` | 1차 세션 끝난 시각 (재도전 6시간 계산) |
| `srsWrongAnswerWordIDsJSON: String?` | 재도전 대상 단어 UUID 배열 |
| `srsUpdatedAt: Date?` | 마지막 반영 시각 |
| `activeSessionJSON: String?` | **신규**. 진행 중 세션 스냅샷 (§3.5, 중간 종료 후 이어하기) |

### 1.4 (선택) 풀이 로그

`ReviewLog { wordID, sessionKind(first/retry), mode, isCorrect, userInput, answeredAt }`
SRS 판정에는 쓰지 않는다. 나중에 "자주 틀리는 유형" 통계에만 쓴다. 급하지 않으면 생략.

---

## 2. SRS 규칙 (원본 그대로, 절대 바꾸지 말 것)

```
BASE_GAPS = [0, 1, 1, 2, 2, 4, 7, 13, 30, 40, 50]   // index = stage
DAILY_REVIEW_LIMIT = 100
RETRY_DELAY = 6시간
```

### 2.1 오늘의 복습 대상
```
nextLearningDay <= currentLearningDay 인 카드
정렬: nextLearningDay 오름차순 → 단어 생성일 오름차순
최대 100개 (초과분은 다음 세션에 자동으로 우선 노출)
```
**대상은 사용자 단어 전체**다. 페이지·단어장 선택 없음.

### 2.2 1차 세션 채점 반영 (단어별, 세션 종료 시 한꺼번에)
- 맞음 → `stage = min(stage+1, 10)`, `nextLearningDay = currentLearningDay + BASE_GAPS[stage]`
- 틀림 → `idkCount += 1`, `stage = max(stage-1, 0)`, **nextLearningDay는 그대로** → 재도전 목록에 추가

세션 종료 후:
- 틀린 단어 0개 → `currentLearningDay += 1`, 세션 상태 초기화
- 1개 이상 → `srsSessionInProgress = true`, `srsFirstSessionCompletionTime = now`, 틀린 ID 저장, 6시간 뒤 로컬 알림 예약

### 2.3 재도전 세션 (완료 후 6시간 지나야 열림)
- 대상: `srsWrongAnswerWordIDsJSON`
- 맞음 → 1차의 "맞음"과 동일
- 틀림 → `idkCount += 1`, `stage = max(stage-1, 0)`, `nextLearningDay = currentLearningDay + 1`
- 끝나면 결과와 무관하게 `currentLearningDay += 1`, 세션 상태 초기화

### 2.4 홈 버튼 상태
`오늘의 학습 시작` / `재도전까지 HH:MM 남음`(비활성) / `재도전 학습 시작` — 원본 `sessionStatus` 로직 그대로.

### 2.5 저장 안전장치
- 결과 반영은 **한 번만** (`hasProcessedCurrentResults` 플래그). 저장 실패 시 rollback + 플래그 해제.
- iCloud 동기화를 쓰면 원본의 `SRSProgressHighWaterStore`(nextLearningDay·idkCount 역행 방지)도 이식. 안 쓰면 생략.

---

## 3. 세션 구성 (듀오링고식 흐름)

### 3.1 핵심 원칙
1. **단어 하나당 채점 문제 1개.** SRS 판정은 그 문제의 결과 하나로 한다 (원본 카드 스와이프 1회와 같은 의미).
2. 문제 유형은 **stage로 결정** — 익숙할수록 어려운 유형 (§3.2).
3. 1차 세션 채점이 끝나면, 틀린 단어는 **"오답 다시 풀기"**로 세션 끝에 한 번 더 나온다. 이건 **채점에 반영하지 않는** 학습용이다 (맞힐 때까지 반복). SRS상 재도전은 여전히 6시간 뒤.
4. 재도전 세션에는 "오답 다시 풀기"를 붙이지 않는다 (끝나면 하루 종료).

### 3.2 stage → 문제 유형

| stage | 기본 유형 | 대체(다양성, 25% 확률) |
|---|---|---|
| 0 (처음 보는 단어) | **새 단어 카드**(채점 X) → **M1 짝 맞추기** | — |
| 1–2 | **M2 빈칸 고르기** | M1 |
| 3–4 | **M3 빈칸 쓰기** (첫 글자 힌트) | M2 |
| 5 | **M3 빈칸 쓰기** (글자 수만 힌트) | M4 |
| 6–10 | **M4 한→영 쓰기** | M3 (힌트 없음) |

- stage 0의 "새 단어 카드": `idkCount == 0`이고 한 번도 채점된 적 없는 단어만. 뜻·예문·발음(TTS)을 보여주고 "알겠어요"로 넘어감.
- 재도전 세션은 **강등된 현재 stage 기준**으로 같은 표를 쓴다.
- 대체 유형은 `(wordID 해시 + currentLearningDay)` 기반 결정적 난수로 고른다 → 앱을 다시 켜도 같은 문제가 나옴.

### 3.3 문제 순서
1. M1(짝 맞추기) 묶음을 앞쪽에 (워밍업)
2. 나머지는 섞되, **같은 유형이 3번 연속 나오지 않게**, 같은 단어가 연달아 나오지 않게
3. 진행 바 = 채점 문제 완료 수 / 전체 채점 문제 수 (새 단어 카드·오답 다시 풀기는 제외)

### 3.4 레슨 단위
100개가 한 번에 나오면 지치므로 **15문제 단위 "레슨"**으로 끊고, 레슨 사이에 "계속하기 / 나중에" 화면을 둔다.
SRS 반영은 원본처럼 **세션(오늘 대상 전체) 완료 시 한 번**만 한다.

### 3.5 중간 종료 / 이어하기
`activeSessionJSON`에 저장:
```json
{
  "sessionID": "uuid",
  "kind": "first | retry",
  "learningDay": 42,
  "plan": [ {"mode": "M1", "wordIDs": ["..."], "fillerWordIDs": ["..."]}, {"mode": "M3", "wordIDs": ["..."]} ],
  "cursor": 17,
  "results": { "wordUUID": true, "wordUUID2": false }
}
```
- 문제 하나 답할 때마다 저장.
- 앱 재실행 시 `learningDay`가 현재와 같으면 이어하기, 다르면 폐기하고 새로 계획.
- 계획 도중 삭제된 단어는 건너뛰고 결과에서도 뺀다.

---

## 4. 문제 유형 상세

공통 UI: 상단 진행 바, 하단 "확인" 버튼 → 정답/오답 배너(초록/빨강) + 정답 표시 + 예문 전체 + 발음 버튼(`AVSpeechSynthesizer`, `en-US`) → "계속".

### M1. 짝 맞추기 (영어 ↔ 한국어)
- 한 화면에 **5쌍** (최소 3쌍). 왼쪽 영어 `term`, 오른쪽 `meaningKo`, 양쪽 각각 섞음.
- 채점 대상: stage 0 단어(또는 대체 유형으로 배정된 단어). 한 화면 최대 5개.
- 채점 대상이 4개 미만이면 **채움 단어(filler)**로 채운다 → 채점 X.
  - 채움 단어 후보: 사용자 단어 전체 중 오늘 대상이 아닌 것, stage ≥ 3 우선, 무작위.
- **모호성 금지**: 같은 화면에 정규화한 `meaningKo`가 같은 쌍이 오면 안 된다.
  정규화 = 공백·문장부호 제거, 괄호 내용 제거, 끝의 `하다/한/히/게` 제거 후 비교. 겹치면 채움 단어를 교체, 채점 대상끼리 겹치면 다른 화면으로 분리.
- 채점: 영어 단어를 기준으로, **그 영어 단어의 첫 연결 시도**가 맞으면 정답. 틀린 연결 → 흔들림 애니메이션 + 선택 해제, 그 영어 단어는 오답 처리(이후 맞게 연결해야 화면 종료).
- 영어 단어를 탭하면 발음 재생.

### M2. 예문 빈칸 고르기 (4지선다)
- `clozeSentence`의 `<>`를 `_____`로 보여주고, 아래에 `exampleKo`를 흐리게 표시.
- 보기 = 정답 `clozeAnswer` + 오답 3개. **오답은 사용자 단어 전체에서 뽑는다:**

```
distractors(target):
  pool = 사용자 단어 전체 - target
  pool = pool.filter {
      같은 품사 그룹 (verb↔verb, phrasal_verb↔phrasal_verb, noun↔noun, adjective↔adjective, adverb↔adverb)
      && $0.forms[target.clozeForm] 가 비어있지 않음
      && normalize($0.meaningKo) != normalize(target.meaningKo)
      && $0.term ∉ target.nearMiss && target.term ∉ $0.nearMiss      // 문장에 같이 들어맞을 위험
      && $0.forms[target.clozeForm] != target.clozeAnswer
  }
  rendered = pool.map { $0.forms[target.clozeForm] }   // ← 정답과 같은 활용형으로 맞춰서 보여줌 (gave up ↔ turned down)
  정렬 점수: CEFR 차이 작을수록 +, 글자 수 차이 ≤3 이면 +, 최근 5문제에서 보기로 쓰였으면 −
  상위 8개 중 무작위 3개
  3개 미만이면 → 이 단어는 M3로 폴백
```
- 정답이 문장 첫 단어라면 보기도 첫 글자 대문자 (프롬프트에서 막지만 방어 코드로).
- `pos ∈ {idiom, preposition, conjunction, other}`는 M2를 쓰지 않는다 → M3로.

### M3. 예문 빈칸 쓰기 (직접 입력)
- M2와 같은 문장, 빈칸 자리에 입력칸. `exampleKo` 표시.
- 힌트: stage 3–4 → `a _ _ _ _ _ _` (첫 글자 + 밑줄), stage 5 이상 → `(7글자)`만. 구동사는 단어별로 (`g _ _ _  u _`).
- 정답 인정: `clozeAnswer` 또는 `clozeAccepted`의 어느 것과 §4.6 정규화 후 일치.

### M4. 한국어 → 영어 쓰기
- 화면: 큰 글씨 `meaningKo`, 품사 배지, `disambiguationKo`(있으면), 맥락으로 `exampleKo`.
- 사용자는 **기본형(`term`)**을 입력.
- 정답 인정: `term`, `forms.base`, `termVariants`.

### 4.5 폴백 규칙 (데이터가 부족할 때)

| 조건 | 가능한 유형 |
|---|---|
| 보강 안 됨 (`enrichmentVersion == 0`) | M1, M4 만 |
| `pos`가 M2 불가 품사 | M1, M3, M4 |
| 오답 보기 3개 못 구함 | M2 → M3 |
| 사용자 단어가 4개 미만 | M1 불가 → M4 (또는 M3) |

폴백은 **한 단계 쉬운 쪽이 아니라 가능한 가장 가까운 유형**으로. 폴백해도 SRS 판정은 동일하게 적용.

### 4.6 입력형(M3·M4) 채점 규칙

```
normalize(s):
  trim → 소문자 → 연속 공백 1칸 → ’ ‘ ʼ 를 ' 로 → 끝의 . , ! ? 제거
correct   : normalize(input) ∈ normalize(accepted 집합)
typo      : 정답 길이 ≥ 5 이고 Levenshtein 거리 == 1 → 정답 처리 + "오타 주의: abandon" 표시
nearMiss  : 1) M3에서 같은 단어의 다른 활용형(forms 값 중 하나)을 씀 → "형태가 달라요 (과거형)"
            2) M4에서 nearMiss 목록의 단어, 또는 target의 다른 활용형을 씀 → "뜻은 맞지만 연습 중인 단어가 아니에요 (a로 시작)"
            → 벌점 없이 **한 번만** 다시 입력. 두 번째 결과로 채점.
그 외     : 오답
```
오타 허용·nearMiss 재시도는 설정 플래그로 끌 수 있게 한다 (기본 켜짐).

---

## 5. 결과 화면
- 맞은 수 / 전체, 단어별 ✅/❌, stage 변화 (`3 → 4`), 다음 복습까지 남은 학습일 수
- 틀린 게 있으면 "6시간 뒤 재도전 알림을 보냈어요"
- 원본 `SRSCardResultView`와 같은 역할

---

## 6. 단어 보강(enrichment) 파이프라인

### 6.1 새 단어 추가 시
```
입력 문자열
 ├─ 한글 포함? → prompts/en_korean_to_english.txt 로 term 결정
 │               (사용자가 입력한 한글은 user_meaning_ko 로 넘김)
 └─ prompts/en_word_system.txt + en_words_prompt.txt + en_word_schema.json
      입력: term, user_meaning_ko(선택), user_example(선택)
      → JSON 응답 → §6.3 로컬 검증
      → 실패 시 원본처럼 <correction> 블록을 붙여 1회 재요청 → 또 실패하면 에러 표시
```
- **사용자가 적은 뜻/예문이 있으면 그것이 기준**이다. 모델은 그 뜻에 맞는 의미로 예문을 만들고, 사용자 예문이 유효하면 그대로 쓴다.
- `enrichmentVersion = 1` 저장.

### 6.2 기존 단어 일괄 보강
- `enrichmentVersion == 0 || needsEnrichment` 인 단어를 **10개씩** `prompts/en_backfill_prompt.txt`로 요청 (원본의 AI 임시 저장소 → 외부 AI 붙여넣기 흐름도 같은 프롬프트로 가능).
- 항목별로 §6.3 검증. 실패한 항목만 다음 배치에 다시 넣기 (최대 2회).
- 기존 단어의 `meaningKo`는 **덮어쓰지 않는다**. 모델이 준 `meaning_ko`는 비어 있던 경우에만 저장.

### 6.3 로컬 검증 (원본 `validate`의 영어판)
1. 필수 필드 비어있지 않음: `term, pos, meaning_ko, example, example_ko, cloze_sentence, cloze_answer, cloze_form`
2. `normalize(term) == normalize(요청 term)` (한글 입력 경로에선 변환된 term 기준)
3. `cloze_sentence`에 `<>`가 정확히 1개, `cloze_sentence.replace("<>", cloze_answer) == example` (글자 단위 완전 일치)
4. `cloze_form != "other"` 이면 `lower(cloze_answer) == lower(forms[cloze_form])`
5. `forms.base`가 비어있지 않고 `normalize(forms.base) == normalize(term)`
6. 품사별 forms 키 제약: 명사 → base, plural만 / 동사·구동사 → base, past, past_participle, present_participle, third_person만 / 형용사 → base, comparative, superlative만 / 그 외 → base만. 나머지는 `""`
7. `<>` 바로 앞 단어가 `a`/`an`이 아님, `<>`가 문장 맨 앞이 아님
8. `example` 안에 `term`의 어떤 활용형도 `cloze_answer` 외에는 등장하지 않음
9. `meaning_ko`, `example_ko`에 한글 포함 / `meaning_ko` ≤ 20자, `disambiguation_ko` ≤ 40자, `example` 6~22단어 · ≤ 200자
10. `near_miss_synonyms`에 `term` 자신이나 그 활용형이 없음, 최대 4개
11. `cefr ∈ A1…C2`

실패 메시지는 원본처럼 `<correction>`에 그대로 넣어 재요청한다.

---

## 7. 구현 단위 (권장 순서)

1. **모델 & 마이그레이션**: 필드 추가, 기존 단어에 SRSCard 생성, 경량 마이그레이션
2. **SRSManager 이식**: `reference/SRSManager.swift` 거의 그대로 (엔티티 이름만 교체)
3. **EnrichmentService**: 프롬프트 3종 + 검증기 + 일괄 보강 큐
4. **SessionPlanner** (순수 로직, UI 없음): 오늘 대상 → 유형 배정 → M1 묶기 → 보기 생성 → 순서 → 레슨 분할
5. **AnswerGrader** (순수 로직): §4.6
6. **SessionViewModel**: 진행·저장·이어하기·결과 반영 (원본 `SRSCardsViewModel`의 `processFirstSessionResults` / `completeRetryLearningSession` 로직 재사용)
7. **UI**: 새 단어 카드, M1~M4 뷰, 레슨 사이 화면, 결과 화면, 홈 버튼 상태
8. **알림**: 6시간 재도전 알림

4·5는 단위 테스트 필수 (`samples/sample_words.json` 사용).

## 8. 수락 기준 (테스트 체크리스트)

- [ ] 단어장 보기 화면 코드 변경 없음
- [ ] 1차 세션 전부 정답 → `currentLearningDay` +1, 재도전 없음
- [ ] 1개라도 틀림 → 재도전 버튼이 6시간 동안 비활성, 알림 예약
- [ ] 재도전 후 → 틀린 단어 `nextLearningDay == day + 1`, `currentLearningDay` +1
- [ ] stage 10에서 맞혀도 10 유지, stage 0에서 틀려도 0 유지
- [ ] 오늘 대상 150개 → 100개만 출제, 나머지는 다음 세션 맨 앞
- [ ] 보강 안 된 단어만 있어도 세션이 M1/M4로 정상 진행
- [ ] M2 보기 4개가 모두 같은 활용형 (예: 모두 과거형)이고, 사용자 단어에서만 나옴
- [ ] M1 한 화면에 뜻이 겹치는 쌍 없음
- [ ] "오답 다시 풀기"가 SRS 결과를 바꾸지 않음
- [ ] 세션 도중 앱 종료 → 재실행 시 같은 문제부터 이어짐
- [ ] 샘플 JSON 8개 모두 §6.3 검증 통과, 일부러 망가뜨린 케이스는 실패
