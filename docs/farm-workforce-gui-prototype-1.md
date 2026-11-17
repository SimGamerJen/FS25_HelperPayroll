# Farm Workforce — Read-only GUI prototype 1

Branch: `design/farm-workforce-integration`
Baseline: HelperPayroll 0.4.4.0 Alpha 1 and HelperProfiles 2.1.2.0.
Status: Source implementation committed; **not validated in the running game**.

## Scope
The existing six payroll tabs remain in place. A seventh `WORKFORCE` tab is added to the existing `RCTRL+H` management screen using the existing FS25 `ScreenElement` + `SmoothList` UI. This deliberately uses a conventional table for the first playable prototype rather than promising that the photorealistic concept screens can be reproduced with the existing GUI components.

The new tab calls the current `getPayrollSnapshot({includeWorkers=true, includeDisabledWorkers=true})` read-only API. It displays:
- number of managed workers and ON/OFF counts;
- roster slot and worker display name;
- current role ID;
- available/working/OFF roster state, plus selected indicator;
- effective hourly/daily compensation rate;
- worker identity, compensation override mode, and roster state in row details.

The view updates every second, like the existing dashboard. No new gameplay actions, monetary charges, worker persistence, relationships, skills or schedules have been implemented. Family relationships in the earlier art are **future design only**, not currently inferred from payroll status.

## Existing functionality intentionally unchanged
- Payroll settings, salary calculations, per-worker overrides, ledger, game-clock accounting and settlement;
- existing six payroll tab callback names;
- all HelperProfiles roster/hire/appearance functions;
- stored worker IDs and current per-save formats;
- standalone operation without HelperProfiles.

No changes were made to either repository's `main` branch.

## Game validation checklist (test on a copied save)
1. Run current HelperProfiles 2.1.2.0 and a local ZIP built **from this development branch** of HelperPayroll. Open `RCTRL+H`.
2. Confirm that the seventh tab is visible, selectable and legible at 1080p, 1440p and 4K. **Seven tabs may exceed the width of the GIANTS subcategory header; check clipping and click targets.** Use PREV/NEXT TAB if it does.
3. Confirm all A–T identities are included and appear in stable order, including OFF-roster helpers.
4. Confirm changes to a HelperProfiles ON/OFF roster state, selection and AI work state appear within approximately one second.
5. Confirm every workforce row is read-only. `APPLY`, `DISCARD` and inline rate editors must not appear on this tab.
6. Confirm detailed payroll role/rate editing continues to work under existing `WORKERS` and `ROLES` tabs, including stage/discard/apply.
7. Reopen and reload the save. Confirm existing appearances, payroll mappings and ledger values are intact.
8. Disable HelperProfiles and confirm the Workforce tab degrades to standalone payroll slot data without errors.
9. Test a job crossing midnight, time acceleration and worker billing; compare against the released 0.4.4.0 Alpha 1 behaviour.
10. Inspect `log.txt` for GUI registration, layout and script errors.

## Known limitations
- This is the first functional table/list prototype, not the final three-tab Farm Workforce redesign.
- Role names are currently IDs; use the existing role view for friendly labels until a capability-aware presentation layer is implemented.
- Status `Available` means ON roster and not marked in use; it is not a simulated employment schedule.
- No stable worker portrait facility has been introduced.
- The final UI may require a custom multilevel tab layout rather than seven equal-width tabs.
- No live game tests or packaging have been executed in this development step.

## Next step
After game UI validation: refactor current Payroll Dashboard / Workers / Roles / Billing into a unified Workforce / Payroll / Settings navigation, preserving access to specialist settings in child panels and keeping all API ownership boundaries.
