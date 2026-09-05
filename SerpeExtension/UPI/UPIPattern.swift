//
//  UPIPattern.swift
//  SerpeExtension
//
//  What the notation produces: a mask, and the layers over it.
//
//  A pattern here is not a melody and not a chord. It is which of n slots are
//  struck, plus two optional layers that ride on the *onsets* rather than on the
//  steps — accents, and which onsets are long. That distinction is the one thing
//  a reader has to hold: `{10}E(3,8)` accents the first and third onsets, not
//  steps 0 and 2, and a port that cycles over steps produces a different pattern
//  that looks plausible.
//
//  Leftmost = LSB throughout: index 0 is the first step. See
//  music-suite's CONVENTIONS.md, and `packages/upi/vectors/upi.json`, which
//  carries `0x94` and `0x49` side by side because reading the digits the other
//  way round is the mistake this convention exists to prevent.
//

import Foundation

/// A parsed UPI pattern.
public struct UPIPattern: Hashable, Sendable {
    /// Which slots are struck. Index 0 is step 0.
    public var steps: [Bool]
    /// Per-step accents, after the `{…}` layer has been cycled over the onsets.
    public var accents: [Bool]
    /// The raw `{…}` layer, before cycling. Nil when none was written.
    ///
    /// Kept because a live interface re-applies it with a playing offset, so the
    /// accents precess across cycles the way the engine plays them — `accents`
    /// above is only the first cycle.
    public var accentPattern: [Bool]?
    /// Per-step "this onset is long", from an `LS(…){mask}` suffix.
    public var longs: [Bool]?
    /// The durational suffix, when one was written.
    public var longShort: LongShortSpec?
    /// The microtiming suffix, when one was written.
    public var microtiming: MicrotimingSpec?
    /// How the pattern was named, normalised. `E(3,8)` for every spelling of it.
    public var label: String

    public init(steps: [Bool], accents: [Bool] = [], accentPattern: [Bool]? = nil,
                longs: [Bool]? = nil, longShort: LongShortSpec? = nil,
                microtiming: MicrotimingSpec? = nil, label: String = "") {
        self.steps = steps
        self.accents = accents.isEmpty ? Array(repeating: false, count: steps.count) : accents
        self.accentPattern = accentPattern
        self.longs = longs
        self.longShort = longShort
        self.microtiming = microtiming
        self.label = label
    }

    public var onsets: [Int] {
        steps.enumerated().compactMap { $0.element ? $0.offset : nil }
    }
    public var onsetCount: Int { steps.lazy.filter { $0 }.count }
    public var stepCount: Int { steps.count }
    public var bits: String { steps.map { $0 ? "1" : "0" }.joined() }
}

/// `LS(min..max, depth){longMask}` — the durational reading.
///
/// The mask says WHICH onsets are long, for an even grid whose own intervals
/// cannot say: E(8,16) has no long and no short, so `LS(1..2){1010}` is how you
/// ask for a swung eighth feel over it.
public struct LongShortSpec: Hashable, Sendable {
    public var min: Double
    public var max: Double
    public var depth: Double
    public var longMask: [Bool]?

    public init(min: Double, max: Double, depth: Double, longMask: [Bool]? = nil) {
        self.min = Swift.max(1, min)
        self.max = Swift.max(Swift.max(1, min), max)
        self.depth = Swift.min(1, Swift.max(0, depth))
        self.longMask = longMask
    }
}

/// `PD(depth, seed)` — Keil's participatory discrepancies: push and pull around
/// the beat, seeded so a given pattern plays the same way twice.
public struct MicrotimingSpec: Hashable, Sendable {
    public var depth: Double
    public var seed: Int

    public init(depth: Double, seed: Int = 1) {
        self.depth = Swift.min(1, Swift.max(0, depth))
        self.seed = seed
    }
}

/// Why a string is not a pattern.
public enum UPIError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The grammar has no rule for this, or the arguments are malformed.
    case unrecognised(String)
    /// A form this port has not implemented yet, named so the gap is visible
    /// rather than looking like a parse failure. See UPIConformance.
    case notPorted(String)

    public var description: String {
        switch self {
        case .unrecognised: return "Unrecognised pattern"
        case .notPorted(let form): return "Not ported yet: \(form)"
        }
    }
}
