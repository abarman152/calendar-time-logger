import Foundation

public enum CalendarAuthorization: String, Sendable {
    case notDetermined
    case denied
    case restricted
    case writeOnly
    case fullAccess

    public var displayName: String {
        switch self {
        case .notDetermined: "Not Requested"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .writeOnly: "Add Events Only"
        case .fullAccess: "Full Access"
        }
    }
}

/// A calendar the user can record work into.
public struct CalendarInfo: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let sourceTitle: String
    public let color: HexColor?
    public let allowsModifications: Bool

    public init(id: String, title: String, sourceTitle: String, color: HexColor?, allowsModifications: Bool) {
        self.id = id
        self.title = title
        self.sourceTitle = sourceTitle
        self.color = color
        self.allowsModifications = allowsModifications
    }
}

/// Everything needed to write an event.
public struct CalendarEventDraft: Hashable, Sendable {
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var notes: String
    public var url: URL
    public var calendarIdentifier: String

    public init(title: String, startDate: Date, endDate: Date, notes: String, url: URL, calendarIdentifier: String) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.notes = notes
        self.url = url
        self.calendarIdentifier = calendarIdentifier
    }
}

/// A snapshot of an event as it exists in Calendar.
public struct CalendarEventRecord: Hashable, Sendable {
    public let identifier: String
    public let calendarIdentifier: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let url: URL?

    public init(identifier: String, calendarIdentifier: String, title: String, startDate: Date, endDate: Date, url: URL?) {
        self.identifier = identifier
        self.calendarIdentifier = calendarIdentifier
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.url = url
    }
}

public enum CalendarProviderError: Error, Equatable, Sendable {
    case calendarNotFound(String)
    case calendarReadOnly(String)
    case eventNotFound(String)
    case operationFailed(String)
}

/// The boundary around EventKit. The app uses `EventKitCalendarProvider`;
/// tests use an in-memory mock.
@MainActor
public protocol CalendarProviding: AnyObject {
    var authorization: CalendarAuthorization { get }
    func requestFullAccess() async throws -> Bool
    func calendars() -> [CalendarInfo]
    func systemDefaultCalendarIdentifier() -> String?
    func event(withIdentifier identifier: String) -> CalendarEventRecord?
    /// Creates a new event, or updates `existingIdentifier` when provided.
    func saveEvent(_ draft: CalendarEventDraft, existingIdentifier: String?) throws -> CalendarEventRecord
    func removeEvent(withIdentifier identifier: String) throws
    /// Events overlapping `interval`, optionally limited to some calendars.
    func events(in interval: DateInterval, calendarIdentifiers: [String]?) -> [CalendarEventRecord]
}
