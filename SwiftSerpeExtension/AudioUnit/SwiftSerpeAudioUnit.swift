//
//  SwiftSerpeAudioUnit.swift
//  SwiftSerpeExtension
//
//  SwiftSerpe's half of the audio unit: the session, and what the kernel plays.
//
//  Third time this file has been written, and it is the same shape each time —
//  a locked session, a `fullState` that round-trips it as JSON under one key,
//  and a reload that only restarts the loop when the material actually changed.
//  `PluginAudioUnit` in the shared package is the other ~900 lines.
//
//  That the three are the same shape and not shared code is deliberate: a
//  plug-in's session type is the plug-in's, and the shell deliberately knows
//  nothing about what one *is*. What "days per app" costs is this file, the
//  view controller beside it, and the parameter tree — about 200 lines before
//  any of the product exists.
//

import AVFoundation
import Shell

public final class SwiftSerpeAudioUnit: PluginAudioUnit, @unchecked Sendable {

    private let stateLock = NSLock()
    private var _state = SwiftSerpeState()

    /// The notation the kernel is currently looping, so a change of voicing or
    /// gate can be told apart from a change of pattern: re-voicing E(3,8) should
    /// not jump the playhead back to step 0.
    private var lastLoadedUPI: String?

    var state: SwiftSerpeState {
        get { stateLock.withLock { _state } }
        set { update(state: newValue) }
    }

    /// - Parameter reloadKernel: pass `false` while the notation field is being
    ///   typed into, so the render thread is not handed a new sequence for every
    ///   keystroke of "E(3,8)" — including the four prefixes that parse.
    func update(state newState: SwiftSerpeState, reloadKernel: Bool = true) {
        stateLock.withLock { _state = newState }
        if reloadKernel { loadIntoKernel(newState) }
    }

    private func loadIntoKernel(_ state: SwiftSerpeState) {
        let notes = state.notes
        guard !notes.isEmpty else { return }
        let isNewPattern = state.upi != lastLoadedUPI
        lastLoadedUPI = state.upi
        setMelody(notes, lengthBeats: state.lengthBeats, restartFromTop: isNewPattern)
    }

    private static let stateKey = "SwiftSerpe.sessionState"

    public override var fullState: [String: Any]? {
        get {
            var dictionary = super.fullState ?? [:]
            if let data = try? JSONEncoder().encode(state) {
                dictionary[Self.stateKey] = data
            }
            return dictionary
        }
        set {
            super.fullState = newValue
            guard let data = newValue?[Self.stateKey] as? Data,
                  let restored = try? JSONDecoder().decode(SwiftSerpeState.self, from: data) else {
                return
            }
            state = restored
        }
    }

    public override var fullStateForDocument: [String: Any]? {
        get { fullState }
        set { fullState = newValue }
    }
}
