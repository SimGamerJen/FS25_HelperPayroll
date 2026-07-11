# FS25_HelperPayroll Alpha Testing Notes

Current build: **v0.1.9.1 Alpha RC**

## 1. Basic load test

Expected log entries:

```text
[HelperPayroll] Initializing
[HelperPayroll] Loaded config. Active payroll profile: default
[HelperPayroll] Worker billing settings: ... payrollMode=roleType ... selectedRole=...
[HelperPayroll] Loaded savegame persistence: ...
[HelperPayroll] AI worker price suppression installed. Hook count=3
[HelperPayroll] Registered console commands: hpayOverlay, hpayRole, hpayDump, hpayReport
```

First-run saves may also show:

```text
[HelperPayroll] No persistent payroll ledger index found yet: .../ledger/index.xml
```

That is normal before the first payroll entry is recorded.

## 2. Role list and role cycling

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

## 3. Vanilla roleType AI job test

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

## 4. Short job / minimum charge test

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

## 5. Longer job above minimum test

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
