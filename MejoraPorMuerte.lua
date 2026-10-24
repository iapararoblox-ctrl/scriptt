-- Auto-apuntado v3: la cámara gira y SIGUE al objetivo sin perderlo de vista (lock-on)
---------------------------------------------------------------
-- SERVICIOS
---------------------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

---------------------------------------------------------------
-- CONFIGURACIÓN FIJA
---------------------------------------------------------------
local CONFIG = {
    ETIQUETA = "Combatant",
    ARCHIVO = "AutoApuntadoConfig_v3.json",
    TECLA_ALTERNAR = Enum.KeyCode.X,   -- encender / apagar
    TECLA_CAMBIAR = Enum.KeyCode.C,    -- cambiar al siguiente objetivo
    NOMBRE_RENDER = "AutoApuntadoCamara",
    MARGEN_SOLTAR = 1.15,              -- el objetivo fijado se suelta al pasar radio x 1.15
    RADIO_MIN = 5,
    RADIO_MAX = 2000,
    FOV_MIN = 20,
    FOV_MAX = 1000,
    SUAVIZADO_MAX = 95,
    ESCALA_MIN = 50,
    ESCALA_MAX = 150,
}

local PARTES = {
    { id = "Head", txt = "Cabeza" },
    { id = "Torso", txt = "Torso" },
}
local PRIORIDADES = { "Más cercano", "Más cercano a la mira" }
local TIPOS = { "Todos", "Solo jugadores", "Solo bots" }

---------------------------------------------------------------
-- ESTADO (se guarda en archivo)
---------------------------------------------------------------
local DEFAULTS = {
    activo = true,
    radio = 100,
    parteIdx = 1,
    suavizado = 0,
    prioIdx = 1,
    soloClic = false,
    fijar = true,             -- mantener al mismo objetivo aunque salga de pantalla
    girarPersonaje = false,   -- el personaje también mira al objetivo
    tipoIdx = 1,
    ignorarEquipo = true,
    paredes = false,
    soloPantalla = true,
    usarFov = false,
    fov = 200,
    mostrarFov = false,
    resaltar = true,
    escala = 100,
}

local S = {}
for k, v in pairs(DEFAULTS) do
    S[k] = v
end

pcall(function()
    if readfile and isfile and isfile(CONFIG.ARCHIVO) then
        local data = HttpService:JSONDecode(readfile(CONFIG.ARCHIVO))
        if type(data) == "table" then
            for k, default in pairs(DEFAULTS) do
                if type(data[k]) == type(default) then
                    S[k] = data[k]
                end
            end
        end
    end
end)

-- Validar valores cargados
S.radio = math.clamp(S.radio, CONFIG.RADIO_MIN, CONFIG.RADIO_MAX)
S.fov = math.clamp(S.fov, CONFIG.FOV_MIN, CONFIG.FOV_MAX)
S.suavizado = math.clamp(S.suavizado, 0, CONFIG.SUAVIZADO_MAX)
S.escala = math.clamp(S.escala, CONFIG.ESCALA_MIN, CONFIG.ESCALA_MAX)
S.parteIdx = math.clamp(math.floor(S.parteIdx), 1, #PARTES)
S.prioIdx = math.clamp(math.floor(S.prioIdx), 1, #PRIORIDADES)
S.tipoIdx = math.clamp(math.floor(S.tipoIdx), 1, #TIPOS)

local closed = false
local dirty = false
local refreshUI

local function markDirty()
    dirty = true
end

local function saveConfig()
    if not writefile then return end
    pcall(function()
        writefile(CONFIG.ARCHIVO, HttpService:JSONEncode(S))
    end)
end

---------------------------------------------------------------
-- PERSONAJE
---------------------------------------------------------------
local function getRoot()
    local character = LocalPlayer.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function estoyVivo()
    local character = LocalPlayer.Character
    local hum = character and character:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > 0
end

---------------------------------------------------------------
-- OBJETIVOS
---------------------------------------------------------------
-- Modelo válido: Humanoid con vida + HumanoidRootPart, y no soy yo
local function esValido(model)
    if not model or not model:IsA("Model") then return false end
    if model == LocalPlayer.Character then return false end
    if not model:IsDescendantOf(Workspace) then return false end

    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end

    local root = model:FindFirstChild("HumanoidRootPart")
    return root ~= nil and root:IsA("BasePart")
end

-- Filtros de tipo (jugador/bot) y de equipo
local function pasaFiltros(model)
    local jugador = Players:GetPlayerFromCharacter(model)
    if S.tipoIdx == 2 and not jugador then return false end
    if S.tipoIdx == 3 and jugador then return false end
    if jugador and S.ignorarEquipo and LocalPlayer.Team ~= nil and jugador.Team == LocalPlayer.Team then
        return false
    end
    return true
end

-- Punto exacto al que se apunta (cabeza o torso, con respaldo al root)
local function getPuntoDeMira(model)
    local id = PARTES[S.parteIdx].id
    local parte
    if id == "Head" then
        parte = model:FindFirstChild("Head")
    else
        parte = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
    end
    if parte and parte:IsA("BasePart") then
        return parte.Position
    end
    return model.HumanoidRootPart.Position
end

-- Comprueba que no haya una pared entre la cámara y el objetivo
local function tieneLineaDeVista(cam, punto, model)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LocalPlayer.Character, model }
    local origen = cam.CFrame.Position
    return Workspace:Raycast(origen, punto - origen, params) == nil
end

local function nombreDe(model)
    local jugador = Players:GetPlayerFromCharacter(model)
    return jugador and jugador.DisplayName or model.Name
end

-- Lista de candidatos dentro del radio.
-- estricto = true aplica "solo en pantalla" y el círculo FOV (para elegir uno NUEVO).
local function listaCandidatos(cam, root, estricto)
    local lista = {}
    local centro = cam.ViewportSize / 2

    for _, model in ipairs(CollectionService:GetTagged(CONFIG.ETIQUETA)) do
        if esValido(model) and pasaFiltros(model) then
            local dist = (model.HumanoidRootPart.Position - root.Position).Magnitude
            if dist <= S.radio then
                local punto = getPuntoDeMira(model)
                local v, enPantalla = cam:WorldToViewportPoint(punto)
                local distPantalla = (Vector2.new(v.X, v.Y) - centro).Magnitude

                local ok = true
                if estricto then
                    if S.soloPantalla and not enPantalla then ok = false end
                    if ok and S.usarFov and distPantalla > S.fov then ok = false end
                end
                if ok and S.paredes and not tieneLineaDeVista(cam, punto, model) then ok = false end

                if ok then
                    table.insert(lista, {
                        model = model,
                        dist = dist,
                        puntaje = (S.prioIdx == 1) and dist or distPantalla,
                    })
                end
            end
        end
    end

    return lista
end

-- Mejor objetivo nuevo según la prioridad elegida
local function buscarMejor(cam, root)
    local mejor
    for _, c in ipairs(listaCandidatos(cam, root, true)) do
        if not mejor or c.puntaje < mejor.puntaje then
            mejor = c
        end
    end
    return mejor and mejor.model or nil
end

---------------------------------------------------------------
-- FIJADO DE OBJETIVO (LOCK-ON)
---------------------------------------------------------------
local bloqueado = nil          -- objetivo fijado
local objetivoActual = nil     -- objetivo usado este fotograma
local distanciaActual = 0

-- ¿Sigue siendo válido el objetivo fijado? Devuelve (ok, distancia)
local function bloqueoSigueValido(cam, root)
    local m = bloqueado
    if not (m and esValido(m) and pasaFiltros(m)) then
        return false
    end
    local dist = (m.HumanoidRootPart.Position - root.Position).Magnitude
    if dist > S.radio * CONFIG.MARGEN_SOLTAR then
        return false
    end
    if S.paredes and not tieneLineaDeVista(cam, getPuntoDeMira(m), m) then
        return false
    end
    return true, dist
end

-- Pasa al siguiente objetivo (por distancia) sin importar si está en pantalla
local function cambiarObjetivo()
    local cam = Workspace.CurrentCamera
    local root = getRoot()
    if not cam or not root then return end

    local lista = listaCandidatos(cam, root, false)
    if #lista == 0 then
        bloqueado = nil
        return
    end
    table.sort(lista, function(a, b) return a.dist < b.dist end)

    local siguiente = lista[1].model
    for i, c in ipairs(lista) do
        if c.model == bloqueado then
            siguiente = lista[(i % #lista) + 1].model
            break
        end
    end

    bloqueado = siguiente
    if not S.fijar then
        S.fijar = true
        markDirty()
    end
end

---------------------------------------------------------------
-- UI: PALETA Y HELPERS
---------------------------------------------------------------
local PALETTE = {
    bg = Color3.fromRGB(18, 20, 28),
    card = Color3.fromRGB(30, 33, 46),
    track = Color3.fromRGB(46, 50, 68),
    accent = Color3.fromRGB(110, 150, 255),
    green = Color3.fromRGB(80, 200, 130),
    red = Color3.fromRGB(225, 85, 95),
    text = Color3.fromRGB(240, 242, 250),
    muted = Color3.fromRGB(140, 146, 170),
}

local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "AutoApuntadoUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

local function corner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = parent
end

local function stroke(parent, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color
    s.Thickness = thickness or 1
    s.Transparency = transparency or 0
    s.Parent = parent
    return s
end

local function label(parent, text, size, color, bold)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextSize = size
    l.TextColor3 = color
    l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Center
    l.Parent = parent
    return l
end

local function button(parent, text, size, color)
    local b = Instance.new("TextButton")
    b.Size = size
    b.BackgroundColor3 = color
    b.Text = text
    b.TextColor3 = PALETTE.text
    b.TextSize = 12
    b.Font = Enum.Font.GothamBold
    b.AutoButtonColor = true
    b.BorderSizePixel = 0
    b.Parent = parent
    corner(b, 8)
    return b
end

local function listLayout(parent, pad, horizontal)
    local l = Instance.new("UIListLayout")
    l.Padding = UDim.new(0, pad)
    l.SortOrder = Enum.SortOrder.LayoutOrder
    if horizontal then
        l.FillDirection = Enum.FillDirection.Horizontal
    end
    l.Parent = parent
    return l
end

local function padding(frame, x, y)
    local p = Instance.new("UIPadding")
    p.PaddingLeft = UDim.new(0, x)
    p.PaddingRight = UDim.new(0, x)
    p.PaddingTop = UDim.new(0, y or x)
    p.PaddingBottom = UDim.new(0, y or x)
    p.Parent = frame
end

local function rowFrame(parent, order)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, -4, 0, 34)
    f.BackgroundColor3 = PALETTE.card
    f.BorderSizePixel = 0
    f.LayoutOrder = order
    f.Parent = parent
    corner(f, 8)
    return f
end

-- Casilla: lee su estado con get() y lo cambia con set(valor)
local function checkRow(parent, text, order, get, set)
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, -4, 0, 34)
    row.BackgroundColor3 = PALETTE.card
    row.BorderSizePixel = 0
    row.Text = ""
    row.AutoButtonColor = false
    row.LayoutOrder = order
    row.Parent = parent
    corner(row, 8)

    local lbl = label(row, text, 12, PALETTE.text, false)
    lbl.Position = UDim2.new(0, 10, 0, 0)
    lbl.Size = UDim2.new(1, -44, 1, 0)
    lbl.TextTruncate = Enum.TextTruncate.AtEnd

    local box = Instance.new("Frame")
    box.Size = UDim2.fromOffset(18, 18)
    box.Position = UDim2.new(1, -28, 0.5, -9)
    box.BorderSizePixel = 0
    box.Parent = row
    corner(box, 5)
    stroke(box, PALETTE.muted, 1, 0.2)

    local tick = label(box, "✓", 13, PALETTE.text, true)
    tick.Size = UDim2.new(1, 0, 1, 0)
    tick.TextXAlignment = Enum.TextXAlignment.Center

    local function paint()
        local on = get()
        box.BackgroundColor3 = on and PALETTE.green or PALETTE.track
        tick.Visible = on
    end

    row.Activated:Connect(function()
        set(not get())
        paint()
    end)

    paint()
    return { refresh = paint }
end

local function arrowRow(parent, order, getText, onPrev, onNext)
    local row = rowFrame(parent, order)

    local prev = button(row, "◀", UDim2.fromOffset(34, 28), PALETTE.track)
    prev.Position = UDim2.new(0, 3, 0.5, -14)
    local nxt = button(row, "▶", UDim2.fromOffset(34, 28), PALETTE.track)
    nxt.Position = UDim2.new(1, -37, 0.5, -14)

    local lbl = label(row, "", 12, PALETTE.text, true)
    lbl.TextXAlignment = Enum.TextXAlignment.Center
    lbl.Position = UDim2.new(0, 42, 0, 0)
    lbl.Size = UDim2.new(1, -84, 1, 0)
    lbl.TextTruncate = Enum.TextTruncate.AtEnd

    prev.Activated:Connect(onPrev)
    nxt.Activated:Connect(onNext)

    return { refresh = function() lbl.Text = getText() end }
end

-- Fila numérica: − [caja editable] +
local function numberRow(parent, order, name, getVal, setVal, step, boxWidth)
    local row = rowFrame(parent, order)
    boxWidth = boxWidth or 64

    local lbl = label(row, name, 12, PALETTE.text, true)
    lbl.Position = UDim2.new(0, 10, 0, 0)
    lbl.Size = UDim2.new(1, -(boxWidth + 90), 1, 0)
    lbl.TextTruncate = Enum.TextTruncate.AtEnd

    local minus = button(row, "−", UDim2.fromOffset(30, 28), PALETTE.track)
    minus.Position = UDim2.new(1, -(boxWidth + 76), 0.5, -14)
    minus.TextSize = 16

    local box = Instance.new("TextBox")
    box.Size = UDim2.fromOffset(boxWidth, 28)
    box.Position = UDim2.new(1, -(boxWidth + 42), 0.5, -14)
    box.BackgroundColor3 = PALETTE.bg
    box.BorderSizePixel = 0
    box.TextColor3 = PALETTE.text
    box.Font = Enum.Font.GothamBold
    box.TextSize = 12
    box.ClearTextOnFocus = false
    box.Text = tostring(getVal())
    box.Parent = row
    corner(box, 6)

    local plus = button(row, "+", UDim2.fromOffset(30, 28), PALETTE.track)
    plus.Position = UDim2.new(1, -38, 0.5, -14)
    plus.TextSize = 16

    minus.Activated:Connect(function()
        setVal(getVal() - step)
    end)
    plus.Activated:Connect(function()
        setVal(getVal() + step)
    end)
    box.FocusLost:Connect(function()
        local n = tonumber(box.Text)
        if n then
            setVal(math.floor(n + 0.5))
        end
        box.Text = tostring(getVal())
    end)

    return {
        refresh = function()
            if not box:IsFocused() then
                box.Text = tostring(getVal())
            end
        end,
    }
end

local function makeDraggable(handle, frame)
    local dragging, startInput, startPos = false, nil, nil
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
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
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y
            )
        end
    end)
end

---------------------------------------------------------------
-- UI: VENTANA PRINCIPAL
---------------------------------------------------------------
local main = Instance.new("Frame")
main.Name = "Main"
main.AnchorPoint = Vector2.new(0.5, 0.5)
main.Position = UDim2.new(0.5, 0, 0.5, 0)
main.Size = UDim2.fromOffset(300, 470)
main.BackgroundColor3 = PALETTE.bg
main.BorderSizePixel = 0
main.ClipsDescendants = true
main.Parent = gui
corner(main, 16)
stroke(main, PALETTE.accent, 1, 0.5)

local mainScale = Instance.new("UIScale")
mainScale.Scale = S.escala / 100
mainScale.Parent = main

-- Cabecera
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 44)
header.BackgroundTransparency = 1
header.Parent = main

local title = label(header, "🎯 Auto-Apuntado", 15, PALETTE.text, true)
title.Position = UDim2.new(0, 14, 0, 6)
title.Size = UDim2.new(1, -100, 0, 18)

local subtitle = label(header, "Arrastra aquí para mover", 10, PALETTE.muted, false)
subtitle.Position = UDim2.new(0, 14, 0, 24)
subtitle.Size = UDim2.new(1, -100, 0, 14)

local minBtn = button(header, "—", UDim2.fromOffset(30, 30), PALETTE.card)
minBtn.Position = UDim2.new(1, -72, 0, 7)
local closeBtn = button(header, "✕", UDim2.fromOffset(30, 30), PALETTE.red)
closeBtn.Position = UDim2.new(1, -36, 0, 7)

-- Tarjeta de estado
local statCard = Instance.new("Frame")
statCard.Position = UDim2.new(0, 10, 0, 48)
statCard.Size = UDim2.new(1, -20, 0, 54)
statCard.BackgroundColor3 = PALETTE.card
statCard.BorderSizePixel = 0
statCard.Parent = main
corner(statCard, 12)

local estLbl = label(statCard, "ESTADO", 9, PALETTE.muted, true)
estLbl.Position = UDim2.new(0, 12, 0, 7)
estLbl.Size = UDim2.new(0.4, -12, 0, 12)

local estadoLabel = label(statCard, "ACTIVO", 18, PALETTE.green, true)
estadoLabel.Position = UDim2.new(0, 12, 0, 19)
estadoLabel.Size = UDim2.new(0.4, -12, 0, 24)

local objLbl = label(statCard, "OBJETIVO", 9, PALETTE.muted, true)
objLbl.Position = UDim2.new(0.4, 0, 0, 7)
objLbl.Size = UDim2.new(0.6, -12, 0, 12)

local objetivoLabel = label(statCard, "—", 14, PALETTE.accent, true)
objetivoLabel.Position = UDim2.new(0.4, 0, 0, 19)
objetivoLabel.Size = UDim2.new(0.6, -12, 0, 24)
objetivoLabel.TextTruncate = Enum.TextTruncate.AtEnd

-- Pestañas
local tabRow = Instance.new("Frame")
tabRow.Position = UDim2.new(0, 10, 0, 110)
tabRow.Size = UDim2.new(1, -20, 0, 30)
tabRow.BackgroundTransparency = 1
tabRow.Parent = main
listLayout(tabRow, 4, true)

local tabNames = { "Apuntar", "Filtros", "Visual" }
local tabButtons = {}
for i, name in ipairs(tabNames) do
    local b = button(tabRow, name, UDim2.new(1 / #tabNames, -3, 1, 0), PALETTE.card)
    b.TextSize = 11
    b.LayoutOrder = i
    tabButtons[i] = b
end

local pageArea = Instance.new("Frame")
pageArea.Position = UDim2.new(0, 10, 0, 148)
pageArea.Size = UDim2.new(1, -20, 1, -158)
pageArea.BackgroundTransparency = 1
pageArea.Parent = main

local pages = {}
local function newPage()
    local p = Instance.new("ScrollingFrame")
    p.Size = UDim2.new(1, 0, 1, 0)
    p.BackgroundTransparency = 1
    p.BorderSizePixel = 0
    p.ScrollBarThickness = 3
    p.ScrollBarImageColor3 = PALETTE.accent
    p.CanvasSize = UDim2.new(0, 0, 0, 0)
    p.AutomaticCanvasSize = Enum.AutomaticSize.Y
    p.Visible = false
    p.Parent = pageArea
    listLayout(p, 6)
    padding(p, 2, 2)
    table.insert(pages, p)
    return p
end

local pageApuntar = newPage()
local pageFiltros = newPage()
local pageVisual = newPage()

local function showTab(index)
    for i, p in ipairs(pages) do
        p.Visible = (i == index)
    end
    for i, b in ipairs(tabButtons) do
        b.BackgroundColor3 = (i == index) and PALETTE.accent or PALETTE.card
    end
end

for i, b in ipairs(tabButtons) do
    b.Activated:Connect(function() showTab(i) end)
end

local function nota(parent, order, height)
    local n = label(parent, "", 10, PALETTE.muted, false)
    n.LayoutOrder = order
    n.Size = UDim2.new(1, -4, 0, height)
    n.TextWrapped = true
    n.TextYAlignment = Enum.TextYAlignment.Top
    return n
end

-- Elementos a refrescar cuando cambia algo
local refreshables = {}
local function track(row)
    table.insert(refreshables, row)
    return row
end

-- Círculo de FOV y resaltado del objetivo
local fovCircle = Instance.new("Frame")
fovCircle.Name = "FovCircle"
fovCircle.AnchorPoint = Vector2.new(0.5, 0.5)
fovCircle.Position = UDim2.new(0.5, 0, 0.5, 0)
fovCircle.BackgroundTransparency = 1
fovCircle.BorderSizePixel = 0
fovCircle.Visible = false
fovCircle.Parent = gui
corner(fovCircle, 1000)
stroke(fovCircle, PALETTE.accent, 1.5, 0.2)

local highlight = Instance.new("Highlight")
highlight.FillColor = PALETTE.red
highlight.FillTransparency = 0.7
highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
highlight.OutlineTransparency = 0.2
highlight.Enabled = false
highlight.Parent = gui

local function applyVisuals()
    fovCircle.Size = UDim2.fromOffset(S.fov * 2, S.fov * 2)
    fovCircle.Visible = S.mostrarFov
    mainScale.Scale = S.escala / 100
end

---------------------------------------------------------------
-- PESTAÑA APUNTAR
---------------------------------------------------------------
track(checkRow(pageApuntar, "Auto-apuntado activado", 1,
    function() return S.activo end,
    function(v) S.activo = v markDirty() refreshUI() end))

track(numberRow(pageApuntar, 2, "Distancia",
    function() return S.radio end,
    function(v)
        S.radio = math.clamp(v, CONFIG.RADIO_MIN, CONFIG.RADIO_MAX)
        markDirty() refreshUI()
    end, 10, 64))

track(checkRow(pageApuntar, "Fijar objetivo (no perderlo de vista)", 3,
    function() return S.fijar end,
    function(v)
        S.fijar = v
        if not v then bloqueado = nil end
        markDirty() refreshUI()
    end))

local cambiarBtn = button(pageApuntar, "⟳ Cambiar de objetivo", UDim2.new(1, -4, 0, 34), PALETTE.accent)
cambiarBtn.LayoutOrder = 4
cambiarBtn.Activated:Connect(function()
    cambiarObjetivo()
    refreshUI()
end)

track(arrowRow(pageApuntar, 5,
    function() return "Apuntar a: " .. PARTES[S.parteIdx].txt end,
    function()
        S.parteIdx = S.parteIdx - 1
        if S.parteIdx < 1 then S.parteIdx = #PARTES end
        markDirty() refreshUI()
    end,
    function()
        S.parteIdx = S.parteIdx + 1
        if S.parteIdx > #PARTES then S.parteIdx = 1 end
        markDirty() refreshUI()
    end))

track(numberRow(pageApuntar, 6, "Suavizado %",
    function() return S.suavizado end,
    function(v)
        S.suavizado = math.clamp(v, 0, CONFIG.SUAVIZADO_MAX)
        markDirty() refreshUI()
    end, 5, 64))

track(arrowRow(pageApuntar, 7,
    function() return "Prioridad: " .. PRIORIDADES[S.prioIdx] end,
    function()
        S.prioIdx = S.prioIdx - 1
        if S.prioIdx < 1 then S.prioIdx = #PRIORIDADES end
        markDirty() refreshUI()
    end,
    function()
        S.prioIdx = S.prioIdx + 1
        if S.prioIdx > #PRIORIDADES then S.prioIdx = 1 end
        markDirty() refreshUI()
    end))

track(checkRow(pageApuntar, "Girar también el personaje", 8,
    function() return S.girarPersonaje end,
    function(v) S.girarPersonaje = v markDirty() refreshUI() end))

track(checkRow(pageApuntar, "Solo con clic derecho (PC)", 9,
    function() return S.soloClic end,
    function(v) S.soloClic = v markDirty() refreshUI() end))

local notaApuntar = nota(pageApuntar, 10, 58)

---------------------------------------------------------------
-- PESTAÑA FILTROS
---------------------------------------------------------------
track(arrowRow(pageFiltros, 1,
    function() return "Objetivos: " .. TIPOS[S.tipoIdx] end,
    function()
        S.tipoIdx = S.tipoIdx - 1
        if S.tipoIdx < 1 then S.tipoIdx = #TIPOS end
        markDirty() refreshUI()
    end,
    function()
        S.tipoIdx = S.tipoIdx + 1
        if S.tipoIdx > #TIPOS then S.tipoIdx = 1 end
        markDirty() refreshUI()
    end))

track(checkRow(pageFiltros, "Ignorar compañeros de equipo", 2,
    function() return S.ignorarEquipo end,
    function(v) S.ignorarEquipo = v markDirty() refreshUI() end))

track(checkRow(pageFiltros, "Ignorar si hay pared en medio", 3,
    function() return S.paredes end,
    function(v) S.paredes = v markDirty() refreshUI() end))

track(checkRow(pageFiltros, "Elegir solo objetivos en pantalla", 4,
    function() return S.soloPantalla end,
    function(v) S.soloPantalla = v markDirty() refreshUI() end))

track(checkRow(pageFiltros, "Elegir solo dentro del círculo FOV", 5,
    function() return S.usarFov end,
    function(v) S.usarFov = v markDirty() refreshUI() end))

track(numberRow(pageFiltros, 6, "Radio FOV (px)",
    function() return S.fov end,
    function(v)
        S.fov = math.clamp(v, CONFIG.FOV_MIN, CONFIG.FOV_MAX)
        markDirty() refreshUI()
    end, 10, 64))

local notaFiltros = nota(pageFiltros, 7, 58)

---------------------------------------------------------------
-- PESTAÑA VISUAL
---------------------------------------------------------------
track(checkRow(pageVisual, "Mostrar círculo FOV", 1,
    function() return S.mostrarFov end,
    function(v) S.mostrarFov = v markDirty() refreshUI() end))

track(checkRow(pageVisual, "Resaltar al objetivo", 2,
    function() return S.resaltar end,
    function(v) S.resaltar = v markDirty() refreshUI() end))

track(numberRow(pageVisual, 3, "Escala del panel %",
    function() return S.escala end,
    function(v)
        S.escala = math.clamp(v, CONFIG.ESCALA_MIN, CONFIG.ESCALA_MAX)
        markDirty() refreshUI()
    end, 10, 64))

local resetBtn = button(pageVisual, "↺ Restablecer todo", UDim2.new(1, -4, 0, 36), PALETTE.card)
resetBtn.LayoutOrder = 4
resetBtn.Activated:Connect(function()
    for k, v in pairs(DEFAULTS) do
        S[k] = v
    end
    bloqueado = nil
    markDirty()
    refreshUI()
end)

local notaVisual = nota(pageVisual, 5, 46)

---------------------------------------------------------------
-- MINIMIZAR / CERRAR
---------------------------------------------------------------
local mini = button(gui, "🎯", UDim2.fromOffset(48, 48), PALETTE.card)
mini.TextSize = 20
mini.Visible = false
stroke(mini, PALETTE.accent, 1, 0.3)

makeDraggable(mini, mini)
makeDraggable(header, main)

minBtn.Activated:Connect(function()
    main.Visible = false
    mini.Position = UDim2.fromOffset(main.AbsolutePosition.X, main.AbsolutePosition.Y)
    mini.Visible = true
end)

mini.Activated:Connect(function()
    mini.Visible = false
    main.Visible = true
end)

---------------------------------------------------------------
-- LÓGICA PRINCIPAL (cada fotograma, DESPUÉS de la cámara por defecto)
---------------------------------------------------------------
-- Se enlaza con prioridad de cámara + 1 para que se ejecute justo después del script
-- de cámara del juego; así nuestra rotación no se pisa y el objetivo no se pierde.
local function paso(dt)
    if closed then return end

    objetivoActual = nil
    local cam = Workspace.CurrentCamera
    local root = getRoot()

    if not (S.activo and cam and root and estoyVivo()) then
        bloqueado = nil
        highlight.Enabled = false
        highlight.Adornee = nil
        return
    end

    local objetivo, dist

    if S.fijar then
        -- Mantiene al objetivo fijado aunque salga de pantalla; solo lo suelta si
        -- muere, se aleja demasiado o deja de cumplir los filtros.
        local ok, d = bloqueoSigueValido(cam, root)
        if ok then
            objetivo, dist = bloqueado, d
        else
            local okBusca, nuevo = pcall(buscarMejor, cam, root)
            bloqueado = okBusca and nuevo or nil
            if bloqueado then
                objetivo = bloqueado
                dist = (bloqueado.HumanoidRootPart.Position - root.Position).Magnitude
            end
        end
    else
        bloqueado = nil
        local okBusca, nuevo = pcall(buscarMejor, cam, root)
        if okBusca and nuevo then
            objetivo = nuevo
            dist = (nuevo.HumanoidRootPart.Position - root.Position).Magnitude
        end
    end

    if objetivo then
        objetivoActual, distanciaActual = objetivo, dist

        local mantener = (not S.soloClic)
            or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)

        if mantener then
            pcall(function()
                local punto = getPuntoDeMira(objetivo)

                -- Girar la cámara hacia el objetivo
                local deseado = CFrame.new(cam.CFrame.Position, punto)
                if S.suavizado > 0 then
                    local alpha = 1 - (S.suavizado / 100) ^ (math.max(dt, 0.001) * 60)
                    cam.CFrame = cam.CFrame:Lerp(deseado, alpha)
                else
                    cam.CFrame = deseado
                end

                -- Girar también al personaje (solo en horizontal)
                if S.girarPersonaje then
                    local pos = root.Position
                    local mira = Vector3.new(punto.X, pos.Y, punto.Z)
                    if (mira - pos).Magnitude > 0.1 then
                        root.CFrame = CFrame.new(pos, mira)
                    end
                end
            end)
        end
    end

    -- Resaltado del objetivo
    if S.resaltar and objetivoActual then
        highlight.Adornee = objetivoActual
        highlight.Enabled = true
    else
        highlight.Enabled = false
        highlight.Adornee = nil
    end
end

RunService:BindToRenderStep(CONFIG.NOMBRE_RENDER, Enum.RenderPriority.Camera.Value + 1, paso)

local connections = {}

-- Teclas (PC): X enciende/apaga, C cambia de objetivo
table.insert(connections, UserInputService.InputBegan:Connect(function(input, procesado)
    if procesado or closed then return end
    if input.KeyCode == CONFIG.TECLA_ALTERNAR then
        S.activo = not S.activo
        markDirty()
        refreshUI()
    elseif input.KeyCode == CONFIG.TECLA_CAMBIAR then
        cambiarObjetivo()
        refreshUI()
    end
end))

---------------------------------------------------------------
-- ACTUALIZAR UI
---------------------------------------------------------------
refreshUI = function()
    estadoLabel.Text = S.activo and "ACTIVO" or "APAGADO"
    estadoLabel.TextColor3 = S.activo and PALETTE.green or PALETTE.red

    if objetivoActual then
        local candado = (S.fijar and bloqueado == objetivoActual) and "🔒 " or ""
        objetivoLabel.Text = string.format("%s%s · %d st", candado, nombreDe(objetivoActual), math.floor(distanciaActual + 0.5))
    else
        objetivoLabel.Text = S.activo and "Sin objetivo" or "—"
    end

    for _, r in ipairs(refreshables) do
        r.refresh()
    end

    notaApuntar.Text = string.format(
        "Con 'Fijar objetivo' la cámara sigue al mismo enemigo aunque se mueva o salga de pantalla, hasta que muera o pase de %d st. Tecla %s: encender/apagar. Tecla %s: cambiar de objetivo.",
        math.floor(S.radio * CONFIG.MARGEN_SOLTAR), CONFIG.TECLA_ALTERNAR.Name, CONFIG.TECLA_CAMBIAR.Name)
    notaFiltros.Text = "'En pantalla' y 'círculo FOV' solo se usan para ELEGIR un objetivo nuevo; una vez fijado, la cámara lo sigue donde vaya. 'Pared' lo suelta si lo tapa algo."
    notaVisual.Text = "El círculo FOV solo limita la elección si activas 'Elegir solo dentro del círculo FOV' en Filtros."

    applyVisuals()
end

closeBtn.Activated:Connect(function()
    closed = true
    S.activo = false
    pcall(function() RunService:UnbindFromRenderStep(CONFIG.NOMBRE_RENDER) end)
    for _, c in ipairs(connections) do
        c:Disconnect()
    end
    saveConfig()
    highlight:Destroy()
    gui:Destroy()
end)

showTab(1)
applyVisuals()
refreshUI()

-- Guardado automático y refresco del texto del objetivo
task.spawn(function()
    while not closed do
        if dirty then
            dirty = false
            saveConfig()
        end
        refreshUI()
        task.wait(0.2)
    end
end)
