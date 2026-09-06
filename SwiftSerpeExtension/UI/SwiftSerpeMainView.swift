//
//  SwiftSerpeMainView.swift
//  SwiftSerpeExtension
//
//  One screen: what you typed, what it is, and what it sounds like.
//
//  The notation is the document, so it is the first thing and it is a text
//  field — everything else on this screen is downstream of a string. That is
//  SwiftSerpe's own shape and it is not MelGen's or ProgGenie's; what is shared is
//  everything underneath it. `Eyebrow`, `LabelledSlider`, `ChipPicker`,
//  `MelGenTheme` and its metrics come out of the package's UI target and were
//  written for a melody plug-in, which is the point: a third plug-in inherits
//  the touch targets, the WCAG-audited palette and the light/dark behaviour
//  without deciding any of it again.
//
//  The ring is this plug-in's own drawing, because a rhythm is a cycle and a
//  piano roll is a line. It is the one control here that had to be written.
//

import SwiftUI
import Carrier
import Shell
import Theory
import UI

struct SwiftSerpeMainView: View {
    var parameterTree: ObservableAUParameterGroup
    weak var audioUnit: SwiftSerpeAudioUnit?

    @State private var state = SwiftSerpeState()
    @State private var draft = "E(3,8)"
    @Environment(\.colorScheme) private var colorScheme

    private var theme: MelGenTheme { colorScheme == .dark ? .dark : .light }
    private var playParameter: ObservableAUParameter { parameterTree.global.playMelody }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MelGenMetrics.space3) {
                notation
                ring
                reading
                sound
            }
            .padding(MelGenMetrics.space3)
        }
        .background(theme.background)
        .onAppear {
            if let audioUnit { state = audioUnit.state }
            draft = state.upi
        }
    }

    // MARK: - What you typed

    private var notation: some View {
        VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
            Eyebrow(text: "Pattern", theme: theme)
            HStack(spacing: MelGenMetrics.space2) {
                TextField("E(3,8)", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.text)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .padding(.horizontal, MelGenMetrics.space2)
                    .frame(height: MelGenMetrics.controlHeight)
                    .background(RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                        .fill(theme.sunken))
                    .overlay(RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                        .strokeBorder(state.parseError == nil ? theme.border : theme.warning,
                                      lineWidth: 1))
                    .onSubmit { commitNotation() }
                    // Committed on submit rather than on every keystroke: the
                    // four prefixes of "E(3,8)" that happen to parse would each
                    // hand the render thread a different sequence, and you would
                    // hear all of them.
                    .onChange(of: draft) { _, _ in }

                Button {
                    playParameter.value = playParameter.boolValue ? 0 : 1
                } label: {
                    Image(systemName: playParameter.boolValue ? "stop.fill" : "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .frame(width: MelGenMetrics.controlHeight * 1.4,
                               height: MelGenMetrics.controlHeight)
                        .background(RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                            .fill(theme.raised))
                        .overlay(RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                            .strokeBorder(theme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playParameter.boolValue ? "Stop" : "Play")
            }

            if let error = state.parseError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.warning)
            }

            // Eight starting points rather than a menu of everything: the field
            // is the interface and these are a way in, not a vocabulary.
            FlowChips(items: ["E(3,8)", "E(5,8)", "E(5,16)", "P(3,0)+P(5,0)",
                              "A(2,2,2,3)", "0x94", "{10}E(5,16)", "B(5,16)"],
                      isSelected: { $0 == state.upi },
                      theme: theme) { chip in
                draft = chip
                commitNotation()
            }
        }
    }

    // MARK: - The ring
    //
    // A rhythm is a cycle. Drawing it as a line makes the wrap invisible, and
    // the wrap is where half of what is interesting lives — a tresillo's third
    // gap is two steps only because the cycle closes.

    private var ring: some View {
        Canvas { context, size in
            guard let pattern = state.parsed, pattern.stepCount > 0 else { return }
            let radius = min(size.width, size.height) / 2 - 14
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let step = (Double.pi * 2) / Double(pattern.stepCount)

            // The grid first, so onsets sit on top of it rather than beside it.
            for index in 0..<pattern.stepCount {
                let angle = step * Double(index) - .pi / 2
                let point = CGPoint(x: centre.x + cos(angle) * radius,
                                    y: centre.y + sin(angle) * radius)
                let struck = pattern.steps[index]
                let accented = index < pattern.accents.count && pattern.accents[index]
                let size: CGFloat = struck ? (accented ? 11 : 8) : 3
                let rect = CGRect(x: point.x - size / 2, y: point.y - size / 2,
                                  width: size, height: size)
                context.fill(Path(ellipseIn: rect),
                             with: .color(struck
                                          ? (accented ? theme.accent : theme.text)
                                          : theme.border))
            }

            // The polygon through the onsets: the shape the pattern *is*, which
            // is what makes P(3,0)+P(5,0) legible as two polygons at once.
            let onsets = pattern.onsets
            if onsets.count > 1 {
                var path = Path()
                for (i, onset) in onsets.enumerated() {
                    let angle = step * Double(onset) - .pi / 2
                    let point = CGPoint(x: centre.x + cos(angle) * radius,
                                        y: centre.y + sin(angle) * radius)
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.closeSubpath()
                context.stroke(path, with: .color(theme.accent.opacity(0.35)), lineWidth: 1.5)
            }
        }
        .frame(height: 190)
        .accessibilityLabel("Pattern ring")
        .accessibilityValue(state.parsed.map {
            "\($0.onsetCount) onsets over \($0.stepCount) steps"
        } ?? "nothing to draw")
    }

    // MARK: - What it is

    @ViewBuilder
    private var reading: some View {
        if let pattern = state.parsed {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "Reading", theme: theme)
                Text(pattern.bits)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(theme.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                Text(readingLine(pattern))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func readingLine(_ pattern: UPIPattern) -> String {
        var parts = ["\(pattern.onsetCount) of \(pattern.stepCount)"]
        if let hex = RhythmCodec.hexString(pattern.steps) { parts.append("0x\(hex)") }
        if let decimal = RhythmCodec.decimal(pattern.steps) { parts.append("d\(decimal)") }
        let intervals = RhythmCodec.interOnsetIntervals(pattern.steps)
        if !intervals.isEmpty {
            parts.append("gaps \(intervals.map(String.init).joined(separator: "·"))")
        }
        let syncopation = Barlow.syncopation(onsets: pattern.onsets,
                                             stepCount: pattern.stepCount)
        parts.append("syncopation \(syncopation.formatted(.number.precision(.fractionLength(2))))")
        return parts.joined(separator: " · ")
    }

    // MARK: - What it sounds like

    private var sound: some View {
        VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
            Eyebrow(text: "Sound", theme: theme)

            ChipPicker(options: SwiftSerpeState.Voicing.allCases.map { ($0, $0.label) },
                       selection: Binding(get: { state.voicing },
                                          set: { state.voicing = $0; commit() }),
                       theme: theme)
            Text(state.voicing.explanation)
                .font(.system(size: 11))
                .foregroundStyle(theme.textMuted)

            if state.voicing != .trigger {
                HStack(spacing: MelGenMetrics.space2) {
                    Text("Chord")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.text)
                    TextField("Dm7", text: Binding(get: { state.chordText },
                                                   set: { state.chordText = $0 }))
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(state.chord == nil ? theme.warning : theme.text)
                        .autocorrectionDisabled()
                        .frame(height: MelGenMetrics.controlHeight)
                        .onSubmit { commit() }
                }
            }

            LabelledSlider(title: "Length", lowLabel: "1 bar", highLabel: "4 bars",
                           value: Binding(get: { state.lengthBeats / 16 },
                                          set: { state.lengthBeats = max(1, ($0 * 16).rounded()) }),
                           theme: theme,
                           format: { value in
                               let bars = (value * 16).rounded() / 4
                               return "\(bars.formatted(.number.precision(.fractionLength(2)))) bars"
                           },
                           onCommit: { commit() })

            LabelledSlider(title: "Gate", lowLabel: "short", highLabel: "legato",
                           value: $state.gate, theme: theme,
                           onCommit: { commit() })
        }
    }

    // MARK: - Doing it

    private func commitNotation() {
        state.upi = draft.trimmingCharacters(in: .whitespaces)
        commit()
    }

    private func commit() {
        audioUnit?.update(state: state)
    }
}
