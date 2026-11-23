import Foundation
import AppKit

/// Tactile pulse emitted by the path-integral trackpad tribology model.
public enum TactilePulseKind: String, Equatable, Sendable {
    case fractureGrit
    case viscousMassDetent
    case tensionWireDetent
    case crystallizationSnap
}

/// Pure spatial-grating physics model (`∫ |ds| >= λ(stress)`).
/// Because pulses are indexed strictly to cursor travel distance `ds` rather than wall-clock time,
/// stationary fingers feel zero vibration (just like real sandpaper, glass, or machined detents).
public struct SpatialGratingIntegrator: Sendable {
    public private(set) var accumulatedDistancePoints: Double = 0.0
    public private(set) var lastPulseNanoseconds: UInt64 = 0
    /// Minimum 12 ms spacing (~83 Hz ceiling) keeps Taptic linear actuator crisp without muddiness.
    public var minInterPulseNanoseconds: UInt64 = 12_000_000

    public init() {}

    /// Computes grating wavelength `λ` in screen points for a given `StressVector`, or `nil` for frictionless glass.
    public static func wavelengthPoints(for stress: StressVector) -> (wavelength: Double, kind: TactilePulseKind)? {
        if stress.fracture >= 0.25 {
            // Fine, sharp micro-grit: 5.5 pt to 9.5 pt spacing depending on fracture severity.
            let w = 9.5 - 4.0 * StressVector.clamp(stress.fracture)
            return (w, .fractureGrit)
        }
        if stress.mass >= 0.50 {
            // Dense mechanical detents: 15 pt to 24 pt spacing.
            let w = 24.0 - 9.0 * StressVector.clamp(stress.mass)
            return (w, .viscousMassDetent)
        }
        if stress.tension >= 0.50 {
            // Subtle wire tension ticks: 26 pt to 36 pt spacing.
            let w = 36.0 - 10.0 * StressVector.clamp(stress.tension)
            return (w, .tensionWireDetent)
        }
        return nil
    }

    /// Virtual cursor/scroll inertia scaling: heavy `O(n^2)` regions physically resist scrolling momentum.
    public static func inertialScrollMultiplier(for stress: StressVector) -> Double {
        1.0 / (1.0 + 1.65 * StressVector.clamp(stress.mass))
    }

    /// Advances cursor travel by `(dx, dy)` and returns a tactile pulse if a spatial grating ridge was crossed.
    public mutating func advance(
        dx: Double,
        dy: Double,
        stress: StressVector,
        nowNanoseconds: UInt64 = StructuralAnalyzer.monotonicNanoseconds()
    ) -> TactilePulseKind? {
        let step = hypot(dx, dy)
        guard step > 0.01 else { return nil }

        guard let (wavelength, kind) = Self.wavelengthPoints(for: stress) else {
            accumulatedDistancePoints = 0
            return nil
        }

        accumulatedDistancePoints += step
        guard accumulatedDistancePoints >= wavelength else {
            return nil
        }

        // Carry remainder modulo wavelength so spatial phase stays locked.
        accumulatedDistancePoints = accumulatedDistancePoints.truncatingRemainder(dividingBy: wavelength)

        if lastPulseNanoseconds > 0 && (nowNanoseconds - lastPulseNanoseconds) < minInterPulseNanoseconds {
            return nil
        }
        lastPulseNanoseconds = nowNanoseconds
        return kind
    }

    public mutating func reset() {
        accumulatedDistancePoints = 0
    }
}

/// Drives the MacBook Force Touch Taptic Engine via `NSHapticFeedbackManager` using `SpatialGratingIntegrator`.
@MainActor
public final class TribologyEngine {
    private var integrator = SpatialGratingIntegrator()
    private var lastCursorPoint: NSPoint?
    public var isEnabled: Bool = true

    public init() {}

    @discardableResult
    public func processCursorMove(to point: NSPoint, stress: StressVector) -> TactilePulseKind? {
        defer { lastCursorPoint = point }
        guard isEnabled, let prev = lastCursorPoint else { return nil }
        let dx = Double(point.x - prev.x)
        let dy = Double(point.y - prev.y)
        guard let pulse = integrator.advance(dx: dx, dy: dy, stress: stress) else {
            return nil
        }
        fireTaptic(for: pulse)
        return pulse
    }

    @discardableResult
    public func processScrollDelta(dx: CGFloat, dy: CGFloat, stress: StressVector) -> (scaledDY: CGFloat, pulse: TactilePulseKind?) {
        let scale = CGFloat(SpatialGratingIntegrator.inertialScrollMultiplier(for: stress))
        let scaledDY = dy * scale
        guard isEnabled else { return (scaledDY, nil) }
        let pulse = integrator.advance(dx: Double(dx), dy: Double( abs(dy) * 1.4 ), stress: stress)
        if let pulse {
            fireTaptic(for: pulse)
        }
        return (scaledDY, pulse)
    }

    public func fireCrystallizationSnap() {
        guard isEnabled else { return }
        fireTaptic(for: .crystallizationSnap)
    }

    public func resetCursorTracking() {
        lastCursorPoint = nil
        integrator.reset()
    }

    private func fireTaptic(for kind: TactilePulseKind) {
        let performer = NSHapticFeedbackManager.defaultPerformer
        switch kind {
        case .fractureGrit:
            performer.perform(.alignment, performanceTime: .now)
        case .viscousMassDetent:
            performer.perform(.levelChange, performanceTime: .now)
        case .tensionWireDetent:
            performer.perform(.alignment, performanceTime: .now)
        case .crystallizationSnap:
            performer.perform(.generic, performanceTime: .now)
        }
    }
}
