-- MaykDev · Auto Chatarra v5 (LocalScript · móvil)
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
    -- Mundos: piezas en Client.Junkyard.<mundo>.Spawn.Parts y robots en Client.Junkyard.fight.<mundo>
    MUNDOS = {
        { nombre = "Space",     color = Color3.fromRGB(170, 120, 255) },
        { nombre = "Heaven",    color = Color3.fromRGB(120, 220, 255) },
        { nombre = "Overworld", color = Color3.fromRGB(240, 200, 120) },
    },
    JUNKYARD = { "Server", "Junkyard" },   -- atributos: nombre de la pieza -> "Scrap/..."
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
    PELIGRO        = { ini = 25, min = 8, max = 80, paso = 5 }, -- distancia a robots que activa la huida
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
    estado = "Listo",
    diag = {},
    log = {},
}
for i = 1, SIN_CAT do S.conteo[i] = 0 end
for i = 1, #CONFIG.MUNDOS do
    S.conteoMundo[i] = 0
    S.robotsMundo[i] = 0
end

local C = {
    bg = Color3.fromRGB(16, 18, 26),
    card = Color3.fromRGB(28, 31, 44),
    track = Color3.fromRGB(44, 48, 66),
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

-- true si el objeto está dentro de otro Model que a su vez está dentro de "carpeta"
local function dentroDeModelo(obj, carpeta)
    local p = obj.Parent
    while p and p ~= carpeta do
        if p:IsA("Model") or esJunk(p.Name) then
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
-- ROBOTS (Client.Junkyard.fight.<mundo>)
---------------------------------------------------------------
local function obtenerRobots(nombreMundo)
    local lista = {}
    local f = fightFolder(nombreMundo)
    if not f then return lista end
    for _, obj in ipairs(f:GetDescendants()) do
        if (obj:IsA("Model") or obj:IsA("BasePart")) and not dentroDeModelo(obj, f) then
            table.insert(lista, obj)
        end
    end
    return lista
end

-- Cache por mundo para no recorrer la carpeta en cada frame
local cacheRobots = {}
local function robotsDe(nombresMundo)
    local ahora = os.clock()
    local todos = {}
    for _, w in ipairs(nombresMundo) do
        local c = cacheRobots[w]
        if not c or ahora - c.t > 0.3 then
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

-- Devuelve el robot vivo más cercano que esté dentro del radio de peligro, o nil
local function amenaza(pos, robots)
    local best, bd
    for _, r in ipairs(robots) do
        if r.Parent and robotVivo(r) then
            local d = (posOf(r) - pos).Magnitude
            if d < S.peligro and (not bd or d < bd) then
                best, bd = r, d
            end
        end
    end
    return best
end

---------------------------------------------------------------
-- PLOT DEL JUGADOR (atributo "Plot" = número)
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

---------------------------------------------------------------
-- ESCANEO: piezas Junk de los mundos activos, sin las cercanas a robots
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
                            if amenaza(pos, robots) then
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
-- MOVIMIENTO SUAVE
--   fnRobots (opcional): función que devuelve los robots a evitar.
--   Devuelve true (llegó), false (falló) o "peligro", robot (hay un robot cerca)
---------------------------------------------------------------
local function deslizarA(destino, fnRobots)
    local t0 = os.clock()
    local robots, tRobots = {}, -1
    while not S.cerrado and (S.activo or S.ocupado) and os.clock() - t0 < CONFIG.TIMEOUT_VUELO do
        local root = getRoot()
        if not root then return false end

        local actual = root.Position

        if fnRobots and os.clock() - tRobots > 0.2 then
            robots = fnRobots()
            tRobots = os.clock()
        end
        if fnRobots then
            local r = amenaza(actual, robots)
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

-- Se aleja del robot en dirección contraria, hasta quedar fuera del radio de peligro
local function huirDe(robot)
    local root = getRoot()
    if not root then return end
    local me = root.Position
    local rp = posOf(robot)
    local dir = Vector3.new(me.X - rp.X, 0, me.Z - rp.Z)
    if dir.Magnitude < 0.5 then
        dir = Vector3.new(1, 0, 0)
    end
    local dest = me + dir.Unit * (S.peligro + 10)
    S.huidas += 1
    S.estado = "Robot cerca: me alejo"
    log("Me alejo de " .. robot.Name)
    deslizarA(Vector3.new(dest.X, me.Y, dest.Z), nil)
end

---------------------------------------------------------------
-- RECOGIDA
---------------------------------------------------------------
local function recoger(pieza)
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
        task.wait(CONFIG.ESPERA_RECOGER)
    end

    return not pieza:IsDescendantOf(Workspace)
end

---------------------------------------------------------------
-- IR AL PLOT Y VACIAR
---------------------------------------------------------------
local function irAPlot()
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
    if deslizarA(pos + Vector3.new(0, S.altura, 0), nil) ~= true then
        log("No llegué al plot " .. plot.Name)
        return false
    end

    local n = venderEnPlot(plot)
    S.estado = "Vaciando en plot " .. plot.Name .. "..."
    log("Plot " .. plot.Name .. ": prompts de venta activados: " .. n)
    task.wait(S.esperaPlot)

    S.cargados = 0
    S.vaciados += 1
    S.estado = "Vaciado, volviendo a buscar"
    return true
end

---------------------------------------------------------------
-- CICLO PRINCIPAL
---------------------------------------------------------------
local function mundosActivos()
    local l = {}
    for i, m in ipairs(CONFIG.MUNDOS) do
        if S.mundoOn[i] then
            table.insert(l, m.nombre)
        end
    end
    return l
end

local function ciclo()
    if S.cargados >= S.maxJunk then
        if not irAPlot() then
            task.wait(1)
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

    local nombre = CONFIG.CATEGORIAS[obj.idx].nombre
    S.estado = "Yendo a: " .. obj.pieza.Name .. " (" .. obj.mundo .. ", " .. nombre .. ")"
    local destino = posOf(obj.pieza) + Vector3.new(0, S.altura, 0)

    local res, robot = deslizarA(destino, function()
        return robotsDe({ obj.mundo })
    end)

    if res == "peligro" then
        S.cooldown[obj.pieza] = os.clock() + CONFIG.COOLDOWN_PELIGRO
        huirDe(robot)
        return
    end

    if res ~= true then
        S.fallos += 1
        S.cooldown[obj.pieza] = os.clock() + CONFIG.COOLDOWN_FALLO
        S.estado = "No llegué, la salto"
        log("No llegó a " .. obj.pieza.Name)
        return
    end

    task.wait(S.retraso)
    S.estado = "Recogiendo: " .. obj.pieza.Name
    if recoger(obj.pieza) then
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
    task.wait(S.retraso)
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

-- Prueba manual: va a una sola pieza y la intenta recoger (con el auto apagado)
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
            log(recoger(obj.pieza) and "Prueba: recogida OK" or "Prueba: no se recogió")
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

local main = Instance.new("Frame")
main.Name = "Main"
main.AnchorPoint = Vector2.new(0.5, 0.5)
main.Position = UDim2.new(0.5, 0, 0.5, 0)
main.Size = UDim2.fromOffset(320, 440)
main.BackgroundColor3 = C.bg
main.BorderSizePixel = 0
main.ClipsDescendants = true
main.Parent = gui
corner(main, 16)
stroke(main, C.accent, 1, 0.4)

local uiScale = Instance.new("UIScale")
uiScale.Parent = main

local function ajustarEscala()
    local cam = Workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(800, 600)
    uiScale.Scale = math.clamp(math.min(vp.X * 0.94 / 320, vp.Y * 0.82 / 440), 0.5, 1)
end
ajustarEscala()
if Workspace.CurrentCamera then
    Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(ajustarEscala)
end

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 46)
header.BackgroundColor3 = C.card
header.BorderSizePixel = 0
header.Parent = main
corner(header, 16)

local title = label(header, "♻️ Auto Chatarra", 15, C.text, true)
title.Position = UDim2.new(0, 14, 0, 5)
title.Size = UDim2.new(1, -100, 0, 18)

local sub = label(header, "MaykDev", 10, C.muted, false)
sub.Position = UDim2.new(0, 14, 0, 24)
sub.Size = UDim2.new(1, -100, 0, 14)

local minBtn = btn(header, "—", UDim2.fromOffset(38, 34), C.track, 15)
minBtn.Position = UDim2.new(1, -84, 0, 6)
local closeBtn = btn(header, "✕", UDim2.fromOffset(38, 34), C.red, 13)
closeBtn.Position = UDim2.new(1, -42, 0, 6)

local tabRow = Instance.new("Frame")
tabRow.Position = UDim2.new(0, 10, 0, 52)
tabRow.Size = UDim2.new(1, -20, 0, 34)
tabRow.BackgroundTransparency = 1
tabRow.Parent = main

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 4)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Parent = tabRow

local tabNombres = { "Principal", "Ajustes", "Diagnóstico" }
local tabBtns, pages = {}, {}
for i, nombre in ipairs(tabNombres) do
    local b = btn(tabRow, nombre, UDim2.new(1 / #tabNombres, -4, 1, 0), C.card, 12)
    b.LayoutOrder = i
    tabBtns[i] = b
end

local function mostrarPestana(idx)
    for i, p in ipairs(pages) do
        p.Visible = (i == idx)
    end
    for i, b in ipairs(tabBtns) do
        b.BackgroundColor3 = (i == idx) and C.accent or C.card
    end
end

local function nuevaPagina()
    local p = Instance.new("ScrollingFrame")
    p.Position = UDim2.new(0, 10, 0, 94)
    p.Size = UDim2.new(1, -20, 0, 336)
    p.BackgroundTransparency = 1
    p.BorderSizePixel = 0
    p.ScrollBarThickness = 4
    p.ScrollBarImageColor3 = C.accent
    p.CanvasSize = UDim2.new(0, 0, 0, 0)
    p.AutomaticCanvasSize = Enum.AutomaticSize.Y
    p.Visible = false
    p.Parent = main

    local l = Instance.new("UIListLayout")
    l.Padding = UDim.new(0, 8)
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Parent = p

    table.insert(pages, p)
    return p
end

for i, b in ipairs(tabBtns) do
    b.Activated:Connect(function()
        mostrarPestana(i)
    end)
end

local pagPrincipal = nuevaPagina()
local pagAjustes = nuevaPagina()
local pagDiag = nuevaPagina()

-- Fila con punto de color, nombre, contador y casilla
local function filaCheck(parent, orden, color, nombreTxt, onClick)
    local fila = Instance.new("TextButton")
    fila.LayoutOrder = orden
    fila.Size = UDim2.new(1, -4, 0, 44)
    fila.BackgroundColor3 = C.card
    fila.BorderSizePixel = 0
    fila.Text = ""
    fila.AutoButtonColor = false
    fila.Parent = parent
    corner(fila, 10)

    local dot = Instance.new("Frame")
    dot.Size = UDim2.fromOffset(12, 12)
    dot.Position = UDim2.new(0, 14, 0.5, -6)
    dot.BackgroundColor3 = color
    dot.BorderSizePixel = 0
    dot.Parent = fila
    corner(dot, 6)

    local nombre = label(fila, nombreTxt, 13, C.text, true)
    nombre.Position = UDim2.new(0, 36, 0, 0)
    nombre.Size = UDim2.new(1, -100, 1, 0)

    local cuenta = label(fila, "0", 12, C.muted, true, Enum.TextXAlignment.Right)
    cuenta.Position = UDim2.new(1, -66, 0, 0)
    cuenta.Size = UDim2.new(0, 32, 1, 0)

    local box = Instance.new("Frame")
    box.Size = UDim2.fromOffset(22, 22)
    box.Position = UDim2.new(1, -30, 0.5, -11)
    box.BorderSizePixel = 0
    box.Parent = fila
    corner(box, 6)

    local tick = label(box, "✓", 14, C.text, true, Enum.TextXAlignment.Center)
    tick.Size = UDim2.new(1, 0, 1, 0)

    if onClick then
        fila.Activated:Connect(onClick)
    end

    return { cuenta = cuenta, box = box, tick = tick }
end

local function seccion(parent, orden, texto)
    local l = label(parent, texto, 10, C.muted, true)
    l.LayoutOrder = orden
    l.Size = UDim2.new(1, -4, 0, 16)
    return l
end

---------------------------------------------------------------
-- PESTAÑA PRINCIPAL
---------------------------------------------------------------
local toggle = btn(pagPrincipal, "○ APAGADO", UDim2.new(1, -4, 0, 50), C.track, 14)
toggle.LayoutOrder = 1
toggle.Activated:Connect(function()
    S.activo = not S.activo
    S.estado = S.activo and "Buscando chatarra..." or "Apagado"
end)

local estadoLbl = label(pagPrincipal, "Listo", 11, C.muted, false)
estadoLbl.LayoutOrder = 2
estadoLbl.Size = UDim2.new(1, -4, 0, 20)

seccion(pagPrincipal, 3, "MUNDOS · toca para farmear o no")

local filasMundo = {}
for i, m in ipairs(CONFIG.MUNDOS) do
    filasMundo[i] = filaCheck(pagPrincipal, 3 + i, m.color, m.nombre, function()
        S.mundoOn[i] = not S.mundoOn[i]
        S.estado = (S.mundoOn[i] and "Farmeando " or "Sin farmear ") .. m.nombre
    end)
end

seccion(pagPrincipal, 7, "PIEZAS · primero las de mayor valor")

local filasCat = {}
for i, cat in ipairs(CONFIG.CATEGORIAS) do
    filasCat[i] = filaCheck(pagPrincipal, 7 + i, cat.color, cat.nombre, function()
        S.catOn[i] = not S.catOn[i]
        S.estado = (S.catOn[i] and "Activada: " or "Desactivada: ") .. cat.nombre
    end)
end

local statCard = Instance.new("Frame")
statCard.LayoutOrder = 20
statCard.Size = UDim2.new(1, -4, 0, 40)
statCard.BackgroundColor3 = C.card
statCard.BorderSizePixel = 0
statCard.Parent = pagPrincipal
corner(statCard, 10)

local statLbl = label(statCard, "", 11, C.muted, false)
statLbl.Position = UDim2.new(0, 12, 0, 0)
statLbl.Size = UDim2.new(1, -24, 1, 0)

---------------------------------------------------------------
-- PESTAÑA AJUSTES
---------------------------------------------------------------
local steppers = {}

local function stepper(orden, nombreTxt, cfg, key, fmt)
    local row = Instance.new("Frame")
    row.LayoutOrder = orden
    row.Size = UDim2.new(1, -4, 0, 52)
    row.BackgroundColor3 = C.card
    row.BorderSizePixel = 0
    row.Parent = pagAjustes
    corner(row, 10)

    local lbl = label(row, "", 12, C.text, true)
    lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.Size = UDim2.new(1, -130, 1, 0)

    local menos = btn(row, "−", UDim2.fromOffset(48, 40), C.track, 20)
    menos.Position = UDim2.new(1, -110, 0.5, -20)
    local mas = btn(row, "+", UDim2.fromOffset(48, 40), C.track, 20)
    mas.Position = UDim2.new(1, -56, 0.5, -20)

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

stepper(1, "Máximo de Junk", CONFIG.MAX_JUNK, "maxJunk", function(v) return string.format("%d piezas", v) end)
stepper(2, "Espera en plot", CONFIG.ESPERA_PLOT, "esperaPlot", function(v) return string.format("%d s", v) end)
stepper(3, "Distancia a robots", CONFIG.PELIGRO, "peligro", function(v) return string.format("%d studs", v) end)
stepper(4, "Velocidad", CONFIG.VELOCIDAD, "velocidad", function(v) return string.format("%d studs/s", v) end)
stepper(5, "Retraso", CONFIG.RETRASO, "retraso", function(v) return string.format("%.1f s", v) end)
stepper(6, "Altura", CONFIG.ALTURA, "altura", function(v) return string.format("%d studs", v) end)
stepper(7, "Intentos", CONFIG.INTENTOS, "intentos", function(v) return string.format("%d", v) end)

---------------------------------------------------------------
-- PESTAÑA DIAGNÓSTICO
---------------------------------------------------------------
local probarBtn = btn(pagDiag, "🧪 Probar 1 pieza", UDim2.new(1, -4, 0, 46), C.accent, 13)
probarBtn.LayoutOrder = 1
probarBtn.Activated:Connect(function()
    task.spawn(probar)
end)

local escanearBtn = btn(pagDiag, "🔎 Escanear ahora", UDim2.new(1, -4, 0, 46), C.track, 13)
escanearBtn.LayoutOrder = 2
escanearBtn.Activated:Connect(function()
    escanear()
    log("Escaneo manual terminado")
end)

local diagCard = Instance.new("Frame")
diagCard.LayoutOrder = 3
diagCard.Size = UDim2.new(1, -4, 0, 0)
diagCard.AutomaticSize = Enum.AutomaticSize.Y
diagCard.BackgroundColor3 = C.card
diagCard.BorderSizePixel = 0
diagCard.Parent = pagDiag
corner(diagCard, 10)

local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 12)
pad.PaddingRight = UDim.new(0, 12)
pad.PaddingTop = UDim.new(0, 10)
pad.PaddingBottom = UDim.new(0, 10)
pad.Parent = diagCard

local diagLbl = Instance.new("TextLabel")
diagLbl.BackgroundTransparency = 1
diagLbl.Size = UDim2.new(1, 0, 0, 0)
diagLbl.AutomaticSize = Enum.AutomaticSize.Y
diagLbl.TextWrapped = true
diagLbl.TextXAlignment = Enum.TextXAlignment.Left
diagLbl.TextYAlignment = Enum.TextYAlignment.Top
diagLbl.TextSize = 11
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
    toggle.Text = S.activo and "● ENCENDIDO" or "○ APAGADO"
    toggle.BackgroundColor3 = S.activo and C.green or C.track
    estadoLbl.Text = S.estado

    for i, f in ipairs(filasMundo) do
        f.cuenta.Text = tostring(S.conteoMundo[i] or 0)
        f.box.BackgroundColor3 = S.mundoOn[i] and C.green or C.track
        f.tick.Visible = S.mundoOn[i]
    end

    for i, f in ipairs(filasCat) do
        f.cuenta.Text = tostring(S.conteo[i] or 0)
        f.box.BackgroundColor3 = S.catOn[i] and C.green or C.track
        f.tick.Visible = S.catOn[i]
    end

    statLbl.Text = string.format("Cargados %d/%d · Recogidas %d · Huidas %d · Vaciados %d",
        S.cargados, S.maxJunk, S.recogidas, S.huidas, S.vaciados)

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
        "Piezas Junk encontradas: %d\n" ..
        "Con categoría (Junkyard): %d\n" ..
        "Con ProximityPrompt: %d · sin prompt: %d\n" ..
        "Piezas descartadas por robot: %d\n" ..
        "Robots: %s\n" ..
        "Remote %s: %s\n" ..
        "Tu plot: %s\n" ..
        "Primera pieza: %s\n\n" ..
        "Últimos eventos:\n%s",
        d.carpetas or 0, d.carpetasTotal or #CONFIG.MUNDOS,
        d.piezas or 0,
        d.categorizadas or 0,
        d.conPrompt or 0, d.sinPrompt or 0,
        d.peligro or 0,
        table.concat(robotsTxt, " · "),
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

mostrarPestana(1)
refrescar()
