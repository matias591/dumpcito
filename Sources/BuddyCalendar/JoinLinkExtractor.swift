import Foundation

/// Finds the first Zoom / Google Meet / Microsoft Teams join link in an event.
/// Search order: event.url, then location, then notes. Notes may be HTML-ish.
public enum JoinLinkExtractor {
    public static func url(url: URL?, location: String?, notes: String?) -> URL? {
        for text in [url?.absoluteString, location, notes] {
            if let text, let found = firstJoinURL(in: text) { return found }
        }
        return nil
    }

    static func firstJoinURL(in text: String) -> URL? {
        let decoded = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#38;", with: "&")
        // Stop at whitespace, quotes and angle brackets so href="..." and <url> both work.
        guard let regex = try? NSRegularExpression(pattern: #"https://[^\s<>"'\x{00A0}]+"#, options: [.caseInsensitive]) else { return nil }
        let ns = decoded as NSString
        for m in regex.matches(in: decoded, range: NSRange(location: 0, length: ns.length)) {
            let cleaned = trimTrailing(ns.substring(with: m.range))
            if let u = URL(string: cleaned), isJoinLink(u) { return u }
        }
        return nil
    }

    private static func trimTrailing(_ s: String) -> String {
        var out = s
        let junk: Set<Character> = [".", ",", ";", ":", "!", "?", ")", "]", "}", ">", "*"]
        while let last = out.last, junk.contains(last) { out.removeLast() }
        return out
    }

    static func isJoinLink(_ u: URL) -> Bool {
        guard u.scheme?.lowercased() == "https", let host = u.host?.lowercased() else { return false }
        let path = u.path.lowercased()
        if host == "zoom.us" || host.hasSuffix(".zoom.us") {
            return path.hasPrefix("/j/") || path.hasPrefix("/my/") || path == "/my"
        }
        if host == "meet.google.com" { return path.count > 1 }
        if host == "teams.microsoft.com" { return path.hasPrefix("/l/meetup-join") }
        if host == "teams.live.com" { return path.hasPrefix("/meet/") }
        return false
    }
}
