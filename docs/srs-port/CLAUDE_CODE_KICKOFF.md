# 영어 앱 레포에서 Claude Code에 붙여넣을 시작 프롬프트

> 사용법: 이 폴더(`english-srs-port/`)를 영어 앱 레포의 `docs/srs-port/`로 복사한 뒤, 아래 ``` 블록 안의 내용을 그대로 붙여넣는다.
> `[ ]` 안은 네가 미리 채우거나 지워도 되고, 비워 두면 Claude가 레포를 보고 채운 뒤 확인을 요청한다.

```
docs/srs-port/ 폴더에 일본어 단어장 앱(단고초)의 SRS 학습 시스템을 이 영어 단어장 앱에 이식하기 위한 명세, 프롬프트, 참조 코드, 샘플 데이터가 있어.
SPEC.md가 기준 문서이고, reference/ 는 원본 Swift 코드, prompts/ 는 LLM 프롬프트, samples/ 는 골든 데이터와 검증기 참조 구현이야.

목표: "시험보기" 기능을 SPEC.md대로 구현한다.
- 단어장 보기 화면과 그 관련 코드는 절대 수정하지 마. (데이터 모델에 필드를 "추가"하는 건 괜찮음)
- 출제 대상은 사용자가 넣은 단어 전체이고, SRS 규칙(SPEC §2)은 원본 reference/SRSManager.swift, reference/SRSCardsViewModel.swift 와 수치·동작이 완전히 같아야 해.
- 문제 유형 4가지(M1 짝 맞추기, M2 빈칸 고르기, M3 빈칸 쓰기, M4 한→영 쓰기)는 SPEC §3·§4를 따른다. 오답 보기와 짝 맞추기 채움 단어는 사용자 단어 전체에서 뽑는다.
- LLM 호출은 prompts/ 파일을 번들 리소스로 넣고 ${...} 치환으로 사용한다. 응답은 en_word_schema.json 으로 구조화 출력을 강제하고, SPEC §6.3 검증 → 실패 시 <correction> 블록을 붙여 1회 재요청한다 (reference/SessionStatus_and_LLMValidation_excerpt.swift 참고).

진행 방식:
1. 먼저 코드를 수정하지 말고 레포를 조사해서 아래를 보고해 줘.
   a. 현재 단어 엔티티/모델과 저장소(Core Data / SwiftData / 기타), 필드 목록 → SPEC §1.1 필드와의 매핑표
   b. 기존 LLM 클라이언트/API 키 관리 방식 (없으면 원본처럼 Gemini + Keychain 제안)
   c. 기존 단어에 한국어 뜻·예문이 얼마나 들어있는지 (보강 전략에 영향)
   d. 알림, 홈 화면 진입점, 기존 퀴즈 화면이 있다면 어떻게 대체/공존할지
   e. SPEC §8 수락 기준 중 이 레포 구조 때문에 바꿔야 할 것
   그리고 결정이 필요한 것만 짧게 질문해 줘. 기본값: 하루 상한 100, 재도전 6시간, 레슨 15문제, 오타 허용 켜짐, 예문 한국어 번역 표시 켜짐.
   [LLM 제공자: Gemini]  [최소 iOS 버전: ]  [iCloud 동기화 사용 여부: ]
2. 내가 승인하면 SPEC §7 순서대로 단계별로 구현하고, 단계마다 빌드가 되는 상태로 멈춰서 요약해 줘.
3. SessionPlanner, AnswerGrader, EntryValidator 는 UI와 분리된 순수 로직으로 만들고 단위 테스트를 작성해.
   - EntryValidator 테스트는 samples/sample_words.json 을 테스트 번들에 넣어, valid 8개는 통과하고 invalid 7개는 각각 괄호 안의 오류 코드로 거절되어야 해 (samples/validate_reference.py 와 같은 결과).
   - SRS 테스트는 SPEC §8의 SRS 항목을 전부 커버해.
4. 실제 LLM 호출 전에 prompts/en_words_prompt.txt 를 samples 의 input 8개로 돌려 보고, 검증 통과율과 실패 사유를 보여 줘. 통과율이 낮으면 프롬프트를 고치기 전에 나한테 먼저 알려 줘.
```
