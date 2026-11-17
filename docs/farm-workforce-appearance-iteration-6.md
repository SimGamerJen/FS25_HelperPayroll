# Farm Workforce — appearance and identity integration (iteration 6)
Date: 2026-11-17
Status: committed; static checks passed, **awaiting FS25 visual validation**.

## Goal
Bring existing HelperProfiles appearance metadata into the member profile without modifying or depending on AvatarSwitcher, while keeping relationships, operational role and payroll separate.

## Changes
- Added an `Appearance:` line beneath the member's name and availability.
- Resolves `appearanceLabel` from the optional `HelperPayroll:getHelperProfilesSlotInfo(slot)` bridge, which reads HelperProfiles API v7. When a label is unavailable but a preset is known, displays `Preset assigned`; when HelperProfiles provides a slot but no preset, displays `Default appearance`; with no compatible slot/API, displays `Not linked`.
- No raw preset ID, internal appearance path, or ambiguous payroll `identityId` is shown.
- Slightly adjusted the right-hand panel's section spacing to fit the appearance line. Left-side roster, top tabs and footer controls are unchanged.
- Existing relationship storage remains separate from payroll role and compensation. No changes to wage calculations or employee relationship semantics.
- This is **appearance metadata**, not a 3D character portrait. AvatarSwitcher remains an independent optional mod.

## Validated statically
- `GuiElement` open/close counts balanced (9/9).
- No duplicate XML GUI IDs; all XML onClick callbacks have controller handlers.
- The new appearance ID exists in XML and is updated by Lua.
- No changes to existing roster and payroll editors.
- No changes to either main branch.

## In-game test
Using the copied save and the latest integration branch ZIP:
1. Open WORKFORCE > TEAM. Confirm the profile header remains inside the panel, and the new Appearance line sits beneath status, above Relationship.
2. Select a member with a known AvatarSwitcher/HelperProfiles appearance link (e.g. Jen, Helena). Check the displayed text is meaningful and matches the HelperProfiles roster.
3. Select an OFF-roster member with no appearance link; check fallback text and no Lua error.
4. Switch between WORKER PAY, PAYROLL and SETTINGS and confirm navigation remains usable.
5. Relaunch and confirm previously saved Family or other relationship selections are unchanged.
6. Supply a screenshot and log if appearance text is missing, misleading or clipped.

## Deferred
No character portrait rendering, schedule, relationship-driven pay effects, or editing appearance from this GUI yet. We can add a full appearance/personal details subview once engine-supported avatar preview options are assessed.
