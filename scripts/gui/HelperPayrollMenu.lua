-- FS25_HelperPayroll
-- Management GUI using the CropControlOverride-style FS25 ScreenElement/SmoothList technique.

local HPAY_GUI_MOD_DIRECTORY = g_currentModDirectory or ""

HelperPayrollMenu = {}

local HelperPayrollMenu_mt = Class(HelperPayrollMenu, ScreenElement)

local TAB_TEXTS = {"OVERVIEW", "BILLING", "ROLES", "LEDGER", "HELP"}
local TAB_TOPICS = {"overview", "billing", "roles", "ledger", "help"}
local TOPIC_INDEX = {overview=1, billing=2, roles=3, ledger=4, help=5}

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
    self.draftRates = {}
    self.stagedDirty = false
    self.suppressTabCallback = false
    self.suppressOptionCallback = false
    self.editControlsInitialised = false
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
    self:refreshDraftFromRuntime()
    self:showTopic(self.currentTopic or "overview")
end

function HelperPayrollMenu:onClose()
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
    self.draftRates = {}
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
            self.draftRates[roleId] = tonumber(worker.hourlyRate) or 0
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
            {id="billingMode", label="Billing mode", value=tostring(self.draftSettings.billingMode or "onJobFinish"), status="Editable", source="Savegame", editType="option", options={"onJobFinish", "dailyPayroll"}, info="Choose whether helper charges are applied when each job finishes, or deferred into the daily payroll run."},
            {id="payrollHour", label="Payroll hour", value=fmtHour(self.draftSettings.payrollHour), status="Editable", source="Savegame", editType="number", step=1, min=0, max=23, info="In dailyPayroll mode, payroll is applied at this in-game hour."},
            {id="minimumWorkerCharge", label="Minimum charge", value=fmtMoney(self.draftSettings.minimumWorkerCharge), status="Editable", source="Savegame", editType="number", step=0.5, min=0, max=999, info="Minimum charge applied to a completed helper job after labour and callout are calculated."},
            {id="workerCalloutFee", label="Callout fee", value=fmtMoney(self.draftSettings.workerCalloutFee), status="Editable", source="Savegame", editType="number", step=0.5, min=0, max=999, info="Flat callout fee added to each charged helper job."},
            {id="roundWorkerCharges", label="Round charges", value=boolText(self.draftSettings.roundWorkerCharges), status="Editable", source="Savegame", editType="option", options={"false", "true"}, info="Round helper charges to whole currency units when applied."},
        }
    elseif topic == "roles" then
        local order = hp ~= nil and hp.getWorkerRateOrder ~= nil and hp:getWorkerRateOrder(profileId) or {}
        for _, roleId in ipairs(order or {}) do
            local worker = hp:getWorkerRateById(profileId, roleId)
            local name = worker ~= nil and worker.name or roleId
            local rate = self.draftRates[roleId]
            if rate == nil and worker ~= nil then rate = tonumber(worker.hourlyRate) or 0 end
            table.insert(rows, {id="rate:"..tostring(roleId), roleId=roleId, label=tostring(name), value=fmtMoney(rate).."/hr", status=(roleId == self.draftSettings.selectedRole and "Selected" or "Editable"), source=tostring(profileId), editType="number", step=1, min=0, max=999, info="Hourly rate for worker role '"..tostring(roleId).."'."})
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
        return string.format("Profile: %s\nPayroll mode: %s\nBilling mode: %s\nSelected role: %s (%.2f/hr)\nMinimum charge: %.2f\nCallout fee: %.2f\nPolicy config: %s\n\nUse the tabs to review billing settings, role rates, and ledger totals.", tostring(hp and hp.settings and hp.settings.activePayrollProfile or "-"), tostring(hp and hp.settings and hp.settings.payrollMode or "-"), tostring(hp and hp.settings and hp.settings.billingMode or "-"), tostring(roleName), tonumber(rate) or 0, tonumber(hp and hp.settings and hp.settings.minimumWorkerCharge or 0) or 0, tonumber(hp and hp.settings and hp.settings.workerCalloutFee or 0) or 0, tostring(hp and hp.CONFIG_FILE or "-"))
    elseif topic == "help" then
        return "HelperPayroll Management\n\nThis screen uses the same FS25-style ScreenElement, tab row, SmoothList table, and details panel technique used by CropControlOverride.\n\nBilling and role-rate changes are staged in this menu. Press APPLY to write the current save payroll settings. Press DISCARD to reload values from the current runtime config.\n\nThis is the first CCO-style management UI pass; deeper role/profile editing can be expanded once this foundation is approved."
    end
    return ""
end

function HelperPayrollMenu:updateContent()
    local tableVisible = self.currentTopic == "billing" or self.currentTopic == "roles" or self.currentTopic == "ledger"
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
    if row.id == "billingMode" then return self.draftSettings.billingMode end
    if row.id == "payrollHour" then return self.draftSettings.payrollHour end
    if row.id == "minimumWorkerCharge" then return self.draftSettings.minimumWorkerCharge end
    if row.id == "workerCalloutFee" then return self.draftSettings.workerCalloutFee end
    if row.id == "roundWorkerCharges" then return self.draftSettings.roundWorkerCharges end
    if row.roleId ~= nil then return self.draftRates[row.roleId] end
    return row.value
end

function HelperPayrollMenu:formatDraftValue(row)
    local v = self:getDraftValue(row)
    if row == nil then return "-" end
    if row.id == "roundWorkerCharges" then return boolText(v == true or tostring(v) == "true") end
    if row.id == "payrollHour" then return fmtHour(v) end
    if row.id == "minimumWorkerCharge" or row.id == "workerCalloutFee" or row.roleId ~= nil then return fmtMoney(v) .. (row.roleId ~= nil and "/hr" or "") end
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
    self:setTextSafe(self.dirtyText, self.stagedDirty and "Unsaved changes staged. Press APPLY to write the current save payroll settings, or DISCARD/RELOAD to revert." or "")
end

function HelperPayrollMenu:setDraftValue(row, value)
    if row == nil then return end
    if row.id == "billingMode" then self.draftSettings.billingMode = tostring(value)
    elseif row.id == "payrollHour" then self.draftSettings.payrollHour = tonumber(value) or 0
    elseif row.id == "minimumWorkerCharge" then self.draftSettings.minimumWorkerCharge = tonumber(value) or 0
    elseif row.id == "workerCalloutFee" then self.draftSettings.workerCalloutFee = tonumber(value) or 0
    elseif row.id == "roundWorkerCharges" then self.draftSettings.roundWorkerCharges = (value == true or tostring(value) == "true")
    elseif row.roleId ~= nil then self.draftRates[row.roleId] = tonumber(value) or 0 end
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
    if HelperPayroll ~= nil and HelperPayroll.applyManagementDraft ~= nil then
        local ok = HelperPayroll:applyManagementDraft(self.draftSettings, self.draftRates, "gui")
        if ok then
            self:refreshDraftFromRuntime()
            self:showTopic(self.currentTopic)
        end
    end
end

function HelperPayrollMenu:onClickDiscard()
    self:refreshDraftFromRuntime()
    self:showTopic(self.currentTopic)
end

function HelperPayrollMenu:onClickReload()
    if HelperPayroll ~= nil then
        HelperPayroll:loadConfig()
        HelperPayroll:loadSavegameSettings()
    end
    self:refreshDraftFromRuntime()
    self:showTopic(self.currentTopic)
end

function HelperPayrollMenu:onClickReset()
    if HelperPayroll ~= nil then
        -- Reset this save's active payroll settings from the global/default policy template.
        -- The global modSettings/defaultPayrollConfig.xml is not modified by this UI action.
        HelperPayroll:loadConfig()
        if HelperPayroll.saveSavegameSettings ~= nil then
            HelperPayroll:saveSavegameSettings("gui-reset-save-from-policy")
        end
        HelperPayroll:loadSavegameSettings()
    end
    self:refreshDraftFromRuntime()
    self:showTopic(self.currentTopic)
end

function HelperPayrollMenu:onPageNext()
    local idx = self:getActiveTabIndex() + 1
    if idx > #TAB_TOPICS then idx = 1 end
    self:showTopic(TAB_TOPICS[idx])
end

function HelperPayrollMenu:onPagePrevious()
    local idx = self:getActiveTabIndex() - 1
    if idx < 1 then idx = #TAB_TOPICS end
    self:showTopic(TAB_TOPICS[idx])
end

function HelperPayrollMenu:onClickOverview() self:showTopic("overview") end
function HelperPayrollMenu:onClickBilling() self:showTopic("billing") end
function HelperPayrollMenu:onClickRoles() self:showTopic("roles") end
function HelperPayrollMenu:onClickLedger() self:showTopic("ledger") end
function HelperPayrollMenu:onClickHelp() self:showTopic("help") end

function HelperPayrollMenu:onClickBack()
    if g_gui ~= nil then g_gui:showGui(nil) end
end
