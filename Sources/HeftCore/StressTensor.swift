import Foundation

/// Physical material state perceived through Haas-window modal acoustics and trackpad tribology.
public enum MaterialState: String, Codable, CaseIterable, Sendable {
    /// Clean, decoupled, linear complexity, zero broken invariants.
    case titanium = "Machined Titanium"
    /// Clean invariants, but high cross-file blast radius — edits pull on many consumers.
    case tautSteel = "Tensioned Spring Steel"
    /// Quadratic loops, deep nesting, blocking I/O in loops, or heavy runtime regression.
    case castLead = "Dense Cast Lead"
    /// Broken cross-file symbol contract, unbalanced syntax, or failing shadow verification.
    case crackedCeramic = "Fractured Ceramic"

    public var shortLabel: String {
        switch self {
        case .titanium: return "TITANIUM"
        case .tautSteel: return "TAUT STEEL"
        case .castLead: return "CAST LEAD"
        case .crackedCeramic: return "FRACTURED"
        }
    }

    public var tactileDescription: String {
        switch self {
        case .titanium:
            return "Frictionless glass glide; crisp 2.8–6.9 kHz titanium keycap resonance"
        case .tautSteel:
            return "Fine tension detents; stretched harmonic overtones across coupled files"
        case .castLead:
            return "Heavy cursor viscosity; damped low-mass 420 Hz thud under keystrokes"
        case .crackedCeramic:
            return "Sharp 6pt fracture grit on trackpad; split inharmonic ceramic rattle"
        }
    }
}

/// Real-time 4D structural stress vector for a line, file, or workspace.
public struct StressVector: Codable, Equatable, Sendable {
    /// Algorithmic & runtime weight in [0, 1] (e.g. O(n^2) inner scans, deep loop nesting, latency spike).
    public var mass: Double
    /// Cross-file coupling & blast radius in [0, 1] (external callers and shared state consumers).
    public var tension: Double
    /// Contract, syntax, or shadow-execution breakage in [0, 1].
    public var fracture: Double
    /// Overall structural integrity in [0, 1].
    public var coherence: Double

    public init(mass: Double = 0, tension: Double = 0, fracture: Double = 0) {
        let m = Self.clamp(mass)
        let t = Self.clamp(tension)
        let f = Self.clamp(fracture)
        self.mass = m
        self.tension = t
        self.fracture = f
        let dragPenalty = 0.45 * m + 0.20 * t
        self.coherence = Self.clamp(1.0 - max(f, dragPenalty))
    }

    public var material: MaterialState {
        if fracture >= 0.25 {
            return .crackedCeramic
        }
        if mass >= 0.50 {
            return .castLead
        }
        if tension >= 0.50 {
            return .tautSteel
        }
        return .titanium
    }

    /// Composite physical heft score used to rank hotspots.
    public var compositeHeft: Double {
        Self.clamp(0.50 * fracture + 0.32 * mass + 0.18 * tension)
    }

    public static let zero = StressVector(mass: 0, tension: 0, fracture: 0)

    @inline(__always)
    public static func clamp(_ value: Double) -> Double {
        if value.isNaN { return 0 }
        return min(1.0, max(0.0, value))
    }
}

/// Downstream location affected by a high-tension or fractured line.
public struct FaultTarget: Codable, Equatable, Sendable {
    public let relativeFile: String
    public let line: Int
    public let symbol: String
    public let detail: String

    public init(relativeFile: String, line: Int, symbol: String, detail: String) {
        self.relativeFile = relativeFile
        self.line = line
        self.symbol = symbol
        self.detail = detail
    }
}

/// Per-line physical impedance profile inside a source file.
public struct LineImpedance: Codable, Equatable, Sendable {
    public let line: Int
    public let stress: StressVector
    public let reasons: [String]
    public let faultTargets: [FaultTarget]

    public init(
        line: Int,
        stress: StressVector,
        reasons: [String] = [],
        faultTargets: [FaultTarget] = []
    ) {
        self.line = line
        self.stress = stress
        self.reasons = reasons
        self.faultTargets = faultTargets
    }
}

/// Stress report for a single file in the workspace.
public struct FileStressReport: Codable, Equatable, Sendable {
    public let relativePath: String
    public let lineCount: Int
    public let stress: StressVector
    public let hotspots: [LineImpedance]

    public init(
        relativePath: String,
        lineCount: Int,
        stress: StressVector,
        hotspots: [LineImpedance]
    ) {
        self.relativePath = relativePath
        self.lineCount = lineCount
        self.stress = stress
        self.hotspots = hotspots
    }

    public func impedance(atLine oneBasedLine: Int) -> LineImpedance? {
        hotspots.first { $0.line == oneBasedLine }
    }
}

/// Full workspace structural stress tensor snapshot.
public struct WorkspaceStressSnapshot: Codable, Equatable, Sendable {
    public let rootPath: String
    public let timestamp: Date
    public let analysisMicroseconds: UInt64
    public let stress: StressVector
    public let files: [FileStressReport]
    public let fractures: [FaultTarget]

    public init(
        rootPath: String,
        timestamp: Date = Date(),
        analysisMicroseconds: UInt64,
        stress: StressVector,
        files: [FileStressReport],
        fractures: [FaultTarget]
    ) {
        self.rootPath = rootPath
        self.timestamp = timestamp
        self.analysisMicroseconds = analysisMicroseconds
        self.stress = stress
        self.files = files
        self.fractures = fractures
    }
}

/// File diff preview inside a counterfactual APFS timeline.
public struct FileDelta: Codable, Equatable, Sendable {
    public let relativePath: String
    public let summary: String
    public let previewBefore: String
    public let previewAfter: String

    public init(relativePath: String, summary: String, previewBefore: String, previewAfter: String) {
        self.relativePath = relativePath
        self.summary = summary
        self.previewBefore = previewBefore
        self.previewAfter = previewAfter
    }
}

public enum TimelineKind: String, Codable, Sendable {
    case presentShadow = "Present Shadow"
    case contractRepair = "Contract Auto-Repair"
    case complexityRelief = "Linear O(n) Relief"
    case crystallizedCheckpoint = "Crystallized Checkpoint"
}

/// An executed parallel reality backed by a real zero-copy APFS `clonefile` directory.
public struct CounterfactualBranch: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: TimelineKind
    public let title: String
    public let explanation: String
    public let conePath: String
    public let createdAt: Date
    public let cloneMicroseconds: UInt64
    public let verifyMilliseconds: Double
    public let commandExitCode: Int32?
    public let commandOutputSnippet: String?
    public let stress: StressVector
    public let deltas: [FileDelta]

    public init(
        id: String,
        kind: TimelineKind,
        title: String,
        explanation: String,
        conePath: String,
        createdAt: Date = Date(),
        cloneMicroseconds: UInt64,
        verifyMilliseconds: Double,
        commandExitCode: Int32? = nil,
        commandOutputSnippet: String? = nil,
        stress: StressVector,
        deltas: [FileDelta] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.explanation = explanation
        self.conePath = conePath
        self.createdAt = createdAt
        self.cloneMicroseconds = cloneMicroseconds
        self.verifyMilliseconds = verifyMilliseconds
        self.commandExitCode = commandExitCode
        self.commandOutputSnippet = commandOutputSnippet
        self.stress = stress
        self.deltas = deltas
    }
}

/// Receipt returned when collapsing a counterfactual branch into live reality via `RENAME_SWAP`.
public struct SwapReceipt: Codable, Equatable, Sendable {
    public let branchID: String
    public let branchTitle: String
    public let swappedFiles: [String]
    public let swapMicroseconds: UInt64
    public let resultingStress: StressVector

    public init(
        branchID: String,
        branchTitle: String,
        swappedFiles: [String],
        swapMicroseconds: UInt64,
        resultingStress: StressVector
    ) {
        self.branchID = branchID
        self.branchTitle = branchTitle
        self.swappedFiles = swappedFiles
        self.swapMicroseconds = swapMicroseconds
        self.resultingStress = resultingStress
    }
}
