# VocaDay 1.2 (build 3) 출시 메모

코드 외에 직접 해야 하는 일과 App Store Connect 에 붙여 넣을 문구를 모아 둔다.
심사 메모는 루트의 `APP_REVIEW_RESPONSE.md` 에 1.2 기준으로 반영했다.

## 1. CloudKit 스키마 Production 배포 (제출 전 필수)

1.2 에서 새로 생긴 레코드·필드가 Production 에 없으면 출시 빌드에서 동기화가 실패한다.

- 새 레코드 타입: `CD_StudyProgress`, `CD_ReviewLog`
- `CD_VocaWord` 새 필드: `CD_srsStage`, `CD_srsNextLearningDay`, `CD_srsIdkCount`, `CD_quiz…` 15개

순서

1. Debug 빌드를 실기기(iCloud 로그인)에서 실행한다. Debug 는 Development 환경을 쓴다.
2. 스키마가 모두 만들어지도록 다음을 한 번씩 한다: 단어 추가 → 시험을 끝까지 풀기(ReviewLog, StudyProgress 생성) → 복습 카드 완료.
3. [CloudKit Console](https://icloud.developer.apple.com/) → `iCloud.com.VocaDay.VocaDay` → Development → Schema → Record Types 에 위 타입·필드가 있는지 확인.
4. **Deploy Schema Changes…** → 변경 목록 확인 → Deploy (Development → Production).
5. Production → Record Types 에서 같은 항목이 보이면 완료. (Production 스키마는 필드 삭제가 안 되므로 목록을 꼭 확인)

## 2. 실기기 테스트 체크리스트

업데이트 경로 (가장 중요)

- [ ] App Store 의 현재 버전(1.1)을 설치하고 데이·단어·복습 기록·학습 메모를 만든다.
- [ ] 1.2 빌드(TestFlight)를 덮어 설치한다.
- [ ] 기존 단어·메모가 그대로 있고, 복습 탭 “오늘 복습할 단어”가 나온다 (기존 단어는 stage 0 부터 시작).
- [ ] 시험 탭에서 오늘의 학습을 시작하고 끝낼 수 있다.

SRS 흐름

- [ ] 1차에서 일부러 하나 틀리기 → 결과 반영 → 재도전 알림 권한 창이 뜨고 “재도전까지 HH:MM” 표시.
- [ ] 6시간 뒤 알림이 오고 재도전을 끝내면 학습일 +1, 같은 날에는 다음 학습이 내일 0시로 표시.
- [ ] 시험 중간에 앱을 종료했다가 다시 열면 이어 풀기.
- [ ] 복습 카드로 일부, 시험으로 나머지를 풀어도 한 번에 반영된다.

동기화 (두 기기, 같은 iCloud)

- [ ] 기기 A 에서 오늘 학습을 끝내면 기기 B 에서 학습일·단어 stage 가 맞게 보인다.
- [ ] 두 기기에서 앱을 처음 켜도 진행 상태(StudyProgress)가 하나로 합쳐진다.
- [ ] (주의: 오늘 푸는 중인 기록은 기기 로컬이라 다른 기기에 안 보이는 게 정상)

Mac

- [ ] 시험 세션이 본문 열에 push 되고, 사이드바를 바꾸면 사라진다.
- [ ] Gemini 키를 넣으면 문제 준비가 동작한다 (1.2 에서 네트워크 권한 추가).

백업

- [ ] 전체 백업 → 전체 삭제 → 복원 후 학습일·stage·풀이 기록이 돌아온다.

## 3. App Privacy (App Store Connect → 앱 개인정보 보호)

판단 근거

- 학습 데이터는 사용자 개인 iCloud(CloudKit private DB)에만 있고 개발자는 접근할 수 없음 → 개발자 수집 아님.
- 분석·광고·추적 SDK 없음, 로그인 없음.
- 예외: 사용자가 **본인 Gemini API 키**를 넣으면 단어·뜻·예문이 Google 로 전송된다. 개발자 서버는 거치지 않지만 Google(제3자)이 받으므로 보수적으로 신고하는 것을 권장.

권장 답변 (보수적)

| 질문 | 답 |
| --- | --- |
| 데이터를 수집합니까? | 예 |
| 데이터 유형 | 사용자 콘텐츠 → **기타 사용자 콘텐츠** |
| 용도 | 앱 기능 |
| 사용자와 연결됨? | 아니요 |
| 추적에 사용? | 아니요 |

“데이터를 수집하지 않음”으로 답하려면, Gemini 전송이 사용자가 직접 연결한 본인 계정으로의 전송이라 개발자·파트너 수집이 아니라는 해석에 기대야 한다. 심사에서 문제 될 여지를 줄이려면 위 답변이 안전하다.

개인정보 처리방침 URL: Notion “VocaDay 개인정보 처리방침” (2026-09-25 개정, Gemini 조항 추가).

## 4. 이번 버전의 새로운 기능

한국어

```
• 시험 탭: 짝 맞추기·뜻 고르기·빈칸·글자 조각·쓰기·듣고 쓰기 등 7가지 문제로 단어를 확인해요.
• 간격 반복 일정: 맞힐수록 다음 복습까지 간격이 늘어나고, 틀린 단어는 6시간 뒤 재도전으로 다시 봐요.
• 복습 카드와 시험이 하나의 일정으로 이어져요. 무엇으로 풀어도 오늘 복습이 채워집니다.
• 통계 탭: 단계별 분포, 앞으로의 복습 예정, 단어별 학습 기록을 볼 수 있어요.
• 단어 추가 시 예문·번역이 시험에 쓸 수 있는지 바로 알려 줘요.
• (선택) 본인의 Gemini API 키를 넣으면 시험 보기를 더 정교하게 만들어요.
```

English

```
• New Exam tab: check your words with 7 question types, including matching, meaning choice, fill-in-the-blank, letter tiles, typing, and dictation.
• Spaced repetition: intervals grow as you answer correctly, and missed words come back in a retry session 6 hours later.
• Review cards and exams share one schedule, so either one completes today's review.
• New Stats tab: stage distribution, upcoming reviews, and per-word study history.
• When adding words, VocaDay tells you whether the example and translation are ready for exams.
• Optional: add your own Gemini API key for more precise answer choices.
```

日本語

```
• テストタブを追加:ペア合わせ、意味選択、穴埋め、文字タイル、入力、聞き取りなど7種類の問題で単語を確認できます。
• 間隔反復スケジュール:正解するほど次の復習までの間隔が伸び、間違えた単語は6時間後の再挑戦でもう一度出題されます。
• 復習カードとテストが一つのスケジュールでつながり、どちらで解いても今日の復習が進みます。
• 統計タブ:段階ごとの分布、今後の復習予定、単語ごとの学習履歴を確認できます。
• 単語追加時に、例文と訳がテストに使えるかをすぐに表示します。
• (任意)ご自身の Gemini API キーを入力すると、選択肢をより精密に作成します。
```

## 5. 스크린샷

`AppStoreAssets/iPhone/1.2/` — iPhone 17 Pro Max 시뮬레이터(6.9인치, 1320×2868)에서 촬영.
