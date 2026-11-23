import Foundation

/// What the progress game counts. Only things already visible on this Mac; no mail, no chat.
public enum ProgressTrack: String, CaseIterable, Codable, Sendable {
    case claude, meetings

    public var displayName: String {
        switch self {
        case .claude: "Claude sessions"
        case .meetings: "Meetings joined"
        }
    }
}

public struct TrackSummary: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var level: Int
    /// 0...1 progress toward the next level of this track.
    public var fraction: Double
    /// Counted in the last 7 days.
    public var weekCount: Int

    public init(id: String, name: String, level: Int, fraction: Double, weekCount: Int) {
        self.id = id; self.name = name; self.level = level; self.fraction = fraction; self.weekCount = weekCount
    }
}

/// Everything the menu shows about progress. Derived from stored daily counts; never stored itself.
public struct ProgressSummary: Equatable, Sendable {
    public var level: Int
    public var xp: Int
    public var levelStartXP: Int
    /// nil at the top level.
    public var nextLevelXP: Int?
    /// 1...5: how far Dumpcito has evolved.
    public var stage: Int
    /// Neutral wording only: never "behind".
    public var pace: String
    public var tracks: [TrackSummary]

    public init(level: Int, xp: Int, levelStartXP: Int, nextLevelXP: Int?, stage: Int, pace: String, tracks: [TrackSummary]) {
        self.level = level; self.xp = xp; self.levelStartXP = levelStartXP; self.nextLevelXP = nextLevelXP
        self.stage = stage; self.pace = pace; self.tracks = tracks
    }

    public var fraction: Double {
        guard let next = nextLevelXP, next > levelStartXP else { return 1 }
        return min(1, max(0, Double(xp - levelStartXP) / Double(next - levelStartXP)))
    }
}
