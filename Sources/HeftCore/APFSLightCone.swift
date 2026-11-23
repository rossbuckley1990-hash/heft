import Foundation
import Darwin

public enum LightConeError: Error, LocalizedError {
    case workspaceMissing(String)
    case cloneFailed(errno: Int32, message: String)
    case branchNotFound(String)
    case swapFailed(errno: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case .workspaceMissing(let p):
            return "Workspace directory does not exist: \(p)"
        case .cloneFailed(let code, let msg):
            return "APFS clonefile() failed (\(code)): \(msg)"
        case .branchNotFound(let id):
            return "Counterfactual timeline '\(id)' not found"
        case .swapFailed(let code, let msg):
            return "Atomic RENAME_SWAP failed (\(code)): \(msg)"
        }
    }
}

/// Manages zero-copy APFS `clonefile()` counterfactual sandboxes and kernel-atomic `RENAME_SWAP` collapses.
public final class APFSLightCone: @unchecked Sendable {
    public let workspaceURL: URL
    public let arenaURL: URL
    public var verificationCommand: String?
    public var commandTimeoutSeconds: TimeInterval = 4.5

    private let analyzer = StructuralAnalyzer()
    private let lock = NSLock()
    private var branches: [CounterfactualBranch] = []
    private var maxCheckpoints = 5
    private var generationCounter: UInt64 = 0

    public init(workspacePath: String, verificationCommand: String? = nil) throws {
        let standardized = URL(fileURLWithPath: workspacePath).standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDir), isDir.boolValue else {
            throw LightConeError.workspaceMissing(standardized.path)
        }
        self.workspaceURL = standardized
        self.verificationCommand = verificationCommand

        // Place cone arena on the exact same APFS mount point (sibling directory) so
        // both `clonefile()` and `renameatx_np(..., RENAME_SWAP)` are guaranteed zero-copy & EXDEV-free.
        let parent = standardized.deletingLastPathComponent()
        let stableHash = Self.fnv1aHex(standardized.path)
        self.arenaURL = parent.appendingPathComponent(".heft-cones-\(standardized.lastPathComponent)-\(stableHash)")
        try FileManager.default.createDirectory(at: arenaURL, withIntermediateDirectories: true)
        self.loadManifestIfPresent()
    }

    private var manifestURL: URL {
        arenaURL.appendingPathComponent("manifest.json")
    }

    private func loadManifestIfPresent() {
        guard let data = try? Data(contentsOf: manifestURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let saved = try? decoder.decode([CounterfactualBranch].self, from: data) {
            self.branches = saved.filter { FileManager.default.fileExists(atPath: $0.conePath) }
            self.generationCounter = UInt64(self.branches.count)
        }
    }

    private func persistManifestLocked() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(branches) {
            try? data.write(to: manifestURL, options: .atomic)
        }
    }

    public func currentBranches() -> [CounterfactualBranch] {
        lock.lock()
        defer { lock.unlock() }
        return branches
    }

    /// Evaluates the live workspace inside zero-copy APFS sandboxes, records green checkpoints,
    /// and synthesizes verified counterfactual repair branches whenever invariants fracture.
    @discardableResult
    public func evaluateLightCone() throws -> (snapshot: WorkspaceStressSnapshot, branches: [CounterfactualBranch]) {
        lock.lock()
        generationCounter += 1
        let gen = generationCounter
        lock.unlock()

        // 1. Spawn zero-copy APFS shadow clone of the workspace.
        let presentConeURL = arenaURL.appendingPathComponent("present-\(gen)")
        try? FileManager.default.removeItem(at: presentConeURL)
        _ = try cloneWorkspace(to: presentConeURL)

        // 2. Run static structural & cross-file stress pass inside the isolated CoW clone.
        let verifyStart = StructuralAnalyzer.monotonicNanoseconds()
        var snapshot = analyzer.analyzeWorkspace(at: presentConeURL.path)

        // 3. Optionally execute user/project verification command inside the isolated CoW clone.
        var exitCode: Int32? = nil
        var snippet: String? = nil
        if let cmd = verificationCommand, !cmd.trimmingCharacters(in: .whitespaces).isEmpty {
            let result = runSandboxedCommand(cmd, cwd: presentConeURL, timeout: commandTimeoutSeconds)
            exitCode = result.exitCode
            snippet = result.outputSnippet
            if result.exitCode != 0 {
                let cmdFracture = StressVector(
                    mass: snapshot.stress.mass,
                    tension: snapshot.stress.tension,
                    fracture: 1.0
                )
                let cmdFault = FaultTarget(
                    relativeFile: "(verification)",
                    line: 1,
                    symbol: cmd,
                    detail: result.outputSnippet.isEmpty ? "Command exited with status \(result.exitCode)" : result.outputSnippet
                )
                snapshot = WorkspaceStressSnapshot(
                    rootPath: workspaceURL.path,
                    timestamp: snapshot.timestamp,
                    analysisMicroseconds: snapshot.analysisMicroseconds,
                    stress: cmdFracture,
                    files: snapshot.files,
                    fractures: snapshot.fractures + [cmdFault]
                )
            }
        } else {
            snapshot = WorkspaceStressSnapshot(
                rootPath: workspaceURL.path,
                timestamp: snapshot.timestamp,
                analysisMicroseconds: snapshot.analysisMicroseconds,
                stress: snapshot.stress,
                files: snapshot.files,
                fractures: snapshot.fractures
            )
        }
        let verifyMs = Double(StructuralAnalyzer.monotonicNanoseconds() - verifyStart) / 1_000_000.0

        var newCounterfactuals: [CounterfactualBranch] = []

        // 4. If present timeline is clean (zero fracture), promote a zero-copy Crystallized Checkpoint!
        if snapshot.stress.fracture < 0.20 && (exitCode == nil || exitCode == 0) {
            let checkpointID = "crystal-\(gen)"
            let checkpointURL = arenaURL.appendingPathComponent(checkpointID)
            try? FileManager.default.removeItem(at: checkpointURL)
            let cpMicros = try Self.apfsClone(from: presentConeURL.path, to: checkpointURL.path)
            let checkpointBranch = CounterfactualBranch(
                id: checkpointID,
                kind: .crystallizedCheckpoint,
                title: "Crystallized Checkpoint #\(gen)",
                explanation: "Verified zero-fracture APFS CoW snapshot (\(snapshot.stress.material.rawValue))",
                conePath: checkpointURL.path,
                cloneMicroseconds: cpMicros,
                verifyMilliseconds: verifyMs,
                commandExitCode: exitCode,
                commandOutputSnippet: snippet,
                stress: snapshot.stress,
                deltas: []
            )
            recordCheckpoint(checkpointBranch)
            try? FileManager.default.removeItem(at: presentConeURL)
        } else {
            // Present state is fractured! Synthesize counterfactual repair timelines in parallel APFS clones.
            if let repair = try synthesizeContractRepairBranch(
                fromCone: presentConeURL,
                generation: gen,
                baselineFracture: snapshot.stress.fracture
            ) {
                newCounterfactuals.append(repair)
            }
            try? FileManager.default.removeItem(at: presentConeURL)
        }

        // Refresh deltas on existing checkpoints relative to current live workspace so Z-axis peel shows exact diff.
        lock.lock()
        let preservedCheckpoints = branches
            .filter { $0.kind == .crystallizedCheckpoint }
            .map { cp -> CounterfactualBranch in
                let liveDeltas = computeDeltas(liveRoot: workspaceURL, coneRoot: URL(fileURLWithPath: cp.conePath))
                return CounterfactualBranch(
                    id: cp.id,
                    kind: cp.kind,
                    title: cp.title,
                    explanation: cp.explanation,
                    conePath: cp.conePath,
                    createdAt: cp.createdAt,
                    cloneMicroseconds: cp.cloneMicroseconds,
                    verifyMilliseconds: cp.verifyMilliseconds,
                    commandExitCode: cp.commandExitCode,
                    commandOutputSnippet: cp.commandOutputSnippet,
                    stress: cp.stress,
                    deltas: liveDeltas
                )
            }
        let combined = newCounterfactuals + preservedCheckpoints
        self.branches = combined
        self.persistManifestLocked()
        lock.unlock()

        return (snapshot, combined)
    }

    /// Atomically collapses a counterfactual APFS branch into the live workspace using Darwin `RENAME_SWAP`.
    /// Displaced files remain preserved inside the branch's cone directory, making every swap 100% lossless & reversible.
    @discardableResult
    public func swapTimeline(branchID: String) throws -> SwapReceipt {
        lock.lock()
        guard let branch = branches.first(where: { $0.id == branchID }) else {
            lock.unlock()
            throw LightConeError.branchNotFound(branchID)
        }
        lock.unlock()

        let coneURL = URL(fileURLWithPath: branch.conePath)
        let liveFiles = Set(analyzer.collectSourceFiles(under: workspaceURL).map { relativePath(of: $0, from: workspaceURL) })
        let coneFiles = Set(analyzer.collectSourceFiles(under: coneURL).map { relativePath(of: $0, from: coneURL) })
        let allRelPaths = liveFiles.union(coneFiles).sorted()

        var swappedPaths: [String] = []
        let t0 = StructuralAnalyzer.monotonicNanoseconds()

        for rel in allRelPaths {
            let liveFile = workspaceURL.appendingPathComponent(rel)
            let coneFile = coneURL.appendingPathComponent(rel)
            let liveExists = FileManager.default.fileExists(atPath: liveFile.path)
            let coneExists = FileManager.default.fileExists(atPath: coneFile.path)

            if liveExists && coneExists {
                let liveData = try? Data(contentsOf: liveFile)
                let coneData = try? Data(contentsOf: coneFile)
                if liveData == coneData { continue }

                let rc = renameatx_np(AT_FDCWD, liveFile.path, AT_FDCWD, coneFile.path, UInt32(RENAME_SWAP))
                if rc != 0 {
                    throw LightConeError.swapFailed(errno: errno, message: String(cString: strerror(errno)))
                }
                swappedPaths.append(rel)
            } else if !liveExists && coneExists {
                try FileManager.default.createDirectory(at: liveFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                _ = try Self.apfsClone(from: coneFile.path, to: liveFile.path)
                swappedPaths.append(rel)
            } else if liveExists && !coneExists {
                try FileManager.default.createDirectory(at: coneFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: liveFile, to: coneFile)
                swappedPaths.append(rel)
            }
        }

        let swapMicros = (StructuralAnalyzer.monotonicNanoseconds() - t0) / 1_000
        let postSnapshot = analyzer.analyzeWorkspace(at: workspaceURL.path)

        return SwapReceipt(
            branchID: branch.id,
            branchTitle: branch.title,
            swappedFiles: swappedPaths,
            swapMicroseconds: swapMicros,
            resultingStress: postSnapshot.stress
        )
    }

    public func cleanupArena() {
        try? FileManager.default.removeItem(at: arenaURL)
    }

    // MARK: - Counterfactual Synthesis

    private func synthesizeContractRepairBranch(
        fromCone sourceConeURL: URL,
        generation: UInt64,
        baselineFracture: Double
    ) throws -> CounterfactualBranch? {
        let broken = analyzer.discoverBrokenContracts(at: sourceConeURL.path)
        guard !broken.isEmpty else { return nil }

        let repairID = "repair-\(generation)"
        let repairURL = arenaURL.appendingPathComponent(repairID)
        try? FileManager.default.removeItem(at: repairURL)
        let cloneMicros = try Self.apfsClone(from: sourceConeURL.path, to: repairURL.path)

        var appliedDeltas: [FileDelta] = []

        for (contract, minCallerArgs, brokenCalls) in broken {
            // Case: Newly added trailing parameter(s) without default values broke existing callsites.
            guard contract.minArgs > minCallerArgs else { continue }
            let targetFileURL = repairURL.appendingPathComponent(contract.relativeFile)
            guard let text = try? String(contentsOf: targetFileURL, encoding: .utf8) else { continue }
            var lines = text.components(separatedBy: .newlines)
            let idx = contract.line - 1
            guard idx >= 0 && idx < lines.count else { continue }

            let originalLine = lines[idx]
            if let patchedLine = injectSafeDefaults(
                intoDeclarationLine: originalLine,
                language: contract.language,
                keepRequiredCount: minCallerArgs
            ), patchedLine != originalLine {
                lines[idx] = patchedLine
                try lines.joined(separator: "\n").write(to: targetFileURL, atomically: true, encoding: .utf8)
                appliedDeltas.append(
                    FileDelta(
                        relativePath: contract.relativeFile,
                        summary: "Added backward-compatible default parameter on `\(contract.name)` for \(brokenCalls.count) caller(s)",
                        previewBefore: originalLine.trimmingCharacters(in: .whitespaces),
                        previewAfter: patchedLine.trimmingCharacters(in: .whitespaces)
                    )
                )
            }
        }

        guard !appliedDeltas.isEmpty else {
            try? FileManager.default.removeItem(at: repairURL)
            return nil
        }

        let t0 = StructuralAnalyzer.monotonicNanoseconds()
        let verifySnap = analyzer.analyzeWorkspace(at: repairURL.path)
        var cmdExit: Int32? = nil
        var cmdOut: String? = nil
        if let cmd = verificationCommand, !cmd.trimmingCharacters(in: .whitespaces).isEmpty {
            let res = runSandboxedCommand(cmd, cwd: repairURL, timeout: commandTimeoutSeconds)
            cmdExit = res.exitCode
            cmdOut = res.outputSnippet
        }
        let verifyMs = Double(StructuralAnalyzer.monotonicNanoseconds() - t0) / 1_000_000.0

        // Only keep the counterfactual repair branch if it genuinely eliminates or reduces fracture!
        let commandPassed = (cmdExit == nil || cmdExit == 0)
        guard verifySnap.stress.fracture < baselineFracture && commandPassed else {
            try? FileManager.default.removeItem(at: repairURL)
            return nil
        }

        return CounterfactualBranch(
            id: repairID,
            kind: .contractRepair,
            title: "Default-Safe Contract Timeline",
            explanation: "Preserves your new logic while keeping downstream callers green via default parameter values",
            conePath: repairURL.path,
            cloneMicroseconds: cloneMicros,
            verifyMilliseconds: verifyMs,
            commandExitCode: cmdExit,
            commandOutputSnippet: cmdOut,
            stress: verifySnap.stress,
            deltas: appliedDeltas
        )
    }

    private func injectSafeDefaults(
        intoDeclarationLine line: String,
        language: String,
        keepRequiredCount: Int
    ) -> String? {
        guard let openParen = line.firstIndex(of: "("),
              let closeParen = line.lastIndex(of: ")"),
              openParen < closeParen else {
            return nil
        }
        let inside = String(line[line.index(after: openParen)..<closeParen])
        let rawParams = inside.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard !rawParams.isEmpty else { return nil }

        var nonSelfIndex = 0
        var rewritten: [String] = []

        for rawParam in rawParams {
            let trimmed = rawParam.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                rewritten.append(rawParam)
                continue
            }
            if trimmed == "self" || trimmed == "cls" || trimmed == "&self" || trimmed == "&mut self" {
                rewritten.append(rawParam)
                continue
            }
            if nonSelfIndex >= keepRequiredCount && !trimmed.contains("=") && !trimmed.contains("...") {
                let fallback = inferDefaultLiteral(forParameter: trimmed, language: language)
                rewritten.append("\(rawParam) = \(fallback)")
            } else {
                rewritten.append(rawParam)
            }
            nonSelfIndex += 1
        }

        let prefix = String(line[...openParen])
        let suffix = String(line[closeParen...])
        return prefix + rewritten.joined(separator: ",") + suffix
    }

    private func inferDefaultLiteral(forParameter param: String, language: String) -> String {
        let lower = param.lowercased()
        if param.hasSuffix("?") { return "nil" }
        if lower.contains("bool") || lower.contains("flag") || lower.contains("enabled") {
            return language == "py" ? "False" : "false"
        }
        if lower.contains("string") || lower.contains("str") || lower.contains("name") || lower.contains("label") {
            return "\"\""
        }
        if lower.contains("double") || lower.contains("float") || lower.contains("rate") || lower.contains("timeout") {
            return "0.0"
        }
        if lower.contains("[") { return "[]" }
        if language == "py" { return "None" }
        if language == "ts" || language == "js" || language == "tsx" || language == "jsx" { return "0" }
        return "0"
    }

    // MARK: - Low-Level APFS & Process Helpers

    private func cloneWorkspace(to destinationURL: URL) throws -> UInt64 {
        // Fast path: attempt full directory-tree APFS clonefile() directly.
        if let micros = try? Self.apfsClone(from: workspaceURL.path, to: destinationURL.path) {
            return micros
        }

        // Fallback selective top-level entry clonefile() if special socket/FIFO exists inside workspace.
        let t0 = StructuralAnalyzer.monotonicNanoseconds()
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        let items = try FileManager.default.contentsOfDirectory(atPath: workspaceURL.path)
        for item in items {
            if item == ".git" || item == ".build" || item == "node_modules" || item.hasPrefix(".heft-cones") {
                continue
            }
            let src = workspaceURL.appendingPathComponent(item).path
            let dst = destinationURL.appendingPathComponent(item).path
            _ = try Self.apfsClone(from: src, to: dst)
        }
        return (StructuralAnalyzer.monotonicNanoseconds() - t0) / 1_000
    }

    public static func apfsClone(from src: String, to dst: String) throws -> UInt64 {
        let t0 = StructuralAnalyzer.monotonicNanoseconds()
        let rc = clonefile(src, dst, 0)
        if rc != 0 {
            throw LightConeError.cloneFailed(errno: errno, message: String(cString: strerror(errno)))
        }
        return (StructuralAnalyzer.monotonicNanoseconds() - t0) / 1_000
    }

    private func recordCheckpoint(_ branch: CounterfactualBranch) {
        lock.lock()
        defer { lock.unlock() }
        var checkpoints = branches.filter { $0.kind == .crystallizedCheckpoint }
        checkpoints.insert(branch, at: 0)
        while checkpoints.count > maxCheckpoints {
            let evicted = checkpoints.removeLast()
            try? FileManager.default.removeItem(atPath: evicted.conePath)
        }
        let nonCheckpoints = branches.filter { $0.kind != .crystallizedCheckpoint }
        branches = nonCheckpoints + checkpoints
    }

    private func computeDeltas(liveRoot: URL, coneRoot: URL) -> [FileDelta] {
        let liveFiles = Set(analyzer.collectSourceFiles(under: liveRoot).map { relativePath(of: $0, from: liveRoot) })
        let coneFiles = Set(analyzer.collectSourceFiles(under: coneRoot).map { relativePath(of: $0, from: coneRoot) })
        var deltas: [FileDelta] = []

        for rel in liveFiles.union(coneFiles).sorted() {
            let liveText = (try? String(contentsOf: liveRoot.appendingPathComponent(rel), encoding: .utf8)) ?? ""
            let coneText = (try? String(contentsOf: coneRoot.appendingPathComponent(rel), encoding: .utf8)) ?? ""
            guard liveText != coneText else { continue }

            let liveLines = liveText.components(separatedBy: .newlines)
            let coneLines = coneText.components(separatedBy: .newlines)
            var diffIdx = 0
            while diffIdx < min(liveLines.count, coneLines.count) && liveLines[diffIdx] == coneLines[diffIdx] {
                diffIdx += 1
            }
            let before = diffIdx < liveLines.count ? liveLines[diffIdx].trimmingCharacters(in: .whitespaces) : "(added)"
            let after = diffIdx < coneLines.count ? coneLines[diffIdx].trimmingCharacters(in: .whitespaces) : "(removed)"
            deltas.append(
                FileDelta(
                    relativePath: rel,
                    summary: "Line \(diffIdx + 1) diverges from crystallized snapshot",
                    previewBefore: before,
                    previewAfter: after
                )
            )
        }
        return deltas
    }

    private func runSandboxedCommand(_ command: String, cwd: URL, timeout: TimeInterval) -> (exitCode: Int32, outputSnippet: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-c", command]
        proc.currentDirectoryURL = cwd

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        do {
            try proc.run()
        } catch {
            return (127, error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while proc.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.015)
        }
        if proc.isRunning {
            proc.terminate()
            return (124, "Shadow verification timed out after \(String(format: "%.1f", timeout))s")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let raw = String(data: data, encoding: .utf8) ?? ""
        let snippet = raw
            .split(whereSeparator: \.isNewline)
            .suffix(3)
            .joined(separator: " | ")
        return (proc.terminationStatus, String(snippet.prefix(220)))
    }

    private func relativePath(of fileURL: URL, from rootURL: URL) -> String {
        let rootPrefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        let full = fileURL.standardizedFileURL.path
        if full.hasPrefix(rootPrefix) {
            return String(full.dropFirst(rootPrefix.count))
        }
        return fileURL.lastPathComponent
    }

    private static func fnv1aHex(_ string: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%08llx", hash & 0xffff_ffff)
    }
}
