-- Caza de bosses (TP): HE IRON TYRANT y Celestial Serpent
-- Altura ajustable desde la UI + recolección de cofres de la isla tras matar al boss
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local CONFIG = {
    DISTANCIA = 4,              -- studs detrás del boss
    ALTURA_INICIAL = 0,         -- altura de ataque inicial (la cambias con ▲ ▼)
    ALTURA_MIN = -20,
    ALTURA_MAX = 40,
    PASO_ALTURA = 1,
    ESPERA_STREAMING = 2,       -- segundos esperando que carguen los cofres al llegar a la isla
    ESPERA_CARGA_BOSS = 20,     -- segundos esperando que aparezca el boss
    ESPERA_ATAQUE = 0.15,       -- segundos entre golpes
    ESPERA_RESPAWN = 3,         -- segundos antes de buscar el boss otra vez
    CAPACIDAD = 81,             -- espacio de tu bóveda en el barco
    ALTURA_COFRE = 3,           -- studs sobre el cofre al recogerlo
    ESPERA_POSICION = 0.25,     -- para que el servidor reciba tu posición antes de recoger
    ESPERA_RECOGER = 0.3,
    INTENTOS_RECOGER = 2,
    ESPERA_GUARDADO = 3,        -- segundos máximos para confirmar que el cofre se guardó
    MARGEN_ISLA = 60,
    RADIO_ISLA_SIN_CAJA = 300,
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
local cofresGuardados = 0
local altura = CONFIG.ALTURA_INICIAL
local statusText = "Listo"
local objetivoCF = nil   -- lo aplica el Heartbeat cada frame (nil = no seguir)

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
    return obj.Position
end

local function tpTo(cf)
    local root = getRoot()
    if not root then return end
    root.AssemblyLinearVelocity = Vector3.zero
    root.CFrame = cf
end

-- Heartbeat: cada frame deja al personaje en el objetivo (sigue al boss)
RunService.Heartbeat:Connect(function()
    if not objetivoCF then return end
    local root = getRoot()
    if root then
        root.AssemblyLinearVelocity = Vector3.zero
        root.CFrame = objetivoCF
    end
end)

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

local function dentroIsla(isla, pos)
    local m = CONFIG.MARGEN_ISLA
    if isla:IsA("Model") then
        local cf, size = isla:GetBoundingBox()
        local rel = cf:PointToObjectSpace(pos)
        if math.abs(rel.X) <= size.X / 2 + m and math.abs(rel.Z) <= size.Z / 2 + m then
            return true
        end
        local flat = Vector3.new(cf.Position.X - pos.X, 0, cf.Position.Z - pos.Z)
        return flat.Magnitude <= math.max(size.X, size.Z) / 2 + m
    end
    local flat = Vector3.new(isla.Position.X - pos.X, 0, isla.Position.Z - pos.Z)
    return flat.Magnitude <= CONFIG.RADIO_ISLA_SIN_CAJA
end

---------------------------------------------------------------
-- BOSS
---------------------------------------------------------------
-- Centro de todas las piezas de la carpeta del boss (o centro del modelo si no hay piezas)
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

local function bossVivo(boss)
    if not boss or not boss.Parent then return false end
    local hum = boss:FindFirstChildWhichIsA("Humanoid", true)
    if hum and hum.Health <= 0 then return false end
    local hp = boss:GetAttribute("Health")
    if type(hp) == "number" and hp <= 0 then return false end
    return true
end

---------------------------------------------------------------
-- BARCO Y COFRES
---------------------------------------------------------------
local function esMiBarco(ship)
    local nombre, id = LocalPlayer.Name, tostring(LocalPlayer.UserId)
    for _, attr in ipairs({ "Owner", "OwnerName", "OwnerId", "Player", "PlayerName", "UserId" }) do
        local v = ship:GetAttribute(attr)
        if v ~= nil then
            local s = tostring(v)
            if s == nombre or s == LocalPlayer.DisplayName or s == id then return true end
        end
    end
    return ship.Name == nombre or ship.Name:find(id, 1, true) ~= nil
end

local function miBarco()
    local dyn = getPath({ "World", "Dynamic" })
    local ships = dyn and dyn:FindFirstChild("Ships")
    if not ships then return nil end
    for _, s in ipairs(ships:GetChildren()) do
        if s:IsA("Folder") then
            for _, d in ipairs(s:GetChildren()) do
                if (d:IsA("Model") or d:IsA("BasePart")) and esMiBarco(d) then return d end
            end
        elseif (s:IsA("Model") or s:IsA("BasePart")) and esMiBarco(s) then
            return s
        end
    end
    return nil
end

-- Espacio usado en la bóveda del barco
local function espacioUsado(barco)
    local total = 0
    local cargo = barco:FindFirstChild("CargoVisuals")
    if cargo then
        for _, c in ipairs(cargo:GetChildren()) do
            if c:IsA("Model") then
                total += tonumber(c:GetAttribute("CargoSize")) or 1
            end
        end
    end
    return total
end

-- Punto encima del barco donde se guardan los cofres
local function topeBarco(barco)
    local center, size
    if barco:IsA("Model") then
        center, size = barco:GetBoundingBox()
    else
        center, size = barco.CFrame, barco.Size
    end
    return CFrame.new(center.Position + Vector3.new(0, size.Y / 2 + 3, 0))
end

-- Recoge todos los cofres de la isla y los lleva al barco, uno por uno
local function recogerCofresIsla(b)
    local isla = getIsla(b.isla)
    local treasure = getPath({ "World", "Dynamic", "Treasure" })
    if not isla or not treasure then
        setStatus("No encuentro la isla o el Treasure")
        return
    end

    local barco = miBarco()
    if not barco then
        setStatus("No encuentro tu barco")
        return
    end

    local saltados = {}
    local recogidosAqui = 0

    while not closed and cazando do
        -- Busca el siguiente cofre de la isla que no hayamos intentado
        local item, base, prompt
        for _, c in ipairs(treasure:GetChildren()) do
            local bs = c:FindFirstChild("Base")
            local att = bs and bs:FindFirstChild("PromptAttachment")
            local pr = att and att:FindFirstChild("TreasurePrompt")
            if bs and pr and pr:IsA("ProximityPrompt") and not saltados[c] and dentroIsla(isla, bs.Position) then
                item, base, prompt = c, bs, pr
                break
            end
        end
        if not item then break end

        local size = tonumber(item:GetAttribute("CargoSize")) or 1
        if espacioUsado(barco) + size > CONFIG.CAPACIDAD then
            setStatus("Bóveda llena: vacíala y vuelve a empezar")
            break
        end

        saltados[item] = true
        setStatus("Recogiendo cofre (" .. size .. " espacio)...")

        -- 1) Ir al cofre y recogerlo
        local att = prompt.Parent
        local pos = (att and att:IsA("Attachment")) and att.WorldPosition or base.Position
        tpTo(CFrame.new(pos + Vector3.new(0, CONFIG.ALTURA_COFRE, 0)))
        task.wait(CONFIG.ESPERA_POSICION)
        pcall(function()
            prompt.RequiresLineOfSight = false
            if prompt.MaxActivationDistance < 25 then prompt.MaxActivationDistance = 25 end
        end)
        for _ = 1, CONFIG.INTENTOS_RECOGER do
            pcall(fireproximityprompt, prompt)
            task.wait(CONFIG.ESPERA_RECOGER)
            if not prompt:IsDescendantOf(Workspace) then break end
        end

        -- 2) Llevarlo al barco y esperar a que se guarde
        local antes = espacioUsado(barco)
        setStatus("Llevando cofre al barco...")
        tpTo(topeBarco(barco))
        local t0 = os.clock()
        while os.clock() - t0 < CONFIG.ESPERA_GUARDADO and espacioUsado(barco) <= antes do
            task.wait(0.25)
        end
        if espacioUsado(barco) > antes then
            recogidosAqui += 1
            cofresGuardados += 1
        else
            setStatus("El cofre no se guardó, sigo con el siguiente")
            task.wait(0.5)
        end
    end

    setStatus("Cofres de la isla: " .. recogidosAqui .. " guardados")
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

    -- 2) Esperar al boss
    local pos, boss
    local t0 = os.clock()
    while not closed and cazando and os.clock() - t0 < CONFIG.ESPERA_CARGA_BOSS do
        pos, boss = posicionBoss(b)
        if pos and bossVivo(boss) then break end
        setStatus("Esperando a " .. b.nombre .. "...")
        task.wait(0.5)
    end
    if not pos then
        setStatus(b.nombre .. " no apareció en la ruta")
        task.wait(2)
        return
    end

    -- 3) Seguir y atacar con la altura elegida
    while not closed and cazando do
        pos, boss = posicionBoss(b)
        if not pos or not bossVivo(boss) then break end

        objetivoCF = CFrame.lookAt(pos + Vector3.new(0, altura, CONFIG.DISTANCIA), pos)

        local tool = herramienta()
        if not tool then
            setStatus("No tienes ninguna tool en la mano")
            cazando = false
            break
        end

        pcall(function() tool:Activate() end)
        setStatus("Atacando " .. b.nombre .. " (altura " .. altura .. ") en " .. fmt(pos))
        task.wait(CONFIG.ESPERA_ATAQUE)
    end

    objetivoCF = nil

    -- 4) Boss muerto: recoger los cofres de la isla
    if cazando and not closed and boss and not bossVivo(boss) then
        kills += 1
        setStatus(b.nombre .. " derrotado (" .. kills .. ")")
        recogerCofresIsla(b)
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

local bossBtn, toggleBtn, killsLbl, statusLbl, alturaLbl

local function construirUI()
    local gui = crearGui()

    local main = mk("Frame", {
        Size = UDim2.fromOffset(150, 132),
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

    statusLbl = mk("TextLabel", {
        Size = UDim2.new(1, -12, 0, 12), Position = UDim2.new(0, 6, 0, 18),
        BackgroundTransparency = 1, TextColor3 = MUTED, TextSize = 8,
        Font = Enum.Font.Gotham, TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, main)

    local function boton(pos, size, color, textSize, onClick)
        local b = mk("TextButton", {
            Position = pos, Size = size, BackgroundColor3 = color,
            TextColor3 = TEXT, TextSize = textSize, Font = Enum.Font.GothamBold, BorderSizePixel = 0,
        }, main)
        mk("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
        b.Activated:Connect(onClick)
        return b
    end

    bossBtn = boton(UDim2.new(0, 6, 0, 34), UDim2.new(1, -12, 0, 22), CARD, 9, function()
        bossIndex = bossIndex % #BOSSES + 1
    end)

    toggleBtn = boton(UDim2.new(0, 6, 0, 60), UDim2.new(1, -12, 0, 26), GREEN, 10, function()
        cazando = not cazando
        if not cazando then
            objetivoCF = nil
            setHover(false)
            setStatus("Caza detenida")
        end
    end)

    -- Fila de altura: ▼ valor ▲
    boton(UDim2.new(0, 6, 0, 90), UDim2.fromOffset(34, 20), CARD, 10, function()
        altura = math.max(CONFIG.ALTURA_MIN, altura - CONFIG.PASO_ALTURA)
    end).Text = "▼"

    alturaLbl = mk("TextLabel", {
        Position = UDim2.new(0, 42, 0, 90), Size = UDim2.new(1, -84, 0, 20),
        BackgroundTransparency = 1, TextColor3 = TEXT, TextSize = 9,
        Font = Enum.Font.GothamBold, Text = "",
    }, main)

    boton(UDim2.new(1, -40, 0, 90), UDim2.fromOffset(34, 20), CARD, 10, function()
        altura = math.min(CONFIG.ALTURA_MAX, altura + CONFIG.PASO_ALTURA)
    end).Text = "▲"

    killsLbl = mk("TextLabel", {
        Size = UDim2.new(1, -12, 0, 12), Position = UDim2.new(0, 6, 0, 114),
        BackgroundTransparency = 1, TextColor3 = TEXT, TextSize = 8, Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, main)

    local closeBtn = boton(UDim2.new(1, -20, 0, 3), UDim2.fromOffset(17, 17), RED, 9, function()
        closed = true
        cazando = false
        objetivoCF = nil
        setHover(false)
        gui:Destroy()
    end)
    closeBtn.Text = "✕"
end

local okUI, errUI = pcall(construirUI)
if not okUI then
    warn("[BOSS] No se pudo crear la UI: " .. tostring(errUI))
end

---------------------------------------------------------------
-- BUCLE PRINCIPAL
---------------------------------------------------------------
task.spawn(function()
    while not closed do
        local b = BOSSES[bossIndex]
        if bossBtn then
            bossBtn.Text = b.nombre
            toggleBtn.Text = cazando and "■ Parar" or "▶ Cazar"
            toggleBtn.BackgroundColor3 = cazando and RED or GREEN
            alturaLbl.Text = "Altura: " .. altura
            statusLbl.Text = statusText
            killsLbl.Text = "Derrotados: " .. kills .. " · Cofres: " .. cofresGuardados
        end

        if cazando then
            local ok, err = pcall(cazar, b)
            if not ok then
                setStatus("Error: " .. tostring(err))
                task.wait(2)
            end
        else
            setHover(false)
            task.wait(0.3)
        end
    end
end)
