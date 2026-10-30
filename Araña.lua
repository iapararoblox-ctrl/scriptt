-- MaykDev · Auto Farm (Orbes / Breakables) · LocalScript · móvil
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

---------------------------------------------------------------
-- CONFIGURACIÓN
---------------------------------------------------------------
local CONFIG = {
    CARPETA_ORBES  = { "Orbs" },            -- Workspace.Orbs
    PREFIJO_ORB    = "Orb",                 -- nombre de cada orbe
    NOMBRE_XP      = "XP",                  -- propiedad con la experiencia
    CARPETA_BREAK  = { "Breakables" },      -- Workspace.Breakables
    TIPOS_BREAK    = { "Egg Cluster", "Silk Stash", "Silk Cocoon", "Acorn", "Sugar Cube", "Golden Cocoon", "Puffball" },
    COLORES_TIPO   = {
        Color3.fromRGB(240, 170, 200), Color3.fromRGB(200, 200, 230), Color3.fromRGB(180, 230, 200),
        Color3.fromRGB(210, 150, 90),  Color3.fromRGB(255, 225, 150), Color3.fromRGB(240, 200, 90),
        Color3.fromRGB(170, 200, 255),
    },
    VELOCIDAD      = { ini = 250, min = 50, max = 800, paso = 50 },
    ALTURA         = { ini = 2, min = 0, max = 10, paso = 1 },
    ESPERA_TOQUE   = 0.6,                   -- segundos esperando a que se recoja o rompa tras cada intento
    INTENTOS       = 3,
    COOLDOWN       = 8,                     -- segundos sin reintentar un objetivo que falló
    ESPERA_CICLO   = 0.4,
    TIMEOUT_VUELO  = 20,
    TOP            = 5,
}

---------------------------------------------------------------
-- ESTADO
---------------------------------------------------------------
local S = {
    activo = false,
    cerrado = false,
    fuente = "ORBES",                       -- "ORBES" o "BREAK"
    modo = "DESLIZAR",                      -- "TP" o "DESLIZAR"
    velocidad = CONFIG.VELOCIDAD.ini,
    altura = CONFIG.ALTURA.ini,
    tipoOn = {},
    conteoTipo = {},
    recogidos = 0,
    fallos = 0,
    xpTotal = 0,
    mejorXP = 0,
    disponibles = 0,
    lista = {},
    cooldown = {},
    diag = {},
    estado = "Listo",
    log = {},
}
for i = 1, #CONFIG.TIPOS_BREAK do
    S.tipoOn[i] = true
    S.conteoTipo[i] = 0
end

local C = {
    bg = Color3.fromRGB(16, 18, 26),
    card = Color3.fromRGB(28, 31, 44),
    row = Color3.fromRGB(37, 41, 58),
    track = Color3.fromRGB(46, 50, 70),
    accent = Color3.fromRGB(110, 150, 255),
    gold = Color3.fromRGB(240, 200, 90),
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
    print("[AUTOFARM]", msg)
end

local function fmtNum(n)
    if n >= 1e6 then
        return string.format("%.1fM", n / 1e6)
    elseif n >= 1e3 then
        return string.format("%.1fK", n / 1e3)
    end
    return tostring(math.floor(n))
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

local function posOf(obj)
    if obj:IsA("Model") then
        return obj:GetPivot().Position
    end
    return obj.Position
end

local function esOrb(name)
    return string.sub(name, 1, #CONFIG.PREFIJO_ORB) == CONFIG.PREFIJO_ORB
end

-- Índice del tipo de Breakable si el nombre empieza por uno de los tipos (p. ej. "Acorn" o "Acorn2")
local function tipoDe(name)
    for i, t in ipairs(CONFIG.TIPOS_BREAK) do
        if name == t then
            return i
        end
        if string.sub(name, 1, #t) == t and not string.match(string.sub(name, #t + 1, #t + 1), "%a") then
            return i
        end
    end
    return nil
end

-- true si el objeto está dentro de otro objeto que ya cuenta (para no contar sus partes)
local function dentroDeContado(obj, carpeta, esMarcado)
    local p = obj.Parent
    while p and p ~= carpeta do
        if esMarcado(p) then
            return true
        end
        p = p.Parent
    end
    return false
end

local function partesDe(obj)
    local partes = {}
    if obj:IsA("BasePart") then
        table.insert(partes, obj)
    end
    for _, d in ipairs(obj:GetDescendants()) do
        if d:IsA("BasePart") then
            table.insert(partes, d)
        end
    end
    return partes
end

-- Lee el XP del orbe: atributo "XP" o ValueBase hijo llamado "XP"
local function leerXP(obj)
    local v = obj:GetAttribute(CONFIG.NOMBRE_XP)
    if v == nil then
        local c = obj:FindFirstChild(CONFIG.NOMBRE_XP, true)
        if c and c:IsA("ValueBase") then
            v = c.Value
        end
    end
    return tonumber(v) or 0
end

local function estaRoto(obj)
    local h = obj:GetAttribute("Health")
    if type(h) == "number" and h <= 0 then
        return true
    end
    local hv = obj:FindFirstChild("Health", true)
    if hv and hv:IsA("ValueBase") and tonumber(hv.Value) and tonumber(hv.Value) <= 0 then
        return true
    end
    return false
end

---------------------------------------------------------------
-- ESCANEO
---------------------------------------------------------------
local function escanearOrbes(lista, miPos, ahora)
    local carpeta = ruta(Workspace, CONFIG.CARPETA_ORBES)
    local diag = { carpeta = carpeta ~= nil, encontrados = 0, conPrompt = 0, conClick = 0, conVida = 0 }
    if carpeta then
        for _, obj in ipairs(carpeta:GetDescendants()) do
            if (obj:IsA("Model") or obj:IsA("BasePart"))
                and esOrb(obj.Name)
                and not dentroDeContado(obj, carpeta, function(p) return esOrb(p.Name) or p:IsA("Model") end)
                and (not S.cooldown[obj] or S.cooldown[obj] <= ahora) then
                diag.encontrados += 1
                table.insert(lista, {
                    obj = obj,
                    nombre = obj.Name,
                    xp = leerXP(obj),
                    dist = (posOf(obj) - miPos).Magnitude,
                })
            end
        end
    end
    table.sort(lista, function(a, b)
        if a.xp ~= b.xp then
            return a.xp > b.xp
        end
        return a.dist < b.dist
    end)
    return diag
end

local function escanearBreak(lista, miPos, ahora)
    local carpeta = ruta(Workspace, CONFIG.CARPETA_BREAK)
    local diag = { carpeta = carpeta ~= nil, encontrados = 0, conPrompt = 0, conClick = 0, conVida = 0 }
    local conteo = {}
    for i = 1, #CONFIG.TIPOS_BREAK do conteo[i] = 0 end

    if carpeta then
        for _, obj in ipairs(carpeta:GetDescendants()) do
            local idx = (obj:IsA("Model") or obj:IsA("BasePart")) and tipoDe(obj.Name) or nil
            if idx and not dentroDeContado(obj, carpeta, function(p)
                    return p:IsA("Model") and tipoDe(p.Name) ~= nil
                end) then
                conteo[idx] += 1
                if S.tipoOn[idx] and (not S.cooldown[obj] or S.cooldown[obj] <= ahora) then
                    diag.encontrados += 1
                    if obj:FindFirstChildWhichIsA("ProximityPrompt", true) then diag.conPrompt += 1 end
                    if obj:FindFirstChildWhichIsA("ClickDetector", true) then diag.conClick += 1 end
                    if obj:GetAttribute("Health") ~= nil then diag.conVida += 1 end
                    table.insert(lista, {
                        obj = obj,
                        nombre = obj.Name,
                        tipo = CONFIG.TIPOS_BREAK[idx],
                        xp = 0,
                        dist = (posOf(obj) - miPos).Magnitude,
                    })
                end
            end
        end
    end

    table.sort(lista, function(a, b)
        return a.dist < b.dist
    end)

    S.conteoTipo = conteo
    return diag
end

local function escanear()
    local root = getRoot()
    local miPos = root and root.Position or Vector3.zero
    local ahora = os.clock()
    local lista = {}
    local diag

    if S.fuente == "ORBES" then
        diag = escanearOrbes(lista, miPos, ahora)
    else
        diag = escanearBreak(lista, miPos, ahora)
    end

    if lista[1] and S.fuente == "ORBES" and lista[1].xp > S.mejorXP then
        S.mejorXP = lista[1].xp
    end
    S.lista = lista
    S.disponibles = #lista
    S.diag = diag
    return lista
end

---------------------------------------------------------------
-- MOVIMIENTO
---------------------------------------------------------------
local function moverA(obj)
    local root = getRoot()
    if not root then return false end

    if S.modo == "TP" then
        root.AssemblyLinearVelocity = Vector3.zero
        root.CFrame = CFrame.new(posOf(obj) + Vector3.new(0, S.altura, 0)) * (root.CFrame - root.CFrame.Position)
        task.wait(0.1)
        return obj:IsDescendantOf(Workspace)
    end

    local t0 = os.clock()
    while not S.cerrado and S.activo and os.clock() - t0 < CONFIG.TIMEOUT_VUELO do
        if not obj:IsDescendantOf(Workspace) then
            return false
        end
        root = getRoot()
        if not root then return false end

        local destino = posOf(obj) + Vector3.new(0, S.altura, 0)
        local actual = root.Position
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

---------------------------------------------------------------
-- INTERACCIÓN: toca, activa prompts y clicks, espera a que se recoja o rompa
---------------------------------------------------------------
local function interactuar(obj)
    for _ = 1, CONFIG.INTENTOS do
        if not obj:IsDescendantOf(Workspace) or estaRoto(obj) then
            return true
        end

        local root = getRoot()
        if not root then
            return false
        end

        for _, p in ipairs(partesDe(obj)) do
            pcall(function()
                firetouchinterest(root, p, 0)
                firetouchinterest(root, p, 1)
            end)
        end

        for _, d in ipairs(obj:GetDescendants()) do
            if d:IsA("ProximityPrompt") then
                pcall(function()
                    d.RequiresLineOfSight = false
                    if d.MaxActivationDistance < 20 then
                        d.MaxActivationDistance = 20
                    end
                end)
                pcall(fireproximityprompt, d)
            elseif d:IsA("ClickDetector") then
                pcall(fireclickdetector, d)
            end
        end

        local t0 = os.clock()
        while os.clock() - t0 < CONFIG.ESPERA_TOQUE do
            if not obj:IsDescendantOf(Workspace) or estaRoto(obj) then
                break
            end
            task.wait(0.05)
        end
    end
    return not obj:IsDescendantOf(Workspace) or estaRoto(obj)
end

---------------------------------------------------------------
-- CICLO
---------------------------------------------------------------
local function nombreFuente()
    return S.fuente == "ORBES" and "orbes" or "breakables"
end

local function ciclo()
    local lista = escanear()
    local top = lista[1]

    if not top then
        S.estado = "Sin " .. nombreFuente() .. " disponibles"
        task.wait(CONFIG.ESPERA_CICLO)
        return
    end

    if S.fuente == "ORBES" then
        S.estado = "Yendo a orbe de " .. fmtNum(top.xp) .. " XP"
    else
        S.estado = "Yendo a " .. top.nombre
    end

    if not moverA(top.obj) then
        S.fallos += 1
        S.cooldown[top.obj] = os.clock() + CONFIG.COOLDOWN
        S.estado = "No llegué a " .. top.nombre
        log("No llegó a " .. top.nombre)
        return
    end

    S.estado = "Interactuando con " .. top.nombre
    if interactuar(top.obj) then
        S.recogidos += 1
        if S.fuente == "ORBES" then
            S.xpTotal += top.xp
            S.estado = "Recogido: +" .. fmtNum(top.xp) .. " XP"
            log("+" .. fmtNum(top.xp) .. " XP (" .. top.nombre .. ")")
        else
            S.estado = "Conseguido: " .. top.nombre
            log("Conseguido: " .. top.nombre)
        end
    else
        S.fallos += 1
        S.cooldown[top.obj] = os.clock() + CONFIG.COOLDOWN
        S.estado = "No se pudo con " .. top.nombre
        log("Falló: " .. top.nombre)
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
-- UI
---------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "MaykDev_AutoFarm"
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
main.Size = UDim2.fromOffset(320, 480)
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
    uiScale.Scale = math.clamp(math.min(vp.X * 0.94 / 320, vp.Y * 0.86 / 480), 0.5, 1)
end
ajustarEscala()
if Workspace.CurrentCamera then
    Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(ajustarEscala)
end

-- Cabecera
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 52)
header.BackgroundColor3 = C.card
header.BorderSizePixel = 0
header.Parent = main
corner(header, 18)

local headerGrad = Instance.new("UIGradient")
headerGrad.Color = ColorSequence.new(Color3.fromRGB(120, 90, 180), Color3.fromRGB(28, 31, 44))
headerGrad.Rotation = 20
headerGrad.Parent = header

local title = label(header, "✨  Auto Farm", 16, C.text, true)
title.Position = UDim2.new(0, 16, 0, 8)
title.Size = UDim2.new(1, -110, 0, 20)

local sub = label(header, "MaykDev", 10, Color3.fromRGB(210, 205, 235), false)
sub.Position = UDim2.new(0, 16, 0, 29)
sub.Size = UDim2.new(1, -110, 0, 14)

local minBtn = btn(header, "—", UDim2.fromOffset(34, 34), Color3.fromRGB(255, 255, 255), 15)
minBtn.BackgroundTransparency = 0.85
minBtn.Position = UDim2.new(1, -80, 0, 9)
local closeBtn = btn(header, "✕", UDim2.fromOffset(34, 34), C.red, 13)
closeBtn.Position = UDim2.new(1, -40, 0, 9)

-- Interruptor
local toggle = btn(main, "○  APAGADO", UDim2.new(1, -24, 0, 46), C.track, 15)
toggle.Position = UDim2.new(0, 12, 0, 62)
toggle.Activated:Connect(function()
    S.activo = not S.activo
    S.estado = S.activo and "Buscando..." or "Apagado"
end)

-- Estado
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

-- Selector de fuente: Orbes / Breakables
local fuenteRow = Instance.new("Frame")
fuenteRow.Position = UDim2.new(0, 12, 0, 154)
fuenteRow.Size = UDim2.new(1, -24, 0, 36)
fuenteRow.BackgroundTransparency = 1
fuenteRow.Parent = main

local fuenteLayout = Instance.new("UIListLayout")
fuenteLayout.FillDirection = Enum.FillDirection.Horizontal
fuenteLayout.Padding = UDim.new(0, 6)
fuenteLayout.SortOrder = Enum.SortOrder.LayoutOrder
fuenteLayout.Parent = fuenteRow

local btnOrbes = btn(fuenteRow, "✨ Orbes", UDim2.new(0.5, -3, 1, 0), C.track, 13)
btnOrbes.LayoutOrder = 1
local btnBreak = btn(fuenteRow, "🌰 Breakables", UDim2.new(0.5, -3, 1, 0), C.track, 13)
btnBreak.LayoutOrder = 2

btnOrbes.Activated:Connect(function()
    S.fuente = "ORBES"
    S.lista = {}
    S.estado = "Farmeando orbes"
end)
btnBreak.Activated:Connect(function()
    S.fuente = "BREAK"
    S.lista = {}
    S.estado = "Farmeando breakables"
end)

-- Selector de modo: TP / Deslizar
local modoRow = Instance.new("Frame")
modoRow.Position = UDim2.new(0, 12, 0, 196)
modoRow.Size = UDim2.new(1, -24, 0, 32)
modoRow.BackgroundTransparency = 1
modoRow.Parent = main

local modoLayout = Instance.new("UIListLayout")
modoLayout.FillDirection = Enum.FillDirection.Horizontal
modoLayout.Padding = UDim.new(0, 6)
modoLayout.SortOrder = Enum.SortOrder.LayoutOrder
modoLayout.Parent = modoRow

local btnTP = btn(modoRow, "⚡ TP", UDim2.new(0.5, -3, 1, 0), C.track, 12)
btnTP.LayoutOrder = 1
local btnDes = btn(modoRow, "🌊 Deslizar", UDim2.new(0.5, -3, 1, 0), C.track, 12)
btnDes.LayoutOrder = 2

btnTP.Activated:Connect(function()
    S.modo = "TP"
    S.estado = "Modo TP"
end)
btnDes.Activated:Connect(function()
    S.modo = "DESLIZAR"
    S.estado = "Modo deslizar"
end)

-- Fichas
local chipsRow = Instance.new("Frame")
chipsRow.Position = UDim2.new(0, 12, 0, 236)
chipsRow.Size = UDim2.new(1, -24, 0, 50)
chipsRow.BackgroundTransparency = 1
chipsRow.Parent = main

local chipsLayout = Instance.new("UIListLayout")
chipsLayout.FillDirection = Enum.FillDirection.Horizontal
chipsLayout.Padding = UDim.new(0, 4)
chipsLayout.SortOrder = Enum.SortOrder.LayoutOrder
chipsLayout.Parent = chipsRow

local chipVals = {}
local function chip(orden, texto, key, color)
    local f = Instance.new("Frame")
    f.LayoutOrder = orden
    f.Size = UDim2.new(0.25, -4, 1, 0)
    f.BackgroundColor3 = C.card
    f.BorderSizePixel = 0
    f.Parent = chipsRow
    corner(f, 10)

    local v = label(f, "0", 13, color or C.accent, true, Enum.TextXAlignment.Center)
    v.Position = UDim2.new(0, 0, 0, 6)
    v.Size = UDim2.new(1, 0, 0, 20)

    local c = label(f, texto, 8, C.muted, true, Enum.TextXAlignment.Center)
    c.Position = UDim2.new(0, 0, 0, 28)
    c.Size = UDim2.new(1, 0, 0, 14)

    chipVals[key] = v
end
chip(1, "RECOGIDOS", "recogidos")
chip(2, "XP TOTAL", "xpTotal", C.gold)
chip(3, "MEJOR XP", "mejorXP", C.gold)
chip(4, "DISPONIBLES", "disponibles")

-- Página con desplegables
local page = Instance.new("ScrollingFrame")
page.Position = UDim2.new(0, 12, 0, 296)
page.Size = UDim2.new(1, -24, 1, -308)
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

-- Desplegable con encabezado, resumen y flecha
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

-- Fila con punto de color, nombre, contador y casilla
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

-- Fila de un objetivo en la lista (top)
local function filaObjetivo(parent, orden)
    local f = Instance.new("Frame")
    f.LayoutOrder = orden
    f.Size = UDim2.new(1, 0, 0, 36)
    f.BackgroundColor3 = C.row
    f.BorderSizePixel = 0
    f.Parent = parent
    corner(f, 10)

    local pos = label(f, "#" .. orden, 11, C.muted, true)
    pos.Position = UDim2.new(0, 12, 0, 0)
    pos.Size = UDim2.new(0, 30, 1, 0)

    local nombre = label(f, "—", 12, C.text, true)
    nombre.Position = UDim2.new(0, 44, 0, 0)
    nombre.Size = UDim2.new(1, -150, 1, 0)

    local valor = label(f, "", 11, C.gold, true, Enum.TextXAlignment.Right)
    valor.Position = UDim2.new(1, -104, 0, 0)
    valor.Size = UDim2.new(0, 90, 1, 0)

    local dist = label(f, "", 10, C.muted, false, Enum.TextXAlignment.Right)
    dist.Position = UDim2.new(1, -12, 0, 0)
    dist.Size = UDim2.new(0, 0, 1, 0)
    dist.AutomaticSize = Enum.AutomaticSize.X

    return { frame = f, nombre = nombre, valor = valor, dist = dist }
end

-- Fila de ajuste numérico con − y +
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
        S[key] = math.clamp(math.floor((S[key] - cfg.paso) * 10 + 0.5) / 10, cfg.min, cfg.max)
    end)
    mas.Activated:Connect(function()
        S[key] = math.clamp(math.floor((S[key] + cfg.paso) * 10 + 0.5) / 10, cfg.min, cfg.max)
    end)

    steppers[#steppers + 1] = {
        refresh = function()
            lbl.Text = nombreTxt .. ": " .. fmt(S[key])
        end,
    }
end

---------------------------------------------------------------
-- DESPLEGABLE: LISTA
---------------------------------------------------------------
local dLista = desplegable(1, "📋", "Objetivos")
local filasTop = {}
for i = 1, CONFIG.TOP do
    filasTop[i] = filaObjetivo(dLista.cuerpo, i)
end

---------------------------------------------------------------
-- DESPLEGABLE: TIPOS DE BREAKABLES
---------------------------------------------------------------
local dTipos = desplegable(2, "🌰", "Tipos de Breakables")
local filasTipo = {}
for i, t in ipairs(CONFIG.TIPOS_BREAK) do
    filasTipo[i] = fila(dTipos.cuerpo, i, CONFIG.COLORES_TIPO[i], t, function()
        S.tipoOn[i] = not S.tipoOn[i]
        S.estado = (S.tipoOn[i] and "Farmeando " or "Ignorando ") .. t
    end)
end

---------------------------------------------------------------
-- DESPLEGABLE: AJUSTES
---------------------------------------------------------------
local dAjustes = desplegable(3, "⚙️", "Ajustes")
stepper(dAjustes.cuerpo, 1, "Velocidad", CONFIG.VELOCIDAD, "velocidad", function(v) return string.format("%d/s", v) end)
stepper(dAjustes.cuerpo, 2, "Altura", CONFIG.ALTURA, "altura", function(v) return string.format("%d st", v) end)

---------------------------------------------------------------
-- DESPLEGABLE: DIAGNÓSTICO
---------------------------------------------------------------
local dDiag = desplegable(4, "🧪", "Diagnóstico")

local diagCard = Instance.new("Frame")
diagCard.LayoutOrder = 1
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
local bubble = btn(gui, "✨", UDim2.fromOffset(54, 54), C.card, 22)
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
-- REFRESCO
---------------------------------------------------------------
local filasTipoRef = filasTipo

local function refrescar()
    toggle.Text = S.activo and "●  ENCENDIDO" or "○  APAGADO"
    toggle.BackgroundColor3 = S.activo and C.green or C.track
    estadoLbl.Text = S.estado

    btnOrbes.BackgroundColor3 = S.fuente == "ORBES" and C.accent or C.track
    btnBreak.BackgroundColor3 = S.fuente == "BREAK" and C.accent or C.track
    btnTP.BackgroundColor3 = S.modo == "TP" and C.accent or C.track
    btnDes.BackgroundColor3 = S.modo == "DESLIZAR" and C.accent or C.track

    chipVals.recogidos.Text = tostring(S.recogidos)
    chipVals.xpTotal.Text = fmtNum(S.xpTotal)
    chipVals.mejorXP.Text = fmtNum(S.mejorXP)
    chipVals.disponibles.Text = tostring(S.disponibles)

    local root = getRoot()
    local miPos = root and root.Position or Vector3.zero
    for i, f in ipairs(filasTop) do
        local e = S.lista[i]
        if e then
            f.frame.Visible = true
            f.nombre.Text = e.nombre
            if S.fuente == "ORBES" then
                f.valor.Text = fmtNum(e.xp) .. " XP"
            else
                f.valor.Text = e.tipo or ""
            end
            f.dist.Text = string.format("%d st", math.floor((posOf(e.obj) - miPos).Magnitude))
        else
            f.frame.Visible = i == 1
            if i == 1 then
                f.nombre.Text = "Sin objetivos"
                f.valor.Text = ""
                f.dist.Text = ""
            end
        end
    end
    dLista.resumen.Text = S.disponibles .. " disp."

    local nTipos = 0
    for i, f in ipairs(filasTipoRef) do
        f.cuenta.Text = tostring(S.conteoTipo[i] or 0)
        f.box.BackgroundColor3 = S.tipoOn[i] and C.green or C.track
        f.tick.Visible = S.tipoOn[i]
        if S.tipoOn[i] then nTipos += 1 end
    end
    dTipos.resumen.Text = nTipos .. "/" .. #CONFIG.TIPOS_BREAK

    for _, s in ipairs(steppers) do
        s.refresh()
    end
    dAjustes.resumen.Text = S.modo == "TP" and "TP" or string.format("%d/s", S.velocidad)

    local d = S.diag or {}
    local carpetaTxt = S.fuente == "ORBES"
        and table.concat(CONFIG.CARPETA_ORBES, ".")
        or table.concat(CONFIG.CARPETA_BREAK, ".")
    local lines = {
        "Carpeta " .. carpetaTxt .. ": " .. (d.carpeta and "encontrada" or "no encontrada"),
        "Objetivos disponibles: " .. (d.encontrados or 0),
        "Con ProximityPrompt: " .. (d.conPrompt or 0) .. " · ClickDetector: " .. (d.conClick or 0) .. " · Vida: " .. (d.conVida or 0),
        "",
        "Últimos eventos:",
        #S.log > 0 and table.concat(S.log, "\n") or "(sin eventos todavía)",
    }
    diagLbl.Text = table.concat(lines, "\n")
end

task.spawn(function()
    while not S.cerrado do
        if not S.activo then
            escanear()
        end
        refrescar()
        task.wait(1)
    end
end)

refrescar()
