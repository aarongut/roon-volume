import Foundation
import VolumeCore

final class Helper {
    var onMessage: ((Data) -> Void)?
    var onExit: (() -> Void)?
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var stopping = false
    private var session = UUID()
    func start() throws {
        let resources = Bundle.main.resourceURL!
        let node = resources.appendingPathComponent("node")
        let script = resources.appendingPathComponent("helper/index.cjs")
        guard FileManager.default.isExecutableFile(atPath: node.path) else { throw NSError(domain: "Missing bundled runtime", code: 1) }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RoonVolume")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let p = Process(), stdin = Pipe(), stdout = Pipe()
        p.executableURL = node; p.arguments = [script.path, support.path]
        p.standardInput = stdin; p.standardOutput = stdout
        let log = support.appendingPathComponent("helper.log")
        // Keep the diagnostic file bounded between launches.
        try Data().write(to: log)
        p.standardError = try FileHandle(forWritingTo: log)
        self.input = stdin.fileHandleForWriting; self.process = p; stopping = false
        let session = UUID(); self.session = session
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async { guard self?.session == session else { return }; self?.receive(data) }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { guard let self, !self.stopping, self.session == session else { return }; self.input = nil; self.onExit?() }
        }
        try p.run()
    }
    private func receive(_ data: Data) {
        buffer.append(data)
        while let index = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<index]); buffer.removeSubrange(...index)
            onMessage?(line)
        }
        if buffer.count > 2_000_000 { buffer.removeAll() }
    }
    func send(_ message: [String: Any]) {
        guard let input, var data = try? JSONSerialization.data(withJSONObject: message) else { return }
        data.append(10)
        do { try input.write(contentsOf: data) } catch { onExit?() }
    }
    func stop() { stopping = true; session = UUID(); try? input?.close(); input = nil; process?.terminate(); process = nil; buffer.removeAll() }
}
