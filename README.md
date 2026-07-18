# FS25 HelperPayroll

**FS25 HelperPayroll** replaces Farming Simulator 25's continuous AI-worker wage deductions with a configurable payroll system.

Instead of paying every helper at one fixed game-controlled rate, farms can define payroll roles, set their own hourly rates, choose when charges are settled, assign roles to individual A–J helper slots, and review a persistent payroll ledger.

The mod works independently in its default `roleType` mode. Optional integration with [FS25 HelperProfiles](https://github.com/SimGamerJen/FS25_HelperProfiles) adds live worker identities and save-specific role mappings.

> **Current release:** `0.3.3.1` beta release candidate  
> **Game:** Farming Simulator 25  
> **Multiplayer:** Not currently supported

---

## Main Features

- Suppresses the game's normal AI-worker wage deductions.
- Calculates custom labour charges from configurable payroll roles.
- Includes Owner, Trainee, Standard, Skilled and Contractor defaults.
- Supports immediate job-finish billing or scheduled daily payroll.
- Supports a global minimum charge and call-out fee.
- Provides a game-styled payroll-management screen.
- Supports role-based and A–J helper-slot payroll modes.
- Stores settings and worker mappings separately for each savegame.
- Records persistent payroll history by month, role, helper and job.
- Provides an in-game role list, report overlay and console tools.
- Optionally consumes live worker identities from an API-enabled HelperProfiles build.
- Captures the worker assignment when a job starts, preventing later role changes from altering a job already in progress.
- Uses the authoritative game clock for accelerated-time-safe daily payroll.

---

## How Payroll Works

### Payroll modes

HelperPayroll provides two worker-assignment modes.

#### `roleType`

This is the default, standalone-friendly mode.

Every new AI job uses the currently selected payroll role. For example, selecting **Skilled Operator** causes subsequently started jobs to use that role and its configured hourly rate.

The assignment is captured when the job starts. Changing the selected role afterwards does not retroactively change an active job.

#### `helperSlot`

This mode assigns payroll roles to the detected vanilla helper slots A–J.

It can operate with slot fallbacks from the payroll policy, but is intended for advanced use with HelperProfiles. When a compatible HelperProfiles API is available, HelperPayroll can use live worker names and stable identities while retaining save-specific payroll mappings.

### Billing modes

#### `onJobFinish`

The calculated charge is deducted when an AI job finishes.

For each completed job:

```text
labour = elapsed hours × hourly rate
subtotal = labour + call-out fee
charge = maximum(subtotal, minimum charge)
```

The minimum is only applied when the calculated subtotal is greater than zero.

#### `dailyPayroll`

Completed jobs are aggregated by worker and game day. At the configured payroll hour, HelperPayroll makes one payment for each worker with recorded work that day.

For each worker/day:

```text
subtotal = combined labour + one call-out fee
charge = maximum(subtotal, minimum charge)
```

Unpaid rows from an earlier game day are treated as overdue and settle automatically.

> `dailyPayroll` is a scheduled settlement mode, not a fixed daily salary. The current minimum charge is global and only applies to workers with recorded chargeable work.

### Current limitation

Version 0.3.3.1 uses hourly role rates. The minimum charge and call-out fee are global for the save, rather than configurable per role or per worker.

Per-role and per-worker hourly/daily pay policies are planned for a later development phase.

---

## Management Screen

Open the payroll-management screen with:

```text
RCTRL + H
```

The screen contains six tabs:

| Tab | Purpose |
|---|---|
| **Overview** | Displays the active profile, modes, selected role, policy values, integration status and save path. |
| **Billing** | Configures payroll mode, billing mode, payroll hour, minimum charge, call-out fee and rounding. |
| **Roles** | Displays the active role list and allows existing hourly rates to be adjusted. |
| **Workers** | Assigns payroll roles to A–J helper slots or HelperProfiles identities. |
| **Ledger** | Displays persistent payroll totals. |
| **Help** | Explains the management workflow and current modes. |

Changes are staged until **Apply** is selected. **Discard** restores the currently loaded values.

### Reload and reset

- **Reload Save** reloads the global policy and then reapplies the current save-specific settings. Its default button-bar shortcut is `X`.
- **Reset Save** has no competing `X` shortcut. It requires a second **Confirm Reset** action before replacing the current save's payroll policy, role list and mappings with the global defaults.

Resetting a save is destructive for that save's custom payroll configuration. It does not overwrite the global `defaultPayrollConfig.xml` file.

---

## Default Keybinds

Keybinds can be changed in the Farming Simulator controls menu.

| Action | Default binding | Description |
|---|---:|---|
| Cycle payroll role | `;` | Selects the next role in `roleType` mode. |
| Toggle payroll role list | `RCTRL + ;` | Shows or hides the standalone role list. |
| Toggle payroll report | `RCTRL + P` | Opens or closes the payroll report overlay. |
| Open management screen | `RCTRL + H` | Opens the full payroll-management UI. |

When HelperProfiles is enabled, it owns the semicolon key family. HelperPayroll therefore suppresses its standalone role-cycle and role-list inputs for that session to prevent conflicts. The management and report shortcuts remain available.

---

## Installation

1. Download `FS25_HelperPayroll.zip` from the GitHub release.
2. Place the ZIP directly in your Farming Simulator 25 mods folder:

```text
Documents/My Games/FarmingSimulator2025/mods
```

3. Do not unpack the ZIP.
4. Launch Farming Simulator 25.
5. Enable **Helper Payroll Beta** for the intended savegame.

HelperProfiles is optional. HelperPayroll remains usable in standalone `roleType` mode when HelperProfiles is absent or does not expose the required shared API.

Because this is a beta release candidate, test it on a copied save before relying on it in an important playthrough.

---

## Configuration and Save Data

### Global policy template

On first use, HelperPayroll creates an editable global policy file at:

```text
Documents/My Games/FarmingSimulator2025/modSettings/FS25_HelperPayroll/defaultPayrollConfig.xml
```

This file supplies the defaults for new saves and for the **Reset Save** action.

The bundled configuration inside the mod ZIP remains a fallback and template. Do not edit the copy inside the ZIP for normal configuration.

### Save-specific settings

Each save stores its active payroll policy, role list, worker mappings, pending daily payroll and overlay settings at:

```text
Documents/My Games/FarmingSimulator2025/modSettings/FS25_HelperPayroll/savegameX/helperPayrollSettings.xml
```

Replace `savegameX` with the relevant save slot, such as `savegame17`.

Save-specific values take priority over the global defaults. Editing `defaultPayrollConfig.xml` does not automatically replace an existing save's active settings.

Use one of the following after editing XML while the game is running:

- Select **Reload Save** in the management screen.
- Run `hpaySave reload` in the console.

Use **Reset Save** only when you deliberately want the current save to inherit the global policy again.

### Persistent ledger

Payroll history is stored under:

```text
Documents/My Games/FarmingSimulator2025/modSettings/FS25_HelperPayroll/savegameX/ledger
```

The folder contains an index and period files such as:

```text
index.xml
Y001_M06.xml
```

Exported text reports are written to the save-specific HelperPayroll folder.

---

## Default Roles

The default public payroll profile includes:

| Role ID | Display name | Hourly rate |
|---|---|---:|
| `owner` | Owner Labour | 0.00 |
| `trainee` | Trainee Helper | 10.00 |
| `standard` | Standard Helper | 18.00 |
| `skilled` | Skilled Operator | 22.00 |
| `contractor` | Contractor | 30.00 |

The policy template also contains example UK tenant-farm and US ranch profiles.

All numeric rates use the active save's currency context.

---

## Adding a Custom Role

The current management UI can edit existing role rates but does not yet provide Add, Rename or Delete Role controls.

Custom roles can be added to the save-specific `helperPayrollSettings.xml` file. Add another worker entry within `<workerRates>`:

```xml
<workerRates>
    <worker profile="default" role="seasonal" name="Seasonal Worker" hourlyRate="16.00" />
</workerRates>
```

The actual file will usually contain the existing roles as well. Keep those entries unless you deliberately want to remove them from that save.

After saving the XML, select **Reload Save** or run:

```text
hpaySave reload
```

Version 0.3.3.1 treats the save-specific role section as authoritative for each profile it contains. Custom IDs, names and rates are loaded into the UI and preserved when **Apply** writes the save again. Familiar policy roles retain their policy order; save-only roles are appended in their XML order.

If the selected or fallback role no longer exists, HelperPayroll selects a valid role from the loaded list.

---

## Default Policy Example

The following is a shortened example of the global policy structure:

```xml
<helperPayroll>
    <settings>
        <suppressVanillaAIWorkerCosts>true</suppressVanillaAIWorkerCosts>
        <enableCustomWorkerCosts>true</enableCustomWorkerCosts>
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
    </settings>

    <profiles>
        <profile id="default" name="Default Helper Payroll" economyMultiplier="1.00" />
    </profiles>

    <workerRates profile="default">
        <worker id="owner" name="Owner Labour" hourlyRate="0" />
        <worker id="trainee" name="Trainee Helper" hourlyRate="10" />
        <worker id="standard" name="Standard Helper" hourlyRate="18" />
        <worker id="skilled" name="Skilled Operator" hourlyRate="22" />
        <worker id="contractor" name="Contractor" hourlyRate="30" />
    </workerRates>
</helperPayroll>
```

---

## HelperProfiles Integration

HelperProfiles is optional and is not a hard dependency.

With a compatible API-enabled HelperProfiles build, HelperPayroll can:

- Read live A–J helper identities and display names.
- Retain mappings by stable identity where available.
- Show selected and in-use worker information in the management UI.
- Assign different payroll roles to individual workers.
- Include worker identity data in payroll reports and ledger entries.

In `helperSlot` mode, the detected `job.helperIndex` identifies the A–J slot. HelperProfiles supplies the live identity, and HelperPayroll applies the save-specific identity or slot mapping.

If HelperProfiles is loaded without the required shared API, HelperPayroll logs the condition and remains available in standalone `roleType` mode.

Check the current integration state with:

```text
hpayProfiles status
hpayProfiles slots
```

---

## Console Commands

Run each main command with `help` to display its available subcommands.

### Role selection

| Command | Description |
|---|---|
| `hpayRole status` | Displays the active profile, selected role and rate. |
| `hpayRole list` | Lists the available roles. |
| `hpayRole next` | Selects the next role. |
| `hpayRole prev` | Selects the previous role. |
| `hpayRole set <id\|index\|name>` | Selects a role immediately. |

### Overlay

| Command | Description |
|---|---|
| `hpayOverlay on\|off\|toggle` | Controls the role-list overlay. |
| `hpayOverlay status` | Displays overlay and selected-role status. |
| `hpayOverlay pos <x> <y>` | Sets normalized screen position. |
| `hpayOverlay anchor TL\|TR\|BL\|BR` | Sets the anchor corner. |
| `hpayOverlay scale <0.5..2.0>` | Sets overlay scale. |
| `hpayOverlay width <0.15..0.90>` | Sets overlay width. |
| `hpayOverlay opacity <0..1>` | Sets background opacity. |
| `hpayOverlay font <0.010..0.030>` | Sets font size. |
| `hpayOverlay rowgap <0.001..0.03>` | Sets row spacing. |
| `hpayOverlay maxrows <3..30>` | Sets the maximum visible rows. |
| `hpayOverlay pad <0..0.05>` | Sets padding. |
| `hpayOverlay bg\|outline\|shadow on\|off` | Controls visual elements. |
| `hpayOverlay debounce <ms>` | Sets role-selector debounce time. |
| `hpayOverlay reset` | Restores the overlay defaults. |

### Reports and ledger

| Command | Description |
|---|---|
| `hpayReport summary` | Prints the persistent ledger summary. |
| `hpayReport session` | Prints the current in-memory session report. |
| `hpayReport jobs [limit] [period]` | Prints recent persisted entries. |
| `hpayReport month <year> <month>` | Prints a specific monthly ledger. |
| `hpayReport roles` | Prints persistent totals by role/helper rate. |
| `hpayReport daily` | Prints pending in-memory daily payroll rows. |
| `hpayReport export [name]` | Exports the persistent ledger summary. |
| `hpayReport exportSession [name]` | Exports the current session report. |

### Configuration and diagnostics

| Command | Description |
|---|---|
| `hpayConfig status` | Shows the global policy source and template values. |
| `hpayConfig path` | Prints the global policy path. |
| `hpayConfig reload` | Reloads the global policy and current save overrides. |
| `hpayConfig reset` | Regenerates the global policy from bundled defaults. |
| `hpaySave status` | Shows the current save's effective settings. |
| `hpaySave path` | Prints the current save settings path. |
| `hpaySave reload` | Reloads the global policy and current save settings. |
| `hpaySave reset` | Immediately resets the current save from the global policy. |
| `hpayProfiles status` | Shows HelperProfiles/API integration status. |
| `hpayProfiles slots` | Lists A–J identities and payroll mappings. |
| `hpayDump status` | Prints the full runtime status. |
| `hpayDump clock` | Shows the payroll clock and pending-row due state. |
| `hpayDump roles\|ledger\|report\|config` | Prints the selected diagnostic view. |

> Unlike the management-screen reset, the console command `hpaySave reset` does not present a confirmation screen.

---

## Troubleshooting

### Vanilla AI wages are still appearing

Check that HelperPayroll is enabled for the save and inspect:

```text
hpayDump status
hpayConfig status
hpaySave status
```

Confirm that the policy contains:

```xml
<suppressVanillaAIWorkerCosts>true</suppressVanillaAIWorkerCosts>
<enableCustomWorkerCosts>true</enableCustomWorkerCosts>
<chargeCustomWorkerCosts>true</chargeCustomWorkerCosts>
```

### A custom role does not appear

- Confirm that it was added to the active save's `helperPayrollSettings.xml`, not only another save slot.
- Confirm that its `profile` matches the active payroll profile.
- Give the role a unique, non-empty ID.
- Use **Reload Save** or `hpaySave reload` after editing.
- Check `log.txt` for duplicate-role or XML warnings.

### Daily payroll did not settle at the expected time

Run:

```text
hpayDump clock
hpayReport daily
```

Pending rows from an earlier game day should settle automatically, even when the configured hour was skipped through accelerated time.

### HelperProfiles names are unavailable

Run:

```text
hpayProfiles status
```

If HelperProfiles is detected but the API is unavailable, update to an API-enabled HelperProfiles build. HelperPayroll will continue to work in standalone `roleType` mode.

### The semicolon controls do not work

When HelperProfiles is enabled, it intentionally owns the semicolon controls. Use the management screen or `hpayRole` console commands for payroll changes.

Also check the Farming Simulator controls menu for local keybind overrides or conflicts.

### Requesting support

Include:

- HelperPayroll version.
- Relevant `log.txt` excerpt.
- Savegame number.
- Active payroll and billing modes.
- Whether HelperProfiles is enabled.
- Clear steps to reproduce the issue.

---

## Version 0.3.3.1

This maintenance build fixes two management-screen and persistence issues found in 0.3.3.0:

- **Reload Save** and **Reset Save** no longer share the same `X` action.
- Reset now requires a second confirmation action in the management screen.
- Save-specific roles no longer need to exist in the global policy before they can be loaded.
- Custom role IDs, display names and rates are preserved when the UI writes the save.
- Save-only roles retain their relative XML order after the known policy roles.
- Invalid selected or fallback roles are safely reassigned after a role-list change.

The finished ZIP was also checked for valid Lua syntax, valid XML and correct top-level FS25 packaging.

---

## Planned Development

The current roadmap includes:

- Per-role and per-worker minimum call-out settings.
- A per-role or per-worker choice between hourly and daily pay.
- Worker-specific overrides that can inherit from role defaults.
- Separate worked-day and rostered-day daily-pay policies.
- Add, rename and delete role controls in the management UI.
- Continued improvement of payroll reporting and HelperProfiles integration.

These items are planned directions and are not yet included in version 0.3.3.1.

---

## Permissions

Copyright © SimGamerJen. All rights reserved.

**Editing, redistributing, or publishing modified versions of this mod is prohibited without prior written permission from the mod author.**

The presence of source files in this repository does not grant permission to republish, repackage, redistribute or release modified versions of the mod.

---

## Disclaimer

FS25 HelperPayroll is an unofficial Farming Simulator 25 mod and is not affiliated with or endorsed by GIANTS Software.
