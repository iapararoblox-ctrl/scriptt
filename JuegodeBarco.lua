-- Cofres: recolección + guardar en la bóveda del barco + apertura con el tesorero (Ser pirata, Móvil)
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

---------------------------------------------------------------
-- CONFIGURACIÓN
---------------------------------------------------------------
local CONFIG = {
    MODO_INICIAL = "TP",              -- "TP" o "DESLIZAR"
    VELOCIDAD_DESLIZAR = 45,          -- studs/s en modo deslizar
    AGARRAR_INICIAL = false,          -- lo activas tú en la UI
    CAPACIDAD_INICIAL = 10,           -- cofres que caben en la bóveda (ajustable en la UI)
    CAPACIDAD_MAX = 50,
    ESPERA_INICIAL_BARCO = 5,         -- segundos encima del barco antes del siguiente cofre
    ESPERA_MAXIMA = 60,
    ALTURA_SOBRE_BARCO = 3,           -- cuántos studs por encima de la cubierta te paras
    ESPERA_GUARDADO = 5,              -- segundos máximos esperando a que el cofre se guarde
    ESPERA_PROMPT = 0.3,
    ESPERA_UI_TESORERO = 1.5,         -- pausa para que abra la interfaz del tesorero
    ESPERA_ENTRE_RONDAS = 2,
    ABRIR_RAPIDO = true,              -- Settings_Set("FastOpen", true) antes de abrir
    MAX_INTENTOS_APERTURA = 30,
    NOMBRE_BARCO_MANUAL = "",         -- nombre exacto de tu barco si lo sabes
    EXCLUIR = { "KingsChest", "CrownOfTheDeep" },  -- exhibición del bazar, no se recogen
}

---------------------------------------------------------------
-- RUTAS CONFIRMADAS
---------------------------------------------------------------
local NPC_TESORERO_NAME = "NPC_StarterPort_Broker"
local CARGO_FOLDER_NAME = "CargoVisuals"

local function getRemote(name)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    return remotes and remotes:FindFirstChild(name)
end

---------------------------------------------------------------
-- ESTADO
---------------------------------------------------------------
local running = true
local closed = false
local mode = CONFIG.MODO_INICIAL
local grabChests = CONFIG.AGARRAR_INICIAL
local capacity = CONFIG.CAPACIDAD_INICIAL
local waitInBoat = CONFIG.ESPERA_INICIAL_BARCO
local manualFull = false
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

local function glideTo(targetPos)
    local root = getRoot()
    if not root then return end

    local startPos = root.Position
    local duration = math.max((targetPos - startPos).Magnitude / CONFIG.VELOCIDAD_DESLIZAR, 0.05)
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
        glideTo(targetPos)
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

-- Punto encima de la cubierta del barco (usa su caja de colisión)
local function getShipTopPosition(ship)
    local center, size
    if ship:IsA("Model") then
        center, size = ship:GetBoundingBox()
    else
        center, size = ship.CFrame, ship.Size
    end
    return Vector3.new(
        center.Position.X,
        center.Position.Y + size.Y / 2 + CONFIG.ALTURA_SOBRE_BARCO,
        center.Position.Z
    )
end

---------------------------------------------------------------
-- BÓVEDA (CargoVisuals dentro de tu barco)
---------------------------------------------------------------
local function getCargoFolder()
    local ship = getMyShip()
    return ship and ship:FindFirstChild(CARGO_FOLDER_NAME)
end

local function storedCount()
    local cargo = getCargoFolder()
    if not cargo then return 0 end
    return #cargo:GetChildren()
end

local function isVaultFull()
    if manualFull then return true end
    return storedCount() >= capacity
end

---------------------------------------------------------------
-- COFRES EN EL MUNDO
---------------------------------------------------------------
local function isExcluded(name)
    for _, excluded in ipairs(CONFIG.EXCLUIR) do
        if name == excluded then return true end
    end
    return false
end

local function findChestPrompts()
    local list = {}
    local world = Workspace:FindFirstChild("World")
    local dynamic = world and world:FindFirstChild("Dynamic")
    if not dynamic then return list end

    local function addFrom(folder, promptName)
        if not folder then return end
        for _, obj in ipairs(folder:GetChildren()) do
            if not isExcluded(obj.Name) then
                local base = obj:FindFirstChild("Base")
                local prompt = base and (
                    (base:FindFirstChild("PromptAttachment")
                        and base.PromptAttachment:FindFirstChild(promptName))
                    or base:FindFirstChild(promptName)
                )
                if base and prompt and prompt:IsA("ProximityPrompt") then
                    table.insert(list, { base = base, prompt = prompt })
                end
            end
        end
    end

    addFrom(dynamic:FindFirstChild("Treasure"), "TreasurePrompt")
    addFrom(dynamic:FindFirstChild("Halloween"), "Grab")
    return list
end

---------------------------------------------------------------
-- TESORERO: ir, abrir interfaz y abrir los cofres guardados
---------------------------------------------------------------
local function getTreasurerRoot()
    local world = Workspace:FindFirstChild("World")
    local dynamic = world and world:FindFirstChild("Dynamic")
    local npcs = dynamic and dynamic:FindFirstChild("NPCs")
    local npc = npcs and npcs:FindFirstChild(NPC_TESORERO_NAME)
    return npc and npc:FindFirstChild("HumanoidRootPart")
end

local function getTreasurerPrompt(root)
    local p1 = root:FindFirstChild("NPCPrompt_1")
    local p = p1 and p1:FindFirstChild("NPCPrompt")
    if p and p:IsA("ProximityPrompt") then
        return p
    end
    return nil
end

local function openAllStoredChests()
    local openRemote = getRemote("Treasure_Open")
    local settingsRemote = getRemote("Settings_Set")

    if CONFIG.ABRIR_RAPIDO and settingsRemote and settingsRemote:IsA("RemoteEvent") then
        pcall(function()
            settingsRemote:FireServer("FastOpen", true)
        end)
        task.wait(0.2)
    end

    if not (openRemote and openRemote:IsA("RemoteEvent")) then
        statusText = "No encuentro el remote Treasure_Open"
        refreshUI()
        return
    end

    local stuck = 0
    for _ = 1, CONFIG.MAX_INTENTOS_APERTURA do
        if closed or not running then return end

        local before = storedCount()
        if before == 0 then break end

        pcall(function()
            openRemote:FireServer("All", nil, CONFIG.ABRIR_RAPIDO)
        end)
        openedCount += 1
        statusText = "Abriendo cofres... quedan " .. before
        refreshUI()
        task.wait(1)

        if storedCount() >= before then
            stuck += 1
            if stuck >= 3 then break end
        else
            stuck = 0
        end
    end

    manualFull = false
end

local function goToTreasurerAndOpen()
    local root = getTreasurerRoot()
    if not root then
        statusText = "No encuentro al tesorero"
        refreshUI()
        return
    end

    statusText = "Bóveda llena: yendo al tesorero..."
    refreshUI()
    moveTo(root.Position + Vector3.new(0, 3, 0))

    local prompt = getTreasurerPrompt(root)
    if prompt then
        pcall(fireproximityprompt, prompt)
        task.wait(CONFIG.ESPERA_UI_TESORERO)
    end

    openAllStoredChests()
    statusText = "Bóveda vacía, buscando cofres"
    refreshUI()
end

---------------------------------------------------------------
-- GUARDAR: subir encima del barco y esperar a que aparezca en la bóveda
---------------------------------------------------------------
local function storeOnShip(countBefore)
    local ship = getMyShip()
    if not ship then
        statusText = "No encuentro tu barco"
        refreshUI()
        return false
    end

    statusText = "Subiendo al barco para guardar..."
    refreshUI()
    moveTo(getShipTopPosition(ship))

    local t0 = os.clock()
    while os.clock() - t0 < CONFIG.ESPERA_GUARDADO and running and not closed do
        if storedCount() > countBefore then
            return true
        end
        task.wait(0.25)
    end

    statusText = "El cofre no se guardó: revisa que estés sobre el barco"
    refreshUI()
    return false
end

---------------------------------------------------------------
-- ESPERA ENCIMA DEL BARCO
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
    if isVaultFull() then
        goToTreasurerAndOpen()
        return
    end

    for _, chest in ipairs(findChestPrompts()) do
        if closed or not running then return end
        if not chest.prompt.Parent then continue end

        if isVaultFull() then
            goToTreasurerAndOpen()
            return
        end

        statusText = "Yendo a cofre..."
        refreshUI()
        moveTo(chest.base.Position + Vector3.new(0, 3, 0))
        task.wait(0.1)

        local countBefore = storedCount()
        pcall(fireproximityprompt, chest.prompt)
        task.wait(CONFIG.ESPERA_PROMPT)
        collectedCount += 1

        if grabChests then
            if storeOnShip(countBefore) then
                waitAtBoat()
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

local function makeRow(parent, order, height)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, height)
    row.BackgroundTransparency = 1
    row.LayoutOrder = order
    row.Parent = parent
    local list = Instance.new("UIListLayout")
    list.FillDirection = Enum.FillDirection.Horizontal
    list.Padding = UDim.new(0, 6)
    list.Parent = row
    return row
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
main.Size = UDim2.new(0, 260, 0, 330)
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

makeLabel(statCard, "EN BÓVEDA", 10, PALETTE.muted, true, 0, 14).Position = UDim2.new(0.5, 0, 0, 8)
local vaultLabel = Instance.new("TextLabel")
vaultLabel.BackgroundTransparency = 1
vaultLabel.Position = UDim2.new(0.5, 0, 0, 20)
vaultLabel.Size = UDim2.new(0.5, -12, 0, 26)
vaultLabel.Text = "0/0"
vaultLabel.TextSize = 20
vaultLabel.TextColor3 = PALETTE.accent
vaultLabel.Font = Enum.Font.GothamBold
vaultLabel.TextXAlignment = Enum.TextXAlignment.Left
vaultLabel.Parent = statCard

-- Modo de viaje
local modeRow = makeRow(body, 2, 36)
local tpBtn = makeButton(modeRow, "⚡ TP", UDim2.new(0.5, -3, 1, 0), PALETTE.card, 1)
local glideBtn = makeButton(modeRow, "🌊 Deslizar", UDim2.new(0.5, -3, 1, 0), PALETTE.card, 2)

-- Agarrar / abrir ahora
local optRow = makeRow(body, 3, 36)
local grabBtn = makeButton(optRow, "🎒 Agarrar", UDim2.new(0.5, -3, 1, 0), PALETTE.card, 1)
local openNowBtn = makeButton(optRow, "🏦 Abrir ahora", UDim2.new(0.5, -3, 1, 0), PALETTE.card, 2)

-- Espera encima del barco
local waitRow = Instance.new("Frame")
waitRow.Size = UDim2.new(1, 0, 0, 40)
waitRow.BackgroundColor3 = PALETTE.card
waitRow.BorderSizePixel = 0
waitRow.LayoutOrder = 4
waitRow.Parent = body
addCorner(waitRow, 10)

local waitMinus = makeButton(waitRow, "−", UDim2.new(0, 48, 0, 30), PALETTE.bg, 0)
waitMinus.Position = UDim2.new(0, 5, 0, 5)
local waitPlus = makeButton(waitRow, "+", UDim2.new(0, 48, 0, 30), PALETTE.bg, 0)
waitPlus.Position = UDim2.new(1, -53, 0, 5)
local waitLabel = Instance.new("TextLabel")
waitLabel.BackgroundTransparency = 1
waitLabel.Size = UDim2.new(1, -110, 1, 0)
waitLabel.Position = UDim2.new(0, 55, 0, 0)
waitLabel.TextSize = 13
waitLabel.TextColor3 = PALETTE.text
waitLabel.Font = Enum.Font.GothamBold
waitLabel.Parent = waitRow

-- Capacidad de la bóveda
local capRow = Instance.new("Frame")
capRow.Size = UDim2.new(1, 0, 0, 40)
capRow.BackgroundColor3 = PALETTE.card
capRow.BorderSizePixel = 0
capRow.LayoutOrder = 5
capRow.Parent = body
addCorner(capRow, 10)

local capMinus = makeButton(capRow, "−", UDim2.new(0, 48, 0, 30), PALETTE.bg, 0)
capMinus.Position = UDim2.new(0, 5, 0, 5)
local capPlus = makeButton(capRow, "+", UDim2.new(0, 48, 0, 30), PALETTE.bg, 0)
capPlus.Position = UDim2.new(1, -53, 0, 5)
local capLabel = Instance.new("TextLabel")
capLabel.BackgroundTransparency = 1
capLabel.Size = UDim2.new(1, -110, 1, 0)
capLabel.Position = UDim2.new(0, 55, 0, 0)
capLabel.TextSize = 13
capLabel.TextColor3 = PALETTE.text
capLabel.Font = Enum.Font.GothamBold
capLabel.Parent = capRow

-- Pausa
local toggleBtn = makeButton(body, "", UDim2.new(1, 0, 0, 40), PALETTE.green, 6)
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
    vaultLabel.Text = storedCount() .. "/" .. capacity
    waitLabel.Text = "Espera barco: " .. waitInBoat .. " s"
    capLabel.Text = "Bóveda: " .. capacity

    tpBtn.BackgroundColor3 = mode == "TP" and PALETTE.accent or PALETTE.card
    glideBtn.BackgroundColor3 = mode == "DESLIZAR" and PALETTE.accent or PALETTE.card
    grabBtn.BackgroundColor3 = grabChests and PALETTE.green or PALETTE.card
    grabBtn.Text = grabChests and "🎒 Agarrar: ON" or "🎒 Agarrar: OFF"
    openNowBtn.BackgroundColor3 = manualFull and PALETTE.orange or PALETTE.card

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

openNowBtn.Activated:Connect(function()
    manualFull = not manualFull
    statusText = manualFull and "Se abrirán cofres en el próximo ciclo" or statusText
    refreshUI()
end)

waitMinus.Activated:Connect(function()
    waitInBoat = math.max(0, waitInBoat - 1)
    refreshUI()
end)

waitPlus.Activated:Connect(function()
    waitInBoat = math.min(CONFIG.ESPERA_MAXIMA, waitInBoat + 1)
    refreshUI()
end)

capMinus.Activated:Connect(function()
    capacity = math.max(1, capacity - 1)
    refreshUI()
end)

capPlus.Activated:Connect(function()
    capacity = math.min(CONFIG.CAPACIDAD_MAX, capacity + 1)
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
-- BUCLE PRINCIPAL
---------------------------------------------------------------
task.spawn(function()
    while not closed do
        if running then
            local ok, err = pcall(collectRound)
            if not ok then
                statusText = "Error: " .. tostring(err)
                refreshUI()
            elseif not closed and running then
                statusText = "Buscando cofres..."
                refreshUI()
            end
        end
        task.wait(CONFIG.ESPERA_ENTRE_RONDAS)
    end
end)

refreshUI()
