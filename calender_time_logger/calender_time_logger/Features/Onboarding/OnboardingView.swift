import CalendarTimeLoggerKit
import SwiftUI

/// First-launch welcome explaining the product and offering Calendar access.
///
/// This is the app's startup experience: macOS apps have no launch screen, so
/// the brand appears here, as the original CTL mark — white “CTL” centered on
/// black — above the welcome content, in both light and dark appearance.
struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var environment
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            BrandHeader()
            content
        }
        .frame(width: 540)
    }

    private var content: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Text("Welcome")
                    .font(.title.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel("Welcome to Calendar Time Logger")
                Text("Your actual work is the source of truth. Apple Calendar is the output.")
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 14) {
                Point(symbol: "play.circle", title: "Start work when you begin",
                      text: "Pick a template from the menu bar. A live timer runs — nothing is added to Calendar yet.")
                Point(symbol: "checkmark.circle", title: "Finish Work when you’re done",
                      text: "The session is saved to Work Logs, then added to Calendar with its real start and finish times.")
                Point(symbol: "lock.shield", title: "Your record is safe",
                      text: "If Calendar is unavailable, your work log is still saved and can be synced later.")
            }
            .frame(maxWidth: 420)

            VStack(spacing: 8) {
                if environment.calendar.authorization == .notDetermined {
                    Button {
                        Task { await environment.calendar.requestAccess() }
                    } label: {
                        Label("Connect Apple Calendar", systemImage: "calendar.badge.plus")
                            .frame(maxWidth: 260)
                    }
                    .buttonStyle(.glass)
                } else {
                    Label("Calendar: \(environment.calendar.authorization.displayName)", systemImage: "calendar")
                        .foregroundStyle(.secondary)
                }
                if environment.notifications.authorization == .notDetermined {
                    Button {
                        Task { await environment.notifications.requestAuthorizationIfNeeded() }
                    } label: {
                        Label("Allow Notifications", systemImage: "bell.badge")
                            .frame(maxWidth: 260)
                    }
                    .buttonStyle(.glass)
                }
                Button {
                    onFinish()
                } label: {
                    Text("Get Started").frame(maxWidth: 260)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 36)
        .padding(.top, 26)
        .padding(.bottom, 32)
    }
}

/// The CTL brand panel: the original wordmark centered on black, with the
/// product name. It is black in both appearances, like the app icon.
private struct BrandHeader: View {
    var body: some View {
        VStack(spacing: 16) {
            Image("CTLWordmark")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 150)
                .accessibilityHidden(true)
            Text("Calendar Time Logger")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 44)
        .padding(.bottom, 30)
        .background(.black)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
    }
}

private struct Point: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
