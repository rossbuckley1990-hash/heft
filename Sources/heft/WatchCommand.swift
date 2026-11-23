import Foundation
import AppKit
import CoreGraphics
import HeftCore

enum WatchCommand {
    static func run(args: [String]) {
        var targetPath = FileManager.default.currentDirectoryPath
        var verifyCmd: String? = nil
        var gainDB: Double = -30.0
        var globalKeys = false

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
            case "--global-keys":
                globalKeys = true
            default:
                if !args[i].hasPrefix("-") {
                    targetPath = args[i]
                }
            }
            i += 1
        }

        let cone: APFSLightCone
        do {
            cone = try APFSLightCone(workspacePath: targetPath, verificationCommand: verifyCmd)
        } catch {
            fputs("heft watch error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }

        let audio = ModalAudioEngine(gainDB: gainDB)
        let audioReady = audio.start()

        print("╭──────────────────────────────────────────────────────────────────────╮")
        print("│ HEFT · LIVE CAUSAL IMPEDANCE WATCHER                                 │")
        print("╰──────────────────────────────────────────────────────────────────────╯")
        print("  Watching  : \(cone.workspaceURL.path)")
        print("  APFS Cone : \(cone.arenaURL.path)")
        print(String(format: "  Audio HAL : %@", audioReady ? String(format: "%.2f ms buffer (<12 ms Haas fusion active)", audio.bufferLatencyMilliseconds) : "offline"))
        if let cmd = verifyCmd {
            print("  Shadow Cmd: `\(cmd)` (runs inside zero-copy APFS clonefile sandbox)")
        }
        print("  Press Ctrl+C to stop.\n")

        final class SharedState: @unchecked Sendable {
            let lock = NSLock()
            var latestStress: StressVector = .zero
            var previousFracture: Double = 0.0
            var lastDigest: UInt64 = 0
        }
        let state = SharedState()

        @Sendable func evaluateOnce(announceUnchanged: Bool) {
            let currentDigest = Self.workspaceDigest(under: cone.workspaceURL)
            state.lock.lock()
            let unchanged = (currentDigest == state.lastDigest && !announceUnchanged)
            if !unchanged { state.lastDigest = currentDigest }
            let prevFrac = state.previousFracture
            state.lock.unlock()

            if unchanged { return }

            guard let result = try? cone.evaluateLightCone() else { return }
            let stress = result.snapshot.stress

            state.lock.lock()
            state.latestStress = stress
            state.previousFracture = stress.fracture
            state.lock.unlock()

            if prevFrac >= 0.25 && stress.fracture < 0.25 {
                audio.triggerCrystallization()
            } else {
                audio.triggerKeystroke(stress: stress, keyCode: 36)
            }

            let timeStr = ISO8601DateFormatter().string(from: Date())
            print("[\(timeStr)] [\(stress.material.shortLabel)] M:\(HeftMain.pct(stress.mass)) T:\(HeftMain.pct(stress.tension)) F:\(HeftMain.pct(stress.fracture)) Coherence:\(HeftMain.pct(stress.coherence)) (\(result.snapshot.analysisMicroseconds) µs)")
            for fault in result.snapshot.fractures.prefix(3) {
                print("   ✦ Fracture: \(fault.relativeFile):\(fault.line) — \(fault.detail)")
            }
            if let repair = result.branches.first(where: { $0.kind == .contractRepair }) {
                print("   ⚡ Counterfactual ready: `heft swap --timeline \(repair.id)` (\(repair.title))")
            }
        }

        evaluateOnce(announceUnchanged: true)

        if globalKeys {
            let mask = (1 << CGEventType.keyDown.rawValue)
            if let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: CGEventMask(mask),
                callback: { _, type, event, userInfo in
                    guard type == .keyDown, let userInfo else {
                        return Unmanaged.passUnretained(event)
                    }
                    let box = Unmanaged<AnyObject>.fromOpaque(userInfo).takeUnretainedValue()
                    if let pair = box as? (SharedState, ModalAudioEngine) {
                        pair.0.lock.lock()
                        let s = pair.0.latestStress
                        pair.0.lock.unlock()
                        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                        pair.1.triggerKeystroke(stress: s, keyCode: code)
                    }
                    return Unmanaged.passUnretained(event)
                },
                userInfo: Unmanaged.passRetained((state, audio) as AnyObject).toOpaque()
            ) {
                let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
                print("  Global Keycap Resonance: ACTIVE (Haas-window synthesis across all apps)\n")
            } else {
                print("  Global Keycap Resonance: Input Monitoring not granted (save-triggered audio still active; use `heft studio` for zero-permission live typing).\n")
            }
        }

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + .milliseconds(220), repeating: .milliseconds(220))
        timer.setEventHandler {
            evaluateOnce(announceUnchanged: false)
        }
        timer.resume()

        RunLoop.main.run()
    }

    private static func workspaceDigest(under rootURL: URL) -> UInt64 {
        let analyzer = StructuralAnalyzer()
        let files = analyzer.collectSourceFiles(under: rootURL).sorted { $0.path < $1.path }
        var hash: UInt64 = 0xcbf29ce484222325
        for file in files {
            for b in file.path.utf8 {
                hash ^= UInt64(b)
                hash &*= 0x100000001b3
            }
            if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path) {
                if let size = attrs[.size] as? UInt64 {
                    hash ^= size
                    hash &*= 0x100000001b3
                }
                if let mtime = attrs[.modificationDate] as? Date {
                    let nanos = UInt64(mtime.timeIntervalSince1970 * 1_000_000)
                    hash ^= nanos
                    hash &*= 0x100000001b3
                }
            }
        }
        return hash
    }
}
