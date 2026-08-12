-- FS25_HelperPayroll
-- Public integration API construction. Kept outside the main payroll controller
-- so consumers and future network adapters depend on a stable boundary.

HelperPayrollPublicAPI = HelperPayrollPublicAPI or {}
HelperPayrollPublicAPI.API_VERSION = 4

function HelperPayrollPublicAPI.build(owner)
    local api = {
        apiVersion = HelperPayrollPublicAPI.API_VERSION,
        snapshotSchemaVersion = HelperPayrollSnapshot ~= nil and HelperPayrollSnapshot.SCHEMA_VERSION or 1,
        modName = "FS25_HelperPayroll",
        modVersion = tostring(owner.VERSION or "0.4.3.0"),
        readOnly = false,
        capabilities = {
            roleMappings = true,
            payrollSnapshot = true,
            dashboardSnapshot = true,
            compatibilityStatus = true,
            multiplayer = false,
            transportReadySnapshot = true,
            rosterAvailability = true,
            enabledWorkerFiltering = true
        }
    }

    function api:getStatus()
        local compatibility = owner.getCompatibilityStatus ~= nil and owner:getCompatibilityStatus() or {}
        local roster = owner.getManagedHelperRosterSummary ~= nil and owner:getManagedHelperRosterSummary() or {}
        return {
            available = owner.isInitialized == true,
            apiVersion = self.apiVersion,
            snapshotSchemaVersion = self.snapshotSchemaVersion,
            modName = self.modName,
            modVersion = self.modVersion,
            activePayrollProfile = tostring(owner.settings.activePayrollProfile or "default"),
            payrollMode = tostring(owner.settings.payrollMode or "roleType"),
            billingMode = tostring(owner.settings.billingMode or "onJobFinish"),
            managedSlotCount = owner:getManagedHelperSlotCount(),
            enabledSlotCount = tonumber(roster.enabled) or owner:getManagedHelperSlotCount(),
            disabledSlotCount = tonumber(roster.disabled) or 0,
            rosterAvailabilitySupported = roster.supported == true,
            targetSlotCount = tonumber(owner.TARGET_HELPER_SLOTS) or 20,
            payrollRuntimeEnabled = owner.isPayrollRuntimeEnabled ~= nil and owner:isPayrollRuntimeEnabled() or true,
            compatibilityBlocked = compatibility.blocked == true,
            compatibilityMessage = compatibility.message,
            multiplayerSupported = false,
            authority = "singlePlayerMission"
        }
    end

    function api:getCompatibilityStatus()
        return owner:getCompatibilityStatus()
    end

    function api:getPayrollSnapshot(options)
        return owner:getPayrollSnapshot(options)
    end

    function api:getDashboardSnapshot()
        return owner:getPayrollSnapshot({includeWorkers = false})
    end

    function api:getRoles()
        return owner:getIntegrationRoleRows()
    end

    function api:getRoleForSlot(slot)
        return owner:getIntegrationRoleForSlot(slot)
    end

    function api:getSlots()
        local rows = {}
        for index, slot in ipairs(owner:getManagedHelperSlots()) do
            rows[index] = owner:getIntegrationRoleForSlot(slot)
        end
        return rows
    end

    function api:getEnabledSlots()
        local rows = {}
        for index, slot in ipairs(owner:getOperationalHelperSlots()) do
            rows[index] = owner:getIntegrationRoleForSlot(slot)
        end
        return rows
    end

    function api:isSlotEnabled(slot)
        local enabled, source = owner:isManagedHelperSlotEnabled(slot)
        return enabled == true, source
    end

    function api:getRosterStatus()
        local roster = owner:getManagedHelperRosterSummary()
        return {
            availabilitySupported = roster.supported == true,
            source = tostring(roster.source or "managed-slot fallback"),
            totalWorkers = tonumber(roster.total) or 0,
            enabledWorkers = tonumber(roster.enabled) or 0,
            disabledWorkers = tonumber(roster.disabled) or 0
        }
    end

    function api:applyRoleMappings(roleMappings, reason)
        return owner:applyIntegrationRoleMappings(roleMappings, reason)
    end

    return api
end
