#if DEBUG
import SwiftData
import SwiftUI

/// 감독용 온보딩 점검 화면 (디버그 빌드 전용). 온보딩 개선 항목을 처음부터 끝까지 직접 실행해 볼 수 있다.
/// 안내를 띄우는 버튼은 이 기기의 완료 기록을 끄고 `SpotlightTourRequest` 를 남긴다. 그러면 `RootView` 가
/// 실제 첫 실행과 같은 경로로 안내를 띄우고, 끝나면 실제 도착지로 보낸다.
struct OnboardingReviewView: View {
    @Query private var days: [VocabularyDay]
    @AppStorage(SpotlightOnboardingCompletion.versionedKey) private var hasCompletedOnboarding = false

    private var hasAddedToday: Bool {
        BundledWordPack.hasAddedToday(existingDays: days)
    }

    private var isCloudCompleted: Bool {
        NSUbiquitousKeyValueStore.default.bool(forKey: SpotlightOnboardingCompletion.versionedKey)
    }

    var body: some View {
        Form {
            Section {
                Button {
                    present(.core)
                } label: {
                    Label("새 사용자 첫 실행 그대로 보기", systemImage: "play.circle.fill")
                        .font(.headline)
                }
                LabeledContent("지금 끝내면", value: OnboardingLanding.after(.finished(.core), hasAddedToday: hasAddedToday).note)
            } header: {
                Text("처음부터 끝까지")
            } footer: {
                Text("핵심 3단계 안내 → 마지막 버튼 ‘오늘의 새 단어 고르기’ → 오늘의 새 단어 검수 화면까지 실제 사용자와 같은 경로로 이어집니다. 오늘 단어장을 이미 만들었다면 학습 탭으로 갑니다. 도착하면 화면 위에 주황 테두리 안내가 6초 동안 떠서 어디로, 왜 왔는지 알려 줍니다.")
            }

            Section {
                ForEach(Array(SpotlightTour.core.steps.enumerated()), id: \.element) { index, step in
                    Button {
                        present(.core, at: step)
                    } label: {
                        LabeledContent {
                            Text(step.section.title)
                        } label: {
                            Text("\(index + 1). \(step.title)")
                        }
                    }
                }
            } header: {
                Text("① 핵심 절차: 기능 설명 → 쓰는 이유")
            } footer: {
                Text("이전: 데이 보기 · 단어 입력 · 저장 · 카드 복습 (4단계, 절반이 직접 입력 설명)\n변경: 오늘의 새 단어 · 오늘 학습(복습 날짜는 앱이 정함) · 내 단어 추가 (3단계). 누르면 그 단계부터 봅니다.")
            }

            Section {
                Button {
                    present(.core, at: SpotlightTour.core.steps.last)
                } label: {
                    Label("마지막 단계에서 시작", systemImage: "flag.checkered")
                }
                LabeledContent("완료 버튼", value: OnboardingLanding.after(.finished(.core), hasAddedToday: hasAddedToday).note)
                LabeledContent("건너뛰기", value: OnboardingLanding.after(.skipped, hasAddedToday: hasAddedToday).note)
            } header: {
                Text("② 끝난 뒤 도착지")
            } footer: {
                Text("이전: 완료·건너뛰기 모두 빈 추가 탭으로 이동했어요. 마지막 단계에서 두 버튼을 번갈아 눌러 비교하세요.")
            }

            Section {
                Button {
                    present(.core, at: .todayStudy)
                } label: {
                    Label("학습 단계 보기", systemImage: "checkmark.seal")
                }
            } header: {
                Text("③ 학습 단계 목업 = 실제 학습 탭")
            } footer: {
                Text("이전: ‘카드로 떠올려 봐요’ 설명 아래 데이 카드만 보여 실제 학습 탭과 달랐어요. 지금은 목업과 실제 학습 탭이 같은 ‘오늘 학습’ 카드(StudyStatusCard)를 쓰고, 첫 단계의 ‘오늘의 새 단어’ 배너도 실제 데이 화면과 같은 컴포넌트예요. iOS 목업 탭 바도 실제와 같은 5칸입니다.")
            }

            Section {
                LabeledContent("이 기기 완료 기록", value: hasCompletedOnboarding ? "있음" : "없음")
                LabeledContent("iCloud 완료 기록", value: isCloudCompleted ? "있음" : "없음")
                LabeledContent("저장된 데이", value: "\(days.count)개")
                LabeledContent("이 기기에 새로 설치하면", value: installDecisionText)

                Button {
                    hasCompletedOnboarding = false
                } label: {
                    Label("이 기기 기록만 지우기 (다른 기기에서 끝낸 사용자)", systemImage: "iphone.gen3.slash")
                }

                Button {
                    NSUbiquitousKeyValueStore.default.set(false, forKey: SpotlightOnboardingCompletion.versionedKey)
                    NSUbiquitousKeyValueStore.default.synchronize()
                    hasCompletedOnboarding = false
                } label: {
                    Label("iCloud 기록도 지우기 (데이터만 동기화된 기존 사용자)", systemImage: "icloud.slash")
                }
            } header: {
                Text("④ 기존 사용자는 건너뛰기")
            } footer: {
                Text("이전: 완료 기록이 이 기기에만 있어 새 기기·재설치 때 기존 사용자도 안내를 다시 봤어요. 지금은 iCloud에도 기록하고, 데이가 이미 있으면 건너뜁니다. 버튼을 누르면 새로 설치한 것처럼 판정이 실행되고, 안내 없이 데이 탭에 도착해 건너뛴 이유가 화면 위에 뜹니다. 판정 뒤 두 기록은 다시 ‘있음’으로 채워집니다.")
            }

            Section {
                Button {
                    present(.full)
                } label: {
                    Label("전체 \(SpotlightTour.full.steps.count)단계 보기", systemImage: "scope")
                }
            } header: {
                Text("참고: 전체 절차")
            } footer: {
                Text("앱의 모든 안내 단계입니다. 첫 실행에는 나오지 않습니다.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("온보딩 점검")
    }

    private var installDecisionText: String {
        switch OnboardingGate.decide(cloudCompleted: isCloudCompleted, hasExistingData: !days.isEmpty, isSupervisedReplay: false) {
        case .present: "안내를 보여 줌"
        case .skip(let reason): reason
        }
    }

    private func present(_ tour: SpotlightTour, at step: SpotlightStep? = nil) {
        SpotlightTourRequest.request(tour, startingAt: step)
        hasCompletedOnboarding = false
    }
}
#endif
