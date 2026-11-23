import BuddyCore
import EventKit
import Foundation

/// Plain snapshot of a calendar event, decoupled from EventKit so the filter is unit-testable.
public struct CalendarEventRecord: Sendable, Equatable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var isCancelled: Bool
    public var currentUserDeclined: Bool
    /// Attendees other than the current user.
    public var otherAttendeeCount: Int
    public var url: URL?
    public var location: String?
    public var notes: String?

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false,
                isCancelled: Bool = false, currentUserDeclined: Bool = false, otherAttendeeCount: Int = 0,
                url: URL? = nil, location: String? = nil, notes: String? = nil) {
        self.id = id; self.title = title; self.start = start; self.end = end; self.isAllDay = isAllDay
        self.isCancelled = isCancelled; self.currentUserDeclined = currentUserDeclined
        self.otherAttendeeCount = otherAttendeeCount; self.url = url; self.location = location; self.notes = notes
    }
}

/// Thin seam over EventKit. Real implementation: EKEventStoreSource. Tests use fakes.
public protocol CalendarEventSource: Sendable {
    func requestAccess() async -> Bool
    /// Events overlapping [from, to] across all calendars. Returns [] when access is not granted.
    func events(from: Date, to: Date) async -> [CalendarEventRecord]
}

public final class EventKitMeetingProvider: MeetingProviding {
    private let source: CalendarEventSource
    private let now: @Sendable () -> Date
    /// A meeting that started this recently is still returned, so a late nudge still works.
    public static let gracePeriod: TimeInterval = 120

    public init(source: CalendarEventSource = EKEventStoreSource(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.source = source
        self.now = now
    }

    public func requestAccess() async -> Bool { await source.requestAccess() }

    public func upcoming(within seconds: TimeInterval) async -> [MeetingEvent] {
        let t = now()
        let from = t.addingTimeInterval(-Self.gracePeriod)
        let records = await source.events(from: from, to: t.addingTimeInterval(seconds))
        return Self.meetings(from: records, now: t, within: seconds)
    }

    /// Pure filter + mapping.
    ///
    /// FILTER RULE (a "meeting" is something worth a nudge). Skipped:
    ///  - all-day events
    ///  - cancelled events
    ///  - events the current user declined
    ///  - events with NO other attendees AND NO join link (personal blocks / focus time)
    /// Kept: start in [now - 2 min, now + window]; sorted soonest first.
    static func meetings(from records: [CalendarEventRecord], now: Date, within seconds: TimeInterval) -> [MeetingEvent] {
        let earliest = now.addingTimeInterval(-gracePeriod)
        let latest = now.addingTimeInterval(seconds)
        var out: [MeetingEvent] = []
        for r in records {
            if r.isAllDay || r.isCancelled || r.currentUserDeclined { continue }
            if r.start < earliest || r.start > latest { continue }
            let join = JoinLinkExtractor.url(url: r.url, location: r.location, notes: r.notes)
            if r.otherAttendeeCount == 0 && join == nil { continue }
            let loc = r.location?.trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(MeetingEvent(id: r.id, title: r.title, start: r.start, end: r.end,
                                    joinURL: join, location: (loc?.isEmpty ?? true) ? nil : loc))
        }
        return out.sorted { $0.start < $1.start }
    }
}

/// Real EventKit adaptor. Never exercised in tests (needs the Calendar permission).
public final class EKEventStoreSource: CalendarEventSource, @unchecked Sendable {
    private let store = EKEventStore()
    public init() {}

    public func requestAccess() async -> Bool {
        do { return try await store.requestFullAccessToEvents() } catch { return false }
    }

    public func events(from: Date, to: Date) async -> [CalendarEventRecord] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: predicate).map { e in
            let me = e.attendees?.first(where: { $0.isCurrentUser })
            let others = (e.attendees ?? []).filter { !$0.isCurrentUser }.count
            // Recurring occurrences share eventIdentifier, so add the start time to make the id unique.
            let base = e.eventIdentifier ?? "\(e.calendarItemIdentifier)"
            return CalendarEventRecord(
                id: "\(base)@\(Int(e.startDate.timeIntervalSince1970))",
                title: e.title ?? "(No title)", start: e.startDate, end: e.endDate,
                isAllDay: e.isAllDay, isCancelled: e.status == .canceled,
                currentUserDeclined: me?.participantStatus == .declined,
                otherAttendeeCount: others, url: e.url, location: e.location, notes: e.notes)
        }
    }
}
