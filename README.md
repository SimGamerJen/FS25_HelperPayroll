# FS25_HelperPayroll

**Helper Payroll** replaces Farming Simulator 25's continuous vanilla AI-worker wage drain with a configurable payroll system.

The mod suppresses supported native AI helper pricing, captures each worker assignment when the job begins, and bills the work using either a standalone payroll role or the deployed A–J helper identity. Payroll settings and history are stored per savegame.

## Current release

**Version:** 0.3.3.0 Beta Release Candidate  
**FS25 modDesc:** 110  
**Multiplayer:** Not currently supported

This release candidate consolidates the tested HelperProfiles integration and the accelerated-time-safe daily payroll scheduler. Routine hourly payroll-clock checks are no longer written at normal log level; detailed timing remains available through `hpayDump clock` or by setting `logLevel` to `debug`.

### Verified in-game

- Vanilla AI helper pricing suppression.
- Standalone `roleType` billing.
- Optional HelperProfiles API integration without a hard dependency.
- Stable named-worker identity while helpers are active.
- Immutable job-start role and rate snapshots.
- Pending daily-payroll persistence and recovery.
- Scheduled payroll settlement at the configured in-game hour while time is accelerated.
- Minimum daily charge and persistent payment-ledger entry.
- HelperProfiles semicolon-key handoff.

### Release-candidate validation still recommended

- Overdue settlement immediately after advancing to a later game day.
- Pending payroll across save and reload.
- Several named workers with different roles and rates on the same day.
- Identity-based mapping after moving a named HelperProfiles worker to another slot.
- Duplicate-payment protection after settlement and reload.

## Features

- Suppresses supported vanilla AI helper wage calculations.
- Tracks native AI jobs and elapsed working time.
- Two payroll modes: `roleType` and `helperSlot`.
- Two billing modes: `onJobFinish` and `dailyPayroll`.
- Configurable role rates, minimum charge, callout fee, payroll hour and rounding.
- Current-save management screen opened with `RCTRL + H`.
- Optional HelperProfiles identity integration through a read-only shared API.
- Per-save named-worker-to-role mappings.
- Immutable worker identity, role and rate snapshot for every job.
- Persistent pending daily payroll.
- Persistent ledger index and monthly period files.
- Read-only report overlay and console reports.
- External global/default policy file plus per-save overrides.

## Payroll modes

### `roleType`

The standalone and default mode. Every new AI job uses the currently selected HelperPayroll role. The randomly assigned vanilla A–J helper slot is recorded for diagnostics but does not determine pay.

```xml
<payrollMode>roleType</payrollMode>
<selectedRole>standard</selectedRole>
```

Without HelperProfiles, use:

```text
;             Cycle payroll role
RCTRL + ;     Open or close the payroll role list
```

### `helperSlot`

The deployed AI job's `helperIndex` identifies slot A–J. HelperPayroll resolves that slot against the current save's worker mapping.

When HelperProfiles is enabled and its optional API is available, HelperProfiles supplies the live worker identity and display name. HelperPayroll continues to own the payroll role, rate, billing and history.

```xml
<payrollMode>helperSlot</payrollMode>
```

A stable `identityId` is preferred over the slot letter, so an AvatarSwitcher-bound worker can retain their payroll role after moving to another slot.

## Billing modes

### `onJobFinish`

Each completed job is charged immediately. The callout fee and minimum charge apply to that job.

### `dailyPayroll`

Completed work is aggregated by worker and workday. The callout fee and minimum charge apply once to that worker's daily row.

Payroll settles when:

- the configured payroll hour is reached on the workday; or
- the row belongs to an earlier monotonic game day and is therefore overdue.

The scheduler uses FS25's `environment.currentMonotonicDay` and `environment.dayTime`, so accelerated time cannot skip the payroll trigger. Pending rows are stored in the current save settings and survive reloads.

## Controls

```text
RCTRL + H     Open HelperPayroll management
RCTRL + P     Open or close payroll report overlay
;             Cycle role or report page when HelperProfiles is absent
RCTRL + ;     Open or close role list when HelperProfiles is absent
```

When HelperProfiles is detected, HelperPayroll suppresses its semicolon controls for that session so HelperProfiles owns the key family.

## Management screen

Open the management screen with `RCTRL + H`.

- **OVERVIEW** — active policy, integration and pending-row status.
- **BILLING** — payroll mode, billing mode, payroll hour, minimum and callout.
- **ROLES** — hourly rates for the active profile.
- **WORKERS** — A–J or live HelperProfiles identity mappings.
- **LEDGER** — accumulated ledger totals.
- **HELP** — storage and mode guidance.

Changes are staged until **APPLY** is pressed. APPLY writes to the current save only.

## Configuration and storage

Configuration precedence:

1. Bundled template and fallback:
   `FS25_HelperPayroll/config/defaultPayrollConfig.xml`
2. Player-editable global defaults:
   `modSettings/FS25_HelperPayroll/defaultPayrollConfig.xml`
3. Current-save settings and overrides:
   `modSettings/FS25_HelperPayroll/<savegame>/helperPayrollSettings.xml`
4. Current-save payroll history:
   `modSettings/FS25_HelperPayroll/<savegame>/ledger/`

The ledger contains:

```text
index.xml
Y001_M06.xml
```

HelperPayroll does not write to HelperProfiles or AvatarSwitcher files.

## Default roles

The bundled default profile includes:

```text
Owner Labour       0.00/hr
Trainee Helper    10.00/hr
Standard Helper   18.00/hr
Skilled Operator  22.00/hr
Contractor        30.00/hr
```

Example UK Tenant and US Ranch profiles are also supplied in the default policy.

## Console commands

### Runtime and scheduler

```text
hpayDump status
hpayDump clock
hpayDump roles
hpayDump ledger
hpayDump report
hpayDump config
```

`hpayDump clock` prints the authoritative game clock and the due state of every pending daily-payroll row.

### HelperProfiles integration

```text
hpayProfiles status
hpayProfiles slots
```

### Current save and global defaults

```text
hpaySave status
hpaySave path
hpaySave reload
hpaySave reset

hpayConfig status
hpayConfig path
hpayConfig reload
hpayConfig reset
```

### Roles, reports and overlay

```text
hpayRole show
hpayRole list
hpayRole next
hpayRole prev
hpayRole set <roleId|index|name>

hpayReport summary
hpayReport session
hpayReport jobs [limit]
hpayReport month <year> <month>
hpayReport roles
hpayReport daily
hpayReport export <name>
hpayReport exportSession <name>

hpayOverlay help
hpayOverlay status
hpayOverlay reset
```

## Diagnostics

Normal logging records job detection, deferred work, settlements, persistence and warnings. Routine hour-by-hour payroll checks are emitted only when the active policy has:

```xml
<logLevel>debug</logLevel>
```

For a one-off scheduler inspection, leave normal logging enabled and run:

```text
hpayDump clock
```

## Installation

1. Place the ZIP directly in the Farming Simulator 25 mods folder.
2. Enable **Helper Payroll Beta** for the save.
3. Open `RCTRL + H` to review the current-save policy.
4. Start an AI worker and review the ledger or log output.

The mod files must remain at the root of the ZIP.

## Compatibility

### HelperProfiles

HelperProfiles is optional. With a compatible version enabled, HelperPayroll consumes the live read-only integration API and hands the semicolon controls to HelperProfiles. Without it, the complete standalone `roleType` workflow remains available.

### AvatarSwitcher

There is no direct dependency. AvatarSwitcher-bound preset IDs may be exposed by HelperProfiles as stable worker identities, but HelperPayroll only stores payroll mappings and history.

## Limitations

- Multiplayer and dedicated-server behaviour are not supported in this build.
- The principal tested job type is native `AIJobFieldWork`.
- Historical browsing is intentionally lightweight.
- Contract reward and rate-card behaviour is outside this mod's scope.

## Licence

See [LICENSE](LICENSE).
