# Farm Workforce — relationship metadata and profile identity (iteration 5)

Status: **Implemented on integration branch, static checks passed; FS25 runtime not yet tested.**

## Changes
- A dedicated `FarmWorkforceRelationships` module stores an optional `relationship` for each persistent HelperProfiles A–T helper slot. Whitelist: `unassigned`, `family`, `permanent`, `seasonal`, `contractor`, `volunteer`.
- Saved independently under the existing HelperPayroll modSettings savegame directory as `farmWorkforceRelationships.xml`, with `schemaVersion=1`. Existing `helperPayrollSettings.xml`, role policies, and ledger files are not modified by relationship edits.
- The profile has a character-initials tile (not a character portrait).
- Relationship is selectable with left/right arrows and written immediately. It is **not** a payroll policy: Family membership does not automatically disable wages, and Contractor/Volunteer are descriptive only.
- A thin green indicator marks the active secondary navigation page.
- Profile keeps friendly role name, payroll data and read-only worker identity from the already-validated split interface.

## Save and compatibility
- Missing relationship file means all members appear `Not assigned`, and no write happens until the user changes a relationship.
- Data is indexed by permanent A–T slots, not appearance presets, session job IDs or display names.
- Foreign/future schema versions are read-only rejected rather than overwritten automatically.
- This metadata is independent of `HelperProfiles` presence and wage settlement.
- No changes to main branch or ModHub release code.

## Test instructions: copied save only
1. Build the ZIP from `design/farm-workforce-integration`, keeping `modDesc.xml` at the ZIP root; ensure the new `scripts/FarmWorkforceRelationships.lua` is included.
2. Launch with HelperProfiles 2.1.2.0 and open `RCTRL+H` -> WORKFORCE -> TEAM. Verify the initial tile and active secondary underline render correctly.
3. Pick Rhys or Helena, use the left/right arrows to select `Family`, `Permanent`, or `Seasonal`. Verify the label changes without modifying any pay rate or payroll role.
4. Exit to game and reopen the screen. Relationship should persist.
5. Quit and restart the game; load the **same copied save** and confirm the relationship remains. Under `modSettings/FS25_HelperPayroll/<savegame>/` verify `farmWorkforceRelationships.xml` exists and contains the correct A–T slot value.
6. Switch to another copied save and confirm relationships are independent.
7. Confirm PAYROLL -> OVERVIEW/LEDGER and SETTINGS -> BILLING/ROLES are unaffected.
8. Provide one WORKFORCE screenshot and `log.txt` if the arrow controls, labels, persistence or layout behave unexpectedly.

## Explicit non-features
No payroll effects, automatic family grouping, schedule, portrait, competency data or worker movement has been added. Relationships are metadata only.

## Static validation
Checked source load order, balanced GUI elements, duplicate IDs, callbacks and Lua-side bindings. **GIANTS runtime tests have not been run here.**
