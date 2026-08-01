-- FS25_HelperPayroll
-- Management GUI using the CropControlOverride-style FS25 ScreenElement/SmoothList technique.

local HPAY_GUI_MOD_DIRECTORY = g_currentModDirectory or ""

HelperPayrollMenu = {}

local HelperPayrollMenu_mt = Class(HelperPayrollMenu, ScreenElement)

local TAB_TEXTS = {"OVERVIEW", "BILLING", "ROLES", "WORKERS", "LEDGER", "HELP"}
local TAB_TOPICS = {"overview", "billing", "roles", "workers", "ledger", "help"}
local TOPIC_INDEX = {overview=1, billing=2, roles=3, workers=4, ledger=5, help=6}

local function fmtMoney(v)
    return string.format("%.2f", tonumber(v or 0) or 0)
end

local function fmtHour(v)
    return tostring(math.floor(tonumber(v or 0) or 0))
end

local function boolText(v)
    return v and "true" or "false"
end

local function copyTable(t)
    local r = {}
    if t ~= nil then
        for k,v in pairs(t) do r[k]=v end
    end
    return r
end

function HelperPayrollMenu.new(target, customMt)
    local self = ScreenElement.new(target, customMt or HelperPayrollMenu_mt)
    self.returnScreenName = ""
    self.currentTopic = "overview"
    self.rows = {}
    self.selectedRowIndex = nil
    self.selectedRow = nil
    self.draftSettings = {}
    self.draftRolePolicies = {}
    self.draftMappings = {}
    self.draftWorkerOverrides = {}
    self.stagedDirty = false
    self.suppressTabCallback = false
    self.suppressOptionCallback = false
    self.editControlsInitialised = false
    self.resetConfirmationArmed = false
    return self
end

function HelperPayrollMenu.register(modDirectory)
    if g_gui == nil then
        print("[HelperPayroll] GUI: g_gui is not available; cannot register management screen")
        return nil
    end

    if HelperPayrollMenu.INSTANCE ~= nil then
        return HelperPayrollMenu.INSTANCE
    end

    local controller = HelperPayrollMenu.new()
    local baseDir = modDirectory or HPAY_GUI_MOD_DIRECTORY or ""
    if (baseDir == nil or baseDir == "") and HelperPayroll ~= nil then
        baseDir = HelperPayroll.MOD_DIRECTORY or ""
    end
    if baseDir == nil then baseDir = "" end
    local last = baseDir:sub(-1)
    if baseDir ~= "" and last ~= "/" and last ~= "\\" then
        baseDir = baseDir .. "/"
    end

    local profiles = baseDir .. "gui/guiProfiles.xml"
    if fileExists == nil or fileExists(profiles) then
        pcall(function() g_gui:loadProfiles(profiles) end)
    end

    local filename = baseDir .. "gui/HelperPayrollMenu.xml"
    print("[HelperPayroll] GUI: loading management screen from " .. tostring(filename))

    if fileExists ~= nil and not fileExists(filename) then
        print("[HelperPayroll] GUI: XML file does not exist at " .. tostring(filename))
        return nil
    end

    local ok, result = pcall(function()
        return g_gui:loadGui(filename, "HelperPayrollMenu", controller)
    end)

    if not ok then
        print("[HelperPayroll] GUI: failed to load management screen: " .. tostring(result))
        return nil
    end

    HelperPayrollMenu.INSTANCE = controller
    print("[HelperPayroll] GUI: registered management screen HelperPayrollMenu")
    return controller
end

function HelperPayrollMenu.show(modDirectory, topic)
    local controller = HelperPayrollMenu.INSTANCE or HelperPayrollMenu.register(modDirectory)
    if controller == nil then
        return false
    end
    controller.currentTopic = topic or controller.currentTopic or "overview"
    controller:refreshDraftFromRuntime()
    controller:showTopic(controller.currentTopic)

    local ok, result = pcall(function()
        return g_gui:showGui("HelperPayrollMenu")
    end)
    if not ok then
        print("[HelperPayroll] GUI: failed to show management screen: " .. tostring(result))
        return false
    end
    return true
end

function HelperPayrollMenu:onCreate()
end

function HelperPayrollMenu:onOpen()
    HelperPayrollMenu:superClass().onOpen(self)
    self:setResetConfirmationArmed(false)
    self:refreshDraftFromRuntime()
    self:showTopic(self.currentTopic or "overview")
end

function HelperPayrollMenu:onClose()
    self:setResetConfirmationArmed(false)
    HelperPayrollMenu:superClass().onClose(self)
end

function HelperPayrollMenu:onGuiSetupFinished()
    HelperPayrollMenu:superClass().onGuiSetupFinished(self)
    self:setupTabs()
    if self.itemList ~= nil then
        self.itemList:setDataSource(self)
        self.itemList:setDelegate(self)
    end
    self:initialiseEditControls()
    self:refreshDraftFromRuntime()
    self:showTopic(self.currentTopic or "overview")
end

function HelperPayrollMenu:refreshDraftFromRuntime()
    local hp = HelperPayroll
    self.draftSettings = {}
    self.draftRolePolicies = {}
    self.draftMappings = {}
    self.draftWorkerOverrides = {}
    if hp ~= nil and hp.settings ~= nil then
        self.draftSettings.billingMode = hp.settings.billingMode or "onJobFinish"
        self.draftSettings.payrollHour = tonumber(hp.settings.payrollHour) or 18
        self.draftSettings.minimumWorkerCharge = tonumber(hp.settings.minimumWorkerCharge) or 0
        self.draftSettings.workerCalloutFee = tonumber(hp.settings.workerCalloutFee) or 0
        self.draftSettings.roundWorkerCharges = hp.settings.roundWorkerCharges == true
        self.draftSettings.selectedRole = hp.settings.selectedRole or "standard"
        self.draftSettings.fallbackRole = hp.settings.fallbackRole or "standard"
        self.draftSettings.payrollMode = hp.settings.payrollMode or "roleType"
        self.draftSettings.activePayrollProfile = hp.settings.activePayrollProfile or "default"
    end
    local profileId = self.draftSettings.activePayrollProfile or "default"
    if hp ~= nil and hp.workerRates ~= nil and hp.workerRates[profileId] ~= nil then
        for roleId, worker in pairs(hp.workerRates[profileId]) do
            local rate = tonumber(worker.rate)
            if rate == nil then rate = tonumber(worker.hourlyRate) or 0 end
            self.draftRolePolicies[roleId] = {
                payBasis = hp.normalisePayBasis ~= nil and hp:normalisePayBasis(worker.payBasis) or "hourly",
                rate = rate,
                minimumCallout = tonumber(worker.minimumCallout) or tonumber(hp.settings.minimumWorkerCharge) or 0
            }
        end
    end
    if hp ~= nil then
        for _, slot in ipairs(hp:getManagedHelperSlots()) do
            local slotInfo = hp.getHelperProfilesSlotInfo ~= nil and hp:getHelperProfilesSlotInfo(slot) or nil
            local roleId = hp.getEffectiveHelperProfilesRole ~= nil and select(1, hp:getEffectiveHelperProfilesRole(slotInfo, slot, profileId)) or (hp.settings.fallbackRole or "standard")
            self.draftMappings[slot] = roleId
            local mapping = hp.getHelperProfilesPayrollMapping ~= nil and select(1, hp:getHelperProfilesPayrollMapping(slotInfo, slot)) or nil
            local rolePolicy = self.draftRolePolicies[roleId] or {payBasis="hourly", rate=0, minimumCallout=0}
            self.draftWorkerOverrides[slot] = {
                compensationMode = mapping ~= nil and tostring(mapping.compensationMode or "inherit") or "inherit",
                payBasis = mapping ~= nil and (hp:normalisePayBasis(mapping.payBasis)) or rolePolicy.payBasis,
                rate = mapping ~= nil and tonumber(mapping.rate) or rolePolicy.rate,
                minimumCallout = mapping ~= nil and tonumber(mapping.minimumCallout) or rolePolicy.minimumCallout
            }
        end
    end
    self.stagedDirty = false
end

function HelperPayrollMenu:setupTabs()
    if self.subCategoryTabs == nil then return end
    for i, tab in ipairs(self.subCategoryTabs) do
        if tab ~= nil and tab.setText ~= nil then tab:setText(TAB_TEXTS[i] or tostring(i)) end
    end
end

function HelperPayrollMenu:getActiveTabIndex()
    return TOPIC_INDEX[self.currentTopic or "overview"] or 1
end

function HelperPayrollMenu:updateTabSelection()
    if self.subCategoryTabs == nil then return end
    local active = self:getActiveTabIndex()
    for i, tab in ipairs(self.subCategoryTabs) do
        if tab ~= nil and tab.setSelected ~= nil then
            pcall(function() tab:setSelected(i == active) end)
        end
    end
end

function HelperPayrollMenu:initialiseEditControls()
    if self.editControlsInitialised then return end
    self.suppressOptionCallback = true
    if self.valueOption ~= nil then
        if self.valueOption.setTexts ~= nil then self.valueOption:setTexts({"-"}) end
        if self.valueOption.setState ~= nil then self.valueOption:setState(1, true) end
        if self.valueOption.setDisabled ~= nil then self.valueOption:setDisabled(true) end
    end
    self.suppressOptionCallback = false
    self.editControlsInitialised = true
end

function HelperPayrollMenu:setTextSafe(element, text)
    if element ~= nil and element.setText ~= nil then element:setText(tostring(text or "")) end
end

function HelperPayrollMenu:setVisibleSafe(element, visible)
    if element ~= nil and element.setVisible ~= nil then element:setVisible(visible == true) end
end

function HelperPayrollMenu:setDisabledSafe(element, disabled)
    if element ~= nil and element.setDisabled ~= nil then element:setDisabled(disabled == true) end
end

function HelperPayrollMenu:showTopic(topic)
    self.currentTopic = topic or "overview"
    self:updateTabSelection()
    self.selectedRowIndex = 1
    self.selectedRow = nil
    self:buildRows()
    self:updateContent()
end

function HelperPayrollMenu:buildRows()
    local topic = self.currentTopic or "overview"
    local rows = {}
    local hp = HelperPayroll
    local profileId = (hp ~= nil and hp.settings ~= nil and hp.settings.activePayrollProfile) or self.draftSettings.activePayrollProfile or "default"

    if topic == "billing" then
        rows = {
            {id="payrollMode", label="Payroll mode", value=tostring(self.draftSettings.payrollMode or "roleType"), status="Editable", source="Savegame", editType="option", options={"roleType", "helperSlot"}, info="roleType assigns every new job to the selected payroll role. helperSlot uses the deployed A-T worker, with live HelperProfiles identity data when available."},
            {id="billingMode", label="Billing mode", value=tostring(self.draftSettings.billingMode or "onJobFinish"), status="Editable", source="Savegame", editType="option", options={"onJobFinish", "dailyPayroll"}, info="onJobFinish charges each completed job immediately. dailyPayroll aggregates each worker's completed work for the game day and settles it through payroll."},
            {id="payrollHour", label="Payroll hour", value=fmtHour(self.draftSettings.payrollHour), status="Editable", source="Savegame", editType="number", step=1, min=0, max=23, info="In dailyPayroll mode, pending rows settle at this in-game hour. Any unpaid row from an earlier game day is treated as overdue and settles automatically."},
            {id="minimumWorkerCharge", label="Legacy minimum", value=fmtMoney(self.draftSettings.minimumWorkerCharge), status="Editable", source="Savegame", editType="number", step=0.5, min=0, max=999, info="Compatibility fallback for old save data that has no per-role minimum. New payroll policies use the minimum call-out configured on each role or worker."},
            {id="workerCalloutFee", label="Callout fee", value=fmtMoney(self.draftSettings.workerCalloutFee), status="Editable", source="Savegame", editType="number", step=0.5, min=0, max=999, info="Flat callout fee: per job in onJobFinish mode, or once per worker and workday in dailyPayroll mode."},
            {id="roundWorkerCharges", label="Round charges", value=boolText(self.draftSettings.roundWorkerCharges), status="Editable", source="Savegame", editType="option", options={"false", "true"}, info="Round applied helper charges to the nearest currency cent."},
        }
    elseif topic == "roles" then
        local order = hp ~= nil and hp.getWorkerRateOrder ~= nil and hp:getWorkerRateOrder(profileId) or {}
        for _, roleId in ipairs(order or {}) do
            local worker = hp:getWorkerRateById(profileId, roleId)
            local name = worker ~= nil and worker.name or roleId
            local policy = self.draftRolePolicies[roleId] or {payBasis="hourly", rate=0, minimumCallout=0}
            local prefix = tostring(name) .. " - "
            table.insert(rows, {id="roleBasis:"..tostring(roleId), roleId=roleId, roleField="payBasis", label=prefix.."Pay basis", status=(roleId == self.draftSettings.selectedRole and "Selected" or "Editable"), source=tostring(profileId), editType="option", options={"hourly", "daily"}, info="Choose whether this role is paid by worked hour or once per worker per game day when used."})
            table.insert(rows, {id="roleRate:"..tostring(roleId), roleId=roleId, roleField="rate", label=prefix.."Rate", status="Editable", source=tostring(profileId), editType="number", step=1, min=0, max=999999, info="The amount paid per hour or per used game day, according to this role's pay basis."})
            table.insert(rows, {id="roleMinimum:"..tostring(roleId), roleId=roleId, roleField="minimumCallout", label=prefix.."Minimum call-out", status=policy.payBasis == "daily" and "Ignored for daily" or "Editable", source=tostring(profileId), editType="number", step=1, min=0, max=999999, info="Hourly roles are charged at least this amount whenever used. Daily roles ignore this setting."})
        end
    elseif topic == "workers" then
        local roleOrder = hp ~= nil and hp.getWorkerRateOrder ~= nil and hp:getWorkerRateOrder(profileId) or {}
        if roleOrder == nil or #roleOrder == 0 then
            roleOrder = {tostring(hp ~= nil and hp.settings ~= nil and hp.settings.fallbackRole or "standard")}
        end
        for _, slot in ipairs(hp:getManagedHelperSlots()) do
            local slotInfo = hp ~= nil and hp.getHelperProfilesSlotInfo ~= nil and hp:getHelperProfilesSlotInfo(slot) or nil
            local displayName = slotInfo ~= nil and slotInfo.displayName or ("Helper " .. slot)
            local identityId = slotInfo ~= nil and slotInfo.identityId or ("slot:" .. slot)
            local identitySource = slotInfo ~= nil and slotInfo.identitySource or "slotFallback"
            local selected = slotInfo ~= nil and slotInfo.selected == true
            local inUse = slotInfo ~= nil and slotInfo.inUse == true
            local status = selected and "Selected" or (inUse and "In use" or "Idle")
            local roleId = self.draftMappings[slot] or tostring(hp ~= nil and hp.settings ~= nil and hp.settings.fallbackRole or "standard")
            local rolePolicy = self.draftRolePolicies[roleId] or {payBasis="hourly", rate=0, minimumCallout=0}
            local override = self.draftWorkerOverrides[slot] or {compensationMode="inherit", payBasis=rolePolicy.payBasis, rate=rolePolicy.rate, minimumCallout=rolePolicy.minimumCallout}
            local custom = tostring(override.compensationMode) == "custom"
            local prefix = string.format("%s - %s - ", slot, tostring(displayName))
            table.insert(rows, {
                id="worker:" .. slot,
                mappingSlot=slot,
                identityId=identityId,
                label=prefix.."Role",
                status=status,
                source=slotInfo ~= nil and "HelperProfiles API" or "Slot fallback",
                editType="option",
                options=roleOrder,
                info=string.format("Identity: %s | Identity source: %s | Assign a HelperPayroll role to this worker. Mappings are stored in the current save.", tostring(identityId), tostring(identitySource))
            })
            table.insert(rows, {id="workerMode:"..slot, workerSlot=slot, workerOverrideField="compensationMode", label=prefix.."Pay settings", status=custom and "Custom" or "Inherited", source="Savegame", editType="option", options={"inherit", "custom"}, info="Inherit uses the assigned role policy. Custom enables this worker's own pay basis, rate, and minimum call-out."})
            table.insert(rows, {id="workerBasis:"..slot, workerSlot=slot, workerOverrideField="payBasis", label=prefix.."Pay basis", status=custom and "Editable" or "Inherited", source=custom and "Worker override" or "Role", editType=custom and "option" or nil, options={"hourly", "daily"}, info="Hourly pays for worked time. Daily pays this worker once per game day when used."})
            table.insert(rows, {id="workerRate:"..slot, workerSlot=slot, workerOverrideField="rate", label=prefix.."Rate", status=custom and "Editable" or "Inherited", source=custom and "Worker override" or "Role", editType=custom and "number" or nil, step=1, min=0, max=999999, info="The worker's custom hourly or daily rate. Switch Pay settings to custom to edit it."})
            table.insert(rows, {id="workerMinimum:"..slot, workerSlot=slot, workerOverrideField="minimumCallout", label=prefix.."Minimum call-out", status=not custom and "Inherited" or (override.payBasis == "daily" and "Ignored for daily" or "Editable"), source=custom and "Worker override" or "Role", editType=custom and "number" or nil, step=1, min=0, max=999999, info="Custom minimum for hourly work. Daily pay ignores this setting."})
        end
    elseif topic == "ledger" then
        local index = hp ~= nil and hp.ledger ~= nil and hp.ledger.index or nil
        local totals = index ~= nil and index.totals or nil
        rows = {
            {label="Total jobs", value=tostring(totals ~= nil and totals.jobs or 0), status="Read-only", source="Ledger"},
            {label="Total hours", value=string.format("%.3f", tonumber(totals ~= nil and totals.hours or 0) or 0), status="Read-only", source="Ledger"},
            {label="Labour value", value=fmtMoney(totals ~= nil and totals.labour or 0), status="Read-only", source="Ledger"},
            {label="Charged", value=fmtMoney(totals ~= nil and totals.charged or 0), status="Read-only", source="Ledger"},
            {label="Current period", value=tostring(hp ~= nil and hp.ledger ~= nil and hp.ledger.currentPeriodId or "-"), status="Read-only", source="Ledger"},
        }
    else
        rows = {}
    end
    self.rows = rows
end

function HelperPayrollMenu:buildBodyText()
    local hp = HelperPayroll
    local topic = self.currentTopic or "overview"
    if topic == "overview" then
        local roleName = "-"
        local rate = 0
        if hp ~= nil then
            local roleId, workerName, hourlyRate = hp:getSelectedRoleInfo()
            roleName = workerName or roleId or roleName
            rate = tonumber(hourlyRate) or 0
        end
        local hpStatus = hp ~= nil and hp.getHelperProfilesStatus ~= nil and hp:getHelperProfilesStatus() or nil
        local integration = "Standalone"
        if hpStatus ~= nil and hpStatus.available == true then
            integration = string.format("Connected (API v%s)", tostring(hpStatus.apiVersion or "?"))
        elseif hpStatus ~= nil and hpStatus.modLoaded == true then
            integration = "Loaded (API unavailable)"
        end
        local pendingRows = hp ~= nil and hp.countPendingDailyPayrollRows ~= nil and hp:countPendingDailyPayrollRows() or 0
        local roleBasis = "hourly"
        if hp ~= nil and hp.getRoleCompensationPolicy ~= nil then
            local roleId = hp.settings ~= nil and hp.settings.selectedRole or "standard"
            local policy = hp:getRoleCompensationPolicy(hp.settings.activePayrollProfile, roleId)
            if policy ~= nil then roleBasis = policy.payBasis or roleBasis end
        end
        return string.format("Profile: %s\nPayroll mode: %s\nPayment schedule: %s\nSelected role: %s (%.2f/%s)\nGlobal callout fee: %.2f\nHelperProfiles: %s\nPending payroll rows: %d\nCurrent-save settings: %s\n\nUse BILLING for payment timing, ROLES for default compensation, WORKERS for named-worker overrides, and LEDGER for accumulated history.", tostring(hp and hp.settings and hp.settings.activePayrollProfile or "-"), tostring(hp and hp.settings and hp.settings.payrollMode or "-"), tostring(hp and hp.settings and hp.settings.billingMode or "-"), tostring(roleName), tonumber(rate) or 0, roleBasis == "daily" and "day" or "hr", tonumber(hp and hp.settings and hp.settings.workerCalloutFee or 0) or 0, tostring(integration), tonumber(pendingRows) or 0, tostring(hp and hp.persistence and hp.persistence.filePath or "-"))
    elseif topic == "help" then
        return "HelperPayroll Management\n\nChanges are staged until APPLY is pressed. APPLY writes gameplay settings to the current save only; it does not overwrite the global default policy. DISCARD restores the currently loaded values.\n\nROLES defines the default pay basis, rate, and hourly minimum call-out. WORKERS can inherit those settings or override all three for a named A-T worker.\n\nHourly pay is hours multiplied by rate, subject to the minimum call-out. Daily pay is charged once per worker per game day when that worker completes work. Payment schedule is separate: onJobFinish settles immediately, while dailyPayroll settles at the configured payroll hour."
    end
    return ""
end

function HelperPayrollMenu:updateContent()
    local tableVisible = self.currentTopic == "billing" or self.currentTopic == "roles" or self.currentTopic == "workers" or self.currentTopic == "ledger"
    self:setVisibleSafe(self.tableContainer, tableVisible)
    self:setVisibleSafe(self.bodyTextElement, not tableVisible)
    self:setTextSafe(self.bodyTextElement, self:buildBodyText())
    if self.itemList ~= nil then
        self.itemList:reloadData()
        if #self.rows > 0 and self.itemList.setSelectedIndex ~= nil then
            pcall(function() self.itemList:setSelectedIndex(1, true) end)
        end
    end
    self:setVisibleSafe(self.itemListSliderBox, #self.rows > 14)
    self.selectedRow = self.rows[self.selectedRowIndex or 1]
    self:updateSelectedDetails()
end

-- SmoothList data source / delegate
function HelperPayrollMenu:getNumberOfSections() return 1 end
function HelperPayrollMenu:getNumberOfItemsInSection(list, section) return #self.rows end
function HelperPayrollMenu:getTitleForSectionHeader(list, section) return nil end
function HelperPayrollMenu:getSectionHeaderHeight(list, section) return 0 end

function HelperPayrollMenu:setCellVisible(cell, name, visible)
    local e = cell ~= nil and cell.getDescendantByName ~= nil and cell:getDescendantByName(name) or nil
    if e ~= nil then
        if e.setVisible ~= nil then e:setVisible(visible == true) end
        if e.setDisabled ~= nil then e:setDisabled(visible ~= true) end
    end
    return e
end

function HelperPayrollMenu:populateCellForItemInSection(list, section, index, cell)
    local row = self.rows[index]
    if row == nil or cell == nil then return end
    local function set(name, value)
        local e = cell.getDescendantByName ~= nil and cell:getDescendantByName(name) or nil
        if e ~= nil and e.setText ~= nil then e:setText(tostring(value or "")) end
        return e
    end

    local editable = row.editType ~= nil
    set("cellItem", row.label)
    set("cellValue", editable and self:formatDraftValue(row) or row.value)
    set("cellStatus", row.status or "")
    set("cellSource", row.source or "")

    local prev = self:setCellVisible(cell, "cellPrev", editable)
    local next = self:setCellVisible(cell, "cellNext", editable)
    if prev ~= nil then prev.hpayRowIndex = index end
    if next ~= nil then next.hpayRowIndex = index end
end

function HelperPayrollMenu:onListSelectionChanged(list, section, index)
    self.selectedRowIndex = index
    self.selectedRow = self.rows[index]
    self:updateSelectedDetails()
end

function HelperPayrollMenu:getDraftValue(row)
    if row == nil then return nil end
    if row.id == "payrollMode" then return self.draftSettings.payrollMode end
    if row.id == "billingMode" then return self.draftSettings.billingMode end
    if row.id == "payrollHour" then return self.draftSettings.payrollHour end
    if row.id == "minimumWorkerCharge" then return self.draftSettings.minimumWorkerCharge end
    if row.id == "workerCalloutFee" then return self.draftSettings.workerCalloutFee end
    if row.id == "roundWorkerCharges" then return self.draftSettings.roundWorkerCharges end
    if row.mappingSlot ~= nil then return self.draftMappings[row.mappingSlot] end
    if row.roleId ~= nil and row.roleField ~= nil then
        local policy = self.draftRolePolicies[row.roleId] or {}
        return policy[row.roleField]
    end
    if row.workerSlot ~= nil and row.workerOverrideField ~= nil then
        local override = self.draftWorkerOverrides[row.workerSlot] or {}
        if tostring(override.compensationMode or "inherit") ~= "custom" and row.workerOverrideField ~= "compensationMode" then
            local roleId = self.draftMappings[row.workerSlot]
            local policy = self.draftRolePolicies[roleId] or {}
            return policy[row.workerOverrideField]
        end
        return override[row.workerOverrideField]
    end
    return row.value
end

function HelperPayrollMenu:formatDraftValue(row)
    local v = self:getDraftValue(row)
    if row == nil then return "-" end
    if row.id == "roundWorkerCharges" then return boolText(v == true or tostring(v) == "true") end
    if row.id == "payrollHour" then return fmtHour(v) end
    if row.mappingSlot ~= nil then
        local profileId = self.draftSettings.activePayrollProfile or "default"
        local worker = HelperPayroll ~= nil and HelperPayroll.getWorkerRateById ~= nil and HelperPayroll:getWorkerRateById(profileId, tostring(v or "")) or nil
        local roleName = worker ~= nil and worker.name or tostring(v or "-")
        local policy = self.draftRolePolicies[tostring(v or "")] or {}
        local rate = tonumber(policy.rate) or 0
        return string.format("%s (%.2f/%s)", tostring(roleName), rate, policy.payBasis == "daily" and "day" or "hr")
    end
    if row.roleField == "rate" or row.workerOverrideField == "rate" then
        local basis = row.roleId ~= nil and (self.draftRolePolicies[row.roleId] or {}).payBasis or self:getDraftValue({workerSlot=row.workerSlot, workerOverrideField="payBasis"})
        return fmtMoney(v) .. (basis == "daily" and "/day" or "/hr")
    end
    if row.id == "minimumWorkerCharge" or row.id == "workerCalloutFee" or row.roleField == "minimumCallout" or row.workerOverrideField == "minimumCallout" then return fmtMoney(v) end
    return tostring(v or "-")
end

function HelperPayrollMenu:updateSelectedDetails()
    local row = self.selectedRow
    local info = "Select an editable row, then use the left/right controls in the Value column. APPLY writes the current save payroll settings."
    if row ~= nil then
        if row.editType ~= nil then
            info = string.format("%s | Draft value: %s | %s", tostring(row.label or "Selected item"), tostring(self:formatDraftValue(row)), tostring(row.info or "Use the Value-column controls to change this setting."))
        else
            info = string.format("%s is read-only. %s", tostring(row.label or "Selected item"), tostring(row.info or ""))
        end
    end
    self:setTextSafe(self.rowHelpText, info)
    local statusText = self.stagedDirty and "Unsaved changes staged. Press APPLY to write the current save payroll settings, or DISCARD/RELOAD to revert." or ""
    if self.resetConfirmationArmed == true then
        statusText = "RESET SAVE is armed. Select CONFIRM RESET to replace this save's payroll settings and role list with the default policy, or choose any other action to cancel."
    end
    self:setTextSafe(self.dirtyText, statusText)
end

function HelperPayrollMenu:setResetConfirmationArmed(armed)
    self.resetConfirmationArmed = armed == true
    if self.resetButton ~= nil and self.resetButton.setText ~= nil then
        self.resetButton:setText(self.resetConfirmationArmed and "CONFIRM RESET" or "RESET SAVE")
    end
end

function HelperPayrollMenu:cancelResetConfirmation()
    if self.resetConfirmationArmed == true then
        self:setResetConfirmationArmed(false)
    end
end

function HelperPayrollMenu:setDraftValue(row, value)
    if row == nil then return end
    self:cancelResetConfirmation()
    if row.id == "payrollMode" then self.draftSettings.payrollMode = tostring(value)
    elseif row.id == "billingMode" then self.draftSettings.billingMode = tostring(value)
    elseif row.id == "payrollHour" then self.draftSettings.payrollHour = tonumber(value) or 0
    elseif row.id == "minimumWorkerCharge" then self.draftSettings.minimumWorkerCharge = tonumber(value) or 0
    elseif row.id == "workerCalloutFee" then self.draftSettings.workerCalloutFee = tonumber(value) or 0
    elseif row.id == "roundWorkerCharges" then self.draftSettings.roundWorkerCharges = (value == true or tostring(value) == "true")
    elseif row.mappingSlot ~= nil then
        self.draftMappings[row.mappingSlot] = tostring(value or "standard")
        local rolePolicy = self.draftRolePolicies[self.draftMappings[row.mappingSlot]] or {}
        local override = self.draftWorkerOverrides[row.mappingSlot] or {compensationMode="inherit"}
        if tostring(override.compensationMode or "inherit") ~= "custom" then
            override.payBasis = rolePolicy.payBasis
            override.rate = rolePolicy.rate
            override.minimumCallout = rolePolicy.minimumCallout
        end
        self.draftWorkerOverrides[row.mappingSlot] = override
    elseif row.roleId ~= nil and row.roleField ~= nil then
        local policy = self.draftRolePolicies[row.roleId] or {}
        policy[row.roleField] = row.roleField == "payBasis" and tostring(value) or (tonumber(value) or 0)
        self.draftRolePolicies[row.roleId] = policy
    elseif row.workerSlot ~= nil and row.workerOverrideField ~= nil then
        local override = self.draftWorkerOverrides[row.workerSlot] or {}
        local field = row.workerOverrideField
        override[field] = (field == "compensationMode" or field == "payBasis") and tostring(value) or (tonumber(value) or 0)
        if field == "compensationMode" and tostring(value) == "custom" then
            local rolePolicy = self.draftRolePolicies[self.draftMappings[row.workerSlot]] or {}
            override.payBasis = rolePolicy.payBasis or "hourly"
            override.rate = tonumber(rolePolicy.rate) or 0
            override.minimumCallout = tonumber(rolePolicy.minimumCallout) or 0
        end
        self.draftWorkerOverrides[row.workerSlot] = override
    end
    self.stagedDirty = true
    self:buildRows()
    if self.itemList ~= nil then
        self.itemList:reloadData()
        if self.selectedRowIndex ~= nil and self.itemList.setSelectedIndex ~= nil then pcall(function() self.itemList:setSelectedIndex(self.selectedRowIndex, true) end) end
    end
    self.selectedRow = self.rows[self.selectedRowIndex or 1]
    self:updateSelectedDetails()
end

function HelperPayrollMenu:getRowFromControl(control)
    local idx = nil
    if control ~= nil and control.hpayRowIndex ~= nil then
        idx = tonumber(control.hpayRowIndex)
    end
    if idx == nil then
        idx = self.selectedRowIndex
    end
    if idx ~= nil then
        self.selectedRowIndex = idx
        self.selectedRow = self.rows[idx]
    end
    return self.selectedRow
end

function HelperPayrollMenu:adjustRowValue(row, direction)
    if row == nil or row.editType == nil then return end
    direction = tonumber(direction) or 1
    if row.editType == "option" then
        local opts = row.options or {}
        if #opts == 0 then return end
        local current = tostring(self:getDraftValue(row))
        local idx = 1
        for i, opt in ipairs(opts) do
            if tostring(opt) == current then idx = i break end
        end
        idx = idx + direction
        if idx < 1 then idx = #opts end
        if idx > #opts then idx = 1 end
        self:setDraftValue(row, opts[idx])
        return
    end
    if row.editType == "number" then
        local n = tonumber(self:getDraftValue(row)) or 0
        local step = tonumber(row.step) or 1
        n = n + (step * direction)
        if row.min ~= nil and n < row.min then n = row.min end
        if row.max ~= nil and n > row.max then n = row.max end
        self:setDraftValue(row, n)
    end
end

function HelperPayrollMenu:onClickCellPrev(control)
    self:adjustRowValue(self:getRowFromControl(control), -1)
end

function HelperPayrollMenu:onClickCellNext(control)
    self:adjustRowValue(self:getRowFromControl(control), 1)
end

function HelperPayrollMenu:onClickValueOption(state)
    if self.suppressOptionCallback then return end
    local row = self.selectedRow
    if row == nil or row.editType ~= "option" then return end
    local idx = tonumber(state) or (self.valueOption ~= nil and self.valueOption.getState ~= nil and self.valueOption:getState()) or 1
    local opt = row.options ~= nil and row.options[idx] or nil
    if opt ~= nil then self:setDraftValue(row, opt) end
end

function HelperPayrollMenu:onClickValueDown()
    local row = self.selectedRow
    if row == nil or row.editType ~= "number" then return end
    local n = tonumber(self:getDraftValue(row)) or 0
    local step = tonumber(row.step) or 1
    n = n - step
    if row.min ~= nil and n < row.min then n = row.min end
    self:setDraftValue(row, n)
end

function HelperPayrollMenu:onClickValueUp()
    local row = self.selectedRow
    if row == nil or row.editType ~= "number" then return end
    local n = tonumber(self:getDraftValue(row)) or 0
    local step = tonumber(row.step) or 1
    n = n + step
    if row.max ~= nil and n > row.max then n = row.max end
    self:setDraftValue(row, n)
end

function HelperPayrollMenu:onClickApply()
    self:cancelResetConfirmation()
    if HelperPayroll ~= nil and HelperPayroll.applyManagementDraft ~= nil then
        local ok = HelperPayroll:applyManagementDraft(self.draftSettings, self.draftRolePolicies, self.draftMappings, self.draftWorkerOverrides, "gui")
        if ok then
            self:refreshDraftFromRuntime()
            self:showTopic(self.currentTopic)
        end
    end
end

function HelperPayrollMenu:onClickDiscard()
    self:cancelResetConfirmation()
    self:refreshDraftFromRuntime()
    self:showTopic(self.currentTopic)
end

function HelperPayrollMenu:onClickReload()
    self:cancelResetConfirmation()
    if HelperPayroll ~= nil then
        HelperPayroll:loadConfig()
        HelperPayroll:loadSavegameSettings()
    end
    self:refreshDraftFromRuntime()
    self:showTopic(self.currentTopic)
end

function HelperPayrollMenu:onClickReset()
    if self.resetConfirmationArmed ~= true then
        self:setResetConfirmationArmed(true)
        self:updateSelectedDetails()
        return
    end
    self:setResetConfirmationArmed(false)
    if HelperPayroll ~= nil then
        -- Reset this save's active payroll settings from the global/default policy template.
        -- The global modSettings/defaultPayrollConfig.xml is not modified by this UI action.
        HelperPayroll:loadConfig()
        HelperPayroll.helperProfilesMappings = {}
        if HelperPayroll.rebuildHelperProfilesMappingIndexes ~= nil then
            HelperPayroll:rebuildHelperProfilesMappingIndexes()
        end
        if HelperPayroll.saveSavegameSettings ~= nil then
            HelperPayroll:saveSavegameSettings("gui-reset-save-from-policy")
        end
        HelperPayroll:loadSavegameSettings()
    end
    self:refreshDraftFromRuntime()
    self:showTopic(self.currentTopic)
end

function HelperPayrollMenu:onPageNext()
    self:cancelResetConfirmation()
    local idx = self:getActiveTabIndex() + 1
    if idx > #TAB_TOPICS then idx = 1 end
    self:showTopic(TAB_TOPICS[idx])
end

function HelperPayrollMenu:onPagePrevious()
    self:cancelResetConfirmation()
    local idx = self:getActiveTabIndex() - 1
    if idx < 1 then idx = #TAB_TOPICS end
    self:showTopic(TAB_TOPICS[idx])
end

function HelperPayrollMenu:onClickOverview() self:cancelResetConfirmation(); self:showTopic("overview") end
function HelperPayrollMenu:onClickBilling() self:cancelResetConfirmation(); self:showTopic("billing") end
function HelperPayrollMenu:onClickRoles() self:cancelResetConfirmation(); self:showTopic("roles") end
function HelperPayrollMenu:onClickWorkers() self:cancelResetConfirmation(); self:showTopic("workers") end
function HelperPayrollMenu:onClickLedger() self:cancelResetConfirmation(); self:showTopic("ledger") end
function HelperPayrollMenu:onClickHelp() self:cancelResetConfirmation(); self:showTopic("help") end

function HelperPayrollMenu:onClickBack()
    self:cancelResetConfirmation()
    if g_gui ~= nil then g_gui:showGui(nil) end
end
