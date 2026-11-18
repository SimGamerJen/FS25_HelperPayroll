# Farm Workforce — independent character portrait proof of concept
Date: 2026-11-18
Status: **Experimental source implementation; not yet tested in FS25**

## Purpose and design boundary
This is a genuinely local, optional, visual-only preview of a workforce member's assigned appearance. It does not hire, select, pay, move or spawn that worker. We inspected the user's The Contractor archive to establish that FS25 supports offscreen character rendering using a native GUI Render element and HumanGraphicsComponent, then authored our own scene and controller for Farm Workforce. No Contractor source, scripts, assets or portrait scene were copied into our repositories.

## Paired development branches
- HelperProfiles `design/farm-workforce-integration`: API **v8** adds `createPreviewPlayerStyle(slot)`, a read-only local PlayerStyle factory. Its existing HP_ASBridge resolves the appearance. API v7 remains supported for existing consumers; the ModHub main branch stays at v7.
- HelperPayroll `design/farm-workforce-integration`: experimental `FarmWorkforcePortrait` controller, independently authored `gui/farmWorkforcePortrait.i3d`, GUI Render element, and lifecycle callbacks.

## Behaviour
1. Open WORKFORCE > TEAM; controller is created only for the visible menu and has no payroll side effects.
2. Select a worker. The controller attempts to load the optional local PlayerStyle via HelperProfiles API v8.
3. If successful, FS25's native graphics component should render the selected appearance in a dedicated portrait area to the right of the member's name.
4. If HelperProfiles is absent, the older API is installed, the style is missing, or any render operation fails, the normal name/initials/appearance label remains. The portrait preview is not required for the menu to work.
5. Changing workers invalidates pending loads. Closing the menu destroys the temporary graphics object and scene.

## Changes deliberately avoided
- No modifications to payroll accounting, rates, ledger or relationship persistence.
- No change to established Slot / Worker / Status roster semantics.
- No dependency on The Contractor.
- No use of The Contractor's `TCWorkerPortrait.lua`, `TCWorkerAppearance.lua`, `workerPortrait.i3d` or assets.
- No merge to either release branch.

## First safe test — paired branches on a copied save
1. Keep your current working ZIPs backed up. Build a fresh HelperProfiles ZIP from **its integration branch** and a fresh HelperPayroll ZIP from **its integration branch**. Both need to be active to exercise this feature; the existing ModHub HelperProfiles v2.1.2.0 (API v7) will not provide portrait styles.
2. Confirm both ZIP files contain `modDesc.xml` at archive root. The HelperPayroll ZIP must include `gui/farmWorkforcePortrait.i3d` and `scripts/gui/FarmWorkforcePortrait.lua`.
3. Open FS25 on a copied save with just the required mods plus AvatarSwitcher if your saved appearances need it. Open Farm Workforce with `RCTRL+H`.
4. Select Jen, then Helena and an unused worker. Record whether a 3D portrait appears, whether the correct appearance is displayed, or whether the UI safely falls back to initials.
5. Verify switching sections, scrolling the roster and closing/reopening the GUI do not crash or corrupt visuals.
6. Save and reload. Check a previously assigned Family relationship, helper selection and payroll role still persist.
7. Supply **one screenshot** and the latest `log.txt`, especially if the portrait is blank or the render scene fails to load.

## Known unknowns (reason for prototype)
- The exact GIANTS `Render` element XML positioning, asynchronous scene initialization and camera render behaviour must be checked in the game.
- A newly authored I3D scene may need further light/camera/asset adjustments after a GIANTS log and screenshot.
- Some linked AvatarSwitcher styles may not support `HumanGraphicsComponent:setStyleAsync` immediately; this is a testable engine compatibility issue.
- A portrait is not a physical worker or a world-worker spawn.
- Static checks cover API presence, GUI names/handlers and source-file registration, **not actual renderer correctness**.

## After validation
If the preview works, stabilise asset lifecycle and style refresh after changing appearances. If it does not, use the log to diagnose the isolated prototype before touching any worker navigation, payroll or save logic.
