-- Dienste
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local TeleportService = game:GetService("TeleportService")

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
    AutoretroLobby = false,
    retroWalkspeed = false,
    AutoClaimHive = false,
    AutoHit = false,
    AutoSlimeKill = false,
    AutoUpgrade = false,
    InterruptAutoSlime = false
}

-- Active tween handles for AutoSlimeKill (accessible globally so UI can interrupt)
local AutoSlime_activeTween = nil
local AutoSlime_activePlatTween = nil
local AutoSlime_activeConn = nil
local AutoSlime_blockUntil = 0

-- Helper to cancel any active AutoSlime tweens/connections
local function cancelActiveAutoSlime()
    pcall(function()
        -- cancel inner-loop handles if present
        if AutoSlime_activeConn then AutoSlime_activeConn:Disconnect() AutoSlime_activeConn = nil end
        if AutoSlime_activeTween then pcall(function() AutoSlime_activeTween:Cancel() end) AutoSlime_activeTween = nil end
        if AutoSlime_activePlatTween then pcall(function() AutoSlime_activePlatTween:Cancel() end) AutoSlime_activePlatTween = nil end
        -- set a short block to prevent immediate restart
        AutoSlime_blockUntil = tick() + 0.8
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
            if result.AutoretroLobby ~= nil then Settings.AutoretroLobby = result.AutoretroLobby end
            if result.retroWalkspeed ~= nil then Settings.retroWalkspeed = result.retroWalkspeed end
            if result.AutoClaimHive ~= nil then Settings.AutoClaimHive = result.AutoClaimHive end
            if result.AutoHit ~= nil then Settings.AutoHit = result.AutoHit end
            if result.AutoSlimeKill ~= nil then Settings.AutoSlimeKill = result.AutoSlimeKill end
            if result.AutoUpgrade ~= nil then Settings.AutoUpgrade = result.AutoUpgrade end
        end
    end
end

-- Config laden
LoadConfig()

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
        if Value then
            Settings.AutoretroLobby = false
            -- Hier könnte man das UI-Element für AutoretroLobby updaten, falls Rayfield das unterstützt
        end
        SaveConfig()
    end,
})

retroTab:CreateToggle({
    Name = "auto teleport retro lobby",
    CurrentValue = Settings.AutoretroLobby,
    Flag = "AutoretroLobby",
    Callback = function(Value)
        Settings.AutoretroLobby = Value
        if Value then
            Settings.Autoretro = false
        end
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
    Name = "Auto Claim Hive",
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
    Name = "Auto Slime Kill",
    CurrentValue = Settings.AutoSlimeKill,
    Flag = "AutoSlimeKill",
    Callback = function(Value)
        Settings.AutoSlimeKill = Value
        SaveConfig()
    end,
})

retroTab:CreateToggle({
    Name = "Auto Upgrade",
    CurrentValue = Settings.AutoUpgrade,
    Flag = "AutoUpgrade",
    Callback = function(Value)
        Settings.AutoUpgrade = Value
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

-- Loop 3: Auto Teleport (10s)
task.spawn(function()
    while ScriptRunning do
        if game.PlaceId == 1537690962 then
            if Settings.Autoretro then
                TeleportService:Teleport(17579225831, LocalPlayer)
            elseif Settings.AutoretroLobby then
                TeleportService:Teleport(17579226768, LocalPlayer)
            end
        end
        task.wait(10)
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
                            print("ClaimHive " .. value .. " gesendet.")
                        end)
                        task.wait(1)
                    end
                    print("Auto Claim Hive Durchlauf beendet.")
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

-- Loop 6: AutoHit (0.1s)
task.spawn(function()
    while ScriptRunning do
        if Settings.AutoHit and game.PlaceId == 17579225831 then
            pcall(function()
                local character = LocalPlayer.Character
                if character then
                    local classicSword = character:FindFirstChild("ClassicSword")
                    if classicSword then
                        local handle = classicSword:FindFirstChild("Handle")
                        if handle then
                            firetouchinterest(handle, character, 0)
                            firetouchinterest(handle, character, 1)
                        end
                    end
                end
            end)
        end
        task.wait(0.1)
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
                
                -- Zu Startposition gehen
                if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                    local HumanoidRootPart = LocalPlayer.Character.HumanoidRootPart
                    local startPos = Vector3.new(-47190.1133, 290.470581, 186.999374)
                    local distance = (startPos - HumanoidRootPart.Position).Magnitude
                    local speed = 69
                    local duration = distance / speed
                    local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)
                    
                    if tick() < AutoSlime_blockUntil then
                        task.wait(0.2)
                    else
                        -- cancel any previously exported tweens
                        cancelActiveAutoSlime()
                        local tween = TweenService:Create(HumanoidRootPart, tweenInfo, {CFrame = CFrame.new(startPos)})
                        tween:Play()
                        AutoSlime_activeTween = tween
                        tween.Completed:Wait()
                        AutoSlime_activeTween = nil
                    end
                end
                
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
                local targetY = 280

                -- Slime finden: prüfe alle Blob*-Parts unter allen SlimeMonstern.
                -- Priorität: kleinstes |Z-230|, Tie-Breaker: geringster horizontaler Abstand (X,Z) zur Z=230-Ebene in Relation zum Spieler
                local TargetSlimeBlob = nil
                local bestZDiff = math.huge
                local bestTie = math.huge

                if workspace:FindFirstChild("Monsters") then
                    for _, monsterFolder in pairs(workspace.Monsters:GetChildren()) do
                        local slimeMonster = monsterFolder:FindFirstChild("SlimeMonster")
                        if slimeMonster then
                            for _, desc in pairs(slimeMonster:GetDescendants()) do
                                if desc:IsA("BasePart") and tostring(desc.Name):match("^Blob") then
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
                                local slimeMonster = monsterFolder:FindFirstChild("SlimeMonster")
                                if slimeMonster then
                                    for _, desc in pairs(slimeMonster:GetDescendants()) do
                                        if desc:IsA("BasePart") and tostring(desc.Name):match("^Blob") then
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
                            task.wait(0.15)
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
        task.wait(0.1)
    end
end)

-- Loop 7: AutoUpgrade
task.spawn(function()
    local TweenService = game:GetService("TweenService")
    local isAutoUpgradeRunning = false

    while ScriptRunning do
        if Settings.AutoUpgrade and game.PlaceId == 17579225831 then
            if not isAutoUpgradeRunning then
                isAutoUpgradeRunning = true

                -- Warte 15 Sekunden am Anfang
                task.wait(15)
                -- Pause AutoSlimeKill while upgrading (save previous state)
                local prevAutoSlime = Settings.AutoSlimeKill
                if prevAutoSlime then
                    Settings.AutoSlimeKill = false
                    SaveConfig()
                    cancelActiveAutoSlime()
                end


                
                local upgrades = {
                    {name = "Bee Upgrade 1", cost = 5, position = Vector3.new(-47190, 290, 222), waitBefore = 0},
                    {name = "Bee Upgrade 2", cost = 15, position = Vector3.new(-47190, 290, 222), waitBefore = 3},
                    {name = "Bee Upgrade 3", cost = 30, position = Vector3.new(-47190, 290, 222), waitBefore = 3}
                }
                
                for upgradeIdx, upgrade in ipairs(upgrades) do
                    if not Settings.AutoUpgrade or game.PlaceId ~= 17579225831 then break end
                    
                    local character = LocalPlayer.Character
                    if not character or not character:FindFirstChild("HumanoidRootPart") then break end
                    local hrp = character.HumanoidRootPart
                    
                    -- Warte auf genug Bricks (check BrickLabel)
                    local hasEnoughBricks = false
                    local maxWait = 300
                    local waitedTime = 0
                    while not hasEnoughBricks and Settings.AutoUpgrade and game.PlaceId == 17579225831 and waitedTime < maxWait do
                        pcall(function()
                            local brickLabel = game:GetService("Players").LocalPlayer.PlayerGui.ScreenGui.UnderPopUpFrame.RetroGuiTopMenu.TopMenuFrame2.BrickLabel
                            if brickLabel then
                                local brickText = tonumber(brickLabel.Text) or 0
                                if brickText >= upgrade.cost then
                                    hasEnoughBricks = true
                                end
                            end
                        end)
                        if not hasEnoughBricks then
                            task.wait(0.5)
                            waitedTime = waitedTime + 0.5
                        end
                    end
                    
                    if not hasEnoughBricks then break end
                    
                    -- Tween zu Position kurz vor Upgrade Button ("-47180, 290, 222")
                    local approachPos = Vector3.new(-47180, 290, 222)
                    local dist1 = (approachPos - hrp.Position).Magnitude
                    if dist1 > 1 then
                        -- Re-check bricks immediately before tweening; wait a short time if needed
                        if not hasEnoughBricks then
                            local shortWait = 0
                            local shortMax = 120
                            while shortWait < shortMax and not hasEnoughBricks and Settings.AutoUpgrade and game.PlaceId == 17579225831 do
                                pcall(function()
                                    local brickLabel = game:GetService("Players").LocalPlayer.PlayerGui.ScreenGui.UnderPopUpFrame.RetroGuiTopMenu.TopMenuFrame2.BrickLabel
                                    if brickLabel then
                                        local brickText = tonumber(brickLabel.Text) or 0
                                        if brickText >= upgrade.cost then
                                            hasEnoughBricks = true
                                        end
                                    end
                                end)
                                if not hasEnoughBricks then
                                    task.wait(0.5)
                                    shortWait = shortWait + 0.5
                                end
                            end
                        end
                        if hasEnoughBricks then
                            local duration1 = dist1 / 69
                            local tween1 = TweenService:Create(hrp, TweenInfo.new(duration1, Enum.EasingStyle.Linear), {CFrame = CFrame.new(approachPos)})
                            tween1:Play()
                            tween1.Completed:Wait()
                        else
                            break
                        end
                    end
                    
                    -- Warte vor dem Button, falls nötig (Cooldown von vorherigem Upgrade)
                    if upgrade.waitBefore > 0 then
                        task.wait(upgrade.waitBefore)
                    end
                    
                    -- Tween zum Upgrade Button ("-47190, 290, 222")
                    local buttonPos = upgrade.position
                    local dist2 = (buttonPos - hrp.Position).Magnitude
                    if dist2 > 1 then
                        -- Re-check bricks right before moving onto the button
                        pcall(function()
                            local brickLabel = game:GetService("Players").LocalPlayer.PlayerGui.ScreenGui.UnderPopUpFrame.RetroGuiTopMenu.TopMenuFrame2.BrickLabel
                            if brickLabel then
                                local brickText = tonumber(brickLabel.Text) or 0
                                if brickText < upgrade.cost then
                                    hasEnoughBricks = false
                                else
                                    hasEnoughBricks = true
                                end
                            end
                        end)
                        if not hasEnoughBricks then break end
                        local duration2 = dist2 / 69
                        local tween2 = TweenService:Create(hrp, TweenInfo.new(duration2, Enum.EasingStyle.Linear), {CFrame = CFrame.new(buttonPos)})
                        tween2:Play()
                        tween2.Completed:Wait()
                    end
                    
                    -- 1 Sekunde nach Ankunft: mehrfach versuchen, die Biene auszuwählen
                    task.wait(1)
                    pcall(function()
                        local attempts = 3
                        for i = 1, attempts do
                            if not Settings.AutoUpgrade or game.PlaceId ~= 17579225831 then break end
                            -- re-check bricks and position before firing
                            local brickLabel = pcall(function()
                                return game:GetService("Players").LocalPlayer.PlayerGui.ScreenGui.UnderPopUpFrame.RetroGuiTopMenu.TopMenuFrame2.BrickLabel
                            end)
                            local brickCount = 0
                            pcall(function()
                                local bl = game:GetService("Players").LocalPlayer.PlayerGui.ScreenGui.UnderPopUpFrame.RetroGuiTopMenu.TopMenuFrame2.BrickLabel
                                brickCount = tonumber(bl and bl.Text) or 0
                            end)
                            if brickCount < upgrade.cost then break end
                            -- ensure we're close enough to the button
                            local hrpPos = hrp and hrp.Position
                            if hrpPos then
                                local distToButton = (hrpPos - buttonPos).Magnitude
                                if distToButton > 6 then break end
                            end
                            pcall(function()
                                local args = {[1] = 2}
                                game:GetService("ReplicatedStorage").Events.RetroChallengeBeeSelect:FireServer(unpack(args))
                            end)
                            task.wait(0.5)
                        end
                    end)
                end
                
                -- Restore AutoSlimeKill to previous value
                if prevAutoSlime ~= nil then
                    Settings.AutoSlimeKill = prevAutoSlime
                    SaveConfig()
                end

                isAutoUpgradeRunning = false
            end
        else
            isAutoUpgradeRunning = false
        end
        task.wait(1)
    end
end)
