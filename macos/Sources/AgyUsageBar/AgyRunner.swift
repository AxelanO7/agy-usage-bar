import Foundation

private final class Buffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ d: Data) { lock.lock(); data.append(d); lock.unlock() }
    var value: Data { lock.lock(); defer { lock.unlock() }; return data }
}

/// Reads quota through the official CLI: `agy -p "/usage" --output-format json`.
/// It never touches tokens or the keychain and makes no model call (0 tokens), so it uses no quota.
enum AgyRunner {
    static let timeout: TimeInterval = 45

    static func locate() -> String? {
        let home = NSHomeDirectory()
        var candidates = [home + "/.local/bin/agy", "/opt/homebrew/bin/agy", "/usr/local/bin/agy"]
        if let env = ProcessInfo.processInfo.environment["AGY_PATH"] { candidates.insert(env, at: 0) }
        if let hit = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return hit }
        // Last resort: ask a login shell (custom PATH).
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "command -v agy"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    static func fetch() async -> Result<Snapshot, FetchError> {
        guard let path = locate() else { return .failure(.noAgy) }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async { cont.resume(returning: run(path)) }
        }
    }

    private static func run(_ path: String) -> Result<Snapshot, FetchError> {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = ["-p", "/usage", "--output-format", "json"]
        p.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        p.standardInput = FileHandle.nullDevice
        var env = ProcessInfo.processInfo.environment
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", NSHomeDirectory() + "/.local/bin", "/usr/bin", "/bin"]
        env["PATH"] = (extra + [env["PATH"] ?? ""]).joined(separator: ":")
        env["NO_COLOR"] = "1"
        p.environment = env

        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        let outBuf = Buffer(), errBuf = Buffer()
        out.fileHandleForReading.readabilityHandler = { outBuf.append($0.availableData) }
        err.fileHandleForReading.readabilityHandler = { errBuf.append($0.availableData) }

        do { try p.run() } catch {
            return .failure(.failed(L.cannotRun(error.localizedDescription)))
        }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        p.waitUntilExit()
        killer.cancel()
        out.fileHandleForReading.readabilityHandler = nil
        err.fileHandleForReading.readabilityHandler = nil
        outBuf.append(out.fileHandleForReading.readDataToEndOfFile())
        errBuf.append(err.fileHandleForReading.readDataToEndOfFile())

        if p.terminationReason == .uncaughtSignal { return .failure(.failed(L.timeout(Int(timeout)))) }
        do { return .success(try UsageParser.parse(outBuf.value)) }
        catch let e as FetchError {
            if case .failed(let m) = e, m == L.emptyOutput, !errBuf.value.isEmpty {
                return .failure(UsageParser.classify(String(decoding: errBuf.value, as: UTF8.self)))
            }
            return .failure(e)
        } catch { return .failure(.failed(error.localizedDescription)) }
    }
}
