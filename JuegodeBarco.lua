-- Recolección automática de cofres + entrega en tu barco (Delta) - Móvil
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

---------------------------------------------------------------
-- CONFIGURACIÓN (velocidades y valores base, aquí en el código)
---------------------------------------------------------------
local CONFIG = {
    VELOCIDAD_DESLIZAR = 45,        -- studs/segundo en modo "Deslizar"
    MODO_INICIAL = "TP",            -- "TP" o "DESLIZAR"
    ESPERA_INICIAL_BARCO = 5,       -- segundos iniciales en el barco (se cambia en la UI)
    ESPERA_MAXIMA = 60,
    ESPERA_PROMPT = 0.3,
    ESPERA_ENTRE_RONDAS = 2,
    NOMBRE_BARCO_MANUAL = "",       -- nombre exacto de tu barco si lo sabes
    NOMBRES_DEPOSITO = { "Deposit", "Store", "Sell", "Guardar", "Vender" },
}

---------------------------------------------------------------
-- ESTADO
---------------------------------------------------------------
local running = true
local closed = false
local mode = CONFIG.MODO_INICIAL
local waitInBoat = CONFIG.ESPERA_INICIAL_BARCO
local cachedShip = nil
local collectedCount = 0
local statusText = "Listo"

local refreshUI -- se define en la sección de UI

---------------------------------------------------------------
-- UTILIDADES DE MOVIMIENTO
---------------------------------------------------------------
local function getRoot()
    local character = LocalPlayer.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

-- Deslizarse suavemente hacia una posición
local function glideTo(targetPos, speed)
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

-- Mover según el modo elegido en la UI
local function moveTo(targetPos)
    if mode == "TP" then
        local root = getRoot()
        if root then
            root.CFrame = CFrame.new(targetPos) * root.CFrame.Rotation
            task.wait(0.1)
        end
    else
        glideTo(targetPos, CONFIG.VELOCIDAD_DESLIZAR)
    end
end

---------------------------------------------------------------
-- IDENTIFICAR TU BARCO
---------------------------------------------------------------
local function isMyShip(ship)
    local name = LocalPlayer.Name
    local userId = tostring(LocalPlayer.UserId)

    for _, attr in ipairs({ "Owner", "OwnerName", "OwnerId", "Player", "UserId" }) do
        local v = ship:GetAttribute(attr)
        if v ~= nil and (tostring(v) == name or tostring(v) == userId) then
            return true
        end
    end

    for _, d in ipairs(ship:GetDescendants()) do
        if d:IsA("ObjectValue") and d.Value == LocalPlayer then
            return true
        elseif d:IsA("StringValue") and (d.Value == name or d.Value == userId) then
            return true
        elseif (d:IsA("IntValue") or d:IsA("NumberValue")) and tostring(d.Value) == userId then
            return true
        end
    end

    if ship.Name:find(name, 1, true) or ship.Name:find(userId, 1, true) then
        return true
    end

    for _, d in ipairs(ship:GetDescendants()) do
        if (d:IsA("Seat") or d:IsA("VehicleSeat")) and d.Occupant
            and d.Occupant.Parent == LocalPlayer.Character then
            return true
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
-- ESPERA EN EL BARCO (configurable desde la UI)
---------------------------------------------------------------
local function waitAtBoat()
    local endTime = os.clock() + waitInBoat
    while os.clock() < endTime and running and not closed do
        statusText = string.format("En el barco: %ds", math.ceil(endTime - os.clock()))
        refreshUI()
        task.wait(0.25)
    end
end

---------------------------------------------------------------
-- CICLO: cofre → barco → esperar → siguiente
---------------------------------------------------------------
local function collectRound()
    for _, chest in ipairs(findChestPrompts()) do
        if closed or not running then return end
        if not chest.prompt.Parent then continue end

        statusText = "Yendo a cofre..."
        refreshUI()
        moveTo(chest.base.Position + Vector3.new(0, 3, 0))
        task.wait(0.1)

        pcall(fireproximityprompt, chest.prompt)
        task.wait(CONFIG.ESPERA_PROMPT)
        collectedCount += 1

        local ship = getMyShip()
        if ship then
            statusText = "Llevando al barco..."
            refreshUI()
            moveTo(getShipPosition(ship))
            depositInShip(ship)
            waitAtBoat()
        else
            statusText = "No encuentro tu barco"
            refreshUI()
        end
    end
end

---------------------------------------------------------------
-- UI MÓVIL
---------------------------------------------------------------
local PALETTE = {
    bg = Color3.fromRGB(22, 24, 34),
    card = Color3.fromRGB(34, 37, 52),
    accent = Color3.fromRGB(110, 150, 255),
    green = Color3.fromRGB(70, 190, 120),
    orange = Color3.fromRGB(245, 160, 60),
    red = Color3.fromRGB(220, 80, 90),
    text = Color3.fromRGB(240, 242, 250),
    muted = Color3.fromRGB(150, 156, 180),
}

local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "CofresUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

local function addCorner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = parent
end

local function addStroke(parent, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color
    s.Thickness = thickness or 1
    s.Transparency = transparency or 0
    s.Parent = parent
end

local function makeLabel(parent, text, size, color, bold, order, height)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Size = UDim2.new(1, 0, 0, height or 20)
    l.Text = text
    l.TextSize = size
    l.TextColor3 = color
    l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.LayoutOrder = order or 0
    l.Parent = parent
    return l
end

local function makeButton(parent, text, size, color, order)
    local b = Instance.new("TextButton")
    b.Size = size
    b.BackgroundColor3 = color
    b.Text = text
    b.TextColor3 = PALETTE.text
    b.TextSize = 16
    b.Font = Enum.Font.GothamBold
    b.AutoButtonColor = true
    b.BorderSizePixel = 0
    b.LayoutOrder = order or 0
    b.Parent = parent
    addCorner(b, 12)
    return b
end

-- Arrastrar con dedo o mouse
local function makeDraggable(handle, frame)
    local dragging, startInput, startPos = false, nil, nil

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
main.Size = UDim2.new(0, 300, 0, 390)
main.Position = UDim2.new(0.5, -150, 0.25, 0)
main.BackgroundColor3 = PALETTE.bg
main.BorderSizePixel = 0
main.Parent = gui
addCorner(main, 18)
addStroke(main, PALETTE.accent, 1.5, 0.4)

-- Cabecera
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 56)
header.BackgroundTransparency = 1
header.Parent = main

local titleLabel = Instance.new("TextLabel")
titleLabel.BackgroundTransparency = 1
titleLabel.Position = UDim2.new(0, 16, 0, 8)
titleLabel.Size = UDim2.new(1, -110, 0, 24)
titleLabel.Text = "🏴‍☠️ Cofres"
titleLabel.TextSize = 18
titleLabel.TextColor3 = PALETTE.text
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = header

local subtitleLabel = Instance.new("TextLabel")
subtitleLabel.BackgroundTransparency = 1
subtitleLabel.Position = UDim2.new(0, 16, 0, 30)
subtitleLabel.Size = UDim2.new(1, -110, 0, 18)
subtitleLabel.Text = statusText
subtitleLabel.TextSize = 13
subtitleLabel.TextColor3 = PALETTE.muted
subtitleLabel.Font = Enum.Font.Gotham
subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
subtitleLabel.TextTruncate = Enum.TextTruncate.AtEnd
subtitleLabel.Parent = header

local minBtn = makeButton(header, "—", UDim2.new(0, 38, 0, 38), PALETTE.card)
minBtn.Position = UDim2.new(1, -92, 0, 9)
local closeBtn = makeButton(header, "✕", UDim2.new(0, 38, 0, 38), PALETTE.red)
closeBtn.Position = UDim2.new(1, -48, 0, 9)

-- Cuerpo
local body = Instance.new("Frame")
body.Position = UDim2.new(0, 0, 0, 56)
body.Size = UDim2.new(1, 0, 1, -56)
body.BackgroundTransparency = 1
body.Parent = main

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 10)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = body

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 16)
padding.PaddingRight = UDim.new(0, 16)
padding.PaddingTop = UDim.new(0, 6)
padding.Parent = body

-- Tarjeta de contador
local statCard = Instance.new("Frame")
statCard.Size = UDim2.new(1, 0, 0, 64)
statCard.BackgroundColor3 = PALETTE.card
statCard.BorderSizePixel = 0
statCard.LayoutOrder = 1
statCard.Parent = body
addCorner(statCard, 14)

makeLabel(statCard, "COFRES RECOGIDOS", 11, PALETTE.muted, true, 0, 16).Position = UDim2.new(0, 14, 0, 10)
local countLabel = Instance.new("TextLabel")
countLabel.BackgroundTransparency = 1
countLabel.Position = UDim2.new(0, 14, 0, 26)
countLabel.Size = UDim2.new(1, -28, 0, 30)
countLabel.Text = "0"
countLabel.TextSize = 24
countLabel.TextColor3 = PALETTE.green
countLabel.Font = Enum.Font.GothamBold
countLabel.TextXAlignment = Enum.TextXAlignment.Left
countLabel.Parent = statCard

-- Selector de modo
makeLabel(body, "MODO DE VIAJE", 11, PALETTE.muted, true, 2, 16)

local modeRow = Instance.new("Frame")
modeRow.Size = UDim2.new(1, 0, 0, 44)
modeRow.BackgroundTransparency = 1
modeRow.LayoutOrder = 3
modeRow.Parent = body

local modeLayout = Instance.new("UIListLayout")
modeLayout.FillDirection = Enum.FillDirection.Horizontal
modeLayout.Padding = UDim.new(0, 8)
modeLayout.Parent = modeRow

local tpBtn = makeButton(modeRow, "⚡ Teletransporte", UDim2.new(0.5, -4, 1, 0), PALETTE.card, 1)
local glideBtn = makeButton(modeRow, "🌊 Deslizar", UDim2.new(0.5, -4, 1, 0), PALETTE.card, 2)

-- Selector de espera en el barco
makeLabel(body, "ESPERA EN EL BARCO", 11, PALETTE.muted, true, 4, 16)

local waitRow = Instance.new("Frame")
waitRow.Size = UDim2.new(1, 0, 0, 44)
waitRow.BackgroundColor3 = PALETTE.card
waitRow.BorderSizePixel = 0
waitRow.LayoutOrder = 5
waitRow.Parent = body
addCorner(waitRow, 12)

local minusBtn = makeButton(waitRow, "−", UDim2.new(0, 56, 0, 36), PALETTE.bg, 0)
minusBtn.Position = UDim2.new(0, 4, 0, 4)
local plusBtn = makeButton(waitRow, "+", UDim2.new(0, 56, 0, 36), PALETTE.bg, 0)
plusBtn.Position = UDim2.new(1, -60, 0, 4)

local waitLabel = Instance.new("TextLabel")
waitLabel.BackgroundTransparency = 1
waitLabel.Size = UDim2.new(1, -130, 1, 0)
waitLabel.Position = UDim2.new(0, 65, 0, 0)
waitLabel.TextSize = 18
waitLabel.TextColor3 = PALETTE.text
waitLabel.Font = Enum.Font.GothamBold
waitLabel.Parent = waitRow

-- Botón pausa / reanudar
local toggleBtn = makeButton(body, "", UDim2.new(1, 0, 0, 50), PALETTE.green, 6)

-- Mini botón (cuadrado al minimizar)
local mini = makeButton(gui, "🏴‍☠️", UDim2.new(0, 60, 0, 60), PALETTE.card, 0)
mini.Position = UDim2.new(0, 16, 0.5, 0)
mini.TextSize = 26
mini.Visible = false
addStroke(mini, PALETTE.accent, 1.5, 0.3)

makeDraggable(header, main)
makeDraggable(mini, mini)

---------------------------------------------------------------
-- ACTUALIZAR UI
---------------------------------------------------------------
refreshUI = function()
    subtitleLabel.Text = statusText
    countLabel.Text = tostring(collectedCount)
    waitLabel.Text = waitInBoat .. " s"

    tpBtn.BackgroundColor3 = mode == "TP" and PALETTE.accent or PALETTE.card
    glideBtn.BackgroundColor3 = mode == "DESLIZAR" and PALETTE.accent or PALETTE.card

    toggleBtn.Text = running and "⏸  Pausar" or "▶  Reanudar"
    toggleBtn.BackgroundColor3 = running and PALETTE.green or PALETTE.orange
end

---------------------------------------------------------------
-- EVENTOS
---------------------------------------------------------------
tpBtn.Activated:Connect(function()
    mode = "TP"
    refreshUI()
end)

glideBtn.Activated:Connect(function()
    mode = "DESLIZAR"
    refreshUI()
end)

minusBtn.Activated:Connect(function()
    waitInBoat = math.max(0, waitInBoat - 1)
    refreshUI()
end)

plusBtn.Activated:Connect(function()
    waitInBoat = math.min(CONFIG.ESPERA_MAXIMA, waitInBoat + 1)
    refreshUI()
end)

toggleBtn.Activated:Connect(function()
    running = not running
    statusText = running and "Buscando cofres..." or "Pausado"
    refreshUI()
end)

minBtn.Activated:Connect(function()
    main.Visible = false
    mini.Position = UDim2.new(0, main.AbsolutePosition.X, 0, main.AbsolutePosition.Y)
    mini.Visible = true
end)

mini.Activated:Connect(function()
    mini.Visible = false
    main.Visible = true
end)

closeBtn.Activated:Connect(function()
    closed = true
    running = false
    gui:Destroy()
end)

---------------------------------------------------------------
-- BUCLE PRINCIPAL SEGURO
---------------------------------------------------------------
task.spawn(function()
    while not closed do
        if running then
            pcall(collectRound)
            if not closed and running then
                statusText = "Esperando nuevos cofres..."
                refreshUI()
            end
        end
        task.wait(CONFIG.ESPERA_ENTRE_RONDAS)
    end
end)

refreshUI()
