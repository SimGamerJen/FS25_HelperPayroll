-- Farm Workforce relationship metadata. Intentionally independent of payroll
-- compensation, runtime availability and HelperProfiles identity ownership.
FarmWorkforceRelationships = {}
FarmWorkforceRelationships.SCHEMA_VERSION = 1
FarmWorkforceRelationships.OPTIONS = {
    {id="unassigned", label="Not assigned"},
    {id="family", label="Family"},
    {id="permanent", label="Permanent"},
    {id="seasonal", label="Seasonal"},
    {id="contractor", label="Contractor"},
    {id="volunteer", label="Volunteer"}
}

local function normaliseSlot(slot)
    local value = string.upper(tostring(slot or ""))
    if #value ~= 1 then return nil end
    local n = string.byte(value)
    if n == nil or n < string.byte("A") or n > string.byte("T") then return nil end
    return value
end

local function normaliseRelationship(value)
    value = string.lower(tostring(value or "unassigned"))
    for _, option in ipairs(FarmWorkforceRelationships.OPTIONS) do
        if option.id == value then return value end
    end
    return "unassigned"
end

local function getPath(owner)
    if owner == nil then return nil end
    if owner.initPersistencePaths ~= nil then owner:initPersistencePaths() end
    local dir = owner.persistence ~= nil and owner.persistence.savegameDir or nil
    if dir == nil or dir == "" then return nil end
    return dir .. "farmWorkforceRelationships.xml"
end

function FarmWorkforceRelationships.ensureLoaded(owner)
    local path = getPath(owner)
    if path == nil then return false end
    if FarmWorkforceRelationships.loadedPath == path then return true end
    FarmWorkforceRelationships.values = {}
    FarmWorkforceRelationships.loadedPath = nil
    if fileExists ~= nil and fileExists(path) then
        local xml = loadXMLFile("farmWorkforceRelationshipsRead", path)
        if xml == nil or xml == 0 then
            print("[FarmWorkforce] Cannot read relationship metadata: " .. tostring(path))
            return false
        end
        local version = tonumber(getXMLInt(xml, "farmWorkforce#schemaVersion")) or 1
        if version > FarmWorkforceRelationships.SCHEMA_VERSION then
            print("[FarmWorkforce] Future relationship schema unsupported: " .. tostring(version))
            delete(xml)
            return false
        end
        for i = 0, 19 do
            local key = string.format("farmWorkforce.member(%d)", i)
            if not hasXMLProperty(xml, key) then break end
            local slot = normaliseSlot(getXMLString(xml, key .. "#slot"))
            if slot ~= nil then
                local relation = normaliseRelationship(getXMLString(xml, key .. "#relationship"))
                if relation ~= "unassigned" then FarmWorkforceRelationships.values[slot] = relation end
            end
        end
        delete(xml)
    end
    FarmWorkforceRelationships.loadedPath = path
    return true
end

function FarmWorkforceRelationships.get(owner, slot)
    local key = normaliseSlot(slot)
    if key == nil then return "unassigned" end
    if not FarmWorkforceRelationships.ensureLoaded(owner) then return "unassigned" end
    return FarmWorkforceRelationships.values[key] or "unassigned"
end

function FarmWorkforceRelationships.label(value)
    value = normaliseRelationship(value)
    for _, option in ipairs(FarmWorkforceRelationships.OPTIONS) do
        if option.id == value then return option.label end
    end
    return "Not assigned"
end

function FarmWorkforceRelationships.set(owner, slot, relationship)
    local key = normaliseSlot(slot)
    if key == nil or not FarmWorkforceRelationships.ensureLoaded(owner) then return false end
    local value = normaliseRelationship(relationship)
    local path = FarmWorkforceRelationships.loadedPath
    local oldValue = FarmWorkforceRelationships.values[key]
    if value == "unassigned" then
        FarmWorkforceRelationships.values[key] = nil
    else
        FarmWorkforceRelationships.values[key] = value
    end
    local xml = createXMLFile("farmWorkforceRelationshipsWrite", path, "farmWorkforce")
    if xml == nil or xml == 0 then
        FarmWorkforceRelationships.values[key] = oldValue
        return false
    end
    setXMLInt(xml, "farmWorkforce#schemaVersion", FarmWorkforceRelationships.SCHEMA_VERSION)
    local i = 0
    for n = string.byte("A"), string.byte("T") do
        local memberSlot = string.char(n)
        local rel = FarmWorkforceRelationships.values[memberSlot]
        if rel ~= nil then
            local row = string.format("farmWorkforce.member(%d)", i)
            setXMLString(xml, row .. "#slot", memberSlot)
            setXMLString(xml, row .. "#relationship", rel)
            i = i + 1
        end
    end
    saveXMLFile(xml)
    delete(xml)
    -- Relationship-only save; no calls to payroll ledgers or compensation.
    return true
end

function FarmWorkforceRelationships.next(owner, slot, direction)
    local old = FarmWorkforceRelationships.get(owner, slot)
    for i, option in ipairs(FarmWorkforceRelationships.OPTIONS) do
        if option.id == old then
            local count = #FarmWorkforceRelationships.OPTIONS
            local nextIndex = ((i - 1 + (direction == -1 and -1 or 1)) % count) + 1
            local target = FarmWorkforceRelationships.OPTIONS[nextIndex].id
            if FarmWorkforceRelationships.set(owner, slot, target) then return true, target end
            return false, old
        end
    end
    return false, old
end
