import Foundation
import Darwin

final class LatestLog {
    static let shared = LatestLog()
    private let queue = DispatchQueue(label: "backrooms.latestlog")
    private let url: URL
    private static var installed = false
    
    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        url = docs.appendingPathComponent("latestlog.txt")
    }
    
    static func install() {
        guard !installed else { return }
        installed = true
        shared.reset()
        log("LatestLog installed")
        NSSetUncaughtExceptionHandler { exception in
            LatestLog.writeSync("UNCAUGHT NSException: \(exception.name.rawValue) reason=\(exception.reason ?? "nil") stack=\(exception.callStackSymbols.joined(separator: " | "))")
        }
        signal(SIGABRT) { sig in LatestLog.writeSync("SIGNAL SIGABRT (\(sig))") ; Darwin.exit(sig) }
        signal(SIGILL)  { sig in LatestLog.writeSync("SIGNAL SIGILL (\(sig))")  ; Darwin.exit(sig) }
        signal(SIGSEGV) { sig in LatestLog.writeSync("SIGNAL SIGSEGV (\(sig))") ; Darwin.exit(sig) }
        signal(SIGFPE)  { sig in LatestLog.writeSync("SIGNAL SIGFPE (\(sig))")  ; Darwin.exit(sig) }
        signal(SIGBUS)  { sig in LatestLog.writeSync("SIGNAL SIGBUS (\(sig))")  ; Darwin.exit(sig) }
        signal(SIGPIPE) { sig in LatestLog.writeSync("SIGNAL SIGPIPE (\(sig))") ; Darwin.exit(sig) }
    }
    
    static func log(_ message: String) { shared.log(message) }
    static func fileURL() -> URL { shared.url }
    static func text() -> String { (try? String(contentsOf: shared.url, encoding: .utf8)) ?? "latestlog.txt is empty" }
    
    private func reset() {
        let header = "\n\n=== Backrooms latestlog session ===\nstarted=\(Date())\ndevice=\(ProcessInfo.processInfo.operatingSystemVersionString)\n===========================\n"
        Self.append(header, to: url)
    }
    
    private func log(_ message: String) {
        let line = "[\(Date())] \(message)\n"
        queue.async { Self.append(line, to: self.url) }
        print(line, terminator: "")
    }
    
    private static func writeSync(_ message: String) {
        let line = "[\(Date())] \(message)\n"
        append(line, to: shared.url)
    }
    
    private static func append(_ line: String, to url: URL) {
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            if let fh = try? FileHandle(forWritingTo: url) {
                try? fh.seekToEnd()
                try? fh.write(contentsOf: data)
                try? fh.close()
            }
        } else {
            try? data.write(to: url)
        }
    }
}
