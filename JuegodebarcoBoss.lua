-- Sesión de caza de bosses: HE IRON TYRANT y Celestial Serpent
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local CONFIG = {
    DISTANCIA = 4,               -- studs detrás del boss
    ALTURA = 0,                  -- studs de altura sobre el punto de ataque
    VELOCIDAD = 60,              -- studs/s al viajar a la isla (movimiento suave)
    ESPERA_CARGA_BOSS = 20,      -- segundos esperando que aparezca el boss al llegar
    ESPERA_ATAQUE = 0.15,        -- segundos entre cada golpe
    ESPERA_RESPAWN = 3,          -- segundos antes de volver a buscar el boss tras morir
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
local statusText = "Listo"

---------------------------------------------------------------
-- UTILIDADES
---------------------------------------------------------------
local function setStatus(text)
    statusText = text
    print("[BOSS]", text)
end

local function getRoot()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function posOf(obj)
    if obj:IsA("Model") then
        return obj:GetPivot().Position
    end
    return obj.Position
end

local function getPath(parts)
    local obj = Workspace
    for _, name in ipairs(parts) do
        obj = obj and obj:FindFirstChild(name)
    end
    return obj
end

-- Busca la isla por nombre en todo el mapa (con caché)
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

-- Punto al que se apega el jugador: la carpeta indicada (o la primera pieza dentro)
local function getAnchor(boss, parteName)
    local carpeta = boss:FindFirstChild(parteName)
    if not carpeta then return nil end
    if carpeta:IsA("BasePart") or carpeta:IsA("Model") then
        return carpeta
    end
    for _, d in ipairs(carpeta:GetDescendants()) do
        if d:IsA("BasePart") then return d end
    end
    return nil
end

local function bossVivo(boss)
    if not boss or not boss.Parent then return false end
    local hum = boss:FindFirstChildWhichIsA("Humanoid", true)
    if hum and hum.Health <= 0 then return false end
    local hp = boss:GetAttribute("Health")
    if type(hp) == "number" and hp <= 0 then return false end
    return true
end

-- Teletransporte suave hasta una posición
local function irA(pos)
    local root = getRoot()
    if not root then return end
    local inicio = root.Position
    local duracion = math.max((pos - inicio).Magnitude / CONFIG.VELOCIDAD, 0.05)
    local t0 = os.clock()
    while not closed and cazando do
        root = getRoot()
        if not root then break end
        local a = math.min((os.clock() - t0) / duracion, 1)
        root.AssemblyLinearVelocity = Vector3.zero
        root.CFrame = CFrame.new(inicio:Lerp(pos, a)) * (root.CFrame - root.CFrame.Position)
        if a >= 1 then break end
        task.wait()
    end
end

-- Mueve al jugador sin espera (para seguir al boss mientras ataca)
local function snapTo(cf)
    local root = getRoot()
    if not root then return end
    root.AssemblyLinearVelocity = Vector3.zero
    root.CFrame = cf
end

-- Se queda flotando sin caer (no se ancla para que el servidor siga recibiendo la posición)
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

-- Usa la tool en la mano; si no hay, equipa la primera de la mochila
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

-- Posición de ataque: detrás del punto de anclaje, mirando al boss
local function cfAtaque(anchor)
    local pos = posOf(anchor)
    local p = pos + Vector3.new(0, CONFIG.ALTURA, CONFIG.DISTANCIA)
    return CFrame.lookAt(p, pos)
end

---------------------------------------------------------------
-- CAZA
---------------------------------------------------------------
local function cazar(b)
    setStatus("Yendo a " .. b.isla .. " (" .. b.mar .. ")...")
    local isla = getIsla(b.isla)
    if not isla then
        setStatus("No encuentro la isla " .. b.isla)
        cazando = false
        return
    end

    irA(posOf(isla) + Vector3.new(0, 10, 0))
    if closed or not cazando then return end
    setHover(true)

    -- Espera a que aparezca el boss al llegar a la isla
    local t0 = os.clock()
    while not closed and cazando and os.clock() - t0 < CONFIG.ESPERA_CARGA_BOSS do
        local boss = getPath(b.ruta)
        local anchor = boss and getAnchor(boss, b.parte)
        if anchor and bossVivo(boss) then break end
        setStatus("Esperando a " .. b.nombre .. "...")
        task.wait(0.5)
    end

    -- Ataque
    while not closed and cazando do
        local boss = getPath(b.ruta)
        local anchor = boss and getAnchor(boss, b.parte)
        if not anchor or not bossVivo(boss) then break end

        local tool = herramienta()
        if not tool then
            setStatus("No tienes ninguna tool en la mano")
            cazando = false
            break
        end

        setStatus("Atacando " .. b.nombre)
        snapTo(cfAtaque(anchor))
        pcall(function() tool:Activate() end)
        task.wait(CONFIG.ESPERA_ATAQUE)
    end

    local boss = getPath(b.ruta)
    if cazando and not closed and boss and not bossVivo(boss) then
        kills += 1
        setStatus(b.nombre .. " derrotado (" .. kills .. ")")
        task.wait(CONFIG.ESPERA_RESPAWN)
    elseif cazando and not closed and not (boss and getAnchor(boss, b.parte)) then
        setStatus(b.nombre .. " no apareció en la isla")
        task.wait(2)
    end
end

---------------------------------------------------------------
-- UI (táctil, compacta)
---------------------------------------------------------------
local function mk(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end

local BG = Color3.fromRGB(18, 20, 28)
local CARD = Color3.fromRGB(30, 33, 46)
local ACCENT = Color3.fromRGB(110, 150, 255)
local GREEN = Color3.fromRGB(80, 200, 130)
local RED = Color3.fromRGB(225, 85, 95)
local TEXT = Color3.fromRGB(240, 242, 250)

local gui = mk("ScreenGui", { Name = "BossHunterUI", ResetOnSpawn = false }, LocalPlayer:WaitForChild("PlayerGui"))
local main = mk("Frame", {
    Size = UDim2.fromOffset(250, 225), Position = UDim2.new(0, 12, 0.3, 0),
    BackgroundColor3 = BG, BorderSizePixel = 0, Active = true, Draggable = true,
}, gui)
mk("UICorner", { CornerRadius = UDim.new(0, 12) }, main)

local title = mk("TextLabel", {
    Size = UDim2.new(1, -16, 0, 20), Position = UDim2.new(0, 8, 0, 6),
    BackgroundTransparency = 1, Text = "Caza de Bosses", TextColor3 = TEXT,
    TextSize = 14, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left,
}, main)

local statusLbl = mk("TextLabel", {
    Size = UDim2.new(1, -16, 0, 30), Position = UDim2.new(0, 8, 0, 26),
    BackgroundTransparency = 1, TextColor3 = Color3.fromRGB(140, 146, 170), TextSize = 10,
    Font = Enum.Font.Gotham, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
}, main)

local function boton(text, pos, size, color, onClick)
    local b = mk("TextButton", {
        Text = text, Position = pos, Size = size, BackgroundColor3 = color,
        TextColor3 = TEXT, TextSize = 12, Font = Enum.Font.GothamBold, BorderSizePixel = 0,
    }, main)
    mk("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
    b.Activated:Connect(onClick)
    return b
end

local bossBtn = boton("", UDim2.new(0, 8, 0, 62), UDim2.new(1, -16, 0, 34), CARD, function()
    bossIndex = bossIndex % #BOSSES + 1
end)

local toggleBtn = boton("▶ Cazar", UDim2.new(0, 8, 0, 102), UDim2.new(1, -16, 0, 40), GREEN, function()
    cazando = not cazando
    if not cazando then
        setHover(false)
        setStatus("Caza detenida")
    end
end)

local killsLbl = mk("TextLabel", {
    Size = UDim2.new(1, -16, 0, 20), Position = UDim2.new(0, 8, 0, 150),
    BackgroundTransparency = 1, TextColor3 = TEXT, TextSize = 11, Font = Enum.Font.Gotham,
    TextXAlignment = Enum.TextXAlignment.Left,
}, main)

boton("Cerrar", UDim2.new(0, 8, 1, -36), UDim2.new(1, -16, 0, 28), RED, function()
    closed = true
    cazando = false
    setHover(false)
    gui:Destroy()
end)

---------------------------------------------------------------
-- BUCLE PRINCIPAL
---------------------------------------------------------------
task.spawn(function()
    while not closed do
        local b = BOSSES[bossIndex]
        bossBtn.Text = "Boss: " .. b.nombre .. " (" .. b.isla .. ")"
        toggleBtn.Text = cazando and "■ Parar" or "▶ Cazar"
        toggleBtn.BackgroundColor3 = cazando and RED or GREEN
        statusLbl.Text = statusText
        killsLbl.Text = "Derrotados: " .. kills

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
