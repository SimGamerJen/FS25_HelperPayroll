# FS25_HelperPayroll Beta Release Candidate Testing Notes

Current build: **v0.3.3.0 Beta Release Candidate**

## v0.3.3.0 beta release-candidate validation

### Baseline startup

1. Load with HelperProfiles enabled and confirm one delayed `Runtime status` line reports the API state.
2. Run `hpayDump status` and verify version `0.3.3.0`, channel `beta-rc`, billing mode, pending-row count and HelperProfiles API version.
3. Confirm normal logging does not print a `Daily payroll check` line for every in-game hour.
4. Set global policy `logLevel` to `debug`, reload the config, and confirm detailed clock checks return.

### Required scheduler edge cases

1. **Overdue next day:** finish a daily-payroll job before payroll, advance into the next game day, and confirm `reason=overdue-day`.
2. **Save/reload:** finish a job, save before settlement, reload, and confirm the pending row remains and settles once.
3. **Multiple workers:** run at least three named workers at different rates and confirm one daily payment per identity.
4. **Identity movement:** move an AvatarSwitcher-bound HelperProfiles identity to another A-J slot and confirm its saved payroll role follows the identity.
5. **Duplicate guard:** reload after a payment and confirm no second payment is created for the same worker/workday.
6. **Standalone fallback:** disable HelperProfiles and confirm `;` and `RCTRL + ;` return to HelperPayroll.

### Evidence to capture

- `hpayDump status`
- `hpayDump clock` before and after settlement
- job-start assignment line
- deferred ledger line
- daily settlement and summary lines
- ledger totals after reload


## 1. Basic load test

Expected log entries:

```text
[HelperPayroll] Initializing
[HelperPayroll] Generated external payroll policy config: ... (first run only)
[HelperPayroll] Loaded config. source=external file=.../modSettings/FS25_HelperPayroll/defaultPayrollConfig.xml Active payroll profile: default
[HelperPayroll] Worker billing settings: ... payrollMode=roleType ... selectedRole=...
[HelperPayroll] Loaded savegame persistence: ...
[HelperPayroll] AI worker price suppression installed. Hook count=3
[HelperPayroll] Registered console commands: hpayOverlay, hpayRole, hpayDump, hpayReport, hpayConfig, hpaySave, hpayProfiles
[HelperPayroll] Runtime status: version=0.3.3.0 channel=beta-rc ...
```

First-run saves may also show:

```text
[HelperPayroll] No persistent payroll ledger index found yet: .../ledger/index.xml
```

That is normal before the first payroll entry is recorded.


## 2. External policy config test

Expected first-run path:

```text
modSettings/FS25_HelperPayroll/defaultPayrollConfig.xml
```

Console checks:

```text
hpayConfig status
hpayConfig path
hpayConfig reload
```

Expected behaviour:

```text
- `hpayConfig status` reports source=external.
- `hpayConfig path` prints the editable policy XML path.
- Editing the external XML then running `hpayConfig reload` reloads roles/rates/settings without restarting the game.
- `hpayConfig reset` regenerates the external policy file from bundled defaults.
```

## 2b. Global/default vs current-save config diagnostics

Global/default policy commands:

```text
hpayConfig status
hpayConfig path
```

Expected behaviour:

```text
- `hpayConfig status` reports `defaultPayrollConfig.xml`.
- It explicitly states that current save settings are separate.
- It points users to `hpaySave status`.
```

Current-save/effective commands:

```text
hpaySave status
hpaySave path
hpaySave reload
```

Expected behaviour:

```text
- `hpaySave status` reports `<savegame>/helperPayrollSettings.xml`.
- It shows the effective values currently used by gameplay.
- Save-specific values may intentionally differ from the global/default policy.
```

## 3. Role list and role cycling

Controls:

```text
;           Cycle payroll role
RCTRL + ;   Open/close payroll role list
```

Expected log entries:

```text
[HelperPayroll] Payroll role list opened
[HelperPayroll] Selected payroll role changed: profile=default role=skilled name=Skilled Operator rate=22.00
[HelperPayroll] Saved savegame persistence: reason=role-cycle ... selectedRole=skilled
```

The active/highlighted role is the selected role. No Enter/confirm step is used.

## 4. Vanilla roleType AI job test

Use default mode:

```xml
<payrollMode>roleType</payrollMode>
```

Start a native AI fieldwork job after selecting a role. Expected pattern:

```text
[HelperPayroll] AI job detected #1: ... payrollMode=roleType helperSlot=G helperSlotSource=job.helperIndex helperSlotUsedForPayroll=false helper=Trainee Helper role=Trainee Helper workerRate=trainee profile=default rate=10.00
[HelperPayroll] AI helper pricing suppressed for jobType=AIJobFieldWork originalPricePerMs=0.0005 returned=0
```

The detected vanilla helper slot may vary, but it must not control the payroll role in `roleType` mode.

## 5. Short job / minimum charge test

Let a worker run briefly and then stop/finish the job.

Expected pattern:

```text
[HelperPayroll] Worker billing applied: ... elapsedHours=0.091 rate=10.00 labour=0.91 minimum=5.00 minimumApplied=true charge=5.00 ...
[HelperPayroll] Worker ledger session total: entries=1 totalCharged=5.00
[HelperPayroll] Saved persistent payroll ledger index: reason=job-charged ... jobs=1 charged=5.00
[HelperPayroll] Persistent payroll ledger entry recorded: reason=job-charged period=Y001_M06 id=Y001_M06_000001 type=job status=charged charged=5.00
[HelperPayroll] AI job finished: ... billingHandled=true immediateCharge=true payrollDeferred=false
```

Important: there should be **only one** `Worker billing applied` line for the finished job.

## 6. Longer job above minimum test

Run a job long enough that hourly labour exceeds the minimum charge.

Expected:

```text
minimumApplied=false
charge=<labour plus callout if configured>
```

## 6. Persistent ledger reload test

After at least one charged job:

1. Save and quit to menu.
2. Reload the same save.
3. Run:

```text
hpayReport summary
hpayReport jobs 10
```

Expected pattern:

```text
[HelperPayroll] HelperPayroll Persistent Ledger Summary
[HelperPayroll] Totals: jobs=1 ... charged=5.00
[HelperPayroll] Periods:
[HelperPayroll] - Y001_M06 | jobs=1 ... charged=5.00
[HelperPayroll] Persistent payroll entries: period=Y001_M06 showing 1-1 of 1
```

## 7. Payroll report overlay test

Controls:

```text
RCTRL + P   Open/close payroll report overlay
;           Next report page while report overlay is open
```

Expected log entries:

```text
[HelperPayroll] Payroll report overlay opened
[HelperPayroll] Payroll report overlay page changed: page=2/4
[HelperPayroll] Payroll report overlay page changed: page=3/4
[HelperPayroll] Payroll report overlay page changed: page=4/4
[HelperPayroll] Payroll report overlay page changed: page=1/4
```

## 8. Console command smoke test

```text
hpayOverlay status
hpayRole show
hpayRole list
hpayRole set standard
hpayReport summary
hpayReport jobs 10
hpayReport roles
hpayReport export helperPayrollTestReport
hpaySave status
hpaySave path
hpayDump status
hpayDump ledger
```

Expected export path:

```text
modSettings/FS25_HelperPayroll/<savegame>/helperPayrollTestReport.txt
```

## 9. Savegame persistence test

1. Change selected role.
2. Change an overlay value, for example:

```text
hpayOverlay scale 1.2
```

3. Save/quit/reload.
4. Run:

```text
hpayRole show
hpayOverlay status
```

Expected persistence file:

```text
modSettings/FS25_HelperPayroll/<savegame>/helperPayrollSettings.xml
```

## 10. helperSlot advanced test

Set:

```xml
<payrollMode>helperSlot</payrollMode>
```

Expected AI job log should show `helperSlotUsedForPayroll=true` if the detected helper slot is configured.

Example:

```text
[HelperPayroll] AI job detected #1: ... payrollMode=helperSlot helperSlot=B helperSlotSource=job.helperIndex helperSlotUsedForPayroll=true helper=Rhys role=Skilled Operator workerRate=skilled
```

This is not the primary vanilla alpha workflow.

## Useful bug report details

Please include:

- FS25 version
- HelperPayroll version
- `payrollMode`
- `billingMode`
- AI job type tested
- Selected payroll role
- Whether HelperProfiles was active
- Relevant `log.txt` section from job start through job finish
- Contents of `helperPayrollSettings.xml` if the issue relates to settings
- `hpayReport export <name>` output if the issue relates to payroll totals


## v0.2.3.3 CCO-style table editing UI

1. Open the management screen with RCTRL + H.
2. Open the Billing tab.
3. Confirm the right-hand details pane is gone.
4. Confirm editable rows show left/right controls in the Value column.
5. Change billing mode, payroll hour, minimum charge, callout fee, and round charges from the table.
6. Press APPLY and confirm the current save payroll settings is written.
7. Use DISCARD/RELOAD to confirm staged changes can be reverted.
8. Confirm role list, report overlay, payroll billing, and persistent ledger still work.


## v0.3.0.0 alpha baseline config/status test

1. Open management UI with `RCTRL + H`.
2. Change one Billing setting or one role hourly rate.
3. Press APPLY.
4. Confirm the log says `Saved savegame persistence` and references `modSettings/FS25_HelperPayroll/<savegame>/helperPayrollSettings.xml`.
5. Confirm `defaultPayrollConfig.xml` is not changed by APPLY.
6. Reload the save and confirm the changed setting is restored from the savegame settings file.
7. Use RESET SAVE and confirm the current save is reset from the global/default policy template.

8. Run `hpayConfig status` and confirm it reports only the global/default policy.
9. Run `hpaySave status` and confirm it reports the current-save/effective values.
10. Confirm both commands make the config source clear and do not mix the two layers.


## v0.3.0.0 HelperProfiles integration smoke test

1. Load HelperPayroll without HelperProfiles and run `hpayProfiles status`; it should report unavailable and standalone mode available.
2. Load HelperProfiles and HelperPayroll together.
3. Run `hpayProfiles status`; it should detect HelperProfiles and report selected slot/name if available.
4. Run `hpayProfiles slots`; it should list A-J HelperProfiles names and HelperPayroll slot mappings.
5. In `roleType` mode, start a helper and confirm payroll still uses the selected HelperPayroll role.
6. Switch to `helperSlot` mode in the current-save settings, configure slot mappings, start a helper selected through HelperProfiles, and confirm the job log shows `helperSlotUsedForPayroll=true` and `identitySource=HelperProfiles` where applicable.

## v0.3.0.1 legacy HelperProfiles XML bridge test (superseded)

1. Enable HelperProfiles and load a save with per-save appearance bindings.
2. Run `hpayProfiles status`.
3. Confirm `available=true`, `appearance links: loaded=true`, and the file points to `FS25_HelperProfiles/saves/<savegame>/appearanceLinks.xml`.
4. Run `hpayProfiles slots`.
5. Confirm bound A-J slots show HelperProfiles display names.
6. In `roleType` mode, confirm the selected payroll role remains authoritative.
7. In `helperSlot` mode, start a worker and confirm `job.helperIndex` resolves the A-J slot while the XML supplies the display name.

## HelperProfiles shared API integration

With HelperProfiles 2.0.23+ enabled:

1. Load a save with HelperProfiles and HelperPayroll enabled.
2. Confirm HelperProfiles logs that its optional shared API was published.
3. Run `hpayProfiles status`; expect `modLoaded=true`, `apiAvailable=true`, and `source=shared-api`.
4. Run `hpayProfiles slots`; confirm A-J identities match the live HelperProfiles overlay/menu.
5. In `roleType` mode, start a worker and confirm the selected payroll role remains authoritative.
6. In `helperSlot` mode, start a worker and confirm `job.helperIndex` selects A-J while HelperProfiles supplies the display name.
7. Disable HelperProfiles and reload; confirm HelperPayroll remains functional and reports standalone mode.

The test must not depend on `appearanceLinks.xml` being present.


## v0.3.1.0 HelperProfiles payroll mapping test

1. Enable HelperPayroll 0.3.1.0 and HelperProfiles 2.0.23.0.
2. Run `hpayProfiles status`; confirm API v2 is available.
3. Open HelperPayroll management and select **WORKERS**.
4. Confirm live names appear for bound HelperProfiles slots.
5. Assign different roles to at least two workers and press APPLY.
6. Confirm `helperPayrollSettings.xml` contains `helperProfilesMappings`.
7. Set Billing > Payroll mode to `helperSlot` and APPLY.
8. Select/deploy one mapped helper through HelperProfiles.
9. Confirm the AI job log includes the expected identityId, mappingSource, role, and rate.
10. Finish the job and confirm the period ledger snapshots the helper identity fields.
11. Reload the save and confirm WORKERS mappings persist.
12. Move an AvatarSwitcher-bound identity to another slot, reload HelperProfiles data, and confirm the identity mapping follows the preset identity.

## v0.3.1.1 HelperProfiles input handoff test

### With HelperProfiles enabled

1. Load HelperProfiles API v2 and HelperPayroll 0.3.1.1.
2. Run `hpayProfiles status`.
3. Confirm `standaloneRoleInputsSuppressed=true`.
4. Confirm the log reports standalone role selector suppression for player/vehicle context.
5. Press `;` and confirm only HelperProfiles changes its selected helper.
6. Press `RCTRL + ;` and confirm only the HelperProfiles overlay opens/closes.
7. Confirm `RCTRL + H` still opens HelperPayroll management.
8. Confirm `RCTRL + P` still opens the payroll report overlay.

### Without HelperProfiles enabled

1. Load HelperPayroll alone.
2. Confirm `;` cycles the standalone payroll role.
3. Confirm `RCTRL + ;` opens/closes the standalone payroll role list.



## v0.3.2.0 stable identity and daily payroll test

1. Install HelperProfiles 2.0.24.0 and HelperPayroll 0.3.2.0.
2. Set HelperPayroll to `helperSlot` and `dailyPayroll` modes.
3. Start two or more named HelperProfiles workers in succession or concurrently.
4. Confirm each `AI job detected` line reports the correct A-J slot, `identityId`, display name, role and rate with `assignmentSnapshot=job-start`.
5. Stop the workers and confirm each deferred entry retains the same identity and rate shown at job start.
6. Save/reload before payroll and confirm `Loaded pending daily payroll rows` is logged.
7. Advance to the next game day before the configured payroll hour.
8. Confirm overdue rows are charged once and removed from pending storage.
9. Reload again and confirm no duplicate payment occurs.

Legacy migration check: a save containing deferred `dailyPayroll` ledger jobs from 0.3.1.x should log `Reconciled pending daily payroll from persistent ledger` and settle any genuinely unpaid rows.

## v0.3.2.1 accelerated-time payroll test

1. Complete a worker job before the configured payroll hour.
2. Run `hpayDump clock` and confirm the row is `same-day-waiting`.
3. Accelerate time through the payroll hour.
4. Confirm `Daily payroll check` reports the changed hour and `Daily payroll settled` is logged.
5. Repeat by advancing directly into the next day; the due reason should be `overdue-day`.
6. Save and reload with a pending row and confirm it remains payable.
