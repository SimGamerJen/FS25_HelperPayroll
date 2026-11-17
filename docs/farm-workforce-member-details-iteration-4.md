# Farm Workforce — Member Details and Payroll profile, iteration 4

Date: 2026-11-17
Status: **Source committed, static checks passed, awaiting in-game visual test**

## Purpose
The first split profile was functional but still resembled a payroll record. This iteration introduces a member-first presentation without introducing an untested data model or changing gameplay.

## Changes
- Workforce panel now has distinct **MEMBER DETAILS** and **PAYROLL** sections.
- Name/status remain prominent.
- **Relationship** explicitly shows `Not assigned`, because Family/Permanent/Seasonal affiliations do not yet have a persistent data field. No inference from wage/role.
- Farm role attempts the saved role's user-facing name via `getWorkerRateById` and falls back to the role ID.
- Compensation and pay basis continue to use existing per-worker snapshot values.
- Effective rate uses `g_i18n:formatMoney` when available, with a numeric fallback. Currency is not hardcoded.
- Raw preset/payroll identity has been removed from the main panel; underlying identity storage and APIs remain unchanged.
- No new player actions, save data, wage calculations or mod dependencies.

## In-game validation
Use the same copied-save setup and this branch's latest build:
1. Open `RCTRL+H` -> WORKFORCE -> TEAM. Confirm profile section headings, member name, and pay fields appear entirely inside the right panel.
2. Select Jen, Rhys, Ellie, Riley and Helena. Confirm role names are human-readable (where present in the stored payroll role definitions) and pay formatting follows the selected in-game currency.
3. Check `Relationship: Not assigned` for all workers. This is intentional until relationship persistence is implemented.
4. Scroll to OFF-roster members and confirm the left roster and right profile stay synchronized.
5. Confirm WORKER PAY, PAYROLL, and SETTINGS still work. No wage edits are required in this visual test.
6. If the GUI reports warnings/errors, supply `log.txt`. Please supply one screenshot even on success so alignment can be confirmed.

## Static checks
- XML GuiElement opening/closing counts balanced (9/9).
- No duplicate GUI IDs.
- Every XML onClick callback exists in Lua.
- All member UI ID bindings are referenced from the controller.
- The technical payroll identity is no longer displayed in the member panel.

## Pending features
Relationships need a versioned, optional per-save schema and safe migration; do not add editable toggles until this is designed and tested. Photos/avatars, favourite tasks, family labels, schedules and skills remain future features, not currently implemented.

HelperProfiles 2.1.2.0 and both released `main` branches are untouched.
