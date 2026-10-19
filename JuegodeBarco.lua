-- Recolección de cofres + barco + barco de otro jugador (con memoria de sesión) + tesorero + isla + filtros (Ser pirata, Móvil)
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
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
    VOLVER_INICIAL = false,
    SOLO_OTROS_INICIAL = false,
    ISLA_INICIAL = false,
    DIFICULTAD_INICIAL = 1,
    ISLA_INDEX_INICIAL = 1,
    MARGEN_ISLA = 40,
    RADIO_ISLA_SIN_CAJA = 250,
    MODO_INICIAL = "TP",
    VELOCIDAD_DESLIZAR = 45,
    CAPACIDAD_INICIAL = 81,
    CAPACIDAD_MAX = 81,
    ESPERA_BARCO_INICIAL = 5,
    ESPERA_BARCO_MAX = 60,
    ESPERA_RECOGER = 0.3,
    ESPERA_GUARDADO = 3,
    ESPERA_TESORERO = 1.5,
    ESPERA_APERTURA = 0.6,
    ESPERA_CARGA_BARCO = 6,        -- segundos máximos esperando que el juego cargue un barco lejano
    ALTURA = 3,
    NOMBRE_BARCO_MANUAL = "",
    ABRIR_RAPIDO = true,
    TAMANO_POR_DEFECTO = 1,

    VALOR_FILTRO_INICIAL = false,
    VALOR_MIN_INICIAL = 10000,
    VALOR_PASO = 1000,
    RAREZA_FILTRO_INICIAL = false,
    RAREZA_MIN_INICIAL = 3,
    RAREZAS = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Divine" },

    PANEL_ANCHO_INICIAL = 280,
    PANEL_ALTO_INICIAL = 440,
    PANEL_MIN_ANCHO = 50,
    PANEL_MIN_ALTO = 10,
    PANEL_MAX = 3000,
    PANEL_PASOS = { 1, 5, 10, 20, 50 },
    PANEL_PASO_INICIAL = 3,

    CONFIG_ARCHIVO = "CofresConfig.json",
    DEBUG = true,
}

local BASE_W, BASE_H = 300, 470
local OWNER_KEYS = { "Owner", "OwnerId", "OwnerName", "Player", "PlayerName", "UserId" }
local MINE_LABEL = "Mi barco"

---------------------------------------------------------------
-- CARGAR CONFIGURACIÓN GUARDADA
---------------------------------------------------------------
local saved = {}
pcall(function()
    if readfile and isfile and isfile(CONFIG.CONFIG_ARCHIVO) then
        local data = HttpService:JSONDecode(readfile(CONFIG.CONFIG_ARCHIVO))
        if type(data) == "table" then
            saved = data
        end
    end
end)

local function svn(key, default)
    return tonumber(saved[key]) or default
end

local function svb(key, default)
    if type(saved[key]) == "boolean" then
        return saved[key]
    end
    return default
end

local function svs(key, default)
    if type(saved[key]) == "string" then
        return saved[key]
    end
    return default
end

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
    return string.lower((string.gsub(tostring(s), "%s", "")))
end

local function dbg(...)
    if CONFIG.DEBUG then print("[COFRES]", ...) end
end

---------------------------------------------------------------
-- ESTADO
---------------------------------------------------------------
local auto = false
local returnToSpot = svb("returnToSpot", CONFIG.VOLVER_INICIAL)
local onlyOthers = svb("onlyOthers", CONFIG.SOLO_OTROS_INICIAL)
local islandMode = svb("islandMode", CONFIG.ISLA_INICIAL)
local diffIndex = math.clamp(math.floor(svn("diffIndex", CONFIG.DIFICULTAD_INICIAL)), 1, #ISLAND_GROUPS)
local islandIndex = math.clamp(
    math.floor(svn("islandIndex", CONFIG.ISLA_INDEX_INICIAL)),
    1, #ISLAND_GROUPS[diffIndex].islas
)
local mode = saved.mode == "DESLIZAR" and "DESLIZAR" or "TP"
local capacity = math.clamp(math.floor(svn("capacity", CONFIG.CAPACIDAD_INICIAL)), 1, CONFIG.CAPACIDAD_MAX)
local waitOnBoat = math.clamp(math.floor(svn("waitOnBoat", CONFIG.ESPERA_BARCO_INICIAL)), 0, CONFIG.ESPERA_BARCO_MAX)
local panelW = svn("panelW", CONFIG.PANEL_ANCHO_INICIAL)
local panelH = svn("panelH", CONFIG.PANEL_ALTO_INICIAL)
local panelStepIdx = math.clamp(math.floor(svn("panelStepIdx", CONFIG.PANEL_PASO_INICIAL)), 1, #CONFIG.PANEL_PASOS)

local valueFilter = svb("valueFilter", CONFIG.VALOR_FILTRO_INICIAL)
local valueMin = math.max(0, math.floor(svn("valueMin", CONFIG.VALOR_MIN_INICIAL)))
local rarityFilter = svb("rarityFilter", CONFIG.RAREZA_FILTRO_INICIAL)
local rarityMinIdx = math.clamp(math.floor(svn("rarityMinIdx", CONFIG.RAREZA_MIN_INICIAL)), 1, #CONFIG.RAREZAS)

local targetLabel = svs("targetLabel", MINE_LABEL)

-- Memoria de sesión de barcos de otros jugadores (no se guarda en archivo)
-- label -> { ship = Instance|nil, shipName = string, pos = Vector3 }
local shipMemory = {}
local memoryOrder = {}

local collectedCount = 0
local openedCount = 0
local statusText = "Listo"
local cachedShip = nil
local islandCache = {}
local manualOpenRequested = false
local closed = false
local dirty = false
local refreshUI

local function markDirty()
    dirty = true
end

local function saveConfig()
    if not writefile then return end
    local data = {
        returnToSpot = returnToSpot,
        onlyOthers = onlyOthers,
        islandMode = islandMode,
        diffIndex = diffIndex,
        islandIndex = islandIndex,
        mode = mode,
        capacity = capacity,
        waitOnBoat = waitOnBoat,
        panelW = panelW,
        panelH = panelH,
        panelStepIdx = panelStepIdx,
        valueFilter = valueFilter,
        valueMin = valueMin,
        rarityFilter = rarityFilter,
        rarityMinIdx = rarityMinIdx,
        targetLabel = targetLabel,
    }
    pcall(function()
        writefile(CONFIG.CONFIG_ARCHIVO, HttpService:JSONEncode(data))
    end)
end

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
-- PROPIEDADES DEL COFRE (CargoSize, Value, Rarity)
---------------------------------------------------------------
local function getChestProp(obj, name)
    local v = obj:GetAttribute(name)
    if v == nil then
        local child = obj:FindFirstChild(name)
        if child and child:IsA("ValueBase") then
            v = child.Value
        end
    end
    return v
end

local function getCargoSize(obj)
    local v = tonumber(getChestProp(obj, "CargoSize"))
    return v or CONFIG.TAMANO_POR_DEFECTO
end

---------------------------------------------------------------
-- FILTROS DE VALOR Y RAREZA
---------------------------------------------------------------
local function rarityIndex(r)
    if r == nil then return nil end
    local n = norm(r)
    for i, name in ipairs(CONFIG.RAREZAS) do
        if norm(name) == n then
            return i
        end
    end
    return nil
end

local function passesValueRarity(chest)
    if valueFilter then
        local v = tonumber(getChestProp(chest, "Value"))
        if not v or v < valueMin then
            return false
        end
    end
    if rarityFilter then
        local idx = rarityIndex(getChestProp(chest, "Rarity"))
        if not idx or idx < rarityMinIdx then
            return false
        end
    end
    return true
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
-- BARCOS
---------------------------------------------------------------
-- Busca barcos en Ships, incluidas carpetas dentro de Ships
local function collectShipCandidates()
    local result = {}
    local dyn = getDynamic()
    local ships = dyn and dyn:FindFirstChild("Ships")
    if not ships then return result end

    for _, child in ipairs(ships:GetChildren()) do
        if child:IsA("Model") or child:IsA("BasePart") then
            table.insert(result, child)
        elseif child:IsA("Folder") then
            for _, d in ipairs(child:GetChildren()) do
                if d:IsA("Model") or d:IsA("BasePart") then
                    table.insert(result, d)
                end
            end
        end
    end
    return result
end

local function isMyShip(ship)
    local name = LocalPlayer.Name
    local displayName = LocalPlayer.DisplayName
    local userId = tostring(LocalPlayer.UserId)

    for _, attr in ipairs({ "Owner", "OwnerName", "OwnerId", "Player", "PlayerName", "UserId" }) do
        local v = ship:GetAttribute(attr)
        if v ~= nil then
            local s = tostring(v)
            if s == name or s == displayName or s == userId then
                return true
            end
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

    if ship.Name == name or ship.Name == displayName then
        return true
    end
    if ship.Name:find(userId, 1, true) then
        return true
    end
    return false
end

local function getMyShip()
    if cachedShip and cachedShip.Parent then
        return cachedShip
    end
    cachedShip = nil

    for _, ship in ipairs(collectShipCandidates()) do
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

-- Nombre del dueño: convierte UserId en nombre y revisa jugadores del servidor
local function ownerNameOf(ship)
    for _, attr in ipairs({ "OwnerName", "PlayerName", "Owner", "Player", "OwnerId", "UserId" }) do
        local v = ship:GetAttribute(attr)
        if v ~= nil and tostring(v) ~= "" then
            local asNumber = tonumber(v)
            if asNumber then
                local p = Players:GetPlayerByUserId(asNumber)
                if p then return p.Name end
            else
                return tostring(v)
            end
        end
    end

    for _, d in ipairs(ship:GetDescendants()) do
        if d:IsA("ObjectValue") and d.Value and d.Value:IsA("Player") then
            return d.Value.Name
        end
    end

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and ship.Name:find(p.Name, 1, true) then
            return p.Name
        end
    end

    return nil
end

local function shipPivotPos(ship)
    if ship:IsA("Model") then
        return ship:GetPivot().Position
    end
    return ship.Position
end

-- Guarda o actualiza un barco en la memoria de la sesión
local function rememberShip(label, ship)
    local m = shipMemory[label]
    if not m then
        m = {}
        shipMemory[label] = m
        table.insert(memoryOrder, label)
    end
    m.ship = ship
    m.shipName = ship.Name
    m.pos = shipPivotPos(ship)
end

-- Revisa los barcos cargados ahora y los recuerda
local function listOtherShips()
    local result = {}
    local seen = {}

    for _, ship in ipairs(collectShipCandidates()) do
        if not isMyShip(ship) then
            local lbl = ownerNameOf(ship) or ship.Name
            seen[lbl] = (seen[lbl] or 0) + 1
            if seen[lbl] > 1 then
                lbl = lbl .. " #" .. seen[lbl]
            end
            rememberShip(lbl, ship)
            table.insert(result, { ship = ship, label = lbl })
        end
    end
    return result
end

-- Opciones del selector: "Mi barco" y todos los barcos recordados en esta sesión
local function buildTargetOptions()
    listOtherShips()
    local opts = { MINE_LABEL }
    for _, lbl in ipairs(memoryOrder) do
        table.insert(opts, lbl)
    end
    return opts
end

-- Si el barco ya no está cargado, se acerca a su última posición para que el juego lo cargue
local function loadRememberedShip(label)
    local m = shipMemory[label]
    if not m or not m.pos then return nil end

    setStatus("Cargando barco de " .. label .. "...")
    teleportTo(m.pos + Vector3.new(0, 15, 0))

    local t0 = os.clock()
    while os.clock() - t0 < CONFIG.ESPERA_CARGA_BARCO and not closed do
        local fallback
        for _, c in ipairs(collectShipCandidates()) do
            if not isMyShip(c) and c.Name == m.shipName then
                if (ownerNameOf(c) or c.Name) == label then
                    rememberShip(label, c)
                    return c
                end
                fallback = fallback or c
            end
        end
        if fallback then
            rememberShip(label, fallback)
            return fallback
        end
        task.wait(0.5)
    end

    setStatus("No se cargó el barco de " .. label .. ": el juego no lo mostró")
    return nil
end

-- Barco de destino según la opción elegida
local function getDestinationShip()
    if targetLabel == MINE_LABEL or targetLabel == "" then
        return getMyShip()
    end

    local m = shipMemory[targetLabel]
    if not m then
        listOtherShips()
        m = shipMemory[targetLabel]
        if not m then return nil end
    end

    if m.ship and m.ship.Parent then
        m.pos = shipPivotPos(m.ship)
        return m.ship
    end

    return loadRememberedShip(targetLabel)
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
-- BÓVEDA (CargoVisuals de cualquier barco)
---------------------------------------------------------------
local function chestsOn(ship)
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

local function usedSpaceOn(ship)
    local total = 0
    for _, chest in ipairs(chestsOn(ship)) do
        total += getCargoSize(chest)
    end
    return total
end

local function getStoredChests()
    return chestsOn(getMyShip())
end

local function usedSpace()
    return usedSpaceOn(getMyShip())
end

---------------------------------------------------------------
-- RECOGER, GUARDAR, ESPERAR
---------------------------------------------------------------
local function pickUpChest(base, prompt)
    teleportTo(base.Position + Vector3.new(0, CONFIG.ALTURA, 0))
    pcall(fireproximityprompt, prompt)
    task.wait(CONFIG.ESPERA_RECOGER)
end

local function storeOnBoat(usedBefore, dest)
    if not dest then
        setStatus("No encuentro el barco destino")
        return false
    end

    setStatus("Guardando en " .. targetLabel .. "...")
    teleportTo(getShipTop(dest))

    local t0 = os.clock()
    while os.clock() - t0 < CONFIG.ESPERA_GUARDADO do
        if usedSpaceOn(dest) > usedBefore then
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
-- TESORERO (solo abre los cofres de TU barco)
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

    setStatus("Yendo al tesorero...")
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

    local dest = getDestinationShip()
    if not dest then
        if targetLabel ~= MINE_LABEL then
            setStatus("No encuentro el barco de " .. targetLabel)
        else
            setStatus("No encuentro tu barco")
        end
        return
    end
    local destIsMine = (targetLabel == MINE_LABEL or targetLabel == "")

    if usedSpaceOn(dest) >= capacity then
        if destIsMine then
            openVault()
        else
            setStatus("El barco de " .. targetLabel .. " está lleno")
        end
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

        if base and prompt and prompt:IsA("ProximityPrompt")
            and inIsland
            and passesOwnerFilter(item)
            and passesValueRarity(item) then

            -- Si el barco de otro jugador se descargó, vuelve a cargarlo
            if not dest.Parent then
                dest = getDestinationShip()
                if not dest then return end
            end

            local size = getCargoSize(item)

            if size > capacity then
                setStatus("Cofre más grande que la bóveda, lo salto")
            else
                if usedSpaceOn(dest) + size > capacity then
                    if destIsMine then
                        openVault()
                    else
                        setStatus("El barco de " .. targetLabel .. " no tiene espacio")
                    end
                    return
                end

                local root = getRoot()
                local returnCF = root and root.CFrame

                setStatus("Recogiendo cofre (espacio " .. size .. ")...")
                local usedBefore = usedSpaceOn(dest)
                pickUpChest(base, prompt)
                collectedCount += 1

                if storeOnBoat(usedBefore, dest) then
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
-- UI
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

local function listLayout(parent, padding, horizontal)
    local l = Instance.new("UIListLayout")
    l.Padding = UDim.new(0, padding)
    l.SortOrder = Enum.SortOrder.LayoutOrder
    if horizontal then
        l.FillDirection = Enum.FillDirection.Horizontal
    end
    l.Parent = parent
    return l
end

local function padding(frame, x, y)
    local p = Instance.new("UIPadding")
    p.PaddingLeft = UDim.new(0, x)
    p.PaddingRight = UDim.new(0, x)
    p.PaddingTop = UDim.new(0, y or x)
    p.PaddingBottom = UDim.new(0, y or x)
    p.Parent = frame
end

local function rowFrame(parent, order)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, -4, 0, 34)
    f.BackgroundColor3 = PALETTE.card
    f.BorderSizePixel = 0
    f.LayoutOrder = order
    f.Parent = parent
    corner(f, 8)
    return f
end

local function checkRow(parent, text, order, initial, onChange)
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, -4, 0, 34)
    row.BackgroundColor3 = PALETTE.card
    row.BorderSizePixel = 0
    row.Text = ""
    row.AutoButtonColor = false
    row.LayoutOrder = order
    row.Parent = parent
    corner(row, 8)

    local lbl = label(row, text, 12, PALETTE.text, false)
    lbl.Position = UDim2.new(0, 10, 0, 0)
    lbl.Size = UDim2.new(1, -44, 1, 0)

    local box = Instance.new("Frame")
    box.Size = UDim2.fromOffset(18, 18)
    box.Position = UDim2.new(1, -28, 0.5, -9)
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
    return { refresh = paint }
end

local function arrowRow(parent, order, getText, onPrev, onNext)
    local row = rowFrame(parent, order)

    local prev = button(row, "◀", UDim2.fromOffset(34, 28), PALETTE.track)
    prev.Position = UDim2.new(0, 3, 0.5, -14)
    local nxt = button(row, "▶", UDim2.fromOffset(34, 28), PALETTE.track)
    nxt.Position = UDim2.new(1, -37, 0.5, -14)

    local lbl = label(row, "", 12, PALETTE.text, true)
    lbl.TextXAlignment = Enum.TextXAlignment.Center
    lbl.Position = UDim2.new(0, 42, 0, 0)
    lbl.Size = UDim2.new(1, -84, 1, 0)
    lbl.TextTruncate = Enum.TextTruncate.AtEnd

    prev.Activated:Connect(onPrev)
    nxt.Activated:Connect(onNext)

    return { refresh = function() lbl.Text = getText() end }
end

local function stepperRow(parent, order, getText, onMinus, onPlus)
    local row = rowFrame(parent, order)

    local lbl = label(row, "", 12, PALETTE.text, true)
    lbl.Position = UDim2.new(0, 10, 0, 0)
    lbl.Size = UDim2.new(1, -86, 1, 0)

    local minus = button(row, "−", UDim2.fromOffset(34, 28), PALETTE.track)
    minus.Position = UDim2.new(1, -76, 0.5, -14)
    minus.TextSize = 16
    local plus = button(row, "+", UDim2.fromOffset(34, 28), PALETTE.track)
    plus.Position = UDim2.new(1, -38, 0.5, -14)
    plus.TextSize = 16

    minus.Activated:Connect(onMinus)
    plus.Activated:Connect(onPlus)

    return { refresh = function() lbl.Text = getText() end }
end

local function numberRow(parent, order, name, getVal, setVal, getStep, boxWidth)
    local row = rowFrame(parent, order)
    boxWidth = boxWidth or 64

    local lbl = label(row, name, 12, PALETTE.text, true)
    lbl.Position = UDim2.new(0, 10, 0, 0)
    lbl.Size = UDim2.new(1, -(boxWidth + 90), 1, 0)

    local minus = button(row, "−", UDim2.fromOffset(30, 28), PALETTE.track)
    minus.Position = UDim2.new(1, -(boxWidth + 76), 0.5, -14)
    minus.TextSize = 16

    local box = Instance.new("TextBox")
    box.Size = UDim2.fromOffset(boxWidth, 28)
    box.Position = UDim2.new(1, -(boxWidth + 42), 0.5, -14)
    box.BackgroundColor3 = PALETTE.bg
    box.BorderSizePixel = 0
    box.TextColor3 = PALETTE.text
    box.Font = Enum.Font.GothamBold
    box.TextSize = 12
    box.ClearTextOnFocus = false
    box.Text = tostring(getVal())
    box.Parent = row
    corner(box, 6)

    local plus = button(row, "+", UDim2.fromOffset(30, 28), PALETTE.track)
    plus.Position = UDim2.new(1, -38, 0.5, -14)
    plus.TextSize = 16

    minus.Activated:Connect(function()
        setVal(getVal() - getStep())
    end)
    plus.Activated:Connect(function()
        setVal(getVal() + getStep())
    end)
    box.FocusLost:Connect(function()
        local n = tonumber(box.Text)
        if n then
            setVal(math.floor(n + 0.5))
        end
        box.Text = tostring(getVal())
    end)

    return {
        refresh = function()
            if not box:IsFocused() then
                box.Text = tostring(getVal())
            end
        end,
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

local main = Instance.new("Frame")
main.Name = "Main"
main.AnchorPoint = Vector2.new(0.5, 0.5)
main.Position = UDim2.new(0.5, 0, 0.5, 0)
main.BackgroundColor3 = PALETTE.bg
main.BorderSizePixel = 0
main.ClipsDescendants = true
main.Parent = gui
corner(main, 16)
stroke(main, PALETTE.accent, 1, 0.5)

local content = Instance.new("Frame")
content.Name = "Content"
content.Position = UDim2.new(0, 0, 0, 0)
content.BackgroundTransparency = 1
content.Parent = main

local contentScale = Instance.new("UIScale")
contentScale.Parent = content

local function applyPanelSize()
    panelW = math.clamp(panelW, CONFIG.PANEL_MIN_ANCHO, CONFIG.PANEL_MAX)
    panelH = math.clamp(panelH, CONFIG.PANEL_MIN_ALTO, CONFIG.PANEL_MAX)
    main.Size = UDim2.fromOffset(panelW, panelH)

    local s = math.min(panelW / BASE_W, panelH / BASE_H)
    contentScale.Scale = s
    content.Size = UDim2.fromOffset(panelW / s, panelH / s)
end

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 44)
header.BackgroundTransparency = 1
header.Parent = content

local title = label(header, "Cofres", 15, PALETTE.text, true)
title.Position = UDim2.new(0, 14, 0, 6)
title.Size = UDim2.new(1, -100, 0, 18)

local subtitle = label(header, statusText, 10, PALETTE.muted, false)
subtitle.Position = UDim2.new(0, 14, 0, 24)
subtitle.Size = UDim2.new(1, -100, 0, 14)
subtitle.TextTruncate = Enum.TextTruncate.AtEnd

local minBtn = button(header, "—", UDim2.fromOffset(30, 30), PALETTE.card)
minBtn.Position = UDim2.new(1, -72, 0, 7)
local closeBtn = button(header, "✕", UDim2.fromOffset(30, 30), PALETTE.red)
closeBtn.Position = UDim2.new(1, -36, 0, 7)

local statCard = Instance.new("Frame")
statCard.Position = UDim2.new(0, 10, 0, 48)
statCard.Size = UDim2.new(1, -20, 0, 54)
statCard.BackgroundColor3 = PALETTE.card
statCard.BorderSizePixel = 0
statCard.Parent = content
corner(statCard, 12)

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
barTrack.Position = UDim2.new(0, 10, 1, -11)
barTrack.Size = UDim2.new(1, -20, 0, 5)
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

local tabRow = Instance.new("Frame")
tabRow.Position = UDim2.new(0, 10, 0, 110)
tabRow.Size = UDim2.new(1, -20, 0, 30)
tabRow.BackgroundTransparency = 1
tabRow.Parent = content
listLayout(tabRow, 3, true)

local tabNames = { "Cofres", "Isla", "Bóveda", "Filtros", "Panel" }
local tabButtons = {}
for i, name in ipairs(tabNames) do
    local b = button(tabRow, name, UDim2.new(0.2, -3, 1, 0), PALETTE.card)
    b.TextSize = 11
    b.LayoutOrder = i
    tabButtons[i] = b
end

local pageArea = Instance.new("Frame")
pageArea.Position = UDim2.new(0, 10, 0, 148)
pageArea.Size = UDim2.new(1, -20, 1, -158)
pageArea.BackgroundTransparency = 1
pageArea.Parent = content

local pages = {}
local function newPage()
    local p = Instance.new("ScrollingFrame")
    p.Size = UDim2.new(1, 0, 1, 0)
    p.BackgroundTransparency = 1
    p.BorderSizePixel = 0
    p.ScrollBarThickness = 3
    p.ScrollBarImageColor3 = PALETTE.accent
    p.CanvasSize = UDim2.new(0, 0, 0, 0)
    p.AutomaticCanvasSize = Enum.AutomaticSize.Y
    p.Visible = false
    p.Parent = pageArea
    listLayout(p, 6)
    padding(p, 2, 2)
    table.insert(pages, p)
    return p
end

local pageCofres = newPage()
local pageIsla = newPage()
local pageBoveda = newPage()
local pageFiltros = newPage()
local pagePanel = newPage()

local function showTab(index)
    for i, p in ipairs(pages) do
        p.Visible = (i == index)
    end
    for i, b in ipairs(tabButtons) do
        b.BackgroundColor3 = (i == index) and PALETTE.accent or PALETTE.card
    end
end

for i, b in ipairs(tabButtons) do
    b.Activated:Connect(function() showTab(i) end)
end

---------------------------------------------------------------
-- PESTAÑA COFRES
---------------------------------------------------------------
checkRow(pageCofres, "Recolección automática", 1, auto, function(v)
    auto = v
    setStatus(v and "Buscando cofres..." or "Recolección apagada")
end)

checkRow(pageCofres, "Ir al barco y volver", 2, returnToSpot, function(v)
    returnToSpot = v
    markDirty()
    setStatus(v and "Volverá a tu posición tras guardar" or "Se quedará en el barco tras guardar")
end)

checkRow(pageCofres, "Solo cofres de otros jugadores", 3, onlyOthers, function(v)
    onlyOthers = v
    markDirty()
    setStatus(v and "Modo: solo cofres de otros" or "Modo: no tomar cofres de otros")
end)

local modeRow = Instance.new("Frame")
modeRow.Size = UDim2.new(1, -4, 0, 32)
modeRow.BackgroundTransparency = 1
modeRow.LayoutOrder = 4
modeRow.Parent = pageCofres
listLayout(modeRow, 6, true)

local tpBtn = button(modeRow, "⚡ Teletransporte", UDim2.new(0.5, -3, 1, 0), PALETTE.card)
local glideBtn = button(modeRow, "🌊 Deslizar", UDim2.new(0.5, -3, 1, 0), PALETTE.card)

local function cycleTarget(step)
    local opts = buildTargetOptions()
    local idx = 1
    for i, v in ipairs(opts) do
        if v == targetLabel then
            idx = i
            break
        end
    end
    idx = idx + step
    if idx < 1 then idx = #opts end
    if idx > #opts then idx = 1 end
    targetLabel = opts[idx]
    markDirty()

    if #opts == 1 then
        setStatus("Solo veo tu barco: acércate a otros barcos para que aparezcan")
    else
        setStatus("Destino: " .. targetLabel)
    end
end

local destRow = arrowRow(pageCofres, 5,
    function() return "Destino: " .. targetLabel end,
    function() cycleTarget(-1) end,
    function() cycleTarget(1) end
)

-- Información recordada del barco destino
local destNote = label(pageCofres, "", 10, PALETTE.muted, false)
destNote.LayoutOrder = 6
destNote.Size = UDim2.new(1, -4, 0, 30)
destNote.TextWrapped = true
destNote.TextYAlignment = Enum.TextYAlignment.Top

local waitStepper = stepperRow(pageCofres, 7,
    function() return "Espera en barco: " .. waitOnBoat .. " s" end,
    function()
        waitOnBoat = math.max(0, waitOnBoat - 1)
        markDirty()
        refreshUI()
    end,
    function()
        waitOnBoat = math.min(CONFIG.ESPERA_BARCO_MAX, waitOnBoat + 1)
        markDirty()
        refreshUI()
    end
)

---------------------------------------------------------------
-- PESTAÑA ISLA
---------------------------------------------------------------
checkRow(pageIsla, "Recolectar por isla", 1, islandMode, function(v)
    islandMode = v
    markDirty()
    setStatus(v and ("Modo isla: " .. currentIslandName()) or "Modo isla apagado")
end)

local diffRow = arrowRow(pageIsla, 2,
    function()
        return ISLAND_GROUPS[diffIndex].nombre .. " (" .. diffIndex .. "/" .. #ISLAND_GROUPS .. ")"
    end,
    function()
        diffIndex = diffIndex - 1
        if diffIndex < 1 then diffIndex = #ISLAND_GROUPS end
        islandIndex = 1
        markDirty()
        refreshUI()
    end,
    function()
        diffIndex = diffIndex + 1
        if diffIndex > #ISLAND_GROUPS then diffIndex = 1 end
        islandIndex = 1
        markDirty()
        refreshUI()
    end
)

local islandRow = arrowRow(pageIsla, 3,
    function()
        local group = ISLAND_GROUPS[diffIndex]
        return group.islas[islandIndex][1] .. " (" .. islandIndex .. "/" .. #group.islas .. ")"
    end,
    function()
        local count = #ISLAND_GROUPS[diffIndex].islas
        islandIndex = islandIndex - 1
        if islandIndex < 1 then islandIndex = count end
        markDirty()
        refreshUI()
    end,
    function()
        local count = #ISLAND_GROUPS[diffIndex].islas
        islandIndex = islandIndex + 1
        if islandIndex > count then islandIndex = 1 end
        markDirty()
        refreshUI()
    end
)

local islandNote = label(pageIsla, "", 10, PALETTE.muted, false)
islandNote.LayoutOrder = 4
islandNote.Size = UDim2.new(1, -4, 0, 30)
islandNote.TextWrapped = true
islandNote.TextYAlignment = Enum.TextYAlignment.Top

---------------------------------------------------------------
-- PESTAÑA BÓVEDA
---------------------------------------------------------------
local capStepper = stepperRow(pageBoveda, 1,
    function() return "Espacio de bóveda: " .. capacity end,
    function()
        capacity = math.max(1, capacity - 1)
        markDirty()
        refreshUI()
    end,
    function()
        capacity = math.min(CONFIG.CAPACIDAD_MAX, capacity + 1)
        markDirty()
        refreshUI()
    end
)

local vaultInfo = label(pageBoveda, "", 11, PALETTE.muted, false)
vaultInfo.LayoutOrder = 2
vaultInfo.Size = UDim2.new(1, -4, 0, 30)
vaultInfo.TextWrapped = true
vaultInfo.TextYAlignment = Enum.TextYAlignment.Top

local emptyBtn = button(pageBoveda, "🏦 Vaciar bóveda ahora", UDim2.new(1, -4, 0, 36), PALETTE.accent)
emptyBtn.LayoutOrder = 3
emptyBtn.Activated:Connect(function()
    manualOpenRequested = true
    setStatus("Se vaciará la bóveda en el próximo ciclo")
end)

---------------------------------------------------------------
-- PESTAÑA FILTROS
---------------------------------------------------------------
checkRow(pageFiltros, "Filtrar por valor (Value)", 1, valueFilter, function(v)
    valueFilter = v
    markDirty()
    setStatus(v and ("Solo cofres con valor ≥ " .. valueMin) or "Filtro de valor apagado")
end)

local valueRow = numberRow(pageFiltros, 2, "Valor mín.",
    function() return valueMin end,
    function(v)
        valueMin = math.max(0, v)
        markDirty()
        refreshUI()
    end,
    function() return CONFIG.VALOR_PASO end,
    78
)

checkRow(pageFiltros, "Filtrar por rareza (Rarity)", 3, rarityFilter, function(v)
    rarityFilter = v
    markDirty()
    setStatus(v and ("Solo cofres desde " .. CONFIG.RAREZAS[rarityMinIdx]) or "Filtro de rareza apagado")
end)

local rarityRow = arrowRow(pageFiltros, 4,
    function()
        return "Mínima: " .. CONFIG.RAREZAS[rarityMinIdx] .. " (" .. rarityMinIdx .. "/" .. #CONFIG.RAREZAS .. ")"
    end,
    function()
        rarityMinIdx = rarityMinIdx - 1
        if rarityMinIdx < 1 then rarityMinIdx = #CONFIG.RAREZAS end
        markDirty()
        refreshUI()
    end,
    function()
        rarityMinIdx = rarityMinIdx + 1
        if rarityMinIdx > #CONFIG.RAREZAS then rarityMinIdx = 1 end
        markDirty()
        refreshUI()
    end
)

local filterNote = label(pageFiltros, "", 10, PALETTE.muted, false)
filterNote.LayoutOrder = 5
filterNote.Size = UDim2.new(1, -4, 0, 44)
filterNote.TextWrapped = true
filterNote.TextYAlignment = Enum.TextYAlignment.Top

---------------------------------------------------------------
-- PESTAÑA PANEL
---------------------------------------------------------------
local function currentStep()
    return CONFIG.PANEL_PASOS[panelStepIdx]
end

local function setPanelW(v)
    panelW = v
    applyPanelSize()
    markDirty()
    refreshUI()
end

local function setPanelH(v)
    panelH = v
    applyPanelSize()
    markDirty()
    refreshUI()
end

local widthRow = numberRow(pagePanel, 1, "Ancho",
    function() return panelW end,
    setPanelW,
    currentStep,
    64
)

local heightRow = numberRow(pagePanel, 2, "Alto",
    function() return panelH end,
    setPanelH,
    currentStep,
    64
)

local stepSelector = arrowRow(pagePanel, 3,
    function() return "Paso de − y +: " .. currentStep() .. " px" end,
    function()
        panelStepIdx = panelStepIdx - 1
        if panelStepIdx < 1 then panelStepIdx = #CONFIG.PANEL_PASOS end
        markDirty()
        refreshUI()
    end,
    function()
        panelStepIdx = panelStepIdx + 1
        if panelStepIdx > #CONFIG.PANEL_PASOS then panelStepIdx = 1 end
        markDirty()
        refreshUI()
    end
)

local resetBtn = button(pagePanel, "↺ Tamaño por defecto", UDim2.new(1, -4, 0, 36), PALETTE.card)
resetBtn.LayoutOrder = 4
resetBtn.Activated:Connect(function()
    panelW = CONFIG.PANEL_ANCHO_INICIAL
    panelH = CONFIG.PANEL_ALTO_INICIAL
    applyPanelSize()
    markDirty()
    refreshUI()
end)

local panelNote = label(pagePanel,
    "Escribe el ancho y el alto en la caja, o usa − y +. La configuración se guarda sola.",
    10, PALETTE.muted, false)
panelNote.LayoutOrder = 5
panelNote.Size = UDim2.new(1, -4, 0, 40)
panelNote.TextWrapped = true
panelNote.TextYAlignment = Enum.TextYAlignment.Top

local mini = button(gui, "🏴‍☠️", UDim2.fromOffset(48, 48), PALETTE.card)
mini.TextSize = 20
mini.Visible = false
stroke(mini, PALETTE.accent, 1, 0.3)
makeDraggable(mini, mini)

makeDraggable(header, main)

applyPanelSize()

---------------------------------------------------------------
-- ACTUALIZAR UI
---------------------------------------------------------------
refreshUI = function()
    local used = usedSpace()
    subtitle.Text = statusText
    countLabel.Text = tostring(collectedCount)
    vaultLabel.Text = used .. "/" .. capacity
    barFill.Size = UDim2.new(math.clamp(used / math.max(capacity, 1), 0, 1), 0, 1, 0)

    tpBtn.BackgroundColor3 = mode == "TP" and PALETTE.accent or PALETTE.card
    glideBtn.BackgroundColor3 = mode == "DESLIZAR" and PALETTE.accent or PALETTE.card

    destRow.refresh()

    local m = shipMemory[targetLabel]
    if targetLabel == MINE_LABEL then
        destNote.Text = "Los cofres se guardan en tu barco."
    elseif m then
        local estado = (m.ship and m.ship.Parent) and "cargado" or "recordado (se cargará al ir)"
        destNote.Text = "Barco: " .. (m.shipName or "?") .. " · " .. estado
    else
        destNote.Text = "Aún no he visto este barco en esta sesión."
    end

    waitStepper.refresh()
    diffRow.refresh()
    islandRow.refresh()
    islandNote.Text = islandMode
        and ("Irá a " .. currentIslandName() .. " y solo recogerá cofres dentro de esa isla.")
        or "Activa la opción para recoger solo en la isla elegida."

    capStepper.refresh()
    vaultInfo.Text = "Guardados en tu barco: " .. #getStoredChests() .. " cofres, " .. used .. " de " .. capacity .. " espacios."

    valueRow.refresh()
    rarityRow.refresh()
    filterNote.Text = "Valor: recoge cofres con Value ≥ " .. valueMin
        .. (valueFilter and " (activo)" or " (apagado)")
        .. ". Rareza: desde " .. CONFIG.RAREZAS[rarityMinIdx]
        .. (rarityFilter and " (activo)" or " (apagado)") .. "."

    widthRow.refresh()
    heightRow.refresh()
    stepSelector.refresh()
end

tpBtn.Activated:Connect(function()
    mode = "TP"
    markDirty()
    refreshUI()
end)

glideBtn.Activated:Connect(function()
    mode = "DESLIZAR"
    markDirty()
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
    saveConfig()
    gui:Destroy()
end)

showTab(1)

task.spawn(function()
    while not closed do
        if dirty then
            dirty = false
            saveConfig()
        end

        if manualOpenRequested then
            manualOpenRequested = false
            pcall(openVault)
        elseif auto then
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
