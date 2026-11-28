import Foundation

public enum CIState: String, Sendable {
    case success = "SUCCESS"
    case failure = "FAILURE"
    case error = "ERROR"
    case pending = "PENDING"
    case none = "NONE"
}

/// One item of `gh prq --json`. Only the fields the menu shows are decoded, and all of them
/// are optional so a gh-prq that adds or drops fields doesn't break the app.
public struct PullRequest: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    public let repo: String
    public let number: Int
    public let title: String
    public let url: String
    public let bucket: String
    public let reason: String
    public let ciState: CIState
    public let badges: [String]
    /// When it became your turn (`actionSince`, falling back to `updatedAt`).
    public let actionSince: Date?

    enum CodingKeys: String, CodingKey {
        case id, repo, number, title, url, bucket, reason, ciState, badges, actionSince, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        repo = try c.decodeIfPresent(String.self, forKey: .repo) ?? ""
        number = try c.decodeIfPresent(Int.self, forKey: .number) ?? 0
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        bucket = try c.decodeIfPresent(String.self, forKey: .bucket) ?? ""
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? url
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
        let ci = try c.decodeIfPresent(String.self, forKey: .ciState) ?? ""
        ciState = CIState(rawValue: ci) ?? .none
        badges = try c.decodeIfPresent([String].self, forKey: .badges) ?? []

        let since = try c.decodeIfPresent(String.self, forKey: .actionSince) ?? ""
        let updated = try c.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        actionSince = ISODate.parse(since.isEmpty ? updated : since)
    }

    public var webURL: URL? { URL(string: url) }

    /// "acme/api#412 · 2 new commits since your review · team · 3h ago"
    public func subtitle(now: Date) -> String {
        [
            "\(repo)#\(number)",
            reason,
            badges.joined(separator: " · "),
            RelativeTime.string(since: actionSince, now: now),
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }
}

enum ISODate {
    static func parse(_ string: String) -> Date? {
        guard !string.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

public enum RelativeTime {
    public static func string(since date: Date?, now: Date) -> String {
        guard let date else { return "" }
        let s = max(0, Int(now.timeIntervalSince(date).rounded()))
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86400 { return "\(s / 3600)h ago" }
        return "\(s / 86400)d ago"
    }
}
