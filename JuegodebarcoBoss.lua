-- Caza de bosses (TP): HE IRON TYRANT y Celestial Serpent
-- Altura y lado por boss (guardados), botín de World.Dynamic.Loot recogido igual que el script de cofres
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

local CONFIG = {
    DISTANCIA = 4,              -- studs detrás del boss
    ALTURA_MIN = -20,
    ALTURA_MAX = 40,
    LADO_MIN = -30,
    LADO_MAX = 30,
    PASO = 1,                   -- studs por pulsación
    ARCHIVO = "BossConfig.json",
    ESPERA_STREAMING = 2,       -- al llegar a la isla
    ESPERA_CARGA_BOSS = 20,     -- esperando que aparezca el boss
    ESPERA_ATAQUE = 0.15,       -- entre golpes
    ESPERA_RESPAWN = 3,         -- antes de buscar el boss otra vez
    ESPERA_BOTIN = 2,           -- tras morir el boss, para que aparezca el botín
    -- Botín (mismos valores que el script de cofres)
    CAPACIDAD = 81,             -- espacio de la bóveda de tu barco
    ALTURA_COFRE = 3,           -- studs sobre el cofre al recogerlo
    ALTURA_BARCO = 3,           -- studs sobre el barco al guardar
    ESPERA_POSICION = 0.25,     -- para que el servidor reciba tu posición antes de recoger
    ESPERA_RECOGER = 0.3,
    INTENTOS_RECOGER = 2,
    ESPERA_GUARDADO = 3,        -- segundos máximos para confirmar que el cofre se guardó
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
local statusText = "Listo"
local objetivoCF = nil

---------------------------------------------------------------
-- AJUSTES POR BOSS (altura y lado), guardados en archivo
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

-- Teletransporte instantáneo (igual que el script de cofres)
local function tpTo(cf)
    local root = getRoot()
    if not root then return end
    root.AssemblyLinearVelocity = Vector3.zero
    root.CFrame = cf
    task.wait(0.2)
end

-- Cada frame deja al personaje en el objetivo (así sigue al boss)
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

---------------------------------------------------------------
-- BOSS
---------------------------------------------------------------
-- Centro de las piezas de la carpeta del boss (o centro del modelo si la carpeta no tiene piezas)
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
-- BARCO Y BÓVEDA (igual que el script de cofres)
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
    local ships = getPath({ "World", "Dynamic", "Ships" })
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
    return tonumber(getChestProp(obj, "CargoSize")) or 1
end

local function chestsOn(barco)
    local list = {}
    local cargo = barco and barco:FindFirstChild("CargoVisuals")
    if cargo then
        for _, c in ipairs(cargo:GetChildren()) do
            if c:IsA("Model") then
                table.insert(list, c)
            end
        end
    end
    return list
end

local function usedSpaceOn(barco)
    local total = 0
    for _, c in ipairs(chestsOn(barco)) do
        total += getCargoSize(c)
    end
    return total
end

-- Punto encima del barco donde se guardan los cofres
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
-- BOTÍN (World.Dynamic.Loot): recoger uno por uno y llevarlo al barco
---------------------------------------------------------------
-- Busca el prompt del botín: primero la ruta de cofre (Base/PromptAttachment/TreasurePrompt),
-- si no existe, cualquier ProximityPrompt dentro
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

local function recogerBotin(b)
    local loot = getPath({ "World", "Dynamic", "Loot" })
    if not loot then
        setStatus("No encuentro World.Dynamic.Loot")
        return
    end

    local barco = miBarco()
    if not barco then
        setStatus("No encuentro tu barco")
        return
    end

    local saltados = {}
    local guardados = 0

    while not closed and cazando do
        local item, prompt
        for _, c in ipairs(loot:GetChildren()) do
            if not saltados[c] then
                local p = findPrompt(c)
                if p then
                    item, prompt = c, p
                    break
                end
            end
        end
        if not item then break end
        saltados[item] = true

        local size = getCargoSize(item)
        if usedSpaceOn(barco) + size > CONFIG.CAPACIDAD then
            setStatus("Bóveda llena: vacíala para seguir")
            break
        end

        -- 1) Ir encima del cofre y recogerlo (igual que el script de cofres)
        local att = prompt.Parent
        local anchorPos = (att and att:IsA("Attachment")) and att.WorldPosition or posOf(item)
        if not anchorPos then
            setStatus("No encuentro la posición de " .. item.Name)
            continue
        end

        setStatus("Recogiendo cofre (" .. size .. " espacio)...")
        tpTo(CFrame.new(anchorPos + Vector3.new(0, CONFIG.ALTURA_COFRE, 0)))

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
            if not prompt:IsDescendantOf(Workspace) then break end
        end

        -- 2) Llevarlo al barco y confirmar que apareció en la bóveda
        local antes = usedSpaceOn(barco)
        setHover(false)
        setStatus("Guardando en tu barco...")
        tpTo(CFrame.new(getShipTop(barco)))

        local t0 = os.clock()
        while os.clock() - t0 < CONFIG.ESPERA_GUARDADO and usedSpaceOn(barco) <= antes do
            task.wait(0.25)
        end

        if usedSpaceOn(barco) > antes then
            guardados += 1
            cofresGuardados += 1
        else
            setStatus("El cofre no se guardó, sigo con el siguiente")
            task.wait(0.5)
        end
    end

    setStatus("Botín guardado en el barco: " .. guardados)
end

---------------------------------------------------------------
-- CAZA
---------------------------------------------------------------
local function cazar(b)
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

    -- Ataque: altura y lado se leen en cada golpe, así se aplican al instante
    while not closed and cazando do
        pos, boss = posicionBoss(b)
        if not pos or not bossVivo(boss) then break end

        local a = ajusteDe(b)
        objetivoCF = CFrame.lookAt(
            pos + Vector3.new(a.lado, a.altura, CONFIG.DISTANCIA),
            pos
        )

        local tool = herramienta()
        if not tool then
            setStatus("No tienes ninguna tool en la mano")
            cazando = false
            break
        end

        pcall(function() tool:Activate() end)
        setStatus("Atacando " .. b.nombre .. " (" .. fmt(pos) .. ")")
        task.wait(CONFIG.ESPERA_ATAQUE)
    end

    objetivoCF = nil

    if cazando and not closed and boss and not bossVivo(boss) then
        kills += 1
        setStatus(b.nombre .. " derrotado (" .. kills .. ")")
        task.wait(CONFIG.ESPERA_BOTIN)
        recogerBotin(b)
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

local bossBtn, toggleBtn, killsLbl, statusLbl, alturaLbl, ladoLbl

local function construirUI()
    local gui = crearGui()

    local main = mk("Frame", {
        Size = UDim2.fromOffset(150, 156),
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

    local function fila(y, onMinus, onPlus, txtMinus, txtPlus)
        boton(UDim2.new(0, 6, 0, y), UDim2.fromOffset(34, 20), CARD, 10, onMinus).Text = txtMinus
        boton(UDim2.new(1, -40, 0, y), UDim2.fromOffset(34, 20), CARD, 10, onPlus).Text = txtPlus
        return mk("TextLabel", {
            Position = UDim2.new(0, 42, 0, y), Size = UDim2.new(1, -84, 0, 20),
            BackgroundTransparency = 1, TextColor3 = TEXT, TextSize = 9,
            Font = Enum.Font.GothamBold, Text = "",
        }, main)
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

    alturaLbl = fila(90,
        function()
            local a = ajusteDe(BOSSES[bossIndex])
            a.altura = math.max(CONFIG.ALTURA_MIN, a.altura - CONFIG.PASO)
            guardarAjustes()
        end,
        function()
            local a = ajusteDe(BOSSES[bossIndex])
            a.altura = math.min(CONFIG.ALTURA_MAX, a.altura + CONFIG.PASO)
            guardarAjustes()
        end,
        "▼", "▲")

    ladoLbl = fila(114,
        function()
            local a = ajusteDe(BOSSES[bossIndex])
            a.lado = math.max(CONFIG.LADO_MIN, a.lado - CONFIG.PASO)
            guardarAjustes()
        end,
        function()
            local a = ajusteDe(BOSSES[bossIndex])
            a.lado = math.min(CONFIG.LADO_MAX, a.lado + CONFIG.PASO)
            guardarAjustes()
        end,
        "◀", "▶")

    killsLbl = mk("TextLabel", {
        Size = UDim2.new(1, -12, 0, 12), Position = UDim2.new(0, 6, 0, 138),
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
            local a = ajusteDe(b)
            bossBtn.Text = b.nombre
            toggleBtn.Text = cazando and "■ Parar" or "▶ Cazar"
            toggleBtn.BackgroundColor3 = cazando and RED or GREEN
            alturaLbl.Text = "Altura: " .. a.altura
            ladoLbl.Text = "Lado: " .. a.lado
            statusLbl.Text = statusText
            killsLbl.Text = "Derrotados: " .. kills .. " · Botín: " .. cofresGuardados
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
