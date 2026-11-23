import Foundation
import Darwin

/// Declaration metadata discovered during workspace symbol indexing.
public struct SymbolContract: Sendable {
    public let name: String
    public let relativeFile: String
    public let line: Int
    public let rawLine: String
    public let minArgs: Int
    public let maxArgs: Int
    public let parameterSlices: [String]
    public let language: String
}

/// Cross-file or local invocation site.
struct CallSite: Sendable {
    let name: String
    let receiver: String?
    let relativeFile: String
    let line: Int
    let rawLine: String
    let argCount: Int
}

/// Zero-dependency static structural, algorithmic mass, coupling tension, and contract fracture analyzer.
public final class StructuralAnalyzer: Sendable {
    public static let supportedExtensions: Set<String> = [
        "swift", "py", "ts", "tsx", "js", "jsx", "rs", "go", "c", "cc", "cpp", "h", "json"
    ]

    public static let ignoredDirectories: Set<String> = [
        ".git", ".build", "node_modules", "DerivedData", ".swiftpm",
        "__pycache__", ".venv", "venv", "target", "dist", "build"
    ]

    private static let polymorphicSDKMethodNames: Set<String> = [
        "draw", "start", "stop", "run", "update", "reset", "close", "open",
        "read", "write", "encode", "decode", "copy", "clone", "contains", "append"
    ]

    private static let controlKeywords: Set<String> = [
        "if", "for", "while", "switch", "catch", "guard", "return", "sizeof",
        "typeof", "match", "loop", "func", "def", "fn", "function", "init",
        "print", "debugPrint", "assert", "precondition", "fatalError", "len",
        "range", "min", "max", "abs", "sum", "Array", "Set", "Dictionary", "String", "Int", "Double"
    ]

    public init() {}

    public func analyzeWorkspace(at rootPath: String) -> WorkspaceStressSnapshot {
        let t0 = Self.monotonicNanoseconds()
        let rootURL = URL(fileURLWithPath: rootPath).standardizedFileURL
        let sourceFiles = collectSourceFiles(under: rootURL)

        var fileLines: [String: [String]] = [:]
        var declarations: [String: [SymbolContract]] = [:]
        var allCallSites: [CallSite] = []

        for url in sourceFiles {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let rel = relativePath(of: url, from: rootURL)
            let lines = content.components(separatedBy: .newlines)
            fileLines[rel] = lines

            let ext = url.pathExtension.lowercased()
            if ext == "json" { continue }

            let fileContracts = extractContracts(lines: lines, relativeFile: rel, ext: ext)
            for c in fileContracts {
                declarations[c.name, default: []].append(c)
            }
            let calls = extractCallSites(lines: lines, relativeFile: rel, ext: ext)
            allCallSites.append(contentsOf: calls)
        }

        // Map symbol -> external call sites and arity mismatches.
        var externalConsumersBySymbol: [String: [CallSite]] = [:]
        var contractFracturesByDefKey: [String: [FaultTarget]] = [:]
        var callSiteFracturesByLineKey: [String: [FaultTarget]] = [:]
        var globalFractures: [FaultTarget] = []

        for call in allCallSites {
            guard let defs = declarations[call.name], !defs.isEmpty else { continue }
            for def in defs where def.relativeFile != call.relativeFile {
                externalConsumersBySymbol[call.name, default: []].append(call)
            }

            // Only flag signature arity fracture when there is an unambiguous single function contract
            // in the workspace and it isn't a dot-call onto a polymorphic SDK method (like `NSString.draw`).
            if let recv = call.receiver, recv != "self" && recv != "Self", Self.polymorphicSDKMethodNames.contains(call.name) {
                continue
            }
            let acceptsArity = defs.contains { call.argCount >= $0.minArgs && call.argCount <= $0.maxArgs }
            if !acceptsArity, defs.count == 1, let soleDef = defs.first {
                let expectedDesc = soleDef.minArgs == soleDef.maxArgs
                    ? "\(soleDef.minArgs)"
                    : "\(soleDef.minArgs)...\(soleDef.maxArgs)"
                let targetAtCall = FaultTarget(
                    relativeFile: call.relativeFile,
                    line: call.line,
                    symbol: call.name,
                    detail: "Call passes \(call.argCount) arg(s), but `\(soleDef.name)` in \(soleDef.relativeFile):\(soleDef.line) expects \(expectedDesc)"
                )
                let defKey = "\(soleDef.relativeFile):\(soleDef.line)"
                contractFracturesByDefKey[defKey, default: []].append(targetAtCall)

                let callKey = "\(call.relativeFile):\(call.line)"
                let targetAtDef = FaultTarget(
                    relativeFile: soleDef.relativeFile,
                    line: soleDef.line,
                    symbol: soleDef.name,
                    detail: "Broken contract with `\(soleDef.name)` (\(soleDef.relativeFile):\(soleDef.line) expects \(expectedDesc) arg(s), got \(call.argCount))"
                )
                callSiteFracturesByLineKey[callKey, default: []].append(targetAtDef)
                globalFractures.append(targetAtCall)
            }
        }

        var fileReports: [FileStressReport] = []
        for rel in fileLines.keys.sorted() {
            guard let lines = fileLines[rel] else { continue }
            let ext = URL(fileURLWithPath: rel).pathExtension.lowercased()
            let report = analyzeFile(
                relativePath: rel,
                lines: lines,
                ext: ext,
                declarations: declarations,
                externalConsumersBySymbol: externalConsumersBySymbol,
                contractFracturesByDefKey: contractFracturesByDefKey,
                callSiteFracturesByLineKey: callSiteFracturesByLineKey,
                globalFractures: &globalFractures
            )
            fileReports.append(report)
        }

        let maxFracture = fileReports.map(\.stress.fracture).max() ?? 0
        let peakMass = fileReports.map(\.stress.mass).max() ?? 0
        let meanMass = fileReports.isEmpty ? 0 : fileReports.map(\.stress.mass).reduce(0, +) / Double(fileReports.count)
        let peakTension = fileReports.map(\.stress.tension).max() ?? 0

        let workspaceStress = StressVector(
            mass: 0.72 * peakMass + 0.28 * meanMass,
            tension: peakTension,
            fracture: maxFracture
        )

        let elapsedMicros = (Self.monotonicNanoseconds() - t0) / 1_000
        return WorkspaceStressSnapshot(
            rootPath: rootURL.path,
            analysisMicroseconds: elapsedMicros,
            stress: workspaceStress,
            files: fileReports,
            fractures: globalFractures
        )
    }

    /// Exposes discovered unambiguous symbol fractures so counterfactual repair cones can synthesize safe fixes.
    public func discoverBrokenContracts(at rootPath: String) -> [(contract: SymbolContract, minCallerArgs: Int, brokenCalls: [FaultTarget])] {
        let rootURL = URL(fileURLWithPath: rootPath).standardizedFileURL
        let sourceFiles = collectSourceFiles(under: rootURL)
        var declarations: [String: [SymbolContract]] = [:]
        var allCallSites: [CallSite] = []

        for url in sourceFiles {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let rel = relativePath(of: url, from: rootURL)
            let lines = content.components(separatedBy: .newlines)
            let ext = url.pathExtension.lowercased()
            if ext == "json" { continue }
            for c in extractContracts(lines: lines, relativeFile: rel, ext: ext) {
                declarations[c.name, default: []].append(c)
            }
            allCallSites.append(contentsOf: extractCallSites(lines: lines, relativeFile: rel, ext: ext))
        }

        var results: [(SymbolContract, Int, [FaultTarget])] = []
        for (name, defs) in declarations where defs.count == 1 {
            let def = defs[0]
            var broken: [FaultTarget] = []
            var observedCounts: [Int] = []
            for call in allCallSites where call.name == name {
                if let recv = call.receiver, recv != "self" && recv != "Self", Self.polymorphicSDKMethodNames.contains(call.name) {
                    continue
                }
                if call.argCount < def.minArgs || call.argCount > def.maxArgs {
                    observedCounts.append(call.argCount)
                    broken.append(
                        FaultTarget(
                            relativeFile: call.relativeFile,
                            line: call.line,
                            symbol: name,
                            detail: "Passes \(call.argCount) arg(s); signature requires \(def.minArgs)...\(def.maxArgs)"
                        )
                    )
                }
            }
            if !broken.isEmpty, let minSeen = observedCounts.min() {
                results.append((def, minSeen, broken))
            }
        }
        return results
    }

    // MARK: - File-Level Impedance Pass

    private func analyzeFile(
        relativePath: String,
        lines: [String],
        ext: String,
        declarations: [String: [SymbolContract]],
        externalConsumersBySymbol: [String: [CallSite]],
        contractFracturesByDefKey: [String: [FaultTarget]],
        callSiteFracturesByLineKey: [String: [FaultTarget]],
        globalFractures: inout [FaultTarget]
    ) -> FileStressReport {
        if ext == "json" {
            let joined = lines.joined(separator: "\n")
            if let data = joined.data(using: .utf8) {
                do {
                    _ = try JSONSerialization.jsonObject(with: data)
                    let s = StressVector(mass: min(0.25, Double(lines.count) / 4000.0), tension: 0.05, fracture: 0)
                    return FileStressReport(relativePath: relativePath, lineCount: lines.count, stress: s, hotspots: [])
                } catch {
                    let fault = FaultTarget(
                        relativeFile: relativePath,
                        line: 1,
                        symbol: "JSON",
                        detail: "Malformed JSON payload: \(error.localizedDescription)"
                    )
                    globalFractures.append(fault)
                    let hotspot = LineImpedance(
                        line: 1,
                        stress: StressVector(mass: 0.1, tension: 0.2, fracture: 1.0),
                        reasons: ["Invalid JSON syntax"],
                        faultTargets: [fault]
                    )
                    return FileStressReport(
                        relativePath: relativePath,
                        lineCount: lines.count,
                        stress: hotspot.stress,
                        hotspots: [hotspot]
                    )
                }
            }
        }

        var hotspots: [LineImpedance] = []
        var braceDepth = 0
        var loopBraceStack: [Int] = []
        var pythonLoopIndents: [Int] = []
        var inBlockComment = false
        var unbalancedLine: Int? = nil
        var lastNonEmptyLine = max(1, lines.count)

        let fileDefs = declarations.values.flatMap { $0 }.filter { $0.relativeFile == relativePath }
        var defByLine: [Int: SymbolContract] = [:]
        for d in fileDefs { defByLine[d.line] = d }
        let hashedIdentifiers = collectHashedContainerIdentifiers(lines: lines, ext: ext)

        for (idx, raw) in lines.enumerated() {
            let lineNum = idx + 1
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { lastNonEmptyLine = lineNum }

            var reasons: [String] = []
            var targets: [FaultTarget] = []
            var lineMass = 0.0
            var lineTension = 0.0
            var lineFracture = 0.0

            // Merge conflict markers are immediate fractures.
            if trimmed.hasPrefix("<<<<<<<") || trimmed.hasPrefix(">>>>>>>") || trimmed == "=======" {
                lineFracture = 1.0
                reasons.append("Unresolved merge conflict marker")
                let fault = FaultTarget(relativeFile: relativePath, line: lineNum, symbol: "conflict", detail: "Unresolved git conflict marker")
                targets.append(fault)
                globalFractures.append(fault)
            }

            let clean = stripCommentsAndStrings(from: raw, ext: ext, inBlockComment: &inBlockComment)
            let cleanTrimmed = clean.trimmingCharacters(in: .whitespaces)

            // Track Python indentation-scoped loops vs brace-scoped loops.
            let activeLoopDepth: Int
            if ext == "py" {
                if !cleanTrimmed.isEmpty {
                    let indent = raw.prefix { $0 == " " || $0 == "\t" }.count
                    while let last = pythonLoopIndents.last, indent <= last {
                        pythonLoopIndents.removeLast()
                    }
                    if isLoopHeader(cleanTrimmed, ext: ext) {
                        pythonLoopIndents.append(indent)
                    }
                }
                activeLoopDepth = pythonLoopIndents.count
            } else {
                let startsLoop = isLoopHeader(cleanTrimmed, ext: ext)
                var openBraces = 0
                var closeBraces = 0
                for ch in clean {
                    if ch == "{" { openBraces += 1 }
                    else if ch == "}" { closeBraces += 1 }
                }
                if startsLoop && openBraces > 0 {
                    loopBraceStack.append(braceDepth + 1)
                }
                braceDepth += openBraces - closeBraces
                if braceDepth < 0 && unbalancedLine == nil {
                    unbalancedLine = lineNum
                }
                while let threshold = loopBraceStack.last, braceDepth < threshold {
                    loopBraceStack.removeLast()
                }
                activeLoopDepth = loopBraceStack.count + (startsLoop && openBraces == 0 ? 1 : 0)
            }

            // 1. Algorithmic Mass: nested loops + hidden linear lookups inside loops (O(n^2) traps).
            if activeLoopDepth >= 2 {
                let nestedMass = min(0.95, 0.58 + Double(activeLoopDepth - 2) * 0.20)
                lineMass = max(lineMass, nestedMass)
                reasons.append("Nested loop depth \(activeLoopDepth) (O(n^\(activeLoopDepth)) multiplicative scaling)")
            }
            if activeLoopDepth >= 1 && hasInnerLinearScan(cleanTrimmed, ext: ext, hashedVars: hashedIdentifiers) {
                let scanMass = min(0.96, 0.72 + Double(activeLoopDepth - 1) * 0.14)
                lineMass = max(lineMass, scanMass)
                reasons.append("Quadratic O(n^2) trap: linear collection scan inside active loop")
            }
            if activeLoopDepth >= 1 && hasExpensiveAllocationInLoop(cleanTrimmed) {
                lineMass = max(lineMass, 0.68)
                reasons.append("Repeated heavy I/O or regex compilation inside active loop")
            }

            // 2. Coupling Tension: symbol blast radius across sibling files + shared mutable state.
            if let def = defByLine[lineNum] {
                let consumers = externalConsumersBySymbol[def.name] ?? []
                if !consumers.isEmpty {
                    let uniqueFiles = Set(consumers.map(\.relativeFile)).count
                    lineTension = max(lineTension, min(0.95, 0.28 + Double(consumers.count) * 0.14 + Double(uniqueFiles) * 0.10))
                    reasons.append("Coupled across \(consumers.count) external callsite(s) in \(uniqueFiles) file(s)")
                    for c in consumers.prefix(6) {
                        targets.append(
                            FaultTarget(
                                relativeFile: c.relativeFile,
                                line: c.line,
                                symbol: def.name,
                                detail: c.rawLine.trimmingCharacters(in: .whitespaces)
                            )
                        )
                    }
                }
            }
            if cleanTrimmed.contains("nonisolated(unsafe)") || cleanTrimmed.hasPrefix("global ") {
                lineTension = max(lineTension, 0.62)
                reasons.append("Shared unsynchronized mutable state increases blast radius")
            }

            // 3. Contract Fractures at either definition or broken callsite.
            let lineKey = "\(relativePath):\(lineNum)"
            if let defFaults = contractFracturesByDefKey[lineKey] {
                lineFracture = 1.0
                reasons.append("Signature change broke \(defFaults.count) downstream callsite(s)")
                targets.append(contentsOf: defFaults)
            }
            if let callFaults = callSiteFracturesByLineKey[lineKey] {
                lineFracture = 1.0
                reasons.append("Callsite signature mismatch against upstream declaration")
                targets.append(contentsOf: callFaults)
            }

            if lineMass > 0.05 || lineTension > 0.05 || lineFracture > 0.05 {
                hotspots.append(
                    LineImpedance(
                        line: lineNum,
                        stress: StressVector(mass: lineMass, tension: lineTension, fracture: lineFracture),
                        reasons: reasons,
                        faultTargets: targets
                    )
                )
            }
        }

        // Check unbalanced braces/delimiters at EOF (for brace-scoped languages).
        if ext != "py" && (braceDepth != 0 || unbalancedLine != nil || inBlockComment) {
            let faultLine = unbalancedLine ?? lastNonEmptyLine
            let detail = inBlockComment
                ? "Unterminated block comment `/*`"
                : "Unbalanced `{` / `}` delimiter (net delta \(braceDepth))"
            let fault = FaultTarget(relativeFile: relativePath, line: faultLine, symbol: "syntax", detail: detail)
            globalFractures.append(fault)
            hotspots.append(
                LineImpedance(
                    line: faultLine,
                    stress: StressVector(mass: 0.15, tension: 0.25, fracture: 1.0),
                    reasons: [detail],
                    faultTargets: [fault]
                )
            )
        }

        let peakMass = hotspots.map(\.stress.mass).max() ?? 0
        let peakTension = hotspots.map(\.stress.tension).max() ?? 0
        let peakFracture = hotspots.map(\.stress.fracture).max() ?? 0

        return FileStressReport(
            relativePath: relativePath,
            lineCount: lines.count,
            stress: StressVector(mass: peakMass, tension: peakTension, fracture: peakFracture),
            hotspots: hotspots.sorted { $0.stress.compositeHeft > $1.stress.compositeHeft }
        )
    }

    // MARK: - Lightweight Multi-Language Contract & Callsite Extraction

    private func extractContracts(lines: [String], relativeFile: String, ext: String) -> [SymbolContract] {
        var contracts: [SymbolContract] = []
        var inBlock = false

        var idx = 0
        while idx < lines.count {
            let raw = lines[idx]
            let clean = stripCommentsAndStrings(from: raw, ext: ext, inBlockComment: &inBlock)
            let trimmed = clean.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                idx += 1
                continue
            }

            // Join continuation lines if a declaration header opens `(` across multiple lines.
            var joinedRaw = raw
            if trimmed.contains("(") && !trimmed.contains(")") {
                var lookahead = idx + 1
                while lookahead < min(lines.count, idx + 14) {
                    joinedRaw += " " + lines[lookahead].trimmingCharacters(in: .whitespaces)
                    if lines[lookahead].contains(")") { break }
                    lookahead += 1
                }
            }

            if let parsed = parseFunctionDeclaration(trimmed: trimmed, rawLine: joinedRaw, ext: ext) {
                contracts.append(
                    SymbolContract(
                        name: parsed.name,
                        relativeFile: relativeFile,
                        line: idx + 1,
                        rawLine: raw,
                        minArgs: parsed.minArgs,
                        maxArgs: parsed.maxArgs,
                        parameterSlices: parsed.slices,
                        language: ext
                    )
                )
            }
            idx += 1
        }
        return contracts
    }

    private func parseFunctionDeclaration(
        trimmed: String,
        rawLine: String,
        ext: String
    ) -> (name: String, minArgs: Int, maxArgs: Int, slices: [String])? {
        // Match `func foo(...)`, `def foo(...)`, `fn foo(...)`, `function foo(...)`
        let keywords = ["func ", "def ", "fn ", "function "]
        var matchedKeyword: String?
        var afterKeyword: Substring?

        for kw in keywords {
            if let range = trimmed.range(of: kw) {
                let prefix = trimmed[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                let validPrefix = prefix.isEmpty || prefix.split(separator: " ").allSatisfy { token in
                    ["public", "private", "internal", "fileprivate", "open", "static", "class",
                     "mutating", "nonmutating", "override", "async", "export", "default", "pub",
                     "unsafe", "const", "@MainActor", "@Sendable", "@inline(__always)"].contains(String(token))
                }
                if validPrefix {
                    matchedKeyword = kw
                    afterKeyword = trimmed[range.upperBound...]
                    break
                }
            }
        }

        guard matchedKeyword != nil, var rest = afterKeyword else { return nil }
        rest = rest.drop { $0 == " " }

        // Handle Go receiver methods `func (s *Server) Handle(...)`
        if ext == "go", rest.first == "(" {
            if let closeIdx = rest.firstIndex(of: ")") {
                rest = rest[rest.index(after: closeIdx)...].drop { $0 == " " }
            }
        }

        // Read identifier up to `<` or `(`
        let nameChars = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        let name = String(nameChars)
        guard !name.isEmpty, !Self.controlKeywords.contains(name) else { return nil }

        // Find parameter list parentheses `( ... )` on rawLine (skipping generic `<...>`)
        guard let nameRangeInRaw = rawLine.range(of: name) else { return nil }
        var cursor = nameRangeInRaw.upperBound
        var angleDepth = 0
        var openParen: String.Index? = nil
        while cursor < rawLine.endIndex {
            let c = rawLine[cursor]
            if c == "<" { angleDepth += 1 }
            else if c == ">" { angleDepth = max(0, angleDepth - 1) }
            else if c == "(" && angleDepth == 0 {
                openParen = cursor
                break
            }
            cursor = rawLine.index(after: cursor)
        }
        guard let startParen = openParen,
              let endParen = findMatchingParen(in: rawLine, from: startParen) else {
            return nil
        }

        let inside = String(rawLine[rawLine.index(after: startParen)..<endParen])
        var slices = splitTopLevelComma(inside)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Strip Python/Rust explicit receiver `self` / `&self` / `&mut self` / `cls`
        if let first = slices.first {
            let normalized = first.replacingOccurrences(of: "&mut ", with: "")
                .replacingOccurrences(of: "&", with: "")
                .trimmingCharacters(in: .whitespaces)
            if normalized == "self" || normalized == "cls" || normalized.hasPrefix("self:") {
                slices.removeFirst()
            }
        }

        var minArgs = 0
        var maxArgs = 0
        for param in slices {
            if param.contains("...") || param.hasPrefix("*") {
                maxArgs = 64
            } else if param.contains("=") {
                maxArgs += 1
            } else {
                minArgs += 1
                maxArgs += 1
            }
        }
        return (name, minArgs, maxArgs, slices)
    }

    private func extractCallSites(lines: [String], relativeFile: String, ext: String) -> [CallSite] {
        var calls: [CallSite] = []
        var inBlock = false

        for (idx, raw) in lines.enumerated() {
            let clean = stripCommentsAndStrings(from: raw, ext: ext, inBlockComment: &inBlock)
            let trimmed = clean.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Skip lines that declare a function themselves.
            let isDecl = parseFunctionDeclaration(trimmed: trimmed, rawLine: clean, ext: ext) != nil
            if isDecl { continue }

            let chars = Array(clean)
            var i = 0
            while i < chars.count {
                if chars[i].isLetter || chars[i] == "_" {
                    let start = i
                    while i < chars.count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") {
                        i += 1
                    }
                    let ident = String(chars[start..<i])
                    var j = i
                    while j < chars.count && chars[j] == " " { j += 1 }
                    if j < chars.count && chars[j] == "(", !Self.controlKeywords.contains(ident) {
                        if let closeIdx = findMatchingParenChars(chars, from: j) {
                            let argStr = String(chars[(j + 1)..<closeIdx]).trimmingCharacters(in: .whitespaces)
                            let args = argStr.isEmpty ? [] : splitTopLevelComma(argStr)

                            // Extract optional dot-receiver (`receiver.method(...)` or `receiver?.method(...)`)
                            var receiver: String? = nil
                            if start > 0 && chars[start - 1] == "." {
                                var rEnd = start - 1
                                if rEnd > 0 && chars[rEnd - 1] == "?" { rEnd -= 1 }
                                var rStart = rEnd
                                while rStart > 0 && (chars[rStart - 1].isLetter || chars[rStart - 1].isNumber || chars[rStart - 1] == "_") {
                                    rStart -= 1
                                }
                                if rStart < rEnd {
                                    receiver = String(chars[rStart..<rEnd])
                                } else {
                                    receiver = "."
                                }
                            }

                            calls.append(
                                CallSite(
                                    name: ident,
                                    receiver: receiver,
                                    relativeFile: relativeFile,
                                    line: idx + 1,
                                    rawLine: raw,
                                    argCount: args.count
                                )
                            )
                        }
                    }
                } else {
                    i += 1
                }
            }
        }
        return calls
    }

    // MARK: - Heuristics & String Utilities

    private func isLoopHeader(_ cleanTrimmed: String, ext: String) -> Bool {
        if cleanTrimmed.hasPrefix("for ") || cleanTrimmed.hasPrefix("for(") ||
            cleanTrimmed.hasPrefix("while ") || cleanTrimmed.hasPrefix("while(") ||
            cleanTrimmed.hasPrefix("loop {") || cleanTrimmed == "loop" {
            return true
        }
        if cleanTrimmed.contains(".forEach(") || cleanTrimmed.contains(".forEach {") {
            return true
        }
        return false
    }

    private func collectHashedContainerIdentifiers(lines: [String], ext: String) -> Set<String> {
        var names: Set<String> = []
        let markers = ["Set<", "Set(", "set(", "frozenset(", "HashSet", "BTreeSet", "Dictionary<", "HashMap", "Map("]
        for line in lines {
            guard markers.contains(where: { line.contains($0) }) else { continue }
            // Extract identifier before `:` or `=`
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let tokens = trimmed
                .replacingOccurrences(of: ":", with: " : ")
                .replacingOccurrences(of: "=", with: " = ")
                .split(separator: " ")
                .map(String.init)
            for idx in 0..<tokens.count {
                if (tokens[idx] == ":" || tokens[idx] == "="), idx > 0 {
                    let candidate = tokens[idx - 1]
                    if candidate.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
                        names.insert(candidate)
                    }
                    break
                }
            }
        }
        return names
    }

    private func hasInnerLinearScan(_ cleanTrimmed: String, ext: String, hashedVars: Set<String>) -> Bool {
        let unconditionalLinear = [
            ".contains {", ".first(where:", ".first {",
            ".last(where:", ".filter(", ".filter {", ".firstIndex(",
            ".indexOf(", ".includes(", ".find(", "SELECT ", "select "
        ]
        if unconditionalLinear.contains(where: { cleanTrimmed.contains($0) }) {
            return true
        }
        if let range = cleanTrimmed.range(of: ".contains(") {
            // Check receiver identifier immediately preceding `.contains(`
            let prefix = cleanTrimmed[..<range.lowerBound]
            let receiver = String(prefix.reversed().prefix { $0.isLetter || $0.isNumber || $0 == "_" }.reversed())
            if !receiver.isEmpty && hashedVars.contains(receiver) {
                return false // O(1) Set / HashSet / Dictionary lookup!
            }
            // Note: String.contains is typically short substring check; still avoid flagging quoted literals
            if prefix.hasSuffix("\"") { return false }
            return true
        }
        if ext == "py", let inRange = cleanTrimmed.range(of: " in "), !cleanTrimmed.hasPrefix("for ") {
            let after = cleanTrimmed[inRange.upperBound...].trimmingCharacters(in: .whitespaces)
            let container = String(after.prefix { $0.isLetter || $0.isNumber || $0 == "_" })
            if !container.isEmpty && hashedVars.contains(container) {
                return false
            }
            return true
        }
        return false
    }

    private func hasExpensiveAllocationInLoop(_ cleanTrimmed: String) -> Bool {
        let heavy = [
            "NSRegularExpression(", "try Regex(", "re.compile(",
            "Data(contentsOf:", "String(contentsOf", "FileManager.default.contents",
            "JSONDecoder()", "DateFormatter()"
        ]
        return heavy.contains { cleanTrimmed.contains($0) }
    }

    private func stripCommentsAndStrings(from line: String, ext: String, inBlockComment: inout Bool) -> String {
        var out = ""
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            if inBlockComment {
                if i + 1 < chars.count && chars[i] == "*" && chars[i + 1] == "/" {
                    inBlockComment = false
                    i += 2
                } else {
                    i += 1
                }
                continue
            }
            if ext == "py" && chars[i] == "#" {
                break
            }
            if ext != "py" && i + 1 < chars.count && chars[i] == "/" && chars[i + 1] == "/" {
                break
            }
            if ext != "py" && i + 1 < chars.count && chars[i] == "/" && chars[i + 1] == "*" {
                inBlockComment = true
                i += 2
                continue
            }
            if chars[i] == "\"" || chars[i] == "'" {
                let quote = chars[i]
                out.append(quote)
                out.append(quote)
                i += 1
                while i < chars.count {
                    if chars[i] == "\\" {
                        i += 2
                        continue
                    }
                    if chars[i] == quote {
                        i += 1
                        break
                    }
                    i += 1
                }
                continue
            }
            out.append(chars[i])
            i += 1
        }
        return out
    }

    private func findMatchingParen(in text: String, from openIdx: String.Index) -> String.Index? {
        var depth = 0
        var idx = openIdx
        while idx < text.endIndex {
            let c = text[idx]
            if c == "(" { depth += 1 }
            else if c == ")" {
                depth -= 1
                if depth == 0 { return idx }
            }
            idx = text.index(after: idx)
        }
        return nil
    }

    private func findMatchingParenChars(_ chars: [Character], from openIdx: Int) -> Int? {
        var depth = 0
        var i = openIdx
        while i < chars.count {
            if chars[i] == "(" { depth += 1 }
            else if chars[i] == ")" {
                depth -= 1
                if depth == 0 { return i }
            }
            i += 1
        }
        return nil
    }

    private func splitTopLevelComma(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        for ch in text {
            switch ch {
            case "(", "[", "{", "<":
                depth += 1
                current.append(ch)
            case ")", "]", "}", ">":
                depth = max(0, depth - 1)
                current.append(ch)
            case "," where depth == 0:
                parts.append(current)
                current = ""
            default:
                current.append(ch)
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(current)
        }
        return parts
    }

    public func collectSourceFiles(under rootURL: URL) -> [URL] {
        var results: [URL] = []
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsPackageDescendants]
        ) else {
            return results
        }

        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name.hasPrefix(".heft-cones") || Self.ignoredDirectories.contains(name) {
                enumerator.skipDescendants()
                continue
            }
            if name.hasPrefix(".") && name != ".gitignore" {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            let ext = url.pathExtension.lowercased()
            if Self.supportedExtensions.contains(ext) {
                results.append(url)
            }
        }
        return results
    }

    private func relativePath(of fileURL: URL, from rootURL: URL) -> String {
        let rootPrefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        let full = fileURL.standardizedFileURL.path
        if full.hasPrefix(rootPrefix) {
            return String(full.dropFirst(rootPrefix.count))
        }
        return fileURL.lastPathComponent
    }

    public static func monotonicNanoseconds() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    }
}
