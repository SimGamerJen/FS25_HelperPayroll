# FS25_HelperPayroll

**Helper Payroll** is an early alpha Farming Simulator 25 mod that replaces the vanilla AI helper wage drain with a configurable payroll model.

Instead of letting the game charge its built-in AI helper rate continuously, Helper Payroll suppresses the vanilla helper price and applies its own helper wage calculation using hourly rates, minimum charges, optional call-out fees, helper-slot mappings, and optional daily payroll.

## Alpha status

This is an **alpha/test build**. It has been tested against native AI fieldwork jobs, including mowing with the standard AI worker system. It is not yet a polished ModHub-ready release.

Current build: **0.1.3.3-alpha**  
FS25 modDesc: **110**

## What it does now

- Suppresses the vanilla AI helper wage calculation for supported AI jobs.
- Detects active AI fieldwork jobs.
- Tracks helper job duration.
- Applies configurable hourly helper wages.
- Supports a minimum charge per job or per daily payroll row, depending on billing mode.
- Supports optional call-out fees.
- Supports two billing modes:
  - `onJobFinish`
  - `dailyPayroll`
- Maintains session and daily ledger summaries in the log.
- Provides helper-slot mapping structure for future HelperProfiles integration.
- Includes UK Tenant Farm and US Ranch example rate profiles.

## What it does not do yet

- It does not yet automatically detect named helpers from FS25_HelperProfiles.
- It does not yet provide an in-game payroll UI.
- It does not yet persist/export the payroll ledger to a savegame XML file.
- It does not change contract rewards.
- It does not include a contract rate-card system.
- It has primarily been tested with `AIJobFieldWork`; other AI job categories may need further testing.

## Installation

1. Download `FS25_HelperPayroll_v0_1_3_3_alpha.zip`.
2. Place the ZIP in your Farming Simulator 25 mods folder.
3. Enable **Helper Payroll Alpha** in the save's mod selection screen.
4. Start a save and hire an AI worker.
5. Check `log.txt` for `[HelperPayroll]` entries.

## Configuration

Configuration is stored in:

```text
config/defaultPayrollConfig.xml
```

Key settings:

```xml
<defaultProfile>uk_tenant</defaultProfile>
<defaultWorker>skilled</defaultWorker>
<defaultHelperSlot></defaultHelperSlot>
<chargeCustomWorkerCosts>true</chargeCustomWorkerCosts>
<billingMode>onJobFinish</billingMode>
<payrollHour>18</payrollHour>
<minimumWorkerCharge>5.00</minimumWorkerCharge>
<workerCalloutFee>0.00</workerCalloutFee>
<roundWorkerCharges>true</roundWorkerCharges>
<logLevel>debug</logLevel>
```

### Billing modes

#### `onJobFinish`

The helper is charged when the AI job ends.

Example:

```text
Helper works 0.205 hours at £18/hour = £3.68
Minimum charge = £5.00
Applied charge = £5.00
```

#### `dailyPayroll`

The helper's work is added to the daily ledger. Payroll is applied once at or after the configured `payrollHour`.

Example:

```xml
<billingMode>dailyPayroll</billingMode>
<payrollHour>18</payrollHour>
```

The helper works during the day, the job is deferred to payroll, and the farm is charged at 18:00 game time.

## Helper slots

The alpha contains helper-slot mapping data, but it does not yet automatically connect to FS25_HelperProfiles.

Example UK profile:

```xml
<helperSlots profile="uk_tenant">
    <helper slot="A" name="Marty" role="Farm Manager" workerRate="manager" />
    <helper slot="B" name="Rhys" role="Skilled Operator" workerRate="skilled" />
    <helper slot="C" name="Ellie" role="General Farmhand" workerRate="casual" />
    <helper slot="D" name="Graham" role="Contractor" workerRate="contractor" />
</helperSlots>
```

For manual testing, set:

```xml
<defaultHelperSlot>B</defaultHelperSlot>
```

This will make jobs resolve to slot B, Rhys, using the configured skilled operator rate.

## Financial impact

Helper Payroll does affect the save's money balance.

It suppresses the vanilla AI helper cost and then applies its own charge using the game's money system with `MoneyType.AI`. Any money charged by the mod remains part of the save's financial history. Removing the mod later will not refund previous payroll charges.

The mod does not add required vehicles, placeables, fillTypes, animals, or map objects.

## Tested behaviour

Confirmed in testing:

- Native AI fieldwork/mowing detected as `AIJobFieldWork`.
- Vanilla helper price detected as `0.0005` per millisecond.
- The mod returns `0` to suppress the vanilla helper charge.
- `onJobFinish` billing applies correctly.
- `dailyPayroll` defers correctly and applies payroll at the configured hour.
- Minimum charge applies correctly.
- Session and daily ledger logs update correctly.

## Recommended alpha testing checklist

- Start a single-player test save.
- Enable Helper Payroll Alpha.
- Hire an AI worker for fieldwork.
- Confirm vanilla helper wages do not drain continuously.
- Confirm `[HelperPayroll] AI helper pricing suppressed` appears in the log.
- Test `onJobFinish` mode.
- Test `dailyPayroll` mode by advancing game time to the payroll hour.
- Test a manual `defaultHelperSlot` value, such as `B`.

## Compatibility notes

- Designed to coexist with FS25_HelperProfiles, but automatic integration is not implemented yet.
- Multiplayer is declared as supported, but the alpha should be treated as unverified for serious multiplayer saves until dedicated testing is completed.
- Other mods that override AI job pricing may conflict.

## Roadmap

Planned next steps:

1. HelperProfiles bridge diagnostics.
2. Automatic helper-slot detection.
3. Named helper payroll.
4. Persistent savegame payroll ledger.
5. Optional in-game payroll summary UI.
6. Wider AI job type testing.

Contract reward realism is now intended to become a separate future mod, likely `FS25_ContractRateCard`.
