-- Re-exec safe: onceki calisma kalintisini temizle
pcall(function()
    if _G.SakuraVsCleanup then _G.SakuraVsCleanup() end
end)
_G.SakuraVsRunning = true

repeat task.wait() until game:IsLoaded()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TS = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local HS = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")
local LP = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ============================================================
-- CACHÉ LOCAL DE SERVICIOS Y FUNCIONES (hot paths)
-- ============================================================
local _tick          = tick
local _clamp         = math.clamp
local _floor         = math.floor
local _abs           = math.abs
local _huge          = math.huge
local _sqrt          = math.sqrt
local _V3new         = Vector3.new
local _V3zero        = Vector3.zero
local _CFnew         = CFrame.new
local _CFlookAt      = CFrame.lookAt
local _RayParams_new = RaycastParams.new

local _GetPlayersCached
do
    local cache, cacheTime = nil, 0
    _GetPlayersCached = function()
        local now = _tick()
        if cache and now - cacheTime < 0.03 then return cache end
        cache = Players:GetPlayers()
        cacheTime = now
        return cache
    end
end

local function waitForCharReady(char, timeout)
    timeout = timeout or 5
    local deadline = _tick() + timeout
    while (not char) or (not char.Parent)
          or (not char:FindFirstChild("HumanoidRootPart"))
          or (not char:FindFirstChildOfClass("Humanoid")) do
        if _tick() > deadline then return false end
        task.wait(0.05)
    end
    return true
end

NS = 60
CS = 29
LAGGER_SPEED = 15
LAGGER_CARRY_SPEED = 24.5
MEDUSA_COOLDOWN = 25
BAT_AIMBOT_SPEED = 58
BYPASS_AIMBOT_SPEED = 60
batAimbotMode = "Normal" -- Normal | V3
batAimbotModeLabel = nil
_specBypass = { conn = nil, swingCD = false }
MOBILE_PANEL_WIDTH = 128
MOBILE_PANEL_HEIGHT = 360
CONFIG_FILE = "Sakura_vs.json"
BAT_V2_HIT_DIST = 4.5
_isDraggingButton = false

-- ============================================================
-- ANTI DROP (from Sakura.vs) — ALWAYS ON
-- Spoofs HRP AssemblyLinearVelocity/Velocity reads so game
-- cannot detect abnormal velocity and force a drop.
-- ============================================================
antiDropEnabled = true
local antiDropActive = false
local antiDropOldIdx, antiDropOldNewIdx = nil, nil
local antiDropSpoofVel = Vector3.zero

local function startAntiDrop()
    if antiDropActive then return end
    local ok, mt = pcall(getrawmetatable, game)
    if not ok or not mt then return end
    antiDropOldIdx = mt.__index
    antiDropOldNewIdx = mt.__newindex
    pcall(setreadonly, mt, false)
    local newIndex = function(self, key)
        if not checkcaller() and (key == "AssemblyLinearVelocity" or key == "Velocity") then
            if typeof(self) == "Instance" and self:IsA("BasePart") and self.Name == "HumanoidRootPart" then
                local char = LP.Character
                if char and self:IsDescendantOf(char) then
                    return antiDropSpoofVel
                end
            end
        end
        return antiDropOldIdx(self, key)
    end
    local newNewIndex = function(self, key, value)
        if not checkcaller() and (key == "AssemblyLinearVelocity" or key == "Velocity") then
            if typeof(self) == "Instance" and self:IsA("BasePart") and self.Name == "HumanoidRootPart" then
                local char = LP.Character
                if char and self:IsDescendantOf(char) then
                    antiDropSpoofVel = value
                    return
                end
            end
        end
        return antiDropOldNewIdx(self, key, value)
    end
    if newcclosure then
        mt.__index = newcclosure(newIndex)
        mt.__newindex = newcclosure(newNewIndex)
    else
        mt.__index = newIndex
        mt.__newindex = newNewIndex
    end
    pcall(setreadonly, mt, true)
    antiDropActive = true
    print("[AntiDrop] ALWAYS ON")
end

local function stopAntiDrop()
    -- Disabled: Anti Drop is forced always-on (Sakura.vs style)
end

local function setAntiDrop(on)
    -- Always force Anti Drop ON (no toggle off)
    antiDropEnabled = true
    startAntiDrop()
end
setAntiDrop(true) -- FORCE ALWAYS ON


-- GUI background (selectable in Settings) — 5 assets
BACKGROUND_ASSET_ID = "118241258424065"
backgroundIndex = 1
backgroundImages = { "118241258424065", "137090941888778", "106638406471484", "126843729942853", "132235750206658" }
backgroundImageTransparency = 0.05
backgroundSelectorLabel = nil
_mainBgImage = nil

-- Steal bar uses its own selectable background from the same 5 assets
stealBarBackgroundIndex = 1
stealBarBackgroundSelectorLabel = nil

local function getActiveBackgroundId()
    backgroundImages = { "118241258424065", "137090941888778", "106638406471484", "126843729942853", "132235750206658" }
    local idx = math.floor(tonumber(backgroundIndex) or 1)
    if idx < 1 then idx = 1 end
    if idx > #backgroundImages then idx = #backgroundImages end
    backgroundIndex = idx
    local id = tostring(backgroundImages[idx])
    BACKGROUND_ASSET_ID = id
    return id
end

local function getStealBarBackgroundId()
    backgroundImages = { "118241258424065", "137090941888778", "106638406471484", "126843729942853", "132235750206658" }
    local idx = math.floor(tonumber(stealBarBackgroundIndex) or 1)
    if idx < 1 then idx = 1 end
    if idx > #backgroundImages then idx = #backgroundImages end
    stealBarBackgroundIndex = idx
    return tostring(backgroundImages[idx])
end

local _backgroundLoadVersion = setmetatable({}, {__mode = "k"})

local function setImageOnLabel(img, id)
    if not img then return end
    id = tostring(id or "")
    if id == "" then return end

    local version = (_backgroundLoadVersion[img] or 0) + 1
    _backgroundLoadVersion[img] = version
    img.Visible = true
    img.ImageTransparency = img.ImageTransparency or 0
    img.ImageColor3 = Color3.fromRGB(255, 255, 255)
    img.ScaleType = Enum.ScaleType.Crop

    local ContentProvider = game:GetService("ContentProvider")
    local candidates = {
        "rbxassetid://" .. id,
        "rbxthumb://type=Asset&id=" .. id .. "&w=768&h=432",
    }
    task.spawn(function()
        for _, candidate in ipairs(candidates) do
            if not img or not img.Parent or _backgroundLoadVersion[img] ~= version then return end
            img.Image = candidate
            pcall(function() ContentProvider:PreloadAsync({img}) end)
            task.wait(0.35)
            if not img or not img.Parent or _backgroundLoadVersion[img] ~= version then return end
            local loaded = false
            pcall(function() loaded = img.IsLoaded end)
            if loaded then return end
        end
        if img and img.Parent and _backgroundLoadVersion[img] == version then
            warn("[Sakura.vs] Background image did not load. Check that asset ID " .. id .. " is a public image/decal.")
        end
    end)
end

local function applyBackgroundImage(img)
    if not img then return end
    local id = getActiveBackgroundId()
    setImageOnLabel(img, id)
end

local function applyStealBarBackground()
    if not pbFrame then return end
    local id = getStealBarBackgroundId()
    for _, name in ipairs({"AutoStealBackground", "StealBarBackground"}) do
        local autoBg = pbFrame:FindFirstChild(name)
        if autoBg and autoBg:IsA("ImageLabel") then
            autoBg.ImageTransparency = 0.18
            setImageOnLabel(autoBg, id)
        end
    end
end

local function applyBackgroundToAll()
    local id = getActiveBackgroundId()
    local targets = {}
    local function collect(root)
        if not root then return end
        if root:IsA("ImageLabel") then
            local n = root.Name
            if n == "BackgroundImage" or n == "MiniBackgroundImage" or n == "TitleAssetBg" then
                targets[#targets + 1] = root
            end
        end
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("ImageLabel") then
                local n = d.Name
                if n == "BackgroundImage" or n == "MiniBackgroundImage" or n == "TitleAssetBg" then
                    targets[#targets + 1] = d
                end
            end
        end
    end
    collect(main)
    collect(gui)
    collect(miniBtn)
    if _mainBgImage then targets[#targets + 1] = _mainBgImage end
    local seen = {}
    for _, img in ipairs(targets) do
        if not seen[img] then
            seen[img] = true
            setImageOnLabel(img, id)
        end
    end
    if backgroundSelectorLabel then
        backgroundSelectorLabel.Text = "BG " .. tostring(backgroundIndex)
    end
    -- steal bar uses its own index
    applyStealBarBackground()
    if stealBarBackgroundSelectorLabel then
        stealBarBackgroundSelectorLabel.Text = "SB " .. tostring(stealBarBackgroundIndex)
    end
end

function setBackgroundIndex(idx)
    backgroundImages = { "118241258424065", "137090941888778", "106638406471484", "126843729942853", "132235750206658" }
    idx = math.floor(tonumber(idx) or 1)
    local n = #backgroundImages
    if idx < 1 then idx = n end
    if idx > n then idx = 1 end
    backgroundIndex = idx
    BACKGROUND_ASSET_ID = tostring(backgroundImages[idx])
    if backgroundSelectorLabel then
        backgroundSelectorLabel.Text = "BG " .. tostring(idx)
    end
    applyBackgroundToAll()
    pcall(function()
        if type(saveAllSettings) == "function" then saveAllSettings() end
    end)
end

function setStealBarBackgroundIndex(idx)
    backgroundImages = { "118241258424065", "137090941888778", "106638406471484", "126843729942853", "132235750206658" }
    idx = math.floor(tonumber(idx) or 1)
    local n = #backgroundImages
    if idx < 1 then idx = n end
    if idx > n then idx = 1 end
    stealBarBackgroundIndex = idx
    if stealBarBackgroundSelectorLabel then
        stealBarBackgroundSelectorLabel.Text = "SB " .. tostring(idx)
    end
    applyStealBarBackground()
    pcall(function()
        if type(saveAllSettings) == "function" then saveAllSettings() end
    end)
end

-- Floating / mobile tus butonlari icin asset arka plan (yazi ustte kalir)
BUTTON_ASSET_ID = "124268985896208"

local function applyButtonAssetBackground(parent)
    if not parent then return end
    local existing = parent:FindFirstChild("BtnAssetBg")
    if existing then existing:Destroy() end
    local existingOv = parent:FindFirstChild("BtnAssetOverlay")
    if existingOv then existingOv:Destroy() end

    local img = Instance.new("ImageLabel")
    img.Name = "BtnAssetBg"
    img.Size = UDim2.new(1, 0, 1, 0)
    img.Position = UDim2.new(0, 0, 0, 0)
    img.BackgroundTransparency = 1
    img.BorderSizePixel = 0
    img.ScaleType = Enum.ScaleType.Crop
    img.ImageTransparency = 0.08
    img.ImageColor3 = Color3.fromRGB(255, 255, 255)
    img.ZIndex = math.max((parent.ZIndex or 1), 1)
    img.ClipsDescendants = true
    img.Parent = parent

    local corner = parent:FindFirstChildOfClass("UICorner")
    if corner then
        local c = Instance.new("UICorner", img)
        c.CornerRadius = corner.CornerRadius
    else
        Instance.new("UICorner", img).CornerRadius = UDim.new(0, 10)
    end

    local id = tostring(BUTTON_ASSET_ID)
    img.Image = "rbxassetid://" .. id
    task.delay(0.6, function()
        if img and img.Parent and img.Image == "rbxassetid://" .. id then
            pcall(function()
                img.Image = "rbxthumb://type=Asset&id=" .. id .. "&w=420&h=420"
            end)
        end
    end)

    -- Hafif overlay (asset daha net, yazi stroke ile okunur)
    local ov = Instance.new("Frame")
    ov.Name = "BtnAssetOverlay"
    ov.Size = UDim2.new(1, 0, 1, 0)
    ov.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    ov.BackgroundTransparency = 0.62
    ov.BorderSizePixel = 0
    ov.ZIndex = img.ZIndex + 1
    ov.Parent = parent
    if corner then
        local c2 = Instance.new("UICorner", ov)
        c2.CornerRadius = corner.CornerRadius
    else
        Instance.new("UICorner", ov).CornerRadius = UDim.new(0, 10)
    end
    return img, ov
end


floatingButtonScale = 1
floatingButtonShape = "Rounded" -- "Rounded" | "Square" | "Circle" | "Circle"
_floatingUIScales = {}

local CarrySystem = {

    normalSpeed = NS,
    carrySpeed = CS,
    laggerSpeed = LAGGER_SPEED,
    laggerCarrySpeed = LAGGER_CARRY_SPEED,

    speedToggled = false,
    laggerMode = 0,

    softStealEnabled = false,
    softStealRadius = 12,
    softStealSpeed = 50, -- auto-carry boost (also uses max with carrySpeed)
    softStealLatched = false,
    autoCarryMode = "WHEN NEAR", -- "ON STEAL" | "WHEN NEAR"

    _isCarrying = false,
    _lastCarryCheck = 0,

    _lvBoost = nil,
    _lvAtt = nil,
    _blockedTime = 0,
    _maxForce = 2200,
    _freeForce = 500,

    _heartbeatConn = nil,
    _softStealScanner = nil,
    _softStealAnimals = {},
    _softStealScanning = false,

    _state = nil,
    _dropInProgress = false,
    _batAimbotToggled = false,

    _rayParams = nil,
    _rayFilter = nil,
    _rayFilterTime = 0,
}

function CarrySystem:isCarrying()
    local now = _tick()
    if now - (self._lastCarryCheck or 0) < 0.1 then
        return self._isCarrying
    end
    self._lastCarryCheck = now
    local char = LP.Character
    if not char then self._isCarrying = false; return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local ws = hum and hum.WalkSpeed or 16
    local bySpeed = (ws < 25 and ws > 0)
    local byAttr = false
    local ok, v = pcall(function() return LP:GetAttribute("Stealing") end)
    if ok and v == true then byAttr = true end
    local ok2, v2 = pcall(function() return char:GetAttribute("Stealing") end)
    if ok2 and v2 == true then byAttr = true end
    if not byAttr then
        for _, name in ipairs({"Carrying","IsCarrying","Grabbed","Holding","StealHold","HasGrab","HoldingAnimal","HasAnimal","Stealing"}) do
            local obj = char:FindFirstChild(name)
            if obj then
                if (obj:IsA("BoolValue") and obj.Value) or
                   (obj:IsA("ObjectValue") and obj.Value) or
                   (obj:IsA("StringValue") and obj.Value ~= "") or
                   obj:IsA("Model") or obj:IsA("BasePart") then
                    byAttr = true; break
                end
            end
            local okA, va = pcall(function() return char:GetAttribute(name) end)
            if okA and va then byAttr = true; break end
            local okB, vb = pcall(function() return LP:GetAttribute(name) end)
            if okB and vb then byAttr = true; break end
        end
    end
    if not byAttr then
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("Tool") or child:IsA("Model") then
                local n = string.lower(child.Name)
                if n:find("animal", 1, true) or n:find("pet", 1, true) or n:find("brain", 1, true) or n:find("talpa", 1, true) then
                    byAttr = true; break
                end
            end
        end
    end
    self._isCarrying = bySpeed or byAttr
    return self._isCarrying
end

function CarrySystem:getActiveSpeed()
    if self._state and (self._state.autoLeftEnabled or self._state.autoRightEnabled) then
        return self.normalSpeed
    end
    if self.laggerMode == 1 then return self.laggerSpeed end
    if self.laggerMode == 2 then return self.laggerCarrySpeed end
    -- Candy.vs style Auto Carry Speed: while stealing / carrying, use carry speed
    if self.speedToggled or (autoCarrySpeedEnabled and self:isCarrying()) then
        return self.carrySpeed
    end
    return self.normalSpeed
end

function CarrySystem:getStatus()
    if self._state and (self._state.autoLeftEnabled or self._state.autoRightEnabled) then
        return "NORMAL", self.normalSpeed
    end
    if self.laggerMode == 1 then return "LAGGER", self.laggerSpeed end
    if self.laggerMode == 2 then return "LAGGER CARRY", self.laggerCarrySpeed end
    if self.speedToggled or (autoCarrySpeedEnabled and self:isCarrying()) then
        return "CARRY", self.carrySpeed
    end
    return "NORMAL", self.normalSpeed
end

local function destroyLV()
    if CarrySystem._lvBoost and CarrySystem._lvBoost.Parent then pcall(function() CarrySystem._lvBoost:Destroy() end) end
    if CarrySystem._lvAtt and CarrySystem._lvAtt.Parent then pcall(function() CarrySystem._lvAtt:Destroy() end) end
    CarrySystem._lvBoost = nil; CarrySystem._lvAtt = nil
end

local function setupLV(hrp)
    if CarrySystem._lvBoost and CarrySystem._lvBoost.Parent == hrp then return end
    destroyLV()
    local att = Instance.new("Attachment"); att.Parent = hrp
    local lv = Instance.new("LinearVelocity")
    lv.Name = "CarryBoostLV"
    lv.Attachment0 = att
    lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
    lv.PrimaryTangentAxis = _V3new(1,0,0)
    lv.SecondaryTangentAxis = _V3new(0,0,1)
    lv.MaxForce = CarrySystem._maxForce
    lv.PlaneVelocity = Vector2.zero
    lv.RelativeTo = Enum.ActuatorRelativeTo.World
    lv.Parent = hrp
    CarrySystem._lvAtt = att
    CarrySystem._lvBoost = lv
    pcall(function() hrp:SetNetworkOwner(LP) end)
end

function CarrySystem:scanSoftStealAnimals()
    self._softStealAnimals = {}
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return end
    for _, plot in ipairs(plots:GetChildren()) do
        if plot:IsA("Model") then
            local podiums = plot:FindFirstChild("AnimalPodiums")
            if podiums then
                for _, podium in ipairs(podiums:GetChildren()) do
                    if podium:IsA("Model") then
                        local base = podium:FindFirstChild("Base")
                        local spawn = base and base:FindFirstChild("Spawn")
                        if spawn then
                            table.insert(self._softStealAnimals, {
                                plot = plot.Name,
                                slot = podium.Name,
                                worldPosition = spawn.Position,
                                uid = plot.Name .. "_" .. podium.Name,
                            })
                        end
                    end
                end
            end
        end
    end
end

function CarrySystem:startSoftStealScanner()
    if self._softStealScanner then return end
    self._softStealScanning = true
    self:scanSoftStealAnimals()
    local lastScan = 0
    self._softStealScanner = RunService.Heartbeat:Connect(function()
        if not self._softStealScanning then return end
        local now = _tick()
        if now - lastScan < 0.25 then return end
        lastScan = now
        self:scanSoftStealAnimals()
    end)
end

function CarrySystem:stopSoftStealScanner()
    self._softStealScanning = false
    if self._softStealScanner then
        self._softStealScanner:Disconnect()
        self._softStealScanner = nil
    end
end

function CarrySystem:getNearestSoftStealAnimal(radius)
    local char = LP.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso"))
    if not root then return nil, _huge end
    local best, bestDist = nil, _huge
    local animals = self._softStealAnimals
    local rpos = root.Position
    for i = 1, #animals do
        local data = animals[i]
        if data.worldPosition then
            local dx = rpos.X - data.worldPosition.X
            local dy = rpos.Y - data.worldPosition.Y
            local dz = rpos.Z - data.worldPosition.Z
            local dist = _sqrt(dx*dx + dy*dy + dz*dz)
            if dist < bestDist then
                best = data; bestDist = dist
            end
        end
    end
    if radius and bestDist > radius then return nil, bestDist end
    return best, bestDist
end

function CarrySystem:updateMovement(dt)
    local char = LP.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end

    -- Clean Hub Bat Bypass owns velocity while active — don't fight it
    if BatBypassV2 and BatBypassV2.Enabled then
        local lv = self._lvBoost
        if lv and lv.Parent then
            lv.PlaneVelocity = Vector2.zero
        end
        return
    end

    local speed = self:getActiveSpeed()
    local moveDir = hum.MoveDirection
    local moving = moveDir.Magnitude > 0.1

    local wallNormalFlat = nil
    if moving then
        if not self._rayParams then
            self._rayParams = _RayParams_new()
            self._rayParams.FilterType = Enum.RaycastFilterType.Exclude
            self._rayFilter = {}
            self._rayFilterTime = 0
        end
        local now = _tick()
        if now - self._rayFilterTime > 1 then
            self._rayFilterTime = now
            local filter = self._rayFilter
            while #filter > 0 do filter[#filter] = nil end
            filter[1] = char
            local plist = _GetPlayersCached()
            for i = 1, #plist do
                local p = plist[i]
                if p.Character then
                    filter[#filter + 1] = p.Character
                end
            end
            self._rayParams.FilterDescendantsInstances = filter
        else
            local filter = self._rayFilter
            local found = false
            for i = 1, #filter do
                if filter[i] == char then found = true; break end
            end
            if not found then
                filter[1] = char
                self._rayParams.FilterDescendantsInstances = filter
            end
        end
        local flatDir = _V3new(moveDir.X, 0, moveDir.Z).Unit
        local hit = Workspace:Raycast(hrp.Position + _V3new(0,1,0), flatDir * 2.5, self._rayParams)
        if hit and hit.Instance and hit.Instance.CanCollide then
            local nf = _V3new(hit.Normal.X, 0, hit.Normal.Z)
            if nf.Magnitude > 0.7 then wallNormalFlat = nf.Unit end
        end
    end

    local hVel = _V3new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z)
    local blocked = wallNormalFlat ~= nil or (moving and hVel.Magnitude < 2)

    if blocked then
        for _, model in ipairs(char:GetChildren()) do
            if model:IsA("Model") then
                for _, part in ipairs(model:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then part.CanCollide = false end
                end
            end
        end
        for _, name in ipairs({"Carrying","IsCarrying","Grabbed","Holding","StealHold","HasGrab"}) do
            local v = char:FindFirstChild(name)
            if v and v:IsA("ObjectValue") and v.Value and v.Value:IsA("Model") then
                for _, part in ipairs(v.Value:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then part.CanCollide = false end
                end
            end
        end
    end

    local state = hum:GetState()
    local ragdolled = state == Enum.HumanoidStateType.Physics
                   or state == Enum.HumanoidStateType.Ragdoll
                   or state == Enum.HumanoidStateType.FallingDown
    local moverBlocked = ragdolled or self._dropInProgress or self._batAimbotToggled

    if not moverBlocked then
        if not CarrySystem._lvBoost or CarrySystem._lvBoost.Parent ~= hrp then setupLV(hrp) end
        local lv = CarrySystem._lvBoost
        if lv then
            if not lv.Enabled then lv.Enabled = true end
            if moveDir.Magnitude > 0.1 then
                local flat = _V3new(moveDir.X, 0, moveDir.Z).Unit
                if wallNormalFlat then
                    local wanted = flat * speed
                    local along = wanted - wallNormalFlat * wanted:Dot(wallNormalFlat)
                    if along.Magnitude < 0.5 then
                        lv.PlaneVelocity = Vector2.zero
                    else
                        lv.PlaneVelocity = Vector2.new(along.X, along.Z)
                    end
                else
                    lv.PlaneVelocity = Vector2.new(flat.X * speed, flat.Z * speed)
                end
            else
                lv.PlaneVelocity = Vector2.zero
            end
            if blocked then
                self._blockedTime = self._blockedTime + (dt or 0.016)
            else
                self._blockedTime = 0
            end
            -- Pet/carry: stronger force so set speed (e.g. 29) actually holds
            local carrying = self:isCarrying()
            local targetForce = self._maxForce
            if carrying then
                targetForce = math.max(self._maxForce, 6000)
            end
            if self._blockedTime > 0.35 then
                targetForce = self._freeForce
            end
            if lv.MaxForce ~= targetForce then lv.MaxForce = targetForce end
        end
    elseif CarrySystem._lvBoost then
        CarrySystem._lvBoost.PlaneVelocity = Vector2.zero
        if CarrySystem._lvBoost.Enabled then CarrySystem._lvBoost.Enabled = false end
    end
end

function CarrySystem:start()
    if self._heartbeatConn then return end
    self._heartbeatConn = RunService.Heartbeat:Connect(function(dt) self:updateMovement(dt) end)
    if self.softStealEnabled then self:startSoftStealScanner() end
    print("[CarrySystem] Enabled")
end

function CarrySystem:stop()
    if self._heartbeatConn then
        self._heartbeatConn:Disconnect()
        self._heartbeatConn = nil
    end
    self:stopSoftStealScanner()
    destroyLV()
    self.softStealLatched = false
    print("[CarrySystem] Disabled")
end

function CarrySystem:setNormalSpeed(v) self.normalSpeed = _clamp(v,1,500) end
function CarrySystem:setCarrySpeed(v) self.carrySpeed = _clamp(v,1,500) end
function CarrySystem:setLaggerSpeed(v) self.laggerSpeed = _clamp(v,0.1,500) end
function CarrySystem:setLaggerCarrySpeed(v) self.laggerCarrySpeed = _clamp(v,0.1,500) end
function CarrySystem:setSoftStealSpeed(v) self.softStealSpeed = _clamp(v,1,500) end
function CarrySystem:setSoftStealRadius(v) self.softStealRadius = _clamp(v,1,200) end

function CarrySystem:toggleCarryMode() self.speedToggled = not self.speedToggled end
function CarrySystem:setLaggerMode(mode)
    if mode == 0 then self.laggerMode = 0
    elseif mode == 1 then self.laggerMode = 1
    elseif mode == 2 then self.laggerMode = 2 end
end
function CarrySystem:toggleLaggerMode()
    if self.laggerMode == 0 then self.laggerMode = 1
    elseif self.laggerMode == 1 then self.laggerMode = 2
    else self.laggerMode = 0 end
end
function CarrySystem:setSoftStealEnabled(enabled)
    self.softStealEnabled = enabled
    if enabled then self:startSoftStealScanner()
    else self:stopSoftStealScanner(); self.softStealLatched = false end
end
function CarrySystem:toggleSoftSteal() self:setSoftStealEnabled(not self.softStealEnabled) end
function CarrySystem:isRunning() return self._heartbeatConn ~= nil end
function CarrySystem:getCurrentSpeed() return self:getActiveSpeed() end

local ORANGE = Color3.fromRGB(255, 140, 0)
local ORANGE_BRIGHT = Color3.fromRGB(255, 165, 40)
local ORANGE_DIM = Color3.fromRGB(180, 90, 0)

local COLOR_THEMES = {
    ["Morado"] = Color3.fromRGB(160, 100, 220),
    ["Mavi"] = Color3.fromRGB(60, 140, 255),
    ["Kirmizi"] = Color3.fromRGB(230, 50, 60),
    ["Yesil"] = Color3.fromRGB(80, 220, 120),
    ["Sari"] = Color3.fromRGB(255, 210, 40),
    ["Naranja"] = Color3.fromRGB(255, 140, 0),
}

local COLOR_THEME_ORDER = { "Morado", "Mavi", "Kirmizi", "Yesil", "Sari", "Naranja" }

currentColorTheme = "Naranja"
selectedColor = ORANGE

discordTextColorTheme = "White"
selectedDiscordColor = Color3.fromRGB(255, 255, 255)
discordColorSelectorLabel = nil
DISCORD_COLOR_THEMES = {
    ["White"]  = Color3.fromRGB(255, 255, 255),
    ["Blue"]   = Color3.fromRGB(60, 140, 255),
    ["Mavi"]   = Color3.fromRGB(40, 170, 255),
    ["Yellow"] = Color3.fromRGB(255, 220, 50),
    ["Sari"]   = Color3.fromRGB(255, 210, 40),
    ["Purple"] = Color3.fromRGB(170, 90, 255),
    ["Mor"]    = Color3.fromRGB(160, 100, 220),
    ["Red"]    = Color3.fromRGB(255, 70, 90),
    ["Green"]  = Color3.fromRGB(80, 230, 120),
    ["Orange"] = Color3.fromRGB(255, 150, 40),
    ["Pink"]   = Color3.fromRGB(255, 120, 200),
}
DISCORD_COLOR_ORDER = { "White", "Blue", "Mavi", "Yellow", "Sari", "Purple", "Mor", "Red", "Green", "Orange", "Pink" }

function getDiscordTextColor()
    return selectedDiscordColor or Color3.fromRGB(255, 255, 255)
end

function applyDiscordTextColor(themeName)
    local color = DISCORD_COLOR_THEMES[themeName]
    if not color then return end
    discordTextColorTheme = themeName
    selectedDiscordColor = color
    if discordColorSelectorLabel then
        discordColorSelectorLabel.Text = themeName .. "  ▼"
        discordColorSelectorLabel.TextColor3 = color
    end
    -- Head billboard
    pcall(function()
        local char = LP.Character
        local head = char and char:FindFirstChild("Head")
        local bb = head and head:FindFirstChild("DiscordText")
        local lbl = bb and bb:FindFirstChild("DiscordLabel")
        if lbl then lbl.TextColor3 = color end
    end)
    -- Steal bar discord if any
    pcall(function()
        if pbFrame then
            local d = pbFrame:FindFirstChild("DiscordLabel")
            if d then d.TextColor3 = color end
        end
        if gui then
            for _, child in ipairs(gui:GetDescendants()) do
                if child:IsA("TextLabel") and (child.Name == "DiscordLabel" or child.Name == "DiscordText" or (child.Text and child.Text:find("discord.gg"))) then
                    child.TextColor3 = color
                end
            end
        end
    end)
    _lastSavedJSON = nil
    pcall(function()
        if type(saveAllSettings) == "function" then saveAllSettings() end
    end)
end

-- ESP color is independent from button/UI theme (default blue, transparent body)
espColorTheme = "Mavi"
selectedESPColor = Color3.fromRGB(60, 140, 255)
espColorSelectorLabel = nil

function getThemeColor() return selectedColor or ORANGE end
function getESPColor() return selectedESPColor or Color3.fromRGB(60, 140, 255) end

function applyESPColorTheme(themeName)
    local color = COLOR_THEMES[themeName]
    if not color then
        warn("[Sakura.vs] Unknown ESP theme:", tostring(themeName))
        return
    end
    espColorTheme = themeName
    selectedESPColor = color
    if espColorSelectorLabel then
        espColorSelectorLabel.Text = themeName .. "  ▼"
        espColorSelectorLabel.TextColor3 = color
    end
    -- Update existing highlights (transparent body + outline)
    for _, hl in pairs(espHighlightCache or {}) do
        if hl and hl.Parent then
            pcall(function()
                hl.FillColor = color
                hl.OutlineColor = color
                hl.FillTransparency = 0.78
                hl.OutlineTransparency = 0.15
            end)
        end
    end
    -- Rebuild tracers so Drawing line colors always refresh
    for plr, lines in pairs(espTracerCache or {}) do
        if lines then
            for _, ln in ipairs(lines) do
                pcall(function()
                    if ln then
                        ln.Color = color
                        if ln.Remove then ln:Remove() elseif ln.Destroy then ln:Destroy() end
                    end
                end)
            end
        end
        espTracerCache[plr] = nil
    end
    for _, bb in pairs(espBillboardCache or {}) do
        if bb then
            local img = bb:FindFirstChildOfClass("ImageLabel")
            if img then
                local stroke = img:FindFirstChildOfClass("UIStroke")
                if stroke then stroke.Color = color end
            end
        end
    end
    -- Next ESP render frame rebuilds tracers with new color
    _espLastRun = 0
    pcall(function()
        if type(saveAllSettings) == "function" then saveAllSettings() end
    end)
end

local _lastThemeUpdate = 0
local _lastThemeColor = nil

function applyColorTheme(themeName)
    local color = COLOR_THEMES[themeName]
    if not color then
        warn("[Sakura.vs] Unknown theme:", tostring(themeName))
        return
    end
    currentColorTheme = themeName
    selectedColor = color
    _lastThemeColor = nil -- force full UI refresh
    updateAllUIThemeColors(color)
    _lastSavedJSON = nil
    pcall(function()
        if type(saveAllSettings) == "function" then saveAllSettings() end
    end)
end

function updateAllUIThemeColors(color)
    if not color then color = getThemeColor() end
    local now = _tick()
    if color == _lastThemeColor and now - _lastThemeUpdate < 0.05 then return end
    _lastThemeUpdate = now
    _lastThemeColor = color

    if progressFill then
        progressFill.BackgroundColor3 = color
        local grad = progressFill:FindFirstChildOfClass("UIGradient")
        if grad then
            grad.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0.00, color),
                ColorSequenceKeypoint.new(0.50, Color3.new(1, 1, 1)),
                ColorSequenceKeypoint.new(1.00, color),
            })
        end
    end
    if pbFrame then
        local border = pbFrame:FindFirstChildOfClass("UIStroke")
        if border then border.Color = color end
        local discordLabel = pbFrame:FindFirstChild("DiscordLabel")
        if discordLabel then discordLabel.TextColor3 = getDiscordTextColor() end
        local fpsNeon = pbFrame:FindFirstChild("FPSNeon")
        if fpsNeon then fpsNeon.TextColor3 = color end
    end
    local function searchAndUpdateText(parent)
        for _, child in ipairs(parent:GetDescendants()) do
            if child:IsA("TextLabel") then
                if child.Text:find("discord.gg") or child.Name == "DiscordLabel" or child.Name == "DiscordText" then
                    child.TextColor3 = getDiscordTextColor()
                elseif child.Text:find("Spd:") or child.Name == "Sakura.vsSpeedIndicator" or child.Text:find("FPS") then
                    child.TextColor3 = color
                end
            end
            if child:IsA("UIStroke") then
                if child.Color == Color3.fromRGB(180, 180, 190) then child.Color = color end
            end
        end
    end
    if gui then searchAndUpdateText(gui) end
    -- Re-color all floating / mobile panel buttons (BAT AIMBOT, ANTI AIMBOT, TP BAT, etc.)
    if tpBatFloatingButton then
        paintFloatingBtn(tpBatFloatingButton:FindFirstChild("Frame"), batDesyncTpEnabled == true)
    end
    if batV2FloatingButton then
        paintFloatingBtn(batV2FloatingButton:FindFirstChild("Frame"), autoBatV2Enabled == true)
    end
    if antiAimbotFloatingButton then
        paintFloatingBtn(antiAimbotFloatingButton:FindFirstChild("Frame"), antiAimbotEnabled == true)
    end
    if instaResetFloatingButton then
        paintFloatingBtn(instaResetFloatingButton:FindFirstChild("Frame"), false)
    end
    if MobilePanel then
        local container = MobilePanel:FindFirstChild("FloatingPanel")
        if container then
            local btnContainer = container:FindFirstChild("ButtonsContainer")
            if btnContainer then
                for _, btn in ipairs(btnContainer:GetChildren()) do
                    if btn:IsA("TextButton") then
                        paintFloatingBtn(btn, btn:GetAttribute("MobActive") == true)
                    end
                end
            end
        end
    end
    for _, tab in ipairs(tabButtons or {}) do
        if tab.TextColor3 == Color3.fromRGB(180, 180, 190) then tab.TextColor3 = color end
    end
    -- ESP keeps its own color (do not overwrite with button theme)
    local espCol = getESPColor()
    for _, hl in pairs(espHighlightCache) do
        if hl then
            hl.FillColor = espCol
            hl.OutlineColor = espCol
            hl.FillTransparency = 0.78
            hl.OutlineTransparency = 0.15
        end
    end
    for _, lines in pairs(espTracerCache) do
        if lines then
            for _, ln in ipairs(lines) do
                if ln then ln.Color = espCol end
            end
        end
    end
    for _, bb in pairs(espBillboardCache) do
        if bb then
            local img = bb:FindFirstChildOfClass("ImageLabel")
            if img then
                local stroke = img:FindFirstChildOfClass("UIStroke")
                if stroke then stroke.Color = espCol end
            end
        end
    end
    if main then
        local titleFrame = main:FindFirstChild("Frame")
        if titleFrame then
            for _, child in ipairs(titleFrame:GetDescendants()) do
                if child:IsA("UIStroke") and child.Color == Color3.fromRGB(180, 180, 190) then
                    child.Color = color
                end
            end
        end
    end
    if colorSelectorLabel then
        colorSelectorLabel.Text = currentColorTheme .. "  ▼"
        colorSelectorLabel.TextColor3 = color
    end
    if miniBtn then
        miniBtn.TextColor3 = color
        local grad = miniBtn:FindFirstChildOfClass("UIGradient")
        if grad then
            grad.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, color),
                ColorSequenceKeypoint.new(0.3, Color3.new(1, 1, 1)),
                ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
                ColorSequenceKeypoint.new(0.7, Color3.new(1, 1, 1)),
                ColorSequenceKeypoint.new(1, color),
            })
        end
    end
    if main then
        local tf = main:FindFirstChild("Frame")
        if tf then
            local tl = tf:FindFirstChild("TitleLabel")
            if tl and tl:IsA("TextLabel") then
                tl.TextColor3 = color
            end
        end
        -- also search TitleLabel anywhere under main
        for _, d in ipairs(main:GetDescendants()) do
            if d:IsA("TextLabel") and (d.Name == "TitleLabel" or d.Text == "Sakura.vs" or d.Text == "SAKURA.VS") then
                d.TextColor3 = color
            end
        end
    end

    local pGui = LP:FindFirstChild("PlayerGui")
    if pGui then
        local bb = pGui:FindFirstChild("RagCountdownBillboard")
        if bb then
            local lbl = bb:FindFirstChildOfClass("TextLabel")
            if lbl then
                lbl.TextColor3 = color
                local grad = lbl:FindFirstChildOfClass("UIGradient")
                if grad then
                    grad.Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, color),
                        ColorSequenceKeypoint.new(0.3, Color3.new(1, 1, 1)),
                        ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
                        ColorSequenceKeypoint.new(0.7, Color3.new(1, 1, 1)),
                        ColorSequenceKeypoint.new(1, color),
                    })
                end
            end
        end
    end

    if MobilePanel then
        local container = MobilePanel:FindFirstChild("FloatingPanel")
        if container then
            local btnContainer = container:FindFirstChild("ButtonsContainer")
            if btnContainer then
                for _, btn in ipairs(btnContainer:GetChildren()) do
                    if btn:IsA("TextButton") and btn:FindFirstChild("BtnGrad") then
                        paintFloatingBtn(btn, btn:GetAttribute("MobActive") == true)
                    end
                end
            end
        end
    end
end

local HOMERO_CFG = {
    body = { 10725826963, 86500008, 86500054, 86500036, 86500064, 86500078 },
    aplicarCuerpo = true,
    items = {
        { id = 103227869700418, offset = _CFnew(0,0,0) },
        { id = 84952305140948,   offset = _CFnew(0,0,0) },
        { id = 122465238537030,  offset = _CFnew(0,0,0) },
    },
    shirt = nil,
    pants = "rbxassetid://78591690208112",
    skinColor = Color3.fromRGB(234,184,146),
    headColor = Color3.fromRGB(0,0,0),
}

local TAG = "LocalOutfit_"

local function loadObjects(id)
    local ok, res = pcall(function()
        return game:GetObjects("rbxassetid://" .. tostring(id))
    end)
    if ok and typeof(res) == "table" and #res > 0 then return res end
    ok, res = pcall(function()
        return game:GetService("InsertService"):LoadAsset(id)
    end)
    if ok and res then return { res } end
    return nil
end

local function collectParts(objs)
    local out = {}
    for _, o in ipairs(objs) do
        if o:IsA("BasePart") then out[#out + 1] = o end
        for _, d in ipairs(o:GetDescendants()) do
            if d:IsA("BasePart") then out[#out + 1] = d end
        end
    end
    return out
end

local function findAtt(char, name)
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("Attachment") and p.Name == name and p.Parent:IsA("BasePart") then
            return p
        end
    end
end

local function applyBody(char)
    local total = 0
    for _, id in ipairs(HOMERO_CFG.body) do
        local objs = loadObjects(id)
        if objs then
            for _, mp in ipairs(collectParts(objs)) do
                local orig = char:FindFirstChild(mp.Name)
                if orig and orig:IsA("BasePart") then
                    local c = mp:Clone()
                    c.Name = TAG .. "body_" .. mp.Name
                    c.CanCollide = false
                    c.Anchored = false
                    c.Massless = true
                    c.Size = orig.Size
                    c.CFrame = orig.CFrame
                    c.Parent = char
                    local w = Instance.new("WeldConstraint")
                    w.Part0 = orig
                    w.Part1 = c
                    w.Parent = c
                    orig.Transparency = 1
                    total = total + 1
                end
            end
            for _, o in ipairs(objs) do pcall(function() o:Destroy() end) end
        end
    end
    return total
end

local function attachItem(char, entry)
    local objs = loadObjects(entry.id)
    if not objs then return false end

    local handle
    for _, p in ipairs(collectParts(objs)) do
        if p.Name == "Handle" then handle = p; break end
        if not handle then handle = p end
    end
    if not handle then
        for _, o in ipairs(objs) do pcall(function() o:Destroy() end) end
        return false
    end

    local H = handle:Clone()
    for _, o in ipairs(objs) do pcall(function() o:Destroy() end) end

    H.Name = TAG .. "item_" .. tostring(entry.id)
    H.CanCollide = false
    H.Anchored = false
    H.Massless = true

    local wrap = H:FindFirstChildWhichIsA("WrapLayer")
    local target, c0, c1

    if wrap then
        target = char:FindFirstChild("UpperTorso")
              or char:FindFirstChild("Torso")
              or char:FindFirstChild("HumanoidRootPart")
        c0 = entry.offset or _CFnew()
        c1 = _CFnew()
    else
        local hAtt = H:FindFirstChildOfClass("Attachment")
        local bAtt = hAtt and findAtt(char, hAtt.Name)
        if bAtt then
            target = bAtt.Parent
            c0 = bAtt.CFrame * (entry.offset or _CFnew())
            c1 = hAtt.CFrame
        else
            target = char:FindFirstChild("Head")
            c0 = entry.offset or _CFnew(0, 1.4, 0)
            c1 = _CFnew()
        end
    end

    if not target then H:Destroy(); return false end

    H.CFrame = target.CFrame * c0 * c1:Inverse()
    H.Parent = char

    local w = Instance.new("Weld")
    w.Part0 = target
    w.Part1 = H
    w.C0 = c0
    w.C1 = c1
    w.Parent = H
    return true
end

function applyHomeroOutfit(char)
    if not char then char = LP.Character end
    if not char then return end
    char:WaitForChild("Humanoid", 10)
    char:WaitForChild("Head", 10)
    task.wait(0.4)

    for _, d in ipairs(char:GetChildren()) do
        if d.Name:sub(1, #TAG) == TAG then pcall(function() d:Destroy() end) end
    end

    if HOMERO_CFG.skinColor then
        local bc = char:FindFirstChildWhichIsA("BodyColors") or Instance.new("BodyColors")
        bc.HeadColor3 = HOMERO_CFG.headColor or HOMERO_CFG.skinColor
        bc.TorsoColor3 = HOMERO_CFG.skinColor
        bc.LeftArmColor3, bc.RightArmColor3 = HOMERO_CFG.skinColor, HOMERO_CFG.skinColor
        bc.LeftLegColor3, bc.RightLegColor3 = HOMERO_CFG.skinColor, HOMERO_CFG.skinColor
        bc.Parent = char
    end

    for _, a in ipairs(char:GetChildren()) do
        if a:IsA("Accessory") then
            local h = a:FindFirstChild("Handle")
            if h then h.Transparency = 1 end
        end
    end

    if HOMERO_CFG.shirt then
        local s = char:FindFirstChildWhichIsA("Shirt") or Instance.new("Shirt")
        s.Name = "Shirt"
        s.ShirtTemplate = HOMERO_CFG.shirt
        s.Parent = char
    end
    if HOMERO_CFG.pants then
        local p = char:FindFirstChildWhichIsA("Pants") or Instance.new("Pants")
        p.Name = "Pants"
        p.PantsTemplate = HOMERO_CFG.pants
        p.Parent = char
    end
    if HOMERO_CFG.aplicarCuerpo then applyBody(char) end
    for _, e in ipairs(HOMERO_CFG.items) do attachItem(char, e) end
end

local function applyNoOutfit(char)
    if not char then char = LP.Character end
    if not char then return end
    for _, d in ipairs(char:GetChildren()) do
        if d.Name:sub(1, #TAG) == TAG then pcall(function() d:Destroy() end) end
    end
    local oldAcc = char:FindFirstChild("AuFfitAccessory")
    if oldAcc then pcall(function() oldAcc:Destroy() end) end
    local oldKorblox = char:FindFirstChild("Korblox_RightLeg")
    if oldKorblox then pcall(function() oldKorblox:Destroy() end) end
    for _, d in ipairs(char:GetChildren()) do
        if d:IsA("CharacterMesh") and d.BodyPart == Enum.BodyPart.Head then
            pcall(function() d:Destroy() end)
        end
    end
    local head = char:FindFirstChild("Head")
    if head then
        head.Transparency = 0
        head.CanCollide = true
        head.LocalTransparencyModifier = 0
        local face = head:FindFirstChild("face")
        if face then face.Transparency = 0 end
        local sm = head:FindFirstChildWhichIsA("SpecialMesh")
        if sm then pcall(function() sm:Destroy() end) end
    end
    pcall(function()
        local neck = char:FindFirstChild("Neck")
        if neck then neck.Enabled = true end
    end)
    for _, partName in ipairs({"RightUpperLeg", "RightLowerLeg", "RightFoot"}) do
        local limb = char:FindFirstChild(partName)
        if limb then limb.Transparency = 0 end
    end
    local shirt = char:FindFirstChildWhichIsA("Shirt")
    if shirt then pcall(function() shirt:Destroy() end) end
    local pants = char:FindFirstChildWhichIsA("Pants")
    if pants then pcall(function() pants:Destroy() end) end
    for _, a in ipairs(char:GetChildren()) do
        if a:IsA("Accessory") then
            local h = a:FindFirstChild("Handle")
            if h then h.Transparency = 0 end
        end
    end
end

local KAWATAN_OUTFIT_SETS = {
    {
        label = "PURPLE",
        hats = "1744060292,439945661,1125510,1029025",
        hair = "",
        accessories = {1744060292,439945661,1125510,1029025,11748356,8465506143,11444217173},
        clothing = {7424637509,7689651773},
    },
    {
        label = "BLUE",
        hats = "74891470",
        hair = "16630147,6346833550,6594911228,6594919952,6823338112,7097747842",
        accessories = {74891470,16630147,6346833550,6594911228,6594919952,6823338112,7097747842},
        clothing = {18423061209,18423154566},
    },
    {
        label = "RED",
        hats = "215718515,439945661",
        hair = "7183785281",
        accessories = {215718515,439945661,7183785281},
        clothing = {15998365201,7689651773},
    },
    {
        label = "BLACK",
        hats = "10159600649,439946249,17798262442,92482095662016",
        hair = "139101716417676",
        accessories = {10159600649,439946249,17798262442,92482095662016,139101716417676,12490213797},
        clothing = {18766106994,13925390578},
    },
    {
        label = "GREEN",
        hats = "553970961,1744060292",
        hair = "93268856876777",
        accessories = {553970961,1744060292,93268856876777},
        clothing = {9478068776,6348682339},
    },
    {
        label = "WHITE",
        hats = "74891470,215718515,439945661,1016143686,1744060292,10159600649,89012651581593,88365652378427",
        hair = "126447390530523",
        accessories = {74891470,215718515,439945661,1016143686,1744060292,10159600649,89012651581593,126447390530523},
        clothing = {88032876921227,108259950755140},
    },
}

-- Avatar Catalog'daki 6 görünüşü Sakura.vs Outfit seçicisine bağlar.
local OUTFITS = {}
for i, skin in ipairs(KAWATAN_OUTFIT_SETS) do
    OUTFITS[i] = { label = skin.label, kawatan = skin }
end

local currentOutfitIndex = 1
local outfitSelectorLabel = nil

local function loadObjectsStd(id)
    local ok, res = pcall(function() return game:GetObjects("rbxassetid://" .. tostring(id)) end)
    if ok and typeof(res) == "table" and #res > 0 then return res end
    ok, res = pcall(function() return game:GetService("InsertService"):LoadAsset(id) end)
    if ok and res then return {res} end
    return nil
end

local function applyHeadlessKorblox(char)
    if not char then return end
    pcall(function() LP.CharacterAvatarType = Enum.AvatarType.R6 end)
    local head = char:FindFirstChild("Head")
    if head then
        head.Transparency = 1
        head.CanCollide = false
        head.LocalTransparencyModifier = 1
        local face = head:FindFirstChild("face")
        if face then face.Transparency = 1 end
    end
    pcall(function()
        local neck = char:FindFirstChild("Neck")
        if neck then neck.Enabled = false end
    end)
    for _, v in pairs(char:GetChildren()) do
        if v:IsA("Accessory") then
            local w = v:FindFirstChildWhichIsA("Weld") or v:FindFirstChildWhichIsA("WeldConstraint") or v:FindFirstChildWhichIsA("Motor6D")
            if w then
                local p0, p1 = w.Part0, w.Part1
                if (p0 and p0.Name == "Head") or (p1 and p1.Name == "Head") then
                    v.Parent = nil
                end
            end
        end
    end
    local rightLegConfig = {
        id = "rbxassetid://139607718",
        targetBodyPart = "RightUpperLeg",
        partsToHide = {"RightUpperLeg", "RightLowerLeg", "RightFoot"},
        scale = _V3new(1, 1, 1),
        offset = _CFnew(0, 0, 0)
    }
    local targetPart = char:FindFirstChild(rightLegConfig.targetBodyPart)
    if targetPart then
        local oldAsset = char:FindFirstChild("Korblox_RightLeg")
        if oldAsset then oldAsset:Destroy() end
        for _, partName in ipairs(rightLegConfig.partsToHide) do
            local limb = char:FindFirstChild(partName)
            if limb and limb:IsA("BasePart") then limb.Transparency = 1 end
        end
        local success, objects = pcall(function() return game:GetObjects(rightLegConfig.id) end)
        if success and objects and #objects > 0 then
            local assetModel = objects[1]
            assetModel.Name = "Korblox_RightLeg"
            local mainMesh = assetModel:IsA("BasePart") and assetModel or assetModel:FindFirstChildWhichIsA("BasePart", true)
            if mainMesh then
                mainMesh.Size = mainMesh.Size * rightLegConfig.scale
                mainMesh.CanCollide = false
                mainMesh.CFrame = targetPart.CFrame * rightLegConfig.offset
                local weld = Instance.new("WeldConstraint")
                weld.Part0 = targetPart
                weld.Part1 = mainMesh
                weld.Parent = mainMesh
                assetModel.Parent = char
            end
        end
    end
end

local function clearSakuraOutfitObjects(char)
    if not char then return end
    for _, d in ipairs(char:GetChildren()) do
        if d:GetAttribute("SakuraOutfitObject") then
            pcall(function() d:Destroy() end)
        end
    end
    for _, d in ipairs(char:GetChildren()) do
        if d:IsA("Shirt") or d:IsA("Pants") or d:IsA("ShirtGraphic") then
            pcall(function() d:Destroy() end)
        end
    end
    for _, name in ipairs({"AuFfitAccessory", "Korblox_RightLeg"}) do
        local old = char:FindFirstChild(name)
        if old then pcall(function() old:Destroy() end) end
    end
end

local function hideHeadForCatalog(char, hidden)
    local head = char and char:FindFirstChild("Head")
    if not head then return end
    head.Transparency = hidden and 1 or 0
    head.LocalTransparencyModifier = hidden and 1 or 0
    head.CanCollide = not hidden
    local face = head:FindFirstChild("face")
    if face then face.Transparency = hidden and 1 or 0 end
    local neck = char:FindFirstChild("Neck")
    if neck then neck.Enabled = not hidden end
end

local function addCatalogAsset(char, assetId)
    local objs = loadObjectsStd(assetId)
    if not objs then return end
    for _, obj in ipairs(objs) do
        local candidates = {}
        if obj:IsA("Accessory") or obj:IsA("Shirt") or obj:IsA("Pants") then
            table.insert(candidates, obj)
        else
            for _, d in ipairs(obj:GetDescendants()) do
                if d:IsA("Accessory") or d:IsA("Shirt") or d:IsA("Pants") then
                    table.insert(candidates, d)
                end
            end
        end
        for _, item in ipairs(candidates) do
            local clone = item:Clone()
            clone:SetAttribute("SakuraOutfitObject", true)
            clone.Parent = char
        end
        pcall(function() obj:Destroy() end)
    end
end

local function applyKawatanCatalogOutfit(char, skin)
    if not char or not skin then return end
    clearSakuraOutfitObjects(char)

    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if humanoid then
        -- Önce mevcut description aksesuarlarını temizle; sonra katalog parçalarını ekle.
        pcall(function()
            local desc = humanoid:GetAppliedDescription()
            if desc then
                desc.HatAccessory = ""
                desc.HairAccessory = ""
                desc.FaceAccessory = ""
                desc.NeckAccessory = ""
                desc.ShouldersAccessory = ""
                desc.FrontAccessory = ""
                desc.BackAccessory = ""
                desc.WaistAccessory = ""
                desc.Shirt = 0
                desc.Pants = 0
                desc.GraphicTShirt = 0
                humanoid:ApplyDescription(desc)
            end
        end)
    end

    -- Katalogdaki gövde kıyafetleri.
    if skin.clothing[1] then addCatalogAsset(char, skin.clothing[1]) end
    if skin.clothing[2] then addCatalogAsset(char, skin.clothing[2]) end

    -- Katalogdaki tüm aksesuarlar.
    for _, id in ipairs(skin.accessories) do
        addCatalogAsset(char, id)
    end

    -- Görseldeki headless görünüm.
    hideHeadForCatalog(char, true)

    -- Sağ bacak için Sakura'nın mevcut Korblox uygulamasını kullanmadan basit uyarlama.
    local oldLeg = char:FindFirstChild("SakuraCatalog_RightLeg")
    if oldLeg then pcall(function() oldLeg:Destroy() end) end
    for _, n in ipairs({"RightUpperLeg", "RightLowerLeg", "RightFoot"}) do
        local part = char:FindFirstChild(n)
        if part and part:IsA("BasePart") then part.Transparency = 1 end
    end

    local rightLegPart = char:FindFirstChild("RightUpperLeg") or char:FindFirstChild("Right Leg")
    if rightLegPart then
        local ok, objects = pcall(function() return game:GetObjects("rbxassetid://139607718") end)
        if ok and objects and #objects > 0 then
            local model = objects[1]
            model.Name = "SakuraCatalog_RightLeg"
            model:SetAttribute("SakuraOutfitObject", true)
            local mesh = model:IsA("BasePart") and model or model:FindFirstChildWhichIsA("BasePart", true)
            if mesh then
                mesh.CanCollide = false
                mesh.Anchored = false
                mesh.CFrame = rightLegPart.CFrame
                local weld = Instance.new("WeldConstraint")
                weld.Part0 = rightLegPart
                weld.Part1 = mesh
                weld.Parent = mesh
                model.Parent = char
            end
        end
    end
end

function applyOutfitByIndex(index)
    local cfg = OUTFITS[index]
    if not cfg then return end
    local char = LP.Character
    if not char then return end

    if cfg.kawatan then
        applyKawatanCatalogOutfit(char, cfg.kawatan)
        if outfitSelectorLabel then outfitSelectorLabel.Text = tostring(cfg.label) .. "  ▼" end
        return
    end

    if cfg.customApply then
        cfg.customApply(char)
        if outfitSelectorLabel then outfitSelectorLabel.Text = tostring(cfg.label) .. "  ▼" end
        return
    end

    char:WaitForChild("Head", 5)
    local head = char:FindFirstChild("Head")
    if not head then return end
    for _, d in ipairs(char:GetChildren()) do
        if d:IsA("CharacterMesh") and d.BodyPart == Enum.BodyPart.Head then
            pcall(function() d:Destroy() end)
        end
    end
    local done = false
    if head:IsA("MeshPart") then
        done = pcall(function()
            head.MeshId = cfg.headMesh
            if cfg.headTexture then head.TextureID = cfg.headTexture end
        end)
    end
    if not done then
        local sm = head:FindFirstChildWhichIsA("SpecialMesh") or Instance.new("SpecialMesh")
        sm.Parent = head
        sm.MeshType = Enum.MeshType.FileMesh
        sm.MeshId = cfg.headMesh
        sm.TextureId = cfg.headTexture or ""
    end
    if cfg.shirt then
        local s = char:FindFirstChildWhichIsA("Shirt") or Instance.new("Shirt")
        s.Name = "Shirt"
        s.ShirtTemplate = cfg.shirt
        s.Parent = char
    end
    if cfg.pants then
        local p = char:FindFirstChildWhichIsA("Pants") or Instance.new("Pants")
        p.Name = "Pants"
        p.PantsTemplate = cfg.pants
        p.Parent = char
    end
    local old = char:FindFirstChild("AuFfitAccessory")
    if old then old:Destroy() end
    if cfg.accessory and head then
        local objs = loadObjectsStd(cfg.accessory)
        if objs then
            local handle
            for _, o in ipairs(objs) do
                if o:IsA("BasePart") then handle = o; break end
                local f = o:FindFirstChildWhichIsA("BasePart", true)
                if f then handle = f; break end
            end
            if handle then
                local h = handle:Clone()
                h.Name = "AuFfitAccessory"
                h.CanCollide = false
                h.Anchored = false
                h.Massless = true
                h.Parent = char
                local weld = Instance.new("Weld")
                weld.Part0 = head
                weld.Part1 = h
                weld.C0 = _CFnew(cfg.offset)
                weld.Parent = h
            end
            for _, o in ipairs(objs) do pcall(function() o:Destroy() end) end
        end
    end
    if cfg.headlessKorblox then
        applyHeadlessKorblox(char)
    else
        if char then
            local head2 = char:FindFirstChild("Head")
            if head2 then
                head2.Transparency = 0
                head2.CanCollide = true
                head2.LocalTransparencyModifier = 0
                local face2 = head2:FindFirstChild("face")
                if face2 then face2.Transparency = 0 end
            end
            pcall(function()
                local neck = char:FindFirstChild("Neck")
                if neck then neck.Enabled = true end
            end)
            for _, partName in ipairs({"RightUpperLeg", "RightLowerLeg", "RightFoot"}) do
                local limb = char:FindFirstChild(partName)
                if limb then limb.Transparency = 0 end
            end
            local oldKorblox = char:FindFirstChild("Korblox_RightLeg")
            if oldKorblox then oldKorblox:Destroy() end
        end
    end
    if outfitSelectorLabel then outfitSelectorLabel.Text = tostring(cfg.label) .. "  ▼" end
end

speedMode = false
autoCarrySpeedEnabled = false -- Candy.vs Auto Carry Speed: auto-use carry speed while stealing
antiRagdollMode = "off"
antiDieEnabled = false
antiFlingEnabled = false
jumpEnabled = false
laggerToggled = false
laggerCarryToggled = false
medusaCounterEnabled = false
batCounterEnabled = false
unwalkEnabled = false
antiBatEnabled = false
antiBatConn = nil
antiBatPanelVisible = false
antiBatPanelGui = nil
kickWarningEnabled = false
_G._SakuraVsKickWarn = { active = false, gen = 0 }
autoLeftEnabled = false
autoRightEnabled = false
autoTpDownEnabled = false
autoTpDownRadius = -5
_autoTpDownConn = nil
autoTpDownRadiusBox = nil
autoBatEnabled = false
BAT_COUNTER_V2_TOUCH_DIST = 10
batCounterV3StudBox = nil
dropMode = 1
antiLagEnabled = false
removeAccessoriesEnabled = false
customToolsEnabled = false
stretchEnabled = false
stretchFOV = 120
uiLocked = true
editModeEnabled = false
uiScaleValue = 78
stealBarScale = 100
antiAimbotEnabled = false
antiAimbotMode = "V1" -- V1 Spectrum | V2 Clean Bat Bypass
antiAimbotModeLabel = nil
setAntiAimbotVisual = nil
tauntEnabled = false
setTauntVisual = nil
mobSetTaunt = nil
_tauntThread = nil
spinEnabled = false
spinSpeed = 0.35
spinSpeedName = "Normal"
spinConn = nil
setSpinVisual = nil
spinSpeedSelectorLabel = nil

setAntiAimbotVisual = nil
espEnabled = false

bodyLockEnabled = false
bodyLockRange = 20
bodyLockRangeBox = nil
_bodyLockConn = nil
_blSuppressCount = 0
_blWasEnabled = false
_blRestoreTimer = nil
_blSmoothRestore = false

savedProgressBarPos = nil
savedButtonPositions = {}
savedMobilePanelPos = nil
tpBatFloatingPos = nil
batV2FloatingPos = nil
instaResetFloatingPos = nil
instaResetFloatingButton = nil

neonWeatherEnabled = false
skyTheme = "Off"
skySelectorLabel = nil
_originalLighting = nil
setNeonWeatherVisual = nil

currentAnimPack = "Off"
originalTryardAnims = nil
tryardHeartbeatConn = nil
animSelectorLabel = nil

autoBatV2Enabled = false
autoBatV2SwingEnabled = true
autoBatV2HitCooldown = false
AUTO_BAT_V2_SPEED = 60
AUTO_BAT_V2_DIST = 1.0
AUTO_BAT_V2_HEIGHT = 1.5
AUTO_BAT_V2_V_OFF = 0.0
AUTO_BAT_V2_HIT_DIST = 4.5
AUTO_BAT_V2_SWING_CD = 0.08
_batV2Conn = nil

useCarrySystem = true
lastMoveDir = _V3zero

local CoreGui = game:GetService("CoreGui")

-- ============================================================
-- INFINITE JUMP (from Sakura.vs) — HOLD + MANUAL
-- HOLD: Space basili tut = surekli zıpla, birak = dur
-- MANUAL: her JumpRequest / Space basisi tek zıpla
-- ============================================================
infJumpEnabled = false
infJumpMode    = "HOLD" -- "HOLD" | "MANUAL"
infJumpModeLabel = nil
if batDesyncTpEnabled == nil then batDesyncTpEnabled = false end
if dropActive == nil then dropActive = false end

_G.SakuraVsNormalInfJump = _G.SakuraVsNormalInfJump or {
    holdPressed = false, holdActive = false,
    controllerActive = false, mobilePressed = false,
    mobileActive = false, hooked = {}
}

function _G._jumpEnsureProxy()
    local char = LP.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

function _G.SakuraVsApplyNormalInfJumpBoost(boost)
    if not infJumpEnabled then return end
    if batDesyncTpEnabled then return end
    if dropActive then return end
    local char = LP.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end
    local proxy = _G._jumpEnsureProxy()
    if not proxy then return end
    local curVel = proxy.AssemblyLinearVelocity
    local y = boost or 50
    proxy.AssemblyLinearVelocity = _V3new(curVel.X, y, curVel.Z)
    pcall(function()
        proxy.Velocity = _V3new(proxy.Velocity.X, y, proxy.Velocity.Z)
    end)
end

function _G.SakuraVsStopNormalInfJumpHoldState()
    local S = _G.SakuraVsNormalInfJump
    S.holdPressed = false
    S.holdActive = false
    S.controllerActive = false
    S.mobilePressed = false
    S.mobileActive = false
end

-- JumpRequest: MANUAL + HOLD (tek basista da zıplasın)
UIS.JumpRequest:Connect(function()
    if not infJumpEnabled then return end
    if UIS:GetFocusedTextBox() then return end
    _G.SakuraVsApplyNormalInfJumpBoost(50)
end)

UIS.InputBegan:Connect(function(input)
    if UIS:GetFocusedTextBox() then return end
    local S = _G.SakuraVsNormalInfJump

    if input.UserInputType == Enum.UserInputType.Keyboard
       and input.KeyCode == Enum.KeyCode.Space then
        if infJumpMode == "MANUAL" then return end
        S.holdPressed = true
        task.delay(0.12, function()
            if _G.SakuraVsNormalInfJump.holdPressed and infJumpEnabled then
                _G.SakuraVsNormalInfJump.holdActive = true
                _G.SakuraVsApplyNormalInfJumpBoost(50)
            end
        end)
    elseif input.KeyCode == Enum.KeyCode.ButtonA
       and input.UserInputType and tostring(input.UserInputType):find("Gamepad") then
        if infJumpMode ~= "MANUAL" then S.controllerActive = true end
    end
end)

UIS.InputEnded:Connect(function(input)
    local S = _G.SakuraVsNormalInfJump
    if input.UserInputType == Enum.UserInputType.Keyboard
       and input.KeyCode == Enum.KeyCode.Space then
        S.holdPressed = false
        S.holdActive  = false
    end
    if input.KeyCode == Enum.KeyCode.ButtonA
       and input.UserInputType and tostring(input.UserInputType):find("Gamepad") then
        S.controllerActive = false
    end
end)

function _G.SakuraVsHookNormalInfMobileJumpButton(obj)
    local S = _G.SakuraVsNormalInfJump
    if not obj or obj.Name ~= "JumpButton"
       or not obj:IsA("GuiButton") or S.hooked[obj] then return end
    S.hooked[obj] = true
    obj.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.Touch
           or not infJumpEnabled then return end
        if infJumpMode == "MANUAL" then return end
        S.mobilePressed = true
        task.delay(0.12, function()
            if S.mobilePressed and infJumpEnabled then
                S.mobileActive = true
                _G.SakuraVsApplyNormalInfJumpBoost(50)
            end
        end)
    end)
    obj.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            S.mobilePressed = false
            S.mobileActive  = false
        end
    end)
end

do
    local pg = LP:FindFirstChildOfClass("PlayerGui")
    if pg then
        for _, obj in ipairs(pg:GetDescendants()) do
            _G.SakuraVsHookNormalInfMobileJumpButton(obj)
        end
        pg.DescendantAdded:Connect(function(obj)
            task.defer(_G.SakuraVsHookNormalInfMobileJumpButton, obj)
        end)
    end
end

RunService.Heartbeat:Connect(function()
    local S = _G.SakuraVsNormalInfJump
    if infJumpEnabled and infJumpMode == "HOLD"
       and (S.holdActive or S.mobileActive or S.controllerActive) then
        _G.SakuraVsApplyNormalInfJumpBoost(50)
    end
end)

function _G.setInfJumpInternal(on)
    infJumpEnabled = on and true or false
    if not infJumpEnabled then
        _G.SakuraVsStopNormalInfJumpHoldState()
        local ch = LP.Character
        local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
        if hrp then
            pcall(function()
                local v = hrp.AssemblyLinearVelocity
                hrp.AssemblyLinearVelocity = _V3new(v.X, math.min(v.Y, 0), v.Z)
            end)
        end
    end
end

InfiniteJump = {
    start = function() _G.setInfJumpInternal(true)  end,
    stop  = function() _G.setInfJumpInternal(false) end,
    isRunning = function() return infJumpEnabled == true end,
    setJumpPower = function() end,
    setMode = function(mode)
        if mode == "manual" or mode == "MANUAL" then
            infJumpMode = "MANUAL"
            _G.SakuraVsStopNormalInfJumpHoldState()
        else
            infJumpMode = "HOLD"
        end
    end,
}

-- Controlled by Visual tab / AntiBat panel toggle; do not auto-start


local function getCharParts()
    local char = LP.Character
    if not char then return nil, nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return nil, nil end
    return hum, root
end

local function claimOwnership(root)
    pcall(function() root:SetNetworkOwner(LP) end)
end

function getActiveMoveSpeed()
    if useCarrySystem and CarrySystem then
        -- Keep CarrySystem speeds authoritative (NS/CS boxes sync into it)
        if laggerCarryToggled then
            CarrySystem:setLaggerMode(2)
            return CarrySystem.laggerCarrySpeed
        elseif laggerToggled then
            CarrySystem:setLaggerMode(1)
            return CarrySystem.laggerSpeed
        else
            CarrySystem:setLaggerMode(0)
        end
        CarrySystem.speedToggled = speedMode == true
        if speedMode then
            return CarrySystem.carrySpeed or CS
        end
        if autoCarrySpeedEnabled and CarrySystem:isCarrying() then
            return CarrySystem.carrySpeed or CS
        end
        return CarrySystem.normalSpeed or NS
    end
    if laggerCarryToggled then return LAGGER_CARRY_SPEED
    elseif laggerToggled then return LAGGER_SPEED
    elseif speedMode then return CS
    elseif autoCarrySpeedEnabled and CarrySystem:isCarrying() then return CS
    else return NS end
end

local _velChecked = {}
local _hookedVelParts = {}

local function _setupVelChecked(char)
    _velChecked = {}
    if not char then return end
    local hrp = char:WaitForChild("HumanoidRootPart", 5)
    if hrp then _velChecked[hrp] = true end
    return hrp
end

local _hookVelSupported = nil
local function _hookVelHRP(hrp)
    if not hrp or _hookedVelParts[hrp] then return end
    if _hookVelSupported == false then return end
    if _hookVelSupported == nil then
        _hookVelSupported = (type(getrawmetatable) == "function")
            and (type(setreadonly) == "function")
            and (type(newcclosure) == "function")
            and (type(checkcaller) == "function")
    end
    if not _hookVelSupported then return end
    _hookedVelParts[hrp] = true
    local ok = pcall(function()
        local mt = getrawmetatable(hrp)
        if not mt then return end
        setreadonly(mt, false)
        local originalVelIndex = rawget(mt, "__index")
        mt.__index = newcclosure(function(self, key)
            if not checkcaller() and _velChecked[self]
               and (key == "AssemblyLinearVelocity" or key == "Velocity") then
                local real
                if type(originalVelIndex) == "function" then
                    real = originalVelIndex(self, key)
                elseif type(originalVelIndex) == "table" then
                    real = originalVelIndex[key]
                end
                if real and real.Magnitude > 20 then return real.Unit * 20 end
                return real
            end
            if type(originalVelIndex) == "function" then
                return originalVelIndex(self, key)
            elseif type(originalVelIndex) == "table" then
                return originalVelIndex[key]
            end
        end)
        setreadonly(mt, true)
    end)
    if not ok then _hookVelSupported = false end
end

if LP.Character then
    local _hrp0 = _setupVelChecked(LP.Character)
    _hookVelHRP(_hrp0)
end

local function _isRagdollState(hum)
    if not hum then return true end
    local st = hum:GetState()
    return hum.PlatformStand
        or st == Enum.HumanoidStateType.Physics
        or st == Enum.HumanoidStateType.Ragdoll
        or st == Enum.HumanoidStateType.FallingDown
end

local function _applyVelocitySpeed(dir, speed, hrp)
    if not hrp or not hrp.Parent then return end
    if autoBatV2Enabled or batDesyncTpEnabled or autoBatEnabled then return end
    if dir and dir.Magnitude > 0.05 then
        pcall(function()
            if hrp.SetNetworkOwner then hrp:SetNetworkOwner(LP) end
        end)
        local unit = dir.Unit
        local vy = hrp.AssemblyLinearVelocity.Y
        hrp.AssemblyLinearVelocity = _V3new(unit.X * speed, vy, unit.Z * speed)
    else
        local vy = hrp.AssemblyLinearVelocity.Y
        hrp.AssemblyLinearVelocity = _V3new(0, vy, 0)
    end
end

function getAutoPathSpeed()
    if laggerCarryToggled or laggerToggled then return LAGGER_SPEED end
    return NS
end

ANIM_PACKS = {
    ["Zombie"] = { idle1="rbxassetid://616158929", idle2="rbxassetid://616160636", walk="rbxassetid://616168032", run="rbxassetid://616163682", jump="rbxassetid://616161997", fall="rbxassetid://616157476", climb="rbxassetid://616156119", swim="rbxassetid://616165109", swimidle="rbxassetid://616166655" },
    ["Ninja"] = { idle1="rbxassetid://656117400", idle2="rbxassetid://656117400", walk="rbxassetid://656121766", run="rbxassetid://656118852", jump="rbxassetid://656117878", fall="rbxassetid://656115606", climb="rbxassetid://656114359", swim="rbxassetid://656117400", swimidle="rbxassetid://656117400" },
    ["Knight"] = { idle1="rbxassetid://657595757", idle2="rbxassetid://657595757", walk="rbxassetid://657552124", run="rbxassetid://657564596", jump="rbxassetid://658409194", fall="rbxassetid://657600338", climb="rbxassetid://658360781", swim="rbxassetid://657595757", swimidle="rbxassetid://657595757" },
    ["Elder"] = { idle1="rbxassetid://845397899", idle2="rbxassetid://845397899", walk="rbxassetid://845403856", run="rbxassetid://845386501", jump="rbxassetid://845398858", fall="rbxassetid://845397673", climb="rbxassetid://845392038", swim="rbxassetid://845397899", swimidle="rbxassetid://845397899" },
    ["Levitate"] = { idle1="rbxassetid://616006778", idle2="rbxassetid://616006778", walk="rbxassetid://616013216", run="rbxassetid://616013216", jump="rbxassetid://616008936", fall="rbxassetid://616005863", climb="rbxassetid://616003713", swim="rbxassetid://616006778", swimidle="rbxassetid://616006778" },
    ["Astronaut"] = { idle1="rbxassetid://891621366", idle2="rbxassetid://891621366", walk="rbxassetid://891636393", run="rbxassetid://891636393", jump="rbxassetid://891627522", fall="rbxassetid://891617961", climb="rbxassetid://891609353", swim="rbxassetid://891621366", swimidle="rbxassetid://891621366" },
    ["Pirate"] = { idle1="rbxassetid://750781874", idle2="rbxassetid://750781874", walk="rbxassetid://750785693", run="rbxassetid://750783738", jump="rbxassetid://750782230", fall="rbxassetid://750780242", climb="rbxassetid://750779899", swim="rbxassetid://750781874", swimidle="rbxassetid://750781874" },
    ["Toy"] = { idle1="rbxassetid://782841498", idle2="rbxassetid://782841498", walk="rbxassetid://782843345", run="rbxassetid://782842708", jump="rbxassetid://782847020", fall="rbxassetid://782846423", climb="rbxassetid://782843869", swim="rbxassetid://782841498", swimidle="rbxassetid://782841498" },
    ["Vampire"] = { idle1="rbxassetid://1083445855", idle2="rbxassetid://1083445855", walk="rbxassetid://1083473930", run="rbxassetid://1083462077", jump="rbxassetid://1083455352", fall="rbxassetid://1083443587", climb="rbxassetid://1083439238", swim="rbxassetid://1083445855", swimidle="rbxassetid://1083445855" },
    ["Werewolf"] = { idle1="rbxassetid://1083195517", idle2="rbxassetid://1083195517", walk="rbxassetid://1083178339", run="rbxassetid://1083216690", jump="rbxassetid://1083218792", fall="rbxassetid://1083189019", climb="rbxassetid://1083182000", swim="rbxassetid://1083195517", swimidle="rbxassetid://1083195517" },
    ["Rthro"] = { idle1="rbxassetid://2510196951", idle2="rbxassetid://2510196951", walk="rbxassetid://2510202577", run="rbxassetid://2510198475", jump="rbxassetid://2510197830", fall="rbxassetid://2510195892", climb="rbxassetid://2510192778", swim="rbxassetid://2510196951", swimidle="rbxassetid://2510196951" },
    ["Stylish"] = { idle1="rbxassetid://616136790", idle2="rbxassetid://616136790", walk="rbxassetid://616146177", run="rbxassetid://616140816", jump="rbxassetid://616139451", fall="rbxassetid://616134815", climb="rbxassetid://616133594", swim="rbxassetid://616136790", swimidle="rbxassetid://616136790" },
}

ANIM_PACK_ORDER = {{"Off", "Off"}, {"Zombie", "Zombie"}, {"Ninja", "Ninja"}, {"Knight", "Knight"}, {"Elder", "Elder"}, {"Levitate", "Levitate"}, {"Astronaut", "Astronaut"}, {"Pirate", "Pirate"}, {"Toy", "Toy"}, {"Vampire", "Vampire"}, {"Werewolf", "Werewolf"}, {"Rthro", "Rthro"}, {"Stylish", "Stylish"}}

local function isPackAnim(id)
    for _, pack in pairs(ANIM_PACKS) do
        for _, v in pairs(pack) do
            if v == id then return true end
        end
    end
    return false
end

local function saveOriginalAnims(char)
    local animate = char:FindFirstChild("Animate")
    if not animate then return end
    local function g(obj) return obj and obj.AnimationId or nil end
    local ids = {
        idle1 = g(animate.idle and animate.idle.Animation1),
        idle2 = g(animate.idle and animate.idle.Animation2),
        walk  = g(animate.walk and animate.walk.WalkAnim),
        run   = g(animate.run  and animate.run.RunAnim),
        jump  = g(animate.jump and animate.jump.JumpAnim),
        fall  = g(animate.fall and animate.fall.FallAnim),
        climb = g(animate.climb and animate.climb.ClimbAnim),
        swim  = g(animate.swim and animate.swim.Swim),
        swimidle = g(animate.swimidle and animate.swimidle.SwimIdle),
    }
    if not isPackAnim(ids.walk) then originalTryardAnims = ids end
end

local function applyAnimPack(packName)
    currentAnimPack = packName
    if animSelectorLabel then animSelectorLabel.Text = tostring(packName) .. "  ▼" end
    if packName == "Off" then
        if originalTryardAnims and LP.Character then
            local animate = LP.Character:FindFirstChild("Animate")
            if animate then
                local function s(obj,id) if obj then obj.AnimationId = id end end
                s(animate.idle and animate.idle.Animation1, originalTryardAnims.idle1)
                s(animate.idle and animate.idle.Animation2, originalTryardAnims.idle2)
                s(animate.walk and animate.walk.WalkAnim, originalTryardAnims.walk)
                s(animate.run  and animate.run.RunAnim,   originalTryardAnims.run)
                s(animate.jump and animate.jump.JumpAnim, originalTryardAnims.jump)
                s(animate.fall and animate.fall.FallAnim, originalTryardAnims.fall)
                s(animate.climb and animate.climb.ClimbAnim, originalTryardAnims.climb)
                s(animate.swim and animate.swim.Swim, originalTryardAnims.swim)
                s(animate.swimidle and animate.swimidle.SwimIdle, originalTryardAnims.swimidle)
            end
        end
        if tryardHeartbeatConn then tryardHeartbeatConn:Disconnect(); tryardHeartbeatConn = nil end
        return
    end
    local pack = ANIM_PACKS[packName]
    if not pack then return end
    if tryardHeartbeatConn then tryardHeartbeatConn:Disconnect() end
    tryardHeartbeatConn = RunService.Heartbeat:Connect(function()
        local c = LP.Character
        if not c then return end
        local animate = c:FindFirstChild("Animate")
        if not animate then return end
        local function s(obj,id) if obj then obj.AnimationId = id end end
        s(animate.idle and animate.idle.Animation1, pack.idle1)
        s(animate.idle and animate.idle.Animation2, pack.idle2)
        s(animate.walk and animate.walk.WalkAnim, pack.walk)
        s(animate.run  and animate.run.RunAnim,   pack.run)
        s(animate.jump and animate.jump.JumpAnim, pack.jump)
        s(animate.fall and animate.fall.FallAnim, pack.fall)
        s(animate.climb and animate.climb.ClimbAnim, pack.climb)
        s(animate.swim and animate.swim.Swim, pack.swim)
        s(animate.swimidle and animate.swimidle.SwimIdle, pack.swimidle)
    end)
end

local function startAnimPack(packName)
    local char = LP.Character
    if char then
        saveOriginalAnims(char)
        applyAnimPack(packName)
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            for _, track in ipairs(hum:GetPlayingAnimationTracks()) do track:Stop(0) end
            hum:ChangeState(Enum.HumanoidStateType.Running)
        end
    else
        applyAnimPack(packName)
    end
    currentAnimPack = packName
end

local function stopAnimPack()
    currentAnimPack = "Off"
    if animSelectorLabel then animSelectorLabel.Text = "Off  ▼" end
    applyAnimPack("Off")
end

DEFAULT_KB = {
    DropBrainrot = {kb = Enum.KeyCode.X, gp = nil},
    AutoLeft     = {kb = Enum.KeyCode.Z, gp = nil},
    AutoRight    = {kb = Enum.KeyCode.C, gp = nil},
    AutoBat      = {kb = Enum.KeyCode.E, gp = nil},
    TPFloor      = {kb = Enum.KeyCode.F, gp = nil},
    GuiHide      = {kb = Enum.KeyCode.LeftControl, gp = nil},
    CarryToggle  = {kb = Enum.KeyCode.Q, gp = nil},
    LaggerMode   = {kb = Enum.KeyCode.R, gp = nil},
    TPBat        = {kb = Enum.KeyCode.V, gp = nil},
    BatV2        = {kb = Enum.KeyCode.N, gp = nil},
    AntiBat      = {kb = Enum.KeyCode.B, gp = nil},
    InstaReset   = {kb = Enum.KeyCode.H, gp = nil},
}

KB = {
    DropBrainrot = {kb = DEFAULT_KB.DropBrainrot.kb, gp = DEFAULT_KB.DropBrainrot.gp},
    AutoLeft     = {kb = DEFAULT_KB.AutoLeft.kb, gp = DEFAULT_KB.AutoLeft.gp},
    AutoRight    = {kb = DEFAULT_KB.AutoRight.kb, gp = DEFAULT_KB.AutoRight.gp},
    AutoBat      = {kb = DEFAULT_KB.AutoBat.kb, gp = DEFAULT_KB.AutoBat.gp},
    TPFloor      = {kb = DEFAULT_KB.TPFloor.kb, gp = DEFAULT_KB.TPFloor.gp},
    GuiHide      = {kb = DEFAULT_KB.GuiHide.kb, gp = DEFAULT_KB.GuiHide.gp},
    CarryToggle  = {kb = DEFAULT_KB.CarryToggle.kb, gp = DEFAULT_KB.CarryToggle.gp},
    LaggerMode   = {kb = DEFAULT_KB.LaggerMode.kb, gp = DEFAULT_KB.LaggerMode.gp},
    TPBat        = {kb = DEFAULT_KB.TPBat.kb, gp = DEFAULT_KB.TPBat.gp},
    BatV2        = {kb = DEFAULT_KB.BatV2.kb, gp = DEFAULT_KB.BatV2.gp},
    AntiBat      = {kb = DEFAULT_KB.AntiBat.kb, gp = DEFAULT_KB.AntiBat.gp},
    InstaReset   = {kb = DEFAULT_KB.InstaReset.kb, gp = DEFAULT_KB.InstaReset.gp},
}

_isResetting = false
_lastSavedJSON = nil
_isLoading = false

CONFIG = {
    AUTO_STEAL_ENABLED = false,
    STEAL_RANGE = 61,
}

local plots = workspace:WaitForChild("Plots")
local stealConnection = nil

local Steal = {
    AutoStealEnabled = false,
    StealRadius = CONFIG.STEAL_RANGE,
    StealDuration = 1.3,
    StealDelay = 0.25,
    Data = {}
}

local isStealing = false
local autoGrabSetDelayRadius = 9
local autoGrabStopTime = 0.96
local autoGrabStopEnabled = true

autoStealVariant = 1
AUTO_STEAL_VARIANT_NAMES = { "Normal", "Semi" }
autoStealVariantLabel = nil

local function autoStealVariantName(n)
    n = _clamp(tonumber(n) or 1, 1, #AUTO_STEAL_VARIANT_NAMES)
    return AUTO_STEAL_VARIANT_NAMES[n]
end

local function autoStealVariantFromName(name)
    for i, v in ipairs(AUTO_STEAL_VARIANT_NAMES) do
        if v == tostring(name) then return i end
    end
    return 1
end

local function getAutoGrabStopTime()
    local dur = (Steal and Steal.StealDuration) or 1.3
    if autoStealVariant == 2 then return dur * 0.80 end -- Semi
    return dur * 0.75 -- Normal
end

local _plotsCache = nil
local _plotsCacheTime = 0
local function getPlotsRoot()
    local now = _tick()
    if _plotsCache and now - _plotsCacheTime < 2 and _plotsCache.Parent then
        return _plotsCache
    end
    _plotsCache = workspace:FindFirstChild("Plots")
    _plotsCacheTime = now
    return _plotsCache
end

local function isMyPlotByName(plotName)
    local plotsRoot = getPlotsRoot()
    if not plotsRoot then return false end
    local plot = plotsRoot:FindFirstChild(plotName)
    if not plot then return false end
    local sign = plot:FindFirstChild("PlotSign")
    if sign then
        local yb = sign:FindFirstChild("YourBase")
        if yb and yb:IsA("BillboardGui") then
            return yb.Enabled == true
        end
    end
    return false
end

local function findNearestPrompt()
    local char = LP.Character
    if not char then return nil, nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return nil, nil end
    local plotsRoot = getPlotsRoot()
    if not plotsRoot then return nil, nil end
    local nearestPrompt, nearestDist, nearestName = nil, _huge, nil
    local rpos = root.Position
    for _, plot in ipairs(plotsRoot:GetChildren()) do
        if isMyPlotByName(plot.Name) then continue end
        local pods = plot:FindFirstChild("AnimalPodiums")
        if not pods then continue end
        for _, pod in ipairs(pods:GetChildren()) do
            pcall(function()
                local base = pod:FindFirstChild("Base")
                local spawn = base and base:FindFirstChild("Spawn")
                if spawn then
                    local sp = spawn.Position
                    local dx = sp.X - rpos.X
                    local dy = sp.Y - rpos.Y
                    local dz = sp.Z - rpos.Z
                    local dist = _sqrt(dx*dx + dy*dy + dz*dz)
                    if dist < nearestDist and dist <= Steal.StealRadius then
                        local att = spawn:FindFirstChild("PromptAttachment")
                        if att then
                            for _, child in ipairs(att:GetChildren()) do
                                if child:IsA("ProximityPrompt") and child.ActionText and child.ActionText:find("Steal") then
                                    nearestPrompt = child
                                    nearestDist = dist
                                    nearestName = pod.Name
                                    break
                                end
                            end
                        end
                    end
                end
            end)
        end
    end
    return nearestPrompt, nearestName
end

local function executeSteal(prompt, podName)
    if isStealing then return end

    if math.random(30) == 1 then
        for p in pairs(Steal.Data) do
            if not p.Parent then Steal.Data[p] = nil end
        end
    end

    if not Steal.Data[prompt] then
        Steal.Data[prompt] = { hold = {}, trigger = {}, ready = true }
        pcall(function()
            if getconnections then
                for _, c in ipairs(getconnections(prompt.PromptButtonHoldBegan)) do
                    if c.Function then table.insert(Steal.Data[prompt].hold, c.Function) end
                end
                for _, c in ipairs(getconnections(prompt.Triggered)) do
                    if c.Function then table.insert(Steal.Data[prompt].trigger, c.Function) end
                end
            end
        end)
    end

    local data = Steal.Data[prompt]
    if not data.ready then return end
    data.ready = false
    isStealing = true

    if progressFill then progressFill.Size = UDim2.new(0, 0, 1, 0) end
    if progressPct then progressPct.Text = "0%" end

    task.spawn(function()
        for _, f in ipairs(data.hold) do task.spawn(f) end

        local startTime = _tick()
        local duration = Steal.StealDuration
        local stopTime = getAutoGrabStopTime()
        local promptFired = false

        if autoGrabStopEnabled then
            while isStealing and Steal.AutoStealEnabled do
                local elapsed = _tick() - startTime
                if elapsed >= stopTime then break end
                local progress = _clamp(elapsed / duration, 0, 1)
                if progressFill then progressFill.Size = UDim2.new(progress, 0, 1, 0) end
                if progressPct then progressPct.Text = _floor(progress * 100) .. "%" end
                if not prompt.Parent or not prompt.Parent.Parent then break end
                local char = LP.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if hrp and (hrp.Position - prompt.Parent.Parent.Position).Magnitude > Steal.StealRadius then
                    break
                end
                task.wait()
            end

            local stopProgress = _clamp(stopTime / duration, 0, 1)
            if progressFill then progressFill.Size = UDim2.new(stopProgress, 0, 1, 0) end
            if progressPct then progressPct.Text = _floor(stopProgress * 100) .. "%" end

            local phase2Timeout = math.max(2.99 - stopTime - math.max(duration - stopTime, 0), 0.05)
            local phase2Start = _tick()

            while isStealing and Steal.AutoStealEnabled do
                if _tick() - phase2Start >= phase2Timeout then
                    if progressFill then progressFill.Size = UDim2.new(0, 0, 1, 0) end
                    if progressPct then progressPct.Text = "0%" end
                    data.ready = true
                    isStealing = false
                    task.wait()
                    local newPrompt, newName = findNearestPrompt()
                    if newPrompt then executeSteal(newPrompt, newName) end
                    return
                end
                if not prompt.Parent or not prompt.Parent.Parent then
                    isStealing = false
                    if progressFill then progressFill.Size = UDim2.new(0, 0, 1, 0) end
                    if progressPct then progressPct.Text = "0%" end
                    data.ready = true
                    return
                end
                local char = LP.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local dist = (hrp.Position - prompt.Parent.Parent.Position).Magnitude
                    if dist <= autoGrabSetDelayRadius then
                        break
                    elseif dist > Steal.StealRadius then
                        isStealing = false
                        if progressFill then progressFill.Size = UDim2.new(0, 0, 1, 0) end
                        if progressPct then progressPct.Text = "0%" end
                        data.ready = true
                        return
                    end
                end
                task.wait()
            end

            if isStealing and Steal.AutoStealEnabled then
                local fillStart = _tick()
                local fillDuration = math.max(duration - stopTime, 0.05)
                while true do
                    local fp = _clamp((_tick() - fillStart) / fillDuration, 0, 1)
                    local totalProgress = stopProgress + fp * (1 - stopProgress)
                    if progressFill then progressFill.Size = UDim2.new(totalProgress, 0, 1, 0) end
                    if progressPct then progressPct.Text = _floor(totalProgress * 100) .. "%" end
                    if fp >= 1 and not promptFired then
                        promptFired = true
                        pcall(function()
                            for _, f in ipairs(data.trigger) do task.spawn(f) end
                            local remote = ReplicatedStorage:FindFirstChild("StealAnimal")
                            if remote and podName then remote:FireServer(podName) end
                            if prompt then prompt:Fire() end
                        end)
                        break
                    end
                    task.wait()
                end
            end
        else
            while isStealing and Steal.AutoStealEnabled do
                local elapsed = _tick() - startTime
                local progress = _clamp(elapsed / duration, 0, 1)
                if progressFill then progressFill.Size = UDim2.new(progress, 0, 1, 0) end
                if progressPct then progressPct.Text = _floor(progress * 100) .. "%" end
                if not prompt.Parent or not prompt.Parent.Parent then break end
                local char = LP.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if hrp and (hrp.Position - prompt.Parent.Parent.Position).Magnitude > Steal.StealRadius then break end
                if elapsed >= duration and not promptFired then
                    promptFired = true
                    pcall(function()
                        for _, f in ipairs(data.trigger) do task.spawn(f) end
                        local remote = ReplicatedStorage:FindFirstChild("StealAnimal")
                        if remote and podName then remote:FireServer(podName) end
                        if prompt then prompt:Fire() end
                    end)
                    break
                end
                task.wait()
            end
        end

        if progressFill then progressFill.Size = UDim2.new(0, 0, 1, 0) end
        if progressPct then progressPct.Text = "0%" end
        data.ready = true
        isStealing = false
    end)
end

function startAutoSteal()
    if stealConnection then
        local connected = false
        pcall(function() connected = stealConnection.Connected == true end)
        if connected then
            Steal.StealRadius = CONFIG.STEAL_RANGE
            Steal.AutoStealEnabled = true
            CONFIG.AUTO_STEAL_ENABLED = true
            return true
        end
        pcall(function() stealConnection:Disconnect() end)
        stealConnection = nil
    end
    Steal.StealRadius = CONFIG.STEAL_RANGE
    Steal.AutoStealEnabled = true
    CONFIG.AUTO_STEAL_ENABLED = true
    stealConnection = RunService.Heartbeat:Connect(function()
        if not Steal.AutoStealEnabled or isStealing then return end
        local p, n = findNearestPrompt()
        if p then executeSteal(p, n) end
    end)
    return true
end

function stopAutoSteal()
    if stealConnection then
        stealConnection:Disconnect()
        stealConnection = nil
    end
    isStealing = false
    Steal.AutoStealEnabled = false
    CONFIG.AUTO_STEAL_ENABLED = false
    if progressFill then
        TS:Create(progressFill, TweenInfo.new(0.2), { Size = UDim2.new(0, 0, 1, 0) }):Play()
    end
    if progressPct then progressPct.Text = "0%" end
end

medusaDebounce = false
medusaLastUsed = 0
dropActive = false
lastDropTime = 0
lastMoveDir = _V3new(0,0,0)
origFOV = nil
fovEnabled = false
fovValue = 70
customFovConn = nil
setFovVisual = nil
fovSliderSet = nil

_anyKeyListening = false
_aimbotConn = nil
_prevAutoRotate = nil
tpBatConn = nil
tpBatPrevAutoRotate = nil
tpBatHitCD = false
TP_BAT_SWING_CD = 0.08
tpBatFloatingButton = nil
batV2FloatingButton = nil

enemySpeedConn = nil
movementLoop = nil
steppedConn = nil
alConn = nil
arConn = nil
infJumpConn = nil
stretchConn = nil
stretchFovConn = nil
antiLagDescConn = nil
medusaResetConns = {}
dropConnections = {}
enemySpeedLabels = {}
Conns = {autoSteal = nil, batCounter = nil, anchor = {}, progress = nil, autoLeft = nil, autoRight = nil}
keyButtonRefs = {}
progressFill = nil
progressPct = nil
progressRadLbl = nil
pbFrame = nil
speedLabel = nil
modeValLbl = nil
normalBox, carryBox, laggerBox, lagger2Box, radInput, batSpeedBox, uiScaleBox = nil, nil, nil, nil, nil, nil, nil
modeSelectBtn, dropModeBtnRef = nil, nil
setJumpToggleState = nil
autoBatSetVisual, autoLeftSetVisual, autoRightSetVisual, setBatCounterVisual, setMedusaVisual, autoTpDownSetVisual, setAntiBatVisual = nil, nil, nil, nil, nil, nil, nil
setAntiRagVisual, setJumpVisual, setUnwalkVisual, setAntiLagVisual, setLockUIVisual, setInstaGrab = nil, nil, nil, nil, nil, nil
setAntiDieVisual = nil
setEditModeVisual = nil
setESPVIsual = nil
mobSetAutoBat, mobSetAntiBat, mobSetAutoLeft, mobSetAutoRight, mobSetDropBR, mobSetTpDown, mobSetCarry, mobSetLagger1, mobSetLagger2, mobSetAntiAimbot = nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
autoBatV2SetVisual = nil
miniBtn, main, gui = nil, nil, nil
MobilePanel = nil
instaResetFloatingButton = nil
showGui = nil
hideGui = nil
mainUIScale = nil
animSelectorLabel = nil
pbScale = nil
tabButtons = nil
colorSelectorLabel = nil

carrySystemToggleSetter = nil
autoCarrySpeedSetVisual = nil
carrySysNormalBox = nil
carrySysCarryBox = nil
carrySysLaggerBox = nil
carrySysLaggerCarryBox = nil
carrySysSoftStealSpeedBox = nil
carrySysSoftStealRadiusBox = nil

GAMEPAD_KEYS = {
    [Enum.KeyCode.ButtonA] = true, [Enum.KeyCode.ButtonB] = true,
    [Enum.KeyCode.ButtonX] = true, [Enum.KeyCode.ButtonY] = true,
    [Enum.KeyCode.ButtonL1] = true, [Enum.KeyCode.ButtonR1] = true,
    [Enum.KeyCode.ButtonL2] = true, [Enum.KeyCode.ButtonR2] = true,
    [Enum.KeyCode.ButtonL3] = true, [Enum.KeyCode.ButtonR3] = true,
    [Enum.KeyCode.ButtonStart] = true, [Enum.KeyCode.ButtonSelect] = true,
    [Enum.KeyCode.DPadUp] = true, [Enum.KeyCode.DPadDown] = true,
    [Enum.KeyCode.DPadLeft] = true, [Enum.KeyCode.DPadRight] = true,
}

MOVE_KEYS = {
    [Enum.KeyCode.W] = true, [Enum.KeyCode.A] = true,
    [Enum.KeyCode.S] = true, [Enum.KeyCode.D] = true,
    [Enum.KeyCode.Up] = true, [Enum.KeyCode.Left] = true,
    [Enum.KeyCode.Down] = true, [Enum.KeyCode.Right] = true,
}

BAT_COUNTER_SLAP_LIST = {
    "Bat", "Slap", "Iron Slap", "Gold Slap", "Diamond Slap",
    "Emerald Slap", "Ruby Slap", "Dark Matter Slap", "Flame Slap",
    "Nuclear Slap", "Galaxy Slap", "Glitched Slap"
}

AP = {
    L1 = _V3new(-476.48, -6.28, 92.73),
    L2 = _V3new(-483.12, -4.95, 94.80),
    L_FACE = _V3new(-482.25, -4.96, 92.09),
    R1 = _V3new(-476.16, -6.52, 25.62),
    R2 = _V3new(-483.06, -5.03, 25.48),
    R_FACE = _V3new(-482.06, -6.93, 35.47),
}

function isGamepadInput(inp)
    return inp and inp.UserInputType and inp.UserInputType.Name:match("^Gamepad") ~= nil
end

function isBindableInput(inp)
    if not inp or inp.KeyCode == Enum.KeyCode.Unknown then return false end
    if inp.UserInputType == Enum.UserInputType.Keyboard then return true end
    return isGamepadInput(inp) and GAMEPAD_KEYS[inp.KeyCode] == true
end

function kbMatch(entry, kc)
    return kc and (kc == entry.kb or (entry.gp and kc == entry.gp))
end

function resetProgressBar()
    if progressPct then progressPct.Text = "0%" end
    if progressFill then progressFill.Size = UDim2.new(0, 0, 1, 0) end
end

local function doTpDown()
    pcall(function()
        local char = LP.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then return end
        root.CFrame = _CFnew(root.Position.X, -7, root.Position.Z) * CFrame.Angles(0, select(2, root.CFrame:ToEulerAnglesYXZ()), 0)
        root.Velocity = _V3zero
    end)
end

local function startAutoTpDown()
    if _autoTpDownConn then return end
    _autoTpDownConn = RunService.Heartbeat:Connect(function()
        if not autoTpDownEnabled then return end
        local char = LP.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not root or not hum or hum.Health <= 0 then return end
        -- Only when holding a Pet (carrying / stealing)
        if not CarrySystem:isCarrying() then return end
        -- TP down when above threshold (autoTpDownRadius = Y height trigger)
        if root.Position.Y > autoTpDownRadius then
            root.CFrame = _CFnew(root.Position.X, -7, root.Position.Z) * CFrame.Angles(0, select(2, root.CFrame:ToEulerAnglesYXZ()), 0)
            root.AssemblyLinearVelocity = _V3new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
        end
    end)
end

local function stopAutoTpDown()
    if _autoTpDownConn then
        _autoTpDownConn:Disconnect()
        _autoTpDownConn = nil
    end
end

local AntiRagdollV1 = {}
AntiRagdollV1.__index = AntiRagdollV1

local BOOST_SPEED = 400
local AR_DEFAULT_SPEED = 16

local stateV1 = {
    active = false,
    isBoosting = false,
    cachedChar = nil,
    ragdollConnections = {},
}

local function disconnectAllV1()
    for _, conn in ipairs(stateV1.ragdollConnections) do
        pcall(function() conn:Disconnect() end)
    end
    stateV1.ragdollConnections = {}
end

local function cacheCharacterV1()
    local char = LP.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return false end
    stateV1.cachedChar = { character = char, humanoid = hum, root = root }
    return true
end

local function isRagdolledV1()
    if not stateV1.cachedChar or not stateV1.cachedChar.humanoid then return false end
    local hum = stateV1.cachedChar.humanoid
    local st = hum:GetState()
    local ragdollStates = {
        [Enum.HumanoidStateType.Physics] = true,
        [Enum.HumanoidStateType.Ragdoll] = true,
        [Enum.HumanoidStateType.FallingDown] = true,
    }
    return ragdollStates[st] or false
end

local function forceExitRagdollV1()
    if not stateV1.cachedChar or not stateV1.cachedChar.humanoid or not stateV1.cachedChar.root then return end
    local hum = stateV1.cachedChar.humanoid
    local root = stateV1.cachedChar.root
    pcall(function()
        LP:SetAttribute("RagdollEndTime", workspace:GetServerTimeNow())
    end)
    for _, descendant in ipairs(stateV1.cachedChar.character:GetDescendants()) do
        if descendant:IsA("BallSocketConstraint") or
           (descendant:IsA("Attachment") and descendant.Name:find("RagdollAttachment")) then
            descendant:Destroy()
        end
    end
    if not stateV1.isBoosting then
        stateV1.isBoosting = true
        hum.WalkSpeed = BOOST_SPEED
    end
    if hum.Health > 0 then
        hum:ChangeState(Enum.HumanoidStateType.Running)
    end
    root.Anchored = false
end

local function heartbeatLoopV1()
    while stateV1.active do
        task.wait()
        if isRagdolledV1() then
            forceExitRagdollV1()
        elseif stateV1.isBoosting and not isRagdolledV1() then
            stateV1.isBoosting = false
            if stateV1.cachedChar and stateV1.cachedChar.humanoid then
                stateV1.cachedChar.humanoid.WalkSpeed = AR_DEFAULT_SPEED
            end
        end
    end
end

function AntiRagdollV1.start()
    if stateV1.active then return end
    AntiRagdollV1.stop()
    if not cacheCharacterV1() then
        warn("[AntiRagdollV1] Could not cache character")
        return
    end
    stateV1.active = true
    stateV1.isBoosting = false
    local camConn = RunService.RenderStepped:Connect(function()
        local cam = workspace.CurrentCamera
        if cam and stateV1.cachedChar and stateV1.cachedChar.humanoid then
            cam.CameraSubject = stateV1.cachedChar.humanoid
        end
    end)
    table.insert(stateV1.ragdollConnections, camConn)
    local respawnConn = LP.CharacterAdded:Connect(function()
        stateV1.isBoosting = false
        task.wait(0.5)
        cacheCharacterV1()
    end)
    table.insert(stateV1.ragdollConnections, respawnConn)
    task.spawn(heartbeatLoopV1)
    print("[AntiRagdollV1] Enabled")
end

function AntiRagdollV1.stop()
    stateV1.active = false
    if stateV1.isBoosting and stateV1.cachedChar and stateV1.cachedChar.humanoid then
        stateV1.cachedChar.humanoid.WalkSpeed = AR_DEFAULT_SPEED
    end
    stateV1.isBoosting = false
    disconnectAllV1()
    stateV1.cachedChar = nil
    print("[AntiRagdollV1] Disabled")
end

function AntiRagdollV1.isRunning() return stateV1.active end

local AntiRagdollV2 = {
    Enabled = false,
    Connection = nil,
    ResetCooldown = 0,
}

local function startAntiRagdollV2()
    if AntiRagdollV2.Connection then return end
    AntiRagdollV2.Enabled = true
    AntiRagdollV2.Connection = RunService.Heartbeat:Connect(function()
        if not AntiRagdollV2.Enabled then return end
        local char = LP.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        local root = char:FindFirstChild("HumanoidRootPart")
        if not hum or not root then return end
        if hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead then return end
        local state = hum:GetState()
        local now = _tick()
        if state == Enum.HumanoidStateType.Physics or
           state == Enum.HumanoidStateType.Ragdoll or
           state == Enum.HumanoidStateType.FallingDown then
            if now - AntiRagdollV2.ResetCooldown > 0.15 then
                AntiRagdollV2.ResetCooldown = now
                pcall(function()
                    if hum:GetState() == Enum.HumanoidStateType.GettingUp then return end
                    if hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead then return end
                    hum:ChangeState(Enum.HumanoidStateType.GettingUp)
                    root.Velocity = _V3zero
                    root.RotVelocity = _V3zero
                    root.AssemblyLinearVelocity = _V3zero
                    root.AssemblyAngularVelocity = _V3zero
                    for _, obj in ipairs(char:GetDescendants()) do
                        if obj:IsA("Motor6D") then obj.Enabled = true end
                        if obj:IsA("Constraint") then obj.Enabled = true end
                    end
                    workspace.CurrentCamera.CameraSubject = hum
                    local PM = LP.PlayerScripts:FindFirstChild("PlayerModule")
                    if PM then
                        local CM = require(PM:FindFirstChild("ControlModule"))
                        if CM then CM:Enable() end
                    end
                    hum.AutoRotate = true
                    hum.PlatformStand = false
                    hum.Sit = false
                end)
            end
        end
    end)
end

local function stopAntiRagdollV2()
    AntiRagdollV2.Enabled = false
    if AntiRagdollV2.Connection then
        AntiRagdollV2.Connection:Disconnect()
        AntiRagdollV2.Connection = nil
    end
    AntiRagdollV2.ResetCooldown = 0
end


-- ============================================================
-- SPIN ONLY BRAINROT — sadece pet/brainrot eldeyken (Ping Lagger AUTO ACTIVATE mantığı)
-- ============================================================
local function isHoldingBrainrotForSpin()
    local char = LP.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and hum.WalkSpeed > 0 and hum.WalkSpeed < 25 then
        return true
    end
    if CarrySystem and type(CarrySystem.isCarrying) == "function" then
        local ok, carrying = pcall(function() return CarrySystem:isCarrying() end)
        if ok and carrying then return true end
    end
    local ok, v = pcall(function() return LP:GetAttribute("Stealing") end)
    if ok and v == true then return true end
    local ok2, v2 = pcall(function() return char:GetAttribute("Stealing") end)
    if ok2 and v2 == true then return true end
    return false
end

function startSpin()
    if spinConn then pcall(function() spinConn:Disconnect() end); spinConn = nil end
    spinEnabled = true
    spinConn = RunService.Heartbeat:Connect(function()
        if not spinEnabled then return end
        if not isHoldingBrainrotForSpin() then return end
        local char = LP.Character
        if not char then return end
        local part = char:FindFirstChild("HumanoidRootPart")
            or char:FindFirstChild("UpperTorso")
            or char:FindFirstChild("Torso")
        if part then
            part.CFrame = part.CFrame * CFrame.Angles(0, spinSpeed or 0.35, 0)
        end
    end)
end

function stopSpin()
    spinEnabled = false
    if spinConn then pcall(function() spinConn:Disconnect() end); spinConn = nil end
end

function setSpinEnabled(on)
    if on then
        if not antiDieEnabled then
            antiDieEnabled = true
            pcall(function() AntiDieModule.start() end)
            if setAntiDieVisual then pcall(setAntiDieVisual, true) end
        end
        spinEnabled = true
        if setSpinVisual then pcall(setSpinVisual, true) end
        startSpin()
    else
        stopSpin()
        if setSpinVisual then pcall(setSpinVisual, false) end
    end
    pcall(saveAllSettings)
end

function setAntiRagdollMode(mode)
    if AntiRagdollV1.isRunning() then AntiRagdollV1.stop() end
    if AntiRagdollV2.Enabled then stopAntiRagdollV2() end
    antiRagdollMode = mode
    if mode == "v1" then AntiRagdollV1.start()
    elseif mode == "v2" then startAntiRagdollV2() end
    if _G.updateAntiRagdollUI then _G.updateAntiRagdollUI(mode) end
    saveAllSettings()
end

local AntiDieModule = {
    enabled = false,
    healthConn = nil,
    diedConn = nil,
    charConn = nil,
    humanoid = nil,
    _reviving = false,
}

local function disconnectHumanoid()
    if AntiDieModule.healthConn then AntiDieModule.healthConn:Disconnect(); AntiDieModule.healthConn = nil end
    if AntiDieModule.diedConn then AntiDieModule.diedConn:Disconnect(); AntiDieModule.diedConn = nil end
    AntiDieModule.humanoid = nil
end

local function activateOnCharacter(char)
    if not AntiDieModule.enabled then return end
    char = char or LP.Character or LP.CharacterAdded:Wait()
    local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 3)
    if not hum or not AntiDieModule.enabled then return end
    disconnectHumanoid()
    AntiDieModule.humanoid = hum

    pcall(function()
        hum.BreakJointsOnDeath = false
        hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.Dying, false)
    end)

    AntiDieModule.healthConn = hum:GetPropertyChangedSignal("Health"):Connect(function()
        if not AntiDieModule.enabled or not hum.Parent then return end
        if hum.Health <= 0 and not AntiDieModule._reviving then
            AntiDieModule._reviving = true
            pcall(function()
                hum.Health = hum.MaxHealth
                hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
                if hum.Health > 0 then
                    hum:ChangeState(Enum.HumanoidStateType.Running)
                end
            end)
            task.delay(0.2, function() AntiDieModule._reviving = false end)
        end
    end)

    AntiDieModule.diedConn = hum.Died:Connect(function()
        if not AntiDieModule.enabled or not char.Parent then return end
        if AntiDieModule._reviving then return end
        AntiDieModule._reviving = true
        task.defer(function()
            if not AntiDieModule.enabled or not char.Parent or not hum.Parent then
                AntiDieModule._reviving = false
                return
            end
            pcall(function()
                hum.Health = hum.MaxHealth
                hum:ChangeState(Enum.HumanoidStateType.Running)
            end)
            AntiDieModule._reviving = false
        end)
    end)
end

function AntiDieModule.start()
    AntiDieModule.enabled = true
    if AntiDieModule.charConn then AntiDieModule.charConn:Disconnect() end
    AntiDieModule.charConn = LP.CharacterAdded:Connect(function(char)
        if AntiDieModule.enabled then task.defer(function() activateOnCharacter(char) end) end
    end)
    task.defer(function() activateOnCharacter(LP.Character) end)
    print("[AntiDie] Enabled (internal)")
end

function AntiDieModule.stop()
    AntiDieModule.enabled = false
    if AntiDieModule.charConn then AntiDieModule.charConn:Disconnect(); AntiDieModule.charConn = nil end
    local hum = AntiDieModule.humanoid
    disconnectHumanoid()
    if hum and hum.Parent then
        pcall(function()
            hum.BreakJointsOnDeath = true
            hum:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
        end)
    end
    print("[AntiDie] Disabled (internal)")
end

_G.AntiDie = AntiDieModule

local AntiFlingShieldModule = {
    enabled = false,
    loop = nil,
    velocityThreshold = 80,
}

local function stabilizeRoot(root)
    if not root or not root.Parent then return end
    if batDesyncTpEnabled then return end
    local velocity
    local ok = pcall(function() velocity = root.AssemblyLinearVelocity end)
    if not ok or typeof(velocity) ~= "Vector3" then
        local legacyOk
        legacyOk, velocity = pcall(function() return root.Velocity end)
        if not legacyOk or typeof(velocity) ~= "Vector3" then return end
    end
    if velocity.Magnitude <= AntiFlingShieldModule.velocityThreshold then return end
    local stabilized = _V3new(0, velocity.Y, 0)
    pcall(function() root.AssemblyLinearVelocity = stabilized end)
    pcall(function() root.AssemblyAngularVelocity = _V3zero end)
    pcall(function() root.Velocity = stabilized end)
    pcall(function() root.RotVelocity = _V3zero end)
end

function AntiFlingShieldModule.start()
    AntiFlingShieldModule.enabled = true
    if AntiFlingShieldModule.loop then AntiFlingShieldModule.loop:Disconnect() end
    AntiFlingShieldModule.loop = RunService.Heartbeat:Connect(function()
        if not AntiFlingShieldModule.enabled then return end
        local char = LP.Character
        stabilizeRoot(char and char:FindFirstChild("HumanoidRootPart"))
    end)
    print("[AntiFlingShield] Enabled (internal)")
end

function AntiFlingShieldModule.stop()
    AntiFlingShieldModule.enabled = false
    if AntiFlingShieldModule.loop then
        AntiFlingShieldModule.loop:Disconnect()
        AntiFlingShieldModule.loop = nil
    end
    print("[AntiFlingShield] Disabled (internal)")
end

_G.AntiFlingShield = AntiFlingShieldModule

do
    local _ragCountdownRunning = false
    local function _getRagBillboard()
        local char = LP.Character
        if not char then return nil, nil end
        local head = char:FindFirstChild("Head")
        if not head then return nil, nil end
        local pGui = LP.PlayerGui
        local existing = pGui:FindFirstChild("RagCountdownBillboard")
        if existing then existing:Destroy() end
        local bb = Instance.new("BillboardGui")
        bb.Name = "RagCountdownBillboard"
        bb.Size = UDim2.new(0, 84, 0, 42)
        bb.StudsOffset = _V3new(0, 4.5, 0)
        bb.AlwaysOnTop = true
        bb.Adornee = head
        bb.Parent = pGui
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.AnchorPoint = Vector2.new(0.5, 0.5)
        lbl.Position = UDim2.new(0.5, 0, 0.5, 0)
        lbl.BackgroundTransparency = 1
        lbl.Font = Enum.Font.GothamBlack
        lbl.TextScaled = true
        lbl.TextColor3 = selectedColor
        lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        lbl.TextStrokeTransparency = 0
        lbl.Text = ""
        lbl.Parent = bb
        local grad = Instance.new("UIGradient", lbl)
        grad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, selectedColor),
            ColorSequenceKeypoint.new(0.3, Color3.new(1, 1, 1)),
            ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
            ColorSequenceKeypoint.new(0.7, Color3.new(1, 1, 1)),
            ColorSequenceKeypoint.new(1, selectedColor),
        })
        grad.Rotation = 45
        grad.Offset = Vector2.new(0,0)
        return bb, lbl
    end

    local function _ragPunch(lbl, text)
        if not (lbl and lbl.Parent) then return end
        lbl.Text = text
    end

    local function _startRagCountdown()
        if _ragCountdownRunning then return end
        _ragCountdownRunning = true
        task.spawn(function()
            local bb, lbl = _getRagBillboard()
            if not bb then _ragCountdownRunning = false; return end
            local timeLeft = 2.5
            local step = 0.1
            while timeLeft > 0 and bb.Parent do
                _ragPunch(lbl, string.format("%.1f", timeLeft))
                task.wait(step)
                timeLeft = timeLeft - step
            end
            if bb and bb.Parent then
                _ragPunch(lbl, "READY!")
                task.wait(0.5)
                if bb and bb.Parent then bb:Destroy() end
            end
            _ragCountdownRunning = false
        end)
    end

    local _wasRagdolled = false
    RunService.Heartbeat:Connect(function()
        local char = LP.Character
        if not char then _wasRagdolled = false; return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then _wasRagdolled = false; return end
        local st = hum:GetState()
        local inRag = st == Enum.HumanoidStateType.Physics
                   or st == Enum.HumanoidStateType.Ragdoll
                   or st == Enum.HumanoidStateType.FallingDown
        if inRag and not _wasRagdolled then
            _wasRagdolled = true
            _startRagCountdown()
        elseif not inRag then
            _wasRagdolled = false
        end
    end)
end

local espHighlightCache = {}
local espBillboardCache = {}
local espTracerCache = {}
local espConn = nil
local _espLastRun = 0
profileImageCache = {}

local function clearESP()
    for plr in pairs(espHighlightCache) do
        pcall(function() espHighlightCache[plr]:Destroy() end)
    end
    for plr in pairs(espBillboardCache) do
        pcall(function() espBillboardCache[plr]:Destroy() end)
    end
    for plr in pairs(espTracerCache) do
        for _, ln in ipairs(espTracerCache[plr]) do
            pcall(function() ln.Visible = false; ln:Remove() end)
        end
    end
    espHighlightCache = {}
    espBillboardCache = {}
    espTracerCache = {}
end

local function makeESPTracers()
    if not (Drawing and type(Drawing.new) == "function") then return nil end
    local color = getESPColor()
    local outer = Drawing.new("Line")
    outer.Color = color
    outer.Thickness = 2.2
    outer.Transparency = 0.90
    outer.Visible = false
    local mid = Drawing.new("Line")
    mid.Color = color
    mid.Thickness = 1.2
    mid.Transparency = 0.74
    mid.Visible = false
    local core = Drawing.new("Line")
    core.Color = color
    core.Thickness = 0.6
    core.Transparency = 0.10
    core.Visible = false
    return {outer, mid, core}
end

local function updateESP()
    local now = _tick()
    if now - _espLastRun < 0.05 then return end
    _espLastRun = now
    if not espEnabled then clearESP(); return end
    local myChar = LP.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end
    local myPos = myRoot.Position
    local myScreenPos, myOnScreen = camera:WorldToViewportPoint(myPos)
    local myVec = Vector2.new(myScreenPos.X, myScreenPos.Y)
    local currentPlayers = _GetPlayersCached()
    local plrSet = {}
    for _, p in ipairs(currentPlayers) do plrSet[p] = true end
    for plr in pairs(espHighlightCache) do
        if not plrSet[plr] then
            pcall(function() espHighlightCache[plr]:Destroy() end)
            espHighlightCache[plr] = nil
        end
    end
    for plr in pairs(espBillboardCache) do
        if not plrSet[plr] then
            pcall(function() espBillboardCache[plr]:Destroy() end)
            espBillboardCache[plr] = nil
        end
    end
    for plr in pairs(espTracerCache) do
        if not plrSet[plr] then
            for _, ln in ipairs(espTracerCache[plr]) do
                pcall(function() ln.Visible = false; ln:Remove() end)
            end
            espTracerCache[plr] = nil
        end
    end
    local color = getESPColor()
    for _, plr in ipairs(currentPlayers) do
        if plr == LP then continue end
        local char = plr.Character
        if not char then
            if espHighlightCache[plr] then
                pcall(function() espHighlightCache[plr]:Destroy() end)
                espHighlightCache[plr] = nil
            end
            if espBillboardCache[plr] then
                pcall(function() espBillboardCache[plr]:Destroy() end)
                espBillboardCache[plr] = nil
            end
            if espTracerCache[plr] then
                for _, ln in ipairs(espTracerCache[plr]) do
                    pcall(function() ln.Visible = false end)
                end
            end
            continue
        end
        local tRoot = char:FindFirstChild("HumanoidRootPart")
        local tHead = char:FindFirstChild("Head")
        local tHum = char:FindFirstChildOfClass("Humanoid")
        local alive = tRoot and tHead and tHum and tHum.Health > 0
        if alive then
            local hl = espHighlightCache[plr]
            if not hl or not hl.Parent or hl.Parent ~= char then
                if hl then pcall(function() hl:Destroy() end) end
                hl = Instance.new("Highlight")
                hl.Name = "Sakura.vsESP"
                hl.FillColor = color
                hl.FillTransparency = 0.78
                hl.OutlineColor = color
                hl.OutlineTransparency = 0.15
                hl.Adornee = char
                hl.Parent = char
                espHighlightCache[plr] = hl
            else
                -- keep transparent blue (or selected ESP color) live
                hl.FillColor = color
                hl.OutlineColor = color
                hl.FillTransparency = 0.78
                hl.OutlineTransparency = 0.15
            end
            local bb = espBillboardCache[plr]
            if not bb or not bb.Parent then
                if bb then pcall(function() bb:Destroy() end) end
                bb = Instance.new("BillboardGui")
                bb.Name = "ProfilePic"
                bb.Size = UDim2.new(0, 56, 0, 56)
                bb.StudsOffset = _V3new(0, 3.8, 0)
                bb.Adornee = tHead
                bb.AlwaysOnTop = true
                bb.Parent = tHead
                local img = Instance.new("ImageLabel", bb)
                img.Size = UDim2.new(1, -6, 1, -6)
                img.Position = UDim2.new(0, 3, 0, 3)
                img.BackgroundTransparency = 1
                img.Image = "rbxassetid://0"
                img.ScaleType = Enum.ScaleType.Fit
                local circle = Instance.new("UICorner", img)
                circle.CornerRadius = UDim.new(1, 0)
                local stroke = Instance.new("UIStroke", img)
                stroke.Color = color
                stroke.Thickness = 1.5
                espBillboardCache[plr] = bb
                task.spawn(function()
                    local userId = plr.UserId
                    local url = profileImageCache[userId]
                    if not url then
                        local success, u = pcall(function()
                            return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
                        end)
                        if success and u and u ~= "" then
                            url = u
                            profileImageCache[userId] = url
                        else
                            url = "rbxassetid://0"
                        end
                    end
                    if img then img.Image = url end
                end)
            else
                if bb.Adornee ~= tHead then bb.Adornee = tHead end
                bb.Enabled = true
                local img = bb:FindFirstChildOfClass("ImageLabel")
                if img then
                    local stroke = img:FindFirstChildOfClass("UIStroke")
                    if stroke then stroke.Color = color end
                end
            end
            local lines = espTracerCache[plr]
            if not lines then
                lines = makeESPTracers()
                espTracerCache[plr] = lines or {}
            end
            if lines and #lines > 0 then
                local destPos = tRoot.Position
                local pos, onScreen = camera:WorldToViewportPoint(destPos)
                if onScreen and pos.Z > 0 and myOnScreen then
                    local tVec = Vector2.new(pos.X, pos.Y)
                    for _, ln in ipairs(lines) do
                        ln.From = myVec
                        ln.To = tVec
                        ln.Color = color
                        ln.Visible = true
                    end
                else
                    for _, ln in ipairs(lines) do ln.Visible = false end
                end
            end
        else
            if espHighlightCache[plr] then
                pcall(function() espHighlightCache[plr]:Destroy() end)
                espHighlightCache[plr] = nil
            end
            if espBillboardCache[plr] then
                pcall(function() espBillboardCache[plr]:Destroy() end)
                espBillboardCache[plr] = nil
            end
            if espTracerCache[plr] then
                for _, ln in ipairs(espTracerCache[plr]) do
                    pcall(function() ln.Visible = false end)
                end
            end
        end
    end
end

local function startESPLoop()
    if espConn then espConn:Disconnect() end
    espConn = RunService.RenderStepped:Connect(updateESP)
end

local function stopESPLoop()
    if espConn then espConn:Disconnect(); espConn = nil end
    clearESP()
end

function toggleESP(on)
    espEnabled = on
    if on then startESPLoop() else stopESPLoop() end
    if setESPVIsual then setESPVIsual(on) end
end

local _enemySpeedAcc = 0
function updateEnemySpeedLabels()
    _enemySpeedAcc = _enemySpeedAcc + 1
    if _enemySpeedAcc < 6 then return end
    _enemySpeedAcc = 0

    local color = getThemeColor()
    local players = _GetPlayersCached()
    for i = 1, #players do
        local player = players[i]
        if player ~= LP then
            local char = player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health > 0 then
                local v = hrp.AssemblyLinearVelocity
                local speed = _sqrt(v.X*v.X + v.Z*v.Z)
                local label = enemySpeedLabels[player]
                if not label then
                    local head = char:FindFirstChild("Head")
                    if head then
                        local bb = Instance.new("BillboardGui")
                        bb.Size = UDim2.new(0, 100, 0, 25)
                        bb.StudsOffset = _V3new(0, 5.5, 0)
                        bb.AlwaysOnTop = true
                        bb.Name = "EnemySpeedGui"
                        bb.Parent = head
                        local tl = Instance.new("TextLabel", bb)
                        tl.Size = UDim2.new(1, 0, 1, 0)
                        tl.BackgroundTransparency = 1
                        tl.TextColor3 = color
                        tl.Font = Enum.Font.GothamBold
                        tl.TextScaled = true
                        tl.TextStrokeTransparency = 0
                        tl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
                        enemySpeedLabels[player] = tl
                        label = tl
                    end
                elseif label.Parent and label.Parent.Parent ~= char then
                    local head = char:FindFirstChild("Head")
                    if head then label.Parent.Parent = head end
                end
                if label then
                    label.Text = string.format("%.1f", speed)
                    if label.TextColor3 ~= color then label.TextColor3 = color end
                end
            else
                local label = enemySpeedLabels[player]
                if label and label.Parent and label.Parent.Parent then label.Parent.Parent = nil end
                enemySpeedLabels[player] = nil
            end
        end
    end
end

function startEnemySpeed()
    if enemySpeedConn then enemySpeedConn:Disconnect() end
    enemySpeedConn = RunService.Heartbeat:Connect(updateEnemySpeedLabels)
end

function stopEnemySpeed()
    if enemySpeedConn then enemySpeedConn:Disconnect(); enemySpeedConn = nil end
end

local function getClosestTargetBody()
    local char = LP.Character
    if not char then return nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local rpos = root.Position
    local closest, minDist = nil, _huge
    local plist = _GetPlayersCached()
    for i = 1, #plist do
        local plr = plist[i]
        if plr ~= LP then
            local c = plr.Character
            if c then
                local tRoot = c:FindFirstChild("HumanoidRootPart")
                if tRoot then
                    local hum = c:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health > 0 then
                        local dx = tRoot.Position.X - rpos.X
                        local dy = tRoot.Position.Y - rpos.Y
                        local dz = tRoot.Position.Z - rpos.Z
                        local d = dx*dx + dy*dy + dz*dz
                        if d < minDist then minDist = d; closest = tRoot end
                    end
                end
            end
        end
    end
    return closest
end

local function _bodyLockTick()
    local char = LP.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    local target = getClosestTargetBody()
    if not target then
        if not hum.AutoRotate then hum.AutoRotate = true end
        return
    end
    local dist = (target.Position - root.Position).Magnitude
    if dist > bodyLockRange then
        if not hum.AutoRotate then hum.AutoRotate = true end
        return
    end
    if hum.AutoRotate then hum.AutoRotate = false end
    local targetVel = target.AssemblyLinearVelocity
    local speed3 = targetVel.Magnitude
    local predictTime = _clamp(speed3 / 80, 0.08, 0.35)
    local predictedPos = target.Position + targetVel * predictTime
    local targetHead = target.Parent and target.Parent:FindFirstChild("Head")
    local targetHeight = targetHead and targetHead.Position.Y or target.Position.Y
    local myHeight = root.Position.Y + (hum.HipHeight or 0)
    local heightDiff = targetHeight - myHeight
    local verticalCorrection = _clamp(heightDiff * 0.15, -1.5, 1.5)
    local flatTarget = _V3new(predictedPos.X, root.Position.Y + verticalCorrection, predictedPos.Z)
    local toPredict = flatTarget - root.Position
    if toPredict.Magnitude > 0.1 then
        local goalCF = _CFlookAt(root.Position, flatTarget)
        local diffCF = root.CFrame:Inverse() * goalCF
        local _, ry, _ = diffCF:ToEulerAnglesXYZ()
        ry = _clamp(ry, -2.5, 2.5)
        root.AssemblyAngularVelocity = root.CFrame:VectorToWorldSpace(_V3new(0, ry * 42, 0))
    end
end

function startBodyLock()
    if _bodyLockConn then _bodyLockConn:Disconnect() end
    local acc = 0
    _bodyLockConn = RunService.Heartbeat:Connect(function(dt)
        if not bodyLockEnabled then return end
        if _blSuppressCount > 0 then return end
        acc = acc + dt
        if acc < 0.033 then return end
        acc = 0
        _bodyLockTick()
    end)
end

function stopBodyLock()
    if _bodyLockConn then
        _bodyLockConn:Disconnect()
        _bodyLockConn = nil
    end
    local c = LP.Character
    local root = c and c:FindFirstChild("HumanoidRootPart")
    if root then
        root.AssemblyAngularVelocity = _V3zero
        root.AssemblyLinearVelocity = _V3new(root.AssemblyLinearVelocity.X, -0.1, root.AssemblyLinearVelocity.Z)
    end
    local hum2 = c and c:FindFirstChildOfClass("Humanoid")
    if hum2 then hum2.AutoRotate = true end
end

function _suppressBodyLock()
    _blSuppressCount = _blSuppressCount + 1
    if _blSuppressCount == 1 and bodyLockEnabled then
        _blWasEnabled = true
        stopBodyLock()
        if bodyLockSetVisual then bodyLockSetVisual(false) end
        if _blRestoreTimer then
            task.cancel(_blRestoreTimer)
            _blRestoreTimer = nil
        end
        _blSmoothRestore = false
    end
end

function _unsuppressBodyLock(delayed)
    if _blSuppressCount > 0 then
        _blSuppressCount = _blSuppressCount - 1
    end
    if _blSuppressCount == 0 and _blWasEnabled then
        _blWasEnabled = false
        if _blRestoreTimer then
            pcall(task.cancel, _blRestoreTimer)
            _blRestoreTimer = nil
        end
        local function restore()
            _blRestoreTimer = nil
            if bodyLockEnabled then
                _blSmoothRestore = true
                startBodyLock()
                if bodyLockSetVisual then bodyLockSetVisual(true) end
                task.delay(0.5, function() _blSmoothRestore = false end)
            end
        end
        if delayed then
            _blRestoreTimer = task.delay(1, restore)
        else
            restore()
        end
    end
end

function setupSpeedIndicator(char)
    local head = char:WaitForChild("Head", 5)
    if not head then return end

    -- Speed indicator (Hız)
    local oldBB = head:FindFirstChild("Sakura.vsSpeedIndicator")
    if oldBB then oldBB:Destroy() end
    local bb = Instance.new("BillboardGui", head)
    bb.Name = "Sakura.vsSpeedIndicator"
    bb.Size = UDim2.new(0, 120, 0, 32)
    bb.StudsOffset = _V3new(0, 3.2, 0)
    bb.AlwaysOnTop = true
    speedLabel = Instance.new("TextLabel", bb)
    speedLabel.Size = UDim2.new(1, 0, 1, 0)
    speedLabel.Position = UDim2.new(0, 0, 0, 0)
    speedLabel.BackgroundTransparency = 1
    speedLabel.Text = "Hız: 0.0"
    speedLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    speedLabel.Font = Enum.Font.GothamBold
    speedLabel.TextScaled = true
    speedLabel.TextStrokeTransparency = 0
    speedLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)

    -- Discord: sade beyaz yazı, mavi çizgi/çerçeve yok
    local discordBB = head:FindFirstChild("DiscordText")
    if discordBB then discordBB:Destroy() end
    discordBB = Instance.new("BillboardGui", head)
    discordBB.Name = "DiscordText"
    discordBB.Size = UDim2.new(0, 260, 0, 36)
    discordBB.StudsOffset = _V3new(0, 5.0, 0)
    discordBB.AlwaysOnTop = true
    discordBB.MaxDistance = 120

    local discordLabel = Instance.new("TextLabel", discordBB)
    discordLabel.Name = "DiscordLabel"
    discordLabel.Size = UDim2.new(1, 0, 1, 0)
    discordLabel.Position = UDim2.new(0, 0, 0, 0)
    discordLabel.BackgroundTransparency = 1
    discordLabel.Text = "discord.gg/sakuraduels"
    discordLabel.TextColor3 = getDiscordTextColor()
    discordLabel.Font = Enum.Font.GothamBlack
    discordLabel.TextScaled = true
    discordLabel.TextStrokeTransparency = 0.3
    discordLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    discordLabel.ZIndex = 5
end

local unwalkSavedAnimate = nil

function startUnwalk()
    local c = LP.Character
    if not c then return end
    local hum = c:FindFirstChildOfClass("Humanoid")
    if hum then
        for _, t in ipairs(hum:GetPlayingAnimationTracks()) do pcall(function() t:Stop() end) end
    end
    local anim = c:FindFirstChild("Animate")
    if anim then
        unwalkSavedAnimate = anim:Clone()
        anim:Destroy()
    end
end

function stopUnwalk()
    local c = LP.Character
    if c then
        local existing = c:FindFirstChild("Animate")
        if not existing then
            local src = game:GetService("StarterPlayer"):FindFirstChildOfClass("StarterCharacterScripts")
            local starterAnim = src and src:FindFirstChild("Animate")
            if starterAnim then
                starterAnim:Clone().Parent = c
            elseif unwalkSavedAnimate then
                unwalkSavedAnimate:Clone().Parent = c
            end
        end
    end
    unwalkSavedAnimate = nil
end

-- ============================================================
-- SAKURA.VS ANTI BAT
-- Simple X/Z velocity jitter; keeps Y. No metatable / no fling stack.
-- ============================================================
-- Aspect-style Anti Bat (spiral velocity)
local _antiBatSpeed = 10000
local _antiBatAngle = 0
local _antiBatDirection = 1

function stopAntiBat()
    antiBatEnabled = false
    if antiBatConn then
        pcall(function() antiBatConn:Disconnect() end)
        antiBatConn = nil
    end
    _antiBatSpeed = 10000
    _antiBatAngle = 0
    _antiBatDirection = 1
    if setAntiBatVisual then pcall(setAntiBatVisual, false) end
    if mobSetAntiBat then pcall(mobSetAntiBat, false) end
end

function startAntiBat()
    local char = LP.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    antiBatEnabled = true
    if antiBatConn then
        pcall(function() antiBatConn:Disconnect() end)
        antiBatConn = nil
    end

    antiBatConn = RunService.Heartbeat:Connect(function()
        if not antiBatEnabled then return end
        if _isResetting then return end
        local c = LP.Character
        if not c then return end
        root = c:FindFirstChild("HumanoidRootPart")
        if not root or not root.Parent then return end
        local hum = c:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health <= 0 then return end

        local origXZ = _V3new(root.Velocity.X, 0, root.Velocity.Z)

        _antiBatSpeed = _antiBatSpeed + (50 * _antiBatDirection)
        if _antiBatSpeed >= 20000 then
            _antiBatSpeed = 20000
            _antiBatDirection = -1
        elseif _antiBatSpeed <= 10000 then
            _antiBatSpeed = 10000
            _antiBatDirection = 1
        end

        _antiBatAngle = _antiBatAngle + (math.random() * 0.5)

        local radius = _antiBatSpeed + math.random(-5000, 5000)
        local newX = math.cos(_antiBatAngle) * radius
        local newZ = math.sin(_antiBatAngle) * radius

        root.Velocity = _V3new(newX, root.Velocity.Y, newZ)

        RunService.RenderStepped:Wait()

        if root and root.Parent then
            root.Velocity = _V3new(origXZ.X, root.Velocity.Y, origXZ.Z)
        end
    end)

    if setAntiBatVisual then pcall(setAntiBatVisual, true) end
    if mobSetAntiBat then pcall(mobSetAntiBat, true) end
end

function setAntiBat(on)
    if on then startAntiBat() else stopAntiBat() end
end

function toggleAntiBat()
    if antiBatEnabled then
        stopAntiBat()
    else
        startAntiBat()
    end
    pcall(saveAllSettings)
    return antiBatEnabled
end

-- ============================================================
-- ADAPT-STYLE KICK WARNING (DONT ENTER while carrying)
-- Replaces previous PlayerRemoving anti-kick banner.
-- Shows "DONT ENTER" while holding / stealing, then "ENTER".
-- ============================================================
_G._SakuraVsKickWarn = _G._SakuraVsKickWarn or { active = false, gen = 0 }

local _kwState = {
    gui = nil,
    banner = nil,
    fill = nil,
    label = nil,
    duration = 2.3,
    showing = false,
    wasHolding = false,
    destroyed = false,
    renderConn = nil,
    loopRunning = false,
}

local function _kwIsEnabled()
    return kickWarningEnabled == true
end

local function _kwIsHolding()
    if LP:GetAttribute("Stealing") == true then return true end
    local char = LP.Character
    if not char then return false end
    local ok, v = pcall(function() return char:GetAttribute("Stealing") end)
    if ok and v == true then return true end
    for _, child in ipairs(char:GetChildren()) do
        local n = child.Name:lower()
        if n:find("brainrot") or n:find("brain") or n:find("animal")
           or n:find("carry") or n:find("stolen") or n:find("held") or n:find("steal") then
            return true
        end
    end
    for _, name in ipairs({"Carrying","IsCarrying","Grabbed","Holding","StealHold","HasGrab"}) do
        local obj = char:FindFirstChild(name)
        if obj then
            if (obj:IsA("BoolValue") and obj.Value)
               or (obj:IsA("ObjectValue") and obj.Value)
               or (obj:IsA("StringValue") and obj.Value ~= "")
               or obj:IsA("Model") or obj:IsA("BasePart") then
                return true
            end
        end
    end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and hum.WalkSpeed > 0 and hum.WalkSpeed <= 25 and hum.WalkSpeed ~= 16 then
        return true
    end
    return false
end

local function _kwHide()
    if _kwState.renderConn then
        pcall(function() _kwState.renderConn:Disconnect() end)
        _kwState.renderConn = nil
    end
    if _kwState.banner and _kwState.banner.Parent then
        _kwState.banner.Visible = false
        local h = _kwState.banner.AbsoluteSize.Y
        if h < 1 then h = 36 end
        _kwState.banner.Position = UDim2.new(0.5, 0, 0, -h - 10)
    end
    _kwState.showing = false
    local KW = _G._SakuraVsKickWarn
    if KW then KW.active = false end
end

local function _kwEnsureGui()
    if _kwState.gui and _kwState.gui.Parent then return end
    local pGui = LP:FindFirstChild("PlayerGui") or LP:WaitForChild("PlayerGui", 5)
    if not pGui then return end
    local old = pGui:FindFirstChild("SakuraVsKickWarning")
    if old then pcall(function() old:Destroy() end) end
    local cg = game:GetService("CoreGui")
    local old2 = cg:FindFirstChild("SakuraVsKickWarning")
    if old2 then pcall(function() old2:Destroy() end) end

    local gui = Instance.new("ScreenGui")
    gui.Name = "SakuraVsKickWarning"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 999
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    pcall(function()
        if syn and syn.protect_gui then syn.protect_gui(gui) end
    end)
    local okP = pcall(function() gui.Parent = game:GetService("CoreGui") end)
    if not okP then gui.Parent = pGui end

    local banner = Instance.new("Frame")
    banner.Name = "KickTimerBanner"
    banner.AnchorPoint = Vector2.new(0.5, 0)
    banner.Size = UDim2.new(0, 220, 0, 36)
    banner.Position = UDim2.new(0.5, 0, 0, -50)
    banner.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    banner.BorderSizePixel = 0
    banner.Visible = false
    banner.ClipsDescendants = true
    banner.ZIndex = 100
    banner.Parent = gui
    Instance.new("UICorner", banner).CornerRadius = UDim.new(1, 0)

    local fill = Instance.new("Frame")
    fill.Name = "ReadyFill"
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(255, 140, 0)
    fill.BackgroundTransparency = 0
    fill.BorderSizePixel = 0
    fill.ZIndex = 101
    fill.Parent = banner
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -16, 1, 0)
    label.Position = UDim2.new(0, 8, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = "DONT ENTER"
    label.TextColor3 = Color3.fromRGB(255, 185, 85)
    label.Font = Enum.Font.GothamBlack
    label.TextSize = 15
    label.ZIndex = 103
    label.Parent = banner
    local labelStroke = Instance.new("UIStroke")
    labelStroke.Color = Color3.fromRGB(20, 10, 0)
    labelStroke.Thickness = 1.5
    labelStroke.Transparency = 0
    labelStroke.Parent = label

    _kwState.gui = gui
    _kwState.banner = banner
    _kwState.fill = fill
    _kwState.label = label
end

function _G.SakuraVsDestroyKickWarning()
    _kwState.destroyed = true
    _kwHide()
    if _kwState.gui then
        pcall(function() _kwState.gui:Destroy() end)
        _kwState.gui = nil
        _kwState.banner = nil
        _kwState.fill = nil
        _kwState.label = nil
    end
    local KW = _G._SakuraVsKickWarn
    if KW then
        KW.gen = (KW.gen or 0) + 1
        KW.active = false
    end
end

function _G.SakuraVsShowKickWarning()
    if not _kwIsEnabled() or _kwState.destroyed then return end
    if _kwState.showing then return end
    _kwEnsureGui()
    if not _kwState.banner then return end

    _kwState.showing = true
    local KW = _G._SakuraVsKickWarn
    if KW then
        KW.active = true
        KW.gen = (KW.gen or 0) + 1
    end
    local myGen = KW and KW.gen or 0

    local banner = _kwState.banner
    local fill = _kwState.fill
    local label = _kwState.label
    label.Text = "DONT ENTER"
    label.TextColor3 = Color3.fromRGB(255, 185, 85)
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(255, 140, 0)
    fill.BackgroundTransparency = 0
    banner.Visible = true
    local h = 36
    banner.Position = UDim2.new(0.5, 0, 0, -h - 12)
    TS:Create(banner, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, 0, 0, 14)
    }):Play()

    local startT = _tick()
    local done = false
    if _kwState.renderConn then
        pcall(function() _kwState.renderConn:Disconnect() end)
    end
    _kwState.renderConn = RunService.RenderStepped:Connect(function()
        if _kwState.destroyed or not _kwIsEnabled() then
            _kwHide()
            return
        end
        if done or not banner.Parent then
            if _kwState.renderConn then
                pcall(function() _kwState.renderConn:Disconnect() end)
                _kwState.renderConn = nil
            end
            return
        end
        local t = _clamp((_tick() - startT) / _kwState.duration, 0, 1)
        fill.Size = UDim2.new(t, 0, 1, 0)
        if t >= 1 then
            done = true
            if _kwState.renderConn then
                pcall(function() _kwState.renderConn:Disconnect() end)
                _kwState.renderConn = nil
            end
            label.Text = "ENTER"
            label.TextColor3 = Color3.fromRGB(0, 0, 0)
            task.delay(2.5, function()
                if _kwState.destroyed then return end
                if not _kwIsEnabled() then _kwHide(); return end
                TS:Create(banner, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                    Position = UDim2.new(0.5, 0, 0, -h - 10)
                }):Play()
                task.delay(0.45, function()
                    if not _kwState.destroyed then
                        banner.Visible = false
                        _kwState.showing = false
                        if KW and KW.gen == myGen then KW.active = false end
                    end
                end)
            end)
        end
    end)
end

-- Monitor carry state (Adapt-style): show when you start holding
if not _G._SakuraVsKickWarnLoop then
    _G._SakuraVsKickWarnLoop = true
    task.spawn(function()
        while true do
            task.wait(0.1)
            if _kwState.destroyed then break end
            if _kwIsEnabled() then
                local holding = false
                pcall(function() holding = _kwIsHolding() end)
                if holding and not _kwState.wasHolding then
                    pcall(_G.SakuraVsShowKickWarning)
                end
                _kwState.wasHolding = holding
                if not holding and _kwState.showing and not (_G._SakuraVsKickWarn and _G._SakuraVsKickWarn.active) then
                    -- leave banner alone if animating; wasHolding tracks edge
                end
            else
                if _kwState.showing then _kwHide() end
                _kwState.wasHolding = false
            end
        end
    end)
end

function refreshSpeedModeLabel()
    if modeValLbl then
        if laggerCarryToggled then modeValLbl.Text = "Lagger Carry"
        elseif laggerToggled then modeValLbl.Text = "Lagger"
        elseif speedMode then modeValLbl.Text = "Carry"
        elseif autoCarrySpeedEnabled and CarrySystem:isCarrying() then modeValLbl.Text = "Auto Carry"
        else modeValLbl.Text = "Normal" end
    end
    if setCarryModeVisual then setCarryModeVisual(speedMode) end
    if setLaggerModeVisual then setLaggerModeVisual(laggerToggled) end
    if setLaggerCarryVisual then setLaggerCarryVisual(laggerCarryToggled) end
end

function resetMovementState()
    if useCarrySystem then
        CarrySystem.speedToggled = speedMode
        if laggerCarryToggled then
            CarrySystem:setLaggerMode(2)
        elseif laggerToggled then
            CarrySystem:setLaggerMode(1)
        else
            CarrySystem:setLaggerMode(0)
        end
    end
    refreshSpeedModeLabel()
    if mobSetCarry then mobSetCarry(speedMode) end
    if setLaggerModeVisual then setLaggerModeVisual(laggerToggled) end
    if setLaggerCarryVisual then setLaggerCarryVisual(laggerCarryToggled) end
end

function toggleCarryMode()
    if laggerToggled or laggerCarryToggled then
        laggerToggled = false; laggerCarryToggled = false; speedMode = true
    else speedMode = not speedMode end
    resetMovementState()
end

function toggleLaggerMode()
    if laggerCarryToggled then laggerCarryToggled = false end
    speedMode = false; laggerToggled = not laggerToggled
    resetMovementState()
end
function toggleLaggerCarryMode()
    if laggerToggled then laggerToggled = false end
    speedMode = false; laggerCarryToggled = not laggerCarryToggled
    resetMovementState()
end

function toggleLaggerCycle()
    if speedMode then
        speedMode = false
        laggerToggled = true
        laggerCarryToggled = false
    elseif laggerToggled then
        speedMode = false
        laggerToggled = false
        laggerCarryToggled = true
    else
        speedMode = true
        laggerToggled = false
        laggerCarryToggled = false
    end
    resetMovementState()
end

function stopAutoLeft()
    if alConn then alConn:Disconnect(); alConn = nil end
    alPhase = 1
    local char = LP.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hum:Move(_V3zero, false) end
    end
    if autoLeftSetVisual then autoLeftSetVisual(false) end
    if mobSetAutoLeft then mobSetAutoLeft(false) end
    _unsuppressBodyLock(true)
end

function startAutoLeft()
    if autoRightEnabled then
        autoRightEnabled = false
        stopAutoRight()
        if autoRightSetVisual then autoRightSetVisual(false) end
        if mobSetAutoRight then mobSetAutoRight(false) end
    end
    disableAllAimbots()
    _suppressBodyLock()
    if alConn then alConn:Disconnect() end
    alPhase = 1
    alConn = RunService.Heartbeat:Connect(function()
        if not autoLeftEnabled then return end
        local char = LP.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not root or not hum then return end
        local spd = NS
        if alPhase == 1 then
            local tgt = _V3new(AP.L1.X, root.Position.Y, AP.L1.Z)
            if (tgt - root.Position).Magnitude < 1 then
                alPhase = 2
                local d = AP.L2 - root.Position
                local mv = _V3new(d.X, 0, d.Z).Unit
                hum:Move(mv, false)
                root.AssemblyLinearVelocity = _V3new(mv.X * spd, root.AssemblyLinearVelocity.Y, mv.Z * spd)
                return
            end
            local d = AP.L1 - root.Position
            local mv = _V3new(d.X, 0, d.Z).Unit
            hum:Move(mv, false)
            root.AssemblyLinearVelocity = _V3new(mv.X * spd, root.AssemblyLinearVelocity.Y, mv.Z * spd)
        elseif alPhase == 2 then
            local tgt = _V3new(AP.L2.X, root.Position.Y, AP.L2.Z)
            if (tgt - root.Position).Magnitude < 1 then
                hum:Move(_V3zero, false)
                root.AssemblyLinearVelocity = _V3zero
                autoLeftEnabled = false
                if alConn then alConn:Disconnect(); alConn = nil end
                alPhase = 1
                if autoLeftSetVisual then autoLeftSetVisual(false) end
                if mobSetAutoLeft then mobSetAutoLeft(false) end
                _unsuppressBodyLock(true)
                local facePos = _V3new(AP.L_FACE.X, root.Position.Y, AP.L_FACE.Z)
                if (facePos - root.Position).Magnitude > 0.01 then
                    root.CFrame = _CFnew(root.Position, facePos)
                end
                return
            end
            local d = AP.L2 - root.Position
            local mv = _V3new(d.X, 0, d.Z).Unit
            hum:Move(mv, false)
            root.AssemblyLinearVelocity = _V3new(mv.X * spd, root.AssemblyLinearVelocity.Y, mv.Z * spd)
        end
    end)
end

function stopAutoRight()
    if arConn then arConn:Disconnect(); arConn = nil end
    arPhase = 1
    local char = LP.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hum:Move(_V3zero, false) end
    end
    if autoRightSetVisual then autoRightSetVisual(false) end
    if mobSetAutoRight then mobSetAutoRight(false) end
    _unsuppressBodyLock(true)
end

function startAutoRight()
    if autoLeftEnabled then
        autoLeftEnabled = false
        stopAutoLeft()
        if autoLeftSetVisual then autoLeftSetVisual(false) end
        if mobSetAutoLeft then mobSetAutoLeft(false) end
    end
    disableAllAimbots()
    _suppressBodyLock()
    if arConn then arConn:Disconnect() end
    arPhase = 1
    arConn = RunService.Heartbeat:Connect(function()
        if not autoRightEnabled then return end
        local char = LP.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not root or not hum then return end
        local spd = NS
        if arPhase == 1 then
            local tgt = _V3new(AP.R1.X, root.Position.Y, AP.R1.Z)
            if (tgt - root.Position).Magnitude < 1 then
                arPhase = 2
                local d = AP.R2 - root.Position
                local mv = _V3new(d.X, 0, d.Z).Unit
                hum:Move(mv, false)
                root.AssemblyLinearVelocity = _V3new(mv.X * spd, root.AssemblyLinearVelocity.Y, mv.Z * spd)
                return
            end
            local d = AP.R1 - root.Position
            local mv = _V3new(d.X, 0, d.Z).Unit
            hum:Move(mv, false)
            root.AssemblyLinearVelocity = _V3new(mv.X * spd, root.AssemblyLinearVelocity.Y, mv.Z * spd)
        elseif arPhase == 2 then
            local tgt = _V3new(AP.R2.X, root.Position.Y, AP.R2.Z)
            if (tgt - root.Position).Magnitude < 1 then
                hum:Move(_V3zero, false)
                root.AssemblyLinearVelocity = _V3zero
                autoRightEnabled = false
                if arConn then arConn:Disconnect(); arConn = nil end
                arPhase = 1
                if autoRightSetVisual then autoRightSetVisual(false) end
                if mobSetAutoRight then mobSetAutoRight(false) end
                _unsuppressBodyLock(true)
                local facePos = _V3new(AP.R_FACE.X, root.Position.Y, AP.R_FACE.Z)
                if (facePos - root.Position).Magnitude > 0.01 then
                    root.CFrame = _CFnew(root.Position, facePos)
                end
                return
            end
            local d = AP.R2 - root.Position
            local mv = _V3new(d.X, 0, d.Z).Unit
            hum:Move(mv, false)
            root.AssemblyLinearVelocity = _V3new(mv.X * spd, root.AssemblyLinearVelocity.Y, mv.Z * spd)
        end
    end)
end

function getClosestTarget()
    local char = LP.Character
    if not char then return nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local rpos = root.Position
    local closest, minDist = nil, _huge
    local plist = _GetPlayersCached()
    for i = 1, #plist do
        local plr = plist[i]
        if plr ~= LP then
            local c = plr.Character
            if c then
                local tRoot = c:FindFirstChild("HumanoidRootPart")
                if tRoot then
                    local hum = c:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health > 0 then
                        local dx = tRoot.Position.X - rpos.X
                        local dy = tRoot.Position.Y - rpos.Y
                        local dz = tRoot.Position.Z - rpos.Z
                        local d = dx*dx + dy*dy + dz*dz
                        if d < minDist then minDist = d; closest = tRoot end
                    end
                end
            end
        end
    end
    return closest
end

function trySwing()
    pcall(function()
        local char = LP.Character
        if not char then return end
        local currentTool = char:FindFirstChildOfClass("Tool")
        if currentTool and not isBatTool(currentTool) then return end
        local bat = findBat()
        if bat then
            if bat.Parent ~= char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then pcall(function() hum:EquipTool(bat) end) end
            end
            pcall(function() bat:Activate() end)
        end
    end)
end

function stopAimbotAdapt()
    if _aimbotConn then
        pcall(function() _aimbotConn:Disconnect() end)
        _aimbotConn = nil
    end
    local char = LP.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.AutoRotate = (_prevAutoRotate == nil) and true or _prevAutoRotate
        hum.PlatformStand = false
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
    end
    if root then
        root.AssemblyLinearVelocity = _V3new(0, -0.1, 0)
        root.AssemblyAngularVelocity = _V3zero
    end
    _prevAutoRotate = nil
    lastMoveDir = _V3zero
    _unsuppressBodyLock(true)
end

function startAimbotAdapt()
    if _aimbotConn then return end
    _suppressBodyLock()
    local hum0 = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
    if hum0 then
        if _prevAutoRotate == nil then _prevAutoRotate = hum0.AutoRotate end
        hum0.AutoRotate = false
    end
    _aimbotConn = RunService.RenderStepped:Connect(function()
        if not autoBatEnabled then return end
        local char = LP.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not root or not hum then return end
        if not char:FindFirstChildOfClass("Tool") then
            local bat = findBat()
            if bat then pcall(function() hum:EquipTool(bat) end) end
        end
        local target = getClosestTarget()
        if not target then return end
        local targetVel = target.AssemblyLinearVelocity
        local myPos = root.Position
        local targetPos = target.Position
        local predictPos = targetPos + targetVel * 0.14
        predictPos = predictPos + target.CFrame.LookVector * 0.3
        local direction = predictPos - myPos
        local flatDir = _V3new(direction.X, 0, direction.Z)
        if flatDir.Magnitude > 0 then flatDir = flatDir.Unit else flatDir = _V3new(0,0,0) end
        local desiredHeight = targetPos.Y + 3.7
        local yVel = (desiredHeight - myPos.Y) * 19.5 + targetVel.Y * 0.8
        if hum.FloorMaterial ~= Enum.Material.Air then yVel = math.max(yVel, 13) end
        yVel = _clamp(yVel, -70, 110)
        local desiredVel = _V3new(flatDir.X * BAT_AIMBOT_SPEED, yVel, flatDir.Z * BAT_AIMBOT_SPEED)
        root.AssemblyLinearVelocity = root.AssemblyLinearVelocity:Lerp(desiredVel, 0.8)
        local speed3 = targetVel.Magnitude
        local predictTime = _clamp(speed3 / 150, 0.05, 0.2)
        local predictedPos = targetPos + targetVel * predictTime
        local toPredict = predictedPos - myPos
        if toPredict.Magnitude > 0.1 then
            local goalCF = _CFlookAt(myPos, predictedPos)
            local diffCF = root.CFrame:Inverse() * goalCF
            local rx, ry, rz = diffCF:ToEulerAnglesXYZ()
            rx = _clamp(rx, -2.5, 2.5)
            ry = _clamp(ry, -2.5, 2.5)
            rz = _clamp(rz, -2.5, 2.5)
            root.AssemblyAngularVelocity = root.CFrame:VectorToWorldSpace(_V3new(rx * 42, ry * 42, rz * 42))
        end
        local distToTarget = (root.Position - target.Position).Magnitude
        if distToTarget <= 8 then trySwing() end
    end)
end

-- ============================================================
-- Bat Aimbot V3 (ported from Yout v12)
-- ============================================================
local _aimbotV3Conn = nil

function stopAimbotV3()
    if _aimbotV3Conn then
        pcall(function() _aimbotV3Conn:Disconnect() end)
        _aimbotV3Conn = nil
    end
    local char = LP.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.AutoRotate = (_prevAutoRotate == nil) and true or _prevAutoRotate
        hum.PlatformStand = false
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
    end
    if root then
        root.AssemblyLinearVelocity = _V3new(0, -0.1, 0)
        root.AssemblyAngularVelocity = _V3zero
    end
    _prevAutoRotate = nil
    lastMoveDir = _V3zero
    _unsuppressBodyLock(true)
end

function startAimbotV3()
    if _aimbotV3Conn then return end
    stopAimbotAdapt()
    stopSpectrumBypassAimbot()
    _suppressBodyLock()
    local hum0 = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
    if hum0 then
        if _prevAutoRotate == nil then _prevAutoRotate = hum0.AutoRotate end
        hum0.AutoRotate = false
    end
    _aimbotV3Conn = RunService.RenderStepped:Connect(function()
        if not autoBatEnabled then return end
        local char = LP.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not root or not hum then return end
        if not char:FindFirstChildOfClass("Tool") then
            local bat = findBat()
            if bat then pcall(function() hum:EquipTool(bat) end) end
        end
        local target = getClosestTarget()
        if not target then return end
        local targetVel = target.AssemblyLinearVelocity
        local myPos = root.Position
        local targetPos = target.Position
        -- Yout v12 prediction values
        local predictPos = targetPos + targetVel * 0.14
        predictPos = predictPos + target.CFrame.LookVector * 0.3
        local direction = predictPos - myPos
        local flatDir = _V3new(direction.X, 0, direction.Z)
        if flatDir.Magnitude > 0 then flatDir = flatDir.Unit else flatDir = _V3new(0,0,0) end
        local desiredHeight = targetPos.Y + 3.7
        local yVel = (desiredHeight - myPos.Y) * 19.5 + targetVel.Y * 0.8
        if hum.FloorMaterial ~= Enum.Material.Air then yVel = math.max(yVel, 13) end
        yVel = _clamp(yVel, -70, 110)
        local desiredVel = _V3new(flatDir.X * BAT_AIMBOT_SPEED, yVel, flatDir.Z * BAT_AIMBOT_SPEED)
        root.AssemblyLinearVelocity = root.AssemblyLinearVelocity:Lerp(desiredVel, 0.8)
        local speed3 = targetVel.Magnitude
        local predictTime = _clamp(speed3 / 150, 0.05, 0.2)
        local predictedPos = targetPos + targetVel * predictTime
        local toPredict = predictedPos - myPos
        if toPredict.Magnitude > 0.1 then
            local goalCF = _CFlookAt(myPos, predictedPos)
            local diffCF = root.CFrame:Inverse() * goalCF
            local rx, ry, rz = diffCF:ToEulerAnglesXYZ()
            rx = _clamp(rx, -2.5, 2.5)
            ry = _clamp(ry, -2.5, 2.5)
            rz = _clamp(rz, -2.5, 2.5)
            root.AssemblyAngularVelocity = root.CFrame:VectorToWorldSpace(_V3new(rx * 42, ry * 42, rz * 42))
        end
        local distToTarget = (root.Position - target.Position).Magnitude
        if distToTarget <= 8 then trySwing() end
    end)
end

-- ============================================================
-- BYPASS AIMBOT — VX7 LinearVelocity "swim" style
-- Replaces Adapt AngularVelocity bypass with VX7 mover aimbot
-- Uses Attachment + LinearVelocity (swim through air) + prediction
-- ============================================================
local _adaptBypass = {
    enabled = false,
    equipped = false,
    target = nil,
    intendedVelocity = Vector3.zero,
    angularVelocity = nil, -- unused (compat)
    attachment = nil,
    linearVelocity = nil,
    conn = nil,
    safetyConn = nil,
    swingCD = false,
    attachmentName = "VX7AimbotMoveAttachment",
    moverName = "VX7AimbotMoveVelocity",
    minForce = 1000000,
    maxForce = 50000000,
}

local _adaptBatPred = {}

local function _vx7ClearAimbotMover(root)
    root = root or (LP.Character and LP.Character:FindFirstChild("HumanoidRootPart"))
    if not root then return end
    local lv = root:FindFirstChild(_adaptBypass.moverName)
    local att = root:FindFirstChild(_adaptBypass.attachmentName)
    if lv and lv:IsA("LinearVelocity") then pcall(function() lv:Destroy() end) end
    if att and att:IsA("Attachment") then pcall(function() att:Destroy() end) end
    _adaptBypass.linearVelocity = nil
    _adaptBypass.attachment = nil
end

local function _vx7EnsureMover(root, speed)
    if not root then return nil end
    local att = root:FindFirstChild(_adaptBypass.attachmentName)
    if att and not att:IsA("Attachment") then
        att:Destroy()
        att = nil
    end
    if not att then
        att = Instance.new("Attachment")
        att.Name = _adaptBypass.attachmentName
        att.Parent = root
    end
    local lv = root:FindFirstChild(_adaptBypass.moverName)
    if not lv or not lv:IsA("LinearVelocity") then
        if lv then pcall(function() lv:Destroy() end) end
        lv = Instance.new("LinearVelocity")
        lv.Name = _adaptBypass.moverName
        lv.Attachment0 = att
        lv.RelativeTo = Enum.ActuatorRelativeTo.World
        lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
        lv.ForceLimitsEnabled = true
        lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
        lv.VectorVelocity = Vector3.zero
        lv.Parent = root
    else
        lv.Attachment0 = att
    end
    local force = math.clamp((root.AssemblyMass or 10) * math.max(speed * 220, 6000), _adaptBypass.minForce, _adaptBypass.maxForce)
    lv.MaxAxesForce = Vector3.new(force, force, force)
    lv.Enabled = true
    _adaptBypass.attachment = att
    _adaptBypass.linearVelocity = lv
    return lv
end

local function _vx7ApplyMove(root, desiredVel, speed, dt)
    local lv = _vx7EnsureMover(root, speed)
    if not lv then return end
    local alpha = 1 - math.exp(-math.max(dt or 0.016666, 0) * 26)
    lv.VectorVelocity = lv.VectorVelocity:Lerp(desiredVel, alpha)
    _adaptBypass.intendedVelocity = desiredVel
    -- keep anti-drop spoof in sync when present
    if antiDropEnabled and antiDropSpoofVel ~= nil then
        antiDropSpoofVel = _V3new(
            math.clamp(desiredVel.X, -16, 16),
            root.AssemblyLinearVelocity.Y,
            math.clamp(desiredVel.Z, -16, 16)
        )
    end
end

local function _vx7FindBat()
    local char = LP.Character
    if not char then return nil end
    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("Tool") then
            local n = child.Name:lower()
            if n:find("bat") or n:find("slap") then return child end
        end
    end
    local bp = LP:FindFirstChildOfClass("Backpack")
    if bp then
        for _, child in ipairs(bp:GetChildren()) do
            if child:IsA("Tool") then
                local n = child.Name:lower()
                if n:find("bat") or n:find("slap") then return child end
            end
        end
    end
    if type(findBat) == "function" then
        local ok, b = pcall(findBat)
        if ok and b then return b end
    end
    return nil
end

local function _vx7NearestTarget(root)
    if type(getClosestTarget) == "function" then
        local ok, t = pcall(getClosestTarget)
        if ok and t then return t end
    end
    local best, bestDist = nil, math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and plr.Character then
            local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
            local hum = plr.Character:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health > 0 then
                local d = (hrp.Position - root.Position).Magnitude
                if d < bestDist then
                    bestDist = d
                    best = hrp
                end
            end
        end
    end
    return best
end

local function _vx7ResetMotion()
    local char = LP.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if root then
        _vx7ClearAimbotMover(root)
        root.Anchored = false
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        pcall(function()
            if sethiddenproperty then
                sethiddenproperty(root, "PhysicsRepRootPart", nil)
            end
        end)
        local look = root.CFrame.LookVector
        local flat = _V3new(look.X, 0, look.Z)
        flat = flat.Magnitude > 0.01 and flat.Unit or _V3new(0, 0, -1)
        root.CFrame = _CFlookAt(root.Position, root.Position + flat)
    end
    if hum then
        hum.AutoRotate = true
        hum.PlatformStand = false
        pcall(function() hum:Move(Vector3.zero, false) end)
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
    end
end

local function _vx7Swing(char)
    if _adaptBypass.swingCD then return end
    _adaptBypass.swingCD = true
    pcall(function()
        local bat = _vx7FindBat()
        if bat and bat.Parent == char then
            bat:Activate()
        elseif type(trySwing) == "function" then
            trySwing()
        end
    end)
    task.delay(0.08, function()
        _adaptBypass.swingCD = false
    end)
end

local function _adaptBypassTick(dt)
    if not _adaptBypass.enabled then return end
    if not antiAimbotEnabled then return end
    local char = LP.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then return end

    if not _adaptBypass.equipped then
        _adaptBypass.equipped = true
        if not char:FindFirstChildOfClass("Tool") then
            local bat = _vx7FindBat()
            if bat and bat.Parent ~= char then
                pcall(function() hum:EquipTool(bat) end)
            end
        end
    end

    local target = _vx7NearestTarget(root)
    if not target then
        _adaptBypass.target = nil
        hum.AutoRotate = true
        root.AssemblyAngularVelocity = Vector3.zero
        _vx7ClearAimbotMover(root)
        return
    end

    _adaptBypass.target = target
    local spd = tonumber(BYPASS_AIMBOT_SPEED) or tonumber(BAT_AIMBOT_SPEED) or 58
    spd = math.clamp(spd, 1, 500)
    hum.AutoRotate = false

    -- velocity prediction (VX7 _adaptBatPred style)
    local now = _tick()
    local pred = _adaptBatPred[target]
    local vel = Vector3.zero
    if not pred then
        _adaptBatPred[target] = { pos = target.Position, time = now, vel = Vector3.zero }
    else
        local dtPred = math.clamp(now - pred.time, 1/120, 0.25)
        local raw = (target.Position - pred.pos) / dtPred
        if raw.Magnitude > 80 then raw = raw.Unit * 80 end
        pred.vel = pred.vel:Lerp(raw, 0.25)
        pred.pos = target.Position
        pred.time = now
        vel = pred.vel
    end

    local aimPos = target.Position
        + vel * math.clamp(vel.Magnitude / 130, 0.05, 0.12)
        + _V3new(0, 1, 0)

    local delta = aimPos - root.Position
    local flat = _V3new(delta.X, 0, delta.Z)

    -- angular aim (yaw + pitch) like VX7
    if delta.Magnitude > 0.01 and flat.Magnitude > 0.01 then
        local yawDiff = (math.deg(math.atan2(-flat.X, -flat.Z)) - root.Orientation.Y + 180) % 360 - 180
        local pitchDiff = (math.deg(math.atan2(delta.Y, flat.Magnitude)) - root.Orientation.X + 180) % 360 - 180
        local yawRate = math.clamp(math.rad(yawDiff) * 285, -28, 28)
        local pitchRate = math.clamp(math.rad(pitchDiff) * 285, -28, 28)
        local facing = _V3new(math.cos(math.rad(root.Orientation.Y)), 0, -math.sin(math.rad(root.Orientation.Y)))
        root.AssemblyAngularVelocity = _V3new(0, yawRate, 0) + facing * pitchRate
    else
        root.AssemblyAngularVelocity = Vector3.zero
    end

    -- approach offset: slightly in front / above target (VX7 swim offset)
    local approach = aimPos - (delta.Magnitude > 0.01 and delta.Unit or Vector3.zero) * -2.8 + _V3new(0, 4.75, 0)
    local toApproach = approach - root.Position
    local flat2 = _V3new(toApproach.X, 0, toApproach.Z)
    local horiz = flat2.Magnitude > 0.1 and flat2.Unit * spd or Vector3.zero
    local yComp = math.abs(toApproach.Y) > 0.1 and _V3new(0, math.sign(toApproach.Y) * 52, 0) or _V3new(0, -2, 0)

    _vx7ApplyMove(root, horiz + yComp, spd, dt)

    if flat2.Magnitude > 0.5 then
        pcall(function() hum:Move(flat2.Unit, false) end)
    end

    local dist = (root.Position - target.Position).Magnitude
    if dist <= 10 then
        _vx7Swing(char)
    end
end

function stopSpectrumBypassAimbot()
    _adaptBypass.enabled = false
    _adaptBypass.equipped = false
    _adaptBypass.target = nil
    if _adaptBypass.conn then
        pcall(function() _adaptBypass.conn:Disconnect() end)
        _adaptBypass.conn = nil
    end
    if _adaptBypass.safetyConn then
        pcall(function() _adaptBypass.safetyConn:Disconnect() end)
        _adaptBypass.safetyConn = nil
    end
    _adaptBypass.swingCD = false
    _adaptBatPred = {}
    pcall(_vx7ResetMotion)
    if type(_unsuppressBodyLock) == "function" then
        pcall(function() _unsuppressBodyLock(true) end)
    end
end



-- ============================================================
-- BAT BYPASS V2 — full port from Clean Hub (SnowVS.BatBypass)
-- Used by: Anti Aimbot Mode V2 + Bat Aimbot Mode V2
-- ============================================================
BAT_V2_SPEED = BAT_V2_SPEED or 55
BAT_V2_HIT_DIST = BAT_V2_HIT_DIST or 13
BAT_V2_LEAD_STUDS = BAT_V2_LEAD_STUDS or 3
BAT_V2_BODY_LOCK_RANGE = BAT_V2_BODY_LOCK_RANGE or 60

BatBypassV2 = {
    Enabled = false,
    Connection = nil,
    _pingStarted = false,
    Z = {
        targetPlayer = nil,
        lastTargetPos = nil,
        targetVelocity = Vector3.zero,
        smoothedVelocity = Vector3.zero,
        velocityHistory = {},
        accelerationHistory = {},
        aerialVelocityHistory = {},
        previousDirection = nil,
        lastDirectionChangeTime = 0,
        airborneTime = 0,
        lastActivationTime = 0,
        currentPing = 0.1,
        realPingMs = 0,
    },
    ZCFG = {
        FOLLOW_SPEED = BAT_V2_SPEED or 55,
        ACTIVATE_DISTANCE = BAT_V2_HIT_DIST or 13,
        MIN_FOLLOW_DISTANCE = 1,
        PREDICTION_TIME = 0.22,
        PREDICT_AHEAD = BAT_V2_LEAD_STUDS or 3,
        MAX_VELOCITY_CHANGE = 150,
        VELOCITY_SMOOTHING = 0.2,
        MAX_HORIZONTAL_VELOCITY = 80,
        SERVER_TICKRATE = 1 / 60,
        MIN_PING_COMPENSATION = 0.03,
        MAX_PING_COMPENSATION = 0.25,
        ACCELERATION_PREDICTION_WEIGHT = 0.3,
        DIRECTION_CHANGE_DETECTION_TIME = 0.12,
        QUICK_DIRECTION_CHANGE_MULTIPLIER = 1.5,
        GRAVITY = 196.2,
        AIR_CONTROL_FACTOR = 0.8,
        MIN_AIRBORNE_TIME = 0.08,
    },
}

local function bbAverageVectors(vectors)
    if #vectors == 0 then
        return Vector3.zero
    end
    local sum = Vector3.zero
    for _, entry in ipairs(vectors) do
        sum = sum + entry
    end
    return sum / #vectors
end

local function bbPushBounded(history, entry, maxEntries)
    table.insert(history, entry)
    while #history > maxEntries do
        table.remove(history, 1)
    end
end

local function bbResetPredictionState()
    local z = BatBypassV2.Z
    z.targetPlayer = nil
    z.lastTargetPos = nil
    z.targetVelocity = Vector3.zero
    z.smoothedVelocity = Vector3.zero
    z.velocityHistory = {}
    z.accelerationHistory = {}
    z.aerialVelocityHistory = {}
    z.previousDirection = nil
    z.airborneTime = 0
end

local function bbApplyAngularAim(rootPart, direction)
    if direction.Magnitude < 0.01 then
        return
    end
    local crossVector = rootPart.CFrame.LookVector:Cross(direction.Unit)
    local angle = math.asin(math.clamp(crossVector.Magnitude, -1, 1))
    if crossVector.Magnitude > 0.1 then
        rootPart.AssemblyAngularVelocity = crossVector.Unit * angle * 80
    else
        rootPart.AssemblyAngularVelocity = Vector3.zero
    end
end

local function bbUpdatePing()
    local ok, result = pcall(function()
        return game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()
    end)
    if ok and type(result) == "number" then
        BatBypassV2.Z.realPingMs = result
        local sec = result / 1000
        local cfg = BatBypassV2.ZCFG
        BatBypassV2.Z.currentPing = math.clamp(sec, cfg.MIN_PING_COMPENSATION, cfg.MAX_PING_COMPENSATION)
    end
end

function BatBypassV2.FindBat()
    local character = LP.Character
    if not character then
        return nil
    end
    local tool = character:FindFirstChildOfClass("Tool")
    if tool then
        local n = string.lower(tool.Name)
        if string.find(n, "bat", 1, true) or string.find(n, "slap", 1, true) then
            return tool
        end
    end
    local backpack = LP:FindFirstChildOfClass("Backpack")
    if backpack then
        for _, child in ipairs(backpack:GetChildren()) do
            if child:IsA("Tool") then
                local n = string.lower(child.Name)
                if string.find(n, "bat", 1, true) or string.find(n, "slap", 1, true) then
                    return child
                end
            end
        end
    end
    -- fallback: any tool in character/backpack
    if tool then
        return tool
    end
    if backpack then
        for _, child in ipairs(backpack:GetChildren()) do
            if child:IsA("Tool") then
                return child
            end
        end
    end
    return nil
end

local function bbFindClosestPlayer(rootPart)
    local closestDistance = math.huge
    local closestPlayer = nil
    local list = _GetPlayersCached()
    for i = 1, #list do
        local player = list[i]
        if player ~= LP and player.Character then
            local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
            local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
            if humanoidRootPart and humanoid and humanoid.Health > 0 then
                local d = (humanoidRootPart.Position - rootPart.Position).Magnitude
                if d < closestDistance then
                    closestDistance = d
                    closestPlayer = player
                end
            end
        end
    end
    return closestPlayer
end

function BatBypassV2.Stop()
    local z = BatBypassV2.Z
    BatBypassV2.Enabled = false
    if BatBypassV2.Connection then
        pcall(function()
            BatBypassV2.Connection:Disconnect()
        end)
        BatBypassV2.Connection = nil
    end
    local character = LP.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if humanoid then
        humanoid.AutoRotate = true
    end
    if root then
        root.AssemblyAngularVelocity = Vector3.zero
    end
    bbResetPredictionState()
    z.lastActivationTime = 0
end

function BatBypassV2.Start(speedOverride)
    if BatBypassV2.Connection then
        return
    end
    local character = LP.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not rootPart then
        return
    end

    local zcfg = BatBypassV2.ZCFG
    zcfg.FOLLOW_SPEED = tonumber(speedOverride)
        or tonumber(BYPASS_AIMBOT_SPEED)
        or tonumber(BAT_AIMBOT_SPEED)
        or tonumber(BAT_V2_SPEED)
        or 55
    zcfg.ACTIVATE_DISTANCE = tonumber(BAT_V2_HIT_DIST) or 13
    zcfg.PREDICT_AHEAD = tonumber(BAT_V2_LEAD_STUDS) or 3

    BatBypassV2.Enabled = true
    humanoid.AutoRotate = false

    local tool = BatBypassV2.FindBat()
    if tool and tool.Parent ~= character then
        pcall(function()
            humanoid:EquipTool(tool)
        end)
    end

    if not BatBypassV2._pingStarted then
        BatBypassV2._pingStarted = true
        task.spawn(function()
            while _G.SakuraVsRunning do
                bbUpdatePing()
                task.wait(0.5)
            end
        end)
    end
    bbUpdatePing()

    BatBypassV2.Connection = RunService.RenderStepped:Connect(function(deltaTime)
        if not BatBypassV2.Enabled then
            BatBypassV2.Stop()
            return
        end

        local z = BatBypassV2.Z
        zcfg = BatBypassV2.ZCFG
        -- live speed from UI boxes
        local liveSpd = tonumber(BYPASS_AIMBOT_SPEED) or tonumber(BAT_AIMBOT_SPEED)
        if liveSpd and liveSpd > 0 then
            zcfg.FOLLOW_SPEED = liveSpd
        end

        local character2 = LP.Character
        local rootPart2 = character2 and character2:FindFirstChild("HumanoidRootPart")
        local humanoid2 = character2 and character2:FindFirstChildOfClass("Humanoid")
        if not rootPart2 or not humanoid2 or humanoid2.Health <= 0 then
            return
        end
        humanoid2.AutoRotate = false
        rootPart = rootPart2
        humanoid = humanoid2

        tool = character2:FindFirstChildOfClass("Tool") or BatBypassV2.FindBat()
        if tool and tool.Parent ~= character2 then
            pcall(function()
                humanoid:EquipTool(tool)
            end)
        end

        z.targetPlayer = bbFindClosestPlayer(rootPart)
        local targetChar = z.targetPlayer and z.targetPlayer.Character
        local targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
        local targetHum = targetChar and targetChar:FindFirstChildOfClass("Humanoid")
        if not targetRoot or not targetHum or targetHum.Health <= 0 then
            bbResetPredictionState()
            return
        end

        local position = targetRoot.Position
        local sampleDeltaTime = math.max(deltaTime, 1 / 240)

        if z.lastTargetPos then
            local targetVelocity = (position - z.lastTargetPos) / sampleDeltaTime
            local vector = targetVelocity - z.targetVelocity
            if vector.Magnitude > zcfg.MAX_VELOCITY_CHANGE then
                targetVelocity = z.targetVelocity + vector.Unit * zcfg.MAX_VELOCITY_CHANGE
            end
            local vector3 = Vector3.new(targetVelocity.X, 0, targetVelocity.Z)
            if vector3.Magnitude > zcfg.MAX_HORIZONTAL_VELOCITY then
                local clamped = vector3.Unit * zcfg.MAX_HORIZONTAL_VELOCITY
                targetVelocity = Vector3.new(clamped.X, targetVelocity.Y, clamped.Z)
            end
            bbPushBounded(z.accelerationHistory, (targetVelocity - z.targetVelocity) / sampleDeltaTime, 4)
            bbPushBounded(z.velocityHistory, targetVelocity, 8)
            z.targetVelocity = targetVelocity
            z.smoothedVelocity = z.smoothedVelocity:Lerp(targetVelocity, zcfg.VELOCITY_SMOOTHING)
        end
        z.lastTargetPos = position

        local isAirborne = targetHum.FloorMaterial == Enum.Material.Air
        if isAirborne then
            z.airborneTime = z.airborneTime + sampleDeltaTime
        else
            z.airborneTime = 0
        end
        if isAirborne and z.airborneTime >= zcfg.MIN_AIRBORNE_TIME then
            bbPushBounded(z.aerialVelocityHistory, z.targetVelocity, 6)
        elseif not isAirborne then
            z.aerialVelocityHistory = {}
        end

        local smoothedVelocity = z.smoothedVelocity
        if isAirborne and #z.aerialVelocityHistory > 0 then
            local vector = bbAverageVectors(z.aerialVelocityHistory)
            smoothedVelocity = Vector3.new(vector.X, z.targetVelocity.Y, vector.Z) * zcfg.AIR_CONTROL_FACTOR
        end

        local changedDirectionQuickly = false
        local horizVel = Vector3.new(z.targetVelocity.X, 0, z.targetVelocity.Z)
        if horizVel.Magnitude > 5 then
            local unit = horizVel.Unit
            if z.previousDirection and z.previousDirection:Dot(unit) < 0.5 then
                changedDirectionQuickly = (tick() - (z.lastDirectionChangeTime or 0)) < zcfg.DIRECTION_CHANGE_DETECTION_TIME
                z.lastDirectionChangeTime = tick()
            end
            z.previousDirection = unit
        end

        local predictionTime = (z.currentPing or 0.1) + zcfg.SERVER_TICKRATE
        if changedDirectionQuickly then
            predictionTime = predictionTime * zcfg.QUICK_DIRECTION_CHANGE_MULTIPLIER
        end

        local predictedPosition = position
            + smoothedVelocity * predictionTime
            + bbAverageVectors(z.accelerationHistory)
                * zcfg.ACCELERATION_PREDICTION_WEIGHT
                * predictionTime
                * predictionTime
                * 0.5

        local leadTime = zcfg.PREDICTION_TIME * 1.1
        local leadPosition
        if isAirborne then
            leadPosition = predictedPosition
                + smoothedVelocity * leadTime
                + Vector3.new(0, -0.5 * zcfg.GRAVITY * leadTime * leadTime, 0)
        else
            leadPosition = predictedPosition + smoothedVelocity * leadTime
        end

        local flatSmoothed = Vector3.new(smoothedVelocity.X, 0, smoothedVelocity.Z)
        if flatSmoothed.Magnitude > 1 then
            leadPosition = leadPosition + flatSmoothed.Unit * zcfg.PREDICT_AHEAD
        end

        local targetDirection = leadPosition - rootPart.Position
        bbApplyAngularAim(rootPart, targetDirection)

        -- swing / activate when in range (0.3s cooldown) — exact Clean Hub behavior
        local bodyDist = (position - rootPart.Position).Magnitude
        local withinActivationRange = bodyDist <= zcfg.ACTIVATE_DISTANCE
        if withinActivationRange then
            if (tick() - (z.lastActivationTime or 0)) >= 0.3 then
                if tool then
                    pcall(function()
                        tool:Activate()
                    end)
                end
                z.lastActivationTime = tick()
            end
        end

        -- follow velocity — exact Clean Hub: full 3D unit * FOLLOW_SPEED
        if targetDirection.Magnitude > zcfg.MIN_FOLLOW_DISTANCE then
            rootPart.AssemblyLinearVelocity = targetDirection.Unit * zcfg.FOLLOW_SPEED
        else
            rootPart.AssemblyLinearVelocity = Vector3.new(0, rootPart.AssemblyLinearVelocity.Y * 0.5, 0)
        end
    end)
end

function BatBypassV2.Toggle()
    if BatBypassV2.Enabled then
        BatBypassV2.Stop()
    else
        BatBypassV2.Start()
    end
end

_G.SakuraBatBypassV2 = BatBypassV2
_G.AceStartAntiBypassAimbot = function()
    local spd = tonumber(BYPASS_AIMBOT_SPEED) or tonumber(BAT_V2_SPEED) or 55
    BatBypassV2.Start(spd)
    _G.AceAntiBypassAimbotOn = true
    return true
end
_G.AceStopAntiBypassAimbot = function()
    BatBypassV2.Stop()
    _G.AceAntiBypassAimbotOn = false
end
_G.AceAntiBypassAimbotOn = _G.AceAntiBypassAimbotOn or false


function startSpectrumBypassAimbot()
    stopSpectrumBypassAimbot()
    -- AntiAimbot only — do NOT touch Bat Aimbot (autoBatEnabled / visuals / mode)
    if batDesyncTpEnabled then pcall(stopBatDesyncTp) end
    if autoBatV2Enabled then pcall(disableBatV2) end
    if autoLeftEnabled then
        autoLeftEnabled = false
        if autoLeftSetVisual then autoLeftSetVisual(false) end
        stopAutoLeft()
    end
    if autoRightEnabled then
        autoRightEnabled = false
        if autoRightSetVisual then autoRightSetVisual(false) end
        stopAutoRight()
    end
    -- Bat Aimbot açıksa kapat (çakışmasın)
    if autoBatEnabled then
        autoBatEnabled = false
        if autoBatSetVisual then pcall(autoBatSetVisual, false) end
        if mobSetAutoBat then pcall(mobSetAutoBat, false) end
        pcall(stopAimbotAdapt)
        pcall(stopAimbotV3)
    end

    _adaptBypass.enabled = true
    _adaptBypass.equipped = false
    _adaptBypass.target = nil
    _adaptBypass.intendedVelocity = Vector3.zero
    _adaptBatPred = {}

    local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if root then
        _vx7ClearAimbotMover(root)
    end
    local hum0 = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
    if hum0 then
        if _prevAutoRotate == nil then _prevAutoRotate = hum0.AutoRotate end
        pcall(function() hum0.AutoRotate = false end)
        if not LP.Character:FindFirstChildOfClass("Tool") then
            local bat = _vx7FindBat()
            if bat then pcall(function() hum0:EquipTool(bat) end) end
        end
    end
    if type(_suppressBodyLock) == "function" then pcall(_suppressBodyLock) end

    _adaptBypass.conn = RunService.RenderStepped:Connect(function(dt)
        _adaptBypassTick(dt)
    end)
    _adaptBypass.safetyConn = RunService.Heartbeat:Connect(function()
        if not _adaptBypass.enabled then return end
        if not antiAimbotEnabled then return end
        local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        if not hrp:FindFirstChild(_adaptBypass.moverName) then
            local spd = tonumber(BYPASS_AIMBOT_SPEED) or tonumber(BAT_AIMBOT_SPEED) or 58
            _vx7EnsureMover(hrp, spd)
        end
    end)
end

-- keep legacy aliases used elsewhere
_specBypass = _adaptBypass

local BAT_AIMBOT_MODES = {"Normal", "V2", "V3"}

function setBatAimbotMode(mode)
    mode = tostring(mode or "Normal")
    if mode == "Bypass" then mode = "V2" end
    local ok = false
    for _, m in ipairs(BAT_AIMBOT_MODES) do
        if m == mode then ok = true; break end
    end
    if not ok then mode = "Normal" end
    batAimbotMode = mode
    if batAimbotModeLabel then batAimbotModeLabel.Text = tostring(batAimbotMode) .. "  ▼" end
    if autoBatEnabled then
        pcall(stopAimbotAdapt)
        pcall(stopAimbotV3)
        pcall(function() if BatBypassV2 then BatBypassV2.Stop() end end)
        if batAimbotMode == "V3" then
            startAimbotV3()
        elseif batAimbotMode == "V2" then
            local spd = tonumber(BYPASS_AIMBOT_SPEED) or tonumber(BAT_AIMBOT_SPEED) or 55
            if BatBypassV2 then BatBypassV2.Start(spd) end
        else
            startAimbotAdapt()
        end
    end
    pcall(saveAllSettings)
    return batAimbotMode
end


function cycleBatAimbotMode(dir)
    dir = dir or 1
    local modes = BAT_AIMBOT_MODES
    local idx = 1
    for i, m in ipairs(modes) do
        if m == batAimbotMode then idx = i; break end
    end
    local newIdx = idx + dir
    if newIdx < 1 then newIdx = #modes end
    if newIdx > #modes then newIdx = 1 end
    return setBatAimbotMode(modes[newIdx])
end



-- ═══════════════════════════════════════════════════════════════
-- BAT BYPASS — Persecución autónoma con predicción de ping
-- (Reemplaza el módulo Anti Bypass anterior. Antes BAT V2.)
-- ═══════════════════════════════════════════════════════════════

BAT_V2_SPEED           = BAT_V2_SPEED           or 55
BAT_V2_HIT_DIST        = BAT_V2_HIT_DIST        or 13
BAT_V2_LEAD_STUDS      = BAT_V2_LEAD_STUDS      or 3
BAT_V2_BODY_LOCK_RANGE = BAT_V2_BODY_LOCK_RANGE or 60

local SnowVS = _G.SnowVS or {}
_G.SnowVS = SnowVS

SnowVS.BatBypass = SnowVS.BatBypass or {}
-- Alias legado para no romper referencias externas existentes
SnowVS.AimbotBypassV2 = SnowVS.BatBypass

local BB = SnowVS.BatBypass

BB.Enabled    = BB.Enabled    or false
BB.Connection = BB.Connection or nil

BB.Z = BB.Z or {
    targetPlayer          = nil,
    lastTargetPos         = nil,
    targetVelocity        = Vector3.zero,
    smoothedVelocity      = Vector3.zero,
    velocityHistory       = {},
    accelerationHistory   = {},
    aerialVelocityHistory = {},
    previousDirection     = nil,
    lastDirectionChangeTime = 0,
    airborneTime          = 0,
    lastActivationTime    = 0,
    currentPing           = 0.1,
    realPingMs            = 0,
}

BB.ZCFG = BB.ZCFG or {
    FOLLOW_SPEED                    = BAT_V2_SPEED,
    ACTIVATE_DISTANCE               = BAT_V2_HIT_DIST,
    MIN_FOLLOW_DISTANCE             = 1,
    PREDICTION_TIME                 = 0.22,
    PREDICT_AHEAD                   = BAT_V2_LEAD_STUDS,
    MAX_VELOCITY_CHANGE             = 150,
    VELOCITY_SMOOTHING              = 0.2,
    MAX_HORIZONTAL_VELOCITY         = 80,
    SERVER_TICKRATE                 = 1 / 60,
    MIN_PING_COMPENSATION           = 0.03,
    MAX_PING_COMPENSATION           = 0.25,
    ACCELERATION_PREDICTION_WEIGHT  = 0.3,
    DIRECTION_CHANGE_DETECTION_TIME = 0.12,
    QUICK_DIRECTION_CHANGE_MULTIPLIER = 1.5,
    GRAVITY                         = 196.2,
    AIR_CONTROL_FACTOR              = 0.8,
    MIN_AIRBORNE_TIME               = 0.08,
}

local function bbAverageVector(history)
    if #history == 0 then return Vector3.zero end
    local total = Vector3.zero
    for _, v in ipairs(history) do total += v end
    return total / #history
end

local function bbPushHistory(history, value, maximum)
    table.insert(history, value)
    if #history > maximum then table.remove(history, 1) end
end

function BB.FindBat()
    local char = LP.Character
    if not char then return nil end
    local equipped = char:FindFirstChildOfClass("Tool")
    if equipped then
        local n = equipped.Name:lower()
        if n:find("bat", 1, true) or n:find("slap", 1, true) then
            return equipped
        end
    end
    local bp = LP:FindFirstChildOfClass("Backpack")
    if bp then
        for _, tool in ipairs(bp:GetChildren()) do
            if tool:IsA("Tool") then
                local n = tool.Name:lower()
                if n:find("bat", 1, true) or n:find("slap", 1, true) then
                    return tool
                end
            end
        end
    end
    return nil
end

local function bbResetTarget()
    local Z = BB.Z
    Z.targetPlayer          = nil
    Z.lastTargetPos         = nil
    Z.targetVelocity        = Vector3.zero
    Z.smoothedVelocity      = Vector3.zero
    Z.velocityHistory       = {}
    Z.accelerationHistory   = {}
    Z.aerialVelocityHistory = {}
    Z.previousDirection     = nil
    Z.airborneTime          = 0
end

local function bbNearestTarget(root)
    local nearest, nearestDistance = nil, math.huge
    for _, candidate in ipairs(Players:GetPlayers()) do
        if candidate ~= LP and candidate.Character then
            local targetRoot     = candidate.Character:FindFirstChild("HumanoidRootPart")
            local targetHumanoid = candidate.Character:FindFirstChildOfClass("Humanoid")
            if targetRoot and targetHumanoid and targetHumanoid.Health > 0 then
                local distance = (root.Position - targetRoot.Position).Magnitude
                if distance < nearestDistance then
                    nearest, nearestDistance = candidate, distance
                end
            end
        end
    end
    return nearest
end

local function bbRotateRoot(root, direction)
    if direction.Magnitude < 0.01 then return end
    local axis  = root.CFrame.LookVector:Cross(direction.Unit)
    local angle = math.asin(math.clamp(axis.Magnitude, -1, 1))
    root.AssemblyAngularVelocity = axis.Magnitude > 0.01
        and axis.Unit * angle * 80
        or  Vector3.zero
end

local function bbSamplePing()
    local ok, value = pcall(function()
        return game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()
    end)
    local Z = BB.Z
    if ok and type(value) == "number" then Z.realPingMs = math.floor(value) end
    Z.currentPing = math.clamp(
        Z.realPingMs / 1000,
        BB.ZCFG.MIN_PING_COMPENSATION,
        BB.ZCFG.MAX_PING_COMPENSATION
    )
end

BB.PingLoopStarted = BB.PingLoopStarted or false
if not BB.PingLoopStarted then
    BB.PingLoopStarted = true
    task.spawn(function()
        while true do
            pcall(bbSamplePing)
            task.wait(0.5)
        end
    end)
end

-- Stubs para compatibilidad con la API antigua (Body Lock ya no se usa aparte)
function BB.StartBodyLock() end
function BB.StopBodyLock()  end

function BB.Stop()
    local Z = BB.Z
    BB.Enabled = false
    if BB.Connection then
        BB.Connection:Disconnect()
        BB.Connection = nil
    end
    local char     = LP.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    local root     = char and char:FindFirstChild("HumanoidRootPart")
    if humanoid then humanoid.AutoRotate = true end
    if root     then root.AssemblyAngularVelocity = Vector3.zero end
    bbResetTarget()
    Z.lastActivationTime = 0
end

function BB.Start()
    if BB.Connection then return end

    local char     = LP.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    local root     = char and char:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root then return end

    BB.Enabled = true
    humanoid.AutoRotate = false

    local bat = BB.FindBat()
    if bat and bat.Parent ~= char then
        pcall(function() humanoid:EquipTool(bat) end)
    end

    BB.Connection = RunService.RenderStepped:Connect(function(dt)
        if not BB.Enabled then BB.Stop(); return end
        local Z     = BB.Z
        local ZCFG  = BB.ZCFG

        -- Refresca velocidad según modo actual (Normal/Lagger/Lagger Carry)
        if _G.AceGetAntiBypassAimbotSpeed then
            ZCFG.FOLLOW_SPEED = _G.AceGetAntiBypassAimbotSpeed()
        end

        local currentChar     = LP.Character
        local currentRoot     = currentChar and currentChar:FindFirstChild("HumanoidRootPart")
        local currentHumanoid = currentChar and currentChar:FindFirstChildOfClass("Humanoid")
        if not currentRoot or not currentHumanoid or currentHumanoid.Health <= 0 then return end

        currentHumanoid.AutoRotate = false
        root, humanoid = currentRoot, currentHumanoid

        bat = currentChar:FindFirstChildOfClass("Tool") or BB.FindBat()
        if bat and bat.Parent ~= currentChar then
            pcall(currentHumanoid.EquipTool, currentHumanoid, bat)
        end

        Z.targetPlayer  = bbNearestTarget(root)
        local targetChar = Z.targetPlayer and Z.targetPlayer.Character
        local targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
        local targetHumanoid = targetChar and targetChar:FindFirstChildOfClass("Humanoid")
        if not targetRoot or not targetHumanoid or targetHumanoid.Health <= 0 then
            bbResetTarget(); return
        end

        local targetPos = targetRoot.Position
        local safeDt    = math.max(dt, 1 / 240)

        -- Estima velocidad del rival filtrando outliers
        if Z.lastTargetPos then
            local rawVelocity   = (targetPos - Z.lastTargetPos) / safeDt
            local velocityDelta = rawVelocity - Z.targetVelocity
            if velocityDelta.Magnitude > ZCFG.MAX_VELOCITY_CHANGE then
                rawVelocity = Z.targetVelocity + velocityDelta.Unit * ZCFG.MAX_VELOCITY_CHANGE
            end
            local horizontal = Vector3.new(rawVelocity.X, 0, rawVelocity.Z)
            if horizontal.Magnitude > ZCFG.MAX_HORIZONTAL_VELOCITY then
                horizontal  = horizontal.Unit * ZCFG.MAX_HORIZONTAL_VELOCITY
                rawVelocity = Vector3.new(horizontal.X, rawVelocity.Y, horizontal.Z)
            end
            bbPushHistory(Z.accelerationHistory, (rawVelocity - Z.targetVelocity) / safeDt, 4)
            bbPushHistory(Z.velocityHistory,     rawVelocity, 8)
            Z.targetVelocity   = rawVelocity
            Z.smoothedVelocity = Z.smoothedVelocity:Lerp(rawVelocity, ZCFG.VELOCITY_SMOOTHING)
        end
        Z.lastTargetPos = targetPos

        -- Estado aéreo
        local airborne = targetHumanoid.FloorMaterial == Enum.Material.Air
        Z.airborneTime = airborne and (Z.airborneTime + safeDt) or 0
        if airborne and Z.airborneTime >= ZCFG.MIN_AIRBORNE_TIME then
            bbPushHistory(Z.aerialVelocityHistory, Z.targetVelocity, 6)
        elseif not airborne then
            Z.aerialVelocityHistory = {}
        end

        local predictionVelocity = Z.smoothedVelocity
        if airborne and #Z.aerialVelocityHistory > 0 then
            local aerial = bbAverageVector(Z.aerialVelocityHistory)
            predictionVelocity = Vector3.new(aerial.X, Z.targetVelocity.Y, aerial.Z) * ZCFG.AIR_CONTROL_FACTOR
        end

        -- Detecta cambios bruscos de dirección
        local quickTurn = false
        local horizontalVelocity = Vector3.new(Z.targetVelocity.X, 0, Z.targetVelocity.Z)
        if horizontalVelocity.Magnitude > 5 then
            local direction = horizontalVelocity.Unit
            if Z.previousDirection and Z.previousDirection:Dot(direction) < 0.5 then
                quickTurn = tick() - Z.lastDirectionChangeTime < ZCFG.DIRECTION_CHANGE_DETECTION_TIME
                Z.lastDirectionChangeTime = tick()
            end
            Z.previousDirection = direction
        end

        local serverDelay = Z.currentPing + ZCFG.SERVER_TICKRATE
        if quickTurn then serverDelay *= ZCFG.QUICK_DIRECTION_CHANGE_MULTIPLIER end

        local predicted    = targetPos + predictionVelocity * serverDelay
        local acceleration = bbAverageVector(Z.accelerationHistory)
        predicted += acceleration * ZCFG.ACCELERATION_PREDICTION_WEIGHT * (serverDelay * serverDelay * 0.5)

        local predictionTime = ZCFG.PREDICTION_TIME * 1.1
        if airborne then
            predicted += predictionVelocity * predictionTime
            predicted += Vector3.new(0, -0.5 * ZCFG.GRAVITY * predictionTime * predictionTime, 0)
        else
            predicted += predictionVelocity * predictionTime
        end

        local flatPrediction = Vector3.new(predictionVelocity.X, 0, predictionVelocity.Z)
        if flatPrediction.Magnitude > 1 then
            predicted += flatPrediction.Unit * ZCFG.PREDICT_AHEAD
        end

        local toTarget = predicted - root.Position
        bbRotateRoot(root, toTarget)

        if (targetPos - root.Position).Magnitude <= ZCFG.ACTIVATE_DISTANCE
        and tick() - Z.lastActivationTime >= 0.3 then
            if bat then pcall(bat.Activate, bat) end
            Z.lastActivationTime = tick()
        end

        if toTarget.Magnitude > ZCFG.MIN_FOLLOW_DISTANCE then
            root.AssemblyLinearVelocity = toTarget.Unit * ZCFG.FOLLOW_SPEED
        else
            root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y * 0.5, 0)
        end
    end)
end


-- Ace wrappers (Sakura)
_G.AceAntiBypassAimbotSpeed = _G.AceAntiBypassAimbotSpeed or 60
_G.AceAntiBypassLaggerAimbotSpeed = _G.AceAntiBypassLaggerAimbotSpeed or 40
_G.AceAntiBypassAimbotOn = _G.AceAntiBypassAimbotOn or false

_G.AceGetAntiBypassAimbotSpeed = function()
    if laggerCarryToggled or laggerToggled then
        return tonumber(_G.AceAntiBypassLaggerAimbotSpeed) or 40
    end
    return tonumber(_G.AceAntiBypassAimbotSpeed) or tonumber(BYPASS_AIMBOT_SPEED) or 60
end

_G.AceStartAntiBypassAimbot = function()
    if type(disableAutoBat) == "function" and autoBatEnabled then pcall(disableAutoBat) end
    if batDesyncTpEnabled and type(stopBatDesyncTp) == "function" then pcall(stopBatDesyncTp) end
    _G.AceAntiBypassAimbotOn = true
    if SnowVS and SnowVS.BatBypass then
        SnowVS.BatBypass.ZCFG.FOLLOW_SPEED = _G.AceGetAntiBypassAimbotSpeed()
        SnowVS.BatBypass.Start()
    end
    if _G.AceAimbotSetVisual then pcall(_G.AceAimbotSetVisual, true) end
    pcall(saveAllSettings)
    return true
end

_G.AceStopAntiBypassAimbot = function()
    if SnowVS and SnowVS.BatBypass then SnowVS.BatBypass.Stop() end
    _G.AceAntiBypassAimbotOn = false
    if _G.AceAimbotSetVisual then pcall(_G.AceAimbotSetVisual, false) end
    pcall(saveAllSettings)
end

function enableBatBypassAimbot()
    return _G.AceStartAntiBypassAimbot()
end

function disableBatBypassAimbot()
    _G.AceStopAntiBypassAimbot()
end


function disableAutoBat()
    autoBatEnabled = false
    if autoBatSetVisual then autoBatSetVisual(false) end
    if mobSetAutoBat then mobSetAutoBat(false) end
    stopAimbotAdapt()
    stopAimbotV3()
    pcall(function() if BatBypassV2 then BatBypassV2.Stop() end end)
    -- Spectrum (Bypass) sadece AntiAimbot'a ait; Bat Aimbot kapanınca onu kapatma
end


function enableAntiAimbot()
    antiAimbotEnabled = true
    if mobSetAntiAimbot then pcall(mobSetAntiAimbot, true) end
    if antiAimbotFloatingButton then
        local f = antiAimbotFloatingButton:FindFirstChild("Frame")
        if f then paintFloatingBtn(f, true) end
    end
    local mode = tostring(antiAimbotMode or "V1"):upper():gsub("%s+", "")
    if mode ~= "V1" and mode ~= "V2" then mode = "V1" end
    antiAimbotMode = mode
    if mode == "V2" then
        stopSpectrumBypassAimbot()
        local spd = tonumber(BYPASS_AIMBOT_SPEED) or 60
        if BatBypassV2 then BatBypassV2.Start(spd) end
    else
        pcall(function() if BatBypassV2 then BatBypassV2.Stop() end end)
        startSpectrumBypassAimbot()
    end
end

function disableAntiAimbot()
    antiAimbotEnabled = false
    stopSpectrumBypassAimbot()
    pcall(function() if BatBypassV2 then BatBypassV2.Stop() end end)
    if mobSetAntiAimbot then pcall(mobSetAntiAimbot, false) end
    if antiAimbotFloatingButton then
        local f = antiAimbotFloatingButton:FindFirstChild("Frame")
        if f then paintFloatingBtn(f, false) end
    end
end

function setAntiAimbotMode(mode)
    mode = tostring(mode or "V1"):upper():gsub("%s+", "")
    if mode == "2" or mode == "BYPASS" or mode == "CLEAN" then mode = "V2" end
    if mode ~= "V1" and mode ~= "V2" then mode = "V1" end
    antiAimbotMode = mode
    if antiAimbotModeLabel then
        antiAimbotModeLabel.Text = mode .. "  ▼"
    end
    if autoBatV2SetVisual then
        pcall(autoBatV2SetVisual, antiAimbotEnabled == true and mode == "V2")
    end
    if antiAimbotEnabled then
        -- restart with new mode
        stopSpectrumBypassAimbot()
        pcall(function() if BatBypassV2 then BatBypassV2.Stop() end end)
        if mode == "V2" then
            local spd = tonumber(BYPASS_AIMBOT_SPEED) or 60
            if BatBypassV2 then BatBypassV2.Start(spd) end
        else
            startSpectrumBypassAimbot()
        end
    end
    _lastSavedJSON = nil -- force persist (V2 must survive rejoin)
    pcall(saveAllSettings)
    return antiAimbotMode
end

function toggleAntiAimbot()
    if antiAimbotEnabled then
        disableAntiAimbot()
    else
        enableAntiAimbot()
    end
    return antiAimbotEnabled
end

-- ==================== TAUNT (chat spam) ====================
function startTaunt()
    if _tauntThread then return end
    tauntEnabled = true
    _tauntThread = task.spawn(function()
        while tauntEnabled do
            pcall(function()
                local chatService = game:GetService("TextChatService")
                local channel = chatService and chatService.TextChannels and chatService.TextChannels:FindFirstChild("RBXGeneral")
                if channel then
                    channel:SendAsync("sakura on top !")
                else
                    local events = ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
                    local say = events and events:FindFirstChild("SayMessageRequest")
                    if say then say:FireServer("sakura on top !", "All") end
                end
            end)
            task.wait(0.2)
        end
        _tauntThread = nil
    end)
end

function stopTaunt()
    tauntEnabled = false
    if _tauntThread then
        pcall(task.cancel, _tauntThread)
        _tauntThread = nil
    end
end

function toggleTaunt()
    if tauntEnabled then
        stopTaunt()
    else
        startTaunt()
    end
    return tauntEnabled
end

function enableAutoBat()
    if autoLeftEnabled then
        autoLeftEnabled = false
        if autoLeftSetVisual then autoLeftSetVisual(false) end
        stopAutoLeft()
    end
    if autoRightEnabled then
        autoRightEnabled = false
        if autoRightSetVisual then autoRightSetVisual(false) end
        stopAutoRight()
    end
    if batDesyncTpEnabled then toggleBatDesyncTp() end
    if autoBatV2Enabled then disableBatV2() end
    -- AntiAimbot açıksa kapat (çakışmasın)
    if antiAimbotEnabled then
        antiAimbotEnabled = false
        stopSpectrumBypassAimbot()
        pcall(function() if BatBypassV2 then BatBypassV2.Stop() end end)
        if mobSetAntiAimbot then pcall(mobSetAntiAimbot, false) end
        if antiAimbotFloatingButton then
            local f = antiAimbotFloatingButton:FindFirstChild("Frame")
            if f then paintFloatingBtn(f, false) end
        end
    end
    autoBatEnabled = true
    if autoBatSetVisual then autoBatSetVisual(true) end
    if mobSetAutoBat then mobSetAutoBat(true) end
    local mode = tostring(batAimbotMode or "Normal")
    if mode == "Bypass" then mode = "V2"; batAimbotMode = "V2" end
    pcall(stopAimbotAdapt)
    pcall(stopAimbotV3)
    pcall(function() if BatBypassV2 then BatBypassV2.Stop() end end)
    if mode == "V3" then
        startAimbotV3()
    elseif mode == "V2" then
        local spd = tonumber(BYPASS_AIMBOT_SPEED) or tonumber(BAT_AIMBOT_SPEED) or 55
        if BatBypassV2 then BatBypassV2.Start(spd) end
    else
        startAimbotAdapt()
    end
end


function enableBatV2()
    if autoBatV2Enabled then return end
    if autoBatEnabled then disableAutoBat() end
    if batDesyncTpEnabled then toggleBatDesyncTp() end
    if autoLeftEnabled then
        autoLeftEnabled = false
        stopAutoLeft()
        if autoLeftSetVisual then autoLeftSetVisual(false) end
        if mobSetAutoLeft then mobSetAutoLeft(false) end
    end
    if autoRightEnabled then
        autoRightEnabled = false
        stopAutoRight()
        if autoRightSetVisual then autoRightSetVisual(false) end
        if mobSetAutoRight then mobSetAutoRight(false) end
    end
    autoBatV2Enabled = true
    startBatV2Aimbot()
    if autoBatV2SetVisual then autoBatV2SetVisual(true) end
    if batV2FloatingButton then
        local btnFrame = batV2FloatingButton:FindFirstChild("Frame")
        if btnFrame then paintFloatingBtn(btnFrame, true) end
    end
end

function disableBatV2()
    if not autoBatV2Enabled then return end
    autoBatV2Enabled = false
    stopBatV2Aimbot()
    if autoBatV2SetVisual then autoBatV2SetVisual(false) end
    if batV2FloatingButton then
        local btnFrame = batV2FloatingButton:FindFirstChild("Frame")
        if btnFrame then paintFloatingBtn(btnFrame, false) end
    end
end

function toggleBatV2()
    if autoBatV2Enabled then disableBatV2()
    else enableBatV2() end
end

local function updateTpBatButtonWithAntiDie(state)
    if tpBatFloatingButton then
        local btnFrame = tpBatFloatingButton:FindFirstChild("Frame")
        if btnFrame then
            local label = btnFrame:FindFirstChild("TextLabel")
            local stroke = btnFrame:FindFirstChildOfClass("UIStroke")
            if state then
                btnFrame.BackgroundColor3 = getThemeColor()
                if label then
                    label.Text = "TP"
                    label.TextColor3 = Color3.fromRGB(0,0,0)
                end
                if stroke then
                    stroke.Color = Color3.fromRGB(255, 215, 0)
                    stroke.Thickness = 2.5
                end
            else
                if label then label.Text = "TP" end
                paintFloatingBtn(btnFrame, batDesyncTpEnabled)
            end
        end
    end
end

batDesyncTpEnabled = false
local batDesyncTpConn = nil
local batDesyncTpSetVisual = nil
local hittingCooldownDesync = false
local _tpBatUnwalkForced = false

-- ============================================================
-- TP BAT — V1 / V2 / V3
-- ============================================================
batTPVersion = batTPVersion or "V1"  -- V1/V2/V3 only
batTPVersionLabel = nil
local _batTPCharConn = nil
local _tpBatHRP = nil
local _tpBatH = nil

local function sharedGetBatTP()
    local char = LP.Character
    if not char then return nil end
    local function isBat(tool)
        if not tool or not tool:IsA("Tool") then return false end
        local n = tool.Name:lower()
        return n:find("bat") or n:find("slap") or n:find("glove") or n:find("hand") or n:find("sword") or n:find("knife")
    end
    for _, tool in ipairs(char:GetChildren()) do
        if isBat(tool) then return tool end
    end
    local bp = LP:FindFirstChildOfClass("Backpack") or LP:FindFirstChild("Backpack")
    if bp then
        for _, tool in ipairs(bp:GetChildren()) do
            if isBat(tool) then
                pcall(function()
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hum then hum:EquipTool(tool) end
                end)
                return tool
            end
        end
    end
    return char:FindFirstChild("Bat")
end

local function sharedClosestTP()
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil, _huge end
    local best, bestD = nil, _huge
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LP and plr.Character then
            local tr = plr.Character:FindFirstChild("HumanoidRootPart")
            if tr then
                local d = (hrp.Position - tr.Position).Magnitude
                if d < bestD then bestD = d; best = plr end
            end
        end
    end
    return best, bestD
end

local function sharedTryHitTP()
    if hittingCooldownDesync then return end
    hittingCooldownDesync = true
    pcall(function()
        local bat = sharedGetBatTP()
        if bat then
            bat:Activate()
            local ev = bat:FindFirstChildWhichIsA("RemoteEvent")
            if ev then ev:FireServer() end
        end
    end)
    task.delay(0.08, function() hittingCooldownDesync = false end)
end

local function cleanupBatTPExtras()
    pcall(function()
        local hrp = (_tpBatHRP and _tpBatHRP.Parent and _tpBatHRP) or (LP.Character and LP.Character:FindFirstChild("HumanoidRootPart"))
        if hrp and sethiddenproperty then sethiddenproperty(hrp, "PhysicsRepRootPart", hrp) end
        local char = LP.Character
        if char then
            local ff = char:FindFirstChild("K7TPBatFF")
            if ff then ff:Destroy() end
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                pcall(function()
                    hum.BreakJointsOnDeath = true
                    hum.RequiresNeck = true
                    hum:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
                    hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
                    hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
                    hum:SetStateEnabled(Enum.HumanoidStateType.Physics, true)
                end)
            end
        end
    end)
    _tpBatHRP = nil
    _tpBatH = nil
end

function startBatDesyncTp()
    if batDesyncTpConn then
        pcall(function() batDesyncTpConn:Disconnect() end)
        batDesyncTpConn = nil
    end
    if _batTPCharConn then
        pcall(function() _batTPCharConn:Disconnect() end)
        _batTPCharConn = nil
    end

    if not unwalkEnabled then
        startUnwalk()
        unwalkEnabled = true
        _tpBatUnwalkForced = true
        if setUnwalkVisual then setUnwalkVisual(true) end
    end
    batDesyncTpEnabled = true

    local ver = tostring(batTPVersion or "V1")
    if ver == "V4" or ver == "V5" then
        ver = "V3"
        batTPVersion = "V3"
    end
    if ver ~= "V1" and ver ~= "V2" and ver ~= "V3" then
        ver = "V1"
        batTPVersion = "V1"
    end

    -- ========== V1: Akatsuki TP Bat (direct TP + look + hit) ==========
    if ver == "V1" then
        batDesyncTpConn = RunService.Heartbeat:Connect(function()
            if not batDesyncTpEnabled then return end
            local char = LP.Character
            if not char then return end
            local root = char:FindFirstChild("HumanoidRootPart")
            local hum = char:FindFirstChildOfClass("Humanoid")
            if not root or not hum or hum.Health <= 0 then return end
            if hum.AutoRotate then
                if _prevAutoRotate == nil then _prevAutoRotate = hum.AutoRotate end
                hum.AutoRotate = false
            end
            pcall(function()
                local bat = sharedGetBatTP()
                if bat and bat.Parent ~= char then pcall(function() hum:EquipTool(bat) end) end
            end)
            local target = select(1, sharedClosestTP())
            if not target or not target.Character then return end
            local tr = target.Character:FindFirstChild("HumanoidRootPart")
            local th = target.Character:FindFirstChildOfClass("Humanoid")
            if not tr or not th or th.Health <= 0 then return end
            local aimPos = tr.Position + _V3new(0, 0.9, 0)
            local dist = (root.Position - aimPos).Magnitude
            if dist > 1.5 then
                root.CFrame = _CFnew(aimPos, aimPos + tr.CFrame.LookVector)
            else
                root.CFrame = _CFlookAt(root.Position, tr.Position)
            end
            local cam = workspace.CurrentCamera
            if cam then
                pcall(function() cam.CFrame = _CFnew(cam.CFrame.Position, tr.Position) end)
            end
            sharedTryHitTP()
        end)
        _batTPCharConn = LP.CharacterAdded:Connect(function(char)
            if not batDesyncTpEnabled then return end
            task.wait(0.2)
            _tpBatHRP = char:FindFirstChild("HumanoidRootPart")
            _tpBatH = char:FindFirstChildOfClass("Humanoid")
        end)
        local char = LP.Character
        if char then
            _tpBatHRP = char:FindFirstChild("HumanoidRootPart")
            _tpBatH = char:FindFirstChildOfClass("Humanoid")
        end

    -- ========== V2: Akatsuki TP Bat (distance + safe sample / under-map) ==========
    elseif ver == "V2" then
        local _v2Samples = {}
        batDesyncTpConn = RunService.Heartbeat:Connect(function()
            if not batDesyncTpEnabled then return end
            local char = LP.Character
            if not char then return end
            local root = char:FindFirstChild("HumanoidRootPart")
            local hum = char:FindFirstChildOfClass("Humanoid")
            if not root or not hum or hum.Health <= 0 then return end
            if hum.AutoRotate then
                if _prevAutoRotate == nil then _prevAutoRotate = hum.AutoRotate end
                hum.AutoRotate = false
            end
            pcall(function()
                local bat = sharedGetBatTP()
                if bat and bat.Parent ~= char then pcall(function() hum:EquipTool(bat) end) end
            end)
            local target = select(1, sharedClosestTP())
            if not target or not target.Character then return end
            local tr = target.Character:FindFirstChild("HumanoidRootPart")
            local th = target.Character:FindFirstChildOfClass("Humanoid")
            if not tr or not th or th.Health <= 0 then return end

            local samp = _v2Samples[target] or {}
            _v2Samples[target] = samp
            local underMap = tr.Position.Y < -9
            local useSafe = false
            local aimCF = tr.CFrame
            if not underMap then
                samp.safeCFrame = tr.CFrame
                samp.safePosition = tr.Position
            else
                if samp.safeCFrame then
                    aimCF = samp.safeCFrame
                    useSafe = true
                end
            end
            local aimPos = aimCF.Position
            if not useSafe then
                aimPos = aimPos + _V3new(0, 0.9, 0)
            end
            local distLimit = tonumber(BAT_V2_HIT_DIST) or 8
            if type(AUTO_BAT_V2_DIST) == "number" then
                distLimit = math.max(distLimit, AUTO_BAT_V2_DIST)
            end
            -- Akatsuki V2 distance gate (tpBatV2Distance style)
            local v2Dist = tonumber(rawget(_G, "__tpBatV2Distance")) or distLimit
            if (root.Position - aimPos).Magnitude > v2Dist then
                root.CFrame = _CFnew(aimPos, aimPos + aimCF.LookVector)
            else
                root.CFrame = _CFlookAt(root.Position, aimCF.Position)
            end
            local cam = workspace.CurrentCamera
            if cam then
                pcall(function() cam.CFrame = _CFnew(cam.CFrame.Position, aimCF.Position) end)
            end
            sharedTryHitTP()
        end)
        _batTPCharConn = LP.CharacterAdded:Connect(function(char)
            if not batDesyncTpEnabled then return end
            task.wait(0.2)
            _tpBatHRP = char:FindFirstChild("HumanoidRootPart")
            _tpBatH = char:FindFirstChildOfClass("Humanoid")
            _v2Samples = {}
        end)
        local char = LP.Character
        if char then
            _tpBatHRP = char:FindFirstChild("HumanoidRootPart")
            _tpBatH = char:FindFirstChildOfClass("Humanoid")
        end

    elseif ver == "V3" then
        -- K7 Duels TP Bat logic
        pcall(function()
            local char = LP.Character
            if char then
                local oldFF = char:FindFirstChild("K7TPBatFF")
                if oldFF then oldFF:Destroy() end
                local ff = Instance.new("ForceField")
                ff.Name = "K7TPBatFF"
                ff.Visible = false
                ff.Parent = char
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then
                    hum.BreakJointsOnDeath = false
                    hum.RequiresNeck = false
                    pcall(function()
                        hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
                        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
                        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
                        hum:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
                    end)
                end
            end
        end)
        batDesyncTpConn = RunService.Heartbeat:Connect(function()
            if not batDesyncTpEnabled then return end
            local char = LP.Character
            if not char then return end
            local root = char:FindFirstChild("HumanoidRootPart")
            local hum = char:FindFirstChildOfClass("Humanoid")
            if not root or not hum then return end
            pcall(function()
                local bat = sharedGetBatTP()
                if bat and bat.Parent ~= char then
                    pcall(function() hum:EquipTool(bat) end)
                end
            end)
            pcall(function()
                hum.MaxHealth = math.max(hum.MaxHealth, 100)
                hum.Health = hum.MaxHealth
                hum.BreakJointsOnDeath = false
                hum.RequiresNeck = false
                hum.PlatformStand = false
                hum.Sit = false
                local st = hum:GetState()
                if st == Enum.HumanoidStateType.Dead
                    or st == Enum.HumanoidStateType.Physics
                    or st == Enum.HumanoidStateType.Ragdoll
                    or st == Enum.HumanoidStateType.FallingDown then
                    hum:ChangeState(Enum.HumanoidStateType.Running)
                end
                if not char:FindFirstChild("K7TPBatFF") then
                    local ff = Instance.new("ForceField")
                    ff.Name = "K7TPBatFF"
                    ff.Visible = false
                    ff.Parent = char
                end
            end)
            local target = select(1, sharedClosestTP())
            if not target or not target.Character then return end
            local tr = target.Character:FindFirstChild("HumanoidRootPart")
            if not tr then return end
            pcall(function()
                if sethiddenproperty then sethiddenproperty(root, "PhysicsRepRootPart", tr) end
            end)
            local back = tr.CFrame.LookVector
            local flatBack = _V3new(back.X, 0, back.Z)
            local offset
            if flatBack.Magnitude < 0.05 then
                offset = _V3new(0, 1.2, 2.2)
            else
                offset = _V3new(0, 1.2, 0) - (flatBack.Unit * 2.2)
            end
            local targetPos = tr.Position + offset
            local dist = (root.Position - targetPos).Magnitude
            if dist > 10 then
                root.CFrame = _CFnew(targetPos, tr.Position)
                root.AssemblyLinearVelocity = _V3zero
                root.AssemblyAngularVelocity = _V3zero
            elseif dist > 2.5 then
                local dir = (targetPos - root.Position)
                local flatDir = _V3new(dir.X, 0, dir.Z)
                if flatDir.Magnitude > 0.05 then
                    root.AssemblyLinearVelocity = flatDir.Unit * math.min(55, dist * 8)
                        + _V3new(0, root.AssemblyLinearVelocity.Y * 0.2, 0)
                end
                local flat = _V3new(tr.Position.X - root.Position.X, 0, tr.Position.Z - root.Position.Z)
                if flat.Magnitude > 0.1 then
                    root.CFrame = _CFnew(root.Position, root.Position + flat.Unit)
                end
            else
                local flat = _V3new(tr.Position.X - root.Position.X, 0, tr.Position.Z - root.Position.Z)
                if flat.Magnitude > 0.1 then
                    root.CFrame = _CFnew(root.Position, root.Position + flat.Unit)
                end
                local v = root.AssemblyLinearVelocity
                root.AssemblyLinearVelocity = _V3new(v.X * 0.5, math.max(v.Y, -10), v.Z * 0.5)
            end
            pcall(function()
                local cam = workspace.CurrentCamera
                if cam then cam.CFrame = _CFnew(cam.CFrame.Position, tr.Position) end
            end)
            sharedTryHitTP()
            pcall(function()
                local maxLin, maxAng = 85, 15
                local v = root.AssemblyLinearVelocity
                if v.Magnitude > maxLin then
                    root.AssemblyLinearVelocity = v.Unit * maxLin
                end
                if root.AssemblyAngularVelocity.Magnitude > maxAng then
                    root.AssemblyAngularVelocity = _V3zero
                end
            end)
        end)
        _batTPCharConn = LP.CharacterAdded:Connect(function(char)
            if not batDesyncTpEnabled then return end
            task.wait(0.15)
            pcall(function()
                local oldFF = char:FindFirstChild("K7TPBatFF")
                if oldFF then oldFF:Destroy() end
                local ff = Instance.new("ForceField")
                ff.Name = "K7TPBatFF"
                ff.Visible = false
                ff.Parent = char
            end)
        end)

    elseif false then -- V4 removed
        -- V4: Anti-Sammy / GRAPE TP Bat (distance 3)
        batDesyncTpConn = RunService.Heartbeat:Connect(function()
            if not batDesyncTpEnabled then return end
            local char = LP.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then return end
            local target = select(1, sharedClosestTP())
            if target and target.Character then
                local tr = target.Character:FindFirstChild("HumanoidRootPart")
                if tr then
                    if sethiddenproperty then
                        pcall(function() sethiddenproperty(hrp, "PhysicsRepRootPart", tr) end)
                    end
                    local targetPos = tr.Position + _V3new(0, 0.9, 0)
                    if (hrp.Position - targetPos).Magnitude > 3 then
                        hrp.CFrame = _CFnew(targetPos)
                    end
                    local cam = workspace.CurrentCamera
                    if cam then
                        cam.CFrame = _CFnew(cam.CFrame.Position, tr.Position)
                    end
                    sharedTryHitTP()
                end
            end
        end)
        _batTPCharConn = LP.CharacterAdded:Connect(function(char)
            if not batDesyncTpEnabled then return end
            task.wait(0.2)
            _tpBatHRP = char:FindFirstChild("HumanoidRootPart")
            _tpBatH = char:FindFirstChildOfClass("Humanoid")
        end)
        local char = LP.Character
        if char then
            _tpBatHRP = char:FindFirstChild("HumanoidRootPart")
            _tpBatH = char:FindFirstChildOfClass("Humanoid")
        end

    else
        -- V4/V5 removed (use V1/V2/V3 only)
    end

    if batDesyncTpSetVisual then batDesyncTpSetVisual(true) end
    updateTpBatButtonWithAntiDie(true)
end

function stopBatDesyncTp()
    if batDesyncTpConn then
        batDesyncTpConn:Disconnect()
        batDesyncTpConn = nil
    end
    if _batTPCharConn then
        pcall(function() _batTPCharConn:Disconnect() end)
        _batTPCharConn = nil
    end
    batDesyncTpEnabled = false
    cleanupBatTPExtras()
    if _tpBatUnwalkForced then
        stopUnwalk()
        unwalkEnabled = false
        _tpBatUnwalkForced = false
        if setUnwalkVisual then setUnwalkVisual(false) end
    end
    if batDesyncTpSetVisual then batDesyncTpSetVisual(false) end
    updateTpBatButtonWithAntiDie(false)
end

function toggleBatDesyncTp()
    if batDesyncTpEnabled then
        stopBatDesyncTp()
        updateTpBatButtonWithAntiDie(false)
    else
        disableAllAimbots()
        if autoLeftEnabled then
            autoLeftEnabled = false; stopAutoLeft()
            if autoLeftSetVisual then autoLeftSetVisual(false) end
            if mobSetAutoLeft then mobSetAutoLeft(false) end
        end
        if autoRightEnabled then
            autoRightEnabled = false; stopAutoRight()
            if autoRightSetVisual then autoRightSetVisual(false) end
            if mobSetAutoRight then mobSetAutoRight(false) end
        end
        startBatDesyncTp()
        updateTpBatButtonWithAntiDie(true)
    end
    -- TP Bat tuşuna basılınca Bat Counter V3 3 sn çalışmasın
    pcall(function()
        if lockBatCounterV3 then lockBatCounterV3(3) end
        _batCounterV2LockUntil = _tick() + 3
    end)
    if batDesyncTpSetVisual then batDesyncTpSetVisual(batDesyncTpEnabled) end
    saveAllSettings()
end

local BAT_TP_VERSIONS = {"V1", "V2", "V3"}
function setBatTPVersion(ver)
    ver = tostring(ver or "V1")
    local ok = false
    for _, v in ipairs(BAT_TP_VERSIONS) do
        if v == ver then ok = true; break end
    end
    if not ok then ver = "V1" end
    batTPVersion = ver
    if batTPVersionLabel then batTPVersionLabel.Text = tostring(batTPVersion) .. "  ▼" end
    if batDesyncTpEnabled then
        stopBatDesyncTp()
        startBatDesyncTp()
        if batDesyncTpSetVisual then batDesyncTpSetVisual(true) end
    end
    pcall(saveAllSettings)
    return batTPVersion
end
function cycleBatTPVersion(dir)
    dir = dir or 1
    local idx = 1
    for i, v in ipairs(BAT_TP_VERSIONS) do
        if v == batTPVersion then idx = i; break end
    end
    local newIdx = idx + dir
    if newIdx < 1 then newIdx = #BAT_TP_VERSIONS end
    if newIdx > #BAT_TP_VERSIONS then newIdx = 1 end
    return setBatTPVersion(BAT_TP_VERSIONS[newIdx])
end


function findBat()
    local char = LP.Character
    if not char then return nil end
    for _, name in ipairs(BAT_COUNTER_SLAP_LIST) do
        local t = char:FindFirstChild(name)
        if t and t:IsA("Tool") then return t end
    end
    local bp = LP:FindFirstChildOfClass("Backpack")
    if bp then
        for _, name in ipairs(BAT_COUNTER_SLAP_LIST) do
            local t = bp:FindFirstChild(name)
            if t and t:IsA("Tool") then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then pcall(function() hum:EquipTool(t) end) end
                return t
            end
        end
    end
    for _, ch in ipairs(char:GetChildren()) do
        if ch:IsA("Tool") and (ch.Name:lower():find("bat") or ch.Name:lower():find("slap")) then
            return ch
        end
    end
    return nil
end

function isBatTool(tool)
    if not tool then return false end
    for _, name in ipairs(BAT_COUNTER_SLAP_LIST) do
        if tool.Name == name then return true end
    end
    return tool.Name:lower():find("bat") or tool.Name:lower():find("slap")
end

function findBatForCounter()
    local char = LP.Character
    if not char then return nil end
    local backpack = LP:FindFirstChildOfClass("Backpack")
    for _, name in ipairs(BAT_COUNTER_SLAP_LIST) do
        local tool = char:FindFirstChild(name) or (backpack and backpack:FindFirstChild(name))
        if tool then return tool end
    end
    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("Tool") and (child.Name:lower():find("bat") or child.Name:lower():find("slap")) then
            return child
        end
    end
    if backpack then
        for _, child in ipairs(backpack:GetChildren()) do
            if child:IsA("Tool") and (child.Name:lower():find("bat") or child.Name:lower():find("slap")) then
                return child
            end
        end
    end
    return nil
end

function swingBatForCounter(bat, character)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if bat.Parent ~= character and humanoid then
        pcall(function() humanoid:EquipTool(bat) end)
        task.wait(0.05)
    end
    local remote = bat:FindFirstChildOfClass("RemoteEvent") or bat:FindFirstChildOfClass("RemoteFunction")
    if remote and remote:IsA("RemoteEvent") then
        pcall(function() remote:FireServer() end)
        task.wait(0.1)
        pcall(function() remote:FireServer() end)
    else
        pcall(function() bat:Activate() end)
        task.wait(0.1)
        pcall(function() bat:Activate() end)
    end
end

batCounterDebounce = false

function stopBatCounter()
    if Conns.batCounter then
        Conns.batCounter:Disconnect()
        Conns.batCounter = nil
    end
    batCounterDebounce = false
end

function startBatCounter()
    if Conns.batCounter then return end
    Conns.batCounter = RunService.Heartbeat:Connect(function()
        if not batCounterEnabled then return end
        if batCounterDebounce then return end
        local character = LP.Character
        if not character then return end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid then return end
        local state = humanoid:GetState()
        if state == Enum.HumanoidStateType.Physics or state == Enum.HumanoidStateType.Ragdoll or state == Enum.HumanoidStateType.FallingDown then
            batCounterDebounce = true
            _suppressBodyLock()
            task.spawn(function()
                task.wait(0.15)
                local bat = findBatForCounter()
                if bat then swingBatForCounter(bat, character) end
                task.wait(0.3)
                batCounterDebounce = false
                _unsuppressBodyLock(true)
            end)
        end
    end)
end

function findMedusa()
    local c = LP.Character
    if not c then return nil end
    for _, t in ipairs(c:GetChildren()) do
        if t:IsA("Tool") then
            local n = t.Name:lower()
            if n:find("medusa") or n:find("head") or n:find("stone") then return t end
        end
    end
    local bp = LP:FindFirstChild("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") then
                local n = t.Name:lower()
                if n:find("medusa") or n:find("head") or n:find("stone") then return t end
            end
        end
    end
    return nil
end

function useMedusaCounter()
    if medusaDebounce then return end
    if _tick() - medusaLastUsed < MEDUSA_COOLDOWN then return end
    local c = LP.Character
    if not c then return end
    medusaDebounce = true
    local med = findMedusa()
    if not med then medusaDebounce = false; return end
    if med.Parent ~= c then
        local hum2 = c:FindFirstChildOfClass("Humanoid")
        if hum2 then hum2:EquipTool(med) end
    end
    pcall(function() med:Activate() end)
    medusaLastUsed = _tick()
    medusaDebounce = false
end

function onAnchorChanged(part)
    return part:GetPropertyChangedSignal("Anchored"):Connect(function()
        if medusaCounterEnabled and part.Anchored and part.Transparency == 1 then useMedusaCounter() end
    end)
end

function setupMedusaCounter(char)
    for _, c in pairs(Conns.anchor) do pcall(function() c:Disconnect() end) end
    Conns.anchor = {}
    if not char or not medusaCounterEnabled then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            table.insert(Conns.anchor, onAnchorChanged(part))
        end
    end
    table.insert(Conns.anchor, char.DescendantAdded:Connect(function(part)
        if part:IsA("BasePart") then
            table.insert(Conns.anchor, onAnchorChanged(part))
        end
    end))
end

function stopMedusaCounter()
    for _, c in pairs(Conns.anchor) do pcall(function() c:Disconnect() end) end
    Conns.anchor = {}
end

local DROP_ASCEND_DURATION = 0.22
local DROP_ASCEND_SPEED = 160
local _dropConn = nil

function stopDropBrainrot()
    dropActive = false
    if _dropConn then
        _dropConn:Disconnect()
        _dropConn = nil
    end
    for _, t in ipairs(dropConnections) do
        if type(t) == "thread" then pcall(task.cancel, t)
        elseif type(t) == "RBXScriptConnection" then pcall(t.Disconnect, t) end
    end
    dropConnections = {}
    local c = LP.Character
    if c then
        local root = c:FindFirstChild("HumanoidRootPart")
        if root then root.AssemblyLinearVelocity = _V3zero end
    end
    if dropBrainrotSetVisual then dropBrainrotSetVisual(false) end
    if mobSetDropBR then mobSetDropBR(false) end
end

function runDropBrainrot()
    if dropActive then return end
    local char = LP.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum then return end
    if dropMode == 1 then
        local speedH = 0
        if root then
            local vel = root.AssemblyLinearVelocity
            speedH = _V3new(vel.X, 0, vel.Z).Magnitude
        end
        local cooldown = (speedH > 5) and 0.6 or 0.25
        if _tick() - lastDropTime < cooldown then return end
        lastDropTime = _tick()
        dropActive = true
        if dropBrainrotSetVisual then dropBrainrotSetVisual(true) end
        if mobSetDropBR then mobSetDropBR(true) end
        local wasAutoBat = false
        if autoBatEnabled then
            wasAutoBat = true
            disableAutoBat()
            if autoBatSetVisual then autoBatSetVisual(false) end
            if mobSetAutoBat then mobSetAutoBat(false) end
        end
        local function finishDrop(threadRef)
            if threadRef and dropConnections then
                for i = #dropConnections, 1, -1 do
                    if dropConnections[i] == threadRef then
                        table.remove(dropConnections, i)
                        break
                    end
                end
            end
            dropActive = false
            local c = LP.Character
            if c then
                local r = c:FindFirstChild("HumanoidRootPart")
                local h = c:FindFirstChildOfClass("Humanoid")
                if r then
                    r.AssemblyLinearVelocity = _V3zero
                    r.AssemblyAngularVelocity = _V3zero
                    if r.Position.Y < -100 then
                        r.CFrame = _CFnew(r.Position.X, 5, r.Position.Z)
                    end
                    local rp = RaycastParams.new()
                    rp.FilterDescendantsInstances = {c}
                    rp.FilterType = Enum.RaycastFilterType.Exclude
                    local rr = workspace:Raycast(r.Position, _V3new(0, -2000, 0), rp)
                    if rr then
                        local off = (h and h.HipHeight or 2) + (r.Size.Y / 2)
                        r.CFrame = _CFnew(r.Position.X, rr.Position.Y + off, r.Position.Z)
                    end
                    if h and h.Health > 0 then h:ChangeState(Enum.HumanoidStateType.Running) end
                end
            end
            if wasAutoBat then
                enableAutoBat()
                if autoBatSetVisual then autoBatSetVisual(true) end
                if mobSetAutoBat then mobSetAutoBat(true) end
            end
            if dropBrainrotSetVisual then dropBrainrotSetVisual(false) end
            if mobSetDropBR then mobSetDropBR(false) end
        end
        local flingThread = nil
        flingThread = task.spawn(function()
            local startTime = _tick()
            while dropActive and (_tick() - startTime) < 0.25 do
                RunService.Heartbeat:Wait()
                local c = LP.Character
                local r = c and c:FindFirstChild("HumanoidRootPart")
                if not r then break end
                local vel = r.AssemblyLinearVelocity
                vel = _V3new(0, vel.Y, 0)
                r.AssemblyLinearVelocity = vel * 10000 + _V3new(0, 10000, 0)
                RunService.RenderStepped:Wait()
                if r and r.Parent then r.AssemblyLinearVelocity = vel end
                RunService.Stepped:Wait()
                if r and r.Parent then r.AssemblyLinearVelocity = vel + _V3new(0, 0.1, 0) end
            end
            finishDrop(flingThread)
        end)
        table.insert(dropConnections, flingThread)
        task.delay(0.35, function()
            if dropActive then finishDrop(flingThread) end
        end)
        return
    end
    dropActive = true
    if dropBrainrotSetVisual then dropBrainrotSetVisual(true) end
    if mobSetDropBR then mobSetDropBR(true) end
    local t0 = _tick()
    if _dropConn then _dropConn:Disconnect() end
    _dropConn = RunService.Heartbeat:Connect(function()
        local c = LP.Character
        local r = c and c:FindFirstChild("HumanoidRootPart")
        if not r then
            if _dropConn then _dropConn:Disconnect(); _dropConn = nil end
            dropActive = false
            if dropBrainrotSetVisual then dropBrainrotSetVisual(false) end
            if mobSetDropBR then mobSetDropBR(false) end
            return
        end
        if not dropActive then
            if _dropConn then _dropConn:Disconnect(); _dropConn = nil end
            if dropBrainrotSetVisual then dropBrainrotSetVisual(false) end
            if mobSetDropBR then mobSetDropBR(false) end
            return
        end
        if _tick() - t0 >= DROP_ASCEND_DURATION then
            if _dropConn then _dropConn:Disconnect(); _dropConn = nil end
            pcall(function()
                local rp = RaycastParams.new()
                rp.FilterDescendantsInstances = {c}
                rp.FilterType = Enum.RaycastFilterType.Exclude
                local rr = workspace:Raycast(r.Position, _V3new(0, -3000, 0), rp)
                if rr then
                    local hum2 = c:FindFirstChildOfClass("Humanoid")
                    local off = ((hum2 and hum2.HipHeight) or 2) + (r.Size.Y / 2)
                    r.CFrame = _CFnew(r.Position.X, rr.Position.Y + off, r.Position.Z)
                    r.AssemblyLinearVelocity = _V3zero
                    r.AssemblyAngularVelocity = _V3zero
                end
                if hum2 and hum2.Health > 0 then hum2:ChangeState(Enum.HumanoidStateType.Running) end
            end)
            dropActive = false
            if dropBrainrotSetVisual then dropBrainrotSetVisual(false) end
            if mobSetDropBR then mobSetDropBR(false) end
            return
        end
        local lv = r.AssemblyLinearVelocity
        r.AssemblyLinearVelocity = _V3new(lv.X, DROP_ASCEND_SPEED, lv.Z)
    end)
end

function executeDropWithToggle(setVisual)
    if dropActive then return end
    task.spawn(function()
        if setVisual then setVisual(true) end
        runDropBrainrot()
        while dropActive do task.wait() end
        task.wait(0.1)
        if setVisual then setVisual(false) end
    end)
end

function applyAntiLagDerender(obj)
    pcall(function()
        if obj:IsA("BasePart") then
            obj.Material = Enum.Material.Plastic
            obj.Reflectance = 0
            obj.CastShadow = false
        elseif obj:IsA("Decal") or obj:IsA("Texture") then obj.Transparency = 1
        elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") or obj:IsA("Fire") or obj:IsA("Smoke") or obj:IsA("Sparkles") then
            obj.Enabled = false
        elseif obj:IsA("AnimationController") or obj:IsA("Animator") then
            for _, t in ipairs(obj:GetPlayingAnimationTracks()) do pcall(function() t:Stop(0) end) end
        end
    end)
end

function enableAntiLag()
    antiLagEnabled = true
    task.spawn(function()
        local descs = workspace:GetDescendants()
        local i = 0
        local total = #descs
        while i < total and antiLagEnabled do
            for _ = 1, 200 do
                i = i + 1
                if i > total then break end
                applyAntiLagDerender(descs[i])
            end
            task.wait()
        end
    end)
    if antiLagDescConn then antiLagDescConn:Disconnect() end
    antiLagDescConn = workspace.DescendantAdded:Connect(function(obj)
        if antiLagEnabled then applyAntiLagDerender(obj) end
    end)
end

function disableAntiLag()
    antiLagEnabled = false
    if antiLagDescConn then antiLagDescConn:Disconnect(); antiLagDescConn = nil end
end

CUSTOM_FOV_BIND = "SakuraVsCustomFOV"

function enableCustomFov()
    local cam = workspace.CurrentCamera
    if cam and origFOV == nil then origFOV = cam.FieldOfView end
    fovEnabled = true
    if cam then
        pcall(function() cam.FieldOfViewMode = Enum.FieldOfViewMode.Diagonal end)
        pcall(function() cam.FieldOfView = fovValue end)
    end
    if customFovConn then customFovConn:Disconnect(); customFovConn = nil end
    pcall(function() RunService:UnbindFromRenderStep(CUSTOM_FOV_BIND) end)
    local prio = 200
    pcall(function() prio = Enum.RenderPriority.Camera.Value + 10 end)
    local ok = pcall(function()
        RunService:BindToRenderStep(CUSTOM_FOV_BIND, prio, function()
            if not fovEnabled then return end
            local c = workspace.CurrentCamera
            if c and c.FieldOfView ~= fovValue then
                c.FieldOfView = fovValue
            end
        end)
    end)
    if not ok then
        customFovConn = RunService.RenderStepped:Connect(function()
            if not fovEnabled then
                if customFovConn then customFovConn:Disconnect(); customFovConn = nil end
                return
            end
            local c = workspace.CurrentCamera
            if c then c.FieldOfView = fovValue end
        end)
    end
end

function disableCustomFov()
    fovEnabled = false
    pcall(function() RunService:UnbindFromRenderStep(CUSTOM_FOV_BIND) end)
    if customFovConn then customFovConn:Disconnect(); customFovConn = nil end
    local cam = workspace.CurrentCamera
    if cam then
        pcall(function() cam.FieldOfViewMode = Enum.FieldOfViewMode.Vertical end)
        pcall(function() cam.FieldOfView = origFOV or 70 end)
    end
end

function applyStretchFOV(val)
    local cam = workspace.CurrentCamera
    if cam then pcall(function() cam.FieldOfView = val end) end
end

function enableStretch()
    if stretchConn then return end
    stretchEnabled = true
    local cam = workspace.CurrentCamera
    if not cam then return end
    origFOV = cam.FieldOfView or 70
    applyStretchFOV(stretchFOV)
    stretchConn = RunService.RenderStepped:Connect(function()
        if not stretchEnabled then
            stretchConn:Disconnect()
            stretchConn = nil
            return
        end
        local c = workspace.CurrentCamera
        if c then c.CFrame = c.CFrame * _CFnew(0,0,0,1,0,0,0,0.7,0,0,0,1) end
    end)
    if stretchFovConn then stretchFovConn:Disconnect() end
    stretchFovConn = RunService.RenderStepped:Connect(function()
        if stretchEnabled then applyStretchFOV(stretchFOV)
        else stretchFovConn:Disconnect(); stretchFovConn = nil end
    end)
end

function disableStretch()
    stretchEnabled = false
    if stretchConn then stretchConn:Disconnect(); stretchConn = nil end
    if stretchFovConn then stretchFovConn:Disconnect(); stretchFovConn = nil end
    local cam = workspace.CurrentCamera
    if cam then pcall(function() cam.FieldOfView = origFOV or 70 end) end
end

local function saveLightingState()
    if _originalLighting then return end
    _originalLighting = {
        Brightness = Lighting.Brightness,
        ClockTime = Lighting.ClockTime,
        OutdoorAmbient = Lighting.OutdoorAmbient,
        GlobalShadows = Lighting.GlobalShadows,
        FogEnd = Lighting.FogEnd,
        FogStart = Lighting.FogStart,
        FogColor = Lighting.FogColor,
        Ambient = Lighting.Ambient,
        ColorCorrection = nil,
        Bloom = nil,
    }
    for _, e in ipairs(Lighting:GetChildren()) do
        if e:IsA("ColorCorrectionEffect") then
            _originalLighting.ColorCorrection = {
                Enabled = e.Enabled,
                Brightness = e.Brightness,
                Contrast = e.Contrast,
                Saturation = e.Saturation,
                TintColor = e.TintColor,
            }
        elseif e:IsA("BloomEffect") then
            _originalLighting.Bloom = {
                Enabled = e.Enabled,
                Intensity = e.Intensity,
                Size = e.Size,
                Threshold = e.Threshold,
            }
        end
    end
end

local function restoreLightingState()
    if not _originalLighting then return end
    local old = _originalLighting
    Lighting.Brightness = old.Brightness
    Lighting.ClockTime = old.ClockTime
    Lighting.OutdoorAmbient = old.OutdoorAmbient
    Lighting.GlobalShadows = old.GlobalShadows
    Lighting.FogEnd = old.FogEnd
    Lighting.FogStart = old.FogStart
    Lighting.FogColor = old.FogColor
    Lighting.Ambient = old.Ambient
    if old.ColorCorrection then
        local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
        if cc then
            cc.Enabled = old.ColorCorrection.Enabled
            cc.Brightness = old.ColorCorrection.Brightness
            cc.Contrast = old.ColorCorrection.Contrast
            cc.Saturation = old.ColorCorrection.Saturation
            cc.TintColor = old.ColorCorrection.TintColor
        end
    end
    if old.Bloom then
        local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
        if bloom then
            bloom.Enabled = old.Bloom.Enabled
            bloom.Intensity = old.Bloom.Intensity
            bloom.Size = old.Bloom.Size
            bloom.Threshold = old.Bloom.Threshold
        end
    end
end

SKY_PRESETS_LIST = {"Off","Night","Aurora","Sunset","Galaxy","Cyber","Sakura","Pink Night","Blood Moon","Emerald Dawn","Volcanic","Arctic","Midnight Ocean","Vaporwave","Toxic","Solar Eclipse","Hellscape","Heaven","Storm","Sunrise","Deep Space","Lavender Dream","Inferno","Mint Sky"}

SKY_PRESETS = {
    ["Off"]={kind="off"},
    ["Night"]={clock=22,brightness=2,ambient={110,100,130},outAmb={120,110,140},sky={stars=4000,moon=18,sun=0,moonTex=true},atm={dens=0.45,color={120,60,180},decay={60,20,100},glare=0.5,haze=1.2}},
    ["Aurora"]={clock=14,brightness=3,ambient={150,120,150},outAmb={160,130,150},atm={dens=0.55,color={255,80,200},decay={255,20,150},glare=2.5,haze=3},clouds={cover=0.7,dens=0.7,color={255,240,250}}},
    ["Sunset"]={clock=17.2,brightness=2.5,ambient={170,120,100},outAmb={180,130,110},sky={stars=0,sun=25,moon=0},atm={dens=0.5,color={255,130,60},decay={255,80,30},glare=2,haze=2.5},clouds={cover=0.55,dens=0.55,color={255,200,140}}},
    ["Galaxy"]={clock=0,brightness=1.5,ambient={70,60,100},outAmb={80,70,110},sky={stars=10000,moon=30,sun=0},atm={dens=0.15,color={40,20,80},decay={20,10,50},glare=0.3,haze=0.5}},
    ["Cyber"]={clock=21,brightness=2.2,ambient={90,130,170},outAmb={100,140,180},sky={stars=2000,moon=12},atm={dens=0.4,color={0,200,255},decay={150,0,255},glare=2,haze=2},clouds={cover=0.4,dens=0.6,color={100,200,255}}},
    ["Sakura"]={clock=11,brightness=3.5,ambient={170,150,160},outAmb={180,160,170},sky={sun=8},atm={dens=0.3,color={255,200,220},decay={255,170,200},glare=1,haze=1.5},clouds={cover=0.6,dens=0.4,color={255,250,252}}},
    ["Pink Night"]={clock=23,brightness=2.2,ambient={120,60,110},outAmb={140,70,120},sky={stars=5000,moon=22,sun=0,moonTex=true},atm={dens=0.5,color={255,80,180},decay={140,30,100},glare=0.7,haze=1.4},clouds={cover=0.3,dens=0.5,color={180,90,150}}},
    ["Blood Moon"]={clock=22.5,brightness=1.6,ambient={130,40,40},outAmb={150,50,50},sky={stars=1500,moon=28,sun=0,moonTex=true},atm={dens=0.6,color={220,30,30},decay={120,10,10},glare=1.4,haze=2},clouds={cover=0.5,dens=0.7,color={120,30,30}}},
    ["Emerald Dawn"]={clock=6.5,brightness=2.8,ambient={130,170,140},outAmb={140,180,150},sky={sun=18,moon=0,stars=0},atm={dens=0.4,color={80,200,140},decay={40,150,90},glare=1.8,haze=2.2},clouds={cover=0.5,dens=0.5,color={200,255,220}}},
    ["Volcanic"]={clock=19,brightness=2,ambient={180,80,40},outAmb={200,90,50},sky={stars=200,sun=12,moon=0},atm={dens=0.75,color={255,60,0},decay={180,20,0},glare=3,haze=3.5},clouds={cover=0.8,dens=0.9,color={120,40,20}}},
    ["Arctic"]={clock=9,brightness=3.2,ambient={200,220,235},outAmb={210,230,245},sky={sun=10,stars=0,moon=0},atm={dens=0.3,color={180,220,255},decay={140,200,240},glare=1.5,haze=1.8},clouds={cover=0.7,dens=0.6,color={250,253,255}}},
    ["Midnight Ocean"]={clock=1.5,brightness=1.7,ambient={60,90,130},outAmb={70,100,140},sky={stars=6000,moon=24,sun=0,moonTex=true},atm={dens=0.5,color={20,60,140},decay={10,30,90},glare=0.6,haze=1.5}},
    ["Vaporwave"]={clock=19.5,brightness=2.4,ambient={180,120,200},outAmb={190,130,210},sky={stars=1000,moon=14},atm={dens=0.45,color={255,100,220},decay={120,60,255},glare=2.2,haze=2.4},clouds={cover=0.55,dens=0.55,color={200,150,255}}},
    ["Toxic"]={clock=13,brightness=2.5,ambient={140,180,80},outAmb={150,190,90},atm={dens=0.55,color={100,220,40},decay={60,150,20},glare=1.8,haze=2.6},clouds={cover=0.65,dens=0.7,color={180,255,120}}},
    ["Solar Eclipse"]={clock=12,brightness=0.9,ambient={50,40,60},outAmb={60,50,70},sky={stars=3500,sun=22,moon=0},atm={dens=0.5,color={255,140,40},decay={30,20,40},glare=2.8,haze=1.8}},
    ["Hellscape"]={clock=18,brightness=1.8,ambient={200,60,30},outAmb={220,70,40},sky={stars=100,sun=30,moon=0},atm={dens=0.85,color={255,30,0},decay={120,0,0},glare=3.5,haze=4},clouds={cover=0.95,dens=0.95,color={80,20,10}}},
    ["Heaven"]={clock=12,brightness=4,ambient={240,235,210},outAmb={250,245,220},sky={sun=16,moon=0,stars=0},atm={dens=0.25,color={255,250,220},decay={255,240,200},glare=3,haze=1.5},clouds={cover=0.85,dens=0.5,color={255,255,255}}},
    ["Storm"]={clock=15,brightness=1.4,ambient={90,90,110},outAmb={100,100,120},sky={stars=0,sun=6,moon=0},atm={dens=0.65,color={80,90,120},decay={40,50,80},glare=0.5,haze=3},clouds={cover=0.95,dens=0.95,color={60,65,80}}},
    ["Sunrise"]={clock=6.2,brightness=2.8,ambient={220,180,130},outAmb={230,190,140},sky={sun=22,stars=0,moon=0},atm={dens=0.45,color={255,180,100},decay={255,140,80},glare=2.4,haze=2.2},clouds={cover=0.4,dens=0.4,color={255,220,180}}},
    ["Deep Space"]={clock=0,brightness=1,ambient={30,25,50},outAmb={40,35,60},sky={stars=15000,moon=0,sun=0},atm={dens=0.08,color={15,5,40},decay={5,0,20},glare=0.2,haze=0.3}},
    ["Lavender Dream"]={clock=18.5,brightness=2.6,ambient={180,160,220},outAmb={190,170,230},sky={stars=800,moon=16,sun=0},atm={dens=0.4,color={200,160,255},decay={160,120,220},glare=1.4,haze=1.8},clouds={cover=0.55,dens=0.5,color={220,200,255}}},
    ["Inferno"]={clock=17.5,brightness=2.2,ambient={220,100,40},outAmb={235,110,50},sky={sun=26,moon=0,stars=0},atm={dens=0.6,color={255,90,20},decay={200,40,0},glare=3,haze=3.2},clouds={cover=0.7,dens=0.7,color={200,80,40}}},
    ["Mint Sky"]={clock=10,brightness=3.2,ambient={180,230,210},outAmb={190,240,220},sky={sun=10},atm={dens=0.32,color={150,255,210},decay={100,220,180},glare=1.6,haze=1.6},clouds={cover=0.55,dens=0.45,color={240,255,250}}},
}

local function _vC3(t) return Color3.fromRGB(t[1], t[2], t[3]) end

function _v4mpClearSky()
    for _, child in ipairs(Lighting:GetChildren()) do
        if child:GetAttribute("_AdaptDuelsSky") then
            pcall(function() child:Destroy() end)
        end
    end
    local terrain = workspace:FindFirstChildOfClass("Terrain")
    if terrain then
        for _, child in ipairs(terrain:GetChildren()) do
            if child:GetAttribute("_AdaptDuelsSky") then
                pcall(function() child:Destroy() end)
            end
        end
    end
end

function applyCustomSky(mode)
    _v4mpClearSky()
    local preset = SKY_PRESETS[mode]
    if not preset or preset.kind == "off" then
        Lighting.ClockTime = 14
        Lighting.Brightness = 2
        Lighting.OutdoorAmbient = Color3.fromRGB(127,127,127)
        Lighting.Ambient = Color3.fromRGB(127,127,127)
        Lighting.FogEnd = 100000
        Lighting.GlobalShadows = true
        skyTheme = "Off"
        return
    end
    Lighting.FogStart = 0
    Lighting.FogEnd = 100000
    Lighting.FogColor = Color3.fromRGB(200,200,200)
    Lighting.ColorShift_Top = Color3.fromRGB(0,0,0)
    Lighting.ColorShift_Bottom = Color3.fromRGB(0,0,0)
    Lighting.GlobalShadows = true
    Lighting.ClockTime = preset.clock or 14
    Lighting.Brightness = preset.brightness or 2
    if preset.outAmb then Lighting.OutdoorAmbient = _vC3(preset.outAmb) end
    if preset.ambient then Lighting.Ambient = _vC3(preset.ambient) end
    if preset.sky then
        local skyInst = Instance.new("Sky")
        skyInst:SetAttribute("_AdaptDuelsSky", true)
        if preset.sky.stars then skyInst.StarCount = preset.sky.stars end
        if preset.sky.moon then skyInst.MoonAngularSize = preset.sky.moon end
        if preset.sky.sun then skyInst.SunAngularSize = preset.sky.sun end
        if preset.sky.moonTex then skyInst.MoonTextureId = "rbxasset://sky/moon.jpg" end
        skyInst.Parent = Lighting
    end
    if preset.atm then
        local atm = Instance.new("Atmosphere")
        atm:SetAttribute("_AdaptDuelsSky", true)
        atm.Density = preset.atm.dens or 0.3
        atm.Color = _vC3(preset.atm.color)
        atm.Decay = _vC3(preset.atm.decay)
        atm.Glare = preset.atm.glare or 1
        atm.Haze = preset.atm.haze or 1
        atm.Parent = Lighting
    end
    local terrain = workspace:FindFirstChildOfClass("Terrain")
    if preset.clouds and terrain then
        local clouds = Instance.new("Clouds")
        clouds:SetAttribute("_AdaptDuelsSky", true)
        clouds.Cover = preset.clouds.cover or 0.5
        clouds.Density = preset.clouds.dens or 0.5
        clouds.Color = _vC3(preset.clouds.color)
        clouds.Parent = terrain
    end
    skyTheme = mode
end

local function applyNeonWeather()
    if not neonWeatherEnabled then
        restoreLightingState()
        return
    end
    if not _originalLighting then saveLightingState() end
    Lighting.Brightness = 3.5
    Lighting.ClockTime = 20
    Lighting.OutdoorAmbient = Color3.fromRGB(20, 40, 80)
    Lighting.GlobalShadows = false
    Lighting.FogEnd = 300
    Lighting.FogStart = 0
    Lighting.FogColor = Color3.fromRGB(200, 200, 200)
    Lighting.Ambient = Color3.fromRGB(40, 40, 40)
    local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
    if not cc then
        cc = Instance.new("ColorCorrectionEffect")
        cc.Parent = Lighting
    end
    cc.Enabled = true
    cc.Brightness = 0.2
    cc.Contrast = 0.15
    cc.Saturation = 0.15
    cc.TintColor = Color3.fromRGB(180, 180, 190)
    local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
    if not bloom then
        bloom = Instance.new("BloomEffect")
        bloom.Parent = Lighting
    end
    bloom.Enabled = true
    bloom.Intensity = 0.6
    bloom.Size = 25
    bloom.Threshold = 0.8
end

function toggleNeonWeather(state)
    if state == nil then
        neonWeatherEnabled = not neonWeatherEnabled
    else
        neonWeatherEnabled = state
    end
    applyNeonWeather()
    if setNeonWeatherVisual then setNeonWeatherVisual(neonWeatherEnabled) end
end

function paintFloatingBtn(btnFrame, active)
    if not btnFrame then return end
    local bg = btnFrame:FindFirstChild("BtnGrad")
    local label = btnFrame:FindFirstChild("TextLabel")
    local stroke = btnFrame:FindFirstChildOfClass("UIStroke")
    local assetBg = btnFrame:FindFirstChild("BtnAssetBg")
    local assetOv = btnFrame:FindFirstChild("BtnAssetOverlay")
    local WHITE = Color3.fromRGB(255, 255, 255)
    -- Theme-aware colors (Button Color selector)
    local theme = getThemeColor() or Color3.fromRGB(255, 140, 0)
    local COLOR_ON = theme
    local COLOR_OFF = Color3.new(
        math.clamp(theme.R * 0.28, 0, 1),
        math.clamp(theme.G * 0.28, 0, 1),
        math.clamp(theme.B * 0.28, 0, 1)
    )
    local COLOR_GLOW = Color3.new(
        math.clamp(theme.R * 1.25 + 0.05, 0, 1),
        math.clamp(theme.G * 1.25 + 0.05, 0, 1),
        math.clamp(theme.B * 1.25 + 0.05, 0, 1)
    )
    local COLOR_OFF_TEXT = Color3.new(
        math.clamp(theme.R * 0.85 + 0.15, 0, 1),
        math.clamp(theme.G * 0.85 + 0.15, 0, 1),
        math.clamp(theme.B * 0.85 + 0.15, 0, 1)
    )

    if assetBg then assetBg.Visible = false end
    if assetOv then assetOv.Visible = false end
    if bg then bg.Enabled = false end

    if active then
        -- ON: theme fill + thick glow stroke
        btnFrame.BackgroundColor3 = COLOR_ON
        btnFrame.BackgroundTransparency = 0
        if label then
            label.TextColor3 = WHITE
            label.TextTransparency = 0
            label.Visible = true
            label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
            label.TextStrokeTransparency = 0.25
            label.ZIndex = math.max((btnFrame.ZIndex or 1) + 5, 60)
        end
        if btnFrame:IsA("TextButton") then
            btnFrame.TextTransparency = 1
        end
        if stroke then
            stroke.Color = COLOR_GLOW
            stroke.Thickness = 2.6
            stroke.Transparency = 0
        end
    else
        -- OFF: dimmed theme color
        btnFrame.BackgroundColor3 = COLOR_OFF
        btnFrame.BackgroundTransparency = 0.25
        if label then
            label.TextColor3 = COLOR_OFF_TEXT
            label.TextTransparency = 0.05
            label.Visible = true
            label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
            label.TextStrokeTransparency = 0.4
            label.ZIndex = math.max((btnFrame.ZIndex or 1) + 5, 60)
        end
        if btnFrame:IsA("TextButton") then
            btnFrame.TextTransparency = 1
        end
        if stroke then
            stroke.Color = COLOR_GLOW
            stroke.Thickness = 1.3
            stroke.Transparency = 0.35
        end
    end
end


function applyFloatingButtonScale()
    for _, uiScale in ipairs(_floatingUIScales) do
        if uiScale and uiScale.Parent then
            uiScale.Scale = floatingButtonScale
        end
    end
end

local function drag(f)
    local dn, ds, sp, di = false, nil, nil, nil
    local endConn = nil
    local function stopDrag()
        if dn then
            -- Persist dragged frame position (progress bar / main) to config
            if f == pbFrame then
                savedProgressBarPos = {
                    XScale = f.Position.X.Scale, XOffset = f.Position.X.Offset,
                    YScale = f.Position.Y.Scale, YOffset = f.Position.Y.Offset
                }
            end
            pcall(saveAllSettings)
        end
        dn = false
        di = nil
        if endConn then
            endConn:Disconnect()
            endConn = nil
        end
    end
    f.InputBegan:Connect(function(i)
        if uiLocked then return end
        if _isDraggingButton then return end
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dn = true; ds = i.Position; sp = f.Position
            if endConn then endConn:Disconnect() end
            endConn = i.Changed:Connect(function()
                if i.UserInputState == Enum.UserInputState.End then stopDrag() end
            end)
        end
    end)
    f.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            stopDrag()
        end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            stopDrag()
        end
    end)
    f.InputChanged:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then di = i end
    end)
    UIS.InputChanged:Connect(function(i)
        if i == di and dn then
            if uiLocked then stopDrag(); return end
            if _isDraggingButton then return end
            if not ds or not sp then return end
            local nX = sp.X.Offset + (i.Position.X - ds.X)
            local nY = sp.Y.Offset + (i.Position.Y - ds.Y)
            f.Position = UDim2.new(sp.X.Scale, nX, sp.Y.Scale, nY)
        end
    end)
end

function setupMovementAndIndicators(char)
    if steppedConn then steppedConn:Disconnect(); steppedConn = nil end
    if movementLoop then movementLoop:Disconnect(); movementLoop = nil end

    local ccAcc = 0
    steppedConn = RunService.Heartbeat:Connect(function(dt)
        ccAcc = ccAcc + dt
        if ccAcc < 0.05 then return end
        ccAcc = 0
        local plist = _GetPlayersCached()
        for i = 1, #plist do
            local p = plist[i]
            if p ~= LP then
                local ch = p.Character
                if ch then
                    local parts = ch:GetChildren()
                    for j = 1, #parts do
                        local part = parts[j]
                        if part:IsA("BasePart") and part.CanCollide then
                            part.CanCollide = false
                        end
                    end
                end
            end
        end
    end)

    movementLoop = RunService.RenderStepped:Connect(function()
        local char2 = LP.Character
        if not char2 then return end
        local hum = char2:FindFirstChildOfClass("Humanoid")
        local hrp = char2:FindFirstChild("HumanoidRootPart")
        if not hum or not hrp then return end

        local bbOn = (BatBypassV2 and BatBypassV2.Enabled) == true
        if not autoBatEnabled and not autoLeftEnabled and not autoRightEnabled
           and not autoBatV2Enabled and not batDesyncTpEnabled and not bbOn then
            if _isRagdollState(hum) then
                lastMoveDir = _V3zero
            else
                local md = hum.MoveDirection
                local spd = getActiveMoveSpeed()
                local dir = nil
                if md.Magnitude > 0 then
                    lastMoveDir = md
                    dir = md
                elseif lastMoveDir.Magnitude > 0 then
                    for key in pairs(MOVE_KEYS) do
                        if UIS:IsKeyDown(key) then dir = lastMoveDir; break end
                    end
                end
                _applyVelocitySpeed(dir, spd, hrp)
            end
        end

        if speedLabel then
            local v = hrp.AssemblyLinearVelocity
            local s = _sqrt(v.X*v.X + v.Z*v.Z)
            if s < 0.05 then s = 0 end
            local target = getActiveMoveSpeed()
            -- Pet tutarken hedef hızı da göster (29 ayarlıysa 29 görünsün)
            if CarrySystem and CarrySystem:isCarrying() then
                speedLabel.Text = string.format("Hız: %.1f / %d", s, _floor(target + 0.5))
            else
                speedLabel.Text = "Hız: " .. string.format("%.1f", s)
            end
        end
    end)
    setupSpeedIndicator(char)
    startEnemySpeed()
end

function toggleLockUI(state)
    if state == nil then uiLocked = not uiLocked else uiLocked = state end
    if uiLocked and editModeEnabled then
        editModeEnabled = false
        if setEditModeVisual then setEditModeVisual(false) end
    end
    if setLockUIVisual then setLockUIVisual(uiLocked) end
end

function toggleEditMode(state)
    if state == nil then state = not editModeEnabled end
    if state and uiLocked then state = false end
    editModeEnabled = state
    if setEditModeVisual then setEditModeVisual(editModeEnabled) end
end

function disableAllAimbots()
    stopSpectrumBypassAimbot()
    if autoBatEnabled then
        disableAutoBat()
        if autoBatSetVisual then autoBatSetVisual(false) end
        if mobSetAutoBat then mobSetAutoBat(false) end
    end
    if batDesyncTpEnabled then stopBatDesyncTp() end
    if autoBatV2Enabled then
        disableBatV2()
        if autoBatV2SetVisual then autoBatV2SetVisual(false) end
        if batV2FloatingButton then
            local btnFrame = batV2FloatingButton:FindFirstChild("Frame")
            if btnFrame then paintFloatingBtn(btnFrame, false) end
        end
    end
end

function stopAllBackgroundTasks()
    if movementLoop then movementLoop:Disconnect(); movementLoop = nil end
    if steppedConn then steppedConn:Disconnect(); steppedConn = nil end
    stopEnemySpeed()
    if stretchEnabled then disableStretch() end
    if stretchConn then stretchConn:Disconnect(); stretchConn = nil end
    if stretchFovConn then stretchFovConn:Disconnect(); stretchFovConn = nil end
    if AntiRagdollV1.isRunning() then AntiRagdollV1.stop() end
    if AntiRagdollV2.Enabled then stopAntiRagdollV2() end
    if antiDieEnabled then AntiDieModule.stop() end
    if antiFlingEnabled then AntiFlingShieldModule.stop() end
    stopBatCounter()
    stopBatCounterV2()
    stopMedusaCounter()
    stopAutoSteal()
    disableAutoBat()
    if batDesyncTpEnabled then stopBatDesyncTp() end
    if autoBatV2Enabled then disableBatV2() end
    stopAutoLeft()
    stopAutoRight()
    if unwalkEnabled and not _tpBatUnwalkForced then stopUnwalk() end
    if antiLagEnabled then disableAntiLag() end
    if espEnabled then toggleESP(false) end
    if dropActive then stopDropBrainrot() end
    if bodyLockEnabled then stopBodyLock() end
    _blSuppressCount = 0
    _blWasEnabled = false
    if _blRestoreTimer then
        pcall(task.cancel, _blRestoreTimer)
        _blRestoreTimer = nil
    end
    if _bodyLockConn then
        _bodyLockConn:Disconnect()
        _bodyLockConn = nil
    end
    for _, t in ipairs(dropConnections) do
        if type(t) == "thread" then pcall(task.cancel, t)
        elseif type(t) == "RBXScriptConnection" then pcall(t.Disconnect, t) end
    end
    dropConnections = {}
    dropActive = false
    alPhase = 1
    arPhase = 1
    lastDropTime = 0
    medusaDebounce = false
    medusaLastUsed = 0
end

function buildConfigTable()
    local config = {
        normalSpeed = NS,
        carrySpeed = CS,
        laggerSpeed1 = LAGGER_SPEED,
        laggerSpeed2 = LAGGER_CARRY_SPEED,
        stealRadius = CONFIG.STEAL_RANGE,
        antiRagdollMode = antiRagdollMode,
        antiDieEnabled = antiDieEnabled,
        autoSteal = CONFIG.AUTO_STEAL_ENABLED,
        medusaCounter = medusaCounterEnabled,
        batCounter = batCounterEnabled,
        batCounterV2 = batCounterV2Enabled,
        batCounterV3Stud = tonumber(BAT_COUNTER_V2_TOUCH_DIST) or 2.5,
        infiniteJump = (InfiniteJump and InfiniteJump.isRunning and InfiniteJump.isRunning()) == true,
        infJumpMode = infJumpMode or "HOLD",
        autoStealVariant = autoStealVariant or 1,
        customToolsEnabled = customToolsEnabled == true,
        katanaSkinEnabled = katanaSkinEnabled == true,
        katanaSkinColorMode = katanaSkinColorMode or "Red",
        discordTextColorTheme = discordTextColorTheme or "White",
        minecraftBatSkinEnabled = minecraftBatSkinEnabled == true,
        medusaSkinChoice = medusaSkinChoice or (_G.RivalMedusaSkin or "Default"),
        minecraftBatSkinColorMode = minecraftBatSkinColorMode or "Default",
        antiBatEnabled = antiBatEnabled,
        antiBatPanelPos = antiBatPanelPos,
        antiBatPanelCollapsed = antiBatPanelCollapsed == true,
        kickWarningEnabled = kickWarningEnabled,
        laggerToggled = laggerToggled,
        laggerCarryToggled = laggerCarryToggled,
        carryMode = speedMode,
        batAimbotSpeed = BAT_AIMBOT_SPEED,
        batAimbotMode = batAimbotMode or "Normal",
        autoBatEnabled = autoBatEnabled == true,
        bypassAimbotSpeed = BYPASS_AIMBOT_SPEED,
        dropMode = dropMode,
        stretchEnabled = stretchEnabled,
        stretchFOV = stretchFOV,
        fovEnabled = fovEnabled,
        fovValue = fovValue,
        uiScale = uiScaleValue,
        stealBarScale = stealBarScale or 100,
        antiAimbot = antiAimbotEnabled == true,
        -- always persist mode explicitly (V2 must survive rejoin)
        antiAimbotMode = (function()
            local m = tostring(antiAimbotMode or "V1"):upper():gsub("%s+", "")
            if m == "V2" or m == "2" or m == "BYPASS" then return "V2" end
            return "V1"
        end)(),
        AntiAimbotMode = (function()
            local m = tostring(antiAimbotMode or "V1"):upper():gsub("%s+", "")
            if m == "V2" or m == "2" or m == "BYPASS" then return "V2" end
            return "V1"
        end)(),
        taunt = tauntEnabled == true,
        spinEnabled = spinEnabled == true,
        spinSpeed = tonumber(spinSpeed) or 0.35,
        spinSpeedName = tostring(spinSpeedName or "Normal"),
        animPack = currentAnimPack,
        espEnabled = espEnabled,
        antiLag = antiLagEnabled,
        unwalk = unwalkEnabled,
        autoTpDownEnabled = autoTpDownEnabled,
        autoTpDownRadius = autoTpDownRadius,
        tpBatEnabled = batDesyncTpEnabled,
        batTPVersion = batTPVersion,
        tpBatV2Distance = (rawget(_G, "__tpBatV2Distance") or 8),
        neonWeather = neonWeatherEnabled,
        skyTheme = skyTheme,
        autoBatV2Enabled = autoBatV2Enabled,
        mobileButtonPositions = savedButtonPositions,
        dropBrainrotKey = {kb = KB.DropBrainrot.kb and KB.DropBrainrot.kb.Name, gp = KB.DropBrainrot.gp and KB.DropBrainrot.gp.Name},
        autoLeftKey = {kb = KB.AutoLeft.kb and KB.AutoLeft.kb.Name, gp = KB.AutoLeft.gp and KB.AutoLeft.gp.Name},
        autoRightKey = {kb = KB.AutoRight.kb and KB.AutoRight.kb.Name, gp = KB.AutoRight.gp and KB.AutoRight.gp.Name},
        autoBatKey = {kb = KB.AutoBat.kb and KB.AutoBat.kb.Name, gp = KB.AutoBat.gp and KB.AutoBat.gp.Name},
        antiBatKey = {kb = KB.AntiBat.kb and KB.AntiBat.kb.Name, gp = KB.AntiBat.gp and KB.AntiBat.gp.Name},
        tpFloorKey = {kb = KB.TPFloor.kb and KB.TPFloor.kb.Name, gp = KB.TPFloor.gp and KB.TPFloor.gp.Name},
        carryToggleKey = {kb = KB.CarryToggle.kb and KB.CarryToggle.kb.Name, gp = KB.CarryToggle.gp and KB.CarryToggle.gp.Name},
        laggerModeKey = {kb = KB.LaggerMode.kb and KB.LaggerMode.kb.Name, gp = KB.LaggerMode.gp and KB.LaggerMode.gp.Name},
        tpBatKey = {kb = KB.TPBat.kb and KB.TPBat.kb.Name, gp = KB.TPBat.gp and KB.TPBat.gp.Name},
        batV2Key = {kb = KB.BatV2.kb and KB.BatV2.kb.Name, gp = KB.BatV2.gp and KB.BatV2.gp.Name},
        instaResetKey = {kb = KB.InstaReset.kb and KB.InstaReset.kb.Name, gp = KB.InstaReset.gp and KB.InstaReset.gp.Name},
        tpBatFloatingPos = tpBatFloatingPos,
        batV2FloatingPos = batV2FloatingPos,
        instaResetFloatingPos = instaResetFloatingPos,
        antiAimbotFloatingPos = antiAimbotFloatingPos,
        bodyLockEnabled = bodyLockEnabled,
        bodyLockRange = bodyLockRange,
        progressBarPos = savedProgressBarPos,
        lockUI = uiLocked,
        editMode = editModeEnabled,
        backgroundIndex = backgroundIndex,
        backgroundImageTransparency = backgroundImageTransparency,
        backgroundImages = backgroundImages,
        backgroundIndex = backgroundIndex,
        stealBarBackgroundIndex = stealBarBackgroundIndex,
        floatingButtonScale = floatingButtonScale,
        floatingButtonShape = floatingButtonShape,
        outfitIndex = currentOutfitIndex,
        themeColor = currentColorTheme,
        espColorTheme = espColorTheme or "Mavi",
        useCarrySystem = useCarrySystem,
        autoCarrySpeedEnabled = autoCarrySpeedEnabled == true,
        carrySysNormal = CarrySystem.normalSpeed,
        carrySysCarry = CarrySystem.carrySpeed,
        carrySysLagger = CarrySystem.laggerSpeed,
        carrySysLaggerCarry = CarrySystem.laggerCarrySpeed,
        carrySysSoftStealSpeed = CarrySystem.softStealSpeed,
        carrySysSoftStealRadius = CarrySystem.softStealRadius,
        autoCarryMode = CarrySystem.autoCarryMode or "WHEN NEAR",
    }
    if pbFrame then
        config.progressBarPos = {
            XScale = pbFrame.Position.X.Scale,
            XOffset = pbFrame.Position.X.Offset,
            YScale = pbFrame.Position.Y.Scale,
            YOffset = pbFrame.Position.Y.Offset
        }
    end
    if MobilePanel and MobilePanel:FindFirstChild("FloatingPanel") then
        local container = MobilePanel:FindFirstChild("FloatingPanel")
        config.mobilePanelPos = {
            XScale = container.Position.X.Scale,
            XOffset = container.Position.X.Offset,
            YScale = container.Position.Y.Scale,
            YOffset = container.Position.Y.Offset
        }
        local btnContainer = container:FindFirstChild("ButtonsContainer")
        if btnContainer then
            local livePos = {}
            for _, child in ipairs(btnContainer:GetChildren()) do
                if child:IsA("TextButton") then
                    livePos[child.Name] = {
                        X = child.Position.X.Offset,
                        Y = child.Position.Y.Offset
                    }
                end
            end
            if next(livePos) then
                config.mobileButtonPositions = livePos
                savedButtonPositions = livePos
            end
        end
    end
    -- Keep floating button positions from live frames if present
    if tpBatFloatingButton then
        local fr = tpBatFloatingButton:FindFirstChild("Frame")
        if fr then
            config.tpBatFloatingPos = {
                XScale = fr.Position.X.Scale, XOffset = fr.Position.X.Offset,
                YScale = fr.Position.Y.Scale, YOffset = fr.Position.Y.Offset
            }
            tpBatFloatingPos = config.tpBatFloatingPos
        end
    end
    if batV2FloatingButton then
        local fr = batV2FloatingButton:FindFirstChild("Frame")
        if fr then
            config.batV2FloatingPos = {
                XScale = fr.Position.X.Scale, XOffset = fr.Position.X.Offset,
                YScale = fr.Position.Y.Scale, YOffset = fr.Position.Y.Offset
            }
            batV2FloatingPos = config.batV2FloatingPos
        end
    end
    if instaResetFloatingButton then
        local fr = instaResetFloatingButton:FindFirstChild("Frame")
        if fr then
            config.instaResetFloatingPos = {
                XScale = fr.Position.X.Scale, XOffset = fr.Position.X.Offset,
                YScale = fr.Position.Y.Scale, YOffset = fr.Position.Y.Offset
            }
            instaResetFloatingPos = config.instaResetFloatingPos
        end
    end
    if antiAimbotFloatingButton then
        local fr = antiAimbotFloatingButton:FindFirstChild("Frame")
        if fr then
            config.antiAimbotFloatingPos = {
                XScale = fr.Position.X.Scale, XOffset = fr.Position.X.Offset,
                YScale = fr.Position.Y.Scale, YOffset = fr.Position.Y.Offset
            }
            antiAimbotFloatingPos = config.antiAimbotFloatingPos
        end
    end
    -- Ping Lagger settings (persist power / interval / etc.)
    do
        local spl = rawget(_G, "SakuraPingLagger") or SakuraPingLagger
        if spl and spl.cfg then
        local cfg = spl.cfg
        config.pingLaggerPower = tonumber(cfg.power) or 100000
        config.pingLaggerInterval = tonumber(cfg.interval) or 0.125
        config.pingLaggerKeybindKb = tostring(cfg.keybindKb or "F")
        config.pingLaggerKeybindGp = tostring(cfg.keybindGp or "ButtonY")
        config.pingLaggerAutoActivate = cfg.autoActivate == true
        config.pingLaggerAntiLag = cfg.antiLag == true
        config.pingLaggerUiSize = tonumber(cfg.uiSize) or 100
        end
    end
    return config
end

function saveAllSettings()
    if _isResetting or _isLoading then return true end
    local okBuild, config = pcall(buildConfigTable)
    if not okBuild or not config then
        warn("[Sakura.vs] saveAllSettings buildConfigTable failed:", config)
        return false
    end
    local okJson, json = pcall(function() return HS:JSONEncode(config) end)
    if not okJson or type(json) ~= "string" then
        warn("[Sakura.vs] saveAllSettings JSONEncode failed:", json)
        return false
    end
    if json == _lastSavedJSON then return true end
    if type(writefile) ~= "function" then
        warn("[Sakura.vs] writefile not available — config cannot be saved")
        return false
    end
    local success, err = pcall(function() writefile(CONFIG_FILE, json) end)
    if success then
        _lastSavedJSON = json
    else
        warn("[Sakura.vs] writefile failed:", err)
    end
    return success
end

function loadAllSettings()
    if not isfile or not isfile(CONFIG_FILE) then return false end
    local success, data = pcall(function() return HS:JSONDecode(readfile(CONFIG_FILE)) end)
    if not success or not data then return false end
    _isLoading = true

    -- Anti Aimbot Mode MUST be restored early so rejoin keeps V2
    do
        local rawMode = data.antiAimbotMode
        if rawMode == nil and data.AntiAimbotMode ~= nil then rawMode = data.AntiAimbotMode end
        if type(rawMode) == "string" then
            local m = string.upper((rawMode:gsub("%s+", "")))
            if m == "V1" or m == "V2" then
                antiAimbotMode = m
            end
        end
        if data.antiAimbot == true then
            antiAimbotEnabled = true
        elseif data.antiAimbot == false then
            antiAimbotEnabled = false
        end
    end

    NS = data.normalSpeed or NS
    CS = data.carrySpeed or CS
    pcall(function()
        CarrySystem:setNormalSpeed(NS)
        CarrySystem:setCarrySpeed(CS)
    end)
    LAGGER_SPEED = data.laggerSpeed1 or LAGGER_SPEED
    LAGGER_CARRY_SPEED = data.laggerSpeed2 or LAGGER_CARRY_SPEED
    CONFIG.STEAL_RANGE = data.stealRadius or CONFIG.STEAL_RANGE
    if radInput then radInput.Text = tostring(CONFIG.STEAL_RANGE) end
    if data.lockUI ~= nil then uiLocked = data.lockUI else uiLocked = true end
    if data.editMode ~= nil then editModeEnabled = data.editMode else editModeEnabled = false end
    if data.antiRagdollMode then
        antiRagdollMode = data.antiRagdollMode
    else
        antiRagdollMode = data.antiRagdoll and "v2" or "off"
    end
    antiDieEnabled = data.antiDieEnabled or false
    antiFlingEnabled = data.antiFlingEnabled or false
    CONFIG.AUTO_STEAL_ENABLED = data.autoSteal or false
    medusaCounterEnabled = data.medusaCounter or false
    batCounterEnabled = data.batCounter or false
    batCounterV2Enabled = false -- Bat Counter V3 removed
    if data.batCounterV3Stud and tonumber(data.batCounterV3Stud) then
        local s = tonumber(data.batCounterV3Stud)
        if s > 0 and s <= 30 then
            if s < 8 then s = 10 end
            BAT_COUNTER_V2_TOUCH_DIST = s
            if batCounterV3StudBox then batCounterV3StudBox.Text = tostring(s) end
        end
    end
    if data.infiniteJump then
        task.defer(function()
            if InfiniteJump then InfiniteJump.start() end
            if setJumpVisual then setJumpVisual(true) end
        end)
    else
        if InfiniteJump then InfiniteJump.stop() end
        if setJumpVisual then setJumpVisual(false) end
    end
    infJumpMode = (data.infJumpMode == "MANUAL") and "MANUAL" or "HOLD"
    if infJumpModeLabel then infJumpModeLabel.Text = tostring(infJumpMode or "HOLD") .. "  ▼" end
    do
        local v = tonumber(data.autoStealVariant) or 1
        if v >= 3 then v = 2 end -- old "Semi Normal" -> Semi
        autoStealVariant = _clamp(v, 1, 2)
    end
    if autoStealVariantLabel then autoStealVariantLabel.Text = autoStealVariantName(autoStealVariant) end
    customToolsEnabled = data.customToolsEnabled == true
    katanaSkinEnabled = data.katanaSkinEnabled == true
    katanaSkinColorMode = data.katanaSkinColorMode or "Red"
    if KatanaColorSelector then KatanaColorSelector.Text = tostring(katanaSkinColorMode) .. "  ▼" end
    discordTextColorTheme = data.discordTextColorTheme or "White"
    pcall(function() applyDiscordTextColor(discordTextColorTheme) end)
    minecraftBatSkinEnabled = data.minecraftBatSkinEnabled == true
    if data.medusaSkinChoice and type(data.medusaSkinChoice) == "string" then
        medusaSkinChoice = data.medusaSkinChoice
        _G.RivalMedusaSkin = data.medusaSkinChoice
        task.defer(function()
            pcall(function()
                if _G.RivalSetMedusaSkin then _G.RivalSetMedusaSkin(data.medusaSkinChoice) end
            end)
        end)
    end
    minecraftBatSkinColorMode = data.minecraftBatSkinColorMode or "Default"
    if MinecraftBatColorSelector then MinecraftBatColorSelector.Text = tostring(minecraftBatSkinColorMode) .. "  ▼" end
    if MinecraftBatSetVisual then MinecraftBatSetVisual(minecraftBatSkinEnabled) end
    if minecraftBatSkinEnabled then
        task.defer(function()
            pcall(function()
                if MinecraftBatSkin then
                    MinecraftBatSkin.State.enabled = true
                    MinecraftBatSkin.SetColorMode(minecraftBatSkinColorMode)
                    MinecraftBatSkin.Apply()
                end
            end)
        end)
    end
    if katanaSkinEnabled then
        task.defer(function()
            pcall(function()
                if KatanaSkin and KatanaSkin.SetColorMode then
                    KatanaSkin.SetColorMode(katanaSkinColorMode or "Red")
                else
                    KatanaSkin.ApplySkin("KATANA")
                end
            end)
        end)
    end
    antiBatEnabled = data.antiBatEnabled or false
    if antiBatEnabled then
        task.defer(function()
            startAntiBat()
            if setAntiBatVisual then setAntiBatVisual(true) end
            if mobSetAntiBat then mobSetAntiBat(true) end
        end)
    end
    if data.antiBatPanelPos then antiBatPanelPos = data.antiBatPanelPos end
    antiBatPanelCollapsed = data.antiBatPanelCollapsed == true
    kickWarningEnabled = data.kickWarningEnabled or false
    unwalkEnabled = data.unwalk or false
    antiLagEnabled = data.antiLag or false
    laggerToggled = data.laggerToggled or false
    speedMode = data.carryMode or false
    laggerCarryToggled = data.laggerCarryToggled or false

    uiScaleValue = data.uiScale or uiScaleValue or 78
    stealBarScale = data.stealBarScale or stealBarScale or 100
    if mainUIScale then mainUIScale.Scale = uiScaleValue / 100 end
    if pbScale then pbScale.Scale = (tonumber(stealBarScale) or 100) / 100 end
    if data.antiAimbot == true then
        antiAimbotEnabled = true
    elseif data.antiAimbot == false then
        antiAimbotEnabled = false
    end
    do
        local raw = data.antiAimbotMode or data.AntiAimbotMode
        if type(raw) == "string" and raw ~= "" then
            local m = string.upper((tostring(raw):gsub("%s+", "")))
            if m == "V1" or m == "V2" then
                antiAimbotMode = m
            end
        end
        if antiAimbotMode ~= "V1" and antiAimbotMode ~= "V2" then
            antiAimbotMode = "V1"
        end
    end
    if data.taunt == true then
        tauntEnabled = true
        task.defer(function()
            startTaunt()
            if setTauntVisual then setTauntVisual(true) end
            if mobSetTaunt then pcall(mobSetTaunt, true) end
        end)
    else
        stopTaunt()
    end
    if data.spinEnabled == true then spinEnabled = true end
    if type(data.spinSpeed) == "number" then
        spinSpeed = data.spinSpeed
    end
    if type(data.spinSpeedName) == "string" and data.spinSpeedName ~= "" then
        spinSpeedName = data.spinSpeedName
        local map = { Slow = 0.15, Normal = 0.35, Fast = 0.60, ["Very Fast"] = 0.90 }
        if map[spinSpeedName] then
            spinSpeed = map[spinSpeedName]
        end
    else
        -- derive name from numeric speed
        local map = { {0.15, "Slow"}, {0.35, "Normal"}, {0.60, "Fast"}, {0.90, "Very Fast"} }
        spinSpeedName = "Normal"
        for _, pair in ipairs(map) do
            if math.abs((spinSpeed or 0.35) - pair[1]) < 0.02 then
                spinSpeedName = pair[2]
                break
            end
        end
    end
    if data.autoTpDownRadius ~= nil then
        autoTpDownRadius = tonumber(data.autoTpDownRadius) or autoTpDownRadius
        if autoTpDownRadiusBox then autoTpDownRadiusBox.Text = tostring(autoTpDownRadius) end
    end
    if data.autoTpDownEnabled ~= nil then
        autoTpDownEnabled = data.autoTpDownEnabled
        if autoTpDownEnabled then
            task.defer(function()
                startAutoTpDown()
                if autoTpDownSetVisual then autoTpDownSetVisual(true) end
            end)
        end
    end
    espEnabled = data.espEnabled or false
    if espEnabled then toggleESP(true) else toggleESP(false) end
    do
        local themeMap = {
            Azul = "Mavi", Verde = "Yesil", Rosado = "Kirmizi",
            Gris = "Naranja", Vainilla = "Sari",
        }
        local tc = data.themeColor
        if tc and themeMap[tc] then tc = themeMap[tc] end
        if tc and COLOR_THEMES[tc] then
            currentColorTheme = tc
            selectedColor = COLOR_THEMES[tc]
            task.defer(function()
                updateAllUIThemeColors(selectedColor)
                if colorSelectorLabel then
                    colorSelectorLabel.Text = currentColorTheme .. "  ▼"
                    colorSelectorLabel.TextColor3 = selectedColor
                end
            end)
        end
        local etc = data.espColorTheme
        if etc and themeMap[etc] then etc = themeMap[etc] end
        if etc and COLOR_THEMES[etc] then
            espColorTheme = etc
            selectedESPColor = COLOR_THEMES[etc]
        else
            espColorTheme = "Mavi"
            selectedESPColor = COLOR_THEMES["Mavi"]
        end
        task.defer(function()
            if espColorSelectorLabel then
                espColorSelectorLabel.Text = espColorTheme .. "  ▼"
                espColorSelectorLabel.TextColor3 = selectedESPColor
            end
            applyESPColorTheme(espColorTheme)
        end)
    end
    autoBatV2Enabled = data.autoBatV2Enabled or false
    if autoBatV2Enabled then
        task.defer(function()
            enableBatV2()
            if autoBatV2SetVisual then autoBatV2SetVisual(true) end
        end)
    else
        if autoBatV2SetVisual then autoBatV2SetVisual(false) end
    end
    -- Load TP BAT version (V1/V2/V3)
    if data.batTPVersion and (data.batTPVersion == "V1" or data.batTPVersion == "V2" or data.batTPVersion == "V3") then
        batTPVersion = data.batTPVersion
    end
    if data.tpBatV2Distance then
        _G.__tpBatV2Distance = tonumber(data.tpBatV2Distance) or 8
    end
    if batTPVersionLabel then
        batTPVersionLabel.Text = tostring(batTPVersion or "V1") .. "  ▼"
    end
    local tpBatStateLoaded = data.tpBatEnabled or false
    if tpBatStateLoaded then
        task.defer(function()
            startBatDesyncTp()
            if batDesyncTpSetVisual then batDesyncTpSetVisual(true) end
            updateTpBatButtonWithAntiDie(true)
        end)
    else
        if batDesyncTpSetVisual then batDesyncTpSetVisual(false) end
        updateTpBatButtonWithAntiDie(false)
    end
    skyTheme = data.skyTheme or "Off"
    if skyTheme ~= "Off" then pcall(applyCustomSky, skyTheme) end
    if skySelectorLabel then skySelectorLabel.Text = tostring(skyTheme) .. "  ▼" end
    neonWeatherEnabled = data.neonWeather or false
    if neonWeatherEnabled then
        task.defer(function() toggleNeonWeather(true) end)
    else
        toggleNeonWeather(false)
        skyTheme = "Off"
        pcall(applyCustomSky, "Off")
        if skySelectorLabel then skySelectorLabel.Text = "Off  ▼" end
    end
    if data.animPack and ANIM_PACKS[data.animPack] then
        startAnimPack(data.animPack)
    else
        currentAnimPack = "Off"
        stopAnimPack()
    end
    local function lk(e, d)
        if not d then return end
        if d.kb and Enum.KeyCode[d.kb] then e.kb = Enum.KeyCode[d.kb] end
        if d.gp and Enum.KeyCode[d.gp] then e.gp = Enum.KeyCode[d.gp] end
    end
    lk(KB.DropBrainrot, data.dropBrainrotKey)
    lk(KB.AutoLeft, data.autoLeftKey)
    lk(KB.AutoRight, data.autoRightKey)
    lk(KB.AutoBat, data.autoBatKey)
    lk(KB.AntiBat, data.antiBatKey)
    lk(KB.TPFloor, data.tpFloorKey)
    lk(KB.CarryToggle, data.carryToggleKey)
    lk(KB.LaggerMode, data.laggerModeKey)
    lk(KB.TPBat, data.tpBatKey)
    lk(KB.BatV2, data.batV2Key)
    lk(KB.InstaReset, data.instaResetKey)
    if data.mobileButtonPositions then savedButtonPositions = data.mobileButtonPositions end
    if data.mobilePanelPos then savedMobilePanelPos = data.mobilePanelPos end
    if data.tpBatFloatingPos then tpBatFloatingPos = data.tpBatFloatingPos end
    if data.batV2FloatingPos then batV2FloatingPos = data.batV2FloatingPos end
    if data.instaResetFloatingPos then instaResetFloatingPos = data.instaResetFloatingPos end
    if data.antiAimbotFloatingPos then antiAimbotFloatingPos = data.antiAimbotFloatingPos end
    if data.progressBarPos then savedProgressBarPos = data.progressBarPos end
    if data.bodyLockEnabled ~= nil then
        bodyLockEnabled = data.bodyLockEnabled
        if bodyLockEnabled then
            task.defer(function()
                if bodyLockSetVisual then bodyLockSetVisual(true) end
                startBodyLock()
            end)
        end
    end
    if data.bodyLockRange then
        bodyLockRange = data.bodyLockRange
        if bodyLockRangeBox then bodyLockRangeBox.Text = tostring(bodyLockRange) end
    end
    dropMode = data.dropMode or 1
    stretchEnabled = data.stretchEnabled or false
    fovValue = data.fovValue or 70
    fovEnabled = data.fovEnabled or false
    if fovSliderSet then fovSliderSet(fovValue) end
    if fovEnabled then enableCustomFov() end
    if setFovVisual then setFovVisual(fovEnabled) end
    stretchFOV = data.stretchFOV or 120
    BAT_AIMBOT_SPEED = data.batAimbotSpeed or BAT_AIMBOT_SPEED
    if data.batAimbotMode == "Normal" or data.batAimbotMode == "V2" or data.batAimbotMode == "V3" then
        batAimbotMode = data.batAimbotMode
    elseif data.batAimbotMode == "Bypass" then
        batAimbotMode = "V2"
    end
    if data.autoBatEnabled then
        task.defer(function()
            if enableAutoBat then pcall(enableAutoBat) end
            if autoBatSetVisual then autoBatSetVisual(true) end
            if mobSetAutoBat then mobSetAutoBat(true) end
        end)
    end
    batAimbotMode = batAimbotMode or "Normal"
    if batAimbotModeLabel then
        batAimbotModeLabel.Text = tostring(batAimbotMode or "Normal") .. "  ▼"
    end
    if data.bypassAimbotSpeed then BYPASS_AIMBOT_SPEED = data.bypassAimbotSpeed end
    backgroundImages = { "118241258424065", "137090941888778", "106638406471484", "126843729942853", "132235750206658" }
    local loadedBg = math.floor(tonumber(data.backgroundIndex) or 1)
    if loadedBg < 1 then loadedBg = 1 end
    if loadedBg > #backgroundImages then loadedBg = 1 end
    backgroundIndex = loadedBg
    local loadedSb = math.floor(tonumber(data.stealBarBackgroundIndex) or 1)
    if loadedSb < 1 then loadedSb = 1 end
    if loadedSb > #backgroundImages then loadedSb = 1 end
    stealBarBackgroundIndex = loadedSb
    backgroundImageTransparency = data.backgroundImageTransparency or 0.05
    BACKGROUND_ASSET_ID = backgroundImages[backgroundIndex]
    pcall(function()
        applyBackgroundToAll()
    end)
    floatingButtonScale = data.floatingButtonScale or 1
    if data.floatingButtonShape == "Square" or data.floatingButtonShape == "Rounded" or data.floatingButtonShape == "Circle" then
        floatingButtonShape = data.floatingButtonShape
    end
    if data.outfitIndex and data.outfitIndex >= 1 and data.outfitIndex <= #OUTFITS then
        currentOutfitIndex = data.outfitIndex
        task.defer(function()
            pcall(function() applyOutfitByIndex(currentOutfitIndex) end)
            if outfitSelectorLabel then
                outfitSelectorLabel.Text = tostring(OUTFITS[currentOutfitIndex].label) .. "  ▼"
            end
        end)
    end

    useCarrySystem = true
    autoCarrySpeedEnabled = data.autoCarrySpeedEnabled == true
    -- Single source: Speed Settings values (NS/CS/LAGGER_*) drive CarrySystem
    CarrySystem.normalSpeed = NS
    CarrySystem.carrySpeed = CS
    CarrySystem.laggerSpeed = LAGGER_SPEED
    CarrySystem.laggerCarrySpeed = LAGGER_CARRY_SPEED
    CarrySystem.softStealSpeed = data.carrySysSoftStealSpeed or 50
    CarrySystem.softStealRadius = data.carrySysSoftStealRadius or 12
    if data.autoCarryMode == "ON STEAL" or data.autoCarryMode == "WHEN NEAR" then
        CarrySystem.autoCarryMode = data.autoCarryMode
    end
    if useCarrySystem then
        CarrySystem:start()
        CarrySystem.speedToggled = speedMode
        if laggerToggled then
        else
            CarrySystem:setLaggerMode(0)
        end
        CarrySystem:setSoftStealEnabled(false)
    else
        CarrySystem:stop()
        CarrySystem:setSoftStealEnabled(false)
    end
    if autoCarrySpeedSetVisual then autoCarrySpeedSetVisual(autoCarrySpeedEnabled) end

    autoBatEnabled = false
    autoLeftEnabled = false
    autoRightEnabled = false
    if dropModeBtnRef then dropModeBtnRef.Text = (dropMode == 1 and "Fling" or "Jump Drop") .. "  ▼" end
    refreshSpeedModeLabel()

    -- Ping Lagger settings restore
    do
        local spl = rawget(_G, "SakuraPingLagger") or SakuraPingLagger
        if spl and spl.cfg then
        local cfg = spl.cfg
        if data.pingLaggerPower ~= nil then
            local p = tonumber(data.pingLaggerPower)
            if p and p >= 1 then cfg.power = math.floor(p) end
        end
        if data.pingLaggerInterval ~= nil then
            local iv = tonumber(data.pingLaggerInterval)
            if iv and iv >= 0.01 then cfg.interval = iv end
        end
        if data.pingLaggerKeybindKb ~= nil then
            cfg.keybindKb = tostring(data.pingLaggerKeybindKb)
        end
        if data.pingLaggerKeybindGp ~= nil then
            cfg.keybindGp = tostring(data.pingLaggerKeybindGp)
        end
        if data.pingLaggerAutoActivate ~= nil then
            cfg.autoActivate = data.pingLaggerAutoActivate == true
        end
        if data.pingLaggerAntiLag ~= nil then
            cfg.antiLag = data.pingLaggerAntiLag == true
        end
        if data.pingLaggerUiSize ~= nil then
            local us = tonumber(data.pingLaggerUiSize)
            if us then cfg.uiSize = math.clamp(us, 65, 145) end
        end
        end
    end

    -- Re-apply MC Bat color mode after full load (selector + skin module)
    if data.minecraftBatSkinColorMode then
        minecraftBatSkinColorMode = data.minecraftBatSkinColorMode
        if MinecraftBatColorSelector then
            MinecraftBatColorSelector.Text = tostring(minecraftBatSkinColorMode) .. "  ▼"
        end
        pcall(function()
            if MinecraftBatSkin and MinecraftBatSkin.SetColorMode then
                MinecraftBatSkin.SetColorMode(minecraftBatSkinColorMode)
            end
        end)
        if minecraftBatSkinEnabled then
            pcall(function()
                if MinecraftBatSkin and MinecraftBatSkin.Apply then
                    MinecraftBatSkin.Apply()
                end
            end)
        end
    end

    _lastSavedJSON = HS:JSONEncode(buildConfigTable())
    _isLoading = false
    return true
end

function forceResetUI()
    if normalBox then normalBox.Text = tostring(NS) end
    if carryBox then carryBox.Text = tostring(CS) end
    if radInput then radInput.Text = tostring(CONFIG.STEAL_RANGE) end
    if laggerBox then laggerBox.Text = tostring(LAGGER_SPEED) end
    if lagger2Box then lagger2Box.Text = tostring(LAGGER_CARRY_SPEED) end
    if batSpeedBox then batSpeedBox.Text = tostring(BAT_AIMBOT_SPEED) end
    if batCounterV3StudBox then batCounterV3StudBox.Text = tostring(BAT_COUNTER_V2_TOUCH_DIST or 2.5) end
    if uiScaleBox then uiScaleBox.Text = tostring(uiScaleValue) end
    if dropModeBtnRef then dropModeBtnRef.Text = (dropMode == 1 and "Fling" or "Jump Drop") .. "  ▼" end
    if bodyLockRangeBox then bodyLockRangeBox.Text = tostring(bodyLockRange) end
    if carrySysNormalBox then carrySysNormalBox.Text = tostring(CarrySystem.normalSpeed) end
    if carrySysCarryBox then carrySysCarryBox.Text = tostring(CarrySystem.carrySpeed) end
    if carrySysLaggerBox then carrySysLaggerBox.Text = tostring(CarrySystem.laggerSpeed) end
    if carrySysLaggerCarryBox then carrySysLaggerCarryBox.Text = tostring(CarrySystem.laggerCarrySpeed) end
    if carrySysSoftStealSpeedBox then carrySysSoftStealSpeedBox.Text = tostring(CarrySystem.softStealSpeed) end
    if carrySysSoftStealRadiusBox then carrySysSoftStealRadiusBox.Text = tostring(CarrySystem.softStealRadius) end
    if carrySystemToggleSetter then carrySystemToggleSetter(useCarrySystem) end
    local function safeSet(fn, val) if fn then fn(val) end end
    safeSet(autoBatSetVisual, false)
    safeSet(autoLeftSetVisual, false)
    safeSet(autoRightSetVisual, false)
    safeSet(setBatCounterVisual, false)
    safeSet(setBatCounterV2Visual, false)
    safeSet(setMedusaVisual, false)
    safeSet(setUnwalkVisual, false)
    safeSet(setAntiLagVisual, false)
    safeSet(setJumpVisual, false)
    pcall(InfiniteJump.stop)
    safeSet(setLockUIVisual, false)
    safeSet(setEditModeVisual, false)
    safeSet(setInstaGrab, false)
    safeSet(batDesyncTpSetVisual, false)
    safeSet(setESPVIsual, false)
    safeSet(bodyLockSetVisual, false)
    safeSet(setNeonWeatherVisual, false)
    safeSet(autoBatV2SetVisual, false)
    safeSet(setAntiDieVisual, false)
    if _G.stretchToggleSetter then _G.stretchToggleSetter(false) end
    safeSet(mobSetAutoBat, false)
    safeSet(mobSetAutoLeft, false)
    safeSet(mobSetAutoRight, false)
    safeSet(mobSetDropBR, false)
    safeSet(mobSetTpDown, false)
    safeSet(mobSetCarry, false)
    safeSet(mobSetLagger1, false)
    safeSet(mobSetLagger2, false)
    refreshSpeedModeLabel()
    updateProgressBarVisibility()
    disableAntiLag()
    toggleNeonWeather(false)
    skyTheme = "Off"
    pcall(applyCustomSky, "Off")
    if skySelectorLabel then skySelectorLabel.Text = "Off  ▼" end
    disableBatV2()
    if antiDieEnabled then
        AntiDieModule.stop()
        antiDieEnabled = false
    end
    if antiFlingEnabled then
        AntiFlingShieldModule.stop()
        antiFlingEnabled = false
    end
    updateTpBatButtonWithAntiDie(false)
    for _, ref in ipairs(keyButtonRefs) do
        local entry = ref.entry
        local label = (entry.gp and entry.gp.Name) or (entry.kb and entry.kb.Name) or "None"
        ref.btn.Text = label
    end
    currentColorTheme = "Naranja"
    selectedColor = COLOR_THEMES["Naranja"]
    if colorSelectorLabel then
        colorSelectorLabel.Text = "Naranja  ▼"
        colorSelectorLabel.TextColor3 = selectedColor
    end
    updateAllUIThemeColors(selectedColor)
    if miniBtn then miniBtn.TextColor3 = Color3.fromRGB(255,255,255) end
    local pGui = LP:FindFirstChild("PlayerGui")
    if pGui then
        local bb = pGui:FindFirstChild("RagCountdownBillboard")
        if bb then
            local lbl = bb:FindFirstChildOfClass("TextLabel")
            if lbl then lbl.TextColor3 = selectedColor end
        end
    end
    if MobilePanel then
        local container = MobilePanel:FindFirstChild("FloatingPanel")
        if container then
            local btnContainer = container:FindFirstChild("ButtonsContainer")
            if btnContainer then
                for _, btn in ipairs(btnContainer:GetChildren()) do
                    if btn:IsA("TextButton") then
                        paintFloatingBtn(btn, btn:GetAttribute("MobActive") == true)
                    end
                end
            end
        end
    end
    saveAllSettings()
end

function resetFloatingPositions()
    if MobilePanel and MobilePanel:FindFirstChild("FloatingPanel") then
        local container = MobilePanel:FindFirstChild("FloatingPanel")
        container.Position = UDim2.new(0, 10, 0, 0)
        savedButtonPositions = {}
        if container:FindFirstChild("ButtonsContainer") then
            for _, btn in ipairs(container.ButtonsContainer:GetChildren()) do
                if btn:IsA("TextButton") and btn.Name then
                    local defX, defY = getDefaultButtonPosition(btn.Name)
                    btn.Position = UDim2.new(0, defX, 0, defY)
                end
            end
        end
    end
    if tpBatFloatingButton and tpBatFloatingButton:FindFirstChild("Frame") then
        local btnFrame = tpBatFloatingButton:FindFirstChild("Frame")
        btnFrame.Position = UDim2.new(1, -72, 0, 8)
        tpBatFloatingPos = nil
    end
    if batV2FloatingButton and batV2FloatingButton:FindFirstChild("Frame") then
        local btnFrame = batV2FloatingButton:FindFirstChild("Frame")
        btnFrame.Position = UDim2.new(0.5, -50, 0, 10)
        batV2FloatingPos = nil
    end
    if instaResetFloatingButton and instaResetFloatingButton:FindFirstChild("Frame") then
        instaResetFloatingButton.Frame.Position = UDim2.new(0.5, 90, 0, 10)
        instaResetFloatingPos = nil
    end
    if antiAimbotFloatingButton and antiAimbotFloatingButton:FindFirstChild("Frame") then
        local btnFrame = antiAimbotFloatingButton:FindFirstChild("Frame")
        btnFrame.Position = UDim2.new(1, -72, 0, 76)
        antiAimbotFloatingPos = nil
    end
    if pbFrame then
        pbFrame.Position = UDim2.new(0.5, -220, 1, -66)
        savedProgressBarPos = nil
    end
    savedMobilePanelPos = nil
    tpBatFloatingPos = nil
    batV2FloatingPos = nil
    instaResetFloatingPos = nil
    antiAimbotFloatingPos = nil
end

function resetToFactoryDefaults()
    _isResetting = true
    local ok, err = pcall(function()
        stopAllBackgroundTasks()
        stopAutoSteal()
        stopBatCounter()
        stopBatCounterV2()
        stopMedusaCounter()
        if AntiRagdollV1.isRunning() then AntiRagdollV1.stop() end
        if AntiRagdollV2.Enabled then stopAntiRagdollV2() end
        if antiDieEnabled then AntiDieModule.stop() end
        if antiFlingEnabled then AntiFlingShieldModule.stop() end
        stopUnwalk()
        disableAutoBat()
        if batDesyncTpEnabled then stopBatDesyncTp() end
        disableBatV2()
        stopBodyLock()
        if espEnabled then toggleESP(false) end
        if stretchEnabled then disableStretch() end
        if antiLagEnabled then disableAntiLag() end
        if dropActive then stopDropBrainrot() end
        toggleNeonWeather(false)
        skyTheme = "Off"
        pcall(applyCustomSky, "Off")
        if skySelectorLabel then skySelectorLabel.Text = "Off  ▼" end
        if antiDieEnabled then
            AntiDieModule.stop()
            antiDieEnabled = false
        end
        if antiFlingEnabled then
            AntiFlingShieldModule.stop()
            antiFlingEnabled = false
        end
        NS = 60
        CS = 29
        LAGGER_SPEED = 15
        LAGGER_CARRY_SPEED = 24.5
        CONFIG.STEAL_RANGE = 61
        speedMode = false
        laggerToggled = false
        laggerCarryToggled = false
        antiRagdollMode = "off"
        antiDieEnabled = false
        antiFlingEnabled = false
        medusaCounterEnabled = false
        batCounterEnabled = false
        batCounterV2Enabled = false
        autoBatEnabled = false
        autoLeftEnabled = false
        autoRightEnabled = false
        unwalkEnabled = false
        antiLagEnabled = false
        uiLocked = true
        editModeEnabled = false
        CONFIG.AUTO_STEAL_ENABLED = false
        BAT_AIMBOT_SPEED = 58
        dropMode = 1
        stretchEnabled = false
        stretchFOV = 120
        fovValue = 70
        disableCustomFov()
        if fovSliderSet then fovSliderSet(70) end
        if setFovVisual then setFovVisual(false) end
        uiScaleValue = 78
stealBarScale = 100
antiAimbotEnabled = false
antiAimbotMode = "V1"
tauntEnabled = false
setAntiAimbotVisual = nil
        if mainUIScale then mainUIScale.Scale = 1 end
        if pbScale then pbScale.Scale = 1 end
        espEnabled = false
        bodyLockEnabled = false
        bodyLockRange = 20
        autoBatV2Enabled = false
        backgroundIndex = 1
        backgroundImageTransparency = 0
        floatingButtonScale = 1
floatingButtonShape = "Rounded" -- "Rounded" | "Square" | "Circle" | "Circle"
        if batDesyncTpEnabled then stopBatDesyncTp() end
        currentAnimPack = "Off"
        stopAnimPack()
        currentOutfitIndex = 1
        currentColorTheme = "Naranja"
        selectedColor = COLOR_THEMES["Naranja"]
        for key, val in pairs(DEFAULT_KB) do
            if KB[key] then
                KB[key].kb = val.kb
                KB[key].gp = val.gp
            end
        end
        useCarrySystem = true
        CarrySystem:stop()
        CarrySystem.normalSpeed = NS
        CarrySystem.carrySpeed = CS
        CarrySystem.laggerSpeed = LAGGER_SPEED
        CarrySystem.laggerCarrySpeed = LAGGER_CARRY_SPEED
        CarrySystem.softStealSpeed = 30
        CarrySystem.softStealRadius = 10
        CarrySystem.speedToggled = false
        CarrySystem.laggerMode = 0
        CarrySystem.softStealEnabled = false
        if isfile and isfile(CONFIG_FILE) then
            pcall(delfile, CONFIG_FILE)
        end
        resetFloatingPositions()
        forceResetUI()
        updateProgressBarVisibility()
        refreshSpeedModeLabel()
        _lastSavedJSON = nil
        saveAllSettings()
    end)
    _isResetting = false
    if not ok then warn("[resetToFactoryDefaults]", err) end
    return ok
end

function updateProgressBarVisibility()
    if pbFrame then pbFrame.Visible = CONFIG.AUTO_STEAL_ENABLED end
end

function applyShimmerToText(obj, speed)
    speed = speed or 0.8
    local color = getThemeColor()
    local grad = Instance.new("UIGradient", obj)
    grad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, color),
        ColorSequenceKeypoint.new(0.3, Color3.fromRGB(200,200,200)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255,255,255)),
        ColorSequenceKeypoint.new(0.7, Color3.fromRGB(200,200,200)),
        ColorSequenceKeypoint.new(1, color),
    })
    grad.Rotation = 45
    grad.Offset = Vector2.new(0,0)
    task.spawn(function()
        local t = 0
        while grad and grad.Parent do
            t = t + 0.02
            grad.Offset = Vector2.new(math.sin(t * speed) * 0.4, 0)
            task.wait(0.04)
        end
    end)
    return grad
end

function getDefaultButtonPosition(btnName)
    local BTN_W, BTN_H = 60, 60
    local GAP = 8
    local orderMap = {
        DropBR = 0, AutoLeft = 1, AutoBat = 2,
        AutoRight = 3, TpDown = 4, Carry = 5, Lagger1 = 6, Lagger2 = 7, AntiAimbot = 8, Taunt = 9
    }
    local order = orderMap[btnName] or 0
    local row = _floor(order / 2)
    local col = order % 2
    return col * (BTN_W + GAP), row * (BTN_H + GAP + 10)
end

-- ============================================================
-- INSTA RESET MODULE
-- ============================================================
do
    print("[IR] 1. inicio")

    if _G.InstaResetLoaded then
        print("[IR] ya cargado")
    else
        _G.InstaResetLoaded = true

        local resetCooldown          = false
        local resetThread            = nil
        local currentResetChar       = nil
        local resetSuccessful        = false
        local stopResetSequence      = false
        local cameraLocked           = false
        local lockedCameraCFrame     = nil
        local _lastInstaResetRequest = 0

        print("[IR] 2. servicios OK, LP =", LP and LP.Name)

        local function instaResetFast()
            if resetCooldown then return end
            resetCooldown     = true
            resetSuccessful   = false
            stopResetSequence = false
            cameraLocked      = false

            local character = LP.Character
            if not character then resetCooldown = false return end
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if not humanoid then resetCooldown = false return end

            local cam = workspace.CurrentCamera
            if cam then
                lockedCameraCFrame = cam.CFrame
                cameraLocked       = true
                cam.CFrame         = lockedCameraCFrame
            end

            currentResetChar = character
            local isRespawning = false

            resetThread = task.spawn(function()
                local attempts          = 0
                local maxAttempts       = 40
                local originalHipHeight = humanoid.HipHeight

                while character and character.Parent and humanoid and humanoid.Health > 0
                      and not isRespawning and not stopResetSequence do
                    if LP.Character ~= character then
                        isRespawning = true
                        break
                    end
                    pcall(function()
                        humanoid.HipHeight  = 1e30
                        humanoid.AutoRotate = true
                        local rootPart = character:FindFirstChild("HumanoidRootPart")
                        if rootPart then rootPart.CanCollide = false end
                        for _, part in ipairs(character:GetChildren()) do
                            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                                part.CanCollide = false
                            end
                        end
                    end)

                    if not character or not character.Parent or not humanoid
                       or humanoid.Health <= 0 or LP.Character ~= character then
                        resetSuccessful = true
                        break
                    end

                    attempts = attempts + 1
                    if attempts >= maxAttempts then break end
                    task.wait(0.05)
                end

                if not resetSuccessful then
                    if character and character.Parent and humanoid
                       and humanoid.Health > 0 and not isRespawning then
                        pcall(function() humanoid.Health = 0 end)
                        task.wait(0.1)
                        if not character.Parent or humanoid.Health <= 0 then
                            resetSuccessful = true
                        end
                    end
                end

                if not resetSuccessful and character and character.Parent and humanoid then
                    pcall(function()
                        humanoid.HipHeight = originalHipHeight
                        local rootPart = character:FindFirstChild("HumanoidRootPart")
                        if rootPart then rootPart.CanCollide = true end
                        for _, part in ipairs(character:GetChildren()) do
                            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                                part.CanCollide = true
                            end
                        end
                    end)
                end

                cameraLocked      = false
                resetCooldown     = false
                resetThread       = nil
                currentResetChar  = nil
                stopResetSequence = false
            end)
        end

        local function instaReset()
            local now = os.clock()
            if now - _lastInstaResetRequest < 0.75 then return end
            _lastInstaResetRequest = now
            instaResetFast()
        end

        print("[IR] 3. función lista")

        LP.CharacterAdded:Connect(function()
            stopResetSequence = true
            if resetThread then pcall(task.cancel, resetThread); resetThread = nil end
            resetCooldown    = false
            currentResetChar = nil
            cameraLocked     = false
        end)

        task.spawn(function()
            while true do
                task.wait(0.016)
                local cam = workspace.CurrentCamera
                if cameraLocked and lockedCameraCFrame and cam then
                    cam.CFrame = lockedCameraCFrame
                end
            end
        end)

        print("[IR] 4. loop cámara iniciado")

        _G.InstaReset = { Trigger = instaReset }
    end
end


-- ============================================================
-- SAKURA.VS ANTI BAT PANEL
-- ============================================================
function destroyAntiBatPanel()
    if antiBatPanelGui then
        pcall(function() antiBatPanelGui:Destroy() end)
        antiBatPanelGui = nil
    end
    pcall(function()
        local pg = LP:FindFirstChild("PlayerGui")
        if pg then
            local g = pg:FindFirstChild("SakuraVsAntiBat")
            if g then g:Destroy() end
        end
        local cg = game:GetService("CoreGui")
        local g2 = cg:FindFirstChild("SakuraVsAntiBat")
        if g2 then g2:Destroy() end
    end)
    antiBatPanelVisible = false
end

antiBatPanelPos = antiBatPanelPos or nil
antiBatPanelCollapsed = antiBatPanelCollapsed or false

function createAntiBatPanel()
    destroyAntiBatPanel()
    local BLUE = Color3.fromRGB(255, 255, 255)
    local WHITE = Color3.fromRGB(255, 255, 255)
    local FULL_H = 212
    local MINI_H = 44
    local collapsed = antiBatPanelCollapsed == true

    local gui = Instance.new("ScreenGui")
    gui.Name = "SakuraVsAntiBat"
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 25
    pcall(function()
        if syn and syn.protect_gui then syn.protect_gui(gui) end
    end)
    local okP = pcall(function() gui.Parent = game:GetService("CoreGui") end)
    if not okP then gui.Parent = LP:WaitForChild("PlayerGui") end

    local Main = Instance.new("Frame")
    Main.Name = "Main"
    Main.ClipsDescendants = true
    if antiBatPanelPos and type(antiBatPanelPos.XOffset) == "number" then
        Main.Position = UDim2.new(
            antiBatPanelPos.XScale or 0,
            antiBatPanelPos.XOffset or 0,
            antiBatPanelPos.YScale or 0,
            antiBatPanelPos.YOffset or 0
        )
    else
        Main.Position = UDim2.new(0.5, -130, 0.5, -80)
    end
    Main.Size = UDim2.new(0, 260, 0, collapsed and MINI_H or FULL_H)
    Main.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
    Main.BorderSizePixel = 0
    Main.Active = true
    Main.Parent = gui
    Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 14)
    local stroke = Instance.new("UIStroke", Main)
    stroke.Color = BLUE
    stroke.Thickness = 1.4
    stroke.Transparency = 0.25

    local bg = Instance.new("ImageLabel", Main)
    bg.Size = UDim2.new(1, 0, 1, 0)
    bg.BackgroundTransparency = 1
    bg.Image = "rbxthumb://type=Asset&id=" .. tostring(BACKGROUND_ASSET_ID) .. "&w=768&h=432"
    bg.ImageTransparency = 0.12
    bg.ScaleType = Enum.ScaleType.Crop
    Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 14)

    local dim = Instance.new("Frame", Main)
    dim.Size = UDim2.new(1, 0, 1, 0)
    dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    dim.BackgroundTransparency = 0.45
    dim.BorderSizePixel = 0
    dim.ZIndex = 2
    Instance.new("UICorner", dim).CornerRadius = UDim.new(0, 14)

    -- Title bar (sürükleme alanı)
    local titleBar = Instance.new("Frame", Main)
    titleBar.Name = "TitleBar"
    titleBar.ZIndex = 5
    titleBar.Position = UDim2.new(0, 0, 0, 0)
    titleBar.Size = UDim2.new(1, 0, 0, 44)
    titleBar.BackgroundTransparency = 1
    titleBar.Active = true

    local title = Instance.new("TextLabel", titleBar)
    title.ZIndex = 5
    title.Position = UDim2.new(0, 14, 0, 4)
    title.Size = UDim2.new(1, -90, 0, 20)
    title.BackgroundTransparency = 1
    title.Text = "Sakura.vs Anti Bat"
    title.TextColor3 = Color3.fromRGB(255, 140, 0)
    title.Font = Enum.Font.GothamBlack
    title.TextSize = 14
    title.TextXAlignment = Enum.TextXAlignment.Left

    local sub = Instance.new("TextLabel", titleBar)
    sub.ZIndex = 5
    sub.Position = UDim2.new(0, 14, 0, 22)
    sub.Size = UDim2.new(1, -90, 0, 16)
    sub.BackgroundTransparency = 1
    sub.Text = ""
    sub.Visible = false
    sub.TextColor3 = WHITE
    sub.Font = Enum.Font.Gotham
    sub.TextSize = 11
    sub.TextXAlignment = Enum.TextXAlignment.Left

    -- Minimize "_" (Bypass panel gibi)
    local minBtn = Instance.new("TextButton", titleBar)
    minBtn.Name = "Minimize"
    minBtn.ZIndex = 7
    minBtn.Position = UDim2.new(1, -64, 0, 9)
    minBtn.Size = UDim2.new(0, 26, 0, 26)
    minBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    minBtn.Text = collapsed and "□" or "_"
    minBtn.TextColor3 = WHITE
    minBtn.Font = Enum.Font.GothamBold
    minBtn.TextSize = 14
    minBtn.AutoButtonColor = false
    Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 6)

    local closeBtn = Instance.new("TextButton", titleBar)
    closeBtn.ZIndex = 7
    closeBtn.Position = UDim2.new(1, -34, 0, 9)
    closeBtn.Size = UDim2.new(0, 26, 0, 26)
    closeBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    closeBtn.Text = "×"
    closeBtn.TextColor3 = WHITE
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 16
    closeBtn.AutoButtonColor = false
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

    -- Content (küçülünce gizlenir)
    local content = Instance.new("Frame", Main)
    content.Name = "Content"
    content.ZIndex = 5
    content.Position = UDim2.new(0, 0, 0, 44)
    content.Size = UDim2.new(1, 0, 1, -44)
    content.BackgroundTransparency = 1
    content.Visible = not collapsed

    local line = Instance.new("Frame", content)
    line.ZIndex = 5
    line.Position = UDim2.new(0, 14, 0, 0)
    line.Size = UDim2.new(1, -28, 0, 1)
    line.BackgroundColor3 = BLUE
    line.BackgroundTransparency = 0.5
    line.BorderSizePixel = 0

    local row = Instance.new("Frame", content)
    row.ZIndex = 5
    row.Position = UDim2.new(0, 14, 0, 12)
    row.Size = UDim2.new(1, -28, 0, 44)
    row.BackgroundColor3 = Color3.fromRGB(6, 6, 12)
    row.BackgroundTransparency = 0.25
    row.BorderSizePixel = 0
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)
    local rowStroke = Instance.new("UIStroke", row)
    rowStroke.Color = Color3.fromRGB(80, 80, 80)
    rowStroke.Transparency = 0.4

    local lbl = Instance.new("TextLabel", row)
    lbl.ZIndex = 6
    lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.Size = UDim2.new(1, -90, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = "Anti Bat"
    lbl.TextColor3 = WHITE
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 13
    lbl.TextXAlignment = Enum.TextXAlignment.Left

    local track = Instance.new("Frame", row)
    track.Name = "Track"
    track.ZIndex = 7
    track.Position = UDim2.new(1, -58, 0.5, -12)
    track.Size = UDim2.new(0, 46, 0, 24)
    track.BackgroundColor3 = antiBatEnabled and BLUE or Color3.fromRGB(55, 55, 68)
    track.BorderSizePixel = 0
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame", track)
    knob.Name = "Knob"
    knob.ZIndex = 8
    knob.Position = antiBatEnabled and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
    knob.Size = UDim2.new(0, 18, 0, 18)
    knob.BackgroundColor3 = WHITE
    knob.BorderSizePixel = 0
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local toggleBtn = Instance.new("TextButton", track)
    toggleBtn.ZIndex = 9
    toggleBtn.Size = UDim2.new(1, 0, 1, 0)
    toggleBtn.BackgroundTransparency = 1
    toggleBtn.Text = ""

    -- Infinite Jump row
    local row2 = Instance.new("Frame", content)
    row2.ZIndex = 5
    row2.Position = UDim2.new(0, 14, 0, 64)
    row2.Size = UDim2.new(1, -28, 0, 44)
    row2.BackgroundColor3 = Color3.fromRGB(6, 6, 12)
    row2.BackgroundTransparency = 0.25
    row2.BorderSizePixel = 0
    Instance.new("UICorner", row2).CornerRadius = UDim.new(0, 10)
    local row2Stroke = Instance.new("UIStroke", row2)
    row2Stroke.Color = Color3.fromRGB(80, 80, 80)
    row2Stroke.Transparency = 0.4

    local lbl2 = Instance.new("TextLabel", row2)
    lbl2.ZIndex = 6
    lbl2.Position = UDim2.new(0, 12, 0, 0)
    lbl2.Size = UDim2.new(1, -90, 1, 0)
    lbl2.BackgroundTransparency = 1
    lbl2.Text = "Infinite Jump"
    lbl2.TextColor3 = WHITE
    lbl2.Font = Enum.Font.GothamMedium
    lbl2.TextSize = 13
    lbl2.TextXAlignment = Enum.TextXAlignment.Left

    local infOn = (InfiniteJump and InfiniteJump.isRunning and InfiniteJump.isRunning()) == true
    local track2 = Instance.new("Frame", row2)
    track2.Name = "Track"
    track2.ZIndex = 7
    track2.Position = UDim2.new(1, -58, 0.5, -12)
    track2.Size = UDim2.new(0, 46, 0, 24)
    track2.BackgroundColor3 = infOn and BLUE or Color3.fromRGB(55, 55, 68)
    track2.BorderSizePixel = 0
    Instance.new("UICorner", track2).CornerRadius = UDim.new(1, 0)

    local knob2 = Instance.new("Frame", track2)
    knob2.Name = "Knob"
    knob2.ZIndex = 8
    knob2.Position = infOn and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
    knob2.Size = UDim2.new(0, 18, 0, 18)
    knob2.BackgroundColor3 = WHITE
    knob2.BorderSizePixel = 0
    Instance.new("UICorner", knob2).CornerRadius = UDim.new(1, 0)

    local toggleBtn2 = Instance.new("TextButton", track2)
    toggleBtn2.ZIndex = 9
    toggleBtn2.Size = UDim2.new(1, 0, 1, 0)
    toggleBtn2.BackgroundTransparency = 1
    toggleBtn2.Text = ""

    local footer = Instance.new("TextLabel", content)
    footer.ZIndex = 6
    footer.Position = UDim2.new(0, 0, 0, 118)
    footer.Size = UDim2.new(1, 0, 0, 18)
    footer.BackgroundTransparency = 1
    footer.Text = "Sakura.vs Anti Bat"
    footer.TextColor3 = BLUE
    footer.Font = Enum.Font.GothamBold
    footer.TextSize = 11

    local function setToggleVisual(on)
        TS:Create(track, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
            BackgroundColor3 = on and BLUE or Color3.fromRGB(55, 55, 68)
        }):Play()
        TS:Create(knob, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
            Position = on and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
        }):Play()
    end

    local function setInfJumpVisual(on)
        TS:Create(track2, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
            BackgroundColor3 = on and BLUE or Color3.fromRGB(55, 55, 68)
        }):Play()
        TS:Create(knob2, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
            Position = on and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
        }):Play()
    end

    local function setCollapsed(on)
        collapsed = on and true or false
        antiBatPanelCollapsed = collapsed
        content.Visible = not collapsed
        Main.Size = UDim2.new(0, 260, 0, collapsed and MINI_H or FULL_H)
        minBtn.Text = collapsed and "□" or "_"
        pcall(saveAllSettings)
    end

    toggleBtn.MouseButton1Click:Connect(function()
        setAntiBat(not antiBatEnabled)
        setToggleVisual(antiBatEnabled)
        saveAllSettings()
    end)

    toggleBtn2.MouseButton1Click:Connect(function()
        if not InfiniteJump then return end
        local nowOn = not InfiniteJump.isRunning()
        if nowOn then
            InfiniteJump.start()
        else
            InfiniteJump.stop()
        end
        setInfJumpVisual(nowOn)
        if setJumpVisual then pcall(setJumpVisual, nowOn) end
        pcall(saveAllSettings)
    end)

    minBtn.MouseButton1Click:Connect(function()
        setCollapsed(not collapsed)
    end)

    closeBtn.MouseButton1Click:Connect(function()
        destroyAntiBatPanel()
    end)

    -- Sürükle + pozisyon kaydet
    do
        local dragging, dragStart, startPos, activeInput = false, nil, nil, nil
        local function savePos()
            antiBatPanelPos = {
                XScale = Main.Position.X.Scale,
                XOffset = Main.Position.X.Offset,
                YScale = Main.Position.Y.Scale,
                YOffset = Main.Position.Y.Offset,
            }
            pcall(saveAllSettings)
        end
        titleBar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos = Main.Position
                activeInput = input
            end
        end)
        titleBar.InputEnded:Connect(function(input)
            if input == activeInput or input.UserInputType == Enum.UserInputType.MouseButton1 then
                if dragging then savePos() end
                dragging = false
                activeInput = nil
            end
        end)
        UIS.InputChanged:Connect(function(input)
            if not dragging then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
                local d = input.Position - dragStart
                Main.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + d.X,
                    startPos.Y.Scale, startPos.Y.Offset + d.Y
                )
            end
        end)
        UIS.InputEnded:Connect(function(input)
            if dragging and (input == activeInput or input.UserInputType == Enum.UserInputType.MouseButton1) then
                savePos()
                dragging = false
                activeInput = nil
            end
        end)
    end

    antiBatPanelGui = gui
    antiBatPanelVisible = true
    setToggleVisual(antiBatEnabled)
    setInfJumpVisual((InfiniteJump and InfiniteJump.isRunning and InfiniteJump.isRunning()) == true)
end

-- ============================================================

-- ============================================================

-- ============================================================



-- ============================================================
-- MEDUSA SKINS SYSTEM (Sakura.vs)
-- ============================================================
do
    local Players = game:GetService("Players")
    local LP = Players.LocalPlayer

    _G.RivalMedusaSkinAssets = {
        Skull = {
            mesh = "rbxassetid://2050312704", tex = "rbxassetid://2050313393",
            scale = Vector3.new(1, 1, 1),
            c0 = CFrame.new(0, 0.65, -0.4) * CFrame.Angles(math.rad(330), 0, 0),
        },
        GoldenDesertEagle = {
            mesh = "rbxassetid://430251413", tex = "rbxassetid://435840335",
            scale = Vector3.new(0.01, 0.01, 0.01),
            c0 = CFrame.new(0, 0, -0.8) * CFrame.Angles(math.rad(330), math.rad(180), 0),
        },
    }
    _G.RivalMedusaSkin = _G.RivalMedusaSkin or "Default"
    medusaSkinChoice = _G.RivalMedusaSkin or "Default"
    MedusaSkinSelector = nil

    local function isMedusaTool(tool)
        if not tool or not tool:IsA("Tool") then return false end
        local n = tool.Name:lower()
        return (n:find("medusa") or n:find("stone") or n:find("head")) and true or false
    end

    local function clearReplica(tool)
        local handle = tool and tool:FindFirstChild("Handle")
        if not handle then return end
        local rep = handle:FindFirstChild("RivalMedusaReplica")
        if rep then pcall(function() rep:Destroy() end) end
        for _, d in ipairs(tool:GetDescendants()) do
            if d:GetAttribute("RivalMedusaHidden") ~= nil then
                local orig = d:GetAttribute("RivalMedusaHidden")
                pcall(function() d.Transparency = orig end)
                pcall(function() d:SetAttribute("RivalMedusaHidden", nil) end)
            end
        end
    end

    local function hideOriginal(tool)
        for _, d in ipairs(tool:GetDescendants()) do
            if (d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture"))
                and not d:FindFirstAncestor("RivalMedusaReplica")
                and not d:FindFirstAncestor("ShelMedusaBombSkin") then
                pcall(function()
                    if d:GetAttribute("RivalMedusaHidden") == nil then
                        d:SetAttribute("RivalMedusaHidden", d.Transparency)
                    end
                    d.Transparency = 1
                end)
            end
        end
    end

    local function buildReplica(tool, key)
        local data = _G.RivalMedusaSkinAssets[key]
        local handle = tool:FindFirstChild("Handle")
        if not data or not handle then return end
        local cur = handle:FindFirstChild("RivalMedusaReplica")
        if cur and cur:GetAttribute("SkinKey") == key then
            hideOriginal(tool)
            for _, d in ipairs(cur:GetDescendants()) do
                if d:IsA("BasePart") then
                    if d.Transparency ~= 0 then d.Transparency = 0 end
                    if d.LocalTransparencyModifier ~= 0 then d.LocalTransparencyModifier = 0 end
                end
            end
            return
        end
        clearReplica(tool)
        hideOriginal(tool)
        local m = Instance.new("Model")
        m.Name = "RivalMedusaReplica"
        m:SetAttribute("SkinKey", key)
        local p = Instance.new("Part")
        p.Name = "MainPart"
        p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
        p.Massless = true; p.Anchored = false
        p.Size = Vector3.new(1, 1, 1)
        p.Transparency = 0
        p.Parent = m
        local mesh = Instance.new("SpecialMesh")
        mesh.MeshType = Enum.MeshType.FileMesh
        mesh.MeshId = data.mesh
        mesh.TextureId = data.tex
        mesh.Scale = data.scale
        mesh.Parent = p
        local w = Instance.new("Motor6D")
        w.Part0 = handle
        w.Part1 = p
        w.C0 = data.c0
        w.Parent = p
        m.Parent = handle
    end

    function _G.RivalApplyMedusaSkin()
        local sk = _G.RivalMedusaSkin or "Default"
        local containers = {}
        if LP.Character then table.insert(containers, LP.Character) end
        local bp = LP:FindFirstChildOfClass("Backpack")
        if bp then table.insert(containers, bp) end
        for _, container in ipairs(containers) do
            for _, tool in ipairs(container:GetChildren()) do
                if isMedusaTool(tool) then
                    if sk == "Default" then
                        clearReplica(tool)
                    else
                        buildReplica(tool, sk)
                    end
                end
            end
        end
    end

    function _G.RivalSetMedusaSkin(choice)
        if choice ~= "Default" and not _G.RivalMedusaSkinAssets[choice] then choice = "Default" end
        _G.RivalMedusaSkin = choice
        medusaSkinChoice = choice
        pcall(_G.RivalApplyMedusaSkin)
        if choice ~= "Default" then pcall(_G.RivalApplyMedusaSkin) end
    end

    task.spawn(function()
        while true do
            if (_G.RivalMedusaSkin or "Default") ~= "Default" then
                pcall(_G.RivalApplyMedusaSkin)
            end
            task.wait(0.6)
        end
    end)

    LP.CharacterAdded:Connect(function()
        task.wait(0.8)
        pcall(_G.RivalApplyMedusaSkin)
    end)
end

-- ============================================================
-- PERSONALIZATION: BAT SKINS (Sakura.vs) — Katana + Minecraft
-- ============================================================
katanaSkinEnabled = false
katanaSkinColorMode = "Red"
KatanaColorSelector = nil

local KatanaSkin = (function()
    local Players       = game:GetService("Players")
    local InsertService = game:GetService("InsertService")
    local Lighting2     = game:GetService("Lighting")
    local ReplicatedStorage2 = game:GetService("ReplicatedStorage")
    local LocalPlayer   = Players.LocalPlayer

    local KATANA_COLOR_PRESETS = {
        ["Red"]    = { primary = Color3.fromRGB(200, 0, 0),     secondary = Color3.fromRGB(255, 100, 100), accent = Color3.fromRGB(255, 185, 50)  },
        ["Blue"]   = { primary = Color3.fromRGB(30, 90, 255),   secondary = Color3.fromRGB(120, 180, 255), accent = Color3.fromRGB(80, 200, 255)  },
        ["Yellow"] = { primary = Color3.fromRGB(255, 210, 30),  secondary = Color3.fromRGB(255, 240, 120), accent = Color3.fromRGB(255, 170, 40)  },
        ["Purple"] = { primary = Color3.fromRGB(150, 50, 230),  secondary = Color3.fromRGB(200, 140, 255), accent = Color3.fromRGB(255, 120, 220) },
        ["Mor"]    = { primary = Color3.fromRGB(130, 40, 200),  secondary = Color3.fromRGB(180, 100, 255), accent = Color3.fromRGB(220, 80, 255)  },
        ["Green"]  = { primary = Color3.fromRGB(30, 220, 80),   secondary = Color3.fromRGB(120, 255, 160), accent = Color3.fromRGB(200, 255, 80)  },
        ["White"]  = { primary = Color3.fromRGB(240, 240, 255), secondary = Color3.fromRGB(200, 210, 255), accent = Color3.fromRGB(255, 255, 255) },
        ["Orange"] = { primary = Color3.fromRGB(255, 120, 20),  secondary = Color3.fromRGB(255, 180, 80),  accent = Color3.fromRGB(255, 220, 100) },
    }

    local function getKatanaPalette()
        local mode = tostring(katanaSkinColorMode or "Red")
        return KATANA_COLOR_PRESETS[mode] or KATANA_COLOR_PRESETS["Red"]
    end

    local function getKC()
        local p = getKatanaPalette()
        return {
            red  = p.primary,
            red2 = p.secondary,
            gold = p.accent,
        }
    end

    local State = {
        Skin = "KATANA",
        SkinOrder = { "KATANA", "NONE" },
        LastBat = nil,
        LastAppliedSkin = nil,
        OriginalKatanaTemplate = nil,
        ExactTemplates = {},
        ExactTemplateSearched = {},
        ExactAssetIds = { KATANA = "" },
        Original = {},
        ColorMode = "Red",
    }

    local function findBatForKatanaSkin()
        local char = LocalPlayer.Character
        if char then
            local t = char:FindFirstChild("Bat")
            if t and t:IsA("Tool") then return t end
        end
        local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
        if bp then
            local t = bp:FindFirstChild("Bat")
            if t and t:IsA("Tool") then return t end
        end
        return nil
    end

    local function setPartSafe(part)
        if not part or not part:IsA("BasePart") then return end
        part.Anchored    = false
        part.CanCollide  = false
        part.CanTouch    = false
        part.CanQuery    = false
        part.Massless    = true
    end

    local function weldToHandle(part, handle, c0)
        if not part or not handle or not part:IsA("BasePart") or not handle:IsA("BasePart") then return end
        setPartSafe(part)
        -- Remove old welds on this part
        for _, ch in ipairs(part:GetChildren()) do
            if ch:IsA("Weld") or ch:IsA("WeldConstraint") or ch:IsA("Motor6D") then
                pcall(function() ch:Destroy() end)
            end
        end
        local w = Instance.new("Weld")
        w.Name  = "FlowerSkin_AssetWeld"
        w.Part0 = handle
        w.Part1 = part
        w.C0    = c0 or CFrame.identity
        w.C1    = CFrame.identity
        w.Parent = part
        -- Snap part so it matches weld immediately
        pcall(function()
            part.CFrame = handle.CFrame * (c0 or CFrame.identity)
        end)
    end

    local function rememberOriginal(tool)
        if not tool then return end
        local handle = tool:FindFirstChild("Handle")
        local slash  = tool:FindFirstChild("Slash")
        State.Original[tool] = State.Original[tool] or {}
        local o = State.Original[tool]
        if handle and handle:IsA("BasePart") and not o.Handle then
            o.Handle = {
                Transparency = handle.Transparency,
                LocalTransparencyModifier = handle.LocalTransparencyModifier,
                CastShadow = handle.CastShadow,
            }
        end
        if slash and slash:IsA("Sound") and not o.SlashSoundId then
            o.SlashSoundId = slash.SoundId
        end
    end

    local function captureKatanaTemplate()
        if State.OriginalKatanaTemplate then return end
        local function scan(container)
            if not container then return end
            local bat = container:FindFirstChild("Bat")
            if not bat then return end
            local folder = bat:FindFirstChild("FlowerSkin_KatanaRealistic")
            local asset  = folder and folder:FindFirstChild("FlowerSkin_AssetKatana")
            if asset then State.OriginalKatanaTemplate = asset:Clone() end
        end
        scan(LocalPlayer:FindFirstChildOfClass("Backpack"))
        scan(LocalPlayer.Character)
    end

    local function hideOriginalHandle(tool, hidden)
        local handle = tool and tool:FindFirstChild("Handle")
        if not handle or not handle:IsA("BasePart") then return end
        rememberOriginal(tool)
        if hidden then
            handle.LocalTransparencyModifier = 1
            handle.Transparency = 1
            handle.CastShadow = false
        else
            local o = State.Original[tool] and State.Original[tool].Handle
            handle.LocalTransparencyModifier = o and o.LocalTransparencyModifier or 0
            handle.Transparency = o and o.Transparency or 0
            handle.CastShadow = o and o.CastShadow
            if handle.CastShadow == nil then handle.CastShadow = true end
        end
    end

    local function setSlashSound(tool, soundId)
        rememberOriginal(tool)
        local slash = tool and tool:FindFirstChild("Slash")
        if slash and slash:IsA("Sound") then
            slash.SoundId = soundId or ((State.Original[tool] and State.Original[tool].SlashSoundId) or slash.SoundId)
        end
    end

    local function removeSkin(tool)
        if not tool then return end
        local oldFolder = tool:FindFirstChild("FlowerSkin_KatanaRealistic")
        if oldFolder then oldFolder:Destroy() end
        local oldLoose = tool:FindFirstChild("FlowerSkin_AssetKatana")
        if oldLoose then oldLoose:Destroy() end
        hideOriginalHandle(tool, false)
        setSlashSound(tool, nil)
    end

    local function addRedVFX(parentPart)
        if not parentPart or not parentPart:IsA("BasePart") then return end
        local KC = getKC()
        local existing = parentPart:FindFirstChild("FlowerSkin_ExtraRedVFX")
        if existing then existing:Destroy() end

        local top = Instance.new("Attachment")
        top.Name = "FlowerSkin_ExtraRedVFX"
        top.Position = Vector3.new(0, parentPart.Size.Y * 0.5, 0)
        top.Parent = parentPart

        local bottom = Instance.new("Attachment")
        bottom.Name = "FlowerSkin_ExtraRedVFX_End"
        bottom.Position = Vector3.new(0, -parentPart.Size.Y * 0.5, 0)
        bottom.Parent = parentPart

        local trail = Instance.new("Trail")
        trail.Name = "FlowerSkin_ExtraRedVFX"
        trail.Attachment0 = top
        trail.Attachment1 = bottom
        trail.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, KC.red2),
            ColorSequenceKeypoint.new(1, KC.red),
        })
        trail.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.35),
            NumberSequenceKeypoint.new(1, 1),
        })
        trail.Lifetime = 0.18
        trail.LightEmission = 0.55
        trail.Parent = parentPart

        local emitter = Instance.new("ParticleEmitter")
        emitter.Name = "FlowerSkin_ExtraRedVFX"
        emitter.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, KC.red),
            ColorSequenceKeypoint.new(1, KC.red2),
        })
        emitter.LightEmission = 0.55
        emitter.Rate = 14
        emitter.Lifetime = NumberRange.new(0.25, 0.45)
        emitter.Speed = NumberRange.new(0.2, 0.7)
        emitter.SpreadAngle = Vector2.new(12, 12)
        emitter.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.08),
            NumberSequenceKeypoint.new(1, 0),
        })
        emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
        emitter.Parent = parentPart
    end

    
local function newPart(parent, name, size, offset, color, material)
        local p = Instance.new("Part")
        p.Name = name
        p.Size = size
        p.Color = color
        p.Material = material or Enum.Material.Neon
        p.TopSurface = Enum.SurfaceType.Smooth
        p.BottomSurface = Enum.SurfaceType.Smooth
        setPartSafe(p)
        p.Parent = parent
        return p, offset or CFrame.identity
    end

    local EXACT_TEMPLATE_NAMES = {
        KATANA = { "FlowerSkin_AssetKatana", "Katana", "FlowerSkin_KatanaRealistic" },
    }

    local function isScriptObject(inst)
        return inst:IsA("Script") or inst:IsA("LocalScript") or inst:IsA("ModuleScript")
    end

    local function stripScripts(root)
        if not root then return end
        if isScriptObject(root) then root:Destroy(); return end
        for _, inst in ipairs(root:GetDescendants()) do
            if isScriptObject(inst) then inst:Destroy() end
        end
    end

    local function hasAnyBasePart(root)
        if not root then return false end
        if root:IsA("BasePart") then return true end
        return root:FindFirstChildWhichIsA("BasePart", true) ~= nil
    end

    local function isGeneratedProxy(root)
        local ok, v = pcall(function() return root:GetAttribute("CursedBatSkinsGenerated") end)
        return ok and v == true
    end

    local function usableTemplate(root)
        if not root or isGeneratedProxy(root) then return nil end
        if root:IsA("Model") or root:IsA("Tool") or root:IsA("Folder") or root:IsA("BasePart") then
            if hasAnyBasePart(root) then return root end
        end
        return nil
    end

    local function findUsableNamed(root, names)
        if not root then return nil end
        for _, name in ipairs(names) do
            if root.Name == name then
                local d = usableTemplate(root)
                if d then return d end
            end
        end
        for _, name in ipairs(names) do
            local found = root:FindFirstChild(name, true)
            local u = usableTemplate(found)
            if u then return u end
        end
        return nil
    end

    local function assetTextFromId(assetId)
        local raw = tostring(assetId or ""):gsub("%s+", "")
        if raw == "" then return nil end
        if raw:match("^rbxassetid://") or raw:match("^rbxasset://") then return raw end
        if raw:match("^%d+$") then return "rbxassetid://" .. raw end
        return raw
    end

    local function loadExactTemplateFromAssetId(skinName)
        local assetText = assetTextFromId(State.ExactAssetIds[skinName])
        if not assetText then return nil end
        local loaded = {}
        pcall(function() loaded = game:GetObjects(assetText) end)
        if #loaded == 0 then
            local id = tostring(assetText):match("(%d+)")
            if id then
                pcall(function()
                    table.insert(loaded, InsertService:LoadAsset(tonumber(id)))
                end)
            end
        end
        local names = EXACT_TEMPLATE_NAMES[skinName] or {}
        for _, root in ipairs(loaded) do
            local exact = findUsableNamed(root, names) or usableTemplate(root)
            if exact then
                local clone = exact:Clone()
                stripScripts(clone)
                return clone
            end
        end
        return nil
    end

    local function findExactTemplateInGame(skinName)
        local names = EXACT_TEMPLATE_NAMES[skinName]
        if not names then return nil end
        local containers = {
            LocalPlayer.Character,
            LocalPlayer:FindFirstChildOfClass("Backpack"),
            ReplicatedStorage2,
            Lighting2,
            workspace,
        }
        for _, container in ipairs(containers) do
            local source = findUsableNamed(container, names)
            if source then
                local clone = source:Clone()
                stripScripts(clone)
                return clone
            end
        end
        return nil
    end

    local function getExactTemplate(skinName)
        if skinName == "KATANA" and State.OriginalKatanaTemplate then
            return State.OriginalKatanaTemplate
        end
        if State.ExactTemplates[skinName] then return State.ExactTemplates[skinName] end
        if State.ExactTemplateSearched[skinName] then return nil end
        State.ExactTemplateSearched[skinName] = true
        local loaded = loadExactTemplateFromAssetId(skinName) or findExactTemplateInGame(skinName)
        if loaded then State.ExactTemplates[skinName] = loaded end
        return loaded
    end

    local function containerToModel(clone, folder)
        if clone:IsA("Model") then
            clone.Name = "FlowerSkin_AssetKatana"
            clone.Parent = folder
            return clone
        end
        if clone:IsA("BasePart") then
            local model = Instance.new("Model")
            model.Name = "FlowerSkin_AssetKatana"
            model.Parent = folder
            clone.Parent = model
            return model
        end
        if clone:IsA("Tool") or clone:IsA("Folder") then
            local nested = clone:FindFirstChild("FlowerSkin_AssetKatana")
                or clone:FindFirstChildWhichIsA("Model")
                or clone:FindFirstChildWhichIsA("BasePart")
            if nested and nested.Parent == clone then
                nested.Parent = nil
                clone:Destroy()
                return containerToModel(nested, folder)
            end
            local model = Instance.new("Model")
            model.Name = "FlowerSkin_AssetKatana"
            model.Parent = folder
            for _, child in ipairs(clone:GetChildren()) do
                if not isScriptObject(child) then child.Parent = model end
            end
            clone:Destroy()
            return model
        end
        return nil
    end

    local function applyExactMesh(tool, skinName)
        local handle = tool and tool:FindFirstChild("Handle")
        if not handle or not handle:IsA("BasePart") then return false end
        local template = getExactTemplate(skinName)
        if not template then return false end

        local folder = Instance.new("Folder")
        folder.Name = "FlowerSkin_KatanaRealistic"
        folder.Parent = tool

        local model = containerToModel(template:Clone(), folder)
        if not model or not hasAnyBasePart(model) then
            folder:Destroy()
            return false
        end
        stripScripts(model)
        pcall(function() model:SetAttribute("CursedBatSkinsExactMesh", true) end)

        local firstPart
        for _, inst in ipairs(model:GetDescendants()) do
            if inst:IsA("BasePart") then
                firstPart = firstPart or inst
                setPartSafe(inst)
            end
        end
        if not firstPart then folder:Destroy(); return false end

        if model:IsA("Model") then
            model.PrimaryPart = model.PrimaryPart or firstPart
            pcall(function() model:PivotTo(handle.CFrame) end)
        end
        for _, inst in ipairs(model:GetDescendants()) do
            if inst:IsA("BasePart") then
                local rel = handle.CFrame:ToObjectSpace(inst.CFrame)
                weldToHandle(inst, handle, rel)
            end
        end

        local vfxPart = model:FindFirstChild("SharpParts", true)
            or model:FindFirstChild("WeaponPart", true)
            or model:FindFirstChild("Handle", true)
            or firstPart
        if vfxPart and not vfxPart:FindFirstChild("FlowerSkin_ExtraRedVFX") then
            addRedVFX(vfxPart)
        end
        return true
    end

    local function buildProxyModel(tool, skinName)
        local handle = tool and tool:FindFirstChild("Handle")
        if not handle or not handle:IsA("BasePart") then return nil end

        local folder = Instance.new("Folder")
        folder.Name = "FlowerSkin_KatanaRealistic"
        folder.Parent = tool

        local model = Instance.new("Model")
        model.Name = "FlowerSkin_AssetKatana"
        model:SetAttribute("CursedBatSkinsGenerated", true)
        model.Parent = folder

        local parts = {}
        -- Base orient: align blade with typical Bat Handle long axis (Y),
        -- slight tilt so it sits in the hand like a real sword grip.
        local BASE = CFrame.Angles(math.rad(-8), math.rad(0), math.rad(5))
        local function add(name, size, localCF, color, material)
            local p = newPart(model, name, size, CFrame.identity, color, material)
            local c0 = BASE * localCF
            weldToHandle(p, handle, c0)
            table.insert(parts, p)
            return p
        end

        if skinName == "KATANA" then
            local KC = getKC()
            -- Grip zone (sits on tool Handle in palm) → blade extends +Y
            add("Handle2", Vector3.new(0.22, 1.05, 0.22), CFrame.new(0, -0.55, 0), Color3.fromRGB(28, 22, 18), Enum.Material.SmoothPlastic)
            add("TsukaWrap", Vector3.new(0.24, 0.9, 0.24), CFrame.new(0, -0.5, 0), Color3.fromRGB(45, 32, 28), Enum.Material.Fabric)
            add("Tsuba", Vector3.new(0.62, 0.07, 0.42), CFrame.new(0, 0.05, 0), KC.gold, Enum.Material.Metal)
            local sharp = add("SharpParts", Vector3.new(0.16, 3.2, 0.07), CFrame.new(0, 1.7, 0), KC.red2, Enum.Material.Neon)
            add("WeaponPart", Vector3.new(0.2, 3.0, 0.05), CFrame.new(0.015, 1.65, 0), KC.red, Enum.Material.Neon)
            add("BladeEdge", Vector3.new(0.05, 2.95, 0.03), CFrame.new(-0.05, 1.62, 0), Color3.fromRGB(235, 240, 255), Enum.Material.Metal)
            add("NeonAccent", Vector3.new(0.48, 0.09, 0.32), CFrame.new(0, 0.05, 0), KC.gold, Enum.Material.Neon)
            addRedVFX(sharp)
        end
        model.PrimaryPart = parts[1]
        return model
    end

    local SKIN_SOUND_IDS = {
        KATANA = "rbxassetid://111808555599832",
    }

    local function applySkin(skinName)
        captureKatanaTemplate()
        local tool = findBatForKatanaSkin()
        if not tool then
            State.LastBat = nil
            State.LastAppliedSkin = nil
            return false
        end
        rememberOriginal(tool)
        removeSkin(tool)
        -- Minecraft Bat visual kalıntısını temizle
        pcall(function()
            local mc = tool:FindFirstChild("CustomUnionVisual")
            if mc then mc:Destroy() end
            local handle = tool:FindFirstChild("Handle")
            if handle then
                handle.Transparency = 0
            end
        end)
        if skinName == "NONE" then
            State.LastBat = tool
            State.LastAppliedSkin = skinName
            return true
        end
        hideOriginalHandle(tool, true)
        setSlashSound(tool, SKIN_SOUND_IDS[skinName])
        if not applyExactMesh(tool, skinName) then
            buildProxyModel(tool, skinName)
        end
        local handle = tool:FindFirstChild("Handle")
        if handle then
            local KC = getKC()
            local fire = handle:FindFirstChildOfClass("Fire") or handle:FindFirstChild("Fire")
            if fire and fire:IsA("Fire") then
                fire.Enabled = true
                fire.Color = KC.red
                fire.SecondaryColor = KC.red2
            end
        end
        -- Tint whole katana model to selected color (exact mesh + proxy)
        pcall(function()
            local KC = getKC()
            local folder = tool:FindFirstChild("FlowerSkin_KatanaRealistic")
            if not folder then return end
            for _, inst in ipairs(folder:GetDescendants()) do
                if inst:IsA("BasePart") then
                    local n = string.lower(inst.Name)
                    local isHandle = n:find("handle") or n:find("tsuka") or n:find("grip")
                    local isGuard  = n:find("tsuba") or n:find("guard") or n:find("accent") or n:find("neon")
                    local isEdge   = n:find("edge") or n:find("tip")
                    if isHandle then
                        -- keep dark handle
                    elseif isGuard then
                        inst.Color = KC.gold
                        inst.Material = Enum.Material.Neon
                    elseif isEdge then
                        inst.Color = Color3.fromRGB(240, 245, 255)
                    else
                        -- blade / body / unknown mesh parts -> primary color
                        inst.Color = KC.red
                        pcall(function()
                            if inst:IsA("MeshPart") then
                                -- force visible tint over baked textures
                                inst.TextureID = ""
                            end
                            if inst:IsA("UnionOperation") then
                                inst.UsePartColor = true
                            end
                        end)
                        local sm = inst:FindFirstChildWhichIsA("SpecialMesh")
                        if sm then
                            pcall(function()
                                sm.VertexColor = Vector3.new(KC.red.R, KC.red.G, KC.red.B)
                            end)
                        end
                        if n:find("sharp") or n:find("blade") or n:find("weapon") or n:find("katana") then
                            inst.Material = Enum.Material.Neon
                            inst.Color = KC.red2
                        end
                    end
                elseif inst:IsA("Trail") then
                    inst.Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, KC.red2),
                        ColorSequenceKeypoint.new(1, KC.red),
                    })
                elseif inst:IsA("ParticleEmitter") then
                    inst.Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, KC.red),
                        ColorSequenceKeypoint.new(1, KC.red2),
                    })
                elseif inst:IsA("Fire") then
                    inst.Color = KC.red
                    inst.SecondaryColor = KC.red2
                end
            end
        end)
        State.LastBat = tool
        State.LastAppliedSkin = skinName
        return true
    end

    return {
        State = State,
        ApplySkin = applySkin,
        SetColorMode = function(mode)
            State.ColorMode = tostring(mode or "Red")
            katanaSkinColorMode = State.ColorMode
            if katanaSkinEnabled then
                applySkin("KATANA")
            end
        end,
        SetExactAssetId = function(assetId)
            State.ExactAssetIds.KATANA = tostring(assetId or "")
            State.ExactTemplateSearched.KATANA = nil
            State.ExactTemplates.KATANA = nil
        end,
    }
end)()

_G.CursedBatKatana = KatanaSkin

task.spawn(function()
    while true do
        if katanaSkinEnabled then
            local bat
            local c = LP.Character
            if c then
                local t = c:FindFirstChild("Bat")
                if t and t:IsA("Tool") then bat = t end
            end
            if not bat then
                local bp = LP:FindFirstChildOfClass("Backpack")
                if bp then
                    local t = bp:FindFirstChild("Bat")
                    if t and t:IsA("Tool") then bat = t end
                end
            end
            if bat and (bat ~= KatanaSkin.State.LastBat or KatanaSkin.State.LastAppliedSkin ~= "KATANA") then
                pcall(function() KatanaSkin.ApplySkin("KATANA") end)
            end
        end
        task.wait(0.5)
    end
end)

minecraftBatSkinEnabled = false
minecraftBatSkinColorMode = "Default"
MinecraftBatSetVisual = nil
MinecraftBatColorSelector = nil

local MinecraftBatSkin = (function()
    local MB_ASSET_ID = "rbxassetid://18566246244"
    local MB_POS_OFFSET = _CFnew(-0.02, -0.52, -0.2)
    local MB_ROT_OFFSET = CFrame.Angles(math.rad(45), math.rad(0), math.rad(5))
    local MB_SCALE = 2

    local MB_COLORS = {
        ["Default"]       = nil,
        ["Red"]           = Color3.fromRGB(230, 30, 40),
        ["Abyss Blue"]    = Color3.fromRGB(0, 40, 150),
        ["Venom Green"]   = Color3.fromRGB(20, 255, 50),
        ["Royal Gold"]    = Color3.fromRGB(255, 200, 0),
        ["Velvet Rose"]   = Color3.fromRGB(220, 20, 100),
        ["Crimson Night"] = Color3.fromRGB(90, 0, 20),
    }

    local State = {
        enabled = false,
        colorMode = "Default",
        cachedVisualPart = nil,
        rgbConnection = nil,
    }

    local okLoad, objects = pcall(function() return game:GetObjects(MB_ASSET_ID) end)
    if okLoad and objects and #objects > 0 then
        local model = objects[1]
        State.cachedVisualPart = model:IsA("BasePart") and model
            or model:FindFirstChildWhichIsA("BasePart", true)
    end

    local function mbSetColor(visual, color)
        if not visual or not color then return end
        visual.Color = color
        if visual:IsA("UnionOperation") then
            pcall(function() visual.UsePartColor = true end)
        end
        local sm = visual:FindFirstChildWhichIsA("SpecialMesh")
        if sm then
            sm.VertexColor = Vector3.new(color.R, color.G, color.B)
        end
    end

    local function mbFindBat()
        local char = LP.Character
        if char then
            local t = char:FindFirstChild("Bat")
            if t and t:IsA("Tool") then return t end
        end
        local bp = LP:FindFirstChildOfClass("Backpack")
        if bp then
            local t = bp:FindFirstChild("Bat")
            if t and t:IsA("Tool") then return t end
        end
        return nil
    end

    local function mbRemoveVisual(tool)
        if not tool then return end
        local old = tool:FindFirstChild("CustomUnionVisual")
        if old then pcall(function() old:Destroy() end) end
        local handle = tool:FindFirstChild("Handle")
        if handle then
            handle.Transparency = 0
            for _, child in ipairs(handle:GetChildren()) do
                if child:IsA("SpecialMesh") or child:IsA("Mesh") or child:IsA("Decal") then
                    pcall(function() child.Transparency = 0 end)
                end
            end
        end
    end

    local function mbApplyVisual(tool)
        if not tool or tool.Name ~= "Bat" or not State.cachedVisualPart then return end
        local handle = tool:WaitForChild("Handle", 2)
        if not handle then return end

        local oldVisual = tool:FindFirstChild("CustomUnionVisual")
        if oldVisual then oldVisual:Destroy() end

        handle.Transparency = 1
        for _, child in ipairs(handle:GetChildren()) do
            if child:IsA("SpecialMesh") or child:IsA("Mesh") or child:IsA("Decal") then
                pcall(function() child.Transparency = 1 end)
            end
        end

        local newVisual = State.cachedVisualPart:Clone()
        newVisual.Name = "CustomUnionVisual"
        newVisual.CanCollide = false
        newVisual.Massless = true
        newVisual.Anchored = false

        local tempModel = Instance.new("Model")
        newVisual.Parent = tempModel
        tempModel.PrimaryPart = newVisual
        pcall(function() tempModel:ScaleTo(MB_SCALE) end)
        newVisual.Parent = nil
        tempModel:Destroy()

        if State.colorMode == "RGB" then
            mbSetColor(newVisual, Color3.fromHSV(tick() % 3 / 3, 1, 1))
        elseif MB_COLORS[State.colorMode] then
            mbSetColor(newVisual, MB_COLORS[State.colorMode])
        end

        for _, child in ipairs(newVisual:GetChildren()) do
            if child:IsA("Weld") or child:IsA("WeldConstraint") then child:Destroy() end
        end

        newVisual.CFrame = handle.CFrame * MB_POS_OFFSET * MB_ROT_OFFSET
        newVisual.Parent = tool

        local weld = Instance.new("WeldConstraint")
        weld.Part0 = handle
        weld.Part1 = newVisual
        weld.Parent = newVisual
    end

    local function mbStartRGB()
        if State.rgbConnection then return end
        State.rgbConnection = RunService.RenderStepped:Connect(function()
            if not State.enabled or State.colorMode ~= "RGB" then return end
            local tool = mbFindBat()
            if not tool then return end
            local visual = tool:FindFirstChild("CustomUnionVisual")
            if visual then
                mbSetColor(visual, Color3.fromHSV(tick() % 3 / 3, 1, 1))
            end
        end)
    end

    local function mbStopRGB()
        if State.rgbConnection then
            State.rgbConnection:Disconnect()
            State.rgbConnection = nil
        end
    end

    return {
        State   = State,
        Colors  = MB_COLORS,
        FindBat = mbFindBat,
        Apply   = function()
            if not State.enabled then return end
            local tool = mbFindBat()
            if tool then mbApplyVisual(tool) end
            if State.colorMode == "RGB" then mbStartRGB() end
        end,
        Remove  = function()
            mbStopRGB()
            local char = LP.Character
            if char then
                local t = char:FindFirstChild("Bat")
                if t then mbRemoveVisual(t) end
            end
            local bp = LP:FindFirstChildOfClass("Backpack")
            if bp then
                local t = bp:FindFirstChild("Bat")
                if t then mbRemoveVisual(t) end
            end
        end,
        SetColorMode = function(mode)
            State.colorMode = mode
            if not State.enabled then return end
            if mode == "RGB" then mbStartRGB() else mbStopRGB() end
            local tool = mbFindBat()
            if tool then mbApplyVisual(tool) end
        end,
    }
end)()

task.spawn(function()
    while true do
        if minecraftBatSkinEnabled and not katanaSkinEnabled then
            MinecraftBatSkin.State.enabled = true
            local tool = MinecraftBatSkin.FindBat()
            if tool and not tool:FindFirstChild("CustomUnionVisual") then
                pcall(MinecraftBatSkin.Apply)
            end
        else
            MinecraftBatSkin.State.enabled = false
        end
        task.wait(0.5)
    end
end)



-- ============================================================
-- SAKURA.VS PING LAGGER (Flux UI, rebranded)
-- ============================================================
local SakuraPingLagger = {
    active = false,
    remote = nil,
    gui = nil,
    brainrotMode = false,
    lastBrainrotState = false,
    manualOverride = false,
    isMinimized = false,
    antiLagEnabled = false,
    antiLagDescConn = nil,
    cfg = {
        power = 100000,
        interval = 0.125,
        keybindKb = "F",
        keybindGp = "ButtonY",
        autoActivate = true,
        antiLag = false,
        uiSize = 100,
    },
}

local function _splResolveKb(name)
    if not name or name == "" or name == "None" then return nil end
    local ok, val = pcall(function() return Enum.KeyCode[name] end)
    return (ok and val) or nil
end

local function _splFindRemote()
    local rrs = game:FindFirstChild("RobloxReplicatedStorage")
    if not rrs then return nil end
    for _, name in ipairs({"SetPlayerBlockList","UpdatePlayerBlockList","SetBlockList","UpdateBlockList"}) do
        local r = rrs:FindFirstChild(name)
        if r and r:IsA("RemoteEvent") then return r end
    end
    for _, c in ipairs(rrs:GetChildren()) do
        if c:IsA("RemoteEvent") and tostring(c.Name):find("Block") then return c end
    end
    return nil
end

local function _splBuildPayload(power)
    local main = {}
    local nested = {{}}
    local current = nested[1]
    for _ = 1, 186 do
        local n = {}
        table.insert(current, n)
        current = n
    end
    local maxRep = math.min(math.floor(power / 188), 10000)
    for _ = 1, maxRep do table.insert(main, nested) end
    return main
end

local function _splRunLoop()
    local delay = SakuraPingLagger.cfg.interval
    while SakuraPingLagger.active and SakuraPingLagger.remote do
        local payload = _splBuildPayload(SakuraPingLagger.cfg.power)
        local ok = pcall(function() SakuraPingLagger.remote:FireServer(payload) end)
        if not ok then
            delay = math.min(delay * 1.5, 0.5)
        else
            delay = math.max(delay * 0.995, 0.05)
        end
        task.wait(delay)
    end
end

function SakuraPingLagger.SetActive(state)
    SakuraPingLagger.active = state and true or false
    if SakuraPingLagger.active then
        if not SakuraPingLagger.remote then
            SakuraPingLagger.remote = _splFindRemote()
        end
        if not SakuraPingLagger.remote then
            SakuraPingLagger.active = false
            return false
        end
        task.spawn(_splRunLoop)
    end
    return SakuraPingLagger.active
end

function SakuraPingLagger.Toggle()
    return SakuraPingLagger.SetActive(not SakuraPingLagger.active)
end

local function _splApplyAntiLagDerender(obj)
    pcall(function()
        if obj:IsA("BasePart") then
            obj.Material = Enum.Material.Plastic
            obj.Reflectance = 0
            obj.CastShadow = false
        elseif obj:IsA("Decal") or obj:IsA("Texture") then
            obj.Transparency = 1
        elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam")
            or obj:IsA("Fire") or obj:IsA("Smoke") or obj:IsA("Sparkles") then
            obj.Enabled = false
        end
    end)
end

local function _splEnableAntiLag()
    SakuraPingLagger.antiLagEnabled = true
    task.spawn(function()
        local descs = Workspace:GetDescendants()
        local i = 0
        local total = #descs
        while i < total and SakuraPingLagger.antiLagEnabled do
            for _ = 1, 200 do
                i = i + 1
                if i > total then break end
                _splApplyAntiLagDerender(descs[i])
            end
            task.wait()
        end
    end)
    if SakuraPingLagger.antiLagDescConn then
        SakuraPingLagger.antiLagDescConn:Disconnect()
    end
    SakuraPingLagger.antiLagDescConn = Workspace.DescendantAdded:Connect(function(obj)
        if SakuraPingLagger.antiLagEnabled then _splApplyAntiLagDerender(obj) end
    end)
end

local function _splDisableAntiLag()
    SakuraPingLagger.antiLagEnabled = false
    if SakuraPingLagger.antiLagDescConn then
        SakuraPingLagger.antiLagDescConn:Disconnect()
        SakuraPingLagger.antiLagDescConn = nil
    end
end

function createSakuraPingLaggerPanel()
    if SakuraPingLagger.gui and SakuraPingLagger.gui.Parent then
        SakuraPingLagger.gui.Enabled = true
        return SakuraPingLagger.gui
    end

    local assetId = tostring(BUTTON_ASSET_ID or "124268985896208")
    local ASSET_OPEN = "rbxassetid://" .. assetId
    local ASSET_CLOSED = "rbxassetid://" .. assetId
    local OPEN_W, OPEN_H = 275, 435
    local CLOSED_W, CLOSED_H = 280, 95

    local C = {
        white = Color3.fromRGB(255,255,255),
        offWhite = Color3.fromRGB(230,230,230),
        gray = Color3.fromRGB(165,165,165),
        inputBg = Color3.fromRGB(18,18,25),
        toggleOn = Color3.fromRGB(60,255,110),
        toggleOff = Color3.fromRGB(45,45,55),
        red = Color3.fromRGB(255,50,50),
        green = Color3.fromRGB(60,255,110),
        yellow = Color3.fromRGB(255,205,60),
    }

    local cfg = SakuraPingLagger.cfg

    -- destroy old
    pcall(function()
        local pg = LP:FindFirstChildOfClass("PlayerGui")
        if pg then
            for _, n in ipairs({"SakuraVsPingLagger", "FluxPingLaggerGui", "BlessPingLaggerGui"}) do
                local o = pg:FindFirstChild(n)
                if o then o:Destroy() end
            end
        end
        local cg = game:GetService("CoreGui")
        for _, n in ipairs({"SakuraVsPingLagger", "FluxPingLaggerGui"}) do
            local o = cg:FindFirstChild(n)
            if o then o:Destroy() end
        end
    end)

    local screen = Instance.new("ScreenGui")
    screen.Name = "SakuraVsPingLagger"
    screen.ResetOnSpawn = false
    screen.DisplayOrder = 28
    screen.IgnoreGuiInset = true
    pcall(function()
        if syn and syn.protect_gui then syn.protect_gui(screen) end
        screen.Parent = game:GetService("CoreGui")
    end)
    if not screen.Parent then screen.Parent = LP:WaitForChild("PlayerGui") end
    SakuraPingLagger.gui = screen

    local function tw(obj, props, t)
        TS:Create(obj, TweenInfo.new(t or 0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
    end

    local function makeDraggable(frame)
        local dragging, dragStart, startPos
        frame.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = i.Position
                startPos = frame.Position
                i.Changed:Connect(function()
                    if i.UserInputState == Enum.UserInputState.End then dragging = false end
                end)
            end
        end)
        frame.InputChanged:Connect(function(i)
            if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                local d = i.Position - dragStart
                frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end)
    end

    local function getScale()
        return math.clamp(cfg.uiSize / 100, 0.7, 1.35)
    end

    local mainFrame = Instance.new("ImageLabel")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, OPEN_W, 0, OPEN_H)
    mainFrame.Position = UDim2.new(0.55, -OPEN_W/2, 0.22, 0)
    mainFrame.BackgroundColor3 = Color3.fromRGB(6, 6, 10)
    mainFrame.BackgroundTransparency = 0
    mainFrame.Image = ASSET_OPEN
    mainFrame.ScaleType = Enum.ScaleType.Crop
    mainFrame.Active = true
    mainFrame.ClipsDescendants = true
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screen
    Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 16)
    task.delay(0.4, function()
        if mainFrame and mainFrame.Parent then
            pcall(function()
                mainFrame.Image = "rbxthumb://type=Asset&id=" .. assetId .. "&w=420&h=420"
            end)
        end
    end)
    makeDraggable(mainFrame)

    local darkOv = Instance.new("Frame", mainFrame)
    darkOv.Size = UDim2.new(1,0,1,0)
    darkOv.BackgroundColor3 = Color3.fromRGB(0,0,0)
    darkOv.BackgroundTransparency = 0.42
    darkOv.BorderSizePixel = 0
    darkOv.ZIndex = 1
    Instance.new("UICorner", darkOv).CornerRadius = UDim.new(0, 16)

    local content = Instance.new("Frame")
    content.Name = "Content"
    content.Size = UDim2.new(1, 0, 1, 0)
    content.BackgroundTransparency = 1
    content.Visible = true
    content.ZIndex = 2
    content.Parent = mainFrame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(0.72, 0, 0, 20)
    title.Position = UDim2.new(0.055, 0, 0.025, 0)
    title.BackgroundTransparency = 1
    title.Text = "SAKURA.VS"
    title.TextColor3 = Color3.fromRGB(255, 140, 0)
    title.Font = Enum.Font.GothamBlack
    title.TextSize = 14
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.ZIndex = 3
    title.Parent = content

    local subTitle = Instance.new("TextLabel")
    subTitle.Size = UDim2.new(0.5, 0, 0, 14)
    subTitle.Position = UDim2.new(0.055, 0, 0.065, 0)
    subTitle.BackgroundTransparency = 1
    subTitle.Text = "PING LAGGER"
    subTitle.TextColor3 = C.offWhite
    subTitle.Font = Enum.Font.GothamBold
    subTitle.TextSize = 11
    subTitle.TextXAlignment = Enum.TextXAlignment.Left
    subTitle.ZIndex = 3
    subTitle.Parent = content

    local minBtn = Instance.new("TextButton")
    minBtn.Size = UDim2.new(0, 26, 0, 26)
    minBtn.Position = UDim2.new(1, -34, 0.020, 0)
    minBtn.BackgroundColor3 = Color3.fromRGB(28,28,38)
    minBtn.BackgroundTransparency = 0.3
    minBtn.BorderSizePixel = 0
    minBtn.Text = "−"
    minBtn.TextColor3 = C.white
    minBtn.Font = Enum.Font.GothamBlack
    minBtn.TextSize = 18
    minBtn.AutoButtonColor = false
    minBtn.ZIndex = 6
    minBtn.Parent = content
    Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 7)

    local uiLbl = Instance.new("TextLabel")
    uiLbl.Size = UDim2.new(0.26, 0, 0, 15)
    uiLbl.Position = UDim2.new(0.055, 0, 0.110, 0)
    uiLbl.BackgroundTransparency = 1
    uiLbl.Text = "UI SIZE"
    uiLbl.TextColor3 = C.offWhite
    uiLbl.Font = Enum.Font.GothamBold
    uiLbl.TextSize = 11
    uiLbl.TextXAlignment = Enum.TextXAlignment.Left
    uiLbl.ZIndex = 3
    uiLbl.Parent = content

    local uiVal = Instance.new("TextLabel")
    uiVal.Size = UDim2.new(0, 32, 0, 15)
    uiVal.Position = UDim2.new(0.30, 0, 0.110, 0)
    uiVal.BackgroundTransparency = 1
    uiVal.Text = tostring(cfg.uiSize)
    uiVal.TextColor3 = C.white
    uiVal.Font = Enum.Font.GothamBold
    uiVal.TextSize = 12
    uiVal.ZIndex = 3
    uiVal.Parent = content

    local uiMinus = Instance.new("TextButton")
    uiMinus.Size = UDim2.new(0, 24, 0, 24)
    uiMinus.Position = UDim2.new(0.48, 0, 0.102, 0)
    uiMinus.BackgroundColor3 = Color3.fromRGB(32,32,45)
    uiMinus.BackgroundTransparency = 0.2
    uiMinus.BorderSizePixel = 0
    uiMinus.Text = "−"
    uiMinus.TextColor3 = C.white
    uiMinus.Font = Enum.Font.GothamBlack
    uiMinus.TextSize = 15
    uiMinus.AutoButtonColor = false
    uiMinus.ZIndex = 3
    uiMinus.Parent = content
    Instance.new("UICorner", uiMinus).CornerRadius = UDim.new(0, 6)

    local uiPlus = Instance.new("TextButton")
    uiPlus.Size = UDim2.new(0, 24, 0, 24)
    uiPlus.Position = UDim2.new(0.59, 0, 0.102, 0)
    uiPlus.BackgroundColor3 = Color3.fromRGB(32,32,45)
    uiPlus.BackgroundTransparency = 0.2
    uiPlus.BorderSizePixel = 0
    uiPlus.Text = "+"
    uiPlus.TextColor3 = C.white
    uiPlus.Font = Enum.Font.GothamBlack
    uiPlus.TextSize = 15
    uiPlus.AutoButtonColor = false
    uiPlus.ZIndex = 3
    uiPlus.Parent = content
    Instance.new("UICorner", uiPlus).CornerRadius = UDim.new(0, 6)

    local keyDisp = Instance.new("TextLabel")
    keyDisp.Size = UDim2.new(0, 72, 0, 16)
    keyDisp.Position = UDim2.new(1, -105, 0.110, 0)
    keyDisp.BackgroundTransparency = 1
    keyDisp.Text = (cfg.keybindGp ~= "None" and cfg.keybindGp) or cfg.keybindKb
    keyDisp.TextColor3 = C.yellow
    keyDisp.Font = Enum.Font.GothamBold
    keyDisp.TextSize = 11
    keyDisp.TextXAlignment = Enum.TextXAlignment.Right
    keyDisp.ZIndex = 3
    keyDisp.Parent = content

    local disc = Instance.new("TextLabel")
    disc.Size = UDim2.new(0.7, 0, 0, 13)
    disc.Position = UDim2.new(0.055, 0, 0.155, 0)
    disc.BackgroundTransparency = 1
    disc.Text = "discord.gg/sakuraduels"
    disc.TextColor3 = C.gray
    disc.Font = Enum.Font.Gotham
    disc.TextSize = 10
    disc.TextXAlignment = Enum.TextXAlignment.Left
    disc.ZIndex = 3
    disc.Parent = content

    local pLbl = Instance.new("TextLabel")
    pLbl.Size = UDim2.new(0.4, 0, 0, 14)
    pLbl.Position = UDim2.new(0.055, 0, 0.195, 0)
    pLbl.BackgroundTransparency = 1
    pLbl.Text = "POWER"
    pLbl.TextColor3 = C.offWhite
    pLbl.Font = Enum.Font.GothamBold
    pLbl.TextSize = 11
    pLbl.TextXAlignment = Enum.TextXAlignment.Left
    pLbl.ZIndex = 3
    pLbl.Parent = content

    local powerBox = Instance.new("TextBox")
    powerBox.Size = UDim2.new(0.89, 0, 0, 32)
    powerBox.Position = UDim2.new(0.055, 0, 0.228, 0)
    powerBox.BackgroundColor3 = C.inputBg
    powerBox.BackgroundTransparency = 0.12
    powerBox.BorderSizePixel = 0
    powerBox.Text = tostring(cfg.power)
    powerBox.TextColor3 = C.white
    powerBox.Font = Enum.Font.GothamBold
    powerBox.TextSize = 14
    powerBox.ClearTextOnFocus = false
    powerBox.ZIndex = 3
    powerBox.Parent = content
    Instance.new("UICorner", powerBox).CornerRadius = UDim.new(0, 9)

    local dLbl = Instance.new("TextLabel")
    dLbl.Size = UDim2.new(0.4, 0, 0, 14)
    dLbl.Position = UDim2.new(0.055, 0, 0.320, 0)
    dLbl.BackgroundTransparency = 1
    dLbl.Text = "DELAY"
    dLbl.TextColor3 = C.offWhite
    dLbl.Font = Enum.Font.GothamBold
    dLbl.TextSize = 11
    dLbl.TextXAlignment = Enum.TextXAlignment.Left
    dLbl.ZIndex = 3
    dLbl.Parent = content

    local delayBox = Instance.new("TextBox")
    delayBox.Size = UDim2.new(0.89, 0, 0, 32)
    delayBox.Position = UDim2.new(0.055, 0, 0.353, 0)
    delayBox.BackgroundColor3 = C.inputBg
    delayBox.BackgroundTransparency = 0.12
    delayBox.BorderSizePixel = 0
    delayBox.Text = tostring(cfg.interval)
    delayBox.TextColor3 = C.white
    delayBox.Font = Enum.Font.GothamBold
    delayBox.TextSize = 14
    delayBox.ClearTextOnFocus = false
    delayBox.ZIndex = 3
    delayBox.Parent = content
    Instance.new("UICorner", delayBox).CornerRadius = UDim.new(0, 9)

    local function makeToggle(y, text, initial, cb)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(0.89, 0, 0, 28)
        row.Position = UDim2.new(0.055, 0, y, 0)
        row.BackgroundTransparency = 1
        row.ZIndex = 3
        row.Parent = content

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(0.62, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = text
        lbl.TextColor3 = C.offWhite
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 12
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.ZIndex = 3
        lbl.Parent = row

        local track = Instance.new("Frame")
        track.Size = UDim2.new(0, 48, 0, 26)
        track.Position = UDim2.new(1, -48, 0.5, -13)
        track.BackgroundColor3 = initial and C.toggleOn or C.toggleOff
        track.BorderSizePixel = 0
        track.ZIndex = 3
        track.Parent = row
        Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

        local knob = Instance.new("Frame")
        knob.Size = UDim2.new(0, 22, 0, 22)
        knob.Position = initial and UDim2.new(1, -24, 0.5, -11) or UDim2.new(0, 2, 0.5, -11)
        knob.BackgroundColor3 = C.white
        knob.BorderSizePixel = 0
        knob.ZIndex = 4
        knob.Parent = track
        Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 1, 0)
        btn.BackgroundTransparency = 1
        btn.Text = ""
        btn.ZIndex = 5
        btn.Parent = track

        local state = initial
        btn.MouseButton1Click:Connect(function()
            state = not state
            tw(track, {BackgroundColor3 = state and C.toggleOn or C.toggleOff}, 0.12)
            tw(knob, {Position = state and UDim2.new(1, -24, 0.5, -11) or UDim2.new(0, 2, 0.5, -11)}, 0.12)
            cb(state)
        end)

        return {
            set = function(v)
                state = v
                track.BackgroundColor3 = v and C.toggleOn or C.toggleOff
                knob.Position = v and UDim2.new(1, -24, 0.5, -11) or UDim2.new(0, 2, 0.5, -11)
            end
        }
    end

    local autoT = makeToggle(0.445, "AUTO ACTIVATE", cfg.autoActivate, function(v)
        cfg.autoActivate = v
        pcall(saveAllSettings)
    end)

    local antiT = makeToggle(0.520, "ANTILAG", cfg.antiLag, function(v)
        cfg.antiLag = v
        if v then _splEnableAntiLag() else _splDisableAntiLag() end
        pcall(saveAllSettings)
    end)

    local mainBtn = Instance.new("TextButton")
    mainBtn.Size = UDim2.new(0.89, 0, 0, 44)
    mainBtn.Position = UDim2.new(0.055, 0, 0.610, 0)
    mainBtn.BackgroundColor3 = Color3.fromRGB(30,30,40)
    mainBtn.BackgroundTransparency = 0.08
    mainBtn.BorderSizePixel = 0
    mainBtn.Text = "OFF"
    mainBtn.TextColor3 = C.red
    mainBtn.Font = Enum.Font.GothamBlack
    mainBtn.TextSize = 17
    mainBtn.AutoButtonColor = false
    mainBtn.ZIndex = 3
    mainBtn.Parent = content
    Instance.new("UICorner", mainBtn).CornerRadius = UDim.new(0, 11)
    local mStroke = Instance.new("UIStroke", mainBtn)
    mStroke.Color = C.red
    mStroke.Thickness = 1.6
    mStroke.Transparency = 0.15

    local saveBtn = Instance.new("TextButton")
    saveBtn.Size = UDim2.new(0.89, 0, 0, 32)
    saveBtn.Position = UDim2.new(0.055, 0, 0.740, 0)
    saveBtn.BackgroundColor3 = Color3.fromRGB(28,28,38)
    saveBtn.BackgroundTransparency = 0.12
    saveBtn.BorderSizePixel = 0
    saveBtn.Text = "CLOSE / HIDE"
    saveBtn.TextColor3 = C.white
    saveBtn.Font = Enum.Font.GothamBold
    saveBtn.TextSize = 13
    saveBtn.AutoButtonColor = false
    saveBtn.ZIndex = 3
    saveBtn.Parent = content
    Instance.new("UICorner", saveBtn).CornerRadius = UDim.new(0, 9)

    -- CLOSED (minimized) bar
    local closed = Instance.new("Frame")
    closed.Name = "ClosedContent"
    closed.Size = UDim2.new(1, 0, 1, 0)
    closed.BackgroundTransparency = 1
    closed.Visible = false
    closed.ZIndex = 2
    closed.Parent = mainFrame

    local cTitle = Instance.new("TextLabel")
    cTitle.Size = UDim2.new(0.70, 0, 0, 18)
    cTitle.Position = UDim2.new(0.05, 0, 0.15, 0)
    cTitle.BackgroundTransparency = 1
    cTitle.Text = "SAKURA.VS"
    cTitle.TextColor3 = C.white
    cTitle.Font = Enum.Font.GothamBlack
    cTitle.TextSize = 12
    cTitle.TextXAlignment = Enum.TextXAlignment.Left
    cTitle.ZIndex = 3
    cTitle.Parent = closed

    local cUi = Instance.new("TextLabel")
    cUi.Size = UDim2.new(0.26, 0, 0, 14)
    cUi.Position = UDim2.new(0.05, 0, 0.46, 0)
    cUi.BackgroundTransparency = 1
    cUi.Text = "UI SIZE"
    cUi.TextColor3 = C.offWhite
    cUi.Font = Enum.Font.GothamBold
    cUi.TextSize = 10
    cUi.TextXAlignment = Enum.TextXAlignment.Left
    cUi.ZIndex = 3
    cUi.Parent = closed

    local cVal = Instance.new("TextLabel")
    cVal.Size = UDim2.new(0, 30, 0, 14)
    cVal.Position = UDim2.new(0.30, 0, 0.46, 0)
    cVal.BackgroundTransparency = 1
    cVal.Text = tostring(cfg.uiSize)
    cVal.TextColor3 = C.white
    cVal.Font = Enum.Font.GothamBold
    cVal.TextSize = 11
    cVal.ZIndex = 3
    cVal.Parent = closed

    local cStatus = Instance.new("TextButton")
    cStatus.Name = "CStatus"
    cStatus.Size = UDim2.new(0, 56, 0, 16)
    cStatus.Position = UDim2.new(0.42, 0, 0.45, 0)
    cStatus.BackgroundTransparency = 1
    cStatus.Text = SakuraPingLagger.active and "ON" or "KAPALI"
    cStatus.TextColor3 = SakuraPingLagger.active and C.green or C.red
    cStatus.Font = Enum.Font.GothamBlack
    cStatus.TextSize = 11
    cStatus.AutoButtonColor = false
    cStatus.ZIndex = 3
    cStatus.Parent = closed

    local cPlus = Instance.new("TextButton")
    cPlus.Size = UDim2.new(0, 26, 0, 26)
    cPlus.Position = UDim2.new(1, -36, 0.14, 0)
    cPlus.BackgroundColor3 = Color3.fromRGB(32,32,45)
    cPlus.BackgroundTransparency = 0.25
    cPlus.BorderSizePixel = 0
    cPlus.Text = "+"
    cPlus.TextColor3 = C.white
    cPlus.Font = Enum.Font.GothamBlack
    cPlus.TextSize = 16
    cPlus.AutoButtonColor = false
    cPlus.ZIndex = 6
    cPlus.Parent = closed
    Instance.new("UICorner", cPlus).CornerRadius = UDim.new(0, 7)

    local cDisc = Instance.new("TextLabel")
    cDisc.Size = UDim2.new(0.6, 0, 0, 12)
    cDisc.Position = UDim2.new(0.05, 0, 0.70, 0)
    cDisc.BackgroundTransparency = 1
    cDisc.Text = "discord.gg/sakuraduels"
    cDisc.TextColor3 = C.gray
    cDisc.Font = Enum.Font.Gotham
    cDisc.TextSize = 9
    cDisc.TextXAlignment = Enum.TextXAlignment.Left
    cDisc.ZIndex = 3
    cDisc.Parent = closed

    local cKey = Instance.new("TextLabel")
    cKey.Size = UDim2.new(0, 70, 0, 14)
    cKey.Position = UDim2.new(1, -100, 0.46, 0)
    cKey.BackgroundTransparency = 1
    cKey.Text = (cfg.keybindGp ~= "None" and cfg.keybindGp) or cfg.keybindKb
    cKey.TextColor3 = C.yellow
    cKey.Font = Enum.Font.GothamBold
    cKey.TextSize = 11
    cKey.TextXAlignment = Enum.TextXAlignment.Right
    cKey.ZIndex = 3
    cKey.Parent = closed

    local function applySize()
        local s = getScale()
        if SakuraPingLagger.isMinimized then
            mainFrame.Size = UDim2.new(0, CLOSED_W * s, 0, CLOSED_H * s)
        else
            mainFrame.Size = UDim2.new(0, OPEN_W * s, 0, OPEN_H * s)
        end
        uiVal.Text = tostring(cfg.uiSize)
        cVal.Text = tostring(cfg.uiSize)
    end

    local function setMin(state)
        SakuraPingLagger.isMinimized = state
        if state then
            mainFrame.Image = ASSET_CLOSED
            content.Visible = false
            closed.Visible = true
        else
            mainFrame.Image = ASSET_OPEN
            content.Visible = true
            closed.Visible = false
        end
        applySize()
    end

    local function updateBtn()
        if SakuraPingLagger.active then
            mainBtn.Text = "ON"
            mainBtn.TextColor3 = C.green
            mStroke.Color = C.green
            if cStatus then cStatus.Text = "ON"; cStatus.TextColor3 = C.green end
        else
            mainBtn.Text = "OFF"
            mainBtn.TextColor3 = C.red
            mStroke.Color = C.red
            if cStatus then cStatus.Text = "KAPALI"; cStatus.TextColor3 = C.red end
        end
    end

    local function flipLag(state)
        SakuraPingLagger.SetActive(state)
        updateBtn()
    end

    minBtn.MouseButton1Click:Connect(function() setMin(true) end)
    cPlus.MouseButton1Click:Connect(function() setMin(false) end)

    uiMinus.MouseButton1Click:Connect(function()
        cfg.uiSize = math.max(65, cfg.uiSize - 5)
        applySize()
        pcall(saveAllSettings)
    end)
    uiPlus.MouseButton1Click:Connect(function()
        cfg.uiSize = math.min(145, cfg.uiSize + 5)
        applySize()
        pcall(saveAllSettings)
    end)

    powerBox.FocusLost:Connect(function()
        local n = tonumber(powerBox.Text)
        if n then
            cfg.power = math.max(1, math.floor(n))
            powerBox.Text = tostring(cfg.power)
            pcall(saveAllSettings)
        else
            powerBox.Text = tostring(cfg.power)
        end
    end)
    delayBox.FocusLost:Connect(function()
        local n = tonumber(delayBox.Text)
        if n then
            cfg.interval = math.max(0.01, n)
            delayBox.Text = tostring(cfg.interval)
            pcall(saveAllSettings)
        else
            delayBox.Text = tostring(cfg.interval)
        end
    end)

    mainBtn.MouseButton1Click:Connect(function() flipLag(not SakuraPingLagger.active) end)
    cStatus.MouseButton1Click:Connect(function() flipLag(not SakuraPingLagger.active) end)

    saveBtn.MouseButton1Click:Connect(function()
        screen.Enabled = false
    end)

    -- auto activate on brainrot / low walkspeed
    RunService.Heartbeat:Connect(function()
        if not cfg.autoActivate then
            if SakuraPingLagger.brainrotMode then
                SakuraPingLagger.brainrotMode = false
                SakuraPingLagger.lastBrainrotState = false
            end
            return
        end
        local char = LP.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hum then return end
        local has = hum.WalkSpeed > 0 and hum.WalkSpeed < 25
        if has and not SakuraPingLagger.lastBrainrotState then
            SakuraPingLagger.brainrotMode = true
            SakuraPingLagger.lastBrainrotState = true
            flipLag(true)
        elseif not has and SakuraPingLagger.lastBrainrotState then
            SakuraPingLagger.brainrotMode = false
            SakuraPingLagger.lastBrainrotState = false
            flipLag(false)
        end
    end)

    -- keybinds
    UIS.InputBegan:Connect(function(input, processed)
        if processed or UIS:GetFocusedTextBox() then return end
        local kc = input.KeyCode
        if kc == Enum.KeyCode.Unknown then return end
        local isGp = tostring(input.UserInputType):find("Gamepad") ~= nil
            or (kc.Name:sub(1,6) == "Button")
        local isKb = input.UserInputType == Enum.UserInputType.Keyboard
        local kbE = _splResolveKb(cfg.keybindKb)
        local gpE = _splResolveKb(cfg.keybindGp)
        if (kbE and kc == kbE and isKb) or (gpE and kc == gpE and isGp) then
            flipLag(not SakuraPingLagger.active)
        end
    end)

    applySize()
    updateBtn()
    autoT.set(cfg.autoActivate)
    antiT.set(cfg.antiLag)
    if cfg.antiLag then _splEnableAntiLag() end
    screen.Enabled = true
    return screen
end

_G.SakuraPingLagger = SakuraPingLagger


function buildGui()
    -- Sakura.vs orange theme
    local LIGHT_ORANGE = Color3.fromRGB(255, 190, 115)
    local SOFT_ORANGE = Color3.fromRGB(255, 165, 75)
    local SILVER = LIGHT_ORANGE
    local SILVER_DARK = Color3.fromRGB(55, 38, 22)
    local SILVER_LIGHT = LIGHT_ORANGE
    local BG = Color3.fromRGB(10, 11, 13)
    local BG2 = Color3.fromRGB(16, 17, 20)
    local ROW_BG = Color3.fromRGB(16, 17, 20)
    local ROW_BORDER = Color3.fromRGB(115, 72, 30)
    local WHITE = LIGHT_ORANGE
    local BLACK = Color3.fromRGB(0, 0, 0)
    local GRAY = Color3.fromRGB(205, 150, 95)
    local INP = LIGHT_ORANGE
    local OFF = Color3.fromRGB(235, 165, 95)
    local TAB_ACTIVE = LIGHT_ORANGE
    local TAB_INACT = Color3.fromRGB(70, 45, 24)
    local SECT_LBL = LIGHT_ORANGE
    local HOV = Color3.fromRGB(255, 205, 140)
    local DOT_ON = BLACK
    local ON_COLOR = Color3.fromRGB(255, 140, 0)
    local STROKE_COLOR = Color3.fromRGB(80, 80, 80)
    local GUI_W, GUI_H = 420, 528

    local old = game:GetService("CoreGui"):FindFirstChild("Sakura.vs")
    if old then old:Destroy() end
    local pg = LP:FindFirstChild("PlayerGui")
    if pg then local o = pg:FindFirstChild("Sakura.vs"); if o then o:Destroy() end end

    gui = Instance.new("ScreenGui")
    gui.Name = "Sakura.vs"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 10
    gui.IgnoreGuiInset = true
    pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
    local guiOk = pcall(function() gui.Parent = game:GetService("CoreGui") end)
    if not guiOk then gui.Parent = LP:WaitForChild("PlayerGui") end

    main = Instance.new("Frame", gui)
    main.Size = UDim2.new(0, GUI_W, 0, GUI_H)
    main.Position = UDim2.new(0, -GUI_W - 20, 0, 18)
    main.Visible = false
    main.BackgroundColor3 = BG
    main.BackgroundTransparency = 0.55
    main.BorderSizePixel = 0
    main.ClipsDescendants = true
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 18)
    local mainStroke = Instance.new("UIStroke", main)
    mainStroke.Color = Color3.fromRGB(255, 140, 0)
    mainStroke.Thickness = 1.5
    mainStroke.Transparency = 0.2

    local bgImage = Instance.new("ImageLabel")
    bgImage.Name = "BackgroundImage"
    bgImage.Size = UDim2.new(1, 0, 1, 0)
    bgImage.Position = UDim2.new(0, 0, 0, 0)
    bgImage.BackgroundTransparency = 1
    bgImage.BorderSizePixel = 0
    bgImage.ScaleType = Enum.ScaleType.Crop
    bgImage.ZIndex = 0
    bgImage.Visible = true
    bgImage.ClipsDescendants = true
    bgImage.Parent = main
    Instance.new("UICorner", bgImage).CornerRadius = UDim.new(0, 18)
    _mainBgImage = bgImage
    applyBackgroundImage(bgImage)

    -- dark wash so rows/text stay readable (like Sakura.vs overlay)
    local bgWash = Instance.new("Frame")
    bgWash.Name = "BackgroundWash"
    bgWash.Size = UDim2.new(1, 0, 1, 0)
    bgWash.BackgroundColor3 = Color3.fromRGB(10, 11, 13)
    bgWash.BackgroundTransparency = 0.72
    bgWash.BorderSizePixel = 0
    bgWash.ZIndex = 2
    bgWash.Parent = main
    Instance.new("UICorner", bgWash).CornerRadius = UDim.new(0, 18)

    main.BackgroundColor3 = Color3.fromRGB(10, 11, 13)
    main.BackgroundTransparency = 0.75


    mainUIScale = Instance.new("UIScale", main)
    mainUIScale.Scale = uiScaleValue / 100

    -- Logo image removed (was covering background)

    local titleFrame = Instance.new("Frame", main)
    titleFrame.Name = "TitleFrame"
    titleFrame.Size = UDim2.new(1, -100, 0, 44)
    titleFrame.Position = UDim2.new(0, 10, 0, 4)
    titleFrame.BackgroundColor3 = Color3.fromRGB(8, 10, 14)
    titleFrame.BackgroundTransparency = 0.18
    titleFrame.BorderSizePixel = 0
    titleFrame.ClipsDescendants = true
    titleFrame.ZIndex = 20
    Instance.new("UICorner", titleFrame).CornerRadius = UDim.new(0, 12)
    -- Title cyan/blue stroke removed (was showing under Sakura.vs)
    local titleStroke = Instance.new("UIStroke", titleFrame)
    titleStroke.Color = Color3.fromRGB(40, 42, 48)
    titleStroke.Thickness = 1
    titleStroke.Transparency = 0.85

    local titleBg = Instance.new("ImageLabel", titleFrame)
    titleBg.Name = "TitleAssetBg"
    titleBg.Size = UDim2.new(1, 0, 1, 0)
    titleBg.BackgroundTransparency = 1
    titleBg.ScaleType = Enum.ScaleType.Crop
    titleBg.ImageTransparency = 0.12
    titleBg.ZIndex = 20
    titleBg.Visible = false -- no image behind Sakura.vs
    Instance.new("UICorner", titleBg).CornerRadius = UDim.new(0, 12)
    local titleWash = Instance.new("Frame", titleFrame)
    titleWash.Size = UDim2.new(1, 0, 1, 0)
    titleWash.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    titleWash.BackgroundTransparency = 0.5
    titleWash.BorderSizePixel = 0
    titleWash.ZIndex = 21
    Instance.new("UICorner", titleWash).CornerRadius = UDim.new(0, 12)

    local titleLabel = Instance.new("TextLabel", titleFrame)
    titleLabel.Name = "TitleLabel"
    titleLabel.Size = UDim2.new(1, -12, 0, 22)
    titleLabel.Position = UDim2.new(0, 10, 0, 2)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "Sakura.vs"
    titleLabel.TextColor3 = Color3.fromRGB(255, 140, 0)
    titleLabel.Font = Enum.Font.GothamBlack
    titleLabel.TextSize = 18
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    titleLabel.TextStrokeTransparency = 0.3
    titleLabel.ZIndex = 23
    applyShimmerToText(titleLabel, 0.9)

    local discordTitle = Instance.new("TextLabel", titleFrame)
    discordTitle.Name = "DiscordText"
    discordTitle.Size = UDim2.new(1, -12, 0, 16)
    discordTitle.Position = UDim2.new(0, 10, 0, 24)
    discordTitle.BackgroundTransparency = 1
    discordTitle.Text = "discord.gg/SakuraDuels"
    discordTitle.TextColor3 = Color3.fromRGB(200, 200, 205)
    discordTitle.Font = Enum.Font.GothamBold
    discordTitle.TextSize = 12
    discordTitle.TextXAlignment = Enum.TextXAlignment.Left
    discordTitle.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    discordTitle.TextStrokeTransparency = 0.35
    discordTitle.ZIndex = 23
    applyShimmerToText(discordTitle, 0.85)

    local closeBtn = Instance.new("TextButton", main)
    closeBtn.Name = "CloseBtn"
    closeBtn.Size = UDim2.new(0, 30, 0, 30)
    closeBtn.Position = UDim2.new(1, -40, 0, 10)
    closeBtn.BackgroundColor3 = Color3.fromRGB(18, 22, 28)
    closeBtn.BackgroundTransparency = 0.1
    closeBtn.BorderSizePixel = 0
    closeBtn.Text = "−"
    closeBtn.TextColor3 = Color3.fromRGB(230, 235, 240)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 22
    closeBtn.AutoButtonColor = false
    closeBtn.ZIndex = 200
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)
    local closeStroke = Instance.new("UIStroke", closeBtn)
    closeStroke.Color = Color3.fromRGB(220, 220, 225)
    closeStroke.Thickness = 1.2
    closeStroke.Transparency = 0.3

    closeBtn.MouseEnter:Connect(function()
        TS:Create(closeBtn, TweenInfo.new(0.12), {
            BackgroundColor3 = Color3.fromRGB(220, 220, 225),
            TextColor3 = Color3.fromRGB(10, 12, 16)
        }):Play()
    end)
    closeBtn.MouseLeave:Connect(function()
        TS:Create(closeBtn, TweenInfo.new(0.12), {
            BackgroundColor3 = Color3.fromRGB(18, 22, 28),
            TextColor3 = Color3.fromRGB(230, 235, 240)
        }):Play()
    end)

    miniBtn = Instance.new("TextButton", gui)
    miniBtn.Name = "SakuraMiniBtn"
    -- %50 boyut (205x62 -> 103x31)
    miniBtn.Size = UDim2.new(0, 103, 0, 31)
    miniBtn.Position = UDim2.new(0, 18, 0, 190)
    miniBtn.BackgroundColor3 = Color3.fromRGB(9, 10, 14)
    miniBtn.BackgroundTransparency = 0.04
    miniBtn.BorderSizePixel = 0
    miniBtn.Text = ""
    miniBtn.ZIndex = 25
    miniBtn.Visible = false
    miniBtn.AutoButtonColor = false
    miniBtn.ClipsDescendants = true
    Instance.new("UICorner", miniBtn).CornerRadius = UDim.new(0, 9)

    -- BG2 thumbnail sits immediately to the left of the OPEN GUI text.
    local miniIcon = Instance.new("ImageLabel", miniBtn)
    miniIcon.Name = "MiniBackgroundImage"
    miniIcon.Position = UDim2.new(0, 3, 0, 3)
    miniIcon.Size = UDim2.new(0, 25, 1, -6)
    miniIcon.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
    miniIcon.BackgroundTransparency = 0
    miniIcon.BorderSizePixel = 0
    miniIcon.ScaleType = Enum.ScaleType.Crop
    miniIcon.ImageTransparency = 0
    miniIcon.ZIndex = 28
    Instance.new("UICorner", miniIcon).CornerRadius = UDim.new(0, 7)
    -- Launcher thumbnail uses BG2, positioned directly left of OPEN GUI.
    -- Keep it independent from the selected main-GUI background.
    setImageOnLabel(miniIcon, backgroundImages[1] or "118241258424065")

    local launcherWash = Instance.new("Frame", miniBtn)
    launcherWash.Name = "LauncherBackgroundWash"
    launcherWash.Position = UDim2.new(0, 31, 0, 0)
    launcherWash.Size = UDim2.new(1, -31, 1, 0)
    launcherWash.BackgroundColor3 = Color3.fromRGB(5, 7, 12)
    launcherWash.BackgroundTransparency = 0.38
    launcherWash.BorderSizePixel = 0
    launcherWash.Active = false
    launcherWash.ZIndex = 27
    Instance.new("UICorner", launcherWash).CornerRadius = UDim.new(0, 9)

    local iconStroke = Instance.new("UIStroke", miniBtn)
    iconStroke.Color = Color3.fromRGB(255, 140, 0)
    iconStroke.Thickness = 1.0
    iconStroke.Transparency = 0.15

    local openLabel = Instance.new("TextLabel", miniBtn)
    openLabel.Name = "OpenGuiLabel"
    openLabel.Position = UDim2.new(0, 34, 0, 3)
    openLabel.Size = UDim2.new(1, -38, 0, 13)
    openLabel.BackgroundTransparency = 1
    openLabel.Text = "OPEN GUI"
    openLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    openLabel.Font = Enum.Font.GothamBlack
    openLabel.TextSize = 9
    openLabel.TextXAlignment = Enum.TextXAlignment.Left
    openLabel.ZIndex = 29

    local brandLabel = Instance.new("TextLabel", miniBtn)
    brandLabel.Name = "SakuraBrandLabel"
    brandLabel.Position = UDim2.new(0, 34, 0, 16)
    brandLabel.Size = UDim2.new(1, -38, 0, 11)
    brandLabel.BackgroundTransparency = 1
    brandLabel.Text = "sakura.vs"
    brandLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
    brandLabel.Font = Enum.Font.GothamBold
    brandLabel.TextSize = 7
    brandLabel.TextXAlignment = Enum.TextXAlignment.Left
    brandLabel.ZIndex = 29

    local miniStroke = Instance.new("UIStroke", miniBtn)
    miniStroke.Color = Color3.fromRGB(255, 140, 0)
    miniStroke.Thickness = 0.9
    miniStroke.Transparency = 0.35

    -- Launcher can be moved with mouse or touch. Keep it inside the screen.
    local draggingLauncher = false
    local launcherDragStart, launcherStartPos
    local launcherDragInput
    miniBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingLauncher = true
            launcherDragStart = input.Position
            launcherStartPos = miniBtn.Position
            launcherDragInput = input
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then draggingLauncher = false end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if not draggingLauncher then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - launcherDragStart
            local cam = workspace.CurrentCamera
            if not cam then return end
            local view = cam.ViewportSize
            local absSize = miniBtn.AbsoluteSize
            local x = math.clamp(launcherStartPos.X.Offset + delta.X, 0, math.max(0, view.X - absSize.X))
            local y = math.clamp(launcherStartPos.Y.Offset + delta.Y, 0, math.max(0, view.Y - absSize.Y))
            miniBtn.Position = UDim2.new(0, x, 0, y)
        end
    end)

    local slideTween = nil
    local mainOriginalPos = UDim2.new(0, 18, 0, 18)

    showGui = function()
        if slideTween then slideTween:Cancel() end
        if not main then return end
        main.Visible = true
        miniBtn.Visible = false
        main.Position = UDim2.new(0, -GUI_W - 20, 0, 18)
        slideTween = TS:Create(main, TweenInfo.new(0.55, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Position = mainOriginalPos})
        slideTween:Play()
        slideTween.Completed:Connect(function() slideTween = nil end)
    end

    hideGui = function()
        if slideTween then slideTween:Cancel() end
        if not main or not main.Visible then return end
        local targetPos = UDim2.new(0, -GUI_W - 20, 0, 18)
        slideTween = TS:Create(main, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {Position = targetPos})
        slideTween:Play()
        slideTween.Completed:Connect(function()
            main.Visible = false
            miniBtn.Visible = true
            slideTween = nil
        end)
    end

    closeBtn.MouseButton1Click:Connect(hideGui)
    miniBtn.MouseButton1Click:Connect(showGui)

    -- Sekme menüsü sağ tarafta, üstten alta doğru.
    local tabBar = Instance.new("Frame", main)
    -- Fill from below title down to bottom of panel (no empty gap under Keybinds)
    tabBar.Size = UDim2.new(0, 100, 1, -96)
    tabBar.Position = UDim2.new(1, -112, 0, 78)
    tabBar.BackgroundTransparency = 1
    tabBar.ZIndex = 10

    local tabLayout = Instance.new("UIListLayout", tabBar)
    tabLayout.FillDirection = Enum.FillDirection.Vertical
    tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    tabLayout.VerticalAlignment = Enum.VerticalAlignment.Top
    tabLayout.Padding = UDim.new(0, 10)

    local tabContent = Instance.new("Frame", main)
    -- İçerik başlığın hemen altından başlasın; üstteki boşluğu azalt.
    tabContent.Size = UDim2.new(1, -140, 1, -96)
    tabContent.Position = UDim2.new(0, 14, 0, 78)
    tabContent.BackgroundTransparency = 1
    tabContent.ClipsDescendants = true
    tabContent.ZIndex = 5

    local tabs = {"Speed", "Combat", "Misc", "Setting", "Keybinds"}
    tabButtons = {}
    local contentPages = {}
    -- 5 tabs + 4 gaps of 10px ≈ fill ~432px panel body → ~78px each
    local TAB_BTN_H = 78

    for i, name in ipairs(tabs) do
        local btn = Instance.new("TextButton", tabBar)
        btn.Size = UDim2.new(1, 0, 0, TAB_BTN_H)
        btn.BackgroundColor3 = Color3.fromRGB(45, 31, 19)
        btn.BackgroundTransparency = 0.18
        btn.BorderSizePixel = 0
        btn.Text = name
        btn.TextColor3 = (name == "Speed" or name == "Combat") and Color3.fromRGB(255, 175, 75) or LIGHT_ORANGE
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 14
        btn.TextWrapped = true
        btn.AutoButtonColor = false
        btn.ZIndex = 11
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 12)
        local stroke = Instance.new("UIStroke", btn)
        stroke.Color = Color3.fromRGB(255, 140, 0)
        stroke.Thickness = 1.2
        stroke.Transparency = 0.35

        local pageName = (name == "Misc" and "Visual") or (name == "Setting" and "Config") or name
        local page = Instance.new("ScrollingFrame", tabContent)
        page.Size = UDim2.new(1, 0, 1, 0)
        page.Position = UDim2.new(0, 0, 0, 0)
        page.BackgroundColor3 = Color3.fromRGB(14, 32, 62)
        page.BackgroundTransparency = 1
        page.BorderSizePixel = 0
        page.ClipsDescendants = true
        page.ScrollBarThickness = 2
        page.ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255)
        page.ScrollBarImageTransparency = 0.2
        page.CanvasSize = UDim2.new(0, 0, 0, 0)
        page.AutomaticCanvasSize = Enum.AutomaticSize.Y
        page.ScrollingDirection = Enum.ScrollingDirection.Y
        page.ZIndex = 6
        Instance.new("UICorner", page).CornerRadius = UDim.new(0, 16)
        page.Visible = (i == 1)

        local layout = Instance.new("UIListLayout", page)
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Padding = UDim.new(0, 6)
        layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

        local padding = Instance.new("UIPadding", page)
        padding.PaddingLeft = UDim.new(0, 6)
        padding.PaddingRight = UDim.new(0, 6)
        padding.PaddingTop = UDim.new(0, 6)
        padding.PaddingBottom = UDim.new(0, 20)

        contentPages[pageName] = page

        btn.MouseButton1Click:Connect(function()
            for _, pg in pairs(contentPages) do pg.Visible = false end
            page.Visible = true
            for _, b in ipairs(tabButtons) do
                b.TextColor3 = (b.Text == "Speed" or b.Text == "Combat" or b.Text == "Misc" or b.Text == "Setting") and Color3.fromRGB(255, 175, 75) or LIGHT_ORANGE
                b.BackgroundColor3 = Color3.fromRGB(45, 31, 19)
                b.BackgroundTransparency = 0.18
            end
            btn.TextColor3 = Color3.fromRGB(255, 185, 95)
            btn.BackgroundColor3 = Color3.fromRGB(82, 48, 18)
            btn.BackgroundTransparency = 0.04
        end)

        table.insert(tabButtons, btn)
    end

    if tabButtons[1] then
        tabButtons[1].TextColor3 = Color3.fromRGB(255, 190, 105)
        tabButtons[1].BackgroundColor3 = Color3.fromRGB(82, 48, 18)
        tabButtons[1].BackgroundTransparency = 0.04
    end

    local pageCounters = {}

    local function getNextOrder(page)
        if not pageCounters[page] then pageCounters[page] = 0 end
        pageCounters[page] = pageCounters[page] + 1
        return pageCounters[page]
    end

    local function mkSect(page, txt)
        local f = Instance.new("Frame", page)
        f.Size = UDim2.new(1, 0, 0, 26)
        f.BackgroundTransparency = 1
        f.BorderSizePixel = 0
        f.LayoutOrder = getNextOrder(page)
        f.ZIndex = 7
        local l = Instance.new("TextLabel", f)
        l.Size = UDim2.new(1, -16, 1, 0)
        l.Position = UDim2.new(0, 8, 0, 0)
        l.BackgroundTransparency = 1
        l.Text = txt:upper()
        l.TextColor3 = getThemeColor()
        l.Font = Enum.Font.GothamBlack
        l.TextSize = 13
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.TextStrokeColor3 = Color3.fromRGB(60,60,60)
        l.TextStrokeTransparency = 0.3
        l.ZIndex = 8
        local line = Instance.new("Frame", f)
        line.Size = UDim2.new(1, -24, 0, 1.5)
        line.Position = UDim2.new(0, 12, 1, -4)
        line.BackgroundColor3 = getThemeColor()
        line.BackgroundTransparency = 0.6
        line.BorderSizePixel = 0
        line.ZIndex = 8
        return f
    end

    local function mkRow(page, h)
        local f = Instance.new("Frame", page)
        f.Size = UDim2.new(1, -4, 0, h or 38)
        f.BackgroundColor3 = ROW_BG
        f.BackgroundTransparency = 0.72
        f.BorderSizePixel = 0
        f.LayoutOrder = getNextOrder(page)
        f.ZIndex = 7
        Instance.new("UICorner", f).CornerRadius = UDim.new(0, 10)
        local rowStroke = Instance.new("UIStroke", f)
        rowStroke.Color = ROW_BORDER
        rowStroke.Thickness = 1
        rowStroke.Transparency = 0.35
        f.MouseEnter:Connect(function()
            TS:Create(f, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(30, 30, 35)}):Play()
        end)
        f.MouseLeave:Connect(function()
            TS:Create(f, TweenInfo.new(0.1), {BackgroundColor3 = ROW_BG}):Play()
        end)
        return f
    end

    local function mkLabel(row, txt)
        local l = Instance.new("TextLabel", row)
        l.Size = UDim2.new(0.55, 0, 1, 0)
        l.Position = UDim2.new(0, 10, 0, 0)
        l.BackgroundTransparency = 1
        l.Text = txt
        l.TextColor3 = WHITE
        l.Font = Enum.Font.GothamBold
        l.TextSize = 11
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.TextTruncate = Enum.TextTruncate.AtEnd
        l.TextStrokeColor3 = Color3.fromRGB(0,0,0)
        l.TextStrokeTransparency = 0.5
        l.ZIndex = 8
        return l
    end

    local function mkPill(row, offset)
        local pill = Instance.new("Frame", row)
        pill.Name = "Track"
        pill.Size = UDim2.new(0, 34, 0, 18)
        pill.AnchorPoint = Vector2.new(0.5, 0.5)
        pill.Position = UDim2.new(1, -(offset or 48), 0.5, 0)
        pill.BackgroundColor3 = Color3.fromRGB(255,255,255)
        pill.BackgroundTransparency = 0.2
        pill.BorderSizePixel = 0
        pill.ZIndex = 8
        Instance.new("UICorner", pill).CornerRadius = UDim.new(0, 9)
        local stroke = Instance.new("UIStroke", pill)
        stroke.Color = ROW_BORDER
        stroke.Thickness = 1
        stroke.Transparency = 0.45
        stroke.Name = "PillStroke"

        local dot = Instance.new("Frame", pill)
        dot.Name = "Knob"
        dot.Size = UDim2.new(0, 13, 0, 13)
        dot.AnchorPoint = Vector2.new(0, 0)
        dot.Position = UDim2.new(0, 3, 0.5, -6)
        dot.BackgroundColor3 = Color3.fromRGB(20, 45, 90)
        dot.BorderSizePixel = 0
        dot.ZIndex = 9
        Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

        local shine = Instance.new("Frame", dot)
        shine.Name = "Shine"
        shine.Size = UDim2.new(1, -4, 0, 4)
        shine.Position = UDim2.new(0, 2, 0, 2)
        shine.BackgroundColor3 = WHITE
        shine.BackgroundTransparency = 0.72
        shine.BorderSizePixel = 0
        shine.ZIndex = 10
        Instance.new("UICorner", shine).CornerRadius = UDim.new(0, 4)

        return pill, dot
    end

    local function animPill(pill, dot, on)
        local stroke = pill:FindFirstChildOfClass("UIStroke")
        local info = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local theme = getThemeColor() or Color3.fromRGB(255, 140, 0)
        local offPill = Color3.new(theme.R * 0.18, theme.G * 0.18, theme.B * 0.18)
        local glow = Color3.new(
            math.clamp(theme.R * 1.2 + 0.05, 0, 1),
            math.clamp(theme.G * 1.2 + 0.05, 0, 1),
            math.clamp(theme.B * 1.2 + 0.05, 0, 1)
        )
        TS:Create(dot, info, {
            Position = on and UDim2.new(1, -16, 0.5, -6) or UDim2.new(0, 3, 0.5, -6),
            BackgroundColor3 = on and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(80, 80, 80),
        }):Play()
        TS:Create(pill, info, {
            BackgroundColor3 = on and theme or offPill,
            BackgroundTransparency = on and 0 or 0.15,
        }):Play()
        if stroke then
            TS:Create(stroke, info, {
                Color = on and glow or Color3.fromRGB(80, 60, 30),
                Transparency = on and 0 or 0.35,
                Thickness = on and 1.8 or 1,
            }):Play()
        end
    end

    local function mkSlider(row, minV, maxV, default, cb)
        local W = 118
        local track = Instance.new("Frame", row)
        track.Size = UDim2.new(0, W, 0, 4)
        track.Position = UDim2.new(1, -(W + 44), 0.5, -2)
        track.BackgroundColor3 = INP
        track.BackgroundTransparency = 0.3
        track.BorderSizePixel = 0
        track.ZIndex = 8
        Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

        local fill = Instance.new("Frame", track)
        fill.Size = UDim2.new(0, 0, 1, 0)
        fill.BackgroundColor3 = getThemeColor()
        fill.BorderSizePixel = 0
        fill.ZIndex = 9
        Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

        local knob = Instance.new("Frame", track)
        knob.Size = UDim2.new(0, 13, 0, 13)
        knob.AnchorPoint = Vector2.new(0.5, 0.5)
        knob.Position = UDim2.new(0, 0, 0.5, 0)
        knob.BackgroundColor3 = WHITE
        knob.BorderSizePixel = 0
        knob.ZIndex = 11
        Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
        local kStroke = Instance.new("UIStroke", knob)
        kStroke.Color = getThemeColor()
        kStroke.Thickness = 2

        local valLabel = Instance.new("TextLabel", row)
        valLabel.Size = UDim2.new(0, 34, 0, 20)
        valLabel.Position = UDim2.new(1, -38, 0.5, -10)
        valLabel.BackgroundTransparency = 1
        valLabel.Text = tostring(default)
        valLabel.TextColor3 = WHITE
        valLabel.Font = Enum.Font.GothamBold
        valLabel.TextSize = 11
        valLabel.TextXAlignment = Enum.TextXAlignment.Right
        valLabel.ZIndex = 9

        local hit = Instance.new("TextButton", row)
        hit.Size = UDim2.new(0, W + 16, 0, 26)
        hit.Position = UDim2.new(1, -(W + 52), 0.5, -13)
        hit.BackgroundTransparency = 1
        hit.Text = ""
        hit.AutoButtonColor = false
        hit.ZIndex = 12

        local current = default

        local function render(a)
            a = _clamp(a, 0, 1)
            fill.Size = UDim2.new(a, 0, 1, 0)
            knob.Position = UDim2.new(a, 0, 0.5, 0)
            fill.BackgroundColor3 = getThemeColor()
            kStroke.Color = getThemeColor()
        end

        local function applyFromX(px)
            local left = track.AbsolutePosition.X
            local width = track.AbsoluteSize.X
            if width <= 0 then width = W end
            if left <= 0 then return end
            local a = (px - left) / width
            a = _clamp(a, 0, 1)
            local v = _floor(minV + (maxV - minV) * a + 0.5)
            current = v
            valLabel.Text = tostring(v)
            render(a)
            if cb then pcall(cb, v) end
        end

        local dragging = false

        hit.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                _isDraggingButton = true
                applyFromX(i.Position.X)
            end
        end)

        hit.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                dragging = false
                _isDraggingButton = false
            end
        end)

        UIS.InputChanged:Connect(function(i)
            if not dragging then return end
            if i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then
                applyFromX(i.Position.X)
            end
        end)

        UIS.InputEnded:Connect(function(i)
            if not dragging then return end
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                dragging = false
                _isDraggingButton = false
            end
        end)

        local function setValue(v)
            v = _clamp(tonumber(v) or minV, minV, maxV)
            current = v
            valLabel.Text = tostring(v)
            render((v - minV) / (maxV - minV))
        end

        setValue(default)
        return setValue
    end

    local function mkToggle(page, txt, cb)
        local row = mkRow(page, 38)
        mkLabel(row, txt)
        local pill, dot = mkPill(row, 48)
        local on = false
        local function sv(s) on = s; animPill(pill, dot, s) end
        local clk = Instance.new("TextButton", pill)
        clk.Size = UDim2.new(1,0,1,0)
        clk.BackgroundTransparency = 1
        clk.Text = ""
        clk.AutoButtonColor = false
        clk.ZIndex = 10
        clk.MouseButton1Click:Connect(function()
            if editModeEnabled and not uiLocked then
                pcall(cb, not on)
            else
                on = not on
                sv(on)
                pcall(cb, on)
            end
            if not _isLoading then
                pcall(saveAllSettings)
            end
        end)
        return sv
    end

    local function mkSelector(parent, default, options, cb)
        local container = Instance.new("Frame", parent)
        container.Size = UDim2.new(0, 160, 1, 0)
        container.Position = UDim2.new(1, -168, 0, 0)
        container.BackgroundTransparency = 1
        container.ZIndex = 8
        local leftBtn = Instance.new("TextButton", container)
        leftBtn.Size = UDim2.new(0, 28, 0, 26)
        leftBtn.Position = UDim2.new(0, 0, 0.5, -13)
        leftBtn.BackgroundColor3 = INP
        leftBtn.BackgroundTransparency = 0.2
        leftBtn.BorderSizePixel = 0
        leftBtn.Text = "<"
        leftBtn.TextColor3 = WHITE
        leftBtn.Font = Enum.Font.GothamBold
        leftBtn.TextSize = 13
        leftBtn.AutoButtonColor = false
        leftBtn.ZIndex = 9
        Instance.new("UICorner", leftBtn).CornerRadius = UDim.new(0, 6)
        local leftStroke = Instance.new("UIStroke", leftBtn)
        leftStroke.Color = ROW_BORDER
        leftStroke.Thickness = 1
        local label = Instance.new("TextLabel", container)
        label.Size = UDim2.new(0, 80, 0, 26)
        label.Position = UDim2.new(0.5, -40, 0.5, -13)
        label.BackgroundTransparency = 1
        label.Text = default
        label.TextColor3 = WHITE
        label.Font = Enum.Font.GothamBold
        label.TextSize = 12
        label.TextXAlignment = Enum.TextXAlignment.Center
        label.ZIndex = 9
        local rightBtn = Instance.new("TextButton", container)
        rightBtn.Size = UDim2.new(0, 28, 0, 26)
        rightBtn.Position = UDim2.new(1, -28, 0.5, -13)
        rightBtn.BackgroundColor3 = INP
        rightBtn.BackgroundTransparency = 0.2
        rightBtn.BorderSizePixel = 0
        rightBtn.Text = ">"
        rightBtn.TextColor3 = WHITE
        rightBtn.Font = Enum.Font.GothamBold
        rightBtn.TextSize = 13
        rightBtn.AutoButtonColor = false
        rightBtn.ZIndex = 9
        Instance.new("UICorner", rightBtn).CornerRadius = UDim.new(0, 6)
        local rightStroke = Instance.new("UIStroke", rightBtn)
        rightStroke.Color = ROW_BORDER
        rightStroke.Thickness = 1
        local function updateLabel(newText) label.Text = newText end
        leftBtn.MouseButton1Click:Connect(function()
            if cb then cb(-1, updateLabel) end
        end)
        rightBtn.MouseButton1Click:Connect(function()
            if cb then cb(1, updateLabel) end
        end)
        return label
    end

    -- Aimbot-mode style ▼ dropdown (options list under the row)
    -- page: parent ScrollingFrame, row: the mkRow, defaultText, options (string list), onPick(optionName)
    -- returns the open button (so caller can update text later)
    local function mkDropdown(page, row, defaultText, options, onPick)
        local openBtn = Instance.new("TextButton", row)
        openBtn.Size = UDim2.new(0, 120, 0, 26)
        openBtn.Position = UDim2.new(1, -128, 0.5, -13)
        openBtn.BackgroundColor3 = INP
        openBtn.BackgroundTransparency = 0.12
        openBtn.BorderSizePixel = 0
        openBtn.Text = tostring(defaultText or "") .. "  ▼"
        openBtn.TextColor3 = WHITE
        openBtn.Font = Enum.Font.GothamBold
        openBtn.TextSize = 12
        openBtn.AutoButtonColor = false
        openBtn.ZIndex = 12
        Instance.new("UICorner", openBtn).CornerRadius = UDim.new(0, 8)
        local openStroke = Instance.new("UIStroke", openBtn)
        openStroke.Color = Color3.fromRGB(220, 220, 225)
        openStroke.Thickness = 1.2
        openStroke.Transparency = 0.35

        local dropFrame = Instance.new("Frame", page)
        dropFrame.Size = UDim2.new(1, -16, 0, 0)
        dropFrame.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
        dropFrame.BackgroundTransparency = 0.15
        dropFrame.BorderSizePixel = 0
        dropFrame.Visible = false
        dropFrame.ClipsDescendants = true
        dropFrame.ZIndex = 30
        dropFrame.LayoutOrder = getNextOrder(page)
        Instance.new("UICorner", dropFrame).CornerRadius = UDim.new(0, 10)
        local dropStroke = Instance.new("UIStroke", dropFrame)
        dropStroke.Color = Color3.fromRGB(220, 220, 225)
        dropStroke.Thickness = 1.2
        dropStroke.Transparency = 0.3

        local maxVisible = 8
        local useScroll = #options > maxVisible
        local listParent = dropFrame
        if useScroll then
            local sf = Instance.new("ScrollingFrame", dropFrame)
            sf.Size = UDim2.new(1, 0, 1, 0)
            sf.BackgroundTransparency = 1
            sf.BorderSizePixel = 0
            sf.ScrollBarThickness = 4
            sf.ScrollBarImageColor3 = Color3.fromRGB(200, 200, 210)
            sf.CanvasSize = UDim2.new(0, 0, 0, 6 + (#options * 32) + 6)
            sf.ZIndex = 31
            listParent = sf
        end
        local dropList = Instance.new("UIListLayout", listParent)
        dropList.FillDirection = Enum.FillDirection.Vertical
        dropList.Padding = UDim.new(0, 4)
        dropList.HorizontalAlignment = Enum.HorizontalAlignment.Center
        local dropPad = Instance.new("UIPadding", listParent)
        dropPad.PaddingTop = UDim.new(0, 6)
        dropPad.PaddingBottom = UDim.new(0, 6)

        local expanded = false
        local current = tostring(defaultText or "")
        local optButtons = {}
        local function refreshOpts()
            for _, b in ipairs(optButtons) do
                local active = (b.Name == current)
                b.BackgroundColor3 = active and Color3.fromRGB(220, 220, 225) or Color3.fromRGB(22, 26, 32)
                b.TextColor3 = active and Color3.fromRGB(8, 10, 14) or WHITE
            end
            openBtn.Text = current .. (expanded and "  ▲" or "  ▼")
        end
        for _, optName in ipairs(options) do
            local b = Instance.new("TextButton", listParent)
            b.Name = optName
            b.Size = UDim2.new(1, -16, 0, 28)
            b.BackgroundColor3 = Color3.fromRGB(22, 26, 32)
            b.BorderSizePixel = 0
            b.Text = optName
            b.TextColor3 = WHITE
            b.Font = Enum.Font.GothamBold
            b.TextSize = 13
            b.AutoButtonColor = false
            b.ZIndex = 32
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
            b.MouseButton1Click:Connect(function()
                current = optName
                expanded = false
                dropFrame.Visible = false
                dropFrame.Size = UDim2.new(1, -16, 0, 0)
                refreshOpts()
                if onPick then onPick(optName) end
            end)
            table.insert(optButtons, b)
        end
        openBtn.MouseButton1Click:Connect(function()
            expanded = not expanded
            if expanded then
                local n = math.min(#options, maxVisible)
                local h = 6 + (n * 32) + 6
                dropFrame.Size = UDim2.new(1, -16, 0, h)
                dropFrame.Visible = true
            else
                dropFrame.Size = UDim2.new(1, -16, 0, 0)
                dropFrame.Visible = false
            end
            refreshOpts()
        end)
        refreshOpts()
        return openBtn, function(newText)
            current = tostring(newText or current)
            refreshOpts()
        end
    end

    local function mkBox(parent, default, w, xOff, cb)
        local tb = Instance.new("TextBox", parent)
        local bw = w or 50
        local xo = math.max(xOff or 56, bw + 12)
        tb.Size = UDim2.new(0, bw, 0, 24)
        tb.Position = UDim2.new(1, -xo, 0.5, -12)
        tb.BackgroundColor3 = INP
        tb.BackgroundTransparency = 0.2
        tb.BorderSizePixel = 0
        tb.Text = tostring(default)
        tb.TextColor3 = WHITE
        tb.Font = Enum.Font.GothamBold
        tb.TextSize = 11
        tb.ClearTextOnFocus = false
        tb.ZIndex = 8
        Instance.new("UICorner", tb).CornerRadius = UDim.new(0, 6)
        local bs = Instance.new("UIStroke", tb)
        bs.Color = ROW_BORDER
        bs.Thickness = 1.2
        bs.Transparency = 0.25
        tb.Focused:Connect(function() TS:Create(bs, TweenInfo.new(0.12), {Color = getThemeColor(), Transparency = 0}):Play() end)
        tb.FocusLost:Connect(function()
            TS:Create(bs, TweenInfo.new(0.12), {Color = ROW_BORDER, Transparency = 0.25}):Play()
            if cb then local n = tonumber(tb.Text); if n then cb(n) else tb.Text = tostring(default) end end
        end)
        return tb
    end

    local function mkKeyButton(parent, kbEntry)
        local btn = Instance.new("TextButton", parent)
        btn.Size = UDim2.new(0, 112, 0, 34)
        btn.Position = UDim2.new(1, -122, 0.5, -17)
        btn.BackgroundColor3 = Color3.fromRGB(45, 31, 19)
        btn.BackgroundTransparency = 0.08
        btn.BorderSizePixel = 0
        local function getLabel() return (kbEntry.gp and kbEntry.gp.Name) or (kbEntry.kb and kbEntry.kb.Name) or "None" end
        btn.Text = getLabel()
        btn.TextColor3 = Color3.fromRGB(255, 175, 75)
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 12
        btn.ZIndex = 8
        btn.AutoButtonColor = false
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)
        local bs = Instance.new("UIStroke", btn)
        bs.Color = Color3.fromRGB(255, 140, 0)
        bs.Thickness = 1.4
        bs.Transparency = 0.25
        local KEY_ORANGE = Color3.fromRGB(255, 175, 75)
        local li = false; local lc; local pv = btn.Text; local listenStart = 0
        btn.Activated:Connect(function()
            if li then li = false; _anyKeyListening = false; if lc then lc:Disconnect(); lc = nil end; btn.Text = pv; btn.TextColor3 = KEY_ORANGE; return end
            pv = btn.Text; li = true; _anyKeyListening = true; listenStart = _tick(); btn.Text = "..."; btn.TextColor3 = Color3.fromRGB(255, 220, 150)
            lc = UIS.InputBegan:Connect(function(inp)
                if not li then return end
                if inp.KeyCode == Enum.KeyCode.Escape then li = false; _anyKeyListening = false; if lc then lc:Disconnect(); lc = nil end; btn.Text = pv; btn.TextColor3 = KEY_ORANGE; return end
                local isGp = isGamepadInput(inp)
                if isGp and _tick()-listenStart < 0.15 then return end
                if not isBindableInput(inp) then return end
                btn.Text = inp.KeyCode.Name; pv = inp.KeyCode.Name; btn.TextColor3 = KEY_ORANGE
                li = false; _anyKeyListening = false; if lc then lc:Disconnect(); lc = nil end
                if isGp then kbEntry.gp = inp.KeyCode; kbEntry.kb = nil else kbEntry.kb = inp.KeyCode; kbEntry.gp = nil end
            end)
        end)
        table.insert(keyButtonRefs, {btn = btn, entry = kbEntry})
        return btn
    end

    local function addKeybindRow(page, labelText, kbEntry)
        local row = mkRow(page, 50)
        local lbl = mkLabel(row, labelText)
        lbl.TextSize = 13
        lbl.Font = Enum.Font.GothamBold
        lbl.Size = UDim2.new(0.48, 0, 1, 0)
        mkKeyButton(row, kbEntry)
    end

    local speedPage = contentPages["Speed"]
    mkSect(speedPage, "Speed Settings")
    do local row = mkRow(speedPage, 38); mkLabel(row, "Normal Speed"); normalBox = mkBox(row, NS, 50, 56, function(v)
        if v > 0 and v <= 500 then
            NS = v
            pcall(function() CarrySystem:setNormalSpeed(v) end)
            pcall(saveAllSettings)
        end
    end) end
    do local row = mkRow(speedPage, 38); mkLabel(row, "Carry Speed"); carryBox = mkBox(row, CS, 50, 56, function(v)
        if v > 0 and v <= 500 then
            CS = v
            pcall(function() CarrySystem:setCarrySpeed(v) end)
            pcall(saveAllSettings)
        end
    end) end
    do local row = mkRow(speedPage, 38); mkLabel(row, "Lagger Normal Speed"); laggerBox = mkBox(row, LAGGER_SPEED, 50, 56, function(v)
        if v > 0 and v <= 500 then
            LAGGER_SPEED = v
            pcall(function() CarrySystem:setLaggerSpeed(v) end)
            pcall(saveAllSettings)
        end
    end) end
    do local row = mkRow(speedPage, 38); mkLabel(row, "Lagger Carry Speed"); lagger2Box = mkBox(row, LAGGER_CARRY_SPEED, 50, 56, function(v)
        if v > 0 and v <= 500 then
            LAGGER_CARRY_SPEED = v
            pcall(function() CarrySystem:setLaggerCarrySpeed(v) end)
            pcall(saveAllSettings)
        end
    end) end
    do
        local row = mkRow(speedPage, 38)
        mkLabel(row, "Current Mode")
        modeValLbl = Instance.new("TextLabel", row)
        modeValLbl.Size = UDim2.new(0, 110, 1, 0)
        modeValLbl.Position = UDim2.new(1, -118, 0, 0)
        modeValLbl.BackgroundTransparency = 1
        modeValLbl.Text = "Normal"
        modeValLbl.TextColor3 = WHITE
        modeValLbl.Font = Enum.Font.GothamBlack
        modeValLbl.TextSize = 11
        modeValLbl.TextXAlignment = Enum.TextXAlignment.Right
        modeValLbl.ZIndex = 8
        local clk = Instance.new("TextButton", row)
        clk.Size = UDim2.new(1,0,1,0)
        clk.BackgroundTransparency = 1
        clk.Text = ""
        clk.AutoButtonColor = false
        clk.ZIndex = 8
        clk.MouseButton1Click:Connect(function() toggleCarryMode() end)
    end

    mkSect(speedPage, "Auto Movement")
    autoLeftSetVisual = mkToggle(speedPage, "Auto Left", function(on)
        autoLeftEnabled = on
        if on then startAutoLeft() else stopAutoLeft() end
        if mobSetAutoLeft then mobSetAutoLeft(on) end
    end)
    autoRightSetVisual = mkToggle(speedPage, "Auto Right", function(on)
        autoRightEnabled = on
        if on then startAutoRight() else stopAutoRight() end
        if mobSetAutoRight then mobSetAutoRight(on) end
    end)

    mkSect(speedPage, "TP & Reset")
    do
        local row = mkRow(speedPage, 38)
        mkLabel(row, "TP Down")
        local clk = Instance.new("TextButton", row)
        clk.Size = UDim2.new(0.58, 0, 1, 0)
        clk.BackgroundTransparency = 1
        clk.Text = ""
        clk.AutoButtonColor = false
        clk.ZIndex = 8
        clk.MouseButton1Click:Connect(function() doTpDown() end)
        local actLbl = Instance.new("TextLabel", row)
        actLbl.Size = UDim2.new(0, 70, 1, 0)
        actLbl.Position = UDim2.new(1, -78, 0, 0)
        actLbl.BackgroundTransparency = 1
        actLbl.Text = "ACTIVATE"
        actLbl.TextColor3 = getThemeColor()
        actLbl.Font = Enum.Font.GothamBold
        actLbl.TextSize = 9
        actLbl.TextXAlignment = Enum.TextXAlignment.Right
        actLbl.ZIndex = 8
    end
    do
        local row = mkRow(speedPage, 38)
        mkLabel(row, "Auto TP Radius")
        autoTpDownRadiusBox = mkBox(row, autoTpDownRadius, 50, 56, function(v)
            if v ~= nil then
                autoTpDownRadius = v
                if autoTpDownRadiusBox then autoTpDownRadiusBox.Text = tostring(autoTpDownRadius) end
                saveAllSettings()
            end
        end)
    end

    autoTpDownSetVisual = mkToggle(speedPage, "Auto TP Down", function(on)
        autoTpDownEnabled = on
        if on then startAutoTpDown() else stopAutoTpDown() end
        saveAllSettings()
    end)

    -- Single speed panel only (Speed Settings above). CarrySystem stays always-on.
    useCarrySystem = true
    CarrySystem:start()
    CarrySystem.speedToggled = speedMode
    CarrySystem:setSoftStealEnabled(false)
    carrySystemToggleSetter = nil
    carrySysNormalBox = nil
    carrySysCarryBox = nil
    carrySysLaggerBox = nil
    carrySysLaggerCarryBox = nil

    autoCarrySpeedSetVisual = mkToggle(speedPage, "Auto Carry Speed", function(on)
        autoCarrySpeedEnabled = on == true
        refreshSpeedModeLabel()
        saveAllSettings()
    end)
    if autoCarrySpeedSetVisual then autoCarrySpeedSetVisual(autoCarrySpeedEnabled == true) end

    mkSect(speedPage, "Sakura.vs Anti Bat")
    local setAntiBatPanelVisual = nil
    setAntiBatPanelVisual = mkToggle(speedPage, "Anti Bat Panel", function(on)
        if on then
            if not antiBatPanelVisible then createAntiBatPanel() end
        else
            if antiBatPanelVisible then destroyAntiBatPanel() end
        end
    end)
    if setAntiBatPanelVisual then setAntiBatPanelVisual(antiBatPanelVisible == true) end

    mkSect(speedPage, ".gg/SakuraDuels")
    local combatPage = contentPages["Combat"]

    mkSect(combatPage, "Anti Ragdoll")
    do
        local row = mkRow(combatPage, 38)
        mkLabel(row, "Anti Ragdoll")
        local modeLabel = ({ off = "Off", v1 = "V1", v2 = "V2" })[tostring(antiRagdollMode or "off")] or "Off"
        local arSelector = mkDropdown(combatPage, row, modeLabel, { "Off", "V1", "V2" }, function(picked)
            local mode = tostring(picked or "Off"):lower()
            if mode ~= "off" and mode ~= "v1" and mode ~= "v2" then mode = "off" end
            setAntiRagdollMode(mode)
        end)
        local function updateAntiRagdollUI(mode)
            local label = ({ off = "Off", v1 = "V1", v2 = "V2" })[tostring(mode or "off")] or "Off"
            if arSelector then
                arSelector.Text = label .. "  ▼"
            end
        end
        _G.updateAntiRagdollUI = updateAntiRagdollUI
        updateAntiRagdollUI(antiRagdollMode)
    end

    setUnwalkVisual = mkToggle(combatPage, "Unwalk", function(on)
        unwalkEnabled = on
        if on then startUnwalk() else stopUnwalk() end
    end)

    local setKickWarningVisual = nil
    setKickWarningVisual = mkToggle(combatPage, "Kick Warning", function(on)
        kickWarningEnabled = on
        if not on then
            pcall(_G.SakuraDestroyKickWarning)
        end
        saveAllSettings()
    end)
    if setKickWarningVisual then setKickWarningVisual(kickWarningEnabled) end

    setAntiDieVisual = mkToggle(combatPage, "Anti Die", function(on)
        antiDieEnabled = on
        if on then AntiDieModule.start() else AntiDieModule.stop() end
        saveAllSettings()
    end)
    if setAntiDieVisual then setAntiDieVisual(antiDieEnabled) end

    -- Spin Only Brainrot (sadece pet eldeyken)
    setSpinVisual = mkToggle(combatPage, "Spin Only Brainrot", function(on)
        setSpinEnabled(on == true)
    end)
    if setSpinVisual then setSpinVisual(spinEnabled == true) end
    do
        local row = mkRow(combatPage, 38)
        mkLabel(row, "Spin Speed")
        local spinSpeedOpts = {"Slow", "Normal", "Fast", "Very Fast"}
        local spinSpeedMap = { Slow = 0.15, Normal = 0.35, Fast = 0.60, ["Very Fast"] = 0.90 }
        local curName = tostring(spinSpeedName or "Normal")
        if not spinSpeedMap[curName] then
            curName = "Normal"
            for n, v in pairs(spinSpeedMap) do
                if math.abs((spinSpeed or 0.35) - v) < 0.02 then curName = n break end
            end
        end
        spinSpeedSelectorLabel = mkDropdown(combatPage, row, curName, spinSpeedOpts, function(picked)
            spinSpeedName = tostring(picked or "Normal")
            spinSpeed = spinSpeedMap[spinSpeedName] or 0.35
            if spinSpeedSelectorLabel then
                spinSpeedSelectorLabel.Text = spinSpeedName .. "  ▼"
            end
            _lastSavedJSON = nil
            pcall(saveAllSettings)
        end)
    end

    mkSect(combatPage, "Drop")
    dropBrainrotSetVisual = mkToggle(combatPage, "Drop Brainrot", function(on)
        if on then
            executeDropWithToggle(function(v)
                dropBrainrotSetVisual(v)
                if mobSetDropBR then mobSetDropBR(v) end
            end)
        end
    end)
    setDropVisual = dropBrainrotSetVisual

    do
        local row = mkRow(combatPage, 38)
        mkLabel(row, "Drop Mode")
        local selectorBtn = Instance.new("TextButton", row)
        selectorBtn.Size = UDim2.new(0, 120, 0, 26)
        selectorBtn.Position = UDim2.new(1, -128, 0.5, -13)
        selectorBtn.BackgroundColor3 = INP
        selectorBtn.BackgroundTransparency = 0.12
        selectorBtn.BorderSizePixel = 0
        selectorBtn.Text = (dropMode == 1 and "Fling" or "Jump Drop") .. "  ▼"
        selectorBtn.TextColor3 = WHITE
        selectorBtn.Font = Enum.Font.GothamBold
        selectorBtn.TextSize = 12
        selectorBtn.AutoButtonColor = false
        selectorBtn.ZIndex = 12
        Instance.new("UICorner", selectorBtn).CornerRadius = UDim.new(0, 8)
        local selStroke = Instance.new("UIStroke", selectorBtn)
        selStroke.Color = Color3.fromRGB(220, 220, 225)
        selStroke.Thickness = 1.2
        selStroke.Transparency = 0.35
        dropModeBtnRef = selectorBtn

        local dropdown = Instance.new("Frame", combatPage)
        dropdown.Name = "DropModeDrop"
        dropdown.Size = UDim2.new(1, -16, 0, 0)
        dropdown.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
        dropdown.BackgroundTransparency = 0.15
        dropdown.BorderSizePixel = 0
        dropdown.Visible = false
        dropdown.ClipsDescendants = true
        dropdown.ZIndex = 30
        dropdown.LayoutOrder = getNextOrder(combatPage)
        Instance.new("UICorner", dropdown).CornerRadius = UDim.new(0, 10)
        local dropStroke = Instance.new("UIStroke", dropdown)
        dropStroke.Color = Color3.fromRGB(220, 220, 225)
        dropStroke.Thickness = 1.2
        dropStroke.Transparency = 0.3
        local dropList = Instance.new("UIListLayout", dropdown)
        dropList.FillDirection = Enum.FillDirection.Vertical
        dropList.Padding = UDim.new(0, 4)
        dropList.HorizontalAlignment = Enum.HorizontalAlignment.Center
        local dropPad = Instance.new("UIPadding", dropdown)
        dropPad.PaddingTop = UDim.new(0, 6)
        dropPad.PaddingBottom = UDim.new(0, 6)

        local modes = {"Fling", "Jump Drop"}
        local expanded = false
        local optButtons = {}
        local function currentName()
            return dropMode == 1 and "Fling" or "Jump Drop"
        end
        local function refreshOpts()
            for _, b in ipairs(optButtons) do
                local active = (b.Name == currentName())
                b.BackgroundColor3 = active and Color3.fromRGB(220, 220, 225) or Color3.fromRGB(22, 26, 32)
                b.TextColor3 = active and Color3.fromRGB(8, 10, 14) or WHITE
            end
            selectorBtn.Text = currentName() .. (expanded and "  ▲" or "  ▼")
        end
        for _, modeName in ipairs(modes) do
            local b = Instance.new("TextButton", dropdown)
            b.Name = modeName
            b.Size = UDim2.new(1, -16, 0, 28)
            b.BackgroundColor3 = Color3.fromRGB(22, 26, 32)
            b.BorderSizePixel = 0
            b.Text = modeName
            b.TextColor3 = WHITE
            b.Font = Enum.Font.GothamBold
            b.TextSize = 13
            b.AutoButtonColor = false
            b.ZIndex = 31
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
            b.MouseButton1Click:Connect(function()
                dropMode = (modeName == "Fling") and 1 or 2
                expanded = false
                dropdown.Visible = false
                dropdown.Size = UDim2.new(1, -16, 0, 0)
                refreshOpts()
                pcall(saveAllSettings)
            end)
            table.insert(optButtons, b)
        end
        selectorBtn.MouseButton1Click:Connect(function()
            expanded = not expanded
            if expanded then
                dropdown.Size = UDim2.new(1, -16, 0, 6 + (#modes * 32) + 6)
                dropdown.Visible = true
            else
                dropdown.Visible = false
                dropdown.Size = UDim2.new(1, -16, 0, 0)
            end
            refreshOpts()
        end)
        refreshOpts()
    end

    mkSect(combatPage, "Counters")
    setBatCounterVisual = mkToggle(combatPage, "Bat Counter", function(on)
        batCounterEnabled = on
        if on then startBatCounter() else stopBatCounter() end
    end)


    setMedusaVisual = mkToggle(combatPage, "Medusa Counter", function(on)
        medusaCounterEnabled = on
        if on then
            if LP.Character then setupMedusaCounter(LP.Character) else stopMedusaCounter() end
        else
            stopMedusaCounter()
        end
        if setMedusaVisual then setMedusaVisual(on) end
    end)

    mkSect(combatPage, "Defense")
    bodyLockSetVisual = mkToggle(combatPage, "Body Lock", function(on)
        bodyLockEnabled = on
        if on then
            if _blSuppressCount == 0 then startBodyLock() end
        else
            stopBodyLock()
        end
    end)
    do
        local row = mkRow(combatPage, 38)
        mkLabel(row, "Body Lock Range")
        bodyLockRangeBox = mkBox(row, bodyLockRange, 50, 56, function(v)
            if v and v > 0 then
                bodyLockRange = _clamp(_floor(v), 5, 200)
                if bodyLockRangeBox then bodyLockRangeBox.Text = tostring(bodyLockRange) end
            end
        end)
    end

    mkSect(combatPage, "Aimbots")
    autoBatSetVisual = mkToggle(combatPage, "Auto Bat", function(on)
        if on then enableAutoBat() else disableAutoBat() end
        if mobSetAutoBat then mobSetAutoBat(on) end
    end)

    -- Anti Aimbot toggle (V1 Spectrum / V2 Clean Bat Bypass)
    setAntiAimbotVisual = mkToggle(combatPage, "Anti Aimbot", function(on)
        if on then enableAntiAimbot() else disableAntiAimbot() end
        _lastSavedJSON = nil
        pcall(saveAllSettings)
    end)
    if setAntiAimbotVisual then setAntiAimbotVisual(antiAimbotEnabled == true) end

    do
        local row = mkRow(combatPage, 38)
        mkLabel(row, "Anti Aimbot Mode")
        antiAimbotModeLabel = mkDropdown(combatPage, row, tostring(antiAimbotMode or "V1"), { "V1", "V2" }, function(picked)
            setAntiAimbotMode(tostring(picked or "V1"))
        end)
    end

    -- Bypass Aimbot ayrı tuş kaldırıldı; V2 için "Anti Aimbot Mode" = V2 kullan
    autoBatV2SetVisual = function(_on) end -- stub (eski referanslar kırılmasın)
    _G.AceAimbotSetVisual = autoBatV2SetVisual

    setAntiBatVisual = mkToggle(combatPage, "Anti Bat", function(on)
        setAntiBat(on)
        if mobSetAntiBat then mobSetAntiBat(on) end
        pcall(saveAllSettings)
    end)
    if setAntiBatVisual then setAntiBatVisual(antiBatEnabled) end
    do local row = mkRow(combatPage, 38); mkLabel(row, "Bat Aimbot Speed"); batSpeedBox = mkBox(row, BAT_AIMBOT_SPEED, 50, 56, function(v) if v > 0 and v <= 200 then BAT_AIMBOT_SPEED = v; pcall(saveAllSettings) end end) end
    do local row = mkRow(combatPage, 38); mkLabel(row, "Bypass Aimbot Speed"); local bypassBox = mkBox(row, BYPASS_AIMBOT_SPEED, 50, 56, function(v) if v > 0 and v <= 200 then BYPASS_AIMBOT_SPEED = v; pcall(saveAllSettings) end end) end

    -- Bat Aimbot Mode: acilir secenek menusu (Normal / Bypass / V3)
    do
        local row = mkRow(combatPage, 38)
        mkLabel(row, "Bat Aimbot Mode")
        local openBtn = Instance.new("TextButton", row)
        openBtn.Size = UDim2.new(0, 120, 0, 26)
        openBtn.Position = UDim2.new(1, -128, 0.5, -13)
        openBtn.BackgroundColor3 = INP
        openBtn.BackgroundTransparency = 0.12
        openBtn.BorderSizePixel = 0
        openBtn.Text = tostring(batAimbotMode or "Normal") .. "  ▼"
        openBtn.TextColor3 = WHITE
        openBtn.Font = Enum.Font.GothamBold
        openBtn.TextSize = 12
        openBtn.AutoButtonColor = false
        openBtn.ZIndex = 12
        Instance.new("UICorner", openBtn).CornerRadius = UDim.new(0, 8)
        local openStroke = Instance.new("UIStroke", openBtn)
        openStroke.Color = Color3.fromRGB(220, 220, 225)
        openStroke.Thickness = 1.2
        openStroke.Transparency = 0.35
        batAimbotModeLabel = openBtn

        local dropFrame = Instance.new("Frame", combatPage)
        dropFrame.Name = "BatAimbotModeDrop"
        dropFrame.Size = UDim2.new(1, -16, 0, 0)
        dropFrame.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
        dropFrame.BackgroundTransparency = 0.15
        dropFrame.BorderSizePixel = 0
        dropFrame.Visible = false
        dropFrame.ClipsDescendants = true
        dropFrame.ZIndex = 30
        dropFrame.LayoutOrder = getNextOrder(combatPage)
        Instance.new("UICorner", dropFrame).CornerRadius = UDim.new(0, 10)
        local dropStroke = Instance.new("UIStroke", dropFrame)
        dropStroke.Color = Color3.fromRGB(220, 220, 225)
        dropStroke.Thickness = 1.2
        dropStroke.Transparency = 0.3
        local dropList = Instance.new("UIListLayout", dropFrame)
        dropList.FillDirection = Enum.FillDirection.Vertical
        dropList.Padding = UDim.new(0, 4)
        dropList.HorizontalAlignment = Enum.HorizontalAlignment.Center
        local dropPad = Instance.new("UIPadding", dropFrame)
        dropPad.PaddingTop = UDim.new(0, 6)
        dropPad.PaddingBottom = UDim.new(0, 6)

        local expanded = false
        local optButtons = {}
        local function refreshOpts()
            for _, b in ipairs(optButtons) do
                local active = (b.Name == tostring(batAimbotMode))
                b.BackgroundColor3 = active and Color3.fromRGB(220, 220, 225) or Color3.fromRGB(22, 26, 32)
                b.TextColor3 = active and Color3.fromRGB(8, 10, 14) or WHITE
            end
            openBtn.Text = tostring(batAimbotMode or "Normal") .. (expanded and "  ▲" or "  ▼")
        end
        for _, modeName in ipairs(BAT_AIMBOT_MODES) do
            local b = Instance.new("TextButton", dropFrame)
            b.Name = modeName
            b.Size = UDim2.new(1, -16, 0, 28)
            b.BackgroundColor3 = Color3.fromRGB(22, 26, 32)
            b.BorderSizePixel = 0
            b.Text = modeName
            b.TextColor3 = WHITE
            b.Font = Enum.Font.GothamBold
            b.TextSize = 13
            b.AutoButtonColor = false
            b.ZIndex = 31
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
            b.MouseButton1Click:Connect(function()
                setBatAimbotMode(modeName)
                expanded = false
                dropFrame.Visible = false
                dropFrame.Size = UDim2.new(1, -16, 0, 0)
                refreshOpts()
            end)
            table.insert(optButtons, b)
        end
        openBtn.MouseButton1Click:Connect(function()
            expanded = not expanded
            if expanded then
                local h = 6 + (#BAT_AIMBOT_MODES * 32) + 6
                dropFrame.Size = UDim2.new(1, -16, 0, h)
                dropFrame.Visible = true
            else
                dropFrame.Visible = false
                dropFrame.Size = UDim2.new(1, -16, 0, 0)
            end
            refreshOpts()
        end)
        refreshOpts()
    end


    mkToggle(combatPage, "Ping Lagger Panel", function(on)
        if on then
            local g = createSakuraPingLaggerPanel()
            if g then g.Enabled = true end
        else
            if SakuraPingLagger and SakuraPingLagger.gui then
                SakuraPingLagger.gui.Enabled = false
            end
        end
    end)

    batDesyncTpSetVisual = mkToggle(combatPage, "TP", function(on)
        if on then
            if not batDesyncTpEnabled then toggleBatDesyncTp() end
        else
            if batDesyncTpEnabled then toggleBatDesyncTp() end
        end
    end)
    if batDesyncTpSetVisual then batDesyncTpSetVisual(batDesyncTpEnabled) end

    -- TP BAT version: acilir secenek menusu (V1 / V2 / V3)
    do
        local row = mkRow(combatPage, 38)
        mkLabel(row, "TP Version")
        local openBtn = Instance.new("TextButton", row)
        openBtn.Size = UDim2.new(0, 120, 0, 26)
        openBtn.Position = UDim2.new(1, -128, 0.5, -13)
        openBtn.BackgroundColor3 = INP
        openBtn.BackgroundTransparency = 0.12
        openBtn.BorderSizePixel = 0
        openBtn.Text = tostring(batTPVersion or "V1") .. "  ▼"
        openBtn.TextColor3 = WHITE
        openBtn.Font = Enum.Font.GothamBold
        openBtn.TextSize = 12
        openBtn.AutoButtonColor = false
        openBtn.ZIndex = 12
        Instance.new("UICorner", openBtn).CornerRadius = UDim.new(0, 8)
        local openStroke = Instance.new("UIStroke", openBtn)
        openStroke.Color = Color3.fromRGB(220, 220, 225)
        openStroke.Thickness = 1.2
        openStroke.Transparency = 0.35
        batTPVersionLabel = openBtn

        local dropFrame = Instance.new("Frame", combatPage)
        dropFrame.Name = "BatTPVersionDrop"
        dropFrame.Size = UDim2.new(1, -16, 0, 0)
        dropFrame.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
        dropFrame.BackgroundTransparency = 0.15
        dropFrame.BorderSizePixel = 0
        dropFrame.Visible = false
        dropFrame.ClipsDescendants = true
        dropFrame.ZIndex = 30
        dropFrame.LayoutOrder = getNextOrder(combatPage)
        Instance.new("UICorner", dropFrame).CornerRadius = UDim.new(0, 10)
        local dropStroke = Instance.new("UIStroke", dropFrame)
        dropStroke.Color = Color3.fromRGB(220, 220, 225)
        dropStroke.Thickness = 1.2
        dropStroke.Transparency = 0.3
        local dropList = Instance.new("UIListLayout", dropFrame)
        dropList.FillDirection = Enum.FillDirection.Vertical
        dropList.Padding = UDim.new(0, 4)
        dropList.HorizontalAlignment = Enum.HorizontalAlignment.Center
        local dropPad = Instance.new("UIPadding", dropFrame)
        dropPad.PaddingTop = UDim.new(0, 6)
        dropPad.PaddingBottom = UDim.new(0, 6)

        local expanded = false
        local optButtons = {}
        local function refreshOpts()
            for _, b in ipairs(optButtons) do
                local active = (b.Name == tostring(batTPVersion))
                b.BackgroundColor3 = active and Color3.fromRGB(220, 220, 225) or Color3.fromRGB(22, 26, 32)
                b.TextColor3 = active and Color3.fromRGB(8, 10, 14) or WHITE
            end
            openBtn.Text = tostring(batTPVersion or "V1") .. (expanded and "  ▲" or "  ▼")
        end
        for _, verName in ipairs(BAT_TP_VERSIONS) do
            local b = Instance.new("TextButton", dropFrame)
            b.Name = verName
            b.Size = UDim2.new(1, -16, 0, 28)
            b.BackgroundColor3 = Color3.fromRGB(22, 26, 32)
            b.BorderSizePixel = 0
            b.Text = verName
            b.TextColor3 = WHITE
            b.Font = Enum.Font.GothamBold
            b.TextSize = 13
            b.AutoButtonColor = false
            b.ZIndex = 31
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
            b.MouseButton1Click:Connect(function()
                setBatTPVersion(verName)
                expanded = false
                dropFrame.Visible = false
                dropFrame.Size = UDim2.new(1, -16, 0, 0)
                refreshOpts()
            end)
            table.insert(optButtons, b)
        end
        openBtn.MouseButton1Click:Connect(function()
            expanded = not expanded
            if expanded then
                local h = 6 + (#BAT_TP_VERSIONS * 32) + 6
                dropFrame.Size = UDim2.new(1, -16, 0, h)
                dropFrame.Visible = true
            else
                dropFrame.Visible = false
                dropFrame.Size = UDim2.new(1, -16, 0, 0)
            end
            refreshOpts()
        end)
        refreshOpts()
    end
    -- Bat V2 removed from GUI

    local visualPage = contentPages["Visual"]

    mkSect(visualPage, "Interface")
    setEditModeVisual = mkToggle(visualPage, "Edit Button", function(on)
        toggleEditMode(on)
        if on and uiLocked then
            editModeEnabled = false
            setEditModeVisual(false)
        end
    end)
    if setEditModeVisual then setEditModeVisual(editModeEnabled) end

    setLockUIVisual = mkToggle(visualPage, "Lock UI", function(on)
        toggleLockUI(on)
        if on and editModeEnabled then
            editModeEnabled = false
            if setEditModeVisual then setEditModeVisual(false) end
        end
    end)

    mkSect(visualPage, "Customization")
    do
        local row = mkRow(visualPage, 38)
        mkLabel(row, "Anim Pack")
        local animNames = {}
        for _, entry in ipairs(ANIM_PACK_ORDER) do
            table.insert(animNames, entry[2])
        end
        animSelectorLabel = mkDropdown(visualPage, row, currentAnimPack or "Off", animNames, function(packName)
            if packName == "Off" then
                stopAnimPack()
            else
                startAnimPack(packName)
            end
            pcall(saveAllSettings)
        end)
    end

    do
        local row = mkRow(visualPage, 38)
        mkLabel(row, "Skin Change")
        local outfitNames = {}
        for i, cfg in ipairs(OUTFITS) do
            outfitNames[i] = cfg.label
        end
        local curLabel = (OUTFITS[currentOutfitIndex] and OUTFITS[currentOutfitIndex].label) or "PURPLE"
        outfitSelectorLabel = mkDropdown(visualPage, row, curLabel, outfitNames, function(label)
            for i, cfg in ipairs(OUTFITS) do
                if cfg.label == label then
                    currentOutfitIndex = i
                    pcall(function() applyOutfitByIndex(currentOutfitIndex) end)
                    break
                end
            end
            _lastSavedJSON = nil -- force write
            pcall(saveAllSettings)
        end)
    end

    mkSect(visualPage, "Personalization")

    do
        local medusaRow = mkRow(visualPage, 38)
        mkLabel(medusaRow, "Medusa Skin")
        local reverse = { Default = "Default", Skull = "Skull", ["Golden DE"] = "GoldenDesertEagle" }
        local labels = { Default = "Default", Skull = "Skull", GoldenDesertEagle = "Golden DE" }
        local current = tostring(medusaSkinChoice or _G.RivalMedusaSkin or "Default")
        local display = labels[current] or "Default"
        MedusaSkinSelector = mkDropdown(visualPage, medusaRow, display, { "Default", "Skull", "Golden DE" }, function(picked)
            local key = reverse[picked] or "Default"
            medusaSkinChoice = key
            _G.RivalMedusaSkin = key
            pcall(function()
                if _G.RivalSetMedusaSkin then _G.RivalSetMedusaSkin(key) end
            end)
            pcall(saveAllSettings)
        end)
    end

    local katanaSkinSetVisual
    local function enableKatanaSkinOnly()
        -- Minecraft Bat ile aynı anda olmasın (görünümü ezer)
        if minecraftBatSkinEnabled then
            minecraftBatSkinEnabled = false
            if MinecraftBatSkin then
                MinecraftBatSkin.State.enabled = false
                pcall(function() MinecraftBatSkin.Remove() end)
            end
            if MinecraftBatSetVisual then pcall(MinecraftBatSetVisual, false) end
        end
        katanaSkinEnabled = true
        pcall(function()
            if KatanaSkin and KatanaSkin.SetColorMode then
                KatanaSkin.SetColorMode(katanaSkinColorMode or "Red")
            else
                KatanaSkin.ApplySkin("KATANA")
            end
        end)
        if katanaSkinSetVisual then pcall(katanaSkinSetVisual, true) end
    end

    katanaSkinSetVisual = mkToggle(visualPage, "Bat Skin (Katana)", function(on)
        katanaSkinEnabled = on
        if on then
            if minecraftBatSkinEnabled then
                minecraftBatSkinEnabled = false
                if MinecraftBatSkin then
                    MinecraftBatSkin.State.enabled = false
                    pcall(function() MinecraftBatSkin.Remove() end)
                end
                if MinecraftBatSetVisual then pcall(MinecraftBatSetVisual, false) end
            end
            pcall(function()
                if KatanaSkin and KatanaSkin.SetColorMode then
                    KatanaSkin.SetColorMode(katanaSkinColorMode or "Red")
                else
                    KatanaSkin.ApplySkin("KATANA")
                end
            end)
        else
            pcall(function() KatanaSkin.ApplySkin("NONE") end)
        end
        pcall(saveAllSettings)
    end)
    if katanaSkinSetVisual then katanaSkinSetVisual(katanaSkinEnabled) end

    MinecraftBatSetVisual = mkToggle(visualPage, "Minecraft Bat", function(on)
        minecraftBatSkinEnabled = on
        if MinecraftBatSkin and MinecraftBatSkin.State then
            MinecraftBatSkin.State.enabled = on
        end
        if on then
            -- Katana ile çakışmasın
            if katanaSkinEnabled then
                katanaSkinEnabled = false
                pcall(function() KatanaSkin.ApplySkin("NONE") end)
                if katanaSkinSetVisual then pcall(katanaSkinSetVisual, false) end
            end
            pcall(function() MinecraftBatSkin.Apply() end)
        else
            pcall(function() MinecraftBatSkin.Remove() end)
        end
        pcall(saveAllSettings)
    end)
    if MinecraftBatSetVisual then MinecraftBatSetVisual(minecraftBatSkinEnabled) end

    -- Custom Tools (Ember-style): Bat=Katana + Medusa skin together
    customToolsEnabled = customToolsEnabled == true
    setCustomToolsVisual = mkToggle(visualPage, "Custom Tools", function(on)
        customToolsEnabled = on == true
        if on then
            -- Katana bat skin
            katanaSkinEnabled = true
            minecraftBatSkinEnabled = false
            pcall(function()
                if MinecraftBatSkin then
                    MinecraftBatSkin.State.enabled = false
                    pcall(function() MinecraftBatSkin.Remove() end)
                end
                if MinecraftBatSetVisual then pcall(MinecraftBatSetVisual, false) end
                if KatanaSkin and KatanaSkin.SetColorMode then
                    KatanaSkin.SetColorMode(katanaSkinColorMode or "Red")
                elseif KatanaSkin then
                    KatanaSkin.ApplySkin("KATANA")
                end
                if katanaSkinSetVisual then pcall(katanaSkinSetVisual, true) end
            end)
            -- Medusa tool skin if available
            pcall(function()
                if _G.RivalSetMedusaSkin then
                    _G.RivalSetMedusaSkin(medusaSkinChoice or _G.RivalMedusaSkin or "Default")
                end
            end)
        else
            pcall(function()
                katanaSkinEnabled = false
                if KatanaSkin then KatanaSkin.ApplySkin("NONE") end
                if katanaSkinSetVisual then pcall(katanaSkinSetVisual, false) end
            end)
        end
        _lastSavedJSON = nil
        pcall(saveAllSettings)
    end)
    if setCustomToolsVisual then setCustomToolsVisual(customToolsEnabled == true) end

    do
        local mcColorRow = mkRow(visualPage, 38)
        mkLabel(mcColorRow, "MC Bat Color")
        local mcColorOptions = {
            "Default", "Red", "Abyss Blue", "Venom Green", "Royal Gold",
            "Velvet Rose", "Crimson Night", "RGB",
        }
        MinecraftBatColorSelector = mkDropdown(visualPage, mcColorRow, minecraftBatSkinColorMode or "Default", mcColorOptions, function(picked)
            minecraftBatSkinColorMode = tostring(picked or "Default")
            if MinecraftBatColorSelector then
                MinecraftBatColorSelector.Text = minecraftBatSkinColorMode .. "  ▼"
            end
            -- MC renk seçince Minecraft Bat açılsın, Katana kapansın
            if not minecraftBatSkinEnabled then
                minecraftBatSkinEnabled = true
                if MinecraftBatSkin then MinecraftBatSkin.State.enabled = true end
                if MinecraftBatSetVisual then pcall(MinecraftBatSetVisual, true) end
            end
            if katanaSkinEnabled then
                katanaSkinEnabled = false
                pcall(function() KatanaSkin.ApplySkin("NONE") end)
                if katanaSkinSetVisual then pcall(katanaSkinSetVisual, false) end
            end
            pcall(function()
                if MinecraftBatSkin and MinecraftBatSkin.SetColorMode then
                    MinecraftBatSkin.SetColorMode(minecraftBatSkinColorMode)
                end
            end)
            pcall(function() MinecraftBatSkin.Apply() end)
            pcall(saveAllSettings)
        end)
    end

    do
        local katColorRow = mkRow(visualPage, 38)
        mkLabel(katColorRow, "Katana Color")
        local katColorOptions = {
            "Red", "Blue", "Yellow", "Purple", "Mor", "Green", "White", "Orange",
        }
        KatanaColorSelector = mkDropdown(visualPage, katColorRow, katanaSkinColorMode or "Red", katColorOptions, function(picked)
            katanaSkinColorMode = tostring(picked or "Red")
            if KatanaColorSelector then
                KatanaColorSelector.Text = katanaSkinColorMode .. "  ▼"
            end
            -- Katana renk seçince otomatik katana skin aç, MC bat kapat
            enableKatanaSkinOnly()
            pcall(saveAllSettings)
        end)
    end

    do
        local discRow = mkRow(visualPage, 38)
        mkLabel(discRow, "Discord Color")
        discordColorSelectorLabel = mkDropdown(visualPage, discRow, discordTextColorTheme or "White", DISCORD_COLOR_ORDER, function(picked)
            applyDiscordTextColor(tostring(picked or "White"))
        end)
        if discordColorSelectorLabel then
            discordColorSelectorLabel.TextColor3 = getDiscordTextColor()
        end
    end

    -- Button Color — same dropdown pattern as Bat Aimbot Mode (proven working)
    do
        local row = mkRow(visualPage, 38)
        mkLabel(row, "Button Color")
        local openBtn = Instance.new("TextButton", row)
        openBtn.Size = UDim2.new(0, 120, 0, 26)
        openBtn.Position = UDim2.new(1, -128, 0.5, -13)
        openBtn.BackgroundColor3 = INP
        openBtn.BackgroundTransparency = 0.12
        openBtn.BorderSizePixel = 0
        openBtn.Text = tostring(currentColorTheme or "Naranja") .. "  ▼"
        openBtn.TextColor3 = selectedColor or WHITE
        openBtn.Font = Enum.Font.GothamBold
        openBtn.TextSize = 12
        openBtn.AutoButtonColor = false
        openBtn.ZIndex = 12
        Instance.new("UICorner", openBtn).CornerRadius = UDim.new(0, 8)
        local openStroke = Instance.new("UIStroke", openBtn)
        openStroke.Color = Color3.fromRGB(220, 220, 225)
        openStroke.Thickness = 1.2
        openStroke.Transparency = 0.35
        colorSelectorLabel = openBtn

        local dropFrame = Instance.new("Frame", visualPage)
        dropFrame.Name = "ButtonColorDrop"
        dropFrame.Size = UDim2.new(1, -16, 0, 0)
        dropFrame.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
        dropFrame.BackgroundTransparency = 0.15
        dropFrame.BorderSizePixel = 0
        dropFrame.Visible = false
        dropFrame.ClipsDescendants = true
        dropFrame.ZIndex = 30
        dropFrame.LayoutOrder = getNextOrder(visualPage)
        Instance.new("UICorner", dropFrame).CornerRadius = UDim.new(0, 10)
        local dropStroke = Instance.new("UIStroke", dropFrame)
        dropStroke.Color = Color3.fromRGB(220, 220, 225)
        dropStroke.Thickness = 1.2
        dropStroke.Transparency = 0.3
        local dropList = Instance.new("UIListLayout", dropFrame)
        dropList.FillDirection = Enum.FillDirection.Vertical
        dropList.Padding = UDim.new(0, 4)
        dropList.HorizontalAlignment = Enum.HorizontalAlignment.Center
        local dropPad = Instance.new("UIPadding", dropFrame)
        dropPad.PaddingTop = UDim.new(0, 6)
        dropPad.PaddingBottom = UDim.new(0, 6)

        local expanded = false
        local optButtons = {}
        local function refreshOpts()
            for _, b in ipairs(optButtons) do
                local active = (b.Name == tostring(currentColorTheme))
                local themeCol = COLOR_THEMES[b.Name] or WHITE
                b.BackgroundColor3 = active and themeCol or Color3.fromRGB(22, 26, 32)
                b.TextColor3 = active and Color3.fromRGB(8, 10, 14) or WHITE
            end
            openBtn.Text = tostring(currentColorTheme or "Naranja") .. (expanded and "  ▲" or "  ▼")
            openBtn.TextColor3 = selectedColor or WHITE
        end
        for _, themeName in ipairs(COLOR_THEME_ORDER) do
            local b = Instance.new("TextButton", dropFrame)
            b.Name = themeName
            b.Size = UDim2.new(1, -16, 0, 28)
            b.BackgroundColor3 = Color3.fromRGB(22, 26, 32)
            b.BorderSizePixel = 0
            b.Text = themeName
            b.TextColor3 = WHITE
            b.Font = Enum.Font.GothamBold
            b.TextSize = 13
            b.AutoButtonColor = false
            b.ZIndex = 31
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
            b.MouseButton1Click:Connect(function()
                applyColorTheme(themeName)
                expanded = false
                dropFrame.Visible = false
                dropFrame.Size = UDim2.new(1, -16, 0, 0)
                refreshOpts()
            end)
            table.insert(optButtons, b)
        end
        openBtn.MouseButton1Click:Connect(function()
            expanded = not expanded
            if expanded then
                local h = 6 + (#COLOR_THEME_ORDER * 32) + 6
                dropFrame.Size = UDim2.new(1, -16, 0, h)
                dropFrame.Visible = true
            else
                dropFrame.Size = UDim2.new(1, -16, 0, 0)
                dropFrame.Visible = false
            end
            refreshOpts()
        end)
        refreshOpts()
    end

    setESPVIsual = mkToggle(visualPage, "Player ESP", function(on) toggleESP(on) end)

    setTauntVisual = mkToggle(visualPage, "Taunt", function(on)
        if on then startTaunt() else stopTaunt() end
        if mobSetTaunt then pcall(mobSetTaunt, on) end
        pcall(saveAllSettings)
    end)
    if setTauntVisual then setTauntVisual(tauntEnabled == true) end

    -- ESP Color — same dropdown pattern as Bat Aimbot Mode
    do
        local row = mkRow(visualPage, 38)
        mkLabel(row, "ESP Color")
        local openBtn = Instance.new("TextButton", row)
        openBtn.Size = UDim2.new(0, 120, 0, 26)
        openBtn.Position = UDim2.new(1, -128, 0.5, -13)
        openBtn.BackgroundColor3 = INP
        openBtn.BackgroundTransparency = 0.12
        openBtn.BorderSizePixel = 0
        openBtn.Text = tostring(espColorTheme or "Mavi") .. "  ▼"
        openBtn.TextColor3 = selectedESPColor or Color3.fromRGB(60, 140, 255)
        openBtn.Font = Enum.Font.GothamBold
        openBtn.TextSize = 12
        openBtn.AutoButtonColor = false
        openBtn.ZIndex = 12
        Instance.new("UICorner", openBtn).CornerRadius = UDim.new(0, 8)
        local openStroke = Instance.new("UIStroke", openBtn)
        openStroke.Color = Color3.fromRGB(220, 220, 225)
        openStroke.Thickness = 1.2
        openStroke.Transparency = 0.35
        espColorSelectorLabel = openBtn

        local dropFrame = Instance.new("Frame", visualPage)
        dropFrame.Name = "ESPColorDrop"
        dropFrame.Size = UDim2.new(1, -16, 0, 0)
        dropFrame.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
        dropFrame.BackgroundTransparency = 0.15
        dropFrame.BorderSizePixel = 0
        dropFrame.Visible = false
        dropFrame.ClipsDescendants = true
        dropFrame.ZIndex = 30
        dropFrame.LayoutOrder = getNextOrder(visualPage)
        Instance.new("UICorner", dropFrame).CornerRadius = UDim.new(0, 10)
        local dropStroke = Instance.new("UIStroke", dropFrame)
        dropStroke.Color = Color3.fromRGB(220, 220, 225)
        dropStroke.Thickness = 1.2
        dropStroke.Transparency = 0.3
        local dropList = Instance.new("UIListLayout", dropFrame)
        dropList.FillDirection = Enum.FillDirection.Vertical
        dropList.Padding = UDim.new(0, 4)
        dropList.HorizontalAlignment = Enum.HorizontalAlignment.Center
        local dropPad = Instance.new("UIPadding", dropFrame)
        dropPad.PaddingTop = UDim.new(0, 6)
        dropPad.PaddingBottom = UDim.new(0, 6)

        local expanded = false
        local optButtons = {}
        local function refreshOpts()
            for _, b in ipairs(optButtons) do
                local active = (b.Name == tostring(espColorTheme))
                local themeCol = COLOR_THEMES[b.Name] or WHITE
                b.BackgroundColor3 = active and themeCol or Color3.fromRGB(22, 26, 32)
                b.TextColor3 = active and Color3.fromRGB(8, 10, 14) or WHITE
            end
            openBtn.Text = tostring(espColorTheme or "Mavi") .. (expanded and "  ▲" or "  ▼")
            openBtn.TextColor3 = selectedESPColor or Color3.fromRGB(60, 140, 255)
        end
        for _, themeName in ipairs(COLOR_THEME_ORDER) do
            local b = Instance.new("TextButton", dropFrame)
            b.Name = themeName
            b.Size = UDim2.new(1, -16, 0, 28)
            b.BackgroundColor3 = Color3.fromRGB(22, 26, 32)
            b.BorderSizePixel = 0
            b.Text = themeName
            b.TextColor3 = WHITE
            b.Font = Enum.Font.GothamBold
            b.TextSize = 13
            b.AutoButtonColor = false
            b.ZIndex = 31
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
            b.MouseButton1Click:Connect(function()
                applyESPColorTheme(themeName)
                expanded = false
                dropFrame.Visible = false
                dropFrame.Size = UDim2.new(1, -16, 0, 0)
                refreshOpts()
            end)
            table.insert(optButtons, b)
        end
        openBtn.MouseButton1Click:Connect(function()
            expanded = not expanded
            if expanded then
                local h = 6 + (#COLOR_THEME_ORDER * 32) + 6
                dropFrame.Size = UDim2.new(1, -16, 0, h)
                dropFrame.Visible = true
            else
                dropFrame.Size = UDim2.new(1, -16, 0, 0)
                dropFrame.Visible = false
            end
            refreshOpts()
        end)
        refreshOpts()
    end

    setJumpVisual = mkToggle(visualPage, "Infinite Jump", function(on)
        if on then
            InfiniteJump.start()
        else
            InfiniteJump.stop()
        end
        pcall(saveAllSettings)
    end)
    if setJumpVisual then setJumpVisual(InfiniteJump.isRunning()) end

    do
        local row = mkRow(visualPage, 38)
        mkLabel(row, "Jump Mode")
        local selectorBtn = Instance.new("TextButton", row)
        selectorBtn.Size = UDim2.new(0, 110, 0, 26)
        selectorBtn.Position = UDim2.new(1, -118, 0.5, -13)
        selectorBtn.BackgroundColor3 = INP
        selectorBtn.BackgroundTransparency = 0.12
        selectorBtn.BorderSizePixel = 0
        selectorBtn.Text = tostring(infJumpMode or "HOLD") .. "  ▼"
        selectorBtn.TextColor3 = WHITE
        selectorBtn.Font = Enum.Font.GothamBold
        selectorBtn.TextSize = 12
        selectorBtn.AutoButtonColor = false
        selectorBtn.ZIndex = 12
        Instance.new("UICorner", selectorBtn).CornerRadius = UDim.new(0, 8)
        local selStroke = Instance.new("UIStroke", selectorBtn)
        selStroke.Color = Color3.fromRGB(220, 220, 225)
        selStroke.Thickness = 1.2
        selStroke.Transparency = 0.35
        infJumpModeLabel = selectorBtn

        local dropdown = Instance.new("Frame", visualPage)
        dropdown.Name = "JumpModeDrop"
        dropdown.Size = UDim2.new(1, -16, 0, 0)
        dropdown.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
        dropdown.BackgroundTransparency = 0.15
        dropdown.BorderSizePixel = 0
        dropdown.Visible = false
        dropdown.ClipsDescendants = true
        dropdown.ZIndex = 30
        dropdown.LayoutOrder = getNextOrder(visualPage)
        Instance.new("UICorner", dropdown).CornerRadius = UDim.new(0, 10)
        local dropStroke = Instance.new("UIStroke", dropdown)
        dropStroke.Color = Color3.fromRGB(220, 220, 225)
        dropStroke.Thickness = 1.2
        dropStroke.Transparency = 0.3
        local dropList = Instance.new("UIListLayout", dropdown)
        dropList.FillDirection = Enum.FillDirection.Vertical
        dropList.Padding = UDim.new(0, 4)
        dropList.HorizontalAlignment = Enum.HorizontalAlignment.Center
        local dropPad = Instance.new("UIPadding", dropdown)
        dropPad.PaddingTop = UDim.new(0, 6)
        dropPad.PaddingBottom = UDim.new(0, 6)

        local modes = {"HOLD", "MANUAL"}
        local expanded = false
        local optButtons = {}
        local function refreshOpts()
            for _, b in ipairs(optButtons) do
                local active = (b.Name == tostring(infJumpMode))
                b.BackgroundColor3 = active and Color3.fromRGB(220, 220, 225) or Color3.fromRGB(22, 26, 32)
                b.TextColor3 = active and Color3.fromRGB(8, 10, 14) or WHITE
            end
            selectorBtn.Text = tostring(infJumpMode or "HOLD") .. (expanded and "  ▲" or "  ▼")
        end
        for _, modeName in ipairs(modes) do
            local b = Instance.new("TextButton", dropdown)
            b.Name = modeName
            b.Size = UDim2.new(1, -16, 0, 28)
            b.BackgroundColor3 = Color3.fromRGB(22, 26, 32)
            b.BorderSizePixel = 0
            b.Text = modeName
            b.TextColor3 = WHITE
            b.Font = Enum.Font.GothamBold
            b.TextSize = 13
            b.AutoButtonColor = false
            b.ZIndex = 31
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
            b.MouseButton1Click:Connect(function()
                infJumpMode = modeName
                if infJumpMode == "MANUAL" then
                    pcall(_G.SakuraVsStopNormalInfJumpHoldState)
                end
                expanded = false
                dropdown.Visible = false
                dropdown.Size = UDim2.new(1, -16, 0, 0)
                refreshOpts()
                pcall(saveAllSettings)
            end)
            table.insert(optButtons, b)
        end
        selectorBtn.MouseButton1Click:Connect(function()
            expanded = not expanded
            if expanded then
                dropdown.Size = UDim2.new(1, -16, 0, 6 + (#modes * 32) + 6)
                dropdown.Visible = true
            else
                dropdown.Visible = false
                dropdown.Size = UDim2.new(1, -16, 0, 0)
            end
            refreshOpts()
        end)
        refreshOpts()
    end

    do
        local row = mkRow(visualPage, 38)
        mkLabel(row, "Stretch Rez")
        local stretchPill, stretchDot = mkPill(row, 48)
        local stretchOn = false
        local function setStretch(s)
            stretchOn = s
            animPill(stretchPill, stretchDot, s)
            if s then enableStretch() else disableStretch() end
            stretchEnabled = s
        end
        local stretchClk = Instance.new("TextButton", stretchPill)
        stretchClk.Size = UDim2.new(1,0,1,0)
        stretchClk.BackgroundTransparency = 1
        stretchClk.Text = ""
        stretchClk.AutoButtonColor = false
        stretchClk.ZIndex = 10
        stretchClk.MouseButton1Click:Connect(function() setStretch(not stretchOn) end)
        _G.stretchToggleSetter = setStretch
    end

    setFovVisual = mkToggle(visualPage, "FOV", function(on)
        if on then enableCustomFov() else disableCustomFov() end
    end)
    if setFovVisual then setFovVisual(fovEnabled) end

    do
        local row = mkRow(visualPage, 38)
        mkLabel(row, "FOV Value")
        fovSliderSet = mkSlider(row, 20, 120, fovValue, function(v)
            fovValue = v
            if not fovEnabled then
                enableCustomFov()
                if setFovVisual then setFovVisual(true) end
            end
            local cam = workspace.CurrentCamera
            if cam then pcall(function() cam.FieldOfView = fovValue end) end
        end)
    end

    setAntiLagVisual = mkToggle(visualPage, "FPS Booster", function(on)
        if on then enableAntiLag() else disableAntiLag() end
    end)

    do
        local row = mkRow(visualPage, 38)
        mkLabel(row, "Sky Theme")
        skySelectorLabel = mkDropdown(visualPage, row, skyTheme or "Off", SKY_PRESETS_LIST, function(name)
            skyTheme = name
            pcall(applyCustomSky, name)
            pcall(saveAllSettings)
        end)
    end

    local configPage = contentPages["Config"]

    mkSect(configPage, "Auto Steal")
    setInstaGrab = mkToggle(configPage, "Auto Steal", function(on)
        CONFIG.AUTO_STEAL_ENABLED = on
        if on then pcall(startAutoSteal) else stopAutoSteal() end
        updateProgressBarVisibility()
    end)

    do
        local row = mkRow(configPage, 38)
        mkLabel(row, "Steal Radius")
        local container = Instance.new("Frame", row)
        container.Size = UDim2.new(0, 148, 1, 0)
        container.Position = UDim2.new(1, -156, 0, 0)
        container.BackgroundTransparency = 1
        container.ZIndex = 8
        local function applyRadius(v)
            local n = _clamp(_floor((tonumber(v) or CONFIG.STEAL_RANGE) + 0.5), 5, 300)
            CONFIG.STEAL_RANGE = n
            Steal.StealRadius = n
            if radInput then radInput.Text = tostring(n) end
            pcall(saveAllSettings)
        end
        local minusBtn = Instance.new("TextButton", container)
        minusBtn.Size = UDim2.new(0, 28, 0, 26)
        minusBtn.Position = UDim2.new(0, 0, 0.5, -13)
        minusBtn.BackgroundColor3 = INP
        minusBtn.BorderSizePixel = 0
        minusBtn.Text = "-"
        minusBtn.TextColor3 = WHITE
        minusBtn.Font = Enum.Font.GothamBold
        minusBtn.TextSize = 16
        minusBtn.AutoButtonColor = false
        minusBtn.ZIndex = 9
        Instance.new("UICorner", minusBtn).CornerRadius = UDim.new(0, 6)
        radInput = Instance.new("TextBox", container)
        radInput.Size = UDim2.new(0, 80, 0, 26)
        radInput.Position = UDim2.new(0, 34, 0.5, -13)
        radInput.BackgroundColor3 = INP
        radInput.BorderSizePixel = 0
        radInput.Text = tostring(CONFIG.STEAL_RANGE)
        radInput.TextColor3 = WHITE
        radInput.Font = Enum.Font.GothamBold
        radInput.TextSize = 13
        radInput.ClearTextOnFocus = false
        radInput.ZIndex = 9
        Instance.new("UICorner", radInput).CornerRadius = UDim.new(0, 6)
        local plusBtn = Instance.new("TextButton", container)
        plusBtn.Size = UDim2.new(0, 28, 0, 26)
        plusBtn.Position = UDim2.new(1, -28, 0.5, -13)
        plusBtn.BackgroundColor3 = INP
        plusBtn.BorderSizePixel = 0
        plusBtn.Text = "+"
        plusBtn.TextColor3 = WHITE
        plusBtn.Font = Enum.Font.GothamBold
        plusBtn.TextSize = 16
        plusBtn.AutoButtonColor = false
        plusBtn.ZIndex = 9
        Instance.new("UICorner", plusBtn).CornerRadius = UDim.new(0, 6)
        minusBtn.MouseButton1Click:Connect(function()
            applyRadius((tonumber(CONFIG.STEAL_RANGE) or 61) - 1)
        end)
        plusBtn.MouseButton1Click:Connect(function()
            applyRadius((tonumber(CONFIG.STEAL_RANGE) or 61) + 1)
        end)
        radInput.FocusLost:Connect(function()
            applyRadius(radInput.Text)
        end)
    end

    do
        local row = mkRow(configPage, 38)
        mkLabel(row, "Auto Steal Mode")
        local selectorBtn = Instance.new("TextButton", row)
        selectorBtn.Size = UDim2.new(0, 130, 0, 26)
        selectorBtn.Position = UDim2.new(1, -138, 0.5, -13)
        selectorBtn.BackgroundColor3 = INP
        selectorBtn.BackgroundTransparency = 0.12
        selectorBtn.BorderSizePixel = 0
        selectorBtn.Text = autoStealVariantName(autoStealVariant) .. "  ▼"
        selectorBtn.TextColor3 = WHITE
        selectorBtn.Font = Enum.Font.GothamBold
        selectorBtn.TextSize = 12
        selectorBtn.AutoButtonColor = false
        selectorBtn.ZIndex = 12
        Instance.new("UICorner", selectorBtn).CornerRadius = UDim.new(0, 8)
        local selStroke = Instance.new("UIStroke", selectorBtn)
        selStroke.Color = Color3.fromRGB(220, 220, 225)
        selStroke.Thickness = 1.2
        selStroke.Transparency = 0.35
        autoStealVariantLabel = selectorBtn

        local dropdown = Instance.new("Frame", configPage)
        dropdown.Name = "AutoStealModeDrop"
        dropdown.Size = UDim2.new(1, -16, 0, 0)
        dropdown.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
        dropdown.BackgroundTransparency = 0.15
        dropdown.BorderSizePixel = 0
        dropdown.Visible = false
        dropdown.ClipsDescendants = true
        dropdown.ZIndex = 30
        dropdown.LayoutOrder = getNextOrder(configPage)
        Instance.new("UICorner", dropdown).CornerRadius = UDim.new(0, 10)
        local dropStroke = Instance.new("UIStroke", dropdown)
        dropStroke.Color = Color3.fromRGB(220, 220, 225)
        dropStroke.Thickness = 1.2
        dropStroke.Transparency = 0.3
        local dropList = Instance.new("UIListLayout", dropdown)
        dropList.FillDirection = Enum.FillDirection.Vertical
        dropList.Padding = UDim.new(0, 4)
        dropList.HorizontalAlignment = Enum.HorizontalAlignment.Center
        local dropPad = Instance.new("UIPadding", dropdown)
        dropPad.PaddingTop = UDim.new(0, 6)
        dropPad.PaddingBottom = UDim.new(0, 6)

        local expanded = false
        local optButtons = {}
        local function refreshOpts()
            local cur = autoStealVariantName(autoStealVariant)
            for _, b in ipairs(optButtons) do
                local active = (b.Name == cur)
                b.BackgroundColor3 = active and Color3.fromRGB(220, 220, 225) or Color3.fromRGB(22, 26, 32)
                b.TextColor3 = active and Color3.fromRGB(8, 10, 14) or WHITE
            end
            selectorBtn.Text = cur .. (expanded and "  ▲" or "  ▼")
        end
        for i, modeName in ipairs(AUTO_STEAL_VARIANT_NAMES) do
            local b = Instance.new("TextButton", dropdown)
            b.Name = modeName
            b.Size = UDim2.new(1, -16, 0, 28)
            b.BackgroundColor3 = Color3.fromRGB(22, 26, 32)
            b.BorderSizePixel = 0
            b.Text = modeName
            b.TextColor3 = WHITE
            b.Font = Enum.Font.GothamBold
            b.TextSize = 13
            b.AutoButtonColor = false
            b.ZIndex = 31
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
            local idx = i
            b.MouseButton1Click:Connect(function()
                autoStealVariant = idx
                expanded = false
                dropdown.Visible = false
                dropdown.Size = UDim2.new(1, -16, 0, 0)
                refreshOpts()
                pcall(saveAllSettings)
            end)
            table.insert(optButtons, b)
        end
        selectorBtn.MouseButton1Click:Connect(function()
            expanded = not expanded
            if expanded then
                dropdown.Size = UDim2.new(1, -16, 0, 6 + (#AUTO_STEAL_VARIANT_NAMES * 32) + 6)
                dropdown.Visible = true
            else
                dropdown.Visible = false
                dropdown.Size = UDim2.new(1, -16, 0, 0)
            end
            refreshOpts()
        end)
        refreshOpts()
    end

    mkSect(configPage, "UI Settings")
    do
        local row = mkRow(configPage, 38)
        mkLabel(row, "UI Scale")
        uiScaleBox = mkBox(row, uiScaleValue, 50, 56, function(v)
            local n = _clamp(_floor(v+0.5), 50, 150)
            uiScaleValue = n
            if mainUIScale then mainUIScale.Scale = n/100 end
        end)
    end

    do
        local row = mkRow(configPage, 38)
        mkLabel(row, "Steal Bar Scale")
        mkBox(row, stealBarScale or 100, 50, 56, function(v)
            local n = _clamp(_floor(v+0.5), 50, 200)
            stealBarScale = n
            if pbScale then pbScale.Scale = n/100 end
            pcall(saveAllSettings)
        end)
    end

    do
        local row = mkRow(configPage, 38)
        mkLabel(row, "Float Scale")
        local box = mkBox(row, _floor(floatingButtonScale * 100), 50, 56, function(v)
            local val = _clamp(v, 50, 200)
            floatingButtonScale = val / 100
            applyFloatingButtonScale()
            saveAllSettings()
        end)
    end

    do
        local row = mkRow(configPage, 38)
        mkLabel(row, "Float Shape")
        local shapes = {"Rounded", "Square", "Circle"}
        local shapeIdx = 1
        for i, s in ipairs(shapes) do
            if s == tostring(floatingButtonShape or "Rounded") then shapeIdx = i; break end
        end
        local container = Instance.new("Frame", row)
        container.Size = UDim2.new(0, 160, 1, 0)
        container.Position = UDim2.new(1, -168, 0, 0)
        container.BackgroundTransparency = 1
        container.ZIndex = 8
        local leftBtn = Instance.new("TextButton", container)
        leftBtn.Size = UDim2.new(0, 28, 0, 26)
        leftBtn.Position = UDim2.new(0, 0, 0.5, -13)
        leftBtn.BackgroundColor3 = INP
        leftBtn.BorderSizePixel = 0
        leftBtn.Text = "<"
        leftBtn.TextColor3 = BLACK
        leftBtn.Font = Enum.Font.GothamBold
        leftBtn.TextSize = 13
        leftBtn.AutoButtonColor = false
        leftBtn.ZIndex = 9
        Instance.new("UICorner", leftBtn).CornerRadius = UDim.new(0, 6)
        local shapeLabel = Instance.new("TextLabel", container)
        shapeLabel.Size = UDim2.new(0, 96, 0, 26)
        shapeLabel.Position = UDim2.new(0, 32, 0.5, -13)
        shapeLabel.BackgroundColor3 = INP
        shapeLabel.BorderSizePixel = 0
        shapeLabel.Text = shapes[shapeIdx]
        shapeLabel.TextColor3 = BLACK
        shapeLabel.Font = Enum.Font.GothamBold
        shapeLabel.TextSize = 12
        shapeLabel.ZIndex = 9
        Instance.new("UICorner", shapeLabel).CornerRadius = UDim.new(0, 6)
        local rightBtn = Instance.new("TextButton", container)
        rightBtn.Size = UDim2.new(0, 28, 0, 26)
        rightBtn.Position = UDim2.new(1, -28, 0.5, -13)
        rightBtn.BackgroundColor3 = INP
        rightBtn.BorderSizePixel = 0
        rightBtn.Text = ">"
        rightBtn.TextColor3 = BLACK
        rightBtn.Font = Enum.Font.GothamBold
        rightBtn.TextSize = 13
        rightBtn.AutoButtonColor = false
        rightBtn.ZIndex = 9
        Instance.new("UICorner", rightBtn).CornerRadius = UDim.new(0, 6)
        local function cycleShape(dir)
            shapeIdx = shapeIdx + dir
            if shapeIdx < 1 then shapeIdx = #shapes end
            if shapeIdx > #shapes then shapeIdx = 1 end
            floatingButtonShape = shapes[shapeIdx]
            shapeLabel.Text = floatingButtonShape
            applyFloatingButtonShape()
            saveAllSettings()
        end
        leftBtn.MouseButton1Click:Connect(function() cycleShape(-1) end)
        rightBtn.MouseButton1Click:Connect(function() cycleShape(1) end)
    end

    do
        local row = mkRow(configPage, 38)
        mkLabel(row, "Background")
        local bgs = backgroundImages or { "118241258424065", "137090941888778", "106638406471484", "126843729942853", "132235750206658" }
        local idx = tonumber(backgroundIndex) or 1
        if idx < 1 then idx = 1 end
        if idx > #bgs then idx = 1 end
        local container = Instance.new("Frame", row)
        container.Size = UDim2.new(0, 160, 1, 0)
        container.Position = UDim2.new(1, -168, 0, 0)
        container.BackgroundTransparency = 1
        container.ZIndex = 8
        local leftBtn = Instance.new("TextButton", container)
        leftBtn.Size = UDim2.new(0, 28, 0, 26)
        leftBtn.Position = UDim2.new(0, 0, 0.5, -13)
        leftBtn.BackgroundColor3 = Color3.fromRGB(255, 140, 0)
        leftBtn.BackgroundTransparency = 0.15
        leftBtn.BorderSizePixel = 0
        leftBtn.Text = "<"
        leftBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        leftBtn.Font = Enum.Font.GothamBold
        leftBtn.TextSize = 13
        leftBtn.AutoButtonColor = false
        leftBtn.ZIndex = 9
        Instance.new("UICorner", leftBtn).CornerRadius = UDim.new(0, 6)
        backgroundSelectorLabel = Instance.new("TextLabel", container)
        backgroundSelectorLabel.Size = UDim2.new(0, 96, 0, 26)
        backgroundSelectorLabel.Position = UDim2.new(0, 32, 0.5, -13)
        backgroundSelectorLabel.BackgroundColor3 = Color3.fromRGB(30, 20, 8)
        backgroundSelectorLabel.BorderSizePixel = 0
        backgroundSelectorLabel.Text = "BG " .. tostring(idx)
        backgroundSelectorLabel.TextColor3 = Color3.fromRGB(255, 140, 0)
        backgroundSelectorLabel.Font = Enum.Font.GothamBold
        backgroundSelectorLabel.TextSize = 12
        backgroundSelectorLabel.ZIndex = 9
        Instance.new("UICorner", backgroundSelectorLabel).CornerRadius = UDim.new(0, 6)
        local rightBtn = Instance.new("TextButton", container)
        rightBtn.Size = UDim2.new(0, 28, 0, 26)
        rightBtn.Position = UDim2.new(1, -28, 0.5, -13)
        rightBtn.BackgroundColor3 = Color3.fromRGB(255, 140, 0)
        rightBtn.BackgroundTransparency = 0.15
        rightBtn.BorderSizePixel = 0
        rightBtn.Text = ">"
        rightBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        rightBtn.Font = Enum.Font.GothamBold
        rightBtn.TextSize = 13
        rightBtn.AutoButtonColor = false
        rightBtn.ZIndex = 9
        Instance.new("UICorner", rightBtn).CornerRadius = UDim.new(0, 6)
        local function cycleBg(dir)
            local cur = math.floor(tonumber(backgroundIndex) or 1)
            local nextIdx = cur + dir
            if nextIdx < 1 then nextIdx = 5 end
            if nextIdx > 5 then nextIdx = 1 end
            setBackgroundIndex(nextIdx)
            if backgroundSelectorLabel then
                backgroundSelectorLabel.Text = "BG " .. tostring(nextIdx)
            end
        end
        leftBtn.MouseButton1Click:Connect(function() cycleBg(-1) end)
        rightBtn.MouseButton1Click:Connect(function() cycleBg(1) end)
    end

    do
        local row = mkRow(configPage, 38)
        mkLabel(row, "Steal Bar BG")
        local idx = math.floor(tonumber(stealBarBackgroundIndex) or 1)
        if idx < 1 then idx = 1 end
        if idx > 5 then idx = 1 end
        local container = Instance.new("Frame", row)
        container.Size = UDim2.new(0, 160, 1, 0)
        container.Position = UDim2.new(1, -168, 0, 0)
        container.BackgroundTransparency = 1
        container.ZIndex = 8
        local leftBtn = Instance.new("TextButton", container)
        leftBtn.Size = UDim2.new(0, 28, 0, 26)
        leftBtn.Position = UDim2.new(0, 0, 0.5, -13)
        leftBtn.BackgroundColor3 = Color3.fromRGB(255, 140, 0)
        leftBtn.BackgroundTransparency = 0.15
        leftBtn.BorderSizePixel = 0
        leftBtn.Text = "<"
        leftBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        leftBtn.Font = Enum.Font.GothamBold
        leftBtn.TextSize = 13
        leftBtn.AutoButtonColor = false
        leftBtn.ZIndex = 9
        Instance.new("UICorner", leftBtn).CornerRadius = UDim.new(0, 6)
        stealBarBackgroundSelectorLabel = Instance.new("TextLabel", container)
        stealBarBackgroundSelectorLabel.Size = UDim2.new(0, 96, 0, 26)
        stealBarBackgroundSelectorLabel.Position = UDim2.new(0, 32, 0.5, -13)
        stealBarBackgroundSelectorLabel.BackgroundColor3 = Color3.fromRGB(30, 20, 8)
        stealBarBackgroundSelectorLabel.BorderSizePixel = 0
        stealBarBackgroundSelectorLabel.Text = "SB " .. tostring(idx)
        stealBarBackgroundSelectorLabel.TextColor3 = Color3.fromRGB(255, 140, 0)
        stealBarBackgroundSelectorLabel.Font = Enum.Font.GothamBold
        stealBarBackgroundSelectorLabel.TextSize = 12
        stealBarBackgroundSelectorLabel.ZIndex = 9
        Instance.new("UICorner", stealBarBackgroundSelectorLabel).CornerRadius = UDim.new(0, 6)
        local rightBtn = Instance.new("TextButton", container)
        rightBtn.Size = UDim2.new(0, 28, 0, 26)
        rightBtn.Position = UDim2.new(1, -28, 0.5, -13)
        rightBtn.BackgroundColor3 = Color3.fromRGB(255, 140, 0)
        rightBtn.BackgroundTransparency = 0.15
        rightBtn.BorderSizePixel = 0
        rightBtn.Text = ">"
        rightBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        rightBtn.Font = Enum.Font.GothamBold
        rightBtn.TextSize = 13
        rightBtn.AutoButtonColor = false
        rightBtn.ZIndex = 9
        Instance.new("UICorner", rightBtn).CornerRadius = UDim.new(0, 6)
        local function cycleSb(dir)
            local cur = math.floor(tonumber(stealBarBackgroundIndex) or 1)
            local nextIdx = cur + dir
            if nextIdx < 1 then nextIdx = 5 end
            if nextIdx > 5 then nextIdx = 1 end
            setStealBarBackgroundIndex(nextIdx)
        end
        leftBtn.MouseButton1Click:Connect(function() cycleSb(-1) end)
        rightBtn.MouseButton1Click:Connect(function() cycleSb(1) end)
    end

    mkSect(configPage, "Config Management")
    do
        local row = mkRow(configPage, 44)
        row.Size = UDim2.new(1, 0, 0, 44)
        local saveBtn = Instance.new("TextButton", row)
        saveBtn.Size = UDim2.new(1, -12, 0.8, 0)
        saveBtn.Position = UDim2.new(0, 6, 0.1, 0)
        saveBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        saveBtn.BackgroundTransparency = 0.15
        saveBtn.BorderSizePixel = 0
        saveBtn.Text = "SAVE CONFIG"
        saveBtn.TextColor3 = WHITE
        saveBtn.Font = Enum.Font.GothamBold
        saveBtn.TextSize = 13
        saveBtn.TextStrokeColor3 = Color3.fromRGB(60,60,60)
        saveBtn.TextStrokeTransparency = 0
        saveBtn.AutoButtonColor = false
        saveBtn.ZIndex = 8
        Instance.new("UICorner", saveBtn).CornerRadius = UDim.new(0, 8)
        local saveStroke = Instance.new("UIStroke", saveBtn)
        saveStroke.Color = ROW_BORDER
        saveStroke.Thickness = 1.2
        saveStroke.Transparency = 0.5
        saveBtn.MouseButton1Click:Connect(function()
            local ok = saveAllSettings()
            saveBtn.Text = ok and "SAVED ✓" or "ERROR"
            task.delay(1.2, function()
                if saveBtn and saveBtn.Parent then saveBtn.Text = "SAVE CONFIG" end
            end)
        end)
    end

    do
        local row = mkRow(configPage, 44)
        row.Size = UDim2.new(1, 0, 0, 44)
        local resetPosBtn = Instance.new("TextButton", row)
        resetPosBtn.Size = UDim2.new(1, -12, 0.8, 0)
        resetPosBtn.Position = UDim2.new(0, 6, 0.1, 0)
        resetPosBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        resetPosBtn.BackgroundTransparency = 0.15
        resetPosBtn.BorderSizePixel = 0
        resetPosBtn.Text = "RESET POSITIONS"
        resetPosBtn.TextColor3 = WHITE
        resetPosBtn.Font = Enum.Font.GothamBold
        resetPosBtn.TextSize = 13
        resetPosBtn.TextStrokeColor3 = Color3.fromRGB(60,60,60)
        resetPosBtn.TextStrokeTransparency = 0
        resetPosBtn.AutoButtonColor = false
        resetPosBtn.ZIndex = 8
        Instance.new("UICorner", resetPosBtn).CornerRadius = UDim.new(0, 8)
        local resetStroke = Instance.new("UIStroke", resetPosBtn)
        resetStroke.Color = ROW_BORDER
        resetStroke.Thickness = 1.2
        resetStroke.Transparency = 0.5
        local resetDebounce = false
        resetPosBtn.MouseButton1Click:Connect(function()
            if resetDebounce then return end
            resetDebounce = true
            resetFloatingPositions()
            resetPosBtn.Text = "RESET ✓"
            task.delay(1.2, function()
                if resetPosBtn and resetPosBtn.Parent then
                    resetPosBtn.Text = "RESET POSITIONS"
                    resetDebounce = false
                end
            end)
        end)
    end

    do
        local row = mkRow(configPage, 44)
        row.Size = UDim2.new(1, 0, 0, 44)
        local delBtn = Instance.new("TextButton", row)
        delBtn.Size = UDim2.new(1, -12, 0.8, 0)
        delBtn.Position = UDim2.new(0, 6, 0.1, 0)
        delBtn.BackgroundColor3 = Color3.fromRGB(140, 25, 65)
        delBtn.BackgroundTransparency = 0.5
        delBtn.BorderSizePixel = 0
        delBtn.Text = "DELETE SETTINGS"
        delBtn.TextColor3 = WHITE
        delBtn.Font = Enum.Font.GothamBold
        delBtn.TextSize = 13
        delBtn.TextStrokeColor3 = Color3.fromRGB(60,60,60)
        delBtn.TextStrokeTransparency = 0
        delBtn.AutoButtonColor = false
        delBtn.ZIndex = 8
        Instance.new("UICorner", delBtn).CornerRadius = UDim.new(0, 8)
        local delStroke = Instance.new("UIStroke", delBtn)
        delStroke.Color = ROW_BORDER
        delStroke.Thickness = 1.2
        delStroke.Transparency = 0.5
        local deleteState = 0
        local originalDeleteText = "DELETE SETTINGS"
        local delDebounce = false
        delBtn.MouseButton1Click:Connect(function()
            if delDebounce then return end
            if deleteState == 0 then
                deleteState = 1
                delBtn.Text = "CONFIRM?"
                delBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 80)
                task.delay(2, function()
                    if delBtn and delBtn.Parent and deleteState == 1 then
                        deleteState = 0
                        delBtn.Text = originalDeleteText
                        delBtn.BackgroundColor3 = Color3.fromRGB(140, 25, 65)
                    end
                end)
            elseif deleteState == 1 then
                delDebounce = true
                local success = pcall(resetToFactoryDefaults)
                delBtn.Text = success and "DELETED ✓" or "ERROR"
                delBtn.BackgroundColor3 = Color3.fromRGB(140, 25, 65)
                deleteState = 0
                task.delay(1.5, function()
                    if delBtn and delBtn.Parent then
                        delBtn.Text = originalDeleteText
                        delBtn.BackgroundColor3 = Color3.fromRGB(140, 25, 65)
                        delDebounce = false
                    end
                end)
            end
        end)
    end

    local keyPage = contentPages["Keybinds"]
    -- Spread keybind rows to fill the tab (less empty space at bottom)
    do
        local layout = keyPage:FindFirstChildOfClass("UIListLayout")
        if layout then layout.Padding = UDim.new(0, 8) end
        local pad = keyPage:FindFirstChildOfClass("UIPadding")
        if pad then
            pad.PaddingTop = UDim.new(0, 4)
            pad.PaddingBottom = UDim.new(0, 10)
        end
    end
    mkSect(keyPage, "Keybinds")
    addKeybindRow(keyPage, "Carry Mode", KB.CarryToggle)
    addKeybindRow(keyPage, "Lagger Mode", KB.LaggerMode)
    addKeybindRow(keyPage, "Auto Left", KB.AutoLeft)
    addKeybindRow(keyPage, "Auto Right", KB.AutoRight)
    addKeybindRow(keyPage, "Auto Bat", KB.AutoBat)
    addKeybindRow(keyPage, "Anti Bat", KB.AntiBat)
    addKeybindRow(keyPage, "TP", KB.TPBat)
    -- Bat V2 keybind removed from GUI
    addKeybindRow(keyPage, "Insta Reset", KB.InstaReset)
    addKeybindRow(keyPage, "TP Down", KB.TPFloor)
    addKeybindRow(keyPage, "Drop Brainrot", KB.DropBrainrot)
    addKeybindRow(keyPage, "Hide GUI", KB.GuiHide)

    local spacer = Instance.new("Frame", keyPage)
    spacer.Size = UDim2.new(1, 0, 0, 8)
    spacer.BackgroundTransparency = 1
    spacer.LayoutOrder = getNextOrder(keyPage)
    spacer.ZIndex = 7

    -- ============================================================
    -- AUTO STEAL BAR — image style (capsule edges + size)
    -- ============================================================
    pbFrame = Instance.new("Frame", gui)

    -- Auto Steal bar background (selectable in Settings)
    do
        local oldBg = pbFrame:FindFirstChild("AutoStealBackground")
        if oldBg then oldBg:Destroy() end
        local autoBg = Instance.new("ImageLabel")
        autoBg.Name = "AutoStealBackground"
        autoBg.Size = UDim2.new(1, 0, 1, 0)
        autoBg.Position = UDim2.new(0, 0, 0, 0)
        autoBg.BackgroundTransparency = 1
        autoBg.BorderSizePixel = 0
        autoBg.ScaleType = Enum.ScaleType.Crop
        autoBg.ImageTransparency = 0.18
        autoBg.ZIndex = 50
        autoBg.Parent = pbFrame
        local c = Instance.new("UICorner", autoBg)
        c.CornerRadius = UDim.new(0, 10)
        pcall(applyStealBarBackground)
    end
    -- Görseldeki uzunluk / yükseklik oranına yakın
    pbFrame.Size = UDim2.new(0, 440, 0, 52)
    pbFrame.Position = UDim2.new(0.5, -220, 1, -66)
    pbFrame.BackgroundColor3 = Color3.fromRGB(18, 28, 42)
    pbFrame.BackgroundTransparency = 0.18
    pbFrame.BorderSizePixel = 0
    pbFrame.Active = true
    pbFrame.ClipsDescendants = true
    pbFrame.Visible = CONFIG.AUTO_STEAL_ENABLED
    pbFrame.ZIndex = 50

    -- AUTO STEAL BAR arka planı (Settings'ten seçilir)
    local pbBackground = Instance.new("ImageLabel", pbFrame)
    pbBackground.Name = "StealBarBackground"
    pbBackground.Size = UDim2.new(1, 0, 1, 0)
    pbBackground.Position = UDim2.new(0, 0, 0, 0)
    pbBackground.BackgroundTransparency = 1
    pbBackground.BorderSizePixel = 0
    pbBackground.ImageTransparency = 0.18
    pbBackground.ImageColor3 = Color3.fromRGB(255, 255, 255)
    pbBackground.ScaleType = Enum.ScaleType.Crop
    pbBackground.ZIndex = 50
    pbBackground.Active = false
    Instance.new("UICorner", pbBackground).CornerRadius = UDim.new(0, 14)
    pcall(function()
        local id = getStealBarBackgroundId()
        setImageOnLabel(pbBackground, id)
    end)

    local pbBackgroundWash = Instance.new("Frame", pbFrame)
    pbBackgroundWash.Name = "StealBarBackgroundWash"
    pbBackgroundWash.Size = UDim2.new(1, 0, 1, 0)
    pbBackgroundWash.BackgroundColor3 = Color3.fromRGB(8, 12, 18)
    pbBackgroundWash.BackgroundTransparency = 0.58
    pbBackgroundWash.BorderSizePixel = 0
    pbBackgroundWash.ZIndex = 51
    pbBackgroundWash.Active = false
    Instance.new("UICorner", pbBackgroundWash).CornerRadius = UDim.new(0, 14)

    -- Dikdörtgen + hafif yuvarlak kenar (foto tarzı)
    local pbCorner = Instance.new("UICorner", pbFrame)
    pbCorner.CornerRadius = UDim.new(0, 14)

    local pbBorder = Instance.new("UIStroke", pbFrame)
    pbBorder.Name = "StealBarStroke"
    pbBorder.Color = Color3.fromRGB(70, 110, 140)
    pbBorder.Thickness = 1.2
    pbBorder.Transparency = 0.35
    pbBorder.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    pbBorder.ZIndex = 58

    pbScale = Instance.new("UIScale", pbFrame)
    pbScale.Scale = (tonumber(stealBarScale) or 100) / 100

    if savedProgressBarPos then
        pbFrame.Position = UDim2.new(
            savedProgressBarPos.XScale or 0.5,
            savedProgressBarPos.XOffset or -230,
            savedProgressBarPos.YScale or 1,
            savedProgressBarPos.YOffset or -62
        )
    end

    -- SOL: %
    local leftCol = Instance.new("Frame", pbFrame)
    leftCol.Name = "LeftCol"
    leftCol.Size = UDim2.new(0, 58, 1, -10)
    leftCol.Position = UDim2.new(0, 16, 0, 5)
    leftCol.BackgroundTransparency = 1
    leftCol.ZIndex = 55

    progressPct = Instance.new("TextLabel", leftCol)
    progressPct.Name = "ProgressPct"
    progressPct.Size = UDim2.new(1, 0, 1, 0)
    progressPct.BackgroundTransparency = 1
    progressPct.Text = "0%"
    progressPct.TextColor3 = Color3.fromRGB(255, 255, 255)
    progressPct.Font = Enum.Font.GothamBold
    progressPct.TextSize = 17
    progressPct.TextXAlignment = Enum.TextXAlignment.Left
    progressPct.TextYAlignment = Enum.TextYAlignment.Center
    progressPct.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    progressPct.TextStrokeTransparency = 0.4
    progressPct.ZIndex = 56

    -- ORTA: progress track (görseldeki ince uzun bar)
    local progressRow = Instance.new("Frame", pbFrame)
    progressRow.Name = "ProgressRow"
    progressRow.Size = UDim2.new(1, -240, 0, 12)
    progressRow.Position = UDim2.new(0, 74, 0.5, -6)
    progressRow.BackgroundTransparency = 1
    progressRow.ZIndex = 54

    local fillRegion = Instance.new("Frame", progressRow)
    fillRegion.Name = "FillRegion"
    fillRegion.Size = UDim2.new(1, 0, 1, 0)
    fillRegion.BackgroundColor3 = Color3.fromRGB(25, 40, 55)
    fillRegion.BackgroundTransparency = 0.25
    fillRegion.BorderSizePixel = 0
    fillRegion.ClipsDescendants = true
    fillRegion.ZIndex = 55
    Instance.new("UICorner", fillRegion).CornerRadius = UDim.new(1, 0)

    progressFill = Instance.new("Frame", fillRegion)
    progressFill.Name = "ProgressFill"
    progressFill.Size = UDim2.new(0, 0, 1, 0)
    progressFill.BackgroundColor3 = Color3.fromRGB(80, 170, 230)
    progressFill.BorderSizePixel = 0
    progressFill.ZIndex = 56
    Instance.new("UICorner", progressFill).CornerRadius = UDim.new(1, 0)
    local fillGrad = Instance.new("UIGradient", progressFill)
    fillGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, Color3.fromRGB(40, 130, 200)),
        ColorSequenceKeypoint.new(0.55, Color3.fromRGB(100, 200, 245)),
        ColorSequenceKeypoint.new(1.00, Color3.fromRGB(220, 245, 255)),
    })

    local glowEnd = Instance.new("Frame", progressFill)
    glowEnd.Size = UDim2.new(0, 14, 1, 0)
    glowEnd.Position = UDim2.new(1, -14, 0, 0)
    glowEnd.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    glowEnd.BackgroundTransparency = 0.45
    glowEnd.BorderSizePixel = 0
    glowEnd.ZIndex = 57
    Instance.new("UICorner", glowEnd).CornerRadius = UDim.new(1, 0)

    -- SAĞ: FPS - MS (görseldeki gibi barın sağ içi)
    local rightCol = Instance.new("Frame", pbFrame)
    rightCol.Name = "RightCol"
    rightCol.Size = UDim2.new(0, 140, 1, -10)
    rightCol.Position = UDim2.new(1, -152, 0, 5)
    rightCol.BackgroundTransparency = 1
    rightCol.ZIndex = 55

    local fpsNeon = Instance.new("TextLabel", rightCol)
    fpsNeon.Name = "FPSNeon"
    fpsNeon.Size = UDim2.new(1, 0, 1, 0)
    fpsNeon.BackgroundTransparency = 1
    fpsNeon.Text = "--FPS - --ms"
    fpsNeon.TextColor3 = Color3.fromRGB(200, 220, 235)
    fpsNeon.Font = Enum.Font.GothamMedium
    fpsNeon.TextSize = 12
    fpsNeon.TextXAlignment = Enum.TextXAlignment.Right
    fpsNeon.TextYAlignment = Enum.TextYAlignment.Center
    fpsNeon.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    fpsNeon.TextStrokeTransparency = 0.45
    fpsNeon.ZIndex = 56

    -- Discord yok
    local discordLabelTop = Instance.new("TextLabel", pbFrame)
    discordLabelTop.Name = "DiscordLabel"
    discordLabelTop.Visible = false
    discordLabelTop.Size = UDim2.new(0, 0, 0, 0)
    discordLabelTop.Text = ""
    discordLabelTop.BackgroundTransparency = 1
    discordLabelTop.ZIndex = 1

    drag(pbFrame)

    task.spawn(function()
        local lastFrame = _tick()
        local fpsSamples = {}
        local fpsAvg = 60
        RunService.RenderStepped:Connect(function()
            local now = _tick()
            local dt = now - lastFrame
            lastFrame = now
            if dt > 0 then
                table.insert(fpsSamples, 1 / dt)
                if #fpsSamples > 30 then table.remove(fpsSamples, 1) end
                local sum = 0
                for _, v in ipairs(fpsSamples) do sum = sum + v end
                fpsAvg = sum / #fpsSamples
            end
        end)
        while true do
            local ping = 0
            pcall(function() ping = LP:GetNetworkPing() * 1000 end)
            if fpsNeon and fpsNeon.Parent then
                fpsNeon.Text = string.format("%dFPS - %dms", _floor(fpsAvg + 0.5), _floor(ping + 0.5))
            end
            task.wait(0.75)
        end
    end)

    drag(main)
end


local function getFloatingCornerRadius()
    local shape = tostring(floatingButtonShape or "Rounded")
    if shape == "Square" then
        return UDim.new(0, 0)
    elseif shape == "Circle" then
        return UDim.new(1, 0) -- fully round (ball / pill)
    end
    return UDim.new(0, 14) -- Rounded
end

function applyFloatingButtonShape()
    local radius = getFloatingCornerRadius()
    local function applyTo(obj)
        if not obj then return end
        local corner = obj:FindFirstChildOfClass("UICorner")
        if not corner then
            corner = Instance.new("UICorner")
            corner.Parent = obj
        end
        corner.CornerRadius = radius
        -- Child asset bg / overlay must match parent radius
        -- (otherwise Circle looks square — only outer corner was updating)
        for _, child in ipairs(obj:GetChildren()) do
            if child.Name == "BtnAssetBg" or child.Name == "BtnAssetOverlay"
                or child:IsA("ImageLabel") or (child:IsA("Frame") and child.Name ~= "TextLabel") then
                if child:IsA("GuiObject") and not child:IsA("TextLabel") and not child:IsA("TextButton") then
                    local c = child:FindFirstChildOfClass("UICorner")
                    if not c then
                        c = Instance.new("UICorner")
                        c.Parent = child
                    end
                    c.CornerRadius = radius
                end
            end
        end
    end
    if MobilePanel then
        local container = MobilePanel:FindFirstChild("FloatingPanel")
        local btnContainer = container and container:FindFirstChild("ButtonsContainer")
        if btnContainer then
            for _, btn in ipairs(btnContainer:GetChildren()) do
                if btn:IsA("TextButton") or btn:IsA("Frame") then
                    applyTo(btn)
                end
            end
        end
    end
    if tpBatFloatingButton then
        applyTo(tpBatFloatingButton:FindFirstChild("Frame") or tpBatFloatingButton)
    end
    if batV2FloatingButton then
        applyTo(batV2FloatingButton:FindFirstChild("Frame") or batV2FloatingButton)
    end
    if instaResetFloatingButton then
        applyTo(instaResetFloatingButton:FindFirstChild("Frame") or instaResetFloatingButton)
    end
    if antiAimbotFloatingButton then
        applyTo(antiAimbotFloatingButton:FindFirstChild("Frame") or antiAimbotFloatingButton)
    end
end

function createMobilePanel()
    local panel = Instance.new("ScreenGui")
    panel.Name = "SakuraVsMobilePanel"
    panel.ResetOnSpawn = false
    panel.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    panel.DisplayOrder = 100
    pcall(function() if syn and syn.protect_gui then syn.protect_gui(panel) end end)
    local okPanel = pcall(function() panel.Parent = game:GetService("CoreGui") end)
    if not okPanel then panel.Parent = LP:WaitForChild("PlayerGui") end

    local BTN_W, BTN_H = 60, 60
    local GAP = 8
    local COLUMNS = 2
    local ROWS = 5
    -- 10 buttons (includes AntiAimbot + Taunt)
    local PANEL_W = BTN_W * COLUMNS + GAP * (COLUMNS - 1)
    local PANEL_H = BTN_H * ROWS + (GAP + 10) * (ROWS - 1)

    local container = Instance.new("Frame", panel)
    container.Name = "FloatingPanel"
    container.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
    container.Position = UDim2.new(1, -140, 0, 220)
    container.BackgroundTransparency = 1
    container.BorderSizePixel = 0
    container.Active = false
    container.Selectable = false
    container.ClipsDescendants = false

    local containerScale = Instance.new("UIScale", container)
    containerScale.Scale = floatingButtonScale
    table.insert(_floatingUIScales, containerScale)

    local btnContainer = Instance.new("Frame", container)
    btnContainer.Name = "ButtonsContainer"
    btnContainer.Size = UDim2.new(1, 0, 1, 0)
    btnContainer.BackgroundTransparency = 1
    btnContainer.ClipsDescendants = false
    btnContainer.ZIndex = 40
    container.ZIndex = 40

    local SILVER = Color3.fromRGB(180, 180, 190)
    local WHITE = Color3.fromRGB(255, 255, 255)
    local INACTIVE_BG = Color3.fromRGB(10,10,10)
    local INACTIVE_TEXT = Color3.fromRGB(0, 0, 0)
    local STROKE_COLOR = Color3.fromRGB(70,70,70)
    local ACTIVE_BG = getThemeColor()
    local ACTIVE_TEXT = Color3.fromRGB(0, 0, 0)

    local buttons = {}
    local buttonNames = {"DropBR", "AutoLeft", "AutoBat", "AutoRight", "TpDown", "Carry", "Lagger1", "Lagger2", "AntiAimbot", "Taunt"}
    local buttonTexts = {"DROP", "AUTO\nLEFT", "BAT\nAIMBOT", "AUTO\nRIGHT", "TP\nDOWN", "CARRY\nSPD", "LAGGER\nNORMAL", "LAGGER\nCARRY", "ANTI\nAIMBOT", "TAUNT"}

    local function createButton(name, text, order, isToggle, callback)
        local btn = Instance.new("TextButton", btnContainer)
        btn.Name = name
        btn.Size = UDim2.new(0, BTN_W, 0, BTN_H)
        btn.BorderSizePixel = 0
        btn.AutoButtonColor = false
        btn.Active = true
        btn.Selectable = true
        btn.ZIndex = 55
        btn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        -- Yazı TextLabel'da (UIGradient text'i karartmasın)
        btn.Text = ""
        btn.TextTransparency = 1

        -- Restore saved button position if available, otherwise use default grid
        local defX, defY = getDefaultButtonPosition(name)
        local saved = savedButtonPositions and savedButtonPositions[name]
        if saved and type(saved.X) == "number" and type(saved.Y) == "number" then
            btn.Position = UDim2.new(0, saved.X, 0, saved.Y)
        else
            btn.Position = UDim2.new(0, defX, 0, defY)
        end

        Instance.new("UICorner", btn).CornerRadius = getFloatingCornerRadius()

        -- Asset arka plan (BAT AIMBOT, TP DOWN, CARRY vb.)

        local bgGrad = Instance.new("UIGradient", btn)
        bgGrad.Name = "BtnGrad"
        bgGrad.Rotation = 90
        bgGrad.Enabled = false
        bgGrad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 255, 255)),
            ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255, 255, 255)),
            ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 255, 255)),
        })

        local stroke = Instance.new("UIStroke", btn)
        stroke.Color = Color3.fromRGB(200, 200, 205)
        stroke.Thickness = 1.4
        stroke.Transparency = 0.25
        stroke.Name = "NormalStroke"

        -- Yazi her zaman ustte ve okunakli
        local label = Instance.new("TextLabel", btn)
        label.Name = "TextLabel"
        label.Size = UDim2.new(1, -4, 1, -4)
        label.Position = UDim2.new(0, 2, 0, 2)
        label.BackgroundTransparency = 1
        label.Text = text
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.TextTransparency = 0
        label.Font = Enum.Font.GothamBlack
        label.TextSize = 10
        label.TextWrapped = true
        label.TextScaled = false
        label.Active = false
        label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        label.TextStrokeTransparency = 0.3
        label.ZIndex = 60

        local active = false
        local function setActive(state)
            active = state and true or false
            btn:SetAttribute("MobActive", active)
            paintFloatingBtn(btn, active)
            btn.Text = ""
            btn.TextTransparency = 1
        end
        setActive(false)

        local dragging = false
        local hasMoved = false
        local dragStart = nil
        local startPos = nil
        local movedDistance = 0
        local lastFire = 0
        local trackedInput = nil

        local function fireClick()
            local now = _tick()
            if now - lastFire < 0.2 then return end
            lastFire = now
            -- Only block click while repositioning in edit mode
            if editModeEnabled and not uiLocked and hasMoved then return end
            if callback then
                pcall(callback, setActive)
            end
        end

        btn.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1
               and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end
            dragging = true
            hasMoved = false
            movedDistance = 0
            dragStart = input.Position
            startPos = btn.Position
            trackedInput = input
            _isDraggingButton = true
        end)

        -- Global move so touch doesn't die when finger leaves the button slightly
        local changeConn = UIS.InputChanged:Connect(function(input)
            if not dragging then return end
            if input ~= trackedInput
               and input.UserInputType ~= Enum.UserInputType.MouseMovement
               and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end
            if not dragStart then return end
            local delta = input.Position - dragStart
            movedDistance = delta.Magnitude
            if editModeEnabled and not uiLocked and movedDistance > 6 then
                hasMoved = true
                btn.Position = UDim2.new(0, startPos.X.Offset + delta.X, 0, startPos.Y.Offset + delta.Y)
            end
        end)

        local function endDrag(input)
            if not dragging then return end
            if input and trackedInput and input ~= trackedInput
               and input.UserInputType ~= Enum.UserInputType.MouseButton1
               and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end
            if movedDistance < 8 then
                fireClick()
            elseif editModeEnabled and not uiLocked and hasMoved then
                savedButtonPositions[name] = {
                    X = btn.Position.X.Offset,
                    Y = btn.Position.Y.Offset
                }
                pcall(saveAllSettings)
            end
            dragging = false
            hasMoved = false
            dragStart = nil
            startPos = nil
            movedDistance = 0
            trackedInput = nil
            _isDraggingButton = false
        end

        btn.InputEnded:Connect(endDrag)
        local endConn = UIS.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
               or input.UserInputType == Enum.UserInputType.Touch then
                endDrag(input)
            end
        end)

        -- Activated is the most reliable on mobile TextButtons
        btn.Activated:Connect(function()
            if hasMoved and editModeEnabled and not uiLocked then return end
            fireClick()
        end)

        buttons[name] = {btn = btn, setActive = setActive, label = label}
        return setActive
    end

    for i, name in ipairs(buttonNames) do
        local text = buttonTexts[i]
        local callback
        if name == "DropBR" then
            callback = function(setActive)
                if autoBatEnabled then return end
                setActive(true)
                executeDropWithToggle(function(v)
                    if dropBrainrotSetVisual then dropBrainrotSetVisual(v) end
                end)
                task.delay(0.3, function() setActive(false) end)
            end
        elseif name == "AutoLeft" then
            callback = function(setActive)
                autoLeftEnabled = not autoLeftEnabled
                setActive(autoLeftEnabled)
                if autoLeftEnabled then startAutoLeft() else stopAutoLeft() end
                if autoLeftSetVisual then autoLeftSetVisual(autoLeftEnabled) end
            end
        elseif name == "AutoBat" then
            callback = function(setActive)
                if not autoBatEnabled then enableAutoBat() else disableAutoBat() end
                setActive(autoBatEnabled)
            end
        elseif name == "AntiAimbot" then
            callback = function(setActive)
                toggleAntiAimbot()
                setActive(antiAimbotEnabled)
                pcall(saveAllSettings)
            end
        elseif name == "AutoRight" then
            callback = function(setActive)
                autoRightEnabled = not autoRightEnabled
                setActive(autoRightEnabled)
                if autoRightEnabled then startAutoRight() else stopAutoRight() end
                if autoRightSetVisual then autoRightSetVisual(autoRightEnabled) end
            end
        elseif name == "TpDown" then
            callback = function(setActive)
                doTpDown()
                setActive(true)
                task.delay(0.2, function() setActive(false) end)
            end
        elseif name == "Carry" then
            callback = function(setActive)
                if not speedMode then
                    speedMode = true; laggerToggled = false; laggerCarryToggled = false; setActive(true)
                    if buttons.Lagger1 and buttons.Lagger1.setActive then buttons.Lagger1.setActive(false) end
                    if buttons.Lagger2 and buttons.Lagger2.setActive then buttons.Lagger2.setActive(false) end
                else
                    speedMode = false; setActive(false)
                end
                refreshSpeedModeLabel()
            end
        elseif name == "Lagger1" then
            callback = function(setActive)
                if speedMode then speedMode = false; if mobSetCarry then mobSetCarry(false) end end
                if not laggerToggled then
                    laggerToggled = true; laggerCarryToggled = false; setActive(true)
                    if buttons.Lagger2 and buttons.Lagger2.setActive then buttons.Lagger2.setActive(false) end
                else
                    laggerToggled = false; setActive(false)
                end
                refreshSpeedModeLabel()
            end
        elseif name == "Lagger2" then
            callback = function(setActive)
                if speedMode then speedMode = false; if mobSetCarry then mobSetCarry(false) end end
                if not laggerCarryToggled then
                    laggerCarryToggled = true; laggerToggled = false; setActive(true)
                    if buttons.Lagger1 and buttons.Lagger1.setActive then buttons.Lagger1.setActive(false) end
                else
                    laggerToggled = false; setActive(false)
                end
                refreshSpeedModeLabel()
            end
        elseif name == "Taunt" then
            callback = function(setActive)
                toggleTaunt()
                setActive(tauntEnabled == true)
                if setTauntVisual then setTauntVisual(tauntEnabled == true) end
                pcall(saveAllSettings)
            end
        end
        mobSetAutoBat = buttons.AutoBat and buttons.AutoBat.setActive
        mobSetAutoLeft = buttons.AutoLeft and buttons.AutoLeft.setActive
        mobSetAutoRight = buttons.AutoRight and buttons.AutoRight.setActive
        mobSetDropBR = buttons.DropBR and buttons.DropBR.setActive
        mobSetTpDown = buttons.TpDown and buttons.TpDown.setActive
        mobSetCarry = buttons.Carry and buttons.Carry.setActive
        mobSetLagger1 = buttons.Lagger1 and buttons.Lagger1.setActive
        mobSetLagger2 = buttons.Lagger2 and buttons.Lagger2.setActive

        local setActive = createButton(name, text, i-1, true, callback)
        if name == "AutoBat" then mobSetAutoBat = setActive end
        if name == "AutoLeft" then mobSetAutoLeft = setActive end
        if name == "AutoRight" then mobSetAutoRight = setActive end
        if name == "DropBR" then mobSetDropBR = setActive end
        if name == "TpDown" then mobSetTpDown = setActive end
        if name == "Carry" then mobSetCarry = setActive end
        if name == "Lagger1" then mobSetLagger1 = setActive end
        if name == "Lagger2" then mobSetLagger2 = setActive end
        if name == "AntiAimbot" then mobSetAntiAimbot = setActive end
        if name == "Taunt" then mobSetTaunt = setActive end
    end

    if buttons.AutoBat and buttons.AutoBat.setActive then buttons.AutoBat.setActive(autoBatEnabled) end
    if buttons.AutoLeft and buttons.AutoLeft.setActive then buttons.AutoLeft.setActive(autoLeftEnabled) end
    if buttons.AutoRight and buttons.AutoRight.setActive then buttons.AutoRight.setActive(autoRightEnabled) end
    if buttons.Carry and buttons.Carry.setActive then buttons.Carry.setActive(speedMode) end
    if buttons.Lagger1 and buttons.Lagger1.setActive then buttons.Lagger1.setActive(laggerToggled) end
    if buttons.Lagger2 and buttons.Lagger2.setActive then buttons.Lagger2.setActive(laggerCarryToggled) end
    if buttons.AntiAimbot and buttons.AntiAimbot.setActive then buttons.AntiAimbot.setActive(antiAimbotEnabled) end
    if buttons.Taunt and buttons.Taunt.setActive then buttons.Taunt.setActive(tauntEnabled == true) end

    -- Restore saved panel position, fallback to right side
    do
        if savedMobilePanelPos
           and type(savedMobilePanelPos.XOffset) == "number"
           and type(savedMobilePanelPos.YOffset) == "number" then
            container.Position = UDim2.new(
                savedMobilePanelPos.XScale or 1,
                savedMobilePanelPos.XOffset,
                savedMobilePanelPos.YScale or 0,
                savedMobilePanelPos.YOffset
            )
        else
            local yOff = 80
            container.Position = UDim2.new(1, -(PANEL_W + 16), 0, yOff)
            savedMobilePanelPos = {
                XScale = 1,
                XOffset = -(PANEL_W + 16),
                YScale = 0,
                YOffset = yOff
            }
        end
    end

    local draggingPanel = false
    local dragStartPos = nil
    local dragStartMousePos = nil
    local function startDragPanel(input)
        if uiLocked or _isDraggingButton or editModeEnabled then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingPanel = true
            dragStartPos = container.Position
            dragStartMousePos = input.Position
        end
    end
    local function onDragPanel(input)
        if not draggingPanel or uiLocked then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            if dragStartPos and dragStartMousePos then
                local delta = input.Position - dragStartMousePos
                local newX = dragStartPos.X.Offset + delta.X
                local newY = dragStartPos.Y.Offset + delta.Y
                container.Position = UDim2.new(dragStartPos.X.Scale, newX, dragStartPos.Y.Scale, newY)
            end
        end
    end
    local function endDragPanel()
        if draggingPanel then
            draggingPanel = false
            savedMobilePanelPos = {
                XScale = container.Position.X.Scale,
                XOffset = container.Position.X.Offset,
                YScale = container.Position.Y.Scale,
                YOffset = container.Position.Y.Offset
            }
            pcall(saveAllSettings)
        end
        dragStartPos = nil
        dragStartMousePos = nil
    end
    container.InputBegan:Connect(startDragPanel)
    container.InputEnded:Connect(endDragPanel)
    UIS.InputChanged:Connect(onDragPanel)

    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            endDragPanel()
        end
    end)

    return panel
end

function createTpBatFloatingButton()
    local SILVER = Color3.fromRGB(180, 180, 190)
    local panel = Instance.new("ScreenGui")
    panel.Name = "TpBatButton"
    panel.ResetOnSpawn = false
    panel.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    panel.DisplayOrder = 21
    pcall(function() if syn and syn.protect_gui then syn.protect_gui(panel) end end)
    local okPanel = pcall(function() panel.Parent = game:GetService("CoreGui") end)
    if not okPanel then panel.Parent = LP:WaitForChild("PlayerGui") end

    local btnFrame = Instance.new("Frame", panel)
    btnFrame.Size = UDim2.new(0, 60, 0, 60)
    btnFrame.Name = "Frame"
    if tpBatFloatingPos then
        btnFrame.Position = UDim2.new(tpBatFloatingPos.XScale or 1,
                                      tpBatFloatingPos.XOffset or -72,
                                      tpBatFloatingPos.YScale or 0,
                                      tpBatFloatingPos.YOffset or 8)
    else
        btnFrame.Position = UDim2.new(0.5, 20, 0, 10)
    end
    btnFrame.BackgroundColor3 = Color3.fromRGB(255,255,255)
    btnFrame.BackgroundTransparency = 0
    btnFrame.BorderSizePixel = 0
    btnFrame.ZIndex = 20
    Instance.new("UICorner", btnFrame).CornerRadius = getFloatingCornerRadius()
    local bgGrad = Instance.new("UIGradient", btnFrame)
    bgGrad.Name = "BtnGrad"
    bgGrad.Rotation = 90
    bgGrad.Enabled = false
    bgGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(1.00, Color3.fromRGB(240, 240, 240)),
    })
    local stroke = Instance.new("UIStroke", btnFrame)
    stroke.Color = batDesyncTpEnabled and Color3.fromRGB(200, 200, 205) or Color3.fromRGB(200, 200, 205)
    stroke.Thickness = batDesyncTpEnabled and 2.2 or 1.4
    stroke.Transparency = batDesyncTpEnabled and 0 or 0.25
    stroke.Name = "TpBatStroke"
    local label = Instance.new("TextLabel", btnFrame)
    label.Name = "TextLabel"
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = "TP"
    label.TextColor3 = Color3.fromRGB(255,255,255)
    label.Font = Enum.Font.GothamBlack
    label.TextSize = 11
    label.TextWrapped = true
    label.TextStrokeColor3 = Color3.fromRGB(0,0,0)
    label.TextStrokeTransparency = 0.3
    label.ZIndex = 60

    local uiScale = Instance.new("UIScale", btnFrame)
    uiScale.Scale = floatingButtonScale
    table.insert(_floatingUIScales, uiScale)

    local function setActive(state)
        label.Text = "TP"
        paintFloatingBtn(btnFrame, state)
    end

    local dragging = false; local hasMoved = false; local dragStart, startPos
    btnFrame.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = true; hasMoved = false; dragStart = inp.Position; startPos = btnFrame.Position
        end
    end)
    btnFrame.InputChanged:Connect(function(inp)
        if not dragging then return end
        if inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch then
            local delta = inp.Position - dragStart
            if delta.Magnitude > 5 then hasMoved = true end
            if hasMoved and not uiLocked then
                btnFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X,
                                              startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end
    end)
    btnFrame.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            if dragging then
                if not hasMoved then
                    toggleBatDesyncTp()
                    setActive(batDesyncTpEnabled)
                elseif not uiLocked and hasMoved then
                    tpBatFloatingPos = {
                        XScale = btnFrame.Position.X.Scale,
                        XOffset = btnFrame.Position.X.Offset,
                        YScale = btnFrame.Position.Y.Scale,
                        YOffset = btnFrame.Position.Y.Offset
                    }
                    pcall(saveAllSettings)
                end
                dragging = false; hasMoved = false
            end
        end
    end)

    paintFloatingBtn(btnFrame, batDesyncTpEnabled == true)
    tpBatFloatingButton = panel
    return panel
end


antiAimbotFloatingButton = nil
antiAimbotFloatingPos = nil

function createAntiAimbotFloatingButton()
    -- Kaldırıldı: mobile panel zaten ANTI AIMBOT tuşu var (çift buton olmasın)
    antiAimbotFloatingButton = nil
    return nil
end

function createBatV2FloatingButton()
    -- Sadece floating BAT V2 butonu yok; özellik / menü / keybind duruyor
    batV2FloatingButton = nil
    return nil
end

function createInstaResetFloatingButton()
    local panel = Instance.new("ScreenGui")
    panel.Name = "InstaResetButton"
    panel.ResetOnSpawn = false
    panel.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    panel.DisplayOrder = 23
    pcall(function() if syn and syn.protect_gui then syn.protect_gui(panel) end end)
    local okPanel = pcall(function() panel.Parent = game:GetService("CoreGui") end)
    if not okPanel then panel.Parent = LP:WaitForChild("PlayerGui") end

    local btnFrame = Instance.new("Frame", panel)
    btnFrame.Size = UDim2.new(0, 60, 0, 60)
    btnFrame.Name = "Frame"
    if instaResetFloatingPos then
        btnFrame.Position = UDim2.new(instaResetFloatingPos.XScale or 1,
                                      instaResetFloatingPos.XOffset or -72,
                                      instaResetFloatingPos.YScale or 0,
                                      instaResetFloatingPos.YOffset or 144)
    else
        btnFrame.Position = UDim2.new(1, -72, 0, 144)
    end
    btnFrame.BackgroundColor3 = Color3.fromRGB(255,255,255)
    btnFrame.BorderSizePixel  = 0
    btnFrame.ZIndex           = 20
    Instance.new("UICorner", btnFrame).CornerRadius = getFloatingCornerRadius()

    local bgGrad = Instance.new("UIGradient", btnFrame)
    bgGrad.Name = "BtnGrad"
    bgGrad.Rotation = 90
    bgGrad.Enabled = false
    bgGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(1.00, Color3.fromRGB(240, 240, 240)),
    })

    local stroke = Instance.new("UIStroke", btnFrame)
    stroke.Color = Color3.fromRGB(200, 200, 205)
    stroke.Thickness = 1.4
    stroke.Transparency = 0.25

    local label = Instance.new("TextLabel", btnFrame)
    label.Name = "TextLabel"
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = "RESET"
    label.TextColor3 = Color3.fromRGB(255,255,255)
    label.Font = Enum.Font.GothamBlack
    label.TextSize = 11
    label.TextStrokeColor3 = Color3.fromRGB(0,0,0)
    label.TextStrokeTransparency = 0.3
    label.TextWrapped = true
    label.ZIndex = 60

    local uiScale = Instance.new("UIScale", btnFrame)
    uiScale.Scale = floatingButtonScale
    table.insert(_floatingUIScales, uiScale)

    local dragging, hasMoved, dragStart, startPos, activeInput
    local RESET_TAP_THRESHOLD = 12

    local function pointInside(pos)
        local ap = btnFrame.AbsolutePosition
        local as = btnFrame.AbsoluteSize
        return pos.X >= ap.X and pos.X <= ap.X + as.X
           and pos.Y >= ap.Y and pos.Y <= ap.Y + as.Y
    end

    local function setActive(state)
        paintFloatingBtn(btnFrame, state and true or false)
    end
    paintFloatingBtn(btnFrame, false)

    btnFrame.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
        or inp.UserInputType == Enum.UserInputType.Touch then
            if activeInput then return end
            activeInput = inp
            dragging    = true
            hasMoved    = false
            dragStart   = inp.Position
            startPos    = btnFrame.Position
        end
    end)

    UIS.InputChanged:Connect(function(inp)
        if not dragging or not activeInput then return end
        local isTouchMove = activeInput.UserInputType == Enum.UserInputType.Touch and inp == activeInput
        local isMouseMove = activeInput.UserInputType == Enum.UserInputType.MouseButton1
                            and inp.UserInputType == Enum.UserInputType.MouseMovement
        if not isTouchMove and not isMouseMove then return end
        local delta = inp.Position - dragStart
        if delta.Magnitude > RESET_TAP_THRESHOLD then hasMoved = true end
        if hasMoved and not uiLocked then
            btnFrame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)

    UIS.InputEnded:Connect(function(inp)
        if inp ~= activeInput then return end
        if inp.UserInputType ~= Enum.UserInputType.MouseButton1
        and inp.UserInputType ~= Enum.UserInputType.Touch then return end
        if dragging then
            local delta = inp.Position - dragStart
            local validTap = not hasMoved
                             and delta.Magnitude <= RESET_TAP_THRESHOLD
                             and pointInside(inp.Position)
            if validTap then
                print("[IR] tap → instaReset()")
                setActive(true)
                if _G.InstaReset and _G.InstaReset.Trigger then
                    _G.InstaReset.Trigger()
                end
                task.delay(0.2, function() setActive(false) end)
            elseif not uiLocked and hasMoved then
                instaResetFloatingPos = {
                    XScale  = btnFrame.Position.X.Scale,
                    XOffset = btnFrame.Position.X.Offset,
                    YScale  = btnFrame.Position.Y.Scale,
                    YOffset = btnFrame.Position.Y.Offset,
                }
                pcall(saveAllSettings)
            end
            dragging    = false
            hasMoved    = false
            activeInput = nil
        end
    end)

    instaResetFloatingButton = panel
    return panel
end


batCounterV2Enabled = false
batCounterV2Debounce = false
batCounterV2Conn = nil
batCounterV2HitCooldown = false
BAT_COUNTER_V2_SWING_CD = 0.05
setBatCounterV2Visual = nil

local _batCounterV2OriginalTpState = false
local _batCounterV2SuppressCount = 0
_lastBatCounterV2Time = 0
_batCounterV2Cooldown = 3.0
_batCounterV2LockUntil = 0
-- Daha geniş algı: dibine girince kesin görsün
BAT_COUNTER_V2_TOUCH_DIST = tonumber(BAT_COUNTER_V2_TOUCH_DIST) or 10
if BAT_COUNTER_V2_TOUCH_DIST < 8 then BAT_COUNTER_V2_TOUCH_DIST = 10 end

function lockBatCounterV3(seconds)
    seconds = tonumber(seconds) or 3
    local untilT = _tick() + seconds
    if untilT > (_batCounterV2LockUntil or 0) then
        _batCounterV2LockUntil = untilT
    end
end

local function isPlayerRagdolled(player)
    if not player or not player.Character then return false end
    local hum = player.Character:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    local state = hum:GetState()
    return state == Enum.HumanoidStateType.Physics or
           state == Enum.HumanoidStateType.Ragdoll or
           state == Enum.HumanoidStateType.FallingDown
end

local function hasAnimalEquipped(player)
    if not player or not player.Character then return false end
    local char = player.Character
    local ok, v = pcall(function() return player:GetAttribute("Stealing") end)
    if ok and v == true then return true end
    local ok2, v2 = pcall(function() return char:GetAttribute("Stealing") end)
    if ok2 and v2 == true then return true end
    for _, attrName in ipairs({"Carrying","IsCarrying","HoldingAnimal","HasAnimal","Stealing"}) do
        local okA, va = pcall(function() return char:GetAttribute(attrName) end)
        if okA and va then return true end
        local okB, vb = pcall(function() return player:GetAttribute(attrName) end)
        if okB and vb then return true end
    end
    for _, name in ipairs({"Carrying","IsCarrying","Grabbed","Holding","StealHold","HasGrab","Animal","Pet"}) do
        local obj = char:FindFirstChild(name)
        if obj then
            if (obj:IsA("BoolValue") and obj.Value) or
               (obj:IsA("ObjectValue") and obj.Value) or
               (obj:IsA("StringValue") and obj.Value ~= "") or
               obj:IsA("Model") or obj:IsA("BasePart") then
                return true
            end
        end
    end
    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("Tool") then
            local n = child.Name:lower()
            if child:FindFirstChild("Handle") or n:find("animal") or n:find("pet") or n:find("brain") or n:find("steal") or n:find("talpa") then
                return true
            end
        elseif child:IsA("Model") and child.Name ~= "Humanoid" then
            local n = child.Name:lower()
            if n:find("animal") or n:find("pet") or n:find("brain") or n:find("talpa") or child:FindFirstChild("Handle") then
                return true
            end
        end
    end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and hum.WalkSpeed > 0 and hum.WalkSpeed < 25 then
        return true
    end
    return false
end

local function isBatCounterV3Blocked()
    if not batCounterV2Enabled then return true end
    if batCounterV2Debounce then return true end
    if _tick() < (_batCounterV2LockUntil or 0) then return true end
    if autoBatEnabled then return true end
    if autoBatV2Enabled then return true end
    -- TP BAT manuel açıksa çakışmasın; execute kendi açıp kapatır
    if batDesyncTpEnabled and not batCounterV2Debounce then return true end
    if hasAnimalEquipped(LP) then return true end
    return false
end

-- Geniş algı: HRP + tüm BasePart (GetDescendants), 3D + yatay
local function getAttackingPlayerWithAnimal()
    local myChar = LP.Character
    if not myChar then return nil end
    local myRoot = myChar:FindFirstChild("HumanoidRootPart")
        or myChar:FindFirstChild("UpperTorso")
        or myChar:FindFirstChild("Torso")
    if not myRoot then return nil end
    local closest, minDist = nil, _huge
    local myPos = myRoot.Position
    local touch = tonumber(BAT_COUNTER_V2_TOUCH_DIST) or 10
    local maxDist = math.max(touch, 8) + 1.5
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and plr.Character then
            local char = plr.Character
            local hum = char:FindFirstChildOfClass("Humanoid")
            if not hum or hum.Health <= 0 then continue end
            local best = _huge
            local root = char:FindFirstChild("HumanoidRootPart")
                or char:FindFirstChild("UpperTorso")
                or char:FindFirstChild("Torso")
            if root then
                local d = (root.Position - myPos).Magnitude
                if d < best then best = d end
                local dx = root.Position.X - myPos.X
                local dz = root.Position.Z - myPos.Z
                local flat = math.sqrt(dx * dx + dz * dz)
                if flat < best then best = flat end
            end
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    local d = (part.Position - myPos).Magnitude
                    if d < best then best = d end
                end
            end
            if best <= maxDist and best < minDist then
                minDist = best
                closest = plr
            end
        end
    end
    return closest
end

local function getBatV2Counter()
    local char = LP.Character
    if not char then return nil end
    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("Tool") then
            local name = child.Name:lower()
            if name:find("bat") or name:find("slap") or name:find("sword") or name:find("knife") then
                return child
            end
        end
    end
    local bp = LP:FindFirstChild("Backpack")
    if bp then
        for _, child in ipairs(bp:GetChildren()) do
            if child:IsA("Tool") then
                local name = child.Name:lower()
                if name:find("bat") or name:find("slap") or name:find("sword") or name:find("knife") then
                    child.Parent = char
                    return child
                end
            end
        end
    end
    if bp then
        for _, child in ipairs(bp:GetChildren()) do
            if child:IsA("Tool") then
                child.Parent = char
                return child
            end
        end
    end
    return nil
end

local function tryHitBatCounterV2()
    if batCounterV2HitCooldown then return end
    batCounterV2HitCooldown = true
    pcall(function()
        local bat = getBatV2Counter()
        if bat then
            bat:Activate()
            local ev = bat:FindFirstChildWhichIsA("RemoteEvent")
            if ev then ev:FireServer() end
        end
    end)
    task.delay(BAT_COUNTER_V2_SWING_CD, function()
        batCounterV2HitCooldown = false
    end)
end

local function executeBatCounterV2()
    if isBatCounterV3Blocked() then return end
    local now = _tick()
    batCounterV2Debounce = true
    _lastBatCounterV2Time = now

    local attacker = getAttackingPlayerWithAnimal()
    if not attacker or not attacker.Character then
        batCounterV2Debounce = false
        return
    end
    if hasAnimalEquipped(LP) then
        batCounterV2Debounce = false
        return
    end

    -- Hedefi kilitle: 3 sn boyunca aynı adama yapış, mesafe flicker olmasın
    local lockedTarget = attacker
    local maxDuration = 3.0
    local endTime = now + maxDuration
    local weEnabledTp = false

    if not batDesyncTpEnabled then
        pcall(startBatDesyncTp)
        if batDesyncTpSetVisual then pcall(batDesyncTpSetVisual, true) end
        if tpBatFloatingButton then
            local btnFrame = tpBatFloatingButton:FindFirstChild("Frame")
            if btnFrame then paintFloatingBtn(btnFrame, true) end
        end
        weEnabledTp = true
    end

    task.spawn(function()
        -- Kesintisiz 3 saniye vur; erken bırakma yok (ragdoll olsa bile süre dolana kadar devam)
        while _tick() < endTime and batCounterV2Enabled do
            if hasAnimalEquipped(LP) then break end
            if autoBatEnabled or autoBatV2Enabled then break end

            local attChar = lockedTarget.Character
            if not attChar then break end
            local attRoot = attChar:FindFirstChild("HumanoidRootPart")
                or attChar:FindFirstChild("UpperTorso")
                or attChar:FindFirstChild("Head")
            if not attRoot then break end

            local char = LP.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                pcall(function()
                    if sethiddenproperty then
                        sethiddenproperty(hrp, "PhysicsRepRootPart", attRoot)
                    end
                    local targetPos = attRoot.Position + _V3new(0, 0.85, 0)
                    hrp.CFrame = _CFnew(targetPos)
                    hrp.AssemblyLinearVelocity = _V3zero
                end)
            end

            batCounterV2HitCooldown = false
            tryHitBatCounterV2()
            task.wait(0.05)
        end

        if weEnabledTp and batDesyncTpEnabled then
            pcall(stopBatDesyncTp)
            if batDesyncTpSetVisual then pcall(batDesyncTpSetVisual, false) end
            if tpBatFloatingButton then
                local btnFrame = tpBatFloatingButton:FindFirstChild("Frame")
                if btnFrame then paintFloatingBtn(btnFrame, false) end
            end
        end
        _lastBatCounterV2Time = _tick()
        lockBatCounterV3(3)
        batCounterV2Debounce = false
    end)
end


function stopBatCounterV2()
    if batCounterV2Conn then
        batCounterV2Conn:Disconnect()
        batCounterV2Conn = nil
    end
    batCounterV2Debounce = false
    batCounterV2HitCooldown = false
end

function startBatCounterV2()
    if batCounterV2Conn then return end
    batCounterV2Conn = RunService.Heartbeat:Connect(function()
        if isBatCounterV3Blocked() then return end
        local character = LP.Character
        if not character then return end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then return end
        local attacker = getAttackingPlayerWithAnimal()
        if attacker then
            executeBatCounterV2()
        end
    end)
end

function toggleBatCounterV2()
    batCounterV2Enabled = not batCounterV2Enabled
    if batCounterV2Enabled then
        startBatCounterV2()
    else
        stopBatCounterV2()
    end
    return batCounterV2Enabled
end

function updateUIFromLoaded()
    task.wait()
    if normalBox then normalBox.Text = tostring(NS) end
    if carryBox then carryBox.Text = tostring(CS) end
    if radInput then radInput.Text = tostring(CONFIG.STEAL_RANGE) end
    if laggerBox then laggerBox.Text = tostring(LAGGER_SPEED) end
    if lagger2Box then lagger2Box.Text = tostring(LAGGER_CARRY_SPEED) end
    if batSpeedBox then batSpeedBox.Text = tostring(BAT_AIMBOT_SPEED) end
    if batCounterV3StudBox then batCounterV3StudBox.Text = tostring(BAT_COUNTER_V2_TOUCH_DIST or 2.5) end
    if uiScaleBox then uiScaleBox.Text = tostring(uiScaleValue) end
    -- Sync MC Bat color label + Ping Lagger power UI if already created
    if MinecraftBatColorSelector then
        MinecraftBatColorSelector.Text = tostring(minecraftBatSkinColorMode or "Default") .. "  ▼"
    end
    if KatanaColorSelector then
        KatanaColorSelector.Text = tostring(katanaSkinColorMode or "Red") .. "  ▼"
    end
    pcall(function()
        if KatanaSkin and KatanaSkin.SetColorMode and katanaSkinEnabled then
            KatanaSkin.SetColorMode(katanaSkinColorMode or "Red")
        end
    end)
    pcall(function()
        if MinecraftBatSkin and MinecraftBatSkin.SetColorMode then
            MinecraftBatSkin.SetColorMode(minecraftBatSkinColorMode or "Default")
        end
    end)
    if dropModeBtnRef then dropModeBtnRef.Text = (dropMode == 1 and "Fling" or "Jump Drop") .. "  ▼" end
    if bodyLockRangeBox then bodyLockRangeBox.Text = tostring(bodyLockRange) end
    if carrySysNormalBox then carrySysNormalBox.Text = tostring(CarrySystem.normalSpeed) end
    if carrySysCarryBox then carrySysCarryBox.Text = tostring(CarrySystem.carrySpeed) end
    if carrySysLaggerBox then carrySysLaggerBox.Text = tostring(CarrySystem.laggerSpeed) end
    if carrySysLaggerCarryBox then carrySysLaggerCarryBox.Text = tostring(CarrySystem.laggerCarrySpeed) end
    if carrySysSoftStealSpeedBox then carrySysSoftStealSpeedBox.Text = tostring(CarrySystem.softStealSpeed) end
    if carrySysSoftStealRadiusBox then carrySysSoftStealRadiusBox.Text = tostring(CarrySystem.softStealRadius) end
    if carrySystemToggleSetter then carrySystemToggleSetter(useCarrySystem) end
    refreshSpeedModeLabel()

    for _, ref in ipairs(keyButtonRefs) do
        local entry = ref.entry
        local label = (entry.gp and entry.gp.Name) or (entry.kb and entry.kb.Name) or "None"
        ref.btn.Text = label
    end

    if savedProgressBarPos and pbFrame then
        pbFrame.Position = UDim2.new(
            savedProgressBarPos.XScale or 0.5,
            savedProgressBarPos.XOffset or -220,
            savedProgressBarPos.YScale or 1,
            savedProgressBarPos.YOffset or -66
        )
    end

    backgroundImages = { "118241258424065", "137090941888778", "106638406471484", "126843729942853", "132235750206658" }
    pcall(applyBackgroundToAll)

    applyFloatingButtonScale()

    if uiLocked and setLockUIVisual then setLockUIVisual(true) end
    if editModeEnabled and setEditModeVisual then setEditModeVisual(true) end

    if _G.updateAntiRagdollUI then _G.updateAntiRagdollUI(antiRagdollMode) end
    if antiRagdollMode == "v1" then
        AntiRagdollV1.start()
    elseif antiRagdollMode == "v2" then
        startAntiRagdollV2()
    end

    if antiDieEnabled then
        if setAntiDieVisual then setAntiDieVisual(true) end
        AntiDieModule.start()
    else
        if setAntiDieVisual then setAntiDieVisual(false) end
    end
    if spinEnabled then
        pcall(startSpin)
        if setSpinVisual then setSpinVisual(true) end
    end
    -- Restore Spin Speed + Anti Aimbot Mode labels from saved config
    do
        local m = tostring(antiAimbotMode or "V1"):upper():gsub("%s+", "")
        if m ~= "V1" and m ~= "V2" then m = "V1" end
        antiAimbotMode = m
    end
    if antiAimbotModeLabel then
        antiAimbotModeLabel.Text = tostring(antiAimbotMode) .. "  ▼"
    end
    if spinSpeedSelectorLabel then
        spinSpeedSelectorLabel.Text = tostring(spinSpeedName or "Normal") .. "  ▼"
    end
    if setAntiAimbotVisual then
        pcall(setAntiAimbotVisual, antiAimbotEnabled == true)
    end
    if autoBatV2SetVisual then
        pcall(autoBatV2SetVisual, antiAimbotEnabled == true and tostring(antiAimbotMode) == "V2")
    end

    if autoStealVariantLabel then autoStealVariantLabel.Text = autoStealVariantName(autoStealVariant or 1) .. "  ▼" end
    if infJumpModeLabel then infJumpModeLabel.Text = tostring(infJumpMode or "HOLD") .. "  ▼" end
    if CONFIG.AUTO_STEAL_ENABLED and setInstaGrab then setInstaGrab(true); pcall(startAutoSteal) end
    if antiAimbotEnabled then pcall(enableAntiAimbot) end

    if medusaCounterEnabled then
        if setMedusaVisual then setMedusaVisual(true) end
        if LP.Character then setupMedusaCounter(LP.Character) end
    else
        if setMedusaVisual then setMedusaVisual(false) end
        stopMedusaCounter()
    end

    if batCounterEnabled and setBatCounterVisual then
        setBatCounterVisual(true)
        startBatCounter()
    end
    -- Bat Counter V3 removed
    batCounterV2Enabled = false
    pcall(stopBatCounterV2)
    if unwalkEnabled and setUnwalkVisual then
        setUnwalkVisual(true)
        task.spawn(function() task.wait(0.5); startUnwalk() end)
    end
    if antiLagEnabled then
        if setAntiLagVisual then setAntiLagVisual(true) end
        enableAntiLag()
    else
        if setAntiLagVisual then setAntiLagVisual(false) end
        disableAntiLag()
    end
    if espEnabled then
        toggleESP(true)
        if setESPVIsual then setESPVIsual(true) end
    else
        toggleESP(false)
        if setESPVIsual then setESPVIsual(false) end
    end

    if batAimbotModeLabel then
        batAimbotModeLabel.Text = tostring(batAimbotMode or "Normal") .. "  ▼"
    end
    if batTPVersionLabel then
        batTPVersionLabel.Text = tostring(batTPVersion or "V1") .. "  ▼"
    end
    if batDesyncTpEnabled then
        if batDesyncTpSetVisual then batDesyncTpSetVisual(true) end
        if not batDesyncTpConn then startBatDesyncTp() end
        updateTpBatButtonWithAntiDie(true)
    else
        if batDesyncTpSetVisual then batDesyncTpSetVisual(false) end
        updateTpBatButtonWithAntiDie(false)
    end

    if autoBatV2Enabled then
        if autoBatV2SetVisual then autoBatV2SetVisual(true) end
        if not _batV2Conn then startBatV2Aimbot() end
        if batV2FloatingButton then
            local btnFrame = batV2FloatingButton:FindFirstChild("Frame")
            if btnFrame then
                btnFrame.BackgroundColor3 = getThemeColor()
                local label = btnFrame:FindFirstChild("TextLabel")
                if label then label.TextColor3 = Color3.fromRGB(0,0,0) end
            end
        end
    else
        if autoBatV2SetVisual then autoBatV2SetVisual(false) end
        if batV2FloatingButton then
            local btnFrame = batV2FloatingButton:FindFirstChild("Frame")
            if btnFrame then paintFloatingBtn(btnFrame, false) end
        end
    end

    if neonWeatherEnabled then
        applyNeonWeather()
        if setNeonWeatherVisual then setNeonWeatherVisual(true) end
    else
        restoreLightingState()
        if setNeonWeatherVisual then setNeonWeatherVisual(false) end
    end

    if stretchEnabled then
        enableStretch()
        if _G.stretchToggleSetter then _G.stretchToggleSetter(true) end
    else
        if _G.stretchToggleSetter then _G.stretchToggleSetter(false) end
    end

    if setFovVisual then setFovVisual(fovEnabled) end
    if fovSliderSet then fovSliderSet(fovValue) end

    if mobSetAutoBat then mobSetAutoBat(autoBatEnabled) end
    if mobSetAutoLeft then mobSetAutoLeft(autoLeftEnabled) end
    if mobSetAutoRight then mobSetAutoRight(autoRightEnabled) end
    if mobSetCarry then mobSetCarry(speedMode) end
    if mobSetLagger1 then mobSetLagger1(laggerToggled) end
    if mobSetLagger2 then mobSetLagger2(laggerCarryToggled) end

    if bodyLockEnabled and bodyLockSetVisual then
        if _blSuppressCount == 0 then
            bodyLockSetVisual(true)
            startBodyLock()
        else
            bodyLockSetVisual(false)
        end
    end

    updateProgressBarVisibility()
    startEnemySpeed()

    toggleLockUI(uiLocked)

    if colorSelectorLabel then
        colorSelectorLabel.Text = currentColorTheme .. "  ▼"
        colorSelectorLabel.TextColor3 = selectedColor
    end
    if espColorSelectorLabel then
        espColorSelectorLabel.Text = (espColorTheme or "Mavi") .. "  ▼"
        espColorSelectorLabel.TextColor3 = selectedESPColor or Color3.fromRGB(60, 140, 255)
    end
    if autoCarrySpeedSetVisual then autoCarrySpeedSetVisual(autoCarrySpeedEnabled == true) end

    pcall(function() applyOutfitByIndex(currentOutfitIndex) end)
    if outfitSelectorLabel then
        outfitSelectorLabel.Text = OUTFITS[currentOutfitIndex].label
    end
end


-- ============================================================
-- SAKURA.VS INTRO
-- ============================================================
local function playSakuraIntro()
    local TweenService = game:GetService("TweenService")
    local Lighting = game:GetService("Lighting")
    local SoundService = game:GetService("SoundService")
    local playerGui = LP:WaitForChild("PlayerGui")

    -- Music (lives in SoundService so it survives GUI destroy)
    local sound = Instance.new("Sound")
    sound.Name = "SakuraVsIntroMusic"
    sound.SoundId = "rbxassetid://89468064746667"
    sound.Volume = 1
    sound.Parent = SoundService

    task.spawn(function()
        pcall(function()
            if not sound.IsLoaded then
                sound.Loaded:Wait()
            end
            sound.TimePosition = 2 -- skip first 2 seconds
            sound:Play()
        end)
    end)

    pcall(function()
        local old = playerGui:FindFirstChild("SakuraIntroGui")
        if old then old:Destroy() end
    end)
    pcall(function()
        local old = Lighting:FindFirstChild("IntroBlur")
        if old then old:Destroy() end
    end)

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "SakuraIntroGui"
    screenGui.IgnoreGuiInset = true
    screenGui.ResetOnSpawn = false
    screenGui.DisplayOrder = 999999
    pcall(function()
        if syn and syn.protect_gui then syn.protect_gui(screenGui) end
    end)
    local okParent = pcall(function()
        screenGui.Parent = game:GetService("CoreGui")
    end)
    if not okParent or not screenGui.Parent then
        screenGui.Parent = playerGui
    end

    local background = Instance.new("Frame")
    background.Name = "Background"
    background.Size = UDim2.new(1, 0, 1, 0)
    background.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
    background.BackgroundTransparency = 0.5
    background.BorderSizePixel = 0
    background.Parent = screenGui

    local blur = Instance.new("BlurEffect")
    blur.Name = "IntroBlur"
    blur.Size = 16
    blur.Parent = Lighting

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "TitleLabel"
    titleLabel.Size = UDim2.new(0, 500, 0, 60)
    titleLabel.Position = UDim2.new(0.5, -250, 0.47, -35)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.Text = "GG./SAKURADUELS"
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.TextScaled = true
    titleLabel.TextTransparency = 1
    titleLabel.Parent = screenGui

    local introDone = false

    task.spawn(function()
        -- Total visual intro ~3s: 0.2 wait + 0.6 fade-in + 1.4 hold + 0.8 fade-out
        task.wait(0.2)

        local tweenInfo = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local fadeInTitle = TweenService:Create(titleLabel, tweenInfo, {TextTransparency = 0})
        fadeInTitle:Play()

        task.wait(1.4)

        local fadeOutInfo = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local fadeOutTitle = TweenService:Create(titleLabel, fadeOutInfo, {TextTransparency = 1})
        local fadeOutBg = TweenService:Create(background, fadeOutInfo, {BackgroundTransparency = 1})
        local fadeOutBlur = TweenService:Create(blur, fadeOutInfo, {Size = 0})

        fadeOutTitle:Play()
        fadeOutBg:Play()
        fadeOutBlur:Play()

        fadeOutBg.Completed:Wait()

        pcall(function()
            if blur and blur.Parent then blur:Destroy() end
        end)
        pcall(function()
            if screenGui and screenGui.Parent then screenGui:Destroy() end
        end)

        introDone = true

        -- Music keeps playing after visuals, then fades out
        task.spawn(function()
            task.wait(10)
            pcall(function()
                if not sound or not sound.Parent then return end
                local fadeOutSound = TweenService:Create(sound, TweenInfo.new(1), {Volume = 0})
                fadeOutSound:Play()
                fadeOutSound.Completed:Wait()
                sound:Stop()
                sound:Destroy()
            end)
        end)
    end)

    local waitStart = os.clock()
    while not introDone and os.clock() - waitStart < 5 do
        task.wait(0.05)
    end
end


-- Intro then GUI slide-in
task.spawn(function()
    pcall(playSakuraIntro)

    buildGui()

    if loadAllSettings() then
        updateUIFromLoaded()
    end

    MobilePanel = createMobilePanel()
    pcall(applyFloatingButtonShape)
    tpBatFloatingButton = createTpBatFloatingButton()
    antiAimbotFloatingButton = nil -- tek anti aimbot: mobile panel (floating kopya kaldırıldı)
    batV2FloatingButton = nil -- Bat V2 removed from GUI
    -- batV2FloatingButton = createBatV2FloatingButton()
    instaResetFloatingButton = createInstaResetFloatingButton()

    -- Slide GUI in from left
    if showGui then
        showGui()
    elseif main then
        main.Visible = true
        main.Position = UDim2.new(1, 20, 0, 18)
        TS:Create(main, TweenInfo.new(0.55, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Position = mainOriginalPos
        }):Play()
    end

    if useCarrySystem then
        CarrySystem:start()
        CarrySystem.speedToggled = speedMode
        if laggerToggled then
        else
            CarrySystem:setLaggerMode(0)
        end
        CarrySystem:setSoftStealEnabled(false)
    end

    if LP.Character then
        task.wait(0.1)
        if waitForCharReady(LP.Character, 5) then
            setupMovementAndIndicators(LP.Character)
            if currentAnimPack ~= "Off" then
                startAnimPack(currentAnimPack)
            end
            pcall(function() applyOutfitByIndex(currentOutfitIndex) end)
        end
    end
end)


-- ============================================================
-- CONEXIÓN ÚNICA DE RESPAWN (evita race conditions)
-- ============================================================
local _respawnQueue = 0
LP.CharacterAdded:Connect(function(char)
    _respawnQueue = _respawnQueue + 1
    local myId = _respawnQueue

    if stealConnection then stealConnection:Disconnect(); stealConnection = nil end
    isStealing = false
    stopAutoLeft()
    stopAutoRight()
    stopBatCounter()
    stopBatCounterV2()
    stopMedusaCounter()
    if not _tpBatUnwalkForced then stopUnwalk() end
    stopDropBrainrot()
    if autoBatEnabled then disableAutoBat() end
    if batDesyncTpEnabled then stopBatDesyncTp() end
    if autoBatV2Enabled then disableBatV2() end
    if bodyLockEnabled then stopBodyLock() end

    local deadline = _tick() + 5
    while (not char.Parent) or (not char:FindFirstChild("HumanoidRootPart"))
          or (not char:FindFirstChildOfClass("Humanoid")) do
        if _tick() > deadline then return end
        if myId ~= _respawnQueue then return end
        task.wait(0.05)
    end

    _hookedVelParts = {}
    local _hrpRespawn = _setupVelChecked(char)
    _hookVelHRP(_hrpRespawn)

    setupMovementAndIndicators(char)

    if antiRagdollMode == "v1" then AntiRagdollV1.start()
    elseif antiRagdollMode == "v2" then startAntiRagdollV2() end

    if AntiDieModule.enabled then task.defer(function() activateOnCharacter(char) end) end
    if CONFIG.AUTO_STEAL_ENABLED then pcall(startAutoSteal) end
    if batDesyncTpEnabled then task.defer(startBatDesyncTp) end
    if autoBatV2Enabled then task.defer(startBatV2Aimbot) end
    if bodyLockEnabled and _blSuppressCount == 0 then startBodyLock() end

    if medusaCounterEnabled then
        setupMedusaCounter(char)
        if setMedusaVisual then setMedusaVisual(true) end
    else
        stopMedusaCounter()
        if setMedusaVisual then setMedusaVisual(false) end
    end

    if batCounterEnabled then startBatCounter() end
    if batCounterV2Enabled then startBatCounterV2() end
    if unwalkEnabled and not _tpBatUnwalkForced then startUnwalk() end
    if antiBatEnabled then
        task.delay(0.3, function()
            if antiBatEnabled then startAntiBat() end
        end)
    end

    if currentAnimPack ~= "Off" then
        task.wait(0.3)
        startAnimPack(currentAnimPack)
    end

    updateProgressBarVisibility()
    refreshSpeedModeLabel()

    pcall(function() applyOutfitByIndex(currentOutfitIndex) end)
    if outfitSelectorLabel then
        outfitSelectorLabel.Text = OUTFITS[currentOutfitIndex].label
    end
end)

local lastLaggerToggle = 0
local LAGGER_COOLDOWN = 0.3

UIS.InputBegan:Connect(function(input, gpe)
    if _anyKeyListening then return end
    if input.UserInputType == Enum.UserInputType.Keyboard then
        if gpe or UIS:GetFocusedTextBox() then return end
    elseif not isGamepadInput(input) then
        return
    end
    if not isBindableInput(input) then return end

    local kc = input.KeyCode
    if not kc then return end

    if kbMatch(KB.LaggerMode, kc) then
        if _tick() - lastLaggerToggle >= LAGGER_COOLDOWN then
            lastLaggerToggle = _tick()
            toggleLaggerCycle()
        end
        return
    end
    if kbMatch(KB.CarryToggle, kc) then toggleCarryMode(); return end
    if kbMatch(KB.DropBrainrot, kc) then
        if not dropActive then
            if dropBrainrotSetVisual then dropBrainrotSetVisual(true) end
            executeDropWithToggle(dropBrainrotSetVisual)
        end
        return
    end
    if kbMatch(KB.TPFloor, kc) then doTpDown(); return end
    if kbMatch(KB.InstaReset, kc) then
        if _G.InstaReset and _G.InstaReset.Trigger then
            _G.InstaReset.Trigger()
        end
        return
    end
    if kbMatch(KB.AutoLeft, kc) then
        autoLeftEnabled = not autoLeftEnabled
        if autoLeftEnabled then startAutoLeft() else stopAutoLeft() end
        if autoLeftSetVisual then autoLeftSetVisual(autoLeftEnabled) end
        if mobSetAutoLeft then mobSetAutoLeft(autoLeftEnabled) end
        return
    end
    if kbMatch(KB.AutoRight, kc) then
        autoRightEnabled = not autoRightEnabled
        if autoRightEnabled then startAutoRight() else stopAutoRight() end
        if autoRightSetVisual then autoRightSetVisual(autoRightEnabled) end
        if mobSetAutoRight then mobSetAutoRight(autoRightEnabled) end
        return
    end
    if kbMatch(KB.AutoBat, kc) then
        if not autoBatEnabled then
            enableAutoBat()
            if autoBatSetVisual then autoBatSetVisual(true) end
            if mobSetAutoBat then mobSetAutoBat(true) end
        else
            disableAutoBat()
            if autoBatSetVisual then autoBatSetVisual(false) end
            if mobSetAutoBat then mobSetAutoBat(false) end
        end
        return
    end
    if kbMatch(KB.AntiBat, kc) then
        toggleAntiBat()
        if setAntiBatVisual then setAntiBatVisual(antiBatEnabled) end
        if mobSetAntiBat then mobSetAntiBat(antiBatEnabled) end
        return
    end
    if kbMatch(KB.TPBat, kc) then
        toggleBatDesyncTp()
        if batDesyncTpSetVisual then batDesyncTpSetVisual(batDesyncTpEnabled) end
        if tpBatFloatingButton then
            local btnFrame = tpBatFloatingButton:FindFirstChild("Frame")
            if btnFrame then paintFloatingBtn(btnFrame, batDesyncTpEnabled) end
        end
        return
    end
    if kbMatch(KB.BatV2, kc) then
        toggleBatV2()
        if autoBatV2SetVisual then autoBatV2SetVisual(autoBatV2Enabled) end
        if batV2FloatingButton then
            local btnFrame = batV2FloatingButton:FindFirstChild("Frame")
            if btnFrame then paintFloatingBtn(btnFrame, autoBatV2Enabled) end
        end
        return
    end
    if kbMatch(KB.GuiHide, kc) then
        if main then
            if main.Visible then hideGui() else showGui() end
        end
        return
    end
end)