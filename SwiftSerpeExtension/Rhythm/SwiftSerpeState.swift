//
//  SwiftSerpeState.swift
//  SwiftSerpeExtension
//
//  The session: a pattern, what it is played on, and what it is played *as*.
//
//  The third of these is where this port goes somewhere the webapp and the JUCE
//  plug-in do not, and it is the reason porting was worth more than
//  transcribing. MelGen's PORTING.md §5: "Swift SwiftSerpe can then go somewhere new
//  at the notation and interaction level — which is the point of porting rather
//  than transcribing — while still being provably the same engine underneath."
//
//  The engine is provably the same: `Scripts/verify.sh upi` puts every notation
//  case in `packages/upi/vectors/upi.json` against this parser, and the shared
//  package's own conformance tests hold Björklund and Barlow to the suite's
//  answers. What is new is `Voicing` below — a rhythm here is not only a
//  trigger pattern, it can be *performed as harmony*, because the foundation
//  this plug-in stands on has a chord dictionary in it and SwiftSerpe never has.
//
//  That is a small feature and an argument about architecture. A rhythm
//  plug-in that can voice a chord, because it shares a package with a melody
//  plug-in, is the dividend the layering was for.
//

import Foundation
import Carrier
import Theory

struct SwiftSerpeState: Codable, Hashable, Sendable {

    // MARK: - What was typed

    /// The UPI source, exactly as written. The pattern is derived, never stored:
    /// the notation is the document, and a stored mask that disagreed with the
    /// text it came from would be two sources of truth.
    var upi: String = "E(3,8)"

    // MARK: - How it sounds

    enum Voicing: String, Codable, CaseIterable, Sendable {
        /// One note per onset. What a rhythm plug-in has always done.
        case trigger
        /// Every onset plays the chord. The foundation's dictionary and its
        /// taxicab voice leading, on a rhythm's grid.
        case chord
        /// The chord's tones, one per onset, cycling — an arpeggio whose rhythm
        /// is the pattern rather than a rate.
        case arpeggio

        var label: String {
            switch self {
            case .trigger: return "Trigger"
            case .chord: return "Chord"
            case .arpeggio: return "Arpeggio"
            }
        }

        var explanation: String {
            switch self {
            case .trigger: return "One note an onset — point it at a drum."
            case .chord: return "Every onset plays the chord."
            case .arpeggio: return "The chord's tones, one an onset, cycling."
            }
        }
    }

    var voicing: Voicing = .trigger
    /// The chord the two harmonic voicings sound. Ignored by `.trigger`.
    var chordText: String = "Dm7"
    /// The note a trigger sends. 36 is a kick in the General MIDI map, which is
    /// what a rhythm plug-in is usually pointed at first.
    var triggerNote: Int = 36
    /// Where the harmonic voicings sit.
    var centre: Int = 60

    // MARK: - How long it is

    /// How many quarter-note beats the whole pattern spans.
    ///
    /// A mask is a shape, not a tempo: the same E(3,8) is an eighth grid over
    /// one bar and a quarter grid over two. This is the number that decides.
    var lengthBeats: Double = 4
    /// Fraction of a step each onset sounds for. Short enough to hear the grid.
    var gate: Double = 0.5
    /// How much louder an accented onset is.
    var accentVelocity: Int = 18
    var velocity: Int = 96

    // MARK: - Deriving

    var parsed: UPIPattern? {
        switch UPIParser.parse(upi) {
        case .success(let pattern): return pattern
        case .failure: return nil
        }
    }

    var parseError: String? {
        switch UPIParser.parse(upi) {
        case .success: return nil
        case .failure(let error): return error.description
        }
    }

    var chord: ChordSymbol? { try? ChordProgression.parseChordSymbol(chordText) }

    /// What the kernel loops.
    ///
    /// The three voicings differ only in which pitches an onset sounds, which is
    /// the whole shape of the feature: the grid, the gate, the accents and the
    /// length are decided once and none of them knows about harmony.
    var notes: [SequencedNote] {
        guard let pattern = parsed, pattern.stepCount > 0 else { return [] }
        let onsets = pattern.onsets
        guard !onsets.isEmpty else { return [] }

        let beatsPerStep = lengthBeats / Double(pattern.stepCount)
        let duration = max(0.01, beatsPerStep * min(1, max(0.05, gate)))

        var notes: [SequencedNote] = []
        var previous: [Int]?
        for (index, step) in onsets.enumerated() {
            let start = Double(step) * beatsPerStep
            let accented = step < pattern.accents.count && pattern.accents[step]
            let level = UInt8(clamping: velocity + (accented ? accentVelocity : 0))

            switch voicing {
            case .trigger:
                notes.append(SequencedNote(note: UInt8(clamping: triggerNote),
                                           velocity: level,
                                           startBeat: start, durationBeats: duration))
            case .chord:
                guard let chord else { break }
                let voiced = ChordVoicings.voice(chord, style: .rootlessA, centre: centre)
                let pitches = ChordVoicings.lead(from: previous, to: voiced.pitches,
                                                 centre: centre, mode: .smooth)
                previous = pitches
                for pitch in pitches {
                    notes.append(SequencedNote(note: UInt8(clamping: pitch), velocity: level,
                                               startBeat: start, durationBeats: duration))
                }
            case .arpeggio:
                guard let chord else { break }
                let voiced = ChordVoicings.voice(chord, style: .close, centre: centre)
                guard !voiced.pitches.isEmpty else { break }
                let pitch = voiced.pitches[index % voiced.pitches.count]
                notes.append(SequencedNote(note: UInt8(clamping: pitch), velocity: level,
                                           startBeat: start, durationBeats: duration))
            }
        }
        return notes
    }

    /// The pattern as a rhythm the carrier can perform a line on.
    ///
    /// Not used by this plug-in — it plays its own notes — but it is what
    /// `MelodyPattern.performed(on:)` takes, so a line kept in MelGen can be
    /// played on a rhythm written here. That is the interop the shared package
    /// makes possible and neither plug-in could have alone.
    var rhythmSpec: RhythmSpec? {
        guard let pattern = parsed else { return nil }
        return RhythmSpec(steps: pattern.steps, accents: pattern.accents,
                          label: pattern.label)
    }
}
