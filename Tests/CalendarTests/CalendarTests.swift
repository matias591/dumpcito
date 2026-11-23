import BuddyCore
import XCTest
@testable import BuddyCalendar

final class JoinLinkExtractorTests: XCTestCase {
    func url(_ s: String) -> URL { URL(string: s)! }

    func testZoomInviteBody() {
        let notes = """
        Hi there, Sam is inviting you to a scheduled Zoom meeting.

        Join Zoom Meeting
        https://example.zoom.us/j/84512345678?pwd=AbCdEf123.

        Meeting ID: 845 1234 5678
        """
        XCTAssertEqual(JoinLinkExtractor.url(url: nil, location: nil, notes: notes),
                       url("https://example.zoom.us/j/84512345678?pwd=AbCdEf123"))
    }

    func testZoomPersonalRoom() {
        XCTAssertEqual(JoinLinkExtractor.url(url: nil, location: "https://zoom.us/my/sam.example", notes: nil),
                       url("https://zoom.us/my/sam.example"))
    }

    func testMeetInHTMLNotes() {
        let notes = #"<p>Join with Google Meet: <a href="https://meet.google.com/abc-defg-hij?authuser=0&amp;hs=122">https://meet.google.com/abc-defg-hij</a></p>"#
        XCTAssertEqual(JoinLinkExtractor.url(url: nil, location: nil, notes: notes),
                       url("https://meet.google.com/abc-defg-hij?authuser=0&hs=122"))
    }

    func testTeamsInAngleBrackets() {
        let notes = "Join: <https://teams.microsoft.com/l/meetup-join/19%3ameeting_Abc%40thread.v2/0?context=%7b%7d>\nOr call in"
        let r = JoinLinkExtractor.url(url: nil, location: nil, notes: notes)
        XCTAssertEqual(r?.host, "teams.microsoft.com")
        XCTAssertTrue(r!.absoluteString.hasSuffix("%7b%7d"))
    }

    func testTeamsLive() {
        XCTAssertEqual(JoinLinkExtractor.url(url: nil, location: nil, notes: "see https://teams.live.com/meet/9312345678901)."),
                       url("https://teams.live.com/meet/9312345678901"))
    }

    func testPrecedenceUrlThenLocationThenNotes() {
        let u = url("https://meet.google.com/aaa-bbbb-ccc")
        XCTAssertEqual(JoinLinkExtractor.url(url: u, location: "https://zoom.us/j/1", notes: "https://zoom.us/j/2"), u)
        XCTAssertEqual(JoinLinkExtractor.url(url: nil, location: "https://zoom.us/j/1", notes: "https://zoom.us/j/2"),
                       url("https://zoom.us/j/1"))
    }

    func testIgnoresNonJoinLinks() {
        XCTAssertNil(JoinLinkExtractor.url(url: url("https://docs.google.com/doc/1"), location: "Room 4",
                                           notes: "Agenda https://zoom.us/pricing and https://example.com/meet.google.com/x"))
    }
}

struct FakeSource: CalendarEventSource {
    var records: [CalendarEventRecord]
    func requestAccess() async -> Bool { true }
    func events(from: Date, to: Date) async -> [CalendarEventRecord] { records }
}

final class ProviderFilterTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func rec(_ id: String, offset: TimeInterval, others: Int = 2, notes: String? = nil, _ tweak: (inout CalendarEventRecord) -> Void = { _ in }) -> CalendarEventRecord {
        var r = CalendarEventRecord(id: id, title: id, start: now.addingTimeInterval(offset),
                                    end: now.addingTimeInterval(offset + 1800), otherAttendeeCount: others, notes: notes)
        tweak(&r)
        return r
    }

    func testFilterRules() async {
        let records = [
            rec("ok-late", offset: 600),
            rec("ok-soon", offset: 60),
            rec("started-1min", offset: -60),
            rec("started-5min", offset: -300),
            rec("too-far", offset: 4000),
            rec("allday", offset: 100) { $0.isAllDay = true },
            rec("declined", offset: 100) { $0.currentUserDeclined = true },
            rec("cancelled", offset: 100) { $0.isCancelled = true },
            rec("focus", offset: 100, others: 0),
            rec("solo-with-link", offset: 200, others: 0, notes: "https://zoom.us/j/123"),
        ]
        let p = EventKitMeetingProvider(source: FakeSource(records: records), now: { self.now })
        let ids = await p.upcoming(within: 3600).map(\.id)
        XCTAssertEqual(ids, ["started-1min", "ok-soon", "solo-with-link", "ok-late"])
    }

    func testJoinURLPopulated() async {
        let p = EventKitMeetingProvider(source: FakeSource(records: [rec("a", offset: 60, notes: "https://meet.google.com/abc-defg-hij")]), now: { self.now })
        let r = await p.upcoming(within: 3600)
        XCTAssertEqual(r.first?.joinURL?.absoluteString, "https://meet.google.com/abc-defg-hij")
    }
}

final class Clock: @unchecked Sendable {
    private let lock = NSLock(); private var t: Date
    init(_ t: Date) { self.t = t }
    var date: Date { lock.lock(); defer { lock.unlock() }; return t }
    func advance(_ s: TimeInterval) { lock.lock(); t = t.addingTimeInterval(s); lock.unlock() }
}

final class FakeProvider: MeetingProviding, @unchecked Sendable {
    var events: [MeetingEvent]
    init(_ e: [MeetingEvent]) { events = e }
    func requestAccess() async -> Bool { true }
    func upcoming(within seconds: TimeInterval) async -> [MeetingEvent] { events }
}

final class WatcherTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var suite: String!
    var defaults: UserDefaults!

    override func setUp() {
        suite = "buddy.test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    func meeting(_ id: String = "m1", startIn: TimeInterval) -> MeetingEvent {
        MeetingEvent(id: id, title: id, start: t0.addingTimeInterval(startIn), end: t0.addingTimeInterval(startIn + 1800), joinURL: nil, location: nil)
    }

    func collect(_ w: MeetingWatcher) async -> (AsyncStream<MeetingEvent>, Box) {
        let box = Box()
        let s = await w.nudges()
        return (s, box)
    }
    final class Box: @unchecked Sendable { var got: [MeetingEvent] = [] }

    func testNotBeforeLeadWindowThenOnceOnly() async {
        let clock = Clock(t0)
        let provider = FakeProvider([meeting(startIn: 600)])
        let w = MeetingWatcher(provider: provider, pollInterval: 3600, defaults: defaults, now: { clock.date })
        let (stream, box) = await collect(w)
        var it = stream.makeAsyncIterator()
        await w.poll()                       // 10 min away: nothing
        clock.advance(310)                   // 4m50s away: enters window
        await w.poll()
        let first = await it.next()
        box.got.append(first!)
        XCTAssertEqual(first?.id, "m1")
        // provider keeps returning same event
        for _ in 0..<3 { clock.advance(30); await w.poll() }
        // add a distinct event to prove the stream is alive and the next element is NOT a repeat of m1
        provider.events.append(meeting("m2", startIn: 700))
        await w.poll()
        let second = await it.next()
        XCTAssertEqual(second?.id, "m2")
    }

    func testPersistenceAcrossInstances() async {
        let clock = Clock(t0)
        let provider = FakeProvider([meeting(startIn: 120)])
        let w1 = MeetingWatcher(provider: provider, pollInterval: 3600, defaults: defaults, now: { clock.date })
        var it1 = await w1.nudges().makeAsyncIterator()
        await w1.poll()
        let a = await it1.next()
        XCTAssertEqual(a?.id, "m1")

        let w2 = MeetingWatcher(provider: provider, pollInterval: 3600, defaults: defaults, now: { clock.date })
        var it2 = await w2.nudges().makeAsyncIterator()
        await w2.poll()
        provider.events.append(meeting("m2", startIn: 100))
        await w2.poll()
        let b = await it2.next()
        XCTAssertEqual(b?.id, "m2")  // m1 not re-emitted by new instance
    }

    func testPrunesAfterOneDay() async {
        let clock = Clock(t0)
        let provider = FakeProvider([meeting(startIn: 60)])
        let w = MeetingWatcher(provider: provider, pollInterval: 3600, defaults: defaults, now: { clock.date })
        _ = await w.nudges()
        await w.poll()
        XCTAssertEqual((defaults.dictionary(forKey: "buddy.calendar.nudged") ?? [:]).count, 1)
        provider.events = []
        clock.advance(2 * 86400)
        await w.poll()
        XCTAssertEqual((defaults.dictionary(forKey: "buddy.calendar.nudged") ?? [:]).count, 0)
    }

    func testNextMeeting() async {
        let clock = Clock(t0)
        let provider = FakeProvider([meeting("old", startIn: -7200), meeting("next", startIn: 3000)])
        let w = MeetingWatcher(provider: provider, defaults: defaults, now: { clock.date })
        let n = await w.nextMeeting()
        XCTAssertEqual(n?.id, "next")
    }
}
