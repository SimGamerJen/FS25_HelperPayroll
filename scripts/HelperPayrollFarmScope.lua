-- FS25_HelperPayroll
-- Farm ownership resolution kept separate from billing calculations.
-- The current release remains single-player, but job-start farm snapshots use
-- a network-safe scalar ID so future server authority can be added cleanly.

HelperPayrollFarmScope = HelperPayrollFarmScope or {}
HelperPayrollFarmScope.SCHEMA_VERSION = 1

local function safeMethod(object, methodName)
    if object == nil or type(object[methodName]) ~= "function" then return nil end
    local ok, value = pcall(object[methodName], object)
    if ok then return value end
    return nil
end

local function normalizeFarmId(value)
    local farmId = tonumber(value)
    if farmId == nil then return nil end
    farmId = math.floor(farmId)
    if farmId <= 0 then return nil end
    return farmId
end

function HelperPayrollFarmScope.getMissionFarmId()
    if g_currentMission == nil then return nil end

    local farmId = safeMethod(g_currentMission, "getFarmId")
    farmId = normalizeFarmId(farmId)
    if farmId ~= nil then return farmId, "mission.getFarmId" end

    if g_currentMission.player ~= nil then
        farmId = normalizeFarmId(g_currentMission.player.farmId)
        if farmId ~= nil then return farmId, "mission.player" end
    end

    return nil, "unresolved"
end

function HelperPayrollFarmScope.resolveJobFarmId(job, fallbackFarmId)
    if job ~= nil then
        local directFields = {
            "startedFarmId",
            "farmId",
            "ownerFarmId"
        }
        for _, fieldName in ipairs(directFields) do
            local farmId = normalizeFarmId(job[fieldName])
            if farmId ~= nil then
                return farmId, "job." .. fieldName
            end
        end

        local methodNames = {
            "getStartedFarmId",
            "getFarmId",
            "getOwnerFarmId"
        }
        for _, methodName in ipairs(methodNames) do
            local farmId = normalizeFarmId(safeMethod(job, methodName))
            if farmId ~= nil then
                return farmId, "job." .. methodName
            end
        end

        local vehicle = job.vehicle or job.vehicleToUse or job.helperVehicle
        if vehicle ~= nil then
            local farmId = normalizeFarmId(safeMethod(vehicle, "getOwnerFarmId"))
                or normalizeFarmId(vehicle.ownerFarmId)
            if farmId ~= nil then
                return farmId, "job.vehicle"
            end
        end
    end

    local fallback = normalizeFarmId(fallbackFarmId)
    if fallback ~= nil then return fallback, "fallback" end

    local missionFarmId, source = HelperPayrollFarmScope.getMissionFarmId()
    if missionFarmId ~= nil then return missionFarmId, source end

    return 1, "defaultFarm1"
end
