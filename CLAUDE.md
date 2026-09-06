# Working on SwiftSerpe

*Short on purpose. This is the third plug-in on a shared foundation, and the
first whose engine had to be split rather than reused, so most of what you need
to know is about where the line falls.*

---

## The two things that surprise everybody

**Nothing builds without the foundation checked out beside this repo.**

```bash
git clone https://github.com/Enkerli/enkerli-swift ../enkerli-swift
```

`Scripts/verify.sh` and `SwiftSerpe.xcodeproj` both look in `$REPO/../enkerli-swift`;
override with `ENKERLI_SWIFT=...`. Without it every suite fails with that line
printed, which is deliberate — a suite that quietly passed without the foundation
would be checking nothing.

**Xcode's test targets reach almost nothing.** Everything real is either in the
`SwiftSerpeExtension` target (extension-only membership) or in the package next
door. A green test action says the host app compiles. The real check is:

```bash
Scripts/verify.sh            # all suites
Scripts/verify.sh upi        # one
```

If you cannot run a terminal, say so plainly and ask for it to be run rather than
reporting a change as verified. Building both schemes is necessary and is not
sufficient.

---

## Where a change belongs

The question to ask about any new type is *would a third plug-in want this?*

| It is | Put it |
|---|---|
| Chords, scales, voice leading, progressions, **and rhythm algorithms** | `enkerli-swift` → `Sources/Theory` |
| A pattern, a note, measurement, curation of material | → `Sources/Carrier` |
| A control any plug-in could use | → `Sources/UI` |
| AU plumbing | → `Sources/Shell` |
| The UPI **notation** — a grammar, not an algorithm, and nothing else wants it | here |
| About rhythm as *this product* sees it | here |

**When in doubt, put it here.** Moving something down later is a `git mv` plus a
`public` sweep; moving it up is a compile error you find immediately. And a
foundation that grows by accident is the failure mode the whole layering exists
to prevent — see `PORTING.md` in [MelGen](https://github.com/Enkerli/MelGen),
which is where the reasoning lives.

Changing the foundation means changing another repo. Run *its* checks and
MelGen's `Scripts/verify.sh` too: MelGen is the other consumer, and a `public`
you narrow or a signature you change breaks it silently from here.

---

## Rules that are not negotiable

**The component triple is forever.** `aumi/Srpe/Enke` — not `RPEd`, which is the
JUCE Rhythm Pattern Explorer's and would collide with the AUv3 that build ships.
This project was scaffolded by copying ProgGenie's project file, which had been
copied from MelGen's, so it started life claiming somebody else's code twice
over. `Scripts/verify.sh identity` exists because that exact class of mistake
already shipped once. Never change the triple. The check reads every sibling
checkout, JUCE `CMakeLists.txt` and Swift `Info.plist` alike.

**Nothing generates on the audio thread.** Generation produces a whole
progression off-thread and hands the kernel already-decided notes. This is
inherited from the shell and it is load-bearing.

**The parser is held to vectors, and gaps are named rather than hidden.**
`Scripts/verify.sh upi` classifies every case in
`packages/upi/vectors/upi.json` as PASS, DIFF or NOT PORTED, and
`UPIError.notPorted` is how the parser says which form it has not implemented.
Adding a form means deleting a `.notPorted` and watching the count move. Never
make a DIFF go away by editing the vectors — they are the monorepo's, and the
whole value of them is that this codebase does not get a vote.

**Leftmost = LSB.** First step is bit 0; hex and octal digit strings are
little-endian. Tresillo is `10010010` = `0x94` = `d73`, and `0x49` is a real
pattern and the wrong one. This is the single thing a port silently inverts and
the vectors carry both side by side to catch it.

---

## House style

The prose in this repo — comments, commit messages, documents — explains *why*,
records what was measured, and says plainly what is not known. A comment that
restates the code is noise; a comment naming the bug that made the code look like
that is the reason the file is readable a month later. When you are unsure
whether something works, write that down instead of rounding up. The README's
"What has not been done" section is the model.
