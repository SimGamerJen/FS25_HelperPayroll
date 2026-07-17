-- Helper Payroll
-- Version: 0.3.3.0-beta-rc
-- Purpose:
--   1. Suppress vanilla AI worker payments.
--   2. Track active AI jobs.
--   3. Apply configurable custom worker wages when AI jobs finish.
--   4. Prepare helper-slot and daily payroll structures for future HelperProfiles integration.

print("[HelperPayroll] Lua file loaded")

-- Forward declarations for helpers used by early callback methods.
local hpIsInputPress
local hpGetTimeMs

HelperPayroll = {}
HelperPayroll.MOD_NAME = g_currentModName or "FS25_HelperPayroll"
HelperPayroll.VERSION = "0.3.3.0"
HelperPayroll.RELEASE_CHANNEL = "beta-rc"
HelperPayroll.MOD_DIRECTORY = g_currentModDirectory or ""
HelperPayroll.BUNDLED_CONFIG_FILE = HelperPayroll.MOD_DIRECTORY .. "config/defaultPayrollConfig.xml"
HelperPayroll.CONFIG_FILE = HelperPayroll.BUNDLED_CONFIG_FILE
HelperPayroll.EXTERNAL_CONFIG_FILENAME = "defaultPayrollConfig.xml"

HelperPayroll.settings = {
    debug = true,
    suppressVanillaAIWorkerCosts = true,
    enableCustomWorkerCosts = true,
    activePayrollProfile = "default",
    payrollMode = "roleType",
    selectedRole = "standard",
    fallbackRole = "standard",
    defaultHelperSlot = "",
    chargeCustomWorkerCosts = true,
    billingMode = "onJobFinish",
    payrollHour = 18,
    minimumWorkerCharge = 0,
    workerCalloutFee = 0,
    roundWorkerCharges = true,
    logLevel = "debug",
    debugAllMoneyTransactions = false,
    helperProfilesDiagnostics = false,
    helperProfilesDiagnosticLimit = 12
}

HelperPayroll.profiles = {}
HelperPayroll.workerRates = {}
HelperPayroll.workerRateOrder = {}
HelperPayroll.helperSlots = {}
HelperPayroll.helperSlotCounts = {}
HelperPayroll.helperProfilesMappings = {}
HelperPayroll.helperProfilesMappingsByIdentity = {}
HelperPayroll.helperProfilesMappingsBySlot = {}
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
HelperPayroll.payrollCheckIntervalMs = 5000
HelperPayroll.lastPayrollClockDay = nil
HelperPayroll.lastPayrollClockHour = nil
HelperPayroll.lastPayrollClockDayTime = nil
HelperPayroll.warnedMissingPayrollClock = false
HelperPayroll.startupStatusElapsedMs = 0
HelperPayroll.startupStatusDelayMs = 1500
HelperPayroll.startupStatusLogged = false
HelperPayroll.helperProfilesGlobalScanDone = false
HelperPayroll.helperProfilesJobDiagnosticCount = 0
HelperPayroll.helperProfilesJobDiagnosticLimit = 6
HelperPayroll.helperProfilesBridge = {
    modLoaded = false,
    apiAvailable = false,
    apiVersion = nil,
    modVersion = nil,
    detectionSource = "none",
    source = "none"
}
HelperPayroll.actionEventIds = {}
HelperPayroll.roleFlashText = nil
HelperPayroll.roleFlashTime = 0
HelperPayroll.roleListVisible = false
HelperPayroll.reportOverlayVisible = false
HelperPayroll.reportOverlayPage = 1
HelperPayroll.reportOverlayMaxPage = 4
HelperPayroll.consoleCommandsRegistered = false
HelperPayroll.persistence = {
    modSettingsDir = nil,
    savegameName = nil,
    savegameDir = nil,
    filePath = nil,
    loaded = false
}
HelperPayroll.policyConfig = {
    modSettingsDir = nil,
    externalPath = nil,
    bundledPath = nil,
    activePath = nil,
    source = "bundled",
    generated = false
}
HelperPayroll.ledger = {
    ledgerDir = nil,
    indexPath = nil,
    loaded = false,
    index = nil,
    periodEntries = {},
    loadedPeriods = {},
    currentPeriodId = nil
}
-- HelperProfiles-style overlay defaults for the payroll role list.
HelperPayroll.roleListUi = {
    anchor = "TR",
    x = 0.985,
    y = 0.900,
    scale = 1.0,
    opacity = 0.40,
    pad = 0.006,
    rowGap = 0.006,
    fontSize = 0.014,
    width = 0.400,
    maxRows = 10,
    bgEnabled = true,
    outline = false,
    shadow = false
}

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

function HelperPayroll:isDetailedDiagnosticsEnabled()
    local level = string.lower(tostring(self.settings ~= nil and self.settings.logLevel or "normal"))
    return level == "debug" or level == "trace"
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


local HPAY_DEFAULT_POLICY_XML = [=[
<?xml version="1.0" encoding="utf-8"?>
<helperPayroll>
    <settings>
        <debug>true</debug>
        <suppressVanillaAIWorkerCosts>true</suppressVanillaAIWorkerCosts>
        <enableCustomWorkerCosts>true</enableCustomWorkerCosts>

        <!-- Public/default profile. This mod uses the savegame's own money display settings. -->
        <activePayrollProfile>default</activePayrollProfile>

        <!--
            roleType  = vanilla-friendly mode; all AI jobs use selectedRole for payroll.
            helperSlot = advanced/roleplay mode; detected vanilla helper slot A-J resolves to helperSlots below.
        -->
        <payrollMode>roleType</payrollMode>
        <selectedRole>standard</selectedRole>
        <fallbackRole>standard</fallbackRole>

        <!-- Optional fallback only. Leave blank unless you deliberately want every job assigned to one slot. -->
        <defaultHelperSlot></defaultHelperSlot>

        <chargeCustomWorkerCosts>true</chargeCustomWorkerCosts>
        <billingMode>onJobFinish</billingMode>
        <payrollHour>18</payrollHour>
        <minimumWorkerCharge>5.00</minimumWorkerCharge>
        <workerCalloutFee>0.00</workerCalloutFee>
        <roundWorkerCharges>true</roundWorkerCharges>
        <roleSelectorDebounceMs>450</roleSelectorDebounceMs>
        <logLevel>normal</logLevel>
        <debugAllMoneyTransactions>false</debugAllMoneyTransactions>
        <helperProfilesDiagnostics>false</helperProfilesDiagnostics>
        <helperProfilesDiagnosticLimit>12</helperProfilesDiagnosticLimit>
    </settings>

    <profiles>
        <profile id="default" name="Default Helper Payroll" economyMultiplier="1.00" />
        <profile id="uk_tenant" name="UK Tenant Farm Example" economyMultiplier="1.00" />
        <profile id="us_ranch" name="US Ranch Example" economyMultiplier="1.00" />
    </profiles>

    <workerRates profile="default">
        <worker id="owner" name="Owner Labour" hourlyRate="0" />
        <worker id="trainee" name="Trainee Helper" hourlyRate="10" />
        <worker id="standard" name="Standard Helper" hourlyRate="18" />
        <worker id="skilled" name="Skilled Operator" hourlyRate="22" />
        <worker id="contractor" name="Contractor" hourlyRate="30" />
    </workerRates>

    <workerRates profile="uk_tenant">
        <worker id="owner" name="Owner Labour" hourlyRate="0" />
        <worker id="trainee" name="Trainee Helper" hourlyRate="10" />
        <worker id="standard" name="General Farmhand" hourlyRate="14" />
        <worker id="skilled" name="Skilled Operator" hourlyRate="18" />
        <worker id="manager" name="Farm Manager" hourlyRate="24" />
        <worker id="contractor" name="External Contractor" hourlyRate="28" />
    </workerRates>

    <workerRates profile="us_ranch">
        <worker id="owner" name="Owner Labour" hourlyRate="0" />
        <worker id="trainee" name="Trainee Ranch Hand" hourlyRate="14" />
        <worker id="standard" name="Ranch Hand" hourlyRate="18" />
        <worker id="skilled" name="Skilled Operator" hourlyRate="24" />
        <worker id="manager" name="Ranch Manager" hourlyRate="30" />
        <worker id="contractor" name="External Contractor" hourlyRate="35" />
    </workerRates>

    <!-- Advanced mode only: used when payrollMode="helperSlot". -->
    <helperSlots profile="default">
        <helper slot="A" name="Helper A" role="Standard Helper" workerRate="standard" />
        <helper slot="B" name="Helper B" role="Standard Helper" workerRate="standard" />
        <helper slot="C" name="Helper C" role="Standard Helper" workerRate="standard" />
        <helper slot="D" name="Helper D" role="Standard Helper" workerRate="standard" />
        <helper slot="E" name="Helper E" role="Standard Helper" workerRate="standard" />
        <helper slot="F" name="Helper F" role="Standard Helper" workerRate="standard" />
        <helper slot="G" name="Helper G" role="Standard Helper" workerRate="standard" />
        <helper slot="H" name="Helper H" role="Standard Helper" workerRate="standard" />
        <helper slot="I" name="Helper I" role="Standard Helper" workerRate="standard" />
        <helper slot="J" name="Helper J" role="Standard Helper" workerRate="standard" />
    </helperSlots>

    <!-- Example roleplay setup for use with HelperProfiles-style helper slot identities. -->
    <helperSlots profile="uk_tenant">
        <helper slot="A" name="Marty" role="Farm Manager" workerRate="manager" />
        <helper slot="B" name="Rhys" role="Skilled Operator" workerRate="skilled" />
        <helper slot="C" name="Ellie" role="General Farmhand" workerRate="standard" />
        <helper slot="D" name="Graham" role="Contractor" workerRate="contractor" />
    </helperSlots>

    <helperSlots profile="us_ranch">
        <helper slot="A" name="Riley" role="Skilled Operator" workerRate="skilled" />
        <helper slot="B" name="Jed" role="Neighbour / Mates Rate" workerRate="standard" />
        <helper slot="C" name="Miguel" role="Ranch Hand" workerRate="standard" />
        <helper slot="D" name="External Contractor" role="Contractor" workerRate="contractor" />
    </helperSlots>
</helperPayroll>
]=]

local function hpayPolicyGetUserPath()
    if getUserProfileAppPath ~= nil then
        return getUserProfileAppPath()
    end
    return ""
end

local function hpayPolicyFileExists(path)
    if path == nil or path == "" then
        return false
    end
    if fileExists ~= nil then
        return fileExists(path)
    end
    return false
end

local function hpayPolicyEnsureFolder(path)
    if path == nil or path == "" then
        return
    end
    if hpayPolicyFileExists(path) then
        return
    end
    if createFolder ~= nil then
        createFolder(path)
    end
end

local function hpayPolicyWriteFile(path, content)
    if path == nil or path == "" then
        return false
    end
    local f = io.open(path, "w")
    if f == nil then
        return false
    end
    f:write(tostring(content or ""))
    f:write("\n")
    f:close()
    return true
end

function HelperPayroll:initPolicyConfigPaths()
    self.policyConfig = self.policyConfig or {}
    local base = hpayPolicyGetUserPath() .. "modSettings/"
    local modDir = base .. "FS25_HelperPayroll/"

    hpayPolicyEnsureFolder(base)
    hpayPolicyEnsureFolder(modDir)

    self.policyConfig.modSettingsDir = modDir
    self.policyConfig.bundledPath = self.BUNDLED_CONFIG_FILE or (self.MOD_DIRECTORY .. "config/defaultPayrollConfig.xml")
    self.policyConfig.externalPath = modDir .. tostring(self.EXTERNAL_CONFIG_FILENAME or "defaultPayrollConfig.xml")
end

function HelperPayroll:ensureExternalPolicyConfig(reason)
    self:initPolicyConfigPaths()
    local path = self.policyConfig ~= nil and self.policyConfig.externalPath or nil
    if path == nil or path == "" then
        rcWarn("External policy config path could not be resolved")
        return false
    end

    if hpayPolicyFileExists(path) then
        return true
    end

    local ok = hpayPolicyWriteFile(path, HPAY_DEFAULT_POLICY_XML)
    if ok then
        self.policyConfig.generated = true
        rcLog("Generated external payroll policy config: reason=%s file=%s", tostring(reason or "first-run"), tostring(path))
        return true
    end

    rcWarn("Could not generate external payroll policy config: %s", tostring(path))
    return false
end

function HelperPayroll:resolvePolicyConfigFile()
    self:ensureExternalPolicyConfig("resolve")
    local externalPath = self.policyConfig ~= nil and self.policyConfig.externalPath or nil
    if externalPath ~= nil and externalPath ~= "" and hpayPolicyFileExists(externalPath) then
        self.CONFIG_FILE = externalPath
        self.policyConfig.activePath = externalPath
        self.policyConfig.source = "external"
        return externalPath, "external"
    end

    local bundled = self.BUNDLED_CONFIG_FILE or self.CONFIG_FILE
    self.CONFIG_FILE = bundled
    if self.policyConfig ~= nil then
        self.policyConfig.activePath = bundled
        self.policyConfig.source = "bundled"
    end
    return bundled, "bundled"
end

function HelperPayroll:resetExternalPolicyConfig(reason)
    self:initPolicyConfigPaths()
    local path = self.policyConfig ~= nil and self.policyConfig.externalPath or nil
    if path == nil or path == "" then
        rcWarn("Policy config reset failed: no external path resolved")
        return false
    end
    local ok = hpayPolicyWriteFile(path, HPAY_DEFAULT_POLICY_XML)
    if ok then
        self.policyConfig.generated = true
        rcLog("External policy config reset: %s", tostring(path))
        rcLog("External payroll policy config reset: reason=%s file=%s", tostring(reason or "manual"), tostring(path))
        return true
    end
    rcWarn("Policy config reset failed: %s", tostring(path))
    return false
end


local function hpayXmlEscape(value)
    local text = tostring(value or "")
    text = text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
    return text
end

function HelperPayroll:buildPolicyConfigXmlFromRuntime()
    local lines = {}
    local function add(line) table.insert(lines, line) end
    local settings = self.settings or {}
    add('<?xml version="1.0" encoding="utf-8"?>')
    add('<helperPayroll>')
    add('    <settings>')
    add(string.format('        <debug>%s</debug>', tostring(settings.debug == true)))
    add(string.format('        <suppressVanillaAIWorkerCosts>%s</suppressVanillaAIWorkerCosts>', tostring(settings.suppressVanillaAIWorkerCosts == true)))
    add(string.format('        <enableCustomWorkerCosts>%s</enableCustomWorkerCosts>', tostring(settings.enableCustomWorkerCosts == true)))
    add(string.format('        <activePayrollProfile>%s</activePayrollProfile>', hpayXmlEscape(settings.activePayrollProfile or 'default')))
    add(string.format('        <payrollMode>%s</payrollMode>', hpayXmlEscape(settings.payrollMode or 'roleType')))
    add(string.format('        <selectedRole>%s</selectedRole>', hpayXmlEscape(settings.selectedRole or 'standard')))
    add(string.format('        <fallbackRole>%s</fallbackRole>', hpayXmlEscape(settings.fallbackRole or 'standard')))
    add(string.format('        <defaultHelperSlot>%s</defaultHelperSlot>', hpayXmlEscape(settings.defaultHelperSlot or '')))
    add(string.format('        <chargeCustomWorkerCosts>%s</chargeCustomWorkerCosts>', tostring(settings.chargeCustomWorkerCosts == true)))
    add(string.format('        <billingMode>%s</billingMode>', hpayXmlEscape(settings.billingMode or 'onJobFinish')))
    add(string.format('        <payrollHour>%s</payrollHour>', tostring(math.floor(tonumber(settings.payrollHour) or 18))))
    add(string.format('        <minimumWorkerCharge>%.2f</minimumWorkerCharge>', tonumber(settings.minimumWorkerCharge) or 0))
    add(string.format('        <workerCalloutFee>%.2f</workerCalloutFee>', tonumber(settings.workerCalloutFee) or 0))
    add(string.format('        <roundWorkerCharges>%s</roundWorkerCharges>', tostring(settings.roundWorkerCharges == true)))
    add(string.format('        <roleSelectorDebounceMs>%s</roleSelectorDebounceMs>', tostring(math.floor(tonumber(settings.roleSelectorDebounceMs) or 450))))
    add(string.format('        <logLevel>%s</logLevel>', hpayXmlEscape(settings.logLevel or 'normal')))
    add(string.format('        <debugAllMoneyTransactions>%s</debugAllMoneyTransactions>', tostring(settings.debugAllMoneyTransactions == true)))
    add(string.format('        <helperProfilesDiagnostics>%s</helperProfilesDiagnostics>', tostring(settings.helperProfilesDiagnostics == true)))
    add(string.format('        <helperProfilesDiagnosticLimit>%s</helperProfilesDiagnosticLimit>', tostring(math.floor(tonumber(settings.helperProfilesDiagnosticLimit) or 12))))
    add('    </settings>')
    add('')
    add('    <profiles>')
    local profileIds = {}
    for id,_ in pairs(self.profiles or {}) do table.insert(profileIds, id) end
    table.sort(profileIds)
    for _, id in ipairs(profileIds) do
        local p = self.profiles[id]
        add(string.format('        <profile id="%s" name="%s" economyMultiplier="%.2f" />', hpayXmlEscape(id), hpayXmlEscape(p.name or id), tonumber(p.economyMultiplier) or 1))
    end
    add('    </profiles>')
    add('')
    for _, profileId in ipairs(profileIds) do
        local rates = self.workerRates ~= nil and self.workerRates[profileId] or nil
        if rates ~= nil then
            add(string.format('    <workerRates profile="%s">', hpayXmlEscape(profileId)))
            local order = self.workerRateOrder ~= nil and self.workerRateOrder[profileId] or {}
            for _, roleId in ipairs(order) do
                local w = rates[roleId]
                if w ~= nil then
                    add(string.format('        <worker id="%s" name="%s" hourlyRate="%s" />', hpayXmlEscape(roleId), hpayXmlEscape(w.name or roleId), hpayXmlEscape(tostring(tonumber(w.hourlyRate) or 0))))
                end
            end
            add('    </workerRates>')
            add('')
        end
    end
    for _, profileId in ipairs(profileIds) do
        local slots = self.helperSlots ~= nil and self.helperSlots[profileId] or nil
        if slots ~= nil then
            add(string.format('    <helperSlots profile="%s">', hpayXmlEscape(profileId)))
            for _, slot in ipairs({'A','B','C','D','E','F','G','H','I','J'}) do
                local h = slots[slot]
                if h ~= nil then
                    add(string.format('        <helper slot="%s" name="%s" role="%s" workerRate="%s" />', hpayXmlEscape(slot), hpayXmlEscape(h.name or ('Helper '..slot)), hpayXmlEscape(h.role or ''), hpayXmlEscape(h.workerRate or 'standard')))
                end
            end
            add('    </helperSlots>')
            add('')
        end
    end
    add('</helperPayroll>')
    return table.concat(lines, '\n')
end

function HelperPayroll:saveExternalPolicyConfigFromRuntime(reason)
    self:initPolicyConfigPaths()
    local path = self.policyConfig ~= nil and self.policyConfig.externalPath or nil
    if path == nil or path == '' then
        rcWarn('Policy config save failed: no external path resolved')
        return false
    end
    local ok = hpayPolicyWriteFile(path, self:buildPolicyConfigXmlFromRuntime())
    if ok then
        self.CONFIG_FILE = path
        self.policyConfig.activePath = path
        self.policyConfig.source = 'external'
        rcLog('External policy config saved: reason=%s file=%s', tostring(reason or 'runtime'), tostring(path))
        return true
    end
    rcWarn('Policy config save failed: %s', tostring(path))
    return false
end

function HelperPayroll:applyManagementDraft(draftSettings, draftRates, draftMappings, reason)
    draftSettings = draftSettings or {}
    draftRates = draftRates or {}
    draftMappings = draftMappings or {}
    self.settings.billingMode = tostring(draftSettings.billingMode or self.settings.billingMode or 'onJobFinish')
    self.settings.payrollHour = math.floor(tonumber(draftSettings.payrollHour or self.settings.payrollHour) or 18)
    self.settings.minimumWorkerCharge = tonumber(draftSettings.minimumWorkerCharge or self.settings.minimumWorkerCharge) or 0
    self.settings.workerCalloutFee = tonumber(draftSettings.workerCalloutFee or self.settings.workerCalloutFee) or 0
    self.settings.roundWorkerCharges = draftSettings.roundWorkerCharges == true or tostring(draftSettings.roundWorkerCharges) == 'true'
    self.settings.payrollMode = tostring(draftSettings.payrollMode or self.settings.payrollMode or 'roleType')
    self.settings.selectedRole = tostring(draftSettings.selectedRole or self.settings.selectedRole or 'standard')
    self.settings.fallbackRole = tostring(draftSettings.fallbackRole or self.settings.fallbackRole or 'standard')
    self.settings.activePayrollProfile = tostring(draftSettings.activePayrollProfile or self.settings.activePayrollProfile or 'default')
    local profileId = self.settings.activePayrollProfile
    if self.workerRates ~= nil and self.workerRates[profileId] ~= nil then
        for roleId, rate in pairs(draftRates) do
            if self.workerRates[profileId][roleId] ~= nil then
                self.workerRates[profileId][roleId].hourlyRate = tonumber(rate) or 0
            end
        end
    end
    for slot, roleId in pairs(draftMappings) do
        local hpSlotInfo = self:getHelperProfilesSlotInfo(slot)
        self:setHelperProfilesPayrollMapping(hpSlotInfo, slot, roleId)
    end
    local ok = self:saveSavegameSettings(reason or 'management-ui')
    if ok then
        self:showRoleMessage('Helper Payroll: save settings applied')
        rcLog('Management draft applied to savegame settings: reason=%s file=%s', tostring(reason or 'management-ui'), tostring(self.persistence ~= nil and self.persistence.filePath or 'unknown'))
    end
    return ok
end

function HelperPayroll:showManagementMenu()
    if HelperPayrollMenu ~= nil and HelperPayrollMenu.show ~= nil then
        self.roleListVisible = false
        self.reportOverlayVisible = false
        return HelperPayrollMenu.show(self.MOD_DIRECTORY, 'overview')
    end
    rcWarn('Management GUI is not available')
    return false
end

function HelperPayroll:onInputToggleManagementMenu(actionName, inputValue, callbackState, isAnalog)
    if not hpIsInputPress(inputValue, callbackState) then return end
    local now = hpGetTimeMs()
    local debounceMs = tonumber(self.settings.roleSelectorDebounceMs) or 450
    self._lastManagementMenuToggleAt = self._lastManagementMenuToggleAt or 0
    if now - self._lastManagementMenuToggleAt < debounceMs then return end
    self._lastManagementMenuToggleAt = now
    self:showManagementMenu()
end

function HelperPayroll:loadConfig()
    -- v0.2.x: prefer the player-editable policy file in modSettings.
    -- The bundled config remains a safe fallback and template source.
    local configPath, configSource = self:resolvePolicyConfigFile()
    local xmlFile = loadXMLFile("helperPayrollConfig", configPath)
    if xmlFile == nil or xmlFile == 0 then
        rcWarn("Could not load %s policy config: %s", tostring(configSource), tostring(configPath))
        local bundled = self.BUNDLED_CONFIG_FILE or self.CONFIG_FILE
        if bundled ~= nil and bundled ~= configPath then
            xmlFile = loadXMLFile("helperPayrollBundledConfigFallback", bundled)
            if xmlFile ~= nil and xmlFile ~= 0 then
                self.CONFIG_FILE = bundled
                self.policyConfig = self.policyConfig or {}
                self.policyConfig.activePath = bundled
                self.policyConfig.source = "bundled-fallback"
                configPath = bundled
                configSource = "bundled-fallback"
                rcWarn("Using bundled payroll policy fallback: %s", tostring(bundled))
            end
        end
        if xmlFile == nil or xmlFile == 0 then
            rcWarn("Could not load any payroll policy config")
            return
        end
    end

    -- Reset policy-derived tables so console reloads do not duplicate entries.
    self.profiles = {}
    self.workerRates = {}
    self.workerRateOrder = {}
    self.helperSlots = {}
    self.helperSlotCounts = {}

    self.settings.debug = getXmlBoolOrDefault(xmlFile, "helperPayroll.settings.debug", self.settings.debug)
    self.settings.suppressVanillaAIWorkerCosts = getXmlBoolOrDefault(xmlFile, "helperPayroll.settings.suppressVanillaAIWorkerCosts", self.settings.suppressVanillaAIWorkerCosts)
    self.settings.enableCustomWorkerCosts = getXmlBoolOrDefault(xmlFile, "helperPayroll.settings.enableCustomWorkerCosts", self.settings.enableCustomWorkerCosts)
    self.settings.activePayrollProfile = getXmlStringOrDefault(xmlFile, "helperPayroll.settings.activePayrollProfile", self.settings.activePayrollProfile)
    -- Backwards compatibility for early alpha configs.
    self.settings.activePayrollProfile = getXmlStringOrDefault(xmlFile, "helperPayroll.settings.defaultProfile", self.settings.activePayrollProfile)
    self.settings.payrollMode = getXmlStringOrDefault(xmlFile, "helperPayroll.settings.payrollMode", self.settings.payrollMode)
    self.settings.selectedRole = getXmlStringOrDefault(xmlFile, "helperPayroll.settings.selectedRole", self.settings.selectedRole)
    self.settings.fallbackRole = getXmlStringOrDefault(xmlFile, "helperPayroll.settings.fallbackRole", self.settings.fallbackRole)
    -- Backwards compatibility for early alpha configs.
    self.settings.selectedRole = getXmlStringOrDefault(xmlFile, "helperPayroll.settings.defaultWorker", self.settings.selectedRole)
    self.settings.defaultHelperSlot = getXmlStringOrDefault(xmlFile, "helperPayroll.settings.defaultHelperSlot", self.settings.defaultHelperSlot)
    self.settings.chargeCustomWorkerCosts = getXmlBoolOrDefault(xmlFile, "helperPayroll.settings.chargeCustomWorkerCosts", self.settings.chargeCustomWorkerCosts)
    self.settings.billingMode = getXmlStringOrDefault(xmlFile, "helperPayroll.settings.billingMode", self.settings.billingMode)
    self.settings.payrollHour = getXmlFloatOrDefault(xmlFile, "helperPayroll.settings.payrollHour", self.settings.payrollHour)
    self.settings.minimumWorkerCharge = getXmlFloatOrDefault(xmlFile, "helperPayroll.settings.minimumWorkerCharge", self.settings.minimumWorkerCharge)
    self.settings.workerCalloutFee = getXmlFloatOrDefault(xmlFile, "helperPayroll.settings.workerCalloutFee", self.settings.workerCalloutFee)
    self.settings.roundWorkerCharges = getXmlBoolOrDefault(xmlFile, "helperPayroll.settings.roundWorkerCharges", self.settings.roundWorkerCharges)
    self.settings.roleSelectorDebounceMs = getXmlFloatOrDefault(xmlFile, "helperPayroll.settings.roleSelectorDebounceMs", self.settings.roleSelectorDebounceMs or 450)
    self.settings.logLevel = getXmlStringOrDefault(xmlFile, "helperPayroll.settings.logLevel", self.settings.logLevel)
    self.settings.debugAllMoneyTransactions = getXmlBoolOrDefault(xmlFile, "helperPayroll.settings.debugAllMoneyTransactions", self.settings.debugAllMoneyTransactions)
    self.settings.helperProfilesDiagnostics = getXmlBoolOrDefault(xmlFile, "helperPayroll.settings.helperProfilesDiagnostics", self.settings.helperProfilesDiagnostics)
    self.settings.helperProfilesDiagnosticLimit = getXmlFloatOrDefault(xmlFile, "helperPayroll.settings.helperProfilesDiagnosticLimit", self.settings.helperProfilesDiagnosticLimit)

    self:loadProfiles(xmlFile)
    self:loadWorkerRates(xmlFile)
    self:loadHelperSlots(xmlFile)

    delete(xmlFile)
    rcLog("Loaded config. source=%s file=%s Active payroll profile: %s", tostring(self.policyConfig ~= nil and self.policyConfig.source or "unknown"), tostring(self.CONFIG_FILE), tostring(self.settings.activePayrollProfile))
    rcLog("Worker billing settings: enabled=%s payrollMode=%s billingMode=%s payrollHour=%s selectedRole=%s fallbackRole=%s defaultHelperSlot=%s minimum=%.2f callout=%.2f round=%s logLevel=%s helperProfilesDiagnostics=%s", tostring(self.settings.chargeCustomWorkerCosts), tostring(self.settings.payrollMode), tostring(self.settings.billingMode), tostring(self.settings.payrollHour), tostring(self.settings.selectedRole), tostring(self.settings.fallbackRole), tostring(self.settings.defaultHelperSlot ~= "" and self.settings.defaultHelperSlot or "none"), tonumber(self.settings.minimumWorkerCharge) or 0, tonumber(self.settings.workerCalloutFee) or 0, tostring(self.settings.roundWorkerCharges), tostring(self.settings.logLevel), tostring(self.settings.helperProfilesDiagnostics))
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

        local profile = getXmlStringOrDefault(xmlFile, groupKey .. "#profile", self.settings.activePayrollProfile)
        self.workerRates[profile] = self.workerRates[profile] or {}
        self.workerRateOrder[profile] = self.workerRateOrder[profile] or {}

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
                table.insert(self.workerRateOrder[profile], id)
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

        local profile = getXmlStringOrDefault(xmlFile, groupKey .. "#profile", self.settings.activePayrollProfile)
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
                    workerRate = getXmlStringOrDefault(xmlFile, helperKey .. "#workerRate", self.settings.selectedRole)
                }
                self.helperSlotCounts[profile] = (self.helperSlotCounts[profile] or 0) + 1
            end
            j = j + 1
        end
        i = i + 1
    end
end

function HelperPayroll:logHelperSlotConfig()
    local profileId = self.settings.activePayrollProfile or "default"
    local slotsForProfile = self.helperSlots ~= nil and self.helperSlots[profileId] or nil
    local slotCount = self.helperSlotCounts ~= nil and self.helperSlotCounts[profileId] or 0

    rcLog("Helper slot config: profile=%s slotsLoaded=%d defaultHelperSlot=%s payrollMode=%s", tostring(profileId), tonumber(slotCount) or 0, tostring(self.settings.defaultHelperSlot ~= "" and self.settings.defaultHelperSlot or "none"), tostring(self.settings.payrollMode))

    if slotsForProfile ~= nil and string.lower(tostring(self.settings.payrollMode or "")) == "helperslot" then
        for slot, helper in pairs(slotsForProfile) do
            rcLog("Helper slot loaded: profile=%s slot=%s name=%s role=%s workerRate=%s", tostring(profileId), tostring(slot), tostring(helper.name), tostring(helper.role), tostring(helper.workerRate))
        end
    end

    if self.settings.defaultHelperSlot ~= nil and self.settings.defaultHelperSlot ~= "" then
        if slotsForProfile == nil or slotsForProfile[self.settings.defaultHelperSlot] == nil then
            rcWarn("defaultHelperSlot '%s' is set but no matching helper slot exists for profile '%s'; jobs will fall back to selectedRole '%s'", tostring(self.settings.defaultHelperSlot), tostring(profileId), tostring(self.settings.selectedRole))
        else
            local helper = slotsForProfile[self.settings.defaultHelperSlot]
            rcLog("Default helper slot resolved: slot=%s name=%s role=%s workerRate=%s", tostring(self.settings.defaultHelperSlot), tostring(helper.name), tostring(helper.role), tostring(helper.workerRate))
        end
    end
end

function HelperPayroll:getActiveProfile()
    return self.profiles[self.settings.activePayrollProfile], self.settings.activePayrollProfile
end



function HelperPayroll:getSelectedWorkerRate()
    local _, profileId = self:getActiveProfile()
    local workerId = self.settings.selectedRole or self.settings.fallbackRole or "standard"
    local ratesForProfile = self.workerRates ~= nil and self.workerRates[profileId] or nil
    local worker = ratesForProfile ~= nil and ratesForProfile[workerId] or nil

    if worker == nil and ratesForProfile ~= nil then
        workerId = self.settings.fallbackRole or "standard"
        worker = ratesForProfile[workerId]
    end

    if worker == nil and ratesForProfile ~= nil then
        worker = ratesForProfile.standard or ratesForProfile.skilled or ratesForProfile.casual or ratesForProfile.owner
        if worker ~= nil then
            rcWarn("Selected role '%s' not found for profile '%s'; using '%s'", tostring(self.settings.selectedRole), tostring(profileId), tostring(worker.name))
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

function HelperPayroll:getDefaultWorkerRate()
    return self:getSelectedWorkerRate()
end

function HelperPayroll:getWorkerRateOrder(profileId)
    if profileId ~= nil and self.workerRateOrder ~= nil and self.workerRateOrder[profileId] ~= nil and #self.workerRateOrder[profileId] > 0 then
        return self.workerRateOrder[profileId]
    end

    local ratesForProfile = self.workerRates ~= nil and self.workerRates[profileId] or nil
    local order = {}
    if ratesForProfile ~= nil then
        for id, _ in pairs(ratesForProfile) do
            table.insert(order, id)
        end
        table.sort(order)
    end

    return order
end


hpIsInputPress = function(inputValue, callbackState)
    if type(inputValue) == "number" then
        return inputValue > 0
    elseif type(inputValue) == "boolean" then
        return inputValue == true
    end

    local v = tonumber(callbackState)
    return v ~= nil and v > 0
end

hpGetTimeMs = function()
    if type(g_time) == "number" then
        return g_time
    end
    if getTimeSec ~= nil then
        local ok, value = pcall(getTimeSec)
        if ok and type(value) == "number" then
            return value * 1000
        end
    end
    return math.floor(os.clock() * 1000)
end


local function hpayGetUserPath()
    if getUserProfileAppPath ~= nil then
        return getUserProfileAppPath()
    end
    return ""
end

local function hpayFileExists(path)
    if path == nil or path == "" then
        return false
    end
    if fileExists ~= nil then
        return fileExists(path)
    end
    local f = io.open(path, "rb")
    if f ~= nil then
        f:close()
        return true
    end
    return false
end

local function hpayEnsureFolder(path)
    if path == nil or path == "" then
        return
    end
    if hpayFileExists(path) then
        return
    end
    if createFolder ~= nil then
        createFolder(path)
    end
end

local function hpayNormalizePath(path)
    if path == nil then return nil end
    return tostring(path):gsub("\\", "/")
end

local function hpayPathBaseName(path)
    path = hpayNormalizePath(path or "") or ""
    path = path:gsub("/+$", "")
    local base = path:match("([^/]+)$")
    if base ~= nil and base ~= "" then return base end
    return nil
end

local function hpayDetectSavegameName()
    local mi = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    if mi ~= nil then
        local candidates = {
            mi.savegameDirectory,
            mi.savegameDir,
            mi.savegamePath,
            mi.savegameXMLFilename,
            mi.savegameSavePath,
        }
        for _, value in ipairs(candidates) do
            if value ~= nil and tostring(value) ~= "" then
                local path = hpayNormalizePath(value)
                local match = path and path:match("(savegame%d+)")
                if match ~= nil and match ~= "" then return match end
                local base = hpayPathBaseName(path)
                if base ~= nil and base ~= "" then return base end
            end
        end

        local index = mi.savegameIndex or mi.savegameNumber or mi.saveGameIndex or mi.saveGameNumber
        if index ~= nil and tonumber(index) ~= nil then
            return "savegame" .. tostring(math.floor(tonumber(index)))
        end
    end

    return "unknownSavegame"
end

local function hpIsPhysicalKeyPressed(keyName)
    if Input == nil or Input.isKeyPressed == nil then
        return false
    end

    local key = Input[keyName]
    if key == nil then
        return false
    end

    local ok, result = pcall(Input.isKeyPressed, key)
    return ok and result == true
end

local function hpIsAnyModifierDown()
    return hpIsPhysicalKeyPressed("KEY_lshift")
        or hpIsPhysicalKeyPressed("KEY_rshift")
        or hpIsPhysicalKeyPressed("KEY_lctrl")
        or hpIsPhysicalKeyPressed("KEY_rctrl")
        or hpIsPhysicalKeyPressed("KEY_lalt")
        or hpIsPhysicalKeyPressed("KEY_ralt")
end

function HelperPayroll:selectRoleByOffset(offset)
    if not self:isRoleTypePayrollMode() then
        rcLog("Payroll role selector ignored: payrollMode=%s; selector only affects roleType mode", tostring(self.settings.payrollMode))
        self:showRoleMessage("Helper Payroll: role selector only affects roleType mode")
        return
    end

    local _, profileId = self:getActiveProfile()
    local order = self:getWorkerRateOrder(profileId)
    if order == nil or #order == 0 then
        rcWarn("Payroll role selector failed: no worker rates loaded for profile '%s'", tostring(profileId))
        return
    end

    local currentRole = tostring(self.settings.selectedRole or self.settings.fallbackRole or order[1])
    local currentIndex = 1
    for i, roleId in ipairs(order) do
        if roleId == currentRole then
            currentIndex = i
            break
        end
    end

    local newIndex = currentIndex + (tonumber(offset) or 0)
    while newIndex < 1 do
        newIndex = newIndex + #order
    end
    while newIndex > #order do
        newIndex = newIndex - #order
    end

    local newRole = order[newIndex]
    self.settings.selectedRole = newRole
    self:saveSavegameSettings("role-cycle")

    local worker = self:getWorkerRateById(profileId, newRole)
    local workerName = worker ~= nil and worker.name or newRole
    local hourlyRate = worker ~= nil and tonumber(worker.hourlyRate) or 0

    rcLog("Selected payroll role changed: profile=%s role=%s name=%s rate=%.2f", tostring(profileId), tostring(newRole), tostring(workerName), hourlyRate or 0)
    self:showRoleMessage(string.format("Helper Payroll Role: %s (%.2f/hr)", tostring(workerName), hourlyRate or 0))
end

function HelperPayroll:handleRoleInput(actionLabel, offset, actionName, inputValue, callbackState, isAnalog)
    if not hpIsInputPress(inputValue, callbackState) then
        return
    end

    -- HelperProfiles owns the semicolon key family when it is enabled.
    -- HelperPayroll keeps these standalone role controls only when running
    -- without HelperProfiles. This also prevents the report overlay from
    -- consuming semicolon while the HelperProfiles selector is active.
    if self:shouldSuppressStandaloneRoleInputs() then
        return
    end

    -- When the report overlay is open, semicolon pages the report instead of
    -- changing the selected payroll role. Modifier chords are still ignored so
    -- RCTRL+semicolon / RCTRL+P do not trigger the plain-cycle action beneath.
    if actionLabel == "HELPERPAYROLL_CYCLE_ROLE" and self.reportOverlayVisible == true and not hpIsAnyModifierDown() then
        self:nextReportOverlayPage(1)
        return
    end

    -- GIANTS action bindings are not exclusive: KEY_semicolon can still fire
    -- while RCTRL+semicolon is pressed. Keep plain cycling quiet while modifier
    -- chords are active so the role list toggle does not also cycle the role.
    if actionLabel == "HELPERPAYROLL_CYCLE_ROLE" and hpIsAnyModifierDown() then
        return
    end

    local now = hpGetTimeMs()
    local debounceMs = tonumber(self.settings.roleSelectorDebounceMs) or 450
    self._lastRoleSelectorInputAt = self._lastRoleSelectorInputAt or 0

    if now - self._lastRoleSelectorInputAt < debounceMs then
        return
    end

    self._lastRoleSelectorInputAt = now

    if self.settings.logLevel == "debug" then
        rcLog("Input callback fired: %s actionName=%s inputValue=%s callbackState=%s isAnalog=%s", tostring(actionLabel), tostring(actionName), tostring(inputValue), tostring(callbackState), tostring(isAnalog))
    end

    self:selectRoleByOffset(offset)
end

function HelperPayroll:onInputNextRole(actionName, inputValue, callbackState, isAnalog)
    self:handleRoleInput("HELPERPAYROLL_NEXT_ROLE", 1, actionName, inputValue, callbackState, isAnalog)
end

function HelperPayroll:onInputPreviousRole(actionName, inputValue, callbackState, isAnalog)
    self:handleRoleInput("HELPERPAYROLL_PREVIOUS_ROLE", -1, actionName, inputValue, callbackState, isAnalog)
end

function HelperPayroll:onInputCycleRole(actionName, inputValue, callbackState, isAnalog)
    self:handleRoleInput("HELPERPAYROLL_CYCLE_ROLE", 1, actionName, inputValue, callbackState, isAnalog)
end

function HelperPayroll:toggleRoleList()
    if not self:isRoleTypePayrollMode() then
        rcLog("Payroll role list ignored: payrollMode=%s; role list only affects roleType mode", tostring(self.settings.payrollMode))
        self:showRoleMessage("Helper Payroll: role list only affects roleType mode")
        return
    end

    self.roleListVisible = not self.roleListVisible
    if self.roleListVisible == true then
        self.reportOverlayVisible = false
    end
    rcLog("Payroll role list %s", self.roleListVisible and "opened" or "closed")
end

function HelperPayroll:toggleReportOverlay()
    self.reportOverlayVisible = not self.reportOverlayVisible
    if self.reportOverlayVisible == true then
        self.roleListVisible = false
        self.reportOverlayPage = self.reportOverlayPage or 1
    end
    rcLog("Payroll report overlay %s", self.reportOverlayVisible and "opened" or "closed")
end

function HelperPayroll:nextReportOverlayPage(offset)
    local maxPage = tonumber(self.reportOverlayMaxPage) or 4
    local page = math.floor(tonumber(self.reportOverlayPage) or 1) + (tonumber(offset) or 1)
    while page < 1 do page = page + maxPage end
    while page > maxPage do page = page - maxPage end
    self.reportOverlayPage = page
    rcLog("Payroll report overlay page changed: page=%d/%d", page, maxPage)
end

function HelperPayroll:onInputToggleReportOverlay(actionName, inputValue, callbackState, isAnalog)
    if not hpIsInputPress(inputValue, callbackState) then
        return
    end

    local now = hpGetTimeMs()
    local debounceMs = tonumber(self.settings.roleSelectorDebounceMs) or 450
    self._lastReportOverlayToggleAt = self._lastReportOverlayToggleAt or 0
    if now - self._lastReportOverlayToggleAt < debounceMs then
        return
    end
    self._lastReportOverlayToggleAt = now

    self:toggleReportOverlay()
end

function HelperPayroll:onInputToggleRoleList(actionName, inputValue, callbackState, isAnalog)
    if not hpIsInputPress(inputValue, callbackState) then
        return
    end

    if self:shouldSuppressStandaloneRoleInputs() then
        return
    end

    local now = hpGetTimeMs()
    local debounceMs = tonumber(self.settings.roleSelectorDebounceMs) or 450
    self._lastRoleListToggleAt = self._lastRoleListToggleAt or 0
    if now - self._lastRoleListToggleAt < debounceMs then
        return
    end
    self._lastRoleListToggleAt = now

    self:toggleRoleList()
end

function HelperPayroll:showRoleMessage(message)
    local text = tostring(message or "")
    if text == "" then
        return
    end

    -- Use our own lightweight draw overlay. The base-game notification/blinking-warning
    -- paths can be queued or swallowed depending on HUD context, so they are not
    -- reliable for rapid role cycling.
    self.roleFlashText = text
    self.roleFlashTime = 2.0

    if self.settings ~= nil and self.settings.logLevel == "debug" then
        rcLog("Role selector overlay message: %s", text)
    end
end

local function hpSafeSetTextAlign(a)
    if _G.setTextAlignment ~= nil then
        setTextAlignment(a)
    end
end

local function hpSafeRenderText(x, y, size, txt)
    if _G.renderText ~= nil then
        renderText(x, y, size, txt)
    end
end

local function hpSafeSetTextColor(r, g, b, a)
    if _G.setTextColor ~= nil then
        setTextColor(r, g, b, a)
    end
end

local function hpSafeGetTextColor()
    if _G.getTextColor ~= nil then
        return getTextColor()
    end
    return 1, 1, 1, 1
end

local function hpSafeRect(x, y, w, h, r, g, b, a)
    if _G.drawFilledRect ~= nil then
        drawFilledRect(x, y, w, h, r, g, b, a)
    end
end

local function hpDrawOutline(x, y, w, h, a)
    local t = 0.0018
    hpSafeRect(x, y, w, t, 1, 1, 1, a)
    hpSafeRect(x, y + h - t, w, t, 1, 1, 1, a)
    hpSafeRect(x, y, t, h, 1, 1, 1, a)
    hpSafeRect(x + w - t, y, t, h, 1, 1, 1, a)
end

local function hpShadowedText(x, y, size, text, shadow)
    if shadow ~= true then
        hpSafeRenderText(x, y, size, text)
        return
    end

    local oldR, oldG, oldB, oldA = hpSafeGetTextColor()
    hpSafeSetTextColor(0, 0, 0, math.min(1, (tonumber(oldA) or 1) * 0.75))
    hpSafeRenderText(x + 0.0012, y - 0.0012, size, text)
    hpSafeSetTextColor(oldR, oldG, oldB, oldA)
    hpSafeRenderText(x, y, size, text)
end

local function hpPlaceAnchored(anchor, x, y, w, h)
    anchor = string.upper(tostring(anchor or "TR"))
    if anchor == "TR" then
        return x - w, y - h
    elseif anchor == "TL" then
        return x, y - h
    elseif anchor == "BR" then
        return x - w, y
    end
    return x, y
end

local function hpEllipsize(text, maxLen)
    text = tostring(text or "")
    maxLen = tonumber(maxLen) or 48
    if string.len(text) <= maxLen then
        return text
    end
    return string.sub(text, 1, math.max(1, maxLen - 3)) .. "..."
end

local function hpClamp(value, minValue, maxValue, fallback)
    local n = tonumber(value)
    if n == nil then
        n = tonumber(fallback) or minValue
    end
    if n < minValue then
        return minValue
    end
    if n > maxValue then
        return maxValue
    end
    return n
end

local function hpFmtMoney(value)
    return string.format("%.2f", tonumber(value) or 0)
end

local function hpFmtHours(value)
    return string.format("%.3f", tonumber(value) or 0)
end

local function hpFmtRate(value)
    return string.format("%.2f", tonumber(value) or 0)
end

local function hpBoolArg(value)
    local v = string.lower(tostring(value or ""))
    if v == "on" or v == "true" or v == "1" or v == "yes" then
        return true
    elseif v == "off" or v == "false" or v == "0" or v == "no" then
        return false
    end
    return nil
end

local function hpSetRoleListDefaults()
    HelperPayroll.roleListUi.anchor = "TR"
    HelperPayroll.roleListUi.x = 0.985
    HelperPayroll.roleListUi.y = 0.900
    HelperPayroll.roleListUi.scale = 1.0
    HelperPayroll.roleListUi.opacity = 0.40
    HelperPayroll.roleListUi.pad = 0.006
    HelperPayroll.roleListUi.rowGap = 0.006
    HelperPayroll.roleListUi.fontSize = 0.014
    HelperPayroll.roleListUi.width = 0.400
    HelperPayroll.roleListUi.maxRows = 10
    HelperPayroll.roleListUi.bgEnabled = true
    HelperPayroll.roleListUi.outline = false
    HelperPayroll.roleListUi.shadow = false
end

function HelperPayroll:drawRoleList()
    if self.roleListVisible ~= true then
        return
    end
    if not self:isRoleTypePayrollMode() then
        return
    end

    local _, profileId = self:getActiveProfile()
    local order = self:getWorkerRateOrder(profileId)
    if order == nil or #order == 0 then
        return
    end

    local ui = self.roleListUi or {}
    local scale = tonumber(ui.scale) or 1.0
    local fs = (tonumber(ui.fontSize) or 0.014) * scale
    local line = fs + ((tonumber(ui.rowGap) or 0.006) * scale)
    local pad = (tonumber(ui.pad) or 0.006) * scale
    local width = (tonumber(ui.width) or 0.400) * scale
    local rows = math.min(#order, tonumber(ui.maxRows) or 10)
    local height = (pad * 2) + (line * (rows + 2))
    local px, py = hpPlaceAnchored(ui.anchor or "TR", tonumber(ui.x) or 0.985, tonumber(ui.y) or 0.900, width, height)

    local oldR, oldG, oldB, oldA = hpSafeGetTextColor()

    if ui.bgEnabled ~= false then
        hpSafeRect(px, py, width, height, 0, 0, 0, tonumber(ui.opacity) or 0.40)
        if ui.outline == true then
            hpDrawOutline(px, py, width, height, math.min(1, (tonumber(ui.opacity) or 0.40) + 0.15))
        end
    end

    local selectedRole = tostring(self.settings.selectedRole or self.settings.fallbackRole or "")
    local selectedName = selectedRole
    for _, roleId in ipairs(order) do
        if tostring(roleId) == selectedRole then
            local worker = self:getWorkerRateById(profileId, roleId)
            if worker ~= nil and worker.name ~= nil then
                selectedName = tostring(worker.name)
            end
            break
        end
    end

    local x = px + pad
    local y = py + height - pad - fs
    local header = string.format("Mode: roleType | Roles shown: %d | Selected: %s", rows, selectedName)

    hpSafeSetTextColor(1, 1, 1, 1)
    hpShadowedText(x, y, fs, header, ui.shadow == true)
    y = y - line

    hpSafeSetTextColor(0.72, 0.82, 0.95, 1)
    hpShadowedText(x, y, fs * 0.82, "; cycle role | RCTRL+; hide list", ui.shadow == true)
    y = y - line

    for idx = 1, rows do
        local roleId = order[idx]
        local worker = self:getWorkerRateById(profileId, roleId)
        local name = worker ~= nil and worker.name or roleId
        local rate = worker ~= nil and tonumber(worker.hourlyRate) or 0
        local selected = tostring(roleId) == selectedRole
        local marker = selected and "» sel" or ""
        local lineText = string.format("%02d  %s  %.2f/hr%s", idx, hpEllipsize(name, 30), rate or 0, marker ~= "" and ("  " .. marker) or "")

        if selected then
            hpSafeSetTextColor(1.00, 0.95, 0.65, 1)
        else
            hpSafeSetTextColor(0.85, 0.95, 0.85, 1)
        end
        hpShadowedText(x, y, fs, lineText, ui.shadow == true)
        y = y - line
    end

    hpSafeSetTextColor(oldR, oldG, oldB, oldA)
end

function HelperPayroll:getCurrentRoleDisplay()
    local _, profileId = self:getActiveProfile()
    local roleId = tostring(self.settings.selectedRole or self.settings.fallbackRole or "standard")
    local worker = self:getWorkerRateById(profileId, roleId)
    local name = worker ~= nil and worker.name or roleId
    local rate = worker ~= nil and tonumber(worker.hourlyRate) or 0
    return tostring(name), roleId, rate, tostring(profileId)
end

function HelperPayroll:buildReportOverlayLines()
    if self.ledger == nil or self.ledger.index == nil then
        self:loadLedgerIndex()
    end

    local idx = self.ledger ~= nil and self.ledger.index or self:createEmptyLedgerIndex()
    local summary = idx.summary or {}
    local periodId = self:getLedgerPeriodId(self:getGameDateKey())
    local period = idx.periods ~= nil and idx.periods[periodId] or nil
    local roleName, roleId, roleRate = self:getCurrentRoleDisplay()
    local page = math.floor(tonumber(self.reportOverlayPage) or 1)
    if page < 1 then page = 1 end
    if page > 4 then page = 4 end

    local lines = {}
    if page == 1 then
        table.insert(lines, "HelperPayroll Report  [1/4] Summary")
        table.insert(lines, string.format("Savegame: %s", tostring(self.persistence ~= nil and self.persistence.savegameName or "unknown")))
        table.insert(lines, string.format("Current period: %s", tostring(periodId)))
        table.insert(lines, string.format("Total charged: %s", hpFmtMoney(summary.charged)))
        table.insert(lines, string.format("Jobs: %d | Hours: %s | Minimum jobs: %d", tonumber(summary.jobs) or 0, hpFmtHours(summary.hours), tonumber(summary.minimumJobs) or 0))
        table.insert(lines, string.format("Labour: %s | Calculated: %s", hpFmtMoney(summary.labour), hpFmtMoney(summary.calculated)))
        table.insert(lines, string.format("Selected role: %s (%s/hr)", tostring(roleName), hpFmtRate(roleRate)))
    elseif page == 2 then
        table.insert(lines, "HelperPayroll Report  [2/4] Current Period")
        table.insert(lines, string.format("Period: %s", tostring(periodId)))
        if period == nil then
            table.insert(lines, "No payroll entries recorded for this period yet.")
        else
            table.insert(lines, string.format("Jobs: %d | Payments: %d", tonumber(period.jobs) or 0, tonumber(period.payments) or 0))
            table.insert(lines, string.format("Hours: %s", hpFmtHours(period.hours)))
            table.insert(lines, string.format("Labour: %s", hpFmtMoney(period.labour)))
            table.insert(lines, string.format("Calculated: %s", hpFmtMoney(period.calculated)))
            table.insert(lines, string.format("Charged: %s", hpFmtMoney(period.charged)))
        end
    elseif page == 3 then
        table.insert(lines, "HelperPayroll Report  [3/4] Recent Jobs")
        local entries = self:loadPeriodLedger(periodId)
        local count = #(entries or {})
        if count <= 0 then
            table.insert(lines, string.format("No entries in %s yet.", tostring(periodId)))
        else
            local first = math.max(1, count - 7)
            for i = first, count do
                local e = entries[i]
                if e ~= nil then
                    table.insert(lines, string.format("%03d  %s  %sh  %s", i, hpEllipsize(e.role or e.helper or e.workerRate or "Worker", 24), hpFmtHours(e.elapsedHours), hpFmtMoney(e.charged)))
                end
            end
        end
    else
        table.insert(lines, "HelperPayroll Report  [4/4] Role Totals")
        if #(idx.roleOrder or {}) == 0 then
            table.insert(lines, "No role totals recorded yet.")
        else
            local shown = 0
            for _, id in ipairs(idx.roleOrder or {}) do
                local r = idx.roles[id]
                if r ~= nil and shown < 8 then
                    shown = shown + 1
                    table.insert(lines, string.format("%s  %d jobs  %sh  %s", hpEllipsize(r.name or id, 20), tonumber(r.jobs) or 0, hpFmtHours(r.hours), hpFmtMoney(r.charged)))
                end
            end
        end
    end

    table.insert(lines, "; next page | RCTRL+P close")
    return lines
end

function HelperPayroll:drawReportOverlay()
    if self.reportOverlayVisible ~= true then
        return
    end

    local lines = self:buildReportOverlayLines()
    if lines == nil or #lines == 0 then
        return
    end

    local ui = self.roleListUi or {}
    local scale = tonumber(ui.scale) or 1.0
    local fs = (tonumber(ui.fontSize) or 0.014) * scale
    local line = fs + ((tonumber(ui.rowGap) or 0.006) * scale)
    local pad = (tonumber(ui.pad) or 0.006) * scale
    local width = (tonumber(ui.width) or 0.400) * scale
    local rows = math.min(#lines, tonumber(ui.maxRows) or 10)
    local height = (pad * 2) + (line * rows)
    local px, py = hpPlaceAnchored(ui.anchor or "TR", tonumber(ui.x) or 0.985, tonumber(ui.y) or 0.900, width, height)

    local oldR, oldG, oldB, oldA = hpSafeGetTextColor()

    if ui.bgEnabled ~= false then
        hpSafeRect(px, py, width, height, 0, 0, 0, tonumber(ui.opacity) or 0.40)
        if ui.outline == true then
            hpDrawOutline(px, py, width, height, math.min(1, (tonumber(ui.opacity) or 0.40) + 0.15))
        end
    end

    local x = px + pad
    local y = py + height - pad - fs
    for i = 1, rows do
        if i == 1 then
            hpSafeSetTextColor(1, 1, 1, 1)
        elseif i == rows then
            hpSafeSetTextColor(0.72, 0.82, 0.95, 1)
        else
            hpSafeSetTextColor(0.85, 0.95, 0.85, 1)
        end
        hpShadowedText(x, y, fs, tostring(lines[i]), ui.shadow == true)
        y = y - line
    end

    hpSafeSetTextColor(oldR, oldG, oldB, oldA)
end

function HelperPayroll:drawRoleFlash()
    if self.roleFlashTime == nil or self.roleFlashTime <= 0 then
        return
    end
    local text = self.roleFlashText
    if text == nil or text == "" then
        return
    end

    local oldR, oldG, oldB, oldA = hpSafeGetTextColor()

    if _G.RenderText ~= nil and RenderText.ALIGN_CENTER ~= nil then
        hpSafeSetTextAlign(RenderText.ALIGN_CENTER)
    end

    -- Simple top-centre text with a shadow. This mirrors the reliable HelperProfiles
    -- overlay style without introducing a full UI module yet.
    hpSafeSetTextColor(0, 0, 0, 0.72)
    hpSafeRenderText(0.5015, 0.9385, 0.021, text)
    hpSafeSetTextColor(1, 1, 1, 1)
    hpSafeRenderText(0.5, 0.94, 0.021, text)

    if _G.RenderText ~= nil and RenderText.ALIGN_LEFT ~= nil then
        hpSafeSetTextAlign(RenderText.ALIGN_LEFT)
    end

    hpSafeSetTextColor(oldR, oldG, oldB, oldA)
end

local function hpSetActionEventDisplay(actionEventId, visible)
    if actionEventId == nil or g_inputBinding == nil then
        return
    end
    if g_inputBinding.setActionEventTextPriority ~= nil then
        g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_VERY_LOW)
    end
    if g_inputBinding.setActionEventTextVisibility ~= nil then
        g_inputBinding:setActionEventTextVisibility(actionEventId, visible ~= false)
    end
    if g_inputBinding.setActionEventActive ~= nil then
        g_inputBinding:setActionEventActive(actionEventId, true)
    end
end

function HelperPayroll:registerInputActions()
    -- Deprecated loadMap-level registration retained as a no-op marker.
    -- FS input callbacks are registered through PlayerInputComponent and Vehicle action-event contexts below.
    rcLog("Input action registration handled by player/vehicle action-event hooks")
end

function HelperPayroll:removeInputActions()
    if g_inputBinding ~= nil and self.actionEventIds ~= nil then
        for _, actionEventId in ipairs(self.actionEventIds) do
            if actionEventId ~= nil and g_inputBinding.removeActionEvent ~= nil then
                pcall(function()
                    g_inputBinding:removeActionEvent(actionEventId)
                end)
            end
        end
    end

    self.actionEventIds = {}
    self.inputActionsRegistered = false
end

function HelperPayroll:registerGlobalPlayerInputActions()
    if g_inputBinding == nil or InputAction == nil then
        rcWarn("Input actions not registered for player; g_inputBinding or InputAction is not available")
        return
    end

    if self.playerInputActionsRegistered then
        return
    end

    self.actionEventIds = self.actionEventIds or {}

    local function registerOne(fieldName, inputAction, callback, label)
        if inputAction == nil then
            rcWarn("Input action %s not available; check modDesc actions/inputBinding", tostring(label))
            return
        end
        local ok, actionEventId = g_inputBinding:registerActionEvent(inputAction, self, callback, false, true, false, true)
        if ok and actionEventId ~= nil then
            self[fieldName] = actionEventId
            table.insert(self.actionEventIds, actionEventId)
            hpSetActionEventDisplay(actionEventId, true)
            rcLog("Registered input action: %s context=player actionEventId=%s", tostring(label), tostring(actionEventId))
        else
            rcWarn("Failed to register input action %s context=player", tostring(label))
        end
    end

    local suppressStandaloneRoleInputs = self:shouldSuppressStandaloneRoleInputs()
    if suppressStandaloneRoleInputs then
        self.roleListVisible = false
        if not self._loggedStandaloneRoleInputSuppressionPlayer then
            rcLog("Standalone role selector inputs suppressed: context=player reason=HelperProfiles-loaded semicolonOwner=HelperProfiles")
            self._loggedStandaloneRoleInputSuppressionPlayer = true
        end
    else
        registerOne("_playerCycleRoleActionEventId", InputAction.HELPERPAYROLL_CYCLE_ROLE, self.onInputCycleRole, "HELPERPAYROLL_CYCLE_ROLE")
        registerOne("_playerToggleRoleListActionEventId", InputAction.HELPERPAYROLL_TOGGLE_ROLE_LIST, self.onInputToggleRoleList, "HELPERPAYROLL_TOGGLE_ROLE_LIST")
    end
    registerOne("_playerToggleReportOverlayActionEventId", InputAction.HELPERPAYROLL_TOGGLE_REPORT_OVERLAY, self.onInputToggleReportOverlay, "HELPERPAYROLL_TOGGLE_REPORT_OVERLAY")
    registerOne("_playerToggleManagementMenuActionEventId", InputAction.HELPERPAYROLL_TOGGLE_MANAGEMENT_MENU, self.onInputToggleManagementMenu, "HELPERPAYROLL_TOGGLE_MANAGEMENT_MENU")

    self.playerInputActionsRegistered = true
end

function HelperPayroll:removeGlobalPlayerInputActions()
    if g_inputBinding ~= nil then
        if self._playerCycleRoleActionEventId ~= nil then
            g_inputBinding:removeActionEvent(self._playerCycleRoleActionEventId)
            self._playerCycleRoleActionEventId = nil
        end
        if self._playerToggleRoleListActionEventId ~= nil then
            g_inputBinding:removeActionEvent(self._playerToggleRoleListActionEventId)
            self._playerToggleRoleListActionEventId = nil
        end
        if self._playerToggleReportOverlayActionEventId ~= nil then
            g_inputBinding:removeActionEvent(self._playerToggleReportOverlayActionEventId)
            self._playerToggleReportOverlayActionEventId = nil
        end
        if self._playerNextRoleActionEventId ~= nil then
            g_inputBinding:removeActionEvent(self._playerNextRoleActionEventId)
            self._playerNextRoleActionEventId = nil
        end
        if self._playerPreviousRoleActionEventId ~= nil then
            g_inputBinding:removeActionEvent(self._playerPreviousRoleActionEventId)
            self._playerPreviousRoleActionEventId = nil
        end
    end
    self.playerInputActionsRegistered = false
end

function HelperPayroll:registerVehicleInputActions(vehicle, isActiveForInput)
    if not isActiveForInput or vehicle == nil or vehicle.addActionEvent == nil or InputAction == nil then
        return
    end

    vehicle.spec_helperPayroll = vehicle.spec_helperPayroll or {}
    local spec = vehicle.spec_helperPayroll
    spec.actionEvents = spec.actionEvents or {}

    if vehicle.clearActionEventsTable ~= nil then
        vehicle:clearActionEventsTable(spec.actionEvents)
    end

    local function addOne(inputAction, callback, label)
        if inputAction == nil then
            rcWarn("Input action %s not available for vehicle context", tostring(label))
            return
        end
        local _, actionEventId = vehicle:addActionEvent(spec.actionEvents, inputAction, self, callback, false, true, false, true)
        if actionEventId ~= nil then
            hpSetActionEventDisplay(actionEventId, true)
            if label == "HELPERPAYROLL_CYCLE_ROLE" and not self._loggedVehicleCycleRoleRegistration then
                rcLog("Registered input action: %s context=vehicle actionEventId=%s", tostring(label), tostring(actionEventId))
                self._loggedVehicleCycleRoleRegistration = true
            end
        else
            rcWarn("Failed to register input action %s context=vehicle", tostring(label))
        end
    end

    local suppressStandaloneRoleInputs = self:shouldSuppressStandaloneRoleInputs()
    if suppressStandaloneRoleInputs then
        self.roleListVisible = false
        if not self._loggedStandaloneRoleInputSuppressionVehicle then
            rcLog("Standalone role selector inputs suppressed: context=vehicle reason=HelperProfiles-loaded semicolonOwner=HelperProfiles")
            self._loggedStandaloneRoleInputSuppressionVehicle = true
        end
    else
        addOne(InputAction.HELPERPAYROLL_CYCLE_ROLE, self.onInputCycleRole, "HELPERPAYROLL_CYCLE_ROLE")
        addOne(InputAction.HELPERPAYROLL_TOGGLE_ROLE_LIST, self.onInputToggleRoleList, "HELPERPAYROLL_TOGGLE_ROLE_LIST")
    end
    addOne(InputAction.HELPERPAYROLL_TOGGLE_REPORT_OVERLAY, self.onInputToggleReportOverlay, "HELPERPAYROLL_TOGGLE_REPORT_OVERLAY")
    addOne(InputAction.HELPERPAYROLL_TOGGLE_MANAGEMENT_MENU, self.onInputToggleManagementMenu, "HELPERPAYROLL_TOGGLE_MANAGEMENT_MENU")
end

function HelperPayroll:removeVehicleInputActions(vehicle)
    if vehicle ~= nil and vehicle.spec_helperPayroll ~= nil and vehicle.spec_helperPayroll.actionEvents ~= nil and vehicle.clearActionEventsTable ~= nil then
        vehicle:clearActionEventsTable(vehicle.spec_helperPayroll.actionEvents)
    end
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


function HelperPayroll:diagnosticShouldInspectKey(key)
    if key == nil then
        return false
    end

    local lowerKey = string.lower(tostring(key))
    return string.find(lowerKey, "helper") ~= nil
        or string.find(lowerKey, "profile") ~= nil
        or string.find(lowerKey, "preset") ~= nil
        or string.find(lowerKey, "slot") ~= nil
        or string.find(lowerKey, "worker") ~= nil
        or string.find(lowerKey, "appearance") ~= nil
        or string.find(lowerKey, "character") ~= nil
        or string.find(lowerKey, "vehicle") ~= nil
end

function HelperPayroll:diagnosticValueToString(value)
    local valueType = type(value)

    if valueType == "nil" then
        return "nil"
    end

    if valueType == "string" or valueType == "number" or valueType == "boolean" then
        return tostring(value)
    end

    if valueType == "table" then
        local parts = { tostring(value) }
        if value.className ~= nil then table.insert(parts, "className=" .. tostring(value.className)) end
        if value.typeName ~= nil then table.insert(parts, "typeName=" .. tostring(value.typeName)) end
        if value.name ~= nil then table.insert(parts, "name=" .. tostring(value.name)) end
        if value.configFileName ~= nil then table.insert(parts, "configFileName=" .. tostring(value.configFileName)) end
        return table.concat(parts, " ")
    end

    return valueType .. ":" .. tostring(value)
end

function HelperPayroll:diagnosticGetObjectName(object)
    if object == nil then
        return nil
    end

    if object.getName ~= nil then
        local ok, result = pcall(function() return object:getName() end)
        if ok and result ~= nil then
            return tostring(result)
        end
    end

    if object.name ~= nil then
        return tostring(object.name)
    end

    return nil
end

function HelperPayroll:diagnosticScanObject(label, object, depth, visited, printedRef)
    if object == nil or type(object) ~= "table" then
        return 0
    end

    visited = visited or {}
    if visited[object] then
        return 0
    end
    visited[object] = true

    local limit = tonumber(self.settings.helperProfilesDiagnosticLimit) or 12
    local printed = printedRef or { count = 0 }

    local objectName = self:diagnosticGetObjectName(object)
    if objectName ~= nil then
        rcLog("HelperProfiles diagnostic object: %s object=%s name=%s", tostring(label), tostring(object), tostring(objectName))
    else
        rcLog("HelperProfiles diagnostic object: %s object=%s", tostring(label), tostring(object))
    end

    local ok, err = pcall(function()
        for key, value in pairs(object) do
            if printed.count >= limit then
                break
            end

            if self:diagnosticShouldInspectKey(key) then
                printed.count = printed.count + 1
                rcLog(
                    "HelperProfiles diagnostic candidate: %s.%s type=%s value=%s",
                    tostring(label),
                    tostring(key),
                    tostring(type(value)),
                    tostring(self:diagnosticValueToString(value))
                )
            end
        end
    end)

    if not ok then
        rcWarn("HelperProfiles diagnostic scan failed for %s: %s", tostring(label), tostring(err))
    end

    return printed.count
end

function HelperPayroll:diagnosticScanGlobals()
    if self.helperProfilesGlobalScanDone then
        return
    end
    self.helperProfilesGlobalScanDone = true

    if not self.settings.helperProfilesDiagnostics then
        return
    end

    if _G == nil then
        rcWarn("HelperProfiles diagnostic: _G is not available; global scan skipped")
        return
    end

    local matches = {}
    local ok, err = pcall(function()
        for key, value in pairs(_G) do
            local lowerKey = string.lower(tostring(key))
            if string.find(lowerKey, "helperprofile") ~= nil
                or string.find(lowerKey, "helper_profiles") ~= nil
                or string.find(lowerKey, "workerappearance") ~= nil
                or string.find(lowerKey, "helperprofiles") ~= nil then
                table.insert(matches, { key = tostring(key), value = value, valueType = type(value) })
            end
        end
    end)

    if not ok then
        rcWarn("HelperProfiles diagnostic global scan failed: %s", tostring(err))
        return
    end

    if #matches == 0 then
        rcLog("HelperProfiles diagnostic global scan: no obvious global HelperProfiles tables found")
        return
    end

    rcLog("HelperProfiles diagnostic global scan: matches=%d", #matches)
    for _, match in ipairs(matches) do
        rcLog("HelperProfiles diagnostic global: %s type=%s value=%s", tostring(match.key), tostring(match.valueType), tostring(self:diagnosticValueToString(match.value)))
        if type(match.value) == "table" then
            self:diagnosticScanObject("_G." .. tostring(match.key), match.value, 1, {}, { count = 0 })
        end
    end
end

function HelperPayroll:diagnosticScanAIJobForHelperProfiles(job, tracked)
    if not self.settings.helperProfilesDiagnostics then
        return
    end

    self.helperProfilesJobDiagnosticCount = self.helperProfilesJobDiagnosticCount or 0
    if self.helperProfilesJobDiagnosticCount >= (self.helperProfilesJobDiagnosticLimit or 6) then
        return
    end
    self.helperProfilesJobDiagnosticCount = self.helperProfilesJobDiagnosticCount + 1

    local seq = tracked ~= nil and tracked.sequence or "?"
    local jobType = self:getAIJobDebugName(job)
    rcLog("HelperProfiles diagnostic start: seq=%s jobType=%s job=%s", tostring(seq), tostring(jobType), tostring(job))

    self:diagnosticScanGlobals()

    local printed = { count = 0 }
    local visited = {}
    self:diagnosticScanObject("job", job, 1, visited, printed)

    local candidateFields = {
        "vehicle", "vehicleToUse", "vehicleInUse", "vehicleParameter", "vehicleParameter1", "vehicleParameter2",
        "task", "vehicleTask", "driveTask", "fieldWorkTask", "object", "target", "helper", "worker", "character", "enterable"
    }

    for _, fieldName in ipairs(candidateFields) do
        if job ~= nil and type(job) == "table" and job[fieldName] ~= nil and type(job[fieldName]) == "table" then
            self:diagnosticScanObject("job." .. tostring(fieldName), job[fieldName], 1, visited, printed)
        end
    end

    if job ~= nil and job.getVehicle ~= nil then
        local ok, vehicle = pcall(function() return job:getVehicle() end)
        if ok and vehicle ~= nil and type(vehicle) == "table" then
            self:diagnosticScanObject("job:getVehicle()", vehicle, 1, visited, printed)
        end
    end

    rcLog("HelperProfiles diagnostic end: seq=%s candidatesLogged=%d", tostring(seq), tonumber(printed.count) or 0)
end

function HelperPayroll:helperIndexToSlot(helperIndex)
    local index = tonumber(helperIndex)

    if index == nil then
        return nil
    end

    index = math.floor(index)

    if index < 1 or index > 10 then
        return nil
    end

    -- FS helper slots are A-J. Diagnostics confirmed job.helperIndex=2 maps to helper B.
    return string.char(string.byte("A") + index - 1)
end

function HelperPayroll:detectHelperSlotForJob(job, tracked)
    if tracked ~= nil and tracked.helperSlot ~= nil and tracked.helperSlot ~= "" and tracked.helperSlot ~= "unassigned" then
        return tracked.helperSlot, "tracked"
    end

    if job ~= nil and type(job) == "table" and job.helperIndex ~= nil then
        local slot = self:helperIndexToSlot(job.helperIndex)

        if slot ~= nil then
            return slot, "job.helperIndex"
        end

        rcLog("[WARN] AI job helperIndex could not be mapped to helper slot: helperIndex=%s", tostring(job.helperIndex))
    end

    if self.settings.defaultHelperSlot ~= nil and self.settings.defaultHelperSlot ~= "" then
        return self.settings.defaultHelperSlot, "config"
    end

    return nil, "unassigned"
end

function HelperPayroll:isHelperSlotPayrollMode()
    return string.lower(tostring(self.settings.payrollMode or "roleType")) == "helperslot"
end

function HelperPayroll:isRoleTypePayrollMode()
    local mode = string.lower(tostring(self.settings.payrollMode or "roleType"))
    return mode == "roletype" or mode == "selectedrole" or mode == "defaultrole"
end

-- ===== HelperProfiles integration helpers ==================================

-- The standalone role selector deliberately uses the same semicolon family as
-- HelperProfiles. When HelperProfiles is loaded, it owns those controls and
-- HelperPayroll does not register/respond to its vanilla role cycle/list actions.
-- Report and management shortcuts remain available.
function HelperPayroll:shouldSuppressStandaloneRoleInputs()
    if self.isHelperProfilesModLoaded == nil then
        return false
    end

    local ok, modLoaded = pcall(self.isHelperProfilesModLoaded, self)
    return ok and modLoaded == true
end

-- HelperProfiles integration is optional. HelperPayroll detects the enabled
-- mod through the engine and consumes a read-only API published on the shared
-- current mission. No HelperProfiles file is used as proof that the mod is
-- active, avoiding stale save-slot data from previous saves.
function HelperPayroll:isHelperProfilesModLoaded()
    local names = {
        "FS25_HelperProfiles",
        "HelperProfiles"
    }

    if type(g_modIsLoaded) == "table" then
        for _, name in ipairs(names) do
            if g_modIsLoaded[name] == true then
                return true, "g_modIsLoaded"
            end
        end
    end

    if g_modManager ~= nil then
        if type(g_modManager.getModByName) == "function" then
            for _, name in ipairs(names) do
                local ok, mod = pcall(g_modManager.getModByName, g_modManager, name)
                if ok and mod ~= nil then
                    if mod.isLoaded == true or mod.isActive == true or mod.isSelected == true then
                        return true, "g_modManager"
                    end
                end
            end
        end

        local mods = g_modManager.mods
        if type(mods) == "table" then
            for _, mod in pairs(mods) do
                if type(mod) == "table" then
                    local name = tostring(mod.modName or mod.name or mod.id or "")
                    if name == "FS25_HelperProfiles" or name == "HelperProfiles" then
                        if mod.isLoaded == true or mod.isActive == true or mod.isSelected == true then
                            return true, "g_modManager.mods"
                        end
                    end
                end
            end
        end
    end

    local api = self:getHelperProfilesAPI(false)
    if api ~= nil then
        return true, "shared-api"
    end

    return false, "none"
end

function HelperPayroll:getHelperProfilesAPI(validateVersion)
    local mission = g_currentMission
    if mission == nil then return nil end

    local api = mission.fs25HelperProfilesAPI or mission.helperProfilesAPI
    if type(api) ~= "table" then return nil end

    if validateVersion ~= false then
        local version = tonumber(api.apiVersion)
        if version == nil or version < 1 then
            return nil
        end
    end

    return api
end

function HelperPayroll:callHelperProfilesAPI(methodName, ...)
    local api = self:getHelperProfilesAPI(true)
    if api == nil then
        return false, nil, "api-unavailable"
    end

    local fn = api[methodName]
    if type(fn) ~= "function" then
        return false, nil, "method-unavailable"
    end

    local ok, result = pcall(fn, api, ...)
    if not ok then
        rcWarn("HelperProfiles API call failed: method=%s error=%s", tostring(methodName), tostring(result))
        return false, nil, tostring(result)
    end

    return true, result, nil
end

function HelperPayroll:isHelperProfilesAvailable()
    local modLoaded = self:isHelperProfilesModLoaded()
    return modLoaded == true and self:getHelperProfilesAPI(true) ~= nil
end

function HelperPayroll:slotToHelperProfilesIndex(slot)
    if slot == nil then return nil end
    local s = string.upper(tostring(slot or ""))
    if #s ~= 1 then return nil end
    local idx = string.byte(s) - string.byte("A") + 1
    if idx < 1 or idx > 10 then return nil end
    return idx
end

function HelperPayroll:getHelperProfilesSlotInfo(slot)
    local idx = self:slotToHelperProfilesIndex(slot)
    if idx == nil then return nil end

    local ok, data = self:callHelperProfilesAPI("getSlotData", string.upper(tostring(slot)))
    if not ok or type(data) ~= "table" then
        return nil
    end

    return {
        slot = tostring(data.slot or string.upper(tostring(slot))),
        index = tonumber(data.index) or idx,
        helper = nil,
        identityId = data.identityId ~= nil and tostring(data.identityId) or nil,
        identitySource = data.identitySource ~= nil and tostring(data.identitySource) or nil,
        baseName = data.baseName,
        displayName = tostring(data.displayName or data.baseName or ("Helper " .. string.upper(tostring(slot)))),
        appearanceLabel = data.appearanceLabel,
        presetId = data.presetId,
        category = data.category,
        inUse = data.inUse == true,
        selected = data.selected == true,
        selectedIndex = data.selectedIndex,
        source = tostring(data.source or "shared-api")
    }
end

function HelperPayroll:getHelperProfilesStatus()
    local modLoaded, detectionSource = self:isHelperProfilesModLoaded()
    local api = self:getHelperProfilesAPI(true)
    local apiAvailable = api ~= nil

    local apiStatus = nil
    if apiAvailable then
        local ok, result = self:callHelperProfilesAPI("getStatus")
        if ok and type(result) == "table" then
            apiStatus = result
        end
    end

    local selectedSlot = apiStatus ~= nil and apiStatus.selectedSlot or nil
    local selectedName = apiStatus ~= nil and apiStatus.selectedName or nil
    local selectedIndex = apiStatus ~= nil and tonumber(apiStatus.selectedIndex) or nil
    local profileCount = apiStatus ~= nil and tonumber(apiStatus.profileCount) or 0

    if selectedSlot == nil and apiAvailable then
        local ok, result = self:callHelperProfilesAPI("getSelectedSlot")
        if ok then selectedSlot = result end
    end
    if selectedName == nil and apiAvailable then
        local ok, result = self:callHelperProfilesAPI("getSelectedDisplayName")
        if ok then selectedName = result end
    end

    local source = "none"
    if apiAvailable then
        source = "shared-api"
    elseif modLoaded then
        source = "mod-loaded-api-unavailable"
    end

    self.helperProfilesBridge = self.helperProfilesBridge or {}
    self.helperProfilesBridge.modLoaded = modLoaded == true
    self.helperProfilesBridge.apiAvailable = apiAvailable
    self.helperProfilesBridge.apiVersion = apiAvailable and tonumber(api.apiVersion) or nil
    self.helperProfilesBridge.modVersion = apiAvailable and tostring(api.modVersion or "") or nil
    self.helperProfilesBridge.source = source
    self.helperProfilesBridge.detectionSource = detectionSource

    return {
        available = modLoaded == true and apiAvailable,
        modLoaded = modLoaded == true,
        detectionSource = detectionSource,
        apiAvailable = apiAvailable,
        apiVersion = apiAvailable and tonumber(api.apiVersion) or nil,
        helperProfilesVersion = apiAvailable and tostring(api.modVersion or "") or nil,
        source = source,
        profileCount = profileCount,
        identityCount = profileCount,
        selectedIndex = selectedIndex,
        selectedSlot = selectedSlot,
        selectedName = selectedName,
        pickMode = apiStatus ~= nil and apiStatus.pickMode or nil
    }
end

function HelperPayroll:logHelperProfilesIntegrationStatus(reason)
    local status = self:getHelperProfilesStatus()
    if status.available then
        rcLog(
            "HelperProfiles integration detected: reason=%s source=%s detection=%s apiVersion=%s helperProfilesVersion=%s profiles=%d selectedSlot=%s selectedName=%s payrollMode=%s",
            tostring(reason),
            tostring(status.source),
            tostring(status.detectionSource),
            tostring(status.apiVersion or "-"),
            tostring(status.helperProfilesVersion or "-"),
            tonumber(status.profileCount) or 0,
            tostring(status.selectedSlot or "-"),
            tostring(status.selectedName or "-"),
            tostring(self.settings.payrollMode)
        )
    elseif status.modLoaded then
        rcLog(
            "HelperProfiles mod detected but shared API is not published yet: reason=%s. HelperPayroll will remain standalone until the live API becomes available.",
            tostring(reason)
        )
    else
        rcLog("HelperProfiles mod not loaded: reason=%s payrollMode=%s standalone roleType mode available", tostring(reason), tostring(self.settings.payrollMode))
    end
end

function HelperPayroll:rebuildHelperProfilesMappingIndexes()
    self.helperProfilesMappings = self.helperProfilesMappings or {}
    self.helperProfilesMappingsByIdentity = {}
    self.helperProfilesMappingsBySlot = {}
    for _, mapping in ipairs(self.helperProfilesMappings) do
        if mapping ~= nil then
            if mapping.identityId ~= nil and tostring(mapping.identityId) ~= "" then
                self.helperProfilesMappingsByIdentity[tostring(mapping.identityId)] = mapping
            end
            if mapping.slot ~= nil and tostring(mapping.slot) ~= "" then
                self.helperProfilesMappingsBySlot[string.upper(tostring(mapping.slot))] = mapping
            end
        end
    end
end

function HelperPayroll:getHelperProfilesPayrollMapping(slotInfo, slot)
    self:rebuildHelperProfilesMappingIndexes()
    local identityId = slotInfo ~= nil and slotInfo.identityId ~= nil and tostring(slotInfo.identityId) or nil
    if identityId ~= nil and identityId ~= "" then
        local mapping = self.helperProfilesMappingsByIdentity[identityId]
        if mapping ~= nil then
            return mapping, "identity"
        end
        -- API v2 preset identities are authoritative. Do not inherit a stale mapping
        -- merely because a different named worker has moved into the old A-J slot.
        if string.sub(identityId, 1, 5) ~= "slot:" then
            return nil, "none"
        end
    end
    if slot ~= nil then
        local mapping = self.helperProfilesMappingsBySlot[string.upper(tostring(slot))]
        if mapping ~= nil then
            return mapping, "slot"
        end
    end
    return nil, "none"
end

function HelperPayroll:setHelperProfilesPayrollMapping(slotInfo, slot, roleId)
    roleId = tostring(roleId or self.settings.fallbackRole or "standard")
    slot = slot ~= nil and string.upper(tostring(slot)) or nil
    local identityId = slotInfo ~= nil and slotInfo.identityId or (slot ~= nil and ("slot:" .. slot) or nil)
    local existing, _ = self:getHelperProfilesPayrollMapping(slotInfo, slot)
    local mapping = existing
    if mapping == nil then
        mapping = {}
        table.insert(self.helperProfilesMappings, mapping)
    end
    mapping.identityId = identityId
    mapping.identitySource = slotInfo ~= nil and slotInfo.identitySource or "slotFallback"
    mapping.slot = slot
    mapping.helperName = slotInfo ~= nil and slotInfo.displayName or (slot ~= nil and ("Helper " .. slot) or "Helper")
    mapping.roleId = roleId
    mapping.workerRateId = roleId
    self:rebuildHelperProfilesMappingIndexes()
    return mapping
end

function HelperPayroll:getEffectiveHelperProfilesRole(slotInfo, slot, profileId)
    local mapping, mappingSource = self:getHelperProfilesPayrollMapping(slotInfo, slot)
    if mapping ~= nil then
        local roleId = mapping.workerRateId or mapping.roleId
        if roleId ~= nil and self:getWorkerRateById(profileId, roleId) ~= nil then
            return tostring(roleId), mapping, "save-" .. tostring(mappingSource)
        end
    end
    local slotConfig = self.helperSlots ~= nil and self.helperSlots[profileId] ~= nil and self.helperSlots[profileId][slot] or nil
    if slotConfig ~= nil and slotConfig.workerRate ~= nil then
        return tostring(slotConfig.workerRate), slotConfig, "policy-slot"
    end
    return tostring(self.settings.fallbackRole or "standard"), nil, "fallback-role"
end

function HelperPayroll:resolveWorkerAssignment(tracked)
    local _, profileId = self:getActiveProfile()
    local helperSlot, helperSlotSource = self:detectHelperSlotForJob(tracked ~= nil and tracked.job or nil, tracked)
    local payrollMode = tostring(self.settings.payrollMode or "roleType")
    local helperSlotUsedForPayroll = false
    local hpSlotInfo = self:getHelperProfilesSlotInfo(helperSlot)
    local identitySource = hpSlotInfo ~= nil and tostring(hpSlotInfo.source or "HelperProfilesAPI") or "HelperPayroll"
    local mappingSource = "roleType"

    local workerId = self.settings.selectedRole or self.settings.fallbackRole or "standard"
    local helperName = nil
    local helperRole = nil

    if self:isHelperSlotPayrollMode() and helperSlot ~= nil then
        local roleId, mapping, resolvedSource = self:getEffectiveHelperProfilesRole(hpSlotInfo, helperSlot, profileId)
        workerId = roleId
        mappingSource = resolvedSource
        helperSlotUsedForPayroll = true
        helperName = hpSlotInfo ~= nil and hpSlotInfo.displayName or (mapping ~= nil and mapping.helperName) or ("Helper " .. tostring(helperSlot))
        helperRole = mapping ~= nil and mapping.roleId or nil
    end

    local worker = self:getWorkerRateById(profileId, workerId)

    if worker == nil then
        worker, profileId = self:getSelectedWorkerRate()
        workerId = worker.id or workerId
        mappingSource = "selected-role-fallback"
    end

    if self:isRoleTypePayrollMode() then
        helperName = worker.name or workerId or "Worker"
        helperRole = worker.name or "Worker"
        identitySource = "roleType"
        mappingSource = "selected-role"
    else
        helperName = helperName or (hpSlotInfo ~= nil and hpSlotInfo.displayName) or worker.name or workerId or "Worker"
        helperRole = worker.name or helperRole or "Worker"
    end

    return {
        profileId = profileId,
        payrollMode = payrollMode,
        helperSlot = helperSlot or "unassigned",
        helperSlotSource = helperSlotSource or "unassigned",
        helperSlotUsedForPayroll = helperSlotUsedForPayroll,
        helperName = helperName,
        helperRole = helperRole,
        workerId = workerId,
        workerName = worker.name or workerId or "Worker",
        hourlyRate = tonumber(worker.hourlyRate) or 0,
        helperIdentityId = hpSlotInfo ~= nil and hpSlotInfo.identityId or nil,
        helperIdentitySource = identitySource,
        helperMappingSource = mappingSource,
        helperProfilesName = hpSlotInfo ~= nil and hpSlotInfo.displayName or nil,
        helperProfilesSelected = hpSlotInfo ~= nil and hpSlotInfo.selected == true or false
    }
end

function HelperPayroll:copyWorkerAssignment(assignment)
    local copy = {}
    for key, value in pairs(assignment or {}) do
        copy[key] = value
    end
    return copy
end

function HelperPayroll:captureWorkerAssignment(tracked)
    local assignment = self:resolveWorkerAssignment(tracked)
    local clock = self:getGameClockSnapshot()
    assignment.gameDate = clock.dateKey
    assignment.workMonotonicDay = clock.monotonicDay
    assignment.workDayTime = clock.dayTimeMs
    assignment.farmId = self:getActiveFarmId()
    assignment.snapshotSource = "job-start"
    return assignment
end

function HelperPayroll:getWorkerAssignmentForBilling(tracked)
    if tracked ~= nil and tracked.assignmentSnapshot ~= nil then
        return self:copyWorkerAssignment(tracked.assignmentSnapshot)
    end

    local assignment = self:resolveWorkerAssignment(tracked)
    local clock = self:getGameClockSnapshot()
    assignment.gameDate = clock.dateKey
    assignment.workMonotonicDay = clock.monotonicDay
    assignment.workDayTime = clock.dayTimeMs
    assignment.farmId = self:getActiveFarmId()
    assignment.snapshotSource = "finish-fallback"
    rcWarn("Worker assignment snapshot was unavailable at billing time; resolved a fallback assignment at job finish")
    return assignment
end

-- GIANTS uses currentMonotonicDay and dayTime as the authoritative game clock.
-- Keep all payroll scheduling on those fields so accelerated time and period/year
-- transitions cannot strand a pending daily row.
function HelperPayroll:getGameClockSnapshot()
    local snapshot = {
        monotonicDay = nil,
        dayTimeMs = nil,
        hour = nil,
        period = nil,
        year = nil,
        dateKey = "unknown"
    }

    if g_currentMission == nil or g_currentMission.environment == nil then
        return snapshot
    end

    local env = g_currentMission.environment
    snapshot.monotonicDay = tonumber(env.currentMonotonicDay)
        or tonumber(env.currentDay)
        or tonumber(env.day)
    snapshot.dayTimeMs = tonumber(env.dayTime)
        or tonumber(env.currentDayTime)

    if snapshot.dayTimeMs ~= nil then
        local totalDayMs = 24 * 60 * 60 * 1000
        local normalized = snapshot.dayTimeMs % totalDayMs
        snapshot.hour = math.floor(normalized / 3600000)
    elseif env.currentHour ~= nil then
        snapshot.hour = math.floor(tonumber(env.currentHour) or 0)
    elseif env.hour ~= nil then
        snapshot.hour = math.floor(tonumber(env.hour) or 0)
    end

    snapshot.period = tonumber(env.currentPeriod)
        or tonumber(env.currentMonth)
        or tonumber(env.month)
        or 0
    snapshot.year = tonumber(env.currentYear)
        or tonumber(env.year)

    if snapshot.monotonicDay ~= nil or snapshot.period ~= nil or snapshot.year ~= nil then
        snapshot.dateKey = string.format(
            "Y%s-M%02d-D%02d",
            tostring(snapshot.year or "?"),
            tonumber(snapshot.period) or 0,
            tonumber(snapshot.monotonicDay) or 0
        )
    end

    return snapshot
end

function HelperPayroll:getGameDateKey()
    return self:getGameClockSnapshot().dateKey
end

function HelperPayroll:getGameHour()
    return self:getGameClockSnapshot().hour
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
    local assignment = self:getWorkerAssignmentForBilling(tracked)
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


function HelperPayroll:getDailyLedgerIdentityKey(entry)
    local identityId = entry ~= nil and entry.helperIdentityId or nil
    if identityId ~= nil and tostring(identityId) ~= "" then
        return tostring(identityId)
    end

    local slot = entry ~= nil and entry.helperSlot or nil
    if slot ~= nil and tostring(slot) ~= "" and tostring(slot) ~= "unassigned" then
        return "slot:" .. string.upper(tostring(slot))
    end

    return "name:" .. tostring(entry ~= nil and (entry.helperName or entry.workerName) or "Worker")
end

function HelperPayroll:getDailyLedgerKey(entry)
    return string.format(
        "%s|%s|%s|farm%s",
        tostring(entry ~= nil and entry.gameDate or "unknown"),
        tostring(entry ~= nil and (entry.profileId or entry.profile) or "default"),
        self:getDailyLedgerIdentityKey(entry),
        tostring(entry ~= nil and entry.farmId or "unknown")
    )
end

function HelperPayroll:updateDailyLedger(entry, quiet)
    if entry == nil then
        return nil
    end

    self.workerDailyLedger = self.workerDailyLedger or {}
    local key = self:getDailyLedgerKey(entry)
    local daily = self.workerDailyLedger[key]

    if daily == nil then
        daily = {
            key = key,
            gameDate = entry.gameDate,
            workMonotonicDay = tonumber(entry.workMonotonicDay),
            workDayTime = tonumber(entry.workDayTime),
            profileId = entry.profileId or entry.profile,
            helperSlot = entry.helperSlot,
            helperIdentityId = entry.helperIdentityId,
            helperIdentitySource = entry.helperIdentitySource,
            helperMappingSource = entry.helperMappingSource,
            helperName = entry.helperName or entry.helper,
            helperRole = entry.helperRole or entry.role,
            workerId = entry.workerId or entry.workerRate,
            hourlyRate = tonumber(entry.hourlyRate or entry.rate) or 0,
            farmId = tonumber(entry.farmId) or entry.farmId,
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
    daily.labour = (daily.labour or 0) + (tonumber(entry.labourCharge or entry.labour) or 0)

    if quiet ~= true then
        rcLog(
            "Worker daily ledger: gameDate=%s helperSlot=%s identityId=%s helper=%s role=%s jobs=%d hours=%.3f labour=%.2f charged=%.2f payrollApplied=%s",
            tostring(daily.gameDate),
            tostring(daily.helperSlot),
            tostring(daily.helperIdentityId or "-"),
            tostring(daily.helperName),
            tostring(daily.helperRole),
            tonumber(daily.jobs) or 0,
            tonumber(daily.hours) or 0,
            tonumber(daily.labour) or 0,
            tonumber(daily.charged) or 0,
            tostring(daily.payrollApplied)
        )
    end

    return daily
end

function HelperPayroll:recoverPendingDailyPayrollFromLedger()
    if not self:isDailyPayrollMode() or self.ledger == nil or self.ledger.index == nil then
        return 0, 0
    end

    self.workerDailyLedger = self.workerDailyLedger or {}
    local savedKeys = {}
    for key, _ in pairs(self.workerDailyLedger) do savedKeys[key] = true end

    local paidKeys = {}
    local deferredEntries = {}
    for _, periodId in ipairs(self.ledger.index.periodOrder or {}) do
        local entries = self:loadPeriodLedger(periodId)
        for _, entry in ipairs(entries or {}) do
            local entryType = string.lower(tostring(entry.entryType or "job"))
            local status = string.lower(tostring(entry.status or ""))
            if entryType == "payment" and status == "paid" then
                paidKeys[self:getDailyLedgerKey(entry)] = true
            elseif entryType == "job" and status == "deferred" and string.lower(tostring(entry.billingMode or "")) == "dailypayroll" then
                table.insert(deferredEntries, entry)
            end
        end
    end

    local removed = 0
    for key, _ in pairs(self.workerDailyLedger) do
        if paidKeys[key] then
            self.workerDailyLedger[key] = nil
            removed = removed + 1
        end
    end

    local recoveredJobs = 0
    for _, entry in ipairs(deferredEntries) do
        local key = self:getDailyLedgerKey(entry)
        if not paidKeys[key] and not savedKeys[key] then
            self:updateDailyLedger({
                gameDate = entry.gameDate,
                workMonotonicDay = tonumber(entry.workMonotonicDay),
                workDayTime = tonumber(entry.workDayTime),
                profileId = entry.profile,
                helperSlot = entry.helperSlot,
                helperIdentityId = entry.helperIdentityId,
                helperIdentitySource = entry.helperIdentitySource,
                helperMappingSource = entry.helperMappingSource,
                helperName = entry.helper,
                helperRole = entry.role,
                workerId = entry.workerRate,
                hourlyRate = tonumber(entry.rate) or 0,
                farmId = tonumber(entry.farmId) or 1,
                elapsedHours = tonumber(entry.elapsedHours) or 0,
                labourCharge = tonumber(entry.labour) or 0,
                charge = 0
            }, true)
            recoveredJobs = recoveredJobs + 1
        end
    end

    local pendingRows = self:countPendingDailyPayrollRows()
    if pendingRows > 0 then
        -- Run the due-date check on the next update rather than waiting for the
        -- normal polling interval after a load or ledger migration.
        self.payrollCheckAccumulatorMs = self.payrollCheckIntervalMs or 30000
    end

    if recoveredJobs > 0 or removed > 0 then
        rcLog("Reconciled pending daily payroll from persistent ledger: recoveredJobs=%d removedPaidRows=%d pendingRows=%d", recoveredJobs, removed, pendingRows)
        self:saveSavegameSettings("daily-payroll-reconciled")
    end

    return recoveredJobs, removed
end

function HelperPayroll:countPendingDailyPayrollRows()
    local count = 0
    for _, daily in pairs(self.workerDailyLedger or {}) do
        if daily ~= nil and daily.payrollApplied ~= true and (tonumber(daily.jobs) or 0) > 0 then
            count = count + 1
        end
    end
    return count
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

function HelperPayroll:parseGameDateKey(value)
    local yearText, month, day = tostring(value or ""):match("^Y([^%-]+)%-M(%d+)%-D(%d+)$")
    if yearText == nil then return nil end
    return tonumber(yearText), tonumber(month), tonumber(day), yearText
end

function HelperPayroll:compareGameDateKeys(left, right)
    local ly, lm, ld, lyText = self:parseGameDateKey(left)
    local ry, rm, rd, ryText = self:parseGameDateKey(right)
    if lm == nil or rm == nil then return nil end
    if ly ~= nil and ry ~= nil and ly ~= ry then return ly < ry and -1 or 1 end
    if ly == nil and ry == nil and lyText ~= ryText then return nil end
    if lm ~= rm then return lm < rm and -1 or 1 end
    if ld ~= rd then return ld < rd and -1 or 1 end
    return 0
end

function HelperPayroll:getStoredWorkMonotonicDay(daily)
    if daily == nil then return nil end
    local stored = tonumber(daily.workMonotonicDay)
    if stored ~= nil then return stored end

    -- Migration fallback for 0.3.2.0 and earlier pending rows. Their D component
    -- was written from environment.currentDay, which is monotonic in the tested
    -- FS25 environment.
    local _, _, day = self:parseGameDateKey(daily.gameDate)
    return tonumber(day)
end

function HelperPayroll:isDailyPayrollRowDue(daily, clock, payrollHour)
    if daily == nil or daily.payrollApplied == true or (tonumber(daily.jobs) or 0) <= 0 then
        return false, "not-pending"
    end

    clock = clock or self:getGameClockSnapshot()
    local workDay = self:getStoredWorkMonotonicDay(daily)
    local currentDay = tonumber(clock.monotonicDay)

    if workDay ~= nil and currentDay ~= nil then
        if currentDay > workDay then return true, "overdue-day" end
        if currentDay < workDay then return false, "future-row" end
        if clock.hour ~= nil and clock.hour >= payrollHour then
            return true, "scheduled-hour"
        end
        return false, "same-day-waiting"
    end

    -- Legacy fallback only when the authoritative monotonic values cannot be read.
    local comparison = self:compareGameDateKeys(daily.gameDate, clock.dateKey)
    if comparison ~= nil then
        if comparison < 0 then return true, "legacy-overdue-date" end
        if comparison > 0 then return false, "legacy-future-date" end
        return clock.hour ~= nil and clock.hour >= payrollHour, "legacy-same-day"
    end

    return clock.hour ~= nil and clock.hour >= payrollHour, "unknown-date-clock"
end

function HelperPayroll:processDailyPayroll(dt, force, triggerReason)
    if not self:isDailyPayrollMode() then return end
    if not self.settings.enableCustomWorkerCosts or not self.settings.chargeCustomWorkerCosts then return end

    local clock = self:getGameClockSnapshot()
    local clockChanged = clock.monotonicDay ~= self.lastPayrollClockDay
        or clock.hour ~= self.lastPayrollClockHour

    self.payrollCheckAccumulatorMs = (self.payrollCheckAccumulatorMs or 0) + (dt or 0)
    if force ~= true and not clockChanged and self.payrollCheckAccumulatorMs < (self.payrollCheckIntervalMs or 5000) then
        return
    end
    self.payrollCheckAccumulatorMs = 0

    self.lastPayrollClockDay = clock.monotonicDay
    self.lastPayrollClockHour = clock.hour
    self.lastPayrollClockDayTime = clock.dayTimeMs

    local payrollHour = tonumber(self.settings.payrollHour) or 18
    local pendingRows = self:countPendingDailyPayrollRows()
    if pendingRows <= 0 then return end

    if (force == true or clockChanged) and self:isDetailedDiagnosticsEnabled() then
        rcLog(
            "Daily payroll check: trigger=%s currentDate=%s currentMonotonicDay=%s dayTimeMs=%s hour=%s payrollHour=%s pendingRows=%d",
            tostring(triggerReason or (clockChanged and "clock-changed" or "forced")),
            tostring(clock.dateKey),
            tostring(clock.monotonicDay),
            tostring(clock.dayTimeMs),
            tostring(clock.hour),
            tostring(payrollHour),
            tonumber(pendingRows) or 0
        )
    end

    local rowsPaid = 0
    local totalPaid = 0
    local paidKeys = {}
    local waitingForClock = false

    for key, daily in pairs(self.workerDailyLedger or {}) do
        local due, dueReason = self:isDailyPayrollRowDue(daily, clock, payrollHour)
        if due then
            local charge, minimumApplied = self:calculateDailyPayrollCharge(daily)
            local farmId = daily.farmId or self:getActiveFarmId()
            local applied = charge <= 0 or self:applyMoneyCharge(charge, farmId, "Daily payroll charge")
            if applied then
                daily.payrollApplied = true
                daily.payrollCharge = charge
                daily.minimumApplied = minimumApplied
                daily.charged = (tonumber(daily.charged) or 0) + charge
                daily.paidMonotonicDay = clock.monotonicDay
                daily.paidDayTime = clock.dayTimeMs
                rowsPaid = rowsPaid + 1
                totalPaid = totalPaid + charge
                self.workerLedgerTotal = (self.workerLedgerTotal or 0) + charge
                rcLog(
                    "Daily payroll settled: reason=%s workDate=%s workMonotonicDay=%s paidDate=%s paidMonotonicDay=%s helperSlot=%s identityId=%s helper=%s role=%s jobs=%d hours=%.3f labour=%.2f callout=%.2f minimum=%.2f minimumApplied=%s charge=%.2f farmId=%s payrollHour=%s moneyType=%s",
                    tostring(dueReason),
                    tostring(daily.gameDate),
                    tostring(self:getStoredWorkMonotonicDay(daily)),
                    tostring(clock.dateKey),
                    tostring(clock.monotonicDay),
                    tostring(daily.helperSlot),
                    tostring(daily.helperIdentityId or "-"),
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
                self:recordPersistentDailyPayment(daily, charge, minimumApplied)
                table.insert(paidKeys, key)
            end
        elseif dueReason == "same-day-waiting" and clock.hour == nil then
            waitingForClock = true
        end
    end

    for _, key in ipairs(paidKeys) do
        self.workerDailyLedger[key] = nil
    end

    if rowsPaid > 0 then
        self:saveSavegameSettings("daily-payroll-settled")
        rcLog(
            "Daily payroll summary: trigger=%s paidDate=%s paidMonotonicDay=%s rows=%d totalPaid=%.2f sessionTotalCharged=%.2f",
            tostring(triggerReason or "poll"),
            tostring(clock.dateKey),
            tostring(clock.monotonicDay),
            rowsPaid,
            totalPaid,
            tonumber(self.workerLedgerTotal) or 0
        )
    elseif waitingForClock and not self.warnedMissingPayrollClock then
        rcWarn("Daily payroll has current-day rows but environment.dayTime could not be resolved; overdue monotonic-day rows remain payable")
        self.warnedMissingPayrollClock = true
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
    local farmId = breakdown.farmId or self:getActiveFarmId()

    self.workerLedgerCount = (self.workerLedgerCount or 0) + 1
    local entry = {
        sequence = tracked.sequence,
        jobType = tracked.name,
        workerId = breakdown.workerId,
        workerName = breakdown.workerName,
        helperSlot = breakdown.helperSlot,
        helperSlotSource = breakdown.helperSlotSource,
        helperSlotUsedForPayroll = breakdown.helperSlotUsedForPayroll,
        helperIdentityId = breakdown.helperIdentityId,
        helperIdentitySource = breakdown.helperIdentitySource,
        helperMappingSource = breakdown.helperMappingSource,
        helperProfilesName = breakdown.helperProfilesName,
        helperProfilesSelected = breakdown.helperProfilesSelected,
        payrollMode = breakdown.payrollMode,
        helperName = breakdown.helperName,
        helperRole = breakdown.helperRole,
        elapsedHours = breakdown.elapsedHours,
        hourlyRate = breakdown.hourlyRate,
        charge = 0,
        calculatedJobCharge = chargeToApply,
        farmId = farmId,
        profileId = breakdown.profileId,
        gameDate = breakdown.gameDate or self:getGameDateKey(),
        workMonotonicDay = breakdown.workMonotonicDay,
        workDayTime = breakdown.workDayTime,
        assignmentSnapshotSource = breakdown.snapshotSource,
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
            "Worker billing deferred to daily payroll: seq=%s type=%s payrollMode=%s helperSlot=%s helperSlotUsedForPayroll=%s helper=%s role=%s workerRate=%s profile=%s elapsedHours=%.3f rate=%.2f labour=%.2f dailyJobs=%s gameDate=%s payrollHour=%s",
            tostring(entry.sequence),
            tostring(entry.jobType),
            tostring(entry.payrollMode or self.settings.payrollMode),
            tostring(entry.helperSlot),
            tostring(entry.helperSlotUsedForPayroll),
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
        self:recordPersistentLedgerEntry(self:buildPersistentLedgerEntryFromWorkerEntry(entry, "deferred"), "job-deferred")
        self:saveSavegameSettings("daily-payroll-pending")
        self:processDailyPayroll(0, true, "job-deferred")
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
        self:recordPersistentLedgerEntry(self:buildPersistentLedgerEntryFromWorkerEntry(entry, "zero-charge"), "job-zero-charge")
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
        "Worker billing applied: seq=%s type=%s payrollMode=%s helperSlot=%s helperSlotSource=%s helperSlotUsedForPayroll=%s helper=%s role=%s workerRate=%s profile=%s elapsedHours=%.3f rate=%.2f labour=%.2f callout=%.2f minimum=%.2f minimumApplied=%s charge=%.2f farmId=%s gameDate=%s moneyType=%s",
        tostring(entry.sequence),
        tostring(entry.jobType),
        tostring(entry.payrollMode or self.settings.payrollMode),
        tostring(entry.helperSlot),
        tostring(entry.helperSlotSource),
        tostring(entry.helperSlotUsedForPayroll),
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

    self:recordPersistentLedgerEntry(self:buildPersistentLedgerEntryFromWorkerEntry(entry, "charged"), "job-charged")

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

            local assignment = self:captureWorkerAssignment(self.trackedAIJobs[jobId])
            self.trackedAIJobs[jobId].assignmentSnapshot = assignment
            self.trackedAIJobs[jobId].helperSlot = assignment.helperSlot
            self.trackedAIJobs[jobId].helperSlotSource = assignment.helperSlotSource
            self.trackedAIJobs[jobId].helperSlotUsedForPayroll = assignment.helperSlotUsedForPayroll
            self.trackedAIJobs[jobId].payrollMode = assignment.payrollMode
            rcLog("AI job detected #%d: id=%s type=%s payrollMode=%s helperSlot=%s helperSlotSource=%s helperSlotUsedForPayroll=%s identityId=%s identitySource=%s mappingSource=%s helper=%s role=%s workerRate=%s profile=%s rate=%.2f assignmentSnapshot=%s", self.trackedAIJobCount, tostring(jobId), tostring(self.trackedAIJobs[jobId].name), tostring(assignment.payrollMode), tostring(assignment.helperSlot), tostring(assignment.helperSlotSource), tostring(assignment.helperSlotUsedForPayroll), tostring(assignment.helperIdentityId or "-"), tostring(assignment.helperIdentitySource or "unknown"), tostring(assignment.helperMappingSource or "unknown"), tostring(assignment.helperName), tostring(assignment.helperRole), tostring(assignment.workerId), tostring(assignment.profileId), tonumber(assignment.hourlyRate) or 0, tostring(assignment.snapshotSource))
            self:diagnosticScanAIJobForHelperProfiles(job, self.trackedAIJobs[jobId])
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
                -- Mark before charging so a downstream report/ledger error cannot bill the same finished job repeatedly.
                tracked.billed = true
                local ok, result = pcall(function()
                    return self:applyWorkerCharge(tracked)
                end)
                if ok then
                    billingHandled = result == true
                    if not billingHandled then
                        rcWarn("Worker billing attempt completed without applying a charge: seq=%s id=%s type=%s", tostring(tracked.sequence), tostring(jobId), tostring(tracked.name))
                    end
                else
                    billingHandled = true
                    rcWarn("Worker billing attempt raised an error after job finish; job will not be retried to prevent duplicate charges: seq=%s id=%s type=%s error=%s", tostring(tracked.sequence), tostring(jobId), tostring(tracked.name), tostring(result))
                end
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


local function hpayPrintf(message, ...)
    print(string.format("[HelperPayroll] " .. tostring(message), ...))
end

local function hpayNormalizeArgs(...)
    local args = {...}
    local sub, p1, p2, p3, p4
    for i = 1, #args do
        local v = args[i]
        if v ~= nil and tostring(v) ~= "" then
            local sv = tostring(v)
            if sv == "hpayOverlay" or sv == "hpayRole" or sv == "hpayDump" or sv == "hpayReport" or sv == "hpayConfig" or sv == "hpaySave" then
                -- Some console APIs echo the command name as argv[1]. Ignore it.
            elseif sub == nil then
                sub = sv
            elseif p1 == nil then
                p1 = sv
            elseif p2 == nil then
                p2 = sv
            elseif p3 == nil then
                p3 = sv
            else
                p4 = sv
            end
        end
    end
    return sub, p1, p2, p3, p4
end

function HelperPayroll:getSelectedRoleInfo()
    local _, profileId = self:getActiveProfile()
    local selectedRole = tostring(self.settings.selectedRole or self.settings.fallbackRole or "")
    local worker = self:getWorkerRateById(profileId, selectedRole)
    local workerName = worker ~= nil and worker.name or selectedRole
    local hourlyRate = worker ~= nil and tonumber(worker.hourlyRate) or 0
    return selectedRole, workerName, hourlyRate, profileId
end

function HelperPayroll:setSelectedRole(roleOrIndex, sourceLabel)
    if not self:isRoleTypePayrollMode() then
        hpayPrintf("Role selection ignored: payrollMode=%s; role selection only affects roleType mode", tostring(self.settings.payrollMode))
        self:showRoleMessage("Helper Payroll: role selector only affects roleType mode")
        return false
    end

    local _, profileId = self:getActiveProfile()
    local order = self:getWorkerRateOrder(profileId)
    if order == nil or #order == 0 then
        hpayPrintf("Role selection failed: no worker rates loaded for profile '%s'", tostring(profileId))
        return false
    end

    local requested = tostring(roleOrIndex or "")
    local requestedIndex = tonumber(requested)
    local newRole = nil

    if requestedIndex ~= nil then
        requestedIndex = math.floor(requestedIndex)
        if requestedIndex >= 1 and requestedIndex <= #order then
            newRole = order[requestedIndex]
        end
    else
        local wanted = string.lower(requested)
        for _, roleId in ipairs(order) do
            local worker = self:getWorkerRateById(profileId, roleId)
            local roleName = worker ~= nil and worker.name or roleId
            if string.lower(tostring(roleId)) == wanted or string.lower(tostring(roleName)) == wanted then
                newRole = roleId
                break
            end
        end
    end

    if newRole == nil then
        hpayPrintf("Role selection failed: unknown role/index '%s'", tostring(roleOrIndex))
        return false
    end

    self.settings.selectedRole = newRole
    self:saveSavegameSettings("role-set")
    local worker = self:getWorkerRateById(profileId, newRole)
    local workerName = worker ~= nil and worker.name or newRole
    local hourlyRate = worker ~= nil and tonumber(worker.hourlyRate) or 0

    hpayPrintf("Selected payroll role changed%s: profile=%s role=%s name=%s rate=%.2f",
        sourceLabel ~= nil and (" via " .. tostring(sourceLabel)) or "",
        tostring(profileId), tostring(newRole), tostring(workerName), hourlyRate or 0)
    self:showRoleMessage(string.format("Helper Payroll Role: %s (%.2f/hr)", tostring(workerName), hourlyRate or 0))
    return true
end


function HelperPayroll:initPersistencePaths()
    self.persistence = self.persistence or {}
    local base = hpayGetUserPath() .. "modSettings/"
    local modDir = base .. "FS25_HelperPayroll/"
    local savegameName = hpayDetectSavegameName()
    local saveDir = modDir .. tostring(savegameName or "unknownSavegame") .. "/"

    hpayEnsureFolder(base)
    hpayEnsureFolder(modDir)
    hpayEnsureFolder(saveDir)

    self.persistence.modSettingsDir = modDir
    self.persistence.savegameName = savegameName
    self.persistence.savegameDir = saveDir
    self.persistence.filePath = saveDir .. "helperPayrollSettings.xml"
end

function HelperPayroll:loadSavegameSettings()
    self:initPersistencePaths()
    self.workerDailyLedger = {}
    local path = self.persistence ~= nil and self.persistence.filePath or nil
    if path == nil or path == "" then
        rcWarn("Savegame persistence skipped: no settings path resolved")
        return false
    end

    if not hpayFileExists(path) then
        rcLog("No savegame persistence file found yet: %s", tostring(path))
        self.persistence.loaded = false
        return false
    end

    local xmlFile = loadXMLFile("helperPayrollSavegameSettingsRead", path)
    if xmlFile == nil or xmlFile == 0 then
        rcWarn("Could not load savegame persistence file: %s", tostring(path))
        return false
    end

    self.settings.activePayrollProfile = getXmlStringOrDefault(xmlFile, "helperPayrollSave#activePayrollProfile", self.settings.activePayrollProfile)
    self.settings.payrollMode = getXmlStringOrDefault(xmlFile, "helperPayrollSave#payrollMode", self.settings.payrollMode)
    self.settings.selectedRole = getXmlStringOrDefault(xmlFile, "helperPayrollSave#selectedRole", self.settings.selectedRole)
    self.settings.fallbackRole = getXmlStringOrDefault(xmlFile, "helperPayrollSave#fallbackRole", self.settings.fallbackRole)

    -- Save-specific gameplay policy overrides.  The global defaultPayrollConfig.xml remains
    -- the template/default policy; the management UI writes active gameplay changes here.
    self.settings.billingMode = getXmlStringOrDefault(xmlFile, "helperPayrollSave.policy#billingMode", self.settings.billingMode)
    self.settings.payrollHour = getXmlFloatOrDefault(xmlFile, "helperPayrollSave.policy#payrollHour", self.settings.payrollHour or 18)
    self.settings.minimumWorkerCharge = getXmlFloatOrDefault(xmlFile, "helperPayrollSave.policy#minimumWorkerCharge", self.settings.minimumWorkerCharge or 0)
    self.settings.workerCalloutFee = getXmlFloatOrDefault(xmlFile, "helperPayrollSave.policy#workerCalloutFee", self.settings.workerCalloutFee or 0)
    self.settings.roundWorkerCharges = getXmlBoolOrDefault(xmlFile, "helperPayrollSave.policy#roundWorkerCharges", self.settings.roundWorkerCharges ~= false)

    local rateIndex = 0
    while true do
        local key = string.format("helperPayrollSave.workerRates.worker(%d)", rateIndex)
        if not hasXMLProperty(xmlFile, key) then break end
        local profileId = getXmlStringOrDefault(xmlFile, key .. "#profile", self.settings.activePayrollProfile or "default")
        local roleId = getXmlStringOrDefault(xmlFile, key .. "#role", "")
        local hourlyRate = getXmlFloatOrDefault(xmlFile, key .. "#hourlyRate", nil)
        if roleId ~= nil and roleId ~= "" and hourlyRate ~= nil and self.workerRates ~= nil and self.workerRates[profileId] ~= nil and self.workerRates[profileId][roleId] ~= nil then
            self.workerRates[profileId][roleId].hourlyRate = tonumber(hourlyRate) or self.workerRates[profileId][roleId].hourlyRate
        end
        rateIndex = rateIndex + 1
    end

    self.helperProfilesMappings = {}
    local mappingIndex = 0
    while true do
        local key = string.format("helperPayrollSave.helperProfilesMappings.worker(%d)", mappingIndex)
        if not hasXMLProperty(xmlFile, key) then break end
        local mapping = {
            identityId = getXmlStringOrDefault(xmlFile, key .. "#identityId", ""),
            identitySource = getXmlStringOrDefault(xmlFile, key .. "#identitySource", ""),
            slot = string.upper(getXmlStringOrDefault(xmlFile, key .. "#slot", "")),
            helperName = getXmlStringOrDefault(xmlFile, key .. "#helperName", ""),
            roleId = getXmlStringOrDefault(xmlFile, key .. "#roleId", self.settings.fallbackRole or "standard"),
            workerRateId = getXmlStringOrDefault(xmlFile, key .. "#workerRateId", self.settings.fallbackRole or "standard")
        }
        if mapping.identityId ~= "" or mapping.slot ~= "" then
            table.insert(self.helperProfilesMappings, mapping)
        end
        mappingIndex = mappingIndex + 1
    end
    self:rebuildHelperProfilesMappingIndexes()

    self.workerDailyLedger = {}
    local pendingIndex = 0
    while true do
        local key = string.format("helperPayrollSave.pendingPayroll.row(%d)", pendingIndex)
        if not hasXMLProperty(xmlFile, key) then break end
        local daily = {
            gameDate = getXmlStringOrDefault(xmlFile, key .. "#gameDate", "unknown"),
            workMonotonicDay = getXmlFloatOrDefault(xmlFile, key .. "#workMonotonicDay", nil),
            workDayTime = getXmlFloatOrDefault(xmlFile, key .. "#workDayTime", nil),
            profileId = getXmlStringOrDefault(xmlFile, key .. "#profileId", self.settings.activePayrollProfile or "default"),
            helperSlot = getXmlStringOrDefault(xmlFile, key .. "#helperSlot", "unassigned"),
            helperIdentityId = getXmlStringOrDefault(xmlFile, key .. "#helperIdentityId", ""),
            helperIdentitySource = getXmlStringOrDefault(xmlFile, key .. "#helperIdentitySource", ""),
            helperMappingSource = getXmlStringOrDefault(xmlFile, key .. "#helperMappingSource", ""),
            helperName = getXmlStringOrDefault(xmlFile, key .. "#helperName", "Worker"),
            helperRole = getXmlStringOrDefault(xmlFile, key .. "#helperRole", "Worker"),
            workerId = getXmlStringOrDefault(xmlFile, key .. "#workerId", self.settings.fallbackRole or "standard"),
            hourlyRate = getXmlFloatOrDefault(xmlFile, key .. "#hourlyRate", 0),
            farmId = getXmlFloatOrDefault(xmlFile, key .. "#farmId", 1),
            jobs = getXmlFloatOrDefault(xmlFile, key .. "#jobs", 0),
            hours = getXmlFloatOrDefault(xmlFile, key .. "#hours", 0),
            labour = getXmlFloatOrDefault(xmlFile, key .. "#labour", 0),
            charged = getXmlFloatOrDefault(xmlFile, key .. "#charged", 0),
            payrollApplied = false,
            payrollCharge = 0
        }
        daily.key = self:getDailyLedgerKey(daily)
        if (tonumber(daily.jobs) or 0) > 0 then
            self.workerDailyLedger[daily.key] = daily
        end
        pendingIndex = pendingIndex + 1
    end
    if pendingIndex > 0 then
        rcLog("Loaded pending daily payroll rows: rows=%d", pendingIndex)
    end

    self.settings.roleSelectorDebounceMs = getXmlFloatOrDefault(xmlFile, "helperPayrollSave.ui#debounceMs", self.settings.roleSelectorDebounceMs or 450)

    self.roleListUi = self.roleListUi or {}
    self.roleListUi.anchor = getXmlStringOrDefault(xmlFile, "helperPayrollSave.ui#anchor", self.roleListUi.anchor or "TR")
    self.roleListUi.x = getXmlFloatOrDefault(xmlFile, "helperPayrollSave.ui#x", self.roleListUi.x or 0.985)
    self.roleListUi.y = getXmlFloatOrDefault(xmlFile, "helperPayrollSave.ui#y", self.roleListUi.y or 0.900)
    self.roleListUi.scale = getXmlFloatOrDefault(xmlFile, "helperPayrollSave.ui#scale", self.roleListUi.scale or 1.0)
    self.roleListUi.width = getXmlFloatOrDefault(xmlFile, "helperPayrollSave.ui#width", self.roleListUi.width or 0.400)
    self.roleListUi.opacity = getXmlFloatOrDefault(xmlFile, "helperPayrollSave.ui#opacity", self.roleListUi.opacity or 0.40)
    self.roleListUi.pad = getXmlFloatOrDefault(xmlFile, "helperPayrollSave.ui#pad", self.roleListUi.pad or 0.006)
    self.roleListUi.rowGap = getXmlFloatOrDefault(xmlFile, "helperPayrollSave.ui#rowGap", self.roleListUi.rowGap or 0.006)
    self.roleListUi.fontSize = getXmlFloatOrDefault(xmlFile, "helperPayrollSave.ui#font", self.roleListUi.fontSize or 0.014)
    self.roleListUi.maxRows = getXmlFloatOrDefault(xmlFile, "helperPayrollSave.ui#maxRows", self.roleListUi.maxRows or 10)
    self.roleListUi.bgEnabled = getXmlBoolOrDefault(xmlFile, "helperPayrollSave.ui#bg", self.roleListUi.bgEnabled ~= false)
    self.roleListUi.outline = getXmlBoolOrDefault(xmlFile, "helperPayrollSave.ui#outline", self.roleListUi.outline == true)
    self.roleListUi.shadow = getXmlBoolOrDefault(xmlFile, "helperPayrollSave.ui#shadow", self.roleListUi.shadow == true)

    delete(xmlFile)
    self.persistence.loaded = true
    rcLog("Loaded savegame persistence: savegame=%s file=%s selectedRole=%s payrollMode=%s profile=%s",
        tostring(self.persistence.savegameName), tostring(path), tostring(self.settings.selectedRole), tostring(self.settings.payrollMode), tostring(self.settings.activePayrollProfile))
    return true
end

function HelperPayroll:saveSavegameSettings(reason)
    self:initPersistencePaths()
    local path = self.persistence ~= nil and self.persistence.filePath or nil
    if path == nil or path == "" then
        rcWarn("Savegame persistence write skipped: no settings path resolved")
        return false
    end

    local xmlFile = createXMLFile("helperPayrollSavegameSettingsWrite", path, "helperPayrollSave")
    if xmlFile == nil or xmlFile == 0 then
        rcWarn("Could not create savegame persistence file: %s", tostring(path))
        return false
    end

    local ui = self.roleListUi or {}
    setXMLString(xmlFile, "helperPayrollSave#version", tostring(self.VERSION or "0.3.3.0"))
    setXMLString(xmlFile, "helperPayrollSave#savegame", tostring(self.persistence.savegameName or "unknownSavegame"))
    setXMLString(xmlFile, "helperPayrollSave#activePayrollProfile", tostring(self.settings.activePayrollProfile or "default"))
    setXMLString(xmlFile, "helperPayrollSave#payrollMode", tostring(self.settings.payrollMode or "roleType"))
    setXMLString(xmlFile, "helperPayrollSave#selectedRole", tostring(self.settings.selectedRole or "standard"))
    setXMLString(xmlFile, "helperPayrollSave#fallbackRole", tostring(self.settings.fallbackRole or "standard"))

    -- Save-specific gameplay policy overrides written by the management UI.
    setXMLString(xmlFile, "helperPayrollSave.policy#billingMode", tostring(self.settings.billingMode or "onJobFinish"))
    setXMLInt(xmlFile, "helperPayrollSave.policy#payrollHour", math.floor(tonumber(self.settings.payrollHour) or 18))
    setXMLFloat(xmlFile, "helperPayrollSave.policy#minimumWorkerCharge", tonumber(self.settings.minimumWorkerCharge) or 0)
    setXMLFloat(xmlFile, "helperPayrollSave.policy#workerCalloutFee", tonumber(self.settings.workerCalloutFee) or 0)
    setXMLBool(xmlFile, "helperPayrollSave.policy#roundWorkerCharges", self.settings.roundWorkerCharges ~= false)

    local activeProfile = tostring(self.settings.activePayrollProfile or "default")
    local rates = self.workerRates ~= nil and self.workerRates[activeProfile] or nil
    if rates ~= nil then
        local ids = {}
        for roleId, _ in pairs(rates) do table.insert(ids, roleId) end
        table.sort(ids)
        for i, roleId in ipairs(ids) do
            local worker = rates[roleId]
            local key = string.format("helperPayrollSave.workerRates.worker(%d)", i - 1)
            setXMLString(xmlFile, key .. "#profile", activeProfile)
            setXMLString(xmlFile, key .. "#role", tostring(roleId))
            setXMLString(xmlFile, key .. "#name", tostring(worker.name or roleId))
            setXMLFloat(xmlFile, key .. "#hourlyRate", tonumber(worker.hourlyRate) or 0)
        end
    end

    self:rebuildHelperProfilesMappingIndexes()
    local mappings = self.helperProfilesMappings or {}
    table.sort(mappings, function(a, b)
        local as = tostring(a.slot or "Z")
        local bs = tostring(b.slot or "Z")
        if as == bs then return tostring(a.identityId or "") < tostring(b.identityId or "") end
        return as < bs
    end)
    for i, mapping in ipairs(mappings) do
        local key = string.format("helperPayrollSave.helperProfilesMappings.worker(%d)", i - 1)
        setXMLString(xmlFile, key .. "#identityId", tostring(mapping.identityId or ""))
        setXMLString(xmlFile, key .. "#identitySource", tostring(mapping.identitySource or ""))
        setXMLString(xmlFile, key .. "#slot", tostring(mapping.slot or ""))
        setXMLString(xmlFile, key .. "#helperName", tostring(mapping.helperName or ""))
        setXMLString(xmlFile, key .. "#roleId", tostring(mapping.roleId or mapping.workerRateId or self.settings.fallbackRole or "standard"))
        setXMLString(xmlFile, key .. "#workerRateId", tostring(mapping.workerRateId or mapping.roleId or self.settings.fallbackRole or "standard"))
    end

    local pendingKeys = {}
    for key, daily in pairs(self.workerDailyLedger or {}) do
        if daily ~= nil and daily.payrollApplied ~= true and (tonumber(daily.jobs) or 0) > 0 then
            table.insert(pendingKeys, key)
        end
    end
    table.sort(pendingKeys)
    for i, pendingKey in ipairs(pendingKeys) do
        local daily = self.workerDailyLedger[pendingKey]
        local key = string.format("helperPayrollSave.pendingPayroll.row(%d)", i - 1)
        setXMLString(xmlFile, key .. "#gameDate", tostring(daily.gameDate or "unknown"))
        if daily.workMonotonicDay ~= nil then setXMLInt(xmlFile, key .. "#workMonotonicDay", math.floor(tonumber(daily.workMonotonicDay) or 0)) end
        if daily.workDayTime ~= nil then setXMLFloat(xmlFile, key .. "#workDayTime", tonumber(daily.workDayTime) or 0) end
        setXMLString(xmlFile, key .. "#profileId", tostring(daily.profileId or self.settings.activePayrollProfile or "default"))
        setXMLString(xmlFile, key .. "#helperSlot", tostring(daily.helperSlot or "unassigned"))
        setXMLString(xmlFile, key .. "#helperIdentityId", tostring(daily.helperIdentityId or ""))
        setXMLString(xmlFile, key .. "#helperIdentitySource", tostring(daily.helperIdentitySource or ""))
        setXMLString(xmlFile, key .. "#helperMappingSource", tostring(daily.helperMappingSource or ""))
        setXMLString(xmlFile, key .. "#helperName", tostring(daily.helperName or "Worker"))
        setXMLString(xmlFile, key .. "#helperRole", tostring(daily.helperRole or "Worker"))
        setXMLString(xmlFile, key .. "#workerId", tostring(daily.workerId or self.settings.fallbackRole or "standard"))
        setXMLFloat(xmlFile, key .. "#hourlyRate", tonumber(daily.hourlyRate) or 0)
        setXMLInt(xmlFile, key .. "#farmId", math.floor(tonumber(daily.farmId) or 1))
        setXMLInt(xmlFile, key .. "#jobs", math.floor(tonumber(daily.jobs) or 0))
        setXMLFloat(xmlFile, key .. "#hours", tonumber(daily.hours) or 0)
        setXMLFloat(xmlFile, key .. "#labour", tonumber(daily.labour) or 0)
        setXMLFloat(xmlFile, key .. "#charged", tonumber(daily.charged) or 0)
    end

    setXMLString(xmlFile, "helperPayrollSave.ui#anchor", tostring(ui.anchor or "TR"))
    setXMLFloat(xmlFile, "helperPayrollSave.ui#x", tonumber(ui.x) or 0.985)
    setXMLFloat(xmlFile, "helperPayrollSave.ui#y", tonumber(ui.y) or 0.900)
    setXMLFloat(xmlFile, "helperPayrollSave.ui#scale", tonumber(ui.scale) or 1.0)
    setXMLFloat(xmlFile, "helperPayrollSave.ui#width", tonumber(ui.width) or 0.400)
    setXMLFloat(xmlFile, "helperPayrollSave.ui#opacity", tonumber(ui.opacity) or 0.40)
    setXMLFloat(xmlFile, "helperPayrollSave.ui#pad", tonumber(ui.pad) or 0.006)
    setXMLFloat(xmlFile, "helperPayrollSave.ui#rowGap", tonumber(ui.rowGap) or 0.006)
    setXMLFloat(xmlFile, "helperPayrollSave.ui#font", tonumber(ui.fontSize) or 0.014)
    setXMLInt(xmlFile, "helperPayrollSave.ui#maxRows", math.floor(tonumber(ui.maxRows) or 10))
    setXMLBool(xmlFile, "helperPayrollSave.ui#bg", ui.bgEnabled ~= false)
    setXMLBool(xmlFile, "helperPayrollSave.ui#outline", ui.outline == true)
    setXMLBool(xmlFile, "helperPayrollSave.ui#shadow", ui.shadow == true)
    setXMLInt(xmlFile, "helperPayrollSave.ui#debounceMs", math.floor(tonumber(self.settings.roleSelectorDebounceMs) or 450))

    saveXMLFile(xmlFile)
    delete(xmlFile)
    rcLog("Saved savegame persistence: reason=%s savegame=%s file=%s selectedRole=%s",
        tostring(reason or "manual"), tostring(self.persistence.savegameName), tostring(path), tostring(self.settings.selectedRole))
    return true
end



local function hpayFormatMoney(value)
    return string.format("%.2f", tonumber(value) or 0)
end

local function hpaySafeFileName(value)
    return tostring(value or "unknown"):gsub("[^%w_%-%.]", "_")
end

-- ===== Persistent payroll ledger ===========================================

local function hpayXmlEscape(value)
    value = tostring(value == nil and "" or value)
    value = value:gsub("&", "&amp;")
    value = value:gsub("<", "&lt;")
    value = value:gsub(">", "&gt;")
    value = value:gsub('"', "&quot;")
    return value
end

local function hpayXmlAttr(name, value)
    return string.format(' %s="%s"', tostring(name), hpayXmlEscape(value))
end

local function hpayRealTimestamp()
    if os ~= nil and os.date ~= nil then
        return os.date("%Y-%m-%d %H:%M:%S")
    end
    return "unknown"
end

-- FS25 restricts raw file reads for mods.  Use GIANTS XML APIs for all read paths.
local function hpayReadFile(path)
    return nil
end

local function hpayXmlGetString(xmlFile, key, default)
    if xmlFile == nil or key == nil then return default end
    if hasXMLProperty ~= nil and not hasXMLProperty(xmlFile, key) then
        return default
    end
    local value = getXMLString(xmlFile, key)
    if value == nil then return default end
    return value
end

local function hpayXmlGetFloat(xmlFile, key, default)
    if xmlFile == nil or key == nil then return default or 0 end
    if hasXMLProperty ~= nil and not hasXMLProperty(xmlFile, key) then
        return default or 0
    end
    local value = getXMLFloat(xmlFile, key)
    if value == nil then return default or 0 end
    return value
end

local function hpayXmlGetInt(xmlFile, key, default)
    if xmlFile == nil or key == nil then return default or 0 end
    if hasXMLProperty ~= nil and not hasXMLProperty(xmlFile, key) then
        return default or 0
    end
    local value = getXMLInt(xmlFile, key)
    if value == nil then return default or 0 end
    return value
end

local function hpayXmlGetBool(xmlFile, key, default)
    if xmlFile == nil or key == nil then return default == true end
    if hasXMLProperty ~= nil and not hasXMLProperty(xmlFile, key) then
        return default == true
    end
    local value = getXMLBool(xmlFile, key)
    if value == nil then return default == true end
    return value
end

local function hpayXmlGetOptionalInt(xmlFile, key)
    if xmlFile == nil or key == nil then return nil end
    if hasXMLProperty ~= nil and not hasXMLProperty(xmlFile, key) then return nil end
    return getXMLInt(xmlFile, key)
end

local function hpayXmlGetOptionalFloat(xmlFile, key)
    if xmlFile == nil or key == nil then return nil end
    if hasXMLProperty ~= nil and not hasXMLProperty(xmlFile, key) then return nil end
    return getXMLFloat(xmlFile, key)
end

local function hpayWriteFile(path, lines)
    local f = io.open(path, "w")
    if f == nil then return false end
    for _, line in ipairs(lines or {}) do
        f:write(tostring(line), "\n")
    end
    f:close()
    return true
end

local function hpayParseAttrs(chunk)
    local attrs = {}
    chunk = tostring(chunk or "")
    for name, value in chunk:gmatch('([%w_]+)="(.-)"') do
        value = tostring(value):gsub("&quot;", '"'):gsub("&gt;", ">"):gsub("&lt;", "<"):gsub("&amp;", "&")
        attrs[name] = value
    end
    return attrs
end

local function hpayToNumber(value, default)
    local n = tonumber(value)
    if n == nil then return default or 0 end
    return n
end

local function hpayBumpSummary(target, entry)
    if target == nil or entry == nil then return end
    local entryType = tostring(entry.entryType or "job")
    if entryType == "job" then
        target.jobs = (tonumber(target.jobs) or 0) + 1
        target.hours = (tonumber(target.hours) or 0) + (tonumber(entry.elapsedHours) or 0)
        target.labour = (tonumber(target.labour) or 0) + (tonumber(entry.labourCharge or entry.labour) or 0)
        target.calculated = (tonumber(target.calculated) or 0) + (tonumber(entry.calculatedJobCharge or entry.calculated) or 0)
        if entry.appliedMinimum == true or tostring(entry.appliedMinimum) == "true" then
            target.minimumJobs = (tonumber(target.minimumJobs) or 0) + 1
        end
    elseif entryType == "payment" then
        target.payments = (tonumber(target.payments) or 0) + 1
    end
    target.charged = (tonumber(target.charged) or 0) + (tonumber(entry.charge or entry.charged) or 0)
end

function HelperPayroll:getLedgerPeriodId(gameDate)
    local dateKey = tostring(gameDate or self:getGameDateKey() or "unknown")
    local year, month = dateKey:match("Y(%d+)%D+M(%d+)")
    if year ~= nil and month ~= nil then
        return string.format("Y%03d_M%02d", tonumber(year) or 0, tonumber(month) or 0)
    end
    return "unknown"
end

function HelperPayroll:initLedgerPaths()
    self:initPersistencePaths()
    self.ledger = self.ledger or {}
    local saveDir = self.persistence ~= nil and self.persistence.savegameDir or nil
    if saveDir == nil or saveDir == "" then return false end
    local ledgerDir = saveDir .. "ledger/"
    hpayEnsureFolder(ledgerDir)
    self.ledger.ledgerDir = ledgerDir
    self.ledger.indexPath = ledgerDir .. "index.xml"
    self.ledger.currentPeriodId = self:getLedgerPeriodId(self:getGameDateKey())
    self.ledger.periodEntries = self.ledger.periodEntries or {}
    self.ledger.loadedPeriods = self.ledger.loadedPeriods or {}
    return true
end

function HelperPayroll:getPeriodLedgerPath(periodId)
    self:initLedgerPaths()
    if self.ledger == nil or self.ledger.ledgerDir == nil then return nil end
    local safe = hpaySafeFileName(periodId or self:getLedgerPeriodId())
    return self.ledger.ledgerDir .. safe .. ".xml"
end

function HelperPayroll:createEmptyLedgerIndex()
    return {
        summary = { jobs = 0, hours = 0, labour = 0, calculated = 0, charged = 0, minimumJobs = 0, payments = 0 },
        periods = {},
        periodOrder = {},
        roles = {},
        roleOrder = {}
    }
end

function HelperPayroll:loadLedgerIndex()
    self:initLedgerPaths()
    self.ledger.index = self:createEmptyLedgerIndex()
    self.ledger.hasIndexFile = false
    local path = self.ledger.indexPath
    if path == nil or not hpayFileExists(path) then
        self.ledger.loaded = true
        self.ledger.hasIndexFile = false
        rcLog("No persistent payroll ledger index found yet: %s", tostring(path))
        return false
    end

    local xmlFile = loadXMLFile("HelperPayrollLedgerIndex", path)
    if xmlFile == nil or xmlFile == 0 then
        self.ledger.loaded = true
        self.ledger.hasIndexFile = false
        rcWarn("Could not load persistent payroll ledger index XML; starting with an empty ledger index: %s", tostring(path))
        return false
    end

    local idx = self.ledger.index
    idx.summary = {
        jobs = hpayXmlGetInt(xmlFile, "helperPayrollLedgerIndex.summary#jobs", 0),
        hours = hpayXmlGetFloat(xmlFile, "helperPayrollLedgerIndex.summary#hours", 0),
        labour = hpayXmlGetFloat(xmlFile, "helperPayrollLedgerIndex.summary#labour", 0),
        calculated = hpayXmlGetFloat(xmlFile, "helperPayrollLedgerIndex.summary#calculated", 0),
        charged = hpayXmlGetFloat(xmlFile, "helperPayrollLedgerIndex.summary#charged", 0),
        minimumJobs = hpayXmlGetInt(xmlFile, "helperPayrollLedgerIndex.summary#minimumJobs", 0),
        payments = hpayXmlGetInt(xmlFile, "helperPayrollLedgerIndex.summary#payments", 0)
    }

    local i = 0
    while true do
        local key = string.format("helperPayrollLedgerIndex.periods.period(%d)", i)
        if hasXMLProperty ~= nil and not hasXMLProperty(xmlFile, key) then break end
        local id = hpayXmlGetString(xmlFile, key .. "#id", nil)
        if id == nil then break end
        idx.periods[id] = {
            id = id,
            jobs = hpayXmlGetInt(xmlFile, key .. "#jobs", 0),
            hours = hpayXmlGetFloat(xmlFile, key .. "#hours", 0),
            labour = hpayXmlGetFloat(xmlFile, key .. "#labour", 0),
            calculated = hpayXmlGetFloat(xmlFile, key .. "#calculated", 0),
            charged = hpayXmlGetFloat(xmlFile, key .. "#charged", 0),
            minimumJobs = hpayXmlGetInt(xmlFile, key .. "#minimumJobs", 0),
            payments = hpayXmlGetInt(xmlFile, key .. "#payments", 0)
        }
        table.insert(idx.periodOrder, id)
        i = i + 1
    end

    i = 0
    while true do
        local key = string.format("helperPayrollLedgerIndex.roles.role(%d)", i)
        if hasXMLProperty ~= nil and not hasXMLProperty(xmlFile, key) then break end
        local id = hpayXmlGetString(xmlFile, key .. "#id", nil)
        if id == nil then break end
        idx.roles[id] = {
            id = id,
            name = hpayXmlGetString(xmlFile, key .. "#name", id),
            jobs = hpayXmlGetInt(xmlFile, key .. "#jobs", 0),
            hours = hpayXmlGetFloat(xmlFile, key .. "#hours", 0),
            labour = hpayXmlGetFloat(xmlFile, key .. "#labour", 0),
            calculated = hpayXmlGetFloat(xmlFile, key .. "#calculated", 0),
            charged = hpayXmlGetFloat(xmlFile, key .. "#charged", 0),
            minimumJobs = hpayXmlGetInt(xmlFile, key .. "#minimumJobs", 0),
            payments = hpayXmlGetInt(xmlFile, key .. "#payments", 0)
        }
        table.insert(idx.roleOrder, id)
        i = i + 1
    end

    delete(xmlFile)
    self.ledger.loaded = true
    self.ledger.hasIndexFile = true
    rcLog("Loaded persistent payroll ledger index: file=%s jobs=%d charged=%.2f periods=%d roles=%d",
        tostring(path), tonumber(idx.summary.jobs) or 0, tonumber(idx.summary.charged) or 0,
        #(idx.periodOrder or {}), #(idx.roleOrder or {}))
    return true
end

function HelperPayroll:saveLedgerIndex(reason)
    self:initLedgerPaths()
    self.ledger.index = self.ledger.index or self:createEmptyLedgerIndex()
    local idx = self.ledger.index
    local s = idx.summary or {}
    local lines = {}
    table.insert(lines, '<?xml version="1.0" encoding="utf-8" standalone="no" ?>')
    table.insert(lines, '<helperPayrollLedgerIndex' .. hpayXmlAttr("version", tostring(self.VERSION or "0.3.3.0")) .. hpayXmlAttr("savegame", self.persistence ~= nil and self.persistence.savegameName or "unknown") .. '>')
    table.insert(lines, '  <summary' .. hpayXmlAttr("jobs", s.jobs or 0) .. hpayXmlAttr("hours", string.format("%.3f", tonumber(s.hours) or 0)) .. hpayXmlAttr("labour", string.format("%.2f", tonumber(s.labour) or 0)) .. hpayXmlAttr("calculated", string.format("%.2f", tonumber(s.calculated) or 0)) .. hpayXmlAttr("charged", string.format("%.2f", tonumber(s.charged) or 0)) .. hpayXmlAttr("minimumJobs", s.minimumJobs or 0) .. hpayXmlAttr("payments", s.payments or 0) .. ' />')
    table.insert(lines, '  <periods>')
    for _, id in ipairs(idx.periodOrder or {}) do
        local p = idx.periods[id]
        if p ~= nil then
            table.insert(lines, '    <period' .. hpayXmlAttr("id", id) .. hpayXmlAttr("jobs", p.jobs or 0) .. hpayXmlAttr("hours", string.format("%.3f", tonumber(p.hours) or 0)) .. hpayXmlAttr("labour", string.format("%.2f", tonumber(p.labour) or 0)) .. hpayXmlAttr("calculated", string.format("%.2f", tonumber(p.calculated) or 0)) .. hpayXmlAttr("charged", string.format("%.2f", tonumber(p.charged) or 0)) .. hpayXmlAttr("minimumJobs", p.minimumJobs or 0) .. hpayXmlAttr("payments", p.payments or 0) .. ' />')
        end
    end
    table.insert(lines, '  </periods>')
    table.insert(lines, '  <roles>')
    for _, id in ipairs(idx.roleOrder or {}) do
        local r = idx.roles[id]
        if r ~= nil then
            table.insert(lines, '    <role' .. hpayXmlAttr("id", id) .. hpayXmlAttr("name", r.name or id) .. hpayXmlAttr("jobs", r.jobs or 0) .. hpayXmlAttr("hours", string.format("%.3f", tonumber(r.hours) or 0)) .. hpayXmlAttr("labour", string.format("%.2f", tonumber(r.labour) or 0)) .. hpayXmlAttr("calculated", string.format("%.2f", tonumber(r.calculated) or 0)) .. hpayXmlAttr("charged", string.format("%.2f", tonumber(r.charged) or 0)) .. hpayXmlAttr("minimumJobs", r.minimumJobs or 0) .. hpayXmlAttr("payments", r.payments or 0) .. ' />')
        end
    end
    table.insert(lines, '  </roles>')
    table.insert(lines, '</helperPayrollLedgerIndex>')

    local ok = hpayWriteFile(self.ledger.indexPath, lines)
    if ok then
        rcLog("Saved persistent payroll ledger index: reason=%s file=%s jobs=%d charged=%.2f", tostring(reason or "manual"), tostring(self.ledger.indexPath), tonumber(s.jobs) or 0, tonumber(s.charged) or 0)
    else
        rcWarn("Could not save persistent payroll ledger index: %s", tostring(self.ledger.indexPath))
    end
    return ok
end

function HelperPayroll:loadPeriodLedger(periodId)
    self:initLedgerPaths()
    periodId = periodId or self:getLedgerPeriodId()
    self.ledger.periodEntries = self.ledger.periodEntries or {}
    self.ledger.loadedPeriods = self.ledger.loadedPeriods or {}
    if self.ledger.loadedPeriods[periodId] == true then
        return self.ledger.periodEntries[periodId] or {}
    end

    local entries = {}
    local path = self:getPeriodLedgerPath(periodId)
    local shouldReadPeriod = path ~= nil and hpayFileExists(path) and self.ledger.hasIndexFile == true
    if path ~= nil and hpayFileExists(path) and self.ledger.hasIndexFile ~= true then
        rcLog("Ignoring existing period ledger until index is created: period=%s file=%s", tostring(periodId), tostring(path))
    end
    if shouldReadPeriod then
        local xmlFile = loadXMLFile("HelperPayrollPeriodLedger", path)
        if xmlFile ~= nil and xmlFile ~= 0 then
            local i = 0
            while true do
                local key = string.format("helperPayrollLedger.entry(%d)", i)
                if hasXMLProperty ~= nil and not hasXMLProperty(xmlFile, key) then break end
                local id = hpayXmlGetString(xmlFile, key .. "#id", nil)
                if id == nil then break end
                local a = {
                    id = id,
                    entryType = hpayXmlGetString(xmlFile, key .. "#entryType", "job"),
                    status = hpayXmlGetString(xmlFile, key .. "#status", "charged"),
                    gameDate = hpayXmlGetString(xmlFile, key .. "#gameDate", "unknown"),
                    workMonotonicDay = hpayXmlGetOptionalInt(xmlFile, key .. "#workMonotonicDay"),
                    workDayTime = hpayXmlGetOptionalFloat(xmlFile, key .. "#workDayTime"),
                    paidMonotonicDay = hpayXmlGetOptionalInt(xmlFile, key .. "#paidMonotonicDay"),
                    paidDayTime = hpayXmlGetOptionalFloat(xmlFile, key .. "#paidDayTime"),
                    realDate = hpayXmlGetString(xmlFile, key .. "#realDate", ""),
                    billingMode = hpayXmlGetString(xmlFile, key .. "#billingMode", ""),
                    payrollMode = hpayXmlGetString(xmlFile, key .. "#payrollMode", ""),
                    profile = hpayXmlGetString(xmlFile, key .. "#profile", ""),
                    role = hpayXmlGetString(xmlFile, key .. "#role", ""),
                    helper = hpayXmlGetString(xmlFile, key .. "#helper", ""),
                    helperSlot = hpayXmlGetString(xmlFile, key .. "#helperSlot", ""),
                    helperIdentityId = hpayXmlGetString(xmlFile, key .. "#helperIdentityId", ""),
                    helperIdentitySource = hpayXmlGetString(xmlFile, key .. "#helperIdentitySource", ""),
                    helperMappingSource = hpayXmlGetString(xmlFile, key .. "#helperMappingSource", ""),
                    assignmentSnapshotSource = hpayXmlGetString(xmlFile, key .. "#assignmentSnapshotSource", ""),
                    helperSlotUsedForPayroll = tostring(hpayXmlGetBool(xmlFile, key .. "#helperSlotUsedForPayroll", false)),
                    workerRate = hpayXmlGetString(xmlFile, key .. "#workerRate", ""),
                    rate = tostring(hpayXmlGetFloat(xmlFile, key .. "#rate", 0)),
                    elapsedHours = tostring(hpayXmlGetFloat(xmlFile, key .. "#elapsedHours", 0)),
                    labour = tostring(hpayXmlGetFloat(xmlFile, key .. "#labour", 0)),
                    callout = tostring(hpayXmlGetFloat(xmlFile, key .. "#callout", 0)),
                    minimum = tostring(hpayXmlGetFloat(xmlFile, key .. "#minimum", 0)),
                    minimumApplied = tostring(hpayXmlGetBool(xmlFile, key .. "#minimumApplied", false)),
                    calculated = tostring(hpayXmlGetFloat(xmlFile, key .. "#calculated", 0)),
                    charged = tostring(hpayXmlGetFloat(xmlFile, key .. "#charged", 0)),
                    farmId = tostring(hpayXmlGetInt(xmlFile, key .. "#farmId", 0)),
                    jobType = hpayXmlGetString(xmlFile, key .. "#jobType", ""),
                    sequence = tostring(hpayXmlGetInt(xmlFile, key .. "#sequence", 0))
                }
                table.insert(entries, a)
                i = i + 1
            end
            delete(xmlFile)
        else
            rcWarn("Could not load persistent payroll period ledger XML: period=%s file=%s", tostring(periodId), tostring(path))
        end
    end
    self.ledger.periodEntries[periodId] = entries
    self.ledger.loadedPeriods[periodId] = true
    rcLog("Loaded persistent payroll period ledger: period=%s entries=%d file=%s", tostring(periodId), #entries, tostring(path))
    return entries
end

function HelperPayroll:savePeriodLedger(periodId)
    self:initLedgerPaths()
    periodId = periodId or self:getLedgerPeriodId()
    local entries = self.ledger.periodEntries ~= nil and self.ledger.periodEntries[periodId] or {}
    local path = self:getPeriodLedgerPath(periodId)
    if path == nil then return false end
    local lines = {}
    table.insert(lines, '<?xml version="1.0" encoding="utf-8" standalone="no" ?>')
    table.insert(lines, '<helperPayrollLedger' .. hpayXmlAttr("version", tostring(self.VERSION or "0.3.3.0")) .. hpayXmlAttr("period", periodId) .. hpayXmlAttr("savegame", self.persistence ~= nil and self.persistence.savegameName or "unknown") .. '>')
    for i, e in ipairs(entries or {}) do
        local attrs = ''
        local names = {"id","entryType","status","gameDate","workMonotonicDay","workDayTime","paidMonotonicDay","paidDayTime","realDate","billingMode","payrollMode","profile","role","helper","helperSlot","helperIdentityId","helperIdentitySource","helperMappingSource","assignmentSnapshotSource","helperSlotUsedForPayroll","workerRate","rate","elapsedHours","labour","callout","minimum","minimumApplied","calculated","charged","farmId","jobType","sequence"}
        for _, name in ipairs(names) do
            if e[name] ~= nil then attrs = attrs .. hpayXmlAttr(name, e[name]) end
        end
        table.insert(lines, '  <entry' .. attrs .. ' />')
    end
    table.insert(lines, '</helperPayrollLedger>')
    local ok = hpayWriteFile(path, lines)
    if not ok then rcWarn("Could not save persistent payroll period ledger: %s", tostring(path)) end
    return ok
end

function HelperPayroll:updateLedgerIndexForEntry(periodId, roleId, roleName, entry)
    self.ledger.index = self.ledger.index or self:createEmptyLedgerIndex()
    local idx = self.ledger.index
    hpayBumpSummary(idx.summary, entry)

    periodId = periodId or self:getLedgerPeriodId(entry.gameDate)
    local p = idx.periods[periodId]
    if p == nil then
        p = { id = periodId, jobs = 0, hours = 0, labour = 0, calculated = 0, charged = 0, minimumJobs = 0, payments = 0 }
        idx.periods[periodId] = p
        table.insert(idx.periodOrder, periodId)
    end
    hpayBumpSummary(p, entry)

    roleId = tostring(roleId or entry.workerRate or entry.role or "unknown")
    local r = idx.roles[roleId]
    if r == nil then
        r = { id = roleId, name = roleName or roleId, jobs = 0, hours = 0, labour = 0, calculated = 0, charged = 0, minimumJobs = 0, payments = 0 }
        idx.roles[roleId] = r
        table.insert(idx.roleOrder, roleId)
    end
    r.name = roleName or r.name or roleId
    hpayBumpSummary(r, entry)
end

function HelperPayroll:recordPersistentLedgerEntry(entry, reason)
    if entry == nil then return false end
    self:initLedgerPaths()
    if self.ledger.index == nil then self:loadLedgerIndex() end
    local periodId = self:getLedgerPeriodId(entry.gameDate)
    local entries
    if self.ledger.hasIndexFile == true then
        entries = self:loadPeriodLedger(periodId)
    else
        self.ledger.periodEntries = self.ledger.periodEntries or {}
        self.ledger.loadedPeriods = self.ledger.loadedPeriods or {}
        entries = self.ledger.periodEntries[periodId] or {}
        self.ledger.periodEntries[periodId] = entries
        self.ledger.loadedPeriods[periodId] = true
    end
    entry.id = entry.id or string.format("%s_%06d", tostring(periodId), (#entries + 1))
    table.insert(entries, entry)
    self:updateLedgerIndexForEntry(periodId, entry.workerRate or entry.role, entry.helper, entry)
    local okPeriod = self:savePeriodLedger(periodId)
    local okIndex = self:saveLedgerIndex(reason or "entry")
    rcLog("Persistent payroll ledger entry recorded: reason=%s period=%s id=%s type=%s status=%s charged=%.2f", tostring(reason or "entry"), tostring(periodId), tostring(entry.id), tostring(entry.entryType or "job"), tostring(entry.status or "recorded"), tonumber(entry.charged) or 0)
    return okPeriod and okIndex
end

function HelperPayroll:buildPersistentLedgerEntryFromWorkerEntry(entry, status)
    if entry == nil then return nil end
    return {
        entryType = "job",
        status = status or (tonumber(entry.charge) ~= nil and tonumber(entry.charge) > 0 and "charged" or "recorded"),
        gameDate = entry.gameDate,
        workMonotonicDay = entry.workMonotonicDay,
        workDayTime = entry.workDayTime,
        realDate = hpayRealTimestamp(),
        billingMode = entry.billingMode,
        payrollMode = entry.payrollMode,
        profile = entry.profileId,
        role = entry.helperRole,
        helper = entry.helperName,
        helperSlot = entry.helperSlot,
        helperIdentityId = entry.helperIdentityId,
        helperIdentitySource = entry.helperIdentitySource,
        helperMappingSource = entry.helperMappingSource,
        assignmentSnapshotSource = entry.assignmentSnapshotSource,
        helperSlotUsedForPayroll = tostring(entry.helperSlotUsedForPayroll == true),
        workerRate = entry.workerId,
        rate = string.format("%.2f", tonumber(entry.hourlyRate) or 0),
        elapsedHours = string.format("%.3f", tonumber(entry.elapsedHours) or 0),
        labour = string.format("%.2f", tonumber(entry.labourCharge) or 0),
        callout = string.format("%.2f", tonumber(entry.calloutFee) or 0),
        minimum = string.format("%.2f", tonumber(entry.minimumCharge) or 0),
        minimumApplied = tostring(entry.appliedMinimum == true),
        calculated = string.format("%.2f", tonumber(entry.calculatedJobCharge) or 0),
        charged = string.format("%.2f", tonumber(entry.charge) or 0),
        farmId = entry.farmId,
        jobType = entry.jobType,
        sequence = entry.sequence
    }
end

function HelperPayroll:recordPersistentDailyPayment(daily, charge, minimumApplied)
    if daily == nil then return false end
    local e = {
        entryType = "payment",
        status = "paid",
        gameDate = daily.gameDate or self:getGameDateKey(),
        workMonotonicDay = daily.workMonotonicDay,
        workDayTime = daily.workDayTime,
        paidMonotonicDay = daily.paidMonotonicDay,
        paidDayTime = daily.paidDayTime,
        realDate = hpayRealTimestamp(),
        billingMode = "dailyPayroll",
        payrollMode = self.settings.payrollMode,
        profile = daily.profileId,
        role = daily.helperRole,
        helper = daily.helperName,
        helperSlot = daily.helperSlot,
        helperIdentityId = daily.helperIdentityId,
        helperIdentitySource = daily.helperIdentitySource,
        helperMappingSource = daily.helperMappingSource,
        helperSlotUsedForPayroll = "",
        workerRate = daily.workerId,
        rate = string.format("%.2f", tonumber(daily.hourlyRate) or 0),
        elapsedHours = string.format("%.3f", tonumber(daily.hours) or 0),
        labour = string.format("%.2f", tonumber(daily.labour) or 0),
        callout = string.format("%.2f", tonumber(self.settings.workerCalloutFee) or 0),
        minimum = string.format("%.2f", tonumber(self.settings.minimumWorkerCharge) or 0),
        minimumApplied = tostring(minimumApplied == true),
        calculated = string.format("%.2f", tonumber(charge) or 0),
        charged = string.format("%.2f", tonumber(charge) or 0),
        farmId = daily.farmId,
        jobType = "DailyPayroll",
        sequence = tostring(daily.key or "daily")
    }
    return self:recordPersistentLedgerEntry(e, "daily-payroll")
end

function HelperPayroll:buildLedgerSummaryLines()
    if self.ledger == nil or self.ledger.index == nil then self:loadLedgerIndex() end
    local idx = self.ledger.index or self:createEmptyLedgerIndex()
    local s = idx.summary or {}
    local lines = {}
    table.insert(lines, "HelperPayroll Persistent Ledger Summary")
    table.insert(lines, "Version: " .. tostring(self.VERSION or "0.3.3.0"))
    table.insert(lines, string.format("Savegame: %s", tostring(self.persistence ~= nil and self.persistence.savegameName or "unknown")))
    table.insert(lines, string.format("Ledger index: %s", tostring(self.ledger ~= nil and self.ledger.indexPath or "unknown")))
    table.insert(lines, string.format("Totals: jobs=%d payments=%d hours=%.3f labour=%s calculated=%s charged=%s minimumJobs=%d",
        tonumber(s.jobs) or 0, tonumber(s.payments) or 0, tonumber(s.hours) or 0, hpayFormatMoney(s.labour), hpayFormatMoney(s.calculated), hpayFormatMoney(s.charged), tonumber(s.minimumJobs) or 0))
    table.insert(lines, "")
    table.insert(lines, "Periods:")
    if #(idx.periodOrder or {}) == 0 then
        table.insert(lines, "- none")
    else
        for _, id in ipairs(idx.periodOrder or {}) do
            local p = idx.periods[id]
            if p ~= nil then
                table.insert(lines, string.format("- %s | jobs=%d payments=%d hours=%.3f charged=%s", tostring(id), tonumber(p.jobs) or 0, tonumber(p.payments) or 0, tonumber(p.hours) or 0, hpayFormatMoney(p.charged)))
            end
        end
    end
    return lines
end

function HelperPayroll:printLedgerSummary()
    for _, line in ipairs(self:buildLedgerSummaryLines()) do hpayPrintf("%s", line) end
end

function HelperPayroll:printLedgerRoles()
    if self.ledger == nil or self.ledger.index == nil then self:loadLedgerIndex() end
    local idx = self.ledger.index or self:createEmptyLedgerIndex()
    hpayPrintf("Persistent ledger role totals:")
    if #(idx.roleOrder or {}) == 0 then hpayPrintf("- none"); return end
    for _, id in ipairs(idx.roleOrder or {}) do
        local r = idx.roles[id]
        if r ~= nil then
            hpayPrintf("- %s (%s) | jobs=%d payments=%d hours=%s labour=%s charged=%s minimumJobs=%d", tostring(r.name), tostring(id), tonumber(r.jobs) or 0, tonumber(r.payments) or 0, hpFmtHours(r.hours), hpFmtMoney(r.labour), hpFmtMoney(r.charged), tonumber(r.minimumJobs) or 0)
        end
    end
end

function HelperPayroll:printLedgerMonth(year, month)
    local periodId = nil
    if month ~= nil then
        periodId = string.format("Y%03d_M%02d", tonumber(year) or 0, tonumber(month) or 0)
    else
        periodId = tostring(year or self:getLedgerPeriodId())
    end
    local entries = self:loadPeriodLedger(periodId)
    hpayPrintf("Persistent ledger month: period=%s entries=%d", tostring(periodId), #(entries or {}))
    for i, e in ipairs(entries or {}) do
        hpayPrintf("%03d id=%s type=%s status=%s date=%s helper=%s role=%s workerRate=%s hours=%s charged=%s", i, tostring(e.id), tostring(e.entryType), tostring(e.status), tostring(e.gameDate), tostring(e.helper), tostring(e.role), tostring(e.workerRate), hpFmtHours(e.elapsedHours), hpFmtMoney(e.charged))
    end
end

function HelperPayroll:printLedgerJobs(limit, periodId)
    limit = math.floor(tonumber(limit) or 10)
    if limit < 1 then limit = 10 end
    periodId = periodId or self:getLedgerPeriodId(self:getGameDateKey())
    local entries = self:loadPeriodLedger(periodId)
    local count = #(entries or {})
    if count <= 0 then hpayPrintf("No persistent payroll entries for period %s", tostring(periodId)); return end
    local first = math.max(1, count - limit + 1)
    hpayPrintf("Persistent payroll entries: period=%s showing %d-%d of %d", tostring(periodId), first, count, count)
    for i = first, count do
        local e = entries[i]
        hpayPrintf("%03d id=%s type=%s status=%s date=%s helper=%s identityId=%s role=%s workerRate=%s hours=%s rate=%s labour=%s calculated=%s charged=%s", i, tostring(e.id), tostring(e.entryType), tostring(e.status), tostring(e.gameDate), tostring(e.helper), tostring(e.helperIdentityId or "-"), tostring(e.role), tostring(e.workerRate), hpFmtHours(e.elapsedHours), hpFmtRate(e.rate), hpFmtMoney(e.labour), hpFmtMoney(e.calculated), hpFmtMoney(e.charged))
    end
end

function HelperPayroll:exportLedgerReport(reportName)
    local safeName = hpaySafeFileName(reportName or "helperPayrollLedgerReport")
    local path = self:getReportPath(safeName)
    if path == nil then hpayPrintf("Ledger report export failed: no path resolved"); return false end
    local lines = self:buildLedgerSummaryLines()
    local ok = hpayWriteFile(path, lines)
    if ok then hpayPrintf("Ledger report exported: %s", tostring(path)) else hpayPrintf("Ledger report export failed: %s", tostring(path)) end
    return ok
end

-- ===== Payroll reporting =====================================================

function HelperPayroll:getReportPath(reportName)
    self:initPersistencePaths()
    local dir = self.persistence ~= nil and self.persistence.savegameDir or nil
    if dir == nil or dir == "" then
        return nil
    end
    return dir .. tostring(reportName or "helperPayrollReport") .. ".txt"
end

function HelperPayroll:buildSessionReportLines()
    local lines = {}
    local dateKey = self:getGameDateKey()
    local roleId, roleName, rate, profileId = self:getSelectedRoleInfo()

    table.insert(lines, "HelperPayroll Report")
    table.insert(lines, string.format("Version: %s", tostring(self.VERSION or "0.3.3.0")))
    table.insert(lines, string.format("Savegame: %s", tostring(self.persistence ~= nil and self.persistence.savegameName or "unknown")))
    table.insert(lines, string.format("Game date: %s", tostring(dateKey)))
    table.insert(lines, string.format("Payroll mode: %s", tostring(self.settings.payrollMode)))
    table.insert(lines, string.format("Billing mode: %s", tostring(self.settings.billingMode)))
    table.insert(lines, string.format("Active profile: %s", tostring(profileId)))
    table.insert(lines, string.format("Selected role: %s (%s/hr)", tostring(roleName), hpayFormatMoney(rate)))
    table.insert(lines, "")

    local entries = tonumber(self.workerLedgerCount) or 0
    table.insert(lines, string.format("Session ledger: jobs=%d totalCharged=%s", entries, hpayFormatMoney(self.workerLedgerTotal)))

    local grouped = {}
    local order = {}
    for i = 1, entries do
        local e = self.workerLedger ~= nil and self.workerLedger[i] or nil
        if e ~= nil then
            local key = table.concat({ tostring(e.profileId or "default"), tostring(e.workerId or "unknown"), tostring(e.helperName or e.workerName or "Worker"), tostring(e.helperRole or "Worker") }, "|")
            local g = grouped[key]
            if g == nil then
                g = {
                    profileId = e.profileId,
                    workerId = e.workerId,
                    helperName = e.helperName or e.workerName,
                    helperRole = e.helperRole,
                    jobs = 0,
                    hours = 0,
                    labour = 0,
                    charged = 0,
                    calculated = 0,
                    minimums = 0,
                    callout = 0,
                    rate = e.hourlyRate
                }
                grouped[key] = g
                table.insert(order, key)
            end
            g.jobs = g.jobs + 1
            g.hours = g.hours + (tonumber(e.elapsedHours) or 0)
            g.labour = g.labour + (tonumber(e.labourCharge) or 0)
            g.charged = g.charged + (tonumber(e.charge) or 0)
            g.calculated = g.calculated + (tonumber(e.calculatedJobCharge) or 0)
            g.callout = g.callout + (tonumber(e.calloutFee) or 0)
            if e.appliedMinimum == true then
                g.minimums = g.minimums + 1
            end
        end
    end

    if #order > 0 then
        table.insert(lines, "")
        table.insert(lines, "By role/helper:")
        for _, key in ipairs(order) do
            local g = grouped[key]
            table.insert(lines, string.format("- %s | role=%s | workerRate=%s | jobs=%d | hours=%.3f | rate=%s/hr | labour=%s | calculated=%s | charged=%s | minimumJobs=%d",
                tostring(g.helperName or "Worker"),
                tostring(g.helperRole or "Worker"),
                tostring(g.workerId or "unknown"),
                tonumber(g.jobs) or 0,
                tonumber(g.hours) or 0,
                hpayFormatMoney(g.rate),
                hpayFormatMoney(g.labour),
                hpayFormatMoney(g.calculated),
                hpayFormatMoney(g.charged),
                tonumber(g.minimums) or 0
            ))
        end
    end

    local dailyRows = 0
    for _, _ in pairs(self.workerDailyLedger or {}) do
        dailyRows = dailyRows + 1
    end
    table.insert(lines, "")
    table.insert(lines, string.format("Daily ledger rows: %d", dailyRows))
    if dailyRows > 0 then
        for _, daily in pairs(self.workerDailyLedger or {}) do
            table.insert(lines, string.format("- %s | helper=%s | role=%s | jobs=%d | hours=%.3f | labour=%s | charged=%s | payrollApplied=%s | payrollCharge=%s",
                tostring(daily.gameDate or "unknown"),
                tostring(daily.helperName or "Worker"),
                tostring(daily.helperRole or "Worker"),
                tonumber(daily.jobs) or 0,
                tonumber(daily.hours) or 0,
                hpayFormatMoney(daily.labour),
                hpayFormatMoney(daily.charged),
                tostring(daily.payrollApplied == true),
                hpayFormatMoney(daily.payrollCharge)
            ))
        end
    end

    return lines
end

function HelperPayroll:printSessionReport()
    local lines = self:buildSessionReportLines()
    for _, line in ipairs(lines or {}) do
        hpayPrintf("%s", tostring(line))
    end
end

function HelperPayroll:printRecentJobs(limit)
    limit = math.floor(tonumber(limit) or 10)
    if limit < 1 then limit = 10 end
    local count = tonumber(self.workerLedgerCount) or 0
    if count <= 0 then
        hpayPrintf("No payroll jobs recorded in the current session")
        return
    end
    local first = math.max(1, count - limit + 1)
    hpayPrintf("Recent payroll jobs: showing %d-%d of %d", first, count, count)
    for i = first, count do
        local e = self.workerLedger[i]
        if e ~= nil then
            hpayPrintf("%02d seq=%s date=%s type=%s helper=%s identityId=%s role=%s workerRate=%s hours=%.3f rate=%.2f labour=%.2f calculated=%.2f charged=%.2f billingMode=%s",
                i,
                tostring(e.sequence),
                tostring(e.gameDate),
                tostring(e.jobType),
                tostring(e.helperName),
                tostring(e.helperIdentityId or "-"),
                tostring(e.helperRole),
                tostring(e.workerId),
                tonumber(e.elapsedHours) or 0,
                tonumber(e.hourlyRate) or 0,
                tonumber(e.labourCharge) or 0,
                tonumber(e.calculatedJobCharge) or 0,
                tonumber(e.charge) or 0,
                tostring(e.billingMode)
            )
        end
    end
end

function HelperPayroll:printDailyReport()
    local rows = 0
    for _, _ in pairs(self.workerDailyLedger or {}) do rows = rows + 1 end
    if rows <= 0 then
        hpayPrintf("No daily payroll rows recorded in the current session")
        return
    end
    hpayPrintf("Daily payroll rows: %d", rows)
    for _, daily in pairs(self.workerDailyLedger or {}) do
        hpayPrintf("date=%s helper=%s role=%s workerRate=%s jobs=%d hours=%.3f labour=%.2f charged=%.2f payrollApplied=%s payrollCharge=%.2f farmId=%s",
            tostring(daily.gameDate),
            tostring(daily.helperName),
            tostring(daily.helperRole),
            tostring(daily.workerId),
            tonumber(daily.jobs) or 0,
            tonumber(daily.hours) or 0,
            tonumber(daily.labour) or 0,
            tonumber(daily.charged) or 0,
            tostring(daily.payrollApplied == true),
            tonumber(daily.payrollCharge) or 0,
            tostring(daily.farmId)
        )
    end
end

function HelperPayroll:exportSessionReport(reportName)
    local safeName = hpaySafeFileName(reportName or "helperPayrollReport")
    local path = self:getReportPath(safeName)
    if path == nil then
        hpayPrintf("Report export failed: no savegame report path resolved")
        return false
    end

    local lines = self:buildSessionReportLines()
    local ok, err = pcall(function()
        local f = io.open(path, "w")
        if f == nil then
            error("io.open returned nil")
        end
        for _, line in ipairs(lines or {}) do
            f:write(tostring(line), "\n")
        end
        f:close()
    end)

    if not ok then
        hpayPrintf("Report export failed: %s", tostring(err))
        return false
    end

    hpayPrintf("Report exported: %s", tostring(path))
    return true
end

function HelperPayroll:hpayReport(...)
    local a, b, c = hpayNormalizeArgs(...)
    a = string.lower(tostring(a or "summary"))

    if a == "help" or a == "" then
        hpayPrintf("hpayReport commands:")
        hpayPrintf("  summary|status       print persistent ledger summary/index")
        hpayPrintf("  session              print current in-memory session report")
        hpayPrintf("  jobs [limit] [period] print recent persisted payroll entries for current/specified period")
        hpayPrintf("  month <year> <month> print a specific period ledger, e.g. hpayReport month 1 6")
        hpayPrintf("  roles                print persistent totals by role/helper rate")
        hpayPrintf("  daily                print current in-memory daily payroll rows")
        hpayPrintf("  export [name]        export persistent ledger summary")
        hpayPrintf("  exportSession [name] export current session report")
        return
    elseif a == "summary" or a == "status" then
        self:printLedgerSummary()
        return
    elseif a == "session" then
        self:printSessionReport()
        return
    elseif a == "jobs" or a == "recent" then
        self:printLedgerJobs(b, c)
        return
    elseif a == "month" or a == "period" then
        self:printLedgerMonth(b, c)
        return
    elseif a == "roles" then
        self:printLedgerRoles()
        return
    elseif a == "daily" then
        self:printDailyReport()
        return
    elseif a == "export" then
        self:exportLedgerReport(b or "helperPayrollLedgerReport")
        return
    elseif a == "exportsession" then
        self:exportSessionReport(b or "helperPayrollSessionReport")
        return
    end

    hpayPrintf("Unknown hpayReport subcommand '%s' (try: hpayReport help)", tostring(a))
end

-- ===== HelperProfiles-style console commands =================================
-- These are intentionally prefixed with hpay* so HelperPayroll does not collide
-- with HelperProfiles commands such as hpOverlay/hpCycle/hpDump.

function HelperPayroll:hpayOverlay(...)
    local a, b, c = hpayNormalizeArgs(...)
    a = string.lower(tostring(a or "help"))

    if a == "help" or a == "" then
        hpayPrintf("hpayOverlay commands:")
        hpayPrintf("  on|off|toggle       show/hide the payroll role list")
        hpayPrintf("  status              print current role-list state")
        hpayPrintf("  pos <x 0..1> <y 0..1> | anchor TL|TR|BL|BR")
        hpayPrintf("  scale <0.5..2.0> | width <0.15..0.90> | opacity <0..1> | font <0.010..0.030>")
        hpayPrintf("  rowgap <0.001..0.03> | maxrows <3..30> | pad <0..0.05>")
        hpayPrintf("  bg on|off | outline on|off | shadow on|off")
        hpayPrintf("  debounce <ms> | reset")
        return
    elseif a == "on" or a == "show" then
        if self:isRoleTypePayrollMode() then
            self.roleListVisible = true
            hpayPrintf("Payroll role list visible=true")
        else
            hpayPrintf("Payroll role list unavailable in payrollMode=%s", tostring(self.settings.payrollMode))
        end
        return
    elseif a == "off" or a == "hide" then
        self.roleListVisible = false
        hpayPrintf("Payroll role list visible=false")
        return
    elseif a == "toggle" then
        self:toggleRoleList()
        return
    elseif a == "status" then
        local roleId, roleName, rate, profileId = self:getSelectedRoleInfo()
        local ui = self.roleListUi or {}
        hpayPrintf("Overlay visible=%s payrollMode=%s profile=%s selectedRole=%s name=%s rate=%.2f",
            tostring(self.roleListVisible == true), tostring(self.settings.payrollMode), tostring(profileId), tostring(roleId), tostring(roleName), tonumber(rate) or 0)
        hpayPrintf("Overlay ui: anchor=%s x=%.3f y=%.3f scale=%.2f width=%.3f opacity=%.2f font=%.3f rowGap=%.3f pad=%.3f maxRows=%d bg=%s outline=%s shadow=%s debounceMs=%d",
            tostring(ui.anchor or "TR"), tonumber(ui.x) or 0, tonumber(ui.y) or 0, tonumber(ui.scale) or 1, tonumber(ui.width) or 0, tonumber(ui.opacity) or 0, tonumber(ui.fontSize) or 0, tonumber(ui.rowGap) or 0, tonumber(ui.pad) or 0, tonumber(ui.maxRows) or 10, tostring(ui.bgEnabled ~= false), tostring(ui.outline == true), tostring(ui.shadow == true), tonumber(self.settings.roleSelectorDebounceMs) or 450)
        return

    elseif a == "pos" then
        self.roleListUi.x = hpClamp(b, 0.0, 1.0, self.roleListUi.x)
        self.roleListUi.y = hpClamp(c, 0.0, 1.0, self.roleListUi.y)
        hpayPrintf("Overlay pos set to x=%.3f y=%.3f (anchor %s)", self.roleListUi.x, self.roleListUi.y, tostring(self.roleListUi.anchor))
        self:saveSavegameSettings("overlay-pos")
        return

    elseif a == "anchor" then
        local anchor = string.upper(tostring(b or ""))
        if anchor == "TL" or anchor == "TR" or anchor == "BL" or anchor == "BR" then
            self.roleListUi.anchor = anchor
            hpayPrintf("Overlay anchor=%s", anchor)
            self:saveSavegameSettings("overlay-anchor")
        else
            hpayPrintf("Usage: hpayOverlay anchor TL|TR|BL|BR")
        end
        return

    elseif a == "scale" then
        self.roleListUi.scale = hpClamp(b, 0.5, 2.0, self.roleListUi.scale)
        hpayPrintf("Overlay scale=%.2f", self.roleListUi.scale)
        self:saveSavegameSettings("overlay-scale")
        return

    elseif a == "width" then
        self.roleListUi.width = hpClamp(b, 0.15, 0.90, self.roleListUi.width)
        hpayPrintf("Overlay width=%.3f", self.roleListUi.width)
        self:saveSavegameSettings("overlay-width")
        return

    elseif a == "opacity" then
        self.roleListUi.opacity = hpClamp(b, 0.0, 1.0, self.roleListUi.opacity)
        hpayPrintf("Overlay opacity=%.2f", self.roleListUi.opacity)
        self:saveSavegameSettings("overlay-opacity")
        return

    elseif a == "font" then
        self.roleListUi.fontSize = hpClamp(b, 0.010, 0.030, self.roleListUi.fontSize)
        hpayPrintf("Overlay fontSize=%.3f", self.roleListUi.fontSize)
        self:saveSavegameSettings("overlay-font")
        return

    elseif a == "rowgap" then
        self.roleListUi.rowGap = hpClamp(b, 0.001, 0.030, self.roleListUi.rowGap)
        hpayPrintf("Overlay rowGap=%.3f", self.roleListUi.rowGap)
        self:saveSavegameSettings("overlay-rowgap")
        return

    elseif a == "maxrows" then
        self.roleListUi.maxRows = math.floor(hpClamp(b, 3, 30, self.roleListUi.maxRows))
        hpayPrintf("Overlay maxRows=%d", self.roleListUi.maxRows)
        self:saveSavegameSettings("overlay-maxrows")
        return

    elseif a == "pad" then
        self.roleListUi.pad = hpClamp(b, 0.0, 0.050, self.roleListUi.pad)
        hpayPrintf("Overlay pad=%.3f", self.roleListUi.pad)
        self:saveSavegameSettings("overlay-pad")
        return

    elseif a == "bg" then
        local bol = hpBoolArg(b)
        if bol == nil then hpayPrintf("Usage: hpayOverlay bg on|off"); return end
        self.roleListUi.bgEnabled = bol
        hpayPrintf("Overlay background=%s", tostring(self.roleListUi.bgEnabled))
        self:saveSavegameSettings("overlay-bg")
        return

    elseif a == "outline" then
        local bol = hpBoolArg(b)
        if bol == nil then hpayPrintf("Usage: hpayOverlay outline on|off"); return end
        self.roleListUi.outline = bol
        hpayPrintf("Overlay outline=%s", tostring(self.roleListUi.outline))
        self:saveSavegameSettings("overlay-outline")
        return

    elseif a == "shadow" then
        local bol = hpBoolArg(b)
        if bol == nil then hpayPrintf("Usage: hpayOverlay shadow on|off"); return end
        self.roleListUi.shadow = bol
        hpayPrintf("Overlay shadow=%s", tostring(self.roleListUi.shadow))
        self:saveSavegameSettings("overlay-shadow")
        return

    elseif a == "debounce" then
        local ms = tonumber(b)
        if ms == nil then hpayPrintf("Usage: hpayOverlay debounce <ms>"); return end
        self.settings.roleSelectorDebounceMs = math.max(0, math.floor(ms))
        hpayPrintf("Role selector debounce=%d ms", self.settings.roleSelectorDebounceMs)
        self:saveSavegameSettings("overlay-debounce")
        return

    elseif a == "reset" then
        hpSetRoleListDefaults()
        hpayPrintf("Overlay reset to defaults")
        self:saveSavegameSettings("overlay-reset")
        return
    end

    hpayPrintf("Unknown hpayOverlay subcommand '%s' (try: hpayOverlay help)", tostring(a))
end

function HelperPayroll:hpayRole(...)
    local a, b = hpayNormalizeArgs(...)
    a = string.lower(tostring(a or "help"))

    if a == "help" or a == "" then
        hpayPrintf("hpayRole commands:")
        hpayPrintf("  show|status         print selected role")
        hpayPrintf("  next|prev           cycle selected role")
        hpayPrintf("  set <id|index|name> select a role immediately")
        hpayPrintf("  list                list available roles")
        return
    elseif a == "show" or a == "status" then
        local roleId, roleName, rate, profileId = self:getSelectedRoleInfo()
        hpayPrintf("Selected role: profile=%s role=%s name=%s rate=%.2f payrollMode=%s",
            tostring(profileId), tostring(roleId), tostring(roleName), tonumber(rate) or 0, tostring(self.settings.payrollMode))
        self:showRoleMessage(string.format("Helper Payroll Role: %s (%.2f/hr)", tostring(roleName), tonumber(rate) or 0))
        return
    elseif a == "next" then
        self:selectRoleByOffset(1)
        return
    elseif a == "prev" or a == "previous" then
        self:selectRoleByOffset(-1)
        return
    elseif a == "set" then
        if b == nil or b == "" then
            hpayPrintf("Usage: hpayRole set <id|index|name>")
            return
        end
        self:setSelectedRole(b, "console")
        return
    elseif a == "list" then
        local _, profileId = self:getActiveProfile()
        local order = self:getWorkerRateOrder(profileId)
        hpayPrintf("Available payroll roles for profile=%s:", tostring(profileId))
        if order ~= nil then
            for i, roleId in ipairs(order) do
                local worker = self:getWorkerRateById(profileId, roleId)
                local name = worker ~= nil and worker.name or roleId
                local rate = worker ~= nil and tonumber(worker.hourlyRate) or 0
                local marker = tostring(roleId) == tostring(self.settings.selectedRole) and " *" or ""
                hpayPrintf("  %02d  id=%s  name=%s  rate=%.2f%s", i, tostring(roleId), tostring(name), tonumber(rate) or 0, marker)
            end
        end
        return
    end

    hpayPrintf("Unknown hpayRole subcommand '%s' (try: hpayRole help)", tostring(a))
end


function HelperPayroll:hpayProfiles(...)
    local a = hpayNormalizeArgs(...)
    a = string.lower(tostring(a or "status"))

    if a == "help" or a == "" then
        hpayPrintf("hpayProfiles commands:")
        hpayPrintf("  status              show HelperProfiles mod/API integration status")
        hpayPrintf("  slots               list HelperProfiles A-J identities and HelperPayroll slot mappings")
        hpayPrintf("  refresh             refresh and display integration status")
        return
    end

    if a == "refresh" or a == "reload" then
        a = "status"
    end

    local status = self:getHelperProfilesStatus()

    if a == "status" then
        hpayPrintf(
            "HelperProfiles integration: available=%s modLoaded=%s detection=%s apiAvailable=%s source=%s payrollMode=%s profile=%s standaloneRoleInputsSuppressed=%s",
            tostring(status.available == true),
            tostring(status.modLoaded == true),
            tostring(status.detectionSource or "none"),
            tostring(status.apiAvailable == true),
            tostring(status.source),
            tostring(self.settings.payrollMode),
            tostring(self.settings.activePayrollProfile),
            tostring(self:shouldSuppressStandaloneRoleInputs())
        )
        hpayPrintf(
            "HelperProfiles API: apiVersion=%s modVersion=%s profiles=%d selectedSlot=%s selectedName=%s pickMode=%s",
            tostring(status.apiVersion or "-"),
            tostring(status.helperProfilesVersion or "-"),
            tonumber(status.profileCount) or 0,
            tostring(status.selectedSlot or "-"),
            tostring(status.selectedName or "-"),
            tostring(status.pickMode or "-")
        )

        if self:shouldSuppressStandaloneRoleInputs() then
            hpayPrintf("HelperProfiles owns ';' and modified ';' controls. HelperPayroll standalone role cycle/list keybinds are suppressed for this session.")
        end

        if status.available then
            if self:isHelperSlotPayrollMode() then
                hpayPrintf("helperSlot mode active. job.helperIndex selects A-J; HelperProfiles API supplies live identity and HelperPayroll applies the per-save identity/slot payroll mapping.")
            else
                hpayPrintf("HelperProfiles is integrated, but roleType mode remains active and uses the selected payroll role.")
            end
        elseif status.modLoaded then
            hpayPrintf("HelperProfiles is loaded but does not expose the required shared API. Install/update the API-enabled HelperProfiles build.")
            hpayPrintf("HelperPayroll standalone roleType mode remains available.")
        else
            hpayPrintf("HelperProfiles is not enabled in this game session. HelperPayroll standalone roleType mode remains available.")
        end
        return
    elseif a == "slots" or a == "list" then
        local _, profileId = self:getActiveProfile()
        hpayPrintf("HelperProfiles/HelperPayroll slot mapping: profile=%s payrollMode=%s source=%s", tostring(profileId), tostring(self.settings.payrollMode), tostring(status.source))
        for i = 1, 10 do
            local slot = string.char(string.byte("A") + i - 1)
            local hpInfo = self:getHelperProfilesSlotInfo(slot)
            local hpName = hpInfo ~= nil and hpInfo.displayName or ("Helper " .. slot)
            local identityId = hpInfo ~= nil and hpInfo.identityId or ("slot:" .. slot)
            local workerRate, mapping, mappingSource = self:getEffectiveHelperProfilesRole(hpInfo, slot, profileId)
            local worker = self:getWorkerRateById(profileId, workerRate)
            local rate = worker ~= nil and tonumber(worker.hourlyRate) or 0
            local marker = hpInfo ~= nil and hpInfo.selected and " *selected" or ""
            hpayPrintf(
                "  %s  HelperProfiles=%s  identityId=%s  mappingSource=%s  workerRate=%s  rate=%.2f%s",
                slot,
                tostring(hpName),
                tostring(identityId),
                tostring(mappingSource),
                tostring(workerRate),
                tonumber(rate) or 0,
                marker
            )
        end
        return
    end

    hpayPrintf("Unknown hpayProfiles subcommand '%s' (try: hpayProfiles help)", tostring(a))
end

function HelperPayroll:getPolicyTemplateStatusValues()
    self:initPolicyConfigPaths()
    local path = self.policyConfig ~= nil and self.policyConfig.activePath or self.CONFIG_FILE
    local source = self.policyConfig ~= nil and self.policyConfig.source or "unknown"
    if path == nil or path == "" then
        return nil
    end

    local xmlFile = loadXMLFile("helperPayrollPolicyStatusRead", path)
    if xmlFile == nil or xmlFile == 0 then
        return nil
    end

    local values = {
        source = source,
        path = path,
        payrollMode = getXmlStringOrDefault(xmlFile, "helperPayroll.settings.payrollMode", "roleType"),
        billingMode = getXmlStringOrDefault(xmlFile, "helperPayroll.settings.billingMode", "onJobFinish"),
        activePayrollProfile = getXmlStringOrDefault(xmlFile, "helperPayroll.settings.activePayrollProfile", "default"),
        selectedRole = getXmlStringOrDefault(xmlFile, "helperPayroll.settings.selectedRole", "standard"),
        fallbackRole = getXmlStringOrDefault(xmlFile, "helperPayroll.settings.fallbackRole", "standard"),
        minimumWorkerCharge = getXmlFloatOrDefault(xmlFile, "helperPayroll.settings.minimumWorkerCharge", 0),
        workerCalloutFee = getXmlFloatOrDefault(xmlFile, "helperPayroll.settings.workerCalloutFee", 0),
        payrollHour = getXmlFloatOrDefault(xmlFile, "helperPayroll.settings.payrollHour", 18),
        roundWorkerCharges = getXmlBoolOrDefault(xmlFile, "helperPayroll.settings.roundWorkerCharges", true),
    }
    delete(xmlFile)
    return values
end

function HelperPayroll:printPolicyTemplateStatus()
    self:initPolicyConfigPaths()
    hpayPrintf("Global/default policy config: source=%s active=%s external=%s bundled=%s generatedThisSession=%s",
        tostring(self.policyConfig ~= nil and self.policyConfig.source or "unknown"),
        tostring(self.policyConfig ~= nil and self.policyConfig.activePath or self.CONFIG_FILE),
        tostring(self.policyConfig ~= nil and self.policyConfig.externalPath or "nil"),
        tostring(self.policyConfig ~= nil and self.policyConfig.bundledPath or self.BUNDLED_CONFIG_FILE),
        tostring(self.policyConfig ~= nil and self.policyConfig.generated == true))

    local values = self:getPolicyTemplateStatusValues()
    if values ~= nil then
        hpayPrintf("Global/default policy values: payrollMode=%s billingMode=%s profile=%s selectedRole=%s fallbackRole=%s minimum=%.2f callout=%.2f payrollHour=%s round=%s",
            tostring(values.payrollMode), tostring(values.billingMode), tostring(values.activePayrollProfile), tostring(values.selectedRole), tostring(values.fallbackRole), tonumber(values.minimumWorkerCharge) or 0, tonumber(values.workerCalloutFee) or 0, tostring(values.payrollHour), tostring(values.roundWorkerCharges))
    else
        hpayPrintf("Global/default policy values: unavailable (config XML could not be read)")
    end
    hpayPrintf("Current save settings are separate. Use: hpaySave status")
end

function HelperPayroll:printSaveSettingsStatus()
    self:initPersistencePaths()
    local roleId, roleName, rate, profileId = self:getSelectedRoleInfo()
    hpayPrintf("Current save payroll settings: savegame=%s file=%s loaded=%s",
        tostring(self.persistence ~= nil and self.persistence.savegameName or "unknown"),
        tostring(self.persistence ~= nil and self.persistence.filePath or "nil"),
        tostring(self.persistence ~= nil and self.persistence.loaded == true))
    hpayPrintf("Effective active values: payrollMode=%s billingMode=%s profile=%s selectedRole=%s name=%s rate=%.2f fallbackRole=%s minimum=%.2f callout=%.2f payrollHour=%s round=%s helperProfilesMappings=%d",
        tostring(self.settings.payrollMode), tostring(self.settings.billingMode), tostring(profileId), tostring(roleId), tostring(roleName), tonumber(rate) or 0, tostring(self.settings.fallbackRole), tonumber(self.settings.minimumWorkerCharge) or 0, tonumber(self.settings.workerCalloutFee) or 0, tostring(self.settings.payrollHour), tostring(self.settings.roundWorkerCharges), #(self.helperProfilesMappings or {}))
end

function HelperPayroll:hpayConfig(...)
    local a = hpayNormalizeArgs(...)
    a = string.lower(tostring(a or "status"))

    if a == "help" or a == "" then
        hpayPrintf("hpayConfig commands:")
        hpayPrintf("  status              show global/default policy config source and template values")
        hpayPrintf("  reload              reload global/default policy, then apply current save overrides")
        hpayPrintf("  reset               regenerate global/default policy config from bundled defaults")
        hpayPrintf("  path                print editable global/default policy config path")
        hpayPrintf("  save                show current save/effective settings (alias for hpaySave status)")
        return
    elseif a == "status" then
        self:printPolicyTemplateStatus()
        return
    elseif a == "save" or a == "effective" then
        return self:hpaySave("status")
    elseif a == "path" then
        self:initPolicyConfigPaths()
        hpayPrintf("Editable global/default policy config path: %s", tostring(self.policyConfig ~= nil and self.policyConfig.externalPath or "nil"))
        return
    elseif a == "reload" then
        self:loadConfig()
        self:loadSavegameSettings()
        hpayPrintf("Global/default policy reloaded, then current save overrides applied: source=%s file=%s saveFile=%s profile=%s payrollMode=%s billingMode=%s",
            tostring(self.policyConfig ~= nil and self.policyConfig.source or "unknown"), tostring(self.CONFIG_FILE), tostring(self.persistence ~= nil and self.persistence.filePath or "nil"), tostring(self.settings.activePayrollProfile), tostring(self.settings.payrollMode), tostring(self.settings.billingMode))
        return
    elseif a == "reset" then
        local ok = self:resetExternalPolicyConfig("console")
        if ok then
            self:loadConfig()
            self:loadSavegameSettings()
            hpayPrintf("Global/default policy config reset and reloaded; current save overrides still applied")
        else
            hpayPrintf("Global/default policy config reset failed")
        end
        return
    end

    hpayPrintf("Unknown hpayConfig subcommand '%s' (try: hpayConfig help)", tostring(a))
end

function HelperPayroll:hpaySave(...)
    local a = hpayNormalizeArgs(...)
    a = string.lower(tostring(a or "status"))

    if a == "help" or a == "" then
        hpayPrintf("hpaySave commands:")
        hpayPrintf("  status              show current save/effective payroll settings")
        hpayPrintf("  path                print current save settings path")
        hpayPrintf("  reload              reload global/default policy, then current save settings")
        hpayPrintf("  reset               reset current save gameplay settings from global/default policy")
        return
    elseif a == "status" then
        self:printSaveSettingsStatus()
        return
    elseif a == "path" then
        self:initPersistencePaths()
        hpayPrintf("Current save payroll settings path: %s", tostring(self.persistence ~= nil and self.persistence.filePath or "nil"))
        return
    elseif a == "reload" then
        self:loadConfig()
        self:loadSavegameSettings()
        self:printSaveSettingsStatus()
        return
    elseif a == "reset" then
        self:loadConfig()
        self.helperProfilesMappings = {}
        self:rebuildHelperProfilesMappingIndexes()
        self:saveSavegameSettings("save-reset-from-global-policy")
        self:loadSavegameSettings()
        hpayPrintf("Current save payroll settings reset from global/default policy")
        self:printSaveSettingsStatus()
        return
    end

    hpayPrintf("Unknown hpaySave subcommand '%s' (try: hpaySave help)", tostring(a))
end

function HelperPayroll:hpayDump(...)
    local a = hpayNormalizeArgs(...)
    a = string.lower(tostring(a or "status"))

    if a == "help" then
        hpayPrintf("hpayDump commands:")
        hpayPrintf("  status              print HelperPayroll runtime status")
        hpayPrintf("  roles               list role rates")
        hpayPrintf("  ledger              print current ledger totals")
        hpayPrintf("  report              print payroll report summary")
        hpayPrintf("  config              print global/default policy and current save settings")
        hpayPrintf("  clock               print authoritative payroll clock and pending-row due state")
        return
    elseif a == "roles" then
        return self:hpayRole("list")
    elseif a == "ledger" then
        hpayPrintf("Worker ledger: entries=%d totalCharged=%.2f billingMode=%s dailyRows=%s",
            tonumber(self.workerLedgerCount) or 0,
            tonumber(self.workerLedgerTotal) or 0,
            tostring(self.settings.billingMode),
            tostring(self.workerDailyLedger ~= nil and "available" or "nil"))
        return
    elseif a == "report" then
        return self:hpayReport("summary")
    elseif a == "config" then
        self:printPolicyTemplateStatus()
        self:printSaveSettingsStatus()
        return
    elseif a == "clock" then
        local clock = self:getGameClockSnapshot()
        local payrollHour = tonumber(self.settings.payrollHour) or 18
        hpayPrintf("Payroll clock: date=%s monotonicDay=%s dayTimeMs=%s hour=%s payrollHour=%s pendingRows=%d",
            tostring(clock.dateKey), tostring(clock.monotonicDay), tostring(clock.dayTimeMs), tostring(clock.hour), tostring(payrollHour), self:countPendingDailyPayrollRows())
        for key, daily in pairs(self.workerDailyLedger or {}) do
            if daily ~= nil and daily.payrollApplied ~= true and (tonumber(daily.jobs) or 0) > 0 then
                local due, reason = self:isDailyPayrollRowDue(daily, clock, payrollHour)
                hpayPrintf("  pending key=%s helper=%s workDate=%s workMonotonicDay=%s jobs=%d labour=%.2f due=%s reason=%s",
                    tostring(key), tostring(daily.helperName), tostring(daily.gameDate), tostring(self:getStoredWorkMonotonicDay(daily)), tonumber(daily.jobs) or 0, tonumber(daily.labour) or 0, tostring(due), tostring(reason))
            end
        end
        return
    elseif a == "status" or a == "" then
        local roleId, roleName, rate, profileId = self:getSelectedRoleInfo()
        local hpStatus = self:getHelperProfilesStatus()
        hpayPrintf("Status: version=%s channel=%s payrollMode=%s billingMode=%s profile=%s selectedRole=%s name=%s rate=%.2f trackedJobs=%d pendingRows=%d helperProfilesLoaded=%s helperProfilesApi=%s helperProfilesApiVersion=%s roleListVisible=%s reportOverlayVisible=%s reportPage=%s saveFile=%s globalPolicySource=%s globalPolicyFile=%s",
            tostring(self.VERSION or "0.3.3.0"), tostring(self.RELEASE_CHANNEL or "beta-rc"),
            tostring(self.settings.payrollMode), tostring(self.settings.billingMode), tostring(profileId), tostring(roleId), tostring(roleName), tonumber(rate) or 0,
            tonumber(self.trackedAIJobCount) or 0, self:countPendingDailyPayrollRows(),
            tostring(hpStatus.modLoaded == true), tostring(hpStatus.apiAvailable == true), tostring(hpStatus.apiVersion or "-"),
            tostring(self.roleListVisible == true), tostring(self.reportOverlayVisible == true), tostring(self.reportOverlayPage or 1),
            tostring(self.persistence ~= nil and self.persistence.filePath or "nil"), tostring(self.policyConfig ~= nil and self.policyConfig.source or "unknown"), tostring(self.CONFIG_FILE))
        return
    end

    hpayPrintf("Unknown hpayDump subcommand '%s' (try: hpayDump help)", tostring(a))
end

local function hpayRegisterConsoleCommand(name, desc, methodName)
    local ok = false
    if g_console ~= nil and g_console.addCommand ~= nil then
        g_console:addCommand(name, desc, methodName, HelperPayroll)
        ok = true
    end
    if not ok and addConsoleCommand ~= nil then
        addConsoleCommand(name, desc, methodName, HelperPayroll)
        ok = true
    end
    _G[name] = function(...)
        local fn = HelperPayroll[methodName]
        if fn ~= nil then
            return fn(HelperPayroll, ...)
        end
    end
    return ok
end

function HelperPayroll:registerConsoleCommands()
    if self.consoleCommandsRegistered == true then
        return
    end

    hpayRegisterConsoleCommand("hpayOverlay", "Configure HelperPayroll role-list overlay", "hpayOverlay")
    hpayRegisterConsoleCommand("hpayRole", "Inspect or change HelperPayroll selected role", "hpayRole")
    hpayRegisterConsoleCommand("hpayDump", "Dump HelperPayroll runtime status", "hpayDump")
    hpayRegisterConsoleCommand("hpayReport", "Print or export HelperPayroll payroll reports", "hpayReport")
    hpayRegisterConsoleCommand("hpayConfig", "Inspect or reload HelperPayroll global/default policy config", "hpayConfig")
    hpayRegisterConsoleCommand("hpaySave", "Inspect or reload HelperPayroll current save settings", "hpaySave")
    hpayRegisterConsoleCommand("hpayProfiles", "Inspect HelperProfiles integration status", "hpayProfiles")
    self.consoleCommandsRegistered = true
    rcLog("Registered console commands: hpayOverlay, hpayRole, hpayDump, hpayReport, hpayConfig, hpaySave, hpayProfiles")
end

function HelperPayroll:installMoneyHooks()
    -- Legacy diagnostic retained only as a fallback marker. FS25 helper suppression is now done through AIJob.getPricePerMs hooks.
    rcLog("Farm.addMoney hook skipped. Using AIJob.getPricePerMs suppression for vanilla helper costs.")
end

function HelperPayroll:logRuntimeStartupStatus()
    local hpStatus = self:getHelperProfilesStatus()
    local apiState = hpStatus.apiAvailable and "available" or (hpStatus.modLoaded and "pending-or-unavailable" or "not-loaded")
    rcLog(
        "Runtime status: version=%s channel=%s payrollMode=%s billingMode=%s profile=%s pendingRows=%d HelperProfilesLoaded=%s HelperProfilesAPI=%s apiVersion=%s helperProfilesVersion=%s selectedSlot=%s selectedName=%s savegame=%s",
        tostring(self.VERSION or "0.3.3.0"),
        tostring(self.RELEASE_CHANNEL or "beta-rc"),
        tostring(self.settings.payrollMode),
        tostring(self.settings.billingMode),
        tostring(self.settings.activePayrollProfile or "default"),
        self:countPendingDailyPayrollRows(),
        tostring(hpStatus.modLoaded == true),
        tostring(apiState),
        tostring(hpStatus.apiVersion or "-"),
        tostring(hpStatus.helperProfilesVersion or "-"),
        tostring(hpStatus.selectedSlot or "-"),
        tostring(hpStatus.selectedName or "-"),
        tostring(self.persistence ~= nil and self.persistence.savegameName or "unknown")
    )
end

function HelperPayroll:processStartupStatus(dt)
    if self.startupStatusLogged == true or self.isInitialized ~= true then
        return
    end

    self.startupStatusElapsedMs = (self.startupStatusElapsedMs or 0) + (tonumber(dt) or 0)
    if self.startupStatusElapsedMs < (self.startupStatusDelayMs or 1500) then
        return
    end

    self.startupStatusLogged = true
    self:logRuntimeStartupStatus()
end

function HelperPayroll:initialize(reason)
    if self.isInitialized then
        rcLog("Initialize skipped; already initialized. reason=%s", tostring(reason))
        return
    end

    rcLog("Initializing. reason=%s modName=%s modDirectory=%s", tostring(reason), tostring(self.MOD_NAME), tostring(self.MOD_DIRECTORY))
    self.lastPayrollClockDay = nil
    self.lastPayrollClockHour = nil
    self.lastPayrollClockDayTime = nil
    self.startupStatusElapsedMs = 0
    self.startupStatusLogged = false
    self:loadConfig()
    self:loadSavegameSettings()
    self:loadLedgerIndex()
    if self.ledger ~= nil and self.ledger.hasIndexFile == true then
        self:loadPeriodLedger(self:getLedgerPeriodId(self:getGameDateKey()))
        self:recoverPendingDailyPayrollFromLedger()
    else
        rcLog("Persistent payroll ledger period load skipped until index exists")
    end
    self:buildMoneyTypeNameCache()
    self:installAIWorkerHooks()
    self:installMoneyHooks()
    if HelperPayrollMenu ~= nil and HelperPayrollMenu.register ~= nil then
        HelperPayrollMenu.register(self.MOD_DIRECTORY)
    end
    self.isInitialized = true
    rcLog("Initialized")
end

function HelperPayroll:onMissionStarted()
    self:initialize("onMissionStarted")
    self:registerConsoleCommands()
end

function HelperPayroll:loadMap(name)
    self:initialize("loadMap")
    self:registerConsoleCommands()
end

function HelperPayroll:onUpdate(dt)
    self:processStartupStatus(dt)
    self:scanActiveAIJobs(dt)
    self:processDailyPayroll(dt, false, "onUpdate")
    if self.roleFlashTime ~= nil and self.roleFlashTime > 0 then
        self.roleFlashTime = math.max(0, self.roleFlashTime - ((tonumber(dt) or 0) / 1000))
    end
end

function HelperPayroll:update(dt)
    -- Some FS script contexts call update instead of onUpdate.
    self:processStartupStatus(dt)
    self:scanActiveAIJobs(dt)
    self:processDailyPayroll(dt, false, "update")
    if self.roleFlashTime ~= nil and self.roleFlashTime > 0 then
        self.roleFlashTime = math.max(0, self.roleFlashTime - ((tonumber(dt) or 0) / 1000))
    end
end

function HelperPayroll:draw()
    self:drawReportOverlay()
    self:drawRoleList()
    self:drawRoleFlash()
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
        self:exportSessionReport("helperPayrollSessionReport")
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
    self:saveSavegameSettings("deleteMap")
    self:logAIPriceSuppressionSummary()
    self:removeInputActions()
    rcLog("deleteMap called")
    self.isInitialized = false
end

function HelperPayroll:onMissionLoaded(mission)
    self:initialize("onMissionLoaded")
end

function HelperPayroll:onStartMission()
    self:initialize("onStartMission")
end


if PlayerInputComponent ~= nil and PlayerInputComponent.registerGlobalPlayerActionEvents ~= nil and Utils ~= nil and Utils.appendedFunction ~= nil then
    PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(
        PlayerInputComponent.registerGlobalPlayerActionEvents,
        function(self, controlling)
            if HelperPayroll ~= nil and HelperPayroll.registerGlobalPlayerInputActions ~= nil then
                HelperPayroll:registerGlobalPlayerInputActions()
            end
        end
    )
    rcLog("Installed PlayerInputComponent action-event hook")
else
    rcWarn("PlayerInputComponent action-event hook not installed")
end

if PlayerInputComponent ~= nil and PlayerInputComponent.removeGlobalPlayerActionEvents ~= nil and Utils ~= nil and Utils.appendedFunction ~= nil then
    PlayerInputComponent.removeGlobalPlayerActionEvents = Utils.appendedFunction(
        PlayerInputComponent.removeGlobalPlayerActionEvents,
        function(self)
            if HelperPayroll ~= nil and HelperPayroll.removeGlobalPlayerInputActions ~= nil then
                HelperPayroll:removeGlobalPlayerInputActions()
            end
        end
    )
end

if Vehicle ~= nil and Vehicle.registerActionEvents ~= nil and Utils ~= nil and Utils.appendedFunction ~= nil then
    Vehicle.registerActionEvents = Utils.appendedFunction(
        Vehicle.registerActionEvents,
        function(self, isActiveForInput, isActiveForGUI)
            if HelperPayroll ~= nil and HelperPayroll.registerVehicleInputActions ~= nil then
                HelperPayroll:registerVehicleInputActions(self, isActiveForInput)
            end
        end
    )
    rcLog("Installed Vehicle action-event hook")
else
    rcWarn("Vehicle action-event hook not installed")
end

if Vehicle ~= nil and Vehicle.removeActionEvents ~= nil and Utils ~= nil and Utils.appendedFunction ~= nil then
    Vehicle.removeActionEvents = Utils.appendedFunction(
        Vehicle.removeActionEvents,
        function(self)
            if HelperPayroll ~= nil and HelperPayroll.removeVehicleInputActions ~= nil then
                HelperPayroll:removeVehicleInputActions(self)
            end
        end
    )
end

rcLog("Registering mod event listener")
addModEventListener(HelperPayroll)
rcLog("Mod event listener registered")
