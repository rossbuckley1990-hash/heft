# heft

**Give digital work physical weight, friction, and resonance on Apple Silicon Macs.**

When your car tires hit black ice, you don't read a popup window on the windshield—you **feel** the steering wheel go light in your hands before your brain can form words. When a knife hits a hidden knot in wood, you **feel** resistance before the blade snaps.

Software threw away 500,000 years of human sensorimotor intuition. On a laptop, typing a subtle mistake that breaks two sibling files or turns a fast `O(n)` loop into an `O(n²)` bottleneck *feels* identical under your fingers to writing clean code. You only find out later by reading walls of text.

**`heft`** implements **Causal Impedance** for macOS: it wires zero-copy APFS future sandboxes (`clonefile`) directly into sub-4ms Haas-window keycap psychoacoustics, distance-indexed Force Touch trackpad friction, and atomic `RENAME_SWAP` reality collapse—turning your MacBook into a physical instrument you can *feel* while you work.

---

## What It Feels Like

| Material State | Triggered By | Under Your Fingers (Trackpad) | Inside Your Keystrokes (`< 10 ms` Haas Fusion) |
| :--- | :--- | :--- | :--- |
| **Machined Titanium** | Clean contracts, `O(1)`/`O(n)` paths, decoupled modules | Frictionless glass glide; zero resistance | Crisp, weightless `2.8–8.9 kHz` titanium transient |
| **Tensioned Spring Steel** | High cross-file blast radius (many external callers) | Subtle `26–36 pt` tension ticks | Stretched upper harmonics warning of tight coupling |
| **Dense Cast Lead** | `O(n²)` nested scans, blocking I/O or regex inside loops | Heavy inertial scroll drag + `15–24 pt` viscous detents | Downward-gliding `420 Hz` damped thud—heavy code *feels* heavy |
| **Fractured Ceramic** | Broken cross-file function contracts, syntax faults, failing shadow checks | Sharp `5.5–9.5 pt` micro-fracture grit over the fault line | Split, beating eigenmodes + `2.6 ms` micro-crack scatter |

> [!NOTE]
> **Why you don't hear "computer sound effects":** Because `heft` renders modal decays inside a `64-frame` (`~1.33 ms`) CoreAudio HAL buffer and terminates every impulse in `< 10 ms`, it lands inside the human auditory cortex's **Haas Precedence (Temporal Ventriloquism) window (`< 12 ms`)**. Your brain perceptually fuses the harmonic decay into the physical scissor-switch click of the keycap you just struck.

---

## How It Works (Zero Dependencies, Pure Darwin + Apple Silicon)

1. **Zero-Copy APFS Future Light-Cones (`clonefile`)**
   Every edit forks your workspace into an adjacent Copy-on-Write APFS arena using Darwin's `clonefile(2)` syscall in microseconds (`0` disk bytes copied for unchanged blocks). Shadow verification and static cross-file stress analysis run inside the clone without ever locking or dirtying your working tree.
2. **4D Structural Stress Tensor (`Mass`, `Tension`, `Fracture`, `Coherence`)**
   Computes per-line physical impedance across Swift, Python, TypeScript/JavaScript, Rust, Go, C/C++, and JSON—distinguishing `O(1)` `Set`/`HashSet`/`Dictionary` lookups from `O(n²)` linear scans inside loops, mapping cross-file blast radius, and catching cross-file arity/signature fractures instantly.
3. **Path-Integral Trackpad Tribology (`∫ |ds| ≥ λ`)**
   Drives the Force Touch Taptic Engine strictly as a function of physical cursor travel distance `ds`, never wall-clock time. Hold your finger still and vibration is zero—glide across a fractured contract and feel `5.5 pt` ceramic grit right on the fault line.
4. **Force-Depth Z-Axis Peel & Atomic `RENAME_SWAP` Collapse**
   When invariants fracture, `heft` automatically synthesizes and verifies counterfactual timelines (such as backward-compatible default parameter contracts alongside your last **Crystallized Checkpoint**) in parallel APFS clones. Deep-pressing (**Stage 2 Force Touch**, or `⌘⏎`) peels open the Z-axis deck; sliding sideways collapses the verified timeline into your live directory via kernel-atomic `renameatx_np(..., RENAME_SWAP)` in `< 1 ms`—100% lossless and instantaneously reversible.

---

## Quickstart

Requires macOS 14+ with Swift 6+ (Xcode or Command Line Tools). Zero external dependencies.

```bash
git clone https://github.com/rossbuckley1990-hash/heft.git
cd heft
swift build -c release
```

### 1. Launch the Interactive Force-Touch Workbench (`heft studio`)

```bash
./.build/release/heft
```

Launching `heft` with no arguments opens the native AppKit **Causal Impedance Workbench** + Menu Bar HUD pre-loaded with a 3-file interactive Swift playground (`OrderEngine.swift`, `CheckoutController.swift`, `BatchReconciler.swift`):
- Click **`1 · Clean Titanium`**, **`2 · Inject O(n²) Lead`**, and **`3 · Fracture Contract`** (or edit any line directly) while typing and gliding across lines to feel the keyboard and trackpad material shift in real time.
- **Force-press (Stage 2)** into the trackpad (or press `⌘⏎` / `⌥-Click` on an external mouse) to peel open the live counterfactual APFS branches and **Atomic `RENAME_SWAP`** back to green in microseconds.

You can also open the Workbench directly on any repository:

```bash
./.build/release/heft studio /path/to/your/repo --cmd "swift test"
```

### 2. Watch Any Repo Alongside Cursor, VS Code, Xcode, or Neovim

```bash
./.build/release/heft watch /path/to/your/repo --cmd "pytest -q" --global-keys
```

Watches your project in real time, spawns zero-copy APFS shadow clones on every save, synthesizes counterfactual repair timelines when contracts fracture, and plays subtle crystallization locks when broken states snap back to green.

### 3. Scan Physical Heft Hotspots (`heft scan`)

```bash
./.build/release/heft scan /path/to/your/repo
```

Outputs the 4D Structural Stress Tensor (`Mass`, `Tension`, `Fracture`, `Coherence`) and ranks the heaviest, highest-blast-radius lines in your codebase (pass `--json` for machine output or `--strict` to fail CI on fractures).

### 4. Lossless Reality Swap from Terminal (`heft swap`)

```bash
./.build/release/heft swap /path/to/your/repo --list
./.build/release/heft swap /path/to/your/repo
```

Atomically swaps your live files with the highest-coherence APFS counterfactual timeline via `RENAME_SWAP`. Because `RENAME_SWAP` exchanges both trees in kernel metadata without deleting either, running `heft swap` again immediately reverses the swap.

### 5. Benchmark Your Mac's Sensorimotor Loop (`heft bench`)

```bash
./.build/release/heft bench
```

Measures real APFS `clonefile()` latency, `RENAME_SWAP` latency, CoreAudio HAL buffer latency against the `12.0 ms` human Haas fusion limit, and Stress Tensor scan throughput on your hardware:

```text
╭──────────────────────────────────────────────────────────────────────╮
│ HEFT · HARDWARE & KERNEL CAUSAL IMPEDANCE BENCHMARK                  │
╰──────────────────────────────────────────────────────────────────────╯
  APFS `clonefile()` Workspace Fork :  117 µs median  ( 159 µs p95, 0 bytes copied)
  Kernel `RENAME_SWAP` Collapse     :   41 µs median  (  44 µs p95, atomic)
  CoreAudio HAL I/O Buffer          :   64 frames @ 48000 Hz = 1.33 ms
  Human Haas Ventriloquism Limit    : 12.0 ms  →  PASS (perceptually fused into keycap)
  Stress Tensor Throughput          : 68912 µs (3673 lines → 53299 lines/sec)
```

---

## License

MIT
