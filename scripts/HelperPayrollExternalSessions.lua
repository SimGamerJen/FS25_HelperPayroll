-- FS25_HelperPayroll
-- Generic externally managed worker-session lifecycle.
--
-- Controllers such as HelperProfiles may own a worker outside GIANTS
-- g_currentMission.aiSystem.activeJobs. This module lets those controllers
-- declare a logical work session while HelperPayroll remains the sole owner of
-- assignment snapshots, compensation policy, billing and ledger persistence.

HelperPayrollExternalSessions = HelperPayrollExternalSessions or {
    sessions = {},
    sequence = 0
}

HelperPayrollExternalSessions.API_VERSION = 1

local LOG = "[HelperPayroll/ExternalSession] "

local function log(message, ...)
    print(LOG .. string.format(tostring(message), ...))
end

local function warn(message, ...)
    print(LOG .. "WARN: " .. string.format(tostring(message), ...))
end

local function copyTable(source)
    local result = {}
    for key, value in pairs(source or {}) do
        result[key] = value
    end
    return result
end

local function normaliseSessionId(request)
    local value = request ~= nil and request.sessionId or nil
    if value == nil then return nil end
    value = tostring(value)
    if value == "" then return nil end
    return value
end

local function normaliseSlot(owner, request)
    if owner == nil or request == nil then return nil, nil end
    local candidate = request.helperSlot
    if candidate == nil then candidate = request.helperIndex end
    if owner.normaliseHelperSlot ~= nil then
        local slot, index = owner:normaliseHelperSlot(candidate)
        return slot, index
    end
    return nil, tonumber(request.helperIndex)
end

local function resolveFarmId(owner, request)
    local requested = tonumber(request ~= nil and request.farmId or nil)
    if requested ~= nil then return requested, "external-request" end
    if owner ~= nil and owner.getActiveFarmId ~= nil then
        return owner:getActiveFarmId(), "active-farm-fallback"
    end
    return 1, "fallback"
end

local function buildAssignment(owner, request)
    local _, profileId = owner:getActiveProfile()
    local helperSlot, helperIndex = normaliseSlot(owner, request)
    local payrollMode = tostring(owner.settings ~= nil and owner.settings.payrollMode or "roleType")
    local hpSlotInfo = helperSlot ~= nil and owner.getHelperProfilesSlotInfo ~= nil and owner:getHelperProfilesSlotInfo(helperSlot) or nil
    local payrollMapping = nil
    local mappingSource = "selected-role"
    local helperSlotUsedForPayroll = false

    local workerId = tostring(owner.settings ~= nil and (owner.settings.selectedRole or owner.settings.fallbackRole) or "standard")

    if owner.isHelperSlotPayrollMode ~= nil and owner:isHelperSlotPayrollMode() and helperSlot ~= nil then
        local resolvedRoleId, mapping, resolvedSource = owner:getEffectiveHelperProfilesRole(hpSlotInfo, helperSlot, profileId)
        if resolvedRoleId ~= nil then workerId = tostring(resolvedRoleId) end
        payrollMapping = mapping
        mappingSource = tostring(resolvedSource or "helper-slot")
        helperSlotUsedForPayroll = true
    end

    local worker = owner:getWorkerRateById(profileId, workerId)
    if worker == nil and owner.getSelectedWorkerRate ~= nil then
        worker, profileId = owner:getSelectedWorkerRate()
        if worker ~= nil and worker.id ~= nil then workerId = tostring(worker.id) end
        mappingSource = "selected-role-fallback"
    end
    worker = worker or {id = workerId, name = workerId}

    local compensation = owner:getEffectiveCompensationPolicy(profileId, workerId, payrollMapping) or {
        payBasis = "hourly",
        rate = 0,
        minimumCallout = tonumber(owner.settings ~= nil and owner.settings.minimumWorkerCharge or 0) or 0,
        source = "fallback"
    }

    local clock = owner:getGameClockSnapshot()
    local farmId, farmIdSource = resolveFarmId(owner, request)
    local helperName = hpSlotInfo ~= nil and hpSlotInfo.displayName
        or (request ~= nil and request.helperName)
        or worker.name
        or (helperSlot ~= nil and ("Helper " .. tostring(helperSlot)))
        or "Worker"

    local identityId = hpSlotInfo ~= nil and hpSlotInfo.identityId
        or (request ~= nil and request.helperIdentityId)
        or (helperSlot ~= nil and ("slot:" .. tostring(helperSlot)))
        or nil

    local identitySource = hpSlotInfo ~= nil and tostring(hpSlotInfo.identitySource or hpSlotInfo.source or "HelperProfilesAPI")
        or tostring(request ~= nil and request.helperIdentitySource or "external-session")

    return {
        profileId = profileId,
        payrollMode = payrollMode,
        helperSlot = helperSlot or "unassigned",
        helperIndex = helperIndex,
        helperSlotSource = tostring(request ~= nil and request.helperSlotSource or "external-session"),
        helperSlotUsedForPayroll = helperSlotUsedForPayroll,
        helperName = tostring(helperName),
        helperRole = tostring(worker.name or workerId or "Worker"),
        workerId = tostring(workerId),
        workerName = tostring(worker.name or workerId or "Worker"),
        payBasis = tostring(compensation.payBasis or "hourly"),
        payRate = tonumber(compensation.rate or compensation.payRate or compensation.hourlyRate) or 0,
        minimumCallout = tonumber(compensation.minimumCallout) or 0,
        compensationSource = tostring(compensation.source or "external-session"),
        hourlyRate = tonumber(compensation.rate or compensation.payRate or compensation.hourlyRate) or 0,
        helperIdentityId = identityId,
        helperIdentitySource = identitySource,
        helperMappingSource = mappingSource,
        helperProfilesName = hpSlotInfo ~= nil and hpSlotInfo.displayName or nil,
        helperProfilesSelected = hpSlotInfo ~= nil and hpSlotInfo.selected == true or false,
        gameDate = clock.dateKey,
        workMonotonicDay = clock.monotonicDay,
        workDayTime = clock.dayTimeMs,
        farmId = farmId,
        farmIdSource = farmIdSource,
        snapshotSource = "external-session-start",
        externalSource = tostring(request ~= nil and request.source or "external"),
        externalController = tostring(request ~= nil and request.controller or "external"),
        externalSessionId = normaliseSessionId(request),
        externalLabel = request ~= nil and request.label or nil
    }
end

local function makeResult(session, status)
    local assignment = session ~= nil and session.assignmentSnapshot or {}
    return {
        status = tostring(status or "unknown"),
        sessionId = session ~= nil and session.sessionId or nil,
        sequence = session ~= nil and session.sequence or nil,
        source = session ~= nil and session.source or nil,
        controller = session ~= nil and session.controller or nil,
        jobType = session ~= nil and session.name or nil,
        helperSlot = assignment.helperSlot,
        helperIdentityId = assignment.helperIdentityId,
        helperName = assignment.helperName,
        roleId = assignment.workerId,
        payBasis = assignment.payBasis,
        payRate = assignment.payRate,
        elapsedHours = session ~= nil and ((tonumber(session.elapsedMs) or 0) / 3600000) or 0
    }
end

function HelperPayrollExternalSessions.begin(owner, request)
    if owner == nil or owner.isInitialized ~= true then
        return false, {status = "payroll-not-ready"}
    end
    if owner.isPayrollRuntimeEnabled ~= nil and not owner:isPayrollRuntimeEnabled() then
        return false, {status = "payroll-runtime-disabled"}
    end
    if type(request) ~= "table" then
        return false, {status = "invalid-request"}
    end

    local sessionId = normaliseSessionId(request)
    if sessionId == nil then
        return false, {status = "missing-session-id"}
    end

    local existing = HelperPayrollExternalSessions.sessions[sessionId]
    if existing ~= nil then
        return true, makeResult(existing, "already-active")
    end

    HelperPayrollExternalSessions.sequence = (tonumber(HelperPayrollExternalSessions.sequence) or 0) + 1
    local assignment = buildAssignment(owner, request)
    local session = {
        sessionId = sessionId,
        sequence = 1000000 + HelperPayrollExternalSessions.sequence,
        name = tostring(request.jobType or request.label or "External worker session"),
        source = tostring(request.source or "external"),
        controller = tostring(request.controller or "external"),
        elapsedMs = 0,
        lastSummaryMs = 0,
        billed = false,
        external = true,
        assignmentSnapshot = assignment,
        metadata = {
            vehicleName = request.vehicleName,
            label = request.label
        }
    }
    HelperPayrollExternalSessions.sessions[sessionId] = session

    log(
        "Started: id=%s controller=%s type=%s helperSlot=%s identityId=%s helper=%s role=%s payBasis=%s rate=%.2f farmId=%s",
        tostring(sessionId),
        tostring(session.controller),
        tostring(session.name),
        tostring(assignment.helperSlot),
        tostring(assignment.helperIdentityId or "-"),
        tostring(assignment.helperName),
        tostring(assignment.helperRole),
        tostring(assignment.payBasis),
        tonumber(assignment.payRate) or 0,
        tostring(assignment.farmId or "?")
    )
    return true, makeResult(session, "started")
end

function HelperPayrollExternalSessions.finish(owner, sessionId, reason)
    sessionId = sessionId ~= nil and tostring(sessionId) or nil
    if sessionId == nil or sessionId == "" then
        return false, {status = "missing-session-id"}
    end

    local session = HelperPayrollExternalSessions.sessions[sessionId]
    if session == nil then
        return false, {status = "not-active", sessionId = sessionId}
    end

    local elapsedHours = (tonumber(session.elapsedMs) or 0) / 3600000
    local billingHandled = false
    local billingError = nil

    if owner ~= nil and owner.applyWorkerCharge ~= nil and not session.billed then
        -- Mark first, matching the normal AI-job path, so a downstream ledger or
        -- reporting failure cannot cause the same completed session to be billed twice.
        session.billed = true
        local ok, result = pcall(function()
            return owner:applyWorkerCharge(session)
        end)
        if ok then
            billingHandled = result == true
        else
            billingHandled = true
            billingError = tostring(result)
            warn("Billing raised an error after external session finish; session will not be retried: id=%s error=%s", tostring(sessionId), billingError)
        end
    end

    HelperPayrollExternalSessions.sessions[sessionId] = nil

    log(
        "Finished: id=%s controller=%s type=%s helperSlot=%s helper=%s elapsedHours=%.3f reason=%s billingHandled=%s billingMode=%s",
        tostring(sessionId),
        tostring(session.controller),
        tostring(session.name),
        tostring(session.assignmentSnapshot ~= nil and session.assignmentSnapshot.helperSlot or "unassigned"),
        tostring(session.assignmentSnapshot ~= nil and session.assignmentSnapshot.helperName or "Worker"),
        elapsedHours,
        tostring(reason or "external-finish"),
        tostring(billingHandled),
        tostring(owner ~= nil and owner.settings ~= nil and owner.settings.billingMode or "unknown")
    )

    local result = makeResult(session, billingError ~= nil and "finished-with-billing-error" or "finished")
    result.reason = tostring(reason or "external-finish")
    result.billingHandled = billingHandled
    result.billingError = billingError
    return true, result
end

function HelperPayrollExternalSessions.getActive(owner)
    local rows = {}
    for _, session in pairs(HelperPayrollExternalSessions.sessions or {}) do
        table.insert(rows, makeResult(session, "active"))
    end
    table.sort(rows, function(a, b)
        return (tonumber(a.sequence) or 0) < (tonumber(b.sequence) or 0)
    end)
    return rows
end

function HelperPayrollExternalSessions.getTrackedSessions()
    local rows = {}
    for _, session in pairs(HelperPayrollExternalSessions.sessions or {}) do
        table.insert(rows, session)
    end
    return rows
end

function HelperPayrollExternalSessions:update(dt)
    local delta = tonumber(dt) or 0
    if delta <= 0 then return end

    for _, session in pairs(self.sessions or {}) do
        session.elapsedMs = (tonumber(session.elapsedMs) or 0) + delta
        if session.elapsedMs - (tonumber(session.lastSummaryMs) or 0) >= 60000 then
            session.lastSummaryMs = session.elapsedMs
            local assignment = session.assignmentSnapshot or {}
            log(
                "Active: id=%s controller=%s helperSlot=%s helper=%s elapsedMinutes=%.1f",
                tostring(session.sessionId),
                tostring(session.controller),
                tostring(assignment.helperSlot or "unassigned"),
                tostring(assignment.helperName or "Worker"),
                session.elapsedMs / 60000
            )
        end
    end
end

function HelperPayrollExternalSessions:loadMap()
    self.sessions = {}
    self.sequence = 0
end

function HelperPayrollExternalSessions:deleteMap()
    if next(self.sessions or {}) ~= nil then
        warn("Mission ended with active external worker sessions; clearing runtime sessions without settlement during teardown")
    end
    self.sessions = {}
end

addModEventListener(HelperPayrollExternalSessions)
