# Changelog

## 0.3.3.0 Beta Release Candidate — Release Hardening

- Promotes the tested HelperProfiles and daily-payroll architecture into a beta release candidate.
- Preserves the working 0.3.2.1 payroll scheduler and accounting behaviour.
- Moves routine hour-by-hour payroll-clock messages behind `logLevel=debug`.
- Retains settlement, persistence, job and warning logs at normal log level.
- Adds a delayed consolidated startup status after optional integration APIs have had time to publish.
- Expands `hpayDump status` with release channel, pending rows and HelperProfiles API state.
- Clarifies management-screen wording for per-job versus per-worker/day minimums and callout fees.
- Updates README, testing guidance and release notes for beta validation.
- Keeps multiplayer and dedicated-server support disabled.

## 0.3.2.1 Alpha — Authoritative Daily Payroll Clock

- Uses `environment.currentMonotonicDay` as the authoritative payroll day.
- Uses `environment.dayTime` as the authoritative in-game clock.
- Runs payroll checks immediately when the game hour or monotonic day changes.
- Runs an immediate due check after a job is deferred.
- Persists the work monotonic day and day-time snapshot with pending rows and ledger entries.
- Migrates older pending rows from their saved game-date key.
- Adds `hpayDump clock` diagnostics for pending-row due state.

## 0.3.2.0 Alpha — Stable Identity and Daily Payroll Recovery

- Uses HelperProfiles API v3 stable A-J resolution instead of runtime helper-list position.
- Captures an immutable worker/payroll assignment when each AI job starts.
- Uses the captured identity, role and hourly rate when the job finishes.
- Persists unpaid daily-payroll rows in the current save settings file.
- Recovers legacy deferred daily-payroll jobs from the persistent ledger.
- Reconciles pending rows against existing payment entries to prevent re-payment.
- Pays overdue rows after the game advances to a later day, even before that day's payroll hour.
- Retains the HelperProfiles semicolon input handoff and standalone behaviour.


## 0.3.1.1 Alpha — HelperProfiles Input Handoff

- Suppresses HelperPayroll's standalone `;` role-cycle action when HelperProfiles is loaded.
- Suppresses HelperPayroll's `RCTRL + ;` role-list action when HelperProfiles is loaded.
- Leaves the semicolon key family entirely to HelperProfiles for the current session.
- Keeps management-menu and payroll-report shortcuts available.
- Preserves standalone role controls when HelperProfiles is absent.
- Adds suppression state to `hpayProfiles status`.

## 0.3.1.0 Alpha — HelperProfiles Payroll Mappings

- Added per-save HelperProfiles identity/slot payroll mappings.
- Added WORKERS management UI page for assigning roles to A-J workers.
- Added payrollMode editing to the Billing page.
- Added identity-first mapping resolution with slot fallback.
- Added helper identity and mapping source snapshots to persistent ledger entries.
- Requires no hard dependency; standalone roleType mode remains available.

## 0.3.0.2 Alpha
- Replaced appearanceLinks.xml-based detection with an optional shared runtime API.
- Detects whether HelperProfiles is enabled in the current game session.
- Reads selected slot and A-J display names from HelperProfiles 2.0.22+ through `g_currentMission.helperProfilesAPI`.
- Keeps standalone `roleType` mode fully functional without HelperProfiles.
- Added clearer diagnostics for mod-loaded/API-unavailable states.

## 0.3.0.1 Alpha
- Added HelperProfiles per-save appearanceLinks.xml bridge for cross-mod worker identities.
- Added `hpayProfiles reload` and clearer integration diagnostics.
- Preserved standalone roleType behaviour.

## 0.3.0.0 Alpha — HelperProfiles Integration

- Added HelperProfiles runtime detection.
- Added HelperProfiles slot identity lookup for helper slots A-J.
- Added `hpayProfiles status` and `hpayProfiles slots` diagnostics.
- In `helperSlot` mode, HelperPayroll can use HelperProfiles display names while preserving HelperPayroll slot role/rate mappings.
- Preserved standalone `roleType` behaviour.

## 0.3.0.0-alpha

- Alpha baseline polish for the tested standalone/vanilla-friendly feature set.
- Documented the final config split: global/default policy, per-save active settings, and per-save ledger history.
- Documented `hpayConfig` vs `hpaySave` diagnostic responsibilities.
- Updated testing notes and release notes for the current management UI and per-save settings model.
- No intentional payroll calculation, ledger, UI behaviour, or config-precedence changes from `0.2.3.5`.

## 0.2.3.5-alpha

- Changed the CCO-style management UI apply behaviour to write gameplay settings to the current savegame's `helperPayrollSettings.xml` instead of the global `defaultPayrollConfig.xml`.
- Added save-specific persistence for billing mode, payroll hour, minimum charge, callout fee, round charges, and active-profile role hourly rates.
- Updated UI wording from global policy XML to current save payroll settings.
- Changed the UI reset action to reset the current save from the global/default policy template without modifying the global template.

## 0.2.3.3-alpha

- Refined the CCO-style management UI.
- Removed the right-hand settings/details pane.
- Moved value changes into the main SmoothList table with inline left/right controls.
- Kept APPLY/DISCARD close to the table and retained reload/reset/back behaviour.
- No payroll calculation changes.

## 0.2.3.1 - Alpha UI Hotfix
- Fixed CCO-style management GUI load failure from missing selected-role helper.
- Replaced missing `buttonExtra2` GUI profile reference.

## 0.2.0.1 - Alpha Hotfix
- Fixed Lua compiler error in the external policy config writer caused by a malformed newline string.
- No gameplay behaviour changed from 0.2.0.0.

## 0.2.0.1 - External Policy Config Alpha

- Added an external player-editable payroll policy file at `modSettings/FS25_HelperPayroll/defaultPayrollConfig.xml`.
- On first run, HelperPayroll generates the external policy config from bundled defaults.
- The bundled `config/defaultPayrollConfig.xml` remains as the template and safe fallback.
- Added `hpayConfig` console command with `status`, `path`, `reload`, and `reset`.
- `hpayDump status` now reports policy config source/path.
- Policy reload resets and reloads role/rate/helper-slot tables safely without duplicating entries.
- Save-specific selected role, UI layout, and ledger data remain in the savegame-specific modSettings folder.
- Payroll calculations, role list UI, report overlay, and persistent ledger behaviour are unchanged from `0.1.9.1`.

## 0.1.9.1 - Alpha Release Candidate Polish

- Bumped mod version to `0.1.9.1`.
- Updated README, TESTING, and release notes for the vanilla-friendly alpha release candidate.
- Clarified the tested standalone `roleType` workflow.
- Documented the payroll report overlay controls and pages.
- Documented persistent settings and split persistent payroll ledger storage.
- Declared multiplayer unsupported for this alpha package until dedicated testing is completed.
- No payroll calculation, ledger, role UI, report overlay, or keybind behaviour changes from `0.1.9.0`.

## 0.1.9.0 - Alpha Report UI

- Added a basic read-only in-game payroll report overlay.
- Added `RCTRL + P` to open/close the report overlay.
- Added four report pages: Summary, Current Period, Recent Jobs, and Role Totals.
- `;` cycles report pages while the report overlay is open.
- Confirmed `RCTRL + ;` remains the role-list open/close shortcut, matching the relevant HelperProfiles modified shortcut pattern.
- Polished report number formatting for cleaner hours and currency output.

## 0.1.8.4 - First-run Ledger Guard

- Fixed first-run behaviour where an empty period XML file could be read before a valid `index.xml` existed.
- The mod now skips period-file loading until a valid ledger index exists.
- First payroll entry initializes the current period ledger cleanly.

## 0.1.8.3 - Ledger Write Guard

- Fixed FS25 sandbox issue where `os` can be nil when generating ledger timestamps.
- Added a billing safety guard so a post-charge ledger/report error cannot repeatedly charge the same finished AI job.

## 0.1.8.2 - Ledger XML Read Fix

- Fixed persistent ledger startup crash caused by raw `io.open(..., "r")` reads being blocked by the FS25 Lua sandbox.
- Ledger index and period files are now loaded using GIANTS XML APIs.

## 0.1.8.1 - Ledger Index and Period Files

- Added persistent payroll ledger folder per savegame.
- Added lightweight `ledger/index.xml` summary file.
- Added monthly/period ledger XML files such as `Y001_M06.xml`.
- Reports now default to persistent ledger data rather than only in-memory session data.
- Current period is loaded on startup; older periods are loaded only when requested.

## 0.1.8.0 - Payroll Reports

- Added `hpayReport` console command for payroll summaries.
- Added summary, job, daily, and export report commands.
- Added grouped output by role/helper.
- Added `hpayDump report` shortcut.

## 0.1.7.0 - Savegame Persistence

- Added per-savegame persistence under `modSettings/FS25_HelperPayroll/<savegame>/helperPayrollSettings.xml`.
- Persists selected role, active profile, payroll mode, fallback role, debounce, and overlay layout.

## 0.1.6.1 - Overlay Sizing Controls

- Added console controls for overlay position, scale, width, opacity, font size, row spacing, padding, max rows, background, outline, shadow, and debounce.

## 0.1.6.0 - Console Commands

- Added `hpayOverlay`, `hpayRole`, `hpayDump`, and `hpayReport` command foundations.

## 0.1.5.9 - Role List UI Polish

- Reworked the payroll role list into a HelperProfiles-style lightweight panel.
- Kept immediate active-role selection; no Enter/confirm step required.

## 0.1.5.8 - Role List UI

- Added a role list overlay for vanilla `roleType` mode.
- Added `RCTRL + ;` to open/close the payroll role list.
- Kept `;` as quick role cycle.

## 0.1.5.7 - HelperProfiles-style Role Cycle

- Replaced temporary next/previous controls with a single semicolon role-cycle action.

## Earlier alpha milestones

- Added vanilla helper wage suppression hooks.
- Added custom worker billing on job finish.
- Added minimum charge and optional call-out fee.
- Added daily payroll mode.
- Renamed the mod to `FS25_HelperPayroll`.
- Added helper slot detection A-J via vanilla `job.helperIndex`.
- Added `roleType` and `helperSlot` payroll modes.