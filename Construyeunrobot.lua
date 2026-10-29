-- MaykDev · Auto Chatarra v7 (LocalScript · móvil)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

---------------------------------------------------------------
-- CONFIGURACIÓN
---------------------------------------------------------------
local CONFIG = {
    MUNDOS = {
        { nombre = "Space",     color = Color3.fromRGB(170, 120, 255) },
        { nombre = "Heaven",    color = Color3.fromRGB(120, 220, 255) },
        { nombre = "Overworld", color = Color3.fromRGB(240, 200, 120) },
    },
    ROBOT_PREFIJO = "Fighter",
    JUNKYARD = { "Server", "Junkyard" },
    PLOTS = { "Client", "Plots" },
    PREFIJOS = { "Junk" },
    CATEGORIAS = {
        { id = "Scrap/Giant",   nombre = "Gigante", color = Color3.fromRGB(240, 110, 90) },
        { id = "Scrap/Big",     nombre = "Grande",  color = Color3.fromRGB(240, 185, 80) },
        { id = "Scrap/Medium",  nombre = "Mediana", color = Color3.fromRGB(110, 170, 255) },
        { id = "Scrap/Small",   nombre = "Pequeña", color = Color3.fromRGB(120, 210, 150) },
        { id = "Sin categoría", nombre = "Sin categoría", color = Color3.fromRGB(140, 146, 170) },
    },
    VELOCIDAD      = { ini = 60, min = 20, max = 200, paso = 10 },
    RETRASO        = { ini = 0.5, min = 0.1, max = 3, paso = 0.1 },
    ALTURA         = { ini = 3, min = 0, max = 10, paso = 1 },
    INTENTOS       = { ini = 2, min = 1, max = 4, paso = 1 },
    MAX_JUNK       = { ini = 20, min = 1, max = 500, paso = 5 },
    ESPERA_PLOT    = { ini = 4, min = 0, max = 30, paso = 1 },
    PELIGRO        = { ini = 25, min = 8, max = 80, paso = 5 },
    ANTICIPO       = { ini = 1.2, min = 0.4, max = 3, paso = 0.1 },
    MULT_HUIDA     = 1.6,
    TIEMPO_EVASION = 4,
    ESPERA_RECOGER = 0.35,
    COOLDOWN_FALLO = 12,
    COOLDOWN_PELIGRO = 6,
    ESPERA_CICLO   = 0.75,
    TIMEOUT_VUELO  = 25,
    REMOTE_RUTA    = { "Packages", "Net", "Remotes" },
    REMOTE_NOMBRE  = "PickUpJunk",
    PALABRAS_VENTA = { "vend", "sell", "deposit", "guard", "entreg", "deliver" },
}

local SIN_CAT = #CONFIG.CATEGORIAS
local CAT_INDEX = {}
for i, c in ipairs(CONFIG.CATEGORIAS) do
    CAT_INDEX[c.id] = i
end

---------------------------------------------------------------
-- ESTADO
---------------------------------------------------------------
local S = {
    activo = false,
    cerrado = false,
    ocupado = false,
    velocidad = CONFIG.VELOCIDAD.ini,
    retraso = CONFIG.RETRASO.ini,
    altura = CONFIG.ALTURA.ini,
    intentos = CONFIG.INTENTOS.ini,
    maxJunk = CONFIG.MAX_JUNK.ini,
    esperaPlot = CONFIG.ESPERA_PLOT.ini,
    peligro = CONFIG.PELIGRO.ini,
    anticipo = CONFIG.ANTICIPO.ini,
    reiniciarGolpe = true,
    mundoOn = { true, true, true },
    catOn = { true, true, true, true, true },
    conteo = {},
    conteoMundo = {},
    robotsMundo = {},
    visibles = 0,
    cooldown = {},
    cargados = 0,
    recogidas = 0,
    vaciados = 0,
    fallos = 0,
    huidas = 0,
    golpes = 0,
    estado = "Listo",
    diag = {},
    log = {},
}
for i = 1, SIN_CAT do S.conteo[i] = 0 end
for i = 1, #CONFIG.MUNDOS do
    S.conteoMundo[i] = 0
    S.robotsMundo[i] = 0
end

local memDist = setmetatable({}, { __mode = "k" })

local C = {
    bg = Color3.fromRGB(16, 18, 26),
    card = Color3.fromRGB(28, 31, 44),
    row = Color3.fromRGB(37, 41, 58),
    track = Color3.fromRGB(46, 50, 70),
    accent = Color3.fromRGB(110, 150, 255),
    green = Color3.fromRGB(80, 200, 130),
    red = Color3.fromRGB(225, 85, 95),
    text = Color3.fromRGB(240, 242, 250),
    muted = Color3.fromRGB(140, 146, 170),
}

local function log(msg)
    table.insert(S.log, 1, string.format("[%.0fs] %s", os.clock(), tostring(msg)))
    while #S.log > 8 do
        table.remove(S.log)
    end
    print("[CHATARRA]", msg)
end

---------------------------------------------------------------
-- UTILIDADES
---------------------------------------------------------------
local function ruta(root, pasos)
    local cur = root
    for _, p in ipairs(pasos) do
        cur = cur and cur:FindFirstChild(p)
        if not cur then return nil end
    end
    return cur
end

local function getRoot()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function partsFolder(nombreMundo)
    return ruta(Workspace, { "Client", "Junkyard", nombreMundo, "Spawn", "Parts" })
end

local function fightFolder(nombreMundo)
    return ruta(Workspace, { "Client", "Junkyard", "fight", nombreMundo })
end

local function esJunk(name)
    for _, p in ipairs(CONFIG.PREFIJOS) do
        if string.sub(name, 1, #p) == p then
            return true
        end
    end
    return false
end

local function esRobot(name)
    return string.sub(name, 1, #CONFIG.ROBOT_PREFIJO) == CONFIG.ROBOT_PREFIJO
end

local function dentroDeModelo(obj, carpeta)
    local p = obj.Parent
    while p and p ~= carpeta do
        if p:IsA("Model") or esJunk(p.Name) or esRobot(p.Name) then
            return true
        end
        p = p.Parent
    end
    return false
end

local function categoriaDeTexto(s)
    local m = string.match((tostring(s):gsub("%s", "")), "Scrap/%a+")
    if m and CAT_INDEX[m] then
        return m
    end
    return nil
end

local function leerCategorias()
    local map = {}
    local jy = ruta(Workspace, CONFIG.JUNKYARD)
    if not jy then return map end
    for k, v in pairs(jy:GetAttributes()) do
        local c = categoriaDeTexto(v)
        if c then
            map[tostring(k)] = CAT_INDEX[c]
        end
    end
    for _, ch in ipairs(jy:GetChildren()) do
        if ch:IsA("ValueBase") then
            local c = categoriaDeTexto(ch.Value)
            if c then
                map[ch.Name] = CAT_INDEX[c]
            end
        end
    end
    return map
end

local function posOf(obj)
    if obj:IsA("Model") then
        return obj:GetPivot().Position
    end
    return obj.Position
end

local function posPlot(p)
    if p:IsA("Model") then
        return p:GetPivot().Position
    end
    if p:IsA("BasePart") then
        return p.Position
    end
    local bp = p:FindFirstChildWhichIsA("BasePart", true)
    return bp and bp.Position
end

local function promptDe(obj)
    for _, d in ipairs(obj:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            return d
        end
    end
    return nil
end

local function obtenerRemote()
    local r = ruta(ReplicatedStorage, CONFIG.REMOTE_RUTA)
    return r and r:FindFirstChild(CONFIG.REMOTE_NOMBRE)
end

local function redondear(x)
    return math.floor(x * 10 + 0.5) / 10
end

---------------------------------------------------------------
-- ROBOTS (Client.Junkyard.fight.<mundo>, nombres Fighter...)
---------------------------------------------------------------
local function obtenerRobots(nombreMundo)
    local lista = {}
    local f = fightFolder(nombreMundo)
    if not f then return lista end
    for _, obj in ipairs(f:GetDescendants()) do
        if (obj:IsA("Model") or obj:IsA("BasePart"))
            and esRobot(obj.Name)
            and not dentroDeModelo(obj, f) then
            table.insert(lista, obj)
        end
    end
    return lista
end

local cacheRobots = {}
local function robotsDe(nombresMundo)
    local ahora = os.clock()
    local todos = {}
    for _, w in ipairs(nombresMundo) do
        local c = cacheRobots[w]
        if not c or ahora - c.t > 0.5 then
            c = { t = ahora, lista = obtenerRobots(w) }
            cacheRobots[w] = c
        end
        for _, r in ipairs(c.lista) do
            table.insert(todos, r)
        end
    end
    return todos
end

local function robotVivo(r)
    local h = r:FindFirstChildWhichIsA("Humanoid", true)
    return not (h and h.Health <= 0)
end

local function amenaza(pos, robots, anticipar)
    local now = os.clock()
    local best, bestD
    for _, r in ipairs(robots) do
        if r.Parent and robotVivo(r) then
            local d = (posOf(r) - pos).Magnitude
            local peligroAhora = d < S.peligro
            local acercandose = false

            if anticipar then
                local prev = memDist[r]
                memDist[r] = { d = d, t = now }
                if prev and now > prev.t and now - prev.t < 1 then
                    local v = (prev.d - d) / (now - prev.t)
                    if v > 0 and (d - S.peligro) / v < S.anticipo then
                        acercandose = true
                    end
                end
            end

            if (peligroAhora or acercandose) and (not bestD or d < bestD) then
                best, bestD = r, d
            end
        end
    end
    return best
end

---------------------------------------------------------------
-- PLOT DEL JUGADOR
---------------------------------------------------------------
local function buscarPlot()
    local num = LocalPlayer:GetAttribute("Plot")
    if num == nil then
        return nil, "No tienes el atributo Plot"
    end
    local n = tostring(num)
    local carpeta = ruta(Workspace, CONFIG.PLOTS)
    if not carpeta then
        return nil, "No encuentro Client.Plots"
    end
    for _, ch in ipairs(carpeta:GetChildren()) do
        if ch.Name == n or ch.Name == "Plot" .. n or ch.Name == "Plot_" .. n or ch.Name == "Plot " .. n then
            return ch
        end
    end
    for _, ch in ipairs(carpeta:GetChildren()) do
        for _, k in ipairs({ "Plot", "Number", "Id", "PlotNumber" }) do
            local v = ch:GetAttribute(k)
            if v ~= nil and tostring(v) == n then
                return ch
            end
        end
    end
    return nil, "No encuentro el plot " .. n
end

local function venderEnPlot(plot)
    local activados = 0
    for _, d in ipairs(plot:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            local txt = string.lower((d.ActionText or "") .. " " .. (d.ObjectText or ""))
            for _, p in ipairs(CONFIG.PALABRAS_VENTA) do
                if string.find(txt, p, 1, true) then
                    pcall(function()
                        d.RequiresLineOfSight = false
                        if d.MaxActivationDistance < 20 then
                            d.MaxActivationDistance = 20
                        end
                    end)
                    pcall(fireproximityprompt, d)
                    activados += 1
                    break
                end
            end
        end
    end
    return activados
end

local function mundosActivos()
    local l = {}
    for i, m in ipairs(CONFIG.MUNDOS) do
        if S.mundoOn[i] then
            table.insert(l, m.nombre)
        end
    end
    return l
end

---------------------------------------------------------------
-- ESCANEO
---------------------------------------------------------------
local function escanear()
    local root = getRoot()
    local miPos = root and root.Position or Vector3.zero
    local ahora = os.clock()
    local lista, vistos = {}, {}
    local conteo, conteoMundo, robotsMundo = {}, {}, {}
    for i = 1, SIN_CAT do conteo[i] = 0 end

    local catMap = leerCategorias()
    local remote = obtenerRemote()
    local diag = {
        carpetas = 0, carpetasTotal = #CONFIG.MUNDOS,
        piezas = 0, conPrompt = 0, sinPrompt = 0,
        categorizadas = 0, peligro = 0,
        remote = remote ~= nil, ejemplo = "ninguno",
    }

    for mi, m in ipairs(CONFIG.MUNDOS) do
        conteoMundo[mi] = 0
        local robots = robotsDe({ m.nombre })
        robotsMundo[mi] = #robots

        local carpeta = partsFolder(m.nombre)
        if carpeta then
            diag.carpetas += 1
            for _, obj in ipairs(carpeta:GetDescendants()) do
                local esPieza = (obj:IsA("Model") or obj:IsA("BasePart"))
                    and esJunk(obj.Name)
                    and not vistos[obj]
                    and not dentroDeModelo(obj, carpeta)

                if esPieza then
                    vistos[obj] = true
                    diag.piezas += 1
                    if diag.ejemplo == "ninguno" then
                        diag.ejemplo = obj.Name
                    end
                    conteoMundo[mi] += 1

                    if S.mundoOn[mi] then
                        local idx = catMap[obj.Name] or SIN_CAT
                        if idx ~= SIN_CAT then
                            diag.categorizadas += 1
                        end
                        conteo[idx] += 1

                        local prompt = promptDe(obj)
                        if prompt then
                            diag.conPrompt += 1
                        else
                            diag.sinPrompt += 1
                        end

                        local libre = not S.cooldown[obj] or S.cooldown[obj] <= ahora
                        if S.catOn[idx] and libre and (prompt or remote) then
                            local pos = posOf(obj)
                            if amenaza(pos, robots, false) then
                                diag.peligro += 1
                            else
                                table.insert(lista, {
                                    pieza = obj,
                                    idx = idx,
                                    mundo = m.nombre,
                                    dist = (pos - miPos).Magnitude,
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(lista, function(a, b)
        if a.idx ~= b.idx then
            return a.idx < b.idx
        end
        return a.dist < b.dist
    end)

    S.conteo = conteo
    S.conteoMundo = conteoMundo
    S.robotsMundo = robotsMundo
    S.visibles = #lista
    S.diag = diag
    return lista
end

---------------------------------------------------------------
-- MOVIMIENTO
---------------------------------------------------------------
local function deslizarA(destino, fnRobots)
    local t0 = os.clock()
    local robots, tRobots = {}, -1
    while not S.cerrado and (S.activo or S.ocupado) and os.clock() - t0 < CONFIG.TIMEOUT_VUELO do
        local root = getRoot()
        if not root then return false end
        local actual = root.Position

        if fnRobots then
            if os.clock() - tRobots > 0.15 then
                robots = fnRobots()
                tRobots = os.clock()
            end
            local r = amenaza(actual, robots, true)
            if r then
                root.AssemblyLinearVelocity = Vector3.zero
                return "peligro", r
            end
        end

        local delta = destino - actual
        local dist = delta.Magnitude
        if dist <= 1.5 then
            root.AssemblyLinearVelocity = Vector3.zero
            return true
        end

        local dt = RunService.Heartbeat:Wait()
        local paso = math.min(dist, S.velocidad * dt)
        local nuevo = actual + delta.Unit * paso

        root.AssemblyLinearVelocity = Vector3.zero
        root.CFrame = CFrame.new(nuevo) * (root.CFrame - root.CFrame.Position)
    end
    return false
end

local function esperarSeguro(seg, fnRobots)
    local t0 = os.clock()
    while os.clock() - t0 < seg and not S.cerrado and (S.activo or S.ocupado) do
        if fnRobots then
            local root = getRoot()
            if root then
                local r = amenaza(root.Position, fnRobots(), true)
                if r then
                    return "peligro", r
                end
            end
        end
        RunService.Heartbeat:Wait()
    end
    return true
end

local function evadir(fnRobots)
    S.huidas += 1
    S.estado = "¡Robot cerca! Evadiendo"
    log("Evadiendo robots")
    local t0 = os.clock()

    while not S.cerrado and (S.activo or S.ocupado) and os.clock() - t0 < CONFIG.TIEMPO_EVASION do
        local root = getRoot()
        if not root then return end
        local me = root.Position
        local robots = fnRobots and fnRobots() or {}

        local threat = amenaza(me, robots, true)
        if not threat then
            return
        end

        local esc = Vector3.zero
        for _, b in ipairs(robots) do
            if b.Parent and robotVivo(b) then
                local bp = posOf(b)
                local flat = Vector3.new(me.X - bp.X, 0, me.Z - bp.Z)
                local d = flat.Magnitude
                if d > 0.1 and d < S.peligro * 2 then
                    esc += flat.Unit * (S.peligro * 2 - d)
                end
            end
        end
        if esc.Magnitude < 0.1 then
            local tp = posOf(threat)
            esc = Vector3.new(me.X - tp.X, 0, me.Z - tp.Z)
            if esc.Magnitude < 0.1 then
                esc = Vector3.new(1, 0, 0)
            end
        end

        local dir = esc.Unit
        local dt = RunService.Heartbeat:Wait()
        local nuevo = me + dir * (S.velocidad * CONFIG.MULT_HUIDA * dt)
        root.AssemblyLinearVelocity = Vector3.zero
        root.CFrame = CFrame.new(nuevo) * (root.CFrame - root.CFrame.Position)
    end
end

---------------------------------------------------------------
-- RECOGIDA
---------------------------------------------------------------
local function recoger(pieza, fnRobots)
    local prompt = promptDe(pieza)
    local remote = (not prompt) and obtenerRemote() or nil
    if not prompt and not remote then
        log("Sin ProximityPrompt ni remote: " .. pieza.Name)
        return false
    end

    for _ = 1, S.intentos do
        if not pieza:IsDescendantOf(Workspace) then break end

        if prompt and prompt.Parent then
            pcall(function()
                prompt.RequiresLineOfSight = false
                if prompt.MaxActivationDistance < 20 then
                    prompt.MaxActivationDistance = 20
                end
            end)
            pcall(fireproximityprompt, prompt)
        elseif remote then
            pcall(function()
                if remote:IsA("RemoteFunction") then
                    remote:InvokeServer(pieza.Name)
                else
                    remote:FireServer(pieza.Name)
                end
            end)
        end

        local res = esperarSeguro(CONFIG.ESPERA_RECOGER, fnRobots)
        if res ~= true then
            return "peligro"
        end
    end

    return not pieza:IsDescendantOf(Workspace)
end

---------------------------------------------------------------
-- PLOT
---------------------------------------------------------------
local function irAPlot()
    local fnAll = function()
        return robotsDe(mundosActivos())
    end

    local plot, err = buscarPlot()
    if not plot then
        S.estado = err
        log(err)
        task.wait(2)
        return false
    end

    local pos = posPlot(plot)
    if not pos then
        S.estado = "El plot no tiene posición"
        log("El plot " .. plot.Name .. " no tiene posición")
        task.wait(2)
        return false
    end

    S.estado = "Lleno (" .. S.cargados .. "): yendo a tu plot " .. plot.Name
    local res = deslizarA(pos + Vector3.new(0, S.altura, 0), fnAll)
    if res == "peligro" then
        evadir(fnAll)
        return false
    end
    if res ~= true then
        log("No llegué al plot " .. plot.Name)
        return false
    end

    local n = venderEnPlot(plot)
    S.estado = "Vaciando en plot " .. plot.Name .. "..."
    log("Plot " .. plot.Name .. ": prompts de venta activados: " .. n)

    local esp = esperarSeguro(S.esperaPlot, fnAll)
    if esp ~= true then
        evadir(fnAll)
        return false
    end

    S.cargados = 0
    S.vaciados += 1
    S.estado = "Vaciado, volviendo a buscar"
    return true
end

---------------------------------------------------------------
-- CICLO PRINCIPAL
---------------------------------------------------------------
local function ciclo()
    if S.cargados >= S.maxJunk then
        if not irAPlot() then
            task.wait(0.3)
        end
        return
    end

    if #mundosActivos() == 0 then
        S.estado = "Activa al menos un mundo"
        task.wait(1)
        return
    end

    local lista = escanear()
    local obj = lista[1]
    if not obj then
        S.estado = "Esperando chatarra (respawn)..."
        task.wait(CONFIG.ESPERA_CICLO)
        return
    end

    local mundo = obj.mundo
    local fnFarm = function()
        return robotsDe({ mundo })
    end

    local nombre = CONFIG.CATEGORIAS[obj.idx].nombre
    S.estado = "Yendo a: " .. obj.pieza.Name .. " (" .. mundo .. ", " .. nombre .. ")"
    local destino = posOf(obj.pieza) + Vector3.new(0, S.altura, 0)

    local res = deslizarA(destino, fnFarm)
    if res == "peligro" then
        S.cooldown[obj.pieza] = os.clock() + CONFIG.COOLDOWN_PELIGRO
        evadir(fnFarm)
        return
    end
    if res ~= true then
        S.fallos += 1
        S.cooldown[obj.pieza] = os.clock() + CONFIG.COOLDOWN_FALLO
        S.estado = "No llegué, la salto"
        log("No llegó a " .. obj.pieza.Name)
        return
    end

    if esperarSeguro(S.retraso, fnFarm) ~= true then
        S.cooldown[obj.pieza] = os.clock() + CONFIG.COOLDOWN_PELIGRO
        evadir(fnFarm)
        return
    end

    S.estado = "Recogiendo: " .. obj.pieza.Name
    local rec = recoger(obj.pieza, fnFarm)
    if rec == "peligro" then
        S.cooldown[obj.pieza] = os.clock() + CONFIG.COOLDOWN_PELIGRO
        evadir(fnFarm)
        return
    end

    if rec then
        S.recogidas += 1
        S.cargados += 1
        S.estado = "Recogida: " .. obj.pieza.Name
        log("Recogida: " .. obj.pieza.Name .. " (" .. S.cargados .. "/" .. S.maxJunk .. ")")
    else
        S.fallos += 1
        S.cooldown[obj.pieza] = os.clock() + CONFIG.COOLDOWN_FALLO
        S.estado = "No se recogió"
        log("Falló: " .. obj.pieza.Name)
    end

    if esperarSeguro(S.retraso, fnFarm) ~= true then
        evadir(fnFarm)
    end
end

task.spawn(function()
    while not S.cerrado do
        if not S.activo then
            S.estado = "Apagado"
            task.wait(0.3)
        elseif not getRoot() then
            S.estado = "Esperando tu personaje..."
            task.wait(1)
        else
            ciclo()
        end
    end
end)

---------------------------------------------------------------
-- GOLPES
---------------------------------------------------------------
local function vigilarVida(char)
    local hum = char:WaitForChild("Humanoid", 10)
    if not hum then return end
    local last = hum.Health
    hum.HealthChanged:Connect(function(h)
        if h < last then
            S.golpes += 1
            if S.reiniciarGolpe then
                S.cargados = 0
            end
            S.estado = "¡Te golpearon!"
            log("Golpe recibido" .. (S.reiniciarGolpe and ": contador de Junk a 0" or ""))
        end
        last = h
    end)
end

if LocalPlayer.Character then
    task.spawn(vigilarVida, LocalPlayer.Character)
end
LocalPlayer.CharacterAdded:Connect(function(char)
    task.spawn(vigilarVida, char)
end)

local function probar()
    if S.activo or S.ocupado then
        log("Apaga el auto antes de probar")
        return
    end
    S.ocupado = true
    local lista = escanear()
    local obj = lista[1]
    if not obj then
        log("Prueba: no hay chatarra recogible")
    else
        log("Prueba: yendo a " .. obj.pieza:GetFullName())
        if deslizarA(posOf(obj.pieza) + Vector3.new(0, S.altura, 0), nil) == true then
            task.wait(S.retraso)
            log(recoger(obj.pieza, nil) == true and "Prueba: recogida OK" or "Prueba: no se recogió")
        else
            log("Prueba: no llegó a la pieza")
        end
    end
    S.ocupado = false
end

---------------------------------------------------------------
-- UI
---------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "MaykDev_Chatarra"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999999
gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local function corner(p, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r)
    c.Parent = p
end

local function stroke(p, col, t, tr)
    local s = Instance.new("UIStroke")
    s.Color = col
    s.Thickness = t or 1
    s.Transparency = tr or 0
    s.Parent = p
end

local function label(p, text, size, col, bold, align)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextSize = size
    l.TextColor3 = col
    l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    l.TextXAlignment = align or Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Center
    l.TextTruncate = Enum.TextTruncate.AtEnd
    l.Parent = p
    return l
end

local function btn(p, text, size, col, tsize)
    local b = Instance.new("TextButton")
    b.Size = size
    b.BackgroundColor3 = col
    b.Text = text
    b.TextColor3 = C.text
    b.TextSize = tsize or 13
    b.Font = Enum.Font.GothamBold
    b.BorderSizePixel = 0
    b.AutoButtonColor = true
    b.Parent = p
    corner(b, 10)
    return b
end

local function makeDraggable(handle, frame)
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
                end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseMovement) then
            local d = input.Position - startInput
            if not state.moved and d.Magnitude >= 6 then
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

-- Panel principal
local main = Instance.new("Frame")
main.Name = "Main"
main.AnchorPoint = Vector2.new(0.5, 0.5)
main.Position = UDim2.new(0.5, 0, 0.5, 0)
main.Size = UDim2.fromOffset(320, 460)
main.BackgroundColor3 = C.bg
main.BorderSizePixel = 0
main.ClipsDescendants = true
main.Parent = gui
corner(main, 18)
stroke(main, C.accent, 1, 0.45)

local uiScale = Instance.new("UIScale")
uiScale.Parent = main

local function ajustarEscala()
    local cam = Workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(800, 600)
    uiScale.Scale = math.clamp(math.min(vp.X * 0.94 / 320, vp.Y * 0.84 / 460), 0.5, 1)
end
ajustarEscala()
if Workspace.CurrentCamera then
    Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(ajustarEscala)
end

-- Cabecera con degradado
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 52)
header.BackgroundColor3 = C.card
header.BorderSizePixel = 0
header.Parent = main
corner(header, 18)

local headerGrad = Instance.new("UIGradient")
headerGrad.Color = ColorSequence.new(Color3.fromRGB(70, 84, 160), Color3.fromRGB(28, 31, 44))
headerGrad.Rotation = 20
headerGrad.Parent = header

local title = label(header, "♻️  Auto Chatarra", 16, C.text, true)
title.Position = UDim2.new(0, 16, 0, 8)
title.Size = UDim2.new(1, -110, 0, 20)

local sub = label(header, "MaykDev · Plot ?", 10, Color3.fromRGB(200, 205, 230), false)
sub.Position = UDim2.new(0, 16, 0, 29)
sub.Size = UDim2.new(1, -110, 0, 14)

local minBtn = btn(header, "—", UDim2.fromOffset(34, 34), Color3.fromRGB(255, 255, 255), 15)
minBtn.BackgroundTransparency = 0.85
minBtn.Position = UDim2.new(1, -80, 0, 9)
local closeBtn = btn(header, "✕", UDim2.fromOffset(34, 34), C.red, 13)
closeBtn.Position = UDim2.new(1, -40, 0, 9)

-- Interruptor grande
local toggle = btn(main, "○  APAGADO", UDim2.new(1, -24, 0, 46), C.track, 15)
toggle.Position = UDim2.new(0, 12, 0, 62)
toggle.Activated:Connect(function()
    S.activo = not S.activo
    S.estado = S.activo and "Buscando chatarra..." or "Apagado"
end)

-- Tarjeta de estado
local estadoCard = Instance.new("Frame")
estadoCard.Position = UDim2.new(0, 12, 0, 116)
estadoCard.Size = UDim2.new(1, -24, 0, 30)
estadoCard.BackgroundColor3 = C.card
estadoCard.BorderSizePixel = 0
estadoCard.Parent = main
corner(estadoCard, 10)

local estadoLbl = label(estadoCard, "Listo", 11, C.muted, false)
estadoLbl.Position = UDim2.new(0, 12, 0, 0)
estadoLbl.Size = UDim2.new(1, -24, 1, 0)

-- Fichas con contadores
local chipsRow = Instance.new("Frame")
chipsRow.Position = UDim2.new(0, 12, 0, 154)
chipsRow.Size = UDim2.new(1, -24, 0, 50)
chipsRow.BackgroundTransparency = 1
chipsRow.Parent = main

local chipsLayout = Instance.new("UIListLayout")
chipsLayout.FillDirection = Enum.FillDirection.Horizontal
chipsLayout.Padding = UDim.new(0, 4)
chipsLayout.SortOrder = Enum.SortOrder.LayoutOrder
chipsLayout.Parent = chipsRow

local chipVals = {}
local function chip(orden, texto, key)
    local f = Instance.new("Frame")
    f.LayoutOrder = orden
    f.Size = UDim2.new(0.2, -4, 1, 0)
    f.BackgroundColor3 = C.card
    f.BorderSizePixel = 0
    f.Parent = chipsRow
    corner(f, 10)

    local v = label(f, "0", 13, C.accent, true, Enum.TextXAlignment.Center)
    v.Position = UDim2.new(0, 0, 0, 6)
    v.Size = UDim2.new(1, 0, 0, 20)

    local c = label(f, texto, 8, C.muted, true, Enum.TextXAlignment.Center)
    c.Position = UDim2.new(0, 0, 0, 28)
    c.Size = UDim2.new(1, 0, 0, 14)

    chipVals[key] = v
end
chip(1, "CARGADOS", "cargados")
chip(2, "RECOGIDAS", "recogidas")
chip(3, "VACIADOS", "vaciados")
chip(4, "HUIDAS", "huidas")
chip(5, "GOLPES", "golpes")

-- Página con desplegables
local page = Instance.new("ScrollingFrame")
page.Position = UDim2.new(0, 12, 0, 214)
page.Size = UDim2.new(1, -24, 1, -226)
page.BackgroundTransparency = 1
page.BorderSizePixel = 0
page.ScrollBarThickness = 3
page.ScrollBarImageColor3 = C.accent
page.CanvasSize = UDim2.new(0, 0, 0, 0)
page.AutomaticCanvasSize = Enum.AutomaticSize.Y
page.Parent = main

local pageLayout = Instance.new("UIListLayout")
pageLayout.Padding = UDim.new(0, 8)
pageLayout.SortOrder = Enum.SortOrder.LayoutOrder
pageLayout.Parent = page

local pagePad = Instance.new("UIPadding")
pagePad.PaddingBottom = UDim.new(0, 12)
pagePad.Parent = page

-- Desplegable: encabezado con título, resumen y flecha. El cuerpo se abre al tocar.
local function desplegable(orden, icono, titulo)
    local cont = Instance.new("Frame")
    cont.LayoutOrder = orden
    cont.Size = UDim2.new(1, 0, 0, 46)
    cont.AutomaticSize = Enum.AutomaticSize.Y
    cont.BackgroundColor3 = C.card
    cont.BorderSizePixel = 0
    cont.Parent = page
    corner(cont, 12)

    local cl = Instance.new("UIListLayout")
    cl.SortOrder = Enum.SortOrder.LayoutOrder
    cl.Parent = cont

    local enc = Instance.new("TextButton")
    enc.LayoutOrder = 1
    enc.Size = UDim2.new(1, 0, 0, 46)
    enc.BackgroundTransparency = 1
    enc.Text = ""
    enc.AutoButtonColor = false
    enc.Parent = cont

    local tit = label(enc, icono .. "  " .. titulo, 13, C.text, true)
    tit.Position = UDim2.new(0, 14, 0, 0)
    tit.Size = UDim2.new(1, -130, 1, 0)

    local res = label(enc, "", 11, C.accent, true, Enum.TextXAlignment.Right)
    res.Position = UDim2.new(1, -110, 0, 0)
    res.Size = UDim2.new(0, 76, 1, 0)

    local flecha = label(enc, "▾", 16, C.muted, true, Enum.TextXAlignment.Center)
    flecha.Position = UDim2.new(1, -30, 0, 0)
    flecha.Size = UDim2.new(0, 24, 1, 0)

    local cuerpo = Instance.new("Frame")
    cuerpo.LayoutOrder = 2
    cuerpo.Size = UDim2.new(1, 0, 0, 0)
    cuerpo.AutomaticSize = Enum.AutomaticSize.Y
    cuerpo.BackgroundTransparency = 1
    cuerpo.Visible = false
    cuerpo.Parent = cont

    local lay = Instance.new("UIListLayout")
    lay.Padding = UDim.new(0, 6)
    lay.SortOrder = Enum.SortOrder.LayoutOrder
    lay.Parent = cuerpo

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 8)
    pad.PaddingRight = UDim.new(0, 8)
    pad.PaddingBottom = UDim.new(0, 10)
    pad.Parent = cuerpo

    local abierto = false
    enc.Activated:Connect(function()
        abierto = not abierto
        cuerpo.Visible = abierto
        flecha.Text = abierto and "▴" or "▾"
    end)

    return { cuerpo = cuerpo, resumen = res }
end

-- Fila dentro de un desplegable: punto de color, nombre, contador y casilla
local function fila(parent, orden, color, nombreTxt, onClick)
    local f = Instance.new("TextButton")
    f.LayoutOrder = orden
    f.Size = UDim2.new(1, 0, 0, 40)
    f.BackgroundColor3 = C.row
    f.BorderSizePixel = 0
    f.Text = ""
    f.AutoButtonColor = false
    f.Parent = parent
    corner(f, 10)

    local dot = Instance.new("Frame")
    dot.Size = UDim2.fromOffset(10, 10)
    dot.Position = UDim2.new(0, 12, 0.5, -5)
    dot.BackgroundColor3 = color
    dot.BorderSizePixel = 0
    dot.Parent = f
    corner(dot, 5)

    local nombre = label(f, nombreTxt, 12, C.text, true)
    nombre.Position = UDim2.new(0, 30, 0, 0)
    nombre.Size = UDim2.new(1, -90, 1, 0)

    local cuenta = label(f, "0", 11, C.muted, true, Enum.TextXAlignment.Right)
    cuenta.Position = UDim2.new(1, -60, 0, 0)
    cuenta.Size = UDim2.new(0, 28, 1, 0)

    local box = Instance.new("Frame")
    box.Size = UDim2.fromOffset(20, 20)
    box.Position = UDim2.new(1, -28, 0.5, -10)
    box.BorderSizePixel = 0
    box.Parent = f
    corner(box, 6)

    local tick = label(box, "✓", 13, C.text, true, Enum.TextXAlignment.Center)
    tick.Size = UDim2.new(1, 0, 1, 0)

    if onClick then
        f.Activated:Connect(onClick)
    end

    return { cuenta = cuenta, box = box, tick = tick }
end

-- Fila de ajuste numérico con botones − y +
local steppers = {}
local function stepper(body, orden, nombreTxt, cfg, key, fmt)
    local row = Instance.new("Frame")
    row.LayoutOrder = orden
    row.Size = UDim2.new(1, 0, 0, 44)
    row.BackgroundColor3 = C.row
    row.BorderSizePixel = 0
    row.Parent = body
    corner(row, 10)

    local lbl = label(row, "", 12, C.text, true)
    lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.Size = UDim2.new(1, -120, 1, 0)

    local menos = btn(row, "−", UDim2.fromOffset(40, 32), C.track, 18)
    menos.Position = UDim2.new(1, -96, 0.5, -16)
    local mas = btn(row, "+", UDim2.fromOffset(40, 32), C.track, 18)
    mas.Position = UDim2.new(1, -48, 0.5, -16)

    menos.Activated:Connect(function()
        S[key] = math.clamp(redondear(S[key] - cfg.paso), cfg.min, cfg.max)
    end)
    mas.Activated:Connect(function()
        S[key] = math.clamp(redondear(S[key] + cfg.paso), cfg.min, cfg.max)
    end)

    steppers[#steppers + 1] = {
        refresh = function()
            lbl.Text = nombreTxt .. ": " .. fmt(S[key])
        end,
    }
end

---------------------------------------------------------------
-- DESPLEGABLE: MUNDOS
---------------------------------------------------------------
local dMundos = desplegable(1, "🌍", "Mundos")
local filasMundo = {}
for i, m in ipairs(CONFIG.MUNDOS) do
    filasMundo[i] = fila(dMundos.cuerpo, i, m.color, m.nombre, function()
        S.mundoOn[i] = not S.mundoOn[i]
        S.estado = (S.mundoOn[i] and "Farmeando " or "Sin farmear ") .. m.nombre
    end)
end

---------------------------------------------------------------
-- DESPLEGABLE: CATEGORÍAS
---------------------------------------------------------------
local dCat = desplegable(2, "📦", "Categorías")
local filasCat = {}
for i, cat in ipairs(CONFIG.CATEGORIAS) do
    filasCat[i] = fila(dCat.cuerpo, i, cat.color, cat.nombre, function()
        S.catOn[i] = not S.catOn[i]
        S.estado = (S.catOn[i] and "Activada: " or "Desactivada: ") .. cat.nombre
    end)
end

---------------------------------------------------------------
-- DESPLEGABLE: AJUSTES
---------------------------------------------------------------
local dAjustes = desplegable(3, "⚙️", "Ajustes")
stepper(dAjustes.cuerpo, 1, "Máximo de Junk", CONFIG.MAX_JUNK, "maxJunk", function(v) return string.format("%d", v) end)
stepper(dAjustes.cuerpo, 2, "Espera en plot", CONFIG.ESPERA_PLOT, "esperaPlot", function(v) return string.format("%d s", v) end)
stepper(dAjustes.cuerpo, 3, "Distancia a robots", CONFIG.PELIGRO, "peligro", function(v) return string.format("%d st", v) end)
stepper(dAjustes.cuerpo, 4, "Anticipo robot", CONFIG.ANTICIPO, "anticipo", function(v) return string.format("%.1f s", v) end)
stepper(dAjustes.cuerpo, 5, "Velocidad", CONFIG.VELOCIDAD, "velocidad", function(v) return string.format("%d/s", v) end)
stepper(dAjustes.cuerpo, 6, "Retraso", CONFIG.RETRASO, "retraso", function(v) return string.format("%.1f s", v) end)
stepper(dAjustes.cuerpo, 7, "Altura", CONFIG.ALTURA, "altura", function(v) return string.format("%d st", v) end)
stepper(dAjustes.cuerpo, 8, "Intentos", CONFIG.INTENTOS, "intentos", function(v) return string.format("%d", v) end)

local filaReinicio = fila(dAjustes.cuerpo, 9, C.red, "Golpe: contador de Junk a 0", function()
    S.reiniciarGolpe = not S.reiniciarGolpe
    S.estado = S.reiniciarGolpe and "Reinicio por golpe: activado" or "Reinicio por golpe: desactivado"
end)

---------------------------------------------------------------
-- DESPLEGABLE: DIAGNÓSTICO
---------------------------------------------------------------
local dDiag = desplegable(4, "🧪", "Diagnóstico")

local botonesRow = Instance.new("Frame")
botonesRow.LayoutOrder = 1
botonesRow.Size = UDim2.new(1, 0, 0, 38)
botonesRow.BackgroundTransparency = 1
botonesRow.Parent = dDiag.cuerpo

local botonesLayout = Instance.new("UIListLayout")
botonesLayout.FillDirection = Enum.FillDirection.Horizontal
botonesLayout.Padding = UDim.new(0, 6)
botonesLayout.SortOrder = Enum.SortOrder.LayoutOrder
botonesLayout.Parent = botonesRow

local probarBtn = btn(botonesRow, "Probar 1", UDim2.new(0.5, -3, 1, 0), C.accent, 12)
probarBtn.LayoutOrder = 1
probarBtn.Activated:Connect(function()
    task.spawn(probar)
end)

local escanearBtn = btn(botonesRow, "Escanear", UDim2.new(0.5, -3, 1, 0), C.track, 12)
escanearBtn.LayoutOrder = 2
escanearBtn.Activated:Connect(function()
    escanear()
    log("Escaneo manual terminado")
end)

local diagCard = Instance.new("Frame")
diagCard.LayoutOrder = 2
diagCard.Size = UDim2.new(1, 0, 0, 0)
diagCard.AutomaticSize = Enum.AutomaticSize.Y
diagCard.BackgroundColor3 = C.row
diagCard.BorderSizePixel = 0
diagCard.Parent = dDiag.cuerpo
corner(diagCard, 10)

local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 10)
pad.PaddingRight = UDim.new(0, 10)
pad.PaddingTop = UDim.new(0, 8)
pad.PaddingBottom = UDim.new(0, 8)
pad.Parent = diagCard

local diagLbl = Instance.new("TextLabel")
diagLbl.BackgroundTransparency = 1
diagLbl.Size = UDim2.new(1, 0, 0, 0)
diagLbl.AutomaticSize = Enum.AutomaticSize.Y
diagLbl.TextWrapped = true
diagLbl.TextXAlignment = Enum.TextXAlignment.Left
diagLbl.TextYAlignment = Enum.TextYAlignment.Top
diagLbl.TextSize = 10
diagLbl.TextColor3 = C.muted
diagLbl.Font = Enum.Font.Gotham
diagLbl.Text = ""
diagLbl.Parent = diagCard

---------------------------------------------------------------
-- MINIMIZAR / BURBUJA
---------------------------------------------------------------
local bubble = btn(gui, "♻️", UDim2.fromOffset(54, 54), C.card, 22)
bubble.Visible = false
stroke(bubble, C.accent, 1, 0.3)

local mainDrag = makeDraggable(header, main)
local bubbleDrag = makeDraggable(bubble, bubble)

minBtn.Activated:Connect(function()
    bubble.Position = UDim2.fromOffset(main.AbsolutePosition.X, main.AbsolutePosition.Y)
    main.Visible = false
    bubble.Visible = true
end)

bubble.Activated:Connect(function()
    if bubbleDrag.moved then return end
    bubble.Visible = false
    main.Visible = true
end)

closeBtn.Activated:Connect(function()
    S.cerrado = true
    S.activo = false
    gui:Destroy()
end)

---------------------------------------------------------------
-- REFRESCO DE LA UI
---------------------------------------------------------------
local function refrescar()
    toggle.Text = S.activo and "●  ENCENDIDO" or "○  APAGADO"
    toggle.BackgroundColor3 = S.activo and C.green or C.track
    estadoLbl.Text = S.estado
    sub.Text = "MaykDev · Plot " .. tostring(LocalPlayer:GetAttribute("Plot") or "?")

    chipVals.cargados.Text = S.cargados .. "/" .. S.maxJunk
    chipVals.recogidas.Text = tostring(S.recogidas)
    chipVals.vaciados.Text = tostring(S.vaciados)
    chipVals.huidas.Text = tostring(S.huidas)
    chipVals.golpes.Text = tostring(S.golpes)

    local nMundos = 0
    for i, f in ipairs(filasMundo) do
        f.cuenta.Text = tostring(S.conteoMundo[i] or 0)
        f.box.BackgroundColor3 = S.mundoOn[i] and C.green or C.track
        f.tick.Visible = S.mundoOn[i]
        if S.mundoOn[i] then nMundos += 1 end
    end
    dMundos.resumen.Text = nMundos .. "/" .. #CONFIG.MUNDOS .. " activos"

    local nCat = 0
    for i, f in ipairs(filasCat) do
        f.cuenta.Text = tostring(S.conteo[i] or 0)
        f.box.BackgroundColor3 = S.catOn[i] and C.green or C.track
        f.tick.Visible = S.catOn[i]
        if S.catOn[i] then nCat += 1 end
    end
    dCat.resumen.Text = nCat .. "/" .. #CONFIG.CATEGORIAS .. " activas"

    filaReinicio.box.BackgroundColor3 = S.reiniciarGolpe and C.green or C.track
    filaReinicio.tick.Visible = S.reiniciarGolpe
    dAjustes.resumen.Text = "Máx " .. S.maxJunk

    for _, s in ipairs(steppers) do
        s.refresh()
    end

    local plot, errPlot = buscarPlot()
    local d = S.diag
    local robotsTxt = {}
    for i, m in ipairs(CONFIG.MUNDOS) do
        table.insert(robotsTxt, m.nombre .. " " .. (S.robotsMundo[i] or 0))
    end

    diagLbl.Text = string.format(
        "Carpetas de mundo: %d de %d\n" ..
        "Piezas Junk: %d · con categoría: %d\n" ..
        "Con prompt: %d · sin prompt: %d\n" ..
        "Descartadas por robot: %d\n" ..
        "Robots %s*: %s\n" ..
        "Remote %s: %s\n" ..
        "Tu plot: %s\n" ..
        "Primera pieza: %s\n\n" ..
        "Últimos eventos:\n%s",
        d.carpetas or 0, d.carpetasTotal or #CONFIG.MUNDOS,
        d.piezas or 0, d.categorizadas or 0,
        d.conPrompt or 0, d.sinPrompt or 0,
        d.peligro or 0,
        CONFIG.ROBOT_PREFIJO, table.concat(robotsTxt, " · "),
        CONFIG.REMOTE_NOMBRE, (d.remote and "encontrado" or "no encontrado"),
        plot and plot.Name or (errPlot or "sin datos"),
        d.ejemplo or "ninguno",
        #S.log > 0 and table.concat(S.log, "\n") or "(sin eventos todavía)"
    )
end

task.spawn(function()
    while not S.cerrado do
        if not S.activo and not S.ocupado then
            escanear()
        end
        refrescar()
        task.wait(1)
    end
end)

refrescar()
