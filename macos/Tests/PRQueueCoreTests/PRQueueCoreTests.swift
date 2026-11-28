import Foundation
import XCTest
@testable import PRQueueCore

final class PRQueueCoreTests: XCTestCase {
    private func sampleJSON() throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // PRQueueCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // macos
            .deletingLastPathComponent()  // repo root
        return try String(contentsOf: repoRoot.appendingPathComponent("docs/sample.json"), encoding: .utf8)
    }

    func testParsesEnvelope() throws {
        let snapshot = try QueueParser.parse(stdout: try sampleJSON(), stderr: "")
        XCTAssertEqual(snapshot.items.count, 6)
        XCTAssertEqual(snapshot.fetchedAt, ISODate.parse("2026-11-25T15:44:13Z"))
        XCTAssertNil(snapshot.staleReason)

        let first = snapshot.items[0]
        XCTAssertEqual(first.repo, "acme/api")
        XCTAssertEqual(first.number, 412)
        XCTAssertEqual(first.ciState, .success)
        XCTAssertEqual(first.webURL?.absoluteString, "https://github.com/acme/api/pull/412")
    }

    func testParsesPlainArrayAndStaleCacheFromStderr() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let stdout = #"[{"repo":"a/b","number":1,"title":"T","url":"u","bucket":"NEEDS_REREVIEW","updatedAt":"2026-01-01T00:00:00.123Z"}]"#
        let snapshot = try QueueParser.parse(stdout: stdout, stderr: "warning: using stale cache (network unreachable)\n", now: now)
        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertEqual(snapshot.fetchedAt, now)
        XCTAssertEqual(snapshot.staleReason, "network unreachable")
        XCTAssertNotNil(snapshot.items[0].actionSince, "falls back to updatedAt, with fractional seconds")
        XCTAssertEqual(snapshot.items[0].ciState, .none)
    }

    func testEnvelopeStaleReason() throws {
        let stdout = #"{"fetchedAt":"2026-11-25T15:44:13Z","staleReason":"HTTP 502","items":[]}"#
        XCTAssertEqual(try QueueParser.parse(stdout: stdout, stderr: "").staleReason, "HTTP 502")
    }

    func testRejectsNonJSON() {
        XCTAssertThrowsError(try QueueParser.parse(stdout: "acme/api#412 Retry webhook…", stderr: ""))
    }

    func testSummaryHidesWaitingByDefault() throws {
        let items = try QueueParser.parse(stdout: try sampleJSON(), stderr: "").items

        let hidden = QueueSummary.make(from: items, showWaiting: false)
        XCTAssertEqual(hidden.actionableCount, 5)
        XCTAssertEqual(hidden.waitingCount, 1)
        XCTAssertEqual(hidden.sections.map(\.label), [
            "Needs Re-review", "Needs Review", "My PRs — Action Needed", "My PRs — Ready to Merge",
        ])
        XCTAssertEqual(hidden.sections[1].items.count, 2)

        let shown = QueueSummary.make(from: items, showWaiting: true)
        XCTAssertEqual(shown.sections.last?.label, "My PRs — Waiting")
        XCTAssertEqual(shown.actionableCount, 5)
    }

    func testSubtitle() throws {
        let items = try QueueParser.parse(stdout: try sampleJSON(), stderr: "").items
        let now = ISODate.parse("2026-11-25T15:44:13Z")!
        XCTAssertEqual(items[2].subtitle(now: now), "acme/infra#57 · team review requested · team · 3h ago")
    }

    func testRelativeTime() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(RelativeTime.string(since: nil, now: now), "")
        XCTAssertEqual(RelativeTime.string(since: now.addingTimeInterval(-30), now: now), "just now")
        XCTAssertEqual(RelativeTime.string(since: now.addingTimeInterval(-125), now: now), "2m ago")
        XCTAssertEqual(RelativeTime.string(since: now.addingTimeInterval(-7200), now: now), "2h ago")
        XCTAssertEqual(RelativeTime.string(since: now.addingTimeInterval(-3 * 86400), now: now), "3d ago")
        XCTAssertEqual(RelativeTime.string(since: now.addingTimeInterval(60), now: now), "just now", "clock skew")
    }

    func testWithoutEnvelope() {
        XCTAssertEqual(QueueCommand.withoutEnvelope("gh prq --json --envelope"), "gh prq --json")
        XCTAssertEqual(QueueCommand.withoutEnvelope("gh prq --json --envelope --org acme"), "gh prq --json --org acme")
        XCTAssertEqual(QueueCommand.withoutEnvelope("gh prq --json --envelopes"), "gh prq --json --envelopes")
    }

    func testInterpreterFallsBackOnceWhenEnvelopeIsRejected() {
        let rejected = CommandResult(exitCode: 1, stderr: "error: unknown option '--envelope'\n")
        XCTAssertEqual(RefreshInterpreter.interpret(rejected, usingLegacyJSON: false), .retryWithoutEnvelope)
        XCTAssertEqual(RefreshInterpreter.interpret(rejected, usingLegacyJSON: true), .failed("error: unknown option '--envelope'"))
    }

    func testInterpreterErrors() {
        XCTAssertEqual(
            RefreshInterpreter.interpret(CommandResult(exitCode: 4, stderr: "first\nauth required\n\n"), usingLegacyJSON: false),
            .failed("auth required"))
        XCTAssertEqual(
            RefreshInterpreter.interpret(CommandResult(exitCode: 127), usingLegacyJSON: false),
            .failed("Command exited with code 127"))
        XCTAssertEqual(
            RefreshInterpreter.interpret(CommandResult(exitCode: -1, timedOut: true, timeout: 120), usingLegacyJSON: false),
            .failed("The command timed out after 120 seconds"))
    }

    func testRunnerCapturesOutputAndExitCode() {
        let result = CommandRunner.runBlocking("echo out; echo err >&2; exit 3", timeout: 10)
        XCTAssertEqual(result.exitCode, 3)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").last, "out")
        XCTAssertTrue(result.stderr.contains("err"))
        XCTAssertFalse(result.timedOut)
    }

    func testRunnerHandlesLargeOutput() {
        let result = CommandRunner.runBlocking("head -c 1000000 /dev/zero | tr '\\0' x", timeout: 10)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.hasSuffix(String(repeating: "x", count: 100)))
        XCTAssertGreaterThanOrEqual(result.stdout.count, 1_000_000)
    }

    func testRunnerTimesOut() {
        let start = Date()
        let result = CommandRunner.runBlocking("sleep 30", timeout: 0.5)
        XCTAssertTrue(result.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
    }

    func testRunnerPutsHomebrewOnPath() {
        let path = CommandRunner.environment()["PATH"] ?? ""
        XCTAssertTrue(path.contains("/opt/homebrew/bin"))
        XCTAssertTrue(path.contains("/usr/local/bin"))
    }
}
