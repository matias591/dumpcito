import BuddyCore
import Foundation

enum GalleryState: String, CaseIterable, Identifiable {
    case demo
    case idle
    case idleBadge
    case meetingSoon
    case listeningEmpty
    case listening
    case listeningLong
    case pickerLive
    case pickerNoLive
    case finished
    case needsYou
    case sent
    case error
    case expanded
    case expandedNotice
    case expandedEmpty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .demo: "Live demo (scripted)"
        case .idle: "Idle"
        case .idleBadge: "Idle, a session needs you"
        case .meetingSoon: "Meeting soon"
        case .listeningEmpty: "Listening, no speech yet"
        case .listening: "Listening"
        case .listeningLong: "Listening, long transcript"
        case .pickerLive: "Picker, live sessions"
        case .pickerNoLive: "Picker, no live (Recent)"
        case .finished: "Session finished"
        case .needsYou: "Session needs you"
        case .sent: "Sent"
        case .error: "Error"
        case .expanded: "Expanded panel"
        case .expandedNotice: "Expanded with notice"
        case .expandedEmpty: "Expanded, nothing going on"
        }
    }

    @MainActor func makeModel() -> BuddyModel {
        let m = BuddyModel()
        m.liveSessions = Fake.live
        m.recentSessions = Fake.recent
        m.nextMeeting = Fake.meeting()
        switch self {
        case .demo, .idle:
            m.liveSessions = Fake.live.map { var s = $0; s.needsAttention = false; s.state = .idle; return s }
        case .idleBadge:
            break
        case .meetingSoon:
            m.mood = .meetingSoon(Fake.meeting())
        case .listeningEmpty:
            m.mood = .listening(partial: "")
        case .listening:
            m.mood = .listening(partial: "Check why the approval email shows the customer card twice")
        case .listeningLong:
            m.mood = .listening(partial: Fake.longTranscript)
        case .pickerLive:
            m.mood = .choosingTarget(CaptureResult(screenshotURL: URL(fileURLWithPath: "/tmp/capture.png"),
                                                   transcript: Fake.longTranscript))
        case .pickerNoLive:
            m.liveSessions = []
            m.mood = .choosingTarget(CaptureResult(screenshotURL: nil,
                                                   transcript: "Summarise the failing n8n executions from this morning"))
        case .finished:
            m.mood = .sessionFinished(Fake.live[1])
        case .needsYou:
            m.mood = .sessionNeedsYou(Fake.live[2])
        case .sent:
            m.mood = .sent("Sent to Build Dumpcito gallery")
        case .error:
            m.mood = .error("Microphone access is off. Turn it on in System Settings > Privacy & Security > Microphone.")
        case .expanded:
            m.expanded = true
        case .expandedNotice:
            m.expanded = true
            m.mood = .sessionNeedsYou(Fake.live[2])
        case .expandedEmpty:
            m.expanded = true
            m.liveSessions = []
            m.recentSessions = []
            m.nextMeeting = nil
        }
        Fake.wireCallbacks(m)
        return m
    }
}

@MainActor
enum Fake {
    static let home = NSHomeDirectory()

    static let live: [AgentSession] = [
        AgentSession(id: "s1", title: "Build Dumpcito gallery", cwd: "\(home)/Projects/buddy",
                      state: .working, needsAttention: false,
                      lastActivity: Date().addingTimeInterval(-20)),
        AgentSession(id: "s2", title: "Quote Genie expansion split", cwd: home,
                      state: .idle, needsAttention: false,
                      lastActivity: Date().addingTimeInterval(-190)),
        AgentSession(id: "s3", title: "Zoom call sync dry run", cwd: "\(home)/Projects/n8n-flows",
                      state: .idle, needsAttention: true,
                      lastActivity: Date().addingTimeInterval(-70)),
        AgentSession(id: "s4", title: "Billing recon cleanup with a deliberately long session title",
                      cwd: "\(home)/Projects/clients/acme/billing-reconciliation/app",
                      state: .working, needsAttention: false,
                      lastActivity: Date().addingTimeInterval(-720)),
    ]

    static let recent: [AgentSession] = [
        AgentSession(id: "r1", title: "RMA portal fixes", cwd: "\(home)/Projects/production-portal",
                      state: .idle, needsAttention: false,
                      lastActivity: Date().addingTimeInterval(-7_200)),
        AgentSession(id: "r2", title: "Sunday calendar quick-add", cwd: "\(home)/Projects/sunday",
                      state: .idle, needsAttention: false,
                      lastActivity: Date().addingTimeInterval(-90_000)),
        AgentSession(id: "r3", title: "Knowledge site", cwd: "\(home)/Projects/knowledge",
                      state: .idle, needsAttention: false,
                      lastActivity: Date().addingTimeInterval(-260_000)),
    ]

    static func meeting() -> MeetingEvent {
        MeetingEvent(id: "m1", title: "Design review: Dumpcito",
                     start: Date().addingTimeInterval(4 * 60 + 10),
                     end: Date().addingTimeInterval(34 * 60 + 10),
                     joinURL: URL(string: "https://zoom.us/j/000000000"), location: nil)
    }

    static let longTranscript = """
    Okay so look at this screenshot, the quote approval email renders the customer card twice \
    when there are more than three vessels. Find where that happens in the template, fix it, \
    then run the QuoteApprovalService tests again and tell me what changed.
    """

    /// Gallery-only behaviour so the states are clickable.
    static func wireCallbacks(_ m: BuddyModel) {
        m.onPick = { [weak m] target in
            print("onPick", target)
            let title: String
            switch target {
            case let .session(id): title = (live + recent).first { $0.id == id }?.title ?? id
            case .newSession: title = "a new session"
            }
            m?.mood = .sent("Sent to \(title)")
        }
        m.onDismiss = { [weak m] in
            print("onDismiss")
            m?.mood = .idle
        }
        m.onJoinMeeting = { [weak m] meeting in
            print("onJoinMeeting", meeting.title)
            m?.mood = .idle
        }
        m.onOpenSession = { session in
            print("onOpenSession", session.title)
        }
    }

    /// Scripted walk through the main flow, to review transitions and motion.
    static func runDemo(_ m: BuddyModel) async {
        func wait(_ s: Double) async -> Bool {
            try? await Task.sleep(for: .seconds(s))
            return !Task.isCancelled
        }
        while !Task.isCancelled {
            m.expanded = false
            m.mood = .idle
            guard await wait(5) else { return }
            m.mood = .meetingSoon(meeting())
            guard await wait(4) else { return }
            m.mood = .idle
            guard await wait(1.2) else { return }
            m.mood = .listening(partial: "")
            guard await wait(0.8) else { return }
            var spoken = ""
            for word in longTranscript.split(separator: " ").prefix(26) {
                spoken += (spoken.isEmpty ? "" : " ") + word
                m.mood = .listening(partial: spoken)
                guard await wait(0.16) else { return }
            }
            m.mood = .choosingTarget(CaptureResult(screenshotURL: URL(fileURLWithPath: "/tmp/capture.png"),
                                                   transcript: spoken))
            guard await wait(3) else { return }
            m.mood = .sent("Sent to Build Dumpcito gallery")
            guard await wait(2.5) else { return }
            m.mood = .idle
            guard await wait(2) else { return }
            m.mood = .sessionNeedsYou(live[2])
            guard await wait(3.5) else { return }
            m.expanded = true
            guard await wait(3.5) else { return }
            m.mood = .idle
            guard await wait(2) else { return }
            m.expanded = false
            m.mood = .error("Speech recognition is unavailable right now.")
            guard await wait(3) else { return }
            m.mood = .sessionFinished(live[1])
            guard await wait(3) else { return }
        }
    }
}
