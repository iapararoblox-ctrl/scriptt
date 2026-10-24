-- Recolección de cofres + barco + barco de otro jugador (con memoria de sesión) + tesorero + mares/islas (español/inglés) + filtros + COMBATE AUTOMÁTICO
-- + PUNTO DE ENTREGA (automático o manual) + POSICIÓN GUARDADA DE PANEL Y BURBUJA
-- + RECORRIDO DE TODAS LAS ISLAS DE UN MAR + RAREZA "Secret" (el filtro incluye la elegida y las superiores)
-- + PUNTO MANUAL DEL TESORERO (para vaciar la bóveda) + VALIDACIÓN Y DIAGNÓSTICO DE TAMAÑOS DE COFRES
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

-- Todo el combate vive en esta tabla para no pasar el límite de 200 variables locales
local CB = {}
-- Punto de entrega, tesorero, tamaños y posiciones de la UI viven aquí por el mismo motivo
local EX = {}

---------------------------------------------------------------
-- MARES E ISLAS
-- I(nombreEnIngles, nombreEnEspañol, ...alias)
-- El nombre en inglés es el que usa el juego para encontrar la isla.
---------------------------------------------------------------
local function I(en, es, ...)
    local names = { en }
    for _, a in ipairs({ ... }) do
        table.insert(names, a)
    end
    return { en = en, es = es, names = names }
end

local ISLAND_GROUPS = {
    { en = "Calm", es = "Calma", islas = {
        I("StarterPort", "Puerto Inicial", "Starter Port"),
        I("FinnsBeach", "Playa de Finn", "Starter Island"),
        I("TinyCay", "Cayo Diminuto", "Small Island"),
        I("MerchantBay", "Bahía del Mercader"),
        I("PalmCove", "Cala Palmera"),
        I("CorallIsland", "Isla Coral", "CoralIsland"),
        I("CoconutAtoll", "Atolón del Coco"),
        I("GullSpire", "Aguja de la Gaviota"),
        I("TurtleRock", "Roca Tortuga"),
        I("SkullRock", "Roca Calavera"),
        I("CrabKingLair", "Guarida del Rey Cangrejo", "Crab Shoals"),
        I("CalmAnchors", "Anclas de la Calma"),
    }},
    { en = "Wild", es = "Salvaje", islas = {
        I("RedwaterHaven", "Refugio Aguaroja"),
        I("CutthroatKey", "Cayo Degollador"),
        I("ThunderFalls", "Cataratas del Trueno"),
        I("ParrotPeak", "Pico del Loro"),
        I("FangJungle", "Jungla Colmillo"),
        I("RedBeardsCove", "Cala Barbarroja"),
    }},
    { en = "Sunken", es = "Hundido", islas = {
        I("CoralSpire", "Aguja de Coral"),
        I("GuardianTemple", "Templo Guardián"),
        I("TidalColonnade", "Columnata de la Marea"),
        I("CatacombIsle", "Isla Catacumba"),
        I("DrownedThrone", "Trono Ahogado"),
    }},
    { en = "Frozen", es = "Helado", islas = {
        I("Frostpoint", "Punta Escarcha"),
        I("Rimeclaw", "Garra de Escarcha"),
        I("Howling", "Aullante"),
        I("Shiverpeak", "Pico Escalofrío"),
        I("WreckersFloe", "Banquisa de Naufragios"),
        I("LeviathanStrait", "Estrecho del Leviatán"),
        I("OpenWater", "Mar Abierto"),
    }},
    { en = "Ash", es = "Ceniza", islas = {
        I("CinderDock", "Muelle de Brasas"),
        I("MountPyre", "Monte Pira"),
        I("KrakenCaldera", "Caldera del Kraken"),
        I("BlackpowderCove", "Cala Pólvora Negra"),
        I("ObsidianKey", "Cayo Obsidiana"),
        I("OpenWater", "Mar Abierto"),
    }},
    { en = "Ironbound", es = "Férreo", islas = {
        I("BlackIronPort", "Puerto Hierro Negro"),
        I("ChainbreakAtoll", "Atolón Rompecadenas"),
        I("FoundryIsle", "Isla Fundición"),
        I("IronwallBastion", "Bastión Muro de Hierro"),
        I("RivetRocks", "Rocas Remache"),
        I("TheAnvil", "El Yunque"),
        I("Seabed", "Lecho Marino"),
    }},
    { en = "Cursed", es = "Maldito", islas = {
        I("LanternsEnd", "Fin de los Faroles"),
        I("WreckersGraveyard", "Cementerio de Naufragios"),
        I("GallowsKey", "Cayo de la Horca"),
        I("WidowsRest", "Descanso de la Viuda"),
        I("WailingSpires", "Agujas Lamentosas"),
        I("DutchmansFog", "Niebla del Holandés"),
    }},
    { en = "Celestial", es = "Celestial", islas = {
        I("StarfallSanctuary", "Santuario de la Estrella Fugaz"),
        I("PrismReef", "Arrecife Prisma"),
        I("SkyholdGardens", "Jardines de la Fortaleza Celeste"),
        I("AstralRuins", "Ruinas Astrales"),
        I("MoonpetalAtoll", "Atolón Pétalo Lunar"),
        I("AuroraRift", "Grieta de la Aurora"),
    }},
    { en = "DeadMans", es = "Mar del Muerto", islas = {
        I("AbyssGate", "Puerta del Abismo"),
        I("Skullcrag", "Risco Calavera"),
        I("LeviathansGrave", "Tumba del Leviatán"),
        I("BrokenArmada", "Armada Rota"),
        I("DavysLocker", "Cofre de Davy"),
    }},
    { en = "Abyssal", es = "Abisal", islas = {
        I("BlackwakeHarbor", "Puerto Estela Negra"),
        I("MidnightReef", "Arrecife de Medianoche"),
        I("TrenchgatePassage", "Paso de la Puerta de la Fosa"),
        I("DrownedCathedral", "Catedral Ahogada"),
        I("AbyssalThrone", "Trono Abisal"),
        I("HollowmastGraveyard", "Cementerio del Mástil Hueco"),
        I("Seabed", "Lecho Marino"),
    }},
}

---------------------------------------------------------------
-- CONFIGURACIÓN
---------------------------------------------------------------
local CONFIG = {
    VOLVER_INICIAL = false,
    SOLO_OTROS_INICIAL = false,
    ISLA_INICIAL = false,
    INGLES_INICIAL = false,        -- false = nombres en español (por defecto), true = en inglés
    DIFICULTAD_INICIAL = 1,
    ISLA_INDEX_INICIAL = 1,
    MARGEN_ISLA = 60,
    RADIO_ISLA_SIN_CAJA = 300,
    RADIO_MIN_ISLA = 200,          -- radio mínimo de la isla aunque su caja sea pequeña
    ALTURA_ISLA = 0,               -- altura a la que se queda en la isla (lejos de los enemigos)
    ESPERA_STREAMING = 2,          -- segundos esperando que carguen los cofres al llegar
    ESPERA_POSICION = 0.25,        -- segundos para que el servidor reciba tu posición antes de recoger
    INTENTOS_RECOGER = 2,          -- veces que intenta activar el prompt de un cofre
    MODO_INICIAL = "TP",
    VELOCIDAD_DESLIZAR = 45,
    CAPACIDAD_INICIAL = 173,
    CAPACIDAD_MAX = 172,
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

    -- PUNTO DE ENTREGA EN EL BARCO
    PUNTO_MODO_INICIAL = "AUTO",   -- "AUTO" = parte alta del centro del barco (como antes), "MANUAL" = el punto que tú fijes
    PUNTO_DISTANCIA_MAX = 150,     -- máximo de studs entre tú y el barco al fijar el punto

    -- PUNTO DEL TESORERO (para vaciar la bóveda)
    TESORERO_MODO_INICIAL = "AUTO", -- "AUTO" = va al NPC tesorero, "MANUAL" = va al punto que tú fijes
    CONTADOR_JUEGO_INICIAL = true,  -- usa el contador de espacio del propio barco si el juego lo tiene

    VALOR_FILTRO_INICIAL = false,
    VALOR_MIN_INICIAL = 10000,
    VALOR_PASO = 1000,
    RAREZA_FILTRO_INICIAL = false,
    RAREZA_MIN_INICIAL = 3,
    RAREZAS = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Divine", "Secret" },

    -- COMBATE
    PREFIJO_TIERRA = "Enemy_",         -- enemigos de tierra: Enemy_(nombre)
    PREFIJO_BARCO = "NPCShip_",        -- enemigos en barco: NPCShip_(nombre)
    ATAQUE_POR_ISLA_INICIAL = true,    -- solo ataca enemigos dentro de la isla elegida
    EQUIPAR_AUTO_INICIAL = true,       -- si no tienes tool en la mano, equipa la primera de la mochila
    OBJETIVO_INICIAL = "*ALL",         -- *ALL = todos, *LAND = todos de tierra, *SHIP = todos de barco
    ATAQUE_DISTANCIA_INICIAL = 4,      -- studs de distancia al enemigo
    ATAQUE_ALTURA_INICIAL = 0,         -- studs extra de altura sobre el enemigo
    ATAQUE_DISTANCIA_MAX = 40,
    ATAQUE_ALTURA_MIN = -20,
    ATAQUE_ALTURA_MAX = 40,
    ESPERA_ATAQUE = 0.15,              -- segundos entre cada golpe (tool:Activate)
    ATAQUE_TIMEOUT = 25,               -- segundos máximos por enemigo antes de saltarlo
    ENEMIGO_BLOQUEO = 30,              -- segundos que se ignora un enemigo al que no se pudo matar
    MAX_ENEMIGOS_POR_CICLO = 5,        -- tras estos kills deja turno a la recolección de cofres

    PANEL_ANCHO_INICIAL = 280,
    PANEL_ALTO_INICIAL = 440,
    PANEL_MIN_ANCHO = 50,
    PANEL_MIN_ALTO = 10,
    PANEL_MAX = 3000,
    PANEL_PASOS = { 1, 5, 10, 20, 50 },
    PANEL_PASO_INICIAL = 3,

    BURBUJA_TAMANO = 48,               -- tamaño de la burbuja minimizada
    ARRASTRE_MIN = 6,                  -- píxeles que hay que mover para que cuente como arrastre y no como toque

    CONFIG_ARCHIVO = "CofresConfig.json",
    DEBUG = true,
}

local BASE_W, BASE_H = 300, 470
local OWNER_KEYS = { "Owner", "OwnerId", "OwnerName", "Player", "PlayerName", "UserId" }
local MINE_LABEL = "Mi barco"
local HOVER_NAME = "CofresHover"

CB.ENEMY_ALL, CB.ENEMY_LAND, CB.ENEMY_SHIP = "*ALL", "*LAND", "*SHIP"

-- Nombres exactos que usa el juego (si los tiene) para el espacio de la bóveda del barco
EX.USED_KEYS = { "CargoUsed", "UsedCargo", "CargoSpaceUsed", "CargoCount", "CurrentCargo", "UsedSpace" }
EX.CAP_KEYS = { "CargoCapacity", "MaxCargo", "CargoMax", "CargoSpace", "CargoSlots", "MaxCargoSize" }

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

function CB.getEnemiesFolder()
    local dyn = getDynamic()
    return dyn and dyn:FindFirstChild("Enemies")
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
local englishNames = svb("englishNames", CONFIG.INGLES_INICIAL)
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

-- Punto de entrega en el barco
-- dropMode: "AUTO" (parte alta del centro, como siempre) o "MANUAL" (punto fijado por ti)
-- dropOffset: posición del punto RELATIVA al barco (así te sigue aunque el barco se mueva o gire)
EX.dropMode = saved.dropMode
if EX.dropMode ~= "MANUAL" and EX.dropMode ~= "AUTO" then
    EX.dropMode = CONFIG.PUNTO_MODO_INICIAL
end
EX.dropOffset = nil
if type(saved.dropOffset) == "table" then
    local x, y, z = tonumber(saved.dropOffset[1]), tonumber(saved.dropOffset[2]), tonumber(saved.dropOffset[3])
    if x and y and z then
        EX.dropOffset = Vector3.new(x, y, z)
    end
end
if EX.dropMode == "MANUAL" and not EX.dropOffset then
    EX.dropMode = "AUTO"
end

-- Punto del tesorero (donde te paras para vaciar la bóveda)
-- brokerMode: "AUTO" (va al NPC tesorero) o "MANUAL" (va al punto que tú fijaste, posición fija del mundo)
EX.brokerMode = saved.brokerMode
if EX.brokerMode ~= "MANUAL" and EX.brokerMode ~= "AUTO" then
    EX.brokerMode = CONFIG.TESORERO_MODO_INICIAL
end
EX.brokerPos = nil
if type(saved.brokerPos) == "table" then
    local x, y, z = tonumber(saved.brokerPos[1]), tonumber(saved.brokerPos[2]), tonumber(saved.brokerPos[3])
    if x and y and z then
        EX.brokerPos = Vector3.new(x, y, z)
    end
end
if EX.brokerMode == "MANUAL" and not EX.brokerPos then
    EX.brokerMode = "AUTO"
end

-- Usar el contador de espacio del juego si el barco lo tiene
EX.useGameCounter = svb("useGameCounter", CONFIG.CONTADOR_JUEGO_INICIAL)

-- Recorrer todas las islas del mar elegido (una tras otra) buscando cofres que pasen tus filtros
EX.sweepMode = svb("sweepMode", false)

-- Posición guardada del panel {xScale, xOffset, yScale, yOffset} y de la burbuja {x, y}
EX.mainPos = nil
if type(saved.mainPos) == "table" then
    local a, b, c, d = tonumber(saved.mainPos[1]), tonumber(saved.mainPos[2]), tonumber(saved.mainPos[3]), tonumber(saved.mainPos[4])
    if a and b and c and d then
        EX.mainPos = { a, b, c, d }
    end
end
EX.miniPos = nil
if type(saved.miniPos) == "table" then
    local a, b = tonumber(saved.miniPos[1]), tonumber(saved.miniPos[2])
    if a and b then
        EX.miniPos = { a, b }
    end
end

-- Combate
CB.attackEnabled = false
CB.attackByIsland = svb("attackByIsland", CONFIG.ATAQUE_POR_ISLA_INICIAL)
CB.autoEquip = svb("autoEquip", CONFIG.EQUIPAR_AUTO_INICIAL)
CB.attackTarget = svs("attackTarget", CONFIG.OBJETIVO_INICIAL)
CB.attackDist = math.clamp(math.floor(svn("attackDist", CONFIG.ATAQUE_DISTANCIA_INICIAL)), 0, CONFIG.ATAQUE_DISTANCIA_MAX)
CB.attackHeight = math.clamp(math.floor(svn("attackHeight", CONFIG.ATAQUE_ALTURA_INICIAL)),
    CONFIG.ATAQUE_ALTURA_MIN, CONFIG.ATAQUE_ALTURA_MAX)
CB.killedCount = 0

-- Memoria de sesión de enemigos vistos (nombre completo -> "LAND" | "SHIP")
CB.enemyMemory = {}
CB.enemyOrder = {}
-- Enemigos que no se pudieron matar a tiempo (se ignoran un rato)
CB.enemyBlacklist = setmetatable({}, { __mode = "k" })

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
        englishNames = englishNames,
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
        attackByIsland = CB.attackByIsland,
        autoEquip = CB.autoEquip,
        attackTarget = CB.attackTarget,
        attackDist = CB.attackDist,
        attackHeight = CB.attackHeight,
        dropMode = EX.dropMode,
        dropOffset = EX.dropOffset and { EX.dropOffset.X, EX.dropOffset.Y, EX.dropOffset.Z } or nil,
        brokerMode = EX.brokerMode,
        brokerPos = EX.brokerPos and { EX.brokerPos.X, EX.brokerPos.Y, EX.brokerPos.Z } or nil,
        useGameCounter = EX.useGameCounter,
        sweepMode = EX.sweepMode,
        mainPos = EX.mainPos,
        miniPos = EX.miniPos,
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

-- Nombres que se muestran en la UI (español por defecto, inglés si está activado)
local function seaDisplayName(group)
    return englishNames and group.en or group.es
end

local function islandDisplayName(entry)
    return englishNames and entry.en or entry.es
end

local function currentIslandEntry()
    return ISLAND_GROUPS[diffIndex].islas[islandIndex]
end

local function currentIslandName()
    return islandDisplayName(currentIslandEntry())
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

-- Convierte a número válido (acepta texto tipo "3"); rechaza nil, NaN, negativos y 0
function EX.validSize(v)
    local n = tonumber(v)
    if n and n == n and n > 0 and n < math.huge then
        return n
    end
    return nil
end

-- Lee el tamaño de un cofre mirando varios sitios. Devuelve (tamaño, de dónde lo sacó).
-- "defecto" significa que NO se pudo leer y se usó TAMANO_POR_DEFECTO.
function EX.readSize(chest)
    local v = EX.validSize(chest:GetAttribute("CargoSize"))
    if v then return v, "atributo" end

    local child = chest:FindFirstChild("CargoSize")
    if child and child:IsA("ValueBase") then
        v = EX.validSize(child.Value)
        if v then return v, "valor" end
    end

    for _, d in ipairs(chest:GetDescendants()) do
        v = EX.validSize(d:GetAttribute("CargoSize"))
        if v then return v, "interno" end
        if d.Name == "CargoSize" and d:IsA("ValueBase") then
            v = EX.validSize(d.Value)
            if v then return v, "interno" end
        end
    end

    return CONFIG.TAMANO_POR_DEFECTO, "defecto"
end

local function getCargoSize(obj)
    local size = EX.readSize(obj)
    return size
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
    local key = entry.en
    local cached = islandCache[key]
    if cached and cached.Parent then
        return cached
    end
    islandCache[key] = nil

    local targets = {}
    for _, name in ipairs(entry.names) do
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
    local m = CONFIG.MARGEN_ISLA
    if island:IsA("Model") then
        local cf, size = island:GetBoundingBox()
        local rel = cf:PointToObjectSpace(pos)
        if math.abs(rel.X) <= size.X / 2 + m
            and math.abs(rel.Z) <= size.Z / 2 + m
            and math.abs(rel.Y) <= size.Y / 2 + 300 then
            return true
        end
        -- Respaldo: círculo alrededor del centro (cubre cajas giradas o pequeñas)
        local flat = Vector3.new(cf.Position.X - pos.X, 0, cf.Position.Z - pos.Z)
        local radius = math.max(math.max(size.X, size.Z) / 2 + m, CONFIG.RADIO_MIN_ISLA)
        return flat.Magnitude <= radius
    end
    local flat = Vector3.new(island.Position.X - pos.X, 0, island.Position.Z - pos.Z)
    return flat.Magnitude <= CONFIG.RADIO_ISLA_SIN_CAJA
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

-- Teletransporte instantáneo, sin espera (para seguir a un enemigo mientras se ataca)
function CB.snapToCFrame(cf)
    local root = getRoot()
    if not root then return false end
    root.AssemblyLinearVelocity = Vector3.zero
    root.CFrame = cf
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

-- Flotar: el personaje se queda quieto en el aire para que los enemigos no lo alcancen.
-- IMPORTANTE: NO se ancla (Anchored). Un personaje anclado no envía su posición al servidor,
-- y entonces el servidor creía que seguías lejos del cofre y no dejaba recogerlo.
-- En su lugar se usa un BodyVelocity en cero que cancela la gravedad y mantiene la replicación.
local hovering = false

local function hoverActive(root)
    root = root or getRoot()
    return root ~= nil and root:FindFirstChild(HOVER_NAME) ~= nil
end

local function setHover(on)
    hovering = on
    local root = getRoot()
    if not root then return end
    pcall(function()
        root.Anchored = false
        local old = root:FindFirstChild(HOVER_NAME)
        if on then
            if not old then
                local bv = Instance.new("BodyVelocity")
                bv.Name = HOVER_NAME
                bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
                bv.P = 1e4
                bv.Velocity = Vector3.zero
                bv.Parent = root
            end
        elseif old then
            old:Destroy()
        end
    end)
end

local function groundY(pos)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LocalPlayer.Character }
    local res = Workspace:Raycast(pos + Vector3.new(0, 300, 0), Vector3.new(0, -800, 0), params)
    return res and res.Position.Y or nil
end

-- Sube a ALTURA_ISLA sobre el suelo en el punto actual y se queda flotando
local function hoverHere()
    local root = getRoot()
    if not root then return end
    local p = root.Position
    local gy = groundY(p)
    local y = gy and (gy + CONFIG.ALTURA_ISLA) or p.Y
    teleportTo(Vector3.new(p.X, y, p.Z))
    setHover(true)
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
    setHover(false)
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
-- PUNTO DE ENTREGA EN EL BARCO
--   AUTO   -> parte alta del centro del barco (comportamiento de siempre)
--   MANUAL -> el punto que fijaste parado en el barco (se guarda relativo al barco)
---------------------------------------------------------------
function EX.shipCFrame(ship)
    if ship:IsA("Model") then
        return ship:GetPivot()
    end
    return ship.CFrame
end

-- Posición en el mundo a la que hay que ir para guardar el cofre en "ship"
function EX.dropPoint(ship)
    if EX.dropMode == "MANUAL" and EX.dropOffset then
        return EX.shipCFrame(ship):PointToWorldSpace(EX.dropOffset)
    end
    return getShipTop(ship)
end

-- Barco destino SOLO si ya está cargado (no te teletransporta a buscarlo)
function EX.loadedDestShip()
    if targetLabel == MINE_LABEL or targetLabel == "" then
        return getMyShip()
    end
    local m = shipMemory[targetLabel]
    if m and m.ship and m.ship.Parent then
        return m.ship
    end
    return nil
end

-- Fija el punto en tu posición actual (debes estar parado en el barco destino)
function EX.setPointHere()
    local root = getRoot()
    if not root then
        setStatus("No encuentro tu personaje")
        return
    end
    local ship = EX.loadedDestShip()
    if not ship then
        setStatus("No encuentro el barco destino cargado: acércate a él")
        return
    end
    local rel = EX.shipCFrame(ship):PointToObjectSpace(root.Position)
    if rel.Magnitude > CONFIG.PUNTO_DISTANCIA_MAX then
        setStatus("Estás muy lejos del barco destino: párate sobre él")
        return
    end
    EX.dropOffset = rel
    EX.dropMode = "MANUAL"
    markDirty()
    setStatus(string.format("Punto manual fijado (%.1f, %.1f, %.1f)", rel.X, rel.Y, rel.Z))
end

function EX.setDropMode(newMode)
    if newMode == "MANUAL" and not EX.dropOffset then
        setStatus("Aún no hay punto manual: párate en el barco y pulsa «Fijar aquí»")
        return
    end
    EX.dropMode = newMode
    markDirty()
    setStatus(newMode == "MANUAL" and "Entrega en tu punto manual" or "Entrega automática (centro del barco)")
end

-- Va al punto actual de entrega para que veas dónde queda
function EX.goToPoint()
    local ship = EX.loadedDestShip()
    if not ship then
        setStatus("No encuentro el barco destino cargado")
        return
    end
    setHover(false)
    teleportTo(EX.dropPoint(ship))
    setStatus("Estás en el punto de entrega")
end

---------------------------------------------------------------
-- BÓVEDA (CargoVisuals de cualquier barco)
-- Se validan los cofres: solo Models, sin repetidos (por nombre) y con el tamaño leído de forma robusta.
---------------------------------------------------------------
local function chestsOn(ship)
    local cargo = ship and ship:FindFirstChild("CargoVisuals")
    local list = {}
    local seen = {}
    if cargo then
        for _, child in ipairs(cargo:GetChildren()) do
            if child:IsA("Model") and child.Parent == cargo and not seen[child.Name] then
                seen[child.Name] = true
                table.insert(list, child)
            end
        end
    end
    return list
end

-- Suma de tamaños de los cofres que hay en la bóveda (+ cuántos no tenían tamaño legible)
function EX.countedSpaceOn(ship)
    local total, unreadable, n = 0, 0, 0
    for _, chest in ipairs(chestsOn(ship)) do
        local size, src = EX.readSize(chest)
        total += size
        n += 1
        if src == "defecto" then
            unreadable += 1
        end
    end
    return total, unreadable, n
end

-- Contador de espacio del propio juego (solo si el barco lo expone con un nombre conocido)
function EX.gameCargo(ship)
    if not ship then return nil, nil end
    local used, cap
    for _, k in ipairs(EX.USED_KEYS) do
        local v = tonumber(getChestProp(ship, k))
        if v then used = v break end
    end
    for _, k in ipairs(EX.CAP_KEYS) do
        local v = tonumber(getChestProp(ship, k))
        if v and v > 0 then cap = v break end
    end
    return used, cap
end

local function usedSpaceOn(ship)
    if EX.useGameCounter then
        local gameUsed = EX.gameCargo(ship)
        if gameUsed then
            return gameUsed
        end
    end
    local counted = EX.countedSpaceOn(ship)
    return counted
end

-- Capacidad que se usa de verdad: la del juego si existe (y está activado), si no la tuya
function EX.capFor(ship)
    if EX.useGameCounter then
        local _, gameCap = EX.gameCargo(ship)
        if gameCap then
            return gameCap
        end
    end
    return capacity
end

local function getStoredChests()
    return chestsOn(getMyShip())
end

local function usedSpace()
    return usedSpaceOn(getMyShip())
end

-- Imprime en la consola (F9 / consola del ejecutor) cada cofre de tu bóveda con su tamaño y de dónde se leyó
function EX.diagnose()
    local ship = getMyShip()
    if not ship then
        setStatus("No encuentro tu barco")
        return
    end
    local cargo = ship:FindFirstChild("CargoVisuals")
    if not cargo then
        setStatus("Tu barco no tiene CargoVisuals")
        return
    end

    print("[COFRES] ===== DIAGNÓSTICO DE BÓVEDA =====")
    print("[COFRES] Barco:", ship:GetFullName())

    local rawModels, ignored = 0, 0
    for _, c in ipairs(cargo:GetChildren()) do
        if c:IsA("Model") then
            rawModels += 1
        else
            ignored += 1
            print("[COFRES] Ignorado (no es Model):", c.ClassName, c.Name)
        end
    end

    local total, unreadable = 0, 0
    local list = chestsOn(ship)
    for i, chest in ipairs(list) do
        local size, src = EX.readSize(chest)
        total += size
        if src == "defecto" then unreadable += 1 end
        print(string.format("[COFRES] %d) %s | tamaño=%s (%s) | rareza=%s | valor=%s",
            i, chest.Name, tostring(size), src,
            tostring(getChestProp(chest, "Rarity")), tostring(getChestProp(chest, "Value"))))
    end

    local duplicates = rawModels - #list
    if duplicates > 0 then
        print("[COFRES] Cofres repetidos (mismo nombre) descartados:", duplicates)
    end

    for k, v in pairs(ship:GetAttributes()) do
        print("[COFRES] atributo del barco:", k, v)
    end

    local gu, gc = EX.gameCargo(ship)
    print("[COFRES] Contado:", total, "| cofres:", #list, "| sin tamaño legible:", unreadable,
        "| contador del juego:", tostring(gu), "/", tostring(gc))
    print("[COFRES] =================================")

    setStatus(string.format("Bóveda: %d cofres, %d espacios contados%s%s",
        #list, total,
        unreadable > 0 and (", " .. unreadable .. " sin tamaño") or "",
        gu and (", juego: " .. gu) or ""))
end

---------------------------------------------------------------
-- RECOGER, GUARDAR, ESPERAR
---------------------------------------------------------------
-- Se coloca justo sobre el prompt del cofre (a "height" studs) y lo activa.
-- En modo isla: height = ALTURA_ISLA y se queda flotando, sin anclarse.
local function pickUpChest(base, prompt, height, hover)
    local anchorPos = base.Position
    local att = prompt.Parent
    if att and att:IsA("Attachment") then
        anchorPos = att.WorldPosition
    end

    teleportTo(anchorPos + Vector3.new(0, height or CONFIG.ALTURA, 0))
    if hover then setHover(true) end

    pcall(function()
        prompt.RequiresLineOfSight = false
        if prompt.MaxActivationDistance < 25 then
            prompt.MaxActivationDistance = 25
        end
    end)

    -- Deja que el servidor reciba tu nueva posición antes de activar el prompt
    task.wait(CONFIG.ESPERA_POSICION)

    for _ = 1, CONFIG.INTENTOS_RECOGER do
        pcall(fireproximityprompt, prompt)
        task.wait(CONFIG.ESPERA_RECOGER)
        if not prompt.Parent or not prompt:IsDescendantOf(Workspace) then
            break
        end
    end
end

local function storeOnBoat(usedBefore, dest)
    if not dest then
        setStatus("No encuentro el barco destino")
        return false
    end

    setStatus("Guardando en " .. targetLabel .. "...")
    -- Automático: parte alta del centro. Manual: el punto que fijaste.
    teleportTo(EX.dropPoint(dest))

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
--   AUTO   -> va al NPC tesorero (NPC_StarterPort_Broker)
--   MANUAL -> va al punto del mundo que fijaste parado cerca del tesorero
---------------------------------------------------------------
function EX.brokerNPC()
    local dyn = getDynamic()
    local npcs = dyn and dyn:FindFirstChild("NPCs")
    local npc = npcs and npcs:FindFirstChild("NPC_StarterPort_Broker")
    return npc and npc:FindFirstChild("HumanoidRootPart")
end

-- Fija el punto del tesorero en tu posición actual (párate donde quieras entregar/abrir)
function EX.setBrokerPointHere()
    local root = getRoot()
    if not root then
        setStatus("No encuentro tu personaje")
        return
    end
    EX.brokerPos = root.Position
    EX.brokerMode = "MANUAL"
    markDirty()
    setStatus(string.format("Punto del tesorero fijado (%.0f, %.0f, %.0f)",
        EX.brokerPos.X, EX.brokerPos.Y, EX.brokerPos.Z))
end

function EX.setBrokerMode(newMode)
    if newMode == "MANUAL" and not EX.brokerPos then
        setStatus("Aún no hay punto del tesorero: párate donde quieras y pulsa «Fijar aquí»")
        return
    end
    EX.brokerMode = newMode
    markDirty()
    setStatus(newMode == "MANUAL" and "Tesorero: usará tu punto manual" or "Tesorero: irá al NPC")
end

-- Va al punto actual del tesorero para que veas dónde queda
function EX.goToBrokerPoint()
    local pos
    if EX.brokerMode == "MANUAL" and EX.brokerPos then
        pos = EX.brokerPos
    else
        local hrp = EX.brokerNPC()
        pos = hrp and (hrp.Position + Vector3.new(0, CONFIG.ALTURA, 0))
    end
    if not pos then
        setStatus("No encuentro al tesorero")
        return
    end
    setHover(false)
    teleportTo(pos)
    setStatus("Estás en el punto del tesorero")
end

local function openVault()
    setHover(false)
    local hrp = EX.brokerNPC()
    local manual = EX.brokerMode == "MANUAL" and EX.brokerPos ~= nil

    if not hrp and not manual then
        setStatus("No encuentro al tesorero")
        return
    end

    if manual then
        setStatus("Yendo a tu punto del tesorero...")
        teleportTo(EX.brokerPos)
    else
        setStatus("Yendo al tesorero...")
        teleportTo(hrp.Position + Vector3.new(0, CONFIG.ALTURA, 0))
    end

    local p1 = hrp and hrp:FindFirstChild("NPCPrompt_1")
    local prompt = p1 and p1:FindFirstChild("NPCPrompt")
    if prompt and prompt:IsA("ProximityPrompt") then
        pcall(function()
            prompt.RequiresLineOfSight = false
            if prompt.MaxActivationDistance < 25 then
                prompt.MaxActivationDistance = 25
            end
        end)
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
-- ISLA: ir y quedarse flotando (lo usan cofres y combate)
---------------------------------------------------------------
function CB.prepareIsland(entryOverride)
    local entry = entryOverride or currentIslandEntry()
    local island = getIsland(entry)
    if not island then
        setStatus("No encuentro la isla " .. islandDisplayName(entry))
        return nil
    end
    local root = getRoot()
    if root and not isInsideIsland(island, root.Position) then
        setHover(false)
        setStatus("Yendo a la isla " .. islandDisplayName(entry) .. "...")
        moveTo(islandTop(island))
        hoverHere()
        setStatus("Esperando que carguen los cofres...")
        task.wait(CONFIG.ESPERA_STREAMING)
    elseif root and not hoverActive(root) then
        hoverHere()
    end
    return island
end

---------------------------------------------------------------
-- COMBATE (enemigos en World.Dynamic.Enemies)
--   Enemy_(nombre)    -> enemigos de tierra
--   NPCShip_(nombre)  -> enemigos en barcos
---------------------------------------------------------------
function CB.enemyKind(name)
    if name:sub(1, #CONFIG.PREFIJO_TIERRA) == CONFIG.PREFIJO_TIERRA then
        return "LAND"
    elseif name:sub(1, #CONFIG.PREFIJO_BARCO) == CONFIG.PREFIJO_BARCO then
        return "SHIP"
    end
    return nil
end

function CB.enemyBaseName(name)
    local kind = CB.enemyKind(name)
    if kind == "LAND" then
        return name:sub(#CONFIG.PREFIJO_TIERRA + 1)
    elseif kind == "SHIP" then
        return name:sub(#CONFIG.PREFIJO_BARCO + 1)
    end
    return name
end

function CB.enemyLabel(key)
    if key == CB.ENEMY_ALL then return "Todos" end
    if key == CB.ENEMY_LAND then return "Todos (tierra)" end
    if key == CB.ENEMY_SHIP then return "Todos (barcos)" end
    local kind = CB.enemyKind(key)
    local base = CB.enemyBaseName(key)
    if kind == "LAND" then return "Tierra: " .. base end
    if kind == "SHIP" then return "Barco: " .. base end
    return key
end

function CB.rememberEnemy(name, kind)
    if not CB.enemyMemory[name] then
        CB.enemyMemory[name] = kind
        table.insert(CB.enemyOrder, name)
        table.sort(CB.enemyOrder)
    end
end

-- Enemigos cargados ahora (y los recuerda para el selector)
function CB.listEnemies()
    local result = {}
    local folder = CB.getEnemiesFolder()
    if not folder then return result end

    for _, e in ipairs(folder:GetChildren()) do
        if e:IsA("Model") or e:IsA("BasePart") then
            local kind = CB.enemyKind(e.Name)
            if kind then
                CB.rememberEnemy(e.Name, kind)
                table.insert(result, e)
            end
        end
    end
    return result
end

function CB.buildEnemyOptions()
    CB.listEnemies()
    local opts = { CB.ENEMY_ALL, CB.ENEMY_LAND, CB.ENEMY_SHIP }
    for _, name in ipairs(CB.enemyOrder) do
        table.insert(opts, name)
    end
    return opts
end

function CB.matchesTarget(name)
    local kind = CB.enemyKind(name)
    if not kind then return false end
    if CB.attackTarget == CB.ENEMY_ALL then return true end
    if CB.attackTarget == CB.ENEMY_LAND then return kind == "LAND" end
    if CB.attackTarget == CB.ENEMY_SHIP then return kind == "SHIP" end
    return name == CB.attackTarget
end

function CB.enemyAlive(e)
    if not e or not e.Parent then return false end
    local hum = e:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health <= 0 then return false end
    local hp = e:GetAttribute("Health")
    if type(hp) == "number" and hp <= 0 then return false end
    return true
end

function CB.enemyPos(e)
    return e:GetPivot().Position
end

-- Enemigo válido más cercano (según el objetivo elegido y, si aplica, la isla)
function CB.nextEnemy(island)
    local root = getRoot()
    local myPos = root and root.Position or Vector3.zero
    local now = os.clock()
    local best, bestDist

    for _, e in ipairs(CB.listEnemies()) do
        local expiry = CB.enemyBlacklist[e]
        local blocked = expiry ~= nil and expiry > now
        if not blocked and CB.matchesTarget(e.Name) and CB.enemyAlive(e) then
            local pos = CB.enemyPos(e)
            if (not island) or isInsideIsland(island, pos) then
                local d = (pos - myPos).Magnitude
                if not bestDist or d < bestDist then
                    best, bestDist = e, d
                end
            end
        end
    end
    return best
end

function CB.countEnemies()
    local land, ship = 0, 0
    for _, e in ipairs(CB.listEnemies()) do
        if CB.enemyAlive(e) then
            if CB.enemyKind(e.Name) == "LAND" then
                land += 1
            else
                ship += 1
            end
        end
    end
    return land, ship
end

function CB.getHeldTool()
    local character = LocalPlayer.Character
    return character and character:FindFirstChildOfClass("Tool")
end

-- Usa la tool que tienes en la mano; si no hay y está activado, equipa la primera de la mochila
function CB.ensureTool()
    local tool = CB.getHeldTool()
    if tool then return tool end
    if not CB.autoEquip then return nil end

    local character = LocalPlayer.Character
    local hum = character and character:FindFirstChildOfClass("Humanoid")
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if hum and backpack then
        local t = backpack:FindFirstChildOfClass("Tool")
        if t then
            pcall(function() hum:EquipTool(t) end)
            task.wait(0.25)
            return CB.getHeldTool()
        end
    end
    return nil
end

-- Posición desde la que se golpea al enemigo
function CB.attackCFrameFor(e, kind)
    local pos = CB.enemyPos(e)
    local p
    if kind == "SHIP" then
        p = getShipTop(e) + Vector3.new(0, CB.attackHeight, 0)
    else
        p = pos + Vector3.new(0, CB.attackHeight, CB.attackDist)
    end
    local look = Vector3.new(pos.X, p.Y, pos.Z)
    if (look - p).Magnitude < 0.1 then
        look = p + Vector3.new(0, 0, -1)
    end
    return CFrame.lookAt(p, look)
end

-- Persigue y golpea al enemigo hasta que muera, desaparezca o se acabe el tiempo
function CB.attackEnemy(e)
    local kind = CB.enemyKind(e.Name) or "LAND"
    local t0 = os.clock()
    setHover(true)

    while not closed and CB.attackEnabled and CB.enemyAlive(e) and os.clock() - t0 < CONFIG.ATAQUE_TIMEOUT do
        local tool = CB.ensureTool()
        if not tool then
            setStatus("No tienes ninguna tool en la mano")
            return false, true
        end

        CB.snapToCFrame(CB.attackCFrameFor(e, kind))
        pcall(function() tool:Activate() end)
        task.wait(CONFIG.ESPERA_ATAQUE)
    end

    return not CB.enemyAlive(e), false
end

function CB.combatCycle()
    local folder = CB.getEnemiesFolder()
    if not folder then
        setStatus("No encuentro World.Dynamic.Enemies")
        return
    end

    local island
    if CB.attackByIsland then
        island = CB.prepareIsland()
        if not island then return end
    end

    local kills = 0
    while CB.attackEnabled and not closed and kills < CONFIG.MAX_ENEMIGOS_POR_CICLO do
        local enemy = CB.nextEnemy(island)
        if not enemy then break end

        setStatus("Atacando " .. CB.enemyLabel(enemy.Name))
        local dead, noTool = CB.attackEnemy(enemy)
        if noTool then return end

        if dead then
            kills += 1
            CB.killedCount += 1
        else
            CB.enemyBlacklist[enemy] = os.clock() + CONFIG.ENEMIGO_BLOQUEO
        end
    end

    if CB.attackEnabled and kills == 0 then
        if CB.attackByIsland then
            setStatus("Sin enemigos (" .. CB.enemyLabel(CB.attackTarget) .. ") en " .. currentIslandName())
        else
            setStatus("Sin enemigos (" .. CB.enemyLabel(CB.attackTarget) .. ")")
        end
    end
end

---------------------------------------------------------------
-- CICLO
---------------------------------------------------------------
local function collectCycle(entryOverride)
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
    local cap = EX.capFor(dest)

    if usedSpaceOn(dest) >= cap then
        if destIsMine then
            openVault()
        else
            setStatus("El barco de " .. targetLabel .. " está lleno")
        end
        return
    end

    local island
    local useIsland = islandMode or entryOverride ~= nil
    local islandLabel = islandDisplayName(entryOverride or currentIslandEntry())
    if useIsland then
        island = CB.prepareIsland(entryOverride)
        if not island then return end
    end

    local seen, inside, passed = 0, 0, 0

    for _, item in ipairs(treasure:GetChildren()) do
        if closed or not auto then return end

        local base = item:FindFirstChild("Base")
        local attach = base and base:FindFirstChild("PromptAttachment")
        local prompt = attach and attach:FindFirstChild("TreasurePrompt")

        local inIsland = (not island) or (base ~= nil and isInsideIsland(island, base.Position))
        seen = seen + 1
        if base and inIsland then inside = inside + 1 end

        if base and prompt and prompt:IsA("ProximityPrompt")
            and inIsland
            and passesOwnerFilter(item)
            and passesValueRarity(item) then

            -- Si el barco de otro jugador se descargó, vuelve a cargarlo
            if not dest.Parent then
                dest = getDestinationShip()
                if not dest then return end
                cap = EX.capFor(dest)
            end

            passed = passed + 1
            local size = getCargoSize(item)

            if size > cap then
                setStatus("Cofre más grande que la bóveda, lo salto")
            else
                if usedSpaceOn(dest) + size > cap then
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
                pickUpChest(base, prompt, useIsland and CONFIG.ALTURA_ISLA or nil, useIsland)
                collectedCount += 1

                setHover(false)
                if storeOnBoat(usedBefore, dest) then
                    waitOnShip()
                end

                if returnToSpot and returnCF then
                    setStatus("Volviendo a tu posición...")
                    teleportToCFrame(returnCF)
                    if useIsland then hoverHere() end
                end
            end
        end
    end

    if auto then
        if useIsland then
            setStatus(string.format("%s: %d cofres en el mapa, %d en la isla, %d válidos con tus filtros",
                islandLabel, seen, inside, passed))
        else
            setStatus("Buscando cofres...")
        end
    end
end

-- Recorre TODAS las islas del mar elegido: va a cada una, recoge los cofres que pasen
-- tus filtros (rareza, valor, dueño) y sigue con la siguiente. Al terminar, el ciclo principal repite.
function EX.sweepCycle()
    local group = ISLAND_GROUPS[diffIndex]
    for i, entry in ipairs(group.islas) do
        if closed or not auto then return end
        setStatus(string.format("Recorriendo %s: isla %d/%d (%s)",
            seaDisplayName(group), i, #group.islas, islandDisplayName(entry)))
        collectCycle(entry)
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

-- Arrastrable. onEnd se llama al soltar (solo si se movió) para guardar la posición.
-- Devuelve una tabla con "moved" para distinguir un arrastre de un simple toque.
local function makeDraggable(handle, frame, onEnd)
    local dragging, startInput, startPos = false, nil, nil
    local state = { moved = false }
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            state.moved = false
            startInput = input.Position
            startPos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if state.moved and onEnd then
                        onEnd()
                    end
                end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseMovement) then
            local d = input.Position - startInput
            if not state.moved and d.Magnitude >= CONFIG.ARRASTRE_MIN then
                state.moved = true
            end
            if state.moved then
                frame.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + d.X,
                    startPos.Y.Scale, startPos.Y.Offset + d.Y
                )
            end
        end
    end)
    return state
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

local tabNames = { "Cofres", "Isla", "Bóveda", "Filtros", "Combate", "Panel" }
local tabButtons = {}
for i, name in ipairs(tabNames) do
    local b = button(tabRow, name, UDim2.new(1 / #tabNames, -3, 1, 0), PALETTE.card)
    b.TextSize = 10
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
CB.pageCombate = newPage()
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

-- Punto de entrega: automático (centro del barco) o manual (el que fijes)
EX.dropRow = Instance.new("Frame")
EX.dropRow.Size = UDim2.new(1, -4, 0, 32)
EX.dropRow.BackgroundTransparency = 1
EX.dropRow.LayoutOrder = 8
EX.dropRow.Parent = pageCofres
listLayout(EX.dropRow, 6, true)

EX.autoPointBtn = button(EX.dropRow, "🎯 Auto (centro)", UDim2.new(0.5, -3, 1, 0), PALETTE.card)
EX.manualPointBtn = button(EX.dropRow, "📍 Punto manual", UDim2.new(0.5, -3, 1, 0), PALETTE.card)

EX.pointRow = Instance.new("Frame")
EX.pointRow.Size = UDim2.new(1, -4, 0, 32)
EX.pointRow.BackgroundTransparency = 1
EX.pointRow.LayoutOrder = 9
EX.pointRow.Parent = pageCofres
listLayout(EX.pointRow, 6, true)

EX.setPointBtn = button(EX.pointRow, "📌 Fijar aquí", UDim2.new(0.5, -3, 1, 0), PALETTE.track)
EX.goPointBtn = button(EX.pointRow, "🚶 Ir al punto", UDim2.new(0.5, -3, 1, 0), PALETTE.track)

EX.dropNote = label(pageCofres, "", 10, PALETTE.muted, false)
EX.dropNote.LayoutOrder = 10
EX.dropNote.Size = UDim2.new(1, -4, 0, 58)
EX.dropNote.TextWrapped = true
EX.dropNote.TextYAlignment = Enum.TextYAlignment.Top

EX.autoPointBtn.Activated:Connect(function()
    EX.setDropMode("AUTO")
end)
EX.manualPointBtn.Activated:Connect(function()
    EX.setDropMode("MANUAL")
end)
EX.setPointBtn.Activated:Connect(function()
    EX.setPointHere()
end)
EX.goPointBtn.Activated:Connect(function()
    EX.goToPoint()
end)

---------------------------------------------------------------
-- PESTAÑA ISLA (mares)
---------------------------------------------------------------
checkRow(pageIsla, "Recolectar por isla", 1, islandMode, function(v)
    islandMode = v
    markDirty()
    setStatus(v and ("Modo isla: " .. currentIslandName()) or "Modo isla apagado")
end)

-- Opción para ver los nombres de mares e islas en inglés (por defecto: español)
checkRow(pageIsla, "Nombres en inglés (English)", 2, englishNames, function(v)
    englishNames = v
    markDirty()
    setStatus(v and "Nombres de islas en inglés" or "Nombres de islas en español")
end)

checkRow(pageIsla, "Recorrer TODAS las islas del mar", 3, EX.sweepMode, function(v)
    EX.sweepMode = v
    markDirty()
    setStatus(v and ("Recorrerá todas las islas de " .. seaDisplayName(ISLAND_GROUPS[diffIndex]))
        or "Recorrido de islas apagado")
end)

local diffRow = arrowRow(pageIsla, 4,
    function()
        return seaDisplayName(ISLAND_GROUPS[diffIndex]) .. " (" .. diffIndex .. "/" .. #ISLAND_GROUPS .. ")"
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

local islandRow = arrowRow(pageIsla, 5,
    function()
        local group = ISLAND_GROUPS[diffIndex]
        return islandDisplayName(group.islas[islandIndex]) .. " (" .. islandIndex .. "/" .. #group.islas .. ")"
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
islandNote.LayoutOrder = 6
islandNote.Size = UDim2.new(1, -4, 0, 58)
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

local vaultInfo = label(pageBoveda, "", 10, PALETTE.muted, false)
vaultInfo.LayoutOrder = 2
vaultInfo.Size = UDim2.new(1, -4, 0, 62)
vaultInfo.TextWrapped = true
vaultInfo.TextYAlignment = Enum.TextYAlignment.Top

local emptyBtn = button(pageBoveda, "🏦 Vaciar bóveda ahora", UDim2.new(1, -4, 0, 36), PALETTE.accent)
emptyBtn.LayoutOrder = 3
emptyBtn.Activated:Connect(function()
    manualOpenRequested = true
    setStatus("Se vaciará la bóveda en el próximo ciclo")
end)

-- Punto del tesorero: automático (NPC) o manual (el que fijes)
EX.brokerRow = Instance.new("Frame")
EX.brokerRow.Size = UDim2.new(1, -4, 0, 32)
EX.brokerRow.BackgroundTransparency = 1
EX.brokerRow.LayoutOrder = 4
EX.brokerRow.Parent = pageBoveda
listLayout(EX.brokerRow, 6, true)

EX.brokerAutoBtn = button(EX.brokerRow, "🧑‍💼 Auto (NPC)", UDim2.new(0.5, -3, 1, 0), PALETTE.card)
EX.brokerManualBtn = button(EX.brokerRow, "📍 Punto manual", UDim2.new(0.5, -3, 1, 0), PALETTE.card)

EX.brokerPointRow = Instance.new("Frame")
EX.brokerPointRow.Size = UDim2.new(1, -4, 0, 32)
EX.brokerPointRow.BackgroundTransparency = 1
EX.brokerPointRow.LayoutOrder = 5
EX.brokerPointRow.Parent = pageBoveda
listLayout(EX.brokerPointRow, 6, true)

EX.brokerSetBtn = button(EX.brokerPointRow, "📌 Fijar aquí", UDim2.new(0.5, -3, 1, 0), PALETTE.track)
EX.brokerGoBtn = button(EX.brokerPointRow, "🚶 Ir al punto", UDim2.new(0.5, -3, 1, 0), PALETTE.track)

EX.brokerNote = label(pageBoveda, "", 10, PALETTE.muted, false)
EX.brokerNote.LayoutOrder = 6
EX.brokerNote.Size = UDim2.new(1, -4, 0, 58)
EX.brokerNote.TextWrapped = true
EX.brokerNote.TextYAlignment = Enum.TextYAlignment.Top

EX.brokerAutoBtn.Activated:Connect(function()
    EX.setBrokerMode("AUTO")
end)
EX.brokerManualBtn.Activated:Connect(function()
    EX.setBrokerMode("MANUAL")
end)
EX.brokerSetBtn.Activated:Connect(function()
    EX.setBrokerPointHere()
end)
EX.brokerGoBtn.Activated:Connect(function()
    EX.goToBrokerPoint()
end)

-- Validación de tamaños
EX.counterCheck = checkRow(pageBoveda, "Usar contador del juego si existe", 7, EX.useGameCounter, function(v)
    EX.useGameCounter = v
    markDirty()
    setStatus(v and "Usará el contador de espacio del juego si el barco lo tiene" or "Contará los cofres uno por uno")
end)

EX.diagBtn = button(pageBoveda, "🔍 Diagnóstico de bóveda (consola)", UDim2.new(1, -4, 0, 36), PALETTE.card)
EX.diagBtn.LayoutOrder = 8
EX.diagBtn.Activated:Connect(function()
    EX.diagnose()
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
    setStatus(v and ("Solo cofres " .. CONFIG.RAREZAS[rarityMinIdx] .. " o superiores") or "Filtro de rareza apagado")
end)

local rarityRow = arrowRow(pageFiltros, 4,
    function()
        return "Rareza ≥ " .. CONFIG.RAREZAS[rarityMinIdx] .. " (" .. rarityMinIdx .. "/" .. #CONFIG.RAREZAS .. ")"
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
-- PESTAÑA COMBATE
---------------------------------------------------------------
checkRow(CB.pageCombate, "Ataque automático", 1, CB.attackEnabled, function(v)
    CB.attackEnabled = v
    setStatus(v and "Buscando enemigos..." or "Ataque apagado")
end)

checkRow(CB.pageCombate, "Solo enemigos de la isla elegida", 2, CB.attackByIsland, function(v)
    CB.attackByIsland = v
    markDirty()
    setStatus(v and ("Atacará solo en: " .. currentIslandName()) or "Atacará enemigos en todo el mapa")
end)

checkRow(CB.pageCombate, "Equipar tool si no tengo en mano", 3, CB.autoEquip, function(v)
    CB.autoEquip = v
    markDirty()
    setStatus(v and "Equipará una tool de la mochila si hace falta" or "Solo usará la tool que tengas en la mano")
end)

function CB.cycleEnemyTarget(step)
    local opts = CB.buildEnemyOptions()
    local idx = 1
    for i, v in ipairs(opts) do
        if v == CB.attackTarget then
            idx = i
            break
        end
    end
    idx = idx + step
    if idx < 1 then idx = #opts end
    if idx > #opts then idx = 1 end
    CB.attackTarget = opts[idx]
    markDirty()

    if #opts == 3 then
        setStatus("Aún no he visto enemigos: acércate a ellos para que aparezcan en la lista")
    else
        setStatus("Objetivo: " .. CB.enemyLabel(CB.attackTarget))
    end
end

CB.enemyRow = arrowRow(CB.pageCombate, 4,
    function() return "Objetivo: " .. CB.enemyLabel(CB.attackTarget) end,
    function() CB.cycleEnemyTarget(-1) end,
    function() CB.cycleEnemyTarget(1) end
)

CB.distStepper = stepperRow(CB.pageCombate, 5,
    function() return "Distancia: " .. CB.attackDist .. " studs" end,
    function()
        CB.attackDist = math.max(0, CB.attackDist - 1)
        markDirty()
        refreshUI()
    end,
    function()
        CB.attackDist = math.min(CONFIG.ATAQUE_DISTANCIA_MAX, CB.attackDist + 1)
        markDirty()
        refreshUI()
    end
)

CB.heightStepper = stepperRow(CB.pageCombate, 6,
    function() return "Altura: " .. CB.attackHeight .. " studs" end,
    function()
        CB.attackHeight = math.max(CONFIG.ATAQUE_ALTURA_MIN, CB.attackHeight - 1)
        markDirty()
        refreshUI()
    end,
    function()
        CB.attackHeight = math.min(CONFIG.ATAQUE_ALTURA_MAX, CB.attackHeight + 1)
        markDirty()
        refreshUI()
    end
)

CB.combatNote = label(CB.pageCombate, "", 10, PALETTE.muted, false)
CB.combatNote.LayoutOrder = 7
CB.combatNote.Size = UDim2.new(1, -4, 0, 70)
CB.combatNote.TextWrapped = true
CB.combatNote.TextYAlignment = Enum.TextYAlignment.Top

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

-- Vuelve a poner el panel y la burbuja en su sitio de fábrica
EX.resetPosBtn = button(pagePanel, "⌖ Centrar panel y burbuja", UDim2.new(1, -4, 0, 36), PALETTE.card)
EX.resetPosBtn.LayoutOrder = 5

local panelNote = label(pagePanel,
    "Escribe el ancho y el alto en la caja, o usa − y +. El tamaño y la posición del panel y de la burbuja se guardan solos.",
    10, PALETTE.muted, false)
panelNote.LayoutOrder = 6
panelNote.Size = UDim2.new(1, -4, 0, 52)
panelNote.TextWrapped = true
panelNote.TextYAlignment = Enum.TextYAlignment.Top

local mini = button(gui, "🏴‍☠️", UDim2.fromOffset(CONFIG.BURBUJA_TAMANO, CONFIG.BURBUJA_TAMANO), PALETTE.card)
mini.TextSize = 20
mini.Visible = false
stroke(mini, PALETTE.accent, 1, 0.3)

-- Coloca el panel y la burbuja donde los dejaste (ajustado a la pantalla actual)
function EX.applySavedPositions()
    local vp = camera.ViewportSize
    if vp.X < 100 or vp.Y < 100 then return end

    if EX.mainPos then
        local hx, hy = vp.X / 2 - 30, vp.Y / 2 - 30
        main.Position = UDim2.new(
            EX.mainPos[1], math.clamp(EX.mainPos[2], -hx, hx),
            EX.mainPos[3], math.clamp(EX.mainPos[4], -hy, hy)
        )
    end

    if EX.miniPos then
        local size = CONFIG.BURBUJA_TAMANO
        mini.Position = UDim2.fromOffset(
            math.clamp(EX.miniPos[1], 0, math.max(vp.X - size, 0)),
            math.clamp(EX.miniPos[2], 0, math.max(vp.Y - size, 0))
        )
    end
end

-- Arrastrar el panel por la cabecera y la burbuja por sí misma; al soltar se guarda la posición
makeDraggable(header, main, function()
    local p = main.Position
    EX.mainPos = { p.X.Scale, p.X.Offset, p.Y.Scale, p.Y.Offset }
    markDirty()
end)

EX.miniDrag = makeDraggable(mini, mini, function()
    local p = mini.Position
    EX.miniPos = { p.X.Offset, p.Y.Offset }
    markDirty()
end)

EX.resetPosBtn.Activated:Connect(function()
    EX.mainPos = nil
    EX.miniPos = nil
    main.Position = UDim2.new(0.5, 0, 0.5, 0)
    mini.Position = UDim2.fromOffset(0, 0)
    markDirty()
    setStatus("Panel y burbuja centrados")
end)

applyPanelSize()
EX.applySavedPositions()

---------------------------------------------------------------
-- ACTUALIZAR UI
---------------------------------------------------------------
refreshUI = function()
    local myShip = getMyShip()
    local counted, unreadable, chestCount = EX.countedSpaceOn(myShip)
    local gameUsed, gameCap = EX.gameCargo(myShip)
    local used = usedSpaceOn(myShip)
    local cap = EX.capFor(myShip)

    subtitle.Text = statusText
    countLabel.Text = tostring(collectedCount)
    vaultLabel.Text = used .. "/" .. cap
    barFill.Size = UDim2.new(math.clamp(used / math.max(cap, 1), 0, 1), 0, 1, 0)

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

    -- Punto de entrega
    local manualOn = EX.dropMode == "MANUAL" and EX.dropOffset ~= nil
    EX.autoPointBtn.BackgroundColor3 = manualOn and PALETTE.card or PALETTE.accent
    EX.manualPointBtn.BackgroundColor3 = manualOn and PALETTE.accent or PALETTE.card
    if EX.dropOffset then
        EX.dropNote.Text = string.format("Punto manual: %.1f, %.1f, %.1f (relativo al barco). %s",
            EX.dropOffset.X, EX.dropOffset.Y, EX.dropOffset.Z,
            manualOn and "Activo: los cofres se dejan en ese punto."
                or "Inactivo: los cofres se dejan en el centro del barco.")
            .. "\nPara cambiarlo, párate en el barco destino y pulsa «Fijar aquí»."
    else
        EX.dropNote.Text = "Sin punto manual: los cofres se dejan en el centro del barco."
            .. "\nPárate en el lugar del barco que quieras y pulsa «Fijar aquí»."
    end

    waitStepper.refresh()
    diffRow.refresh()
    islandRow.refresh()
    if EX.sweepMode then
        islandNote.Text = "Recorrerá las " .. #ISLAND_GROUPS[diffIndex].islas .. " islas de "
            .. seaDisplayName(ISLAND_GROUPS[diffIndex]) .. " una por una y recogerá los cofres que pasen tus filtros (pestaña Filtros). Tiene prioridad sobre «Recolectar por isla»."
    elseif islandMode then
        islandNote.Text = "Irá a " .. currentIslandName() .. " (" .. seaDisplayName(ISLAND_GROUPS[diffIndex]) .. ") y solo recogerá cofres dentro de esa isla."
    else
        islandNote.Text = "Activa «Recolectar por isla» (una isla) o «Recorrer TODAS las islas» (todo el mar elegido)."
    end

    capStepper.refresh()

    -- Bóveda: lo contado cofre por cofre frente al contador del juego (si existe)
    local info = "Cofres en tu barco: " .. chestCount .. " · espacio contado: " .. counted
    if gameUsed then
        info = info .. "\nContador del juego: " .. gameUsed .. (gameCap and ("/" .. gameCap) or "")
            .. (EX.useGameCounter and " (en uso)" or " (sin usar)")
        if gameUsed ~= counted then
            info = info .. "\n⚠ No coincide con lo contado."
        end
    else
        info = info .. "\nEl barco no expone contador propio: se usa lo contado."
    end
    if unreadable > 0 then
        info = info .. "\n⚠ " .. unreadable .. " cofre(s) sin tamaño legible (cuentan como "
            .. CONFIG.TAMANO_POR_DEFECTO .. ")."
    end
    vaultInfo.Text = info
    EX.counterCheck.refresh()

    -- Punto del tesorero
    local brokerManualOn = EX.brokerMode == "MANUAL" and EX.brokerPos ~= nil
    EX.brokerAutoBtn.BackgroundColor3 = brokerManualOn and PALETTE.card or PALETTE.accent
    EX.brokerManualBtn.BackgroundColor3 = brokerManualOn and PALETTE.accent or PALETTE.card
    if EX.brokerPos then
        EX.brokerNote.Text = string.format("Punto del tesorero: %.0f, %.0f, %.0f. %s",
            EX.brokerPos.X, EX.brokerPos.Y, EX.brokerPos.Z,
            brokerManualOn and "Activo: al vaciar la bóveda irá a ese punto."
                or "Inactivo: al vaciar la bóveda irá al NPC tesorero.")
            .. "\nPara cambiarlo, párate donde quieras y pulsa «Fijar aquí»."
    else
        EX.brokerNote.Text = "Sin punto manual: al vaciar la bóveda irá al NPC tesorero."
            .. "\nPárate junto al tesorero (o donde funcione) y pulsa «Fijar aquí»."
    end

    valueRow.refresh()
    rarityRow.refresh()
    filterNote.Text = "Valor: recoge cofres con Value ≥ " .. valueMin
        .. (valueFilter and " (activo)" or " (apagado)")
        .. ". Rareza: " .. CONFIG.RAREZAS[rarityMinIdx] .. " y todas las superiores"
        .. (rarityFilter and " (activo)" or " (apagado)") .. "."

    -- Combate
    CB.enemyRow.refresh()
    CB.distStepper.refresh()
    CB.heightStepper.refresh()
    local land, ship = CB.countEnemies()
    local tool = CB.getHeldTool()
    CB.combatNote.Text = "Enemigos cargados: " .. land .. " de tierra, " .. ship .. " en barcos."
        .. "\nEliminados: " .. CB.killedCount
        .. "\nTool en mano: " .. (tool and tool.Name or "ninguna")
        .. (CB.attackByIsland and ("\nIsla: " .. currentIslandName()) or "\nIsla: todo el mapa")

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
    -- Si ya dejaste la burbuja en un sitio, se queda ahí. Si no, aparece donde estaba el panel.
    if not EX.miniPos then
        mini.Position = UDim2.fromOffset(main.AbsolutePosition.X, main.AbsolutePosition.Y)
    end
    mini.Visible = true
end)

mini.Activated:Connect(function()
    -- Si fue un arrastre (moviste la burbuja), no abre el panel
    if EX.miniDrag and EX.miniDrag.moved then
        return
    end
    mini.Visible = false
    main.Visible = true
end)

closeBtn.Activated:Connect(function()
    closed = true
    auto = false
    CB.attackEnabled = false
    setHover(false)
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
        elseif CB.attackEnabled or auto then
            -- Primero combate (si está activo) y luego recolección de cofres
            if CB.attackEnabled then
                local ok, err = pcall(CB.combatCycle)
                if not ok then
                    setHover(false)
                    setStatus("Error de combate: " .. tostring(err))
                end
            end
            if auto and not closed then
                local ok, err = pcall(EX.sweepMode and EX.sweepCycle or collectCycle)
                if not ok then
                    setHover(false)
                    setStatus("Error: " .. tostring(err))
                end
            end
        end
        if not auto and not CB.attackEnabled and hovering then
            setHover(false)
        end
        refreshUI()
        task.wait(1)
    end
end)

refreshUI()
