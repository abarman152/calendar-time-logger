import Foundation
import Observation

/// Publishes the current time once per second for live timer UI.
///
/// The clock only drives *refresh*; durations are always computed from
/// session timestamps, so a late or skipped tick never affects accuracy.
@MainActor
@Observable
public final class SessionClock {
    public private(set) var now: Date
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let source: () -> Date

    public init(source: @escaping () -> Date = Date.init) {
        self.source = source
        self.now = source()
    }

    public var isRunning: Bool { timer != nil }

    public func start() {
        guard timer == nil else { return }
        tick()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.1
        // `.common` keeps the timer firing while menus are open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        tick()
    }

    public func tick() {
        now = source()
    }
}
