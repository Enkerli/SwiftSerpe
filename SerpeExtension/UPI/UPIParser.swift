//
//  UPIParser.swift
//  SerpeExtension
//
//  Universal Pattern Input — the notation, in Swift.
//
//  This file is Serpe. MelGen's PORTING.md §5 makes the split explicit: the
//  rhythm *algorithms* — Björklund, Barlow, the codecs — are shared theory and
//  live in the `enkerli-swift` package, held to `packages/theory/vectors/
//  rhythm.json`. The *notation* is where this plug-in's identity lives, it has a
//  grammar rather than an algorithm, and no other plug-in wants it. So it is
//  here, and it is the only substantial thing here that is not in the package.
//
//  Ported from `packages/upi/src/upi.js` and held to
//  `packages/upi/vectors/upi.json`, which was written for this port and did not
//  exist before it — one thin file (poly.json, about lane splitting) was the
//  whole of that package's cross-language coverage. See `Scripts/verify.sh upi`,
//  which reports every vector case as PASS, DIFF or NOT-PORTED, so what is
//  missing is visible in the output rather than in a comment somebody has to
//  find.
//
//  **Order matters and is not obvious.** The suffixes come off first, then the
//  accent prefix, then `;N` quantization splits the string, then shorthand
//  resolves, then Morse is tried *before* combination because Morse uses `-`.
//  Getting that sequence wrong produces patterns rather than errors, which is
//  the worst way for a parser to be wrong.
//

import Foundation
import Theory

public enum UPIParser {

    /// Shorthand names, resolved to what they mean before anything else parses.
    static let shorthand: [String: String] = [
        "tri": "P(3,0)", "pent": "P(5,0)", "hex": "P(6,0)",
        "hept": "P(7,0)", "oct": "P(8,0)",
        "tresillo": "E(3,8)", "cinquillo": "E(5,8)",
    ]

    // MARK: - Entry point

    public static func parse(_ input: String) -> Result<UPIPattern, UPIError> {
        var source = input.trimmingCharacters(in: .whitespaces)

        // Suffixes, in the engine's order: microtiming, then durational. Both
        // are stripped before anything else looks at the string.
        let pd = microtimingSuffix(source)
        let microtiming = pd.spec
        source = pd.rest

        let ls = longShortSuffix(source)
        let longShort = ls.spec
        source = ls.rest

        // Accent prefix `{…}`.
        var accentPattern: [Bool]?
        if source.hasPrefix("{"), let close = source.firstIndex(of: "}") {
            let inside = source[source.index(after: source.startIndex)..<close]
            accentPattern = inside.compactMap { $0 == "1" ? true : ($0 == "0" ? false : nil) }
            source = String(source[source.index(after: close)...])
                .trimmingCharacters(in: .whitespaces)
            if accentPattern?.isEmpty == true { accentPattern = nil }
        }

        return steps(of: source).map { built in
            finish(steps: built.steps, label: built.label,
                   accentPattern: accentPattern, longShort: longShort,
                   microtiming: microtiming)
        }
    }

    /// Applies the layers that ride on onsets, and assembles the pattern.
    private static func finish(steps: [Bool], label: String,
                               accentPattern: [Bool]?,
                               longShort: LongShortSpec?,
                               microtiming: MicrotimingSpec?) -> UPIPattern {
        // Accents cycle over ONSETS, not steps: the k-th onset takes
        // accents[k % count]. Cycling over steps instead is the single most
        // plausible-looking way to get this wrong, and the vectors carry two
        // cases whose only job is to catch it.
        func projected(_ layer: [Bool]?) -> [Bool]? {
            guard let layer, !layer.isEmpty else { return nil }
            var out = Array(repeating: false, count: steps.count)
            var onset = 0
            for i in steps.indices where steps[i] {
                out[i] = layer[onset % layer.count]
                onset += 1
            }
            return out
        }

        return UPIPattern(
            steps: steps,
            accents: projected(accentPattern) ?? Array(repeating: false, count: steps.count),
            accentPattern: accentPattern,
            longs: projected(longShort?.longMask),
            longShort: longShort,
            microtiming: microtiming,
            label: label)
    }

    // MARK: - The grammar

    private static func steps(of input: String) -> Result<(steps: [Bool], label: String), UPIError> {
        var source = input.trimmingCharacters(in: .whitespaces)
        guard !source.isEmpty else { return .failure(.unrecognised(input)) }

        // `<expr>;N` — angular quantization, clockwise; `;-N` counter. The base
        // parses recursively, so `tresillo;12` and `P(3,0)+P(5,0);16` both work.
        if let semi = source.firstIndex(of: ";"), semi != source.startIndex {
            let tail = String(source[source.index(after: semi)...])
                .trimmingCharacters(in: .whitespaces)
            if let (count, clockwise) = signedCount(tail) {
                let head = String(source[..<semi]).trimmingCharacters(in: .whitespaces)
                return steps(of: head).map { base in
                    (quantize(base.steps, to: count, clockwise: clockwise),
                     "\(base.label);\(clockwise ? "" : "-")\(count)")
                }
            }
        }

        // Shorthand resolves here, so `{10}tresillo;12` behaves like the
        // spelled-out form all the way down.
        if let expansion = shorthand[source.lowercased()] { source = expansion }

        // A(a,b,c…) — additive / aksak: beat groups, one onset each.
        if let groups = captures(source, #"^[Aa]\(\s*([\d\s,]+?)\s*\)$"#),
           let numbers = groups.first.map(commaSeparatedInts), !numbers.isEmpty,
           numbers.allSatisfy({ $0 >= 1 }) {
            var out: [Bool] = []
            for group in numbers {
                out.append(true)
                out.append(contentsOf: Array(repeating: false, count: group - 1))
            }
            return .success((out, "A(\(numbers.map(String.init).joined(separator: ",")))"))
        }

        // Morse comes BEFORE combination, because Morse uses '-'. Only pure
        // dot/dash strings, an `M:` prefix, or a bare letter word qualify — a
        // real combination carries parens or digits and falls through.
        if let morse = morse(of: source) { return .success(morse) }

        // Combination: top-level '+' / '-' between whole patterns. A purely
        // numeric term is a progressive offset, not a combination, and the whole
        // expression is then refused here — the progressive layer owns it.
        if source.contains("+") || source.contains("-"),
           case let terms = splitTopLevel(source), terms.count >= 2 {
            if terms.contains(where: { Int($0.pattern) != nil }) {
                return .failure(.unrecognised(input))
            }
            return combine(terms)
        }

        // E(k,n) / E(k,n,rotation)
        if let m = captures(source, #"^[Ee]\(\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*(-?\d+)\s*)?\)$"#),
           let k = Int(m[0]), let n = Int(m[1]) {
            let rotation = m[2].isEmpty ? 0 : (Int(m[2]) ?? 0)
            return .success((EuclideanRhythm.pattern(beats: k, steps: n, offset: rotation),
                             "E(\(k),\(n)\(rotation != 0 ? ",\(rotation)" : ""))"))
        }

        // P(sides, offset) / P(sides, offset, expansion).
        //
        // The third argument is an EXPANSION FACTOR, not a step count: P(3,1,4)
        // is a triangle over 3x4 = 12 steps, still exactly even. Read as a step
        // count it gives `1110`, three onsets crammed into four, which is not a
        // triangle. Re-gridding onto an arbitrary count is what `;N` does.
        if let m = captures(source, #"^[Pp]\(\s*(\d+)\s*,\s*(-?\d+)\s*(?:,\s*(\d+)\s*)?\)$"#),
           let k = Int(m[0]), let offset = Int(m[1]) {
            let expansion = m[2].isEmpty ? 1 : (Int(m[2]) ?? 1)
            let n = k * max(1, expansion)
            guard n > 0 else { return .failure(.unrecognised(input)) }
            let label = "P(\(k),\(offset)\(m[2].isEmpty ? "" : ",\(expansion)"))"
            return .success((polygon(k, offset: ((offset % n) + n) % n, steps: n), label))
        }

        // R(k,n) — random. Deliberately refused rather than implemented with a
        // different RNG than the JS: a pattern that cannot be reproduced across
        // languages has no vector and no contract, and Serpe's own vectors say
        // so in their scope note.
        if captures(source, #"^[Rr]\(\s*\d+\s*,\s*\d+\s*\)$"#) != nil {
            return .failure(.notPorted("R(k,n) — random, and not reproducible across languages"))
        }

        // B / W / D — Barlow, Wolrab, Dilcue.
        if let m = captures(source, #"^([BbWwDd])\(\s*(\d+)\s*,\s*(\d+)\s*\)$"#),
           let k = Int(m[1]), let n = Int(m[2]) {
            let tag = m[0].uppercased()
            if tag == "D" {
                let euclid = EuclideanRhythm.pattern(beats: n - k, steps: n)
                return .success((euclid.map { !$0 }, "D(\(k),\(n))"))
            }
            var base = Array(repeating: false, count: n)
            if n > 0 { base[0] = true }
            let result = BarlowTransform.apply(base, targetOnsets: k,
                                               options: .init(wolrab: tag == "W"))
            return .success((result.pattern, "\(tag)(\(k),\(n))"))
        }

        // Numeric forms. Digits little-endian; width from the `:n` suffix, or
        // from the digit count, which is why `d73` is seven steps and not eight.
        if let m = captures(source, #"^0[xX]([0-9a-fA-F]+)(?::(\d+))?$"#) {
            let width = m[1].isEmpty ? m[0].count * 4 : (Int(m[1]) ?? m[0].count * 4)
            guard let steps = RhythmCodec.pattern(hex: m[0], steps: width) else {
                return .failure(.unrecognised(input))
            }
            return .success((steps, "0x\(m[0].uppercased())"))
        }
        if let m = captures(source, #"^[oO]([0-7]+)(?::(\d+))?$"#) {
            let width = m[1].isEmpty ? m[0].count * 3 : (Int(m[1]) ?? m[0].count * 3)
            guard let steps = RhythmCodec.pattern(octal: m[0], steps: width) else {
                return .failure(.unrecognised(input))
            }
            return .success((steps, "o\(m[0])"))
        }
        if let m = captures(source, #"^[dD](\d+)(?::(\d+))?$"#), let value = UInt64(m[0]) {
            let natural = max(1, String(value, radix: 2).count)
            let width = m[1].isEmpty ? natural : (Int(m[1]) ?? natural)
            guard let steps = RhythmCodec.pattern(decimal: value, steps: width) else {
                return .failure(.unrecognised(input))
            }
            return .success((steps, "d\(m[0])"))
        }
        if let m = captures(source, #"^\[([\d,\s]*)\](?::(\d+))?$"#) {
            let indices = commaSeparatedInts(m[0])
            let width = m[1].isEmpty ? ((indices.max() ?? -1) + 1) : (Int(m[1]) ?? 0)
            guard width > 0 else { return .failure(.unrecognised(input)) }
            var out = Array(repeating: false, count: width)
            for i in indices where i >= 0 && i < width { out[i] = true }
            return .success((out, "[\(indices.map(String.init).joined(separator: ","))]:\(width)"))
        }
        if let m = captures(source, #"^[bB]?([01]+)$"#) {
            let steps = m[0].map { $0 == "1" }
            return .success((steps, m[0]))
        }

        return .failure(.unrecognised(input))
    }

    // MARK: - Combination

    private struct Term { var op: Character; var pattern: String }

    /// Splits on '+' and '-' that are not inside parentheses.
    private static func splitTopLevel(_ source: String) -> [Term] {
        var terms: [Term] = []
        var depth = 0
        var current = ""
        var op: Character = "+"
        for character in source {
            if character == "(" { depth += 1 }
            if character == ")" { depth -= 1 }
            if depth == 0, character == "+" || character == "-", !current.isEmpty {
                terms.append(Term(op: op, pattern: current.trimmingCharacters(in: .whitespaces)))
                op = character
                current = ""
                continue
            }
            current.append(character)
        }
        if !current.isEmpty {
            terms.append(Term(op: op, pattern: current.trimmingCharacters(in: .whitespaces)))
        }
        return terms
    }

    /// Every operand is a SHAPE spanning one shared cycle, so each is projected
    /// onto the lcm — its onsets scaled to the new length — rather than repeated
    /// to fill it.
    ///
    /// This is what makes combination a geometry: `P(3,1)+P(5,0)+P(2,5)` is
    /// perfectly balanced across 30 steps only because each polygon spans the
    /// cycle once. Tiling breaks it — a bare polygon repeated to fill the lcm is
    /// solid onsets — which is why `E(3,8)+P(3,0)` used to come back as a drone.
    ///
    /// A bare `P(k,off)` has no step grid of its own; its length here is its
    /// vertex count.
    private static func combine(_ terms: [Term]) -> Result<(steps: [Bool], label: String), UPIError> {
        let label = terms.enumerated()
            .map { $0.offset == 0 ? $0.element.pattern : "\($0.element.op)\($0.element.pattern)" }
            .joined()

        enum Resolved { case polygon(k: Int, offset: Int); case steps([Bool]) }
        var resolved: [Resolved] = []
        for term in terms {
            if let m = captures(term.pattern, #"^[Pp]\(\s*(\d+)\s*,\s*(-?\d+)\s*\)$"#),
               let k = Int(m[0]), let offset = Int(m[1]) {
                resolved.append(.polygon(k: k, offset: offset))
            } else {
                switch steps(of: term.pattern) {
                case .failure(let error): return .failure(error)
                case .success(let parsed): resolved.append(.steps(parsed.steps))
                }
            }
        }

        let lengths = resolved.map { item -> Int in
            switch item {
            case .polygon(let k, _): return max(1, k)
            case .steps(let s): return max(1, s.count)
            }
        }
        let total = lengths.reduce(1) { lcm($0, $1) }
        guard total > 0 else { return .failure(.unrecognised(label)) }

        func project(_ item: Resolved) -> [Bool] {
            switch item {
            case .polygon(let k, let offset):
                return polygon(k, offset: ((offset % total) + total) % total, steps: total)
            case .steps(let source):
                var out = Array(repeating: false, count: total)
                let n = source.count
                for i in 0..<n where source[i] {
                    out[Int((Double(i * total) / Double(n)).rounded()) % total] = true
                }
                return out
            }
        }

        var steps = project(resolved[0])
        for index in 1..<resolved.count {
            let next = project(resolved[index])
            let adding = terms[index].op == "+"
            for j in 0..<total {
                steps[j] = adding ? (steps[j] || next[j]) : (steps[j] && !next[j])
            }
        }
        return .success((steps, label))
    }

    // MARK: - Generators the package does not own

    /// A regular k-gon mapped onto n steps, rotated by `offset`.
    ///
    /// Not in `Theory` because it is not a rhythm algorithm the suite holds to
    /// vectors — it is three lines of geometry that only this notation asks for.
    ///
    /// The rounding is dead precision, and that is worth writing down rather
    /// than leaving as a thing someone re-derives. `n` is always a multiple of
    /// `k` everywhere this is called — a bare `P(k,off)` is `k` steps, an
    /// expansion is `k·e`, and in a combination every term's length divides the
    /// lcm — so `i·n/k` is always a whole number and `.rounded()` and truncation
    /// agree. Found by planting truncation and watching all 59 vector cases
    /// still pass, which is the useful half of planting a divergence: sometimes
    /// the answer is that the line cannot be wrong.
    static func polygon(_ k: Int, offset: Int, steps n: Int) -> [Bool] {
        var out = Array(repeating: false, count: max(0, n))
        guard k > 0, n > 0 else { return out }
        for i in 0..<k {
            let position = Int((Double(i * n) / Double(k)).rounded(.toNearestOrAwayFromZero)) % n
            out[(position + offset) % n] = true
        }
        return out
    }

    /// Lascabettes angular quantization: re-grid a pattern onto `count` steps.
    ///
    /// Angles, not step arithmetic. Each onset is a position on a circle, the
    /// circle is re-divided into `count` slots, and the onset lands in the
    /// nearest one — which is not the same as scaling the index and truncating.
    /// Written that way first, it put E(3,8);12 on 0,4,8 instead of 0,5,9, and
    /// the vectors said so on the first run.
    ///
    /// Counter-clockwise mirrors the angle rather than the index, so the
    /// downbeat stays the downbeat. Collisions merge, because two onsets landing
    /// in one slot is one onset — which is why the result can have fewer onsets
    /// than the source, and why this returns a set rather than a count.
    static func quantize(_ steps: [Bool], to count: Int, clockwise: Bool) -> [Bool] {
        guard !steps.isEmpty, count >= 1 else { return steps }
        guard steps.count != count else { return steps }
        var out = Array(repeating: false, count: count)
        let twoPi = Double.pi * 2
        let n = Double(steps.count)
        for i in steps.indices where steps[i] {
            var angle = (Double(i) / n) * twoPi
            if !clockwise { angle = twoPi - angle }
            angle = angle.truncatingRemainder(dividingBy: twoPi)
            if angle < 0 { angle += twoPi }
            var position = Int(((angle / twoPi) * Double(count)).rounded())
            if position >= count { position = 0 }
            out[Swift.max(0, Swift.min(position, count - 1))] = true
        }
        return out
    }

    // MARK: - Suffixes

    static func microtimingSuffix(_ text: String) -> (rest: String, spec: MicrotimingSpec?) {
        let number = #"\d+(?:\.\d+)?"#
        let pattern = #"\s*[Pp][Dd]\(\s*("# + number + #"%?)\s*(?:,\s*(-?"# + number
            + #")\s*)?\)\s*$"#
        guard let range = matchRange(text, pattern),
              let groups = captures(String(text[range.range]), "^" + pattern)
        else { return (text.trimmingCharacters(in: .whitespaces), nil) }
        guard let depth = percentOrNumber(groups[0]) else {
            return (text.trimmingCharacters(in: .whitespaces), nil)
        }
        let seed = groups[1].isEmpty ? 1 : Int(Double(groups[1]) ?? 1)
        return (String(text[text.startIndex..<range.range.lowerBound])
                    .trimmingCharacters(in: .whitespaces),
                MicrotimingSpec(depth: depth, seed: seed))
    }

    static func longShortSuffix(_ text: String) -> (rest: String, spec: LongShortSpec?) {
        // `\d+(?:\.\d+)?` rather than `[0-9.]+`, which is the suite's own NUM and
        // is not a detail: the greedy character class swallows the range's dots,
        // so `LS(1..3,50%)` captured a minimum of "1..3" and then failed to be a
        // number. It matched, it produced nothing, and the vectors reported it
        // as a refusal — which is a much better way to find out than a plug-in
        // quietly ignoring a suffix.
        let number = #"\d+(?:\.\d+)?"#
        let pattern = #"\s*[Ll][Ss]\(\s*("# + number + #")\s*(?:\.\.\s*("# + number
            + #")\s*)?(?:,\s*("# + number + #"%?)\s*)?\)\s*(?:\{([01]+)\}\s*)?$"#
        guard let range = matchRange(text, pattern),
              let groups = captures(String(text[range.range]), "^" + pattern)
        else { return (text.trimmingCharacters(in: .whitespaces), nil) }
        guard let minimum = Double(groups[0]) else {
            return (text.trimmingCharacters(in: .whitespaces), nil)
        }
        let maximum = groups[1].isEmpty ? minimum : (Double(groups[1]) ?? minimum)
        // A range with no depth means "use the range", which is depth 1; a
        // single value with no depth means no variation at all.
        let depth = groups[2].isEmpty
            ? (maximum > minimum ? 1 : 0)
            : (percentOrNumber(groups[2]) ?? (maximum > minimum ? 1 : 0))
        let mask = groups[3].isEmpty ? nil : groups[3].map { $0 == "1" }
        return (String(text[text.startIndex..<range.range.lowerBound])
                    .trimmingCharacters(in: .whitespaces),
                LongShortSpec(min: minimum, max: maximum, depth: depth,
                              longMask: (mask?.isEmpty ?? true) ? nil : mask))
    }

    // MARK: - Small helpers

    // MARK: - Morse

    static let morseAlphabet: [Character: String] = [
        "a": ".-", "b": "-...", "c": "-.-.", "d": "-..", "e": ".", "f": "..-.",
        "g": "--.", "h": "....", "i": "..", "j": ".---", "k": "-.-", "l": ".-..",
        "m": "--", "n": "-.", "o": "---", "p": ".--.", "q": "--.-", "r": ".-.",
        "s": "...", "t": "-", "u": "..-", "v": "...-", "w": ".--", "x": "-..-",
        "y": "-.--", "z": "--..",
    ]

    /// A dot/dash reading, when the source is one. Nil when it is not.
    ///
    /// Each symbol is an INTERVAL — an onset followed by (length − 1) rests —
    /// which is what makes this an additive-meter notation rather than a
    /// decoration. `D:2,3 ...-` is short-short-short-long, 2+2+2+3 = 9, the
    /// Balkan nine. The `D:` spelling is the webapp's and `L:` is the C++
    /// engine's; both engines accept both, because the divergence between them
    /// was silent and cost real confusion.
    static func morse(of source: String) -> (steps: [Bool], label: String)? {
        var body = source
        var shortLength = 1
        var longLength = 2
        var hadDurations = false

        if let m = captures(source, #"^[DdLl]:\s*(\d+)\s*,\s*(\d+)\s*(.*)$"#),
           let short = Int(m[0]), let long = Int(m[1]) {
            shortLength = Swift.max(1, short)
            longLength = Swift.max(1, long)
            body = m[2].trimmingCharacters(in: .whitespaces)
            hadDurations = true
        }

        var symbols: String?
        if body.lowercased().hasPrefix("m:") {
            symbols = String(body.dropFirst(2))
        } else if captures(body, #"^[.\-\s]+$"#) != nil,
                  body.contains(where: { $0 == "." || $0 == "-" }) {
            symbols = body
        } else if captures(body, #"^[A-Za-z]+$"#) != nil {
            // A bare letter word. Shorthand names resolved before this, so
            // "tresillo" never arrives here; anything else is spelled out.
            symbols = body
        }
        guard var text = symbols?.lowercased().trimmingCharacters(in: .whitespaces),
              !text.isEmpty
        else { return nil }

        // Two prosigns, spelled the way an operator sends them rather than as
        // three letters each.
        if text == "sos" { text = "...---..." }
        else if text == "cq" { text = "-.-.--.-" }
        else if text.contains(where: { $0.isLetter }) {
            text = text.map { morseAlphabet[$0] ?? String($0) }.joined()
        }

        var steps: [Bool] = []
        func emit(_ length: Int) {
            steps.append(true)
            steps.append(contentsOf: Array(repeating: false, count: Swift.max(0, length - 1)))
        }
        for character in text {
            switch character {
            case ".": emit(shortLength)
            case "-": emit(longLength)
            case " ": steps.append(false)
            default: break
            }
        }
        guard !steps.isEmpty else { return nil }
        return (steps, hadDurations
                ? "D:\(shortLength),\(longLength) \(body)"
                : "♪ \(source)")
    }

    static func signedCount(_ text: String) -> (count: Int, clockwise: Bool)? {
        guard let m = captures(text, #"^(-?)(\d+)$"#), let value = Int(m[1]) else { return nil }
        return (value, m[0].isEmpty)
    }

    static func percentOrNumber(_ text: String) -> Double? {
        if text.hasSuffix("%") { return (Double(text.dropLast()) ?? .nan) / 100 }
        return Double(text)
    }

    static func commaSeparatedInts(_ text: String) -> [Int] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap(Int.init)
    }

    static func lcm(_ a: Int, _ b: Int) -> Int {
        guard a != 0, b != 0 else { return 0 }
        var x = abs(a), y = abs(b)
        while y != 0 { (x, y) = (y, x % y) }
        return abs(a / x * b)
    }

    /// The capture groups of the first match, or nil when there is none.
    ///
    /// `NSRegularExpression` rather than Swift's `Regex`: this file is compiled
    /// by `Scripts/verify.sh` with plain `swiftc` as well as by Xcode, and
    /// Foundation's is the one that behaves the same in both.
    /// A group that did not participate comes back as "", not as a missing
    /// element. Returning a short array instead was the first shape of this and
    /// it is wrong as soon as an optional group is followed by another one:
    /// `LS(1..2){1010}` skips the depth and supplies the mask, and a version
    /// that stopped at the first gap lost the mask and refused the string.
    static func captures(_ text: String, _ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (1..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }

    static func matchRange(_ text: String, _ pattern: String) -> (range: Range<String.Index>, Void)? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text)
        else { return nil }
        return (range, ())
    }
}
