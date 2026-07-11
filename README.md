# FS25_HelperPayroll

**Helper Payroll** is an alpha Farming Simulator 25 mod that replaces the vanilla AI helper wage drain with a configurable payroll model.

Instead of letting the game charge its built-in AI helper rate continuously, HelperPayroll suppresses supported vanilla AI helper wage calculations and applies configurable role-based worker costs, minimum charges, optional call-out fees, and optional daily payroll.

## Alpha status

Current build: **0.1.9.1 Alpha RC**  
FS25 modDesc: **110**

This is a GitHub alpha release candidate. The standalone vanilla `roleType` workflow has been tested with native AI fieldwork jobs. Multiplayer and dedicated-server behaviour are intentionally not declared as supported in this alpha.

## Tested vanilla workflow

```text
Open role list with RCTRL + ;
Cycle payroll role with ;
Start an AI worker
Vanilla helper slot is detected but ignored for payroll in roleType mode
Selected role/rate is billed when the worker finishes
Payroll entry is written to the persistent ledger
Payroll can be reviewed through the report overlay or console report commands
```

## Features in this alpha

- Suppresses vanilla AI helper wage calculation for supported AI jobs.
- Tracks native AI fieldwork jobs and elapsed work time.
- Default vanilla-friendly `roleType` payroll mode.
- Advanced `helperSlot` mode for A-J helper-slot/named-helper mapping.
- HelperProfiles-style role list overlay.
- In-game payroll report overlay.
- Persistent per-savegame settings.
- Persistent payroll ledger with lightweight `index.xml` and period files such as `Y001_M06.xml`.
- Console commands for role control, overlay layout, report review, and report export.
- Configurable hourly rates, minimum worker charge, call-out fee, and billing mode.
- Supports `onJobFinish` and `dailyPayroll` billing modes.
- Generic default rates plus example UK Tenant Farm and US Ranch profiles.

## Default controls

```text
;           Cycle payroll role / next report page when the report overlay is open
RCTRL + ;   Open/close payroll role list
RCTRL + P   Open/close payroll report overlay
```

The active/highlighted role is the selected role. There is no Enter/confirm step. The selected role applies to new AI helper jobs started after the role is changed. Existing active jobs keep the role they were assigned when they started.

## Payroll report overlay

The report overlay is read-only and intentionally lightweight for alpha. It has four pages:

```text
1. Summary
2. Current period
3. Recent jobs
4. Role totals
```

Use `RCTRL + P` to open/close it and `;` to cycle pages while it is open.

## Console commands

```text
hpayOverlay help
hpayOverlay on|off|toggle|status
hpayOverlay pos <x> <y>
hpayOverlay anchor TL|TR|BL|BR
hpayOverlay scale <0.5..2.0>
hpayOverlay width <0.15..0.90>
hpayOverlay opacity <0..1>
hpayOverlay font <0.010..0.030>
hpayOverlay rowgap <0.001..0.03>
hpayOverlay maxrows <3..30>
hpayOverlay pad <0..0.05>
hpayOverlay bg on|off
hpayOverlay outline on|off
hpayOverlay shadow on|off
hpayOverlay debounce <ms>
hpayOverlay reset

hpayRole help
hpayRole show
hpayRole list
hpayRole next
hpayRole prev
hpayRole set <roleId|index|name>

hpayReport help
hpayReport summary
hpayReport session
hpayReport jobs [limit]
hpayReport month <year> <month>
hpayReport roles
hpayReport daily
hpayReport export <name>
hpayReport exportSession <name>

hpayDump status
hpayDump roles
hpayDump ledger
hpayDump report
```

## Payroll modes

### `roleType` — recommended vanilla mode

This is the default public alpha mode.

The vanilla game may randomly assign helper slots A-J, but HelperPayroll does **not** use that random slot to decide pay. All new AI jobs use the selected payroll role:

```xml
<payrollMode>roleType</payrollMode>
<selectedRole>standard</selectedRole>
```

Example:

```text
[HelperPayroll] AI job detected #1: ... payrollMode=roleType helperSlot=G helperSlotUsedForPayroll=false helper=Trainee Helper workerRate=trainee rate=10.00
```

### `helperSlot` — advanced / HelperProfiles-friendly mode

This mode uses the vanilla helper slot detected from the AI job:

```xml
<payrollMode>helperSlot</payrollMode>
```

Example mapping:

```text
helperIndex=1  -> helperSlot=A
helperIndex=2  -> helperSlot=B
helperIndex=10 -> helperSlot=J
```

This can align with **FS25_HelperProfiles** without a hard dependency. HelperProfiles can control the visual helper slot while HelperPayroll bills the same slot using the configured payroll entry.

## Persistent settings

Per-save settings are stored in:

```text
modSettings/FS25_HelperPayroll/<savegame>/helperPayrollSettings.xml
```

This stores selected role, payroll mode/profile, fallback role, role selector debounce, and overlay layout settings.

## Persistent payroll ledger

Payroll history is stored per savegame in a split ledger structure:

```text
modSettings/FS25_HelperPayroll/<savegame>/ledger/
    index.xml
    Y001_M06.xml
```

`index.xml` stores fast summaries. Period files such as `Y001_M06.xml` store detailed job/payment rows. The mod loads the index and current period during normal startup; older periods are loaded on demand by report commands.

## Configuration

Default configuration is stored in:

```text
config/defaultPayrollConfig.xml
```

Key settings:

```xml
<activePayrollProfile>default</activePayrollProfile>
<payrollMode>roleType</payrollMode>
<selectedRole>standard</selectedRole>
<fallbackRole>standard</fallbackRole>
<chargeCustomWorkerCosts>true</chargeCustomWorkerCosts>
<billingMode>onJobFinish</billingMode>
<payrollHour>18</payrollHour>
<minimumWorkerCharge>5.00</minimumWorkerCharge>
<workerCalloutFee>0.00</workerCalloutFee>
<roundWorkerCharges>true</roundWorkerCharges>
<logLevel>normal</logLevel>
<helperProfilesDiagnostics>false</helperProfilesDiagnostics>
```

HelperPayroll does **not** define currency, area units, or distance units. It uses the savegame/game display settings.

## Billing modes

### `onJobFinish`

The helper is charged when the AI job ends.

```text
Helper works 0.205 hours at 18/hour = 3.69
Minimum charge = 5.00
Applied charge = 5.00
```

### `dailyPayroll`

The helper's work is added to the daily ledger. Payroll is applied once at or after the configured `payrollHour`.

```xml
<billingMode>dailyPayroll</billingMode>
<payrollHour>18</payrollHour>
```

## Alpha limitations

- Primary alpha path is vanilla `roleType` mode.
- `helperSlot` mode exists for advanced testing but is not the main alpha workflow.
- Payroll reports are command/overlay based; there is no full mouse-driven payroll management UI yet.
- Historical browsing is intentionally lightweight and paged.
- Multiplayer/dedicated server behaviour is not supported in this alpha package.
- Broad testing is still needed beyond native `AIJobFieldWork`.
- Contract reward/rate-card behaviour is intentionally out of scope for this mod.

## Installation

1. Download the ZIP from the GitHub alpha release.
2. Place the ZIP in your Farming Simulator 25 mods folder.
3. Enable **Helper Payroll Alpha** in the save's mod selection screen.
4. Start a save and hire an AI worker.
5. Check the in-game report overlay or `log.txt` for `[HelperPayroll]` entries.

Do not use GitHub's green **Code** button unless you want the source files.

## Compatibility notes

### FS25_HelperProfiles

HelperPayroll does not require HelperProfiles.

If `payrollMode=helperSlot`, HelperPayroll can align with HelperProfiles through the vanilla helper slot system. For standalone vanilla use, keep `payrollMode=roleType`.

### AvatarSwitcher

HelperPayroll does not require AvatarSwitcher. If HelperProfiles uses AvatarSwitcher for worker appearance, HelperPayroll remains separate and only cares about payroll identity/rate mapping.

## Recommended alpha test checklist

- First-run load with no existing ledger.
- Existing-save load with a populated ledger.
- Role list open/close.
- Role cycling and selected-role persistence.
- Short job below minimum charge.
- Longer job exceeding minimum charge.
- Report overlay page cycling.
- `hpayReport summary` and `hpayReport jobs 10`.
- `hpayReport export <name>`.
