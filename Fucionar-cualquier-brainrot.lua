--[[
    AUTO-RECOLECTOR DE MONEDAS para "Fusiona cualquier cosa en Brainrot"
    Delta (Mobile/PC)

    - Busca tus corrales (Pen_piso_número) y llama a PenService.RF.CollectCoins
    - Botón flotante 💰 ON/OFF (toque corto) y arrastrable
    - Intervalo entre rondas y pausa entre llamadas ajustables
    - Modo de posición: colector (desde lejos) o tu personaje
    - Muestra cobradas / vacías / errores y el último error del servidor
    - Guarda tus ajustes por juego (writefile/readfile)
]]

----------------------------------------------------------------
-- CONFIGURACIÓN
----------------------------------------------------------------
local GUI_NAME = "AutoCollectGUI"
local FILE     = "AutoCollect_" .. game.PlaceId .. ".json"
local HEADER_H = 46

local C = {
    Bg = Color3.fromRGB(16, 18, 26), Card = Color3.fromRGB(28, 31, 43), Btn = Color3.fromRGB(44, 48, 64),
    Accent = Color3.fromRGB(90, 130, 255), Green = Color3.fromRGB(46, 160, 105),
    Red = Color3.fromRGB(200, 70, 80), Amber = Color3.fromRGB(214, 150, 40),
    Text = Color3.fromRGB(235, 238, 245), Sub = Color3.fromRGB(150, 158, 178),
}

----------------------------------------------------------------
-- SERVICIOS
----------------------------------------------------------------
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local CoreGui           = game:GetService("CoreGui")
local HttpService       = game:GetService("HttpService")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local function getGuiParent()
    local ok, ui = pcall(function() return gethui and gethui() end)
    if ok and ui then return ui end
    local ok2 = pcall(function() return CoreGui.Name end)
    if ok2 then return CoreGui end
    return player:WaitForChild("PlayerGui")
end

local guiParent = getGuiParent()
local old = guiParent:FindFirstChild(GUI_NAME)
if old then old:Destroy() end

local function clamp(n, lo, hi) return math.max(lo, math.min(hi, n)) end

----------------------------------------------------------------
-- AJUSTES (se guardan por juego)
----------------------------------------------------------------
local S = { Interval = 15, Delay = 200, Mode = 1 } -- segundos, milisegundos, 1=colector 2=personaje
pcall(function()
    if isfile and isfile(FILE) then
        local d = HttpService:JSONDecode(readfile(FILE))
        if type(d) == "table" then
            for k in pairs(S) do
                if type(d[k]) == "number" then S[k] = d[k] end
            end
        end
    end
end)
S.Interval = clamp(S.Interval, 5, 300)
S.Delay    = clamp(S.Delay, 50, 1000)
S.Mode     = (S.Mode == 2) and 2 or 1

local function save()
    pcall(function() writefile(FILE, HttpService:JSONEncode(S)) end)
end

----------------------------------------------------------------
-- ESTADO
----------------------------------------------------------------
local running, enabled, busy, minimized = true, false, false, false
local connections = {}
local function track(c) table.insert(connections, c) return c end

local pens, lastScan = {}, 0
local stats = { ok = 0, empty = 0, err = 0, rounds = 0 }
local lastError, statusText = "", "Listo."

----------------------------------------------------------------
-- LÓGICA: remote, corrales y recolección
----------------------------------------------------------------
local remoteCache
local function getRemote()
    if remoteCache and remoteCache.Parent then return remoteCache end
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d.Name == "CollectCoins" and d.ClassName == "RemoteFunction"
            and d.Parent and d.Parent.Name == "RF"
            and d.Parent.Parent and d.Parent.Parent.Name == "PenService" then
            remoteCache = d
            return d
        end
    end
    return nil
end

-- ¿Este modelo pertenece a mi rancho?
local function isMine(model)
    local cur = model.Parent
    while cur and cur ~= Workspace do
        local owner = cur:GetAttribute("OwnerUserId")
        if owner ~= nil then return owner == player.UserId end
        if cur.Name:find("^Ranch_%d+_") then
            if cur.Name:find(player.Name, 1, true) or cur.Name:find(player.DisplayName, 1, true) then
                return true
            end
        end
        cur = cur.Parent
    end
    return false
end

local function scanPens()
    local found, seen, n = {}, {}, 0
    for _, d in ipairs(Workspace:GetDescendants()) do
        n += 1
        if n % 500 == 0 then task.wait() end -- no congela el móvil
        local f, s = d.Name:match("^Pen_(%d+)_(%d+)$")
        if f and not seen[f .. "_" .. s] then
            local col = d:FindFirstChild("Collector")
            if col and col:IsA("BasePart") and isMine(d) then
                seen[f .. "_" .. s] = true
                found[#found + 1] = { id = f .. "_" .. s, floor = tonumber(f), slot = tonumber(s), collector = col }
            end
        end
    end
    table.sort(found, function(a, b)
        if a.floor ~= b.floor then return a.floor < b.floor end
        return a.slot < b.slot
    end)
    pens, lastScan = found, os.clock()
end

local function getPos(p)
    if S.Mode == 2 then
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then return hrp.Position end
    end
    return p.collector.Position + Vector3.new(0, 3, 0)
end

-- Una ronda: recoge de todos tus corrales. keepGoing() decide si se sigue.
local function runCycle(keepGoing)
    if busy then return end
    busy = true
    local remote = getRemote()
    if not remote then
        lastError = "No encontré PenService.CollectCoins"
        busy = false
        return
    end
    if #pens == 0 or os.clock() - lastScan > 60 then scanPens() end
    if #pens == 0 then
        lastError = "No encontré tus corrales"
        busy = false
        return
    end

    for _, p in ipairs(pens) do
        if not running or not keepGoing() then break end
        local ok, res = pcall(function() return remote:InvokeServer(p.id, getPos(p)) end)
        if not ok then
            stats.err += 1
            lastError = tostring(res):sub(1, 60)
        elseif type(res) == "table" then
            if res.success then
                stats.ok += 1
            elseif res.error == "no_coins" then
                stats.empty += 1
            else
                stats.err += 1
                lastError = tostring(res.error)
            end
        else
            stats.err += 1
            lastError = "respuesta inesperada"
        end
        task.wait(S.Delay / 1000)
    end
    stats.rounds += 1
    busy = false
end

----------------------------------------------------------------
-- INTERFAZ
----------------------------------------------------------------
local function corner(obj, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 10)
    c.Parent = obj
end

local function makeButton(parent, text, size, pos, color)
    local b = Instance.new("TextButton")
    b.Size = size
    b.Position = pos or UDim2.new()
    b.BackgroundColor3 = color or C.Btn
    b.Text = text
    b.TextColor3 = C.Text
    b.Font = Enum.Font.GothamBold
    b.TextSize = 14
    b.Parent = parent
    corner(b, 10)
    return b
end

local function makeLabel(parent, text, size, pos, textSize, color)
    local l = Instance.new("TextLabel")
    l.Size = size
    l.Position = pos or UDim2.new()
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = color or C.Text
    l.Font = Enum.Font.Gotham
    l.TextSize = textSize or 14
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Top
    l.TextWrapped = true
    l.Parent = parent
    return l
end

local function makeDraggable(handle, target, onTap)
    local dragging, moved, dragStart, startPos = false, false, nil, nil
    track(handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging, moved = true, false
            dragStart, startPos = input.Position, target.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if not moved and onTap then onTap() end
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

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = guiParent

local frame = Instance.new("Frame")
frame.Position = UDim2.new(0, 10, 0, 56)
frame.BackgroundColor3 = C.Bg
frame.BorderSizePixel = 0
frame.ClipsDescendants = true
frame.Parent = gui
corner(frame, 16)
local fs = Instance.new("UIStroke", frame)
fs.Color, fs.Transparency, fs.Thickness = C.Accent, 0.6, 1.5

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, HEADER_H)
header.BackgroundColor3 = C.Card
header.BorderSizePixel = 0
header.Active = true
header.Parent = frame
local grad = Instance.new("UIGradient")
grad.Color = ColorSequence.new(Color3.fromRGB(60, 80, 160), C.Card)
grad.Parent = header

makeLabel(header, "💰 Auto-Recolector", UDim2.new(1, -90, 0, 24), UDim2.new(0, 14, 0, 4), 16).Font = Enum.Font.GothamBold
makeLabel(header, "Fusiona cualquier cosa en Brainrot", UDim2.new(1, -90, 0, 16), UDim2.new(0, 14, 0, 26), 11, C.Sub)
local minBtn   = makeButton(header, "–", UDim2.fromOffset(32, 32), UDim2.new(1, -78, 0.5, -16))
local closeBtn = makeButton(header, "✕", UDim2.fromOffset(32, 32), UDim2.new(1, -40, 0.5, -16), C.Red)

local body = Instance.new("Frame")
body.Size = UDim2.new(1, -16, 1, -HEADER_H - 8)
body.Position = UDim2.new(0, 8, 0, HEADER_H + 8)
body.BackgroundTransparency = 1
body.Parent = frame

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, 0, 1, 0)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 3
scroll.ScrollBarImageColor3 = C.Accent
scroll.CanvasSize = UDim2.new()
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = body
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 6)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = scroll
local pad = Instance.new("UIPadding", scroll)
pad.PaddingRight, pad.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6)

local lo = 0
local function nextOrder() lo += 1 return lo end
local function card(h)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, 0, 0, h)
    f.BackgroundColor3 = C.Card
    f.LayoutOrder = nextOrder()
    f.Parent = scroll
    corner(f, 12)
    return f
end
local function bigButton(text, color, h)
    local b = makeButton(scroll, text, UDim2.new(1, 0, 0, h or 44), nil, color)
    b.LayoutOrder = nextOrder()
    return b
end

-- Botón flotante
local floatBtn = Instance.new("TextButton")
floatBtn.Size = UDim2.fromOffset(52, 52)
floatBtn.Position = UDim2.new(1, -68, 0.6, 0)
floatBtn.BackgroundColor3 = C.Red
floatBtn.Text = "💰"
floatBtn.TextSize = 24
floatBtn.Font = Enum.Font.GothamBold
floatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
floatBtn.AutoButtonColor = false
floatBtn.ZIndex = 20
floatBtn.Parent = gui
corner(floatBtn, 26)
local st = Instance.new("UIStroke", floatBtn)
st.Color, st.Transparency, st.Thickness = Color3.fromRGB(255, 255, 255), 0.2, 2

-- ON/OFF
local mainBtn = bigButton("", C.Red, 52)
mainBtn.TextSize = 17
local function refreshMain()
    mainBtn.Text = enabled and "💰  ACTIVADO" or "💰  DESACTIVADO"
    mainBtn.BackgroundColor3 = enabled and C.Green or C.Red
    floatBtn.BackgroundColor3 = enabled and C.Green or C.Red
end
local function setEnabled(v)
    enabled = v
    refreshMain()
end
mainBtn.Activated:Connect(function() setEnabled(not enabled) end)

-- Estado
local statusCard = card(96)
local statusLabel = makeLabel(statusCard, "", UDim2.new(1, -20, 1, -12), UDim2.new(0, 10, 0, 6), 12)

-- Stepper (– valor +)
local function addStepper(text, get, set, mn, mx, step, suffix)
    local row = card(48)
    makeLabel(row, text, UDim2.new(1, -160, 1, 0), UDim2.new(0, 12, 0, 14), 13)
    local minus = makeButton(row, "–", UDim2.fromOffset(40, 36), UDim2.new(1, -152, 0.5, -18))
    local val = makeLabel(row, "", UDim2.fromOffset(56, 36), UDim2.new(1, -108, 0.5, -10), 13)
    val.TextXAlignment = Enum.TextXAlignment.Center
    val.Font = Enum.Font.GothamBold
    local plus = makeButton(row, "+", UDim2.fromOffset(40, 36), UDim2.new(1, -48, 0.5, -18))
    local function refresh() val.Text = tostring(get()) .. suffix end
    local function change(d)
        set(clamp(get() + d, mn, mx))
        refresh()
        save()
    end
    minus.Activated:Connect(function() change(-step) end)
    plus.Activated:Connect(function() change(step) end)
    refresh()
end

addStepper("Intervalo entre rondas", function() return S.Interval end, function(v) S.Interval = v end, 5, 300, 5, " s")
addStepper("Pausa entre corrales", function() return S.Delay end, function(v) S.Delay = v end, 50, 1000, 50, " ms")

-- Modo de posición
local modeBtn = bigButton("", C.Btn, 42)
modeBtn.TextSize = 12
local function refreshMode()
    modeBtn.Text = S.Mode == 1 and "Posición enviada: COLECTOR (desde lejos)" or "Posición enviada: MI PERSONAJE"
end
modeBtn.Activated:Connect(function()
    S.Mode = S.Mode == 1 and 2 or 1
    refreshMode()
    save()
end)
refreshMode()

-- Acciones manuales
local nowBtn = bigButton("▶  Recolectar ahora (1 ronda)", C.Accent, 44)
nowBtn.Activated:Connect(function()
    if busy then statusText = "Ya hay una ronda en curso." return end
    statusText = "Recolectando…"
    task.spawn(function()
        runCycle(function() return true end)
        statusText = "Ronda completada."
    end)
end)

local scanBtn = bigButton("🔎  Volver a buscar mis corrales", C.Btn, 40)
scanBtn.Activated:Connect(function()
    statusText = "Buscando corrales…"
    task.spawn(function()
        scanPens()
        statusText = "Encontré " .. #pens .. " corrales."
    end)
end)

local resetBtn = bigButton("🧹  Reiniciar contadores", C.Btn, 40)
resetBtn.Activated:Connect(function()
    stats.ok, stats.empty, stats.err, stats.rounds = 0, 0, 0, 0
    lastError = ""
end)

----------------------------------------------------------------
-- BUCLE PRINCIPAL
----------------------------------------------------------------
task.spawn(function()
    while running do
        if enabled and not busy then
            runCycle(function() return enabled end)
            -- Espera el intervalo (se corta si apagas el script)
            local waited = 0
            while running and enabled and waited < S.Interval do
                task.wait(0.25)
                waited += 0.25
            end
        else
            task.wait(0.2)
        end
    end
end)

-- Estado en pantalla
task.spawn(function()
    while running do
        task.wait(0.5)
        statusLabel.Text = string.format(
            "%s\nCorrales: %d | Rondas: %d\nCobradas: %d | Vacías: %d | Errores: %d%s",
            statusText, #pens, stats.rounds, stats.ok, stats.empty, stats.err,
            lastError ~= "" and ("\nÚltimo error: " .. lastError) or "")
    end
end)

----------------------------------------------------------------
-- VENTANA
----------------------------------------------------------------
local function layoutFrame()
    local cam = Workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(800, 600)
    local w = clamp(vp.X * 0.92, 260, 340)
    local h = clamp(vp.Y * 0.82, 260, 520)
    frame.Size = minimized and UDim2.fromOffset(w, HEADER_H) or UDim2.fromOffset(w, h)
end
do
    local cam = Workspace.CurrentCamera
    if cam then track(cam:GetPropertyChangedSignal("ViewportSize"):Connect(layoutFrame)) end
end
minBtn.Activated:Connect(function()
    minimized = not minimized
    body.Visible = not minimized
    minBtn.Text = minimized and "+" or "–"
    layoutFrame()
end)
makeDraggable(header, frame)
makeDraggable(floatBtn, floatBtn, function() setEnabled(not enabled) end)

closeBtn.Activated:Connect(function()
    running, enabled = false, false
    save()
    for _, c in ipairs(connections) do c:Disconnect() end
    gui:Destroy()
end)

----------------------------------------------------------------
-- INICIO
----------------------------------------------------------------
layoutFrame()
refreshMain()
task.spawn(function()
    scanPens()
    statusText = #pens > 0 and ("Listo. Encontré " .. #pens .. " corrales.")
        or "No encontré corrales. Pulsa «Volver a buscar»."
end)
