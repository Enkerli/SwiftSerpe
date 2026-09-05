# Serpe

An iOS/macOS **AUv3 MIDI processor** (`aumi Srpe`) that turns **UPI notation**
into rhythm — Euclidean patterns, polygons, Barlow transforms, additive meters,
Morse, and the numeric forms — and plays it as a trigger, a chord, or an
arpeggio.

The third plug-in on [`enkerli-swift`](https://github.com/Enkerli/enkerli-swift),
and the first whose engine had to be *split* rather than reused. The rhythm
algorithms — Björklund, Barlow indispensability, the codecs — are shared theory
and live in that package, held to `packages/theory/vectors/rhythm.json`. The
notation is Serpe's, has a grammar rather than an algorithm, and lives here.

It is **not** the JUCE [Rhythm Pattern
Explorer](https://github.com/Enkerli/rhythm_pattern_explorer). That one is
`aumi RPEd` and ships five formats on four platforms. This one is AUv3 only,
macOS and iOS only, SwiftUI rather than WebView — and a different four-character
code, so both can be installed at once and compared.

## Provably the same engine

```
Scripts/verify.sh upi

  ── UPI notation, against packages/upi/vectors/upi.json ──
    59 cases: 59 PASS, 0 DIFF, 0 NOT PORTED
```

Every case in the monorepo's notation vectors goes through this parser and comes
back PASS, DIFF or NOT PORTED. **Those vectors were written for this port and
did not exist before it** — `@enkerli/upi` had one 3.5 KB file about lane
splitting, against 2,600 lines of engine, and MelGen's `PORTING.md` §5 named
writing them as the prerequisite: *"One thin file is not enough to hold a port
honest."*

The three-way classification is the point. A partial port that hides its gaps
behind a parse error is what this is built to prevent, so the parser names each
form it has not implemented and the count is printed every run. Coverage is a
number in the output, not a claim in this file.

It reached 59 of 59 by finding four real bugs on the way: quantization written
as index arithmetic instead of angles, a capture-group reader that lost a group
after any optional one that did not participate, a greedy `[0-9.]+` where the
suite uses `\d+(?:\.\d+)?`, and Morse, which was simply not written yet and said
so. Then it was made to fail on purpose — the planted divergences and what each
caught are listed at the top of `Scripts/tests/upi-main.swift`, including the one
that *didn't* fail and why that was informative too.

## What it does that its siblings don't

**A rhythm can be performed as harmony.** Trigger is what a rhythm plug-in has
always done — one note an onset, point it at a drum. Chord voices the whole
chord on every onset; Arpeggio takes the chord's tones one an onset, cycling.
Neither is a rhythm feature: they work because this plug-in shares a package
with a melody plug-in, so it has 172 chord qualities and taxicab voice leading
sitting there. A rhythm tool that can voice a `Dm7♯11` because of who its
neighbours are is the dividend the layering was for.

**And the pattern is a cycle, so it is drawn as one.** A piano roll makes the
wrap invisible, and the wrap is where half of what is interesting lives — a
tresillo's third gap is two steps only because the cycle closes. The ring draws
the polygon through the onsets, which is what makes `P(3,0)+P(5,0)` legible as
two shapes at once rather than as fifteen bits.

## Building

Clone the foundation beside this repo. Nothing builds without it:

```bash
git clone https://github.com/Enkerli/enkerli-swift ../enkerli-swift
git clone https://github.com/Enkerli/music-suite   ../music-suite   # for the vectors
```

Then open `Serpe.xcodeproj` (Xcode 27+, iOS/macOS 26.0+). `SerpeExtension` is
the plug-in; `Serpe` is a host app that loads it.

## Verifying

```bash
Scripts/verify.sh            # all suites
Scripts/verify.sh upi        # one suite
```

| Suite | Checks |
|---|---|
| `identity` | The component triple is unique across every sibling checkout, JUCE and Swift alike, and matches the host app's lookup. First, because codes are forever and this project was scaffolded from ProgGenie's, which was scaffolded from MelGen's |
| `upi` | Every notation case in `packages/upi/vectors/upi.json`, as PASS / DIFF / NOT PORTED |

Without a `music-suite` checkout the `upi` suite prints the clone line and the
words **NOT RUN**. A skip is not a pass.

## What this plug-in is, in files

| File | Lines | What it is |
|---|---:|---|
| `UPI/UPIParser.swift` | ~530 | The notation. The only substantial thing here that could not be in the package |
| `UPI/UPIPattern.swift` | ~130 | What the notation produces: a mask, and the two layers that ride on its onsets |
| `Rhythm/SerpeState.swift` | ~175 | The session, and the three voicings |
| `UI/SerpeMainView.swift` | ~250 | One screen, and the ring |
| `AudioUnit/` (3 files) | ~200 | The session half of the audio unit, three overrides, the parameter tree |

Björklund, Barlow, the codecs, the AU shell, the C++ kernel, the SwiftUI kit and
its WCAG-audited palette are all the package.

## What has not been done

- **None of this has been heard on a device.** It builds, its suites pass, and
  the kernel is the one MelGen has been heard through. That is not the same as
  knowing it sounds like anything.
- **Progressive notation is not wired up.** `pat>N`, `pat%N`, `pat+N` and
  `pat*N` are stateful across triggers, the monorepo has vectors for all four,
  and this plug-in has nowhere to put a trigger index yet. `E(3,8)+2` is refused
  with that reason rather than mis-parsed as a combination.
- **`R(k,n)` is refused on purpose.** It draws from `Math.random`, so it has no
  vector and no cross-language contract; implementing it with a different RNG
  would look like parity and not be it.
- **Poly lanes are not ported.** `packages/upi/vectors/poly.json` has covered
  them since before this port existed — the vectors are ready and the parser is
  not.
- **The analysis readout is thin.** One line: onsets, hex, decimal, gaps,
  Barlow syncopation. The monorepo's `analyse` and its six-way syncopation are
  vector-covered and not yet shown.

## Licence

Public domain, all the way down. See [LICENSE](LICENSE).
