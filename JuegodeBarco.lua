-- Recolección de cofres + guardar en el barco + abrir con el tesorero (Ser pirata, Móvil)
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

---------------------------------------------------------------
-- CONFIGURACIÓN
---------------------------------------------------------------
local CONFIG = {
    CAPACIDAD_INICIAL = 10,       -- cofres en la bóveda antes de ir con el tesorero (se cambia en la UI)
    CAPACIDAD_MAX = 50,
    ESPERA_BARCO_INICIAL = 5,     -- segundos encima del barco antes del siguiente cofre (se cambia en la UI)
    ESPERA_BARCO_MAX = 60,
    SOLO_OTROS_INICIAL = false,   -- false = no agarra cofres de otros; true = solo agarra de otros
    ESPERA_RECOGER = 0.3,         -- igual que tu script que funciona
    ESPERA_GUARDADO = 3,          -- máximo esperando que el cofre aparezca en CargoVisuals
    ESPERA_TESORERO = 1.5,        -- pausa para que abra la interfaz del tesorero
    ESPERA_APERTURA = 0.6,        -- pausa entre cofres abiertos
    ALTURA = 3,                   -- studs por encima del cofre, cubierta o tesorero
    NOMBRE_BARCO_MANUAL = "",     -- nombre exacto de tu barco si no lo detecta
    ABRIR_RAPIDO = true,          -- Settings_Set("FastOpen", true)
    DEBUG = true,                 -- imprime en consola (F9) de qué dueño es cada cofre
}

-- Claves donde podría guardarse el dueño de un cofre (ajústalas si ves otra en el Explorer)
local OWNER_KEYS = { "Owner", "OwnerId", "OwnerName", "Player", "PlayerName", "UserId" }

---------------------------------------------------------------
-- RUTAS
---------------------------------------------------------------
local treasureFolder = Workspace:FindFirstChild("World")
    and Workspace.World:FindFirstChild("Dynamic")
    and Workspace.World.Dynamic:FindFirstChild("Treasure")

local function getDynamic()
    local world = Workspace:FindFirstChild("World")
    return world and world:FindFirstChild("Dynamic")
end

local function getRemote(name)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    return remotes and remotes:FindFirstChild(name)
end

local function dbg(...)
    if CONFIG.DEBUG then print("[COFRES]", ...) end
end

---------------------------------------------------------------
-- ESTADO
---------------------------------------------------------------
local running = true
local closed = false
local capacity = CONFIG.CAPACIDAD_INICIAL
local waitOnBoat = CONFIG.ESPERA_BARCO_INICIAL
local onlyOthers = CONFIG.SOLO_OTROS_INICIAL
local collectedCount = 0
local openedCount = 0
local statusText = "Listo"
local cachedShip = nil
local refreshUI

local function setStatus(text)
    statusText = text
    dbg(text)
    if refreshUI then refreshUI() end
end

---------------------------------------------------------------
-- DUEÑO DE LOS COFRES
---------------------------------------------------------------
local function isMine(owner)
    return owner == LocalPlayer.Name
        or owner == LocalPlayer.DisplayName
        or owner == tostring(LocalPlayer.UserId)
end

-- Devuelve el dueño del cofre como texto, o nil si no tiene dueño visible
local function getChestOwner(chest)
    for _, key in ipairs(OWNER_KEYS) do
        local v = chest:GetAttribute(key)
        if v ~= nil then
            return tostring(v)
        end
    end

    for _, d in ipairs(chest:GetDescendants()) do
        local n = d.Name:lower()
        if n:find("owner") or n:find("player") then
            if d:IsA("ObjectValue") and d.Value then
                if d.Value:IsA("Player") then
                    return tostring(d.Value.UserId)
                end
                return d.Value.Name
            elseif d:IsA("StringValue") or d:IsA("IntValue") or d:IsA("NumberValue") then
                return tostring(d.Value)
            end
        end
    end
    return nil
end

-- true si este cofre se debe agarrar según el filtro
local function shouldCollect(chest)
    local owner = getChestOwner(chest)
    local mine = owner == nil or isMine(owner)

    dbg("Cofre", chest.Name, "| dueño:", owner or "sin dato")

    if onlyOthers then
        return owner ~= nil and not isMine(owner)
    end
    return mine
end

---------------------------------------------------------------
-- PERSONAJE
---------------------------------------------------------------
local function getRoot()
    local character = LocalPlayer.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function teleportTo(pos)
    local root = getRoot()
    if not root then return false end
    root.AssemblyLinearVelocity = Vector3.zero
    root.CFrame = CFrame.new(pos) * (root.CFrame - root.CFrame.Position)
    task.wait(0.2)
    return true
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
        end
    end
    return ship.Name:find(name, 1, true) ~= nil or ship.Name:find(userId, 1, true) ~= nil
end

local function getMyShip()
    if cachedShip and cachedShip.Parent then
        return cachedShip
    end
    cachedShip = nil

    local dyn = getDynamic()
    local ships = dyn and dyn:FindFirstChild("Ships")
    if not ships then return nil end

    for _, ship in ipairs(ships:GetChildren()) do
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

local function getShipTop(ship)
    local center, size
    if ship:IsA("Model") then
        center, size = ship:GetBoundingBox()
    else
        center, size = ship.CFrame, ship.Size
    end
    return Vector3.new(center.Position.X, center.Position.Y + size.Y / 2 + CONFIG.ALTURA, center.Position.Z)
end

---------------------------------------------------------------
-- BÓVEDA: cada Model dentro de CargoVisuals es un cofre
---------------------------------------------------------------
local function getStoredChests()
    local ship = getMyShip()
    local cargo = ship and ship:FindFirstChild("CargoVisuals")
    local list = {}
    if cargo then
        for _, child in ipairs(cargo:GetChildren()) do
            if child:IsA("Model") then
                table.insert(list, child)
            end
        end
    end
    return list
end

local function storedCount()
    return #getStoredChests()
end

---------------------------------------------------------------
-- RECOGER UN COFRE
---------------------------------------------------------------
local function pickUpChest(base, prompt)
    teleportTo(base.Position + Vector3.new(0, CONFIG.ALTURA, 0))
    pcall(fireproximityprompt, prompt)
    task.wait(CONFIG.ESPERA_RECOGER)
end

---------------------------------------------------------------
-- GUARDAR EN EL BARCO
---------------------------------------------------------------
local function storeOnBoat(countBefore)
    local ship = getMyShip()
    if not ship then
        setStatus("No encuentro tu barco")
        return false
    end

    setStatus("Guardando en el barco...")
    teleportTo(getShipTop(ship))

    local t0 = os.clock()
    while os.clock() - t0 < CONFIG.ESPERA_GUARDADO do
        if storedCount() > countBefore then
            return true
        end
        task.wait(0.25)
    end
    setStatus("El cofre no se guardó: revisa que estés sobre el barco")
    return false
end

-- Espera encima del barco antes del siguiente cofre
local function waitOnShip()
    local endTime = os.clock() + waitOnBoat
    while os.clock() < endTime and running and not closed do
        setStatus(string.format("En el barco: %ds", math.ceil(endTime - os.clock())))
        task.wait(0.25)
    end
end

---------------------------------------------------------------
-- TESORERO
---------------------------------------------------------------
local function openVault()
    local dyn = getDynamic()
    local npcs = dyn and dyn:FindFirstChild("NPCs")
    local npc = npcs and npcs:FindFirstChild("NPC_StarterPort_Broker")
    local hrp = npc and npc:FindFirstChild("HumanoidRootPart")
    if not hrp then
        setStatus("No encuentro al tesorero")
        return
    end

    setStatus("Bóveda llena: yendo al tesorero...")
    teleportTo(hrp.Position + Vector3.new(0, CONFIG.ALTURA, 0))

    local p1 = hrp:FindFirstChild("NPCPrompt_1")
    local prompt = p1 and p1:FindFirstChild("NPCPrompt")
    if prompt and prompt:IsA("ProximityPrompt") then
        pcall(fireproximityprompt, prompt)
        task.wait(CONFIG.ESPERA_TESORERO)
    end

    local openRemote = getRemote("Treasure_Open")
    local settingsRemote = getRemote("Settings_Set")
    if not (openRemote and openRemote:IsA("RemoteEvent")) then
        setStatus("No encuentro el remote Treasure_Open")
        return
    end

    if CONFIG.ABRIR_RAPIDO and settingsRemote and settingsRemote:IsA("RemoteEvent") then
        pcall(function() settingsRemote:FireServer("FastOpen", true) end)
        task.wait(0.2)
    end

    for _, chest in ipairs(getStoredChests()) do
        if closed or not running then return end
        pcall(function()
            openRemote:FireServer("One", chest.Name, CONFIG.ABRIR_RAPIDO)
        end)
        openedCount += 1
        setStatus("Abriendo " .. chest.Name)
        task.wait(CONFIG.ESPERA_APERTURA)
    end

    setStatus("Bóveda abierta, buscando cofres")
end

---------------------------------------------------------------
-- CICLO
---------------------------------------------------------------
local function collectCycle()
    if not treasureFolder then
        setStatus("No encuentro World.Dynamic.Treasure")
        return
    end

    if storedCount() >= capacity then
        openVault()
        return
    end

    for _, item in ipairs(treasureFolder:GetChildren()) do
        if closed or not running then return end

        local base = item:FindFirstChild("Base")
        local attach = base and base:FindFirstChild("PromptAttachment")
        local prompt = attach and attach:FindFirstChild("TreasurePrompt")

        if base and prompt and prompt:IsA("ProximityPrompt") and shouldCollect(item) then
            setStatus("Recogiendo cofre...")
            local before = storedCount()
            pickUpChest(base, prompt)
            collectedCount += 1

            if storeOnBoat(before) then
                waitOnShip()
            end

            if storedCount() >= capacity then
                openVault()
                return
            end
        end
    end

    setStatus("Buscando cofres...")
end

---------------------------------------------------------------
-- UI
---------------------------------------------------------------
local PALETTE = {
    bg = Color3.fromRGB(22, 24, 34),
    card = Color3.fromRGB(34, 37, 52),
    track = Color3.fromRGB(50, 54, 72),
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

local function makeLabel(parent, text, size, color, bold, height)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Size = UDim2.new(1, 0, 0, height or 16)
    l.Text = text
    l.TextSize = size
    l.TextColor3 = color
    l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = parent
    return l
end

local function makeButton(parent, text, size, color)
    local b = Instance.new("TextButton")
    b.Size = size
    b.BackgroundColor3 = color
    b.Text = text
    b.TextColor3 = PALETTE.text
    b.TextSize = 13
    b.Font = Enum.Font.GothamBold
    b.AutoButtonColor = true
    b.BorderSizePixel = 0
    b.Parent = parent
    addCorner(b, 10)
    return b
end

local function makeCard(parent, order, height)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, height)
    card.BackgroundColor3 = PALETTE.card
    card.BorderSizePixel = 0
    card.LayoutOrder = order
    card.Parent = parent
    addCorner(card, 12)
    return card
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
main.Size = UDim2.new(0, 260, 0, 320)
main.BackgroundColor3 = PALETTE.bg
main.BorderSizePixel = 0
main.Parent = gui
addCorner(main, 16)
addStroke(main, PALETTE.accent, 1.2, 0.4)

local mainScale = Instance.new("UIScale")
mainScale.Parent = main

-- Cabecera
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 46)
header.BackgroundTransparency = 1
header.Parent = main

local titleLabel = makeLabel(header, "🏴‍☠️ Cofres", 15, PALETTE.text, true, 20)
titleLabel.Position = UDim2.new(0, 14, 0, 6)
titleLabel.Size = UDim2.new(1, -100, 0, 20)

local subtitleLabel = makeLabel(header, statusText, 11, PALETTE.muted, false, 14)
subtitleLabel.Position = UDim2.new(0, 14, 0, 26)
subtitleLabel.Size = UDim2.new(1, -100, 0, 14)
subtitleLabel.TextTruncate = Enum.TextTruncate.AtEnd

local minBtn = makeButton(header, "—", UDim2.new(0, 32, 0, 32), PALETTE.card)
minBtn.Position = UDim2.new(1, -74, 0, 7)
local closeBtn = makeButton(header, "✕", UDim2.new(0, 32, 0, 32), PALETTE.red)
closeBtn.Position = UDim2.new(1, -38, 0, 7)

-- Cuerpo
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

-- Estadísticas
local statCard = makeCard(body, 1, 52)
makeLabel(statCard, "RECOGIDOS", 10, PALETTE.muted, true, 14).Position = UDim2.new(0, 12, 0, 8)
local countLabel = makeLabel(statCard, "0", 20, PALETTE.green, true, 26)
countLabel.Position = UDim2.new(0, 12, 0, 20)
countLabel.Size = UDim2.new(0.5, -12, 0, 26)

makeLabel(statCard, "EN BÓVEDA", 10, PALETTE.muted, true, 14).Position = UDim2.new(0.5, 0, 0, 8)
local vaultLabel = makeLabel(statCard, "0/0", 20, PALETTE.accent, true, 26)
vaultLabel.Position = UDim2.new(0.5, 0, 0, 20)
vaultLabel.Size = UDim2.new(0.5, -12, 0, 26)

-- Barra de la bóveda
local barTrack = Instance.new("Frame")
barTrack.Size = UDim2.new(1, 0, 0, 8)
barTrack.BackgroundColor3 = PALETTE.track
barTrack.BorderSizePixel = 0
barTrack.LayoutOrder = 2
barTrack.Parent = body
addCorner(barTrack, 4)

local barFill = Instance.new("Frame")
barFill.Size = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = PALETTE.accent
barFill.BorderSizePixel = 0
barFill.Parent = barTrack
addCorner(barFill, 4)

-- Filtro de dueño
local filterBtn = makeButton(body, "", UDim2.new(1, 0, 0, 36), PALETTE.card)
filterBtn.LayoutOrder = 3

-- Espera encima del barco
local waitCard = makeCard(body, 4, 40)
local waitMinus = makeButton(waitCard, "−", UDim2.new(0, 48, 0, 30), PALETTE.bg)
waitMinus.Position = UDim2.new(0, 5, 0, 5)
local waitPlus = makeButton(waitCard, "+", UDim2.new(0, 48, 0, 30), PALETTE.bg)
waitPlus.Position = UDim2.new(1, -53, 0, 5)
local waitLabel = makeLabel(waitCard, "", 13, PALETTE.text, true, nil)
waitLabel.Size = UDim2.new(1, -110, 1, 0)
waitLabel.Position = UDim2.new(0, 55, 0, 0)

-- Capacidad manual
local capCard = makeCard(body, 5, 40)
local capMinus = makeButton(capCard, "−", UDim2.new(0, 48, 0, 30), PALETTE.bg)
capMinus.Position = UDim2.new(0, 5, 0, 5)
local capPlus = makeButton(capCard, "+", UDim2.new(0, 48, 0, 30), PALETTE.bg)
capPlus.Position = UDim2.new(1, -53, 0, 5)
local capLabel = makeLabel(capCard, "", 13, PALETTE.text, true, nil)
capLabel.Size = UDim2.new(1, -110, 1, 0)
capLabel.Position = UDim2.new(0, 55, 0, 0)

-- Pausa / reanudar
local toggleBtn = makeButton(body, "", UDim2.new(1, 0, 0, 42), PALETTE.green)
toggleBtn.LayoutOrder = 6
toggleBtn.TextSize = 14

-- Minimizado
local mini = makeButton(gui, "🏴‍☠️", UDim2.new(0, 50, 0, 50), PALETTE.card)
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

refreshUI = function()
    local stored = storedCount()
    subtitleLabel.Text = statusText
    countLabel.Text = tostring(collectedCount)
    vaultLabel.Text = stored .. "/" .. capacity
    barFill.Size = UDim2.new(math.clamp(stored / math.max(capacity, 1), 0, 1), 0, 1, 0)

    filterBtn.Text = onlyOthers and "👥 Solo cofres de otros" or "👤 No tomar cofres de otros"
    filterBtn.BackgroundColor3 = onlyOthers and PALETTE.orange or PALETTE.card

    waitLabel.Text = "Espera barco: " .. waitOnBoat .. " s"
    capLabel.Text = "Bóveda: " .. capacity

    toggleBtn.Text = running and "⏸  Pausar" or "▶  Reanudar"
    toggleBtn.BackgroundColor3 = running and PALETTE.green or PALETTE.orange
end

---------------------------------------------------------------
-- EVENTOS
---------------------------------------------------------------
filterBtn.Activated:Connect(function()
    onlyOthers = not onlyOthers
    setStatus(onlyOthers and "Modo: solo cofres de otros jugadores" or "Modo: no tomar cofres de otros")
end)

waitMinus.Activated:Connect(function()
    waitOnBoat = math.max(0, waitOnBoat - 1)
    refreshUI()
end)

waitPlus.Activated:Connect(function()
    waitOnBoat = math.min(CONFIG.ESPERA_BARCO_MAX, waitOnBoat + 1)
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
    setStatus(running and "Buscando cofres..." or "Pausado")
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
            local ok, err = pcall(collectCycle)
            if not ok then
                setStatus("Error: " .. tostring(err))
            end
        end
        refreshUI()
        task.wait(1)
    end
end)

refreshUI()
