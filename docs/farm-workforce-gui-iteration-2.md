# Farm Workforce — three-area GUI prototype (iteration 2)
Date: 2026-11-17
Status: Source committed; **not yet tested inside FS25**

## Navigation
The prior seven equally weighted tabs have been replaced by three main tabs:
- **WORKFORCE** — contextual views `TEAM` (read-only roster) and `WORKER PAY` (existing per-worker role and override editor).
- **PAYROLL** — `OVERVIEW` (existing live dashboard) and `LEDGER` (existing persistent ledger).
- **SETTINGS** — `BILLING` (existing billing policy editor), `ROLES` (existing compensation policy editor) and `HELP` (existing help page).

The second-row subview buttons are dynamically labelled and shown/hidden based on the primary area. The PREV AREA/NEXT AREA buttons cycle the three primary areas. The previous `RCTRL+H` keybinding is unchanged.

## Implementation
- `gui/HelperPayrollMenu.xml`: three primary tabs, three contextual subview buttons, header rename to FARM WORKFORCE.
- `scripts/gui/HelperPayrollMenu.lua`: topic-to-group routing, dynamic subviews and button callbacks; starts at Workforce when no explicit saved topic is supplied.
- Old handlers `onClickDashboard`, `onClickWorkers`, `onClickBilling`, `onClickRoles`, `onClickLedger`, `onClickHelp` are retained for backward compatibility and programmatic navigation.
- Existing payroll and role editors, apply/discard staging, reload/reset and calculations are unchanged.
- Existing Worker view from iteration 1 remains read-only and refreshes every second.

## Static checks completed
- Every XML `onClick` callback is declared by the Lua menu controller.
- Exactly three main tab IDs and three contextual subview button IDs are present.
- No duplicate XML GUI IDs.
- All seven underlying topics still exist in Lua.

## Tests required before shipping
Use a **copied savegame**. Do not install this branch build over your normal release/testing mod without a backup.

1. Package the contents of the branch as `FS25_HelperPayroll.zip` with `modDesc.xml`, `gui/`, `scripts/` at the **ZIP root**. Do not zip the enclosing GitHub repository directory. Keep the previously verified release ZIP separately.
2. Enable current HelperProfiles 2.1.2.0 and this development build of HelperPayroll.
3. Open the menu using `RCTRL+H`. Check that the title is FARM WORKFORCE, with only three primary tabs. Note any clipping/overlap at your active resolution.
4. WORKFORCE -> TEAM should display A–T, including OFF-roster members, their role IDs and effective pay rate. WORKER PAY should open the existing editable worker assignments.
5. PAYROLL -> OVERVIEW / LEDGER should show the existing values and continue to refresh correctly.
6. SETTINGS -> BILLING / ROLES / HELP should retain their existing controls and explanatory text.
7. Change a worker rate, hit DISCARD, and check no setting persists; then change a harmless copied-save value and APPLY, reopen the screen, confirm it persists. Verify active work billing is unaffected by later edits.
8. Test PREV AREA / NEXT AREA and ESC. Verify unsaved drafts are not accidentally applied, and that the menu doesn't lose focus.
9. Confirm that removing HelperProfiles still leaves this menu operational in payroll standalone mode.
10. Inspect the game `log.txt` for Lua errors and XML GUI warnings. **Do not promote the branch until this test passes.**

## Known design limitations
This iteration improves information architecture, not the final appearance. The existing large four-column table remains; per-worker portrait, family relationship, routines and skills are future features. The secondary buttons have not yet been confirmed for sizing or focus/gamepad navigation in FS25. An actual screen capture is needed to validate spatial layout.

## Change isolation
Only the `design/farm-workforce-integration` branch of HelperPayroll was changed. Neither main branch was modified, and HelperProfiles has no gameplay changes in its integration branch.
