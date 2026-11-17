# Farm Workforce — Split-panel member profile prototype
Date: 2026-11-17
Status: Implemented on integration branch; **not yet tested in FS25**.

## Delivered
- WORKFORCE > TEAM now has its own GUI panel rather than the four-column payroll table.
- Left side: scrollable 20-member roster, each showing helper slot, display name and availability.
- Right side: selected member name, status, payroll role, pay basis, effective wage rate, compensation inheritance and payroll identity.
- Data comes from the existing `HelperPayroll:getPayrollSnapshot({includeWorkers=true, includeDisabledWorkers=true})` call. No new persistent data fields, costs, mutations or changes to payroll arithmetic.
- The payroll and settings pages still use the previous table/list and retain their edit controls.
- Selection uses a stored helper slot to help preserve the displayed member when revisiting the Workforce tab.
- The roster refreshes once per second; profile values update from the current snapshot.

## Important limitations
- This is the **first interactive profile layout**, not the final concept image. Real worker portrait integration, family relationship, availability schedule, favoured jobs, and task assignment are not implemented.
- Role is presently a stable policy ID, not the friendly display label.
- The payroll identity may be an appearance-linked preset identifier. The existing snapshot does not unambiguously expose a separate canonical HelperProfiles slot ID. UI displays both slot and payroll identity.
- Large screen sections have not been verified for clipping, scrolling or focus handling in the FS25 engine.
- Static verification checked that XML callback names exist in Lua, but **no game runtime or TestRunner execution** has been performed.

## In-game test (copied save)
1. Download the latest branch and rebuild the ZIP with `modDesc.xml` at ZIP root. Retain working release ZIP separately.
2. Launch FS25 with HelperProfiles 2.1.2.0 and the development HelperPayroll build.
3. Open `RCTRL+H` and select WORKFORCE > TEAM. Capture a screenshot.
4. Check roster left / details right. Select Jen, Rhys, Ellie, Riley and Helena, and verify the right panel updates correctly.
5. Scroll down to Sarah (slot K) and confirm all 20 slots remain accessible, including OFF-roster entries.
6. Verify selected worker stays selected during one-second updates. Switch to PAYROLL, then return to WORKFORCE and verify the same worker remains selected.
7. Open WORKER PAY, PAYROLL and SETTINGS, and confirm no old screens were hidden or broken.
8. Inspect `log.txt` for GUI XML errors, missing property bindings, Lua exceptions or list-selection glitches.
9. Do not modify rates or saves as part of this first visual test.

## Isolation
Only the HelperPayroll integration branch has changed. HelperProfiles main and HelperPayroll main are untouched.
