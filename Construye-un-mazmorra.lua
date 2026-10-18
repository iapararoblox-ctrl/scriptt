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
    AUTO_INICIAL = false,          -- recolección automática encendida al iniciar
    VOLVER_INICIAL = false,        -- ir al barco y volver a la posición anterior
    SOLO_OTROS_INICIAL = false,    -- true = solo cofres de otros jugadores
    MODO_INICIAL = "TP",           -- "TP" o "DESLIZAR"
    VELOCIDAD_DESLIZAR = 45,
    CAPACIDAD_INICIAL = 5,         -- espacio total de la bóveda
    CAPACIDAD_MAX = 50,
    ESPERA_BARCO_INICIAL = 5,      -- segundos encima del barco antes de continuar
    ESPERA_BARCO_MAX = 60,
    ESPERA_RECOGER = 0.3,
    ESPERA_GUARDADO = 3,           -- máximo esperando que el cofre ocupe espacio
    ESPERA_TESORERO = 1.5,
    ESPERA_APERTURA = 0.6,
    ALTURA = 3,
    NOMBRE_BARCO_MANUAL = "",      -- nombre exacto de tu barco si no lo detecta
    ABRIR_RAPIDO = true,           -- Settings_Set("FastOpen", true)
    TAMANO_POR_DEFECTO = 1,        -- espacio si un cofre no tiene CargoSize
    DEBUG = true,
}

local OWNER_KEYS = { "Owner", "OwnerId", "OwnerName", "Player", "PlayerName", "UserId" }

---------------------------------------------------------------
-- RUTAS
---------------------------------------------------------------
local function getDynamic()
    local world = Workspace:FindFirstChild("World")
    return world and world:FindFirstChild("Dynamic")
end

local function getTreasureFolder()
    local dyn = getDynamic()
    return dyn and dyn:FindFirstChild("Treasure")
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
local auto = CONFIG.AUTO_INICIAL
local returnToSpot = CONFIG.VOLVER_INICIAL
local onlyOthers = CONFIG.SOLO_OTROS_INICIAL
local mode = CONFIG.MODO_INICIAL
local capacity = CONFIG.CAPACIDAD_INICIAL
local waitOnBoat = CONFIG.ESPERA_BARCO_INICIAL
local collectedCount = 0
local openedCount = 0
local statusText = "Listo"
local cachedShip = nil
local closed = false
local refreshUI

local function setStatus(text)
    statusText = text
    dbg(text)
    if refreshUI then refreshUI() end
end

---------------------------------------------------------------
-- ESPACIO (CargoSize)
---------------------------------------------------------------
local function getCargoSize(obj)
    local v = obj:GetAttribute("CargoSize")
    if v ~= nil then
        return tonumber(v) or CONFIG.TAMANO_POR_DEFECTO
    end
    local child = obj:FindFirstChild("CargoSize")
    if child and (child:IsA("NumberValue") or child:IsA("IntValue")) then
        return child.Value
    end
    return CONFIG.TAMANO_POR_DEFECTO
end

---------------------------------------------------------------
-- DUEÑO DE LOS COFRES
---------------------------------------------------------------
local function isMine(owner)
    return owner == LocalPlayer.Name
        or owner == LocalPlayer.DisplayName
        or owner == tostring(LocalPlayer.UserId)
end

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

local function shouldCollect(chest)
    local owner = getChestOwner(chest)
    if onlyOthers then
        return owner ~= nil and not isMine(owner)
    end
    return owner == nil or isMine(owner)
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

local function teleportToCFrame(cf)
    local root = getRoot()
    if not root then return false end
    root.AssemblyLinearVelocity = Vector3.zero
    root.CFrame = cf
    task.wait(0.2)
    return true
end

local function glideTo(pos)
    local root = getRoot()
    if not root then return end
    local startPos = root.Position
    local duration = math.max((pos - startPos).Magnitude / CONFIG.VELOCIDAD_DESLIZAR, 0.05)
    local t0 = os.clock()
    local alpha = 0
    while alpha < 1 and not closed do
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
-- BÓVEDA: cada Model en CargoVisuals es un cofre; ocupa CargoSize
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

local function usedSpace()
    local total = 0
    for _, chest in ipairs(getStoredChests()) do
        total += getCargoSize(chest)
    end
    return total
end

---------------------------------------------------------------
-- RECOGER, GUARDAR, VOLVER
---------------------------------------------------------------
local function pickUpChest(base, prompt)
    teleportTo(base.Position + Vector3.new(0, CONFIG.ALTURA, 0))
    pcall(fireproximityprompt, prompt)
    task.wait(CONFIG.ESPERA_RECOGER)
end

local function storeOnBoat(usedBefore)
    local ship = getMyShip()
    if not ship then
        setStatus("No encuentro tu barco")
        return false
    end

    setStatus("Guardando en el barco...")
    teleportTo(getShipTop(ship))

    local t0 = os.clock()
    while os.clock() - t0 < CONFIG.ESPERA_GUARDADO do
        if usedSpace() > usedBefore then
            return true
        end
        task.wait(0.25)
    end
    setStatus("El cofre no se guardó: revisa que estés sobre el barco")
    return false
end

local function waitOnShip()
    local endTime = os.clock() + waitOnBoat
    while os.clock() < endTime and not closed do
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
        if closed then return end
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
    local treasure = getTreasureFolder()
    if not treasure then
        setStatus("No encuentro World.Dynamic.Treasure")
        return
    end

    if usedSpace() >= capacity then
        openVault()
        return
    end

    for _, item in ipairs(treasure:GetChildren()) do
        if closed or not auto then return end

        local base = item:FindFirstChild("Base")
        local attach = base and base:FindFirstChild("PromptAttachment")
        local prompt = attach and attach:FindFirstChild("TreasurePrompt")

        if base and prompt and prompt:IsA("ProximityPrompt") and shouldCollect(item) then
            local size = getCargoSize(item)

            if size > capacity then
                setStatus("Cofre más grande que la bóveda, lo salto")
            else
                if usedSpace() + size > capacity then
                    openVault()
                    return
                end

                -- Guardar la posición donde estabas para volver después
                local root = getRoot()
                local returnCF = root and root.CFrame

                setStatus("Recogiendo cofre (espacio " .. size .. ")...")
                local usedBefore = usedSpace()
                pickUpChest(base, prompt)
                collectedCount += 1

                if storeOnBoat(usedBefore) then
                    waitOnShip()
                end

                if returnToSpot and returnCF then
                    setStatus("Volviendo a tu posición...")
                    teleportToCFrame(returnCF)
                end
            end
        end
    end

    if auto then
        setStatus("Buscando cofres...")
    end
end

---------------------------------------------------------------
-- UI
---------------------------------------------------------------
local PALETTE = {
    bg = Color3.fromRGB(18, 20, 28),
    card = Color3.fromRGB(30, 33, 46),
    cardHover = Color3.fromRGB(40, 44, 60),
    track = Color3.fromRGB(46, 50, 68),
    accent = Color3.fromRGB(110, 150, 255),
    green = Color3.fromRGB(80, 200, 130),
    orange = Color3.fromRGB(245, 160, 60),
    red = Color3.fromRGB(225, 85, 95),
    text = Color3.fromRGB(240, 242, 250),
    muted = Color3.fromRGB(140, 146, 170),
}

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
end

local function stroke(parent, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color
    s.Thickness = thickness or 1
    s.Transparency = transparency or 0
    s.Parent = parent
end

local function label(parent, text, size, color, bold)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextSize = size
    l.TextColor3 = color
    l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Center
    l.Parent = parent
    return l
end

local function button(parent, text, size, color)
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
    corner(b, 10)
    return b
end

local function card(parent, order, height)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, 0, 0, height)
    f.BackgroundColor3 = PALETTE.card
    f.BorderSizePixel = 0
    f.LayoutOrder = order
    f.Parent = parent
    corner(f, 14)
    return f
end

local function padCard(frame, p)
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, p)
    pad.PaddingRight = UDim.new(0, p)
    pad.PaddingTop = UDim.new(0, p / 2)
    pad.PaddingBottom = UDim.new(0, p / 2)
    pad.Parent = frame
end

local function listLayout(parent, padding)
    local l = Instance.new("UIListLayout")
    l.Padding = UDim.new(0, padding)
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Parent = parent
    return l
end

-- Fila con casilla de activado / desactivado
local function checkRow(parent, text, order, initial, onChange)
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, 0, 0, 38)
    row.BackgroundTransparency = 1
    row.Text = ""
    row.AutoButtonColor = false
    row.LayoutOrder = order
    row.Parent = parent

    local lbl = label(row, text, 13, PALETTE.text, false)
    lbl.Size = UDim2.new(1, -40, 1, 0)

    local box = Instance.new("Frame")
    box.Size = UDim2.new(0, 22, 0, 22)
    box.Position = UDim2.new(1, -22, 0.5, -11)
    box.BorderSizePixel = 0
    box.Parent = row
    corner(box, 6)
    stroke(box, PALETTE.muted, 1.2, 0.2)

    local tick = label(box, "✓", 15, PALETTE.text, true)
    tick.Size = UDim2.new(1, 0, 1, 0)
    tick.TextXAlignment = Enum.TextXAlignment.Center

    local state = initial
    local function paint()
        box.BackgroundColor3 = state and PALETTE.green or PALETTE.track
        tick.Visible = state
    end

    row.Activated:Connect(function()
        state = not state
        paint()
        onChange(state)
    end)

    paint()
    return {
        set = function(v) state = v; paint() end,
    }
end

-- Fila con − valor +
local function stepperRow(parent, order, getText, onMinus, onPlus)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 40)
    row.BackgroundTransparency = 1
    row.LayoutOrder = order
    row.Parent = parent

    local lbl = label(row, "", 13, PALETTE.text, true)
    lbl.Size = UDim2.new(1, -96, 1, 0)

    local minus = button(row, "−", UDim2.new(0, 36, 0, 32), PALETTE.track)
    minus.Position = UDim2.new(1, -84, 0.5, -16)
    minus.TextSize = 18

    local plus = button(row, "+", UDim2.new(0, 36, 0, 32), PALETTE.track)
    plus.Position = UDim2.new(1, -40, 0.5, -16)
    plus.TextSize = 18

    minus.Activated:Connect(onMinus)
    plus.Activated:Connect(onPlus)

    return {
        refresh = function() lbl.Text = getText() end,
    }
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
main.Size = UDim2.new(0, 280, 0, 430)
main.BackgroundColor3 = PALETTE.bg
main.BorderSizePixel = 0
main.Parent = gui
corner(main, 18)
stroke(main, PALETTE.accent, 1.2, 0.5)

local mainScale = Instance.new("UIScale")
mainScale.Parent = main

-- Cabecera
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 52)
header.BackgroundTransparency = 1
header.Parent = main

local title = label(header, "Cofres", 17, PALETTE.text, true)
title.Position = UDim2.new(0, 16, 0, 8)
title.Size = UDim2.new(1, -110, 0, 22)

local subtitle = label(header, statusText, 11, PALETTE.muted, false)
subtitle.Position = UDim2.new(0, 16, 0, 30)
subtitle.Size = UDim2.new(1, -110, 0, 14)
subtitle.TextTruncate = Enum.TextTruncate.AtEnd

local minBtn = button(header, "—", UDim2.new(0, 34, 0, 34), PALETTE.card)
minBtn.Position = UDim2.new(1, -80, 0, 9)
local closeBtn = button(header, "✕", UDim2.new(0, 34, 0, 34), PALETTE.red)
closeBtn.Position = UDim2.new(1, -40, 0, 9)

-- Cuerpo
local body = Instance.new("Frame")
body.Position = UDim2.new(0, 0, 0, 52)
body.Size = UDim2.new(1, 0, 1, -52)
body.BackgroundTransparency = 1
body.Parent = main

local bodyLayout = listLayout(body, 10)
local bodyPad = Instance.new("UIPadding")
bodyPad.PaddingLeft = UDim.new(0, 14)
bodyPad.PaddingRight = UDim.new(0, 14)
bodyPad.PaddingTop = UDim.new(0, 2)
bodyPad.Parent = body

-- Estadísticas
local statCard = card(body, 1, 62)
local recLbl = label(statCard, "RECOGIDOS", 10, PALETTE.muted, true)
recLbl.Position = UDim2.new(0, 14, 0, 9)
recLbl.Size = UDim2.new(0.5, -14, 0, 14)

local countLabel = label(statCard, "0", 20, PALETTE.green, true)
countLabel.Position = UDim2.new(0, 14, 0, 24)
countLabel.Size = UDim2.new(0.5, -14, 0, 26)

local spaceLbl = label(statCard, "ESPACIO", 10, PALETTE.muted, true)
spaceLbl.Position = UDim2.new(0.5, 0, 0, 9)
spaceLbl.Size = UDim2.new(0.5, -14, 0, 14)

local vaultLabel = label(statCard, "0/0", 20, PALETTE.accent, true)
vaultLabel.Position = UDim2.new(0.5, 0, 0, 24)
vaultLabel.Size = UDim2.new(0.5, -14, 0, 26)

-- Barra de espacio
local barTrack = Instance.new("Frame")
barTrack.Size = UDim2.new(1, 0, 0, 6)
barTrack.BackgroundColor3 = PALETTE.track
barTrack.BorderSizePixel = 0
barTrack.LayoutOrder = 2
barTrack.Parent = body
corner(barTrack, 3)

local barFill = Instance.new("Frame")
barFill.Size = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = PALETTE.accent
barFill.BorderSizePixel = 0
barFill.Parent = barTrack
corner(barFill, 3)

-- Opciones con casillas
local optCard = card(body, 3, 128)
padCard(optCard, 12)
local optList = listLayout(optCard, 2)

local autoRow = checkRow(optCard, "Recolección automática", 1, auto, function(v)
    auto = v
    setStatus(v and "Buscando cofres..." or "Recolección apagada")
end)

local returnRow = checkRow(optCard, "Ir al barco y volver", 2, returnToSpot, function(v)
    returnToSpot = v
    setStatus(v and "Volverá a tu posición tras guardar" or "Se quedará en el barco tras guardar")
end)

local othersRow = checkRow(optCard, "Solo cofres de otros jugadores", 3, onlyOthers, function(v)
    onlyOthers = v
    setStatus(v and "Modo: solo cofres de otros" or "Modo: no tomar cofres de otros")
end)

-- Ajustes con − +
local setCard = card(body, 4, 92)
local setList = listLayout(setCard, 2)
local setPad = Instance.new("UIPadding")
setPad.PaddingLeft = UDim.new(0, 12)
setPad.PaddingRight = UDim.new(0, 12)
setPad.PaddingTop = UDim.new(0, 6)
setPad.Parent = setCard

local capStepper = stepperRow(setCard, 1,
    function() return "Espacio de bóveda: " .. capacity end,
    function()
        capacity = math.max(1, capacity - 1)
        refreshUI()
    end,
    function()
        capacity = math.min(CONFIG.CAPACIDAD_MAX, capacity + 1)
        refreshUI()
    end
)

local waitStepper = stepperRow(setCard, 2,
    function() return "Espera en barco: " .. waitOnBoat .. " s" end,
    function()
        waitOnBoat = math.max(0, waitOnBoat - 1)
        refreshUI()
    end,
    function()
        waitOnBoat = math.min(CONFIG.ESPERA_BARCO_MAX, waitOnBoat + 1)
        refreshUI()
    end
)

-- Modo de viaje
local modeRow = Instance.new("Frame")
modeRow.Size = UDim2.new(1, 0, 0, 38)
modeRow.BackgroundTransparency = 1
modeRow.LayoutOrder = 5
modeRow.Parent = body

local modeList = Instance.new("UIListLayout")
modeList.FillDirection = Enum.FillDirection.Horizontal
modeList.Padding = UDim.new(0, 8)
modeList.Parent = modeRow

local tpBtn = button(modeRow, "⚡ Teletransporte", UDim2.new(0.5, -4, 1, 0), PALETTE.card)
local glideBtn = button(modeRow, "🌊 Deslizar", UDim2.new(0.5, -4, 1, 0), PALETTE.card)

makeDraggable(header, main)

-- Minimizado (cuadrado)
local mini = button(gui, "🏴‍☠️", UDim2.new(0, 52, 0, 52), PALETTE.card)
mini.TextSize = 22
mini.Visible = false
stroke(mini, PALETTE.accent, 1.2, 0.3)
local miniScale = Instance.new("UIScale")
miniScale.Parent = mini
makeDraggable(mini, mini)

local camera = Workspace.CurrentCamera
local function updateScale()
    local vp = camera.ViewportSize
    local s = math.clamp(math.min(vp.X / 360, vp.Y / 500), 0.6, 1)
    mainScale.Scale = s
    miniScale.Scale = s
end
updateScale()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)

refreshUI = function()
    local used = usedSpace()
    subtitle.Text = statusText
    countLabel.Text = tostring(collectedCount)
    vaultLabel.Text = used .. "/" .. capacity
    barFill.Size = UDim2.new(math.clamp(used / math.max(capacity, 1), 0, 1), 0, 1, 0)

    tpBtn.BackgroundColor3 = mode == "TP" and PALETTE.accent or PALETTE.card
    glideBtn.BackgroundColor3 = mode == "DESLIZAR" and PALETTE.accent or PALETTE.card

    capStepper.refresh()
    waitStepper.refresh()
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
    auto = false
    gui:Destroy()
end)

---------------------------------------------------------------
-- BUCLE PRINCIPAL
---------------------------------------------------------------
task.spawn(function()
    while not closed do
        if auto then
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
