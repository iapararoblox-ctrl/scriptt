-- MaykDev · Auto Orbes (LocalScript · móvil)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

---------------------------------------------------------------
-- CONFIGURACIÓN
---------------------------------------------------------------
local CONFIG = {
    CARPETA      = { "Orbs" },      -- Workspace.Orbs
    PREFIJO      = "Orb",           -- nombre de cada orbe: Orb
    NOMBRE_XP    = "XP",            -- propiedad con la experiencia del orbe
    VELOCIDAD    = { ini = 250, min = 50, max = 800, paso = 50 },
    ALTURA       = { ini = 2, min = 0, max = 10, paso = 1 },
    ESPERA_TOQUE = 0.2,             -- segundos tras tocar/activar el orbe
    INTENTOS     = 3,               -- veces que intenta recogerlo
    COOLDOWN     = 8,               -- segundos sin reintentar un orbe que no se pudo recoger
    ESPERA_CICLO = 0.4,             -- espera cuando no hay orbes
    TIMEOUT_VUELO = 20,
    TOP = 5,                        -- cuántos orbes se muestran en la lista
}

---------------------------------------------------------------
-- ESTADO
---------------------------------------------------------------
local S = {
    activo = false,
    cerrado = false,
    modo = "DESLIZAR",              -- "TP" o "DESLIZAR"
    velocidad = CONFIG.VELOCIDAD.ini,
    altura = CONFIG.ALTURA.ini,
    recogidos = 0,
    fallos = 0,
    xpTotal = 0,
    mejorXP = 0,
    disponibles = 0,
    lista = {},
    cooldown = {},
    estado = "Listo",
    log = {},
}

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
    print("[ORBES]", msg)
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
    return string.sub(name, 1, #CONFIG.PREFIJO) == CONFIG.PREFIJO
end

-- true si el objeto está dentro de otro orbe (para no contar sus partes)
local function dentroDeOrb(obj, carpeta)
    local p = obj.Parent
    while p and p ~= carpeta do
        if p:IsA("Model") or esOrb(p.Name) then
            return true
        end
        p = p.Parent
    end
    return false
end

-- Lee el XP: atributo "XP" o ValueBase hijo llamado "XP". Devuelve número (0 si no existe)
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

---------------------------------------------------------------
-- ESCANEO: orbes ordenados por XP (mayor primero) y luego por distancia
---------------------------------------------------------------
local function escanear()
    local lista = {}
    local carpeta = ruta(Workspace, CONFIG.CARPETA)
    local root = getRoot()
    local miPos = root and root.Position or Vector3.zero
    local ahora = os.clock()

    if carpeta then
        for _, obj in ipairs(carpeta:GetDescendants()) do
            if (obj:IsA("Model") or obj:IsA("BasePart"))
                and esOrb(obj.Name)
                and not dentroDeOrb(obj, carpeta)
                and (not S.cooldown[obj] or S.cooldown[obj] <= ahora) then
                table.insert(lista, {
                    obj = obj,
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

    S.lista = lista
    S.disponibles = #lista
    if lista[1] and lista[1].xp > S.mejorXP then
        S.mejorXP = lista[1].xp
    end
    return lista
end

---------------------------------------------------------------
-- MOVIMIENTO
---------------------------------------------------------------
-- Va hasta el orbe. TP: salto directo. DESLIZAR: avance rápido frame a frame.
-- Devuelve true si llegó, false si falló o el orbe desapareció.
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
-- RECOGIDA: toca las partes del orbe y activa su prompt si tiene
---------------------------------------------------------------
local function recogerOrb(obj)
    for _ = 1, CONFIG.INTENTOS do
        if not obj:IsDescendantOf(Workspace) then
            return true
        end

        local root = getRoot()
        if not root then
            return false
        end

        local partes = {}
        if obj:IsA("BasePart") then
            table.insert(partes, obj)
        end
        for _, d in ipairs(obj:GetDescendants()) do
            if d:IsA("BasePart") then
                table.insert(partes, d)
            end
        end
        for _, p in ipairs(partes) do
            pcall(function()
                firetouchinterest(root, p, 0)
                firetouchinterest(root, p, 1)
            end)
        end

        local prompt = obj:FindFirstChildWhichIsA("ProximityPrompt", true)
        if prompt then
            pcall(function()
                prompt.RequiresLineOfSight = false
                if prompt.MaxActivationDistance < 20 then
                    prompt.MaxActivationDistance = 20
                end
            end)
            pcall(fireproximityprompt, prompt)
        end

        task.wait(CONFIG.ESPERA_TOQUE)
    end
    return not obj:IsDescendantOf(Workspace)
end

---------------------------------------------------------------
-- CICLO
---------------------------------------------------------------
local function ciclo()
    local lista = escanear()
    local top = lista[1]

    if not top then
        S.estado = "Sin orbes disponibles"
        task.wait(CONFIG.ESPERA_CICLO)
        return
    end

    S.estado = string.format("Yendo al orbe de %s XP", fmtNum(top.xp))
    if not moverA(top.obj) then
        S.fallos += 1
        S.cooldown[top.obj] = os.clock() + CONFIG.COOLDOWN
        S.estado = "No llegué al orbe"
        log("No llegó a " .. top.obj.Name)
        return
    end

    S.estado = "Recogiendo orbe de " .. fmtNum(top.xp) .. " XP"
    if recogerOrb(top.obj) then
        S.recogidos += 1
        S.xpTotal += top.xp
        S.estado = "Recogido: +" .. fmtNum(top.xp) .. " XP"
        log("+" .. fmtNum(top.xp) .. " XP (" .. top.obj.Name .. ")")
    else
        S.fallos += 1
        S.cooldown[top.obj] = os.clock() + CONFIG.COOLDOWN
        S.estado = "No se recogió el orbe"
        log("Falló: " .. top.obj.Name)
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
gui.Name = "MaykDev_Orbes"
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

local title = label(header, "✨  Auto Orbes", 16, C.text, true)
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
    S.estado = S.activo and "Buscando orbes..." or "Apagado"
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

-- Selector de modo: TP / Deslizar
local modoRow = Instance.new("Frame")
modoRow.Position = UDim2.new(0, 12, 0, 154)
modoRow.Size = UDim2.new(1, -24, 0, 36)
modoRow.BackgroundTransparency = 1
modoRow.Parent = main

local modoLayout = Instance.new("UIListLayout")
modoLayout.FillDirection = Enum.FillDirection.Horizontal
modoLayout.Padding = UDim.new(0, 6)
modoLayout.SortOrder = Enum.SortOrder.LayoutOrder
modoLayout.Parent = modoRow

local btnTP = btn(modoRow, "⚡ TP", UDim2.new(0.5, -3, 1, 0), C.track, 13)
btnTP.LayoutOrder = 1
local btnDes = btn(modoRow, "🌊 Deslizar", UDim2.new(0.5, -3, 1, 0), C.track, 13)
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
chipsRow.Position = UDim2.new(0, 12, 0, 198)
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
page.Position = UDim2.new(0, 12, 0, 256)
page.Size = UDim2.new(1, -24, 1, -268)
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

-- Fila de un orbe en la lista
local function filaOrbe(parent, orden)
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

    local xp = label(f, "", 12, C.gold, true, Enum.TextXAlignment.Right)
    xp.Position = UDim2.new(1, -104, 0, 0)
    xp.Size = UDim2.new(0, 90, 1, 0)

    local dist = label(f, "", 10, C.muted, false, Enum.TextXAlignment.Right)
    dist.Position = UDim2.new(1, -12, 0, 0)
    dist.Size = UDim2.new(0, 0, 1, 0)
    dist.AutomaticSize = Enum.AutomaticSize.X

    return { frame = f, nombre = nombre, xp = xp, dist = dist }
end

---------------------------------------------------------------
-- DESPLEGABLE: ORBES (top de mayor XP)
---------------------------------------------------------------
local dOrbes = desplegable(1, "🔮", "Orbes")
local filasTop = {}
for i = 1, CONFIG.TOP do
    filasTop[i] = filaOrbe(dOrbes.cuerpo, i)
end

---------------------------------------------------------------
-- DESPLEGABLE: AJUSTES
---------------------------------------------------------------
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

local dAjustes = desplegable(2, "⚙️", "Ajustes")
stepper(dAjustes.cuerpo, 1, "Velocidad", CONFIG.VELOCIDAD, "velocidad", function(v) return string.format("%d/s", v) end)
stepper(dAjustes.cuerpo, 2, "Altura", CONFIG.ALTURA, "altura", function(v) return string.format("%d st", v) end)

---------------------------------------------------------------
-- DESPLEGABLE: DIAGNÓSTICO
---------------------------------------------------------------
local dDiag = desplegable(3, "🧪", "Diagnóstico")

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
local function refrescar()
    toggle.Text = S.activo and "●  ENCENDIDO" or "○  APAGADO"
    toggle.BackgroundColor3 = S.activo and C.green or C.track
    estadoLbl.Text = S.estado

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
            f.nombre.Text = e.obj.Name
            f.xp.Text = fmtNum(e.xp) .. " XP"
            f.dist.Text = string.format("%d st", math.floor((posOf(e.obj) - miPos).Magnitude))
        else
            f.frame.Visible = i == 1
            if i == 1 then
                f.nombre.Text = "Sin orbes"
                f.xp.Text = ""
                f.dist.Text = ""
            end
        end
    end
    dOrbes.resumen.Text = S.disponibles .. " orbes"

    for _, s in ipairs(steppers) do
        s.refresh()
    end
    dAjustes.resumen.Text = S.modo == "TP" and "TP" or string.format("%d/s", S.velocidad)

    local carpeta = ruta(Workspace, CONFIG.CARPETA)
    local lines = {
        "Carpeta " .. table.concat(CONFIG.CARPETA, ".") .. ": " .. (carpeta and "encontrada" or "no encontrada"),
        "Orbes con prefijo '" .. CONFIG.PREFIJO .. "': " .. S.disponibles,
        "Propiedad de XP: " .. CONFIG.NOMBRE_XP,
        "Modo: " .. S.modo,
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
