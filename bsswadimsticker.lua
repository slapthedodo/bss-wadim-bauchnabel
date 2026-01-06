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
local HiveClaimedInRBC = false

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
    AutoRBC = false,
    AutoRBCLobby = false,
    RBCWalkspeed = false,
    AutoClaimHive = false
}

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
            if result.AutoRBC ~= nil then Settings.AutoRBC = result.AutoRBC end
            if result.AutoRBCLobby ~= nil then Settings.AutoRBCLobby = result.AutoRBCLobby end
            if result.RBCWalkspeed ~= nil then Settings.RBCWalkspeed = result.RBCWalkspeed end
            if result.AutoClaimHive ~= nil then Settings.AutoClaimHive = result.AutoClaimHive end
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
    -- Wenn RBC Walkspeed aktiv ist, setze ihn nach dem Respawn
    if Settings.RBCWalkspeed and game.PlaceId == 17579225831 then
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

-- TAB: RBC
local RBCTab = Window:CreateTab("RBC", 4483362458)

RBCTab:CreateButton({
    Name = "tp to rbc (atlas bypass and direct join)",
    Callback = function()
        TeleportService:Teleport(17579225831, LocalPlayer)
    end,
})

RBCTab:CreateButton({
    Name = "tp to rbc lobby (atlas bypass)",
    Callback = function()
        TeleportService:Teleport(17579226768, LocalPlayer)
    end,
})

RBCTab:CreateSection("atuo tp")

RBCTab:CreateToggle({
    Name = "auto teleport rbc",
    CurrentValue = Settings.AutoRBC,
    Flag = "AutoRBC",
    Callback = function(Value)
        Settings.AutoRBC = Value
        SaveConfig()
    end,
})

RBCTab:CreateToggle({
    Name = "RBC Walkspeed (70)",
    CurrentValue = Settings.RBCWalkspeed,
    Flag = "RBCWalkspeed",
    Callback = function(Value)
        Settings.RBCWalkspeed = Value
        SaveConfig()
        
        if game.PlaceId == 17579225831 then
            if Value then
                SetWalkspeed(70)
            end
        end
    end,
})

RBCTab:CreateToggle({
    Name = "Auto Claim Hive",
    CurrentValue = Settings.AutoClaimHive,
    Flag = "AutoClaimHive",
    Callback = function(Value)
        Settings.AutoClaimHive = Value
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
            if Settings.AutoRBC then
                TeleportService:Teleport(17579225831, LocalPlayer)
            elseif Settings.AutoRBCLobby then
                TeleportService:Teleport(17579226768, LocalPlayer)
            end
        end
        task.wait(10)
    end
end)

-- Loop 4: Walkspeed und AutoClaimHive (bei Join)
game.Loaded:Wait() -- Warten, bis das Spiel geladen ist
task.spawn(function()
    while ScriptRunning do
        if game.PlaceId == 17579225831 then
            -- Walkspeed setzen, falls aktiv
            if Settings.RBCWalkspeed then
                SetWalkspeed(70)
            end
            
            -- Auto Claim Hive Logic (nur einmalig)
            if Settings.AutoClaimHive and not HiveClaimedInRBC and LocalPlayer.Character then
                HiveClaimedInRBC = true -- Setzen, damit es nicht nochmal ausgeführt wird
                print("Starte Auto Claim Hive...")
                
                local claimValues = {10, 9, 8, 7}
                
                for i, value in ipairs(claimValues) do
                    local success, err = pcall(function()
                        local args = {[1] = value}
                        ReplicatedStorage.Events.ClaimHive:FireServer(unpack(args))
                        print("ClaimHive mit Argument: " .. value .. " ausgeführt.")
                    end)
                    task.wait(1)
                end
                print("Auto Claim Hive beendet.")
            end
            
        else
            -- Zurücksetzen, wenn nicht in der RBC PlaceId
            if HiveClaimedInRBC then
                HiveClaimedInRBC = false
            end

        end
        
        task.wait(1)
    end
end)