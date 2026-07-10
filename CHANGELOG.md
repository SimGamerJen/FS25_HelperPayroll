# Changelog

## 0.1.3.3-alpha

### Added

- Alpha packaging and documentation.
- Helper Payroll DDS icon reference: `HelperPayroll_icon.dds`.
- README with installation, configuration, testing notes, limitations, and roadmap.

### Confirmed in testing

- AI fieldwork helper wage suppression.
- Custom worker billing on job finish.
- Daily payroll deferral and payroll-hour charging.
- Minimum charge application.
- Session and daily ledger logging.

### Known limitations

- HelperProfiles integration is not automatic yet.
- No in-game UI yet.
- No persistent payroll ledger export yet.
- Primarily tested with native AI fieldwork jobs.

## 0.1.3.3

- Updated mod icon reference to `HelperPayroll_icon.dds`.

## 0.1.3.2

- Improved final AI job billing-state logging.
- Replaced ambiguous `billed=true` style output with explicit billing-state fields.

## 0.1.3.1

- Renamed mod from RealisticContracting to HelperPayroll.
- Updated namespace, log prefix, config root, script name, and mod identity.

## 0.1.3.0

- Added optional daily payroll mode.
- Added payroll-hour based charging.
- Kept `onJobFinish` as default billing mode.

## 0.1.2.x

- Added helper-slot ledger structure.
- Added cleaner game-date formatting.
- Added helper-slot config logging and validation.

## 0.1.1.x

- Added custom worker billing.
- Added minimum charge, call-out fee, rounding, and session ledger totals.

## 0.1.0.x

- Proved AI helper wage suppression using `AIJob.getPricePerMs` and `AIJobFieldWork.getPricePerMs` hooks.
- Added active AI job tracking diagnostics.
