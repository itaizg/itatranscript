# Contract: Caption Screen (UI)

## Controls (FR-009, MISSION: three controls)

1. **Start/Stop**: a large toggle.
2. **Freeze**: the visible lines stay fixed while capture continues. Tap it again, or tap the "jump to live" chip, to resume.
3. **Language**: cycles `auto → he → en`. It shows the current mode, and a change applies at the next VAD pause (research R-14).

Settings, export and stats sit behind one overflow icon, so they don't count as caption controls.

## Display rules

| Rule | Spec |
|---|---|
| The newest line is the largest and full-contrast; older lines are smaller and dimmer | FR-007 |
| Provisional text is grey italic; final text is full-contrast upright | FR-008 |
| A speaker change shows as a thin divider with a colored dot | FR-006 |
| Alignment is per segment: Hebrew right-aligned, English left-aligned | FR-003 |
| Scrolling up pauses auto-scroll and shows a "jump to live" chip | FR-010 |
| `unknown` language shows as a dim `[unrecognized]` | edge case |
| High contrast, dark theme by default | SC-006 |

The widget only renders snapshots from the session controller. No logic lives in `build` (VI).

## Status banners (FR-021)

| State | Banner |
|---|---|
| `fallback` | Amber badge: "offline – lower accuracy" |
| `paused_offline` | Red: "captions paused – no connection" |
| `paused_mic` | Red: "paused – mic in use", with the reason |
| `ended` by OS kill | On return: "captions stopped at HH:MM" |
| Battery low (`shared/pipeline.yaml` `battery_warning`) | Amber: "battery low – about N min left" |
| Cost cap at 90% / 100% | Sheet offering to continue or switch to a free engine |

Banners never cover the newest line.
