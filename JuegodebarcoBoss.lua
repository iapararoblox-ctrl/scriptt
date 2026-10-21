-- Caza de bosses (TP): HE IRON TYRANT y Celestial Serpent
-- Versión estable: UI en PlayerGui, seguimiento desconectable, detección de muerte y botín por fuerza bruta
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

print("[BOSS] Script iniciado")

---------------------------------------------------------------
-- CONFIGURACIÓN
---------------------------------------------------------------
local CONFIG = {
    DISTANCIA = 4,               -- studs detrás del boss
    ALTURA_MIN = -20,
    ALTURA_MAX = 40,
    LADO_MIN = -30,
    LADO_MAX = 30,
    PASO = 1,
    ARCHIVO = "BossConfig.json",
    ESPERA_STREAMING = 2,        -- al llegar a la isla
    ESPERA_CARGA_BOSS = 20,      -- esperando que aparezca el boss
    ESPERA_ATAQUE = 0.15,        -- entre golpes
    ESPERA_RESPAWN = 3,          -- antes de buscar el boss otra vez
    ESPERA_INICIAL_BOTIN = 8,    -- tras morir el boss, antes de buscar botín
    ESPERA_BARCO = 3,            -- encima del barco para que se guarde
    ALTURA_BOTIN = 3,            -- studs sobre el botín
    ALTURA_BARCO = 0,            -- studs sobre el barco
    INTENTOS_PROMPT = 5,         -- veces que se activa el prompt de cada botín
    MAX_INTENTOS_BOTIN = 5,      -- si un botín no desaparece, se salta
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

local LOOT_PATH = { "World", "Dynamic", "Loot" }
local SHIPS_PATH = { "World", "Dynamic", "Ships" }

---------------------------------------------------------------
-- ESTADO
---------------------------------------------------------------
local bossIndex = 1
local cazando = false
local cerrado = false
local muertes = 0
local botinTotal = 0
local statusText = "Listo"
local cachedShip = nil
local islaCache = {}
local UI = {}

---------------------------------------------------------------
-- AJUSTES (altura y lado por boss, botón de botín) en archivo
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
    print("[BOSS] " .. text)
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

local function fmt(v)
    return string.format("%.0f,%.0f,%.0f", v.X, v.Y, v.Z)
end

---------------------------------------------------------------
-- SEGUIMIENTO (se conecta al atacar y se desconecta al morir el boss)
---------------------------------------------------------------
local followConn = nil
local followCF = nil

local function startFollow()
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

local function stopFollow()
    followCF = nil
    if followConn then
        followConn:Disconnect()
        followConn = nil
    end
end

-- Flotar (sin anclar, para que el servidor siga recibiendo la posición)
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

---------------------------------------------------------------
-- ISLAS
---------------------------------------------------------------
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
-- Posición: centro de las piezas de la carpeta del boss (o del modelo si no tiene piezas)
local function posicionBoss(b)
    local boss = getPath(b.ruta)
    if not boss then return nil, nil end

    local pos
    local carpeta = boss:FindFirstChild(b.parte)
    if carpeta then
        if carpeta:IsA("BasePart") or carpeta:IsA("Model") then
            pos = posOf(carpeta)
        else
            local suma, n = Vector3.zero, 0
            for _, d in ipairs(carpeta:GetDescendants()) do
                if d:IsA("BasePart") then
                    suma += d.Position
                    n += 1
                end
            end
            if n > 0 then pos = suma / n end
        end
    end
    return pos or posOf(boss), boss
end

-- Devuelve el motivo de la muerte, o nil si sigue vivo
local function motivoMuerte(b, ref, lootAntes, teniaParte)
    if not ref or not ref.Parent then
        return "el boss desapareció del Workspace"
    end

    local hum = ref:FindFirstChildWhichIsA("Humanoid", true)
    if hum and hum.Health <= 0 then
        return "Humanoid.Health = 0"
    end

    local hp = ref:GetAttribute("Health")
    if type(hp) == "number" and hp <= 0 then
        return "atributo Health = 0"
    end

    if ref:GetAttribute("Dead") == true then
        return "atributo Dead"
    end

    if teniaParte and not ref:FindFirstChild(b.parte) then
        return "la carpeta " .. b.parte .. " ya no existe"
    end

    local loot = getPath(LOOT_PATH)
    if loot and #listaBotin(loot) > lootAntes then
        return "apareció botín nuevo en Loot"
    end

    return nil
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
    return ship.Name:find(userId, 1, true) ~= nil
end

local function getMyShip()
    if cachedShip and cachedShip.Parent then
        return cachedShip
    end
    cachedShip = nil

    local ships = getPath(SHIPS_PATH)
    if not ships then return nil end

    for _, child in ipairs(ships:GetChildren()) do
        local candidatos = {}
        if child:IsA("Model") or child:IsA("BasePart") then
            table.insert(candidatos, child)
        elseif child:IsA("Folder") then
            for _, d in ipairs(child:GetChildren()) do
                if d:IsA("Model") or d:IsA("BasePart") then
                    table.insert(candidatos, d)
                end
            end
        end
        for _, c in ipairs(candidatos) do
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

function listaBotin(loot)
    local lista = {}
    for _, c in ipairs(loot:GetChildren()) do
        if findPrompt(c) then
            table.insert(lista, c)
        end
    end
    return lista
end

local function recogerBotin()
    local loot = getPath(LOOT_PATH)
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
    setStatus("Esperando botín...")
    task.wait(CONFIG.ESPERA_INICIAL_BOTIN)

    local intentos = {}
    local recogidos = 0
    local vacios = 0

    while not cerrado and cazando do
        local item, prompt
        for _, c in ipairs(loot:GetChildren()) do
            local p = findPrompt(c)
            if p and (intentos[c] or 0) < CONFIG.MAX_INTENTOS_BOTIN then
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
            intentos[item] = (intentos[item] or 0) + 1
            setStatus("Botín: " .. item.Name .. " (" .. intentos[item] .. ")")

            -- 1) Ir encima del botín y activar el prompt
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

            -- 2) Ir encima del barco y esperar a que se guarde
            tpTo(CFrame.new(getShipTop(barco)))
            task.wait(CONFIG.ESPERA_BARCO)

            if not prompt:IsDescendantOf(Workspace) or not findPrompt(item) then
                recogidos += 1
                botinTotal += 1
            end
        end
    end

    setHover(true)
    setStatus("Botín procesado: " .. recogidos)
end

---------------------------------------------------------------
-- CAZA
---------------------------------------------------------------
local function cazar(b)
    -- 1) TP a la isla y quedarse flotando
    setStatus("TP a " .. b.isla .. " (" .. b.mar .. ")")
    local isla = getIsla(b.isla)
    if not isla then
        setStatus("No encuentro la isla " .. b.isla)
        cazando = false
        return
    end
    tpTo(CFrame.new(posOf(isla) + Vector3.new(0, 10, 0)))
    setHover(true)
    task.wait(CONFIG.ESPERA_STREAMING)

    -- 2) Esperar a que aparezca el boss vivo
    local ref
    local t0 = os.clock()
    while not cerrado and cazando and os.clock() - t0 < CONFIG.ESPERA_CARGA_BOSS do
        local p, bo = posicionBoss(b)
        if p and bo and not motivoMuerte(b, bo, 0, false) then
            ref = bo
            break
        end
        setStatus("Esperando a " .. b.nombre .. "...")
        task.wait(0.5)
    end
    if not ref then
        if cazando then setStatus(b.nombre .. " no apareció en la ruta") end
        task.wait(2)
        return
    end

    -- 3) Atacar y vigilar la muerte
    local loot = getPath(LOOT_PATH)
    local lootAntes = loot and #listaBotin(loot) or 0
    local teniaParte = ref:FindFirstChild(b.parte) ~= nil
    local motivo = nil

    startFollow()
    while not cerrado and cazando do
        local p, bo = posicionBoss(b)
        if bo then ref = bo end

        motivo = motivoMuerte(b, ref, lootAntes, teniaParte)
        if motivo then break end
        if not p then
            motivo = "no encuentro la ruta del boss"
            break
        end

        local a = ajusteDe(b)
        followCF = CFrame.lookAt(p + Vector3.new(a.lado, a.altura, CONFIG.DISTANCIA), p)

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

    -- 4) Soltar al personaje del boss PRIMERO
    stopFollow()

    if motivo and cazando and not cerrado then
        muertes += 1
        print("[BOSS] " .. b.nombre .. " derrotado. Motivo: " .. motivo)
        setStatus(b.nombre .. " derrotado (" .. muertes .. ")")

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
-- UI (compacta, táctil) — se crea en PlayerGui
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

local function boton(parent, pos, size, color, textSize, texto, onClick)
    local b = mk("TextButton", {
        Position = pos, Size = size, BackgroundColor3 = color,
        TextColor3 = TEXT, TextSize = textSize, Font = Enum.Font.GothamBold,
        BorderSizePixel = 0, Text = texto,
    }, parent)
    mk("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
    b.Activated:Connect(onClick)
    return b
end

local function crearUI()
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")

    local gui = mk("ScreenGui", {
        Name = "BossHunterUI",
        ResetOnSpawn = false,
        DisplayOrder = 999,
        IgnoreGuiInset = true,
    }, playerGui)

    local main = mk("Frame", {
        Size = UDim2.fromOffset(150, 178),
        Position = UDim2.new(0, 8, 0.3, 0),
        BackgroundColor3 = BG,
        BorderSizePixel = 0,
        Active = true,
        Draggable = true,
    }, gui)
    mk("UICorner", { CornerRadius = UDim.new(0, 8) }, main)

    mk("TextLabel", {
        Size = UDim2.new(1, -28, 0, 14), Position = UDim2.new(0, 6, 0, 4),
        BackgroundTransparency = 1, Text = "Bosses", TextColor3 = TEXT,
        TextSize = 11, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left,
    }, main)

    UI.status = mk("TextLabel", {
        Size = UDim2.new(1, -12, 0, 12), Position = UDim2.new(0, 6, 0, 18),
        BackgroundTransparency = 1, TextColor3 = MUTED, TextSize = 8,
        Font = Enum.Font.Gotham, TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, main)

    UI.boss = boton(main, UDim2.new(0, 6, 0, 34), UDim2.new(1, -12, 0, 22), CARD, 9, "", function()
        bossIndex = bossIndex % #BOSSES + 1
    end)

    UI.toggle = boton(main, UDim2.new(0, 6, 0, 60), UDim2.new(1, -12, 0, 26), GREEN, 10, "", function()
        cazando = not cazando
        if not cazando then
            stopFollow()
            setHover(false)
            setStatus("Caza detenida")
        else
            setStatus("Iniciando caza...")
        end
    end)

    -- Fila altura
    boton(main, UDim2.new(0, 6, 0, 90), UDim2.fromOffset(34, 20), CARD, 10, "▼", function()
        local a = ajusteDe(BOSSES[bossIndex])
        a.altura = math.max(CONFIG.ALTURA_MIN, a.altura - CONFIG.PASO)
        guardarAjustes()
    end)
    UI.altura = mk("TextLabel", {
        Position = UDim2.new(0, 42, 0, 90), Size = UDim2.new(1, -84, 0, 20),
        BackgroundTransparency = 1, TextColor3 = TEXT, TextSize = 9,
        Font = Enum.Font.GothamBold, Text = "",
    }, main)
    boton(main, UDim2.new(1, -40, 0, 90), UDim2.fromOffset(34, 20), CARD, 10, "▲", function()
        local a = ajusteDe(BOSSES[bossIndex])
        a.altura = math.min(CONFIG.ALTURA_MAX, a.altura + CONFIG.PASO)
        guardarAjustes()
    end)

    -- Fila lado
    boton(main, UDim2.new(0, 6, 0, 114), UDim2.fromOffset(34, 20), CARD, 10, "◀", function()
        local a = ajusteDe(BOSSES[bossIndex])
        a.lado = math.max(CONFIG.LADO_MIN, a.lado - CONFIG.PASO)
        guardarAjustes()
    end)
    UI.lado = mk("TextLabel", {
        Position = UDim2.new(0, 42, 0, 114), Size = UDim2.new(1, -84, 0, 20),
        BackgroundTransparency = 1, TextColor3 = TEXT, TextSize = 9,
        Font = Enum.Font.GothamBold, Text = "",
    }, main)
    boton(main, UDim2.new(1, -40, 0, 114), UDim2.fromOffset(34, 20), CARD, 10, "▶", function()
        local a = ajusteDe(BOSSES[bossIndex])
        a.lado = math.min(CONFIG.LADO_MAX, a.lado + CONFIG.PASO)
        guardarAjustes()
    end)

    UI.botin = boton(main, UDim2.new(0, 6, 0, 138), UDim2.new(1, -12, 0, 20), CARD, 9, "", function()
        ajustes._botin = not botinActivo()
        guardarAjustes()
    end)

    UI.kills = mk("TextLabel", {
        Size = UDim2.new(1, -12, 0, 12), Position = UDim2.new(0, 6, 0, 162),
        BackgroundTransparency = 1, TextColor3 = TEXT, TextSize = 8, Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, main)

    boton(main, UDim2.new(1, -20, 0, 3), UDim2.fromOffset(17, 17), RED, 9, "✕", function()
        cerrado = true
        cazando = false
        stopFollow()
        setHover(false)
        gui:Destroy()
    end)

    print("[BOSS] UI creada")
end

local okUI, errUI = pcall(crearUI)
if not okUI then
    warn("[BOSS] Error al crear la UI: " .. tostring(errUI))
end

---------------------------------------------------------------
-- BUCLE PRINCIPAL
---------------------------------------------------------------
task.spawn(function()
    while not cerrado do
        local b = BOSSES[bossIndex]

        if UI.boss then
            local a = ajusteDe(b)
            UI.boss.Text = b.nombre
            UI.toggle.Text = cazando and "■ Parar" or "▶ Cazar"
            UI.toggle.BackgroundColor3 = cazando and RED or GREEN
            UI.altura.Text = "Altura: " .. a.altura
            UI.lado.Text = "Lado: " .. a.lado
            UI.botin.Text = "Botín: " .. (botinActivo() and "ON" or "OFF")
            UI.botin.BackgroundColor3 = botinActivo() and GREEN or CARD
            UI.status.Text = statusText
            UI.kills.Text = "Muertes: " .. muertes .. " · Botín: " .. botinTotal
        end

        if cazando then
            local ok, err = pcall(cazar, b)
            if not ok then
                stopFollow()
                setStatus("Error: " .. tostring(err))
                task.wait(2)
            end
        else
            task.wait(0.3)
        end
    end
end)
