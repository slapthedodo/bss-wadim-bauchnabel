-- Dienste
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

-- Variable zum Steuern des Loops (für Unload wichtig)
local ScriptRunning = true

-- Dateiname für Config
local FileName = "BeeSwarmSchlipSchlop_" .. LocalPlayer.UserId .. ".json"

-- Standard Werte
local Settings = {
    BronzeStar = false,
    DiamondStar = false,
    FieldDice = false,
    Snowflake = false
}

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
        end
    end
end

-- Config laden
LoadConfig()

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

-- TAB: Generators
local FarmTab = Window:CreateTab("Generators", 4483362458)

FarmTab:CreateToggle({
    Name = "Auto Bronze Star Amulet (+Reject) (für sticker)",
    CurrentValue = Settings.BronzeStar,
    Flag = "BronzeStar", 
    Callback = function(Value)
        Settings.BronzeStar = Value
        SaveConfig()
    end,
})

FarmTab:CreateToggle({
    Name = "Auto Diamond Star Amulet (+Reject) (für sticker)",
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

-- TAB: Settings (Für Unload)
local SettingsTab = Window:CreateTab("Settings", 4483362458)

SettingsTab:CreateButton({
    Name = "Unload Script (Stop & Close)",
    Callback = function()
        -- 1. Loop stoppen
        ScriptRunning = false
        
        -- 2. Rayfield zerstören
        Rayfield:Destroy()
        
        print("Script unloaded successfully.")
    end,
})

-- [HAUPT LOGIK LOOP]
task.spawn(function()
    -- Der Loop läuft nur solange ScriptRunning wahr ist
    while ScriptRunning do
        
        -- 1. Bronze Star Logic
        if Settings.BronzeStar then
            pcall(function()
                local args = {[1] = "Bronze Star Amulet Generator"}
                ReplicatedStorage.Events.ToyEvent:FireServer(unpack(args))
                task.wait(0.05) 
                firesignal(game:GetService("Players").LocalPlayer.PlayerGui.ScreenGui.RewardsPopUp.NoButton.MouseButton1Click)
            end)
        end

        -- 2. Diamond Star Logic
        if Settings.DiamondStar then
            pcall(function()
                local args = {[1] = "Diamond Star Amulet Generator"}
                ReplicatedStorage.Events.ToyEvent:FireServer(unpack(args))
                task.wait(0.05) 
                firesignal(game:GetService("Players").LocalPlayer.PlayerGui.ScreenGui.RewardsPopUp.NoButton.MouseButton1Click)
            end)
        end

        -- 3. Field Dice Logic
        if Settings.FieldDice then
            pcall(function()
                local args = {[1] = {["Name"] = "Field Dice"}}
                ReplicatedStorage.Events.PlayerActivesCommand:FireServer(unpack(args))
            end)
        end

        -- 4. Snowflake Logic
        if Settings.Snowflake then
            pcall(function()
                local args = {[1] = {["Name"] = "Snowflake"}}
                ReplicatedStorage.Events.PlayerActivesCommand:FireServer(unpack(args))
            end)
        end
        
        task.wait(3.05)
    end
end)