-- MaykDev · Auto Chatarra (LocalScript)
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

---------------------------------------------------------------
-- CONFIGURACIÓN
---------------------------------------------------------------
local CONFIG = {
    CARPETAS = {
        { "Client", "Junkyard", "Heaven", "Spawn", "Parts" },
        { "Client", "Junkyard", "Overworld", "Spawn", "Parts" },
        { "Server", "Junkyard" },
    },
    -- Orden de prioridad: de mayor a menor valor (el índice 1 se recoge primero)
    CATEGORIAS = {
        { id = "Scrap/Giant",  nombre = "Gigante", color = Color3.fromRGB(240, 110, 90) },
        { id = "Scrap/Big",    nombre = "Grande",  color = Color3.fromRGB(240, 185, 80) },
        { id = "Scrap/Medium", nombre = "Mediana", color = Color3.fromRGB(110, 170, 255) },
        { id = "Scrap/Small",  nombre = "Pequeña", color = Color3.fromRGB(120, 210, 150) },
    },
    RETRASO_INICIAL = 0.6,      -- segundos entre teletransportes (evita rollbacks y cierres)
    RETRASO_MIN = 0.2,
    RETRASO_MAX = 3,
    RETRASO_PASO = 0.1,
    ESPERA_RECOGER = 0.35,      -- segundos tras activar el prompt
    INTENTOS = 2,               -- veces que se activa el prompt de una pieza
    ALTURA = 3,                 -- studs por encima de la pieza
    COOLDOWN_FALLO = 12,        -- segundos sin reintentar una pieza que no se pudo recoger
    ESPERA_CICLO = 0.75,        -- espera cuando no hay chatarra disponible (respawn)
    REMOTE_RUTA = { "Packages", "Net", "Remotes" },
    REMOTE_NOMBRE = "PickUpJunk", -- se usa solo si la pieza no tiene ProximityPrompt
    DEBUG = true,
}

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
    delay = CONFIG.RETRASO_INICIAL,
    catOn = { true, true, true, true },
    conteo = { 0, 0, 0, 0 },
    cooldown = {},
    recogidas = 0,
    fallos = 0,
    visibles = 0,
    estado = "Listo",
}

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

local function dbg(...)
    if CONFIG.DEBUG then print("[CHATARRA]", ...) end
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

local function categoriaDeTexto(s)
    local m = string.match((tostring(s):gsub("%s", "")), "Scrap/%a+")
    if m and CAT_INDEX[m] then
        return m
    end
    return nil
end

-- Busca "Scrap/..." en los atributos y valores del objeto y de su padre
local function buscarCategoria(inst)
    local cur, n = inst, 0
    while cur and n < 2 do
        for _, v in pairs(cur:GetAttributes()) do
            local c = categoriaDeTexto(v)
            if c then return c end
        end
        for _, ch in ipairs(cur:GetChildren()) do
            if ch:IsA("StringValue") then
                local c = categoriaDeTexto(ch.Value)
                if c then return c end
            end
        end
        cur = cur.Parent
        n += 1
    end
    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA("StringValue") then
            local c = categoriaDeTexto(d.Value)
            if c then return c end
        end
    end
    return nil
end

local function indiceCategoria(obj)
    local c = buscarCategoria(obj)
    return c and CAT_INDEX[c] or nil
end

local function posOf(obj)
    if obj:IsA("Model") then
        return obj:GetPivot().Position
    end
    return obj.Position
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

local function irA(pos)
    local root = getRoot()
    if not root then return false end
    root.AssemblyLinearVelocity = Vector3.zero
    root.CFrame = CFrame.new(pos) * (root.CFrame - root.CFrame.Position)
    return true
end

---------------------------------------------------------------
-- ESCANEO: detecta la chatarra, cuenta por categoría y ordena por valor
---------------------------------------------------------------
local function escanear()
    local root = getRoot()
    local miPos = root and root.Position or Vector3.zero
    local ahora = os.clock()
    local lista, vistos, conteo = {}, {}, { 0, 0, 0, 0 }
    local remote = obtenerRemote()

    for _, cfg in ipairs(CONFIG.CARPETAS) do
        local carpeta = ruta(Workspace, cfg)
        if carpeta then
            for _, obj in ipairs(carpeta:GetDescendants()) do
                -- Models, o BaseParts sueltas (las partes de un Model se ignoran para no contar doble)
                local valida = obj:IsA("Model")
                    or (obj:IsA("BasePart") and not (obj.Parent and obj.Parent:IsA("Model")))
                if valida and not vistos[obj] then
                    vistos[obj] = true
                    local idx = indiceCategoria(obj)
                    if idx then
                        conteo[idx] += 1
                        local libre = not S.cooldown[obj] or S.cooldown[obj] <= ahora
                        if S.catOn[idx] and libre and (promptDe(obj) or remote) then
                            local pos = posOf(obj)
                            table.insert(lista, {
                                pieza = obj,
                                idx = idx,
                                dist = (pos - miPos).Magnitude,
                            })
                        end
                    end
                end
            end
        end
    end

    -- Mayor valor primero; dentro de la misma categoría, la más cercana
    table.sort(lista, function(a, b)
        if a.idx ~= b.idx then
            return a.idx < b.idx
        end
        return a.dist < b.dist
    end)

    S.conteo = conteo
    S.visibles = #lista
    return lista
end

---------------------------------------------------------------
-- RECOGIDA
---------------------------------------------------------------
local function recoger(pieza)
    irA(posOf(pieza) + Vector3.new(0, CONFIG.ALTURA, 0))
    task.wait(S.delay) -- deja que el servidor reciba tu posición

    for _ = 1, CONFIG.INTENTOS do
        if not pieza:IsDescendantOf(Workspace) then break end

        local prompt = promptDe(pieza)
        if prompt then
            pcall(function()
                prompt.RequiresLineOfSight = false
                if prompt.MaxActivationDistance < 20 then
                    prompt.MaxActivationDistance = 20
                end
            end)
            pcall(fireproximityprompt, prompt)
        else
            local remote = obtenerRemote()
            if remote then
                pcall(function()
                    if remote:IsA("RemoteFunction") then
                        remote:InvokeServer(pieza.Name)
                    else
                        remote:FireServer(pieza.Name)
                    end
                end)
            end
        end
        task.wait(CONFIG.ESPERA_RECOGER)
    end

    -- Recogida correcta: la pieza ya no está en el Workspace
    return not pieza:IsDescendantOf(Workspace)
end

---------------------------------------------------------------
-- BUCLE PRINCIPAL (se queda evaluando el mapa cuando hay respawn)
---------------------------------------------------------------
task.spawn(function()
    while not S.cerrado do
        if not S.activo then
            S.estado = "Apagado"
            task.wait(0.3)
        elseif not getRoot() then
            S.estado = "Esperando tu personaje..."
            task.wait(1)
        else
            local lista = escanear()
            local obj = lista[1]
            if obj then
                local nombre = CONFIG.CATEGORIAS[obj.idx].nombre
                S.estado = "Recogiendo: " .. nombre
                local ok = recoger(obj.pieza)
                if ok then
                    S.recogidas += 1
                    S.estado = "Recogida: " .. nombre
                else
                    S.fallos += 1
                    S.cooldown[obj.pieza] = os.clock() + CONFIG.COOLDOWN_FALLO
                    S.estado = "No se pudo, la salto"
                    dbg("No se recogió:", obj.pieza:GetFullName())
                end
                task.wait(S.delay) -- retraso entre teletransportes
            else
                S.estado = "Esperando chatarra (respawn)..."
                task.wait(CONFIG.ESPERA_CICLO)
            end
        end
    end
end)

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
    b.TextSize = tsize or 12
    b.Font = Enum.Font.GothamBold
    b.BorderSizePixel = 0
    b.AutoButtonColor = true
    b.Parent = p
    corner(b, 8)
    return b
end

-- Arrastrable (táctil y ratón). Devuelve { moved } para distinguir arrastre de toque.
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
                    if state.moved and onEnd then onEnd() end
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
main.Size = UDim2.fromOffset(290, 392)
main.BackgroundColor3 = C.bg
main.BorderSizePixel = 0
main.ClipsDescendants = true
main.Parent = gui
corner(main, 16)
stroke(main, C.accent, 1, 0.4)

local grad = Instance.new("UIGradient")
grad.Color = ColorSequence.new(C.bg, Color3.fromRGB(30, 24, 48))
grad.Rotation = 90
grad.Parent = main

-- Cabecera
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 48)
header.BackgroundColor3 = C.card
header.BorderSizePixel = 0
header.Parent = main
corner(header, 16)

local title = label(header, "♻️ Auto Chatarra", 15, C.text, true)
title.Position = UDim2.new(0, 14, 0, 6)
title.Size = UDim2.new(1, -90, 0, 18)

local sub = label(header, "MaykDev", 10, C.muted, false)
sub.Position = UDim2.new(0, 14, 0, 25)
sub.Size = UDim2.new(1, -90, 0, 14)

local minBtn = btn(header, "—", UDim2.fromOffset(30, 30), C.track, 14)
minBtn.Position = UDim2.new(1, -70, 0, 9)
local closeBtn = btn(header, "✕", UDim2.fromOffset(30, 30), C.red, 12)
closeBtn.Position = UDim2.new(1, -34, 0, 9)

-- Interruptor principal
local toggle = btn(main, "AUTO CHATARRA: APAGADO", UDim2.new(1, -24, 0, 44), C.track, 13)
toggle.Position = UDim2.new(0, 12, 0, 58)

local estadoLbl = label(main, "Listo", 11, C.muted, false)
estadoLbl.Position = UDim2.new(0, 14, 0, 108)
estadoLbl.Size = UDim2.new(1, -28, 0, 16)

local secLbl = label(main, "CATEGORÍAS · de mayor a menor valor", 9, C.muted, true)
secLbl.Position = UDim2.new(0, 14, 0, 132)
secLbl.Size = UDim2.new(1, -28, 0, 14)

-- Filas de categoría (toque = activar/desactivar)
local filas = {}
for i, cat in ipairs(CONFIG.CATEGORIAS) do
    local fila = Instance.new("TextButton")
    fila.Size = UDim2.new(1, -24, 0, 32)
    fila.Position = UDim2.new(0, 12, 0, 150 + (i - 1) * 38)
    fila.BackgroundColor3 = C.card
    fila.BorderSizePixel = 0
    fila.Text = ""
    fila.AutoButtonColor = false
    fila.Parent = main
    corner(fila, 8)

    local dot = Instance.new("Frame")
    dot.Size = UDim2.fromOffset(10, 10)
    dot.Position = UDim2.new(0, 12, 0.5, -5)
    dot.BackgroundColor3 = cat.color
    dot.BorderSizePixel = 0
    dot.Parent = fila
    corner(dot, 5)

    local nombre = label(fila, cat.nombre, 12, C.text, true)
    nombre.Position = UDim2.new(0, 30, 0, 0)
    nombre.Size = UDim2.new(1, -90, 1, 0)

    local cuenta = label(fila, "0", 11, C.muted, true, Enum.TextXAlignment.Right)
    cuenta.Position = UDim2.new(1, -62, 0, 0)
    cuenta.Size = UDim2.new(0, 30, 1, 0)

    local box = Instance.new("Frame")
    box.Size = UDim2.fromOffset(18, 18)
    box.Position = UDim2.new(1, -26, 0.5, -9)
    box.BorderSizePixel = 0
    box.Parent = fila
    corner(box, 5)

    local tick = label(box, "✓", 12, C.text, true, Enum.TextXAlignment.Center)
    tick.Size = UDim2.new(1, 0, 1, 0)

    fila.Activated:Connect(function()
        S.catOn[i] = not S.catOn[i]
        S.estado = (S.catOn[i] and "Activada: " or "Desactivada: ") .. cat.nombre
    end)

    filas[i] = { cuenta = cuenta, box = box, tick = tick }
end

-- Retraso entre teletransportes
local delayRow = Instance.new("Frame")
delayRow.Size = UDim2.new(1, -24, 0, 36)
delayRow.Position = UDim2.new(0, 12, 0, 306)
delayRow.BackgroundColor3 = C.card
delayRow.BorderSizePixel = 0
delayRow.Parent = main
corner(delayRow, 8)

local delayLbl = label(delayRow, "", 11, C.text, true)
delayLbl.Position = UDim2.new(0, 12, 0, 0)
delayLbl.Size = UDim2.new(1, -110, 1, 0)

local dMinus = btn(delayRow, "−", UDim2.fromOffset(34, 26), C.track, 16)
dMinus.Position = UDim2.new(1, -82, 0.5, -13)
local dPlus = btn(delayRow, "+", UDim2.fromOffset(34, 26), C.track, 16)
dPlus.Position = UDim2.new(1, -40, 0.5, -13)

local function ajustarDelay(paso)
    local v = math.floor((S.delay + paso) * 10 + 0.5) / 10
    S.delay = math.clamp(v, CONFIG.RETRASO_MIN, CONFIG.RETRASO_MAX)
end
dMinus.Activated:Connect(function() ajustarDelay(-CONFIG.RETRASO_PASO) end)
dPlus.Activated:Connect(function() ajustarDelay(CONFIG.RETRASO_PASO) end)

-- Estadísticas
local statCard = Instance.new("Frame")
statCard.Size = UDim2.new(1, -24, 0, 32)
statCard.Position = UDim2.new(0, 12, 0, 350)
statCard.BackgroundColor3 = C.card
statCard.BorderSizePixel = 0
statCard.Parent = main
corner(statCard, 8)

local statLbl = label(statCard, "", 10, C.muted, false)
statLbl.Position = UDim2.new(0, 10, 0, 0)
statLbl.Size = UDim2.new(1, -20, 1, 0)

-- Burbuja minimizada
local bubble = btn(gui, "♻️", UDim2.fromOffset(52, 52), C.card, 22)
bubble.Visible = false
stroke(bubble, C.accent, 1, 0.3)

---------------------------------------------------------------
-- EVENTOS DE UI
---------------------------------------------------------------
local function refrescar()
    toggle.Text = S.activo and "AUTO CHATARRA: ENCENDIDO" or "AUTO CHATARRA: APAGADO"
    toggle.BackgroundColor3 = S.activo and C.green or C.track
    estadoLbl.Text = S.estado

    for i, f in ipairs(filas) do
        f.cuenta.Text = tostring(S.conteo[i])
        f.box.BackgroundColor3 = S.catOn[i] and C.green or C.track
        f.tick.Visible = S.catOn[i]
    end

    delayLbl.Text = string.format("Retraso entre TP: %.1f s", S.delay)
    statLbl.Text = string.format("Recogidas: %d  ·  Fallos: %d  ·  Disponibles: %d",
        S.recogidas, S.fallos, S.visibles)
end

toggle.Activated:Connect(function()
    S.activo = not S.activo
    S.estado = S.activo and "Buscando chatarra..." or "Apagado"
end)

local mainDrag = makeDraggable(header, main, nil)
local bubbleDrag = makeDraggable(bubble, bubble, nil)

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

-- Refresco de la UI y de los contadores (cada segundo)
task.spawn(function()
    while not S.cerrado do
        if not S.activo then
            escanear() -- mantiene los contadores al día aunque esté apagado
        end
        refrescar()
        task.wait(1)
    end
end)

refrescar()
