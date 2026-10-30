-- FS25_HelperPayroll
-- Work-time accounting shared by GIANTS AI jobs and externally managed worker sessions.
--
-- Billing can follow either the in-game clock (default) or real frame time
-- (legacy compatibility). Game-clock mode validates observed environment-clock
-- movement against the mission's effective time scale so normal fast-forward
-- counts while discontinuous jumps such as sleep/period skips only re-anchor.
-- Billable acceleration can be capped independently from the actual game speed.

HelperPayrollWorkClock = HelperPayrollWorkClock or {}

HelperPayrollWorkClock.DAY_MS = 24 * 60 * 60 * 1000
HelperPayrollWorkClock.MIN_VALID_STEP_MS = 15000
HelperPayrollWorkClock.EXPECTED_STEP_FACTOR = 4
HelperPayrollWorkClock.EXPECTED_STEP_TOLERANCE_MS = 5000

local function normaliseBasis(value)
    return string.lower(tostring(value or "gameClock")) == "realtime" and "realTime" or "gameClock"
end

local function copyAnchor(clock)
    if type(clock) ~= "table" then return nil end
    if tonumber(clock.monotonicDay) == nil or tonumber(clock.dayTimeMs) == nil then return nil end
    return {
        monotonicDay = tonumber(clock.monotonicDay),
        dayTimeMs = tonumber(clock.dayTimeMs),
        dateKey = tostring(clock.dateKey or "unknown")
    }
end

local function getEffectiveTimeScale()
    if g_currentMission ~= nil and g_currentMission.getEffectiveTimeScale ~= nil then
        local ok, value = pcall(g_currentMission.getEffectiveTimeScale, g_currentMission)
        if ok and tonumber(value) ~= nil then
            return math.max(0, tonumber(value))
        end
    end

    if g_currentMission ~= nil and tonumber(g_currentMission.timeScale) ~= nil then
        return math.max(0, tonumber(g_currentMission.timeScale))
    end

    return 1
end

local function getClock(owner)
    if owner ~= nil and owner.getGameClockSnapshot ~= nil then
        local ok, clock = pcall(owner.getGameClockSnapshot, owner)
        if ok and type(clock) == "table" then return clock end
    end
    return nil
end

local function getSegment(tracked, dateKey, monotonicDay)
    tracked.workSegments = tracked.workSegments or {}
    for _, segment in ipairs(tracked.workSegments) do
        if tostring(segment.gameDate) == tostring(dateKey)
            and tonumber(segment.monotonicDay) == tonumber(monotonicDay) then
            return segment
        end
    end

    local segment = {
        gameDate = tostring(dateKey or "unknown"),
        monotonicDay = tonumber(monotonicDay),
        elapsedMs = 0
    }
    table.insert(tracked.workSegments, segment)
    return segment
end

local function addSegment(tracked, dateKey, monotonicDay, delta)
    delta = tonumber(delta) or 0
    if delta <= 0 then return end
    local segment = getSegment(tracked, dateKey, monotonicDay)
    segment.elapsedMs = (tonumber(segment.elapsedMs) or 0) + delta
end

function HelperPayrollWorkClock.normaliseTimeBasis(value)
    return normaliseBasis(value)
end

function HelperPayrollWorkClock.getCurrentScales(owner)
    local effectiveScale = getEffectiveTimeScale()
    local configuredCap = tonumber(owner ~= nil and owner.settings ~= nil and owner.settings.maxPayrollTimeScale or 10) or 10
    configuredCap = math.max(0, configuredCap)
    local billableScale = configuredCap > 0 and math.min(effectiveScale, configuredCap) or effectiveScale
    return effectiveScale, billableScale, configuredCap
end

function HelperPayrollWorkClock.initialise(owner, tracked)
    if tracked == nil then return end

    tracked.elapsedMs = tonumber(tracked.elapsedMs) or 0
    tracked.realElapsedMs = tonumber(tracked.realElapsedMs) or 0
    tracked.gameElapsedMs = tonumber(tracked.gameElapsedMs) or 0
    tracked.billableGameElapsedMs = tonumber(tracked.billableGameElapsedMs) or 0
    tracked.clockDiscontinuities = tonumber(tracked.clockDiscontinuities) or 0
    tracked.expectedGameDeltaMs = tonumber(tracked.expectedGameDeltaMs) or 0
    tracked.expectedBillableDeltaMs = tonumber(tracked.expectedBillableDeltaMs) or 0
    tracked.workSegments = tracked.workSegments or {}

    local clock = getClock(owner)
    tracked.workClockAnchor = copyAnchor(clock)
    tracked.lastEffectiveTimeScale = getEffectiveTimeScale()
end

function HelperPayrollWorkClock.reanchor(owner, tracked)
    if tracked == nil then return end
    tracked.workClockAnchor = copyAnchor(getClock(owner))
    tracked.lastEffectiveTimeScale = getEffectiveTimeScale()
    tracked.expectedGameDeltaMs = 0
    tracked.expectedBillableDeltaMs = 0
end

function HelperPayrollWorkClock.accrue(owner, tracked, dt)
    if tracked == nil then return 0, "missing-tracker" end

    local realDelta = math.max(0, tonumber(dt) or 0)
    tracked.realElapsedMs = (tonumber(tracked.realElapsedMs) or 0) + realDelta

    local basis = normaliseBasis(owner ~= nil and owner.settings ~= nil and owner.settings.workerTimeBasis or "gameClock")
    tracked.timeBasis = basis

    if basis == "realTime" then
        tracked.elapsedMs = (tonumber(tracked.elapsedMs) or 0) + realDelta
        return realDelta, "realTime"
    end

    local current = copyAnchor(getClock(owner))
    if current == nil then
        tracked.workClockAnchor = nil
        return 0, "clock-unavailable"
    end

    local previous = tracked.workClockAnchor
    tracked.workClockAnchor = current
    local effectiveScale, billableScale, configuredCap = HelperPayrollWorkClock.getCurrentScales(owner)

    tracked.lastEffectiveTimeScale = effectiveScale
    tracked.lastBillableTimeScale = billableScale
    tracked.maxPayrollTimeScale = configuredCap
    tracked.expectedGameDeltaMs = (tonumber(tracked.expectedGameDeltaMs) or 0) + realDelta * effectiveScale
    tracked.expectedBillableDeltaMs = (tonumber(tracked.expectedBillableDeltaMs) or 0) + realDelta * billableScale

    if previous == nil then
        tracked.expectedGameDeltaMs = 0
        tracked.expectedBillableDeltaMs = 0
        return 0, "anchored"
    end

    local dayDiff = current.monotonicDay - previous.monotonicDay
    if dayDiff < 0 or dayDiff > 1 then
        tracked.clockDiscontinuities = (tonumber(tracked.clockDiscontinuities) or 0) + 1
        tracked.expectedGameDeltaMs = 0
        tracked.expectedBillableDeltaMs = 0
        return 0, "day-discontinuity"
    end

    local actualDelta = dayDiff * HelperPayrollWorkClock.DAY_MS
        + current.dayTimeMs - previous.dayTimeMs
    if actualDelta < 0 then
        tracked.clockDiscontinuities = (tonumber(tracked.clockDiscontinuities) or 0) + 1
        tracked.expectedGameDeltaMs = 0
        tracked.expectedBillableDeltaMs = 0
        return 0, "clock-rollback"
    end

    local expectedDelta = tonumber(tracked.expectedGameDeltaMs) or 0
    local maximumExpected = math.max(
        HelperPayrollWorkClock.MIN_VALID_STEP_MS,
        expectedDelta * HelperPayrollWorkClock.EXPECTED_STEP_FACTOR
            + HelperPayrollWorkClock.EXPECTED_STEP_TOLERANCE_MS
    )

    if actualDelta > maximumExpected then
        tracked.clockDiscontinuities = (tonumber(tracked.clockDiscontinuities) or 0) + 1
        tracked.expectedGameDeltaMs = 0
        tracked.expectedBillableDeltaMs = 0
        return 0, "clock-jump"
    end

    if actualDelta <= 0 then
        if effectiveScale <= 0 then
            tracked.expectedGameDeltaMs = 0
            tracked.expectedBillableDeltaMs = 0
            return 0, "paused"
        end
        return 0, "clock-wait"
    end

    local expectedGameDelta = tonumber(tracked.expectedGameDeltaMs) or 0
    local expectedBillableDelta = tonumber(tracked.expectedBillableDeltaMs) or 0
    local billableRatio = expectedGameDelta > 0 and math.min(1, expectedBillableDelta / expectedGameDelta) or 1
    local billableDelta = actualDelta * billableRatio

    if dayDiff == 0 then
        addSegment(tracked, previous.dateKey, previous.monotonicDay, billableDelta)
    else
        local beforeMidnight = math.max(0, HelperPayrollWorkClock.DAY_MS - previous.dayTimeMs)
        local afterMidnight = math.max(0, current.dayTimeMs)
        local beforeRatio = actualDelta > 0 and beforeMidnight / actualDelta or 0
        local afterRatio = actualDelta > 0 and afterMidnight / actualDelta or 0
        addSegment(tracked, previous.dateKey, previous.monotonicDay, billableDelta * beforeRatio)
        addSegment(tracked, current.dateKey, current.monotonicDay, billableDelta * afterRatio)
    end

    tracked.gameElapsedMs = (tonumber(tracked.gameElapsedMs) or 0) + actualDelta
    tracked.billableGameElapsedMs = (tonumber(tracked.billableGameElapsedMs) or 0) + billableDelta
    tracked.elapsedMs = tracked.billableGameElapsedMs
    tracked.expectedGameDeltaMs = 0
    tracked.expectedBillableDeltaMs = 0
    return billableDelta, "gameClock"
end

function HelperPayrollWorkClock.getSegments(tracked)
    local rows = {}
    for _, segment in ipairs(tracked ~= nil and tracked.workSegments or {}) do
        if (tonumber(segment.elapsedMs) or 0) > 0 then
            table.insert(rows, {
                gameDate = tostring(segment.gameDate or "unknown"),
                monotonicDay = tonumber(segment.monotonicDay),
                elapsedMs = tonumber(segment.elapsedMs) or 0
            })
        end
    end
    table.sort(rows, function(a, b)
        if tonumber(a.monotonicDay) ~= tonumber(b.monotonicDay) then
            return (tonumber(a.monotonicDay) or 0) < (tonumber(b.monotonicDay) or 0)
        end
        return tostring(a.gameDate) < tostring(b.gameDate)
    end)
    return rows
end

function HelperPayrollWorkClock.getDiagnostics(tracked)
    return {
        timeBasis = tostring(tracked ~= nil and tracked.timeBasis or "unknown"),
        elapsedMs = tonumber(tracked ~= nil and tracked.elapsedMs or 0) or 0,
        realElapsedMs = tonumber(tracked ~= nil and tracked.realElapsedMs or 0) or 0,
        gameElapsedMs = tonumber(tracked ~= nil and tracked.gameElapsedMs or 0) or 0,
        billableGameElapsedMs = tonumber(tracked ~= nil and tracked.billableGameElapsedMs or 0) or 0,
        discontinuities = tonumber(tracked ~= nil and tracked.clockDiscontinuities or 0) or 0,
        effectiveTimeScale = tonumber(tracked ~= nil and tracked.lastEffectiveTimeScale or 0) or 0,
        billableTimeScale = tonumber(tracked ~= nil and tracked.lastBillableTimeScale or 0) or 0,
        maxPayrollTimeScale = tonumber(tracked ~= nil and tracked.maxPayrollTimeScale or 0) or 0
    }
end
