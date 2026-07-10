# Alpha Testing Notes

## Basic load test

Expected log entries:

```text
[HelperPayroll] Lua file loaded
[HelperPayroll] Initializing
[HelperPayroll] Loaded config. Active profile: uk_tenant
[HelperPayroll] AI worker price suppression installed
```

## AI fieldwork test

1. Start a save.
2. Hire a native AI worker for fieldwork, such as mowing.
3. Expected log entries:

```text
[HelperPayroll] AI job detected #1: ... type=AIJobFieldWork
[HelperPayroll] AI helper pricing suppressed for jobType=AIJobFieldWork originalPricePerMs=0.0005 returned=0
```

## onJobFinish test

Use:

```xml
<billingMode>onJobFinish</billingMode>
```

Expected completion log:

```text
[HelperPayroll] Worker billing applied: ... charge=...
[HelperPayroll] AI job finished: ... billingMode=onJobFinish ... immediateCharge=true payrollDeferred=false
```

## dailyPayroll test

Use:

```xml
<billingMode>dailyPayroll</billingMode>
<payrollHour>18</payrollHour>
```

Expected job completion log:

```text
[HelperPayroll] Worker billing deferred to daily payroll: ... payrollHour=18
[HelperPayroll] AI job finished: ... billingMode=dailyPayroll ... immediateCharge=false payrollDeferred=true
```

Then advance game time to 18:00 or later.

Expected payroll log:

```text
[HelperPayroll] Daily payroll applied: ... charge=...
[HelperPayroll] Daily payroll summary: ... totalPaid=...
```

## Helper slot manual test

Set:

```xml
<defaultHelperSlot>B</defaultHelperSlot>
```

Expected job detection should include:

```text
helperSlot=B helperSlotSource=config helper=Rhys role=Skilled Operator workerRate=skilled
```
