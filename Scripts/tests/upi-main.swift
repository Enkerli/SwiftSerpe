//
//  upi-main.swift
//  SwiftSerpe
//
//  The Swift parser against the monorepo's own answers, case by case.
//
//  Every case in `packages/upi/vectors/upi.json`'s `notation` group is read and
//  classified into one of three, and the three are the point:
//
//    PASS       the Swift answer and the JavaScript answer agree
//    DIFF       they disagree — a failure, and the only thing that fails a run
//    NOT PORTED the parser said so itself, by name
//
//  A partial port that hides its gaps behind a parse error is the thing this is
//  built to prevent. `UPIError.notPorted` exists for exactly this: the parser
//  says which form it has not implemented, this counts them, and the count is
//  printed every run. Coverage is a number in the output, not a claim in a
//  README, and it goes up by deleting a `.notPorted` and watching a DIFF turn
//  into a PASS.
//
//  It reached 59 of 59 by finding four real bugs, which is what a first run is
//  supposed to do: quantization written as index arithmetic instead of angles
//  (E(3,8);12 landed on 0,4,8 rather than 0,5,9); a capture-group reader that
//  stopped at the first optional group that did not participate, so
//  `LS(1..2){1010}` lost its mask; a greedy `[0-9.]+` where the suite uses
//  `\d+(?:\.\d+)?`, which swallowed a range's dots; and Morse, which was simply
//  not written yet and said so.
//
//  Then it was made to fail on purpose, because a suite that has only ever been
//  green is indistinguishable from one that checks nothing. Accents cycled over
//  steps instead of onsets → 3 DIFF. Morse symbols emitting one rest too many
//  → 5 DIFF. Quantization spun the other way → 4 DIFF. And one probe that did
//  NOT fail: truncating instead of rounding in `polygon`, which turns out to be
//  unreachable — the note in UPIParser explains why, and finding that out is
//  the other thing planting a divergence is good for.
//

import Foundation

// ── Reading the vectors ────────────────────────────────────────────────────

let environment = ProcessInfo.processInfo.environment
let suiteRoot = environment["MUSIC_SUITE"] ?? "../music-suite"
let vectorPath = "\(suiteRoot)/packages/upi/vectors/upi.json"

guard let data = FileManager.default.contents(atPath: vectorPath),
      let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let groups = document["groups"] as? [String: Any],
      let notation = groups["notation"] as? [[String: Any]]
else {
    print("SKIP: no UPI vectors at \(vectorPath)")
    print("      git clone https://github.com/Enkerli/music-suite ../music-suite")
    print("      (or set MUSIC_SUITE=/path/to/music-suite)")
    print("      These cases were NOT run.")
    exit(0)
}

// ── Comparing ──────────────────────────────────────────────────────────────

var passed = 0
var notPorted: [(String, String)] = []
var differences: [String] = []

func bits(_ steps: [Bool]) -> String { steps.map { $0 ? "1" : "0" }.joined() }

for testCase in notation {
    let input = testCase["input"] as? String ?? ""
    let expectedOK = testCase["ok"] as? Bool ?? false
    let name = input.isEmpty ? "(empty)" : input

    switch UPIParser.parse(input) {
    case .failure(.notPorted(let form)):
        notPorted.append((name, form))

    case .failure(.unrecognised):
        if expectedOK {
            differences.append("\(name): the suite parses this, we refuse it")
        } else {
            passed += 1
        }

    case .success(let pattern):
        guard expectedOK else {
            differences.append("\(name): the suite refuses this, we parse it as \(pattern.bits)")
            continue
        }
        var complaints: [String] = []
        if let expected = testCase["steps"] as? String, pattern.bits != expected {
            complaints.append("steps \(pattern.bits) != \(expected)")
        }
        if let expected = testCase["label"] as? String, pattern.label != expected {
            complaints.append("label \(pattern.label.debugDescription) != \(expected.debugDescription)")
        }
        if let expected = testCase["accents"] as? String, bits(pattern.accents) != expected {
            complaints.append("accents \(bits(pattern.accents)) != \(expected)")
        }
        if let expected = testCase["longs"] as? String {
            let got = pattern.longs.map(bits) ?? ""
            if got != expected { complaints.append("longs \(got) != \(expected)") }
        }
        if let expected = testCase["microtiming"] as? [String: Any] {
            let depth = (expected["depth"] as? NSNumber)?.doubleValue ?? -1
            let seed = (expected["seed"] as? NSNumber)?.intValue ?? -1
            if pattern.microtiming?.depth != depth || pattern.microtiming?.seed != seed {
                complaints.append("microtiming \(String(describing: pattern.microtiming)) "
                                  + "!= depth \(depth) seed \(seed)")
            }
        }
        if complaints.isEmpty {
            passed += 1
        } else {
            differences.append("\(name): " + complaints.joined(separator: "; "))
        }
    }
}

// ── Saying what happened ───────────────────────────────────────────────────

print("── UPI notation, against packages/upi/vectors/upi.json ──")
print("  \(notation.count) cases: \(passed) PASS, \(differences.count) DIFF, "
      + "\(notPorted.count) NOT PORTED")

if !notPorted.isEmpty {
    print()
    print("  Not ported yet — the parser names each of these itself, so the gap")
    print("  is in the output rather than in somebody's memory:")
    var forms: [String: [String]] = [:]
    for (input, form) in notPorted { forms[form, default: []].append(input) }
    for form in forms.keys.sorted() {
        print("    · \(form)")
        print("      \(forms[form]!.joined(separator: ", "))")
    }
}

if !differences.isEmpty {
    print()
    for difference in differences { print("  DIFF  \(difference)") }
    print()
    print("upi: \(differences.count) DIFFERENCES")
    exit(1)
}

print()
print("upi: no differences")
