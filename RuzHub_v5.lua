--[[
    ============================================================
    RuzHub v5 Pro  --  MM2 Fan-Made Script
    UI  : WindUI  (github.com/Footagesus/WindUI)
    Game: Murder Mystery 2

    Features:
      - Full ESP  (per-role, color picker, line ESP, self toggle)
      - Silent Aim + Bullet Travel Prediction (v4 engine)
      - Shoot Murderer  (AutoKill)
      - Gold Jump / Normal Jump  (4s / 21s cooldown)
      - Grab Dropped Gun  (FIXED teleport + pickup)
      - Dropped Gun ESP + Billboard
      - Bomb Retriever  (auto background task)
      - Anti-Fling
      - FOV Changer  (slider, 50-120)
      - Stretched Screen  (wide FOV simulation, adjustable)
      - On-Screen Draggable Buttons  (enable per button from panel)
      - Mobile-First Design
    ============================================================
]]

-- ============================================================
--  SERVICES
-- ============================================================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local Camera            = Workspace.CurrentCamera
local LP                = Players.LocalPlayer

-- ============================================================
--  STATE
-- ============================================================
local BULLET_SPEED       = 250
local STRETCH_FOV_VALUE  = 110

local goldCD             = false
local normalCD           = false
local grabCD             = false

local silentAimEnabled   = false
local espEnabled         = false
local espMurderer        = true
local espSheriff         = true
local espHero            = true
local espInnocent        = false
local espSelf            = false
local espLine            = false
local espFillTrans       = 0.45
local espColors          = {
    Murderer = Color3.fromRGB(255,  50,  50),
    Sheriff  = Color3.fromRGB(  0, 120, 255),
    Hero     = Color3.fromRGB(255, 215,   0),
    Innocent = Color3.fromRGB(  0, 255, 100),
}

local antiFlingEnabled   = false
local antiFlingThreshold = 80    -- velocity threshold to trigger anti-fling
local droppedGunESP      = true
local bombRetriever      = true
local fovEnabled         = false  -- custom FOV toggle
local stretchEnabled     = false
local currentFOV         = 70
local DEFAULT_FOV        = 70

local rolesData          = {}
local lastRoleUpdate     = 0
local currentKillerChar  = nil

-- On-screen button visibility
local showGoldBtn  = true
local showNormBtn  = true
local showKillBtn  = true
local showGrabBtn  = true

-- On-screen GUI refs (set later)
local onScreenGuis = {}

-- ============================================================
--  FORWARD DECLARATIONS  (functions that call each other)
-- ============================================================
local Notify
local AutoKill
local GrabDroppedGun
local ExecuteJump
local FindGunDrop
local ClearGunESP
local ApplyGunHighlight
local RefreshOnScreenButtons

-- ============================================================
--  PREDICTION PART
-- ============================================================
local predPart = Instance.new("Part")
predPart.Name         = "RuzPredictionPart"
predPart.Size         = Vector3.new(0.5, 0.5, 0.5)
predPart.Anchored     = true
predPart.CanCollide   = false
predPart.Transparency = 1
predPart.Parent       = Workspace

-- ============================================================
--  ROLE REMOTE
-- ============================================================
local targetRemote = ReplicatedStorage:FindFirstChild("GetCurrentPlayerData", true)

local function UpdateRoles()
    if tick() - lastRoleUpdate < 0.5 then return end
    lastRoleUpdate = tick()
    if targetRemote and targetRemote:IsA("RemoteFunction") then
        local ok, data = pcall(function() return targetRemote:InvokeServer() end)
        if ok and type(data) == "table" then rolesData = data end
    end
end

local function GetPlayerRole(p)
    if rolesData[p.Name] then
        local d = rolesData[p.Name]
        local r = tostring(d.Role or d.role or d.Team or ""):lower()
        if r:find("murd")             then return "Murderer" end
        if r:find("sheriff") or r:find("gun") then return "Sheriff"  end
        if r:find("hero")             then return "Hero"     end
    end
    if p.Character then
        if p.Backpack:FindFirstChild("Knife") or p.Character:FindFirstChild("Knife") then return "Murderer" end
        if p.Backpack:FindFirstChild("Gun")   or p.Character:FindFirstChild("Gun")   then return "Sheriff"  end
    end
    return "Innocent"
end

-- ============================================================
--  DROPPED GUN ESP
-- ============================================================
local activeHL = nil
local activeBB = nil

ClearGunESP = function()
    if activeHL then activeHL:Destroy(); activeHL = nil end
    if activeBB then activeBB:Destroy(); activeBB = nil end
end

FindGunDrop = function()
    return Workspace:FindFirstChild("GunDrop", true)
end

ApplyGunHighlight = function(gunDrop)
    if not droppedGunESP then return end
    ClearGunESP()

    local hl = Instance.new("Highlight")
    hl.Adornee             = gunDrop
    hl.FillColor           = Color3.fromRGB(255, 215, 0)
    hl.OutlineColor        = Color3.fromRGB(255, 255, 255)
    hl.FillTransparency    = 0.4
    hl.OutlineTransparency = 0
    hl.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent              = gunDrop
    activeHL               = hl

    local handle = gunDrop:FindFirstChild("Handle")
                or gunDrop.PrimaryPart
                or gunDrop:FindFirstChildWhichIsA("BasePart")
    if not handle then return end

    local bb = Instance.new("BillboardGui")
    bb.Name        = "RuzGunLabel"
    bb.Adornee     = handle
    bb.Size        = UDim2.new(0, 130, 0, 36)
    bb.StudsOffset = Vector3.new(0, 3.5, 0)
    bb.AlwaysOnTop = true
    bb.MaxDistance = 300
    bb.Parent      = handle

    local bg = Instance.new("Frame", bb)
    bg.Size                   = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
    bg.BackgroundTransparency = 0.35
    bg.BorderSizePixel        = 0
    Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 6)

    local stroke = Instance.new("UIStroke", bg)
    stroke.Color       = Color3.fromRGB(255, 215, 0)
    stroke.Thickness   = 1.5
    stroke.Transparency = 0.1

    local lbl = Instance.new("TextLabel", bg)
    lbl.Size                   = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text                   = "GRAB GUN"
    lbl.TextColor3             = Color3.fromRGB(255, 215, 0)
    lbl.Font                   = Enum.Font.GothamBlack
    lbl.TextSize               = 14
    lbl.TextStrokeTransparency = 0.5
    lbl.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)

    activeBB = bb
end

-- ============================================================
--  SHERIFF WATCH
-- ============================================================
local function WatchSheriff(p)
    local function Hook(char)
        if not char then return end
        local hum = char:WaitForChild("Humanoid", 5)
        if not hum then return end
        hum.Died:Connect(function()
            if p.Backpack:FindFirstChild("Gun") or char:FindFirstChild("Gun") then
                task.delay(1, function()
                    local gd = FindGunDrop()
                    if gd then
                        ApplyGunHighlight(gd)
                        if Notify then Notify("Gun Dropped", "Sheriff died - go pick it up!", 3) end
                    end
                end)
            end
        end)
    end
    if p.Character then task.spawn(Hook, p.Character) end
    p.CharacterAdded:Connect(Hook)
end

for _, p in ipairs(Players:GetPlayers()) do
    if p ~= LP then task.spawn(WatchSheriff, p) end
end
Players.PlayerAdded:Connect(function(p)
    if p ~= LP then WatchSheriff(p) end
end)

local function WatchFolder(folder)
    folder.ChildAdded:Connect(function(obj)
        if obj.Name == "GunDrop" then
            task.wait(0.15)
            ApplyGunHighlight(obj)
            if Notify then Notify("Gun Dropped", "A gun appeared on the map.", 2) end
        end
    end)
    folder.ChildRemoved:Connect(function(obj)
        if obj.Name == "GunDrop" then ClearGunESP() end
    end)
end

for _, c in ipairs(Workspace:GetChildren()) do
    if c:IsA("Model") or c:IsA("Folder") then WatchFolder(c) end
end
Workspace.ChildAdded:Connect(function(obj)
    if obj:IsA("Model") or obj:IsA("Folder") then WatchFolder(obj) end
    if obj.Name == "GunDrop" then
        task.wait(0.15)
        ApplyGunHighlight(obj)
    end
end)

-- ============================================================
--  GRAB GUN  (FIXED)
--  Fix 1: Y offset  3 → 1.5   (pickup sphere'i içine girer)
--  Fix 2: wait    0.35 → 0.6  (sunucu pickup kontrolü biter)
--  Fix 3: velocity sıfırla    (fizik motoru pozisyonu kaçırmasın)
-- ============================================================
GrabDroppedGun = function()
    if grabCD then
        if Notify then Notify("Cooldown", "Wait 5 seconds before grabbing again.", 2) end
        return
    end

    local gd = FindGunDrop()
    if not gd then
        if Notify then Notify("No Gun", "No dropped gun found on the map.", 2) end
        return
    end

    local handle = gd:FindFirstChild("Handle")
                or gd.PrimaryPart
                or gd:FindFirstChildWhichIsA("BasePart")
    if not handle then
        if Notify then Notify("Error", "Could not find gun handle.", 2) end
        return
    end

    local char = LP.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    grabCD = true
    if Notify then Notify("Grab Gun", "Teleporting to gun...", 1) end

    local returnCF = hrp.CFrame

    -- Teleport to gun (1.5 studs above handle = inside pickup range)
    hrp.CFrame                 = CFrame.new(handle.Position + Vector3.new(0, 1.5, 0))
    hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)

    -- Wait for server to register the pickup
    task.wait(0.6)

    -- Return to original position
    hrp.CFrame                 = returnCF
    hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)

    ClearGunESP()
    if Notify then Notify("Grab Gun", "Done! 5s cooldown active.", 2) end

    task.delay(5, function()
        grabCD = false
        if Notify then Notify("Grab Gun", "Ready again!", 2) end
    end)
end

-- ============================================================
--  JUMP ENGINE
-- ============================================================
ExecuteJump = function(bombName, isGold)
    local char = LP.Character
    if not char then return end
    local bomb = LP.Backpack:FindFirstChild(bombName) or char:FindFirstChild(bombName)
    if not bomb then
        if Notify then Notify("No Item", "You don't have " .. bombName, 2) end
        return
    end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    if bomb.Parent ~= char then char.Humanoid:EquipTool(bomb); task.wait() end
    pcall(function()
        bomb.Remote:FireServer(
            CFrame.new(hrp.Position + hrp.CFrame.LookVector * 1.5 + Vector3.new(0, -3, 0)),
            50
        )
    end)
    char.Humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
    hrp.AssemblyLinearVelocity = Vector3.new(
        hrp.AssemblyLinearVelocity.X, 62, hrp.AssemblyLinearVelocity.Z
    )
    if isGold then
        task.spawn(function() goldCD = true;   task.wait(4);  goldCD   = false end)
    else
        task.spawn(function() normalCD = true; task.wait(21); normalCD = false end)
    end
end

-- ============================================================
--  TARGET FINDER  (v4 Duel Mode)
-- ============================================================
local function FindBestTarget()
    local myChar = LP.Character
    local myHRP  = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myHRP then return nil end

    local killerChar = nil
    local sheriffs   = {}

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character then
            local char = p.Character
            local hum  = char:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                if p.Backpack:FindFirstChild("Knife") or char:FindFirstChild("Knife") then
                    killerChar = char
                elseif p.Backpack:FindFirstChild("Gun") or char:FindFirstChild("Gun") then
                    table.insert(sheriffs, char)
                end
            end
        end
    end

    if killerChar then return killerChar end

    if #sheriffs >= 1 then
        local best, bestDist = nil, math.huge
        for _, c in ipairs(sheriffs) do
            local hrp = c:FindFirstChild("HumanoidRootPart")
            if hrp then
                local dist = (hrp.Position - myHRP.Position).Magnitude
                if dist < bestDist then bestDist = dist; best = c end
            end
        end
        return best
    end

    return nil
end

-- ============================================================
--  AUTO KILL
-- ============================================================
AutoKill = function()
    local char = LP.Character
    if not char then return end
    local myHRP = char:FindFirstChild("HumanoidRootPart")
    if not myHRP then return end

    local gun = LP.Backpack:FindFirstChild("Gun") or char:FindFirstChild("Gun")
    if not gun then
        if Notify then Notify("No Gun", "You don't have a gun.", 2) end
        return
    end

    local target = currentKillerChar
    if not target then
        if Notify then Notify("No Target", "No murderer or sheriff found.", 2) end
        return
    end

    if gun.Parent ~= char then char.Humanoid:EquipTool(gun); task.wait(0.05) end

    local targetPos = predPart.CFrame.Position
    pcall(function()
        gun:WaitForChild("Shoot"):FireServer(
            CFrame.new(myHRP.Position, targetPos),
            CFrame.new(targetPos)
        )
    end)
end

-- ============================================================
--  BOMB RETRIEVER  (background task)
-- ============================================================
task.spawn(function()
    while true do
        task.wait(2)
        if not bombRetriever then continue end
        pcall(function()
            ReplicatedStorage.Remotes.Extras.ReplicateToy:InvokeServer("FakeBomb")
            ReplicatedStorage.Remotes.Extras.ReplicateToy:InvokeServer("GoldBomb")
        end)
    end
end)

-- ============================================================
--  PREDICTION LOOP  (v4 Bullet Travel Time)
-- ============================================================
RunService.RenderStepped:Connect(function()
    local targetChar = FindBestTarget()
    currentKillerChar = targetChar
    if not targetChar then return end

    local myChar = LP.Character
    local myHRP  = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myHRP then return end

    local head  = targetChar:FindFirstChild("Head")
    local torso = targetChar:FindFirstChild("UpperTorso") or targetChar:FindFirstChild("HumanoidRootPart")
    local hum   = targetChar:FindFirstChildOfClass("Humanoid")
    if not torso then return end

    local basePos   = head and head.Position or (torso.Position + Vector3.new(0, 0.5, 0))
    local dist      = (basePos - myHRP.Position).Magnitude
    local travelTime = dist / BULLET_SPEED
    local vel        = torso.AssemblyLinearVelocity

    if hum and (
        hum:GetState() == Enum.HumanoidStateType.Freefall or
        hum:GetState() == Enum.HumanoidStateType.Jumping
    ) then
        vel = Vector3.new(vel.X, 0, vel.Z)
    end

    predPart.CFrame = CFrame.new(basePos + vel * travelTime)
end)

-- ============================================================
--  ANTI-FLING
-- ============================================================
RunService.Heartbeat:Connect(function()
    if not antiFlingEnabled then return end
    local char = LP.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local vel = hrp.AssemblyLinearVelocity
    if math.abs(vel.X) > antiFlingThreshold or math.abs(vel.Z) > antiFlingThreshold then
        hrp.AssemblyLinearVelocity = Vector3.new(0, math.min(vel.Y, 50), 0)
    end
end)

-- ============================================================
--  ESP SYSTEM
-- ============================================================
local ESPHighlights = {}
local ESPLines      = {}

local lineGui = Instance.new("ScreenGui")
lineGui.Name           = "RuzLineESP"
lineGui.IgnoreGuiInset = true
lineGui.ResetOnSpawn   = false
lineGui.DisplayOrder   = 5
lineGui.Parent         = LP.PlayerGui

local function RemovePlayerESP(p)
    if ESPHighlights[p] then
        pcall(function() ESPHighlights[p]:Destroy() end)
        ESPHighlights[p] = nil
    end
    if ESPLines[p] then
        pcall(function() ESPLines[p]:Destroy() end)
        ESPLines[p] = nil
    end
end

local function ClearAllESP()
    for p in pairs(ESPHighlights) do RemovePlayerESP(p) end
    lineGui:ClearAllChildren()
    ESPLines = {}
end

local lastESPTick = 0
RunService.Heartbeat:Connect(function()
    -- Update at 10 fps for performance
    if tick() - lastESPTick < 0.1 then return end
    lastESPTick = tick()

    UpdateRoles()

    if not espEnabled then
        ClearAllESP()
        return
    end

    local viewSize     = Camera.ViewportSize
    local bottomCenter = Vector2.new(viewSize.X / 2, viewSize.Y)

    for _, p in ipairs(Players:GetPlayers()) do
        local isSelf = (p == LP)

        if isSelf and not espSelf then RemovePlayerESP(p); continue end

        local char = p.Character
        if not char then RemovePlayerESP(p); continue end

        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health <= 0 then RemovePlayerESP(p); continue end

        local role = GetPlayerRole(p)

        local shouldShow = false
        if     isSelf                             and espSelf      then shouldShow = true
        elseif role == "Murderer"                 and espMurderer  then shouldShow = true
        elseif role == "Sheriff"                  and espSheriff   then shouldShow = true
        elseif role == "Hero"                     and espHero      then shouldShow = true
        elseif role == "Innocent" and not isSelf  and espInnocent  then shouldShow = true
        end

        if not shouldShow then RemovePlayerESP(p); continue end

        local color = espColors[role] or espColors.Innocent

        -- Highlight
        local hl = ESPHighlights[p]
        if not hl or not hl.Parent then
            hl = Instance.new("Highlight")
            hl.Parent = char
            ESPHighlights[p] = hl
        else
            hl.Parent = char
        end
        hl.FillColor           = color
        hl.OutlineColor        = Color3.fromRGB(255, 255, 255)
        hl.FillTransparency    = espFillTrans
        hl.OutlineTransparency = 0
        hl.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop

        -- Line ESP
        if espLine then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local sp, onScreen = Camera:WorldToViewportPoint(hrp.Position)
                if onScreen then
                    local playerPos = Vector2.new(sp.X, sp.Y)
                    local diff      = playerPos - bottomCenter
                    local mag       = diff.Magnitude

                    local lf = ESPLines[p]
                    if not lf or not lf.Parent then
                        lf = Instance.new("Frame")
                        lf.BackgroundColor3 = color
                        lf.BorderSizePixel  = 0
                        lf.AnchorPoint      = Vector2.new(0.5, 0.5)
                        lf.ZIndex           = 2
                        Instance.new("UICorner", lf).CornerRadius = UDim.new(1, 0)
                        lf.Parent  = lineGui
                        ESPLines[p] = lf
                    end

                    lf.Size             = UDim2.fromOffset(math.max(mag, 1), 2)
                    lf.Position         = UDim2.fromOffset(
                        (bottomCenter.X + playerPos.X) / 2,
                        (bottomCenter.Y + playerPos.Y) / 2
                    )
                    lf.Rotation         = math.deg(math.atan2(diff.Y, diff.X))
                    lf.BackgroundColor3 = color
                    lf.Visible          = true
                else
                    if ESPLines[p] then ESPLines[p].Visible = false end
                end
            end
        else
            if ESPLines[p] then ESPLines[p]:Destroy(); ESPLines[p] = nil end
        end
    end

    -- Cleanup disconnected players
    for p in pairs(ESPHighlights) do
        if not p or not p.Parent then RemovePlayerESP(p) end
    end
end)

Players.PlayerRemoving:Connect(RemovePlayerESP)

-- ============================================================
--  FOV & STRETCHED SCREEN
-- ============================================================
local function ApplyCurrentFOV()
    if stretchEnabled then
        Camera.FieldOfView = STRETCH_FOV_VALUE
    elseif fovEnabled then
        Camera.FieldOfView = currentFOV
    else
        Camera.FieldOfView = DEFAULT_FOV
    end
end

local function SetFOV(val)
    currentFOV = val
    ApplyCurrentFOV()
end

local function SetFOVEnabled(enabled)
    fovEnabled = enabled
    ApplyCurrentFOV()
    if Notify then
        Notify("FOV Changer", enabled and ("Custom FOV: " .. tostring(currentFOV)) or ("Reset to default (" .. DEFAULT_FOV .. ")"), 2)
    end
end

local function SetStretch(enabled)
    stretchEnabled = enabled
    ApplyCurrentFOV()
    if Notify then
        Notify("Stretch", enabled and ("Stretched FOV: " .. tostring(STRETCH_FOV_VALUE)) or "Stretch disabled.", 2)
    end
end

-- Prevent game from resetting FOV
RunService.RenderStepped:Connect(function()
    local target = stretchEnabled and STRETCH_FOV_VALUE
                or (fovEnabled    and currentFOV)
                or DEFAULT_FOV
    if math.abs(Camera.FieldOfView - target) > 0.5 then
        Camera.FieldOfView = target
    end
end)

-- ============================================================
--  DRAGGABLE ON-SCREEN BUTTON FACTORY
-- ============================================================
local function CreateOnScreenButton(id, text, color, posX, posY, size, onClick)
    local existing = game.CoreGui:FindFirstChild("RuzBtn_" .. id)
    if existing then existing:Destroy() end

    local sg = Instance.new("ScreenGui")
    sg.Name          = "RuzBtn_" .. id
    sg.ResetOnSpawn  = false
    sg.IgnoreGuiInset = true
    sg.DisplayOrder  = 20
    sg.Parent        = game.CoreGui

    local btn = Instance.new("TextButton", sg)
    btn.Size                   = UDim2.fromOffset(size, size)
    btn.Position               = UDim2.fromOffset(posX, posY)
    btn.BackgroundColor3       = Color3.fromRGB(10, 10, 14)
    btn.BackgroundTransparency = 0.4
    btn.Text                   = text
    btn.TextColor3             = color
    btn.Font                   = Enum.Font.GothamBold
    btn.TextSize               = math.clamp(size * 0.14, 10, 16)
    btn.AutoButtonColor        = false
    btn.BorderSizePixel        = 0
    btn.TextStrokeTransparency = 1

    local corner = Instance.new("UICorner", btn)
    corner.CornerRadius = UDim.new(0, math.floor(size * 0.15))

    local stroke = Instance.new("UIStroke", btn)
    stroke.Color       = color
    stroke.Thickness   = 1.5
    stroke.Transparency = 0.45

    -- Drag + tap detection
    local dragging  = false
    local hasDragged = false
    local dragStart, startPos

    btn.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.Touch
        or inp.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging   = true
            hasDragged = false
            dragStart  = Vector2.new(inp.Position.X, inp.Position.Y)
            startPos   = btn.Position
        end
    end)

    btn.InputChanged:Connect(function(inp)
        if not dragging then return end
        if inp.UserInputType == Enum.UserInputType.Touch
        or inp.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = Vector2.new(inp.Position.X - dragStart.X, inp.Position.Y - dragStart.Y)
            if delta.Magnitude > 12 then hasDragged = true end
            btn.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)

    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.Touch
        or inp.UserInputType == Enum.UserInputType.MouseButton1 then
            if dragging and not hasDragged then
                task.spawn(onClick)
            end
            dragging = false
        end
    end)

    -- Cooldown label for jump buttons
    local cdLabel = Instance.new("TextLabel", btn)
    cdLabel.Name                   = "CooldownLabel"
    cdLabel.Size                   = UDim2.new(1, 0, 0.28, 0)
    cdLabel.Position               = UDim2.new(0, 0, 0.72, 0)
    cdLabel.BackgroundTransparency = 1
    cdLabel.TextColor3             = Color3.fromRGB(200, 200, 200)
    cdLabel.Font                   = Enum.Font.Gotham
    cdLabel.TextSize               = 9
    cdLabel.Text                   = ""
    cdLabel.ZIndex                 = 3

    return sg, btn
end

-- ============================================================
--  REFRESH ON-SCREEN BUTTONS
-- ============================================================
RefreshOnScreenButtons = function()
    -- Remove all existing
    for _, id in ipairs({"GoldJump","NormJump","AutoKill","GrabGun"}) do
        local g = game.CoreGui:FindFirstChild("RuzBtn_" .. id)
        if g then g:Destroy() end
    end
    onScreenGuis = {}

    local baseY = 620
    local xStart = 20

    if showGoldBtn then
        local sg, btn = CreateOnScreenButton(
            "GoldJump", "GOLD\nJUMP", Color3.fromRGB(255, 215, 0),
            xStart, baseY, 86,
            function()
                if goldCD then
                    if Notify then Notify("Cooldown", "Gold Jump on cooldown.", 1) end
                else ExecuteJump("GoldBomb", true) end
            end
        )
        onScreenGuis["GoldJump"] = sg
        xStart = xStart + 96

        -- Cooldown updater
        task.spawn(function()
            local cdLbl = btn:FindFirstChild("CooldownLabel")
            while btn and btn.Parent do
                if cdLbl then cdLbl.Text = goldCD and "WAIT" or "4s CD" end
                task.wait(0.5)
            end
        end)
    end

    if showNormBtn then
        local sg, btn = CreateOnScreenButton(
            "NormJump", "NORMAL\nJUMP", Color3.fromRGB(0, 170, 255),
            xStart, baseY, 86,
            function()
                if normalCD then
                    if Notify then Notify("Cooldown", "Normal Jump on cooldown.", 1) end
                else ExecuteJump("FakeBomb", false) end
            end
        )
        onScreenGuis["NormJump"] = sg
        xStart = xStart + 96

        task.spawn(function()
            local cdLbl = btn:FindFirstChild("CooldownLabel")
            while btn and btn.Parent do
                if cdLbl then cdLbl.Text = normalCD and "WAIT" or "21s CD" end
                task.wait(0.5)
            end
        end)
    end

    if showKillBtn then
        local sg, _ = CreateOnScreenButton(
            "AutoKill", "SHOOT\nMURDER", Color3.fromRGB(255, 60, 60),
            xStart, baseY, 86,
            AutoKill
        )
        onScreenGuis["AutoKill"] = sg
        xStart = xStart + 96
    end

    if showGrabBtn then
        local sg, btn = CreateOnScreenButton(
            "GrabGun", "GRAB\nGUN", Color3.fromRGB(50, 255, 120),
            xStart, baseY, 86,
            GrabDroppedGun
        )
        onScreenGuis["GrabGun"] = sg

        task.spawn(function()
            local cdLbl = btn:FindFirstChild("CooldownLabel")
            while btn and btn.Parent do
                if cdLbl then
                    local gunExists = FindGunDrop() ~= nil
                    cdLbl.Text      = grabCD and "5s..." or (gunExists and "READY" or "NO GUN")
                    cdLbl.TextColor3 = gunExists
                        and Color3.fromRGB(50, 255, 120)
                        or  Color3.fromRGB(150, 150, 150)
                end
                task.wait(0.5)
            end
        end)
    end
end

-- ============================================================
--  WIND UI  LOAD
-- ============================================================
local Library
local ok, err = pcall(function()
    Library = loadstring(
        game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua")
    )()
end)

if not ok or not Library then
    warn("RuzHub: WindUI could not be loaded. Error: " .. tostring(err))
    -- Fallback: still run on-screen buttons without panel
    Notify = function() end
    RefreshOnScreenButtons()
    return
end

-- ============================================================
--  NOTIFY  (defined after Library is available)
-- ============================================================
Notify = function(title, msg, duration)
    pcall(function()
        Library:Notify({
            Title    = title,
            Content  = msg,
            Duration = duration or 3,
        })
    end)
end

-- ============================================================
--  WINDOW
-- ============================================================
local Window = Library:CreateWindow({
    Title        = "RuzHub",
    SubTitle     = "v5 Pro | MM2 Edition",
    TabWidth     = 152,
    Size         = UDim2.fromOffset(580, 460),
    Acrylic      = false,      -- false = mobile performans iyileşir
    Theme        = "Dark",
    MinimizeKey  = Enum.KeyCode.RightControl,
})

-- ============================================================
--  MOBILE TOGGLE BUTTON  (RuzHub yazılı, paneli açar/kapatır)
-- ============================================================
do
    local mGui = Instance.new("ScreenGui")
    mGui.Name           = "RuzHubMobileToggle"
    mGui.ResetOnSpawn   = false
    mGui.IgnoreGuiInset = true
    mGui.DisplayOrder   = 100
    mGui.Parent         = game.CoreGui

    local mBtn = Instance.new("TextButton", mGui)
    mBtn.Size                   = UDim2.fromOffset(92, 30)
    mBtn.Position               = UDim2.new(0.5, -46, 0, 6)
    mBtn.BackgroundColor3       = Color3.fromRGB(12, 12, 18)
    mBtn.BackgroundTransparency = 0.25
    mBtn.Text                   = "RuzHub"
    mBtn.TextColor3             = Color3.fromRGB(110, 185, 255)
    mBtn.Font                   = Enum.Font.GothamBold
    mBtn.TextSize               = 14
    mBtn.AutoButtonColor        = false
    mBtn.BorderSizePixel        = 0
    Instance.new("UICorner", mBtn).CornerRadius = UDim.new(0, 8)
    local ms = Instance.new("UIStroke", mBtn)
    ms.Color       = Color3.fromRGB(110, 185, 255)
    ms.Thickness   = 1.2
    ms.Transparency = 0.45

    -- Drag the mobile button
    local mdrag, mdragStart, mstartPos = false, nil, nil
    local mHasDragged = false

    mBtn.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.Touch
        or inp.UserInputType == Enum.UserInputType.MouseButton1 then
            mdrag      = true
            mHasDragged = false
            mdragStart = Vector2.new(inp.Position.X, inp.Position.Y)
            mstartPos  = mBtn.Position
        end
    end)

    mBtn.InputChanged:Connect(function(inp)
        if not mdrag then return end
        if inp.UserInputType == Enum.UserInputType.Touch
        or inp.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = Vector2.new(inp.Position.X - mdragStart.X, inp.Position.Y - mdragStart.Y)
            if delta.Magnitude > 10 then mHasDragged = true end
            mBtn.Position = UDim2.new(
                mstartPos.X.Scale, mstartPos.X.Offset + delta.X,
                mstartPos.Y.Scale, mstartPos.Y.Offset + delta.Y
            )
        end
    end)

    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.Touch
        or inp.UserInputType == Enum.UserInputType.MouseButton1 then
            if mdrag and not mHasDragged then
                -- Toggle the panel
                pcall(function() Window:Toggle() end)
            end
            mdrag = false
        end
    end)
end

-- ============================================================
--  TABS
-- ============================================================
local Tabs = {
    Home   = Window:AddTab({ Title = "Home",   Icon = "house"        }),
    Combat = Window:AddTab({ Title = "Combat", Icon = "crosshair"    }),
    ESP    = Window:AddTab({ Title = "ESP",    Icon = "eye"          }),
    Jump   = Window:AddTab({ Title = "Jump",   Icon = "chevrons-up"  }),
    Visual = Window:AddTab({ Title = "Visual", Icon = "monitor"      }),
    Misc   = Window:AddTab({ Title = "Misc",   Icon = "settings"     }),
}

-- ============================================================
--  HOME TAB
-- ============================================================
do
    local left  = Tabs.Home:AddLeftGroupbox("RuzHub v5 Pro")
    left:AddLabel("MM2 Fan-Made Script")
    left:AddLabel("Open / Close Panel  :  RuzHub Button or RightCtrl")
    left:AddDivider()
    left:AddLabel("All features are mobile compatible.")
    left:AddLabel("On-screen buttons are draggable.")
    left:AddDivider()
    left:AddButton({
        Text = "Show On-Screen Buttons",
        Func = function()
            RefreshOnScreenButtons()
            Notify("Buttons", "On-screen buttons loaded.", 2)
        end,
    })

    local right = Tabs.Home:AddRightGroupbox("Status")
    right:AddLabel("Bullet Speed    : " .. tostring(BULLET_SPEED))
    right:AddLabel("Script by       : Ruz")
    right:AddLabel("UI Library      : WindUI")
    right:AddDivider()
    right:AddButton({
        Text = "Destroy Script",
        Func = function()
            Notify("RuzHub", "Cleaning up...", 2)
            task.wait(1)
            ClearAllESP()
            ClearGunESP()
            predPart:Destroy()
            for _, sg in pairs(onScreenGuis) do pcall(function() sg:Destroy() end) end
            pcall(function() game.CoreGui.RuzHubMobileToggle:Destroy() end)
            pcall(function() game.CoreGui.RuzLineESP:Destroy() end)
        end,
    })
end

-- ============================================================
--  COMBAT TAB
-- ============================================================
do
    local left = Tabs.Combat:AddLeftGroupbox("Attack")
    left:AddButton({
        Text = "Shoot Murderer",
        Func = AutoKill,
    })
    left:AddToggle("SilentAim", {
        Text     = "Silent Aim  (auto-aim on shoot)",
        Default  = false,
        Callback = function(v) silentAimEnabled = v end,
    })
    left:AddDivider()
    left:AddSlider("BulletSpeed", {
        Text     = "Bullet Speed",
        Default  = 250,
        Min      = 100,
        Max      = 600,
        Rounding = 0,
        Callback = function(v) BULLET_SPEED = v end,
    })

    local right = Tabs.Combat:AddRightGroupbox("Info")
    right:AddLabel("Shoot Murderer fires the gun")
    right:AddLabel("remote directly at the killer.")
    right:AddDivider()
    right:AddLabel("Bullet Speed adjusts the")
    right:AddLabel("travel-time prediction.")
    right:AddLabel("Default: 250 (MM2 standard)")
end

-- ============================================================
--  ESP TAB
-- ============================================================
do
    local left = Tabs.ESP:AddLeftGroupbox("Enable")
    left:AddToggle("ESPMaster", {
        Text     = "Enable ESP",
        Default  = false,
        Callback = function(v)
            espEnabled = v
            if not v then ClearAllESP() end
        end,
    })
    left:AddToggle("ESPLine", {
        Text     = "Line ESP  (trace lines)",
        Default  = false,
        Callback = function(v) espLine = v end,
    })
    left:AddToggle("ESPSelf", {
        Text     = "Show Self",
        Default  = false,
        Callback = function(v) espSelf = v end,
    })
    left:AddDivider()
    left:AddSlider("ESPFill", {
        Text     = "Fill Transparency  (0=solid)",
        Default  = 45,
        Min      = 0,
        Max      = 100,
        Rounding = 0,
        Callback = function(v) espFillTrans = v / 100 end,
    })

    local right = Tabs.ESP:AddRightGroupbox("Roles")
    right:AddToggle("ESPMurderer", {
        Text     = "Murderer ESP",
        Default  = true,
        Callback = function(v) espMurderer = v end,
    })
    right:AddColorPicker("ColorMurd", {
        Title    = "Murderer Color",
        Default  = espColors.Murderer,
        Callback = function(v) espColors.Murderer = v end,
    })
    right:AddDivider()
    right:AddToggle("ESPSheriff", {
        Text     = "Sheriff ESP",
        Default  = true,
        Callback = function(v) espSheriff = v end,
    })
    right:AddColorPicker("ColorSheriff", {
        Title    = "Sheriff Color",
        Default  = espColors.Sheriff,
        Callback = function(v) espColors.Sheriff = v end,
    })
    right:AddDivider()
    right:AddToggle("ESPHero", {
        Text     = "Hero ESP",
        Default  = true,
        Callback = function(v) espHero = v end,
    })
    right:AddColorPicker("ColorHero", {
        Title    = "Hero Color",
        Default  = espColors.Hero,
        Callback = function(v) espColors.Hero = v end,
    })
    right:AddDivider()
    right:AddToggle("ESPInnocent", {
        Text     = "Innocent ESP",
        Default  = false,
        Callback = function(v) espInnocent = v end,
    })
    right:AddColorPicker("ColorInnocent", {
        Title    = "Innocent Color",
        Default  = espColors.Innocent,
        Callback = function(v) espColors.Innocent = v end,
    })
end

-- ============================================================
--  JUMP TAB
-- ============================================================
do
    local left = Tabs.Jump:AddLeftGroupbox("Jumps")
    left:AddButton({
        Text = "Gold Jump  (4s cooldown)",
        Func = function()
            if goldCD then
                Notify("Cooldown", "Gold Jump is on cooldown.", 1)
            else
                ExecuteJump("GoldBomb", true)
            end
        end,
    })
    left:AddButton({
        Text = "Normal Jump  (21s cooldown)",
        Func = function()
            if normalCD then
                Notify("Cooldown", "Normal Jump is on cooldown.", 1)
            else
                ExecuteJump("FakeBomb", false)
            end
        end,
    })

    local right = Tabs.Jump:AddRightGroupbox("Grab Gun")
    right:AddToggle("DroppedGunESP", {
        Text     = "Dropped Gun ESP",
        Default  = true,
        Callback = function(v)
            droppedGunESP = v
            if not v then ClearGunESP() end
        end,
    })
    right:AddDivider()
    right:AddButton({
        Text = "Grab Dropped Gun",
        Func = GrabDroppedGun,
    })
    right:AddLabel("Teleports to the gun,")
    right:AddLabel("picks it up, returns to")
    right:AddLabel("your original position.")
    right:AddLabel("5 second cooldown.")
end

-- ============================================================
--  VISUAL TAB
-- ============================================================
do
    -- LEFT: FOV Changer
    local left = Tabs.Visual:AddLeftGroupbox("FOV Changer")
    left:AddLabel("Enable to apply a custom FOV.")
    left:AddLabel("Disable to return to default (70).")
    left:AddDivider()
    left:AddToggle("FOVEnabled", {
        Text     = "Enable Custom FOV",
        Default  = false,
        Callback = function(v) SetFOVEnabled(v) end,
    })
    left:AddSlider("FOVValue", {
        Text     = "FOV  (default: 70)",
        Default  = 70,
        Min      = 50,
        Max      = 120,
        Rounding = 0,
        Callback = function(v)
            currentFOV = v
            if fovEnabled then ApplyCurrentFOV() end
        end,
    })
    left:AddDivider()
    left:AddButton({
        Text = "Reset FOV  (→ 70)",
        Func = function()
            currentFOV = DEFAULT_FOV
            SetFOVEnabled(false)
            Notify("FOV", "Reset to default 70.", 2)
        end,
    })
    left:AddDivider()
    left:AddLabel("Tip: FOV 90+ gives wider view.")
    left:AddLabel("FOV 50-60 narrows the view.")

    -- RIGHT: Stretched Screen
    local right = Tabs.Visual:AddRightGroupbox("Stretched Screen")
    right:AddLabel("Simulates a stretched resolution")
    right:AddLabel("by widening the FOV horizontally.")
    right:AddLabel("Works like 4:3 stretch in FPS games.")
    right:AddDivider()
    right:AddToggle("StretchToggle", {
        Text     = "Enable Stretch",
        Default  = false,
        Callback = function(v) SetStretch(v) end,
    })
    right:AddSlider("StretchFOV", {
        Text     = "Stretch Amount  (FOV)",
        Default  = 110,
        Min      = 80,
        Max      = 140,
        Rounding = 0,
        Callback = function(v)
            STRETCH_FOV_VALUE = v
            if stretchEnabled then
                Camera.FieldOfView = v
                Notify("Stretch", "FOV set to " .. tostring(v), 1)
            end
        end,
    })
    right:AddDivider()
    right:AddLabel("80  = slight stretch")
    right:AddLabel("110 = medium (recommended)")
    right:AddLabel("140 = heavy stretch")
    right:AddDivider()
    right:AddButton({
        Text = "Reset Stretch Off",
        Func = function()
            SetStretch(false)
        end,
    })
end

-- ============================================================
--  MISC TAB
-- ============================================================
do
    -- LEFT: Anti-Fling + Extras
    local left = Tabs.Misc:AddLeftGroupbox("Anti-Fling")
    left:AddLabel("Prevents other players from")
    left:AddLabel("launching your character into the air.")
    left:AddDivider()
    left:AddToggle("AntiFling", {
        Text     = "Enable Anti-Fling",
        Default  = false,
        Callback = function(v)
            antiFlingEnabled = v
            Notify("Anti-Fling", v and "Active - velocity capped." or "Disabled.", 2)
        end,
    })
    left:AddSlider("FlingThreshold", {
        Text     = "Velocity Threshold",
        Default  = 80,
        Min      = 20,
        Max      = 200,
        Rounding = 0,
        Callback = function(v)
            antiFlingThreshold = v
        end,
    })
    left:AddDivider()
    left:AddLabel("Lower = stricter (stops more)")
    left:AddLabel("Higher = permissive (only hard flings)")
    left:AddLabel("Default 80 works for most cases.")
    left:AddDivider()
    left:AddToggle("BombRetriever", {
        Text     = "Bomb Retriever  (auto)",
        Default  = true,
        Callback = function(v) bombRetriever = v end,
    })
    left:AddDivider()
    left:AddButton({
        Text = "Reset Character",
        Func = function()
            local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum.Health = 0 end
        end,
    })

    -- RIGHT: On-Screen Buttons
    local right = Tabs.Misc:AddRightGroupbox("On-Screen Buttons")
    right:AddLabel("Toggle which buttons appear on screen.")
    right:AddLabel("All buttons are draggable.")
    right:AddDivider()
    right:AddToggle("ShowGold", {
        Text     = "Gold Jump Button",
        Default  = true,
        Callback = function(v) showGoldBtn = v; RefreshOnScreenButtons() end,
    })
    right:AddToggle("ShowNorm", {
        Text     = "Normal Jump Button",
        Default  = true,
        Callback = function(v) showNormBtn = v; RefreshOnScreenButtons() end,
    })
    right:AddToggle("ShowKill", {
        Text     = "Shoot Murderer Button",
        Default  = true,
        Callback = function(v) showKillBtn = v; RefreshOnScreenButtons() end,
    })
    right:AddToggle("ShowGrab", {
        Text     = "Grab Gun Button",
        Default  = true,
        Callback = function(v) showGrabBtn = v; RefreshOnScreenButtons() end,
    })
    right:AddDivider()
    right:AddButton({
        Text = "Reload All Buttons",
        Func = function()
            RefreshOnScreenButtons()
            Notify("Buttons", "On-screen buttons refreshed.", 2)
        end,
    })
end

-- ============================================================
--  INITIAL SETUP
-- ============================================================
RefreshOnScreenButtons()

Notify("RuzHub v5", "Script loaded. Tap the RuzHub button to open the panel.", 4)
