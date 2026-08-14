-- FS25_HelperPayroll
-- Runtime compatibility detection and safety gating.
-- Kept independent from payroll calculation so future multiplayer authority
-- checks can use the same runtime gate without changing persisted settings.

HelperPayrollCompatibility = HelperPayrollCompatibility or {}
HelperPayrollCompatibility.SCHEMA_VERSION = 1

HelperPayrollCompatibility.CONFLICTS = {
    {
        id = "workerCosts",
        displayName = "Realistic Worker Costs",
        modNames = {
            "FS25_WorkerCostsMod",
            "FS25_WorkerCosts",
            "WorkerCostsMod",
            "WorkerCosts"
        },
        globalNames = {
            "WorkerCostsMod",
            "WorkerCosts",
            "FS25_WorkerCostsMod"
        },
        reason = "Both mods suppress or replace vanilla AI wages and apply their own worker charges. Running both can produce missing deductions or duplicate payroll records."
    }
}

local function copyArray(values)
    local result = {}
    for i, value in ipairs(values or {}) do
        result[i] = value
    end
    return result
end

local function isLoadedThroughModTable(name)
    if type(g_modIsLoaded) == "table" and g_modIsLoaded[name] == true then
        return true, "g_modIsLoaded"
    end
    return false, nil
end

local function isLoadedThroughManager(name)
    if g_modManager == nil then
        return false, nil
    end

    if type(g_modManager.getModByName) == "function" then
        local ok, mod = pcall(g_modManager.getModByName, g_modManager, name)
        if ok and type(mod) == "table" then
            if mod.isLoaded == true or mod.isActive == true then
                return true, "g_modManager.getModByName"
            end
        end
    end

    if type(g_modManager.mods) == "table" then
        for _, mod in pairs(g_modManager.mods) do
            if type(mod) == "table" then
                local candidate = tostring(mod.modName or mod.name or mod.id or mod.directoryName or "")
                if candidate == name and (mod.isLoaded == true or mod.isActive == true) then
                    return true, "g_modManager.mods"
                end
            end
        end
    end

    return false, nil
end

local function isLoadedThroughGlobal(name)
    if rawget(_G, name) ~= nil then
        return true, "global"
    end
    return false, nil
end

function HelperPayrollCompatibility.findLoadedName(definition)
    for _, name in ipairs(definition.modNames or {}) do
        local loaded, source = isLoadedThroughModTable(name)
        if loaded then return name, source end

        loaded, source = isLoadedThroughManager(name)
        if loaded then return name, source end
    end

    for _, name in ipairs(definition.globalNames or {}) do
        local loaded, source = isLoadedThroughGlobal(name)
        if loaded then return name, source end
    end

    return nil, nil
end

function HelperPayrollCompatibility.scan()
    local status = {
        schemaVersion = HelperPayrollCompatibility.SCHEMA_VERSION,
        safe = true,
        blocked = false,
        detectedCount = 0,
        primaryConflictId = nil,
        primaryConflictName = nil,
        message = "No incompatible worker-cost mod detected.",
        conflicts = {}
    }

    for _, definition in ipairs(HelperPayrollCompatibility.CONFLICTS) do
        local loadedName, source = HelperPayrollCompatibility.findLoadedName(definition)
        if loadedName ~= nil then
            status.safe = false
            status.blocked = true
            status.detectedCount = status.detectedCount + 1
            status.primaryConflictId = status.primaryConflictId or definition.id
            status.primaryConflictName = status.primaryConflictName or definition.displayName
            table.insert(status.conflicts, {
                id = definition.id,
                displayName = definition.displayName,
                loadedName = loadedName,
                detectionSource = source,
                reason = definition.reason,
                modNames = copyArray(definition.modNames)
            })
        end
    end

    if status.blocked then
        status.message = string.format(
            "HelperPayroll payroll processing is disabled because %s is active. Disable one of the worker-cost mods and reload the save.",
            tostring(status.primaryConflictName or "an incompatible worker-cost mod")
        )
    end

    return status
end

function HelperPayrollCompatibility.apply(owner)
    local status = HelperPayrollCompatibility.scan()
    owner.compatibilityStatus = status
    owner.runtimeBillingBlocked = status.blocked == true
    owner.runtimeBillingBlockReason = status.blocked and status.message or nil
    return status
end

function HelperPayrollCompatibility.isRuntimeEnabled(owner)
    if owner == nil then return false end
    if owner.runtimeBillingBlocked == true then return false end
    return true
end

function HelperPayrollCompatibility.copyStatus(status)
    status = status or {}
    local copy = {
        schemaVersion = tonumber(status.schemaVersion) or HelperPayrollCompatibility.SCHEMA_VERSION,
        safe = status.safe ~= false,
        blocked = status.blocked == true,
        detectedCount = tonumber(status.detectedCount) or 0,
        primaryConflictId = status.primaryConflictId,
        primaryConflictName = status.primaryConflictName,
        message = tostring(status.message or "Compatibility status unavailable."),
        conflicts = {}
    }
    for _, conflict in ipairs(status.conflicts or {}) do
        table.insert(copy.conflicts, {
            id = conflict.id,
            displayName = conflict.displayName,
            loadedName = conflict.loadedName,
            detectionSource = conflict.detectionSource,
            reason = conflict.reason
        })
    end
    return copy
end
