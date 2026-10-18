-- Auto-farm de cofres: recoger, guardar en el barco, abrir con el tesorero (Ser pirata, Móvil)
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
    VELOCIDAD_DESLIZAR = 45,
    AGARRAR_INICIAL = false,          -- lo activas tú en la UI
    CAPACIDAD_INICIAL = 10,           -- cofres que caben en la bóveda (ajustable en la UI)
    CAPACIDAD_MAX = 50,
    ESPERA_BARCO = 5,                 -- segundos encima del barco antes del siguiente cofre
    ESPERA_MAX_BARCO = 60,
    ALTURA_BARCO = 3,                 -- studs por encima de la cubierta
    ALTURA_COFRE = 3,                 -- studs por encima del cofre al llegar
    ESPERA_GUARDADO = 5,              -- máximo esperando que el cofre aparezca en la bóveda
    ESPERA_RECOGER = 2,               -- máximo esperando que el cofre desaparezca tras el prompt
    ESPERA_UI_TESORERO = 1.5,         -- pausa para que abra la interfaz del tesorero
    ESPERA_ENTRE_RONDAS = 2,
    ABRIR_RAPIDO = true,              -- Settings_Set("FastOpen", true) antes de abrir
    MAX_INTENTOS_APERTURA = 30,
    RECOGER_EXHIBICION = false,       -- KingsChest y CrownOfTheDeep están en exhibición
    NOMBRE_BARCO_MANUAL = "",         -- nombre exacto de tu barco si lo sabes
    DEBUG = true,                     -- imprime lo que hace en la consola (F9)
}

---------------------------------------------------------------
-- TIPOS DE COFRE
---------------------------------------------------------------
local function norm(s)
    return string.lower((string.gsub(s, "%s", "")))
end

local CHEST_TYPES = {}
for _, n in ipairs({
    "Halloween Chest", "Pearl Clam", "Wooden Chest", "Coin Sack", "Golden Coin Sack",
    "Supply Crate", "Silver Coffer", "KingsChest", "CrownOfTheDeep",
}) do
    CHEST_TYPES[norm(n)] = true
end
local EXHIBITION = { [norm("KingsChest")] = true, [norm("CrownOfTheDeep")] = true }

local function isChestName(name)
    local n = norm(name)
    if not CHEST_TYPES[n] then return false end
    if EXHIBITION[n] and not CONFIG.RECOGER_EXHIBICION then return false end
    return true
end

---------------------------------------------------------------
-- RUTAS
---------------------------------------------------------------
local NPC_TESORERO = "NPC_StarterPort_Broker"
local CARGO_NAME = "CargoVisuals"

local function dbg(...)
    if CONFIG.DEBUG then print("[COFRES]", ...) end
end

local function getDynamic()
    local world = Workspace:FindFirstChild("World")
    return world and world:FindFirstChild("Dynamic")
end

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
local waitOnBoat = CONFIG.ESPERA_BARCO
local manualOpen = false
local cachedShip = nil
local collectedCount = 0
local openedCount = 0
local statusText = "Listo"

local refreshUI -- se asigna en la UI

local function setStatus(text)
    statusText = text
    dbg(text)
    if refreshUI then refreshUI() end
end

---------------------------------------------------------------
-- MOVIMIENTO
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
    task.wait(0.15)
    return true
end

local function glideTo(pos)
    local root = getRoot()
    if not root then return end
    local startPos = root.Position
    local duration = math.max((pos - startPos).Magnitude / CONFIG.VELOCIDAD_DESLIZAR, 0.05)
    local t0 = os.clock()
    local alpha = 0
    while alpha < 1 and running and not closed do
        root = getRoot()
        if not root then break end
        alpha = math.min((os.clock() - t0) / duration, 1)
        root.AssemblyLinearVelocity = Vector3.zero
        root.CFrame = CFrame.new(startPos:Lerp(pos, alpha)) * (root.CFrame - root.CFrame.Position)
        task.wait()
    end
end

local function moveTo(pos)
    if mode == "TP" then
        teleportTo(pos)
    else
        glideTo(pos)
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

-- Punto encima de la cubierta usando la caja del barco
local function getShipTop()
    local ship = getMyShip()
    if not ship then return nil end
    local center, size
    if ship:IsA("Model") then
        center, size = ship:GetBoundingBox()
    else
        center, size = ship.CFrame, ship.Size
    end
    return Vector3.new(
        center.Position.X,
        center.Position.Y + size.Y / 2 + CONFIG.ALTURA_BARCO,
        center.Position.Z
    )
end

---------------------------------------------------------------
-- BÓVEDA (CargoVisuals): cada Model dentro es un cofre
---------------------------------------------------------------
local function getStoredChests()
    local ship = getMyShip()
    local cargo = ship and ship:FindFirstChild(CARGO_NAME)
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

local function isVaultFull()
    return manualOpen or storedCount() >= capacity
end

---------------------------------------------------------------
-- COFRES EN EL MUNDO
---------------------------------------------------------------
local function findPrompt(obj)
    local preferred = obj:FindFirstChild("TreasurePrompt", true) or obj:FindFirstChild("Grab", true)
    if preferred and preferred:IsA("ProximityPrompt") then
        return preferred
    end
    for _, d in ipairs(obj:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            return d
        end
    end
    return nil
end

local function findWorldChests()
    local result = {}
    local dyn = getDynamic()
    if not dyn then return result end

    local ships = dyn:FindFirstChild("Ships")
    local npcs = dyn:FindFirstChild("NPCs")

    for _, obj in ipairs(dyn:GetDescendants()) do
        local isCandidate = (obj:IsA("Model") or obj:IsA("BasePart")) and isChestName(obj.Name)
        local insideShip = ships and obj:IsDescendantOf(ships)
        local insideNpc = npcs and obj:IsDescendantOf(npcs)
        local nestedChest = obj.Parent and isChestName(obj.Parent.Name)

        if isCandidate and not insideShip and not insideNpc and not nestedChest then
            local prompt = findPrompt(obj)
            if prompt and prompt.Enabled then
                local pos = obj:IsA("Model") and obj:GetPivot().Position or obj.Position
                table.insert(result, { model = obj, prompt = prompt, pos = pos })
            end
        end
    end
    return result
end

---------------------------------------------------------------
-- GUARDAR EN EL BARCO
---------------------------------------------------------------
local function storeOnShip(countBefore)
    local top = getShipTop()
    if not top then
        setStatus("No encuentro tu barco")
        return false
    end

    setStatus("Subiendo al barco para guardar...")
    moveTo(top)

    local t0 = os.clock()
    while os.clock() - t0 < CONFIG.ESPERA_GUARDADO and running and not closed do
        if storedCount() > countBefore then
            return true
        end
        task.wait(0.25)
    end

    setStatus("El cofre no se guardó: revisa que estés sobre el barco")
    return false
end

---------------------------------------------------------------
-- TESORERO: abrir cofres guardados
---------------------------------------------------------------
local function getTreasurerRoot()
    local dyn = getDynamic()
    local npcs = dyn and dyn:FindFirstChild("NPCs")
    local npc = npcs and npcs:FindFirstChild(NPC_TESORERO)
    return npc and npc:FindFirstChild("HumanoidRootPart")
end

local function getTreasurerPrompt(root)
    local p1 = root:FindFirstChild("NPCPrompt_1")
    local p = p1 and p1:FindFirstChild("NPCPrompt")
    return (p and p:IsA("ProximityPrompt")) and p or nil
end

-- El ID del cofre es el nombre del Model dentro de CargoVisuals
local function getTreasureId(chest)
    return chest.Name
end

local function openStoredChests()
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

    local failures = 0
    local usedAll = false

    for _ = 1, CONFIG.MAX_INTENTOS_APERTURA do
        if closed or not running then return end

        local chests = getStoredChests()
        local before = #chests
        if before == 0 then break end

        if not usedAll then
            pcall(function()
                openRemote:FireServer("One", getTreasureId(chests[1]), CONFIG.ABRIR_RAPIDO)
            end)
        else
            pcall(function()
                openRemote:FireServer("All", nil, CONFIG.ABRIR_RAPIDO)
            end)
        end

        task.wait(0.6)
        local after = storedCount()

        if after < before then
            openedCount += (before - after)
            failures = 0
            setStatus("Abriendo cofres... quedan " .. after)
        else
            failures += 1
            dbg("Apertura sin cambio, intento fallido #" .. failures)
            if failures >= 3 and not usedAll then
                usedAll = true
                failures = 0
                dbg("Cambiando a apertura 'All'")
            elseif failures >= 3 then
                setStatus("La bóveda no baja: revisa el ID o el remote")
                break
            end
        end
    end
end

local function goToTreasurerAndOpen()
    local root = getTreasurerRoot()
    if not root then
        setStatus("No encuentro al tesorero")
        return
    end

    setStatus("Bóveda llena: yendo al tesorero...")
    moveTo(root.Position + Vector3.new(0, CONFIG.ALTURA_COFRE, 0))

    local prompt = getTreasurerPrompt(root)
    if prompt then
        pcall(fireproximityprompt, prompt)
        task.wait(CONFIG.ESPERA_UI_TESORERO)
    else
        dbg("Sin prompt del tesorero, intento abrir directo")
    end

    openStoredChests()
    manualOpen = false
    setStatus("Bóveda vacía, buscando cofres")
end

---------------------------------------------------------------
-- ESPERA ENCIMA DEL BARCO
---------------------------------------------------------------
local function waitOnShip()
    local endTime = os.clock() + waitOnBoat
    while os.clock() < endTime and running and not closed do
        setStatus(string.format("En el barco: %ds", math.ceil(endTime - os.clock())))
        task.wait(0.25)
    end
end

---------------------------------------------------------------
-- CICLO: recoger → (guardar) → repetir → abrir cuando esté llena
---------------------------------------------------------------
local function collectRound()
    if isVaultFull() then
        goToTreasurerAndOpen()
        return
    end

    local chests = findWorldChests()
    if #chests == 0 then
        setStatus("No hay cofres disponibles")
        return
    end
    dbg("Cofres encontrados:", #chests)

    for _, chest in ipairs(chests) do
        if closed or not running then return end
        if isVaultFull() then
            goToTreasurerAndOpen()
            return
        end
        if not chest.model.Parent or not chest.prompt.Parent then continue end

        setStatus("Yendo a " .. chest.model.Name)
        moveTo(chest.pos + Vector3.new(0, CONFIG.ALTURA_COFRE, 0))

        local countBefore = storedCount()
        pcall(fireproximityprompt, chest.prompt)

        local t0 = os.clock()
        while os.clock() - t0 < CONFIG.ESPERA_RECOGER and chest.prompt.Parent do
            task.wait(0.1)
        end
        collectedCount += 1

        if grabChests then
            if storeOnShip(countBefore) then
                waitOnShip()
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

-- Panel principal
local main = Instance.new("Frame")
main.Name = "Main"
main.AnchorPoint = Vector2.new(0.5, 0.5)
main.Position = UDim2.new(0.5, 0, 0.5, 0)
main.Size = UDim2.new(0, 260, 0, 340)
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

-- Tarjeta de estadísticas
local statCard = makeCard(body, 1, 52)
makeLabel(statCard, "RECOGIDOS", 10, PALETTE.muted, true, 14).Position = UDim2.new(0, 12, 0, 8)
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

makeLabel(statCard, "BÓVEDA", 10, PALETTE.muted, true, 14).Position = UDim2.new(0.5, 0, 0, 8)
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

-- Modo de viaje
local modeRow = makeRow(body, 3, 36)
local tpBtn = makeButton(modeRow, "⚡ TP", UDim2.new(0.5, -3, 1, 0), PALETTE.card, 1)
local glideBtn = makeButton(modeRow, "🌊 Deslizar", UDim2.new(0.5, -3, 1, 0), PALETTE.card, 2)

-- Agarrar / abrir ahora
local optRow = makeRow(body, 4, 36)
local grabBtn = makeButton(optRow, "🎒 Agarrar", UDim2.new(0.5, -3, 1, 0), PALETTE.card, 1)
local openNowBtn = makeButton(optRow, "🏦 Abrir ahora", UDim2.new(0.5, -3, 1, 0), PALETTE.card, 2)

-- Espera encima del barco
local waitCard = makeCard(body, 5, 40)
local waitMinus = makeButton(waitCard, "−", UDim2.new(0, 48, 0, 30), PALETTE.bg, 0)
waitMinus.Position = UDim2.new(0, 5, 0, 5)
local waitPlus = makeButton(waitCard, "+", UDim2.new(0, 48, 0, 30), PALETTE.bg, 0)
waitPlus.Position = UDim2.new(1, -53, 0, 5)
local waitLabel = makeLabel(waitCard, "", 13, PALETTE.text, true, nil)
waitLabel.Size = UDim2.new(1, -110, 1, 0)
waitLabel.Position = UDim2.new(0, 55, 0, 0)

-- Capacidad de la bóveda
local capCard = makeCard(body, 6, 40)
local capMinus = makeButton(capCard, "−", UDim2.new(0, 48, 0, 30), PALETTE.bg, 0)
capMinus.Position = UDim2.new(0, 5, 0, 5)
local capPlus = makeButton(capCard, "+", UDim2.new(0, 48, 0, 30), PALETTE.bg, 0)
capPlus.Position = UDim2.new(1, -53, 0, 5)
local capLabel = makeLabel(capCard, "", 13, PALETTE.text, true, nil)
capLabel.Size = UDim2.new(1, -110, 1, 0)
capLabel.Position = UDim2.new(0, 55, 0, 0)

-- Pausa
local toggleBtn = makeButton(body, "", UDim2.new(1, 0, 0, 40), PALETTE.green, 7)
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

-- Escala según pantalla
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
    local stored = storedCount()
    subtitleLabel.Text = statusText
    countLabel.Text = tostring(collectedCount)
    vaultLabel.Text = stored .. "/" .. capacity
    barFill.Size = UDim2.new(math.clamp(stored / math.max(capacity, 1), 0, 1), 0, 1, 0)
    waitLabel.Text = "Espera barco: " .. waitOnBoat .. " s"
    capLabel.Text = "Bóveda: " .. capacity

    tpBtn.BackgroundColor3 = mode == "TP" and PALETTE.accent or PALETTE.card
    glideBtn.BackgroundColor3 = mode == "DESLIZAR" and PALETTE.accent or PALETTE.card
    grabBtn.BackgroundColor3 = grabChests and PALETTE.green or PALETTE.card
    grabBtn.Text = grabChests and "🎒 Agarrar: ON" or "🎒 Agarrar: OFF"
    openNowBtn.BackgroundColor3 = manualOpen and PALETTE.orange or PALETTE.card

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
    manualOpen = not manualOpen
    setStatus(manualOpen and "Se abrirán cofres en el próximo ciclo" or "Apertura manual cancelada")
end)

waitMinus.Activated:Connect(function()
    waitOnBoat = math.max(0, waitOnBoat - 1)
    refreshUI()
end)

waitPlus.Activated:Connect(function()
    waitOnBoat = math.min(CONFIG.ESPERA_MAX_BARCO, waitOnBoat + 1)
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
            local ok, err = pcall(collectRound)
            if not ok then
                setStatus("Error: " .. tostring(err))
            end
        end
        refreshUI()
        task.wait(CONFIG.ESPERA_ENTRE_RONDAS)
    end
end)

refreshUI()
