-- Dienste
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

-- Dateiname für Config (Account-Spezifisch)
local FileName = "BeeSwarmRayfield_" .. LocalPlayer.UserId .. ".json"

-- Standard Werte
local Settings = {
    BronzeStar = false,
    DiamondStar = false,
    FieldDice = false
}

-- [FUNKTIONEN] Speichern und Laden
local function SaveConfig()
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
        end
    end
end

-- Config laden BEVOR UI startet
LoadConfig()

-- Rayfield Library laden
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
    Name = "Bee Swarm Script",
    LoadingTitle = "Loading...",
    LoadingSubtitle = "By Gemini",
    ConfigurationSaving = {
        Enabled = false, -- Wir nutzen unser eigenes System
    },
    KeySystem = false,
})

local FarmTab = Window:CreateTab("Generators", 4483362458)

-- Toggles erstellen
FarmTab:CreateToggle({
    Name = "Auto Bronze Star Amulet (+Reject)",
    CurrentValue = Settings.BronzeStar,
    Flag = "BronzeStar", 
    Callback = function(Value)
        Settings.BronzeStar = Value
        SaveConfig()
    end,
})

FarmTab:CreateToggle({
    Name = "Auto Diamond Star Amulet (+Reject)",
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

-- Der Mini-Button Oben Rechts
local ScreenGui = Instance.new("ScreenGui")
local ToggleBtn = Instance.new("TextButton")
local UICorner = Instance.new("UICorner")

if syn and syn.protect_gui then
    syn.protect_gui(ScreenGui)
    ScreenGui.Parent = CoreGui
elseif gethui then
    ScreenGui.Parent = gethui()
else
    ScreenGui.Parent = CoreGui
end

ScreenGui.Name = "RayfieldToggleMini"

ToggleBtn.Name = "MiniButton"
ToggleBtn.Parent = ScreenGui
ToggleBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
ToggleBtn.Position = UDim2.new(1, -40, 0, 10) -- Ganz rechts oben
ToggleBtn.Size = UDim2.new(0, 30, 0, 30)
ToggleBtn.Font = Enum.Font.FredokaOne
ToggleBtn.Text = "UI"
ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleBtn.TextSize = 14.000
ToggleBtn.AutoButtonColor = true

UICorner.CornerRadius = UDim.new(0, 4)
UICorner.Parent = ToggleBtn

local uiOpen = true
ToggleBtn.MouseButton1Click:Connect(function()
    uiOpen = not uiOpen
    local rayfieldUI = game:GetService("CoreGui"):FindFirstChild("Rayfield")
    if rayfieldUI then
        rayfieldUI.Enabled = uiOpen
    end
end)

-- [HAUPT LOGIK LOOP]
task.spawn(function()
    while true do
        -- 1. Bronze Star Logic
        if Settings.BronzeStar then
            pcall(function()
                -- Generator aktivieren
                local args = {[1] = "Bronze Star Amulet Generator"}
                ReplicatedStorage.Events.ToyEvent:FireServer(unpack(args))
                
                -- Kurz warten, damit der Server den Roll registriert (Sicherheitspuffer)
                task.wait(0.1) 
                
                -- Direkt ablehnen (Reject)
                ReplicatedStorage.Events.ClientRejectAmulet:FireServer()
            end)
        end

        -- 2. Diamond Star Logic
        if Settings.DiamondStar then
            pcall(function()
                -- Generator aktivieren
                local args = {[1] = "Diamond Star Amulet Generator"}
                ReplicatedStorage.Events.ToyEvent:FireServer(unpack(args))
                
                task.wait(0.1) 
                
                -- Direkt ablehnen (Reject)
                ReplicatedStorage.Events.ClientRejectAmulet:FireServer()
            end)
        end

        -- 3. Field Dice Logic (Hat kein Reject)
        if Settings.FieldDice then
            pcall(function()
                local args = {[1] = {["Name"] = "Field Dice"}}
                ReplicatedStorage.Events.PlayerActivesCommand:FireServer(unpack(args))
            end)
        end
        
        task.wait(1.5) -- Loop Geschwindigkeit
    end
end)