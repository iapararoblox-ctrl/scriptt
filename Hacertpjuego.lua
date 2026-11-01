--[[
    📍 MARCADORES TP v3 · Delta (Móvil / PC)

    - Velocidad de deslizamiento ajustable (20 a 500 st/s) con deslizador y presets
    - Modo de viaje: Deslizar o Teletransporte
    - Botón ⏹ Parar para cortar el viaje en cualquier momento
    - Se recuerda todo: velocidad, modo, altura, tamaño, transparencia,
      pestaña abierta y posición del panel y del botón
    - Secciones separadas en cada pestaña y diseño renovado
    Pestañas: Marcadores | Juegos | Ajustes
]]

----------------------------------------------------------------
-- CONFIGURACIÓN
----------------------------------------------------------------
local GUI_NAME       = "TPMarkersGUI"
local FILE           = "TeleportMarkers.json"
local MAX_MARKERS    = 40
local HEADER_H       = 52
local SPEED_MIN      = 20
local SPEED_MAX      = 500
local SPEED_STEP     = 10
local PRESETS        = { { "Lenta", 60 }, { "Normal", 120 }, { "Rápida", 250 }, { "Turbo", 400 } }

local C = {
    Bg      = Color3.fromRGB(14, 16, 24),
    Card    = Color3.fromRGB(24, 27, 40),
    Card2   = Color3.fromRGB(33, 37, 54),
    Btn     = Color3.fromRGB(42, 46, 66),
    Accent  = Color3.fromRGB(96, 134, 255),
    Accent2 = Color3.fromRGB(160, 110, 255),
    Green   = Color3.fromRGB(52, 188, 126),
    Red     = Color3.fromRGB(226, 84, 96),
    Amber   = Color3.fromRGB(240, 168, 60),
    Text    = Color3.fromRGB(240, 243, 250),
    Sub     = Color3.fromRGB(146, 154, 178),
    White   = Color3.fromRGB(255, 255, 255),
}

----------------------------------------------------------------
-- SERVICIOS
----------------------------------------------------------------
local Players            = game:GetService("Players")
local UserInputService   = game:GetService("UserInputService")
local CoreGui            = game:GetService("CoreGui")
local HttpService        = game:GetService("HttpService")
local TweenService       = game:GetService("TweenService")
local RunService         = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local Workspace          = game:GetService("Workspace")

local player   = Players.LocalPlayer
local placeKey = tostring(game.PlaceId)

----------------------------------------------------------------
-- PADRE DE LA GUI + LIMPIEZA
----------------------------------------------------------------
local function getGuiParent()
    local ok, ui = pcall(function() return gethui and gethui() end)
    if ok and ui then return ui end
    local ok2 = pcall(function() return CoreGui.Name end)
    if ok2 then return CoreGui end
    return player:WaitForChild("PlayerGui")
end

local guiParent = getGuiParent()
local oldGui = guiParent:FindFirstChild(GUI_NAME)
if oldGui then oldGui:Destroy() end

----------------------------------------------------------------
-- DATOS Y AJUSTES (se guardan solos)
----------------------------------------------------------------
local function clamp(n, lo, hi) return math.max(lo, math.min(hi, n)) end
local function isPair(t) return type(t) == "table" and type(t[1]) == "number" and type(t[2]) == "number" end

local store = {
    Places   = {},
    Offset   = 3,
    Speed    = 120,
    Mode     = "DESLIZAR",
    Scale    = 100,
    Alpha    = 0,
    Tab      = 1,
    PanelPos = nil,
    FloatPos = nil,
}

pcall(function()
    if isfile and isfile(FILE) then
        local data = HttpService:JSONDecode(readfile(FILE))
        if type(data) == "table" then
            if type(data.Places) == "table" then store.Places = data.Places end
            for _, k in ipairs({ "Offset", "Speed", "Scale", "Alpha", "Tab" }) do
                if type(data[k]) == "number" then store[k] = data[k] end
            end
            if data.Mode == "TP" or data.Mode == "DESLIZAR" then store.Mode = data.Mode end
            if isPair(data.PanelPos) then store.PanelPos = data.PanelPos end
            if isPair(data.FloatPos) then store.FloatPos = data.FloatPos end
        end
    end
end)

store.Offset = clamp(store.Offset, 0, 50)
store.Speed  = clamp(store.Speed, SPEED_MIN, SPEED_MAX)
store.Scale  = clamp(store.Scale, 70, 150)
store.Alpha  = clamp(store.Alpha, 0, 60)
store.Tab    = clamp(math.floor(store.Tab), 1, 3)

-- Asegura el formato nuevo (migra el formato antiguo de la v1)
local function ensurePlace(key)
    local p = store.Places[key]
    if type(p) ~= "table" then
        p = { Markers = {} }
    elseif type(p.Markers) ~= "table" then
        p = { Markers = p }
    end
    store.Places[key] = p
    return p
end

for key in pairs(store.Places) do ensurePlace(key) end

local place    = ensurePlace(placeKey)
local markers  = place.Markers
local gameName = place.Name or ("Juego " .. placeKey)

local function save()
    pcall(function() writefile(FILE, HttpService:JSONEncode(store)) end)
end

-- Guarda como mucho una vez cada 0.6 s (evita escribir el archivo en cada cambio)
local saveQueued = false
local function queueSave()
    if saveQueued then return end
    saveQueued = true
    task.delay(0.6, function()
        saveQueued = false
        save()
    end)
end

local function validCF(t)
    if type(t) ~= "table" or #t ~= 12 then return false end
    for i = 1, 12 do
        if type(t[i]) ~= "number" then return false end
    end
    return true
end

----------------------------------------------------------------
-- ESTADO
----------------------------------------------------------------
local running, minimized = true, false
local lastCF = nil
local traveling = false
local travelId = 0
local connections = {}
local refreshers = {}

local function track(c)
    table.insert(connections, c)
    return c
end

local function refreshAll()
    for _, f in ipairs(refreshers) do f() end
end

----------------------------------------------------------------
-- HELPERS DE INTERFAZ
----------------------------------------------------------------
local function corner(obj, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 10)
    c.Parent = obj
    return c
end

local function stroke(obj, color, transparency, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color
    s.Transparency = transparency or 0
    s.Thickness = thickness or 1
    s.Parent = obj
    return s
end

local function grad(obj, c1, c2, rot)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new(c1, c2)
    g.Rotation = rot or 90
    g.Parent = obj
    return g
end

local function mkBtn(parent, text, size, pos, color, textSize)
    local b = Instance.new("TextButton")
    b.Size = size
    b.Position = pos or UDim2.new()
    b.BackgroundColor3 = color or C.Btn
    b.Text = text
    b.TextColor3 = C.Text
    b.Font = Enum.Font.GothamBold
    b.TextSize = textSize or 14
    b.AutoButtonColor = true
    b.BorderSizePixel = 0
    b.Parent = parent
    corner(b, 10)
    return b
end

local function mkLabel(parent, text, size, pos, textSize, color, bold)
    local l = Instance.new("TextLabel")
    l.Size = size
    l.Position = pos or UDim2.new()
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = color or C.Text
    l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    l.TextSize = textSize or 14
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextTruncate = Enum.TextTruncate.AtEnd
    l.Parent = parent
    return l
end

local function mkBox(parent, size, placeholder)
    local t = Instance.new("TextBox")
    t.Size = size
    t.BackgroundColor3 = C.Card
    t.Text = ""
    t.PlaceholderText = placeholder or ""
    t.PlaceholderColor3 = C.Sub
    t.TextColor3 = C.Text
    t.Font = Enum.Font.Gotham
    t.TextSize = 14
    t.ClearTextOnFocus = false
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.BorderSizePixel = 0
    t.Parent = parent
    corner(t, 10)
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 12)
    pad.PaddingRight = UDim.new(0, 12)
    pad.Parent = t
    return t
end

local function mkCard(parent, size, order)
    local f = Instance.new("Frame")
    f.Size = size
    f.BackgroundColor3 = C.Card
    f.BorderSizePixel = 0
    f.LayoutOrder = order or 0
    f.Parent = parent
    corner(f, 12)
    return f
end

local function mkSection(parent, order, text)
    local l = mkLabel(parent, text, UDim2.new(1, -4, 0, 18), nil, 10, C.Accent, true)
    l.LayoutOrder = order
    return l
end

-- Arrastrar. onTap = toque corto. onEnd = al soltar tras arrastrar (para guardar la posición)
local function makeDraggable(handle, target, onTap, onEnd)
    local dragging, moved, dragStart, startPos = false, false, nil, nil
    track(handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging, moved = true, false
            dragStart, startPos = input.Position, target.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if not moved then
                        if onTap then onTap() end
                    elseif onEnd then
                        onEnd()
                    end
                end
            end)
        end
    end))
    track(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            if d.Magnitude > 6 then moved = true end
            if moved then
                target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                            startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end
    end))
end

-- Botón de borrado con confirmación: 1er toque arma, 2º toque ejecuta
local function confirmable(btn, idleText, action)
    local armed = false
    local idleColor = btn.BackgroundColor3
    btn.Activated:Connect(function()
        if not armed then
            armed = true
            btn.Text = "¿Seguro?"
            btn.BackgroundColor3 = C.Red
            task.delay(2, function()
                if btn.Parent and armed then
                    armed = false
                    btn.Text = idleText
                    btn.BackgroundColor3 = idleColor
                end
            end)
        else
            armed = false
            btn.Text = idleText
            btn.BackgroundColor3 = idleColor
            action()
        end
    end)
end

-- Deslizador horizontal con arrastre (táctil y ratón)
local function makeSlider(parent, order, get, set, mn, mx)
    local hit = Instance.new("Frame")
    hit.Size = UDim2.new(1, 0, 0, 30)
    hit.BackgroundTransparency = 1
    hit.LayoutOrder = order
    hit.Parent = parent

    local bar = Instance.new("Frame")
    bar.AnchorPoint = Vector2.new(0, 0.5)
    bar.Position = UDim2.new(0, 0, 0.5, 0)
    bar.Size = UDim2.new(1, 0, 0, 8)
    bar.BackgroundColor3 = C.Btn
    bar.BorderSizePixel = 0
    bar.Parent = hit
    corner(bar, 4)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = C.Accent
    fill.BorderSizePixel = 0
    fill.Parent = bar
    corner(fill, 4)
    grad(fill, C.Accent, C.Accent2, 0)

    local knob = Instance.new("Frame")
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Size = UDim2.fromOffset(22, 22)
    knob.Position = UDim2.new(0, 0, 0.5, 0)
    knob.BackgroundColor3 = C.White
    knob.BorderSizePixel = 0
    knob.Parent = hit
    corner(knob, 11)
    stroke(knob, C.Accent, 0, 2)

    local dragging = false
    local function setFromX(x)
        local w = hit.AbsoluteSize.X
        if w <= 0 then return end
        local rel = clamp((x - hit.AbsolutePosition.X) / w, 0, 1)
        set(math.floor(mn + rel * (mx - mn) + 0.5))
    end

    hit.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            setFromX(input.Position.X)
        end
    end)
    track(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseMovement) then
            setFromX(input.Position.X)
        end
    end))
    track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end))

    table.insert(refreshers, function()
        local r = clamp((get() - mn) / (mx - mn), 0, 1)
        fill.Size = UDim2.new(r, 0, 1, 0)
        knob.Position = UDim2.new(r, 0, 0.5, 0)
    end)
end

----------------------------------------------------------------
-- VENTANA
----------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = guiParent

local frame = Instance.new("Frame")
frame.Position = UDim2.fromOffset(10, 56)
frame.Size = UDim2.fromOffset(320, 440)
frame.BackgroundColor3 = C.Bg
frame.BorderSizePixel = 0
frame.ClipsDescendants = true
frame.Parent = gui
corner(frame, 18)
stroke(frame, C.Accent, 0.55, 1.5)
local uiScale = Instance.new("UIScale")
uiScale.Parent = frame

-- Cabecera con degradado
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, HEADER_H)
header.BackgroundColor3 = C.Card
header.BorderSizePixel = 0
header.Active = true
header.Parent = frame
grad(header, Color3.fromRGB(70, 88, 190), Color3.fromRGB(34, 38, 60), 0)

local title = mkLabel(header, "📍 Marcadores TP", UDim2.new(1, -110, 0, 22), UDim2.new(0, 14, 0, 6), 17, C.White, true)
local subtitle = mkLabel(header, gameName, UDim2.new(1, -110, 0, 16), UDim2.new(0, 14, 0, 29), 11, Color3.fromRGB(205, 210, 235))

local minBtn   = mkBtn(header, "–", UDim2.fromOffset(34, 34), UDim2.new(1, -80, 0.5, -17), Color3.fromRGB(255, 255, 255), 16)
minBtn.BackgroundTransparency = 0.82
local closeBtn = mkBtn(header, "✕", UDim2.fromOffset(34, 34), UDim2.new(1, -40, 0.5, -17), C.Red, 14)

local body = Instance.new("Frame")
body.Size = UDim2.new(1, 0, 1, -HEADER_H)
body.Position = UDim2.new(0, 0, 0, HEADER_H)
body.BackgroundTransparency = 1
body.Parent = frame

-- Pestañas en forma de píldora
local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -16, 0, 40)
tabBar.Position = UDim2.new(0, 8, 0, 8)
tabBar.BackgroundTransparency = 1
tabBar.Parent = body
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 6)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Parent = tabBar

local content = Instance.new("Frame")
content.Size = UDim2.new(1, -16, 1, -62)
content.Position = UDim2.new(0, 8, 0, 54)
content.BackgroundTransparency = 1
content.Parent = body

local function newScroll()
    local s = Instance.new("ScrollingFrame")
    s.Size = UDim2.new(1, 0, 1, 0)
    s.BackgroundTransparency = 1
    s.BorderSizePixel = 0
    s.ScrollBarThickness = 3
    s.ScrollBarImageColor3 = C.Accent
    s.CanvasSize = UDim2.new()
    s.AutomaticCanvasSize = Enum.AutomaticSize.Y
    s.ScrollingDirection = Enum.ScrollingDirection.Y
    s.Visible = false
    s.Parent = content
    local l = Instance.new("UIListLayout")
    l.Padding = UDim.new(0, 8)
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Parent = s
    local pad = Instance.new("UIPadding")
    pad.PaddingRight = UDim.new(0, 6)
    pad.PaddingBottom = UDim.new(0, 10)
    pad.Parent = s
    return s
end

local pMark = newScroll()
local pGames = newScroll()
local pSet = newScroll()

local tabs = {}
local function selectTab(i, silent)
    for idx, t in ipairs(tabs) do
        t.page.Visible = (idx == i)
        t.btn.BackgroundColor3 = (idx == i) and C.Accent or C.Card
        t.btn.TextColor3 = (idx == i) and C.White or C.Sub
    end
    store.Tab = i
    if not silent then queueSave() end
end

local function addTab(text, page)
    local b = mkBtn(tabBar, text, UDim2.new(1 / 3, -4, 1, 0), nil, C.Card, 13)
    table.insert(tabs, { btn = b, page = page })
    local idx = #tabs
    b.Activated:Connect(function() selectTab(idx) end)
end

addTab("📍 Marcadores", pMark)
addTab("🎮 Juegos", pGames)
addTab("⚙ Ajustes", pSet)

----------------------------------------------------------------
-- AVISOS FLOTANTES
----------------------------------------------------------------
local toastLabel = Instance.new("TextLabel")
toastLabel.AnchorPoint = Vector2.new(0.5, 1)
toastLabel.Position = UDim2.new(0.5, 0, 1, -28)
toastLabel.Size = UDim2.fromOffset(0, 36)
toastLabel.AutomaticSize = Enum.AutomaticSize.X
toastLabel.BackgroundColor3 = C.Card
toastLabel.BackgroundTransparency = 1
toastLabel.TextTransparency = 1
toastLabel.TextColor3 = C.Text
toastLabel.Font = Enum.Font.GothamBold
toastLabel.TextSize = 14
toastLabel.ZIndex = 50
toastLabel.Parent = gui
corner(toastLabel, 18)
local toastPad = Instance.new("UIPadding")
toastPad.PaddingLeft = UDim.new(0, 18)
toastPad.PaddingRight = UDim.new(0, 18)
toastPad.Parent = toastLabel
local toastStroke = stroke(toastLabel, C.Accent, 1, 1.5)

local toastToken = 0
local function toast(text)
    toastToken = toastToken + 1
    local my = toastToken
    toastLabel.Text = text
    local info = TweenInfo.new(0.2)
    TweenService:Create(toastLabel, info, { BackgroundTransparency = 0.05, TextTransparency = 0 }):Play()
    TweenService:Create(toastStroke, info, { Transparency = 0.2 }):Play()
    task.delay(2.2, function()
        if toastToken == my and toastLabel.Parent then
            TweenService:Create(toastLabel, info, { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
            TweenService:Create(toastStroke, info, { Transparency = 1 }):Play()
        end
    end)
end

----------------------------------------------------------------
-- BOTÓN FLOTANTE
----------------------------------------------------------------
local floatBtn = Instance.new("TextButton")
floatBtn.Size = UDim2.fromOffset(54, 54)
floatBtn.Position = UDim2.fromOffset(300, 300)
floatBtn.BackgroundColor3 = C.Accent
floatBtn.Text = "📍"
floatBtn.TextSize = 24
floatBtn.Font = Enum.Font.GothamBold
floatBtn.TextColor3 = C.White
floatBtn.AutoButtonColor = false
floatBtn.BorderSizePixel = 0
floatBtn.ZIndex = 20
floatBtn.Parent = gui
corner(floatBtn, 27)
stroke(floatBtn, C.White, 0.25, 2)
grad(floatBtn, Color3.fromRGB(130, 166, 255), Color3.fromRGB(70, 100, 220), 90)

----------------------------------------------------------------
-- LÓGICA: VELOCIDAD, MODO Y VIAJE
----------------------------------------------------------------
local function setSpeed(v)
    store.Speed = clamp(math.floor(v + 0.5), SPEED_MIN, SPEED_MAX)
    queueSave()
    refreshAll()
end

local function setMode(m)
    store.Mode = m
    queueSave()
    refreshAll()
    toast(m == "TP" and "⚡ Modo teletransporte" or "🛫 Modo deslizar")
end

local function getHRP()
    local char = player.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function stopTravel(silent)
    if traveling then
        travelId = travelId + 1
        traveling = false
        if not silent then toast("⏹ Viaje detenido") end
    elseif not silent then
        toast("No hay ningún viaje en curso")
    end
end

-- Desliza hasta la posición final a la velocidad elegida (studs por segundo)
local function slideTo(finalCF, nombre)
    travelId = travelId + 1
    local my = travelId
    traveling = true

    task.spawn(function()
        local ok, err = pcall(function()
            local hrp = getHRP()
            if not hrp then
                toast("⚠ No hay personaje")
                return
            end

            local startPos = hrp.Position
            local endPos = finalCF.Position
            local dist = (endPos - startPos).Magnitude
            local dur = math.max(dist / store.Speed, 0.05)
            local t0 = os.clock()

            while my == travelId do
                local root = getHRP()
                if not root then break end
                local a = math.min((os.clock() - t0) / dur, 1)
                root.AssemblyLinearVelocity = Vector3.zero
                root.CFrame = CFrame.new(startPos:Lerp(endPos, a)) * (root.CFrame - root.CFrame.Position)
                if a >= 1 then
                    root.CFrame = finalCF
                    toast("✔ Llegaste a " .. nombre)
                    break
                end
                RunService.Heartbeat:Wait()
            end
        end)
        if not ok then
            warn("[MARCADORES] " .. tostring(err))
        end
        if my == travelId then
            traveling = false
        end
    end)
end

local function travelTo(m)
    if not validCF(m.CF) then toast("⚠ Marcador dañado") return end
    local hrp = getHRP()
    if not hrp then toast("⚠ No hay personaje") return end

    if traveling then
        stopTravel(true)
    end

    lastCF = hrp.CFrame
    local finalCF = CFrame.new(table.unpack(m.CF)) + Vector3.new(0, store.Offset, 0)

    if store.Mode == "TP" then
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.CFrame = finalCF
        toast("✔ " .. m.Name)
    else
        toast("🛫 Yendo a " .. m.Name .. " · " .. store.Speed .. " st/s")
        slideTo(finalCF, m.Name)
    end
end

----------------------------------------------------------------
-- PESTAÑA 1: MARCADORES
----------------------------------------------------------------
local rebuildMarkers, rebuildGames

mkSection(pMark, 1, "GUARDAR POSICIÓN")

local nameBox = mkBox(pMark, UDim2.new(1, -4, 0, 42), "Nombre del marcador (opcional)")
nameBox.LayoutOrder = 2

local saveBtn = mkBtn(pMark, "📍  Guardar posición actual", UDim2.new(1, -4, 0, 46), nil, C.Green, 15)
saveBtn.LayoutOrder = 3
grad(saveBtn, Color3.fromRGB(64, 206, 140), Color3.fromRGB(40, 150, 98), 90)

local navRow = Instance.new("Frame")
navRow.Size = UDim2.new(1, -4, 0, 44)
navRow.BackgroundTransparency = 1
navRow.LayoutOrder = 4
navRow.Parent = pMark
local navLayout = Instance.new("UIListLayout")
navLayout.FillDirection = Enum.FillDirection.Horizontal
navLayout.Padding = UDim.new(0, 6)
navLayout.Parent = navRow

local backBtn = mkBtn(navRow, "↩  Volver", UDim2.new(0.5, -3, 1, 0), nil, C.Amber, 14)
local stopBtn = mkBtn(navRow, "⏹  Parar viaje", UDim2.new(0.5, -3, 1, 0), nil, C.Red, 14)

-- Píldora con el modo y la velocidad actuales (toca para ir a Ajustes)
local modePill = mkBtn(pMark, "", UDim2.new(1, -4, 0, 42), nil, C.Card2, 13)
modePill.LayoutOrder = 5
modePill.TextXAlignment = Enum.TextXAlignment.Left
local pillPad = Instance.new("UIPadding")
pillPad.PaddingLeft = UDim.new(0, 14)
pillPad.Parent = modePill
modePill.Activated:Connect(function() selectTab(3) end)

local sectionPuntos = mkSection(pMark, 6, "MIS PUNTOS")

local emptyLabel = mkLabel(pMark, "Aún no hay marcadores.\nMuévete a un lugar y pulsa Guardar.",
    UDim2.new(1, -4, 0, 50), nil, 13, C.Sub)
emptyLabel.TextWrapped = true
emptyLabel.TextXAlignment = Enum.TextXAlignment.Center
emptyLabel.LayoutOrder = 7

local function addMarker()
    local hrp = getHRP()
    if not hrp then toast("⚠ No hay personaje") return end
    if #markers >= MAX_MARKERS then toast("⚠ Máximo " .. MAX_MARKERS .. " marcadores") return end
    local name = (nameBox.Text:gsub("^%s+", ""):gsub("%s+$", ""))
    if name == "" then name = "Punto " .. (#markers + 1) end
    name = string.sub(name, 1, 24)
    table.insert(markers, { Name = name, CF = { hrp.CFrame:GetComponents() } })
    nameBox.Text = ""
    save()
    rebuildMarkers()
    rebuildGames()
    toast("💾 Guardado: " .. name)
end

function rebuildMarkers()
    for _, c in ipairs(pMark:GetChildren()) do
        if c.Name == "MRow" then c:Destroy() end
    end
    emptyLabel.Visible = (#markers == 0)
    sectionPuntos.Text = "MIS PUNTOS · " .. #markers .. "/" .. MAX_MARKERS

    for i, m in ipairs(markers) do
        local row = Instance.new("Frame")
        row.Name = "MRow"
        row.Size = UDim2.new(1, -4, 0, 56)
        row.BackgroundTransparency = 1
        row.LayoutOrder = 100 + i
        row.Parent = pMark

        local go = mkCard(row, UDim2.new(1, -54, 1, 0), 0)
        go.BackgroundColor3 = C.Card
        local go2 = Instance.new("TextButton")
        go2.Size = UDim2.new(1, 0, 1, 0)
        go2.BackgroundTransparency = 1
        go2.Text = ""
        go2.Parent = go

        local bar = Instance.new("Frame")
        bar.Size = UDim2.new(0, 4, 0.6, 0)
        bar.Position = UDim2.new(0, 0, 0.2, 0)
        bar.BackgroundColor3 = C.Accent
        bar.BorderSizePixel = 0
        bar.Parent = go
        corner(bar, 2)

        local nameL = mkLabel(go, m.Name, UDim2.new(1, -28, 0, 22), UDim2.new(0, 14, 0, 7), 15, C.Text, true)
        local coords = "?"
        if validCF(m.CF) then
            coords = string.format("%.0f, %.0f, %.0f", m.CF[1], m.CF[2], m.CF[3])
        end
        mkLabel(go, coords, UDim2.new(1, -28, 0, 16), UDim2.new(0, 14, 0, 30), 11, C.Sub)

        go2.Activated:Connect(function() travelTo(m) end)

        local del = mkBtn(row, "🗑", UDim2.new(0, 46, 1, 0), UDim2.new(1, -46, 0, 0), C.Btn, 18)
        confirmable(del, "🗑", function()
            local idx = table.find(markers, m)
            if idx then table.remove(markers, idx) end
            save()
            rebuildMarkers()
            rebuildGames()
            toast("Marcador borrado")
        end)
    end
end

saveBtn.Activated:Connect(addMarker)

backBtn.Activated:Connect(function()
    if not lastCF then toast("Aún no hay posición anterior") return end
    local hrp = getHRP()
    if not hrp then toast("⚠ No hay personaje") return end
    stopTravel(true)
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.CFrame = lastCF
    lastCF = nil
    toast("↩ Has vuelto")
end)

stopBtn.Activated:Connect(function() stopTravel(false) end)

table.insert(refreshers, function()
    if store.Mode == "TP" then
        modePill.Text = "⚡  Teletransporte          ›"
    else
        modePill.Text = "🛫  Deslizar · " .. store.Speed .. " st/s          ›"
    end
end)

----------------------------------------------------------------
-- PESTAÑA 2: JUEGOS
----------------------------------------------------------------
local curCard = mkCard(pGames, UDim2.new(1, -4, 0, 78), 1)
stroke(curCard, C.Accent, 0.4, 1.5)
grad(curCard, Color3.fromRGB(40, 50, 90), C.Card, 90)
local curTag = mkLabel(curCard, "JUEGO ACTUAL", UDim2.new(1, -24, 0, 14), UDim2.new(0, 14, 0, 10), 10, C.Accent, true)
local curName = mkLabel(curCard, gameName, UDim2.new(1, -24, 0, 22), UDim2.new(0, 14, 0, 24), 16, C.Text, true)
local curInfo = mkLabel(curCard, "", UDim2.new(1, -24, 0, 16), UDim2.new(0, 14, 0, 52), 12, C.Sub)

mkSection(pGames, 2, "ACCIONES")

local actRow = Instance.new("Frame")
actRow.Size = UDim2.new(1, -4, 0, 42)
actRow.BackgroundTransparency = 1
actRow.LayoutOrder = 3
actRow.Parent = pGames
local actLayout = Instance.new("UIListLayout")
actLayout.FillDirection = Enum.FillDirection.Horizontal
actLayout.Padding = UDim.new(0, 6)
actLayout.Parent = actRow
local copyBtn = mkBtn(actRow, "📋 Copiar", UDim2.new(0.5, -3, 1, 0), nil, C.Accent, 14)
local clearBtn = mkBtn(actRow, "🗑 Borrar todo", UDim2.new(0.5, -3, 1, 0), nil, C.Btn, 14)

mkSection(pGames, 4, "IMPORTAR")
local importBox = mkBox(pGames, UDim2.new(1, -4, 0, 42), "Pega aquí marcadores copiados")
importBox.LayoutOrder = 5
local importBtn = mkBtn(pGames, "⬇ Importar a este juego", UDim2.new(1, -4, 0, 42), nil, C.Green, 14)
importBtn.LayoutOrder = 6

mkSection(pGames, 7, "OTROS JUEGOS GUARDADOS")
local noOthers = mkLabel(pGames, "Aún no guardaste marcadores en otros juegos.",
    UDim2.new(1, -4, 0, 36), nil, 12, C.Sub)
noOthers.TextWrapped = true
noOthers.LayoutOrder = 8

function rebuildGames()
    curName.Text = gameName
    curInfo.Text = string.format("%d / %d marcadores  ·  ID %s", #markers, MAX_MARKERS, placeKey)

    for _, c in ipairs(pGames:GetChildren()) do
        if c.Name == "GRow" then c:Destroy() end
    end

    local others = {}
    for key, p in pairs(store.Places) do
        if key ~= placeKey and type(p.Markers) == "table" and #p.Markers > 0 then
            table.insert(others, { Key = key, Name = p.Name or ("Juego " .. key), Count = #p.Markers })
        end
    end
    table.sort(others, function(a, b) return a.Name:lower() < b.Name:lower() end)
    noOthers.Visible = (#others == 0)

    for i, g in ipairs(others) do
        local row = mkCard(pGames, UDim2.new(1, -4, 0, 58), 100 + i)
        row.Name = "GRow"
        mkLabel(row, g.Name, UDim2.new(1, -110, 0, 22), UDim2.new(0, 14, 0, 8), 14, C.Text, true)
        mkLabel(row, g.Count .. " marcadores · ID " .. g.Key, UDim2.new(1, -110, 0, 16), UDim2.new(0, 14, 0, 32), 11, C.Sub)
        local del = mkBtn(row, "Borrar", UDim2.fromOffset(84, 34), UDim2.new(1, -94, 0.5, -17), C.Btn, 12)
        confirmable(del, "Borrar", function()
            store.Places[g.Key] = nil
            save()
            rebuildGames()
            toast("Datos de " .. g.Name .. " borrados")
        end)
    end
end

copyBtn.Activated:Connect(function()
    if #markers == 0 then toast("No hay marcadores que copiar") return end
    if not setclipboard then toast("⚠ Tu ejecutor no soporta copiar") return end
    local ok = pcall(function() setclipboard(HttpService:JSONEncode(markers)) end)
    toast(ok and "📋 Copiado al portapapeles" or "⚠ No se pudo copiar")
end)

clearBtn.Activated:Connect(function()
    -- Usa el mismo sistema de confirmación que el resto de botones de borrado
end)
confirmable(clearBtn, "🗑 Borrar todo", function()
    table.clear(markers)
    save()
    rebuildMarkers()
    rebuildGames()
    toast("Marcadores de este juego borrados")
end)

importBtn.Activated:Connect(function()
    local text = importBox.Text
    if text == "" then toast("Pega primero los marcadores") return end
    local ok, data = pcall(function() return HttpService:JSONDecode(text) end)
    if not ok or type(data) ~= "table" then toast("⚠ Texto no válido") return end
    local added = 0
    for _, m in ipairs(data) do
        if #markers >= MAX_MARKERS then break end
        if type(m) == "table" and type(m.Name) == "string" and validCF(m.CF) then
            table.insert(markers, { Name = string.sub(m.Name, 1, 24), CF = m.CF })
            added = added + 1
        end
    end
    importBox.Text = ""
    if added > 0 then
        save()
        rebuildMarkers()
        rebuildGames()
    end
    toast("⬇ Importados: " .. added)
end)

----------------------------------------------------------------
-- PESTAÑA 3: AJUSTES
----------------------------------------------------------------
local function addStepper(parent, order, text, get, set, mn, mx, step, suffix)
    local row = mkCard(parent, UDim2.new(1, -4, 0, 50), order)
    mkLabel(row, text, UDim2.new(1, -160, 1, 0), UDim2.new(0, 14, 0, 0), 13, C.Text, true)
    local minus = mkBtn(row, "–", UDim2.fromOffset(40, 36), UDim2.new(1, -150, 0.5, -18), C.Btn, 18)
    local val = mkLabel(row, "", UDim2.fromOffset(60, 36), UDim2.new(1, -106, 0.5, -18), 13, C.Accent, true)
    val.TextXAlignment = Enum.TextXAlignment.Center
    local plus = mkBtn(row, "+", UDim2.fromOffset(40, 36), UDim2.new(1, -44, 0.5, -18), C.Btn, 18)

    local function refresh() val.Text = tostring(get()) .. suffix end
    local function change(delta)
        set(clamp(get() + delta, mn, mx))
        refresh()
        queueSave()
    end
    minus.Activated:Connect(function() change(-step) end)
    plus.Activated:Connect(function() change(step) end)
    table.insert(refreshers, refresh)
    refresh()
end

mkSection(pSet, 1, "VIAJE")

-- Modo: Deslizar / Teletransporte
local modeCard = mkCard(pSet, UDim2.new(1, -4, 0, 52), 2)
local btnModoDes = mkBtn(modeCard, "🛫 Deslizar", UDim2.new(0.5, -9, 1, -12), UDim2.new(0, 6, 0, 6), C.Btn, 13)
local btnModoTP = mkBtn(modeCard, "⚡ Teletransporte", UDim2.new(0.5, -9, 1, -12), UDim2.new(0.5, 3, 0, 6), C.Btn, 13)
btnModoDes.Activated:Connect(function() setMode("DESLIZAR") end)
btnModoTP.Activated:Connect(function() setMode("TP") end)
table.insert(refreshers, function()
    local des = store.Mode == "DESLIZAR"
    btnModoDes.BackgroundColor3 = des and C.Accent or C.Btn
    btnModoTP.BackgroundColor3 = (not des) and C.Accent or C.Btn
end)

-- Velocidad: tarjeta con valor, deslizador, −/+ y presets
local speedCard = Instance.new("Frame")
speedCard.Size = UDim2.new(1, -4, 0, 0)
speedCard.AutomaticSize = Enum.AutomaticSize.Y
speedCard.BackgroundColor3 = C.Card
speedCard.BorderSizePixel = 0
speedCard.LayoutOrder = 3
speedCard.Parent = pSet
corner(speedCard, 12)
stroke(speedCard, C.Accent, 0.6, 1)
local spPad = Instance.new("UIPadding")
spPad.PaddingLeft = UDim.new(0, 12)
spPad.PaddingRight = UDim.new(0, 12)
spPad.PaddingTop = UDim.new(0, 12)
spPad.PaddingBottom = UDim.new(0, 12)
spPad.Parent = speedCard
local spLayout = Instance.new("UIListLayout")
spLayout.Padding = UDim.new(0, 10)
spLayout.SortOrder = Enum.SortOrder.LayoutOrder
spLayout.Parent = speedCard

local valueRow = Instance.new("Frame")
valueRow.Size = UDim2.new(1, 0, 0, 44)
valueRow.BackgroundTransparency = 1
valueRow.LayoutOrder = 1
valueRow.Parent = speedCard

local spMinus = mkBtn(valueRow, "–", UDim2.fromOffset(44, 40), UDim2.new(0, 0, 0.5, -20), C.Btn, 20)
local spPlus = mkBtn(valueRow, "+", UDim2.fromOffset(44, 40), UDim2.new(1, -44, 0.5, -20), C.Btn, 20)
local spValue = mkLabel(valueRow, "", UDim2.new(1, -100, 1, 0), UDim2.new(0, 50, 0, 0), 22, C.Accent, true)
spValue.TextXAlignment = Enum.TextXAlignment.Center

spMinus.Activated:Connect(function() setSpeed(store.Speed - SPEED_STEP) end)
spPlus.Activated:Connect(function() setSpeed(store.Speed + SPEED_STEP) end)

makeSlider(speedCard, 2,
    function() return store.Speed end,
    function(v) setSpeed(v) end,
    SPEED_MIN, SPEED_MAX)

local presetRow = Instance.new("Frame")
presetRow.Size = UDim2.new(1, 0, 0, 34)
presetRow.BackgroundTransparency = 1
presetRow.LayoutOrder = 3
presetRow.Parent = speedCard
local presetLayout = Instance.new("UIListLayout")
presetLayout.FillDirection = Enum.FillDirection.Horizontal
presetLayout.Padding = UDim.new(0, 6)
presetLayout.Parent = presetRow

local presetBtns = {}
for i, p in ipairs(PRESETS) do
    local b = mkBtn(presetRow, p[1], UDim2.new(0.25, -5, 1, 0), nil, C.Btn, 12)
    b.Text = p[1] .. " " .. p[2]
    b.Activated:Connect(function() setSpeed(p[2]) end)
    presetBtns[i] = { btn = b, value = p[2] }
end

table.insert(refreshers, function()
    spValue.Text = store.Speed .. " st/s"
    for _, pb in ipairs(presetBtns) do
        pb.btn.BackgroundColor3 = (pb.value == store.Speed) and C.Accent or C.Btn
    end
end)

mkSection(pSet, 4, "")
addStepper(pSet, 5, "Altura extra al viajar", function() return store.Offset end,
    function(v) store.Offset = v end, 0, 50, 1, " st")

mkSection(pSet, 6, "APARIENCIA")
addStepper(pSet, 7, "Tamaño de interfaz", function() return store.Scale end,
    function(v) store.Scale = v; layoutFrame() end, 70, 150, 10, "%")
addStepper(pSet, 8, "Transparencia", function() return store.Alpha end,
    function(v) store.Alpha = v; frame.BackgroundTransparency = v / 100 end, 0, 60, 10, "%")

mkSection(pSet, 9, "DATOS")
local resetBtn = mkBtn(pSet, "Restaurar ajustes", UDim2.new(1, -4, 0, 42), nil, C.Btn, 14)
resetBtn.LayoutOrder = 10
resetBtn.Activated:Connect(function()
    store.Offset = 3
    store.Speed = 120
    store.Mode = "DESLIZAR"
    store.Scale = 100
    store.Alpha = 0
    frame.BackgroundTransparency = 0
    layoutFrame()
    refreshAll()
    save()
    toast("Ajustes restaurados")
end)

local canSave = (writefile ~= nil and readfile ~= nil)
local infoLabel = mkLabel(pSet,
    canSave and "💾 Todo se guarda solo: velocidad, modo, tamaño, pestaña y posiciones."
        or "⚠ Tu ejecutor no soporta writefile/readfile: no se guardará nada al cerrar.",
    UDim2.new(1, -4, 0, 46), nil, 12, canSave and C.Sub or C.Amber)
infoLabel.TextWrapped = true
infoLabel.TextTruncate = Enum.TextTruncate.None
infoLabel.TextYAlignment = Enum.TextYAlignment.Top
infoLabel.LayoutOrder = 11

----------------------------------------------------------------
-- DISEÑO ADAPTABLE (móvil / PC)
----------------------------------------------------------------
function layoutFrame()
    local cam = Workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(800, 600)
    local sc = store.Scale / 100
    uiScale.Scale = sc
    local w = clamp(vp.X * 0.92 / sc, 250, 340)
    local h = clamp(vp.Y * 0.80 / sc, 230, 480)
    frame.Size = minimized and UDim2.fromOffset(w, HEADER_H) or UDim2.fromOffset(w, h)
end

local function applyPositions()
    local cam = Workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(800, 600)
    local p = store.PanelPos or { 10, 56 }
    frame.Position = UDim2.fromOffset(
        clamp(p[1], 0, math.max(0, vp.X - 120)),
        clamp(p[2], 0, math.max(0, vp.Y - 60))
    )
    local f = store.FloatPos or { vp.X - 68, vp.Y * 0.6 }
    floatBtn.Position = UDim2.fromOffset(
        clamp(f[1], 0, math.max(0, vp.X - 54)),
        clamp(f[2], 0, math.max(0, vp.Y - 54))
    )
end

do
    local cam = Workspace.CurrentCamera
    if cam then
        track(cam:GetPropertyChangedSignal("ViewportSize"):Connect(layoutFrame))
    end
end

----------------------------------------------------------------
-- CONTROLES DE VENTANA
----------------------------------------------------------------
minBtn.Activated:Connect(function()
    minimized = not minimized
    body.Visible = not minimized
    minBtn.Text = minimized and "+" or "–"
    layoutFrame()
end)

makeDraggable(header, frame, nil, function()
    store.PanelPos = { frame.Position.X.Offset, frame.Position.Y.Offset }
    queueSave()
end)

makeDraggable(floatBtn, floatBtn,
    function() frame.Visible = not frame.Visible end,
    function()
        store.FloatPos = { floatBtn.Position.X.Offset, floatBtn.Position.Y.Offset }
        queueSave()
    end)

closeBtn.Activated:Connect(function()
    running = false
    stopTravel(true)
    save()
    for _, c in ipairs(connections) do c:Disconnect() end
    gui:Destroy()
end)

----------------------------------------------------------------
-- INICIO
----------------------------------------------------------------
frame.BackgroundTransparency = store.Alpha / 100
applyPositions()
layoutFrame()
selectTab(store.Tab, true)
rebuildMarkers()
rebuildGames()
refreshAll()
toast("📍 " .. #markers .. " marcadores en este juego")

-- Nombre real del juego (sin bloquear el resto)
task.spawn(function()
    local ok, info = pcall(function() return MarketplaceService:GetProductInfo(game.PlaceId) end)
    if ok and type(info) == "table" and type(info.Name) == "string" and running then
        place.Name = info.Name
        gameName = info.Name
        subtitle.Text = gameName
        curName.Text = gameName
        queueSave()
        rebuildGames()
    end
end)
