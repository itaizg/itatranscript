<!--
Sync Impact Report
==================
Version change: (none) → 1.0.0
Bump rationale: initial ratification. The constitution is new to this repository; it applies every
principle, gate, constraint and governance rule of the photo-crawler constitution (v2.2.1),
adapted from that project's crawler/Airflow context to this project's mission (live captions,
Phase 0 engine benchmark, cross-platform app).

Template: the repository has no Spec Kit template resolver (`.specify/scripts/python/
resolve_template.py` is missing), so the core `constitution-template.md` from the photo-crawler
Spec Kit install was used as the scaffold. Its five-principle skeleton was expanded to twenty
principles to carry every photo-crawler principle.

Principle mapping (photo-crawler → itatranscript):
  - I. Assignment Fidelity → I. Mission Fidelity (`MISSION.md` replaces `assignment.md`)
  - II. Typed Code, Checked by ty → II. Typed Code, Checked Statically (ty for Python,
    strict analyzer for Dart)
  - III. One Linter and Formatter: ruff → III. One Linter and Formatter per Language
  - IV–VI → IV–VI (same names; tests, KISS/YAGNI/DRY, SOLID/Demeter/coupling)
  - VII. Pythonic Code → VII. Idiomatic Code (Python and Dart idioms)
  - VIII. Exceptions Only at Boundaries → VIII (same name)
  - IX. Immutability by Default, with Pydantic Models → IX. Immutability by Default, with
    Validated Models (Pydantic for Python, immutable value classes for Dart)
  - X–XII → X–XII (same names)
  - XIII. Security by Default → XIII. Security and Privacy by Default (mission privacy rules
    added)
  - XIV. Zero Trust → XIV (same name)
  - XV. Stateless, Idempotent Tasks → XV. Stateless, Idempotent Runs and Sessions
  - XVI–XX → XVI–XX (same names)
Added sections: Core Principles I–XX, Quality Gates and Automation, Project Constraints,
Governance.
Removed sections: none (first version).

Follow-up TODOs (repository changes, not made by this amendment):
  - Add the Spec Kit scripts and templates to `.specify/` (resolver, plan/spec/tasks templates)
    so `/speckit-*` commands resolve templates in this repository.
  - When the harness code starts: add `pyproject.toml` with `[tool.ruff]` (rule families under
    Quality Gates) and `[tool.ty]`, `uv.lock`, and pydantic as a dependency.
  - When the app code starts: add `analysis_options.yaml` (strict modes, lints) and pin the
    Flutter SDK version.
  - Add `.pre-commit-config.yaml` and `.github/workflows/ci.yml` so the Quality Gates are
    enforced.
  - Add test clips, reference transcripts and harness results paths to `.gitignore`
    (Project Constraints, "Consented recordings").
  - If the Phase 1 stack spike picks a framework other than Flutter, amend Principles II, III,
    VII, IX and the Project Constraints before app code is written.
-->

# itatranscript Constitution

## Core Principles

**Inheritance.** This constitution inherits the team constitution of team-ai-directives
(`context_modules/constitution.md`) and carries it at the same weight as this project's own
principles. Every team principle appears below, either as its own principle or merged into the
project principle that already covers it (team 5 → IV, team 11 → V). Both documents rank below
`MISSION.md` (Principle I); no team principle may widen the mission's scope.

**Origin.** These principles apply, one for one, the principles of the photo-crawler
constitution (v2.2.1), adapted to this project's mission and stack.

### I. Mission Fidelity

- `MISSION.md` is the single authoritative source of requirements. Every spec, plan, task, and
  line of code MUST trace to a goal, constraint, success criterion, or implementation step in
  it. If something contradicts it, you have to ask the user explicitly
- The system MUST deliver everything the mission lists for the current phase, with no
  omissions:
  - Phase 0 (benchmark): consented clips with hand-corrected transcripts; a Mac CLI harness
    that streams each clip in real time through the engine interface; adapters for the OS
    on-device speech baselines, 2–3 cloud streaming providers with Hebrew, and a
    Whisper/ivrit.ai streaming setup; WER, time to first word, time to final and cost per
    hour, with VAD + noise suppression on/off as a variable. Output: an engine per language,
    a decision on an external mic, and locked S3 thresholds.
  - Phase 1 (MVP): a stack spike; the app on iOS first (mic → VAD/noise suppression →
    winning engine → caption screen, with config and a lock-screen widget); real use in G1
    and G3, then S1–S8 measured.
- Mandated design MUST NOT be substituted: one cross-platform codebase, with native plugins
  only where the OS forces it; the engine interface
  `audio in → {partial|final text, timestamps, speaker-change}`, shared by the app and the
  harness; engine, language mode, API keys and cost cap in config, not code; one caption
  screen with three controls (start/stop, freeze, language); OS built-in captions used only
  as a benchmark baseline and fallback.
- Scope MUST NOT grow beyond the mission. Its non-goals (audio playback into ears,
  summaries, translation, any LLM layer, accounts, sync, sharing, app store, monetization,
  full speaker labels, guaranteed offline mode) and its "Later" items stay out until the
  mission brings them in. An addition is allowed only when a mission requirement cannot be
  met without it, and that need is written down.
- Where the mission is silent or leaves a choice open, the choice MUST be recorded as a
  decision (in the spec, a decision record, or the README) that cites the mission text it
  serves. A recorded decision never overrides the mission.
- Speech models are used as-is (pre-trained or hosted); no training or fine-tuning is
  performed, since the mission chooses engines from benchmark results.

Rationale: the mission is the contract for what this product is. Any deviation, omission, or
unrequested addition is a defect against it, regardless of engineering merit.

### II. Typed Code, Checked Statically

- Every function, method, and module-level variable in project code (harness, adapters, app,
  native plugin glue, and tests) MUST carry type annotations, including return types
  (`-> None` and `void` included).
- Python: `ty check` MUST pass with zero errors on every commit to `main`. Modern Python 3.13
  syntax MUST be used: `list[str]`, `X | None`, the `type` statement for aliases, and PEP 695
  generics; `typing.List`, `Optional`, and `Union` MUST NOT be used.
- Dart: `dart analyze` MUST pass with zero issues, with `strict-casts`, `strict-inference`
  and `strict-raw-types` enabled. `dynamic` and implicit `dynamic` are treated as `Any`.
- New suppressions (`# type: ignore`, `# ty: ignore`, `// ignore:`) MUST name the specific
  rule and give a one-line reason.
- `Any` / `dynamic` is permitted only at true trust boundaries (provider stream messages and
  HTTP responses, platform-channel messages, config files, clip and transcript files) and
  MUST be narrowed to a validated model (Principle IX) before it crosses into project logic.
- Seams between components (audio source, VAD/noise suppressor, engine adapter, caption
  assembler, config store, stats store) MUST be typed interfaces (Python `Protocol`, Dart
  `abstract interface class`), so that a non-conforming implementation fails the type check,
  not a live session.

Rationale: the code is read and defended line by line in review; types are the cheapest
documentation that cannot drift, and the checker catches contract breaks before a benchmark
run or a real conversation.

### III. One Linter and Formatter per Language

- Python: `ruff check` and `ruff format --check` MUST pass on every commit. ruff is the sole
  Python linter and formatter; black, isort, flake8, and pylint MUST NOT be added. Rule
  selection lives only in `pyproject.toml` under `[tool.ruff]`.
- Dart: `dart analyze` and `dart format --set-exit-if-changed` MUST pass on every commit; lint
  selection lives only in `analysis_options.yaml`. No second Dart linter is added.
- Changes to the selected rule sets are deliberate commits with a stated reason, never
  incidental.
- Per-line suppressions (`# noqa`, `// ignore:`) MUST name the rule code.

Rationale: one tool per language, one config file each, zero style debate in review.

### IV. Tests Are the Contract and Drive Confidence

- Python tests MUST use pytest and live under the harness's `tests/`; Dart tests MUST use
  `flutter test` / `package:test` and live under the app's `test/`.
- Unit tests MUST run with no network access beyond loopback, no microphone, no GPU, no
  downloaded model weights, and no API keys. Providers are replaced by recorded event streams
  or a deterministic fake engine behind the engine interface; audio comes from fixture files;
  time comes from an injected fake clock.
- Tests are written before or alongside the logic they cover. Every behavior change MUST ship
  with a test that fails without the change. Bug fixes MUST include a regression test.
- Tests MUST assert observable behavior, not existence. A test that would still pass if the
  feature were broken (asserting only that a function returns, that an object is not null,
  or that a mock was called) counts as a missing test.
- Each mission requirement (Principle I) MUST be covered by at least one test that asserts
  its observable outcome, for example: every adapter emits events that conform to the engine
  interface; WER is computed per language against reference transcripts; partial text is
  replaced by final text; silence-only input produces no text; speaker-change events produce
  markers; freezing the view loses no segments; switching the engine in config needs no
  rebuild; no audio is persisted after a session ends; session stats contain no audio or
  caption text.
- Tests MUST be deterministic: seeded randomness, injected clocks, no wall-clock or ordering
  dependence.
- Live benchmark runs against real engines are evaluations, not unit tests: they are run
  explicitly, never by default and never in CI (Quality Gates).
- A change MUST NOT ship when coverage of a requirement it touches is missing, or when its
  tests pass without exercising the behavior.

Rationale: the mission's requirements are only met if a test proves them; an untested
requirement is an unverified claim, and a hollow test is worse because it hides that.

### V. Simplicity First: KISS, YAGNI, DRY

- KISS: choose the most direct construct that solves the current problem. A plain function
  beats a class; the standard library and SDK beat a dependency. Validated models are the one
  accepted exception for data records (Principle IX).
- YAGNI: build only what the mission requires (Principle I). An abstraction, option, or hook
  is added only when a concrete current use requires it. The trigger is the second real
  instance, not the anticipated one. The engine interface is the mission's own required
  abstraction, not a speculative one.
- Implementation ladder: before writing code, stop at the first rung that holds:
  1. Does this need to exist? If not, skip it.
  2. Is there a built-in language or platform capability (OS speech, OS audio session,
     OS VAD)? Use it.
  3. Is there a native framework or runtime feature (Flutter, the provider's SDK, Pydantic)?
     Use it.
  4. Is there an already available dependency? Use it.
  5. Is it one line? Write one line.
  6. Only then write the minimum that works.
- DRY: each fact (the engine interface event schema, language modes, the WER normalization
  rules, the latency definitions for first word and final text, cost-per-hour figures,
  success-criteria targets) has exactly one authoritative location. Facts shared by the
  Python harness and the Dart app live in one language-neutral definition that both sides are
  tested against. Duplication of *knowledge* MUST be removed; incidental similarity of code
  that may diverge MAY remain.
- When KISS/YAGNI and DRY conflict, prefer the simpler code and accept small duplication until
  a third occurrence proves the shared shape.
- Trust-boundary validation, privacy guarantees, security, and failure visibility are never
  removed in the name of simplicity.

Rationale: a small system is one the author can own and explain end to end, and one simple
enough that grandma can use it.

### VI. Structure: SOLID, Law of Demeter, Low Coupling, Convention over Configuration

- Single responsibility: audio capture, VAD/noise suppression, engine adapters, caption
  assembly, display, settings, and session stats are separate units. Widgets and native
  plugins are thin wrappers that call plain, testable code; business logic MUST NOT live in
  widget `build` methods, platform-channel handlers, or CLI argument parsing.
- Dependency inversion: core logic depends on interfaces and plain data, never directly on a
  provider SDK, a platform channel, an HTTP/WebSocket client, or the microphone.
  Collaborators are passed in (constructor or function arguments), not created inside the
  logic that uses them.
- Law of Demeter: a unit talks only to its direct collaborators. Chains reaching through
  another object's internals MUST be replaced by passing the needed value or asking the owner.
- Coupling and cohesion: modules communicate through typed data and interfaces, with no shared
  mutable state and no import cycles; things that change together live together. The app
  MUST NOT depend on the harness, and the harness MUST NOT depend on app UI code; they share
  only the engine interface definition.
- Convention over Configuration: sensible defaults (language mode, active engine, VAD and
  noise-suppression settings, no cost cap) live in one place; config entries exist to
  override them. New configuration knobs require a current need (see YAGNI).

Rationale: separated units make the app testable without a microphone or a network, and let
the harness and the app exercise the same engine adapters, as the mission requires.

### VII. Idiomatic Code

- Code MUST use the idiomatic construct of its language where one exists.
- Python:
  - comprehensions and generator expressions instead of loops that append or build dicts;
  - `pathlib.Path` instead of `os.path` and string path joins;
  - f-strings instead of `%` or `str.format`;
  - `with` statements for every resource (files, audio streams, network sessions);
  - `enumerate`, `zip(..., strict=True)`, tuple unpacking, and `itertools` / `functools`
    instead of index arithmetic;
  - generators and async iterators for streams (audio chunks, engine events);
  - truthiness checks (`if items:`) and `is None` / `is not None` comparisons;
  - `match` statements where they make branching on shape clearer than `if` chains;
  - keyword-only parameters (`*`) for configuration-like arguments.
- Dart:
  - sound null safety; the `!` operator only where non-null is proven and commented;
  - `final` by default and `const` constructors where possible;
  - collection `if`/`for` and spreads instead of building lists imperatively;
  - `Stream` and `async*` for audio chunks and engine events; `await for` to consume them;
  - records, patterns and `switch` expressions (Dart 3) where they make branching on shape
    clearer than `if` chains;
  - named parameters (`required` where mandatory) for configuration-like arguments.
- Java-style patterns MUST NOT be used: no getter/setter methods (use fields, properties, or
  model fields), no classes holding only static members (use top-level / module functions),
  no manual boilerplate for records (use validated models, Principle IX).
- Readability wins ties: a one-line comprehension or collection expression that needs a
  comment to be understood MUST be rewritten as a plain loop or a named helper.

Rationale: idiomatic code is shorter, matches what every reviewer of that language expects,
and lets the linter catch the non-idiomatic forms automatically.

### VIII. Exceptions Only at Boundaries

- `try`/`except`/`catch`/`finally` MUST be avoided where another construct does the job:
  - `with` statements, context managers, and Dart `dispose`/`close` owned by a single owner
    replace `finally` for cleanup; `finally` MUST NOT be used for resource release in
    Python;
  - model validation and explicit checks replace catching errors from bad data;
  - functions return `X | None` / `T?` (or an empty collection) for expected "nothing found"
    outcomes instead of raising and catching;
  - APIs that report outcomes instead of raising are preferred (stream error events, status
    codes, result values).
- Where an exception cannot be avoided, it MAY be caught only at a trust boundary: network and
  provider streams, the microphone and audio session, platform channels, file I/O for config,
  clips and transcripts, model inference, and the per-item failure-isolation point
  (Project Constraints, "Failure isolation"). There:
  - the narrowest exception type MUST be caught; bare `except:` and untyped `catch (e)` are
    forbidden, and catching all errors is permitted only at the single isolation point of a
    harness run or a caption session;
  - the `try` body MUST contain only the call that can raise;
  - the exception MUST NOT be swallowed: it is logged with its stack trace and counted
    (Principle XII), turned into a visible status (FR-021), or re-raised with its cause
    (`raise ... from err`, `Error.throwWithStackTrace`);
  - `contextlib.suppress` and `catchError` count as exception handling and follow the same
    rules.
- Exceptions MUST NOT be used for ordinary control flow.

Rationale: every `try` is a place where a failure can disappear. Keeping them few, narrow, and
at the edges makes the remaining failures loud and easy to trace, and a hidden failure in a
caption app means stale text shown as live.

### IX. Immutability by Default, with Validated Models

- Data records that cross a function or component boundary (audio chunk metadata, engine
  event, caption segment, caption session snapshot, engine profile, settings, session stats,
  test clip, evaluation result) MUST be immutable, validated models:
  - Python: Pydantic v2 models declared with `model_config = ConfigDict(frozen=True)`. Frozen
    dataclasses, `NamedTuple`, `TypedDict`, and plain dicts MUST NOT be used for such
    records.
  - Dart: `@immutable` classes with only `final` fields, `const` constructors where possible,
    value equality, and `copyWith`; collections held as unmodifiable views. Plain `Map`s MUST
    NOT be used for such records.
- Values from trust boundaries (Principle II) are parsed into these models
  (`Model.model_validate(...)`, a `fromJson` factory that checks every field), so invalid
  data is rejected at the edge, once.
- Functions MUST return new objects instead of mutating their inputs; changes to a record use
  `model.model_copy(update={...})` or `copyWith`. Fields hold immutable types (`tuple`,
  `frozenset`, nested immutable models).
- Settings are a single immutable model, the one place defaults live (Principle VI,
  Convention over Configuration).
- Module-level and global mutable state is forbidden; constants are immutable. Live session
  state is owned by one controller and exposed only as immutable snapshots.

Rationale: immutable, validated records make every function predictable and every boundary
checked once; a caption list that cannot be mutated behind the UI's back cannot lose text.

### X. Human Oversight Is Mandatory

- Every change produced by an AI agent MUST be reviewed by a human before it merges into
  `main`. An agent MUST NOT merge or approve its own pull request.
- Agents work inside the guardrails of this constitution and the Quality Gates; the human
  author is accountable for every merged line.

Rationale: autonomy speeds up the work, but accountability for the product stays with a
person.

### XI. Appropriate Delegation

- Deterministic decisions MUST be expressed as deterministic code or configuration: WER
  normalization, latency definitions, VAD thresholds, speaker-change display rules, retry and
  reconnect policy, cost estimates, the spending-cap warning, and success-criteria targets
  are values in code or config, never judgments delegated to a model at runtime.
- Speech models are used only for what requires them (speech recognition, and the language,
  timestamp and speaker-change signals they emit). No LLM calls are part of the app or the
  harness (mission non-goal).
- The engine per language is chosen from benchmark results, not reputation; during
  development, AI agents MUST NOT invent thresholds, targets, or provider choices ad hoc; each
  comes from a recorded decision (Principle I).

Rationale: a rule that a model re-decides on every call gives different answers on different
days; a rule in code gives the same answer every time.

### XII. Observability and Reproducibility

- All runtime code MUST log through the language's standard logging facility (Python
  `logging`, Dart `package:logging` or `dart:developer`); `print` MUST NOT be used outside
  the harness's user-facing report output.
- Logs MUST NOT contain audio, caption or transcript text, or secrets (Principle XIII).
- Every harness run MUST log, at its end, counts of what it processed, succeeded, skipped,
  and failed (for example: clips streamed, engine sessions completed, engine errors, clips
  scored).
- Every caption session MUST record its session stats on the device (time to provisional
  text, time to final text, session length, battery used, engine, language mode, errors and
  interruptions; spec FR-023).
- Skips, fallbacks, reconnects, and failures MUST be surfaced in those counts, stats and logs.
  A run MUST NOT report success while silently dropping work; a run in which every item
  failed MUST fail; a session MUST NOT show stale text as live.
- Runs are reproducible: each benchmark result records the clip set, engine, model or API
  version, configuration (including VAD/noise suppression on/off), and harness version. Model
  and dependency versions are pinned.
- Within the mission's scope this means logs, counts and on-device stats; no analytics,
  telemetry, or tracing service is added (Principle I: no accounts, no sync).

Rationale: silent successes that hide silent failures are the most expensive class of bug;
counts and stats make them visible on the first run.

### XIII. Security and Privacy by Default

- All external input MUST be validated before use: provider stream messages and HTTP
  responses, platform-channel messages, config files, clip audio files (format, sample rate,
  duration) and reference transcripts.
- Network traffic to engines MUST use TLS; certificate validation MUST NOT be disabled.
- Credentials follow least privilege, are provided as managed secrets (in the harness,
  environment variables from a git-ignored `.env`; in the app, the OS keychain/keystore), and
  are never hard-coded, committed, printed, or logged.
- Privacy (mission constraints): captured audio MUST NOT be saved on the device or any server
  after a session ends; transcripts are saved only on explicit user request; audio is sent
  only to providers whose terms (recorded in a decision) say they don't keep or train on
  audio, or that allow opting out; session stats never contain audio or text.
- Dependencies are pinned and updated deliberately.

Rationale: the app streams people's voices by design; every input is hostile until validated,
and every byte of audio is someone else's privacy.

### XIV. Zero Trust

- No component is trusted because of where it runs: the app and harness authenticate to every
  engine endpoint, and an engine's output is validated like any other external input.
- Each component gets only the access it needs: the app requests only microphone (and the
  background-audio capability the mission needs), not contacts, location or other
  permissions; each provider key is scoped as narrowly as the provider allows; the harness
  and the app use separate keys.
- Default or sample credentials shipped with SDKs or examples MUST NOT be used.

Rationale: a compromised key, provider, or plugin should not be able to reach more than its
own job requires.

### XV. Stateless, Idempotent Runs and Sessions

- Engine adapters and harness runs MUST NOT keep state between runs or sessions in memory or
  on local disk. Persistent state lives only in declared places: config, the keychain,
  benchmark result files, on-device session stats, and transcripts the user chose to save.
- Within a session, state passes between units as immutable snapshots and event streams
  (Principle IX), never through shared mutable objects.
- Runs MUST be idempotent: re-running the harness for the same clip, engine and
  configuration MUST replace that result, not duplicate it (results are keyed by clip, engine
  and configuration). Reconnecting an engine mid-session MUST NOT duplicate or drop caption
  segments.

Rationale: stateless, idempotent runs can be retried and re-run without corrupting the
benchmark, and a reconnect that duplicates text is as bad as one that loses it.

### XVI. Documentation Matters

- Assumptions, decisions, and data contracts (the engine interface event schema, the
  validated models, the results format, WER normalization rules, provider terms checks)
  MUST be documented in the repository, next to the code or in the README / spec.
- Public modules, classes, and functions MUST have docstrings / doc comments stating purpose
  and any non-obvious behavior; comments explain *why*, not *what*.
- Work handed between sessions or people leaves hand-off notes in the feature's spec
  directory.

Rationale: agents and humans both move fast only when the context is written down where they
will look for it.

### XVII. Think Before Coding

- Assumptions MUST be stated explicitly. When a requirement is ambiguous, ask instead of
  guessing; when several interpretations exist, present them.
- Read before writing: understand adjacent code and nearby files before adding code.
- When the codebase disagrees with itself, flag the conflict and pick one side; MUST NOT
  produce code that half-satisfies both.
- Push back when a simpler approach exists; stop and name what is unclear when confused.

Rationale: most wasted work starts from an unstated assumption.

### XVIII. Surgical Changes

- A change touches only what its task requires. Adjacent code, comments, and formatting are
  not "improved" in passing, and working code is not refactored without a task for it.
- New code matches the existing style and patterns, even where another pattern would be
  preferred; a second pattern for the same thing MUST NOT be introduced.
- A change removes the imports, variables, and functions that it made unused, and nothing
  else.

Rationale: small, focused diffs are reviewable (Principle X) and keep unrelated breakage out.

### XIX. Goal-Driven Execution

- Every task MUST have explicit, verifiable success criteria before work starts (spec-kit
  specs and tasks provide them, traced to the mission's S1–S9).
- Multi-step work states a short plan with how each step is verified, then loops until the
  criteria are met.
- After each significant step of long-running work, a checkpoint summarizes what was done
  and what was verified before continuing.

Rationale: strong success criteria let work proceed autonomously; weak ones demand constant
clarification.

### XX. Memory: Learn From Every Run

- Notable failures, surprises, and decisions from development, benchmark runs, and real-use
  sessions MUST be recorded so they are reused: in the feature's spec directory, and, when
  they generalize beyond this project, proposed to team-ai-directives through `/team-curate`.
- Recorded lessons are consolidated, not just appended: a new lesson that contradicts an old
  one replaces it.
- This principle governs the development process; it does not add runtime components
  (Principle I).

Rationale: without memory, every session starts from scratch; with it, the work compounds.

## Quality Gates and Automation

- pre-commit: `.pre-commit-config.yaml` MUST run ruff (check and format) and ty for Python,
  and `dart format` and `dart analyze` for Dart, on every commit. Hook revisions MUST be
  pinned to exact versions. Contributors MUST install the hooks (`pre-commit install`);
  bypassing them with `--no-verify` is not permitted for commits intended for `main`.
- ruff rule selection MUST include the families that enforce Principles VII and VIII, at
  minimum: `UP` (pyupgrade), `SIM` (simplify), `C4` (comprehensions), `PTH` (pathlib), `RET`
  (returns), `PIE`, `PERF`, `E722` and `BLE` (bare / blind except), and `TRY` (exception
  handling patterns). `analysis_options.yaml` MUST enable the strict modes of Principle II and
  lints that enforce Principles VII and VIII (for example `avoid_catches_without_on_clauses`,
  `prefer_final_locals`, `prefer_const_constructors`, `avoid_print`).
- GitHub Actions: `.github/workflows/ci.yml` MUST, on every pull request and push to `main`,
  run (1) all pre-commit hooks on all files, (2) pytest on Python 3.13 for the harness, and
  (3) `flutter test` for the app, for whichever of these exist.
- CI jobs MUST use least-privilege permissions (`contents: read` unless a job needs more),
  pinned action versions, and no secrets; consequently, live engine benchmarks never run in
  CI.
- A pull request MUST NOT merge with a failing or skipped required check, and MUST NOT merge
  without human review (Principle X). The local gate and the CI gate run the same tools at
  the same versions, so "passes locally" implies "passes in CI."
- Before a deliverable is declared done, it MUST be run for real: for Phase 0, the harness
  streams the full clip set through every candidate engine and the decision report's numbers
  come from that run; for Phase 1, the app runs on a physical iPhone in a real G1 or G3
  situation, and S1, S2 and S7 are read from that session's stats.

## Project Constraints

- Languages and runtimes: the harness, if written in Python, uses Python 3.13 managed with
  `uv` and pinned in `uv.lock`; CI installs with `uv sync --locked`. The app uses Flutter
  (Dart), the mission's lead candidate, with the SDK version pinned and `pubspec.lock`
  committed. Any other language, or another framework chosen by the Phase 1 spike, requires
  an amendment before code is written (Governance, "No divergence").
- Python execution: every Python command run in this repository (scripts, tests, tools,
  Spec Kit scripts, hooks, CI steps, and commands in the docs) MUST go through `uv run`
  (project environment) or `uvx` (one-off tools). `python`, `python3`, and `pip` MUST NOT be
  invoked directly.
- Core libraries: Pydantic v2 for Python data records and settings; immutable value classes
  for Dart (Principle IX).
- Native code is limited to what the OS forces (lock-screen widget, background audio, OS
  speech engines) and stays a thin plugin behind a typed interface (Principle VI).
- Shared engine contract: the harness and the app MUST use the same engine interface event
  schema, the same latency definitions, and the same engine configuration, read from one
  shared definition. A mismatch makes benchmark numbers meaningless for the app.
- Result integrity: benchmark numbers, locked S3 thresholds, success-criteria evidence, and
  README example outputs come only from executed runs; no simulated or hand-filled results.
- Consented recordings: test clips are recorded only with the consent of everyone in them.
  Clips and reference transcripts MUST NOT be committed to the repository; they live in a
  git-ignored location.
- Provider etiquette and cost: each provider is used within its terms and rate limits; the
  estimated cost per hour of every engine is recorded, and the optional spending cap is
  honored when set.
- Failure isolation: in the harness, a failure on one clip or engine MUST NOT stop the run;
  every other item is still processed. It MUST NOT go unnoticed either: the run is marked
  failed after the work has finished, and the cause is visible in the logs and the run's
  failure count (Principle XII). In the app, a network, microphone, or engine failure MUST
  NOT end the session silently: the user sees a clear status (spec FR-021) and captioning
  resumes automatically when the cause clears.
- Secrets: in the harness, environment variables from a git-ignored `.env`; in the app, the OS
  keychain/keystore; never committed, never printed or logged.

## Governance

- Precedence: `MISSION.md` first. Below it, the team constitution (team-ai-directives
  `context_modules/constitution.md`) and this constitution rank equally. Everything else
  (specs, plans, decision records, `CLAUDE.md`, ad-hoc habit) ranks below both.
- Conflicts between equally ranked principles: apply both where possible; otherwise the
  stricter requirement wins. Where neither is stricter, the choice MUST be recorded as a
  decision in the PR description. No principle may widen the mission's scope.
- No divergence: code that is written or added MUST conform to `MISSION.md`, the team
  constitution, and this constitution. A change that diverges from them MUST NOT merge. If
  the divergence is wanted, the governing document is amended first, explicitly and with the
  user's approval; code never leads a document out of date.
- Team constitution changes: when the team constitution changes, this document MUST be
  re-synced through `/speckit-constitution` so the inheritance stays complete.
- Amendments are made by a commit or pull request that edits this file, updates the Sync
  Impact Report, and bumps the version, and MUST be explicitly approved by the user. The same
  applies to changes to the team constitution or to how this project applies it; neither is
  changed implicitly. No amendment MAY weaken Principle I. Any amendment that introduces a
  new gate MUST land together with, or be immediately followed by, the tooling change that
  enforces it.
- Versioning (semantic): MAJOR for removing or redefining a principle or gate; MINOR for a new
  principle or section or materially expanded guidance; PATCH for clarifications and wording.
- Compliance: every pull request review MUST check the change against Principles I–XX and the
  Quality Gates. Deviations from Principles II–XX require an explicit, written justification
  in the PR description; deviations from Principle I are not permitted.
- Spec Kit plans (`/speckit-plan`) MUST include a Constitution Check that maps the design to
  the mission requirements it implements and evaluates it against these principles before
  implementation begins.

**Version**: 1.0.0 | **Ratified**: 2026-11-18 | **Last Amended**: 2026-11-18
