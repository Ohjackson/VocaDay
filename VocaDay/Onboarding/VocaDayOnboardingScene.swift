import SwiftUI

struct VocaDayOnboardingScene: View {
    @ObservedObject var controller: SpotlightFlowController
    var onCompletion: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    var body: some View {
        #if os(macOS)
        macScene
        #else
        ZStack {
            onboardingShell
                .environment(\.activeSpotlightTarget, controller.currentStep.target)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            descriptionLayer
        }
        .background(AppTheme.background)
        .sceneAnimation(step: controller.currentStep, reduceMotion: reduceMotion)
        .onAppear(perform: prepareVisualVerification)
        #endif
    }

    #if os(macOS)
    private var macScene: some View {
        MacAppNavigationShell(
            selectedSection: sectionBinding,
            interactionPolicy: .readOnly,
            hidesSidebarFromAccessibility: true
        ) { section in
            NavigationStack {
                mockDestination(for: section)
            }
            .environment(\.activeSpotlightTarget, controller.currentStep.target)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .overlay {
                macDescriptionLayer
                    .allowsHitTesting(true)
                    .accessibilityHidden(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.activeSpotlightTarget, controller.currentStep.target)
        .background(AppTheme.background)
        .sceneAnimation(step: controller.currentStep, reduceMotion: reduceMotion)
        .onAppear(perform: prepareVisualVerification)
    }

    private var macDescriptionLayer: some View {
        VStack(spacing: 0) {
            if controller.currentStep.placement != .top {
                Spacer(minLength: 0)
            }

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                onboardingDescriptionCard
                    // 창이 아직 크기를 갖기 전에도 바깥 컨테이너에 음수 크기를
                    // 제안하지 않도록 카드 자체가 안전 여백을 포함합니다.
                    .padding(24)
            }

            if controller.currentStep.placement != .bottom {
                Spacer(minLength: 0)
            }
        }
    }
    #endif

    @ViewBuilder
    private var onboardingShell: some View {
        TabView(selection: sectionBinding) {
            NavigationStack { MockDaysOnboardingView() }
                .tabItem {
                    Label(AppSection.days.title, systemImage: AppSection.days.systemImage)
                        .componentSpotlight(.navigation)
                }
                .tag(AppSection.days)

            NavigationStack { MockAddWordsOnboardingView() }
                .tabItem {
                    Label(AppSection.add.title, systemImage: AppSection.add.systemImage)
                        .componentSpotlight(.navigation)
                }
                .tag(AppSection.add)

            NavigationStack { MockReviewOnboardingView() }
                .tabItem {
                    Label(AppSection.review.title, systemImage: AppSection.review.systemImage)
                        .componentSpotlight(.navigation)
                }
                .tag(AppSection.review)

            NavigationStack { MockStudyMemosOnboardingView() }
                .tabItem {
                    Label(AppSection.studyMemos.title, systemImage: AppSection.studyMemos.systemImage)
                        .componentSpotlight(.navigation)
                }
                .tag(AppSection.studyMemos)
        }
    }

    private var sectionBinding: Binding<AppSection> {
        Binding(
            get: { controller.currentStep.section },
            set: { _ in }
        )
    }

    @ViewBuilder
    private func mockDestination(for section: AppSection) -> some View {
        switch section {
        case .days: MockDaysOnboardingView()
        case .add: MockAddWordsOnboardingView()
        case .review: MockReviewOnboardingView()
        case .studyMemos: MockStudyMemosOnboardingView()
        }
    }

    private var descriptionLayer: some View {
        VStack(spacing: 0) {
            if controller.currentStep.placement != .top {
                Spacer(minLength: 0)
            }

            onboardingDescriptionCard

            if controller.currentStep.placement != .bottom {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }

    private var onboardingDescriptionCard: some View {
        SpotlightDescriptionCard(
            step: controller.currentStep,
            canGoBack: controller.canGoBack,
            onBack: controller.moveBack,
            onNext: moveNext,
            onSkip: skip
        )
    }

    static func snapshotDescription(for step: SpotlightStep, sizeName: String) -> String {
        #if os(macOS)
        let cardScope = "detail-column"
        #else
        let cardScope = "full-screen"
        #endif
        return "scene=VocaDayOnboarding|size=\(sizeName)|step=\(step.snapshotValue)|cardScope=\(cardScope)|data=mock-only|interaction=read-only"
    }

    private func prepareVisualVerification() {
        #if DEBUG
        if let rawValue = ProcessInfo.processInfo.environment["VOCADAY_ONBOARDING_STEP"].flatMap(Int.init),
           let step = SpotlightStep(rawValue: rawValue) {
            controller.setStepForVisualVerification(step)
        }
        #endif
    }

    private func moveNext() {
        if controller.currentStep == SpotlightStep.allCases.last {
            controller.finish()
            onCompletion()
        } else {
            controller.moveNext()
        }
    }

    private func skip() {
        controller.skip()
        onCompletion()
    }
}

private struct MockDaysOnboardingView: View {
    var body: some View {
        AppCollectionPage(
            maxContentWidth: 840,
            horizontalPadding: 20,
            verticalPadding: 24
        ) {
            LazyVStack(spacing: 12) {
                ForEach(Array(VocaDayOnboardingMockData.dayCards.enumerated()), id: \.offset) { index, day in
                    DayCardView(presentation: day)
                        .componentSpotlight(index == 0 ? .dayCollection : .supportingContent)
                }
            }
        }
        .background(AppTheme.background)
        .navigationTitle("VocaDay")
        .toolbar {
            ToolbarItemGroup(placement: toolbarPlacement) {
                Button(action: {}) { Image(systemName: "gearshape") }
                    .componentSpotlight(.settingsButton)
                Button(action: {}) { Image(systemName: "square.and.pencil") }
                    .componentSpotlight(.editDaysButton)
                Button(action: {}) {
                    AppToolbarActionLabel(title: "새 데이", systemImage: "plus")
                }
                .componentSpotlight(.createDayButton)
                .accessibilityLabel("새 데이 만들기")
            }
        }
    }
}

private struct MockAddWordsOnboardingView: View {
    private static let destinationID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!

    @State private var selectedDestinationID: UUID? = destinationID
    @State private var entryMode: AddEntryMode = .manual
    @State private var inputWord = "reservation"
    @State private var words = VocaDayOnboardingMockData.temporaryWords
    @State private var selectedWordID: UUID?
    @FocusState private var isInputFocused: Bool
    @Environment(\.activeSpotlightTarget) private var activeTarget
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        AddWordsSetupCard(
                            destinations: [DayDestinationOption(id: Self.destinationID, title: "Day 2 · 회의 표현")],
                            selectedDestinationID: $selectedDestinationID,
                            showsEntryMode: false,
                            entryMode: $entryMode,
                            onCreateDestination: {}
                        )
                        .componentSpotlight(.storageSelection)
                        .id(SpotlightTarget.storageSelection)

                        AddWordsGuideCard(
                            title: "영단어를 입력하고 Enter를 누르세요",
                            message: "한국어 뜻이 자동으로 채워집니다. 필요한 내용만 고친 뒤 아래에서 저장하세요.",
                            systemImage: "return",
                            showsHelpLink: false,
                            onDismiss: {}
                        ) { EmptyView() }
                        .componentSpotlight(.addGuide)
                        .id(SpotlightTarget.addGuide)

                        WordInputCard(
                            inputWord: $inputWord,
                            isInputFocused: $isInputFocused,
                            onSubmit: {}
                        )
                        .componentSpotlight(.wordInput)
                        .id(SpotlightTarget.wordInput)

                        TemporaryWordTable(
                            words: $words,
                            selectedWordID: $selectedWordID,
                            emptyTitle: "아직 추가할 단어가 없습니다. 위 입력란에서 시작하세요."
                        )
                        .componentSpotlight(.pendingWords)
                        .id(SpotlightTarget.pendingWords)
                    }
                    .padding(16)
                    .frame(maxWidth: 980)
                    .frame(maxWidth: .infinity)
                }
                .onAppear { revealTargetIfNeeded(using: proxy) }
                .onChange(of: activeTarget) { _, _ in
                    revealTargetIfNeeded(using: proxy)
                }
            }

            VStack(spacing: 0) {
                Divider()
                AppActionButton(
                    title: "Day 2 · 회의 표현에 2개 저장",
                    systemImage: "tray.and.arrow.down",
                    isProminent: true,
                    action: {}
                )
                .componentSpotlight(.saveWordsButton)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .background(.regularMaterial)
        }
        .background(AppTheme.background)
        .navigationTitle("단어 추가")
        .toolbar {
            ToolbarItem(placement: toolbarPlacement) {
                Button(action: {}) { Image(systemName: "questionmark.circle") }
                    .componentSpotlight(.addHelpButton)
            }
        }
    }

    private func revealTargetIfNeeded(using proxy: ScrollViewProxy) {
        guard let activeTarget,
              activeTarget == .wordInput || activeTarget == .pendingWords else { return }

        if reduceMotion {
            proxy.scrollTo(activeTarget, anchor: .center)
        } else {
            withAnimation(.easeInOut(duration: 0.22)) {
                proxy.scrollTo(activeTarget, anchor: .center)
            }
        }
    }
}

private struct MockReviewOnboardingView: View {
    var body: some View {
        AppCollectionPage(
            maxContentWidth: 840,
            horizontalPadding: 20,
            verticalPadding: 24
        ) {
            LazyVStack(spacing: 12) {
                ForEach(Array(VocaDayOnboardingMockData.dayCards.enumerated()), id: \.offset) { index, day in
                    DayCardView(presentation: day)
                        .componentSpotlight(index == 0 ? .reviewDay : .dayCollection)
                }
            }
        }
        .background(AppTheme.background)
        .navigationTitle("복습")
        .toolbar {
            ToolbarItem(placement: toolbarPlacement) {
                Button(action: {}) { Image(systemName: "square.and.pencil") }
                    .componentSpotlight(.editReviewButton)
            }
        }
    }
}

private struct MockStudyMemosOnboardingView: View {
    var body: some View {
        AppCollectionPage(
            maxContentWidth: 860,
            horizontalPadding: 14,
            verticalPadding: 12
        ) {
            LazyVStack(spacing: 2) {
                ForEach(Array(VocaDayOnboardingMockData.studyMemoRows.enumerated()), id: \.offset) { _, memo in
                    StudyPageListRow(presentation: memo)
                        .componentSpotlight(.studyMemoCollection)
                }
            }
        }
        .background(StudyPageStyle.background)
        .navigationTitle("학습 메모")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: toolbarPlacement) {
                Button(action: {}) {
                    AppToolbarActionLabel(title: "새 페이지", systemImage: "plus")
                }
                .componentSpotlight(.createStudyMemoButton)
                .accessibilityLabel("새 페이지")
            }
        }
    }
}

private var toolbarPlacement: ToolbarItemPlacement {
    #if os(iOS)
    .topBarTrailing
    #else
    .primaryAction
    #endif
}

private extension View {
    func sceneAnimation(step: SpotlightStep, reduceMotion: Bool) -> some View {
        animation(
            reduceMotion ? nil : .easeInOut(duration: 0.22),
            value: step
        )
    }
}
