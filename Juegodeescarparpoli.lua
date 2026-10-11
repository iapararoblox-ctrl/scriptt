--[[
    ═══════════════════════════════════════════════════════════
    DELTA SCRIPT v2 - Steal a Brainrot (CORREGIDO)
    ═══════════════════════════════════════════════════════════
    ✓ Auto Steal (ProximityPrompts "Steal?")
    ✓ Auto Sell (vía remotes y GUI)
    ✓ Auto Claim Earnings
    ✓ Auto Rebirth
    ✓ Auto Collect All (Jail)
    ✓ Auto Polish
    ✓ Speed Hack
    ✓ Noclip
    ✓ Anti-AFK
    ✓ ESP de Items
    ═══════════════════════════════════════════════════════════
]]

-- ═══════════════════════════════════════════════════════════
-- SERVICIOS
-- ═══════════════════════════════════════════════════════════
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local StarterGui        = game:GetService("StarterGui")
local Workspace         = game:GetService("Workspace")
local VirtualUser       = game:GetService("VirtualUser")
local UserInputService  = game:GetService("UserInputService")

local LP     = Players.LocalPlayer
local Char   = LP.Character or LP.CharacterAdded:Wait()
local Hum    = Char:WaitForChild("Humanoid")
local Root   = Char:WaitForChild("HumanoidRootPart")
local PlayerGui = LP:WaitForChild("PlayerGui")
local Backpack = LP:WaitForChild("Backpack")
local Leaderstats = LP:WaitForChild("leaderstats")

-- ═══════════════════════════════════════════════════════════
-- REMOTES (verificados del volcado)
-- ═══════════════════════════════════════════════════════════
local Remotes       = ReplicatedStorage:WaitForChild("Remotes")
local ServerRemotes = Remotes:WaitForChild("Server")
local ClientRemotes = Remotes:WaitForChild("Client")

local function getRemote(name)
    return ServerRemotes:FindFirstChild(name)
end

-- ═══════════════════════════════════════════════════════════
-- CONFIGURACIÓN
-- ═══════════════════════════════════════════════════════════
local CFG = {
    AutoSteal       = false,
    AutoSell        = false,
    AutoClaim       = false,
    AutoRebirth     = false,
    AutoPolish      = false,
    AutoCollect     = false,
    AutoTutorial    = false,
    AutoTreadmill   = false,
    SpeedHack       = false,
    SpeedValue      = 100,
    Noclip          = false,
    AntiAFK         = true,
    ESP             = false,
    StealRange      = 15,  -- Distancia para teletransportar al item
}

-- ═══════════════════════════════════════════════════════════
-- NOTIFICACIONES
-- ═══════════════════════════════════════════════════════════
local function notify(title, text, dur)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title, Text = text, Duration = dur or 3
        })
    end)
end

-- ═══════════════════════════════════════════════════════════
-- TELETRANSPORTE
-- ═══════════════════════════════════════════════════════════
local function tpTo(pos)
    if not Root or not Root.Parent then return end
    pcall(function()
        Root.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
    end)
end

-- ═══════════════════════════════════════════════════════════
-- 1. AUTO STEAL (ProximityPrompts "Steal?")
-- ═══════════════════════════════════════════════════════════
local function firePrompt(prompt)
    if not prompt or not prompt.Parent then return end
    pcall(function()
        if fireproximityprompt then
            fireproximityprompt(prompt)
        end
    end)
end

local function autoStealLoop()
    while CFG.AutoSteal do
        task.wait(0.15)
        if not Char or not Char.Parent then 
            Char = LP.Character or LP.CharacterAdded:Wait()
            Hum = Char:WaitForChild("Humanoid")
            Root = Char:WaitForChild("HumanoidRootPart")
        end
        
        -- Buscar todos los ProximityPrompts en Stages (donde están los items robables)
        local stages = Workspace:FindFirstChild("Stages")
        if not stages then task.wait(1) continue end
        
        for _, prompt in ipairs(stages:GetDescendants()) do
            if prompt:IsA("ProximityPrompt") 
               and prompt.ActionText == "Steal?" 
               and prompt.Enabled then
                -- Teletransportarse al item y disparar prompt
                local itemPart = prompt.Parent
                if itemPart and itemPart:IsA("BasePart") then
                    tpTo(itemPart.Position)
                    task.wait(0.05)
                end
                firePrompt(prompt)
                task.wait(0.05)
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- 2. AUTO SELL (remotes + GUI fallback)
-- ═══════════════════════════════════════════════════════════
local function autoSellLoop()
    while CFG.AutoSell do
        task.wait(0.5)
        
        -- Método 1: Buscar items en el plot y hacer Pickup
        local plots = Workspace:FindFirstChild("Plots")
        if plots then
            for _, prompt in ipairs(plots:GetDescendants()) do
                if prompt:IsA("ProximityPrompt") 
                   and prompt.ActionText == "Pickup" 
                   and prompt.Enabled then
                    firePrompt(prompt)
                    task.wait(0.1)
                end
            end
        end
        
        -- Método 2: Buscar items que ya tenemos y venderlos via GUI
        local sellFrame = PlayerGui:FindFirstChild("Main")
        if sellFrame then
            sellFrame = sellFrame:FindFirstChild("SellingFrame")
            if sellFrame then
                local bottom = sellFrame:FindFirstChild("BottomFrame")
                if bottom then
                    local btns = bottom:FindFirstChild("Buttons")
                    if btns then
                        local sellAll = btns:FindFirstChild("SellAllButton")
                        if sellAll and sellAll:IsA("ImageButton") then
                            pcall(function()
                                sellAll.MouseButton1Click:Fire()
                            end)
                        end
                    end
                end
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- 3. AUTO CLAIM EARNINGS
-- ═══════════════════════════════════════════════════════════
local function autoClaimLoop()
    while CFG.AutoClaim do
        task.wait(1.5)
        
        local claimAll = getRemote("ClaimAllEarnings")
        local claim = getRemote("ClaimEarnings")
        local group = getRemote("ClaimGroupReward")
        
        if claimAll then pcall(function() claimAll:FireServer() end) end
        if claim then pcall(function() claim:FireServer() end) end
        if group then pcall(function() group:FireServer() end) end
    end
end

-- ═══════════════════════════════════════════════════════════
-- 4. AUTO REBIRTH
-- ═══════════════════════════════════════════════════════════
local function autoRebirthLoop()
    while CFG.AutoRebirth do
        task.wait(2)
        local remote = getRemote("Rebirth")
        if remote then
            pcall(function() remote:FireServer() end)
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- 5. AUTO POLISH
-- ═══════════════════════════════════════════════════════════
local function autoPolishLoop()
    while CFG.AutoPolish do
        task.wait(0.8)
        local map = Workspace:FindFirstChild("Map")
        if map then
            local machines = map:FindFirstChild("Machines")
            if machines then
                local pm = machines:FindFirstChild("Polishing Machine")
                if pm then
                    for _, prompt in ipairs(pm:GetDescendants()) do
                        if prompt:IsA("ProximityPrompt") and prompt.Enabled then
                            if prompt.ActionText == "Start?" 
                               or prompt.ActionText == "Place Item?" then
                                firePrompt(prompt)
                            end
                        end
                    end
                end
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- 6. AUTO COLLECT ALL (Jail)
-- ═══════════════════════════════════════════════════════════
local function autoCollectLoop()
    while CFG.AutoCollect do
        task.wait(1)
        if not Root or not Root.Parent then continue end
        
        local map = Workspace:FindFirstChild("Map")
        if not map then continue end
        local jail = map:FindFirstChild("Jail")
        if not jail then continue end
        local pad = jail:FindFirstChild("CollectAllPad")
        if not pad then continue end
        local hitbox = pad:FindFirstChild("Hitbox")
        if not hitbox then continue end
        
        -- Teletransportar al pad y tocar
        tpTo(hitbox.Position)
        task.wait(0.1)
        
        if firetouchinterest then
            pcall(function()
                firetouchinterest(Root, hitbox, 0)
                task.wait(0.05)
                firetouchinterest(Root, hitbox, 1)
            end)
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- 7. AUTO TUTORIAL
-- ═══════════════════════════════════════════════════════════
local function autoTutorialLoop()
    while CFG.AutoTutorial do
        task.wait(2)
        local complete = getRemote("TutorialComplete")
        local step = getRemote("TutorialStep")
        local watched = getRemote("WatchedCutscene")
        
        if step then pcall(function() step:FireServer(1) end) end
        if watched then pcall(function() watched:FireServer() end) end
        if complete then pcall(function() complete:FireServer() end) end
    end
end

-- ═══════════════════════════════════════════════════════════
-- 8. AUTO TREADMILL (equipar automáticamente)
-- ═══════════════════════════════════════════════════════════
local function autoTreadmillLoop()
    while CFG.AutoTreadmill do
        task.wait(1)
        -- Buscar herramienta con IsTreadmill en backpack
        for _, tool in ipairs(Backpack:GetChildren()) do
            if tool:IsA("Tool") then
                local hasAttr = tool:GetAttribute("IsTreadmill")
                if hasAttr then
                    pcall(function()
                        Hum:EquipTool(tool)
                    end)
                end
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- 9. SPEED HACK
-- ═══════════════════════════════════════════════════════════
local function speedLoop()
    while CFG.SpeedHack do
        task.wait(0.1)
        if Hum and Hum.Parent then
            Hum.WalkSpeed = CFG.SpeedValue
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- 10. NOCLIP
-- ═══════════════════════════════════════════════════════════
local noclipConn
local function setNoclip(state)
    if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
    if state then
        noclipConn = RunService.Stepped:Connect(function()
            if Char then
                for _, p in ipairs(Char:GetDescendants()) do
                    if p:IsA("BasePart") then p.CanCollide = false end
                end
            end
        end)
    end
end

-- ═══════════════════════════════════════════════════════════
-- 11. ANTI-AFK
-- ═══════════════════════════════════════════════════════════
local function enableAntiAFK()
    LP.Idled:Connect(function()
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end)
end

-- ═══════════════════════════════════════════════════════════
-- 12. ESP DE ITEMS (Highlight)
-- ═══════════════════════════════════════════════════════════
local espFolder = Instance.new("Folder", Workspace)
espFolder.Name = "DeltaESP"

local function clearESP()
    for _, c in ipairs(espFolder:GetChildren()) do c:Destroy() end
end

local function espLoop()
    while CFG.ESP do
        task.wait(1)
        clearESP()
        local stages = Workspace:FindFirstChild("Stages")
        if not stages then continue end
        
        for _, prompt in ipairs(stages:GetDescendants()) do
            if prompt:IsA("ProximityPrompt") and prompt.ActionText == "Steal?" then
                local item = prompt.Parent
                if item and item:IsA("BasePart") then
                    local hl = Instance.new("Highlight")
                    hl.Adornee = item
                    hl.FillColor = Color3.fromRGB(255, 50, 50)
                    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                    hl.FillTransparency = 0.5
                    hl.Parent = espFolder
                end
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- 13. INTERFAZ GRÁFICA
-- ═══════════════════════════════════════════════════════════
local function createUI()
    -- Eliminar UI previa
    local old = PlayerGui:FindFirstChild("DeltaUI")
    if old then old:Destroy() end
    
    local sg = Instance.new("ScreenGui")
    sg.Name = "DeltaUI"
    sg.ResetOnSpawn = false
    sg.IgnoreGuiInset = true
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.Parent = PlayerGui
    
    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 260, 0, 420)
    main.Position = UDim2.new(0, 15, 0.5, -210)
    main.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    main.BorderSizePixel = 0
    main.Active = true
    main.Draggable = true
    main.Parent = sg
    
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
    local stroke = Instance.new("UIStroke", main)
    stroke.Color = Color3.fromRGB(120, 80, 255)
    stroke.Thickness = 2
    
    -- Header
    local header = Instance.new("Frame", main)
    header.Size = UDim2.new(1, 0, 0, 35)
    header.BackgroundColor3 = Color3.fromRGB(40, 30, 70)
    header.BorderSizePixel = 0
    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 10)
    
    local title = Instance.new("TextLabel", header)
    title.Size = UDim2.new(1, -40, 1, 0)
    title.BackgroundTransparency = 1
    title.Text = "⚡ DELTA - Lucky Farm"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 14
    title.Font = Enum.Font.GothamBold
    title.Position = UDim2.new(0, 10, 0, 0)
    title.TextXAlignment = Enum.TextXAlignment.Left
    
    -- Botón cerrar
    local close = Instance.new("TextButton", header)
    close.Size = UDim2.new(0, 25, 0, 25)
    close.Position = UDim2.new(1, -30, 0, 5)
    close.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    close.Text = "✕"
    close.TextColor3 = Color3.fromRGB(255, 255, 255)
    close.TextSize = 14
    close.Font = Enum.Font.GothamBold
    close.BorderSizePixel = 0
    Instance.new("UICorner", close).CornerRadius = UDim.new(0, 6)
    close.MouseButton1Click:Connect(function() sg:Destroy() end)
    
    -- Info del jugador
    local info = Instance.new("TextLabel", main)
    info.Size = UDim2.new(1, -20, 0, 30)
    info.Position = UDim2.new(0, 10, 0, 40)
    info.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
    info.BorderSizePixel = 0
    info.Text = "💰 Cash: 0  |  ⚡ Speed: 0"
    info.TextColor3 = Color3.fromRGB(200, 200, 255)
    info.TextSize = 11
    info.Font = Enum.Font.Gotham
    Instance.new("UICorner", info).CornerRadius = UDim.new(0, 6)
    
    -- Scroll
    local scroll = Instance.new("ScrollingFrame", main)
    scroll.Size = UDim2.new(1, -10, 1, -85)
    scroll.Position = UDim2.new(0, 5, 0, 75)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 4
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    
    local layout = Instance.new("UIListLayout", scroll)
    layout.Padding = UDim.new(0, 4)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    
    -- Función para crear toggle
    local function mkToggle(text, key, order, callback)
        local btn = Instance.new("TextButton", scroll)
        btn.Size = UDim2.new(1, -5, 0, 32)
        btn.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
        btn.BorderSizePixel = 0
        btn.Text = "  " .. text .. "  [ OFF ]"
        btn.TextColor3 = Color3.fromRGB(220, 220, 220)
        btn.TextSize = 12
        btn.Font = Enum.Font.GothamMedium
        btn.TextXAlignment = Enum.TextXAlignment.Left
        btn.LayoutOrder = order
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
        
        btn.MouseButton1Click:Connect(function()
            CFG[key] = not CFG[key]
            if CFG[key] then
                btn.Text = "  " .. text .. "  [ ON ]"
                btn.BackgroundColor3 = Color3.fromRGB(60, 140, 60)
                btn.TextColor3 = Color3.fromRGB(200, 255, 200)
                if callback then task.spawn(callback) end
            else
                btn.Text = "  " .. text .. "  [ OFF ]"
                btn.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
                btn.TextColor3 = Color3.fromRGB(220, 220, 220)
            end
        end)
    end
    
    -- Botones
    mkToggle("🚀 Auto Steal", "AutoSteal", 1, autoStealLoop)
    mkToggle("💰 Auto Sell", "AutoSell", 2, autoSellLoop)
    mkToggle("💵 Auto Claim Earnings", "AutoClaim", 3, autoClaimLoop)
    mkToggle("🔄 Auto Rebirth", "AutoRebirth", 4, autoRebirthLoop)
    mkToggle("✨ Auto Polish", "AutoPolish", 5, autoPolishLoop)
    mkToggle("📦 Auto Collect All (Jail)", "AutoCollect", 6, autoCollectLoop)
    mkToggle("📚 Auto Tutorial", "AutoTutorial", 7, autoTutorialLoop)
    mkToggle("🏃 Auto Treadmill", "AutoTreadmill", 8, autoTreadmillLoop)
    mkToggle("👻 Noclip", "Noclip", 9, function() setNoclip(true) end)
    mkToggle("⚡ Speed Hack (100)", "SpeedHack", 10, speedLoop)
    mkToggle("👁️ ESP Items", "ESP", 11, espLoop)
    
    -- Botón limpiar (no toggle)
    local cleanBtn = Instance.new("TextButton", scroll)
    cleanBtn.Size = UDim2.new(1, -5, 0, 32)
    cleanBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
    cleanBtn.BorderSizePixel = 0
    cleanBtn.Text = "  🧹 Limpiar todos los toggles"
    cleanBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    cleanBtn.TextSize = 12
    cleanBtn.Font = Enum.Font.GothamMedium
    cleanBtn.LayoutOrder = 12
    cleanBtn.TextXAlignment = Enum.TextXAlignment.Left
    Instance.new("UICorner", cleanBtn).CornerRadius = UDim.new(0, 6)
    cleanBtn.MouseButton1Click:Connect(function()
        for k, _ in pairs(CFG) do
            if type(CFG[k]) == "boolean" then CFG[k] = false end
        end
        setNoclip(false)
        clearESP()
        sg:Destroy()
        notify("Delta", "Todos los toggles reiniciados", 2)
        task.wait(0.1)
        createUI()
    end)
    
    -- Actualizar info cada segundo
    task.spawn(function()
        while sg.Parent do
            task.wait(1)
            local cash = Leaderstats:FindFirstChild("Cash")
            local speed = Leaderstats:FindFirstChild("Speed")
            info.Text = "💰 Cash: " .. (cash and cash.Value or "?") 
                     .. "  |  ⚡ Speed: " .. (speed and speed.Value or "?")
        end
    end)
end

-- ═══════════════════════════════════════════════════════════
-- INICIALIZACIÓN
-- ═══════════════════════════════════════════════════════════
-- Reconectar al respawn
LP.CharacterAdded:Connect(function(c)
    Char = c
    Hum = c:WaitForChild("Humanoid")
    Root = c:WaitForChild("HumanoidRootPart")
    task.wait(1)
    if CFG.Noclip then setNoclip(true) end
end)

-- Anti-AFK siempre activo
enableAntiAFK()

-- Crear UI
task.wait(1)
createUI()

notify("⚡ Delta Script", "¡Cargado correctamente!", 4)
print("[Delta] Script cargado")
print("[Delta] fireproximityprompt:", tostring(fireproximityprompt ~= nil))
print("[Delta] firetouchinterest:", tostring(firetouchinterest ~= nil))
