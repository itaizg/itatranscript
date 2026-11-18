# Feature Specification: Live Captions for Hard Listening Situations

**Feature Branch**: `feat/phase-0`

**Created**: 2026-11-18

**Status**: Draft

**Input**: User description: "mission.md" (the mission brief at `MISSION.md`, v3)

## Clarifications

### Session 2026-11-18

- Q: Should grandma's simple mode on Android count toward v1 being done, or come later? → A: Later. v1 is iPhone only. Story 6, FR-012 and SC-009 are post-v1.
- Q: When the iPhone locks or the app goes to the background mid-session, what should captions do? → A: Keep capturing. When the user unlocks, everything said in the meantime is there.
- Q: Should the app keep speed and reliability stats from real sessions, without audio or text? → A: Yes. Keep them per session on the device only, with no audio or caption text, and let the user view and delete them.
- Q: If a cloud engine loses its connection mid-session, what should happen? → A: Switch automatically to an engine on the phone, show an "offline – lower accuracy" badge, and switch back when the connection returns.
- Q: When the user saves a session's transcript, how should v1 keep it? → A: Export only, as a text file with timestamps and speaker-change markers through the share menu. The app keeps no copy. A "test mode" setting also includes that session's stats in the export.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Follow a conversation in a noisy café (Priority: P1)

Itai is at a loud café or bar with one or two people. He sets his phone on the table and starts captions. What they say appears on screen as large text, in Hebrew, English, or both mixed in one sentence. He glances at it to keep up without asking them to repeat themselves.

**Why this priority**: This is the situation that hurts most today, and it is the reason the product exists. If only this story ships, it is already useful.

**Independent Test**: Run a live session in a real noisy café with one or two speakers. Check that captions appear fast enough to keep up, are readable from arm's length, and are accurate enough to follow the gist.

**Acceptance Scenarios**:

1. **Given** captions are running, **When** someone speaks, **Then** a provisional guess of their words appears within 1 second of their starting to speak, and becomes final within 2 seconds of their stopping (90% of the time; SC-001, SC-002).
2. **Given** captions are running, **When** a speaker switches from Hebrew to English mid-sentence, **Then** both parts are captioned in the language spoken, without the switched words being dropped.
3. **Given** captions are running, **When** nobody speaks but there is background clatter or music, **Then** no made-up words appear.
4. **Given** captions are on screen, **When** Itai glances from arm's length, **Then** the newest line is the most prominent, and provisional text looks visibly different from final text.

---

### User Story 2 - Pick the best speech engine using my own recordings (Priority: P2)

Before relying on the tool, Itai records consented clips from his real situations and hand-corrects their transcripts. He then compares the candidate speech-recognition options on those clips. Each option is scored on accuracy, speed and cost, per language and per situation, so he can choose with evidence rather than reputation. He can also change the active engine later without the app being rebuilt.

**Why this priority**: Hebrew streaming quality is the biggest unknown. Story 1's accuracy depends on this choice, and the accuracy targets (SC-003) get set from it.

**Independent Test**: Run the comparison over the recorded test set and get a report showing accuracy, time to first word, time to final text and cost per hour for every option. Switch the active engine in settings and confirm the captions screen uses the new one.

**Acceptance Scenarios**:

1. **Given** a set of recorded clips with corrected reference transcripts, **When** the comparison runs, **Then** each engine gets accuracy, first-word time, final-text time and cost per hour, with Hebrew, English and mixed reported separately.
2. **Given** the comparison is run with and without noise cleanup, **When** results are reported, **Then** the effect of the cleanup is visible for each engine.
3. **Given** the comparison results, **When** Itai changes the active engine in settings, **Then** the next caption session uses that engine, with no rebuild.
4. **Given** the active engine has a cost, **When** Itai opens settings, **Then** he sees its estimated cost per hour. If he has set an optional spending cap, he is warned before it is exceeded.

---

### User Story 3 - Not miss a question in a meeting (Priority: P3)

In an in-person meeting or interview, Itai keeps captions running beside his notes. If he loses track, he freezes the view to re-read the last few lines while the session keeps capturing. He can scroll back through the session without it jumping to the bottom.

**Why this priority**: Missing a question in a meeting is costly. This builds on Story 1 by adding the review controls.

**Independent Test**: Run a mock interview, then freeze, scroll back and resume. Check that no speech is lost while frozen.

**Acceptance Scenarios**:

1. **Given** captions are running, **When** Itai taps freeze, **Then** the visible lines stop moving and capture continues in the background.
2. **Given** the view is frozen or scrolled back, **When** Itai resumes, **Then** the view jumps to the newest line, and speech said in the meantime is all there.
3. **Given** Itai scrolls back, **When** new speech arrives, **Then** auto-scroll pauses until he returns to the bottom.

---

### User Story 4 - Know when the speaker changes in a group (Priority: P4)

At a family dinner with 3–6 people and overlapping speech, the captions mark each change of speaker. That way Itai can tell where one person's sentence ends and the next begins.

**Why this priority**: Group conversation is the second-most painful situation. Speaker-change markers are what v1 can reliably offer.

**Independent Test**: Play or record a group conversation with annotated turn changes, and count how many turn changes are marked.

**Acceptance Scenarios**:

1. **Given** captions are running in a group, **When** a different person starts speaking, **Then** a visible speaker-change marker appears before their words.

---

### User Story 5 - Start captions instantly (Priority: P5)

A conversation starts unexpectedly. From the lock screen or home screen, Itai gets to live captions in 2 taps or fewer.

**Why this priority**: If starting is slow, the start of the conversation is gone. This matters most once Stories 1–3 work.

**Independent Test**: With a stopwatch, go from the locked phone to captions showing speech.

**Acceptance Scenarios**:

1. **Given** the phone is locked, **When** Itai uses the captions shortcut, **Then** live captions are running within 3 seconds and 2 taps.

---

### User Story 6 - Simple mode for grandma (Priority: P6, post-v1)

Itai's grandmother uses the app on her own Android phone, in a simple mode: one button to start or stop and very large text, with no settings to get lost in. She uses it on her own, without help.

**Why this priority**: It's a second user with real need, but it ships in a release after v1, which is iPhone only. It isn't part of v1 acceptance.

**Independent Test**: Hand the phone to grandma in simple mode with no instructions beyond "press the button", and see whether she starts it and follows a conversation.

**Acceptance Scenarios**:

1. **Given** simple mode is on, **When** grandma opens the app, **Then** she sees a single start/stop button and nothing else to configure.
2. **Given** simple mode captions are running, **When** someone speaks, **Then** text appears larger than in the standard mode and follows the same speed targets as Story 1.

---

### Edge Cases

- **Network drops mid-session** with a cloud engine: captions continue on the on-device fallback engine with an "offline – lower accuracy" badge, and switch back automatically when the network returns (FR-024). The handover must not lose or duplicate speech.
- **Network drops and no on-device fallback can run** (e.g., language not supported on the device): the user sees a clear "captions paused – no connection" state, not stale text, and captioning resumes when the network returns.
- **Microphone permission denied or mic taken by another app** (e.g., an incoming call): the user is told why captions stopped and how to fix it.
- **Phone locks or app goes to the background during a session**: capture and captioning continue (FR-022). If the OS ends the session anyway, the user sees, on return, that it stopped and at what time.
- **Battery low**: the user is warned before the session would end unexpectedly.
- **Speech in a language other than Hebrew or English**: no confident-looking wrong text. It shows as unrecognized, or is left out.
- **Very long session (2+ hours)**: the transcript view stays responsive, and memory doesn't grow without bound.
- **Spending cap reached**: the user is told, and chooses whether to continue or switch to a free engine.
- **Two people talking at once**: text from both may interleave. A speaker-change marker is still shown when the dominant speaker changes.

## Requirements *(mandatory)*

### Functional Requirements

**Captioning**

- **FR-001**: System MUST turn live speech picked up by the device microphone into on-screen text continuously for the length of a session.
- **FR-002**: System MUST show provisional text while a phrase is being spoken, and replace it with final text once that phrase is settled.
- **FR-003**: System MUST caption Hebrew, English, and a mix of both within one sentence.
- **FR-004**: Users MUST be able to set the language mode to Hebrew, English or automatic (mixed).
- **FR-005**: System MUST suppress background noise and ignore non-speech sound, so silence and clatter don't produce text.
- **FR-006**: System MUST show a visible marker when the speaker changes.

**Display and controls**

- **FR-007**: The caption screen MUST use large, high-contrast text, with the newest line visually most prominent.
- **FR-008**: Provisional text MUST look visibly different from final text.
- **FR-009**: Users MUST be able to start and stop captions, freeze the view, and change language mode from the caption screen. No other controls are required on that screen.
- **FR-010**: Auto-scroll MUST pause when the user scrolls back, and resume when they return to the newest line.
- **FR-011**: Users MUST be able to reach live captions from the lock screen or home screen in at most 2 taps.
- **FR-012** *(post-v1)*: System MUST offer a simple mode with a single start/stop control and extra-large text, and with settings hidden.

**Engines and settings**

- **FR-013**: Users MUST be able to choose the active speech-recognition engine in settings, without changing or rebuilding the app.
- **FR-014**: System MUST show the estimated cost per hour of the active engine.
- **FR-015**: Users MUST be able to set an optional monthly spending cap, which is off by default. System MUST warn before the cap is exceeded.
- **FR-016**: System MUST provide an evaluation that runs the same recorded clips through each candidate engine. It reports accuracy against reference transcripts, time to first word, time to final text and cost per hour, scored separately for Hebrew, English and mixed speech.
- **FR-017**: The evaluation MUST be able to compare results with and without noise cleanup.

**Privacy**

- **FR-018**: System MUST NOT keep captured audio on the device or on any server after a session ends.
- **FR-019**: System MUST NOT save transcripts unless the user explicitly exports the current session. Export produces a text file with timestamps and speaker-change markers, handed to the phone's share menu. The app MUST NOT keep its own copy.
- **FR-025**: Users MUST be able to turn on a "test mode" setting, off by default. When it's on, an export also includes that session's stats (FR-023).
- **FR-020**: System MUST send audio only to speech services whose terms state they don't keep audio or train on it, or that let the user opt out.
- **FR-021**: System MUST show clear status for loss of network, microphone or engine, and never show stale text as if it were live.
- **FR-022**: A running session MUST keep capturing and captioning while the phone is locked or the app is in the background. When the user returns, all speech from that period MUST be in the session, and the view MUST jump to the newest line.
- **FR-023**: System MUST record session stats for every session, on the device only: time to provisional text, time to final text, session length, battery used, engine, language mode, and errors or interruptions. Stats MUST NOT contain audio or caption text. Users MUST be able to view and delete them.
- **FR-024**: When the active engine is remote and the connection drops, System MUST switch within 3 seconds to an on-device fallback engine and show an "offline – lower accuracy" badge. It MUST switch back automatically when the connection returns. Speech MUST NOT be lost or duplicated across the switch, and each switch MUST be recorded in the session stats.

### Key Entities

- **Caption Session**: one continuous run of captioning. It has a start and end time, language mode, active engine, and an ordered list of caption segments. Its text is discarded when the session ends unless the user exports it.
- **Caption Segment**: a stretch of recognized text. It has provisional or final status, a time span, a detected language, and whether a speaker change precedes it.
- **Engine Profile**: a selectable speech-recognition option. It has its name, supported languages, estimated cost per hour, whether it runs on the device or remotely, and whether it can be the offline fallback.
- **Settings**: active engine, offline fallback engine, language mode, display mode (standard/simple), test mode (on/off), and optional spending cap. Engine access keys are entered in settings but stored separately, in the phone's secure keychain.
- **Test Clip**: a consented recording from a target situation. It has its situation type, language (Hebrew/English/mixed) and a hand-corrected reference transcript.
- **Session Stats**: speed and reliability figures for one Caption Session (see FR-023). They're stored on the device, never contain audio or text, and the user can delete them.
- **Evaluation Result**: the scores of one engine on one clip. It has accuracy, time to first word, time to final text and cost.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In 90% of utterances, a provisional guess of the words appears within 1 second of the moment speech is detected starting. This is measured the same way in the evaluation and in real use.
- **SC-002**: In 90% of utterances, final text appears within 2 seconds of the moment speech is detected ending. This is measured the same way in the evaluation and in real use.
- **SC-003**: Word error rate in noisy one-to-one and group situations meets per-language targets (Hebrew, English, mixed). These targets are set and locked from the engine evaluation before the MVP is built.
- **SC-004**: Silence-only and noise-only test clips produce zero made-up words.
- **SC-005**: At least 80% of speaker turn changes in annotated group clips are marked.
- **SC-006**: Captions are readable from arm's length (about 60 cm) at a table, confirmed in real use in the café and meeting situations.
- **SC-007**: 2 hours of continuous captioning, including periods with the phone locked, uses no more than 60% of a full phone battery.
- **SC-008**: From a locked phone to live captions takes at most 2 taps and 3 seconds.
- **SC-009** *(post-v1)*: Grandma starts the app in simple mode and follows a conversation without help, on her first try.
- **SC-010**: v1 is accepted when SC-001 to SC-008 pass (SC-001, SC-002 and SC-007 measured from real-use session stats) and Itai has used it for real at least 5 times across café and meeting situations (MISSION: "used it for real at least 5 times in G1 and G3").

## Assumptions

- **Scope**: v1 covers noisy one-to-one talk, group conversation and in-person meetings. Lectures, phone/video calls, translation, summaries, full speaker naming, full-accuracy offline use, and audio playback into the ears are out of scope.
- **Users**: there are two people (Itai and his grandmother), each with their own device. There are no accounts, sync or sharing.
- **Devices**: v1 is iPhone only. The Android phone (grandma, simple mode) and the Mac come in later releases.
- **Microphone**: the phone's built-in mic is the default. The evaluation decides whether an external mic is needed.
- **Connectivity**: cloud engines need an internet connection. v1 includes an on-device fallback for connection loss (FR-024). The speed and accuracy targets (SC-001 to SC-003) apply to the active engine, not the fallback.
- **Accuracy targets**: SC-003 thresholds are intentionally left to be set from the evaluation, at the user's request.
- **Spending**: there's no spending cap by default. A cap is optional and set in settings.
- **Saving transcripts**: in v1, saving means exporting the current session as a text file (FR-019), with stats added in test mode (FR-025). An in-app transcript history comes later.
- **Consent and legality**: test clips are recorded only with the consent of the people in them. Live captioning without storing audio is assumed to be allowed for personal use, but should be checked before a cloud engine is chosen.
- **Evaluation**: the engine evaluation is driven from a computer and used by Itai only. The Android on-device baseline runs on a connected Android phone or emulator.
