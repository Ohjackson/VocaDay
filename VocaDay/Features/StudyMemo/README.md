# 학습 메모 기능 모듈

`StudyMemo` 폴더는 노션형 학습 메모 기능의 모델, 화면, Markdown 변환, 예시 데이터 처리를 한곳에 모은 기능 단위 폴더입니다. 외부 라이브러리 없이 `SwiftUI`, `SwiftData`, `UniformTypeIdentifiers`만 사용합니다.

## 제공 기능

- 페이지 생성, 복제, 고정, 삭제
- 사용자 정의 분류 생성, 색상 지정, 선택 및 삭제
- 본문, 제목 1~3, 글머리 목록, 번호 목록, 할 일, 인용, 메모 상자, 코드, 구분선 블록
- `# `, `## `, `### `, `- `, `1. `, `> ` 등의 Markdown 단축 입력
- `/` 입력으로 블록 종류 선택
- 굵게, 기울임, 밑줄, 취소선의 적용 및 해제
- 기본색과 사용자 지정색 하이라이트
- Markdown 파일 가져오기와 내보내기
- iPhone과 Mac에 맞춘 반응형 편집 화면
- 받아쓰기, 문법, 표현 예시 페이지 생성
- 중복된 예시 페이지와 분류 자동 정리

## 폴더 구성

```text
StudyMemo/
├── README.md
├── StudyMemoFeature.swift
├── Models/
│   └── StudyMemo.swift
├── Services/
│   └── StudyMemoDemoSeeder.swift
└── Views/
    └── StudyMemosView.swift
```

- `StudyMemoFeature.swift`: 다른 화면에서 사용하는 기능 진입점입니다.
- `Models/StudyMemo.swift`: SwiftData 모델과 편집 블록 타입을 정의합니다.
- `Services/StudyMemoDemoSeeder.swift`: 예시 데이터 생성과 중복 데이터 정리를 담당합니다.
- `Views/StudyMemosView.swift`: 목록, 편집기, 서식 막대, 분류 선택, Markdown 코덱과 파일 입출력 UI를 포함합니다.

## 다른 앱에서 사용하는 방법

### 1. 폴더 복사

이 `StudyMemo` 폴더 전체를 대상 Xcode 프로젝트의 앱 타깃에 복사하고 모든 Swift 파일의 Target Membership을 활성화합니다.

### 2. SwiftData 모델 등록

대상 앱의 `ModelContainer`에 아래 두 모델을 추가합니다.

```swift
let container = try ModelContainer(
    for: StudyMemo.self,
    StudyPageCategory.self
)
```

기존 앱에 다른 SwiftData 모델이 있다면 같은 `ModelContainer` 목록에 함께 등록합니다. CloudKit을 사용하는 앱에서는 배포 전 개발 컨테이너의 스키마 변경도 확인해야 합니다.

### 3. 화면 연결

호스트 화면의 `NavigationStack` 또는 `NavigationSplitView` 안에 기능 진입점을 배치합니다.

```swift
NavigationStack {
    StudyMemoFeatureView()
}
```

예시 데이터를 만들지 않으려면 다음처럼 사용합니다.

```swift
StudyMemoFeatureView(includesDemoData: false)
```

### 4. 미리보기 또는 독립 실행

```swift
#Preview {
    NavigationStack {
        StudyMemoFeatureView()
    }
    .modelContainer(
        for: [StudyMemo.self, StudyPageCategory.self],
        inMemory: true
    )
}
```

## 호스트 앱과 연결되는 선택 기능

다음 부분은 학습 메모 편집기의 필수 의존성이 아니라 VocaDay 전체 앱과의 연결 지점입니다.

- `VocaDayApp.swift`: 앱 공용 SwiftData 스키마에 모델 등록
- `RootView.swift`: 탭 또는 사이드바에서 `StudyMemoFeatureView` 표시
- `SettingsView.swift`: 학습 메모 초기화와 예시 데이터 재생성
- `AppDataBackupService.swift`: 전체 앱 JSON 백업에 학습 메모와 분류 포함

다른 앱에서 백업이 필요하면 해당 앱의 백업 형식에 `StudyMemo`와 `StudyPageCategory`를 변환하는 어댑터를 별도로 연결하면 됩니다. 편집기 자체는 VocaDay의 단어, 데이, 복습 모델에 의존하지 않습니다.

## Markdown 호환 범위

- 가져오기/내보내기: 제목, 글머리 목록, 번호 목록, 할 일, 인용, 코드 블록, 구분선, 굵게, 기울임, 취소선, 하이라이트
- 밑줄과 사용자 지정 하이라이트의 정확한 색상은 표준 Markdown에 대응 문법이 없어 앱 내부 리치 텍스트에서만 완전히 보존됩니다.
- 하이라이트는 내보낼 때 `<mark>내용</mark>` 형식을 사용합니다.

## 테스트

회귀 테스트는 다음 위치에 있습니다.

```text
VocaDayTests/Features/StudyMemo/StudyMemoEditorTests.swift
```

테스트 범위는 Markdown 단축 입력, 편집기 센티널 처리, 부분 하이라이트, Markdown 왕복 변환, 예시와 분류 중복 정리입니다.

## 재사용 시 주의사항

- `TextEditor`의 `AttributedString` 및 선택 영역 API를 사용하므로 대상 앱의 Xcode와 최소 OS 버전이 이 API를 지원해야 합니다.
- `StudyMemoDemoSeeder`는 예시 생성 여부를 `UserDefaults`와 `NSUbiquitousKeyValueStore`에 기록합니다. iCloud 키-값 저장을 사용하지 않는 앱이라면 `NSUbiquitousKeyValueStore` 부분을 제거해도 편집 기능에는 영향이 없습니다.
- 모델 속성이나 블록 JSON 구조를 변경할 때는 기존 사용자 데이터 마이그레이션과 CloudKit 스키마 호환성을 함께 확인해야 합니다.
