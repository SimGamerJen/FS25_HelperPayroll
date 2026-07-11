# Changelog

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
