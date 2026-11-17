# Farm Workforce — integration and GUI redesign audit
Date: 2026-11-17
Status: Design-only; no runtime changes

## Baseline
- HelperProfiles: **2.1.2.0**, ModHub-released; repository `SimGamerJen/FS25_HelperProfiles`, `main`.
- HelperPayroll: **0.4.4.0 Alpha 1**, repository `SimGamerJen/FS25_HelperPayroll`, `main`.
- Both repositories have a `design/farm-workforce-integration` branch. No released code is to be modified until design and migration tests are agreed.

## Verified source observations
- HelperProfiles `scripts/HP_SlotRegistry.lua` maps twenty A–T slots to canonical `helper01`–`helper20` identities, including aliases.
- HelperProfiles `scripts/HP_IntegrationAPI.lua` exposes API v7, stable identities, roster and temporary scoped hiring.
- HelperProfiles `scripts/HP_TabbedManagement.lua` coordinates appearance and roster screens, preserving staged drafts when switching tabs.
- HelperPayroll `scripts/gui/HelperPayrollMenu.lua` currently has six topics: dashboard, billing, roles, workers, ledger, help, with staged changes.
- HelperPayroll `scripts/HelperPayrollPublicAPI.lua` exposes API v5 and snapshot/capability discovery.
- HelperPayroll `scripts/HelperPayrollFarmScope.lua` resolves a farm ownership identifier for job accounting; this is not yet multiplayer support.
- HelperPayroll currently supports roleType / helperSlot, hourly or daily pay, worker overrides, job snapshots, immediate or daily settlement, and a persistent ledger. Game-clock accounting in 0.4.4.0 must be preserved.

## Proposed product and UI boundaries
**Farm Workforce** is the umbrella concept. Keep separate mod ZIPs for now; design a coherent interface via capability-checked APIs. HelperProfiles remains authoritative for identity, name, roster ON/OFF, selection, appearance binding and operational availability. HelperPayroll remains authoritative for roles, pay policies, accrued costs, payment events and ledger. Do not duplicate wage computations or create competing worker IDs.

Proposed navigation:
1. **Workforce** — fast roster list, selected member, availability and role. Advanced profile detail as a drill-down, not everything on the roster page.
2. **Payroll** — summary of accrued/pending/settled actual amounts, worker breakdown and ledger; drill-down to role, rate and overrides.
3. **Settings** — grouped payroll and integration settings; specialist billing and role configuration may use secondary pages/dialogs, not a single overloaded panel.
4. **Appearances** may remain under Workforce member detail or a dedicated subview; preserve legacy quick-selection overlay and RCTRL+; bindings.

Separate **relationship** (family/permanent/seasonal/volunteer/contractor) from **payment policy** (paid/unpaid), **availability** (roster ON/OFF, active/idle) and **role**. Do not assume every family member is unpaid or every hired worker is paid hourly. Persist any proposed relationship metadata in a new versioned optional per-save schema keyed by canonical helper ID; keep old saves fully readable.

## Concept art is aspirational, not implemented functionality
The previous mockups include avatars, skill bars, weekly routines, employee biographies, job assignments and monthly/weekly forecasts. These **must not be presented as implemented**. The present code does not establish those features as available. Likewise, real-world weekday schedules are not automatically suitable for FS25's configurable days per month. Design routines around game days/time periods, with explicit calendar semantics after validation. Pay dates and estimates shown in the mockup are illustrative only.

## Migration and compatibility constraints
- Never rename or renumber `helper01` through `helper20`.
- Preserve HelperProfiles per-save `roster.xml`, `appearanceLinks.xml` and their legacy migration paths.
- Preserve all HelperPayroll per-save role policies, worker overrides, pending transactions, settlements and ledger history.
- Preserve job-start compensation snapshots: UI policy edits must not retroactively change an active job.
- Keep HelperProfiles API v7 / HelperPayroll API v5 working; capability-check newer optional features.
- Do not interfere with Hired Helper Tool conflict protection.
- Do not modify the released 2.1.2.0 version or its release artifacts.
- Keep both mods functional independently while a shared UI is prototyped.

## Initial GUI implementation strategy
1. Audit current GUI XML bindings and Lua callbacks in both repositories.
2. Extract a read-only workforce view model: canonical id, display name, roster enabled, activity, appearance label, assigned payroll role, effective policy, accrued/pending cost. Distinguish missing API values from zero.
3. Prototype a simplified roster and per-member view using existing FS25 ScreenElement conventions; do not introduce speculative business logic.
4. Prototype a payroll landing view backed exclusively by current snapshot/ledger services. Keep editable policy forms as drill-down screens.
5. Introduce relationship/paid status as separately versioned and optional data only after save migration and tests are defined.
6. Test no-payroll, no-profiles, disabled workers, all workers active, save/load, midnight crossing, accelerated game time, old save migrations and scoped hiring.
7. Reconsider a single-ZIP package only after end-to-end testing and migration feasibility assessment.

## Decisions not yet made
- Whether one launcher GUI should live in HelperProfiles or a thin separate companion while both mods remain optional.
- Whether future family members occupy one of the twenty existing helper slots or can be non-helper workforce participants.
- Whether character portraits are feasible via GIANTS character assets/appearance presets instead of invented image resources.
- Whether world-worker scheduling belongs in core workforce or remains an optional experimental subsystem.
