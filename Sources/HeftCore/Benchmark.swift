import Foundation
import Darwin

public struct PhysicsBenchmarkReport: Codable, Sendable {
    public let cloneMedianMicroseconds: UInt64
    public let cloneP95Microseconds: UInt64
    public let swapMedianMicroseconds: UInt64
    public let swapP95Microseconds: UInt64
    public let audioSampleRateHz: Double
    public let audioBufferFrames: UInt32
    public let audioBufferLatencyMs: Double
    public let haasFusionLimitMs: Double
    public let withinHaasWindow: Bool
    public let tensorScanMicroseconds: UInt64
    public let scannedLineCount: Int
    public let linesPerSecond: Int
}

public enum PhysicsBenchmark {
    public static let haasWindowThresholdMs: Double = 12.0

    public static func run(targetPath: String? = nil) throws -> PhysicsBenchmarkReport {
        let tempRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".heft-cones-bench-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.removeItem(at: tempRoot)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        // Seed a realistic multi-file synthetic tree on the active APFS volume.
        let seedDir = tempRoot.appendingPathComponent("seed")
        try FileManager.default.createDirectory(at: seedDir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        for i in 0..<12 {
            let content = """
            import Foundation
            public struct Module\(i) {
                public static func compute(items: [Int], blocked: [Int]) -> Int {
                    var total = 0
                    for x in items {
                        if blocked.contains(x) { continue }
                        total += x * \(i + 1)
                    }
                    return total
                }
            }
            """
            try content.write(
                to: seedDir.appendingPathComponent("Sources/Module\(i).swift"),
                atomically: true,
                encoding: .utf8
            )
        }

        // 1. Measure 25 APFS `clonefile()` full-directory forks.
        var cloneSamples: [UInt64] = []
        for i in 0..<25 {
            let dst = tempRoot.appendingPathComponent("cone-\(i)").path
            let micros = try APFSLightCone.apfsClone(from: seedDir.path, to: dst)
            cloneSamples.append(micros)
        }
        cloneSamples.sort()

        // 2. Measure 40 kernel-atomic `renameatx_np(..., RENAME_SWAP)` reality collapses.
        let fileA = tempRoot.appendingPathComponent("swapA.swift")
        let fileB = tempRoot.appendingPathComponent("swapB.swift")
        try "func timelineA() -> Int { return 1 }\n".write(to: fileA, atomically: true, encoding: .utf8)
        try "func timelineB() -> Int { return 2 }\n".write(to: fileB, atomically: true, encoding: .utf8)

        var swapSamples: [UInt64] = []
        for _ in 0..<40 {
            let t0 = StructuralAnalyzer.monotonicNanoseconds()
            let rc = renameatx_np(AT_FDCWD, fileA.path, AT_FDCWD, fileB.path, UInt32(RENAME_SWAP))
            let elapsed = (StructuralAnalyzer.monotonicNanoseconds() - t0) / 1_000
            if rc == 0 {
                swapSamples.append(max(1, elapsed))
            }
        }
        swapSamples.sort()

        // 3. Measure CoreAudio HAL low-latency buffer vs 12 ms Haas precedence window.
        let audio = ModalAudioEngine(gainDB: -60.0)
        _ = audio.start()
        let sr = audio.hardwareSampleRate
        let frames = audio.hardwareBufferFrames
        let latencyMs = audio.bufferLatencyMilliseconds
        audio.stop()

        // 4. Measure Structural Stress Tensor scan speed on `targetPath` (or `seedDir`).
        let scanTarget = targetPath ?? seedDir.path
        let analyzer = StructuralAnalyzer()
        let snap = analyzer.analyzeWorkspace(at: scanTarget)
        let totalLines = max(1, snap.files.map(\.lineCount).reduce(0, +))
        let secs = max(0.000_001, Double(snap.analysisMicroseconds) / 1_000_000.0)
        let lps = Int(Double(totalLines) / secs)

        return PhysicsBenchmarkReport(
            cloneMedianMicroseconds: percentile(cloneSamples, p: 0.50),
            cloneP95Microseconds: percentile(cloneSamples, p: 0.95),
            swapMedianMicroseconds: percentile(swapSamples, p: 0.50),
            swapP95Microseconds: percentile(swapSamples, p: 0.95),
            audioSampleRateHz: sr,
            audioBufferFrames: frames,
            audioBufferLatencyMs: latencyMs,
            haasFusionLimitMs: Self.haasWindowThresholdMs,
            withinHaasWindow: latencyMs < Self.haasWindowThresholdMs,
            tensorScanMicroseconds: snap.analysisMicroseconds,
            scannedLineCount: totalLines,
            linesPerSecond: lps
        )
    }

    private static func percentile(_ sorted: [UInt64], p: Double) -> UInt64 {
        guard !sorted.isEmpty else { return 0 }
        let idx = min(sorted.count - 1, max(0, Int(Double(sorted.count - 1) * p)))
        return sorted[idx]
    }
}
