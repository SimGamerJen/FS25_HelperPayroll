# Farm Workforce — GUI screenshot review and layout correction
Date: 2026-11-17
Branch: `design/farm-workforce-integration`

## Evidence
User supplied three in-game captures showing WORKFORCE, PAYROLL and SETTINGS, plus a GIANTS Engine log from the same session. The three main tabs, current payroll data and worker roster render successfully. The log confirms HelperPayroll initialized, GUI registered, API v5 published, HelperProfiles API v7 available, and no reported payroll GUI Lua exception.

## Observed visual problems
1. Contextual navigation (TEAM/WORKER PAY etc.) is rendered at the bottom edge rather than directly beneath the selected primary tab.
2. General-purpose table headings ITEM/VALUE/STATUS/SOURCE make the roster resemble a debug screen.
3. The page retains large unused space; a more substantial personal member view is still a future iteration.
4. A 20-slot roster necessarily scrolls; OFF-roster members should remain visible for continuity.
5. Details show a payroll identity that may be a linked appearance/preset identifier; do not assume it is equivalent to canonical helper slot identity without validating the API data contract.

## Changes committed
- Position contextual navigation under the main tabs by adjusting `workforceSubNav` from `0px 68px` to `0px 615px` in the existing GIANTS bottom-up coordinate layout.
- Shift the table content down from `0px 240px` to `0px 170px` to create separation from contextual navigation.
- Add named column text GUI IDs and change the Workforce headings to MEMBER / ROLE / AVAILABILITY / PAY POLICY. Restore generic headers on the other areas.
- Clarify detail label as 'Payroll identity' and reference the correct screen names for editing.

## Validation status
Post-change static check: every XML onClick callback has a Lua handler, all three main and contextual tabs are represented, heading bindings exist. **Visual layout not yet tested in FS25 after repositioning.**

## Next test
1. Build a new local ZIP from the latest development branch, with `modDesc.xml` at the ZIP root.
2. Open the three primary areas at the same display resolution used for the previous screenshots.
3. Verify secondary tabs are immediately under the primary tabs and don't overlap table headers, and that scrolling and the selected-row help text are visible.
4. Verify WORKFORCE column headings read MEMBER, ROLE, AVAILABILITY, PAY POLICY; PAYROLL and SETTINGS must retain ITEM/VALUE/STATUS/SOURCE.
5. Switch WORKER PAY / LEDGER / ROLES and verify visible editing controls remain limited to editable pages.
6. Share screenshots and relevant fresh log section if the layout overlaps or errors appear.

The release branches and data schemas remain untouched. Other startup errors in the submitted log concern unrelated mod packages and should not be attributed to Farm Workforce without evidence.
