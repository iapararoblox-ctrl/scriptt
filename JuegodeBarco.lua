-- Recolección automática de cofres + entrega en tu barco (Delta)
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local Workspace = game:GetService("Workspace")

---------------------------------------------------------------
-- CONFIGURACIÓN (cambia aquí, no desde la UI)
---------------------------------------------------------------
local CONFIG = {
    VELOCIDAD_COFRE = 45,         -- studs/segundo al ir a un cofre
    VELOCIDAD_BARCO = 45,         -- studs/segundo al ir al barco
    ESPERA_ENTRE_RONDAS = 3,      -- segundos entre cada revisión de cofres
    ESPERA_PROMPT = 0.3,          -- pausa después de activar un prompt
    NOMBRE_BARCO_MANUAL = "",     -- si lo sabes, pon el nombre exacto de tu barco
    NOMBRES_DEPOSITO = { "Deposit", "Store", "Sell", "Guardar", "Vender" },
}

---------------------------------------------------------------
-- ESTADO
---------------------------------------------------------------
local running = true
local closed = false
local cachedShip = nil
local collectedCount = 0
local statusText = "Listo"

---------------------------------------------------------------
-- UTILIDADES
---------------------------------------------------------------
local function getRoot()
    local character = LocalPlayer.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

-- Movimiento suave hacia una posición (sin teleport brusco)
local function smoothMoveTo(targetPos, speed)
    local root = getRoot()
    if not root then return end

    local startPos = root.Position
    local duration = math.max((targetPos - startPos).Magnitude / speed, 0.05)
    local t0 = os.clock()
    local alpha = 0

    while alpha < 1 and running and not closed do
        root = getRoot()
        if not root then break end
        alpha = math.min((os.clock() - t0) / duration, 1)
        root.CFrame = CFrame.new(startPos:Lerp(targetPos, alpha)) * root.CFrame.Rotation
        task.wait()
    end
end

---------------------------------------------------------------
-- IDENTIFICAR TU BARCO
---------------------------------------------------------------
local function isMyShip(ship)
    local name = LocalPlayer.Name
    local userId = tostring(LocalPlayer.UserId)

    -- 1) Atributos comunes de dueño
    for _, attr in ipairs({ "Owner", "OwnerName", "OwnerId", "Player", "UserId" }) do
        local v = ship:GetAttribute(attr)
        if v ~= nil and (tostring(v) == name or tostring(v) == userId) then
            return true
        end
    end

    -- 2) Valores hijos (ObjectValue / StringValue / IntValue)
    for _, d in ipairs(ship:GetDescendants()) do
        if d:IsA("ObjectValue") and d.Value == LocalPlayer then
            return true
        elseif d:IsA("StringValue") and (d.Value == name or d.Value == userId) then
            return true
        elseif (d:IsA("IntValue") or d:IsA("NumberValue")) and tostring(d.Value) == userId then
            return true
        end
    end

    -- 3) Nombre del barco contiene tu nombre o tu UserId
    if ship.Name:find(name, 1, true) or ship.Name:find(userId, 1, true) then
        return true
    end

    -- 4) Tu personaje está sentado en un asiento del barco
    for _, d in ipairs(ship:GetDescendants()) do
        if d:IsA("Seat") or d:IsA("VehicleSeat") then
            if d.Occupant and d.Occupant.Parent == LocalPlayer.Character then
                return true
            end
        end
    end

    return false
end

local function getMyShip()
    if cachedShip and cachedShip.Parent then
        return cachedShip
    end
    cachedShip = nil

    local world = Workspace:FindFirstChild("World")
    local dynamic = world and world:FindFirstChild("Dynamic")
    local shipsFolder = dynamic and dynamic:FindFirstChild("Ships")
    if not shipsFolder then return nil end

    for _, ship in ipairs(shipsFolder:GetChildren()) do
        local match
        if CONFIG.NOMBRE_BARCO_MANUAL ~= "" then
            match = ship.Name == CONFIG.NOMBRE_BARCO_MANUAL
        else
            match = isMyShip(ship)
        end
        if match then
            cachedShip = ship
            return ship
        end
    end
    return nil
end

local function getShipPosition(ship)
    local cf = ship:IsA("Model") and ship:GetPivot() or ship.CFrame
    return cf.Position + Vector3.new(0, 5, 0)
end

local function depositInShip(ship)
    for _, d in ipairs(ship:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            for _, keyword in ipairs(CONFIG.NOMBRES_DEPOSITO) do
                if d.Name:find(keyword, 1, true) or d.ActionText:find(keyword, 1, true) then
                    pcall(fireproximityprompt, d)
                    task.wait(CONFIG.ESPERA_PROMPT)
                end
            end
        end
    end
end

---------------------------------------------------------------
-- BUSCAR COFRES
---------------------------------------------------------------
local function findChestPrompts()
    local list = {}
    local world = Workspace:FindFirstChild("World")
    local dynamic = world and world:FindFirstChild("Dynamic")
    if not dynamic then return list end

    local treasure = dynamic:FindFirstChild("Treasure")
    if treasure then
        for _, obj in ipairs(treasure:GetChildren()) do
            local base = obj:FindFirstChild("Base")
            local attach = base and base:FindFirstChild("PromptAttachment")
            local prompt = attach and attach:FindFirstChild("TreasurePrompt")
            if base and prompt and prompt:IsA("ProximityPrompt") then
                table.insert(list, { base = base, prompt = prompt })
            end
        end
    end

    local halloween = dynamic:FindFirstChild("Halloween")
    if halloween then
        for _, obj in ipairs(halloween:GetChildren()) do
            local base = obj:FindFirstChild("Base")
            local grab = base and base:FindFirstChild("Grab")
            if base and grab and grab:IsA("ProximityPrompt") then
                table.insert(list, { base = base, prompt = grab })
            end
        end
    end

    return list
end

---------------------------------------------------------------
-- CICLO PRINCIPAL: cofre → barco → depositar
---------------------------------------------------------------
local updateUI -- se define más abajo

local function collectRound()
    for _, chest in ipairs(findChestPrompts()) do
        if closed or not running then return end
        if not chest.prompt.Parent then continue end

        statusText = "Yendo a cofre..."
        updateUI()
        smoothMoveTo(chest.base.Position + Vector3.new(0, 3, 0), CONFIG.VELOCIDAD_COFRE)
        task.wait(0.1)

        pcall(fireproximityprompt, chest.prompt)
        task.wait(CONFIG.ESPERA_PROMPT)
        collectedCount += 1

        local ship = getMyShip()
        if ship then
            statusText = "Llevando al barco..."
            updateUI()
            smoothMoveTo(getShipPosition(ship), CONFIG.VELOCIDAD_BARCO)
            depositInShip(ship)
        else
            statusText = "No encuentro tu barco"
            updateUI()
        end
    end
end

---------------------------------------------------------------
-- UI MÓVIL
---------------------------------------------------------------
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "CofresUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

local function corner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = parent
    return c
end

local function makeButton(text, size, pos, parent, color)
    local b = Instance.new("TextButton")
    b.Size = size
    b.Position = pos
    b.BackgroundColor3 = color
    b.Text = text
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.TextScaled = true
    b.Font = Enum.Font.GothamBold
    b.AutoButtonColor = true
    b.Parent = parent
    corner(b, 8)
    return b
end

-- Hacer arrastrable un frame con dedo o mouse
local function makeDraggable(handle, frame)
    local dragging = false
    local startInput, startPos

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            startInput = input.Position
            startPos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseMovement) then
            local d = input.Position - startInput
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y
            )
        end
    end)
end

-- Panel principal
local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.new(0, 270, 0, 190)
main.Position = UDim2.new(0.5, -135, 0.3, 0)
main.BackgroundColor3 = Color3.fromRGB(28, 30, 40)
main.BorderSizePixel = 0
main.Parent = gui
corner(main, 14)

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 40)
titleBar.BackgroundColor3 = Color3.fromRGB(45, 48, 64)
titleBar.BorderSizePixel = 0
titleBar.Parent = main
corner(titleBar, 14)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -90, 1, 0)
title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Text = "Cofres"
title.TextColor3 = Color3.fromRGB(235, 235, 245)
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextScaled = true
title.Font = Enum.Font.GothamBold
title.Parent = titleBar

local minBtn = makeButton("–", UDim2.new(0, 34, 0, 28), UDim2.new(1, -78, 0, 6), titleBar, Color3.fromRGB(70, 110, 200))
local closeBtn = makeButton("✕", UDim2.new(0, 34, 0, 28), UDim2.new(1, -40, 0, 6), titleBar, Color3.fromRGB(190, 70, 70))

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -24, 0, 30)
statusLabel.Position = UDim2.new(0, 12, 0, 52)
statusLabel.BackgroundTransparency = 1
statusLabel.TextColor3 = Color3.fromRGB(180, 200, 255)
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextScaled = true
statusLabel.Font = Enum.Font.Gotham
statusLabel.Text = statusText
statusLabel.Parent = main

local countLabel = Instance.new("TextLabel")
countLabel.Size = UDim2.new(1, -24, 0, 24)
countLabel.Position = UDim2.new(0, 12, 0, 86)
countLabel.BackgroundTransparency = 1
countLabel.TextColor3 = Color3.fromRGB(235, 235, 245)
countLabel.TextXAlignment = Enum.TextXAlignment.Left
countLabel.TextScaled = true
countLabel.Font = Enum.Font.GothamBold
countLabel.Text = "Cofres: 0"
countLabel.Parent = main

local toggleBtn = makeButton("⏸ Pausar", UDim2.new(1, -24, 0, 46), UDim2.new(0, 12, 1, -58), main, Color3.fromRGB(60, 150, 90))

-- Botón minimizado (cuadrado)
local mini = makeButton("🏴‍☠️", UDim2.new(0, 56, 0, 56), UDim2.new(0, 16, 0.5, 0), gui, Color3.fromRGB(45, 48, 64))
mini.Visible = false
mini.TextScaled = true

makeDraggable(titleBar, main)
makeDraggable(mini, mini)

updateUI = function()
    statusLabel.Text = statusText
    countLabel.Text = "Cofres: " .. collectedCount
    toggleBtn.Text = running and "⏸ Pausar" or "▶ Reanudar"
    toggleBtn.BackgroundColor3 = running and Color3.fromRGB(60, 150, 90) or Color3.fromRGB(200, 140, 40)
end

minBtn.Activated:Connect(function()
    main.Visible = false
    mini.Position = UDim2.new(0, main.AbsolutePosition.X, 0, main.AbsolutePosition.Y)
    mini.Visible = true
end)

mini.Activated:Connect(function()
    mini.Visible = false
    main.Visible = true
end)

toggleBtn.Activated:Connect(function()
    running = not running
    if not running then statusText = "Pausado" else statusText = "Buscando cofres..." end
    updateUI()
end)

closeBtn.Activated:Connect(function()
    closed = true
    running = false
    gui:Destroy()
end)

---------------------------------------------------------------
-- BUCLE SEGURO
---------------------------------------------------------------
task.spawn(function()
    while not closed do
        if running then
            pcall(collectRound)
            if not closed and running then
                statusText = "Esperando nuevos cofres..."
                updateUI()
            end
        end
        task.wait(CONFIG.ESPERA_ENTRE_RONDAS)
    end
end)

updateUI()
