-- Helper Payroll
-- Version: 0.1.3.3-alpha
-- Purpose:
--   1. Suppress vanilla AI worker payments.
--   2. Track active AI jobs.
--   3. Apply configurable custom worker wages when AI jobs finish.
--   4. Prepare helper-slot and daily payroll structures for future HelperProfiles integration.

print("[HelperPayroll] Lua file loaded")

HelperPayroll = {}
HelperPayroll.MOD_NAME = g_currentModName or "FS25_HelperPayroll"
HelperPayroll.MOD_DIRECTORY = g_currentModDirectory or ""
HelperPayroll.CONFIG_FILE = HelperPayroll.MOD_DIRECTORY .. "config/defaultPayrollConfig.xml"

HelperPayroll.settings = {
    debug = true,
    suppressVanillaAIWorkerCosts = true,
    enableCustomWorkerCosts = true,
    defaultProfile = "uk_tenant",
    defaultWorker = "skilled",
    defaultHelperSlot = "",
    chargeCustomWorkerCosts = true,
    billingMode = "onJobFinish",
    payrollHour = 18,
    minimumWorkerCharge = 0,
    workerCalloutFee = 0,
    roundWorkerCharges = true,
    logLevel = "debug",
    debugAllMoneyTransactions = false
}

HelperPayroll.profiles = {}
HelperPayroll.workerRates = {}
HelperPayroll.helperSlots = {}
HelperPayroll.helperSlotCounts = {}
HelperPayroll.originalFarmAddMoney = nil
HelperPayroll.aiWorkerHooksInstalled = false
HelperPayroll.aiPriceDebugCount = 0
HelperPayroll.aiPriceDebugLimit = 10
HelperPayroll.aiPriceStatsByType = {}
HelperPayroll.trackedAIJobs = {}
HelperPayroll.trackedAIJobCount = 0
HelperPayroll.isInitialized = false
HelperPayroll.moneyTypeNames = {}
HelperPayroll.moneyDebugCount = 0
HelperPayroll.moneyDebugLimit = 80
HelperPayroll.workerLedger = {}
HelperPayroll.workerLedgerCount = 0
HelperPayroll.workerLedgerTotal = 0
HelperPayroll.workerDailyLedger = {}
HelperPayroll.payrollCheckAccumulatorMs = 0
HelperPayroll.payrollCheckIntervalMs = 30000
HelperPayroll.warnedMissingPayrollClock = false

local function rcLog(message, ...)
    if HelperPayroll.settings ~= nil and HelperPayroll.settings.logLevel == "quiet" then
        return
    end

    if HelperPayroll.settings == nil or HelperPayroll.settings.debug then
        print(string.format("[HelperPayroll] " .. tostring(message), ...))
    end
end

local function rcWarn(message, ...)
    print(string.format("[HelperPayroll][WARN] " .. tostring(message), ...))
end

local function getXmlBoolOrDefault(xmlFile, key, default)
    local value = getXMLBool(xmlFile, key)
    if value == nil then
        return default
    end
    return value
end

local function getXmlStringOrDefault(xmlFile, key, default)
    local value = getXMLString(xmlFile, key)
    if value == nil or value == "" then
        return default
    end
    return value
end

local function getXmlFloatOrDefault(xmlFile, key, default)
    local value = getXMLFloat(xmlFile, key)
    if value == nil then
        return default
    end
    return value
end

function HelperPayroll:loadConfig()
    local xmlFile = loadXMLFile("helperPayrollConfig", self.CONFIG_FILE)
    if xmlFile == nil or xmlFile == 0 then
        rcWarn("Could not load config: %s", tostring(self.CONFIG_FILE))
        return
    end

    self.settings.debug = getXmlBoolOrDefault(xmlFile, "helperPayroll.settings.debug", self.settings.debug)
    self.settings.suppressVanillaAIWorkerCosts = getXmlBoolOrDefault(xmlFile, "helperPayroll.settings.suppressVanillaAIWorkerCosts", self.settings.suppressVanillaAIWorkerCosts)
    self.settings.enableCustomWorkerCosts = getXmlBoolOrDefault(xmlFile, "helperPayroll.settings.enableCustomWorkerCosts", self.settings.enableCustomWorkerCosts)
    self.settings.defaultProfile = getXmlStringOrDefault(xmlFile, "helperPayroll.settings.defaultProfile", self.settings.defaultProfile)
    self.settings.defaultWorker = getXmlStringOrDefault(xmlFile, "helperPayroll.settings.defaultWorker", self.settings.defaultWorker)
    self.settings.defaultHelperSlot = getXmlStringOrDefault(xmlFile, "helperPayroll.settings.defaultHelperSlot", self.settings.defaultHelperSlot)
    self.settings.chargeCustomWorkerCosts = getXmlBoolOrDefault(xmlFile, "helperPayroll.settings.chargeCustomWorkerCosts", self.settings.chargeCustomWorkerCosts)
    self.settings.billingMode = getXmlStringOrDefault(xmlFile, "helperPayroll.settings.billingMode", self.settings.billingMode)
    self.settings.payrollHour = getXmlFloatOrDefault(xmlFile, "helperPayroll.settings.payrollHour", self.settings.payrollHour)
    self.settings.minimumWorkerCharge = getXmlFloatOrDefault(xmlFile, "helperPayroll.settings.minimumWorkerCharge", self.settings.minimumWorkerCharge)
    self.settings.workerCalloutFee = getXmlFloatOrDefault(xmlFile, "helperPayroll.settings.workerCalloutFee", self.settings.workerCalloutFee)
    self.settings.roundWorkerCharges = getXmlBoolOrDefault(xmlFile, "helperPayroll.settings.roundWorkerCharges", self.settings.roundWorkerCharges)
    self.settings.logLevel = getXmlStringOrDefault(xmlFile, "helperPayroll.settings.logLevel", self.settings.logLevel)
    self.settings.debugAllMoneyTransactions = getXmlBoolOrDefault(xmlFile, "helperPayroll.settings.debugAllMoneyTransactions", self.settings.debugAllMoneyTransactions)

    self:loadProfiles(xmlFile)
    self:loadWorkerRates(xmlFile)
    self:loadHelperSlots(xmlFile)

    delete(xmlFile)
    rcLog("Loaded config. Active profile: %s", tostring(self.settings.defaultProfile))
    rcLog("Worker billing settings: enabled=%s billingMode=%s payrollHour=%s defaultWorker=%s defaultHelperSlot=%s minimum=%.2f callout=%.2f round=%s logLevel=%s", tostring(self.settings.chargeCustomWorkerCosts), tostring(self.settings.billingMode), tostring(self.settings.payrollHour), tostring(self.settings.defaultWorker), tostring(self.settings.defaultHelperSlot ~= "" and self.settings.defaultHelperSlot or "none"), tonumber(self.settings.minimumWorkerCharge) or 0, tonumber(self.settings.workerCalloutFee) or 0, tostring(self.settings.roundWorkerCharges), tostring(self.settings.logLevel))
    self:logHelperSlotConfig()
end

function HelperPayroll:loadProfiles(xmlFile)
    local i = 0
    while true do
        local key = string.format("helperPayroll.profiles.profile(%d)", i)
        if not hasXMLProperty(xmlFile, key) then break end

        local id = getXMLString(xmlFile, key .. "#id")
        if id ~= nil then
            self.profiles[id] = {
                name = getXmlStringOrDefault(xmlFile, key .. "#name", id),
                currency = getXmlStringOrDefault(xmlFile, key .. "#currency", "GBP"),
                areaUnit = getXmlStringOrDefault(xmlFile, key .. "#areaUnit", "hectare"),
                distanceUnit = getXmlStringOrDefault(xmlFile, key .. "#distanceUnit", "km"),
                economyMultiplier = getXmlFloatOrDefault(xmlFile, key .. "#economyMultiplier", 1.0)
            }
        end
        i = i + 1
    end
end

function HelperPayroll:loadWorkerRates(xmlFile)
    local i = 0
    while true do
        local groupKey = string.format("helperPayroll.workerRates(%d)", i)
        if not hasXMLProperty(xmlFile, groupKey) then break end

        local profile = getXmlStringOrDefault(xmlFile, groupKey .. "#profile", self.settings.defaultProfile)
        self.workerRates[profile] = self.workerRates[profile] or {}

        local j = 0
        while true do
            local workerKey = string.format("%s.worker(%d)", groupKey, j)
            if not hasXMLProperty(xmlFile, workerKey) then break end

            local id = getXMLString(xmlFile, workerKey .. "#id")
            if id ~= nil then
                self.workerRates[profile][id] = {
                    id = id,
                    name = getXmlStringOrDefault(xmlFile, workerKey .. "#name", id),
                    hourlyRate = getXmlFloatOrDefault(xmlFile, workerKey .. "#hourlyRate", 0)
                }
            end
            j = j + 1
        end
        i = i + 1
    end
end


function HelperPayroll:loadHelperSlots(xmlFile)
    self.helperSlots = self.helperSlots or {}
    self.helperSlotCounts = {}

    local i = 0
    while true do
        local groupKey = string.format("helperPayroll.helperSlots(%d)", i)
        if not hasXMLProperty(xmlFile, groupKey) then break end

        local profile = getXmlStringOrDefault(xmlFile, groupKey .. "#profile", self.settings.defaultProfile)
        self.helperSlots[profile] = self.helperSlots[profile] or {}

        local j = 0
        while true do
            local helperKey = string.format("%s.helper(%d)", groupKey, j)
            if not hasXMLProperty(xmlFile, helperKey) then break end

            local slot = getXMLString(xmlFile, helperKey .. "#slot")
            if slot ~= nil and slot ~= "" then
                self.helperSlots[profile][slot] = {
                    slot = slot,
                    name = getXmlStringOrDefault(xmlFile, helperKey .. "#name", slot),
                    role = getXmlStringOrDefault(xmlFile, helperKey .. "#role", "Worker"),
                    workerRate = getXmlStringOrDefault(xmlFile, helperKey .. "#workerRate", self.settings.defaultWorker)
                }
                self.helperSlotCounts[profile] = (self.helperSlotCounts[profile] or 0) + 1
            end
            j = j + 1
        end
        i = i + 1
    end
end

function HelperPayroll:logHelperSlotConfig()
    local profileId = self.settings.defaultProfile or "default"
    local slotsForProfile = self.helperSlots ~= nil and self.helperSlots[profileId] or nil
    local slotCount = self.helperSlotCounts ~= nil and self.helperSlotCounts[profileId] or 0

    rcLog("Helper slot config: profile=%s slotsLoaded=%d defaultHelperSlot=%s", tostring(profileId), tonumber(slotCount) or 0, tostring(self.settings.defaultHelperSlot ~= "" and self.settings.defaultHelperSlot or "none"))

    if slotsForProfile ~= nil then
        for slot, helper in pairs(slotsForProfile) do
            rcLog("Helper slot loaded: profile=%s slot=%s name=%s role=%s workerRate=%s", tostring(profileId), tostring(slot), tostring(helper.name), tostring(helper.role), tostring(helper.workerRate))
        end
    end

    if self.settings.defaultHelperSlot ~= nil and self.settings.defaultHelperSlot ~= "" then
        if slotsForProfile == nil or slotsForProfile[self.settings.defaultHelperSlot] == nil then
            rcWarn("defaultHelperSlot '%s' is set but no matching helper slot exists for profile '%s'; jobs will fall back to defaultWorker '%s'", tostring(self.settings.defaultHelperSlot), tostring(profileId), tostring(self.settings.defaultWorker))
        else
            local helper = slotsForProfile[self.settings.defaultHelperSlot]
            rcLog("Default helper slot resolved: slot=%s name=%s role=%s workerRate=%s", tostring(self.settings.defaultHelperSlot), tostring(helper.name), tostring(helper.role), tostring(helper.workerRate))
        end
    end
end

function HelperPayroll:getActiveProfile()
    return self.profiles[self.settings.defaultProfile], self.settings.defaultProfile
end



function HelperPayroll:getDefaultWorkerRate()
    local _, profileId = self:getActiveProfile()
    local workerId = self.settings.defaultWorker or "skilled"
    local ratesForProfile = self.workerRates ~= nil and self.workerRates[profileId] or nil
    local worker = ratesForProfile ~= nil and ratesForProfile[workerId] or nil

    if worker == nil and ratesForProfile ~= nil then
        worker = ratesForProfile.skilled or ratesForProfile.casual or ratesForProfile.owner
        if worker ~= nil then
            rcWarn("Default worker '%s' not found for profile '%s'; using '%s'", tostring(workerId), tostring(profileId), tostring(worker.name))
            workerId = worker.id or workerId
        end
    end

    if worker == nil then
        rcWarn("No worker rate found for profile '%s'; using zero-cost owner labour", tostring(profileId))
        return {
            id = "owner",
            name = "Owner Labour",
            hourlyRate = 0
        }, profileId
    end

    worker.id = worker.id or workerId
    return worker, profileId
end

function HelperPayroll:roundCurrency(value)
    if not self.settings.roundWorkerCharges then
        return value
    end

    return math.floor(((tonumber(value) or 0) * 100) + 0.5) / 100
end


function HelperPayroll:getWorkerRateById(profileId, workerId)
    local ratesForProfile = self.workerRates ~= nil and self.workerRates[profileId] or nil
    if ratesForProfile == nil then
        return nil
    end

    return ratesForProfile[workerId]
end

function HelperPayroll:detectHelperSlotForJob(job, tracked)
    -- Reserved for future HelperProfiles integration. For now, use a config fallback only.
    -- HelperProfiles visibly selects slots such as A/B/C, but we still need a stable public field/API to read.
    if tracked ~= nil and tracked.helperSlot ~= nil and tracked.helperSlot ~= "" then
        return tracked.helperSlot, "tracked"
    end

    if self.settings.defaultHelperSlot ~= nil and self.settings.defaultHelperSlot ~= "" then
        return self.settings.defaultHelperSlot, "config"
    end

    return nil, "unassigned"
end

function HelperPayroll:resolveWorkerAssignment(tracked)
    local _, profileId = self:getActiveProfile()
    local helperSlot, helperSlotSource = self:detectHelperSlotForJob(tracked ~= nil and tracked.job or nil, tracked)
    local slotConfig = nil

    if helperSlot ~= nil and self.helperSlots ~= nil and self.helperSlots[profileId] ~= nil then
        slotConfig = self.helperSlots[profileId][helperSlot]
    end

    local workerId = self.settings.defaultWorker or "skilled"
    local helperName = nil
    local helperRole = nil

    if slotConfig ~= nil then
        workerId = slotConfig.workerRate or workerId
        helperName = slotConfig.name
        helperRole = slotConfig.role
    end

    local worker = self:getWorkerRateById(profileId, workerId)

    if worker == nil then
        worker, profileId = self:getDefaultWorkerRate()
        workerId = worker.id or workerId
    end

    helperName = helperName or worker.name or workerId or "Worker"
    helperRole = helperRole or worker.name or "Worker"

    return {
        profileId = profileId,
        helperSlot = helperSlot or "unassigned",
        helperSlotSource = helperSlotSource or "unassigned",
        helperName = helperName,
        helperRole = helperRole,
        workerId = workerId,
        workerName = worker.name or workerId or "Worker",
        hourlyRate = tonumber(worker.hourlyRate) or 0
    }
end

function HelperPayroll:getGameDateKey()
    if g_currentMission ~= nil and g_currentMission.environment ~= nil then
        local env = g_currentMission.environment
        local day = env.currentDay or env.day or env.currentMonotonicDay
        local month = env.currentPeriod or env.currentMonth or env.month
        local year = env.currentYear or env.year

        if day ~= nil or month ~= nil or year ~= nil then
            return string.format("Y%s-M%02d-D%02d", tostring(year or "?"), tonumber(month) or 0, tonumber(day) or 0)
        end
    end

    return "unknown"
end


function HelperPayroll:getGameHour()
    if g_currentMission ~= nil and g_currentMission.environment ~= nil then
        local env = g_currentMission.environment

        if env.currentHour ~= nil then
            return tonumber(env.currentHour)
        end

        if env.hour ~= nil then
            return tonumber(env.hour)
        end

        local dayTime = env.dayTime or env.currentDayTime
        if dayTime ~= nil then
            return math.floor((tonumber(dayTime) or 0) / 3600000)
        end
    end

    return nil
end

function HelperPayroll:isDailyPayrollMode()
    return string.lower(tostring(self.settings.billingMode or "")) == "dailypayroll"
end

function HelperPayroll:isOnJobFinishMode()
    local mode = string.lower(tostring(self.settings.billingMode or "onJobFinish"))
    return mode == "onjobfinish" or mode == "jobfinish" or mode == "immediate"
end

function HelperPayroll:getActiveFarmId()
    local farmId = nil
    if g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
        farmId = g_currentMission:getFarmId()
    end

    if farmId == nil and g_currentMission ~= nil and g_currentMission.player ~= nil and g_currentMission.player.farmId ~= nil then
        farmId = g_currentMission.player.farmId
    end

    if farmId == nil then
        farmId = 1
        rcWarn("Could not resolve active farmId for worker charge; falling back to farmId=1")
    end

    return farmId
end

function HelperPayroll:calculateWorkerCharge(tracked)
    local assignment = self:resolveWorkerAssignment(tracked)
    local elapsedHours = (tracked ~= nil and tracked.elapsedMs or 0) / 3600000
    local hourlyRate = tonumber(assignment.hourlyRate) or 0
    local labourCharge = elapsedHours * hourlyRate
    local calloutFee = tonumber(self.settings.workerCalloutFee) or 0
    local minimumCharge = tonumber(self.settings.minimumWorkerCharge) or 0
    local subtotal = labourCharge + calloutFee
    local appliedMinimum = false
    local charge = subtotal

    if charge > 0 and minimumCharge > 0 and charge < minimumCharge then
        charge = minimumCharge
        appliedMinimum = true
    end

    charge = self:roundCurrency(charge)

    assignment.elapsedHours = elapsedHours
    assignment.labourCharge = self:roundCurrency(labourCharge)
    assignment.calloutFee = self:roundCurrency(calloutFee)
    assignment.minimumCharge = self:roundCurrency(minimumCharge)
    assignment.appliedMinimum = appliedMinimum

    return charge, assignment
end


function HelperPayroll:updateDailyLedger(entry)
    if entry == nil then
        return nil
    end

    self.workerDailyLedger = self.workerDailyLedger or {}
    local key = string.format("%s|%s|%s|%s|farm%s", tostring(entry.gameDate or "unknown"), tostring(entry.profileId or "default"), tostring(entry.helperSlot or "unassigned"), tostring(entry.helperName or entry.workerName or "Worker"), tostring(entry.farmId or "unknown"))
    local daily = self.workerDailyLedger[key]

    if daily == nil then
        daily = {
            key = key,
            gameDate = entry.gameDate,
            profileId = entry.profileId,
            helperSlot = entry.helperSlot,
            helperName = entry.helperName,
            helperRole = entry.helperRole,
            workerId = entry.workerId,
            hourlyRate = entry.hourlyRate,
            farmId = entry.farmId,
            jobs = 0,
            hours = 0,
            charged = 0,
            labour = 0,
            payrollApplied = false,
            payrollCharge = 0
        }
        self.workerDailyLedger[key] = daily
    end

    daily.jobs = (daily.jobs or 0) + 1
    daily.hours = (daily.hours or 0) + (tonumber(entry.elapsedHours) or 0)
    daily.charged = (daily.charged or 0) + (tonumber(entry.charge) or 0)
    daily.labour = (daily.labour or 0) + (tonumber(entry.labourCharge) or 0)

    rcLog(
        "Worker daily ledger: gameDate=%s helperSlot=%s helper=%s role=%s jobs=%d hours=%.3f labour=%.2f charged=%.2f payrollApplied=%s",
        tostring(daily.gameDate),
        tostring(daily.helperSlot),
        tostring(daily.helperName),
        tostring(daily.helperRole),
        tonumber(daily.jobs) or 0,
        tonumber(daily.hours) or 0,
        tonumber(daily.labour) or 0,
        tonumber(daily.charged) or 0,
        tostring(daily.payrollApplied)
    )

    return daily
end

function HelperPayroll:calculateDailyPayrollCharge(daily)
    if daily == nil then
        return 0, false
    end

    local labour = tonumber(daily.labour) or 0
    local calloutFee = tonumber(self.settings.workerCalloutFee) or 0
    local minimumCharge = tonumber(self.settings.minimumWorkerCharge) or 0
    local subtotal = labour

    if daily.jobs ~= nil and daily.jobs > 0 then
        subtotal = subtotal + calloutFee
    end

    local appliedMinimum = false
    local charge = subtotal

    if charge > 0 and minimumCharge > 0 and charge < minimumCharge then
        charge = minimumCharge
        appliedMinimum = true
    end

    return self:roundCurrency(charge), appliedMinimum
end

function HelperPayroll:applyMoneyCharge(amount, farmId, context)
    if g_currentMission == nil or g_currentMission.addMoney == nil then
        rcWarn("Could not apply %s; g_currentMission.addMoney is not available", tostring(context or "worker charge"))
        return false
    end

    local moneyType = MoneyType ~= nil and MoneyType.AI or nil
    local ok, result = pcall(function()
        g_currentMission:addMoney(-amount, farmId, moneyType, true)
    end)

    if not ok then
        rcWarn("%s failed: %s", tostring(context or "Worker charge"), tostring(result))
        return false
    end

    return true
end

function HelperPayroll:processDailyPayroll(dt)
    if not self:isDailyPayrollMode() then
        return
    end

    if not self.settings.enableCustomWorkerCosts or not self.settings.chargeCustomWorkerCosts then
        return
    end

    self.payrollCheckAccumulatorMs = (self.payrollCheckAccumulatorMs or 0) + (dt or 0)
    if self.payrollCheckAccumulatorMs < (self.payrollCheckIntervalMs or 30000) then
        return
    end
    self.payrollCheckAccumulatorMs = 0

    local currentHour = self:getGameHour()
    if currentHour == nil then
        if not self.warnedMissingPayrollClock then
            rcWarn("Daily payroll mode is enabled but game hour could not be resolved; payroll will not run until the clock is readable")
            self.warnedMissingPayrollClock = true
        end
        return
    end

    local payrollHour = tonumber(self.settings.payrollHour) or 18
    if currentHour < payrollHour then
        return
    end

    local currentDate = self:getGameDateKey()
    local rowsPaid = 0
    local totalPaid = 0

    for _, daily in pairs(self.workerDailyLedger or {}) do
        if daily ~= nil and not daily.payrollApplied and (daily.jobs or 0) > 0 and (daily.gameDate == currentDate or daily.gameDate == nil or daily.gameDate == "unknown") then
            local charge, minimumApplied = self:calculateDailyPayrollCharge(daily)
            if charge > 0 then
                local farmId = daily.farmId or self:getActiveFarmId()
                local applied = self:applyMoneyCharge(charge, farmId, "Daily payroll charge")
                if applied then
                    daily.payrollApplied = true
                    daily.payrollCharge = charge
                    daily.minimumApplied = minimumApplied
                    daily.charged = (tonumber(daily.charged) or 0) + charge
                    rowsPaid = rowsPaid + 1
                    totalPaid = totalPaid + charge
                    self.workerLedgerTotal = (self.workerLedgerTotal or 0) + charge
                    rcLog(
                        "Daily payroll applied: gameDate=%s helperSlot=%s helper=%s role=%s jobs=%d hours=%.3f labour=%.2f callout=%.2f minimum=%.2f minimumApplied=%s charge=%.2f farmId=%s payrollHour=%s moneyType=%s",
                        tostring(daily.gameDate),
                        tostring(daily.helperSlot),
                        tostring(daily.helperName),
                        tostring(daily.helperRole),
                        tonumber(daily.jobs) or 0,
                        tonumber(daily.hours) or 0,
                        tonumber(daily.labour) or 0,
                        tonumber(self.settings.workerCalloutFee) or 0,
                        tonumber(self.settings.minimumWorkerCharge) or 0,
                        tostring(minimumApplied),
                        tonumber(charge) or 0,
                        tostring(farmId),
                        tostring(payrollHour),
                        tostring(self:getMoneyTypeName(MoneyType ~= nil and MoneyType.AI or nil))
                    )
                end
            end
        end
    end

    if rowsPaid > 0 then
        rcLog("Daily payroll summary: gameDate=%s rows=%d totalPaid=%.2f sessionTotalCharged=%.2f", tostring(currentDate), rowsPaid, totalPaid, tonumber(self.workerLedgerTotal) or 0)
    end
end


function HelperPayroll:applyWorkerCharge(tracked)
    if tracked == nil then
        return false
    end

    if not self.settings.enableCustomWorkerCosts or not self.settings.chargeCustomWorkerCosts then
        return false
    end

    if self.settings.billingMode == "disabled" then
        rcLog("Worker billing skipped: billingMode=disabled")
        return false
    end

    if not self:isOnJobFinishMode() and not self:isDailyPayrollMode() then
        rcWarn("Unsupported billingMode '%s'; using onJobFinish behaviour for this prototype", tostring(self.settings.billingMode))
    end

    local chargeToApply, breakdown = self:calculateWorkerCharge(tracked)
    local farmId = self:getActiveFarmId()

    self.workerLedgerCount = (self.workerLedgerCount or 0) + 1
    local entry = {
        sequence = tracked.sequence,
        jobType = tracked.name,
        workerId = breakdown.workerId,
        workerName = breakdown.workerName,
        helperSlot = breakdown.helperSlot,
        helperSlotSource = breakdown.helperSlotSource,
        helperName = breakdown.helperName,
        helperRole = breakdown.helperRole,
        elapsedHours = breakdown.elapsedHours,
        hourlyRate = breakdown.hourlyRate,
        charge = 0,
        calculatedJobCharge = chargeToApply,
        farmId = farmId,
        profileId = breakdown.profileId,
        gameDate = self:getGameDateKey(),
        billingMode = self.settings.billingMode
    }
    entry.labourCharge = breakdown.labourCharge
    entry.calloutFee = breakdown.calloutFee
    entry.minimumCharge = breakdown.minimumCharge
    entry.appliedMinimum = breakdown.appliedMinimum
    self.workerLedger[self.workerLedgerCount] = entry
    local daily = self:updateDailyLedger(entry)

    if self:isDailyPayrollMode() then
        rcLog(
            "Worker billing deferred to daily payroll: seq=%s type=%s helperSlot=%s helper=%s role=%s workerRate=%s profile=%s elapsedHours=%.3f rate=%.2f labour=%.2f dailyJobs=%s gameDate=%s payrollHour=%s",
            tostring(entry.sequence),
            tostring(entry.jobType),
            tostring(entry.helperSlot),
            tostring(entry.helperName),
            tostring(entry.helperRole),
            tostring(entry.workerId),
            tostring(entry.profileId),
            tonumber(entry.elapsedHours) or 0,
            tonumber(entry.hourlyRate) or 0,
            tonumber(entry.labourCharge) or 0,
            tostring(daily ~= nil and daily.jobs or "unknown"),
            tostring(entry.gameDate),
            tostring(self.settings.payrollHour)
        )
        return true
    end

    if chargeToApply <= 0 then
        rcLog(
            "Worker billing skipped: seq=%s type=%s worker=%s elapsedHours=%.3f rate=%.2f charge=%.2f",
            tostring(tracked.sequence),
            tostring(tracked.name),
            tostring(breakdown.helperName or breakdown.workerName),
            tonumber(breakdown.elapsedHours) or 0,
            tonumber(breakdown.hourlyRate) or 0,
            tonumber(chargeToApply) or 0
        )
        return false
    end

    local applied = self:applyMoneyCharge(chargeToApply, farmId, "Custom worker charge")
    if not applied then
        return false
    end

    entry.charge = chargeToApply
    if daily ~= nil then
        daily.charged = (tonumber(daily.charged) or 0) + chargeToApply
    end
    self.workerLedgerTotal = (self.workerLedgerTotal or 0) + (tonumber(entry.charge) or 0)

    rcLog(
        "Worker billing applied: seq=%s type=%s helperSlot=%s helperSlotSource=%s helper=%s role=%s workerRate=%s profile=%s elapsedHours=%.3f rate=%.2f labour=%.2f callout=%.2f minimum=%.2f minimumApplied=%s charge=%.2f farmId=%s gameDate=%s moneyType=%s",
        tostring(entry.sequence),
        tostring(entry.jobType),
        tostring(entry.helperSlot),
        tostring(entry.helperSlotSource),
        tostring(entry.helperName),
        tostring(entry.helperRole),
        tostring(entry.workerId),
        tostring(entry.profileId),
        tonumber(entry.elapsedHours) or 0,
        tonumber(entry.hourlyRate) or 0,
        tonumber(entry.labourCharge) or 0,
        tonumber(entry.calloutFee) or 0,
        tonumber(entry.minimumCharge) or 0,
        tostring(entry.appliedMinimum),
        tonumber(entry.charge) or 0,
        tostring(entry.farmId),
        tostring(entry.gameDate),
        tostring(self:getMoneyTypeName(MoneyType ~= nil and MoneyType.AI or nil))
    )

    rcLog(
        "Worker ledger session total: entries=%d totalCharged=%.2f",
        tonumber(self.workerLedgerCount) or 0,
        tonumber(self.workerLedgerTotal) or 0
    )

    return true
end


function HelperPayroll:buildMoneyTypeNameCache()
    self.moneyTypeNames = {}

    if MoneyType == nil then
        rcWarn("MoneyType table is not available while building debug cache")
        return
    end

    for name, value in pairs(MoneyType) do
        if value ~= nil then
            self.moneyTypeNames[value] = name
        end
    end

    rcLog("MoneyType debug cache built. AI=%s WORKER_WAGES=%s", tostring(MoneyType.AI), tostring(MoneyType.WORKER_WAGES))
end

function HelperPayroll:getMoneyTypeName(moneyType)
    if self.moneyTypeNames ~= nil and self.moneyTypeNames[moneyType] ~= nil then
        return self.moneyTypeNames[moneyType]
    end

    return tostring(moneyType)
end

function HelperPayroll:isAIMoneyType(moneyType)
    return MoneyType ~= nil and MoneyType.AI ~= nil and moneyType == MoneyType.AI
end

function HelperPayroll:getAIJobDebugName(job)
    if job == nil then
        return "nil"
    end

    if job.className ~= nil then
        return tostring(job.className)
    end

    if job.typeName ~= nil then
        return tostring(job.typeName)
    end

    local safeIsa = function(classRef)
        if classRef == nil or job.isa == nil then
            return false
        end

        local ok, result = pcall(function()
            return job:isa(classRef)
        end)

        return ok and result == true
    end

    if safeIsa(AIJobFieldWork) then return "AIJobFieldWork" end
    if safeIsa(AIJobConveyor) then return "AIJobConveyor" end
    if safeIsa(AIJobDriveTo) then return "AIJobDriveTo" end
    if safeIsa(AIJobBaleFinder) then return "AIJobBaleFinder" end
    if safeIsa(AIJobCombine) then return "AIJobCombine" end
    if safeIsa(AIJobSprayer) then return "AIJobSprayer" end

    return tostring(job)
end

function HelperPayroll.aiJobGetPricePerMs(job, superFunc, ...)
    local jobName = HelperPayroll:getAIJobDebugName(job)
    local stats = HelperPayroll.aiPriceStatsByType[jobName]

    if stats == nil then
        stats = {
            calls = 0,
            logged = false,
            originalPricePerMs = nil
        }
        HelperPayroll.aiPriceStatsByType[jobName] = stats
    end

    stats.calls = (stats.calls or 0) + 1

    -- This hook is called very frequently while the AI job is active, so logging must stay throttled.
    -- Only call the original price function once per observed job type for diagnostics, then always return zero.
    if not stats.logged then
        local originalPrice = nil

        if superFunc ~= nil then
            local ok, result = pcall(superFunc, job, ...)
            if ok then
                originalPrice = result
                stats.originalPricePerMs = result
            else
                rcWarn("AIJob price superFunc failed for %s: %s", tostring(jobName), tostring(result))
            end
        end

        stats.logged = true
        HelperPayroll.aiPriceDebugCount = HelperPayroll.aiPriceDebugCount + 1

        rcLog(
            "AI helper pricing suppressed for jobType=%s originalPricePerMs=%s returned=0; further per-call logs muted",
            tostring(jobName),
            tostring(originalPrice)
        )
    end

    return 0
end

function HelperPayroll:installAIWorkerHooks()
    if self.aiWorkerHooksInstalled then
        rcLog("AI worker price hooks already installed")
        return
    end

    if not self.settings.suppressVanillaAIWorkerCosts then
        rcLog("AI worker price hooks skipped; suppressVanillaAIWorkerCosts=false")
        return
    end

    if Utils == nil or Utils.overwrittenFunction == nil then
        rcWarn("Utils.overwrittenFunction not available; AI worker price hooks not installed")
        return
    end

    local installed = 0

    local function hookPriceFunction(label, classRef)
        if classRef == nil then
            rcWarn("%s not available; price hook skipped", tostring(label))
            return
        end

        if classRef.getPricePerMs == nil then
            rcWarn("%s.getPricePerMs not available; price hook skipped", tostring(label))
            return
        end

        classRef.getPricePerMs = Utils.overwrittenFunction(classRef.getPricePerMs, HelperPayroll.aiJobGetPricePerMs)
        installed = installed + 1
        rcLog("Installed %s.getPricePerMs suppression hook", tostring(label))
    end

    hookPriceFunction("AIJob", AIJob)
    hookPriceFunction("AIJobFieldWork", AIJobFieldWork)
    hookPriceFunction("AIJobConveyor", AIJobConveyor)
    hookPriceFunction("AIJobDriveTo", AIJobDriveTo)
    hookPriceFunction("AIJobBaleFinder", AIJobBaleFinder)
    hookPriceFunction("AIJobCombine", AIJobCombine)
    hookPriceFunction("AIJobSprayer", AIJobSprayer)

    self.aiWorkerHooksInstalled = installed > 0

    if self.aiWorkerHooksInstalled then
        rcLog("AI worker price suppression installed. Hook count=%d", installed)
    else
        rcWarn("No AI worker price hooks were installed")
    end
end

function HelperPayroll:scanActiveAIJobs(dt)
    if g_currentMission == nil or g_currentMission.aiSystem == nil then
        return
    end

    local activeJobs = g_currentMission.aiSystem.activeJobs
    if activeJobs == nil then
        return
    end

    local seen = {}

    for _, job in pairs(activeJobs) do
        local jobId = tostring(job)
        seen[jobId] = true

        if self.trackedAIJobs[jobId] == nil then
            self.trackedAIJobCount = self.trackedAIJobCount + 1
            self.trackedAIJobs[jobId] = {
                sequence = self.trackedAIJobCount,
                name = self:getAIJobDebugName(job),
                job = job,
                elapsedMs = 0,
                lastSummaryMs = 0,
                billed = false
            }

            local assignment = self:resolveWorkerAssignment(self.trackedAIJobs[jobId])
            self.trackedAIJobs[jobId].helperSlot = assignment.helperSlot
            self.trackedAIJobs[jobId].helperSlotSource = assignment.helperSlotSource
            rcLog("AI job detected #%d: id=%s type=%s helperSlot=%s helperSlotSource=%s helper=%s role=%s workerRate=%s profile=%s rate=%.2f", self.trackedAIJobCount, tostring(jobId), tostring(self.trackedAIJobs[jobId].name), tostring(assignment.helperSlot), tostring(assignment.helperSlotSource), tostring(assignment.helperName), tostring(assignment.helperRole), tostring(assignment.workerId), tostring(assignment.profileId), tonumber(assignment.hourlyRate) or 0)
        end

        local tracked = self.trackedAIJobs[jobId]
        tracked.elapsedMs = (tracked.elapsedMs or 0) + (dt or 0)

        -- Duration tracking and active summary. Billing is applied when the job finishes.
        if tracked.elapsedMs - (tracked.lastSummaryMs or 0) >= 60000 then
            tracked.lastSummaryMs = tracked.elapsedMs
            rcLog(
                "AI job active summary: seq=%s id=%s type=%s helperSlot=%s elapsedMinutes=%.1f customBilling=%s",
                tostring(tracked.sequence),
                tostring(jobId),
                tostring(tracked.name),
                tostring(tracked.helperSlot or "unassigned"),
                (tracked.elapsedMs or 0) / 60000,
                tostring(self.settings.enableCustomWorkerCosts and self.settings.chargeCustomWorkerCosts)
            )
        end
    end

    for jobId, tracked in pairs(self.trackedAIJobs) do
        if not seen[jobId] then
            local elapsedHours = (tracked.elapsedMs or 0) / 3600000
            local stats = self.aiPriceStatsByType ~= nil and self.aiPriceStatsByType[tracked.name] or nil
            local billingHandled = false
            if not tracked.billed then
                billingHandled = self:applyWorkerCharge(tracked)
                tracked.billed = billingHandled
            end

            local billingMode = tostring(self.settings.billingMode or "onJobFinish")
            local immediateCharge = billingHandled and self:isOnJobFinishMode()
            local payrollDeferred = billingHandled and self:isDailyPayrollMode()

            rcLog(
                "AI job finished: seq=%s id=%s type=%s elapsedHours=%.3f suppressedPriceCalls=%s customBilling=%s billingMode=%s billingHandled=%s immediateCharge=%s payrollDeferred=%s",
                tostring(tracked.sequence),
                tostring(jobId),
                tostring(tracked.name),
                elapsedHours,
                tostring(stats ~= nil and stats.calls or "unknown"),
                tostring(self.settings.enableCustomWorkerCosts and self.settings.chargeCustomWorkerCosts),
                billingMode,
                tostring(billingHandled),
                tostring(immediateCharge),
                tostring(payrollDeferred)
            )
            self.trackedAIJobs[jobId] = nil
        end
    end
end

function HelperPayroll:installMoneyHooks()
    -- Legacy diagnostic retained only as a fallback marker. FS25 helper suppression is now done through AIJob.getPricePerMs hooks.
    rcLog("Farm.addMoney hook skipped. Using AIJob.getPricePerMs suppression for vanilla helper costs.")
end

function HelperPayroll:initialize(reason)
    if self.isInitialized then
        rcLog("Initialize skipped; already initialized. reason=%s", tostring(reason))
        return
    end

    rcLog("Initializing. reason=%s modName=%s modDirectory=%s", tostring(reason), tostring(self.MOD_NAME), tostring(self.MOD_DIRECTORY))
    self:loadConfig()
    self:buildMoneyTypeNameCache()
    self:installAIWorkerHooks()
    self:installMoneyHooks()
    self.isInitialized = true
    rcLog("Initialized")
end

function HelperPayroll:onMissionStarted()
    self:initialize("onMissionStarted")
end

function HelperPayroll:loadMap(name)
    self:initialize("loadMap")
end

function HelperPayroll:onUpdate(dt)
    self:scanActiveAIJobs(dt)
    self:processDailyPayroll(dt)
end

function HelperPayroll:update(dt)
    -- Some FS script contexts call update instead of onUpdate.
    self:scanActiveAIJobs(dt)
    self:processDailyPayroll(dt)
end

function HelperPayroll:logAIPriceSuppressionSummary()
    if self.aiPriceStatsByType == nil then
        return
    end

    for jobName, stats in pairs(self.aiPriceStatsByType) do
        rcLog(
            "AI price suppression summary: jobType=%s calls=%s originalPricePerMs=%s returned=0",
            tostring(jobName),
            tostring(stats.calls),
            tostring(stats.originalPricePerMs)
        )
    end
end

function HelperPayroll:deleteMap()
    if self.workerLedgerCount ~= nil and self.workerLedgerCount > 0 then
        rcLog("Worker ledger summary: entries=%d totalCharged=%.2f billingMode=%s", self.workerLedgerCount, tonumber(self.workerLedgerTotal) or 0, tostring(self.settings.billingMode))
    end
    if self.workerDailyLedger ~= nil then
        local dailyRows = 0
        for _, _ in pairs(self.workerDailyLedger) do
            dailyRows = dailyRows + 1
        end
        if dailyRows > 0 then
            rcLog("Worker daily ledger summary: rows=%d", dailyRows)
        end
    end
    self:logAIPriceSuppressionSummary()
    rcLog("deleteMap called")
    self.isInitialized = false
end

function HelperPayroll:onMissionLoaded(mission)
    self:initialize("onMissionLoaded")
end

function HelperPayroll:onStartMission()
    self:initialize("onStartMission")
end

rcLog("Registering mod event listener")
addModEventListener(HelperPayroll)
rcLog("Mod event listener registered")
