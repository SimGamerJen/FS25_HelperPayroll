# FS25_HelperPayroll v0.3.3.0 Beta Release Candidate

This build packages the proven HelperProfiles integration and authoritative daily-payroll scheduler into the first beta release candidate.

## Included

- Standalone `roleType` payroll remains fully functional without HelperProfiles.
- Optional HelperProfiles integration remains a soft dependency through the live read-only API.
- `helperSlot` mode resolves named workers and per-save payroll mappings.
- Every AI job captures an immutable worker identity, role and hourly rate at job start.
- Daily-payroll rows persist across save settings and reconcile with the persistent ledger.
- Payroll uses `currentMonotonicDay` and `dayTime` to survive accelerated time.
- Scheduled settlement at the configured payroll hour is confirmed in game.
- Minimum daily charge and payment-ledger persistence are confirmed in game.

## Release hardening

- Routine hourly payroll checks now require `logLevel=debug`.
- Settlement and accounting logs remain visible at normal log level.
- Startup produces one delayed runtime summary including payroll mode, billing mode, pending rows and HelperProfiles API state.
- `hpayDump status` now reports the release channel, pending rows and integration state.
- Management guidance now distinguishes per-job billing from per-worker/day payroll.

## Recommended release-candidate tests

1. Complete a job, pass midnight before the configured payroll hour, and confirm `reason=overdue-day`.
2. Save and reload with an unpaid daily row, then confirm it still settles.
3. Run several named workers at different rates and confirm one payment row per worker/day.
4. Move a named HelperProfiles identity to another slot and confirm its identity mapping follows it.
5. Reload after payment and confirm the same workday is not paid again.
6. Disable HelperProfiles and confirm standalone semicolon role controls return.

## Compatibility

- HelperProfiles is optional and is not listed as a required dependency.
- HelperPayroll never writes to HelperProfiles or AvatarSwitcher files.
- Existing 0.2.x and 0.3.x current-save settings and ledgers remain readable.
- Multiplayer and dedicated-server support remain disabled.
