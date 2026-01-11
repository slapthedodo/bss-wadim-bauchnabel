-- Dienste
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local TeleportService = game:GetService("TeleportService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer

-- Variable zum Steuern des Loops (für Unload wichtig)
local ScriptRunning = true

-- Variable for AutoClaimHive state (Setzt sich bei Join auf false)
local HiveClaimedInretro = false

-- Dateiname für Config
local FileName = "BeeSwarmSchlipSchlop_" .. LocalPlayer.UserId .. ".json"

-- Standard Werte
local Settings = {
    BronzeStar = false,
    DiamondStar = false,
    FieldDice = false,
    Snowflake = false,
    SnowflakeDelay = 1.05,
    RedCannon = false,
    BlueCannon = false,
    YellowCannon = false,
    ShowCooldowns = true,
    Autoretro = false,
    retroWalkspeed = false,
    AutoClaimHive = false,
    AutoHit = false,
    AutoSlimeKill = false,
    AutoUpgrade = false,
    AutoBuyBricks = false,
    InterruptAutoSlime = false,
    FarmPollen = false,
    AutoToolSwitch = false,
    KillAuraVisual = false,
    KillAuraRange = 50,
    KillAuraTrigger = 5,
    KillAuraCooldown = 3,
    BloomLevel = 5,
    CameraMaxZoomDistance = 128,
    MaxAxisFieldOfView = 70,
    CollectTokens = true
}

-- Global states for equipped/owned items
local hasClassicSword = false
local hasFirebrand = false
local hasIllumina = false
local currentEquippedSword = nil -- Can be "ClassicSword", "Firebrand", "Illumina", or nil (for farming tool)

-- Active tween handles for AutoSlimeKill (accessible globally so UI can interrupt)
local AutoSlime_activeTween = nil
local AutoSlime_activePlatTween = nil
local AutoSlime_activeConn = nil
local AutoSlime_blockUntil = 0

local KillAura_isExecuting = false
local KillAura_lastExecution = 0

-- Ensure AutoUpgrade runs only once per user activation while leaving the UI toggle on
local AutoUpgrade_hasRun = false

-- Helper to cancel any active AutoSlime tweens/connections
local function cancelActiveAutoSlime()
    pcall(function()
        -- cancel inner-loop handles if present
        if AutoSlime_activeConn then AutoSlime_activeConn:Disconnect() AutoSlime_activeConn = nil end
        if AutoSlime_activeTween then pcall(function() AutoSlime_activeTween:Cancel() end) AutoSlime_activeTween = nil end
        if AutoSlime_activePlatTween then pcall(function() AutoSlime_activePlatTween:Cancel() end) AutoSlime_activePlatTween = nil end
        -- set a short block to prevent immediate restart
        AutoSlime_blockUntil = tick() + 0.05
    end)
end

local lastEquipTime = 0
local function EquipTool(toolName)
    if not ScriptRunning then return end
    if tick() - lastEquipTime < 0.5 then return end

    local character = LocalPlayer.Character
    if not character then return end

    local currentTool = character:FindFirstChildOfClass("Tool")
    
    if toolName == "FarmingTool" then
        if currentTool and (currentTool.Name == "ClassicSword" or currentTool.Name == "ClassicFirebrand" or currentTool.Name == "ClassicIllumina") then
            local oldName = currentTool.Name
            local remoteName = (oldName == "ClassicSword" and "Sword") or (oldName == "ClassicFirebrand" and "Firebrand") or (oldName == "ClassicIllumina" and "Illumina")
            print("unequipping " .. oldName .. " (Remote: " .. tostring(remoteName) .. ")")
            pcall(function()
                local args = {
                    [1] = {
                        ["Name"] = remoteName
                    }
                }
                ReplicatedStorage.Events.PlayerActivesCommand:FireServer(unpack(args))
            end)
            currentEquippedSword = nil
            lastEquipTime = tick()
            task.wait(0.2)
        end
    else -- Equip a sword
        local remoteName = (toolName == "ClassicSword" and "Sword") or (toolName == "ClassicFirebrand" and "Firebrand") or (toolName == "ClassicIllumina" and "Illumina")
        
        if currentTool and currentTool.Name == toolName then
            return -- Already equipped
        end

        print("equip " .. toolName .. " (Remote: " .. tostring(remoteName) .. ")")
        pcall(function()
            local args = {
                [1] = {
                    ["Name"] = remoteName
                }
            }
            ReplicatedStorage.Events.PlayerActivesCommand:FireServer(unpack(args))
        end)
        currentEquippedSword = toolName
        lastEquipTime = tick()
        task.wait(0.2)
    end
end

-- Watcher: if Settings.InterruptAutoSlime is set, cancel active tweens and clear the flag
task.spawn(function()
    while ScriptRunning do
        if Settings.InterruptAutoSlime then
            cancelActiveAutoSlime()
            Settings.InterruptAutoSlime = false
            SaveConfig()
        end
        task.wait(0.5)
    end
end)

-- UI für Cooldowns
local CooldownGui = Instance.new("ScreenGui")
CooldownGui.Name = "BSSCooldowns"
CooldownGui.ResetOnSpawn = false
CooldownGui.Enabled = true

-- Prüfen ob CoreGui verfügbar ist (für Exploits üblich), sonst PlayerGui
local successGui, errGui = pcall(function()
    CooldownGui.Parent = CoreGui
end)
if not successGui then
    CooldownGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

local CooldownContainer = Instance.new("Frame")
CooldownContainer.Name = "Container"
CooldownContainer.Size = UDim2.new(0, 200, 0, 100)
CooldownContainer.Position = UDim2.new(0.05, 0, 0.7, 0)
CooldownContainer.BackgroundTransparency = 1
CooldownContainer.Parent = CooldownGui

local UIListLayout = Instance.new("UIListLayout")
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.Padding = UDim.new(0, 5)
UIListLayout.Parent = CooldownContainer

local function CreateCooldownBar(name, color)
    local Frame = Instance.new("Frame")
    Frame.Name = name
    Frame.Size = UDim2.new(1, 0, 0, 20)
    Frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    Frame.BackgroundTransparency = 0.5
    Frame.BorderSizePixel = 0
    Frame.Visible = false
    Frame.Parent = CooldownContainer

    local Bar = Instance.new("Frame")
    Bar.Name = "Bar"
    Bar.Size = UDim2.new(0, 0, 1, 0)
    Bar.BackgroundColor3 = color
    Bar.BackgroundTransparency = 0.3
    Bar.BorderSizePixel = 0
    Bar.Parent = Frame

    local TextLabel = Instance.new("TextLabel")
    TextLabel.Size = UDim2.new(1, 0, 1, 0)
    TextLabel.BackgroundTransparency = 1
    TextLabel.Text = name
    TextLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    TextLabel.TextSize = 14
    TextLabel.Font = Enum.Font.SourceSansBold
    TextLabel.Parent = Frame

    return Frame
end

local Bars = {
    Stars = CreateCooldownBar("Stars & Dice", Color3.fromRGB(255, 200, 0)),
    Snowflake = CreateCooldownBar("Snowflake", Color3.fromRGB(0, 255, 255)),
    KillAura = CreateCooldownBar("KillAura", Color3.fromRGB(255, 0, 0))
}

local function UpdateBar(barName, duration)
    local barFrame = Bars[barName]
    if not Settings.ShowCooldowns or not barFrame then 
        if barFrame then barFrame.Visible = false end
        return 
    end
    
    -- Sichtbarkeit prüfen basierend auf Toggles
    if barName == "Stars" then
        barFrame.Visible = (Settings.BronzeStar or Settings.DiamondStar or Settings.FieldDice)
    elseif barName == "Snowflake" then
        barFrame.Visible = Settings.Snowflake
    elseif barName == "KillAura" then
        barFrame.Visible = Settings.KillAuraVisual
    end

    if not barFrame.Visible then return end

    local bar = barFrame:FindFirstChild("Bar")
    if bar then
        bar:TweenSize(UDim2.new(1, 0, 1, 0), "Out", "Linear", 0, true) -- Reset
        bar.Size = UDim2.new(1, 0, 1, 0)
        bar:TweenSize(UDim2.new(0, 0, 1, 0), "Out", "Linear", duration, true)
    end
end

-- [FUNKTIONEN] Speichern und Laden
local function SaveConfig()
    -- Nur speichern, wenn das Skript noch läuft
    if not ScriptRunning then return end
    
    local success, err = pcall(function()
        local json = HttpService:JSONEncode(Settings)
        writefile(FileName, json)
    end)
end

local function LoadConfig()
    if isfile(FileName) then
        local content = readfile(FileName)
        local success, result = pcall(function()
            return HttpService:JSONDecode(content)
        end)
        
        if success then
            if result.BronzeStar ~= nil then Settings.BronzeStar = result.BronzeStar end
            if result.DiamondStar ~= nil then Settings.DiamondStar = result.DiamondStar end
            if result.FieldDice ~= nil then Settings.FieldDice = result.FieldDice end
            if result.Snowflake ~= nil then Settings.Snowflake = result.Snowflake end
            if result.SnowflakeDelay ~= nil then Settings.SnowflakeDelay = result.SnowflakeDelay end
            if result.RedCannon ~= nil then Settings.RedCannon = result.RedCannon end
            if result.BlueCannon ~= nil then Settings.BlueCannon = result.BlueCannon end
            if result.YellowCannon ~= nil then Settings.YellowCannon = result.YellowCannon end
            if result.ShowCooldowns ~= nil then Settings.ShowCooldowns = result.ShowCooldowns end
            if result.Autoretro ~= nil then Settings.Autoretro = result.Autoretro end
            if result.retroWalkspeed ~= nil then Settings.retroWalkspeed = result.retroWalkspeed end
            if result.AutoClaimHive ~= nil then Settings.AutoClaimHive = result.AutoClaimHive end
            if result.AutoHit ~= nil then Settings.AutoHit = result.AutoHit end
            if result.AutoSlimeKill ~= nil then Settings.AutoSlimeKill = result.AutoSlimeKill end
            if result.AutoUpgrade ~= nil then Settings.AutoUpgrade = result.AutoUpgrade end
            if result.AutoBuyBricks ~= nil then Settings.AutoBuyBricks = result.AutoBuyBricks end
            if result.FarmPollen ~= nil then Settings.FarmPollen = result.FarmPollen end
            if result.AutoToolSwitch ~= nil then Settings.AutoToolSwitch = result.AutoToolSwitch end
            if result.KillAuraVisual ~= nil then Settings.KillAuraVisual = result.KillAuraVisual end
            if result.KillAuraRange ~= nil then Settings.KillAuraRange = result.KillAuraRange end
            if result.KillAuraTrigger ~= nil then Settings.KillAuraTrigger = result.KillAuraTrigger end
            if result.KillAuraCooldown ~= nil then Settings.KillAuraCooldown = result.KillAuraCooldown end
            if result.BloomLevel ~= nil then Settings.BloomLevel = result.BloomLevel end
            if result.CameraMaxZoomDistance ~= nil then Settings.CameraMaxZoomDistance = result.CameraMaxZoomDistance end
            if result.MaxAxisFieldOfView ~= nil then Settings.MaxAxisFieldOfView = result.MaxAxisFieldOfView end
            if result.CollectTokens ~= nil then Settings.CollectTokens = result.CollectTokens end
        end
    end
end

-- Config laden
LoadConfig()

task.spawn(function()
    local lastPrint = 0
    while ScriptRunning do
        if game.PlaceId == 17579225831 then
            hasIllumina = LocalPlayer.Backpack:FindFirstChild("ClassicIllumina") ~= nil or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("ClassicIllumina") ~= nil)
            hasFirebrand = (LocalPlayer.Backpack:FindFirstChild("ClassicFirebrand") ~= nil or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("ClassicFirebrand") ~= nil)) and not hasIllumina
            hasClassicSword = (LocalPlayer.Backpack:FindFirstChild("ClassicSword") ~= nil or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("ClassicSword") ~= nil)) and not (hasFirebrand or hasIllumina)

            local equippedTool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
            if equippedTool then
                if equippedTool.Name == "ClassicSword" then
                    currentEquippedSword = "ClassicSword"
                elseif equippedTool.Name == "ClassicFirebrand" then
                    currentEquippedSword = "ClassicFirebrand"
                elseif equippedTool.Name == "ClassicIllumina" then
                    currentEquippedSword = "ClassicIllumina"
                else
                    currentEquippedSword = nil -- Farming tool or other
                end
            else
                currentEquippedSword = nil -- No tool
            end
            
            if tick() - lastPrint > 10 then
                print("owned: Sword="..tostring(hasClassicSword)..", firebrand="..tostring(hasFirebrand)..", illumina="..tostring(hasIllumina).." equipped: "..tostring(currentEquippedSword))
                lastPrint = tick()
            end
        end
        task.wait(0.5)
    end
end)

-- Laufend die aktuelle Brick-Anzahl pollen (keine Logs)
local CurrentBricks = 0
local CurrentRound = 0
task.spawn(function()
    while ScriptRunning do
        pcall(function()
            local screenGui = LocalPlayer.PlayerGui:FindFirstChild("ScreenGui")
            local brickLabel = screenGui and screenGui:FindFirstChild("UnderPopUpFrame")
                and screenGui.UnderPopUpFrame:FindFirstChild("RetroGuiTopMenu")
                and screenGui.UnderPopUpFrame.RetroGuiTopMenu:FindFirstChild("TopMenuFrame2")
                and screenGui.UnderPopUpFrame.RetroGuiTopMenu.TopMenuFrame2:FindFirstChild("BrickLabel")
            
            if brickLabel and brickLabel.Text then
                local text = brickLabel.Text:gsub("%D", "") -- Entferne alles außer Ziffern (z.B. Kommas)
                CurrentBricks = tonumber(text) or 0
            else
                CurrentBricks = 0
            end
        end)
        task.wait(1)
    end
end)

-- Poll current round for FarmPollen
task.spawn(function()
    while ScriptRunning do
        pcall(function()
            local screenGui = LocalPlayer.PlayerGui:FindFirstChild("ScreenGui")
            local roundLabel = screenGui and screenGui:FindFirstChild("UnderPopUpFrame")
                and screenGui.UnderPopUpFrame:FindFirstChild("RetroGuiTopMenu")
                and screenGui.UnderPopUpFrame.RetroGuiTopMenu:FindFirstChild("TopMenuFrame2")
                and screenGui.UnderPopUpFrame.RetroGuiTopMenu.TopMenuFrame2:FindFirstChild("RoundLabel")
            
            if roundLabel then
                local roundText = roundLabel.Text -- e.g. "ROUND 1"
                local roundNum = tonumber(roundText:match("ROUND%s+(%d+)"))
                if roundNum then
                    CurrentRound = roundNum
                end
            end
        end)
        task.wait(10)
    end
end)

-- Funktion zum Setzen des Walkspeeds
local function SetWalkspeed(speed)
    local Character = LocalPlayer.Character
    if Character and Character:FindFirstChildOfClass("Humanoid") then
        Character.Humanoid.WalkSpeed = speed
    end
end

-- Wenn der Spieler respawnt, muss der Walkspeed neu gesetzt werden, falls aktiv
LocalPlayer.CharacterAdded:Connect(function(Character)
    -- Wenn retro Walkspeed aktiv ist, setze ihn nach dem Respawn
    if Settings.retroWalkspeed and game.PlaceId == 17579225831 then
        Character:WaitForChild("Humanoid").WalkSpeed = 70
    end
end)

-- Rayfield Library laden
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
    Name = "bss schlip schlop benutzer schnittstelle",
    LoadingTitle = "Loading...",
    LoadingSubtitle = "hoppe hoppe reiter ich hoff ich leb nicht weiter",
    ConfigurationSaving = {
        Enabled = false,
    },
    KeySystem = false,
})

-- Versuchen das Fenster zu minimieren
pcall(function()
    if Window.Minimize then
        Window:Minimize()
    end
end)
Rayfield:SetVisibility(false)

-- TAB: Generators
local FarmTab = Window:CreateTab("Generators", 4483362458)

FarmTab:CreateToggle({
    Name = "Auto Bronze Star Amulet",
    CurrentValue = Settings.BronzeStar,
    Flag = "BronzeStar", 
    Callback = function(Value)
        Settings.BronzeStar = Value
        SaveConfig()
    end,
})

FarmTab:CreateToggle({
    Name = "Auto Diamond Star Amulet",
    CurrentValue = Settings.DiamondStar,
    Flag = "DiamondStar",
    Callback = function(Value)
        Settings.DiamondStar = Value
        SaveConfig()
    end,
})

FarmTab:CreateToggle({
    Name = "Auto Field Dice",
    CurrentValue = Settings.FieldDice,
    Flag = "FieldDice",
    Callback = function(Value)
        Settings.FieldDice = Value
        SaveConfig()
    end,
})

FarmTab:CreateToggle({
    Name = "Auto Snowflake",
    CurrentValue = Settings.Snowflake,
    Flag = "Snowflake",
    Callback = function(Value)
        Settings.Snowflake = Value
        SaveConfig()
    end,
})

FarmTab:CreateSlider({
    Name = "Snowflake Delay",
    Range = {1.05, 10},
    Increment = 0.05,
    Suffix = "s",
    CurrentValue = Settings.SnowflakeDelay,
    Flag = "SnowflakeDelay",
    Callback = function(Value)
        Settings.SnowflakeDelay = Value
        SaveConfig()
    end,
})

FarmTab:CreateSection("Cannons")

FarmTab:CreateToggle({
    Name = "Auto Red Cannon",
    CurrentValue = Settings.RedCannon,
    Flag = "RedCannon",
    Callback = function(Value)
        Settings.RedCannon = Value
        SaveConfig()
    end,
})

FarmTab:CreateToggle({
    Name = "Auto Blue Cannon",
    CurrentValue = Settings.BlueCannon,
    Flag = "BlueCannon",
    Callback = function(Value)
        Settings.BlueCannon = Value
        SaveConfig()
    end,
})

FarmTab:CreateToggle({
    Name = "Auto Yellow Cannon",
    CurrentValue = Settings.YellowCannon,
    Flag = "YellowCannon",
    Callback = function(Value)
        Settings.YellowCannon = Value
        SaveConfig()
    end,
})

-- TAB: Masks
local MaskTab = Window:CreateTab("Masks", 4483362458)
local MaskEquipping = false

local function TweenToMask(position, maskType)
    if MaskEquipping then return end
    MaskEquipping = true
    
    local Character = LocalPlayer.Character
    if not Character then MaskEquipping = false return end
    local HumRoot = Character:FindFirstChild("HumanoidRootPart")
    if not HumRoot then MaskEquipping = false return end
    
    local TweenService = game:GetService("TweenService")
    local oldPos = HumRoot.Position
    
    local function doTween(targetPos)
        local distance = (targetPos - HumRoot.Position).Magnitude
        local duration = distance / 69
        local tween = TweenService:Create(HumRoot, TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
            CFrame = CFrame.new(targetPos)
        })
        tween:Play()
        tween.Completed:Wait()
    end
    
    doTween(position)
    
    local args = {
        [1] = "Equip",
        [2] = {
            ["Type"] = maskType,
            ["Category"] = "Accessory"
        }
    }
    ReplicatedStorage.Events.ItemPackageEvent:InvokeServer(unpack(args))
    task.wait(0.5)
    
    doTween(oldPos)
    MaskEquipping = false
end

MaskTab:CreateButton({
    Name = "Equip Diamond Mask",
    Callback = function()
        TweenToMask(Vector3.new(-338, 132, -400), "Diamond Mask")
    end,
})

MaskTab:CreateButton({
    Name = "Equip Demon Mask",
    Callback = function()
        TweenToMask(Vector3.new(304, 28, 275), "Demon Mask")
    end,
})

-- TAB: retro
local retroTab = Window:CreateTab("retro", 4483362458)

retroTab:CreateButton({
    Name = "tp to retro (atlas bypass and direct join)",
    Callback = function()
        TeleportService:Teleport(17579225831, LocalPlayer)
    end,
})

retroTab:CreateButton({
    Name = "tp to retro lobby (atlas bypass)",
    Callback = function()
        TeleportService:Teleport(17579226768, LocalPlayer)
    end,
})

retroTab:CreateSection("atuo tp")

retroTab:CreateToggle({
    Name = "auto teleport retro",
    CurrentValue = Settings.Autoretro,
    Flag = "Autoretro",
    Callback = function(Value)
        Settings.Autoretro = Value
        SaveConfig()
    end,
})

retroTab:CreateToggle({
    Name = "retro Walkspeed (70)",
    CurrentValue = Settings.retroWalkspeed,
    Flag = "retroWalkspeed",
    Callback = function(Value)
        Settings.retroWalkspeed = Value
        SaveConfig()
        
        if game.PlaceId == 17579225831 then
            if Value then
                SetWalkspeed(70)
            end
        end
    end,
})

retroTab:CreateToggle({
    Name = "auto claim hive",
    CurrentValue = Settings.AutoClaimHive,
    Flag = "AutoClaimHive",
    Callback = function(Value)
        Settings.AutoClaimHive = Value
        SaveConfig()
    end,
})

retroTab:CreateToggle({
    Name = "autohit",
    CurrentValue = Settings.AutoHit,
    Flag = "AutoHit",
    Callback = function(Value)
        Settings.AutoHit = Value
        SaveConfig()
    end,
})

retroTab:CreateToggle({
    Name = "auto slime kill",
    CurrentValue = Settings.AutoSlimeKill,
    Flag = "AutoSlimeKill",
    Callback = function(Value)
        Settings.AutoSlimeKill = Value
        SaveConfig()
    end,
})

retroTab:CreateToggle({
    Name = "collect tokens",
    CurrentValue = Settings.CollectTokens,
    Flag = "CollectTokens",
    Callback = function(Value)
        Settings.CollectTokens = Value
        SaveConfig()
    end,
})

retroTab:CreateToggle({
    Name = "auto buy",
    CurrentValue = Settings.AutoUpgrade,
    Flag = "AutoUpgrade",
    Callback = function(Value)
        Settings.AutoUpgrade = Value
        SaveConfig()
    end,
})

retroTab:CreateToggle({
    Name = "autobuy bricks",
    CurrentValue = Settings.AutoBuyBricks,
    Flag = "AutoBuyBricks",
    Callback = function(Value)
        Settings.AutoBuyBricks = Value
        SaveConfig()
    end,
})

retroTab:CreateToggle({
    Name = "farm pollen (r0-8)",
    CurrentValue = Settings.FarmPollen,
    Flag = "FarmPollen",
    Callback = function(Value)
        Settings.FarmPollen = Value
        SaveConfig()
    end,
})

retroTab:CreateToggle({
    Name = "auto tool switch",
    CurrentValue = Settings.AutoToolSwitch,
    Flag = "AutoToolSwitch",
    Callback = function(Value)
        Settings.AutoToolSwitch = Value
        SaveConfig()
    end,
})

retroTab:CreateToggle({
    Name = "killaura",
    CurrentValue = Settings.KillAuraVisual,
    Flag = "KillAuraVisual",
    Callback = function(Value)
        Settings.KillAuraVisual = Value
        SaveConfig()
    end,
})

retroTab:CreateSlider({
    Name = "killaura ranges lider",
    Range = {20, 70},
    Increment = 1,
    Suffix = "studs",
    CurrentValue = Settings.KillAuraRange,
    Flag = "KillAuraRange",
    Callback = function(Value)
        Settings.KillAuraRange = Value
        SaveConfig()
    end,
})

retroTab:CreateSlider({
    Name = "killaura trigger",
    Range = {2, 8},
    Increment = 1,
    Suffix = "enemies",
    CurrentValue = Settings.KillAuraTrigger,
    Flag = "KillAuraTrigger",
    Callback = function(Value)
        Settings.KillAuraTrigger = Value
        SaveConfig()
    end,
})

retroTab:CreateSlider({
    Name = "killaura cooldown",
    Range = {0.2, 6},
    Increment = 0.1,
    Suffix = "seconds",
    CurrentValue = Settings.KillAuraCooldown,
    Flag = "KillAuraCooldown",
    Callback = function(Value)
        Settings.KillAuraCooldown = Value
        SaveConfig()
    end,
})

retroTab:CreateSlider({
    Name = "max bloom level slider",
    Range = {1, 12},
    Increment = 1,
    Suffix = "lvl",
    CurrentValue = Settings.BloomLevel,
    Flag = "BloomLevel",
    Callback = function(Value)
        Settings.BloomLevel = Value
        SaveConfig()
    end,
})

retroTab:CreateSection("Upgrades")

local function teleportToUpgradePad(button)
    local character = LocalPlayer.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then return end
    local hrp = character.HumanoidRootPart

    pcall(function()
        local oldCFrame = button.CFrame
        button.CanCollide = false
        button.CFrame = hrp.CFrame
        task.wait(0.5)
        button.CFrame = oldCFrame * CFrame.new(0, 50, 0)
    end)
end

task.spawn(function()
    -- Wait for the game and TycoonButtons to load
    while not workspace:FindFirstChild("ClassicMinigame") or not workspace.ClassicMinigame:FindFirstChild("TycoonButtons") do
        task.wait(1)
    end

    local tycoonButtons = workspace.ClassicMinigame.TycoonButtons

    for _, child in ipairs(tycoonButtons:GetChildren()) do
        local button = child:FindFirstChild("Button")
        if button and button:IsA("BasePart") then
            retroTab:CreateButton({
                Name = child.Name,
                Callback = function()
                    teleportToUpgradePad(button)
                end,
            })
        end
    end
end)

retroTab:CreateSection("cam")

retroTab:CreateSlider({
    Name = "max zoom",
    Range = {10, 1000},
    Increment = 10,
    Suffix = "studs",
    CurrentValue = Settings.CameraMaxZoomDistance,
    Flag = "CameraMaxZoomDistance",
    Callback = function(Value)
        Settings.CameraMaxZoomDistance = Value
        LocalPlayer.CameraMaxZoomDistance = Value
        SaveConfig()
    end,
})

retroTab:CreateSlider({
    Name = "MaxAxisFOV",
    Range = {60, 140},
    Increment = 1,
    Suffix = "deg",
    CurrentValue = Settings.MaxAxisFieldOfView,
    Flag = "MaxAxisFieldOfView",
    Callback = function(Value)
        Settings.MaxAxisFieldOfView = Value
        pcall(function()
            if workspace.CurrentCamera then
                workspace.CurrentCamera.MaxAxisFieldOfView = Value
            end
        end)
        SaveConfig()
    end,
})

-- TAB: Settings (Für Unload)
local SettingsTab = Window:CreateTab("Settings", 4483362458)

SettingsTab:CreateButton({
    Name = "Unload Script (Stop & Close)",
    Callback = function()
        -- 1. Loop stoppen
        ScriptRunning = false
        
        -- 2. Rayfield zerstören
        Rayfield:Destroy()

        -- 3. UI zerstören
        if CooldownGui then CooldownGui:Destroy() end

        -- KillAura Visuals clean up should happen via Loop 9 checking ScriptRunning
        
        print("unloaded")
    end,
})

SettingsTab:CreateToggle({
    Name = "Show Cooldowns",
    CurrentValue = Settings.ShowCooldowns,
    Flag = "ShowCooldowns",
    Callback = function(Value)
        Settings.ShowCooldowns = Value
        if not Value then
            for _, frame in pairs(Bars) do
                frame.Visible = false
            end
        end
        SaveConfig()
    end,
})

-- [HAUPT LOGIK LOOP]
-- Loop 1: Stars, Field Dice and Cannons (1.05s)
task.spawn(function()
    while ScriptRunning do
        local usedAny = false
        -- 1. Bronze Star Logic
        if Settings.BronzeStar then
            pcall(function()
                local args = {[1] = "Bronze Star Amulet Generator"}
                ReplicatedStorage.Events.ToyEvent:FireServer(unpack(args))
                usedAny = true
            end)
        end

        -- 2. Diamond Star Logic
        if Settings.DiamondStar then
            pcall(function()
                local args = {[1] = "Diamond Star Amulet Generator"}
                ReplicatedStorage.Events.ToyEvent:FireServer(unpack(args))
                usedAny = true
            end)
        end

        -- 3. Field Dice Logic
        if Settings.FieldDice then
            pcall(function()
                local args = {[1] = {["Name"] = "Field Dice"}}
                ReplicatedStorage.Events.PlayerActivesCommand:FireServer(unpack(args))
                usedAny = true
            end)
        end
        
        -- 4. Cannon Logic
        if Settings.RedCannon then
            pcall(function()
                ReplicatedStorage.Events.ToyEvent:FireServer("Red Cannon")
                usedAny = true
            end)
        end
        
        if Settings.BlueCannon then
            pcall(function()
                ReplicatedStorage.Events.ToyEvent:FireServer("Blue Cannon")
                usedAny = true
            end)
        end
        
        if Settings.YellowCannon then
            pcall(function()
                ReplicatedStorage.Events.ToyEvent:FireServer("Yellow Cannon")
                usedAny = true
            end)
        end
        
        if usedAny then
            UpdateBar("Stars", 1.05)
        end
        
        task.wait(1.05)
    end
end)

-- Loop 2: Snowflake (Customizable Delay)
task.spawn(function()
    while ScriptRunning do
        if Settings.Snowflake then
            pcall(function()
                local args = {[1] = {["Name"] = "Snowflake"}}
                ReplicatedStorage.Events.PlayerActivesCommand:FireServer(unpack(args))
                UpdateBar("Snowflake", Settings.SnowflakeDelay)
            end)
        end
        task.wait(Settings.SnowflakeDelay)
    end
end)

-- Loop 3: Auto Teleport (5s)
task.spawn(function()
    while ScriptRunning and game.PlaceId ~= 17579225831 do
        if Settings.Autoretro then
            TeleportService:Teleport(17579225831, LocalPlayer)
        end
        task.wait(5)
    end
end)

-- Loop 4: Walkspeed (bei Join)
if not game:IsLoaded() then
    game.Loaded:Wait()
end

task.spawn(function()
    while ScriptRunning do
        if game.PlaceId == 17579225831 then
            if Settings.retroWalkspeed then
                SetWalkspeed(70)
            end
        end
        task.wait(1)
    end
end)

-- Loop 5: AutoClaimHive (Separate Logik)
task.spawn(function()
    while ScriptRunning do
        if game.PlaceId == 17579225831 then
            if Settings.AutoClaimHive and not HiveClaimedInretro then
                HiveClaimedInretro = true -- Verhindert mehrfaches Ausführen in der gleichen Session

                -- Nochmals prüfen, ob Toggle noch an ist und wir noch in retro sind
                if Settings.AutoClaimHive and game.PlaceId == 17579225831 then
                    local claimValues = {9, 9}
                    
                    for _, value in ipairs(claimValues) do
                        pcall(function()
                            ReplicatedStorage.Events.ClaimHive:FireServer(value)
                            print("hive claim " .. value)
                        end)
                        task.wait(1)
                    end
                else
                    HiveClaimedInretro = false -- Reset falls abgebrochen
                end
            end
        else
            -- Reset wenn man das Spiel verlässt
            if HiveClaimedInretro then
                HiveClaimedInretro = false
            end
        end
        task.wait(1)
    end
end)

-- Loop 6: AutoHit (0.05s) - Pausiert wenn Rayfield UI offen ist
task.spawn(function()
    while ScriptRunning do
        if Settings.AutoHit and game.PlaceId == 17579225831 then
            -- Prüfe ob Rayfield UI sichtbar ist
            local uiVisible = false
            pcall(function()
                uiVisible = Rayfield:IsVisible()
            end)

            -- Nur AutoHit wenn UI nicht sichtbar ist
            if not uiVisible then
                pcall(function()
                    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
                    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
                end)
            end
        end
        task.wait(0.05)
    end
end)

task.spawn(function()
    local TweenService = game:GetService("TweenService")
    local lastToggleState = false
    local platform = nil
    local collectingTokensNow = false
    local sprinklerPlaced = false
    local lastBloom = nil

    while ScriptRunning do
        if Settings.AutoSlimeKill and game.PlaceId == 17579225831 then
            if KillAura_isExecuting then
                task.wait()
                -- Wait for killaura to finish before doing any slime kill logic
            elseif not lastToggleState then
                lastToggleState = true
                collectingTokensNow = false
                sprinklerPlaced = false
                -- ClassicBaseplate Collision ausschalten
                pcall(function()
                    local classicBaseplate = workspace.ClassicMinigame.ClassicBaseplate
                    if classicBaseplate then
                        classicBaseplate.CanCollide = false
                    end
                end)
                
                -- 10 Sekunden warten beim ersten Einschalten
                task.wait(10)
            elseif LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and LocalPlayer.Character:FindFirstChild("Humanoid") then
                local HumanoidRootPart = LocalPlayer.Character.HumanoidRootPart
                local Humanoid = LocalPlayer.Character.Humanoid

                -- Physics komplett ausschalten für den Part während das Feature aktiv ist
                HumanoidRootPart.AssemblyLinearVelocity = Vector3.zero
                HumanoidRootPart.AssemblyAngularVelocity = Vector3.zero

                -- Platform erstellen
                if not platform or not platform.Parent then
                    platform = Instance.new("Part")
                    platform.Size = Vector3.new(100, 1, 100) -- Große Platform für maximale Sicherheit
                    platform.Anchored = true
                    platform.Transparency = 1
                    platform.CanCollide = true
                    platform.Name = "SlimeKillPlatform"
                    platform.Parent = workspace
                end

                -- Character hinlegen und nach oben schauen lassen
                Humanoid.PlatformStand = true
                
                -- Rotation fixieren: Schaut nach oben (Bauch nach unten, Gesicht zum Himmel)
                local upRotation = CFrame.Angles(math.rad(90), 0, 0)
                local targetY = 283

                -- Monster-Target finden: prüfe nur Blob*-Parts (Slimes) und Torso (z.B. Zombies).
                -- Priorität: kleinstes |Z-230|, Tie-Breaker: geringster horizontaler Abstand (X,Z) zur Z=230-Ebene in Relation zum Spieler
                local TargetSlimeBlob = nil
                local bestZDiff = math.huge
                local bestTie = math.huge

                if workspace:FindFirstChild("Monsters") then
                    for _, monsterFolder in pairs(workspace.Monsters:GetChildren()) do
                        local folderName = tostring(monsterFolder.Name)
                        -- Match any Zombie or Slime regardless of level
                        local isSlime = folderName:match("^Slime")
                        local slimeLvl = isSlime and tonumber(folderName:match("Lvl%s+(%d+)"))
                        if (folderName:match("^Zombie") or isSlime) and (not slimeLvl or slimeLvl < 22) then
                            -- Suche direkt alle Nachkommen im Folder
                            for _, desc in pairs(monsterFolder:GetDescendants()) do
                                if desc:IsA("BasePart") then
                                    -- Zombie: nur Torso angreifen
                                    if folderName:match("^Zombie") and desc.Name == "Torso" then
                                        local zDiff = math.abs(desc.Position.Z - 230)
                                        local horizDist = (Vector2.new(desc.Position.X - HumanoidRootPart.Position.X, desc.Position.Z - 230)).Magnitude
                                        if zDiff < bestZDiff or (zDiff == bestZDiff and horizDist < bestTie) then
                                            bestZDiff = zDiff
                                            bestTie = horizDist
                                            TargetSlimeBlob = desc
                                            sprinklerPlaced = false
                                            lastBloom = nil
                                        end
                                    end
                                    -- Slime: nur Blob2 angreifen
                                    if folderName:match("^Slime") and desc.Name == "Blob2" then
                                        local zDiff = math.abs(desc.Position.Z - 230)
                                        local horizDist = (Vector2.new(desc.Position.X - HumanoidRootPart.Position.X, desc.Position.Z - 230)).Magnitude
                                        if zDiff < bestZDiff or (zDiff == bestZDiff and horizDist < bestTie) then
                                            bestZDiff = zDiff
                                            bestTie = horizDist
                                            TargetSlimeBlob = desc
                                            sprinklerPlaced = false
                                            lastBloom = nil
                                        end
                                    end
                                end
                            end
                        end
                    end
                end

                -- Wenn kein Slime gefunden: Sammle Collectibles 'C' ohne zurückzufliegen
                if not TargetSlimeBlob and not collectingTokensNow and Settings.CollectTokens then
                    collectingTokensNow = true
                    local collectingTokens = true
                    local visitedCollects = {}
                    while collectingTokens and Settings.AutoSlimeKill and Settings.CollectTokens and game.PlaceId == 17579225831 do
                        -- Prüfe nochmal auf neue Slimes (Priorität)
                        local CheckSlimeBlob = nil
                        local checkZDiff = math.huge
                        local checkTie = math.huge
                        if workspace:FindFirstChild("Monsters") then
                                for _, monsterFolder in pairs(workspace.Monsters:GetChildren()) do
                                    local folderName = tostring(monsterFolder.Name)
                                    -- Match any Zombie or Slime regardless of level
                                    local isSlime = folderName:match("^Slime")
                                    local slimeLvl = isSlime and tonumber(folderName:match("Lvl%s+(%d+)"))
                                    if (folderName:match("^Zombie") or isSlime) and (not slimeLvl or slimeLvl < 22) then
                                        -- Suche direkt alle Nachkommen im Folder
                                        for _, desc in pairs(monsterFolder:GetDescendants()) do
                                            if desc:IsA("BasePart") then
                                                if folderName:match("^Zombie") and desc.Name == "Torso" then
                                                    local zDiff = math.abs(desc.Position.Z - 230)
                                                    local horizDist = (Vector2.new(desc.Position.X - HumanoidRootPart.Position.X, desc.Position.Z - 230)).Magnitude
                                                    if zDiff < checkZDiff or (zDiff == checkZDiff and horizDist < checkTie) then
                                                        checkZDiff = zDiff
                                                        checkTie = horizDist
                                                        CheckSlimeBlob = desc
                                                    end
                                                end
                                                if folderName:match("^Slime") and desc.Name == "Blob2" then
                                                    local zDiff = math.abs(desc.Position.Z - 230)
                                                    local horizDist = (Vector2.new(desc.Position.X - HumanoidRootPart.Position.X, desc.Position.Z - 230)).Magnitude
                                                    if zDiff < checkZDiff or (zDiff == checkZDiff and horizDist < checkTie) then
                                                        checkZDiff = zDiff
                                                        checkTie = horizDist
                                                        CheckSlimeBlob = desc
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                        end
                        
                        if CheckSlimeBlob or not Settings.CollectTokens then
                            -- Slime gefunden oder Toggle aus, raus aus Token-Loop
                            TargetSlimeBlob = CheckSlimeBlob
                            collectingTokens = false
                            collectingTokensNow = false
                            sprinklerPlaced = false
                            lastBloom = nil
                            break
                        end

                        -- Bereinige besuchte Tokens (entferne verschwundene oder alte Einträge)
                        for k, v in pairs(visitedCollects) do
                            if (not k.Parent) or ((tick() - v) > 10) then
                                visitedCollects[k] = nil
                            end
                        end

                        -- Suche nächsten 'C'-Token innerhalb 400 Radius (ignoriert bereits besuchte)
                        local nextCollect = nil
                        local nextCollectDist = math.huge
                        local siblings = {}
                        pcall(function()
                            if workspace:FindFirstChild("Collectibles") then
                                local allCollects = workspace.Collectibles:GetChildren()
                                for _, c in pairs(allCollects) do
                                    if c and c:IsA("BasePart") and c.Name == "C" and c.Parent and not visitedCollects[c] then
                                        local d = (c.Position - HumanoidRootPart.Position).Magnitude
                                        if d <= 400 and d < nextCollectDist then
                                            nextCollectDist = d
                                            nextCollect = c
                                        end
                                    end
                                end
                                
                                if nextCollect then
                                    for _, c in pairs(allCollects) do
                                        if c and c:IsA("BasePart") and c.Name == "C" and c.Parent and not visitedCollects[c] then
                                            -- Check if it's "ineinander" (very close)
                                            if (c.Position - nextCollect.Position).Magnitude < 2 then
                                                table.insert(siblings, c)
                                            end
                                        end
                                    end
                                end
                            end
                        end)

                        if nextCollect then
                            -- Markiere alle ineinanderliegenden Tokens als besucht
                            for _, s in ipairs(siblings) do
                                visitedCollects[s] = tick()
                            end
                            sprinklerPlaced = false
                            lastBloom = nil

                            -- Tween direkt zur Token-Position
                            local collectPos = nextCollect.Position
                            local collectTarget = Vector3.new(collectPos.X, collectPos.Y, collectPos.Z)
                            local dist = (collectTarget - HumanoidRootPart.Position).Magnitude
                            local speed = 69
                            local duration = math.max(0.02, dist / speed)

                            local targetCFrame = CFrame.new(collectTarget) * upRotation
                            if tick() < AutoSlime_blockUntil then
                                task.wait()
                            else
                                cancelActiveAutoSlime()
                                if Settings.AutoToolSwitch and currentEquippedSword ~= nil and tick() - lastEquipTime > 0.5 then
                                    EquipTool("FarmingTool")
                                end
                                local tween = TweenService:Create(HumanoidRootPart, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame = targetCFrame})
                                local platTween = TweenService:Create(platform, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame = CFrame.new(collectTarget - Vector3.new(0, 3, 0))})
                                tween:Play()
                                platTween:Play()
                                AutoSlime_activeTween = tween
                                AutoSlime_activePlatTween = platTween
                                AutoSlime_activeConn = game:GetService("RunService").Heartbeat:Connect(function()
                                    if not Settings.AutoSlimeKill or not Settings.CollectTokens or not AutoSlime_activeTween or game.PlaceId ~= 17579225831 then
                                        if AutoSlime_activeConn then AutoSlime_activeConn:Disconnect() AutoSlime_activeConn = nil end
                                        return
                                    end
                                    HumanoidRootPart.AssemblyLinearVelocity = Vector3.zero
                                    HumanoidRootPart.AssemblyAngularVelocity = Vector3.zero
                                    if platform and platform:IsA("BasePart") then
                                        platform.AssemblyLinearVelocity = Vector3.zero
                                        platform.AssemblyAngularVelocity = Vector3.zero
                                    end
                                end)
                                tween.Completed:Wait()
                                if AutoSlime_activeConn then AutoSlime_activeConn:Disconnect() AutoSlime_activeConn = nil end
                                AutoSlime_activeTween = nil
                                AutoSlime_activePlatTween = nil
                            end

                            -- Berühre alle ineinanderliegenden Tokens mit firetouchinterest
                            pcall(function()
                                local hrp = HumanoidRootPart
                                for _, s in ipairs(siblings) do
                                    if s and hrp and s:IsA("BasePart") and s.Parent then
                                        firetouchinterest(s, hrp, 0)
                                        firetouchinterest(s, hrp, 1)
                                    end
                                end
                            end)
                            task.wait(0.03)
                        else
                            -- Keine Token mehr gefunden, beende Loop
                            collectingTokens = false
                            collectingTokensNow = false
                        end
                    end

                    -- Nach Token-Sammeln: Suche nach Brick Blooms falls keine Slimes da sind
                    local targetBloom = nil
                    if not TargetSlimeBlob then
                        pcall(function()
                            if workspace:FindFirstChild("Happenings") and workspace.Happenings:FindFirstChild("BrickBlooms") then
                                for _, bloom in pairs(workspace.Happenings.BrickBlooms:GetChildren()) do
                                    local centerPart = bloom:FindFirstChild("CenterPart")
                                    if centerPart then
                                        local attachment = centerPart:FindFirstChild("Attachment")
                                        local gui = attachment and attachment:FindFirstChild("Gui")
                                        local nameRow = gui and gui:FindFirstChild("NameRow")
                                        local label = nameRow and nameRow:FindFirstChild("TextLabel")
                                        if label and label.Text then
                                            local text = label.Text
                                            local level = tonumber(text:match("Lvl%s+(%d+)"))
                                            if level and level <= Settings.BloomLevel then
                                                targetBloom = centerPart
                                                break
                                            end
                                        end
                                    end
                                end
                            end
                        end)

                        if targetBloom then
                            -- Bloom gefunden!
                            if Settings.AutoToolSwitch and currentEquippedSword ~= nil and tick() - lastEquipTime > 0.5 then
                                EquipTool("FarmingTool")
                            end

                            local bloomPos = targetBloom.Position
                            local bloomHeight = 290 -- Einheitliche Höhe für diesen Bloom
                            
                            -- 1. Nur zum Zentrum fliegen & Sprinkler platzieren, wenn es ein NEUER Bloom ist
                            if targetBloom ~= lastBloom then
                                lastBloom = targetBloom
                                local targetPos = Vector3.new(bloomPos.X, bloomHeight, bloomPos.Z)
                                local dist = (targetPos - HumanoidRootPart.Position).Magnitude
                                local speed = 69
                                local duration = dist / speed
                                local targetCFrame = CFrame.new(targetPos) * upRotation
                                
                                if tick() >= AutoSlime_blockUntil then
                                    cancelActiveAutoSlime()
                                    local tween = TweenService:Create(HumanoidRootPart, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame = targetCFrame})
                                    local platTween = TweenService:Create(platform, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame = CFrame.new(targetPos - Vector3.new(0, 3, 0))})
                                    
                                    tween:Play()
                                    platTween:Play()
                                    AutoSlime_activeTween = tween
                                    AutoSlime_activePlatTween = platTween
                                    
                                    AutoSlime_activeConn = game:GetService("RunService").Heartbeat:Connect(function()
                                        if not Settings.AutoSlimeKill or not AutoSlime_activeTween or game.PlaceId ~= 17579225831 then
                                            if AutoSlime_activeConn then AutoSlime_activeConn:Disconnect() AutoSlime_activeConn = nil end
                                            return
                                        end
                                        HumanoidRootPart.AssemblyLinearVelocity = Vector3.zero
                                        HumanoidRootPart.AssemblyAngularVelocity = Vector3.zero
                                        if platform and platform:IsA("BasePart") then
                                            platform.AssemblyLinearVelocity = Vector3.zero
                                            platform.AssemblyAngularVelocity = Vector3.zero
                                        end
                                    end)
                                    
                                    tween.Completed:Wait()
                                    if AutoSlime_activeConn then AutoSlime_activeConn:Disconnect() AutoSlime_activeConn = nil end
                                    AutoSlime_activeTween = nil
                                    AutoSlime_activePlatTween = nil

                                    -- Sprinkler platzieren
                                    pcall(function()
                                        local args = {[1] = {["Name"] = "Sprinkler Builder"}}
                                        game:GetService("ReplicatedStorage").Events.PlayerActivesCommand:FireServer(unpack(args))
                                    end)
                                    task.wait(0.2)
                                end
                            end

                            -- 2. Im Viereck rumrennen (Jede Umdrehung)
                            if tick() >= AutoSlime_blockUntil then
                                local offset = 12
                                local squarePoints = {
                                    Vector3.new(bloomPos.X + offset, bloomHeight, bloomPos.Z + offset),
                                    Vector3.new(bloomPos.X - offset, bloomHeight, bloomPos.Z + offset),
                                    Vector3.new(bloomPos.X - offset, bloomHeight, bloomPos.Z - offset),
                                    Vector3.new(bloomPos.X + offset, bloomHeight, bloomPos.Z - offset)
                                }

                                for _, p in ipairs(squarePoints) do
                                    -- Ensure FarmingTool is equipped during bloom square movement
                                    if Settings.AutoToolSwitch and currentEquippedSword ~= nil and tick() - lastEquipTime > 0.5 then
                                        EquipTool("FarmingTool")
                                    end

                                    -- Abbruch falls Slime erscheint oder Toggle aus
                                    local foundSlime = false
                                    if workspace:FindFirstChild("Monsters") then
                                        for _, monsterFolder in pairs(workspace.Monsters:GetChildren()) do
                                            local folderName = tostring(monsterFolder.Name)
                                            local isSlime = folderName:match("^Slime")
                                            local slimeLvl = isSlime and tonumber(folderName:match("Lvl%s+(%d+)"))
                                            if (folderName:match("^Zombie") or isSlime) and (not slimeLvl or slimeLvl < 22) then
                                                foundSlime = true
                                                break
                                            end
                                        end
                                    end
                                    if foundSlime or not Settings.AutoSlimeKill then break end

                                    local d = (p - HumanoidRootPart.Position).Magnitude
                                    local dur = d / speed
                                    local t = TweenService:Create(HumanoidRootPart, TweenInfo.new(dur, Enum.EasingStyle.Linear), {CFrame = CFrame.new(p) * upRotation})
                                    local pt = TweenService:Create(platform, TweenInfo.new(dur, Enum.EasingStyle.Linear), {CFrame = CFrame.new(p - Vector3.new(0, 3, 0))})
                                    
                                    t:Play()
                                    pt:Play()
                                    AutoSlime_activeTween = t
                                    AutoSlime_activePlatTween = pt
                                    
                                    AutoSlime_activeConn = game:GetService("RunService").Heartbeat:Connect(function()
                                        if not Settings.AutoSlimeKill or not AutoSlime_activeTween or game.PlaceId ~= 17579225831 then
                                            if AutoSlime_activeConn then AutoSlime_activeConn:Disconnect() AutoSlime_activeConn = nil end
                                            return
                                        end
                                        HumanoidRootPart.AssemblyLinearVelocity = Vector3.zero
                                        HumanoidRootPart.AssemblyAngularVelocity = Vector3.zero
                                        if platform and platform:IsA("BasePart") then
                                            platform.AssemblyLinearVelocity = Vector3.zero
                                            platform.AssemblyAngularVelocity = Vector3.zero
                                        end
                                    end)
                                    
                                    t.Completed:Wait()
                                    if AutoSlime_activeConn then AutoSlime_activeConn:Disconnect() AutoSlime_activeConn = nil end
                                    AutoSlime_activeTween = nil
                                    AutoSlime_activePlatTween = nil
                                end
                            end
                        else
                            lastBloom = nil
                        end
                    end

                    -- Nach Bloom-Check: Falls immer noch kein Slime gefunden und kein Bloom gefunden wurde, gehe zur Fallback Position
                    if not TargetSlimeBlob and not targetBloom then
                        if Settings.FarmPollen and CurrentRound >= 0 and CurrentRound <= 8 then
                            -- Farm Pollen Logic for Rounds 0-8
                            if Settings.AutoToolSwitch and currentEquippedSword ~= nil and tick() - lastEquipTime > 0.5 then
                                EquipTool("FarmingTool")
                            end
                            local farmCoords = {
                                Vector3.new(-47030, 290, 64),
                                Vector3.new(-46985, 290, 64),
                                Vector3.new(-46985, 290, 86),
                                Vector3.new(-47030, 290, 86)
                            }
                            
                            local firstCoord = true
                            for _, targetPos in ipairs(farmCoords) do
                                -- Check if slime appeared during move or toggle turned off
                                local foundSlime = false
                                if workspace:FindFirstChild("Monsters") then
                                    for _, monsterFolder in pairs(workspace.Monsters:GetChildren()) do
                                        local folderName = tostring(monsterFolder.Name)
                                        local isSlime = folderName:match("^Slime")
                                        local slimeLvl = isSlime and tonumber(folderName:match("Lvl%s+(%d+)"))
                                        if (folderName:match("^Zombie") or isSlime) and (not slimeLvl or slimeLvl < 22) then
                                            foundSlime = true
                                            break
                                        end
                                    end
                                end
                                if foundSlime or not Settings.AutoSlimeKill or not Settings.FarmPollen or CurrentRound > 8 then break end

                                local dist = (targetPos - HumanoidRootPart.Position).Magnitude
                                local speed = 69
                                local duration = dist / speed
                                local targetCFrame = CFrame.new(targetPos) * upRotation
                                
                                if tick() >= AutoSlime_blockUntil then
                                    cancelActiveAutoSlime()
                                    local tween = TweenService:Create(HumanoidRootPart, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame = targetCFrame})
                                    local platTween = TweenService:Create(platform, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame = CFrame.new(targetPos - Vector3.new(0, 3, 0))})
                                    
                                    tween:Play()
                                    platTween:Play()
                                    AutoSlime_activeTween = tween
                                    AutoSlime_activePlatTween = platTween
                                    
                                    AutoSlime_activeConn = game:GetService("RunService").Heartbeat:Connect(function()
                                        if not Settings.AutoSlimeKill or not AutoSlime_activeTween or game.PlaceId ~= 17579225831 then 
                                            if AutoSlime_activeConn then AutoSlime_activeConn:Disconnect() AutoSlime_activeConn = nil end
                                            return 
                                        end
                                        HumanoidRootPart.AssemblyLinearVelocity = Vector3.zero
                                        HumanoidRootPart.AssemblyAngularVelocity = Vector3.zero
                                        if platform and platform:IsA("BasePart") then
                                            platform.AssemblyLinearVelocity = Vector3.zero
                                            platform.AssemblyAngularVelocity = Vector3.zero
                                        end
                                    end)
                                    
                                    tween.Completed:Wait()
                                    if AutoSlime_activeConn then AutoSlime_activeConn:Disconnect() AutoSlime_activeConn = nil end
                                    AutoSlime_activeTween = nil
                                    AutoSlime_activePlatTween = nil
                                    
                                    if firstCoord and not sprinklerPlaced then
                                        if Settings.AutoToolSwitch and currentEquippedSword ~= nil then
                                            EquipTool("FarmingTool")
                                        end
                                        task.wait(0.2) -- Give some time for the tool to unequip
                                        -- Place Sprinkler at the first coordinate
                                        pcall(function()
                                            local args = {[1] = {["Name"] = "Sprinkler Builder"}}
                                            game:GetService("ReplicatedStorage").Events.PlayerActivesCommand:FireServer(unpack(args))
                                            sprinklerPlaced = true
                                        end)
                                        firstCoord = false
                                    end
                                end
                            end
                        else
                            -- Original Fallback Logic
                            local fallbackPos = Vector3.new(-47064, 291.907898, -183.909866)
                            local distance = (fallbackPos - HumanoidRootPart.Position).Magnitude
                            if distance > 1 then
                                local speed = 69
                                local duration = distance / speed
                                local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)
                                local targetCFrame = CFrame.new(fallbackPos) * upRotation

                                if tick() < AutoSlime_blockUntil then
                                    task.wait()
                                else
                                    cancelActiveAutoSlime()
                                    local tween = TweenService:Create(HumanoidRootPart, tweenInfo, {CFrame = targetCFrame})
                                    local platTween = TweenService:Create(platform, tweenInfo, {CFrame = CFrame.new(fallbackPos - Vector3.new(0, 3, 0))})

                                    tween:Play()
                                    platTween:Play()
                                    AutoSlime_activeTween = tween
                                    AutoSlime_activePlatTween = platTween
                                    AutoSlime_activeConn = game:GetService("RunService").Heartbeat:Connect(function()
                                        if not Settings.AutoSlimeKill or not AutoSlime_activeTween or game.PlaceId ~= 17579225831 then 
                                            if AutoSlime_activeConn then AutoSlime_activeConn:Disconnect() AutoSlime_activeConn = nil end
                                            return 
                                        end
                                        HumanoidRootPart.AssemblyLinearVelocity = Vector3.zero
                                        HumanoidRootPart.AssemblyAngularVelocity = Vector3.zero
                                        if platform and platform:IsA("BasePart") then
                                            platform.AssemblyLinearVelocity = Vector3.zero
                                            platform.AssemblyAngularVelocity = Vector3.zero
                                        end
                                    end)

                                    tween.Completed:Wait()
                                    if AutoSlime_activeConn then AutoSlime_activeConn:Disconnect() AutoSlime_activeConn = nil end
                                    AutoSlime_activeTween = nil
                                    AutoSlime_activePlatTween = nil
                                end
                            else
                                HumanoidRootPart.CFrame = CFrame.new(fallbackPos) * upRotation
                                platform.CFrame = CFrame.new(fallbackPos - Vector3.new(0, 3, 0))
                            end
                        end
                    end
                else
                    -- Ziel-Slime gefunden: tween zum Slime (Y fixed to targetY)
                    local targetPos = TargetSlimeBlob.Position
                    local adjustedTarget = Vector3.new(targetPos.X, targetY, targetPos.Z)
                    local distance = (adjustedTarget - HumanoidRootPart.Position).Magnitude
                        if distance > 1 then
                        local speed = 69
                        local duration = distance / speed
                        local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)

                        local targetCFrame = CFrame.new(adjustedTarget) * upRotation
                        if tick() < AutoSlime_blockUntil then
                            task.wait()
                        else
                            cancelActiveAutoSlime()

                        -- Equip sword before tweening to monster
                        if Settings.AutoToolSwitch then
                            if hasIllumina and currentEquippedSword ~= "ClassicIllumina" and tick() - lastEquipTime > 0.5 then
                                EquipTool("ClassicIllumina")
                                task.wait(0.1)
                            elseif hasFirebrand and currentEquippedSword ~= "ClassicFirebrand" and tick() - lastEquipTime > 0.5 then
                                EquipTool("ClassicFirebrand")
                                task.wait(0.1)
                            elseif hasClassicSword and currentEquippedSword ~= "ClassicSword" and tick() - lastEquipTime > 0.5 then
                                EquipTool("ClassicSword")
                                task.wait(0.1)
                            end
                        end

                            local tween = TweenService:Create(HumanoidRootPart, tweenInfo, {CFrame = targetCFrame})
                            local platTween = TweenService:Create(platform, tweenInfo, {CFrame = CFrame.new(adjustedTarget - Vector3.new(0, 3, 0))})

                            tween:Play()
                            platTween:Play()
                            AutoSlime_activeTween = tween
                            AutoSlime_activePlatTween = platTween

                            AutoSlime_activeConn = game:GetService("RunService").Heartbeat:Connect(function()
                                if not Settings.AutoSlimeKill or not AutoSlime_activeTween or game.PlaceId ~= 17579225831 then 
                                    if AutoSlime_activeConn then AutoSlime_activeConn:Disconnect() AutoSlime_activeConn = nil end
                                    return 
                                end
                                HumanoidRootPart.AssemblyLinearVelocity = Vector3.zero
                                HumanoidRootPart.AssemblyAngularVelocity = Vector3.zero
                                if platform and platform:IsA("BasePart") then
                                    platform.AssemblyLinearVelocity = Vector3.zero
                                    platform.AssemblyAngularVelocity = Vector3.zero
                                end
                            end)

                            tween.Completed:Wait()
                            if AutoSlime_activeConn then AutoSlime_activeConn:Disconnect() AutoSlime_activeConn = nil end
                            AutoSlime_activeTween = nil
                            AutoSlime_activePlatTween = nil
                        end
                    else
                        if Settings.AutoToolSwitch then
                            if hasIllumina and currentEquippedSword ~= "ClassicIllumina" and tick() - lastEquipTime > 0.5 then
                                EquipTool("ClassicIllumina")
                            elseif hasFirebrand and currentEquippedSword ~= "ClassicFirebrand" and tick() - lastEquipTime > 0.5 then
                                EquipTool("ClassicFirebrand")
                            elseif hasClassicSword and currentEquippedSword ~= "ClassicSword" and tick() - lastEquipTime > 0.5 then
                                EquipTool("ClassicSword")
                            end
                        end
                        HumanoidRootPart.CFrame = CFrame.new(HumanoidRootPart.Position.X, targetY, HumanoidRootPart.Position.Z) * upRotation
                        platform.CFrame = CFrame.new(HumanoidRootPart.Position - Vector3.new(0, 3, 0))
                    end
                end
            end
        else
            if lastToggleState then
                lastToggleState = false
                collectingTokensNow = false
                sprinklerPlaced = false
                lastBloom = nil
                -- Cancel any active tweens/handlers
                cancelActiveAutoSlime()
                if platform then platform:Destroy() platform = nil end
                -- ClassicBaseplate Collision wieder anschalten
                pcall(function()
                    local classicBaseplate = workspace.ClassicMinigame.ClassicBaseplate
                    if classicBaseplate then
                        classicBaseplate.CanCollide = true
                    end
                end)
                pcall(function()
                    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
                        LocalPlayer.Character.Humanoid.PlatformStand = false
                        -- Sicherstellen, dass die Physik wieder aktiviert ist
                        LocalPlayer.Character.HumanoidRootPart.AssemblyLinearVelocity = Vector3.zero
                        LocalPlayer.Character.HumanoidRootPart.AssemblyAngularVelocity = Vector3.zero
                    end
                end)
            end
        end
        task.wait()
    end
end)

-- Loop 7: AutoUpgrade
task.spawn(function()
    local isAutoUpgradeRunning = false

    local function getBricks()
        return CurrentBricks
    end

    local function handleButton(button, cost, name, isBee, maxWait)
        local character = LocalPlayer.Character
        if not character or not character:FindFirstChild("HumanoidRootPart") then 
            return false 
        end
        local hrp = character.HumanoidRootPart
        local bricks = getBricks()

        -- Wenn maxWait == nil: warte unbegrenzt bis genug Bricks vorhanden sind (solange AutoUpgrade und ScriptRunning true)
        if maxWait == nil then
            while bricks < cost and Settings.AutoUpgrade and ScriptRunning do
                task.wait(1)
                bricks = getBricks()
            end
        elseif maxWait > 0 then
            local waited = 0
            while bricks < cost and waited < maxWait and Settings.AutoUpgrade and ScriptRunning do
                task.wait(1)
                waited = waited + 1
                bricks = getBricks()
            end
        end

        if bricks >= cost then
            local oldCFrame = button.CFrame
            button.CanCollide = false
            button.CFrame = hrp.CFrame
            task.wait(0.5)
            button.CFrame = oldCFrame * CFrame.new(0, 50, 0)
            
            if isBee then
                task.wait(1) -- Wait for UI to potentially appear
                for i = 1, 3 do -- Try up to 3 times
                    local success, err = pcall(function()
                        local screenGui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("ScreenGui")
                        local miscPopUp = screenGui and screenGui:FindFirstChild("MiscPopUpFrame")
                        local beeSelect = miscPopUp and miscPopUp:FindFirstChild("BeeSelectScreen")
                        
                        if beeSelect and beeSelect.Visible then
                            firesignal(beeSelect.Frame.Choice2.Button.MouseButton1Click)
                            return true
                        end
                        return false
                    end)
                    if success and err then
                        break -- Signal fired successfully, exit loop
                    else
                        task.wait(0.5) -- Wait a bit before retrying
                    end
                end
            end
            
            task.wait(5)
            return true
        else
            return false
        end
    end

    while ScriptRunning do
        if Settings.AutoUpgrade and game.PlaceId == 17579225831 and not AutoUpgrade_hasRun then
            if not isAutoUpgradeRunning then
                isAutoUpgradeRunning = true

                task.wait(12)

                pcall(function()
                    local tycoonButtons = workspace:FindFirstChild("ClassicMinigame") and workspace.ClassicMinigame:FindFirstChild("TycoonButtons")
                    if tycoonButtons then
                        -- 1. Sword
                        local swordBtnFolder = tycoonButtons:FindFirstChild("Buy Classic Sword")
                        local swordBtn = swordBtnFolder and swordBtnFolder:FindFirstChild("Button")
                        if swordBtn then
                            local bought = handleButton(swordBtn, 10, "Classic Sword", false)
                            if not bought then 
                                isAutoUpgradeRunning = false
                                return 
                            end
                        else
                            print("not found")
                        end

                        -- 2. Bee Upgrades (First 3)
                        local beeUpgrades = {
                            {name = "Unlock Bees Button", cost = 5},
                            {name = "Unlock Bees Button", cost = 15},
                            {name = "Unlock Bees Button", cost = 30}
                        }

                        for _, upgrade in ipairs(beeUpgrades) do
                            if not Settings.AutoUpgrade then break end
                            local beeBtnFolder = tycoonButtons:FindFirstChild(upgrade.name)
                            local beeBtn = beeBtnFolder and beeBtnFolder:FindFirstChild("Button")
                            
                            if beeBtn then
                                local bought = handleButton(beeBtn, upgrade.cost, upgrade.name, true)
                                if not bought then 
                                    isAutoUpgradeRunning = false
                                    return 
                                end
                                task.wait(1) -- Extra wait after each bee purchase to avoid UI spam/overlap
                            else
                                print("not found")
                            end
                        end

                        -- 3. Firebrand (300 bricks)
                        local firebrandBtnFolder = tycoonButtons:FindFirstChild("Buy Firebrand")
                        local firebrandBtn = firebrandBtnFolder and firebrandBtnFolder:FindFirstChild("Button")
                        if firebrandBtn then
                            -- Warte unbegrenzt bis genug Bricks für Firebrand vorhanden sind
                            local bought = handleButton(firebrandBtn, 300, "Firebrand", false)
                            if not bought then
                                isAutoUpgradeRunning = false
                                return
                            end
                        else
                            print("not found")
                        end

                        -- 4. 4th Bee (40 bricks)
                        local fourthBeeBtnFolder = tycoonButtons:FindFirstChild("Unlock Bees Button")
                        local fourthBeeBtn = fourthBeeBtnFolder and fourthBeeBtnFolder:FindFirstChild("Button")
                        if fourthBeeBtn then
                            local bought = handleButton(fourthBeeBtn, 40, "Unlock Bees Button (4th)", true)
                            if not bought then
                                isAutoUpgradeRunning = false
                                return
                            end
                        else
                            print("not found")
                        end

                        -- 5. Bee (55 bricks)
                        local beeBtnFolder = tycoonButtons:FindFirstChild("Unlock Bees Button")
                        local beeBtn = beeBtnFolder and beeBtnFolder:FindFirstChild("Button")
                        if beeBtn then
                            local bought = handleButton(beeBtn, 55, "Bee", true)
                            if not bought then
                                isAutoUpgradeRunning = false
                                return
                            end
                        end

                        -- 6. Bloxiade (100 bricks)
                        local bloxiadeBtnFolder = tycoonButtons:FindFirstChild("Buy Bloxiade") or tycoonButtons:FindFirstChild("Buy Bloxiade Button")
                        local bloxiadeBtn = bloxiadeBtnFolder and bloxiadeBtnFolder:FindFirstChild("Button")
                        if bloxiadeBtn then
                            local bought = handleButton(bloxiadeBtn, 100, "Bloxiade", false)
                            if not bought then
                                isAutoUpgradeRunning = false
                                return
                            end
                        end

                        -- 7. Illumina (1500 bricks)
                        local illuminaBtnFolder = tycoonButtons:FindFirstChild("Buy Illumina") or tycoonButtons:FindFirstChild("Buy Illumina Button")
                        local illuminaBtn = illuminaBtnFolder and illuminaBtnFolder:FindFirstChild("Button")
                        if illuminaBtn then
                            local bought = handleButton(illuminaBtn, 1500, "Illumina", false)
                            if not bought then
                                isAutoUpgradeRunning = false
                                return
                            end
                        else
                            -- Try searching by name if direct child not found
                            for _, v in pairs(tycoonButtons:GetChildren()) do
                                if v.Name:find("Illumina") then
                                    local b = v:FindFirstChild("Button")
                                    if b then
                                        handleButton(b, 1500, "Illumina", false)
                                        break
                                    end
                                end
                            end
                        end

                        -- 8. Bloxy Cola (200 bricks)
                        local colaBtnFolder = tycoonButtons:FindFirstChild("Buy Bloxy Cola") or tycoonButtons:FindFirstChild("Buy Bloxy Cola Button")
                        local colaBtn = colaBtnFolder and colaBtnFolder:FindFirstChild("Button")
                        if colaBtn then
                            local bought = handleButton(colaBtn, 200, "Bloxy Cola", false)
                            if not bought then
                                isAutoUpgradeRunning = false
                                return
                            end
                        end

                        -- 9. Chez Burger (300 bricks)
                        local burgerBtnFolder = tycoonButtons:FindFirstChild("Buy Chez Burger") or tycoonButtons:FindFirstChild("Buy Chez Burger Button")
                        local burgerBtn = burgerBtnFolder and burgerBtnFolder:FindFirstChild("Button")
                        if burgerBtn then
                            local bought = handleButton(burgerBtn, 300, "Chez Burger", false)
                            if not bought then
                                isAutoUpgradeRunning = false
                                return
                            end
                        end

                        -- 10. Pizza (500 bricks)
                        local pizzaBtnFolder = tycoonButtons:FindFirstChild("Buy Pizza") or tycoonButtons:FindFirstChild("Buy Pizza Button")
                        local pizzaBtn = pizzaBtnFolder and pizzaBtnFolder:FindFirstChild("Button")
                        if pizzaBtn then
                            local bought = handleButton(pizzaBtn, 500, "Pizza", false)
                            if not bought then
                                isAutoUpgradeRunning = false
                                return
                            end
                        end

                        -- 11. Continuous Bee purchases every 30 seconds
                        while Settings.AutoUpgrade and ScriptRunning do
                            local beeBtnFolder = tycoonButtons:FindFirstChild("Unlock Bees Button")
                            local beeBtn = beeBtnFolder and beeBtnFolder:FindFirstChild("Button")
                            if beeBtn and getBricks() >= 55 then
                                local oldCFrame = beeBtn.CFrame
                                beeBtn.CanCollide = false
                                beeBtn.CFrame = LocalPlayer.Character.HumanoidRootPart.CFrame
                                task.wait(0.5)
                                beeBtn.CFrame = oldCFrame * CFrame.new(0, 50, 0)
                                task.wait(1)
                                
                                -- Select bee
                                for i = 1, 3 do
                                    local success, err = pcall(function()
                                        local screenGui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("ScreenGui")
                                        local miscPopUp = screenGui and screenGui:FindFirstChild("MiscPopUpFrame")
                                        local beeSelect = miscPopUp and miscPopUp:FindFirstChild("BeeSelectScreen")
                                        if beeSelect and beeSelect.Visible then
                                            firesignal(beeSelect.Frame.Choice2.Button.MouseButton1Click)
                                            return true
                                        end
                                        return false
                                    end)
                                    if success and err then break end
                                    task.wait(0.5)
                                end
                            end
                            task.wait(30)
                        end
                    else
                        print("folder not found")
                    end
                end)

                -- After completing the cycle, mark AutoUpgrade as having run
                -- so it won't run again until the user toggles it off and back on.
                AutoUpgrade_hasRun = true
                isAutoUpgradeRunning = false
            end
        else
            isAutoUpgradeRunning = false
            if not Settings.AutoUpgrade then
                AutoUpgrade_hasRun = false
            end
        end
        task.wait(1)
    end
end)

-- Loop 8: AutoBuyBricks (6s)
task.spawn(function()
    while ScriptRunning do
        if Settings.AutoBuyBricks and game.PlaceId == 17579225831 then
            pcall(function()
                local character = LocalPlayer.Character
                if character and character:FindFirstChild("HumanoidRootPart") then
                    local hrp = character.HumanoidRootPart
                    local button = workspace.ClassicMinigame.TycoonButtons["Buy 10 Bricks Button"].Button
                    
                    if button then
                        local oldCFrame = button.CFrame
                        button.CanCollide = false
                        button.CFrame = hrp.CFrame
                        task.wait(0.5)
                        button.CFrame = oldCFrame * CFrame.new(0, 50, 0)
                    end
                end
            end)
            task.wait(6)
        else
            task.wait(1)
        end
    end
end)

-- Loop 9: KillAura Visuals
task.spawn(function()
    local visualPart = nil
    local ringStroke = nil
    local countGui = nil
    local countLabel = nil
    local activeMarkers = {}
    local visualConn = nil

    local function cleanup()
        if visualConn then visualConn:Disconnect() visualConn = nil end
        if visualPart then visualPart:Destroy() visualPart = nil end
        if countGui then countGui:Destroy() countGui = nil end
        for monster, marker in pairs(activeMarkers) do
            if marker then pcall(function() marker:Destroy() end) end
        end
        activeMarkers = {}
    end

    while ScriptRunning do
        if Settings.KillAuraVisual and game.PlaceId == 17579225831 then
            local character = LocalPlayer.Character
            local hrp = character and character:FindFirstChild("HumanoidRootPart")

            if hrp then
                -- Visual Part & Ring setup
                if not visualPart or not visualPart.Parent then
                    visualPart = Instance.new("Part")
                    visualPart.Name = "KillAuraVisualPart"
                    visualPart.Anchored = true
                    visualPart.CanCollide = false
                    visualPart.CanTouch = false
                    visualPart.CanQuery = false
                    visualPart.Transparency = 1
                    visualPart.Size = Vector3.new(1, 0.1, 1)
                    visualPart.Parent = workspace

                    local sg = Instance.new("SurfaceGui")
                    sg.Face = Enum.NormalId.Top
                    sg.AlwaysOnTop = false
                    sg.Parent = visualPart

                    local frame = Instance.new("Frame")
                    frame.Size = UDim2.new(1, 0, 1, 0)
                    frame.BackgroundTransparency = 1
                    frame.Parent = sg

                    local corner = Instance.new("UICorner")
                    corner.CornerRadius = UDim.new(1, 0)
                    corner.Parent = frame

                    ringStroke = Instance.new("UIStroke")
                    ringStroke.Thickness = 3
                    ringStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
                    ringStroke.Color = Color3.fromRGB(0, 255, 0)
                    ringStroke.Parent = frame
                end

                -- Update Visual Part Position & Size (Stay flat on ground or at fixed height)
                local currentRange = Settings.KillAuraRange
                visualPart.Size = Vector3.new(currentRange * 2, 0.1, currentRange * 2)
                
                if not visualConn then
                    visualConn = game:GetService("RunService").Heartbeat:Connect(function()
                        if visualPart and visualPart.Parent and hrp and hrp.Parent then
                            visualPart.CFrame = CFrame.new(hrp.Position.X, 292, hrp.Position.Z)
                        end
                    end)
                end

                -- GUI setup
                if not countGui or countGui.Parent ~= hrp then
                    if countGui then countGui:Destroy() end
                    countGui = Instance.new("BillboardGui")
                    countGui.Name = "KillAuraCount"
                    countGui.Size = UDim2.new(0, 100, 0, 50)
                    countGui.StudsOffset = Vector3.new(0, 2, 0)
                    countGui.AlwaysOnTop = true
                    countGui.Adornee = visualPart
                    
                    countLabel = Instance.new("TextLabel")
                    countLabel.Size = UDim2.new(1, 0, 1, 0)
                    countLabel.BackgroundTransparency = 1
                    countLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
                    countLabel.TextStrokeTransparency = 0
                    countLabel.TextSize = 20
                    countLabel.Font = Enum.Font.SourceSansBold
                    countLabel.Parent = countGui
                    
                    countGui.Parent = hrp
                end

                -- Counting enemies (Skip update while executing to preserve markers)
                local enemyCount = 0
                local currentEnemies = {}
                if not KillAura_isExecuting then
                    if workspace:FindFirstChild("Monsters") then
                        for _, monsterFolder in pairs(workspace.Monsters:GetChildren()) do
                            local folderName = tostring(monsterFolder.Name)
                            local isSlime = folderName:match("^Slime")
                            local slimeLvl = isSlime and tonumber(folderName:match("Lvl%s+(%d+)"))
                            if (folderName:match("^Zombie") or isSlime) and (not slimeLvl or slimeLvl < 22) then
                                for _, desc in pairs(monsterFolder:GetDescendants()) do
                                    if desc:IsA("BasePart") and (desc.Name == "Torso" or desc.Name == "Blob2") then
                                        local dist = (desc.Position - hrp.Position).Magnitude
                                        if dist <= currentRange then
                                            enemyCount = enemyCount + 1
                                            local monster = monsterFolder
                                            currentEnemies[monster] = true
                                            
                                            if not activeMarkers[monster] then
                                                pcall(function()
                                                    local h = Instance.new("Highlight")
                                                    h.Name = "KillAuraHighlight"
                                                    h.FillColor = Color3.fromRGB(255, 0, 0)
                                                    h.OutlineColor = Color3.fromRGB(255, 255, 255)
                                                    h.FillTransparency = 0.4
                                                    h.OutlineTransparency = 0
                                                    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                                                    h.Adornee = desc
                                                    h.Parent = monster
                                                    activeMarkers[monster] = h
                                                end)
                                            end
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end

                    -- Remove markers for enemies no longer in range
                    for monster, marker in pairs(activeMarkers) do
                        if not currentEnemies[monster] or not monster.Parent then
                            if marker then pcall(function() marker:Destroy() end) end
                            activeMarkers[monster] = nil
                        end
                    end
                else
                    -- While executing, just count remaining marked enemies for the UI
                    for monster, marker in pairs(activeMarkers) do
                        if marker and monster.Parent then
                            enemyCount = enemyCount + 1
                        end
                    end
                end

                local trigger = Settings.KillAuraTrigger
                countLabel.Text = string.format("gegnär: %d/%d", enemyCount, trigger)

                if enemyCount >= trigger then
                    ringStroke.Color = Color3.fromRGB(255, 0, 0)
                    countLabel.TextColor3 = Color3.fromRGB(255, 100, 100)

                    -- EXECUTION LOGIC
                    if tick() - KillAura_lastExecution > Settings.KillAuraCooldown and not KillAura_isExecuting then
                        local TweenService = game:GetService("TweenService")
                        local targetY = 283
                        local upRotation = CFrame.Angles(math.rad(90), 0, 0)

                        -- Ensure platform exists BEFORE interrupting
                        local ka_platform = workspace:FindFirstChild("SlimeKillPlatform")
                        if not ka_platform or not ka_platform.Parent then
                            ka_platform = Instance.new("Part")
                            ka_platform.Size = Vector3.new(100, 1, 100)
                            ka_platform.Anchored = true
                            ka_platform.Transparency = 1
                            ka_platform.CanCollide = true
                            ka_platform.Name = "SlimeKillPlatform"
                            ka_platform.Parent = workspace
                        end

                        -- Secure position immediately
                        KillAura_isExecuting = true
                        cancelActiveAutoSlime()
                        
                        pcall(function()
                            -- Lock height and snap platform
                            hrp.CFrame = CFrame.new(hrp.Position.X, targetY, hrp.Position.Z) * upRotation
                            ka_platform.CFrame = hrp.CFrame - Vector3.new(0, 3, 0)
                            ka_platform.CanCollide = true
                            hrp.AssemblyLinearVelocity = Vector3.zero
                            hrp.AssemblyAngularVelocity = Vector3.zero
                        end)

                        -- Keep track of enemies to hit (ensure they are still valid)
                        local enemiesToHit = {}
                        for monster, _ in pairs(currentEnemies) do
                            if monster and monster.Parent then
                                table.insert(enemiesToHit, monster)
                            end
                        end

                        -- Heartbeat connection for the whole session to prevent falling and movement
                        local ka_conn = game:GetService("RunService").Heartbeat:Connect(function()
                            if hrp and hrp.Parent then
                                hrp.AssemblyLinearVelocity = Vector3.zero
                                hrp.AssemblyAngularVelocity = Vector3.zero
                                -- Ensure height stays locked even if tween is not running
                                hrp.CFrame = CFrame.new(hrp.Position.X, targetY, hrp.Position.Z) * upRotation
                            end
                            if ka_platform and ka_platform.Parent then
                                ka_platform.AssemblyLinearVelocity = Vector3.zero
                                ka_platform.AssemblyAngularVelocity = Vector3.zero
                            end
                            pcall(function()
                                if character and character:FindFirstChildOfClass("Humanoid") then
                                    character:FindFirstChildOfClass("Humanoid").PlatformStand = true
                                end
                            end)
                        end)

                        -- Give a small moment for AutoSlimeKill to fully yield
                        task.wait(0.1)

                        for i, monster in ipairs(enemiesToHit) do
                            if not ScriptRunning or not Settings.KillAuraVisual then
                                break
                            end
                            
                            local targetPart = nil
                            pcall(function()
                                if monster and monster.Parent then
                                    targetPart = monster:FindFirstChild("Torso") or monster:FindFirstChild("Blob2") or monster:FindFirstChildWhichIsA("BasePart")
                                end
                            end)

                            if targetPart then
                                local targetPos = targetPart.Position
                                local adjustedTarget = Vector3.new(targetPos.X, targetY, targetPos.Z)
                                
                                -- Use current position for distance
                                local currentHRPPos = hrp.Position
                                local dist = (adjustedTarget - currentHRPPos).Magnitude
                                local speed = 120
                                local duration = math.max(0.05, dist / speed)

                                print(" " .. i .. "/" .. #enemiesToHit .. " " .. math.floor(dist) .. ")")

                                -- Equip sword if tool switch is on
                                if Settings.AutoToolSwitch then
                                    if hasIllumina and currentEquippedSword ~= "ClassicIllumina" then
                                        EquipTool("ClassicIllumina")
                                    elseif hasFirebrand and currentEquippedSword ~= "ClassicFirebrand" then
                                        EquipTool("ClassicFirebrand")
                                    elseif hasClassicSword and currentEquippedSword ~= "ClassicSword" then
                                        EquipTool("ClassicSword")
                                    end
                                end

                                local tween = TweenService:Create(hrp, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame = CFrame.new(adjustedTarget) * upRotation})
                                local platTween = TweenService:Create(ka_platform, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame = CFrame.new(adjustedTarget - Vector3.new(0, 3, 0))})
                                
                                tween:Play()
                                platTween:Play()
                                
                                -- Wait for tween to finish
                                local completed = false
                                local conn = nil
                                conn = tween.Completed:Connect(function()
                                    completed = true
                                    if conn then conn:Disconnect() end
                                end)
                                
                                -- Heartbeat-like lock during this specific tween
                                local startTween = tick()
                                while not completed and ScriptRunning and (tick() - startTween < duration + 0.5) do
                                    -- Velocity lock is already in the outer heartbeat
                                    task.wait()
                                end
                                if conn then conn:Disconnect() end
                                
                                -- Mark as hit visually
                                if activeMarkers[monster] then
                                    pcall(function()
                                        activeMarkers[monster].FillColor = Color3.fromRGB(0, 255, 0)
                                        activeMarkers[monster].FillTransparency = 0.5
                                    end)
                                end
                            end
                        end
                        task.wait(0.2)
                        
                        -- Clear markers
                        for monster, marker in pairs(activeMarkers) do
                            if marker then pcall(function() marker:Destroy() end) end
                        end
                        activeMarkers = {}

                        if ka_conn then ka_conn:Disconnect() end
                        KillAura_lastExecution = tick()
                        KillAura_isExecuting = false
                        UpdateBar("KillAura", Settings.KillAuraCooldown)
                    end
                else
                    ringStroke.Color = Color3.fromRGB(0, 255, 0)
                    countLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
                end
            else
                cleanup()
            end
        else
            cleanup()
        end
        task.wait()
    end
    cleanup()
end)

-- Loop 10: Camera Settings Persistence
task.spawn(function()
    while ScriptRunning do
        pcall(function()
            LocalPlayer.CameraMaxZoomDistance = Settings.CameraMaxZoomDistance
            if workspace.CurrentCamera then
                workspace.CurrentCamera.MaxAxisFieldOfView = Settings.MaxAxisFieldOfView
            end
        end)
        task.wait(1)
    end
end)
