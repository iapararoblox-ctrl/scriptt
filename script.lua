--[[
    AUTO-CLICKER v4 para Delta (Mobile/PC)

    NOVEDADES:
    - Botón flotante ON/OFF (círculo arrastrable, visible aunque minimices)
    - Velocidad aleatoria (jitter %), mantener pulsado, temporizador, cuenta atrás
    - Varios puntos de clic (se recorren en orden) + indicadores visuales
    - Guardar ajustes y 3 perfiles (necesita writefile/readfile en tu ejecutor)
    - Pausa al escribir/abrir chat, pausa al morir (se reactiva al reaparecer)
    - Anti-AFK, autoequipar herramienta, clic solo si hay objetivo cerca
    - CPS real, tiempo activo, clics totales y promedio
    - Transparencia ajustable, minimizar (-) y cerrar (X), tecla F6 en PC

    Todos los valores iniciales están en DEFAULTS (arriba) para ajustarlos fácil.
]]

----------------------------------------------------------------
-- CONFIGURACIÓN
----------------------------------------------------------------
local HOTKEY   = Enum.KeyCode.F6        -- Tecla ON/OFF en PC
local GUI_NAME = "AutoClickerGUI"
local FILE     = "AutoClickerV4.json"   -- Archivo donde se guardan los ajustes

-- Valores iniciales (se pueden cambiar desde la interfaz)
local function newDefaults()
    return {
        CPS = 10,            -- Clics por segundo (1-100)
        Burst = 1,           -- Clics por ciclo (1-10)
        Jitter = 0,          -- Variación aleatoria del delay en % (0-50)
        Limit = 0,           -- Detenerse tras N clics (0 = infinito)
        Timer = 0,           -- Detenerse tras N segundos (0 = infinito)
        StartDelay = 0,      -- Cuenta atrás antes de empezar, en segundos
        Mode = 1,            -- 1 Auto, 2 Herramienta, 3 Pantalla, 4 Executor, 5 VirtualUser
        Hold = false,        -- Mantener pulsado en vez de clics sueltos
        TargetOnly = false,  -- Clicar solo si hay un humanoide cerca
        Radius = 30,         -- Distancia (studs) para detectar objetivo
        AutoEquip = false,   -- Equipar la primera herramienta si no hay ninguna
        PauseDead = true,    -- Pausar al morir y reanudar al reaparecer
        PauseTyping = true,  -- Pausar mientras hay una caja de texto activa (chat/menús)
        AntiAFK = true,      -- Evita la expulsión por inactividad
        ShowDots = true,     -- Mostrar los puntos de clic en pantalla
        Alpha = 0,           -- Transparencia de la ventana en % (0-80)
        Points = {},         -- Lista de puntos {X=, Y=}; vacía = centro de pantalla
    }
end

local modes = { "Auto", "Herramienta", "Pantalla", "Executor", "VirtualUser" }

----------------------------------------------------------------
-- SERVICIOS
----------------------------------------------------------------
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local VirtualUser      = game:GetService("VirtualUser")
local CoreGui          = game:GetService("CoreGui")
local GuiService       = game:GetService("GuiService")
local Workspace        = game:GetService("Workspace")
local HttpService      = game:GetService("HttpService")

local player = Players.LocalPlayer
local VIM
pcall(function() VIM = game:GetService("VirtualInputManager") end)

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
local old = guiParent:FindFirstChild(GUI_NAME)
if old then old:Destroy() end

----------------------------------------------------------------
-- ESTADO
----------------------------------------------------------------
local S = newDefaults()
local Profiles = {}
local profileIndex = 1

local enabled, starting, running = false, false, true
local minimized, settingPoint = false, false
local clickCount, activeTime, realCPS = 0, 0, 0
local runStart, pointIndex = 0, 0
local clicking, status = false, "Inactivo"
local resumeAfterRespawn = false
local holding, holdMethod, holdPoint = false, nil, nil
local connections = {}
local refreshers = {}

local function track(c) table.insert(connections, c) return c end
local function clamp(n, lo, hi) return math.max(lo, math.min(hi, n)) end

----------------------------------------------------------------
-- GUARDAR / CARGAR
----------------------------------------------------------------
local function copySettings(t)
    local c = {}
    for k, v in pairs(t) do
        if k == "Points" then
            c.Points = {}
            for _, p in ipairs(v) do table.insert(c.Points, { X = p.X, Y = p.Y }) end
        else
            c[k] = v
        end
    end
    return c
end

local function applySettings(t)
    local d = newDefaults()
    for k, dv in pairs(d) do
        if k == "Points" then
            S.Points = {}
            if type(t.Points) == "table" then
                for _, p in ipairs(t.Points) do
                    if type(p.X) == "number" and type(p.Y) == "number" then
                        table.insert(S.Points, { X = p.X, Y = p.Y })
                    end
                end
            end
        elseif type(t[k]) == type(dv) then
            S[k] = t[k]
        else
            S[k] = dv
        end
    end
    S.Mode = clamp(math.floor(S.Mode), 1, #modes)
end

local function writeAll()
    pcall(function()
        writefile(FILE, HttpService:JSONEncode({ Current = copySettings(S), Profiles = Profiles }))
    end)
end

local function loadAll()
    local ok, data = pcall(function()
        if isfile and isfile(FILE) then
            return HttpService:JSONDecode(readfile(FILE))
        end
    end)
    if ok and type(data) == "table" then
        if type(data.Profiles) == "table" then Profiles = data.Profiles end
        if type(data.Current) == "table" then applySettings(data.Current) end
    end
end

loadAll()

----------------------------------------------------------------
-- HELPERS DE INTERFAZ
----------------------------------------------------------------
local function corner(obj, r)
    Instance.new("UICorner", obj).CornerRadius = UDim.new(0, r or 6)
end

local function makeButton(parent, text, size, pos, color)
    local b = Instance.new("TextButton")
    b.Size = size
    b.Position = pos or UDim2.new()
    b.BackgroundColor3 = color or Color3.fromRGB(60, 60, 70)
    b.Text = text
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.Parent = parent
    corner(b)
    return b
end

local function makeLabel(parent, text, size, pos)
    local l = Instance.new("TextLabel")
    l.Size = size
    l.Position = pos or UDim2.new()
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = Color3.fromRGB(200, 200, 200)
    l.Font = Enum.Font.Gotham
    l.TextSize = 13
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = parent
    return l
end

local function makeBox(parent, size, pos)
    local t = Instance.new("TextBox")
    t.Size = size
    t.Position = pos
    t.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    t.Text = ""
    t.TextColor3 = Color3.fromRGB(255, 255, 255)
    t.Font = Enum.Font.Gotham
    t.TextSize = 13
    t.ClearTextOnFocus = false
    t.Parent = parent
    corner(t)
    return t
end

-- Arrastrar: handle = zona que se toca, target = lo que se mueve, onTap = acción si fue un toque corto
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

----------------------------------------------------------------
-- INTERFAZ PRINCIPAL
----------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true -- así las coordenadas coinciden con la pantalla real
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = guiParent

local EXPANDED_SIZE  = UDim2.new(0, 240, 0, 330)
local MINIMIZED_SIZE = UDim2.new(0, 240, 0, 30)

local frame = Instance.new("Frame")
frame.Size = EXPANDED_SIZE
frame.Position = UDim2.new(0, 10, 0, 40)
frame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
frame.BorderSizePixel = 0
frame.ClipsDescendants = true
frame.Parent = gui
corner(frame, 10)

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 30)
header.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
header.BorderSizePixel = 0
header.Active = true
header.Parent = frame

makeLabel(header, "Auto-Clicker v4", UDim2.new(1, -70, 1, 0), UDim2.new(0, 10, 0, 0)).Font = Enum.Font.GothamBold
local minBtn   = makeButton(header, "-", UDim2.new(0, 24, 0, 22), UDim2.new(1, -56, 0, 4))
local closeBtn = makeButton(header, "X", UDim2.new(0, 24, 0, 22), UDim2.new(1, -28, 0, 4), Color3.fromRGB(170, 55, 55))

local body = Instance.new("Frame")
body.Size = UDim2.new(1, -16, 1, -38)
body.Position = UDim2.new(0, 8, 0, 34)
body.BackgroundTransparency = 1
body.Parent = frame

local toggleBtn = makeButton(body, "OFF", UDim2.new(1, 0, 0, 34), UDim2.new(), Color3.fromRGB(190, 60, 60))
toggleBtn.TextSize = 16

local statsLabel = makeLabel(body, "", UDim2.new(1, 0, 0, 32), UDim2.new(0, 0, 0, 37))
statsLabel.TextSize = 11
statsLabel.TextWrapped = true
statsLabel.TextYAlignment = Enum.TextYAlignment.Top

-- Lista con scroll para todas las opciones
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, 0, 1, -72)
scroll.Position = UDim2.new(0, 0, 0, 72)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.CanvasSize = UDim2.new()
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = body

local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 4)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = scroll

local order = 0
local function nextOrder() order += 1 return order end

local function addSection(text)
    local l = makeLabel(scroll, "— " .. text .. " —", UDim2.new(1, -8, 0, 18), UDim2.new())
    l.Font = Enum.Font.GothamBold
    l.TextSize = 11
    l.TextColor3 = Color3.fromRGB(130, 150, 200)
    l.LayoutOrder = nextOrder()
end

local function addRow()
    local r = Instance.new("Frame")
    r.Size = UDim2.new(1, -8, 0, 28)
    r.BackgroundTransparency = 1
    r.LayoutOrder = nextOrder()
    r.Parent = scroll
    return r
end

local function addButton(text, color)
    local b = makeButton(scroll, text, UDim2.new(1, -8, 0, 28), UDim2.new(), color)
    b.LayoutOrder = nextOrder()
    return b
end

----------------------------------------------------------------
-- BOTÓN FLOTANTE
----------------------------------------------------------------
local floatBtn = Instance.new("TextButton")
floatBtn.Size = UDim2.fromOffset(46, 46)
floatBtn.Position = UDim2.new(1, -62, 0.45, 0)
floatBtn.BackgroundColor3 = Color3.fromRGB(190, 60, 60)
floatBtn.Text = "OFF"
floatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
floatBtn.Font = Enum.Font.GothamBold
floatBtn.TextSize = 13
floatBtn.AutoButtonColor = false
floatBtn.ZIndex = 20
floatBtn.Parent = gui
corner(floatBtn, 23)
local stroke = Instance.new("UIStroke", floatBtn)
stroke.Color = Color3.fromRGB(255, 255, 255)
stroke.Thickness = 2

----------------------------------------------------------------
-- APARIENCIA (transparencia / minimizar)
----------------------------------------------------------------
local function applyLook()
    local a = S.Alpha / 100
    if minimized then a = math.min(0.85, a + 0.3) end
    frame.BackgroundTransparency = a
    header.BackgroundTransparency = a
end

local function refreshToggle()
    local txt = enabled and "ON" or "OFF"
    local col = enabled and Color3.fromRGB(60, 170, 90) or Color3.fromRGB(190, 60, 60)
    if starting then col = Color3.fromRGB(200, 150, 40) end
    if not starting then toggleBtn.Text = txt; floatBtn.Text = txt end
    toggleBtn.BackgroundColor3 = col
    floatBtn.BackgroundColor3 = col
end

-- Puntos visibles en pantalla
local function refreshDots()
    for _, c in ipairs(gui:GetChildren()) do
        if c.Name == "Dot" then c:Destroy() end
    end
    if not S.ShowDots then return end
    for i, p in ipairs(S.Points) do
        local d = Instance.new("TextLabel")
        d.Name = "Dot"
        d.AnchorPoint = Vector2.new(0.5, 0.5)
        d.Size = UDim2.fromOffset(20, 20)
        d.Position = UDim2.fromOffset(p.X, p.Y)
        d.BackgroundColor3 = Color3.fromRGB(255, 70, 70)
        d.BackgroundTransparency = 0.3
        d.Text = tostring(i)
        d.TextColor3 = Color3.fromRGB(255, 255, 255)
        d.Font = Enum.Font.GothamBold
        d.TextSize = 11
        d.ZIndex = 10
        d.Parent = gui
        corner(d, 10)
    end
end

local function refreshAll()
    for _, f in ipairs(refreshers) do f() end
    refreshDots()
    applyLook()
    refreshToggle()
end

----------------------------------------------------------------
-- CONTROLES (generados con helpers)
----------------------------------------------------------------
-- Fila con - / caja / +  (clave de S, mínimo, máximo, salto)
local function addStepper(text, key, mn, mx, step, after)
    local row = addRow()
    makeLabel(row, text, UDim2.new(1, -110, 1, 0))
    local minus = makeButton(row, "-", UDim2.new(0, 26, 0, 26), UDim2.new(1, -106, 0, 1))
    local box   = makeBox(row, UDim2.new(0, 46, 0, 26), UDim2.new(1, -76, 0, 1))
    local plus  = makeButton(row, "+", UDim2.new(0, 26, 0, 26), UDim2.new(1, -26, 0, 1))
    local function set(n)
        S[key] = clamp(math.floor(n + 0.5), mn, mx)
        box.Text = tostring(S[key])
        if after then after() end
    end
    minus.Activated:Connect(function() set(S[key] - step) end)
    plus.Activated:Connect(function() set(S[key] + step) end)
    box.FocusLost:Connect(function() set(tonumber(box.Text) or S[key]) end)
    table.insert(refreshers, function() box.Text = tostring(S[key]) end)
end

-- Botón SÍ/NO
local function addToggle(text, key, after)
    local b = addButton("")
    local function r()
        b.Text = text .. ": " .. (S[key] and "SÍ" or "NO")
        b.BackgroundColor3 = S[key] and Color3.fromRGB(50, 120, 80) or Color3.fromRGB(60, 60, 70)
    end
    b.Activated:Connect(function()
        S[key] = not S[key]
        r()
        if after then after() end
    end)
    table.insert(refreshers, r)
end

----------------------------------------------------------------
-- ARMADO DE LA LISTA DE OPCIONES
----------------------------------------------------------------
addSection("VELOCIDAD")
addStepper("Clics/seg:",   "CPS",    1, 100, 1)
addStepper("Clics/ciclo:", "Burst",  1, 10,  1)
addStepper("Aleatorio %:", "Jitter", 0, 50,  5)
addStepper("Límite clics:", "Limit", 0, 100000, 10)

addSection("TIEMPO")
addStepper("Temporizador s:", "Timer",      0, 3600, 5)
addStepper("Cuenta atrás s:", "StartDelay", 0, 10,   1)

addSection("CLIC")
local modeBtn = addButton("", Color3.fromRGB(50, 80, 140))
modeBtn.Activated:Connect(function()
    S.Mode = S.Mode % #modes + 1
    modeBtn.Text = "Modo: " .. modes[S.Mode]
end)
table.insert(refreshers, function() modeBtn.Text = "Modo: " .. modes[S.Mode] end)

addToggle("Mantener pulsado", "Hold")

local addPointBtn = addButton("", Color3.fromRGB(110, 80, 150))
addPointBtn.Activated:Connect(function()
    settingPoint = true
    addPointBtn.Text = "Toca la pantalla..."
end)
table.insert(refreshers, function()
    addPointBtn.Text = "+ Agregar punto (" .. #S.Points .. ")"
end)

local clearPointsBtn = addButton("Borrar puntos (clic al centro)", Color3.fromRGB(110, 60, 80))
clearPointsBtn.Activated:Connect(function()
    S.Points = {}
    pointIndex = 0
    refreshAll()
end)

addSection("AUTOMÁTICO")
addToggle("Autoequipar herramienta", "AutoEquip")
addToggle("Solo si hay objetivo", "TargetOnly")
addStepper("Distancia objetivo:", "Radius", 5, 200, 5)
addToggle("Pausar al morir", "PauseDead")
addToggle("Pausar al escribir", "PauseTyping")
addToggle("Anti-AFK", "AntiAFK")

addSection("PANTALLA")
addToggle("Mostrar puntos", "ShowDots", refreshDots)
addStepper("Transparencia %:", "Alpha", 0, 80, 10, applyLook)

local resetCountBtn = addButton("Reiniciar estadísticas", Color3.fromRGB(40, 40, 48))
resetCountBtn.Activated:Connect(function()
    clickCount, activeTime = 0, 0
end)

addSection("PERFILES")
local profRow = addRow()
local profBtn = makeButton(profRow, "Perfil 1", UDim2.new(0.34, -2, 1, 0), UDim2.new(0, 0, 0, 0), Color3.fromRGB(50, 80, 140))
local saveBtn = makeButton(profRow, "Guardar", UDim2.new(0.33, -2, 1, 0), UDim2.new(0.34, 0, 0, 0), Color3.fromRGB(50, 120, 80))
local loadBtn = makeButton(profRow, "Cargar",  UDim2.new(0.33, -2, 1, 0), UDim2.new(0.67, 0, 0, 0), Color3.fromRGB(140, 110, 40))

profBtn.Activated:Connect(function()
    profileIndex = profileIndex % 3 + 1
    profBtn.Text = "Perfil " .. profileIndex
end)
saveBtn.Activated:Connect(function()
    Profiles[profileIndex] = copySettings(S)
    writeAll()
    saveBtn.Text = "¡Listo!"
    task.delay(1, function() if saveBtn.Parent then saveBtn.Text = "Guardar" end end)
end)
loadBtn.Activated:Connect(function()
    if Profiles[profileIndex] then
        applySettings(Profiles[profileIndex])
        refreshAll()
        loadBtn.Text = "¡Listo!"
    else
        loadBtn.Text = "Vacío"
    end
    task.delay(1, function() if loadBtn.Parent then loadBtn.Text = "Cargar" end end)
end)

local defaultsBtn = addButton("Restaurar valores", Color3.fromRGB(110, 60, 60))
defaultsBtn.Activated:Connect(function()
    applySettings(newDefaults())
    pointIndex = 0
    refreshAll()
end)

----------------------------------------------------------------
-- ACTIVAR / DESACTIVAR (con cuenta atrás opcional)
----------------------------------------------------------------
local function activate()
    starting = false
    enabled = true
    runStart = os.clock()
    refreshToggle()
end

local function setEnabled(v)
    if not running then return end
    if v then
        if enabled or starting then return end
        if S.StartDelay > 0 then
            starting = true
            refreshToggle()
            task.spawn(function()
                for i = S.StartDelay, 1, -1 do
                    if not starting or not running then return end
                    toggleBtn.Text = "Inicia en " .. i
                    floatBtn.Text = tostring(i)
                    task.wait(1)
                end
                if starting and running then activate() end
            end)
        else
            activate()
        end
    else
        starting = false
        enabled = false
        refreshToggle()
    end
end

local function toggleFromUser()
    setEnabled(not (enabled or starting))
end

toggleBtn.Activated:Connect(toggleFromUser)
makeDraggable(floatBtn, floatBtn, toggleFromUser) -- toque corto = ON/OFF, arrastrar = mover
makeDraggable(header, frame)

minBtn.Activated:Connect(function()
    minimized = not minimized
    body.Visible = not minimized
    frame.Size = minimized and MINIMIZED_SIZE or EXPANDED_SIZE
    minBtn.Text = minimized and "+" or "-"
    applyLook()
end)

----------------------------------------------------------------
-- ENTRADAS: fijar puntos + tecla rápida
----------------------------------------------------------------
track(UserInputService.InputBegan:Connect(function(input, processed)
    if settingPoint and not processed
        and (input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch) then
        local inset = GuiService:GetGuiInset()
        table.insert(S.Points, { X = input.Position.X + inset.X, Y = input.Position.Y + inset.Y })
        settingPoint = false
        refreshAll()
        return
    end
    if not processed and input.KeyCode == HOTKEY then
        toggleFromUser()
    end
end))

----------------------------------------------------------------
-- MÉTODOS DE CLIC
----------------------------------------------------------------
local function getPoint(advance)
    local pts = S.Points
    if #pts == 0 then
        return Workspace.CurrentCamera.ViewportSize / 2
    end
    if advance then pointIndex = pointIndex % #pts + 1 end
    local p = pts[pointIndex] or pts[1]
    return Vector2.new(p.X, p.Y)
end

local function clickTool()
    local char = player.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    if tool then tool:Activate() return true end
    return false
end

local function clickScreen(p)
    if not VIM then return false end
    VIM:SendMouseButtonEvent(p.X, p.Y, 0, true, game, 0)
    VIM:SendMouseButtonEvent(p.X, p.Y, 0, false, game, 0)
    return true
end

local function clickExecutor()
    if mouse1click then mouse1click() return true end
    return false
end

local function clickVirtualUser(p)
    local cf = Workspace.CurrentCamera.CFrame
    VirtualUser:CaptureController()
    VirtualUser:Button1Down(p, cf)
    VirtualUser:Button1Up(p, cf)
    return true
end

local function doClick()
    local mode = modes[S.Mode]
    local p = getPoint(true)
    if mode == "Herramienta" then
        clickTool()
    elseif mode == "Pantalla" then
        clickScreen(p)
    elseif mode == "Executor" then
        clickExecutor()
    elseif mode == "VirtualUser" then
        clickVirtualUser(p)
    else -- Auto: herramienta + clic de pantalla, con respaldos
        clickTool()
        if not clickScreen(p) then
            if not clickExecutor() then clickVirtualUser(p) end
        end
    end
end

-- Mantener pulsado
local function holdable()
    local mode = modes[S.Mode]
    if mode == "Auto" or mode == "Pantalla" then return VIM ~= nil end
    if mode == "Executor" then return mouse1press ~= nil end
    return false
end

local function holdAction()
    if not holding then
        holdPoint = getPoint(false)
        if VIM and modes[S.Mode] ~= "Executor" then
            VIM:SendMouseButtonEvent(holdPoint.X, holdPoint.Y, 0, true, game, 0)
            holdMethod = "vim"
        else
            mouse1press()
            holdMethod = "exec"
        end
        holding = true
        clickCount += 1
    end
    if modes[S.Mode] == "Auto" then clickTool() end
end

local function holdStop()
    if not holding then return end
    holding = false
    if holdMethod == "vim" and VIM then
        VIM:SendMouseButtonEvent(holdPoint.X, holdPoint.Y, 0, false, game, 0)
    elseif holdMethod == "exec" and mouse1release then
        mouse1release()
    end
end

----------------------------------------------------------------
-- AUTOMATIZACIONES
----------------------------------------------------------------
-- Autoequipar herramienta
local function autoEquip()
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum or char:FindFirstChildOfClass("Tool") then return end
    local tool = player.Backpack:FindFirstChildOfClass("Tool")
    if tool then hum:EquipTool(tool) end
end

-- Detectar humanoide cercano (se revisa como máximo cada 0.2 s para no dar lag)
local lastCheck, lastResult = 0, false
local function hasTarget()
    if os.clock() - lastCheck < 0.2 then return lastResult end
    lastCheck, lastResult = os.clock(), false
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { char }
        params.MaxParts = 100
        for _, part in ipairs(Workspace:GetPartBoundsInRadius(hrp.Position, S.Radius, params)) do
            local model = part:FindFirstAncestorOfClass("Model")
            local hum = model and model:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                lastResult = true
                break
            end
        end
    end
    return lastResult
end

-- Pausa al morir y reanuda al reaparecer
local function hookCharacter(char)
    local hum = char:WaitForChild("Humanoid", 10)
    if hum then
        hum.Died:Connect(function()
            if S.PauseDead and (enabled or starting) then
                resumeAfterRespawn = true
                setEnabled(false)
            end
        end)
    end
end

track(player.CharacterAdded:Connect(function(char)
    task.spawn(hookCharacter, char)
    if resumeAfterRespawn then
        resumeAfterRespawn = false
        task.wait(1.5)
        setEnabled(true)
    end
end))
if player.Character then task.spawn(hookCharacter, player.Character) end

-- Anti-AFK
track(player.Idled:Connect(function()
    if S.AntiAFK then
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end
end))

----------------------------------------------------------------
-- CERRAR
----------------------------------------------------------------
closeBtn.Activated:Connect(function()
    running = false
    enabled, starting = false, false
    writeAll() -- guarda los ajustes actuales para la próxima vez
    pcall(holdStop)
    for _, c in ipairs(connections) do c:Disconnect() end
    gui:Destroy()
end)

----------------------------------------------------------------
-- BUCLE PRINCIPAL (un solo hilo)
----------------------------------------------------------------
task.spawn(function()
    while running do
        if enabled then
            if S.Timer > 0 and os.clock() - runStart >= S.Timer then
                setEnabled(false) -- temporizador cumplido
            else
                local reason
                if S.PauseTyping and UserInputService:GetFocusedTextBox() then
                    reason = "Pausado (escribiendo)"
                elseif S.TargetOnly and not hasTarget() then
                    reason = "Esperando objetivo"
                end

                if reason then
                    status, clicking = reason, false
                    pcall(holdStop)
                    task.wait(0.1)
                else
                    status, clicking = "Activo", true
                    if S.AutoEquip then pcall(autoEquip) end

                    if S.Hold and holdable() then
                        pcall(holdAction)
                        task.wait(0.1)
                    else
                        pcall(holdStop)
                        for _ = 1, S.Burst do
                            pcall(doClick)
                            clickCount += 1
                            if S.Limit > 0 and clickCount >= S.Limit then
                                setEnabled(false)
                                break
                            end
                        end
                        -- Delay base con variación aleatoria opcional
                        local delay = 1 / S.CPS
                        if S.Jitter > 0 then
                            delay = delay * (1 + (math.random() * 2 - 1) * S.Jitter / 100)
                        end
                        task.wait(math.max(delay, 0.005))
                    end
                end
            end
        else
            status = starting and "Cuenta atrás" or "Inactivo"
            clicking = false
            pcall(holdStop)
            task.wait(0.1)
        end
    end
    pcall(holdStop)
end)

----------------------------------------------------------------
-- ESTADÍSTICAS (se actualizan cada 0.5 s)
----------------------------------------------------------------
task.spawn(function()
    local lastCount, lastT = clickCount, os.clock()
    while running do
        task.wait(0.5)
        local now = os.clock()
        local dt = now - lastT
        lastT = now
        realCPS = math.max(0, (clickCount - lastCount) / dt)
        lastCount = clickCount
        if clicking then activeTime += dt end

        if not minimized then
            local avg = activeTime > 0 and clickCount / activeTime or 0
            statsLabel.Text = string.format(
                "CPS real: %.1f | Clics: %d\nTiempo: %02d:%02d | Prom: %.1f/s\n%s",
                realCPS, clickCount,
                math.floor(activeTime / 60), math.floor(activeTime % 60),
                avg, status
            )
        end
    end
end)

----------------------------------------------------------------
-- INICIO
----------------------------------------------------------------
refreshAll()
