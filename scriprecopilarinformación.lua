--[[
    REMOTE CAPTURE (ligero) para Delta (Mobile/PC)

    Solo captura los RemoteEvent / RemoteFunction que el juego envía al servidor
    cuando TÚ haces una acción. No dispara nada ni modifica el juego.

    - Guarda argumentos y la respuesta del servidor (en los RemoteFunction)
    - Botón "Marcar acción": escribe el nombre de lo que vas a hacer y pulsa Marcar
      antes de hacerlo; el informe queda ordenado por acciones
    - Oculta remotes ruidosos (Get*, Report*, Record*, Note*, Hover)
    - Informe corto de una sola parte: Copiar o Guardar en archivo
    - Oculta los nombres de usuario del informe (el tuyo y los de otros jugadores)
]]

----------------------------------------------------------------
-- CONFIGURACIÓN
----------------------------------------------------------------
local GUI_NAME   = "RemoteCaptureGUI"
local MAX_CALLS  = 150    -- Máximo de llamadas distintas guardadas
local MAX_REPORT = 30000  -- Tamaño máximo del informe (caracteres)
-- Remotes que se ocultan si "Ocultar ruido" está activo (patrones sobre el nombre del remote)
local NOISE = { "^Get", "^Report", "^Record", "^Note", "Hover", "^IsWild" }

local C = {
    Bg = Color3.fromRGB(16, 18, 26), Card = Color3.fromRGB(28, 31, 43), Btn = Color3.fromRGB(44, 48, 64),
    Accent = Color3.fromRGB(90, 130, 255), Green = Color3.fromRGB(46, 160, 105),
    Red = Color3.fromRGB(200, 70, 80), Text = Color3.fromRGB(235, 238, 245), Sub = Color3.fromRGB(150, 158, 178),
}

----------------------------------------------------------------
-- SERVICIOS
----------------------------------------------------------------
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local CoreGui          = game:GetService("CoreGui")
local Workspace        = game:GetService("Workspace")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local env    = (getgenv and getgenv()) or _G

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
-- UTILIDADES
----------------------------------------------------------------
local function clamp(n, lo, hi) return math.max(lo, math.min(hi, n)) end

local function path(inst)
    local ok, p = pcall(function() return inst:GetFullName() end)
    return ok and p or tostring(inst)
end

-- Convierte cualquier valor en texto corto
local function ser(v, depth)
    depth = depth or 0
    local t = typeof(v)
    if t == "string" then
        return '"' .. (#v > 60 and (v:sub(1, 60) .. "…") or v) .. '"'
    elseif t == "number" or t == "boolean" or t == "nil" then
        return tostring(v)
    elseif t == "Instance" then
        return "<" .. v.ClassName .. ":" .. path(v) .. ">"
    elseif t == "buffer" then
        local ok, n = pcall(function() return buffer.len(v) end)
        return "buffer[" .. (ok and n or "?") .. "]"
    elseif t == "table" then
        if depth >= 3 then return "{…}" end
        local parts, n = {}, 0
        for k, val in pairs(v) do
            n += 1
            if n > 20 then parts[#parts + 1] = "…" break end
            parts[#parts + 1] = "[" .. ser(k, depth + 1) .. "]=" .. ser(val, depth + 1)
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    elseif t == "function" then
        return "fn"
    else
        return t .. ":" .. tostring(v)
    end
end

-- Oculta nombres de usuario y IDs de todos los jugadores del servidor
local function scrub(s)
    for i, pl in ipairs(Players:GetPlayers()) do
        local alias = (pl == player) and "LocalPlayer" or ("Jugador" .. i)
        for _, n in ipairs({ pl.Name, pl.DisplayName }) do
            if n and #n > 1 then s = s:gsub(n:gsub("%p", "%%%0"), alias) end
        end
        s = s:gsub(tostring(pl.UserId), "UID")
    end
    return s
end

----------------------------------------------------------------
-- ESTADO + CAPTURA
----------------------------------------------------------------
local running = true
local connections = {}
local function track(c) table.insert(connections, c) return c end

-- seq = lista cronológica de marcadores y llamadas; map = para agrupar repetidas
local state = { capturing = false, hide = true, seq = {}, map = {}, total = 0, calls = 0, marker = 0, dirty = true }
env.__RemoteCapture = state

local hookOK = false
if hookmetamethod and getnamecallmethod then
    pcall(function()
        if env.__RemoteCaptureHooked then hookOK = true return end
        local oldNamecall
        local function handler(self, ...)
            local st = env.__RemoteCapture
            if st and st.capturing then
                local method = getnamecallmethod()
                if (method == "FireServer" or method == "InvokeServer") and typeof(self) == "Instance" then
                    local cls = self.ClassName
                    if cls == "RemoteEvent" or cls == "RemoteFunction" or cls == "UnreliableRemoteEvent" then
                        local args = table.pack(...)
                        if method == "InvokeServer" then
                            -- Se guarda también lo que responde el servidor
                            local res = table.pack(oldNamecall(self, ...))
                            task.defer(st.record, self, method, args, res)
                            return table.unpack(res, 1, res.n)
                        end
                        task.defer(st.record, self, method, args, nil)
                    end
                end
            end
            return oldNamecall(self, ...)
        end
        oldNamecall = hookmetamethod(game, "__namecall", newcclosure and newcclosure(handler) or handler)
        env.__RemoteCaptureHooked = true
        hookOK = true
    end)
end

local function joinValues(t)
    local list = {}
    for i = 1, t.n do list[i] = ser(t[i], 0) end
    return table.concat(list, ", ")
end

state.record = function(remote, method, args, res)
    if not running then return end
    local full = path(remote)
    local short = full:match("Services%.(.+)$") or full
    if state.hide then
        for _, pat in ipairs(NOISE) do
            if remote.Name:find(pat) then return end
        end
    end
    local argStr = joinValues(args)
    if #argStr > 400 then argStr = argStr:sub(1, 400) .. "…" end
    local resStr = res and joinValues(res) or nil
    if resStr and #resStr > 300 then resStr = resStr:sub(1, 300) .. "…" end

    state.total += 1
    state.dirty = true
    local key = state.marker .. "|" .. short .. "|" .. method .. "|" .. argStr
    local e = state.map[key]
    if e then
        e.count += 1
        if resStr and not e.res then e.res = resStr end
    elseif state.calls < MAX_CALLS then
        state.calls += 1
        e = { kind = "call", path = short, method = method, args = argStr, res = resStr, count = 1 }
        state.map[key] = e
        table.insert(state.seq, e)
    end
end

local function addMarker(label)
    state.marker += 1
    table.insert(state.seq, { kind = "mark", label = label })
    state.dirty = true
end

local function buildReport()
    local name = "?"
    pcall(function() name = MarketplaceService:GetProductInfo(game.PlaceId).Name end)
    local out = {
        "=== REMOTES CAPTURADOS ===",
        "Juego: " .. name .. " | PlaceId: " .. game.PlaceId,
        "Llamadas totales: " .. state.total .. " | Distintas: " .. state.calls,
        "",
    }
    for _, e in ipairs(state.seq) do
        if e.kind == "mark" then
            out[#out + 1] = ""
            out[#out + 1] = "### ACCIÓN: " .. e.label
        else
            local line = string.format("[x%d] %s  %s  args:(%s)", e.count, e.method, e.path, e.args)
            if e.res then line = line .. "  =>  (" .. e.res .. ")" end
            out[#out + 1] = line
        end
    end
    local text = scrub(table.concat(out, "\n"))
    if #text > MAX_REPORT then text = text:sub(1, MAX_REPORT) .. "\n… (recortado)" end
    return text
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

local function makeDraggable(handle, target)
    local dragging, dragStart, startPos = false, nil, nil
    track(handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPos = true, input.Position, target.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end))
    track(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                        startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
end

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = guiParent

local HEADER_H = 46
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

makeLabel(header, "📡 Remote Capture", UDim2.new(1, -90, 0, 24), UDim2.new(0, 14, 0, 4), 16).Font = Enum.Font.GothamBold
makeLabel(header, "Solo captura, no modifica nada", UDim2.new(1, -90, 0, 16), UDim2.new(0, 14, 0, 26), 11, C.Sub)
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
local function bigButton(text, color, h)
    local b = makeButton(scroll, text, UDim2.new(1, 0, 0, h or 44), nil, color)
    b.LayoutOrder = nextOrder()
    return b
end
local function card(h)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, 0, 0, h)
    f.BackgroundColor3 = C.Card
    f.LayoutOrder = nextOrder()
    f.Parent = scroll
    corner(f, 12)
    return f
end

-- Estado
local statusCard = card(54)
local statusLabel = makeLabel(statusCard, "", UDim2.new(1, -20, 1, -12), UDim2.new(0, 10, 0, 6), 13)

-- Captura ON/OFF
local logBtn = bigButton("", C.Btn, 50)
local function refreshLog()
    logBtn.Text = "📡 Captura: " .. (state.capturing and "ON" or "OFF")
    logBtn.BackgroundColor3 = state.capturing and C.Red or C.Btn
end
logBtn.Activated:Connect(function()
    if not hookOK then
        statusLabel.Text = "⚠ Tu ejecutor no soporta hookmetamethod: no se puede capturar."
        return
    end
    state.capturing = not state.capturing
    refreshLog()
end)
refreshLog()

-- Ocultar ruido
local hideBtn = bigButton("", C.Btn, 38)
local function refreshHide()
    hideBtn.Text = "Ocultar ruido (Get/Report/Record): " .. (state.hide and "SÍ" or "NO")
    hideBtn.BackgroundColor3 = state.hide and C.Green or C.Btn
    hideBtn.TextSize = 12
end
hideBtn.Activated:Connect(function() state.hide = not state.hide refreshHide() end)
refreshHide()

-- Marcar acción
local markCard = card(48)
local markBox = Instance.new("TextBox")
markBox.Size = UDim2.new(1, -110, 0, 34)
markBox.Position = UDim2.new(0, 8, 0, 7)
markBox.BackgroundColor3 = C.Btn
markBox.PlaceholderText = "Ej: fusionar"
markBox.PlaceholderColor3 = C.Sub
markBox.Text = ""
markBox.TextColor3 = C.Text
markBox.Font = Enum.Font.Gotham
markBox.TextSize = 14
markBox.ClearTextOnFocus = false
markBox.Parent = markCard
corner(markBox, 8)
local markBtn = makeButton(markCard, "Marcar", UDim2.fromOffset(88, 34), UDim2.new(1, -96, 0, 7), C.Accent)
markBtn.Activated:Connect(function()
    local label = markBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
    if label == "" then label = "acción " .. (state.marker + 1) end
    addMarker(label)
    markBox.Text = ""
    statusLabel.Text = "Marcado: " .. label .. ". Ahora haz la acción en el juego."
end)

-- Vista en vivo
local liveTag = makeLabel(scroll, "ÚLTIMAS LLAMADAS", UDim2.new(1, 0, 0, 16), nil, 11, C.Sub)
liveTag.Font = Enum.Font.GothamBold
liveTag.LayoutOrder = nextOrder()
local liveCard = card(150)
local liveLabel = makeLabel(liveCard, "", UDim2.new(1, -16, 1, -12), UDim2.new(0, 8, 0, 6), 11, C.Sub)
liveLabel.Font = Enum.Font.Code

-- Copiar / guardar / limpiar
local copyBtn  = bigButton("📋  Copiar informe", C.Green, 50)
local saveBtn  = bigButton("💾  Guardar en archivo", C.Btn, 40)
local clearBtn = bigButton("🧹  Limpiar", C.Btn, 40)

copyBtn.Activated:Connect(function()
    local text = buildReport()
    local copier = setclipboard or toclipboard
    if state.total == 0 then statusLabel.Text = "Aún no hay nada capturado." return end
    if copier and pcall(copier, text) then
        statusLabel.Text = "📋 Copiado (" .. #text .. " caracteres). Pégalo en el chat."
    else
        statusLabel.Text = "⚠ No se pudo copiar. Usa «Guardar en archivo»."
    end
end)

saveBtn.Activated:Connect(function()
    if not writefile then statusLabel.Text = "⚠ Tu ejecutor no soporta writefile." return end
    local name = "RemoteCapture_" .. game.PlaceId .. ".txt"
    local ok = pcall(writefile, name, buildReport())
    statusLabel.Text = ok and ("💾 Guardado como " .. name .. " (carpeta workspace).") or "⚠ No se pudo guardar."
end)

clearBtn.Activated:Connect(function()
    state.seq, state.map, state.total, state.calls, state.marker = {}, {}, 0, 0, 0
    state.dirty = true
    statusLabel.Text = "Limpio."
end)

-- Actualización de la vista (cada 0.5 s, sin gastar rendimiento)
task.spawn(function()
    while running do
        task.wait(0.5)
        if state.dirty then
            state.dirty = false
            statusLabel.Text = statusLabel.Text ~= "" and statusLabel.Text or ""
            local lines = {}
            local from = math.max(1, #state.seq - 7)
            for i = from, #state.seq do
                local e = state.seq[i]
                if e.kind == "mark" then
                    lines[#lines + 1] = "## " .. e.label
                else
                    local s = string.format("x%d %s (%s)", e.count, e.path, e.args)
                    lines[#lines + 1] = #s > 95 and (s:sub(1, 95) .. "…") or s
                end
            end
            liveLabel.Text = #lines > 0 and table.concat(lines, "\n") or "(nada todavía)"
            if state.capturing then
                statusLabel.Text = string.format("Capturando… %d llamadas (%d distintas).", state.total, state.calls)
            end
        end
    end
end)

-- Ventana
local minimized = false
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

closeBtn.Activated:Connect(function()
    running = false
    state.capturing = false -- el hook queda inactivo y deja pasar todo sin registrar
    for _, c in ipairs(connections) do c:Disconnect() end
    gui:Destroy()
end)

layoutFrame()
statusLabel.Text = hookOK and "Listo. Activa la captura y marca cada acción." or "⚠ Tu ejecutor no soporta hookmetamethod."
