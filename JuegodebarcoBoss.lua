-- Caza de bosses (TP): HE IRON TYRANT y Celestial Serpent
-- Detección de muerte por varias señales + botín por fuerza bruta
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

local CONFIG = {
    DISTANCIA = 4,
    ALTURA_MIN = -20,
    ALTURA_MAX = 40,
    LADO_MIN = -30,
    LADO_MAX = 30,
    PASO = 1,
    ARCHIVO = "BossConfig.json",
    ESPERA_STREAMING = 2,
    ESPERA_CARGA_BOSS = 20,
    ESPERA_ATAQUE = 0.15,
    ESPERA_RESPAWN = 3,
    ESPERA_INICIAL_BOTIN = 8,
    ESPERA_BARCO = 3,
    ALTURA_BOTIN = 3,
    ALTURA_BARCO = 0,
    INTENTOS_PROMPT = 5,
    MAX_INTENTOS_BOTIN = 5,
    DEBUG = true,
}

local BOSSES = {
    {
        nombre = "HE IRON TYRANT",
        mar = "Ironbound",
        isla = "TheAnvil",
        ruta = { "World", "Dynamic", "Bosses", "Boss_IronTyrant" },
        parte = "captain",
    },
    {
        nombre = "Celestial Serpent",
        mar = "Celestial",
        isla = "AuroraRift",
        ruta = { "World", "Dynamic", "Bosses", "Boss_CelestialSerpent" },
        parte = "Head.Body",
    },
}

local bossIndex = 1
local cazando = false
local closed = false
local kills = 0
local botinRecogido = 0
local statusText = "Listo"
local cachedShip = nil

---------------------------------------------------------------
-- AJUSTES (altura y lado por boss, botón de botín) guardados en archivo
---------------------------------------------------------------
local ajustes = {}
pcall(function()
    if readfile and isfile and isfile(CONFIG.ARCHIVO) then
        local d = HttpService:JSONDecode(readfile(CONFIG.ARCHIVO))
        if type(d) == "table" then ajustes = d end
    end
end)

local function ajusteDe(b)
    if not ajustes[b.nombre] then
        ajustes[b.nombre] = { altura = 0, lado = 0 }
    end
    return ajustes[b.nombre]
end

local function botinActivo()
    return ajustes._botin ~= false
end

local function guardarAjustes()
    if not writefile then return end
    pcall(function()
        writefile(CONFIG.ARCHIVO, HttpService:JSONEncode(ajustes))
    end)
end

---------------------------------------------------------------
-- UTILIDADES
---------------------------------------------------------------
local function setStatus(text)
    statusText = text
    if CONFIG.DEBUG then print("[BOSS]", text) end
end

local function getRoot()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getPath(parts)
    local obj = Workspace
    for _, name in ipairs(parts) do
        obj = obj and obj:FindFirstChild(name)
    end
    return obj
end

local function posOf(obj)
    if obj:IsA("Model") then return obj:GetPivot().Position end
    if obj:IsA("BasePart") then return obj.Position end
    for _, d in ipairs(obj:GetDescendants()) do
        if d:IsA("BasePart") then return d.Position end
    end
    return nil
end

local function tpTo(cf)
    local root = getRoot()
    if not root then return end
    root.AssemblyLinearVelocity = Vector3.zero
    root.CFrame = cf
    task.wait(0.2)
end

---------------------------------------------------------------
-- SEGUIMIENTO (se conecta y desconecta)
---------------------------------------------------------------
local followConn = nil
local followCF = nil

function startFollow()
    if followConn then return end
    followConn = RunService.Heartbeat:Connect(function()
        if not followCF then return end
        local root = getRoot()
        if root then
            root.AssemblyLinearVelocity = Vector3.zero
            root.CFrame = followCF
        end
    end)
end

function stopFollow()
    followCF = nil
    if followConn then
        followConn:Disconnect()
        followConn = nil
    end
end

local HOVER = "BossHover"
local function setHover(on)
    local root = getRoot()
    if not root then return end
    local old = root:FindFirstChild(HOVER)
    if on and not old then
        local bv = Instance.new("BodyVelocity")
        bv.Name = HOVER
        bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
        bv.Velocity = Vector3.zero
        bv.Parent = root
    elseif not on and old then
        old:Destroy()
    end
end

local function herramienta()
    local char = LocalPlayer.Character
    if not char then return nil end
    local t = char:FindFirstChildOfClass("Tool")
    if t then return t end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local mochila = LocalPlayer:FindFirstChildOfClass("Backpack")
    local nueva = mochila and mochila:FindFirstChildOfClass("Tool")
    if hum and nueva then
        pcall(function() hum:EquipTool(nueva) end)
        task.wait(0.25)
        return char:FindFirstChildOfClass("Tool")
    end
    return nil
end

local function fmt(v)
    return string.format("%.0f,%.0f,%.0f", v.X, v.Y, v.Z)
end

---------------------------------------------------------------
-- ISLAS
---------------------------------------------------------------
local islaCache = {}
local function getIsla(nombre)
    local c = islaCache[nombre]
    if c and c.Parent then return c end
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if (obj:IsA("Model") or obj:IsA("BasePart")) and obj.Name == nombre then
            islaCache[nombre] = obj
            return obj
        end
    end
    return nil
end

local function islandTop(island)
    if island:IsA("Model") then
        local cf, size = island:GetBoundingBox()
        return cf.Position + Vector3.new(0, size.Y / 2 + 5, 0)
    end
    return island.Position + Vector3.new(0, island.Size.Y / 2 + 5, 0)
end

---------------------------------------------------------------
-- BOSS
---------------------------------------------------------------
local function posicionBoss(b)
    local boss = getPath(b.ruta)
    if not boss then return nil, nil end

    local suma, n = Vector3.zero, 0
    local carpeta = boss:FindFirstChild(b.parte)
    if carpeta then
        if carpeta:IsA("BasePart") or carpeta:IsA("Model") then
            suma += posOf(carpeta)
            n += 1
        else
            for _, d in ipairs(carpeta:GetDescendants()) do
                if d:IsA("BasePart") then
                    suma += d.Position
                    n += 1
                end
            end
        end
    end

    if n == 0 then return boss:GetPivot().Position, boss end
    return suma / n, boss
end

---------------------------------------------------------------
-- BARCO
---------------------------------------------------------------
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

    local ships = getPath({ "World", "Dynamic", "Ships" })
    if not ships then return nil end

    for _, child in ipairs(ships:GetChildren()) do
        local candidates = {}
        if child:IsA("Model") or child:IsA("BasePart") then
            table.insert(candidates, child)
        elseif child:IsA("Folder") then
            for _, d in ipairs(child:GetChildren()) do
                if d:IsA("Model") or d:IsA("BasePart") then
                    table.insert(candidates, d)
                end
            end
        end
        for _, c in ipairs(candidates) do
            if isMyShip(c) then
                cachedShip = c
                return c
            end
        end
    end
    return nil
end

local function getShipTop(barco)
    local center, size
    if barco:IsA("Model") then
        center, size = barco:GetBoundingBox()
    else
        center, size = barco.CFrame, barco.Size
    end
    return Vector3.new(center.Position.X, center.Position.Y + size.Y / 2 + CONFIG.ALTURA_BARCO, center.Position.Z)
end

---------------------------------------------------------------
-- BOTÍN
-- Loot > Treasure_xxx > Base > PromptAttachment > TreasurePrompt
---------------------------------------------------------------
local function findPrompt(item)
    local base = item:FindFirstChild("Base")
    local att = base and base:FindFirstChild("PromptAttachment")
    local p = att and att:FindFirstChild("TreasurePrompt")
    if p and p:IsA("ProximityPrompt") then return p end
    for _, d in ipairs(item:GetDescendants()) do
        if d:IsA("ProximityPrompt") then return d end
    end
    return nil
end

local function listaBotin(loot)
    local lista = {}
    for _, c in ipairs(loot:GetChildren()) do
        if findPrompt(c) then table.insert(lista, c) end
    end
    return lista
end

local function recogerBotin()
    local loot = getPath({ "World", "Dynamic", "Loot" })
    if not loot then
        setStatus("No encuentro World.Dynamic.Loot")
        return
    end

    local barco = getMyShip()
    if not barco then
        setStatus("No encuentro tu barco")
        return
    end

    setHover(false)
    task.wait(CONFIG.ESPERA_INICIAL_BOTIN)

    local intentosPorItem = {}
    local recogidos = 0
    local vacios = 0

    while not closed and cazando do
        local item, prompt
        for _, c in ipairs(loot:GetChildren()) do
            local p = findPrompt(c)
            if p and (intentosPorItem[c] or 0) < CONFIG.MAX_INTENTOS_BOTIN then
                item, prompt = c, p
                break
            end
        end

        if not item then
            vacios += 1
            if vacios >= 10 then break end
            task.wait(1)
        else
            vacios = 0
            intentosPorItem[item] = (intentosPorItem[item] or 0) + 1
            setStatus("Botín: " .. item.Name .. " (" .. intentosPorItem[item] .. ")")

            local att = prompt.Parent
            local pos = (att and att:IsA("Attachment")) and att.WorldPosition or posOf(item)
            if pos then
                tpTo(CFrame.new(pos + Vector3.new(0, CONFIG.ALTURA_BOTIN, 0)))
                pcall(function()
                    prompt.RequiresLineOfSight = false
                    prompt.MaxActivationDistance = math.max(prompt.MaxActivationDistance, 25)
                end)
                task.wait(0.3)
                for _ = 1, CONFIG.INTENTOS_PROMPT do
                    pcall(fireproximityprompt, prompt)
                    task.wait(0.2)
                end
            end

            tpTo(CFrame.new(getShipTop(barco)))
            task.wait(CONFIG.ESPERA_BARCO)

            if not prompt:IsDescendantOf(Workspace) or not findPrompt(item) then
                recogidos += 1
                botinRecogido += 1
            end
        end
    end

    setHover(true)
    setStatus("Botín procesado: " .. recogidos)
end

---------------------------------------------------------------
-- DETECCIÓN DE MUERTE (varias señales; devuelve el motivo o nil)
---------------------------------------------------------------
local function motivoMuerte(b, ref, lootAntes, teniaParte)
    if not ref or not ref.Parent then
        return "el boss desapareció del Workspace"
    end

    local hum = ref:FindFirstChildWhichIsA("Humanoid", true)
    if hum and hum.Health <= 0 then
        return "Humanoid.Health = 0"
    end

    for _, attr in ipairs({ "Health", "HP", "Hp" }) do
        local v = ref:GetAttribute(attr)
        if type(v) == "number" and v <= 0 then
            return "atributo " .. attr .. " = 0"
        end
    end

    for _, attr in ipairs({ "Dead", "IsDead", "Died" }) do
        if ref:GetAttribute(attr) == true then
            return "atributo " .. attr
        end
    end

    if teniaParte and not ref:FindFirstChild(b.parte) then
        return "la carpeta " .. b.parte .. " ya no existe"
    end

    local loot = getPath({ "World", "Dynamic", "Loot" })
    if loot and #listaBotin(loot) > lootAntes then
        return "apareció botín nuevo en Loot"
    end

    return nil
end

---------------------------------------------------------------
-- CAZA
---------------------------------------------------------------
local function cazar(b)
    -- 1) TP a la isla
    setStatus("TP a " .. b.isla .. " (" .. b.mar .. ")...")
    local isla = getIsla(b.isla)
    if not isla then
        setStatus("No encuentro la isla " .. b.isla)
        cazando = false
        return
    end
    tpTo(CFrame.new(posOf(isla) + Vector3.new(0, 10, 0)))
    setHover(true)
    task.wait(CONFIG.ESPERA_STREAMING)

    -- 2) Esperar al boss vivo
    local ref
    local t0 = os.clock()
    while not closed and cazando and os.clock() - t0 < CONFIG.ESPERA_CARGA_BOSS do
        local p, bo = posicionBoss(b)
        if p and bo and not motivoMuerte(b, bo, math.huge, false) then
            ref = bo
            break
        end
        setStatus("Esperando a " .. b.nombre .. "...")
        task.wait(0.5)
    end
    if not ref then
        setStatus(b.nombre .. " no apareció en la ruta")
        task.wait(2)
        return
    end

    -- 3) Atacar y vigilar la muerte
    local lootRef = getPath({ "World", "Dynamic", "Loot" })
    local lootAntes = lootRef and #listaBotin(lootRef) or 0
    local teniaParte = ref:FindFirstChild(b.parte) ~= nil
    local motivo = nil

    startFollow()
    while not closed and cazando do
        local p, bo = posicionBoss(b)
        if bo then ref = bo end

        motivo = motivoMuerte(b, ref, lootAntes, teniaParte)
        if motivo then break end
        if not p then
            motivo = "no encuentro la ruta del boss"
            break
        end

        local a = ajusteDe(b)
        followCF = CFrame.lookAt(
            p + Vector3.new(a.lado, a.altura, CONFIG.DISTANCIA),
            p
        )

        local tool = herramienta()
        if not tool then
            setStatus("No tienes ninguna tool en la mano")
            cazando = false
            break
        end

        pcall(function() tool:Activate() end)
        setStatus("Atacando " .. b.nombre .. " (" .. fmt(p) .. ")")
        task.wait(CONFIG.ESPERA_ATAQUE)
    end

    -- 4) Soltar al personaje del boss
    stopFollow()

    if motivo and cazando and not closed then
        kills += 1
        setStatus(b.nombre .. " derrotado (" .. motivo .. ")")
        print("[BOSS] " .. b.nombre .. " derrotado. Motivo: " .. motivo)

        local isla2 = getIsla(b.isla)
        if isla2 then
            tpTo(CFrame.new(islandTop(isla2) + Vector3.new(0, 10, 0)))
        end

        if botinActivo() then
            recogerBotin()
        end
        task.wait(CONFIG.ESPERA_RESPAWN)
    end
end

---------------------------------------------------------------
-- UI (compacta, táctil)
---------------------------------------------------------------
local BG = Color3.fromRGB(18, 20, 28)
local CARD = Color3.fromRGB(30, 33, 46)
local GREEN = Color3.fromRGB(80, 200, 130)
local RED = Color3.fromRGB(225, 85, 95)
local TEXT = Color3.fromRGB(240, 242, 250)
local MUTED = Color3.fromRGB(140, 146, 170)

local function mk(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end

local function crearGui()
    local gui = Instance.new("ScreenGui")
    gui.Name = "BossHunterUI"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 999
    gui.IgnoreGuiInset = true
    local ok = pcall(function()
        gui.Parent = game:GetService("CoreGui")
    end)
    if not ok or not gui.Parent then
        gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
    return gui
end

local bossBtn, toggleBtn, botinBtn, killsLbl, statusLbl, alturaLbl, ladoLbl

local function construirUI()
    local gui = crearGui()

    local main = mk("Frame", {
        Size = UDim2.fromOffset(150, 178),
        Position = UDim2.new(0, 8, 0.3, 0),
        BackgroundColor3 = BG,
        BorderSizePixel = 0,
        Active = true,
        Draggable = true,
    }, gui)
    mk("UICorner", { CornerRadius = UDim.new(0, 8) },
