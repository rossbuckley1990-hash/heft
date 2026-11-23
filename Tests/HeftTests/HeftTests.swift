import XCTest
@testable import HeftCore

final class HeftTests: XCTestCase {

    private func makeTempDir() throws -> URL {
        let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".heft-cones-tests-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    func testSetLookupStaysTitaniumWhileArrayScanTriggersCastLead() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("Engine.swift")

        // 1. O(1) Set<Int> lookup inside loop -> Titanium (low mass, zero fracture)
        try """
        public func sumClean(values: [Int]) -> Int {
            let skip: Set<Int> = [0, -1]
            var acc = 0
            for v in values {
                if skip.contains(v) { continue }
                acc += v
            }
            return acc
        }
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let analyzer = StructuralAnalyzer()
        let cleanSnap = analyzer.analyzeWorkspace(at: dir.path)
        XCTAssertEqual(cleanSnap.stress.fracture, 0.0)
        XCTAssertLessThan(cleanSnap.stress.mass, 0.25)
        XCTAssertEqual(cleanSnap.stress.material, .titanium)

        // 2. O(n^2) Array `[Int]` linear scan inside loop -> Cast Lead
        try """
        public func sumHeavy(values: [Int]) -> Int {
            let skip: [Int] = [0, -1]
            var acc = 0
            for v in values {
                if skip.contains(v) { continue }
                acc += v
            }
            return acc
        }
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let heavySnap = analyzer.analyzeWorkspace(at: dir.path)
        XCTAssertGreaterThanOrEqual(heavySnap.stress.mass, 0.70)
        XCTAssertEqual(heavySnap.stress.material, .castLead)
    }

    func testCrossFileContractFractureAndCounterfactualAutoRepairViaRenameSwap() throws {
        let root = try makeTempDir()
        let workspace = root.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let billingURL = workspace.appendingPathComponent("Billing.swift")
        let checkoutURL = workspace.appendingPathComponent("Checkout.swift")
        let auditURL = workspace.appendingPathComponent("Audit.swift")

        try """
        public func computeTotal(cents: [Int], taxBP: Int) -> Int {
            return cents.reduce(0, +) + taxBP
        }
        """.write(to: billingURL, atomically: true, encoding: .utf8)

        try """
        public func runCheckout() -> Int {
            return computeTotal(cents: [100, 200], taxBP: 50)
        }
        """.write(to: checkoutURL, atomically: true, encoding: .utf8)

        try """
        public func runAudit() -> Int {
            return computeTotal(cents: [500], taxBP: 25)
        }
        """.write(to: auditURL, atomically: true, encoding: .utf8)

        let cone = try APFSLightCone(workspacePath: workspace.path)
        defer { cone.cleanupArena() }

        // Baseline: zero fracture, creates Crystallized Checkpoint #1.
        let initial = try cone.evaluateLightCone()
        XCTAssertEqual(initial.snapshot.stress.fracture, 0.0)
        XCTAssertTrue(initial.branches.contains { $0.kind == .crystallizedCheckpoint })

        // Break signature across 2 downstream files by adding two required parameters without defaults!
        try """
        public func computeTotal(cents: [Int], taxBP: Int, currency: String, retries: Int) -> Int {
            return cents.reduce(0, +) + taxBP + retries + currency.count
        }
        """.write(to: billingURL, atomically: true, encoding: .utf8)

        let fractured = try cone.evaluateLightCone()
        XCTAssertEqual(fractured.snapshot.stress.fracture, 1.0)
        XCTAssertEqual(fractured.snapshot.stress.material, .crackedCeramic)
        XCTAssertEqual(fractured.snapshot.fractures.count, 2)

        // Verify counterfactual `contractRepair` timeline was automatically cloned & verified at 0 fracture!
        guard let repairBranch = fractured.branches.first(where: { $0.kind == .contractRepair }) else {
            XCTFail("Expected APFSLightCone to synthesize a verified contractRepair branch")
            return
        }
        XCTAssertEqual(repairBranch.stress.fracture, 0.0)

        // Collapse repair timeline into live reality via kernel `RENAME_SWAP`!
        let receipt = try cone.swapTimeline(branchID: repairBranch.id)
        XCTAssertEqual(receipt.resultingStress.fracture, 0.0)
        XCTAssertTrue(receipt.swappedFiles.contains("Billing.swift"))

        let healedBilling = try String(contentsOf: billingURL, encoding: .utf8)
        XCTAssertTrue(healedBilling.contains("currency: String = \"\""))
        XCTAssertTrue(healedBilling.contains("retries: Int = 0"))

        // And verify RENAME_SWAP losslessness: swapping the same branch ID again restores the fractured version!
        let reverseReceipt = try cone.swapTimeline(branchID: repairBranch.id)
        XCTAssertEqual(reverseReceipt.resultingStress.fracture, 1.0)
    }

    func testModalSynthesizerStaysInsideHaasWindowAndShiftsSpectralCentroid() {
        var synth = ModalSynthesizer(sampleRate: 48_000.0, gainDB: -12.0)

        // 1. Titanium impulse must decay completely to 0.0 before 12 ms (576 samples @ 48 kHz).
        synth.triggerKeyImpact(stress: StressVector(mass: 0.05, tension: 0.1, fracture: 0.0))
        let tiSamples = synth.renderBuffer(frameCount: 700)
        let tiTailEnergy = tiSamples[576..<700].map { $0 * $0 }.reduce(0, +)
        XCTAssertEqual(tiTailEnergy, 0.0, accuracy: 1e-7, "Modal tail must terminate inside the 12 ms Haas fusion window")
        let tiZeroCrossings = countZeroCrossings(Array(tiSamples[0..<240]))

        // 2. Cast Lead impulse must shift fundamental pitch downward (fewer zero crossings in 5 ms window).
        synth.triggerKeyImpact(stress: StressVector(mass: 0.90, tension: 0.1, fracture: 0.0))
        let leadSamples = synth.renderBuffer(frameCount: 700)
        let leadTailEnergy = leadSamples[576..<700].map { $0 * $0 }.reduce(0, +)
        XCTAssertEqual(leadTailEnergy, 0.0, accuracy: 1e-7)
        let leadZeroCrossings = countZeroCrossings(Array(leadSamples[0..<240]))

        XCTAssertLessThan(leadZeroCrossings, tiZeroCrossings / 2, "Cast Lead must exhibit markedly lower modal frequency than Titanium")
    }

    func testSpatialGratingIntegratorRequiresPhysicalMotionNotTime() {
        var integrator = SpatialGratingIntegrator()
        let fractured = StressVector(mass: 0.1, tension: 0.2, fracture: 1.0)
        let clean = StressVector.zero

        // Stationary finger (dx=0, dy=0) never emits vibration regardless of elapsed time.
        XCTAssertNil(integrator.advance(dx: 0, dy: 0, stress: fractured, nowNanoseconds: 100_000_000))
        XCTAssertNil(integrator.advance(dx: 0, dy: 0, stress: fractured, nowNanoseconds: 900_000_000))

        // Clean titanium emits zero pulses even across large cursor motion.
        XCTAssertNil(integrator.advance(dx: 200, dy: 0, stress: clean, nowNanoseconds: 1_000_000_000))

        // Fractured ceramic emits `.fractureGrit` once travel exceeds ~5.5 pt wavelength.
        let pulse = integrator.advance(dx: 7.0, dy: 0, stress: fractured, nowNanoseconds: 1_100_000_000)
        XCTAssertEqual(pulse, .fractureGrit)
    }

    func testSwiftControlConditionBraceIsNotMiscountedAsTrailingClosure() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try """
        public func isReady(flag: Bool) -> Bool {
            return flag
        }
        public func check() -> Int {
            if isReady(flag: true) {
                return 1
            }
            return 0
        }
        """.write(to: dir.appendingPathComponent("Check.swift"), atomically: true, encoding: .utf8)

        let snap = StructuralAnalyzer().analyzeWorkspace(at: dir.path)
        XCTAssertEqual(snap.stress.fracture, 0.0)
        XCTAssertTrue(snap.fractures.isEmpty)
    }

    private func countZeroCrossings(_ samples: [Float]) -> Int {
        guard samples.count > 1 else { return 0 }
        var crossings = 0
        for i in 1..<samples.count {
            if (samples[i - 1] >= 0 && samples[i] < 0) || (samples[i - 1] < 0 && samples[i] >= 0) {
                crossings += 1
            }
        }
        return crossings
    }
}
