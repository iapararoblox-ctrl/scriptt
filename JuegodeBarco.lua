-- Recolección de cofres + entrega en barco + apertura en el tesorero (Ser pirata, Móvil)
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

---------------------------------------------------------------
-- CONFIGURACIÓN (aquí en el código)
---------------------------------------------------------------
local CONFIG = {
    VELOCIDAD_DESLIZAR = 45,
    MODO_INICIAL = "TP",              -- "TP" o "DESLIZAR"
    AGARRAR_INICIAL = false,          -- desactivado por defecto, lo activas en la UI
    ABRIR_RAPIDO = true,              -- usa FastOpen al abrir cofres
    ESPERA_INICIAL_BARCO = 5,
    ESPERA_MAXIMA = 60,
    ESPERA_PROMPT = 0.3,
    ESPERA_ENTRE_RONDAS = 2,
    NOMBRE_BARCO_MANUAL = "",         -- nombre exacto de tu barco si lo sabes
    NOMBRES_DEPOSITO = { "Deposit", "Store", "Sell", "Guardar", "Vender" },
    MAX_APERTURAS = 20,
    PAUSA_APERTURA = 0.6,

    -- TESORERO (pon aquí su posición exacta y la ruta de su prompt, si tiene)
    POSICION_TESORERO = nil,          -- ejemplo: Vector3.new(x, y, z)
    RUTA_PROMPT_TESORERO = nil,       -- ejemplo: { "World", "Dynamic", "NPCs", "NombreNPC", "HumanoidRootPart", "NPCPrompt_1", "NPCPrompt" }
}

---------------------------------------------------------------
-- REMOTES
---------------------------------------------------------------
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
local function getRemote(name)
    return Remotes and Remotes:FindFirstChild(name)
end

---------------------------------------------------------------
-- ESTADO
---------------------------------------------------------------
local running = true
local closed = false
local mode = CONFIG.MODO_INICIAL
local grabChests = CONFIG.AGARRAR_INICIAL
local waitInBoat = CONFIG.ESPERA_INICIAL_BARCO
local holdFullManual = false
local cachedShip = nil
local collectedCount = 0
local openedCount = 0
local statusText = "Listo"

local refreshUI

---------------------------------------------------------------
-- MOVIMIENTO
---------------------------------------------------------------
local function getRoot()
    local character = LocalPlayer.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

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
-- TU BARCO
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
-- ESTADO DE LA BÓVEDA DEL BARCO
-- Busca en el HUD un texto tipo "12/12" relacionado con el barco.
-- Si no lo detecta, usa el botón manual "Vaciar".
---------------------------------------------------------------
local function isHoldFull()
    if holdFullManual then return true end

    local hud = LocalPlayer.PlayerGui:FindFirstChild("HUD")
    if not hud then return false end

    for _, obj in ipairs(hud:GetDescendants()) do
        if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and obj.Visible then
            local cur, max = obj.Text:match("(%d+)%s*/%s*(%d+)")
            if cur and max then
                local n = obj.Name:lower()
                local related = obj:FindFirstAncestor("Ship") ~= nil
                    or n:find("cargo") or n:find("hold") or n:find("bodega") or n:find("capacity")
                if related and tonumber(max) > 0 and tonumber(cur) >= tonumber(max) then
                    return true
                end
            end
        end
    end
    return false
end

---------------------------------------------------------------
-- TESORERO
---------------------------------------------------------------
local function getTreasurerPrompt()
    if not CONFIG.RUTA_PROMPT_TESORERO then return nil end

    local node = Workspace
    for _, name in ipairs(CONFIG.RUTA_PROMPT_TESORERO) do
        node = node and node:FindFirstChild(name)
    end
    if node and node:IsA("ProximityPrompt") then
        return node
    end
    return nil
end

local function openStoredTreasures()
    local openRemote = getRemote("Treasure_Open")
    local settingsRemote = getRemote("Settings_Set")

    if CONFIG.ABRIR_RAPIDO and settingsRemote and settingsRemote:IsA("RemoteEvent") then
        pcall(function()
            settingsRemote:FireServer("FastOpen", true)
        end)
        task.wait(0.2)
    end

    if openRemote and openRemote:IsA("RemoteEvent") then
        for _ = 1, CONFIG.MAX_APERTURAS do
            if closed or not running then break end

            pcall(function()
                openRemote:FireServer("All", nil, CONFIG.ABRIR_RAPIDO)
            end)

            openedCount += 1
            refreshUI()
            task.wait(CONFIG.PAUSA_APERTURA)

            if not isHoldFull() then break end
        end
    end

    holdFullManual = false
end

local function goToTreasurerAndOpen()
    if not CONFIG.POSICION_TESORERO then
        statusText = "Falta POSICION_TESORERO en CONFIG"
        refreshUI()
        return
    end

    statusText = "Bóveda llena: yendo al tesorero..."
    refreshUI()
    moveTo(CONFIG.POSICION_TESORERO + Vector3.new(0, 3, 0))

    local prompt = getTreasurerPrompt()
    if prompt then
        pcall(fireproximityprompt, prompt)
        task.wait(CONFIG.ESPERA_PROMPT)
    end

    statusText = "Abriendo cofres..."
    refreshUI()
    openStoredTreasures()
    statusText = "Bóveda vacía, volviendo a buscar cofres"
    refreshUI()
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
-- ESPERA EN EL BARCO
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
-- CICLO
---------------------------------------------------------------
local function collectRound()
    if isHoldFull() then
        goToTreasurerAndOpen()
        return
    end

    for _, chest in ipairs(findChestPrompts()) do
        if closed or not running then return end
        if not chest.prompt.Parent then continue end

        if isHoldFull() then
            goToTreasurerAndOpen()
            return
        end

        statusText = "Yendo a cofre..."
        refreshUI()
        moveTo(chest.base.Position + Vector3.new(0, 3, 0))
        task.wait(0.1)

        pcall(fireproximityprompt, chest.prompt)
        task.wait(CONFIG.ESPERA_PROMPT)
        collectedCount += 1

        if grabChests then
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
end

---------------------------------------------------------------
-- UI ADAPTATIVA
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
    l.Size = UDim2.new(1, 0, 0, height or 16)
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
    b.TextSize = 13
    b.Font = Enum.Font.GothamBold
    b.AutoButtonColor = true
    b.BorderSizePixel = 0
    b.LayoutOrder = order or 0
    b.Parent = parent
    addCorner(b, 10)
    return b
end

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

local main = Instance.new("Frame")
main.Name = "Main"
main.AnchorPoint = Vector2.new(0.5, 0.5)
main.Position = UDim2.new(0.5, 0, 0.5, 0)
main.Size = UDim2.new(0, 260, 0, 310)
main.BackgroundColor3 = PALETTE.bg
main.BorderSizePixel = 0
main.Parent = gui
addCorner(main, 16)
addStroke(main, PALETTE.accent, 1.2, 0.4)

local mainScale = Instance.new("UIScale")
mainScale.Parent = main

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 46)
header.BackgroundTransparency = 1
header.Parent = main

local titleLabel = Instance.new("TextLabel")
titleLabel.BackgroundTransparency = 1
titleLabel.Position = UDim2.new(0, 14, 0, 6)
titleLabel.Size = UDim2.new(1, -100, 0, 20)
titleLabel.Text = "🏴‍☠️ Cofres"
titleLabel.TextSize = 15
titleLabel.TextColor3 = PALETTE.text
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = header

local subtitleLabel = Instance.new("TextLabel")
subtitleLabel.BackgroundTransparency = 1
subtitleLabel.Position = UDim2.new(0, 14, 0, 26)
subtitleLabel.Size = UDim2.new(1, -100, 0, 14)
subtitleLabel.Text = statusText
subtitleLabel.TextSize = 11
subtitleLabel.TextColor3 = PALETTE.muted
subtitleLabel.Font = Enum.Font.Gotham
subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
subtitleLabel.TextTruncate = Enum.TextTruncate.AtEnd
subtitleLabel.Parent = header

local minBtn = makeButton(header, "—", UDim2.new(0, 32, 0, 32), PALETTE.card)
minBtn.Position = UDim2.new(1, -74, 0, 7)
local closeBtn = makeButton(header, "✕", UDim2.new(0, 32, 0, 32), PALETTE.red)
closeBtn.Position = UDim2.new(1, -38, 0, 7)

local body = Instance.new("Frame")
body.Position = UDim2.new(0, 0, 0, 46)
body.Size = UDim2.new(1, 0, 1, -46)
body.BackgroundTransparency = 1
body.Parent = main

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = body

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 12)
padding.PaddingRight = UDim.new(0, 12)
padding.PaddingTop = UDim.new(0, 4)
padding.Parent = body

-- Contadores
local statCard = Instance.new("Frame")
statCard.Size = UDim2.new(1, 0, 0, 52)
statCard.BackgroundColor3 = PALETTE.card
statCard.BorderSizePixel = 0
statCard.LayoutOrder = 1
statCard.Parent = body
addCorner(statCard, 12)

makeLabel(statCard, "RECOGIDOS", 10, PALETTE.muted, true, 0, 14).Position = UDim2.new(0, 12, 0, 8)
local countLabel = Instance.new("TextLabel")
countLabel.BackgroundTransparency = 1
countLabel.Position = UDim2.new(0, 12, 0, 20)
countLabel.Size = UDim2.new(0.5, -12, 0, 26)
countLabel.Text = "0"
countLabel.TextSize = 20
countLabel.TextColor3 = PALETTE.green
countLabel.Font = Enum.Font.GothamBold
countLabel.TextXAlignment = Enum.TextXAlignment.Left
countLabel.Parent = statCard

makeLabel(statCard, "ABIERTOS", 10, PALETTE.muted, true, 0, 14).Position = UDim2.new(0.5, 0, 0, 8)
local openedLabel = Instance.new("TextLabel")
openedLabel.BackgroundTransparency = 1
openedLabel.Position = UDim2.new(0.5, 0, 0, 20)
openedLabel.Size = UDim2.new(0.5, -12, 0, 26)
openedLabel.Text = "0"
openedLabel.TextSize = 20
openedLabel.TextColor3 = PALETTE.accent
openedLabel.Font = Enum.Font.GothamBold
openedLabel.TextXAlignment = Enum.TextXAlignment.Left
openedLabel.Parent = statCard

-- Modo de viaje
local modeRow = Instance.new("Frame")
modeRow.Size = UDim2.new(1, 0, 0, 36)
modeRow.BackgroundTransparency = 1
modeRow.LayoutOrder = 2
modeRow.Parent = body

local modeLayout = Instance.new("UIListLayout")
modeLayout.FillDirection = Enum.FillDirection.Horizontal
modeLayout.Padding = UDim.new(0, 6)
modeLayout.Parent = modeRow

local tpBtn = makeButton(modeRow, "⚡ TP", UDim2.new(0.5, -3, 1, 0), PALETTE.card, 1)
local glideBtn = makeButton(modeRow, "🌊 Deslizar", UDim2.new(0.5, -3, 1, 0), PALETTE.card, 2)

-- Opciones: agarrar / vaciar bóveda
local optRow = Instance.new("Frame")
optRow.Size = UDim2.new(1, 0, 0, 36)
optRow.BackgroundTransparency = 1
optRow.LayoutOrder = 3
optRow.Parent = body

local optLayout = Instance.new("UIListLayout")
optLayout.FillDirection = Enum.FillDirection.Horizontal
optLayout.Padding = UDim.new(0, 6)
optLayout.Parent = optRow

local grabBtn = makeButton(optRow, "🎒 Agarrar", UDim2.new(0.5, -3, 1, 0), PALETTE.card, 1)
local emptyBtn = makeButton(optRow, "📦 Vaciar", UDim2.new(0.5, -3, 1, 0), PALETTE.card, 2)

-- Espera en el barco
local waitRow = Instance.new("Frame")
waitRow.Size = UDim2.new(1, 0, 0, 40)
waitRow.BackgroundColor3 = PALETTE.card
waitRow.BorderSizePixel = 0
waitRow.LayoutOrder = 4
waitRow.Parent = body
addCorner(waitRow, 10)

local minusBtn = makeButton(waitRow, "−", UDim2.new(0, 48, 0, 30), PALETTE.bg, 0)
minusBtn.Position = UDim2.new(0, 5, 0, 5)
local plusBtn = makeButton(waitRow, "+", UDim2.new(0, 48, 0, 30), PALETTE.bg, 0)
plusBtn.Position = UDim2.new(1, -53, 0, 5)

local waitLabel = Instance.new("TextLabel")
waitLabel.BackgroundTransparency = 1
waitLabel.Size = UDim2.new(1, -110, 1, 0)
waitLabel.Position = UDim2.new(0, 55, 0, 0)
waitLabel.TextSize = 14
waitLabel.TextColor3 = PALETTE.text
waitLabel.Font = Enum.Font.GothamBold
waitLabel.Parent = waitRow

-- Pausa
local toggleBtn = makeButton(body, "", UDim2.new(1, 0, 0, 40), PALETTE.green, 5)
toggleBtn.TextSize = 14

-- Mini botón
local mini = makeButton(gui, "🏴‍☠️", UDim2.new(0, 50, 0, 50), PALETTE.card, 0)
mini.TextSize = 22
mini.Visible = false
addStroke(mini, PALETTE.accent, 1.2, 0.3)

local miniScale = Instance.new("UIScale")
miniScale.Parent = mini

makeDraggable(header, main)
makeDraggable(mini, mini)

local camera = Workspace.CurrentCamera
local function updateScale()
    local vp = camera.ViewportSize
    local s = math.clamp(math.min(vp.X / 340, vp.Y / 480), 0.6, 1)
    mainScale.Scale = s
    miniScale.Scale = s
end
updateScale()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)

---------------------------------------------------------------
-- ACTUALIZAR UI
---------------------------------------------------------------
refreshUI = function()
    subtitleLabel.Text = statusText
    countLabel.Text = tostring(collectedCount)
    openedLabel.Text = tostring(openedCount)
    waitLabel.Text = "Espera barco: " .. waitInBoat .. " s"

    tpBtn.BackgroundColor3 = mode == "TP" and PALETTE.accent or PALETTE.card
    glideBtn.BackgroundColor3 = mode == "DESLIZAR" and PALETTE.accent or PALETTE.card
    grabBtn.BackgroundColor3 = grabChests and PALETTE.green or PALETTE.card
    grabBtn.Text = grabChests and "🎒 Agarrar: ON" or "🎒 Agarrar: OFF"
    emptyBtn.BackgroundColor3 = holdFullManual and PALETTE.orange or PALETTE.card

    toggleBtn.Text = running and "⏸  Pausar" or "▶  Reanudar"
    toggleBtn.BackgroundColor3 = running and PALETTE.green or PALETTE.orange
end

---------------------------------------------------------------
-- EVENTOS
---------------------------------------------------------------
tpBtn.Activated:Connect(function() mode = "TP"; refreshUI() end)
glideBtn.Activated:Connect(function() mode = "DESLIZAR"; refreshUI() end)

grabBtn.Activated:Connect(function()
    grabChests = not grabChests
    refreshUI()
end)

emptyBtn.Activated:Connect(function()
    holdFullManual = not holdFullManual
    statusText = holdFullManual and "Se abrirán cofres en el próximo ciclo" or statusText
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
    mini.Position = UDim2.fromOffset(main.AbsolutePosition.X, main.AbsolutePosition.Y)
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
