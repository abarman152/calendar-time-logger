import Foundation

/// A running copy of Calendar Time Logger.
public struct RunningAppInstance: Hashable, Sendable {
    public let processIdentifier: Int32
    public let launchDate: Date?

    public init(processIdentifier: Int32, launchDate: Date?) {
        self.processIdentifier = processIdentifier
        self.launchDate = launchDate
    }
}

/// Keeps one copy of the app running.
///
/// A second copy would add a second CTL item to the menu bar and write to the
/// same database, so a newly launched copy hands over to the one already
/// running and quits.
public enum AppInstancePolicy {
    /// The instance the current process should defer to, or `nil` to keep
    /// running. The earliest-launched instance wins; ties (or unknown launch
    /// dates) go to the lower process identifier, so two copies launched at
    /// the same moment never both quit.
    public static func instanceToDefer(to current: RunningAppInstance, among running: [RunningAppInstance]) -> RunningAppInstance? {
        running
            .filter { $0.processIdentifier != current.processIdentifier && launchedBefore($0, current) }
            .min { launchedBefore($0, $1) }
    }

    private static func launchedBefore(_ lhs: RunningAppInstance, _ rhs: RunningAppInstance) -> Bool {
        switch (lhs.launchDate, rhs.launchDate) {
        case let (l?, r?) where l != r: l < r
        default: lhs.processIdentifier < rhs.processIdentifier
        }
    }
}

extension MenuBarService {
    /// Whether the permanent CTL item is in the menu bar. It is independent of
    /// sessions: idle or working, the item stays while the app runs.
    public var isItemInserted: Bool { settings.showsMenuBarItem }
}
