--[[
    REMOTE CAPTURE + SCANNER para Delta (Mobile/PC)

    PESTAÑA 📡 CAPTURA (igual que antes)
    - Captura RemoteEvent / RemoteFunction que TÚ disparas, con argumentos y respuesta del servidor
    - Botón "Marcar acción", ocultar ruido, copiar / guardar informe

    PESTAÑA 🔍 SCANNER (nueva, independiente de la captura)
    - Lista los nombres de TODOS los modelos del Workspace (pets, NPCs, corrales, etc.), agrupados
      (Pen_1_2, Pen_3_4 -> Pen_#_#) con cantidad, ejemplo de ruta, atributos e hijos
    - Zona: Workspace / ReplicatedStorage / ambos
    - Modo: solo Modelos / Modelos+Carpetas / Todo
    - Filtro por nombre o ruta (ej: pet) y radio alrededor de tu personaje
    - Clases más comunes, hijos directos del Workspace y ProximityPrompts (NPCs, tiendas)
    - Ver mi personaje y mochila (lo que llevas en la mano)
    - Copiar o guardar el informe, con nombres de usuario ocultos
]]

----------------------------------------------------------------
-- CONFIGURACIÓN
----------------------------------------------------------------
local GUI_NAME   = "RemoteCaptureGUI"
local MAX_CALLS  = 150
local MAX_REPORT = 30000
local MAX_SCAN   = 40000
local MAX_GROUPS = 250
local NOISE = { "^Get", "^Report", "^Record", "^Note", "Hover", "^IsWild" }

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
local Workspace          = game:GetService("Workspace")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
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
            if n and #n > 1 then
                local pat = n:gsub("%p", "%%%0")
                s = s:gsub(pat, alias)
            end
        end
        s = s:gsub(tostring(pl.UserId), "UID")
    end
    return s
end

local function copyText(text)
    local copier = setclipboard or toclipboard
    return copier ~= nil and pcall(copier, text)
end

local function gameName()
    local name = "?"
    pcall(function() name = MarketplaceService:GetProductInfo(game.PlaceId).Name end)
    return name
end

----------------------------------------------------------------
-- ESTADO + CAPTURA DE REMOTES
----------------------------------------------------------------
local running = true
local connections = {}
local function track(c) table.insert(connections, c) return c end

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
    local out = {
        "=== REMOTES CAPTURADOS ===",
        "Juego: " .. gameName() .. " | PlaceId: " .. game.PlaceId,
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
-- SCANNER DE WORKSPACE
----------------------------------------------------------------
local scan = {
    zone = 1,          -- 1 Workspace, 2 ReplicatedStorage, 3 ambos
    mode = 1,          -- 1 Modelos, 2 Modelos+Carpetas, 3 Todo
    hidePlayers = true,
    report = "",
    busy = false,
    preview = "(nada todavía)",
    status = "Pulsa «Escanear».",
}
local zoneNames = { "Workspace", "ReplicatedStorage", "Workspace + ReplicatedStorage" }
local modeNames = { "Solo Modelos", "Modelos + Carpetas", "Todo (cualquier objeto)" }

-- "Pen_3_12" -> "Pen_#_#" ; uuid -> <uuid>
local function normName(n)
    n = n:gsub("%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x", "<uuid>")
    n = n:gsub("%d+", "#")
    return n
end

local function relPath(inst)
    local p = path(inst)
    p = p:gsub("^Workspace%.", "")
    return #p > 100 and ("…" .. p:sub(-99)) or p
end

local function sampleInfo(d)
    local bits = {}
    local okA, attrs = pcall(d.GetAttributes, d)
    if okA and attrs and next(attrs) then bits[#bits + 1] = "attrs=" .. ser(attrs, 0) end
    local kids, seen, n = {}, {}, 0
    for _, c in ipairs(d:GetChildren()) do
        local k = c.ClassName .. ":" .. normName(c.Name)
        if not seen[k] then
            seen[k] = true
            n += 1
            if n <= 8 then kids[#kids + 1] = k end
        end
    end
    if n > 0 then bits[#bits + 1] = "hijos=" .. table.concat(kids, ", ") .. (n > 8 and ", …" or "") end
    if d:IsA("Model") then
        if d:FindFirstChildOfClass("Humanoid") then bits[#bits + 1] = "Humanoid" end
        if d.PrimaryPart then bits[#bits + 1] = "Primary=" .. d.PrimaryPart.Name end
    end
    return table.concat(bits, " | ")
end

local function instPos(d)
    local ok, pos = pcall(function()
        if d:IsA("Model") then return d:GetPivot().Position end
        if d:IsA("BasePart") then return d.Position end
        return nil
    end)
    return ok and pos or nil
end

local function runScan(filterText, radiusText)
    if scan.busy then return end
    scan.busy = true
    scan.status = "Escaneando…"

    local ok, err = pcall(function()
        local filter = (filterText or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        local radius = tonumber(radiusText) or 0
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local center = (radius > 0 and hrp) and hrp.Position or nil

        local chars = {}
        if scan.hidePlayers then
            for _, pl in ipairs(Players:GetPlayers()) do
                if pl.Character then chars[#chars + 1] = pl.Character end
            end
        end

        local roots = {}
        if scan.zone == 1 or scan.zone == 3 then roots[#roots + 1] = Workspace end
        if scan.zone == 2 or scan.zone == 3 then roots[#roots + 1] = ReplicatedStorage end

        local groups, classCount, prompts = {}, {}, {}
        local keyCache = {}
        local function keyOf(name)
            local k = keyCache[name]
            if not k then k = normName(name) keyCache[name] = k end
            return k
        end

        local checked, n = 0, 0
        for _, root in ipairs(roots) do
            for _, d in ipairs(root:GetDescendants()) do
                n += 1
                if n % 400 == 0 then task.wait() end

                local skip = false
                for _, ch in ipairs(chars) do
                    if d == ch or d:IsDescendantOf(ch) then skip = true break end
                end
                if skip then continue end
                checked += 1
                classCount[d.ClassName] = (classCount[d.ClassName] or 0) + 1

                if d:IsA("ProximityPrompt") then
                    local pk = tostring(d.ActionText) .. " | " .. tostring(d.ObjectText) .. " | en " .. keyOf(d.Parent and d.Parent.Name or "?")
                    local g = prompts[pk]
                    if g then g.count += 1 else prompts[pk] = { count = 1, sample = d } end
                end

                local take = (scan.mode == 3) or d:IsA("Model") or (scan.mode == 2 and d:IsA("Folder"))
                if not take then continue end

                local dist
                if center then
                    local pos = instPos(d)
                    if not pos then continue end
                    dist = (pos - center).Magnitude
                    if dist > radius then continue end
                end

                local key = keyOf(d.Name)
                local p
                if filter ~= "" then
                    p = relPath(d)
                    if not (key:lower():find(filter, 1, true) or p:lower():find(filter, 1, true)) then continue end
                end

                local gk = key .. "|" .. d.ClassName
                local g = groups[gk]
                if g then
                    g.count += 1
                    if dist and (not g.dist or dist < g.dist) then g.dist = dist end
                else
                    groups[gk] = { name = key, class = d.ClassName, count = 1, sample = d, dist = dist }
                end
            end
        end

        -- Ordenar
        local list = {}
        for _, g in pairs(groups) do list[#list + 1] = g end
        table.sort(list, function(a, b)
            if a.count ~= b.count then return a.count > b.count end
            return a.name < b.name
        end)

        -- Informe
        local out = {
            "=== SCANNER ===",
            "Juego: " .. gameName() .. " | PlaceId: " .. game.PlaceId,
            "Zona: " .. zoneNames[scan.zone] .. " | Modo: " .. modeNames[scan.mode],
            "Filtro: " .. (filter ~= "" and filter or "ninguno") .. " | Radio: " .. (center and (radius .. " studs") or "todo")
                .. " | Jugadores ocultos: " .. (scan.hidePlayers and "sí" or "no"),
            "Instancias revisadas: " .. checked .. " | Grupos de nombres: " .. #list,
            "",
        }

        -- Clases más comunes
        local cl = {}
        for k, v in pairs(classCount) do cl[#cl + 1] = { k, v } end
        table.sort(cl, function(a, b) return a[2] > b[2] end)
        out[#out + 1] = "## CLASES MÁS COMUNES"
        local cparts = {}
        for i = 1, math.min(15, #cl) do cparts[#cparts + 1] = cl[i][1] .. " x" .. cl[i][2] end
        out[#out + 1] = table.concat(cparts, ", ")
        out[#out + 1] = ""

        -- Hijos directos del Workspace
        if scan.zone == 1 or scan.zone == 3 then
            local direct, dorder = {}, {}
            for _, c in ipairs(Workspace:GetChildren()) do
                local isChar = false
                for _, ch in ipairs(chars) do if c == ch then isChar = true break end end
                if not isChar then
                    local k = keyOf(c.Name) .. " [" .. c.ClassName .. "]"
                    if direct[k] then direct[k] += 1 else direct[k] = 1 dorder[#dorder + 1] = k end
                end
            end
            table.sort(dorder)
            out[#out + 1] = "## HIJOS DIRECTOS DE WORKSPACE"
            for i, k in ipairs(dorder) do
                if i > 80 then out[#out + 1] = "… (más)" break end
                out[#out + 1] = k .. (direct[k] > 1 and (" x" .. direct[k]) or "")
            end
            out[#out + 1] = ""
        end

        -- Modelos / objetos agrupados
        out[#out + 1] = "## NOMBRES (nombre [Clase] xCantidad)"
        local previewLines = {}
        for i, g in ipairs(list) do
            if i > MAX_GROUPS then out[#out + 1] = "… (" .. (#list - MAX_GROUPS) .. " grupos más; usa filtro o radio)" break end
            out[#out + 1] = g.name .. " [" .. g.class .. "] x" .. g.count .. (g.dist and (string.format("  (más cerca: %.0f studs)", g.dist)) or "")
            out[#out + 1] = "    ej: " .. relPath(g.sample)
            local info = sampleInfo(g.sample)
            if info ~= "" then out[#out + 1] = "    " .. info end
            if i <= 8 then previewLines[#previewLines + 1] = g.name .. " x" .. g.count end
        end
        if #list == 0 then out[#out + 1] = "(ninguno con esos criterios)" end
        out[#out + 1] = ""

        -- Prompts (NPCs, tiendas, acciones)
        local pl = {}
        for k, v in pairs(prompts) do pl[#pl + 1] = { k, v } end
        table.sort(pl, function(a, b) return a[2].count > b[2].count end)
        out[#out + 1] = "## PROXIMITY PROMPTS (acción | objeto | en)"
        for i, e in ipairs(pl) do
            if i > 40 then out[#out + 1] = "… (más)" break end
            out[#out + 1] = e[1] .. " x" .. e[2].count .. "  ej: " .. relPath(e[2].sample)
        end
        if #pl == 0 then out[#out + 1] = "(ninguno)" end

        local text = scrub(table.concat(out, "\n"))
        if #text > MAX_SCAN then text = text:sub(1, MAX_SCAN) .. "\n… (recortado)" end
        scan.report = text
        scan.preview = #previewLines > 0 and scrub(table.concat(previewLines, "\n")) or "(ninguno)"
        scan.status = "✅ " .. #list .. " grupos, " .. checked .. " objetos revisados. Copia o guarda el informe."
    end)

    scan.busy = false
    if not ok then scan.status = "⚠ Error: " .. tostring(err):sub(1, 70) end
end

-- Personaje, mochila y lo que llevas en la mano
local function myCharReport()
    local out = { "=== MI PERSONAJE ===", "Juego: " .. gameName() .. " | PlaceId: " .. game.PlaceId, "" }
    local char = player.Character
    if char then
        out[#out + 1] = "## HIJOS DEL PERSONAJE"
        for _, c in ipairs(char:GetChildren()) do
            if not c:IsA("BasePart") and not c:IsA("Accessory") and not c:IsA("Humanoid") then
                local okA, attrs = pcall(c.GetAttributes, c)
                out[#out + 1] = c.ClassName .. ": " .. c.Name
                    .. ((okA and attrs and next(attrs)) and ("  attrs=" .. ser(attrs, 0)) or "")
                if c:IsA("Model") or c:IsA("Tool") or c:IsA("Folder") then
                    local kids, n = {}, 0
                    for _, k in ipairs(c:GetChildren()) do
                        n += 1
                        if n <= 10 then kids[#kids + 1] = k.ClassName .. ":" .. k.Name end
                    end
                    if n > 0 then out[#out + 1] = "    hijos=" .. table.concat(kids, ", ") .. (n > 10 and ", …" or "") end
                end
            end
        end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then
            out[#out + 1] = string.format("Posición: %.1f, %.1f, %.1f", hrp.Position.X, hrp.Position.Y, hrp.Position.Z)
        end
    else
        out[#out + 1] = "(sin personaje)"
    end
    out[#out + 1] = ""
    out[#out + 1] = "## MOCHILA"
    local bp = player:FindFirstChildOfClass("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            local okA, attrs = pcall(t.GetAttributes, t)
            out[#out + 1] = t.ClassName .. ": " .. t.Name
                .. ((okA and attrs and next(attrs)) and ("  attrs=" .. ser(attrs, 0)) or "")
        end
        if #bp:GetChildren() == 0 then out[#out + 1] = "(vacía)" end
    else
        out[#out + 1] = "(sin Backpack)"
    end
    out[#out + 1] = ""
    out[#out + 1] = "## ATRIBUTOS DEL JUGADOR"
    local okP, pattrs = pcall(player.GetAttributes, player)
    out[#out + 1] = (okP and pattrs and next(pattrs)) and ser(pattrs, 0) or "(ninguno)"
    local ls = player:FindFirstChild("leaderstats")
    if ls then
        out[#out + 1] = ""
        out[#out + 1] = "## LEADERSTATS"
        for _, v in ipairs(ls:GetChildren()) do
            out[#out + 1] = v.Name .. " = " .. (pcall(function() return v.Value end) and tostring(v.Value) or "?")
        end
    end
    return scrub(table.concat(out, "\n"))
end

----------------------------------------------------------------
-- INTERFAZ: helpers
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

----------------------------------------------------------------
-- INTERFAZ: ventana y pestañas
----------------------------------------------------------------
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

makeLabel(header, "📡 Remote Capture + Scanner", UDim2.new(1, -90, 0, 24), UDim2.new(0, 14, 0, 4), 16).Font = Enum.Font.GothamBold
makeLabel(header, "Solo captura y lee, no modifica nada", UDim2.new(1, -90, 0, 16), UDim2.new(0, 14, 0, 26), 11, C.Sub)
local minBtn   = makeButton(header, "–", UDim2.fromOffset(32, 32), UDim2.new(1, -78, 0.5, -16))
local closeBtn = makeButton(header, "✕", UDim2.fromOffset(32, 32), UDim2.new(1, -40, 0.5, -16), C.Red)

local body = Instance.new("Frame")
body.Size = UDim2.new(1, -16, 1, -HEADER_H - 8)
body.Position = UDim2.new(0, 8, 0, HEADER_H + 8)
body.BackgroundTransparency = 1
body.Parent = frame

local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, 0, 0, 36)
tabBar.BackgroundTransparency = 1
tabBar.Parent = body
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 6)
tabLayout.Parent = tabBar

local content = Instance.new("Frame")
content.Size = UDim2.new(1, 0, 1, -42)
content.Position = UDim2.new(0, 0, 0, 42)
content.BackgroundTransparency = 1
content.Parent = body

local lo = 0
local function nextOrder() lo += 1 return lo end

local function newPage()
    local s = Instance.new("ScrollingFrame")
    s.Size = UDim2.new(1, 0, 1, 0)
    s.BackgroundTransparency = 1
    s.BorderSizePixel = 0
    s.ScrollBarThickness = 3
    s.ScrollBarImageColor3 = C.Accent
    s.CanvasSize = UDim2.new()
    s.AutomaticCanvasSize = Enum.AutomaticSize.Y
    s.Visible = false
    s.Parent = content
    local l = Instance.new("UIListLayout")
    l.Padding = UDim.new(0, 6)
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Parent = s
    local pad = Instance.new("UIPadding", s)
    pad.PaddingRight, pad.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6)
    return s
end

local pageCap, pageScan = newPage(), newPage()
local tabs = {}
local function selectTab(i)
    for idx, t in ipairs(tabs) do
        t.page.Visible = (idx == i)
        t.btn.BackgroundColor3 = (idx == i) and C.Accent or C.Card
        t.btn.TextColor3 = (idx == i) and Color3.fromRGB(255, 255, 255) or C.Sub
    end
end
local function addTab(text, page)
    local b = makeButton(tabBar, text, UDim2.new(0.5, -3, 1, 0), nil, C.Card)
    b.TextSize = 13
    table.insert(tabs, { btn = b, page = page })
    local idx = #tabs
    b.Activated:Connect(function() selectTab(idx) end)
end
addTab("📡 Captura", pageCap)
addTab("🔍 Scanner", pageScan)

local function bigButton(parent, text, color, h)
    local b = makeButton(parent, text, UDim2.new(1, 0, 0, h or 44), nil, color)
    b.LayoutOrder = nextOrder()
    return b
end
local function card(parent, h)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, 0, 0, h)
    f.BackgroundColor3 = C.Card
    f.LayoutOrder = nextOrder()
    f.Parent = parent
    corner(f, 12)
    return f
end
local function makeBox(parent, placeholder)
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, -16, 0, 34)
    box.Position = UDim2.new(0, 8, 0, 7)
    box.BackgroundColor3 = C.Btn
    box.PlaceholderText = placeholder
    box.PlaceholderColor3 = C.Sub
    box.Text = ""
    box.TextColor3 = C.Text
    box.Font = Enum.Font.Gotham
    box.TextSize = 14
    box.ClearTextOnFocus = false
    box.Parent = parent
    corner(box, 8)
    return box
end

----------------------------------------------------------------
-- PESTAÑA 1: CAPTURA
----------------------------------------------------------------
local statusCard = card(pageCap, 54)
local statusLabel = makeLabel(statusCard, "", UDim2.new(1, -20, 1, -12), UDim2.new(0, 10, 0, 6), 13)

local logBtn = bigButton(pageCap, "", C.Btn, 50)
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

local hideBtn = bigButton(pageCap, "", C.Btn, 38)
local function refreshHide()
    hideBtn.Text = "Ocultar ruido (Get/Report/Record): " .. (state.hide and "SÍ" or "NO")
    hideBtn.BackgroundColor3 = state.hide and C.Green or C.Btn
    hideBtn.TextSize = 12
end
hideBtn.Activated:Connect(function() state.hide = not state.hide refreshHide() end)
refreshHide()

local markCard = card(pageCap, 48)
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

local liveTag = makeLabel(pageCap, "ÚLTIMAS LLAMADAS", UDim2.new(1, 0, 0, 16), nil, 11, C.Sub)
liveTag.Font = Enum.Font.GothamBold
liveTag.LayoutOrder = nextOrder()
local liveCard = card(pageCap, 150)
local liveLabel = makeLabel(liveCard, "", UDim2.new(1, -16, 1, -12), UDim2.new(0, 8, 0, 6), 11, C.Sub)
liveLabel.Font = Enum.Font.Code

local copyBtn  = bigButton(pageCap, "📋  Copiar informe", C.Green, 50)
local saveBtn  = bigButton(pageCap, "💾  Guardar en archivo", C.Btn, 40)
local clearBtn = bigButton(pageCap, "🧹  Limpiar", C.Btn, 40)

copyBtn.Activated:Connect(function()
    if state.total == 0 then statusLabel.Text = "Aún no hay nada capturado." return end
    local text = buildReport()
    if copyText(text) then
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

----------------------------------------------------------------
-- PESTAÑA 2: SCANNER
----------------------------------------------------------------
local scanStatusCard = card(pageScan, 54)
local scanStatusLabel = makeLabel(scanStatusCard, "", UDim2.new(1, -20, 1, -12), UDim2.new(0, 10, 0, 6), 13)

local scanGo = bigButton(pageScan, "🔍  ESCANEAR", C.Green, 50)

local filterCard = card(pageScan, 48)
local filterBox = makeBox(filterCard, "Filtrar por nombre o ruta (ej: pet)")
local radiusCard = card(pageScan, 48)
local radiusBox = makeBox(radiusCard, "Radio alrededor de mí en studs (vacío = todo)")
radiusBox.Text = ""

local zoneBtn = bigButton(pageScan, "", C.Btn, 40)
zoneBtn.TextSize = 12
local function refreshZone() zoneBtn.Text = "Zona: " .. zoneNames[scan.zone] .. "\nToca para cambiar" end
zoneBtn.Activated:Connect(function() scan.zone = scan.zone % 3 + 1 refreshZone() end)
refreshZone()

local modeBtn = bigButton(pageScan, "", C.Btn, 40)
modeBtn.TextSize = 12
local function refreshMode() modeBtn.Text = "Buscar: " .. modeNames[scan.mode] .. "\nToca para cambiar" end
modeBtn.Activated:Connect(function() scan.mode = scan.mode % 3 + 1 refreshMode() end)
refreshMode()

local playersBtn = bigButton(pageScan, "", C.Btn, 38)
playersBtn.TextSize = 12
local function refreshPlayers()
    playersBtn.Text = "Ignorar personajes de jugadores: " .. (scan.hidePlayers and "SÍ" or "NO")
    playersBtn.BackgroundColor3 = scan.hidePlayers and C.Green or C.Btn
end
playersBtn.Activated:Connect(function() scan.hidePlayers = not scan.hidePlayers refreshPlayers() end)
refreshPlayers()

local previewTag = makeLabel(pageScan, "VISTA PREVIA (los más repetidos)", UDim2.new(1, 0, 0, 16), nil, 11, C.Sub)
previewTag.Font = Enum.Font.GothamBold
previewTag.LayoutOrder = nextOrder()
local previewCard = card(pageScan, 130)
local previewLabel = makeLabel(previewCard, "", UDim2.new(1, -16, 1, -12), UDim2.new(0, 8, 0, 6), 11, C.Sub)
previewLabel.Font = Enum.Font.Code

local charBtn = bigButton(pageScan, "👤  Ver mi personaje y mochila (copia)", C.Accent, 42)
charBtn.TextSize = 12
local scanCopy = bigButton(pageScan, "📋  Copiar informe del scanner", C.Green, 50)
local scanSave = bigButton(pageScan, "💾  Guardar scanner en archivo", C.Btn, 40)

scanGo.Activated:Connect(function()
    if scan.busy then return end
    task.spawn(runScan, filterBox.Text, radiusBox.Text)
end)

charBtn.Activated:Connect(function()
    local text = myCharReport()
    scan.status = copyText(text) and ("📋 Personaje copiado (" .. #text .. " car.)") or "⚠ No se pudo copiar."
end)

scanCopy.Activated:Connect(function()
    if scan.report == "" then scan.status = "Primero pulsa «Escanear»." return end
    scan.status = copyText(scan.report) and ("📋 Copiado (" .. #scan.report .. " caracteres). Pégalo en el chat.")
        or "⚠ No se pudo copiar. Usa «Guardar»."
end)

scanSave.Activated:Connect(function()
    if scan.report == "" then scan.status = "Primero pulsa «Escanear»." return end
    if not writefile then scan.status = "⚠ Tu ejecutor no soporta writefile." return end
    local name = "WorkspaceScan_" .. game.PlaceId .. ".txt"
    local ok = pcall(writefile, name, scan.report)
    scan.status = ok and ("💾 Guardado como " .. name .. " (carpeta workspace).") or "⚠ No se pudo guardar."
end)

----------------------------------------------------------------
-- ACTUALIZACIÓN DE LA VISTA
----------------------------------------------------------------
task.spawn(function()
    while running do
        task.wait(0.5)
        if state.dirty then
            state.dirty = false
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
        scanStatusLabel.Text = scan.status
        previewLabel.Text = scan.preview
    end
end)

----------------------------------------------------------------
-- VENTANA
----------------------------------------------------------------
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
    state.capturing = false
    for _, c in ipairs(connections) do c:Disconnect() end
    gui:Destroy()
end)

layoutFrame()
selectTab(1)
statusLabel.Text = hookOK and "Listo. Activa la captura y marca cada acción." or "⚠ Tu ejecutor no soporta hookmetamethod (el Scanner sí funciona)."
