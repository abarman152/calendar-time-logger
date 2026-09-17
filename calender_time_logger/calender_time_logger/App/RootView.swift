import CalendarTimeLoggerKit
import SwiftUI

/// The main window: a sidebar of sections plus app-wide sheets and alerts.
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openWindow) private var openWindow
    @State private var showsOnboarding = false

    var body: some View {
        @Bindable var environment = environment

        NavigationSplitView {
            // Rows are identified and tagged by `AppSection` itself, matching the
            // selection type; see `AppSection.id`.
            List(selection: Binding(
                get: { environment.selectedSection },
                set: { environment.selectedSection = AppSection.resolvedSelection($0, current: environment.selectedSection) }
            )) {
                Section {
                    ForEach(AppSection.primary) { section in
                        SidebarRow(section: section, isSelected: section == environment.selectedSection)
                            .badge(badge(for: section))
                            .tag(section)
                    }
                }
                Section {
                    ForEach(AppSection.secondary) { section in
                        SidebarRow(section: section, isSelected: section == environment.selectedSection)
                            .tag(section)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .safeAreaInset(edge: .bottom) {
                SidebarSessionStatus()
                    .padding(10)
            }
        } detail: {
            detail
                .frame(minWidth: 640, minHeight: 520)
        }
        .sheet(item: Binding(
            get: { environment.sessions.lastCompletion },
            set: { environment.sessions.lastCompletion = $0 }
        )) { completion in
            CompletionView(completionID: completion.id)
        }
        .sheet(isPresented: $environment.isExportPresented) {
            ExportWorkLogsView { environment.isExportPresented = false }
        }
        .sheet(isPresented: $environment.isStartSessionPresented) {
            StartSessionSheet { environment.isStartSessionPresented = false }
        }
        .sheet(isPresented: $environment.isQuickTaskPresented) {
            QuickTaskSheet { environment.isQuickTaskPresented = false }
        }
        .sheet(isPresented: Binding(
            get: { environment.isChangePriorityPresented && environment.sessions.activeSession != nil },
            set: { environment.isChangePriorityPresented = $0 }
        )) {
            if let session = environment.sessions.activeSession {
                ChangeTaskPrioritySheet(session: session) { environment.isChangePriorityPresented = false }
            }
        }
        .sheet(isPresented: $showsOnboarding) {
            OnboardingView {
                environment.settings.hasCompletedOnboarding = true
                showsOnboarding = false
            }
            .interactiveDismissDisabled()
        }
        .alert(item: $environment.presentedError) { error in
            Alert(title: Text(error.title), message: error.message.isEmpty ? nil : Text(error.message))
        }
        .alert(item: $environment.exportNotice) { notice in
            Alert(
                title: Text("Work Logs Exported"),
                message: Text("\(notice.sessionCount == 1 ? "1 session was" : "\(notice.sessionCount) sessions were") saved to “\(notice.url.lastPathComponent)”."),
                primaryButton: .default(Text("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([notice.url]) },
                secondaryButton: .cancel(Text("OK"))
            )
        }
        .onOpenURL { environment.handle(url: $0) }
        .onAppear {
            if !environment.settings.hasCompletedOnboarding { showsOnboarding = true }
            // Recovery is shown on the Dashboard rather than as a launch-time sheet.
            if environment.sessions.pendingRecovery != nil { environment.selectedSection = .dashboard }
            #if DEBUG
            if DemoMode.current?.showsMenuWindow == true { openWindow(id: "demo-menu") }
            DemoMode.current?.presentOnAppear(environment)
            #endif
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch environment.selectedSection {
        case .dashboard: DashboardView()
        case .templates: TemplatesView()
        case .workLogs: WorkLogsView()
        case .calendar: CalendarView()
        case .analytics: AnalyticsView()
        case .settings: SettingsSectionView()
        case .about: AboutSectionView()
        }
    }

    private func badge(for section: AppSection) -> Int {
        guard section == .calendar else { return 0 }
        return ((try? environment.persistence.completedSessions()) ?? []).filter { $0.calendarSyncStatus.needsAttention }.count
    }
}

/// A sidebar item. Selection highlighting is drawn by the List; this adds a
/// subtle hover highlight to unselected rows. `onHover` doesn't consume clicks,
/// so selection still goes through the List.
private struct SidebarRow: View {
    let section: AppSection
    let isSelected: Bool
    @State private var isHovering = false

    var body: some View {
        Label(section.title, systemImage: section.symbol)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(isHovering && !isSelected ? 0.07 : 0))
                    .padding(.horizontal, -8)
                    .padding(.vertical, -5)
            }
            .onHover { isHovering = $0 }
    }
}

/// A compact live indicator at the bottom of the sidebar.
private struct SidebarSessionStatus: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        if let session = environment.sessions.activeSession {
            let active = session.activeDuration(at: environment.clock.now)
            Button {
                environment.selectedSection = .dashboard
            } label: {
                HStack(spacing: 10) {
                    TemplateIconView(icon: session.templateSymbolName, color: session.templateColor, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.templateName)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            Image(systemName: session.state == .paused ? "pause.fill" : "circle.fill")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(session.state == .paused ? .orange : .green)
                                .accessibilityHidden(true)
                            Text(DurationFormatting.clock(active))
                                .font(.callout)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(.background.secondary, in: .rect(cornerRadius: Metrics.cardCornerRadius))
                .overlay(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(session.state == .paused ? "Paused" : "Working on") \(session.templateName), \(DurationFormatting.spoken(active))")
            .accessibilityHint("Shows the Dashboard")
        }
    }
}
