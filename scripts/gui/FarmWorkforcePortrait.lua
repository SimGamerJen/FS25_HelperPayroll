-- Experimental Farm Workforce portrait preview.
-- Original implementation using FS25's native Render and HumanGraphicsComponent.
-- A single scene exists only while the management screen is open.
-- All worker/style resolution goes through the optional HelperProfiles API.
FarmWorkforcePortrait = {}
FarmWorkforcePortrait.__index = FarmWorkforcePortrait

local function hideRender(render, value)
    if render ~= nil and render.setVisible ~= nil then
        pcall(render.setVisible, render, value)
    end
end

function FarmWorkforcePortrait.new(renderElement, modDirectory)
    local self = setmetatable({}, FarmWorkforcePortrait)
    self.render = renderElement
    self.modDirectory = modDirectory or g_currentModDirectory or ""
    self.requestedSlot = nil
    self.renderedSlot = nil
    self.graphics = nil
    self.actorNode = nil
    self.loadGeneration = 0
    self.sceneRequested = false
    self.ready = false
    self.attemptedSlot = nil
    self.reason = "idle"
    hideRender(self.render, false)
    return self
end

function FarmWorkforcePortrait:clearCharacter()
    self.loadGeneration = self.loadGeneration + 1
    self.ready = false
    self.renderedSlot = nil
    local graphics = self.graphics
    self.graphics = nil
    if graphics ~= nil and graphics.delete ~= nil then
        pcall(graphics.delete, graphics)
    end
    hideRender(self.render, false)
end

function FarmWorkforcePortrait:showSlot(slot)
    slot = slot ~= nil and tostring(slot) or nil
    if slot == self.requestedSlot then return end
    self.requestedSlot = slot
    self.attemptedSlot = nil
    self.reason = "waiting"
    self:clearCharacter()
end

function FarmWorkforcePortrait:ensureScene()
    if self.render == nil or type(self.render.setScene) ~= "function" then
        self.reason = "render-element-unavailable"
        return false
    end
    if self.render.scene ~= nil then return true end
    if self.sceneRequested then return false end
    if type(HumanGraphicsComponent) ~= "table" or type(HumanGraphicsComponent.new) ~= "function" then
        self.reason = "character-renderer-unavailable"
        return false
    end
    local base = self.modDirectory
    if base ~= "" and base:sub(-1) ~= "/" and base:sub(-1) ~= "\\" then base = base .. "/" end
    local ok = pcall(self.render.setScene, self.render, base .. "gui/farmWorkforcePortrait.i3d")
    self.sceneRequested = ok
    if not ok then self.reason = "scene-load-failed" end
    return false
end

function FarmWorkforcePortrait:setupActor()
    if self.actorNode ~= nil then return true end
    if self.render == nil or self.render.scene == nil or type(getChildAt) ~= "function" then
        return false
    end
    local ok, node = pcall(function()
        local root = getChildAt(self.render.scene, 0)
        return root ~= nil and getChildAt(root, 0) or nil
    end)
    if not ok or node == nil or node == 0 then
        self.reason = "scene-nodes-unavailable"
        return false
    end
    self.actorNode = node
    return true
end

function FarmWorkforcePortrait:beginCharacterLoad(slot)
    self.attemptedSlot = slot
    local hp = HelperPayroll
    if hp == nil or type(hp.callHelperProfilesAPI) ~= "function" then
        self.reason = "profiles-api-unavailable"
        return
    end
    local ok, style = hp:callHelperProfilesAPI("createPreviewPlayerStyle", slot)
    if not ok or style == nil then
        self.reason = "no-preview-style"
        return
    end
    local created, graphics = pcall(HumanGraphicsComponent.new)
    if not created or graphics == nil then
        self.reason = "graphics-create-failed"
        return
    end
    self.graphics = graphics
    local setupOk = pcall(function()
        if graphics.setSoundsEnabled ~= nil then graphics:setSoundsEnabled(false) end
        graphics:initialize()
        link(self.actorNode, graphics.graphicsRootNode)
        setTranslation(graphics.graphicsRootNode, 0, 0, 0)
        if graphics.setModelYaw ~= nil then graphics:setModelYaw(0) end
    end)
    if not setupOk or type(graphics.setStyleAsync) ~= "function" then
        self.reason = "graphics-initialization-failed"
        self:clearCharacter()
        return
    end
    local generation = self.loadGeneration
    local loadOk = pcall(function()
        graphics:setStyleAsync(style, function(_, state)
            if generation ~= self.loadGeneration or self.graphics ~= graphics then return end
            if HumanModelLoadingState ~= nil and state == HumanModelLoadingState.OK then
                self.ready = true
                self.renderedSlot = slot
                self.reason = "ready"
                hideRender(self.render, self.requestedSlot == slot)
                if self.render.setRenderDirty ~= nil then self.render:setRenderDirty() end
            else
                self.reason = "character-style-load-failed"
                self:clearCharacter()
            end
        end, nil, nil, true)
    end)
    if not loadOk then
        self.reason = "character-style-call-failed"
        self:clearCharacter()
    end
end

function FarmWorkforcePortrait:update(dt)
    if self.requestedSlot == nil then return end
    if not self:ensureScene() then return end
    if not self:setupActor() then return end
    if self.graphics == nil and self.attemptedSlot ~= self.requestedSlot then
        self:beginCharacterLoad(self.requestedSlot)
    end
    if self.graphics ~= nil and self.ready then
        if self.graphics.defaultAllParameters ~= nil then
            pcall(self.graphics.defaultAllParameters, self.graphics)
        end
        if self.graphics.update ~= nil then pcall(self.graphics.update, self.graphics, dt or 0) end
        if self.render ~= nil and self.render.setRenderDirty ~= nil then
            self.render:setRenderDirty()
        end
    end
end

function FarmWorkforcePortrait:destroy()
    self.requestedSlot = nil
    self:clearCharacter()
    if self.render ~= nil and self.render.destroyScene ~= nil then
        pcall(self.render.destroyScene, self.render)
    end
    self.actorNode = nil
    self.sceneRequested = false
end
