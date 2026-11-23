import Foundation
import AppKit
import HeftCore

@main
struct HeftMain {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        let subcommand = args.first ?? "studio"

        switch subcommand {
        case "-h", "--help", "help":
            printUsage()
        case "-v", "--version", "version":
            print("heft 0.1.0 — Causal Impedance for Apple Silicon Macs")
        case "scan":
            runScan(args: Array(args.dropFirst()))
        case "bench":
            runBench(args: Array(args.dropFirst()))
        case "watch":
            WatchCommand.run(args: Array(args.dropFirst()))
        case "swap":
            runSwap(args: Array(args.dropFirst()))
        case "studio":
            runStudio(args: Array(args.dropFirst()))
        default:
            // If user passes a directory directly (`heft ./my-repo`), open Studio on that directory.
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: subcommand, isDirectory: &isDir), isDir.boolValue {
                runStudio(args: args)
            } else {
                fputs("Unknown subcommand '\(subcommand)'. Run `heft --help` for usage.\n", stderr)
                exit(2)
            }
        }
    }

    private static func runScan(args: [String]) {
        var targetPath = FileManager.default.currentDirectoryPath
        var asJSON = false
        var strict = false
        var evaluateCones = false
        var verifyCmd: String? = nil

        var i = 0
        while i < args.count {
            switch args[i] {
            case "--json":
                asJSON = true
            case "--strict":
                strict = true
            case "--cone":
                evaluateCones = true
            case "--cmd":
                if i + 1 < args.count {
                    verifyCmd = args[i + 1]
                    i += 1
                }
            default:
                if !args[i].hasPrefix("-") {
                    targetPath = args[i]
                }
            }
            i += 1
        }

        let snapshot: WorkspaceStressSnapshot
        var branches: [CounterfactualBranch] = []

        if evaluateCones || verifyCmd != nil {
            do {
                let cone = try APFSLightCone(workspacePath: targetPath, verificationCommand: verifyCmd)
                let res = try cone.evaluateLightCone()
                snapshot = res.snapshot
                branches = res.branches
            } catch {
                fputs("heft scan error: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        } else {
            let analyzer = StructuralAnalyzer()
            snapshot = analyzer.analyzeWorkspace(at: targetPath)
        }

        if asJSON {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(snapshot), let out = String(data: data, encoding: .utf8) {
                print(out)
            }
        } else {
            renderHumanScan(snapshot: snapshot, branches: branches)
        }

        if strict && snapshot.stress.fracture >= 0.25 {
            exit(1)
        }
    }

    private static func renderHumanScan(snapshot: WorkspaceStressSnapshot, branches: [CounterfactualBranch]) {
        let s = snapshot.stress
        print("╭──────────────────────────────────────────────────────────────────────╮")
        print("│ HEFT · STRUCTURAL STRESS TENSOR                                      │")
        print("╰──────────────────────────────────────────────────────────────────────╯")
        print("  Workspace : \(snapshot.rootPath)")
        print("  Material  : \(s.material.rawValue) [\(s.material.shortLabel)]")
        print("  Feel      : \(s.material.tactileDescription)")
        print(String(format: "  Scan Time : %llu µs across %d source file(s)", snapshot.analysisMicroseconds, snapshot.files.count))
        print("")
        print("  Mass      \(bar(s.mass))  \(pct(s.mass))  (algorithmic & loop weight)")
        print("  Tension   \(bar(s.tension))  \(pct(s.tension))  (cross-file blast radius)")
        print("  Fracture  \(bar(s.fracture))  \(pct(s.fracture))  (contract / syntax breakage)")
        print("  Coherence \(bar(s.coherence))  \(pct(s.coherence))  (structural integrity)")

        let rankedHotspots = snapshot.files
            .flatMap { file in file.hotspots.map { (file.relativePath, $0) } }
            .sorted { $0.1.stress.compositeHeft > $1.1.stress.compositeHeft }

        if !rankedHotspots.isEmpty {
            print("\n  Top Physical Impedance Hotspots:")
            for (relPath, hs) in rankedHotspots.prefix(8) {
                let tag = hs.stress.material.shortLabel
                let reason = hs.reasons.first ?? ""
                print(String(format: "    • [%@] %@:%d  (M:%@ T:%@ F:%@)", tag, relPath, hs.line, pct(hs.stress.mass), pct(hs.stress.tension), pct(hs.stress.fracture)))
                if !reason.isEmpty {
                    print("      └─ \(reason)")
                }
                for target in hs.faultTargets.prefix(3) {
                    print("         ↳ \(target.relativeFile):\(target.line) — \(target.detail)")
                }
            }
        } else {
            print("\n  No high-impedance hotspots detected. Workspace glides cleanly.")
        }

        if !branches.isEmpty {
            print("\n  Warm APFS Counterfactual Timelines (`heft swap` ready):")
            for b in branches.prefix(4) {
                print("    • [\(b.id)] \(b.title) — \(b.stress.material.shortLabel) (cloned in \(b.cloneMicroseconds) µs)")
                for d in b.deltas.prefix(2) {
                    print("      └─ \(d.relativePath): \(d.summary)")
                }
            }
        }
    }

    private static func runBench(args: [String]) {
        var targetPath: String? = nil
        var asJSON = false
        for arg in args {
            if arg == "--json" { asJSON = true }
            else if !arg.hasPrefix("-") { targetPath = arg }
        }

        do {
            let report = try PhysicsBenchmark.run(targetPath: targetPath)
            if asJSON {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let data = try? encoder.encode(report), let s = String(data: data, encoding: .utf8) {
                    print(s)
                }
                return
            }

            print("╭──────────────────────────────────────────────────────────────────────╮")
            print("│ HEFT · HARDWARE & KERNEL CAUSAL IMPEDANCE BENCHMARK                  │")
            print("╰──────────────────────────────────────────────────────────────────────╯")
            print(String(format: "  APFS `clonefile()` Workspace Fork : %4llu µs median  (%4llu µs p95, 0 bytes copied)", report.cloneMedianMicroseconds, report.cloneP95Microseconds))
            print(String(format: "  Kernel `RENAME_SWAP` Collapse     : %4llu µs median  (%4llu µs p95, atomic)", report.swapMedianMicroseconds, report.swapP95Microseconds))
            print(String(format: "  CoreAudio HAL I/O Buffer          : %4u frames @ %.0f Hz = %.2f ms", report.audioBufferFrames, report.audioSampleRateHz, report.audioBufferLatencyMs))
            print(String(format: "  Human Haas Ventriloquism Limit    : %.1f ms  →  %@", report.haasFusionLimitMs, report.withinHaasWindow ? "PASS (perceptually fused into keycap)" : "EXCEEDED"))
            print(String(format: "  Stress Tensor Throughput          : %llu µs (%d lines → %d lines/sec)", report.tensorScanMicroseconds, report.scannedLineCount, report.linesPerSecond))
        } catch {
            fputs("heft bench error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func runSwap(args: [String]) {
        var targetPath = FileManager.default.currentDirectoryPath
        var listOnly = false
        var requestedID: String? = nil

        var i = 0
        while i < args.count {
            switch args[i] {
            case "--list", "-l":
                listOnly = true
            case "--timeline", "-t":
                if i + 1 < args.count {
                    requestedID = args[i + 1]
                    i += 1
                }
            default:
                if !args[i].hasPrefix("-") {
                    targetPath = args[i]
                }
            }
            i += 1
        }

        do {
            let cone = try APFSLightCone(workspacePath: targetPath)
            var available = cone.currentBranches()
            if available.isEmpty {
                available = try cone.evaluateLightCone().branches
            }

            if listOnly {
                if available.isEmpty {
                    print("No counterfactual APFS timelines recorded yet for \(cone.workspaceURL.path).")
                    print("Run `heft scan --cone` or `heft watch` first to seed checkpoints.")
                    return
                }
                print("Available APFS Counterfactual Timelines for \(cone.workspaceURL.path):")
                for b in available {
                    print("  • \(b.id)  [\(b.kind.rawValue)]  \(b.title) — \(b.stress.material.shortLabel)")
                    for d in b.deltas {
                        print("      \(d.relativePath): \(d.previewBefore)  →  \(d.previewAfter)")
                    }
                }
                return
            }

            let chosen = requestedID != nil
                ? available.first { $0.id == requestedID }
                : (available.first { $0.kind == .contractRepair } ?? available.first)

            guard let branch = chosen else {
                fputs("No counterfactual timeline found to swap. Run `heft swap --list` to inspect.\n", stderr)
                exit(1)
            }

            let receipt = try cone.swapTimeline(branchID: branch.id)
            print("⚡ Atomic RENAME_SWAP complete in \(receipt.swapMicroseconds) µs")
            print("   Timeline : [\(receipt.branchID)] \(receipt.branchTitle)")
            print("   Swapped  : \(receipt.swappedFiles.isEmpty ? "(already identical)" : receipt.swappedFiles.joined(separator: ", "))")
            print("   Material : \(receipt.resultingStress.material.rawValue) (Coherence \(pct(receipt.resultingStress.coherence)))")
        } catch {
            fputs("heft swap error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func runStudio(args: [String]) {
        var workspacePath: String? = nil
        var verifyCmd: String? = nil
        var gainDB: Double = -30.0

        var i = 0
        while i < args.count {
            switch args[i] {
            case "--cmd":
                if i + 1 < args.count {
                    verifyCmd = args[i + 1]
                    i += 1
                }
            case "--gain":
                if i + 1 < args.count, let g = Double(args[i + 1]) {
                    gainDB = g
                    i += 1
                }
            default:
                if !args[i].hasPrefix("-") {
                    workspacePath = args[i]
                }
            }
            i += 1
        }

        MainActor.assumeIsolated {
            StudioLauncher.launch(workspacePath: workspacePath, verificationCommand: verifyCmd, gainDB: gainDB)
        }
    }

    public static func bar(_ value: Double, width: Int = 18) -> String {
        let clamped = StressVector.clamp(value)
        let filled = Int((clamped * Double(width)).rounded())
        return "[" + String(repeating: "█", count: filled) + String(repeating: "░", count: max(0, width - filled)) + "]"
    }

    public static func pct(_ value: Double) -> String {
        String(format: "%3.0f%%", StressVector.clamp(value) * 100.0)
    }

    private static func printUsage() {
        print("""
        heft — Causal Impedance for Apple Silicon Macs
        Give digital work physical weight, friction, and resonance before things break.

        USAGE:
          heft [studio] [path] [--cmd "<verify>"] [--gain -30]
              Launch the native Force-Touch Z-Axis Workbench & Menu Bar HUD.
              (Creates an interactive 3-file sandbox if no path is given.)

          heft scan [path] [--cone] [--cmd "<verify>"] [--json] [--strict]
              Compute the 4D Structural Stress Tensor (Mass, Tension, Fracture, Coherence)
              and rank physical impedance hotspots across your codebase.

          heft watch [path] [--cmd "<verify>"] [--gain -30] [--global-keys]
              Watch a directory in real time while you edit in Cursor, VS Code, Xcode, or Neovim.
              Spawns zero-copy APFS `clonefile` sandboxes on every save and drives live modal audio.

          heft swap [path] [--list] [--timeline <id>]
              Atomically collapse a verified APFS counterfactual timeline into your live tree
              using Darwin `renameatx_np(..., RENAME_SWAP)` in < 1 ms (lossless & reversible).

          heft bench [path] [--json]
              Measure APFS `clonefile()` latency, `RENAME_SWAP` latency, CoreAudio Haas fusion
              margin, and Stress Tensor scan speed on this Mac.
        """)
    }
}
