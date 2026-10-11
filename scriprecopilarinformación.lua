--[[
    INFO COLLECTOR para Delta (Mobile/PC)
    Recopila la información de un juego para poder armar un script a medida.

    QUÉ RECOPILA
    - Datos generales del juego y del ejecutor
    - Tus valores (leaderstats, dinero, atributos) y herramientas
    - Remotes (RemoteEvent / RemoteFunction) y módulos de datos
    - Objetos con nombres clave (brainrot, fuse, merge, slot, shop, etc.)
    - ProximityPrompts y ClickDetectors
    - Botones y textos de la interfaz
    - Objetos cercanos a tu personaje
    - CAPTURA DE REMOTES: registra qué remotes dispara el juego cuando TÚ haces una
      acción (fusionar, comprar, vender...), con sus argumentos. Es lo más valioso.

    Solo LEE información. No dispara remotes ni modifica nada del juego.
    El informe sale en partes para copiarlas y pegarlas en el chat.
]]

----------------------------------------------------------------
-- CONFIGURACIÓN
----------------------------------------------------------------
local GUI_NAME  = "InfoCollectorGUI"
local PART_SIZE = 15000   -- Caracteres por parte al copiar
local MAX_REPORT = 120000 -- Tamaño máximo del informe

-- Palabras clave para buscar objetos (en minúsculas)
local KEYWORDS = {
    "brainrot", "fuse", "fusion", "fusionar", "merge", "combin", "machine", "maquina",
    "altar", "slot", "conveyor", "cinta", "collect", "cash", "money", "coins", "rebirth",
    "upgrade", "sell", "vender", "buy", "shop", "egg", "plot", "steal", "rarity", "mutation",
}
-- Módulos de datos que se leen (si la opción está activada)
local MODULE_KEYS = { "brainrot", "config", "data", "fuse", "fusion", "merge", "recipe",
    "rarity", "mutation", "item", "shop" }

local C = {
    Bg = Color3.fromRGB(16, 18, 26), Card = Color3.fromRGB(28, 31, 43), Btn = Color3.fromRGB(44, 48, 64),
    Accent = Color3.fromRGB(90, 130, 255), Green = Color3.fromRGB(46, 160, 105),
    Red = Color3.fromRGB(200, 70, 80), Amber = Color3.fromRGB(214, 150, 40),
    Text = Color3.fromRGB(235, 238, 245), Sub = Color3.fromRGB(150, 158, 178),
}

----------------------------------------------------------------
-- SERVICIOS
----------------------------------------------------------------
local Players            = game:GetService("Players")
local UserInputService   = game:GetService("UserInputService")
local CoreGui            = game:GetService("CoreGui")
local TweenService       = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local Workspace          = game:GetService("Workspace")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ReplicatedFirst    = game:GetService("ReplicatedFirst")

local player   = Players.LocalPlayer
local placeKey = tostring(game.PlaceId)
local env      = (getgenv and getgenv()) or _G

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

local function attrs(inst)
    local t = {}
    local ok, a = pcall(function() return inst:GetAttributes() end)
    if ok then
        for k, v in pairs(a) do t[#t + 1] = k .. "=" .. tostring(v) end
    end
    table.sort(t)
    return #t > 0 and ("  {" .. table.concat(t, ", ") .. "}") or ""
end

local function matchesAny(nameLower, list)
    for _, k in ipairs(list) do
        if string.find(nameLower, k, 1, true) then return true end
    end
    return false
end

-- Convierte cualquier valor en texto (limitado, para no llenar el informe)
local function ser(v, depth)
    depth = depth or 0
    local t = typeof(v)
    if t == "string" then
        return '"' .. (#v > 60 and (v:sub(1, 60) .. "…") or v) .. '"'
    elseif t == "number" or t == "boolean" or t == "nil" then
        return tostring(v)
    elseif t == "Instance" then
        return "<" .. v.ClassName .. ":" .. path(v) .. ">"
    elseif t == "table" then
        if depth >= 3 then return "{…}" end
        local parts, n = {}, 0
        for k, val in pairs(v) do
            n += 1
            if n > 25 then parts[#parts + 1] = "…" break end
            parts[#parts + 1] = "[" .. ser(k, depth + 1) .. "]=" .. ser(val, depth + 1)
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    elseif t == "function" then
        return "fn"
    else
        return t .. ":" .. tostring(v)
    end
end

-- Quita tu nombre de usuario del informe (privacidad)
local function scrub(s)
    for _, n in ipairs({ player.Name, player.DisplayName }) do
        if n and #n > 0 then
            local pat = n:gsub("%p", "%%%0")
            s = s:gsub(pat, "LocalPlayer")
        end
    end
    return s
end

----------------------------------------------------------------
-- ESTADO
----------------------------------------------------------------
local running, scanning = true, false
local connections = {}
local data = {}           -- secciones del informe: data.nombre = { líneas }
local order = { "general", "player", "tools", "remotes", "modules", "keywords", "prompts", "gui", "nearby" }
local fullText, parts, partIndex = "", {}, 1
local readModules = true
local logging = false

local function track(c) table.insert(connections, c) return c end

----------------------------------------------------------------
-- CAPTURA DE REMOTES (hook de solo lectura)
----------------------------------------------------------------
local state = { capturing = false, log = {}, order = {}, per = {}, total = 0 }
env.__InfoCollector = state

local hookOK = false
if hookmetamethod and getnamecallmethod then
    local ok = pcall(function()
        if env.__InfoCollectorHooked then hookOK = true return end
        local oldNamecall
        local function handler(self, ...)
            local st = env.__InfoCollector
            if st and st.capturing then
                local method = getnamecallmethod()
                if (method == "FireServer" or method == "InvokeServer") and typeof(self) == "Instance" then
                    local cls = self.ClassName
                    if cls == "RemoteEvent" or cls == "RemoteFunction" or cls == "UnreliableRemoteEvent" then
                        task.defer(st.record, self, method, table.pack(...))
                    end
                end
            end
            return oldNamecall(self, ...)
        end
        oldNamecall = hookmetamethod(game, "__namecall", newcclosure and newcclosure(handler) or handler)
        env.__InfoCollectorHooked = true
        hookOK = true
    end)
    if not ok then hookOK = false end
end

local refreshSummary -- se define abajo

state.record = function(remote, method, args)
    if not running then return end
    local rpath = path(remote)
    local list = {}
    for i = 1, args.n do list[i] = ser(args[i], 0) end
    local argStr = table.concat(list, ", ")
    if #argStr > 400 then argStr = argStr:sub(1, 400) .. "…" end
    local key = rpath .. "|" .. method .. "|" .. argStr
    state.total += 1
    state.per[rpath] = (state.per[rpath] or 0) + 1
    local e = state.log[key]
    if e then
        e.count += 1
    elseif #state.order < 150 then
        state.log[key] = { path = rpath, class = remote.ClassName, method = method, args = argStr, count = 1 }
        table.insert(state.order, key)
    end
    if refreshSummary then refreshSummary() end
end

----------------------------------------------------------------
-- RECOLECCIÓN DE DATOS
----------------------------------------------------------------
local yieldCounter = 0
local function ystep()
    yieldCounter += 1
    if yieldCounter % 400 == 0 then task.wait() end -- evita congelar el móvil
end

local setStatus -- se define con la interfaz

local function getHRP()
    local char = player.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function secGeneral()
    local name = "?"
    pcall(function() name = MarketplaceService:GetProductInfo(game.PlaceId).Name end)
    local exec = "?"
    pcall(function() exec = identifyexecutor and table.concat({ identifyexecutor() }, " ") or "desconocido" end)
    local L = {}
    L[#L + 1] = "Juego: " .. name
    L[#L + 1] = "PlaceId: " .. placeKey .. " | GameId: " .. tostring(game.GameId)
    L[#L + 1] = "Jugadores en el servidor: " .. #Players:GetPlayers() .. " | Servidor privado: " .. tostring(game.PrivateServerId ~= "")
    L[#L + 1] = "Ejecutor: " .. exec
    L[#L + 1] = "Dispositivo táctil: " .. tostring(UserInputService.TouchEnabled)
    L[#L + 1] = "Funciones: hookmetamethod=" .. tostring(hookOK) .. ", setclipboard=" .. tostring(setclipboard ~= nil)
        .. ", writefile=" .. tostring(writefile ~= nil) .. ", firesignal=" .. tostring(firesignal ~= nil)
        .. ", fireproximityprompt=" .. tostring(fireproximityprompt ~= nil)
        .. ", fireclickdetector=" .. tostring(fireclickdetector ~= nil)
    L[#L + 1] = "Fecha: " .. os.date("%Y-%m-%d %H:%M")
    data.general = L
end

local function secPlayer()
    local L = {}
    local a = attrs(player)
    if a ~= "" then L[#L + 1] = "Atributos del jugador:" .. a end
    local count = 0
    for _, d in ipairs(player:GetDescendants()) do
        ystep()
        if d:IsA("ValueBase") and not d:IsDescendantOf(player:FindFirstChild("PlayerGui") or player) then
            count += 1
            if count > 150 then L[#L + 1] = "… (más valores omitidos)" break end
            L[#L + 1] = path(d) .. " [" .. d.ClassName .. "] = " .. tostring(d.Value)
        end
    end
    if #L == 0 then L[1] = "(sin valores visibles en el jugador)" end
    data.player = L
end

local function secTools()
    local L = {}
    local function dump(container, label)
        if not container then return end
        for _, t in ipairs(container:GetChildren()) do
            if t:IsA("Tool") then
                local kids = {}
                for _, k in ipairs(t:GetChildren()) do kids[#kids + 1] = k.Name .. "(" .. k.ClassName .. ")" end
                L[#L + 1] = label .. ": " .. t.Name .. " | " .. table.concat(kids, ", ") .. attrs(t)
            end
        end
    end
    dump(player:FindFirstChild("Backpack"), "Mochila")
    dump(player.Character, "Equipada")
    if #L == 0 then L[1] = "(sin herramientas)" end
    data.tools = L
end

-- Un solo recorrido por Workspace y ReplicatedStorage para varias secciones
local function secWorld()
    local remotes, modules, promptGroups, promptOrder, clickers = {}, {}, {}, {}, {}
    local kwGroups, kwOrder = {}, {}

    local function visit(inst, root)
        local cls = inst.ClassName
        if cls == "RemoteEvent" or cls == "RemoteFunction" or cls == "UnreliableRemoteEvent" then
            if #remotes < 300 then remotes[#remotes + 1] = path(inst) .. "  [" .. cls .. "]" end
        elseif cls == "ModuleScript" and root ~= Workspace then
            if #modules < 200 then modules[#modules + 1] = inst end
        elseif cls == "ProximityPrompt" then
            local par = inst.Parent
            local key = inst.ActionText .. "|" .. inst.ObjectText .. "|" .. (par and par.Name or "?")
            local g = promptGroups[key]
            if g then
                g.count += 1
            elseif #promptOrder < 200 then
                local pos = ""
                if par and par:IsA("BasePart") then
                    local p = par.Position
                    pos = string.format(" pos(%.0f,%.0f,%.0f)", p.X, p.Y, p.Z)
                end
                promptGroups[key] = { count = 1, text = string.format(
                    'Action="%s" Object="%s" Hold=%.1f Dist=%.0f Enabled=%s | %s%s%s',
                    inst.ActionText, inst.ObjectText, inst.HoldDuration, inst.MaxActivationDistance,
                    tostring(inst.Enabled), path(inst), pos, attrs(par or inst)) }
                table.insert(promptOrder, key)
            end
        elseif cls == "ClickDetector" then
            if #clickers < 80 then clickers[#clickers + 1] = path(inst) end
        end

        -- Nombres clave (agrupados por nombre+clase para no repetir)
        local lower = inst.Name:lower()
        if #kwOrder < 250 and matchesAny(lower, KEYWORDS) then
            local key = inst.Name .. "|" .. cls
            local g = kwGroups[key]
            if g then
                g.count += 1
            else
                kwGroups[key] = { count = 1, text = inst.Name .. " [" .. cls .. "] " .. path(inst) .. attrs(inst) }
                table.insert(kwOrder, key)
            end
        end
    end

    local roots = { ReplicatedStorage, ReplicatedFirst, Workspace }
    for _, root in ipairs(roots) do
        setStatus("Escaneando " .. root.Name .. "…")
        for _, inst in ipairs(root:GetDescendants()) do
            if not scanning or not running then return end
            ystep()
            visit(inst, root)
        end
    end

    table.sort(remotes)
    data.remotes = #remotes > 0 and remotes or { "(no se encontraron remotes)" }

    -- Módulos: lista + lectura de los de datos
    local L = {}
    for _, m in ipairs(modules) do L[#L + 1] = path(m) end
    if readModules then
        local read = 0
        for _, m in ipairs(modules) do
            if read >= 12 then break end
            if matchesAny(m.Name:lower(), MODULE_KEYS) then
                read += 1
                local ok, res = pcall(require, m)
                local text = ok and ser(res, 0) or ("(no se pudo leer: " .. tostring(res):sub(1, 80) .. ")")
                if #text > 2500 then text = text:sub(1, 2500) .. "…" end
                L[#L + 1] = ""
                L[#L + 1] = ">> CONTENIDO de " .. path(m) .. ":"
                L[#L + 1] = text
            end
        end
    end
    data.modules = #L > 0 and L or { "(sin módulos en ReplicatedStorage)" }

    local K = {}
    for _, key in ipairs(kwOrder) do
        local g = kwGroups[key]
        K[#K + 1] = (g.count > 1 and ("[x" .. g.count .. "] ") or "") .. g.text
    end
    data.keywords = #K > 0 and K or { "(sin coincidencias)" }

    local P = {}
    for _, key in ipairs(promptOrder) do
        local g = promptGroups[key]
        P[#P + 1] = (g.count > 1 and ("[x" .. g.count .. "] ") or "") .. g.text
    end
    if #clickers > 0 then
        P[#P + 1] = ""
        P[#P + 1] = "ClickDetectors:"
        for _, c in ipairs(clickers) do P[#P + 1] = c end
    end
    data.prompts = #P > 0 and P or { "(sin prompts ni click detectors)" }
end

local function secGui()
    local L = {}
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then data.gui = { "(sin PlayerGui)" } return end

    L[#L + 1] = "ScreenGuis:"
    for _, g in ipairs(pg:GetChildren()) do
        if g:IsA("ScreenGui") then L[#L + 1] = "  " .. g.Name .. " | Enabled=" .. tostring(g.Enabled) end
    end

    local btns, labels = 0, 0
    L[#L + 1] = ""
    L[#L + 1] = "Botones (ruta | texto | visible):"
    for _, d in ipairs(pg:GetDescendants()) do
        ystep()
        if (d:IsA("TextButton") or d:IsA("ImageButton")) and btns < 200 then
            btns += 1
            local txt = d:IsA("TextButton") and d.Text or ""
            L[#L + 1] = "  " .. path(d) .. " | \"" .. txt:sub(1, 40) .. "\" | " .. tostring(d.Visible)
        end
    end
    L[#L + 1] = ""
    L[#L + 1] = "Textos (ruta | contenido):"
    for _, d in ipairs(pg:GetDescendants()) do
        ystep()
        if d:IsA("TextLabel") and d.Text ~= "" and labels < 200 then
            labels += 1
            L[#L + 1] = "  " .. path(d) .. " | \"" .. d.Text:sub(1, 50):gsub("\n", " ") .. "\""
        end
    end
    data.gui = L
end

local function secNearby(radius)
    local hrp = getHRP()
    if not hrp then data.nearby = { "(sin personaje)" } return end
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { player.Character }
    params.MaxParts = 600
    local groups, list = {}, {}
    for _, part in ipairs(Workspace:GetPartBoundsInRadius(hrp.Position, radius, params)) do
        ystep()
        local m = part:FindFirstAncestorOfClass("Model") or part
        local key = m.Name .. "|" .. m.ClassName
        local dist = (part.Position - hrp.Position).Magnitude
        local g = groups[key]
        if g then
            g.count += 1
            g.dist = math.min(g.dist, dist)
        else
            groups[key] = { name = m.Name, cls = m.ClassName, count = 1, dist = dist, path = path(m), attrs = attrs(m) }
            table.insert(list, groups[key])
        end
    end
    table.sort(list, function(a, b) return a.dist < b.dist end)
    local p = hrp.Position
    local L = { string.format("Tu posición: (%.0f, %.0f, %.0f) | radio %d", p.X, p.Y, p.Z, radius) }
    for i, g in ipairs(list) do
        if i > 60 then L[#L + 1] = "… (más omitidos)" break end
        L[#L + 1] = string.format("%s%s [%s] dist≈%.0f | %s%s",
            g.count > 1 and ("[x" .. g.count .. "] ") or "", g.name, g.cls, g.dist, g.path, g.attrs)
    end
    data.nearby = L
end

-- Sección con lo capturado de los remotes
local function capturedLines()
    local L = {}
    if state.total == 0 then return { "(no se capturó nada)" } end
    L[#L + 1] = "Total de llamadas capturadas: " .. state.total
    L[#L + 1] = ""
    L[#L + 1] = "Resumen por remote (cuántas veces se llamó):"
    local per = {}
    for p, n in pairs(state.per) do per[#per + 1] = { p = p, n = n } end
    table.sort(per, function(a, b) return a.n > b.n end)
    for i, e in ipairs(per) do
        if i > 40 then break end
        L[#L + 1] = "  " .. e.n .. "x  " .. e.p
    end
    L[#L + 1] = ""
    L[#L + 1] = "Llamadas únicas (veces | método | remote | argumentos):"
    for _, key in ipairs(state.order) do
        local e = state.log[key]
        L[#L + 1] = string.format("  [x%d] %s  %s [%s]  args: (%s)", e.count, e.method, e.path, e.class, e.args)
    end
    return L
end

----------------------------------------------------------------
-- ARMAR EL INFORME
----------------------------------------------------------------
local titles = {
    general = "DATOS GENERALES", player = "VALORES DEL JUGADOR", tools = "HERRAMIENTAS",
    remotes = "REMOTES", modules = "MÓDULOS (ReplicatedStorage)", keywords = "OBJETOS CON NOMBRES CLAVE",
    prompts = "PROXIMITYPROMPTS / CLICKDETECTORS", gui = "INTERFAZ (PlayerGui)", nearby = "OBJETOS CERCANOS",
}

local function buildReport()
    local out = { "=== INFO COLLECTOR ===" }
    for _, key in ipairs(order) do
        if data[key] then
            out[#out + 1] = ""
            out[#out + 1] = "##### " .. titles[key] .. " #####"
            for _, line in ipairs(data[key]) do out[#out + 1] = line end
        end
    end
    if state.total > 0 then
        out[#out + 1] = ""
        out[#out + 1] = "##### REMOTES CAPTURADOS (acciones hechas por mí) #####"
        for _, line in ipairs(capturedLines()) do out[#out + 1] = line end
    end
    local text = scrub(table.concat(out, "\n"))
    if #text > MAX_REPORT then text = text:sub(1, MAX_REPORT) .. "\n… (informe recortado)" end
    fullText = text

    -- Dividir en partes por saltos de línea
    parts = {}
    local cur = {}
    local size = 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
        if size + #line + 1 > PART_SIZE and #cur > 0 then
            parts[#parts + 1] = table.concat(cur, "\n")
            cur, size = {}, 0
        end
        cur[#cur + 1] = line
        size += #line + 1
    end
    if #cur > 0 then parts[#parts + 1] = table.concat(cur, "\n") end
    partIndex = clamp(partIndex, 1, math.max(#parts, 1))
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

local t1 = makeLabel(header, "🔎 Info Collector", UDim2.new(1, -90, 0, 24), UDim2.new(0, 14, 0, 4), 16)
t1.Font = Enum.Font.GothamBold
makeLabel(header, "Recopila datos del juego", UDim2.new(1, -90, 0, 16), UDim2.new(0, 14, 0, 26), 11, C.Sub)

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
    local b = makeButton(scroll, text, UDim2.new(1, 0, 0, h or 46), nil, color)
    b.LayoutOrder = nextOrder()
    return b
end

-- Estado
local statusCard = card(54)
local statusLabel = makeLabel(statusCard, "Listo. Pulsa «Escanear todo».", UDim2.new(1, -20, 1, -12), UDim2.new(0, 10, 0, 6), 13, C.Text)
function setStatus(text) statusLabel.Text = text end

-- Escaneo
local scanBtn = bigButton("🔎  Escanear todo", C.Accent, 50)

-- Módulos
local modBtn = bigButton("", C.Btn, 40)
local function refreshMod()
    modBtn.Text = "Leer módulos de datos: " .. (readModules and "SÍ" or "NO")
    modBtn.BackgroundColor3 = readModules and C.Green or C.Btn
end
modBtn.Activated:Connect(function() readModules = not readModules refreshMod() end)
refreshMod()

-- Remotes
local hint = makeLabel(scroll, "Para captar las acciones del juego: activa la captura y haz TÚ la acción varias veces (fusionar, comprar, vender…).",
    UDim2.new(1, 0, 0, 48), nil, 12, C.Sub)
hint.LayoutOrder = nextOrder()
local logBtn = bigButton("", C.Btn, 48)
local function refreshLog()
    logBtn.Text = "📡 Capturar remotes: " .. (logging and "ON" or "OFF")
    logBtn.BackgroundColor3 = logging and C.Red or C.Btn
end
logBtn.Activated:Connect(function()
    if not hookOK then
        setStatus("⚠ Tu ejecutor no soporta hookmetamethod: no se pueden capturar remotes.")
        return
    end
    logging = not logging
    state.capturing = logging
    refreshLog()
    setStatus(logging and "Capturando… haz la acción en el juego." or "Captura detenida.")
end)
refreshLog()

-- Cercanos
local nearCard = card(48)
makeLabel(nearCard, "Radio (studs):", UDim2.new(0, 100, 1, 0), UDim2.new(0, 10, 0, 14), 13, C.Sub)
local radiusBox = Instance.new("TextBox")
radiusBox.Size = UDim2.fromOffset(56, 32)
radiusBox.Position = UDim2.new(0, 108, 0, 8)
radiusBox.BackgroundColor3 = C.Btn
radiusBox.Text = "60"
radiusBox.TextColor3 = C.Text
radiusBox.Font = Enum.Font.GothamBold
radiusBox.TextSize = 14
radiusBox.ClearTextOnFocus = false
radiusBox.Parent = nearCard
corner(radiusBox, 8)
local nearBtn = makeButton(nearCard, "📍 Cercanos", UDim2.new(1, -176, 0, 32), UDim2.new(0, 168, 0, 8), C.Btn)

-- Resumen e informe
local sumCard = card(96)
local sumLabel = makeLabel(sumCard, "", UDim2.new(1, -20, 1, -12), UDim2.new(0, 10, 0, 6), 12, C.Sub)

local copyBtn = bigButton("📋  Copiar informe", C.Green, 50)
local saveBtn = bigButton("💾  Guardar en archivo", C.Btn, 42)
local clearBtn = bigButton("🧹  Limpiar todo", C.Btn, 42)

local prevTag = makeLabel(scroll, "VISTA PREVIA", UDim2.new(1, 0, 0, 18), nil, 11, C.Sub)
prevTag.Font = Enum.Font.GothamBold
prevTag.LayoutOrder = nextOrder()
local preview = Instance.new("TextBox")
preview.Size = UDim2.new(1, 0, 0, 160)
preview.BackgroundColor3 = C.Card
preview.TextColor3 = C.Sub
preview.Font = Enum.Font.Code
preview.TextSize = 11
preview.TextXAlignment = Enum.TextXAlignment.Left
preview.TextYAlignment = Enum.TextYAlignment.Top
preview.TextWrapped = true
preview.MultiLine = true
preview.ClearTextOnFocus = false
preview.TextEditable = false
preview.Text = ""
preview.LayoutOrder = nextOrder()
preview.Parent = scroll
corner(preview, 10)

local function refreshCopyBtn()
    if #parts == 0 then
        copyBtn.Text = "📋  Copiar informe"
    else
        copyBtn.Text = string.format("📋  Copiar parte %d/%d", partIndex, #parts)
    end
end

function refreshSummary()
    local function n(key) return data[key] and #data[key] or 0 end
    sumLabel.Text = string.format(
        "Remotes: %d | Módulos: %d | Claves: %d\nPrompts: %d | GUI: %d líneas | Cercanos: %d\nCapturados: %d llamadas (%d únicas)\nInforme: %d caracteres en %d parte(s)",
        n("remotes"), n("modules"), n("keywords"), n("prompts"), n("gui"), n("nearby"),
        state.total, #state.order, #fullText, #parts)
end

local function refreshAll()
    buildReport()
    refreshSummary()
    refreshCopyBtn()
    local p = parts[partIndex] or ""
    preview.Text = #p > 2500 and (p:sub(1, 2500) .. "\n…") or p
end

-- Toque de aviso
local function flash(text)
    setStatus(text)
end

----------------------------------------------------------------
-- ACCIONES
----------------------------------------------------------------
scanBtn.Activated:Connect(function()
    if scanning then return end
    scanning = true
    scanBtn.Text = "Escaneando…"
    task.spawn(function()
        local steps = {
            { "Datos generales…", secGeneral }, { "Tus valores…", secPlayer }, { "Herramientas…", secTools },
            { "Mundo (remotes, prompts, nombres clave)…", secWorld }, { "Interfaz…", secGui },
        }
        for _, s in ipairs(steps) do
            if not running then return end
            setStatus(s[1])
            local ok, err = pcall(s[2])
            if not ok then setStatus("⚠ Error en una sección: " .. tostring(err):sub(1, 80)) task.wait(1) end
            task.wait()
        end
        scanning = false
        scanBtn.Text = "🔎  Escanear todo"
        partIndex = 1
        refreshAll()
        flash("✔ Escaneo completo. Copia el informe por partes.")
    end)
end)

nearBtn.Activated:Connect(function()
    local r = clamp(tonumber(radiusBox.Text) or 60, 10, 300)
    radiusBox.Text = tostring(r)
    local ok, err = pcall(secNearby, r)
    refreshAll()
    flash(ok and "✔ Objetos cercanos añadidos al informe." or ("⚠ " .. tostring(err):sub(1, 80)))
end)

copyBtn.Activated:Connect(function()
    refreshAll() -- incluye lo último capturado
    if #parts == 0 then flash("Aún no hay informe. Escanea primero.") return end
    local p = parts[partIndex]
    local copier = setclipboard or toclipboard
    if copier then
        local ok = pcall(copier, p)
        if ok then
            flash(string.format("📋 Copiada la parte %d de %d. Pégala en el chat%s.",
                partIndex, #parts, #parts > partIndex and " y vuelve por la siguiente" or ""))
            partIndex = partIndex % #parts + 1
            refreshCopyBtn()
            return
        end
    end
    flash("⚠ No se pudo copiar. Usa «Guardar en archivo».")
end)

saveBtn.Activated:Connect(function()
    refreshAll()
    if not writefile then flash("⚠ Tu ejecutor no soporta writefile.") return end
    local name = "InfoCollector_" .. placeKey .. ".txt"
    local ok = pcall(writefile, name, fullText)
    flash(ok and ("💾 Guardado como " .. name .. " en la carpeta workspace de tu ejecutor.") or "⚠ No se pudo guardar.")
end)

clearBtn.Activated:Connect(function()
    data = {}
    state.log, state.order, state.per, state.total = {}, {}, {}, 0
    fullText, parts, partIndex = "", {}, 1
    preview.Text = ""
    refreshSummary()
    refreshCopyBtn()
    flash("Todo limpio.")
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
    running, scanning = false, false
    state.capturing = false -- el hook queda inactivo (pasa todo sin registrar)
    for _, c in ipairs(connections) do c:Disconnect() end
    gui:Destroy()
end)

----------------------------------------------------------------
-- INICIO
----------------------------------------------------------------
layoutFrame()
refreshSummary()
refreshCopyBtn()
if not hookOK then
    setStatus("Listo. Nota: tu ejecutor no soporta hookmetamethod, así que no podrás capturar remotes.")
end
