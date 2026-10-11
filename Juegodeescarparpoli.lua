--[[
    ═══════════════════════════════════════════════════════════
    SCRIPT PARA DELTA - Steal a Brainrot (estilo)
    Basado en el volcado de juego_pruebaaaa.txt
    ═══════════════════════════════════════════════════════════
]]

-- ═══════════════════════════════════════════════════════════
-- SERVICIOS Y VARIABLES GLOBALES
-- ═══════════════════════════════════════════════════════════
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer
local Backpack = LocalPlayer:WaitForChild("Backpack")
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local leaderstats = LocalPlayer:WaitForChild("leaderstats")
local dataFolder = LocalPlayer:WaitForChild("data")

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ServerRemotes = Remotes:WaitForChild("Server")
local ClientRemotes = Remotes:WaitForChild("Client")

-- ═══════════════════════════════════════════════════════════
-- CONFIGURACIÓN
-- ═══════════════════════════════════════════════════════════
local Config = {
    AutoSteal = false,
    AutoSell = false,
    AutoClaim = false,
    AutoRebirth = false,
    AutoPolish = false,
    SpeedHack = false,
    SpeedValue = 100,
    InstantProximity = false,
    NoClip = false,
    AntiAFK = true,
    AutoCollectAll = false,
    AutoClaimEarnings = false,
    AutoClaimGroupReward = false,
    AutoTutorial = false,
    AutoWatchedCutscene = false,
    AutoPlaceItem = false,
    AutoSellItems = false,
}

-- ═══════════════════════════════════════════════════════════
-- UTILIDADES
-- ═══════════════════════════════════════════════════════════
local function notify(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = duration or 3,
        })
    end)
end

local function getRemote(folder, name)
    local remote = folder:FindFirstChild(name)
    if remote and remote:IsA("RemoteEvent") then
        return remote
    end
    return nil
end

-- ═══════════════════════════════════════════════════════════
-- 1. AUTO STEAL (ProximityPrompts)
-- ═══════════════════════════════════════════════════════════
local function getAllProximityPrompts()
    local prompts = {}
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and obj.Enabled then
            table.insert(prompts, obj)
        end
    end
    return prompts
end

local function fireProximityPrompt(prompt)
    if not prompt or not prompt.Parent then return end
    local character = LocalPlayer.Character
    if not character then return end
    
    pcall(function()
        if fireproximityprompt then
            fireproximityprompt(prompt, 0)
        elseif prompt:IsA("ProximityPrompt") then
            prompt:InputHoldBegin()
            task.wait(0.05)
            prompt:InputHoldEnd()
        end
    end)
end

local function autoStealLoop()
    while Config.AutoSteal do
        task.wait(0.1)
        local prompts = getAllProximityPrompts()
        for _, prompt in ipairs(prompts) do
            if prompt.ActionText == "Steal?" or prompt.ActionText == "Steal" then
                fireProximityPrompt(prompt)
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- 2. AUTO SELL
-- ═══════════════════════════════════════════════════════════
local function autoSellLoop()
    while Config.AutoSell do
        task.wait(0.5)
        local sellRemote = getRemote(ServerRemotes, "SellItem")
        if sellRemote then
            -- Buscar items en la mochila para vender
            for _, tool in ipairs(Backpack:GetChildren()) do
                if tool:IsA("Tool") then
                    pcall(function()
                        sellRemote:FireServer(tool)
                    end)
                end
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- 3. AUTO CLAIM EARNINGS
-- ═══════════════════════════════════════════════════════════
local function autoClaimLoop()
    while Config.AutoClaim do
        task.wait(1)
        local claimAllRemote = getRemote(ServerRemotes, "ClaimAllEarnings")
        local claimRemote = getRemote(ServerRemotes, "ClaimEarnings")
        
        if claimAllRemote then
            pcall(function()
                claimAllRemote:FireServer()
            end)
        end
        
        if claimRemote then
            pcall(function()
                claimRemote:FireServer()
            end)
        end
        
        -- ClaimGroupReward
        if Config.AutoClaimGroupReward then
            local groupRemote = getRemote(ServerRemotes, "ClaimGroupReward")
            if groupRemote then
                pcall(function()
                    groupRemote:FireServer()
                end)
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- 4. AUTO REBIRTH
-- ═══════════════════════════════════════════════════════════
local function autoRebirthLoop()
    while Config.AutoRebirth do
        task.wait(2)
        local rebirthRemote = getRemote(ServerRemotes, "Rebirth")
        if rebirthRemote then
            pcall(function()
                rebirthRemote:FireServer()
            end)
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- 5. AUTO POLISH
-- ═══════════════════════════════════════════════════════════
local function autoPolishLoop()
    while Config.AutoPolish do
        task.wait(1)
        -- Buscar la máquina de pulir
        local polishingMachine = Workspace:FindFirstChild("Map")
        if polishingMachine then
            local machines = polishingMachine:FindFirstChild("Machines")
            if machines then
                local polishMachine = machines:FindFirstChild("Polishing Machine")
                if polishMachine then
                    local marker = polishMachine:FindFirstChild("Marker")
                    if marker then
                        local startPrompt = marker:FindFirstChild("StartPromptAttachment")
                        if startPrompt then
                            local prompt = startPrompt:FindFirstChild("StartPrompt")
                            if prompt and prompt.Enabled then
                                fireProximityPrompt(prompt)
                            end
                        end
                    end
                end
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- 6. SPEED HACK
-- ═══════════════════════════════════════════════════════════
local function applySpeed()
    local character = LocalPlayer.Character
    if character then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = Config.SpeedValue
        end
    end
end

local function speedHackLoop()
    while Config.SpeedHack do
        task.wait(0.1)
        applySpeed()
    end
end

-- ═══════════════════════════════════════════════════════════
-- 7. INSTANT PROXIMITY PROMPT
-- ═══════════════════════════════════════════════════════════
local function enableInstantProximity()
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") then
            pcall(function()
                obj.HoldDuration = 0
            end)
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- 8. NOCLIP
-- ═══════════════════════════════════════════════════════════
local noclipConnection
local function toggleNoclip(state)
    Config.NoClip = state
    if state then
        noclipConnection = RunService.Stepped:Connect(function()
            local character = LocalPlayer.Character
            if character then
                for _, part in ipairs(character:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = false
                    end
                end
            end
        end)
    else
        if noclipConnection then
            noclipConnection:Disconnect()
            noclipConnection = nil
        end
        local character = LocalPlayer.Character
        if character then
            for _, part in ipairs(character:GetDescendants()) do
                if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                    part.CanCollide = true
                end
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- 9. ANTI-AFK
-- ═══════════════════════════════════════════════════════════
local antiAfkConnection
local function enableAntiAFK()
    if antiAfkConnection then antiAfkConnection:Disconnect() end
    antiAfkConnection = LocalPlayer.Idled:Connect(function()
        pcall(function()
            game:GetService("VirtualUser"):CaptureController()
            game:GetService("VirtualUser"):ClickButton2(Vector2.new())
        end)
    end)
end

-- ═══════════════════════════════════════════════════════════
-- 10. AUTO COLLECT ALL (CollectAllPad)
-- ═══════════════════════════════════════════════════════════
local function autoCollectAllLoop()
    while Config.AutoCollectAll do
        task.wait(2)
        -- Buscar el CollectAllPad en Jail
        local map = Workspace:FindFirstChild("Map")
        if map then
            local jail = map:FindFirstChild("Jail")
            if jail then
                local collectPad = jail:FindFirstChild("CollectAllPad")
                if collectPad then
                    local hitbox = collectPad:FindFirstChild("Hitbox")
                    if hitbox then
                        local touchInterest = hitbox:FindFirstChild("TouchInterest")
                        if touchInterest and firetouchinterest then
                            local character = LocalPlayer.Character
                            if character and character:FindFirstChild("HumanoidRootPart") then
                                firetouchinterest(character.HumanoidRootPart, hitbox, 0)
                                task.wait(0.1)
                                firetouchinterest(character.HumanoidRootPart, hitbox, 1)
                            end
                        end
                    end
                end
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- 11. AUTO PLACE ITEM (Plots)
-- ═══════════════════════════════════════════════════════════
local function autoPlaceItemLoop()
    while Config.AutoPlaceItem do
        task.wait(1)
        local placeRemote = getRemote(ServerRemotes, "PlaceItem")
        if placeRemote then
            -- Buscar slots disponibles en el plot
            local plots = Workspace:FindFirstChild("Plots")
            if plots then
                for _, plot in ipairs(plots:GetChildren()) do
                    if plot.Name:find("Plot") then
                        local floors = plot:FindFirstChild("Floors")
                        if floors then
                            for _, floor in ipairs(floors:GetChildren()) do
                                local slots = floor:FindFirstChild("Slots")
                                if slots then
                                    for _, slot in ipairs(slots:GetChildren()) do
                                        local marker = slot:FindFirstChild("Marker")
                                        if marker then
                                            local prompt = marker:FindFirstChild("ActionPrompt")
                                            if prompt and prompt.Enabled and prompt.ActionText == "Place" then
                                                fireProximityPrompt(prompt)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- 12. AUTO TUTORIAL
-- ═══════════════════════════════════════════════════════════
local function autoTutorialLoop()
    while Config.AutoTutorial do
        task.wait(2)
        local tutorialComplete = getRemote(ServerRemotes, "TutorialComplete")
        local tutorialStep = getRemote(ServerRemotes, "TutorialStep")
        
        if tutorialComplete then
            pcall(function()
                tutorialComplete:FireServer()
            end)
        end
        
        if tutorialStep then
            pcall(function()
                tutorialStep:FireServer()
            end)
        end
        
        if Config.AutoWatchedCutscene then
            local watchedCutscene = getRemote(ServerRemotes, "WatchedCutscene")
            if watchedCutscene then
                pcall(function()
                    watchedCutscene:FireServer()
                end)
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- 13. AUTO SELL ITEMS (desde Selling Shop)
-- ═══════════════════════════════════════════════════════════
local function autoSellItemsLoop()
    while Config.AutoSellItems do
        task.wait(0.5)
        local sellRemote = getRemote(ServerRemotes, "SellItem")
        if sellRemote then
            -- Buscar items en el plot para vender
            local plots = Workspace:FindFirstChild("Plots")
            if plots then
                for _, plot in ipairs(plots:GetChildren()) do
                    if plot.Name:find("Plot") then
                        local floors = plot:FindFirstChild("Floors")
                        if floors then
                            for _, floor in ipairs(floors:GetChildren()) do
                                local slots = floor:FindFirstChild("Slots")
                                if slots then
                                    for _, slot in ipairs(slots:GetChildren()) do
                                        local marker = slot:FindFirstChild("Marker")
                                        if marker then
                                            local prompt = marker:FindFirstChild("ActionPrompt")
                                            if prompt and prompt.Enabled and prompt.ActionText == "Pickup" then
                                                fireProximityPrompt(prompt)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- 14. FUNCIONES DE UTILIDAD EXTRA
-- ═══════════════════════════════════════════════════════════
local function getSpeed()
    return leaderstats and leaderstats:FindFirstChild("Speed") and leaderstats.Speed.Value or "0"
end

local function getCash()
    return leaderstats and leaderstats:FindFirstChild("Cash") and leaderstats.Cash.Value or "0"
end

local function getRebirths()
    return dataFolder and dataFolder:FindFirstChild("Rebirths") and dataFolder.Rebirths.Value or 0
end

-- ═══════════════════════════════════════════════════════════
-- 15. INTERFAZ GRÁFICA (UI)
-- ═══════════════════════════════════════════════════════════
local function createUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "DeltaScriptUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = PlayerGui

    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 300, 0, 450)
    mainFrame.Position = UDim2.new(0, 20, 0, 100)
    mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    mainFrame.BorderSizePixel = 0
    mainFrame.Active = true
    mainFrame.Draggable = true
    mainFrame.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = mainFrame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(100, 100, 255)
    stroke.Thickness = 2
    stroke.Parent = mainFrame

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, 0, 0, 40)
    title.Position = UDim2.new(0, 0, 0, 0)
    title.BackgroundColor3 = Color3.fromRGB(50, 50, 80)
    title.BorderSizePixel = 0
    title.Text = "⚡ Delta Script - Steal a Brainrot"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 14
    title.Font = Enum.Font.GothamBold
    title.Parent = mainFrame

    local titleCorner = Instance.new("UICorner")
    titleCorner.CornerRadius = UDim.new(0, 8)
    titleCorner.Parent = title

    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = "Close"
    closeBtn.Size = UDim2.new(0, 30, 0, 30)
    closeBtn.Position = UDim2.new(1, -35, 0, 5)
    closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    closeBtn.BorderSizePixel = 0
    closeBtn.Text = "X"
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.TextSize = 14
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.Parent = title

    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, 6)
    closeCorner.Parent = closeBtn

    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Name = "Scroll"
    scrollFrame.Size = UDim2.new(1, -10, 1, -50)
    scrollFrame.Position = UDim2.new(0, 5, 0, 45)
    scrollFrame.BackgroundTransparency = 1
    scrollFrame.BorderSizePixel = 0
    scrollFrame.ScrollBarThickness = 4
    scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 255)
    scrollFrame.Parent = mainFrame

    local uiList = Instance.new("UIListLayout")
    uiList.SortOrder = Enum.SortOrder.LayoutOrder
    uiList.Padding = UDim.new(0, 5)
    uiList.Parent = scrollFrame

    local function createButton(text, callback, order)
        local btn = Instance.new("TextButton")
        btn.Name = text:gsub("%s", "")
        btn.Size = UDim2.new(1, -10, 0, 35)
        btn.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
        btn.BorderSizePixel = 0
        btn.Text = text
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.TextSize = 12
        btn.Font = Enum.Font.Gotham
        btn.LayoutOrder = order or 1
        btn.Parent = scrollFrame

        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 6)
        btnCorner.Parent = btn

        btn.MouseButton1Click:Connect(function()
            btn.BackgroundColor3 = Color3.fromRGB(80, 80, 120)
            task.wait(0.1)
            btn.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
            callback()
        end)
    end

    local function createToggle(text, configKey, order)
        local btn = Instance.new("TextButton")
        btn.Name = text:gsub("%s", "")
        btn.Size = UDim2.new(1, -10, 0, 35)
        btn.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
        btn.BorderSizePixel = 0
        btn.Text = text .. ": OFF"
        btn.TextColor3 = Color3.fromRGB(255, 100, 100)
        btn.TextSize = 12
        btn.Font = Enum.Font.Gotham
        btn.LayoutOrder = order or 1
        btn.Parent = scrollFrame

        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 6)
        btnCorner.Parent = btn

        btn.MouseButton1Click:Connect(function()
            Config[configKey] = not Config[configKey]
            if Config[configKey] then
                btn.Text = text .. ": ON"
                btn.TextColor3 = Color3.fromRGB(100, 255, 100)
            else
                btn.Text = text .. ": OFF"
                btn.TextColor3 = Color3.fromRGB(255, 100, 100)
            end
        end)
    end

    -- Botones
    createButton("🚀 Auto Steal", function()
        Config.AutoSteal = not Config.AutoSteal
        if Config.AutoSteal then
            task.spawn(autoStealLoop)
            notify("Delta", "Auto Steal: ON")
        else
            notify("Delta", "Auto Steal: OFF")
        end
    end, 1)

    createButton("💰 Auto Sell", function()
        Config.AutoSell = not Config.AutoSell
        if Config.AutoSell then
            task.spawn(autoSellLoop)
            notify("Delta", "Auto Sell: ON")
        else
            notify("Delta", "Auto Sell: OFF")
        end
    end, 2)

    createButton("💵 Auto Claim Earnings", function()
        Config.AutoClaim = not Config.AutoClaim
        if Config.AutoClaim then
            task.spawn(autoClaimLoop)
            notify("Delta", "Auto Claim: ON")
        else
            notify("Delta", "Auto Claim: OFF")
        end
    end, 3)

    createButton("🔄 Auto Rebirth", function()
        Config.AutoRebirth = not Config.AutoRebirth
        if Config.AutoRebirth then
            task.spawn(autoRebirthLoop)
            notify("Delta", "Auto Rebirth: ON")
        else
            notify("Delta", "Auto Rebirth: OFF")
        end
    end, 4)

    createButton("✨ Auto Polish", function()
        Config.AutoPolish = not Config.AutoPolish
        if Config.AutoPolish then
            task.spawn(autoPolishLoop)
            notify("Delta", "Auto Polish: ON")
        else
            notify("Delta", "Auto Polish: OFF")
        end
    end, 5)

    createButton("🏃 Speed Hack (100)", function()
        Config.SpeedHack = not Config.SpeedHack
        if Config.SpeedHack then
            task.spawn(speedHackLoop)
            notify("Delta", "Speed Hack: ON (100)")
        else
            notify("Delta", "Speed Hack: OFF")
        end
    end, 6)

    createButton("⚡ Instant Proximity", function()
        enableInstantProximity()
        notify("Delta", "Proximity Prompts instantáneos")
    end, 7)

    createButton("👻 Noclip", function()
        toggleNoclip(not Config.NoClip)
        notify("Delta", "Noclip: " .. (Config.NoClip and "ON" or "OFF"))
    end, 8)

    createButton("🤖 Anti-AFK", function()
        Config.AntiAFK = not Config.AntiAFK
        if Config.AntiAFK then
            enableAntiAFK()
            notify("Delta", "Anti-AFK: ON")
        else
            if antiAfkConnection then
                antiAfkConnection:Disconnect()
                antiAfkConnection = nil
            end
            notify("Delta", "Anti-AFK: OFF")
        end
    end, 9)

    createButton("📦 Auto Collect All", function()
        Config.AutoCollectAll = not Config.AutoCollectAll
        if Config.AutoCollectAll then
            task.spawn(autoCollectAllLoop)
            notify("Delta", "Auto Collect: ON")
        else
            notify("Delta", "Auto Collect: OFF")
        end
    end, 10)

    createButton("📥 Auto Place Item", function()
        Config.AutoPlaceItem = not Config.AutoPlaceItem
        if Config.AutoPlaceItem then
            task.spawn(autoPlaceItemLoop)
            notify("Delta", "Auto Place: ON")
        else
            notify("Delta", "Auto Place: OFF")
        end
    end, 11)

    createButton("📚 Auto Tutorial", function()
        Config.AutoTutorial = not Config.AutoTutorial
        Config.AutoWatchedCutscene = Config.AutoTutorial
        if Config.AutoTutorial then
            task.spawn(autoTutorialLoop)
            notify("Delta", "Auto Tutorial: ON")
        else
            notify("Delta", "Auto Tutorial: OFF")
        end
    end, 12)

    createButton("💸 Auto Sell Items", function()
        Config.AutoSellItems = not Config.AutoSellItems
        if Config.AutoSellItems then
            task.spawn(autoSellItemsLoop)
            notify("Delta", "Auto Sell Items: ON")
        else
            notify("Delta", "Auto Sell Items: OFF")
        end
    end, 13)

    -- Información
    local infoLabel = Instance.new("TextLabel")
    infoLabel.Name = "Info"
    infoLabel.Size = UDim2.new(1, -10, 0, 60)
    infoLabel.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
    infoLabel.BorderSizePixel = 0
    infoLabel.Text = "📊 Speed: " .. tostring(getSpeed()) .. "\n💰 Cash: " .. tostring(getCash())
    infoLabel.TextColor3 = Color3.fromRGB(200, 200, 255)
    infoLabel.TextSize = 11
    infoLabel.Font = Enum.Font.Gotham
    infoLabel.LayoutOrder = 14
    infoLabel.Parent = scrollFrame

    local infoCorner = Instance.new("UICorner")
    infoCorner.CornerRadius = UDim.new(0, 6)
    infoCorner.Parent = infoLabel

    -- Actualizar info cada segundo
    task.spawn(function()
        while screenGui.Parent do
            task.wait(1)
            pcall(function()
                infoLabel.Text = "📊 Speed: " .. tostring(getSpeed()) .. "\n💰 Cash: " .. tostring(getCash())
            end)
        end
    end)

    closeBtn.MouseButton1Click:Connect(function()
        screenGui:Destroy()
    end)

    -- Minimizar
    local minimizeBtn = Instance.new("TextButton")
    minimizeBtn.Name = "Minimize"
    minimizeBtn.Size = UDim2.new(0, 30, 0, 30)
    minimizeBtn.Position = UDim2.new(1, -70, 0, 5)
    minimizeBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 120)
    minimizeBtn.BorderSizePixel = 0
    minimizeBtn.Text = "—"
    minimizeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    minimizeBtn.TextSize = 16
    minimizeBtn.Font = Enum.Font.GothamBold
    minimizeBtn.Parent = title

    local minCorner = Instance.new("UICorner")
    minCorner.CornerRadius = UDim.new(0, 6)
    minCorner.Parent = minimizeBtn

    local minimized = false
    minimizeBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        if minimized then
            mainFrame.Size = UDim2.new(0, 300, 0, 40)
            scrollFrame.Visible = false
        else
            mainFrame.Size = UDim2.new(0, 300, 0, 450)
            scrollFrame.Visible = true
        end
    end)
end

-- ═══════════════════════════════════════════════════════════
-- INICIALIZACIÓN
-- ═══════════════════════════════════════════════════════════
local function init()
    -- Esperar a que el personaje cargue
    if not LocalPlayer.Character then
        LocalPlayer.CharacterAdded:Wait()
    end
    
    task.wait(1)
    
    -- Crear UI
    createUI()
    
    -- Anti-AFK por defecto
    enableAntiAFK()
    
    -- Notificar
    notify("⚡ Delta Script", "Cargado correctamente", 5)
    
    -- Aplicar speed si está activado
    if Config.SpeedHack then
        task.spawn(speedHackLoop)
    end
end

-- Ejecutar
init()
