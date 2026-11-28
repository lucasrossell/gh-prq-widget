import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct CommandResult: Equatable, Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    public var timedOut: Bool
    public var timeout: TimeInterval

    public init(exitCode: Int32, stdout: String = "", stderr: String = "", timedOut: Bool = false, timeout: TimeInterval = 0) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
        self.timeout = timeout
    }
}

/// Runs the command setting the way a terminal line would run.
///
/// Apps started from Finder or at login get a bare PATH (/usr/bin:/bin:/usr/sbin:/sbin), so
/// `gh` from Homebrew wouldn't be found. The command goes through the user's login shell
/// (`zsh -l -c`), which reads ~/.zprofile where `brew shellenv` usually lives, and the
/// Homebrew bin folders are added to PATH in case it doesn't.
public enum CommandRunner {
    public static func run(_ command: String, timeout: TimeInterval) async -> CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: runBlocking(command, timeout: timeout))
            }
        }
    }

    public static func runBlocking(_ command: String, timeout: TimeInterval) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: loginShell())
        process.arguments = ["-l", "-c", command]
        process.environment = environment()
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            return CommandResult(exitCode: -1, stderr: "Couldn't start \(loginShell()): \(error.localizedDescription)")
        }

        // Drain both pipes while the command runs so a large queue can't fill a pipe buffer and stall it.
        let stdoutBox = DataBox()
        let stderrBox = DataBox()
        let readers = DispatchGroup()
        for (pipe, box) in [(stdoutPipe, stdoutBox), (stderrPipe, stderrBox)] {
            readers.enter()
            DispatchQueue.global(qos: .utility).async {
                box.data = pipe.fileHandleForReading.readDataToEndOfFile()
                readers.leave()
            }
        }

        var timedOut = false
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            _ = exited.wait(timeout: .now() + 2)
        }
        // A grandchild that outlives the shell can hold the pipes open; don't wait on it forever.
        _ = readers.wait(timeout: .now() + (timedOut ? 2 : 10))

        return CommandResult(
            exitCode: timedOut ? -1 : process.terminationStatus,
            stdout: String(decoding: stdoutBox.data, as: UTF8.self),
            stderr: String(decoding: stderrBox.data, as: UTF8.self),
            timedOut: timedOut,
            timeout: timeout
        )
    }

    static func loginShell() -> String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return FileManager.default.isExecutableFile(atPath: "/bin/zsh") ? "/bin/zsh" : "/bin/sh"
    }

    static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extra = ["/opt/homebrew/bin", "/usr/local/bin"]
        let existing = (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init)
        env["PATH"] = (extra.filter { !existing.contains($0) } + existing).joined(separator: ":")
        // gh-prq colors and spinners are for terminals.
        env["NO_COLOR"] = "1"
        return env
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}
