-- FS25_HelperPayroll
-- Serializable, read-only payroll snapshots for the dashboard and public API.
-- Tables returned here deliberately contain no functions, mission objects,
-- jobs, vehicles or other userdata, making the schema suitable for later
-- server-to-client transport without changing consumers.

HelperPayrollSnapshot = HelperPayrollSnapshot or {}
HelperPayrollSnapshot.SCHEMA_VERSION = 2

local function round(value, places)
    local n = tonumber(value) or 0
    local p = 10 ^ (places or 2)
    return math.floor(n * p + 0.5) / p
end

local function copyCompatibility(status)
    status = status or {}
    local result = {
        schemaVersion = tonumber(status.schemaVersion) or 1,
        safe = status.safe ~= false,
        blocked = status.blocked == true,
        detectedCount = tonumber(status.detectedCount) or 0,
        primaryConflictId = status.primaryConflictId,
        primaryConflictName = status.primaryConflictName,
        message = tostring(status.message or "Compatibility status unavailable."),
        conflicts = {}
    }
    for _, conflict in ipairs(status.conflicts or {}) do
        table.insert(result.conflicts, {
            id = conflict.id,
            displayName = conflict.displayName,
            loadedName = conflict.loadedName,
            detectionSource = conflict.detectionSource,
            reason = conflict.reason
        })
    end
    return result
end

local function getRoleName(owner, assignment)
    local roleId = tostring(assignment.helperRole or assignment.workerId or "standard")
    local worker = owner.getWorkerRateById ~= nil and owner:getWorkerRateById(assignment.profileId, assignment.workerId) or nil
    return tostring(worker ~= nil and worker.name or roleId)
end

local function estimateTrackedCharge(owner, tracked)
    local assignment = tracked.assignmentSnapshot
    if assignment == nil and owner.resolveWorkerAssignment ~= nil then
        assignment = owner:resolveWorkerAssignment(tracked)
    end
    assignment = assignment or {}

    local elapsedHours = (tonumber(tracked.elapsedMs) or 0) / 3600000
    local payBasis = owner.normalisePayBasis ~= nil and owner:normalisePayBasis(assignment.payBasis) or tostring(assignment.payBasis or "hourly")
    local payRate = tonumber(assignment.payRate or assignment.hourlyRate) or 0
    local labour = payBasis == "daily" and payRate or elapsedHours * payRate
    local callout = payBasis == "daily" and 0 or tonumber(owner.settings ~= nil and owner.settings.workerCalloutFee or 0) or 0
    local minimum = payBasis == "daily" and 0 or tonumber(assignment.minimumCallout or (owner.settings ~= nil and owner.settings.minimumWorkerCharge)) or 0
    local estimate = labour + callout
    if estimate > 0 and minimum > 0 and estimate < minimum then estimate = minimum end

    return round(estimate, 2), round(labour, 2), round(elapsedHours, 3), assignment, payBasis, round(payRate, 2)
end

local function buildActiveJobs(owner)
    local jobs = {}
    for _, tracked in pairs(owner.trackedAIJobs or {}) do
        local estimate, labour, elapsedHours, assignment, payBasis, payRate = estimateTrackedCharge(owner, tracked)
        table.insert(jobs, {
            sequence = tonumber(tracked.sequence) or 0,
            jobType = tostring(tracked.name or "AI job"),
            helperSlot = assignment.helperSlot,
            helperIdentityId = assignment.helperIdentityId,
            helperName = tostring(assignment.helperName or assignment.workerName or "Worker"),
            roleId = tostring(assignment.workerId or assignment.helperRole or "standard"),
            roleName = getRoleName(owner, assignment),
            payBasis = payBasis,
            payRate = payRate,
            elapsedHours = elapsedHours,
            labourEstimate = labour,
            chargeEstimate = estimate,
            farmId = tonumber(assignment.farmId) or assignment.farmId,
            farmIdSource = tostring(assignment.farmIdSource or "unknown"),
            gameDate = assignment.gameDate,
            snapshotSource = tostring(assignment.snapshotSource or "runtime")
        })
    end
    table.sort(jobs, function(a, b) return (a.sequence or 0) < (b.sequence or 0) end)
    return jobs
end

local function buildPendingPayroll(owner)
    local rows = {}
    local clock = owner.getGameClockSnapshot ~= nil and owner:getGameClockSnapshot() or {}
    local payrollHour = tonumber(owner.settings ~= nil and owner.settings.payrollHour or 18) or 18
    for key, daily in pairs(owner.workerDailyLedger or {}) do
        if daily ~= nil and daily.payrollApplied ~= true and (tonumber(daily.jobs) or 0) > 0 then
            local charge, minimumApplied = 0, false
            if owner.calculateDailyPayrollCharge ~= nil then
                charge, minimumApplied = owner:calculateDailyPayrollCharge(daily)
            end
            local due, dueReason = false, "pending"
            if owner.isDailyPayrollRowDue ~= nil then
                due, dueReason = owner:isDailyPayrollRowDue(daily, clock, payrollHour)
            end
            local pendingRoleId = tostring(daily.workerId or daily.helperRole or "standard")
            local pendingWorker = owner.getWorkerRateById ~= nil and owner:getWorkerRateById(daily.profileId, pendingRoleId) or nil
            table.insert(rows, {
                key = tostring(key),
                gameDate = tostring(daily.gameDate or "unknown"),
                helperSlot = daily.helperSlot,
                helperIdentityId = daily.helperIdentityId,
                helperName = tostring(daily.helperName or "Worker"),
                roleId = pendingRoleId,
                roleName = tostring(pendingWorker ~= nil and pendingWorker.name or daily.helperRole or pendingRoleId),
                payBasis = tostring(daily.payBasis or "hourly"),
                payRate = round(daily.payRate or daily.hourlyRate, 2),
                jobs = tonumber(daily.jobs) or 0,
                hours = round(daily.hours, 3),
                labour = round(daily.labour, 2),
                chargeEstimate = round(charge, 2),
                minimumApplied = minimumApplied == true,
                due = due == true,
                dueReason = tostring(dueReason or "pending"),
                farmId = tonumber(daily.farmId) or daily.farmId
            })
        end
    end
    table.sort(rows, function(a, b)
        if a.gameDate == b.gameDate then return a.helperName < b.helperName end
        return a.gameDate < b.gameDate
    end)
    return rows
end

local function buildWorkers(owner, options)
    options = options or {}
    local rows = {}
    local profileId = tostring(owner.settings ~= nil and owner.settings.activePayrollProfile or "default")
    for _, slot in ipairs(owner.getManagedHelperSlots ~= nil and owner:getManagedHelperSlots() or {}) do
        local slotInfo = owner.getHelperProfilesSlotInfo ~= nil and owner:getHelperProfilesSlotInfo(slot) or nil
        local roleId = tostring(owner.settings ~= nil and owner.settings.fallbackRole or "standard")
        local mappingSource = "fallback"
        if owner.getEffectiveHelperProfilesRole ~= nil then
            local resolvedRoleId, _, resolvedSource = owner:getEffectiveHelperProfilesRole(slotInfo, slot, profileId)
            if resolvedRoleId ~= nil then roleId = tostring(resolvedRoleId) end
            if resolvedSource ~= nil then mappingSource = tostring(resolvedSource) end
        end
        local mapping = owner.getHelperProfilesPayrollMapping ~= nil and select(1, owner:getHelperProfilesPayrollMapping(slotInfo, slot)) or nil
        local policy = owner.getEffectiveCompensationPolicy ~= nil and owner:getEffectiveCompensationPolicy(profileId, roleId, mapping) or {}
        local enabled = slotInfo == nil or slotInfo.enabled ~= false
        if options.includeDisabledWorkers ~= false or enabled then
            table.insert(rows, {
                slot = tostring(slot),
                enabled = enabled,
                availabilityKnown = slotInfo ~= nil and slotInfo.availabilityKnown == true,
                rosterState = slotInfo ~= nil and tostring(slotInfo.rosterState or "unknown") or "unknown",
                enabledIndex = slotInfo ~= nil and tonumber(slotInfo.enabledIndex) or nil,
                identityId = slotInfo ~= nil and slotInfo.identityId or ("slot:" .. tostring(slot)),
                displayName = tostring(slotInfo ~= nil and slotInfo.displayName or ("Helper " .. tostring(slot))),
                selected = slotInfo ~= nil and slotInfo.selected == true,
                inUse = slotInfo ~= nil and slotInfo.inUse == true,
                roleId = tostring(roleId or "standard"),
                mappingSource = tostring(mappingSource or "fallback"),
                compensationMode = tostring(mapping ~= nil and mapping.compensationMode or "inherit"),
                payBasis = tostring(policy.payBasis or "hourly"),
                payRate = round(policy.rate or policy.payRate or policy.hourlyRate, 2),
                minimumCallout = round(policy.minimumCallout, 2)
            })
        end
    end
    return rows
end

function HelperPayrollSnapshot.build(owner, options)
    options = options or {}
    local clock = owner.getGameClockSnapshot ~= nil and owner:getGameClockSnapshot() or {}
    local activeJobs = buildActiveJobs(owner)
    local pendingPayroll = buildPendingPayroll(owner)
    local ledgerIndex = owner.ledger ~= nil and owner.ledger.index or nil
    local totals = ledgerIndex ~= nil and ledgerIndex.totals or nil
    local compatibility = copyCompatibility(owner.compatibilityStatus)
    local selectedRoleId = tostring(owner.settings ~= nil and owner.settings.selectedRole or "standard")
    local activeProfileId = tostring(owner.settings ~= nil and owner.settings.activePayrollProfile or "default")
    local selectedRoleWorker = owner.getWorkerRateById ~= nil and owner:getWorkerRateById(activeProfileId, selectedRoleId) or nil
    local selectedRolePolicy = owner.getRoleCompensationPolicy ~= nil and owner:getRoleCompensationPolicy(activeProfileId, selectedRoleId) or {}
    local roster = owner.getManagedHelperRosterSummary ~= nil and owner:getManagedHelperRosterSummary() or {
        supported = false,
        source = "managed-slot fallback",
        total = owner.getManagedHelperSlotCount ~= nil and owner:getManagedHelperSlotCount() or 0,
        enabled = owner.getManagedHelperSlotCount ~= nil and owner:getManagedHelperSlotCount() or 0,
        disabled = 0
    }

    local snapshot = {
        schemaVersion = HelperPayrollSnapshot.SCHEMA_VERSION,
        generatedAt = {
            gameDate = tostring(clock.dateKey or "unknown"),
            monotonicDay = tonumber(clock.monotonicDay),
            dayTimeMs = tonumber(clock.dayTimeMs),
            hour = tonumber(clock.hour)
        },
        runtime = {
            initialized = owner.isInitialized == true,
            payrollEnabled = owner.isPayrollRuntimeEnabled ~= nil and owner:isPayrollRuntimeEnabled() or owner.runtimeBillingBlocked ~= true,
            billingBlocked = owner.runtimeBillingBlocked == true,
            billingBlockReason = owner.runtimeBillingBlockReason,
            authority = "singlePlayerMission",
            multiplayerSupported = false,
            transportReadySchema = true
        },
        compatibility = compatibility,
        roster = {
            availabilitySupported = roster.supported == true,
            source = tostring(roster.source or "managed-slot fallback"),
            totalWorkers = tonumber(roster.total) or 0,
            enabledWorkers = tonumber(roster.enabled) or 0,
            disabledWorkers = tonumber(roster.disabled) or 0
        },
        policy = {
            activePayrollProfile = activeProfileId,
            payrollMode = tostring(owner.settings ~= nil and owner.settings.payrollMode or "roleType"),
            billingMode = tostring(owner.settings ~= nil and owner.settings.billingMode or "onJobFinish"),
            payrollHour = tonumber(owner.settings ~= nil and owner.settings.payrollHour or 18) or 18,
            selectedRole = selectedRoleId,
            selectedRoleName = tostring(selectedRoleWorker ~= nil and selectedRoleWorker.name or selectedRoleId),
            selectedRolePayBasis = tostring(selectedRolePolicy.payBasis or "hourly"),
            selectedRoleRate = round(selectedRolePolicy.rate or selectedRolePolicy.hourlyRate, 2),
            fallbackRole = tostring(owner.settings ~= nil and owner.settings.fallbackRole or "standard"),
            calloutFee = round(owner.settings ~= nil and owner.settings.workerCalloutFee, 2),
            legacyMinimum = round(owner.settings ~= nil and owner.settings.minimumWorkerCharge, 2),
            roundCharges = owner.settings ~= nil and owner.settings.roundWorkerCharges == true
        },
        activeJobs = activeJobs,
        pendingPayroll = pendingPayroll,
        ledger = {
            currentPeriodId = owner.ledger ~= nil and owner.ledger.currentPeriodId or nil,
            totalJobs = tonumber(totals ~= nil and totals.jobs) or 0,
            totalHours = round(totals ~= nil and totals.hours, 3),
            labour = round(totals ~= nil and totals.labour, 2),
            charged = round(totals ~= nil and totals.charged, 2),
            sessionEntries = tonumber(owner.workerLedgerCount) or 0,
            sessionCharged = round(owner.workerLedgerTotal, 2)
        },
        counts = {
            activeJobs = #activeJobs,
            pendingPayroll = #pendingPayroll,
            managedWorkers = tonumber(roster.total) or 0,
            enabledWorkers = tonumber(roster.enabled) or 0,
            disabledWorkers = tonumber(roster.disabled) or 0
        }
    }

    if options.includeWorkers ~= false then
        snapshot.workers = buildWorkers(owner, options)
    end

    return snapshot
end
