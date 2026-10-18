-- Recolección de cofres + barco + tesorero + modo por isla (Ser pirata, Móvil)
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

---------------------------------------------------------------
-- ISLAS POR DIFICULTAD
---------------------------------------------------------------
local function I(...) return { ... } end

local ISLAND_GROUPS = {
    { nombre = "Muy Fácil", islas = {
        I("Starter Island", "FinnsBeach"),
        I("Small Island", "TinyCay"),
        I("Starter Port"),
    }},
    { nombre = "Fácil", islas = {
        I("Merchant Bay", "MerchantBay"),
        I("Palm Cove", "PalmCove"),
        I("Coral Island", "CoralIsland"),
        I("Coconut Atoll", "CoconutAtoll"),
    }},
    { nombre = "Medio", islas = {
        I("Gull Spire", "GullSpire"),
        I("Redwater Haven", "RedwaterHaven"),
        I("CutthroatKey", "Cutthroat Key"),
        I("ThunderFalls", "Thunder Falls"),
        I("Parrot Peak", "ParrotPeak"),
    }},
    { nombre = "Difícil", islas = {
        I("Turtle Rock", "TurtleRock"),
        I("Skull Rock", "SkullRock"),
        I("Crab King Lair", "CrabKingLair", "Crab Shoals"),
        I("Fang Jungle", "FangJungle"),
        I("Redbeards Cove", "RedbeardsCove"),
    }},
    { nombre = "Sunken", islas = {
        I("CoralSpire"), I("GuardianTemple"), I("TidalColonnade"),
        I("CatacombIsle"), I("DrownedThrone"),
    }},
    { nombre = "Frozen", islas = {
        I("Frostpoint"), I("Rimeclaw"), I("Howling"),
        I("Shiverpeak"), I("WreckersFloe"),
    }},
    { nombre = "Ash", islas = {
        I("LeviathanStrait"), I("CinderDock"), I("MountPyre"), I("KrakenCaldera"),
    }},
    { nombre = "Cursed", islas = {
        I("BlackpowderCove"), I("ObsidianKey"), I("LanternsEnd"), I("WreckersGraveyard"),
        I("GallowsKey"), I("WidowsRest"), I("WailingSpires"), I("DutchmansFog"),
        I("StarfallSanctuary"), I("PrismReef"), I("SkyholdGardens"), I("AstralRuins"),
        I("MoonpetalAtoll"), I("AuroraRift"), I("Skullcrag"), I("LeviathansGrave"),
        I("BrokenArmada"), I("DavysLocker"),
    }},
    { nombre = "Abyssal", islas = {
        I("AbyssGate"), I("BlackwakeHarbor"), I("MidnightReef"), I("TrenchgatePassage"),
        I("DrownedCathedral"), I("AbyssalThrone"), I("HollowmastGraveyard"),
    }},
}

---------------------------------------------------------------
-- CONFIGURACIÓN
---------------------------------------------------------------
local CONFIG = {
    AUTO_INICIAL = false,
    VOLVER_INICIAL = false,
    SOLO_OTROS_INICIAL = false,
    ISLA_INICIAL = false,
    DIFICULTAD_INICIAL = 1,
    ISLA_INDEX_INICIAL = 1,
    MARGEN_ISLA = 40,
    RADIO_ISLA_SIN_CAJA = 250,
    MODO_INICIAL = "TP",
    VELOCIDAD_DESLIZAR = 45,
    CAPACIDAD_INICIAL = 5,
    CAPACIDAD_MAX = 50,
    ESPERA_BARCO_INICIAL = 5,
    ESPERA_BARCO_MAX = 60,
    ESPERA_RECOGER = 0.3,
    ESPERA_GUARDADO = 3,
    ESPERA_TESORERO = 1.5,
    ESPERA_APERTURA = 0.6,
    ALTURA = 3,
    NOMBRE_BARCO_MANUAL = "",
    ABRIR_RAPIDO = true,
    TAMANO_POR_DEFECTO = 1,
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

local function getIslandRoots()
    local roots = {}
    local world = Workspace:FindFirstChild("World")
    if world then
        local a = world:FindFirstChild("Islands")
        if a then table.insert(roots, a) end
        local dyn = world:FindFirstChild("Dynamic")
        local b = dyn and dyn:FindFirstChild("Islands")
        if b then table.insert(roots, b) end
    end
    return roots
end

local function getRemote(name)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    return remotes and remotes:FindFirstChild(name)
end

local function norm(s)
    return string.lower((string.gsub(s, "%s", "")))
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
local islandMode = CONFIG.ISLA_INICIAL
local diffIndex = CONFIG.DIFICULTAD_INICIAL
local islandIndex = CONFIG.ISLA_INDEX_INICIAL
local mode = CONFIG.MODO_INICIAL
local capacity = CONFIG.CAPACIDAD_INICIAL
local waitOnBoat = CONFIG.ESPERA_BARCO_INICIAL
local collectedCount = 0
local openedCount = 0
local statusText = "Listo"
local cachedShip = nil
local islandCache = {}
local closed = false
local refreshUI

local function setStatus(text)
    statusText = text
    dbg(text)
    if refreshUI then refreshUI() end
end

local function currentIslandEntry()
    return ISLAND_GROUPS[diffIndex].islas[islandIndex]
end

local function currentIslandName()
    return currentIslandEntry()[1]
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

local function passesOwnerFilter(chest)
    local owner = getChestOwner(chest)
    if onlyOthers then
        return owner ~= nil and not isMine(owner)
    end
    return owner == nil or isMine(owner)
end

---------------------------------------------------------------
-- ISLAS
---------------------------------------------------------------
local function isModelOrPart(obj)
    return obj and (obj:IsA("Model") or obj:IsA("BasePart"))
end

local function getIsland(entry)
    local key = entry[1]
    local cached = islandCache[key]
    if cached and cached.Parent then
        return cached
    end
    islandCache[key] = nil

    local targets = {}
    for _, name in ipairs(entry) do
        table.insert(targets, norm(name))
    end

    local function matches(obj)
        if not isModelOrPart(obj) then return false end
        local n = norm(obj.Name)
        for _, t in ipairs(targets) do
            if n == t then return true end
        end
        return false
    end

    local found
    for _, root in ipairs(getIslandRoots()) do
        for _, obj in ipairs(root:GetDescendants()) do
            if matches(obj) then
                found = obj
                break
            end
        end
        if found then break end
    end

    if not found then
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if matches(obj) then
                found = obj
                break
            end
        end
    end

    if found then
        islandCache[key] = found
    end
    return found
end

local function isInsideIsland(island, pos)
    if island:IsA("Model") then
        local cf, size = island:GetBoundingBox()
        local rel = cf:PointToObjectSpace(pos)
        local m = CONFIG.MARGEN_ISLA
        return math.abs(rel.X) <= size.X / 2 + m
            and math.abs(rel.Z) <= size.Z / 2 + m
            and math.abs(rel.Y) <= size.Y / 2 + 200
    end
    return (island.Position - pos).Magnitude <= CONFIG.RADIO_ISLA_SIN_CAJA
end

local function islandTop(island)
    if island:IsA("Model") then
        local cf, size = island:GetBoundingBox()
        return cf.Position + Vector3.new(0, size.Y / 2 + 5, 0)
    end
    return island.Position + Vector3.new(0, island.Size.Y / 2 + 5, 0)
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
-- BÓVEDA
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
-- RECOGER, GUARDAR, ESPERAR
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

    local island
    if islandMode then
        local entry = currentIslandEntry()
        island = getIsland(entry)
        if not island then
            setStatus("No encuentro la isla " .. entry[1])
            return
        end
        local root = getRoot()
        if root and not isInsideIsland(island, root.Position) then
            setStatus("Yendo a la isla " .. entry[1] .. "...")
            moveTo(islandTop(island))
        end
    end

    for _, item in ipairs(treasure:GetChildren()) do
        if closed or not auto then return end

        local base = item:FindFirstChild("Base")
        local attach = base and base:FindFirstChild("PromptAttachment")
        local prompt = attach and attach:FindFirstChild("TreasurePrompt")

        local inIsland = (not island) or (base ~= nil and isInsideIsland(island, base.Position))

        if base and prompt and prompt:IsA("ProximityPrompt") and inIsland and passesOwnerFilter(item) then
            local size = getCargoSize(item)

            if size > capacity then
                setStatus("Cofre más grande que la bóveda, lo salto")
            else
                if usedSpace() + size > capacity then
                    openVault()
                    return
                end

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
        setStatus(islandMode and ("Buscando cofres en " .. currentIslandName()) or "Buscando cofres...")
    end
end

---------------------------------------------------------------
-- UI (compacta, se ajusta a la pantalla del teléfono)
---------------------------------------------------------------
local PALETTE = {
    bg = Color3.fromRGB(18, 20, 28),
    card = Color3.fromRGB(30, 33, 46),
    track = Color3.fromRGB(46, 50, 68),
    accent = Color3.fromRGB(110, 150, 255),
    green = Color3.fromRGB(80, 200, 130),
    red = Color3.fromRGB(225, 85, 95),
    text = Color3.fromRGB(240, 242, 250),
    muted = Color3.fromRGB(140, 146, 170),
}

local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera or Workspace:WaitForChild("CurrentCamera")

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
    b.TextSize = 12
    b.Font = Enum.Font.GothamBold
    b.AutoButtonColor = true
    b.BorderSizePixel = 0
    b.Parent = parent
    corner(b, 8)
    return b
end

-- Tarjeta: altura fija si se pasa, si no crece con su contenido
local function card(parent, order, height)
    local f = Instance.new("Frame")
    f.Size = height and UDim2.new(1, 0, 0, height) or UDim2.new(1, 0, 0, 0)
    if not height then
        f.AutomaticSize = Enum.AutomaticSize.Y
    end
    f.BackgroundColor3 = PALETTE.card
    f.BorderSizePixel = 0
    f.LayoutOrder = order
    f.Parent = parent
    corner(f, 12)
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

-- Casilla de activado / desactivado
local function checkRow(parent, text, order, initial, onChange)
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, 0, 0, 30)
    row.BackgroundTransparency = 1
    row.Text = ""
    row.AutoButtonColor = false
    row.LayoutOrder = order
    row.Parent = parent

    local lbl = label(row, text, 12, PALETTE.text, false)
    lbl.Size = UDim2.new(1, -34, 1, 0)

    local box = Instance.new("Frame")
    box.Size = UDim2.new(0, 18, 0, 18)
    box.Position = UDim2.new(1, -18, 0.5, -9)
    box.BorderSizePixel = 0
    box.Parent = row
    corner(box, 5)
    stroke(box, PALETTE.muted, 1, 0.2)

    local tick = label(box, "✓", 13, PALETTE.text, true)
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
    return { set = function(v) state = v; paint() end }
end

-- ◀ texto ▶
local function arrowRow(parent, order, getText, onPrev, onNext)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 32)
    row.BackgroundTransparency = 1
    row.LayoutOrder = order
    row.Parent = parent

    local prev = button(row, "◀", UDim2.new(0, 34, 0, 30), PALETTE.track)
    prev.Position = UDim2.new(0, 0, 0.5, -15)
    prev.TextSize = 14

    local nxt = button(row, "▶", UDim2.new(0, 34, 0, 30), PALETTE.track)
    nxt.Position = UDim2.new(1, -34, 0.5, -15)
    nxt.TextSize = 14

    local lbl = label(row, "", 12, PALETTE.text, true)
    lbl.TextXAlignment = Enum.TextXAlignment.Center
    lbl.Size = UDim2.new(1, -76, 1, 0)
    lbl.Position = UDim2.new(0, 39, 0, 0)
    lbl.TextTruncate = Enum.TextTruncate.AtEnd

    prev.Activated:Connect(onPrev)
    nxt.Activated:Connect(onNext)

    return { refresh = function() lbl.Text = getText() end }
end

-- − valor +
local function stepperRow(parent, order, getText, onMinus, onPlus)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 32)
    row.BackgroundTransparency = 1
    row.LayoutOrder = order
    row.Parent = parent

    local lbl = label(row, "", 12, PALETTE.text, true)
    lbl.Size = UDim2.new(1, -76, 1, 0)

    local minus = button(row, "−", UDim2.new(0, 32, 0, 30), PALETTE.track)
    minus.Position = UDim2.new(1, -72, 0.5, -15)
    minus.TextSize = 16

    local plus = button(row, "+", UDim2.new(0, 32, 0, 30), PALETTE.track)
    plus.Position = UDim2.new(1, -36, 0.5, -15)
    plus.TextSize = 16

    minus.Activated:Connect(onMinus)
    plus.Activated:Connect(onPlus)

    return { refresh = function() lbl.Text = getText() end }
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

-- Panel principal: se ajusta al tamaño de la pantalla
local main = Instance.new("Frame")
main.Name = "Main"
main.AnchorPoint = Vector2.new(0.5, 0.5)
main.Position = UDim2.new(0.5, 0, 0.5, 0)
main.Size = UDim2.fromOffset(260, 400)
main.BackgroundColor3 = PALETTE.bg
main.BorderSizePixel = 0
main.Parent = gui
corner(main, 16)
stroke(main, PALETTE.accent, 1, 0.5)

local function fitToScreen()
    local vp = camera.ViewportSize
    local w = math.min(270, vp.X - 20)
    local h = math.min(440, vp.Y - 30)
    main.Size = UDim2.fromOffset(math.max(w, 200), math.max(h, 200))
end
fitToScreen()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(fitToScreen)

-- Cabecera
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 44)
header.BackgroundTransparency = 1
header.Parent = main

local title = label(header, "Cofres", 15, PALETTE.text, true)
title.Position = UDim2.new(0, 14, 0, 6)
title.Size = UDim2.new(1, -100, 0, 18)

local subtitle = label(header, statusText, 10, PALETTE.muted, false)
subtitle.Position = UDim2.new(0, 14, 0, 24)
subtitle.Size = UDim2.new(1, -100, 0, 14)
subtitle.TextTruncate = Enum.TextTruncate.AtEnd

local minBtn = button(header, "—", UDim2.new(0, 30, 0, 30), PALETTE.card)
minBtn.Position = UDim2.new(1, -72, 0, 7)
local closeBtn = button(header, "✕", UDim2.new(0, 30, 0, 30), PALETTE.red)
closeBtn.Position = UDim2.new(1, -36, 0, 7)

-- Cuerpo desplazable (si algo no cabe, se puede bajar)
local body = Instance.new("ScrollingFrame")
body.Position = UDim2.new(0, 0, 0, 44)
body.Size = UDim2.new(1, 0, 1, -44)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ScrollBarThickness = 3
body.ScrollBarImageColor3 = PALETTE.accent
body.CanvasSize = UDim2.new(0, 0, 0, 0)
body.AutomaticCanvasSize = Enum.AutomaticSize.Y
body.Parent = main

listLayout(body, 8)
local bodyPad = Instance.new("UIPadding")
bodyPad.PaddingLeft = UDim.new(0, 10)
bodyPad.PaddingRight = UDim.new(0, 10)
bodyPad.PaddingBottom = UDim.new(0, 10)
bodyPad.Parent = body

-- Estadísticas + barra
local statCard = card(body, 1, 56)
local recLbl = label(statCard, "RECOGIDOS", 9, PALETTE.muted, true)
recLbl.Position = UDim2.new(0, 12, 0, 7)
recLbl.Size = UDim2.new(0.5, -12, 0, 12)

local countLabel = label(statCard, "0", 18, PALETTE.green, true)
countLabel.Position = UDim2.new(0, 12, 0, 19)
countLabel.Size = UDim2.new(0.5, -12, 0, 24)

local spaceLbl = label(statCard, "ESPACIO", 9, PALETTE.muted, true)
spaceLbl.Position = UDim2.new(0.5, 0, 0, 7)
spaceLbl.Size = UDim2.new(0.5, -12, 0, 12)

local vaultLabel = label(statCard, "0/0", 18, PALETTE.accent, true)
vaultLabel.Position = UDim2.new(0.5, 0, 0, 19)
vaultLabel.Size = UDim2.new(0.5, -12, 0, 24)

local barTrack = Instance.new("Frame")
barTrack.Size = UDim2.new(1, -24, 0, 5)
barTrack.Position = UDim2.new(0, 12, 1, -10)
barTrack.BackgroundColor3 = PALETTE.track
barTrack.BorderSizePixel = 0
barTrack.Parent = statCard
corner(barTrack, 3)

local barFill = Instance.new("Frame")
barFill.Size = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = PALETTE.accent
barFill.BorderSizePixel = 0
barFill.Parent = barTrack
corner(barFill, 3)

-- Opciones
local optCard = card(body, 2)
padCard(optCard, 10)
listLayout(optCard, 3)

checkRow(optCard, "Recolección automática", 1, auto, function(v)
    auto = v
    setStatus(v and "Buscando cofres..." or "Recolección apagada")
end)

checkRow(optCard, "Ir al barco y volver", 2, returnToSpot, function(v)
    returnToSpot = v
    setStatus(v and "Volverá a tu posición tras guardar" or "Se quedará en el barco tras guardar")
end)

checkRow(optCard, "Solo cofres de otros jugadores", 3, onlyOthers, function(v)
    onlyOthers = v
    setStatus(v and "Modo: solo cofres de otros" or "Modo: no tomar cofres de otros")
end)

checkRow(optCard, "Recolectar por isla", 4, islandMode, function(v)
    islandMode = v
    setStatus(v and ("Modo isla: " .. currentIslandName()) or "Modo isla apagado")
end)

-- Selector de isla
local islandCard = card(body, 3)
padCard(islandCard, 8)
listLayout(islandCard, 4)

local diffRow = arrowRow(islandCard, 1,
    function()
        return ISLAND_GROUPS[diffIndex].nombre .. " (" .. diffIndex .. "/" .. #ISLAND_GROUPS .. ")"
    end,
    function()
        diffIndex = diffIndex - 1
        if diffIndex < 1 then diffIndex = #ISLAND_GROUPS end
        islandIndex = 1
        refreshUI()
    end,
    function()
        diffIndex = diffIndex + 1
        if diffIndex > #ISLAND_GROUPS then diffIndex = 1 end
        islandIndex = 1
        refreshUI()
    end
)

local islandRow = arrowRow(islandCard, 2,
    function()
        local group = ISLAND_GROUPS[diffIndex]
        return group.islas[islandIndex][1] .. " (" .. islandIndex .. "/" .. #group.islas .. ")"
    end,
    function()
        local count = #ISLAND_GROUPS[diffIndex].islas
        islandIndex = islandIndex - 1
        if islandIndex < 1 then islandIndex = count end
        refreshUI()
    end,
    function()
        local count = #ISLAND_GROUPS[diffIndex].islas
        islandIndex = islandIndex + 1
        if islandIndex > count then islandIndex = 1 end
        refreshUI()
    end
)

-- Ajustes
local setCard = card(body, 4)
padCard(setCard, 8)
listLayout(setCard, 4)

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
modeRow.Size = UDim2.new(1, 0, 0, 32)
modeRow.BackgroundTransparency = 1
modeRow.LayoutOrder = 5
modeRow.Parent = body

local modeList = Instance.new("UIListLayout")
modeList.FillDirection = Enum.FillDirection.Horizontal
modeList.Padding = UDim.new(0, 6)
modeList.Parent = modeRow

local tpBtn = button(modeRow, "⚡ Teletransporte", UDim2.new(0.5, -3, 1, 0), PALETTE.card)
local glideBtn = button(modeRow, "🌊 Deslizar", UDim2.new(0.5, -3, 1, 0), PALETTE.card)

makeDraggable(header, main)

-- Minimizado (cuadrado)
local mini = button(gui, "🏴‍☠️", UDim2.fromOffset(48, 48), PALETTE.card)
mini.TextSize = 20
mini.Visible = false
stroke(mini, PALETTE.accent, 1, 0.3)
makeDraggable(mini, mini)

refreshUI = function()
    local used = usedSpace()
    subtitle.Text = statusText
    countLabel.Text = tostring(collectedCount)
    vaultLabel.Text = used .. "/" .. capacity
    barFill.Size = UDim2.new(math.clamp(used / math.max(capacity, 1), 0, 1), 0, 1, 0)

    tpBtn.BackgroundColor3 = mode == "TP" and PALETTE.accent or PALETTE.card
    glideBtn.BackgroundColor3 = mode == "DESLIZAR" and PALETTE.accent or PALETTE.card

    diffRow.refresh()
    islandRow.refresh()
    capStepper.refresh()
    waitStepper.refresh()
end

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
