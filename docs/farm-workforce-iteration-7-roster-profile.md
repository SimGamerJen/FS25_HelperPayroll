# Farm Workforce — roster clarity and profile-card redesign (iteration 7)
Date: 2026-11-17
Status: **Source implemented; static wiring checks passed; not yet validated visually in FS25.**

## Scope
This iteration combines the requested roster presentation fix with a more substantial visual redesign, rather than creating a separate test cycle for the columns.

### Roster
- New clearly labeled columns: **SLOT**, **WORKER**, **STATUS**.
- Slot A–T is in its own text element, no longer concatenated with the worker's display name.
- If the API reports an empty name or a raw slot letter (e.g. `A`), the roster shows `Helper A` **without modifying HelperProfiles' underlying identity/name**.
- Explicit status continues to show SELECTED / AVAILABLE / WORKING / OFF.
- Existing scrolling/selection and roster identities remain unchanged.

### Member profile
- Dedicated tinted background blocks create a more visible profile header, farm-details area, and separate **PAYROLL ARRANGEMENTS** area.
- Header renamed to **PERSONAL PROFILE**; existing name/status/appearance, editable relationship, friendly role name and payroll values remain.
- Initials tile uses a visible baseReference background rather than the earlier tab-background element.
- No photo or character portrait is claimed; this is a legible first visual upgrade using engine-native UI primitives.

## Non-goals/safety
No changes to payroll arithmetic, ledger history, save schema, relationship persistence, HelperProfiles, or AvatarSwitcher. The integration remains on the development branch only. Existing Billing, Roles, Worker Pay and Ledger views still use the prior table infrastructure.

## Static audit
- Balanced XML GuiElement tags (9 opening and 9 closing).
- No duplicated XML GUI IDs.
- All XML onClick callback methods exist in the Lua controller.
- New roster cellSlot and existing cellItem/cellStatus are bound in the list delegate.
- Existing editable table cellValue and editor callbacks remain.

## Test on a copied save
1. Build a fresh ZIP from `design/farm-workforce-integration`; use the same visual resolution and copied save as previous rounds.
2. Open WORKFORCE → TEAM. Confirm header **SLOT | WORKER | STATUS** and first rows **A | Jen | SELECTED**, **B | Rhys | AVAILABLE**; confirm unused slot shows **F | Helper F | OFF**, not `F F`.
3. Select several workers and scroll down to Sarah in K. Confirm that the right profile follows selection and that the left list remains readable, including the new 3-column spacing.
4. Confirm the large right-hand profile has visible, distinct grouped backgrounds, a visible initial tile, relationship arrows and legible identity/appearance/payroll details. Capture a screenshot.
5. Confirm that PAYROLL, WORKER PAY and SETTINGS still work, and that already stored relationship choices (such as Family) persist.
6. If any XML warnings or Lua errors appear, send `log.txt` as well.

This is the next meaningful visual test; further micro-adjustments should be deferred until screenshots establish whether the new cards work in GIANTS UI.
