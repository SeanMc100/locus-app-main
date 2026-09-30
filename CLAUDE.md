# Locus

## Purpose & audience

Locus is a journaling app for **emotional fitness**: helping people become
more in tune with, and in control of, their own emotional reactions. Target
user is broader than committed Stoics (though they're in scope). Stoicism
is the mechanism, not the goal.

Core premise (Stoic, and shared with CBT): we're disturbed less by events
than by our **judgements** about them. The distress worth targeting is
*disproportion*: suffering bigger than the facts support. Judgements that
cause it tend to be factually inaccurate ("I'll be alone forever"),
true-but-inflated in scope/stakes (one rejection -> proof of worthlessness),
or misplaced value (treating an external as if your good depends on it).
Not every painful feeling is an error (grief can be proportionate), so the
app must never imply "you overreacted."

## Current default: skills toolkit (2026-09-29)

After writing, **Save** stores the entry and offers an optional **Work
through this**: structured CBT / DBT / ACT skills. The earlier question /
judgement / sort flows are intact behind
`FeatureFlags.useLegacyPostEntryFlow` (`Locus/App/FeatureFlags.swift`);
`true` restores them and hides all toolkit UI.

Note: this deliberately goes against two earlier principles below (it uses
distortion labels and clinical CBT/DBT/ACT framing), at the user's request.
The core rule carries over: **the user does the cognitive work**. Nothing
writes a balanced thought, reframe, or conclusion for them; AI only asks,
finds, or matches.

- **Storage:** skills models (`Locus/Models/Therapy/`) live in a second,
  local-only SwiftData store (`Application Support/Skills/skills.store`,
  no CloudKit, iOS file protection `completeUnlessOpen`). Journal entries
  keep syncing via `default.store`. Links are by `JournalEntry.linkID`
  (assigned lazily). Tool answers are JSON in `TherapySession.payload`
  (`ToolData.swift`): new fields there must be optional.
- **Flow:** `TherapyFlowHost` (safety check -> method picker / "Help me
  choose" -> tool -> completion, with next steps). Each tool is a
  `…Flow` view on `StepScaffold`; drafts save on every change and resume
  from "In progress" in the toolkit home (journal toolbar grid icon).
- **Safety:** `RiskDetector` + editable `Data/SafetyPhrases.swift` run on
  entries, captures, and every step (`SafetyGate`). AI can only escalate
  (`RiskDetector.escalate`). Safety screen: 988, Crisis Text Line, 911,
  safety plan; never blocking.
- **AI:** `TherapyAIService` (protocol) -> `OnDeviceTherapyAIService`
  (Foundation Models) or `OfflineTherapyAIService`; `TherapyAI` applies
  guardrails (`AIGuardrails`), timeouts, and fallbacks. Off by default
  (Settings). `RemoteTherapyAIService` is an unwired cloud stub.
- **Editable data:** `Locus/Data/` (emotions, distortions, Socratic
  question bank, safety phrases, catalog of skills/activities/values).

Testing: `LocusUITests` walks every flow end to end (`-uiTesting` uses
in-memory or throwaway stores; `-seedSkillsDemo` adds sample records).
Pure logic (risk, router, insights math, spaced repetition, guardrails,
and the on-device AI prompts) is tested in the Mac harness with `swiftc`,
since those files are Foundation-only.

## Direction (as of 2026-09-26)

The app is pivoting from the original dichotomy-of-control sort toward
**judgement work**, done in a "first-principles" way, not clinical CBT
(no distortion labels, no pathology framing).

Principles the user has settled on:
- **No templated journal.** The blank page stays blank; venting is the raw
  material. Structure only comes *after* writing.
- **Replace, don't just remove.** The goal isn't a judgement-free journal;
  it's truer, believable judgements (not affirmations). Long-term target is
  Marcus Aurelius-style hypnomnemata: a journal that rehearses what's true,
  in the user's own words, ideally addressed to themselves as "you".
- **AI finds, the user rewrites.** AI may locate judgements; the
  reframing/replacement is always user-authored ("mirror back, don't
  instruct").
- **Feelings and self-observations are not judgements.** "I feel sad",
  "I blame myself", and "I keep replaying it" are honest reports; only a
  judgement *inside* them counts ("…because I'm useless").
- Long-term win condition: the user needs the post-writing step less over
  time because they start writing clean. A possible metric is judgements
  per entry trending down (but never a score to beat, or people will
  self-censor).

### Legacy default: question flow (`SessionFlowView.flow = .question`, 2026-09-26)

Write -> **one question** chosen for this entry -> written answer ->
summary. The idea: the journal creates the moment that shifts your
headspace (like "What would you say to a friend?" or "Why shouldn't you
do this?"), but a fixed question habituates after 2–3 uses, so the app
picks the right question for each entry and rotates. Aim: what a Stoic
teacher or a monk would ask. Decided: the answer is written; it always
asks something; when nothing fits, it says so visibly while testing.

- `QuestionMoves.swift`: the hand-written library, meant for the user
  to review and edit. ~20 "moves" (distance, evidence, control, burden
  flip, need underneath, acceptance, grief, evening review…), each with
  the `EntryState`s it fits, an "avoid when", and questions. `{crux}` in
  a question = the writer's own words; `Question("…", only: [...])`
  limits a question to certain states.
- `QuestionAsker.swift`: read (state + crux) -> model ranks fitting
  moves, least recently used of its top 3 wins (rotation across
  sessions) -> model chooses one of that move's questions. About 2s.
  Saves `question`, `questionAnswer`, `questionMove`, `questionNotes`.
- `QuestionAsker.showsDiagnostics` shows state · move · crux under the
  question and in history; "No move fit" is flagged in orange.
- Simulator: launch with `-sampleQuestion` for canned output.

Learned in the Mac harness (2026-09-26), don't retry: letting the model
**write** questions gave clumsy or off-topic ones, so it only chooses.
Naming self-harm in the reader's instructions trips the input guardrail
on **every** entry, which is why the crisis state is worded as "may not be
safe". The crux must be a belief, not a fact: "Were they right?" about
"My dog died" was cruel. Rhetorical-question cruxes are dropped.
`stopArguing` is not offered for loss, and `wisestYou` is not offered
for urges ("trust yourself" read as permission).

**Real-device feedback (2026-09-26): the move-matching approach was
"quite bad".** It keyed on phrases out of context ("I'm not sure how
it's going to go" was curiosity, read as worry) and asked in-the-moment
coping questions (CBT/ACT-style triage) instead of deepening thought.
What the user wants is **Socratic, contemplative depth**: take an idea
in the entry and open it up. Their example, for an entry about letting a
friend go because "I couldn't control my feelings": "If you could
control your feelings for her, would they even be real?"

So `QuestionAsker.approach = .socratic` now routes to
`SocraticAsker.swift` (the model writes 5 candidates, then chooses one;
all candidates are shown in the diagnostics). Moves remain as `.moves`.
Harness finding: the ~3B on-device model occasionally writes a real
Socratic question ("If you think she misses you, why do you keep
deleting the message?"), but it misreads entries, invents beliefs,
asks interviewer questions, and picks poorly among its own candidates.
**Open decision for the user:** keep testing on-device vs. using a
stronger (cloud) model, which breaks the "everything stays on this
device" promise and needs consent, a backend, and has a cost.

### Judgement flow (`SessionFlowView.flow = .judgement`)

Write -> **RateBeforeView** ("How strongly do you feel this right now?",
0–10; `JudgementFinder` runs in the background meanwhile, so most of the
~5s wait is hidden) -> **JudgementsView** (stripped version first, titled
"What actually happened", toggle to "What you wrote" with highlights; the
re-rating sits below: "Reading just what happened, how strongly do you
feel it now?", worded so an unchanged rating is fine) -> **OwnWordsView**
(optional, Skip in the toolbar; segmented "To a friend" / "To yourself":
friend reply or truer judgement addressed to "you") -> summary. Saves
`judgements`, `withoutJudgements`, `intensityBefore`, `intensityAfter`
(nil if no judgements were found), and `friendReply` or `truerJudgement`
on `JournalEntry`. `JournalEntry.isSortFlow` distinguishes legacy
entries (don't use `friendReply.isEmpty` for that any more).

**User feedback after real-device testing (2026-09-26):** highlights are
"decent"; the **without-judgements version is the powerful part**. It
reads as "this is what you wrote… this is what actually happened." That
led to the current flow (decided 2026-09-26: re-rating over a free-text
reflection question; user picks friend vs truer judgement). Because the
stripped version is now front and center, strip accuracy matters more
than highlight accuracy: one bad strip (e.g. removing an honest
observation) breaks trust.

Not yet built: surfacing `truerJudgement`s as a personal collection, and
any use of the before/after ratings beyond showing them.

### Ideas to consider (not decided)

- **Training mode:** AI finds judgements but hides them; the user rewrites
  the entry themselves; the AI compares against what it found. Harder for
  the small on-device model (grading), and risks feeling like a test.
- **Personal collection:** keep the user's own best reframes and resurface
  them when a similar worry recurs (hypnomnemata = notes to reach for).
- **Real-time "judgement spellcheck"** while writing was considered and
  **rejected**: it interrupts venting and teaches people to write around
  their judgements instead of examining them. Post-writing review only.
- Old idea from the sort flow: an "are you sure?" nudge on ambiguous swipes.

## JudgementFinder (`Locus/Services/JudgementFinder.swift`)

On-device Foundation Models. `find(in:)`: two find passes over the whole
entry (unioned, because one pass randomly missed a clear judgement ~1/3
of the time), then a per-quote check pass (judgement / feeling /
observation / event) that drops non-judgements and trims to the judgement,
re-checking its own trim. `withoutJudgements(_:quotes:)`: cutting and
cleanup are done **in code** so wording is never paraphrased; the model
only repairs a sentence cut mid-way, and the repair is rejected if it adds
any word not already in the sentence. Takes about 5s per entry.

Tried and worse (don't retry): per-judgement kind labels; sentence-by-
sentence finding; asking the checker to split merged judgements; letting
the model rewrite the whole entry for the stripped version.

Known quirks: some highlights are narrow ("loser" vs "I'm such a loser");
a fact can be removed along with its judgement ("My brother didn't text
back…, he obviously doesn't care" goes whole); two judgements joined by
"and" sometimes stay one highlight. Calibrate by adding real failure cases
as examples to the check instructions; that's how the "I blame myself"
fix worked.

**Testing:** the iOS Simulator can't run Foundation Models on this machine
("no underlying assets … com.apple.modelcatalog", surfaces as
`LanguageModelError -1`). Use a real device, or a Mac harness: compile
`JudgementFinder.swift` + `ItemExtractor.swift` + a small `main.swift` with
`swiftc` (same on-device model, much faster to iterate). Run each test
several times, since results vary run to run. To click through the flow's UI in
the Simulator anyway, launch with `-sampleJudgements` (DEBUG only, e.g.
`xcrun simctl launch <udid> com.seanmcdonnell.Locus -sampleJudgements`):
it swaps in canned harness output that only matches the "Life sucks
today…" sample entry. A "Couldn't find judgements" / `-1` screen without
the flag means the Simulator hit the model limitation, not that the
flow works.

## Legacy: dichotomy-of-control sort flow (`SessionFlowView.flow = .sort`)

Journal -> AI item extraction (`ItemExtractor.swift`, "Whether…" clauses,
rules for surfacing implied fears and against over-merging) -> swipe-sort
(`SortCardsView`) -> for each not-in-control item, a user-authored "What's
yours to focus on instead?" counterpart (`CounterpartView`). Known weak
spot: extraction sometimes surfaces too few items; a soft minimum-count
nudge was considered but must not fight the "don't invent concerns" rule.
Whether this flow survives the pivot is undecided.

## Skills toolkit: status and handoff (2026-09-29, end of session)

All 7 build phases are implemented and the app builds with no errors or
warnings (`xcodebuild ... -derivedDataPath build/dd build-for-testing`).
Mac-harness tests pass: risk detector + router, insights math, spaced
repetition, AI guardrails, and the on-device AI prompts against the real
model. Harness sources live in the session scratchpad (lost). Recreate
them by compiling the Foundation-only files (`TherapyTypes`, `ToolData`,
`Data/*`, `RiskDetector`, `MethodRouter`, `AIGuardrails`, `InsightsMath`,
`TherapyAIService`, `OnDeviceTherapyAIService`) with a `main.swift`.

UI tests (`LocusUITests`, 29 tests): the last full run was on an older
build. Passing there: all of Phase 1 (6), Phase 2 except the experiment
test, all of Phase 3 (7), Defusion + Committed Action, archive capture,
quick capture → inbox → work through. The fixes for everything that
failed are in the current code but **not yet re-run**:
- Insights hang: a parent and the screen it pushed both held `@Query`s on
  the same model, so they re-rendered each other forever (97% CPU). Fixed:
  `InsightsView` has no live queries, and the toolkit home's diary query
  moved into `DiaryCardRow`. Verified by hand: Calibration and Patterns
  now open and are correct. **Don't reintroduce `@Query` in a view that
  pushes another view querying the same model.**
- Keyboard: dismissing it by swiping hit the suggestion bar (inserted
  words) or dragged sheets closed. Fixed: `KeyboardHideButton`
  ("Hide keyboard", toolbar) in the step scaffold and every sheet with
  text input; the test helper taps it.
- Test helper: an any-element query took ~30 s per check on chart
  screens; `expectText`/`field` now query specific element types.
  Failures attach a screenshot and the UI tree.
- Entry ⋯ menu now has `accessibilityLabel("More")`.

### To do next
1. Re-run the full UI suite and fix what's left. Split it across two
   simulators to halve the time, e.g. `-only-testing:LocusUITests/Phase1FoundationTests`
   (and Phase2CBTTests, Phase3DBTTests) on one, and Phase4ACTTests,
   Phase5CaptureTests, Phase6InsightsTests, Phase7AITests on the other.
   Tests that haven't passed yet: experiment scheduled → outcome
   ("If…" field), values clarification ("Importance 9/10" after the
   domain editor), entry ↔ session links, work through from history,
   strong capture → calming skill, Insights (empty states, computed from
   `-seedSkillsDemo`, if-then hit rate), and all of Phase 7 (AI toggle
   fallback, safety screen with AI on). Export passed.
2. Walk through on a real device with AI on (the Simulator can't run
   Foundation Models): the journal bridge chips, Socratic questions, the
   balanced-thought check, ledger match, pattern summary.
3. Known AI quality notes: summaries can misstate what numbers mean
   ("7 sessions of anxiety" = 7 ratings). Lines with invented numbers,
   percentages, or verdict words are already filtered
   (`AIGuardrails.cleanSummaryLine`).
4. Decisions for the user: find-a-therapist link (currently
   findtreatment.gov, US); crisis resources are US-only (988, 741741,
   911), so localize if needed; whether skills data should ever sync
   (currently never, by design); whether the old question/judgement
   flows get removed or stay behind the flag.
5. Not built / deviations to be aware of: no home-screen widget (quick
   actions instead: "Quick capture", "I need to calm down"); the "did your
   plan fire?" prompt is on the diary card and each plan row, not after
   every session; sleep/activity correlation is only a protocol stub
   (`ContextSignalProvider`); the situation step shows the journal entry
   rather than auto-extracting the situation.

## Next conversation should focus on

1. Real-device testing of the Socratic question flow (judge the candidates
   in the diagnostics, not just the pick), then the on-device vs. cloud
   model decision.
2. Whether the judgement flow's stripped version returns as one move.
3. Continuing to calibrate `JudgementFinder`; deciding what happens to
   the legacy sort flow.

## TODO — CloudKit follow-ups (2026-09-21)

CloudKit sync works (SwiftData + private CloudKit DB, `Locus/App/LocusApp.swift`);
new fields must keep default values to stay CloudKit-compatible.

- [ ] Re-test uninstall/reinstall a couple more times, including a cold
      start on a second device with the same Apple ID.
- [ ] Decide whether `DraftStore` (`UserDefaults`-only) should sync via
      CloudKit or stay local-only.

## Noise to ignore in the Simulator console

Simulator/system-level, not app bugs; don't chase them:
- Keyboard-factory warnings (`isKeyboardMinorEdgeWidth…`), and
  `CHHapticPattern` / `hapticpatternlibrary.plist` errors
- `cannot add handler to 0 from 0 - dropping`
- `Client not entitled` / `RBSServiceErrorDomain`
- Constraint conflicts involving `TUIPredictionViewCell` /
  `TUICandidateGradientContentLabel`
- `Invalid UIScreen coordinate space conversion` / `Conversion error!`
- `glassEffect() tried to update multiple times per frame`
- `BGSystemTaskSchedulerErrorDomain Code=3` for
  `com.apple.coredata.cloudkit.activity.export...` (Xcode-relaunch
  artifact; doesn't affect sync)
