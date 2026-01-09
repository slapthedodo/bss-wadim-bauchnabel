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
    InterruptAutoSlime = false
}

-- Active tween handles for AutoSlimeKill (accessible globally so UI can interrupt)
local AutoSlime_activeTween = nil
local AutoSlime_activePlatTween = nil
local AutoSlime_activeConn = nil
local AutoSlime_blockUntil = 0

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
        AutoSlime_blockUntil = tick() + 0.2
    end)
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
    Snowflake = CreateCooldownBar("Snowflake", Color3.fromRGB(0, 255, 255))
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
        end
    end
end

-- Config laden
LoadConfig()

-- Laufend die aktuelle Brick-Anzahl pollen (keine Logs)
local CurrentBricks = 0
task.spawn(function()
    while ScriptRunning do
        pcall(function()
            local screenGui = LocalPlayer.PlayerGui:FindFirstChild("ScreenGui")
            local brickLabel = screenGui and screenGui:FindFirstChild("UnderPopUpFrame")
                and screenGui.UnderPopUpFrame:FindFirstChild("RetroGuiTopMenu")
                and screenGui.UnderPopUpFrame.RetroGuiTopMenu:FindFirstChild("TopMenuFrame2")
                and screenGui.UnderPopUpFrame.RetroGuiTopMenu.TopMenuFrame2:FindFirstChild("BrickLabel")
            CurrentBricks = tonumber(brickLabel and brickLabel.Text) or 0
        end)
        task.wait(1)
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
        local duration = distance / 70
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
        
        print("Script unloaded successfully.")
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
                    print("Starte Auto Claim Hive (10, 9, 8, 7)...")
                    local claimValues = {9, 9}
                    
                    for _, value in ipairs(claimValues) do
                        pcall(function()
                            ReplicatedStorage.Events.ClaimHive:FireServer(value)
                            print("ClaimHive " .. value)
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

    while ScriptRunning do
        if Settings.AutoSlimeKill and game.PlaceId == 17579225831 then
            if not lastToggleState then
                lastToggleState = true
                collectingTokensNow = false
                -- ClassicBaseplate Collision ausschalten
                pcall(function()
                    local classicBaseplate = workspace.ClassicMinigame.ClassicBaseplate
                    if classicBaseplate then
                        classicBaseplate.CanCollide = false
                    end
                end)
                
                -- 10 Sekunden warten beim ersten Einschalten
                task.wait(10)
            end

            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and LocalPlayer.Character:FindFirstChild("Humanoid") then
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
                        if folderName:match("^Zombie") or folderName:match("^Slime") then
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
                                        end
                                    end
                                end
                            end
                        end
                    end
                end

                -- Wenn kein Slime gefunden: Sammle Collectibles 'C' ohne zurückzufliegen
                if not TargetSlimeBlob and not collectingTokensNow then
                    collectingTokensNow = true
                    local collectingTokens = true
                    local visitedCollects = {}
                    while collectingTokens and Settings.AutoSlimeKill and game.PlaceId == 17579225831 do
                        -- Prüfe nochmal auf neue Slimes (Priorität)
                        local CheckSlimeBlob = nil
                        local checkZDiff = math.huge
                        local checkTie = math.huge
                        if workspace:FindFirstChild("Monsters") then
                                for _, monsterFolder in pairs(workspace.Monsters:GetChildren()) do
                                    local folderName = tostring(monsterFolder.Name)
                                    -- Match any Zombie or Slime regardless of level
                                    if folderName:match("^Zombie") or folderName:match("^Slime") then
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
                        
                        if CheckSlimeBlob then
                            -- Slime gefunden, raus aus Token-Loop
                            TargetSlimeBlob = CheckSlimeBlob
                            collectingTokens = false
                            collectingTokensNow = false
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
                        pcall(function()
                            if workspace:FindFirstChild("Collectibles") then
                                for _, c in pairs(workspace.Collectibles:GetChildren()) do
                                    if c and c:IsA("BasePart") and c.Name == "C" and c.Parent and not visitedCollects[c] then
                                        local d = (c.Position - HumanoidRootPart.Position).Magnitude
                                        if d <= 400 and d < nextCollectDist then
                                            nextCollectDist = d
                                            nextCollect = c
                                        end
                                    end
                                end
                            end
                        end)

                        if nextCollect then
                            -- Markiere als besucht sofort, damit wir das Token nicht erneut targetten
                            visitedCollects[nextCollect] = tick()

                            -- Tween direkt zur Token-Position
                            local collectPos = nextCollect.Position
                            local collectTarget = Vector3.new(collectPos.X, collectPos.Y, collectPos.Z)
                            local dist = (collectTarget - HumanoidRootPart.Position).Magnitude
                            local speed = 69
                            local duration = math.max(0.05, dist / speed)

                            local targetCFrame = CFrame.new(collectTarget) * upRotation
                            if tick() < AutoSlime_blockUntil then
                                task.wait(0.15)
                            else
                                cancelActiveAutoSlime()
                                local tween = TweenService:Create(HumanoidRootPart, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame = targetCFrame})
                                local platTween = TweenService:Create(platform, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame = CFrame.new(collectTarget - Vector3.new(0, 3, 0))})
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

                            -- Berühre Token mit firetouchinterest für ~150ms
                            pcall(function()
                                local hrp = HumanoidRootPart
                                if nextCollect and hrp and nextCollect:IsA("BasePart") and nextCollect.Parent then
                                    firetouchinterest(nextCollect, hrp, 0)
                                    firetouchinterest(nextCollect, hrp, 1)
                                end
                            end)
                            task.wait(0.12)
                        else
                            -- Keine Token mehr gefunden, beende Loop
                            collectingTokens = false
                            collectingTokensNow = false
                        end
                    end

                    -- Nach Token-Sammeln: Falls keine Slimes gefunden, gehe zur Fallback Position
                    if not TargetSlimeBlob then
                        local fallbackPos = Vector3.new(-47064, 291.907898, -183.909866)
                        local distance = (fallbackPos - HumanoidRootPart.Position).Magnitude
                        if distance > 1 then
                            local speed = 69
                            local duration = distance / speed
                            local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)
                            local targetCFrame = CFrame.new(fallbackPos) * upRotation

                            if tick() < AutoSlime_blockUntil then
                                task.wait(0.2)
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
                            task.wait(0.2)
                        else
                            cancelActiveAutoSlime()
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
                        HumanoidRootPart.CFrame = CFrame.new(HumanoidRootPart.Position.X, targetY, HumanoidRootPart.Position.Z) * upRotation
                        platform.CFrame = CFrame.new(HumanoidRootPart.Position - Vector3.new(0, 3, 0))
                    end
                end
            end
        else
            if lastToggleState then
                lastToggleState = false
                collectingTokensNow = false
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
                            print("[DEBUG] Sword button not found!")
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
                                print("[DEBUG] Unlock Bees Button not found!")
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
                            print("[DEBUG] Buy Firebrand button not found!")
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
                            print("[DEBUG] 4th Bee button not found!")
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
                        local bloxiadeBtnFolder = tycoonButtons:FindFirstChild("Buy Bloxiade")
                        local bloxiadeBtn = bloxiadeBtnFolder and bloxiadeBtnFolder:FindFirstChild("Button")
                        if bloxiadeBtn then
                            local bought = handleButton(bloxiadeBtn, 100, "Bloxiade", false)
                            if not bought then
                                isAutoUpgradeRunning = false
                                return
                            end
                        end

                        -- 7. Illumina (1500 bricks)
                        local illuminaBtnFolder = tycoonButtons:FindFirstChild("Buy Illumina")
                        local illuminaBtn = illuminaBtnFolder and illuminaBtn:FindFirstChild("Button")
                        if illuminaBtn then
                            local bought = handleButton(illuminaBtn, 1500, "Illumina", false)
                            if not bought then
                                isAutoUpgradeRunning = false
                                return
                            end
                        end

                        -- 8. Bloxy Cola (200 bricks)
                        local colaBtnFolder = tycoonButtons:FindFirstChild("Buy Bloxy Cola")
                        local colaBtn = colaBtnFolder and colaBtnFolder:FindFirstChild("Button")
                        if colaBtn then
                            local bought = handleButton(colaBtn, 200, "Bloxy Cola", false)
                            if not bought then
                                isAutoUpgradeRunning = false
                                return
                            end
                        end

                        -- 9. Chez Burger (300 bricks)
                        local burgerBtnFolder = tycoonButtons:FindFirstChild("Buy Chez Burger")
                        local burgerBtn = burgerBtnFolder and burgerBtnFolder:FindFirstChild("Button")
                        if burgerBtn then
                            local bought = handleButton(burgerBtn, 300, "Chez Burger", false)
                            if not bought then
                                isAutoUpgradeRunning = false
                                return
                            end
                        end

                        -- 10. Pizza (500 bricks)
                        local pizzaBtnFolder = tycoonButtons:FindFirstChild("Buy Pizza")
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
                        print("[DEBUG] TycoonButtons folder not found!")
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

-- Loop 8: AutoBuyBricks (15s)
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
            task.wait(15)
        else
            task.wait(1)
        end
    end
end)
