# FS25 HelperPayroll

**FS25 HelperPayroll** replaces Farming Simulator 25's continuous AI-worker wage deductions with a configurable, save-specific payroll system.

It supports role-based and named-worker compensation, hourly or daily pay, per-role minimum call-outs, per-worker overrides, immediate or scheduled settlement, persistent ledger reporting, and optional integration with HelperProfiles.

> **Current version:** `0.4.2.0` Alpha 2  
> **Game:** Farming Simulator 25  
> **Multiplayer:** Not supported

## Main Features

- Suppresses the game's normal continuous AI-worker wage deductions.
- Calculates custom worker charges from configurable payroll policies.
- Supports `roleType` and `helperSlot` payroll modes.
- Supports helper slots **A–T** when used with the twenty-worker HelperProfiles roster.
- Accepts canonical identities `helper01` through `helper20` and legacy slot identities.
- Supports hourly and daily compensation independently of payment timing.
- Configures pay basis, rate, and minimum call-out for each role.
- Allows each worker to inherit role terms or use a custom override.
- Supports immediate `onJobFinish` settlement or scheduled `dailyPayroll`.
- Supports a global call-out fee and optional charge rounding.
- Stores settings, role policies, worker mappings, and pending payroll per savegame.
- Captures worker identity, role, and compensation terms when a job starts.
- Records persistent payroll history by period, role, worker, and job.
- Provides an FS25-style management screen, overlays, reports, and console tools.
- Publishes an optional API used by HelperProfiles for read-only role display.

## Installation

1. Download `FS25_HelperPayroll.zip`.
2. Place the ZIP directly in the Farming Simulator 25 mods folder. Do not unpack it.

```text
Documents/My Games/FarmingSimulator2025/mods
```

3. Enable **Helper Payroll Alpha** for the intended savegame.
4. Optionally enable [FS25 HelperProfiles](https://github.com/SimGamerJen/FS25_HelperProfiles) for stable A–T helper identities, named workers, and the HelperProfiles overlay role column.

Alpha builds should be tested on a copied savegame before being used in an important playthrough.

## Default Controls

Keybinds can be reassigned in the Farming Simulator controls menu.

| Action | Default binding | Description |
|---|---:|---|
| Cycle payroll role | `;` | Selects the next role in standalone `roleType` mode. |
| Toggle role list | `RCTRL + ;` | Shows or hides the standalone role list. |
| Toggle report overlay | `RCTRL + P` | Shows or hides the payroll report. |
| Open management screen | `RCTRL + H` | Opens the full payroll-management UI. |

When HelperProfiles is active, it owns the semicolon key family. HelperPayroll suppresses its standalone `;` and `RCTRL + ;` actions for that session to avoid conflicts. The management and report shortcuts remain available.

## Core Concepts

HelperPayroll separates three decisions:

1. **Who is assigned?**  
   Controlled by the payroll mode and worker-role mapping.

2. **How is the worker paid?**  
   Controlled by the role or worker compensation policy: hourly or daily.

3. **When is the charge settled?**  
   Controlled by the billing mode: on job finish or at the daily payroll hour.

Changing one does not automatically change the others.

## Payroll Modes

### `roleType`

Standalone-friendly default.

Every new AI job uses the currently selected payroll role. The selected role and its compensation terms are captured when the job starts.

### `helperSlot`

Assigns roles to individual deployed helper slots.

- Supports A–T with HelperProfiles `2.1.0.0` or a compatible later build.
- Retains the existing standalone fallback when HelperProfiles is absent.
- Uses live display names and stable canonical identities when the HelperProfiles API is available.
- Stores identity and slot mappings in the current save.
- Supports separate custom compensation overrides for each worker.

Use the **Workers** tab in the HelperPayroll management screen to assign roles and compensation policies. HelperProfiles does not edit payroll data.

## Compensation Policies

### Hourly pay

Hourly work is based on the recorded job duration and the effective hourly rate.

```text
labour = worked hours × rate
subtotal = labour + applicable call-out fee
charge = maximum(subtotal, effective minimum call-out)
```

The effective minimum comes from the worker override when custom compensation is enabled, otherwise from the assigned role. Older save data can fall back to the legacy global minimum.

### Daily pay

A daily worker is charged once per worker per in-game day when that worker completes chargeable work.

- The role or worker rate is interpreted as a daily rate.
- Multiple completed jobs by the same worker on the same game day do not create multiple daily-rate charges.
- Minimum call-out is ignored for daily compensation.
- Payment timing still follows the selected billing mode.

### Role policy

Each role defines:

- `payBasis`: `hourly` or `daily`
- `rate`: hourly or daily amount
- `minimumCallout`: minimum charge when the role is hourly

### Worker override

Each managed worker can use:

- `inherit`: uses the assigned role policy
- `custom`: uses the worker's own pay basis, rate, and minimum call-out

With the twenty-slot HelperProfiles integration, the Workers tab supports A–T. This allows a role to be hourly by default while one named worker is paid a fixed daily amount.

## Job-Start Snapshot Behaviour

When a job starts, HelperPayroll captures the worker's:

- helper slot;
- canonical identity when available;
- display name;
- assigned role;
- pay basis, rate, and minimum call-out;
- mapping and compensation source.

Those values remain attached to the active job. Changing a worker's role or HelperProfiles appearance binding while the worker is active does not retroactively alter the ledger entry or charge for that job. The new assignment applies to later jobs.

## Billing Modes

### `onJobFinish`

Completed work is settled immediately.

- Hourly work is calculated when the job finishes.
- Daily compensation is applied once for that worker and game day.
- The global call-out fee is applied according to the current billing rules.

### `dailyPayroll`

Completed work is accumulated and settled at the configured in-game payroll hour.

- Pending rows are grouped by worker and game day.
- Earlier unpaid days are treated as overdue and settle automatically.
- The authoritative game clock is used so accelerated time cannot silently skip a due payroll row.

`dailyPayroll` controls settlement timing; it does not force every role to use daily compensation.

## Management Screen

Open the screen with:

```text
RCTRL + H
```

The screen contains six tabs:

| Tab | Purpose |
|---|---|
| **Overview** | Shows active profile, modes, selected role, integration status, pending payroll, and save path. |
| **Billing** | Edits payroll mode, billing mode, payroll hour, legacy minimum, global call-out fee, and rounding. |
| **Roles** | Edits each role's pay basis, rate, and minimum call-out. |
| **Workers** | Assigns roles and configures inherited or custom worker compensation for the managed roster. |
| **Ledger** | Displays persistent payroll totals. |
| **Help** | Explains assignment, compensation, and settlement. |

Changes are staged until **Apply** is selected. **Discard** restores the currently loaded values.

### Reload and reset

- **Reload Save** reloads the global policy and reapplies the current save-specific settings.
- **Reset Save** requires a second confirmation before replacing the current save's payroll settings with the global defaults.
- `hpaySave reset` performs the reset immediately and does not show the management-screen confirmation.

Resetting a save does not overwrite the global `defaultPayrollConfig.xml`.

## HelperProfiles Integration

HelperProfiles is optional and is not a hard dependency.

HelperPayroll `0.4.2.0` supports the twenty-slot HelperProfiles API and publishes its own role-assignment API globally and on the active mission.

With HelperProfiles `2.1.0.0` or a compatible later build:

- HelperProfiles supplies stable helper identities `helper01` through `helper20` and live display names.
- HelperPayroll supplies ordered role definitions and effective role mappings.
- HelperPayroll manages role assignments from its own **Workers** tab.
- Set payroll mode to `helperSlot` for individual A–T worker assignments to control payroll calculations.
- `roleType` continues to use the globally selected role.
- The HelperProfiles overlay displays a read-only **ROLE** column.
- Assignments are stored by stable identity where possible, with A–T slot fallback.
- Worker identities and roles are included in payroll reports and ledger entries.
- HelperPayroll remains responsible for compensation rules, worker overrides, settlement, and persistence.

Check integration status with:

```text
hpayProfiles status
hpayProfiles slots
```

HelperPayroll remains usable in standalone `roleType` mode when HelperProfiles is absent.

### Hired Helper Tool note

HelperProfiles and Hired Helper Tool are explicitly incompatible because both own the helper roster. When HelperProfiles disables itself due to that conflict, its shared identity API is intentionally unavailable to HelperPayroll. HelperPayroll remains responsible only for its own payroll behaviour and does not treat Hired Helper Tool's roster as a HelperProfiles A–T roster.

## Configuration and Save Data

### Global policy template

On first use, HelperPayroll creates:

```text
Documents/My Games/FarmingSimulator2025/modSettings/FS25_HelperPayroll/defaultPayrollConfig.xml
```

This file provides defaults for new saves and for **Reset Save**. The bundled XML inside the mod ZIP is a fallback/template and should not normally be edited.

### Save-specific settings

Each save stores its effective configuration at:

```text
Documents/My Games/FarmingSimulator2025/modSettings/FS25_HelperPayroll/savegameX/helperPayrollSettings.xml
```

The file contains:

- Active payroll profile.
- Payroll and billing modes.
- Role compensation policies.
- Worker-role mappings.
- Worker compensation overrides.
- Pending daily payroll.
- Overlay and reporting settings.

Save-specific settings take priority over the global template. Editing `defaultPayrollConfig.xml` does not automatically replace an existing save's settings.

Reload after manual XML edits with:

```text
hpaySave reload
```

### Persistent ledger

Payroll history is stored under:

```text
Documents/My Games/FarmingSimulator2025/modSettings/FS25_HelperPayroll/savegameX/ledger
```

Typical files include:

```text
index.xml
Y001_M06.xml
```

Exported reports are written to the current save's HelperPayroll settings folder.

## Default Roles

The bundled `default` profile contains:

| Role ID | Display name | Pay basis | Rate | Minimum call-out |
|---|---|---|---:|---:|
| `owner` | Owner Labour | Hourly | 0.00 | 0.00 |
| `trainee` | Trainee Helper | Hourly | 10.00 | 5.00 |
| `standard` | Standard Helper | Hourly | 18.00 | 5.00 |
| `skilled` | Skilled Operator | Hourly | 22.00 | 5.00 |
| `contractor` | Contractor | Hourly | 30.00 | 5.00 |

Rates use the active save's currency display and economy context.

The bundled policy also includes example `uk_tenant` and `us_ranch` profiles.

## Adding a Custom Role

The current UI can edit existing roles but does not yet add, rename, reorder, or delete role definitions.

Add custom roles to the relevant `<workerRates>` section in either the global template or the save-specific file:

```xml
<workerRates profile="default">
    <worker id="seasonal"
            name="Seasonal Worker"
            payBasis="hourly"
            rate="16.00"
            minimumCallout="5.00" />
</workerRates>
```

For a daily role:

```xml
<worker id="dayContractor"
        name="Day Contractor"
        payBasis="daily"
        rate="240.00"
        minimumCallout="0.00" />
```

After editing the active save file while the game is running:

```text
hpaySave reload
```

Role IDs must be unique and non-empty. Save-specific role definitions are preserved when the management screen writes the save.

## Policy Structure Example

```xml
<helperPayroll>
    <settings>
        <activePayrollProfile>default</activePayrollProfile>
        <payrollMode>helperSlot</payrollMode>
        <selectedRole>standard</selectedRole>
        <fallbackRole>standard</fallbackRole>
        <billingMode>dailyPayroll</billingMode>
        <payrollHour>18</payrollHour>
        <workerCalloutFee>0.00</workerCalloutFee>
        <roundWorkerCharges>true</roundWorkerCharges>
    </settings>

    <workerRates profile="default">
        <worker id="standard"
                name="Standard Helper"
                payBasis="hourly"
                rate="18.00"
                minimumCallout="5.00" />
        <worker id="contractor"
                name="Contractor"
                payBasis="daily"
                rate="250.00"
                minimumCallout="0.00" />
    </workerRates>

    <helperSlots profile="default">
        <helper slot="A"
                name="Helper A"
                role="Standard Helper"
                workerRate="standard" />
        <helper slot="T"
                name="Helper T"
                role="Contractor"
                workerRate="contractor" />
    </helperSlots>
</helperPayroll>
```

## Console Commands

Run a main command with `help` to display available subcommands.

### Roles

| Command | Description |
|---|---|
| `hpayRole status` | Shows the active profile, selected role, basis, and rate. |
| `hpayRole list` | Lists available roles. |
| `hpayRole next` | Selects the next role. |
| `hpayRole prev` | Selects the previous role. |
| `hpayRole set <id\|index\|name>` | Selects a role. |

### Overlays

| Command | Description |
|---|---|
| `hpayOverlay on\|off\|toggle` | Controls the standalone role-list overlay. |
| `hpayOverlay status` | Shows role-list overlay status. |
| `hpayOverlay pos <x> <y>` | Sets normalized screen position. |
| `hpayOverlay anchor TL\|TR\|BL\|BR` | Sets the anchor corner. |
| `hpayOverlay scale <0.5..2.0>` | Sets scale. |
| `hpayOverlay width <0.15..0.90>` | Sets width. |
| `hpayOverlay opacity <0..1>` | Sets background opacity. |
| `hpayOverlay font <0.010..0.030>` | Sets font size. |
| `hpayOverlay rowgap <0.001..0.03>` | Sets row spacing. |
| `hpayOverlay maxrows <3..30>` | Sets maximum rows. |
| `hpayOverlay pad <0..0.05>` | Sets padding. |
| `hpayOverlay bg\|outline\|shadow on\|off` | Controls visual elements. |

### Reports and ledger

| Command | Description |
|---|---|
| `hpayReport summary` | Prints the persistent ledger summary. |
| `hpayReport session` | Prints the current session report. |
| `hpayReport jobs [limit] [period]` | Prints recent persisted entries. |
| `hpayReport month <year> <month>` | Prints a specific monthly ledger. |
| `hpayReport roles` | Prints totals by role and worker rate. |
| `hpayReport daily` | Prints pending daily payroll rows. |
| `hpayReport export [name]` | Exports the persistent ledger summary. |
| `hpayReport exportSession [name]` | Exports the current session report. |

### Configuration and diagnostics

| Command | Description |
|---|---|
| `hpayConfig status` | Shows the global policy source and template values. |
| `hpayConfig path` | Prints the global policy path. |
| `hpayConfig reload` | Reloads global policy and save overrides. |
| `hpayConfig reset` | Regenerates the global template from bundled defaults. |
| `hpaySave status` | Shows the current save's effective settings. |
| `hpaySave path` | Prints the current save settings path. |
| `hpaySave reload` | Reloads global and current-save settings. |
| `hpaySave reset` | Immediately resets the current save from the global template. |
| `hpayProfiles status` | Shows HelperProfiles integration state. |
| `hpayProfiles slots` | Lists identities and payroll mappings. |
| `hpayDump status` | Prints full runtime status. |
| `hpayDump clock` | Shows payroll-clock and due-row state. |
| `hpayDump roles\|ledger\|report\|config` | Prints the selected diagnostic view. |

## Troubleshooting

### Vanilla AI wages still appear

Run:

```text
hpayDump status
hpayConfig status
hpaySave status
```

Confirm that suppression and custom charging are enabled in the active settings.

### A custom role is missing

- Confirm it was added to the active profile.
- Use a unique, non-empty role ID.
- Confirm `payBasis` is `hourly` or `daily`.
- Reload the active save settings.
- Check `log.txt` for XML or duplicate-role warnings.

### Daily compensation was charged unexpectedly

Remember that compensation basis and payment schedule are separate:

- A `daily` role is paid once per worker/day.
- `dailyPayroll` only controls when completed work is settled.
- An `hourly` role can still be settled through `dailyPayroll`.
- A `daily` role can still be settled through `onJobFinish`.

### Payroll did not settle at the configured hour

Run:

```text
hpayDump clock
hpayReport daily
```

Rows from an earlier game day should be treated as overdue and settle automatically.

### A–T workers or HelperProfiles identities are missing

Run:

```text
hpayProfiles status
hpayProfiles slots
```

Confirm that HelperProfiles `2.1.0.0` or a compatible later build is enabled, only one copy of each mod ZIP exists, and the game was fully restarted after replacing either mod.

Role assignments are edited in the HelperPayroll **Workers** tab. The HelperProfiles binding screen is for AvatarSwitcher appearances only.

### Requesting support

Include the HelperPayroll version, HelperProfiles version when installed, relevant `log.txt` excerpt, savegame number, active modes, and clear reproduction steps.

## Version History

### Version 0.4.2.0 Alpha 2

- Extended helper-slot handling from A–J to A–T.
- Added canonical `helper01` through `helper20` identity support.
- Extended role mappings, worker overrides, job-slot detection, and the Workers screen to 20 slots.
- Added default mappings for K–T.
- Updated HelperProfiles API discovery and twenty-slot integration.
- Retained job-start role, identity, and compensation snapshots.
- Kept all payroll editing within the HelperPayroll management UI.

### Version 0.4.1.1 Alpha 2

- Published the role-assignment API globally and on the active mission.
- Allowed HelperProfiles to discover the API reliably regardless of load order.
- Supplied ordered role definitions and effective identity/slot mappings.
- Retained hourly and daily role policies, worker overrides, and persistent ledger behaviour.

## Development Status

This is an alpha integration build.

Planned work includes:

- Add, rename, reorder, and delete role controls in the management UI.
- Optional rostered-day policies distinct from worked-day daily compensation.
- Continued reporting, localisation, and usability improvements.

## Permissions

Copyright © 2026 SimGamerJen. All rights reserved.

Editing, redistributing, re-uploading, repackaging, or publishing modified versions of this mod is prohibited without prior written permission from SimGamerJen.

The presence of source files in this repository does not grant permission to publish or redistribute derivative versions.

## Disclaimer

FS25 HelperPayroll is an unofficial Farming Simulator 25 mod and is not affiliated with or endorsed by GIANTS Software.
