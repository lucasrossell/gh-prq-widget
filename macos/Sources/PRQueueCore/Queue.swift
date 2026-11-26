import Foundation

/// Mirrors BUCKET_LABELS / ACTIONABLE_BUCKETS / WAITING_BUCKETS in gh-prq's src/core/types.ts.
public enum Bucket {
    public static let labels: [String: String] = [
        "NEEDS_REREVIEW": "Needs Re-review",
        "NEEDS_INITIAL_REVIEW": "Needs Review",
        "MY_PR_ACTION_NEEDED": "My PRs — Action Needed",
        "MY_PR_READY": "My PRs — Ready to Merge",
        "WAITING_ON_AUTHOR": "Waiting on Author",
        "MY_PR_WAITING": "My PRs — Waiting",
    ]
    public static let actionable: Set<String> = [
        "NEEDS_REREVIEW", "NEEDS_INITIAL_REVIEW", "MY_PR_ACTION_NEEDED", "MY_PR_READY",
    ]
    public static let waiting: Set<String> = ["WAITING_ON_AUTHOR", "MY_PR_WAITING"]

    public static func label(for bucket: String) -> String { labels[bucket] ?? bucket }
}

public struct QueueSection: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let items: [PullRequest]
}

public struct QueueSummary: Equatable, Sendable {
    public let sections: [QueueSection]
    public let actionableCount: Int
    public let waitingCount: Int

    public static let empty = QueueSummary(sections: [], actionableCount: 0, waitingCount: 0)

    /// Keeps gh-prq's order and groups consecutive PRs of the same bucket, like the Plasma list's sections.
    public static func make(from items: [PullRequest], showWaiting: Bool) -> QueueSummary {
        var sections: [QueueSection] = []
        var current: (label: String, items: [PullRequest])?
        var actionable = 0
        var waiting = 0

        func flush() {
            if let current {
                sections.append(QueueSection(id: "\(sections.count)-\(current.label)", label: current.label, items: current.items))
            }
            current = nil
        }

        for pr in items {
            let isActionable = Bucket.actionable.contains(pr.bucket)
            let isWaiting = Bucket.waiting.contains(pr.bucket)
            if isActionable { actionable += 1 }
            if isWaiting { waiting += 1 }
            guard isActionable || (showWaiting && isWaiting) else { continue }

            let label = Bucket.label(for: pr.bucket)
            if current?.label == label {
                current?.items.append(pr)
            } else {
                flush()
                current = (label, [pr])
            }
        }
        flush()
        return QueueSummary(sections: sections, actionableCount: actionable, waitingCount: waiting)
    }
}

public struct QueueSnapshot: Equatable, Sendable {
    public let items: [PullRequest]
    public let fetchedAt: Date
    /// Set when gh-prq served its cache because the fetch failed.
    public let staleReason: String?
}

public enum QueueParseError: Error, Equatable {
    case notJSON
}

public enum QueueParser {
    private struct Envelope: Decodable {
        let items: [PullRequest]?
        let fetchedAt: String?
        let staleReason: String?
    }

    /// Accepts both `--json --envelope` (an object) and plain `--json` (an array).
    public static func parse(stdout: String, stderr: String, now: Date = Date()) throws -> QueueSnapshot {
        let data = Data(stdout.utf8)
        let decoder = JSONDecoder()

        if let items = try? decoder.decode([PullRequest].self, from: data) {
            // Plain --json: no fetch time, so stamp it with when we read it.
            return QueueSnapshot(items: items, fetchedAt: now, staleReason: staleReason(fromStderr: stderr))
        }
        guard let envelope = try? decoder.decode(Envelope.self, from: data) else {
            throw QueueParseError.notJSON
        }
        let stale = envelope.staleReason.flatMap { $0.isEmpty ? nil : $0 }
        return QueueSnapshot(
            items: envelope.items ?? [],
            fetchedAt: envelope.fetchedAt.flatMap(ISODate.parse) ?? now,
            staleReason: stale
        )
    }

    static func staleReason(fromStderr stderr: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"stale cache \((.*)\)"#),
              let match = regex.firstMatch(in: stderr, range: NSRange(stderr.startIndex..., in: stderr)),
              let range = Range(match.range(at: 1), in: stderr)
        else { return nil }
        return String(stderr[range])
    }
}

public enum QueueCommand {
    public static let defaultCommand = "gh prq --json --envelope"

    /// For a gh-prq that predates `--envelope`.
    public static func withoutEnvelope(_ command: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\s--envelope\b"#) else { return command }
        return regex.stringByReplacingMatches(
            in: command, range: NSRange(command.startIndex..., in: command), withTemplate: "")
    }
}

public enum RefreshOutcome: Equatable, Sendable {
    case loaded(QueueSnapshot)
    case failed(String)
    /// gh-prq rejected `--envelope`; run again without it.
    case retryWithoutEnvelope
}

public enum RefreshInterpreter {
    public static func interpret(_ result: CommandResult, usingLegacyJSON: Bool, now: Date = Date()) -> RefreshOutcome {
        if result.timedOut {
            return .failed("The command timed out after \(Int(result.timeout)) seconds")
        }
        if result.exitCode != 0 && !usingLegacyJSON && result.stderr.contains("--envelope") {
            return .retryWithoutEnvelope
        }
        if result.exitCode != 0 {
            let lastLine = result.stderr
                .split(whereSeparator: \.isNewline)
                .last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            return .failed(lastLine.map(String.init) ?? "Command exited with code \(result.exitCode)")
        }
        do {
            return .loaded(try QueueParser.parse(stdout: result.stdout, stderr: result.stderr, now: now))
        } catch {
            return .failed("Output wasn't JSON. Does the command include --json?")
        }
    }
}
