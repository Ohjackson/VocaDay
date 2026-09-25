# VocaDay 개발 규칙

## 내비게이션 (반드시 지킬 것)
- 화면 push 는 `AppRoute` (VocaDay/Navigation/AppNavigation.swift) 로만 한다.
  - 링크: `NavigationLink(value: AppRoute.…)` / 코드: `@Environment(\.appNavigate)`
  - 새 화면 = `AppRoute` 에 case 추가 + `AppRouteDestination` 에 매핑. 모델은 ID 로 넘긴다.
- 금지: `NavigationLink { 목적지 }`, `NavigationLink(destination:)`, `navigationDestination(item:/isPresented:)`,
  `NavigationStack { … }.id(…)`. 경로 밖에 쌓인 화면은 macOS 사이드바를 바꿔도 남아서 선택과 본문이 어긋난다.
- 섹션 선택은 `AppNavigationState.select` 를 거친다 (macOS 는 모든 스택 초기화, iOS 는 탭별 유지).
- `NavigationArchitectureTests` 가 위 규칙을 소스 스캔으로 검사한다.
- macOS 에서 고정 최소 높이 `.sheet` 로 긴 화면을 띄우지 않는다 (창보다 크면 창 아래로 넘친다). 본문 열에 push 한다.

## 학습(SRS) 규칙
- 복습 카드·시험 결과는 모두 `SRSStudyService`(VocaDay/Features/Exam/SRS)로만 기록한다. 단어 일정 필드를 화면에서 직접 바꾸지 않는다.
  - 오늘 대상: `StudyDayLedger`에 첫 결과만 기록 → 대상이 모두 채워지면 `SRSEngine` 규칙으로 한 번에 반영.
  - 대상이 아닌 단어(미리 복습): '다시'만 단계 강등 + 오늘 대상 편입, '알아요'는 일정 유지.
- `SRSEngine`의 간격표·재도전 규칙은 바꾸지 않는다. 학습일은 달력 하루에 하나만 진행한다 (`StudyQueue` 게이트).
- "오늘 복습할 단어" 수는 항상 `StudyQueue.snapshot`에서 가져온다 (예전 `nextReviewAt`/`ReviewScheduler`는 삭제됨).
- 시험 유형 배정은 `SessionPlanner`: 가능한 유형 중 stage 가중 무작위. 떠올리기 유형(글자 조각·빈칸 쓰기·한→영)은 stage ≥ 2, 듣고 쓰기는 stage ≥ 3부터.
- 단어 데이터 조건은 `WordDataCheck`(뜻 + 단어가 들어간 예문 + 예문 번역). 새 입력 경로를 만들면 이 검사를 붙인다.
