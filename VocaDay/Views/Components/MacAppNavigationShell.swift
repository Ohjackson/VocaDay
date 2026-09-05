import SwiftUI

#if os(macOS)
enum AppInteractionPolicy: Sendable {
    case enabled
    case readOnly

    var permitsActions: Bool { self == .enabled }
}

/// 프로덕션과 온보딩이 같은 Mac 내비게이션 구조를 사용하도록 하는 공용 셸입니다.
struct MacAppNavigationShell<Detail: View>: View {
    @Binding private var selectedSection: AppSection
    private let interactionPolicy: AppInteractionPolicy
    private let hidesSidebarFromAccessibility: Bool
    private let detail: (AppSection) -> Detail

    init(
        selectedSection: Binding<AppSection>,
        interactionPolicy: AppInteractionPolicy = .enabled,
        hidesSidebarFromAccessibility: Bool = false,
        @ViewBuilder detail: @escaping (AppSection) -> Detail
    ) {
        _selectedSection = selectedSection
        self.interactionPolicy = interactionPolicy
        self.hidesSidebarFromAccessibility = hidesSidebarFromAccessibility
        self.detail = detail
    }

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(AppSection.allCases) { section in
                    Button {
                        guard interactionPolicy.permitsActions else { return }
                        selectedSection = section
                    } label: {
                        AppSidebarRow(
                            section: section,
                            isSelected: selectedSection == section
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                    .listRowBackground(Color.clear)
                    .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
                }
            }
            .listStyle(.sidebar)
            // 시스템 제목 막대의 안전 영역을 따르므로 창 제어 버튼과 첫 행이 겹치지 않습니다.
            .safeAreaPadding(.top)
            .navigationTitle("VocaDay")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .accessibilityHidden(hidesSidebarFromAccessibility)
        } detail: {
            detail(selectedSection)
        }
    }
}

private struct AppSidebarRow: View {
    let section: AppSection
    let isSelected: Bool

    var body: some View {
        Label(section.title, systemImage: section.systemImage)
            .font(.body.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            // 선택 배경과 레이블을 같은 밝기 계층에서 처리합니다.
            .componentSpotlight(.navigation)
    }
}
#endif
