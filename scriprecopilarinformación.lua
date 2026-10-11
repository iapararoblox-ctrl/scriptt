--[[
    REMOTE CAPTURE + SCANNER + INFO ÚTIL v3 para Delta (Mobile/PC)

    📡 CAPTURA
    - Captura RemoteEvent / RemoteFunction que TÚ disparas (argumentos, respuesta, script que llamó)
    - Botón "Marcar acción", ocultar ruido, copiar / guardar informe

    🔍 SCANNER
    - Nombres de modelos agrupados (Pen_#_#), atributos, hijos, filtro, radio, prompts,
      mi personaje / mochila, detalle objeto por objeto

    📦 INFO ÚTIL (NUEVO, reemplaza al volcado total)
    Solo lo necesario para automatizar:
      1. REMOTES: lista completa con ruta exacta (+ marca ✔ si ya los capturaste)
      2. CAPTURAS: lo que hiciste con 📡
      3. INTERACTUABLES E IDs: ProximityPrompts, ClickDetectors, TouchInterest, NPCs/Humanoids,
         objetos con atributos y tags (CollectionService)
      4. INTERFAZ: botones de PlayerGui con ruta, texto y si están visibles
      5. MIS DATOS: posición, atributos, leaderstats, valores y tools
      6. JERARQUÍA: contenedores de Workspace y ReplicatedStorage (agrupados, sin partes sueltas)
    Cada sección se puede activar/desactivar. El informe sale por partes para copiar.

    📝 NOMBRE DE ARCHIVO
    - Escribe el nombre arriba (ej: mapa_zombies). Se añade .txt si no pones extensión.
    - "No sobrescribir": si existe, guarda como nombre_2.txt, nombre_3.txt…
    - Carpetas de destino: ver SAVE_DIRS
]]

----------------------------------------------------------------
-- CONFIGURACIÓN
----------------------------------------------------------------
local GUI_NAME   = "RemoteCaptureGUI"
local MAX_CALLS  = 150
local MAX_REPORT = 30000
local MAX_SCAN   = 40000
local MAX_GROUPS = 250
local MAX_INFO   = 300000   -- tamaño máximo del informe útil
local PART_SIZE  = 15000    -- caracteres por parte al copiar (el portapapeles móvil no aguanta más)
-- Carpetas donde intentar guardar (en orden). La primera que funcione se usa.
local SAVE_DIRS = {
    "/storage/emulated/0/Delta/Informaciónrecopilada",
    "../Informaciónrecopilada",
    "Informaciónrecopilada",
}
local NOISE = { "^Get", "^Report", "^Record", "^Note", "Hover", "^IsWild" }

local C = {
    Bg = Color3.fromRGB(16, 18, 26), Card = Color3.fromRGB(28, 31, 43), Btn = Color3.fromRGB(44, 48, 64),
    Accent = Color3.fromRGB(90, 130, 255), Green = Color3.fromRGB(46, 160, 105),
    Red = Color3.fromRGB(200, 70, 80), Amber = Color3.fromRGB(214, 150, 40),
    Text = Color3.fromRGB(235, 238, 245), Sub = Color3.fromRGB(150, 158, 178),
}

-- Opciones (se cambian con botones en la interfaz)
local opts = {
    scrub = true,   -- ocultar nombres de usuario
    safe = true,    -- no sobrescribir archivos
    labels = false, -- incluir textos (labels) de la interfaz
    sec = { remotes = true, caps = true, inter = true, gui = true, mine = true, hier = true },
}

----------------------------------------------------------------
-- SERVICIOS
----------------------------------------------------------------
local Players            = game:GetService("Players")
local UserInputService   = game:GetService("UserInputService")
local CoreGui            = game:GetService("CoreGui")
local Workspace          = game:GetService("Workspace")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ReplicatedFirst    = game:GetService("ReplicatedFirst")
local MarketplaceService = game:GetService("MarketplaceService")
local CollectionService  = game:GetService("CollectionService")

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

-- Oculta nombres de usuario e IDs de todos los jugadores del servidor
local function scrub(s)
    if not opts.scrub then return s end
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

local function tryGet(f)
    local ok, v = pcall(f)
    if ok then return v end
    return nil
end

----------------------------------------------------------------
-- ESTADO + CAPTURA DE REMOTES
----------------------------------------------------------------
local running = true
local connections = {}
local function track(c) table.insert(connections, c) return c end

local state = { capturing = false, hide = true, seq = {}, map = {}, seen = {}, total = 0, calls = 0, marker = 0, dirty = true }
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
                        local callerScript
                        if getcallingscript then
                            local okc, cs = pcall(getcallingscript)
                            if okc then callerScript = cs end
                        end
                        if method == "InvokeServer" then
                            local res = table.pack(oldNamecall(self, ...))
                            task.defer(st.record, self, method, args, res, callerScript)
                            return table.unpack(res, 1, res.n)
                        end
                        task.defer(st.record, self, method, args, nil, callerScript)
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

state.record = function(remote, method, args, res, caller)
    if not running then return end
    local full = path(remote)
    state.seen[full] = (state.seen[full] or 0) + 1 -- para marcar ✔ en la lista de remotes
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
        e = { kind = "call", path = short, method = method, args = argStr, res = resStr, count = 1,
              caller = caller and path(caller) or nil }
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
            if e.caller then line = line .. "  de: " .. e.caller end
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
    n = n:gsub("^(HeldPet_).+(_%a+)$", "%1<usuario>%2")
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

        local groups, prompts = {}, {}
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
                if filter ~= "" then
                    local p = relPath(d)
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

        local list = {}
        for _, g in pairs(groups) do list[#list + 1] = g end
        table.sort(list, function(a, b)
            if a.count ~= b.count then return a.count > b.count end
            return a.name < b.name
        end)

        local out = {
            "=== SCANNER ===",
            "Juego: " .. gameName() .. " | PlaceId: " .. game.PlaceId,
            "Zona: " .. zoneNames[scan.zone] .. " | Modo: " .. modeNames[scan.mode],
            "Filtro: " .. (filter ~= "" and filter or "ninguno") .. " | Radio: " .. (center and (radius .. " studs") or "todo")
                .. " | Jugadores ocultos: " .. (scan.hidePlayers and "sí" or "no"),
            "Instancias revisadas: " .. checked .. " | Grupos de nombres: " .. #list,
            "",
        }

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

-- Personaje, mochila y atributos
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
    return table.concat(out, "\n")
end

-- Detalle objeto por objeto (Pet_<uuid>, HeldPet_<usuario>_left, etc.)
local DETAIL_MAX = 60

local function valueOf(inst)
    local ok, v = pcall(function() return inst.Value end)
    return ok and ser(v, 0) or "?"
end

local function describe(d, indent, depth, out)
    local pad = string.rep("  ", indent)
    local line = pad .. d.ClassName .. ": " .. d.Name
    if d:IsA("ValueBase") then line = line .. " = " .. valueOf(d) end
    local okA, attrs = pcall(d.GetAttributes, d)
    if okA and attrs and next(attrs) then line = line .. "  attrs=" .. ser(attrs, 0) end
    out[#out + 1] = line
    if depth <= 0 then return end

    local n, counts = 0, {}
    for _, c in ipairs(d:GetChildren()) do
        if c:IsA("ValueBase") or c:IsA("Folder") or c:IsA("Model") or c:IsA("Configuration")
            or c:IsA("Tool") or c:IsA("ProximityPrompt") then
            n += 1
            if n <= 25 then describe(c, indent + 1, depth - 1, out) end
        else
            counts[c.ClassName] = (counts[c.ClassName] or 0) + 1
        end
    end
    if n > 25 then out[#out + 1] = pad .. "  … (" .. (n - 25) .. " más)" end
    local parts = {}
    for k, v in pairs(counts) do parts[#parts + 1] = k .. " x" .. v end
    table.sort(parts)
    if #parts > 0 then out[#out + 1] = pad .. "  (+ " .. table.concat(parts, ", ") .. ")" end
end

local function detailReport(filterText)
    local filter = (filterText or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local needles = filter ~= "" and { filter } or { "pet_", "heldpet_" }
    local out = {
        "=== DETALLE DE OBJETOS ===",
        "Juego: " .. gameName() .. " | PlaceId: " .. game.PlaceId,
        "Buscando nombres que contengan: " .. table.concat(needles, " / "),
        "",
    }

    local described, found, n = {}, 0, 0
    for _, d in ipairs(Workspace:GetDescendants()) do
        n += 1
        if n % 400 == 0 then task.wait() end
        if d:IsA("Model") or d:IsA("Folder") or d:IsA("Tool") then
            local nm = d.Name:lower()
            local match = false
            for _, p in ipairs(needles) do
                if nm:find(p, 1, true) then match = true break end
            end
            if match then
                local nested, a = false, d.Parent
                while a and a ~= Workspace do
                    if described[a] then nested = true break end
                    a = a.Parent
                end
                if not nested then
                    described[d] = true
                    found += 1
                    if found <= DETAIL_MAX then
                        local mine = false
                        if d:GetAttribute("OwnerUserId") == player.UserId then mine = true end
                        if d.Name:find(player.Name, 1, true) then mine = true end
                        out[#out + 1] = "### " .. relPath(d) .. (mine and "   (MÍO)" or "")
                        local pos = instPos(d)
                        if pos then
                            out[#out + 1] = string.format("  pos: %.1f, %.1f, %.1f", pos.X, pos.Y, pos.Z)
                        end
                        describe(d, 1, 2, out)
                        out[#out + 1] = ""
                    end
                end
            end
        end
    end
    out[#out + 1] = "Coincidencias: " .. found .. (found > DETAIL_MAX and (" (mostrando " .. DETAIL_MAX .. "; usa un filtro más concreto)") or "")
    local text = scrub(table.concat(out, "\n"))
    if #text > MAX_SCAN then text = text:sub(1, MAX_SCAN) .. "\n… (recortado)" end
    return text, found
end

----------------------------------------------------------------
-- INFO ÚTIL (pestaña 📦): solo lo necesario para automatizar
----------------------------------------------------------------
local info = { busy = false, text = "", parts = {}, partIndex = 1, status = "Pulsa «Recopilar»." }

local function trimPath(p) return #p > 170 and ("…" .. p:sub(-169)) or p end

-- Agrupa por clave. Devuelve nil si se alcanzó el límite de grupos.
local function grp(map, order, key, cap, make)
    local g = map[key]
    if g then g.count += 1 return g end
    if #order >= cap then return nil end
    g = make()
    g.count = 1
    map[key] = g
    order[#order + 1] = key
    return g
end

local function attrString(a, max)
    local t = {}
    for k, v in pairs(a) do t[#t + 1] = k .. "=" .. ser(v, 0) end
    table.sort(t)
    local s = table.concat(t, ", ")
    return #s > (max or 200) and (s:sub(1, max or 200) .. "…") or s
end

-- 1) REMOTES: lista completa con ruta exacta
local function collectRemotes()
    local found, n = {}, 0
    for _, root in ipairs({ ReplicatedStorage, ReplicatedFirst }) do
        for _, d in ipairs(root:GetDescendants()) do
            n += 1
            if n % 500 == 0 then task.wait() info.status = "Buscando remotes… " .. n end
            local cn = d.ClassName
            if cn == "RemoteEvent" or cn == "RemoteFunction" or cn == "UnreliableRemoteEvent" then
                found[#found + 1] = { path = path(d), class = cn }
            end
        end
    end
    return found
end

local function splitPath(p)
    local t = {}
    for seg in p:gmatch("[^%.]+") do t[#t + 1] = seg end
    return t
end

local function secRemotes(out)
    local list = collectRemotes()
    table.sort(list, function(a, b) return a.path < b.path end)
    out[#out + 1] = "## REMOTES (" .. #list .. ")  — RF = :InvokeServer(...)   RE = :FireServer(...)   ✔ = ya capturado"
    if #list == 0 then out[#out + 1] = "(ninguno)" return end

    -- Prefijo común escrito una sola vez
    local first = splitPath(list[1].path)
    local n = #first - 1
    for i = 2, #list do
        local s = splitPath(list[i].path)
        local m = 0
        while m < n and m < #s - 1 and s[m + 1] == first[m + 1] do m += 1 end
        n = m
    end
    local prefix = n > 0 and (table.concat(first, ".", 1, n) .. ".") or ""
    if prefix ~= "" then out[#out + 1] = "Prefijo común: " .. prefix end

    for _, r in ipairs(list) do
        local rel = prefix ~= "" and r.path:sub(#prefix + 1) or r.path
        local kind = r.class == "RemoteFunction" and "RF" or (r.class == "RemoteEvent" and "RE" or "URE")
        local seen = state.seen[r.path]
        out[#out + 1] = rel .. "  [" .. kind .. "]" .. (seen and ("  ✔x" .. seen) or "")
    end
end

-- 3) INTERACTUABLES E IDs: un solo recorrido por Workspace (sin entrar en personajes)
local function scanWorld(skipSet)
    local R = { prompts = {}, po = {}, clicks = {}, co = {}, touch = {}, to = {}, npcs = {}, no = {}, attrs = {}, ao = {} }
    local stack, n = { Workspace }, 0
    local cam = Workspace.CurrentCamera
    while #stack > 0 do
        local inst = table.remove(stack)
        for _, c in ipairs(inst:GetChildren()) do
            if skipSet[c] or c == cam or c.ClassName == "Terrain" then continue end
            n += 1
            if n % 400 == 0 then task.wait() info.status = "Workspace… " .. n .. " objetos" end
            stack[#stack + 1] = c

            local cn, owner = c.ClassName, c.Parent
            local ownerName = normName(owner and owner.Name or "?")
            if cn == "ProximityPrompt" then
                local key = tostring(c.ActionText) .. "|" .. tostring(c.ObjectText) .. "|" .. ownerName
                grp(R.prompts, R.po, key, 150, function() return { p = c } end)
            elseif cn == "ClickDetector" then
                grp(R.clicks, R.co, ownerName, 60, function() return { p = c } end)
            elseif cn == "TouchTransmitter" then
                grp(R.touch, R.to, ownerName, 60, function() return { p = c } end)
            elseif cn == "Humanoid" then
                grp(R.npcs, R.no, ownerName, 100, function() return { p = c, model = owner } end)
            end

            if c:IsA("Model") or c:IsA("Folder") or c:IsA("Tool") or c:IsA("Configuration") or c:IsA("BasePart") then
                local okA, a = pcall(c.GetAttributes, c)
                if okA and a and next(a) then
                    grp(R.attrs, R.ao, normName(c.Name) .. "|" .. cn, 120, function() return { p = c, a = a } end)
                end
            end
        end
    end
    return R
end

local function secInter(out, R)
    out[#out + 1] = "## PROXIMITYPROMPTS (" .. #R.po .. " tipos)  — fireproximityprompt(<ruta>)"
    for _, key in ipairs(R.po) do
        local g = R.prompts[key]
        local p = g.p
        out[#out + 1] = string.format('x%d  Action="%s" Object="%s" Hold=%.1f Dist=%.0f Enabled=%s',
            g.count, p.ActionText, p.ObjectText, p.HoldDuration, p.MaxActivationDistance, tostring(p.Enabled))
        out[#out + 1] = "    ej: " .. trimPath(path(p))
    end
    if #R.po == 0 then out[#out + 1] = "(ninguno)" end
    out[#out + 1] = ""

    out[#out + 1] = "## CLICKDETECTORS (" .. #R.co .. " tipos)  — fireclickdetector(<ruta>)"
    for _, key in ipairs(R.co) do
        local g = R.clicks[key]
        out[#out + 1] = "x" .. g.count .. "  en " .. key .. "  ej: " .. trimPath(path(g.p))
    end
    if #R.co == 0 then out[#out + 1] = "(ninguno)" end
    out[#out + 1] = ""

    out[#out + 1] = "## OBJETOS CON TOUCHINTEREST (" .. #R.to .. " tipos: coleccionables, zonas, puertas)"
    for _, key in ipairs(R.to) do
        local g = R.touch[key]
        out[#out + 1] = "x" .. g.count .. "  " .. key .. "  ej: " .. trimPath(path(g.p.Parent or g.p))
    end
    if #R.to == 0 then out[#out + 1] = "(ninguno)" end
    out[#out + 1] = ""

    out[#out + 1] = "## NPCs / ENEMIGOS (Humanoid) (" .. #R.no .. " tipos)"
    for _, key in ipairs(R.no) do
        local g = R.npcs[key]
        local h = g.p
        local line = string.format("x%d  %s  Health=%s/%s", g.count, key,
            tostring(tryGet(function() return h.Health end)), tostring(tryGet(function() return h.MaxHealth end)))
        local okA, a = pcall(function() return g.model and g.model:GetAttributes() end)
        if okA and a and next(a) then line = line .. "  attrs={" .. attrString(a) .. "}" end
        out[#out + 1] = line
        out[#out + 1] = "    ej: " .. trimPath(path(g.model or h))
    end
    if #R.no == 0 then out[#out + 1] = "(ninguno)" end
    out[#out + 1] = ""

    out[#out + 1] = "## OBJETOS CON ATRIBUTOS (IDs y datos) (" .. #R.ao .. " tipos)"
    for _, key in ipairs(R.ao) do
        local g = R.attrs[key]
        out[#out + 1] = "x" .. g.count .. "  " .. key:gsub("|", " [") .. "]  {" .. attrString(g.a) .. "}"
        out[#out + 1] = "    ej: " .. trimPath(path(g.p))
    end
    if #R.ao == 0 then out[#out + 1] = "(ninguno)" end
    out[#out + 1] = ""

    -- Tags de CollectionService
    local okT, tags = pcall(function() return CollectionService:GetAllTags() end)
    out[#out + 1] = "## TAGS (CollectionService)"
    local shown = 0
    if okT and type(tags) == "table" then
        table.sort(tags)
        for _, tag in ipairs(tags) do
            local okG, tagged = pcall(function() return CollectionService:GetTagged(tag) end)
            if okG and #tagged > 0 then
                shown += 1
                if shown > 80 then out[#out + 1] = "… (más)" break end
                out[#out + 1] = tag .. " x" .. #tagged .. "  ej: " .. trimPath(path(tagged[1]))
            end
        end
    end
    if shown == 0 then out[#out + 1] = "(ninguno)" end
end

-- 4) INTERFAZ: botones (y opcionalmente textos) de PlayerGui
local function secGui(out)
    local pg = player:FindFirstChild("PlayerGui")
    out[#out + 1] = "## INTERFAZ (PlayerGui) — rutas relativas a PlayerGui"
    if not pg then out[#out + 1] = "(sin PlayerGui)" return end

    local prefix = "^Players%.[^%.]+%.PlayerGui%."
    local btnGroups, border = {}, {}
    local lblGroups, lorder = {}, {}
    local screens, n = {}, 0

    for _, sg in ipairs(pg:GetChildren()) do
        if sg:IsA("ScreenGui") and sg.Name ~= GUI_NAME then
            local sInfo = { name = sg.Name, enabled = sg.Enabled, buttons = 0 }
            screens[#screens + 1] = sInfo
            local stack = { { sg, sg.Enabled } }
            while #stack > 0 do
                local item = table.remove(stack)
                for _, c in ipairs(item[1]:GetChildren()) do
                    n += 1
                    if n % 400 == 0 then task.wait() info.status = "Interfaz… " .. n end
                    local vis = item[2]
                    if c:IsA("GuiObject") then vis = vis and c.Visible end
                    stack[#stack + 1] = { c, vis }

                    if c:IsA("TextButton") or c:IsA("ImageButton") then
                        sInfo.buttons += 1
                        local rel = path(c):gsub(prefix, "")
                        local text = c:IsA("TextButton") and c.Text or ""
                        local key = normName(rel) .. "|" .. normName(text) .. "|" .. tostring(vis)
                        grp(btnGroups, border, key, 250, function()
                            return { rel = rel, text = text, vis = vis, class = c.ClassName }
                        end)
                    elseif opts.labels and c:IsA("TextLabel") and c.Text ~= "" and #c.Text <= 50 then
                        local rel = path(c):gsub(prefix, "")
                        grp(lblGroups, lorder, normName(rel), 150, function() return { rel = rel, text = c.Text } end)
                    end
                end
            end
        end
    end

    out[#out + 1] = "ScreenGuis:"
    for _, s in ipairs(screens) do
        out[#out + 1] = "  " .. s.name .. " | Enabled=" .. tostring(s.enabled) .. " | " .. s.buttons .. " botones"
    end
    out[#out + 1] = ""
    out[#out + 1] = "BOTONES (visible/oculto | xN | ruta | texto | clase):"
    for _, key in ipairs(border) do
        local g = btnGroups[key]
        out[#out + 1] = string.format("  [%s] x%d  %s  \"%s\"  (%s)", g.vis and "visible" or "oculto",
            g.count, g.rel, (g.text:gsub("\n", " ")):sub(1, 40), g.class)
    end
    if #border == 0 then out[#out + 1] = "  (ninguno)" end

    if opts.labels then
        out[#out + 1] = ""
        out[#out + 1] = "TEXTOS (ruta = texto):"
        for _, key in ipairs(lorder) do
            local g = lblGroups[key]
            out[#out + 1] = "  " .. (g.count > 1 and ("x" .. g.count .. " ") or "") .. g.rel
                .. " = \"" .. (g.text:gsub("\n", " ")) .. "\""
        end
        if #lorder == 0 then out[#out + 1] = "  (ninguno)" end
    end
end

-- 5) MIS DATOS (corto)
local function secMine(out)
    out[#out + 1] = "## MIS DATOS"
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        out[#out + 1] = string.format("Posición: %.0f, %.0f, %.0f", hrp.Position.X, hrp.Position.Y, hrp.Position.Z)
    end
    local okP, pattrs = pcall(player.GetAttributes, player)
    if okP and pattrs and next(pattrs) then out[#out + 1] = "Atributos del jugador: {" .. attrString(pattrs, 400) .. "}" end

    -- Valores (leaderstats, Data, etc.) sin entrar en PlayerGui / Backpack
    local values, stack = {}, { player }
    while #stack > 0 and #values < 40 do
        local inst = table.remove(stack)
        for _, c in ipairs(inst:GetChildren()) do
            if c.Name ~= "PlayerGui" and c.Name ~= "Backpack" and c.Name ~= "PlayerScripts" then
                if c:IsA("ValueBase") then
                    if #values < 40 then
                        values[#values + 1] = (path(c):gsub("^Players%.[^%.]+%.", "")) .. " = " .. valueOf(c)
                    end
                elseif c:IsA("Folder") or c:IsA("Configuration") then
                    stack[#stack + 1] = c
                end
            end
        end
    end
    if #values > 0 then
        out[#out + 1] = "Valores:"
        for _, v in ipairs(values) do out[#out + 1] = "  " .. v end
    end

    local tools = {}
    local bp = player:FindFirstChildOfClass("Backpack")
    for _, container in ipairs({ bp, char }) do
        if container then
            for _, t in ipairs(container:GetChildren()) do
                if t:IsA("Tool") then
                    local okA, a = pcall(t.GetAttributes, t)
                    tools[#tools + 1] = t.Name .. ((okA and a and next(a)) and ("  {" .. attrString(a, 150) .. "}") or "")
                end
            end
        end
    end
    out[#out + 1] = "Tools: " .. (#tools > 0 and "" or "(ninguna)")
    for _, t in ipairs(tools) do out[#out + 1] = "  " .. t end
end

-- 6) JERARQUÍA: contenedores agrupados (sin partes sueltas)
local CONTAINER = {
    Folder = true, Model = true, Configuration = true, Tool = true, ModuleScript = true, Script = true,
    LocalScript = true, RemoteEvent = true, RemoteFunction = true, UnreliableRemoteEvent = true,
    BindableEvent = true, BindableFunction = true,
}
local OMIT = { Packages = true, _Index = true }

local function hierarchy(root, maxDepth, cap, skipSet, title, out)
    local st = { lines = 0, n = 0 }
    local cam = Workspace.CurrentCamera

    local function node(inst, depth)
        local order, groups, other = {}, {}, {}
        for _, c in ipairs(inst:GetChildren()) do
            if skipSet[c] or c == cam or c.ClassName == "Terrain" then continue end
            if CONTAINER[c.ClassName] or c:IsA("ValueBase") then
                local key = normName(c.Name) .. "|" .. c.ClassName
                local g = groups[key]
                if g then g.count += 1 else g = { count = 1, first = c } groups[key] = g order[#order + 1] = g end
            else
                other[c.ClassName] = (other[c.ClassName] or 0) + 1
            end
        end
        local pad = string.rep("  ", depth)
        for _, g in ipairs(order) do
            if st.lines >= cap then return end
            st.n += 1
            if st.n % 300 == 0 then task.wait() info.status = "Jerarquía… " .. st.lines .. " líneas" end
            local c = g.first
            local label = c.ClassName .. ' "' .. (g.count > 1 and normName(c.Name) or c.Name) .. '"'
            if g.count > 1 then label = label .. " x" .. g.count .. "  (ej: " .. c.Name .. ")" end
            if c:IsA("ValueBase") then label = label .. " = " .. valueOf(c) end
            if OMIT[c.Name] then label = label .. "  (omitido)" end
            out[#out + 1] = pad .. label
            st.lines += 1
            if not OMIT[c.Name] and depth < maxDepth and #c:GetChildren() > 0 then node(c, depth + 1) end
        end
        if next(other) then
            local parts = {}
            for k, v in pairs(other) do parts[#parts + 1] = k .. " x" .. v end
            table.sort(parts)
            out[#out + 1] = pad .. "(+ " .. table.concat(parts, ", ") .. ")"
            st.lines += 1
        end
    end

    out[#out + 1] = "## " .. title
    node(root, 1)
    if st.lines >= cap then out[#out + 1] = "… (límite de " .. cap .. " líneas)" end
end

-- Construye el informe completo
local function buildInfo()
    local out = {}
    local sec = opts.sec

    local skipSet = {}
    if scan.hidePlayers then
        for _, pl in ipairs(Players:GetPlayers()) do
            if pl.Character then skipSet[pl.Character] = true end
        end
    end

    local streaming = tryGet(function() return Workspace.StreamingEnabled end)
    local funcs = {}
    for _, f in ipairs({ "hookmetamethod", "fireproximityprompt", "fireclickdetector", "firetouchinterest",
        "firesignal", "getconnections", "writefile", "setclipboard" }) do
        funcs[#funcs + 1] = f .. "=" .. (env[f] ~= nil and "sí" or "no")
    end
    out[#out + 1] = "=== INFO ÚTIL ==="
    out[#out + 1] = "Juego: " .. gameName() .. " | PlaceId: " .. game.PlaceId .. " | " .. os.date("%Y-%m-%d %H:%M")
    out[#out + 1] = "StreamingEnabled: " .. tostring(streaming)
        .. (streaming and "  (⚠ solo ves lo cercano a tu personaje; repite en otra zona si falta algo)" or "")
    out[#out + 1] = "Funciones del ejecutor: " .. table.concat(funcs, ", ")
    out[#out + 1] = ""

    local function run(name, fn)
        info.status = name .. "…"
        local ok, err = pcall(fn)
        if not ok then out[#out + 1] = "(error en «" .. name .. "»: " .. tostring(err):sub(1, 80) .. ")" end
        out[#out + 1] = ""
    end

    if sec.remotes then run("Remotes", function() secRemotes(out) end) end
    if sec.caps and state.total > 0 then
        run("Capturas", function() out[#out + 1] = buildReport() end)
    end
    if sec.inter then
        run("Interactuables e IDs", function()
            local R = scanWorld(skipSet)
            secInter(out, R)
        end)
    end
    if sec.gui then run("Interfaz", function() secGui(out) end) end
    if sec.mine then run("Mis datos", function() secMine(out) end) end
    if sec.hier then
        run("Jerarquía de Workspace", function()
            hierarchy(Workspace, 3, 250, skipSet, "JERARQUÍA DE WORKSPACE (contenedores)", out)
        end)
        run("Jerarquía de ReplicatedStorage", function()
            hierarchy(ReplicatedStorage, 6, 400, {}, "JERARQUÍA DE REPLICATEDSTORAGE", out)
        end)
    end

    local text = scrub(table.concat(out, "\n"))
    if #text > MAX_INFO then text = text:sub(1, MAX_INFO) .. "\n… (recortado por tamaño)" end
    return text
end

local function splitParts(text)
    local parts, cur, size = {}, {}, 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
        if size + #line + 1 > PART_SIZE and #cur > 0 then
            parts[#parts + 1] = table.concat(cur, "\n")
            cur, size = {}, 0
        end
        cur[#cur + 1] = line
        size += #line + 1
    end
    if #cur > 0 then parts[#parts + 1] = table.concat(cur, "\n") end
    return parts
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

makeLabel(header, "📡 Capture + Scanner + Info v3", UDim2.new(1, -90, 0, 24), UDim2.new(0, 14, 0, 4), 16).Font = Enum.Font.GothamBold
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
tabLayout.Padding = UDim.new(0, 5)
tabLayout.Parent = tabBar

-- Caja de nombre de archivo (compartida por las 3 pestañas)
local nameRow = Instance.new("Frame")
nameRow.Size = UDim2.new(1, 0, 0, 34)
nameRow.Position = UDim2.new(0, 0, 0, 40)
nameRow.BackgroundTransparency = 1
nameRow.Parent = body
local nameBox = Instance.new("TextBox")
nameBox.Size = UDim2.new(1, 0, 1, 0)
nameBox.BackgroundColor3 = C.Card
nameBox.PlaceholderText = "📝 Nombre del archivo (vacío = automático)"
nameBox.PlaceholderColor3 = C.Sub
nameBox.Text = ""
nameBox.TextColor3 = C.Text
nameBox.Font = Enum.Font.Gotham
nameBox.TextSize = 13
nameBox.ClearTextOnFocus = false
nameBox.Parent = nameRow
corner(nameBox, 8)

local content = Instance.new("Frame")
content.Size = UDim2.new(1, 0, 1, -82)
content.Position = UDim2.new(0, 0, 0, 78)
content.BackgroundTransparency = 1
content.Parent = body

-- Guardado con nombre personalizado
local function cleanFileName(raw, default)
    local n = tostring(raw or ""):gsub("^%s+", ""):gsub("%s+$", "")
    n = n:gsub("[^%w%._%-%s]", "_")
    n = n:gsub("%s+", "_")
    n = n:gsub("^%.+", "")
    if n == "" then n = default end
    if not n:find("%.%w+$") then n = n .. ".txt" end
    return n
end

local function ensureFolder(dir)
    if isfolder then
        local okF, ex = pcall(isfolder, dir)
        if okF and ex then return true end
    end
    if makefolder then
        pcall(makefolder, dir)
        if isfolder then
            local okF, ex = pcall(isfolder, dir)
            return okF and ex == true
        end
        return true
    end
    return false
end

local function uniqueName(dir, name)
    if not (opts.safe and isfile) then return name end
    local base, ext = name:match("^(.*)(%.%w+)$")
    if not base then base, ext = name, "" end
    local cand, i = name, 1
    while i < 1000 do
        local okF, exists = pcall(isfile, dir .. "/" .. cand)
        if not (okF and exists) then break end
        i += 1
        cand = base .. "_" .. i .. ext
    end
    return cand
end

-- Prueba cada carpeta de SAVE_DIRS. Devuelve ok, rutaFinal | mensajeError
local function saveFile(text, default)
    if not writefile then return false, "tu ejecutor no soporta writefile" end
    local name = cleanFileName(nameBox.Text, default)
    local lastErr = "ninguna carpeta aceptó el archivo"
    for _, dir in ipairs(SAVE_DIRS) do
        ensureFolder(dir)
        local target = dir .. "/" .. uniqueName(dir, name)
        local ok, err = pcall(writefile, target, text)
        if ok then
            local verified = true
            if isfile then
                local okV, ex = pcall(isfile, target)
                verified = okV and ex == true
            end
            if verified then return true, target end
            lastErr = "no se pudo verificar: " .. dir
        else
            lastErr = tostring(err):sub(1, 60)
        end
    end
    return false, lastErr
end

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

local pageCap, pageScan, pageAll = newPage(), newPage(), newPage()
local tabs = {}
local function selectTab(i)
    for idx, t in ipairs(tabs) do
        t.page.Visible = (idx == i)
        t.btn.BackgroundColor3 = (idx == i) and C.Accent or C.Card
        t.btn.TextColor3 = (idx == i) and Color3.fromRGB(255, 255, 255) or C.Sub
    end
end
local function addTab(text, page)
    local b = makeButton(tabBar, text, UDim2.new(1 / 3, -4, 1, 0), nil, C.Card)
    b.TextSize = 12
    table.insert(tabs, { btn = b, page = page })
    local idx = #tabs
    b.Activated:Connect(function() selectTab(idx) end)
end
addTab("📡 Captura", pageCap)
addTab("🔍 Scanner", pageScan)
addTab("📦 Info útil", pageAll)

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

-- Botón SÍ/NO ligado a una opción (se mantiene sincronizado si aparece en varias pestañas)
local toggleRefresh = {}
local function makeToggle(parent, label, tbl, key, h)
    local b = bigButton(parent, "", C.Btn, h or 36)
    b.TextSize = 12
    local function refresh()
        b.Text = label .. ": " .. (tbl[key] and "SÍ" or "NO")
        b.BackgroundColor3 = tbl[key] and C.Green or C.Btn
    end
    toggleRefresh[key] = toggleRefresh[key] or {}
    table.insert(toggleRefresh[key], refresh)
    b.Activated:Connect(function()
        tbl[key] = not tbl[key]
        for _, f in ipairs(toggleRefresh[key]) do f() end
    end)
    refresh()
    return b
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
local saveBtn  = bigButton(pageCap, "💾  Guardar en archivo (usa el nombre de arriba)", C.Btn, 40)
saveBtn.TextSize = 12
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
    if state.total == 0 then statusLabel.Text = "Aún no hay nada capturado." return end
    local ok, res = saveFile(buildReport(), "RemoteCapture_" .. game.PlaceId .. ".txt")
    statusLabel.Text = ok and ("💾 Guardado como " .. res .. ".") or ("⚠ No se pudo guardar: " .. res)
end)

clearBtn.Activated:Connect(function()
    state.seq, state.map, state.seen, state.total, state.calls, state.marker = {}, {}, {}, 0, 0, 0
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

makeToggle(pageScan, "Ignorar personajes de jugadores", scan, "hidePlayers", 38)

local previewTag = makeLabel(pageScan, "VISTA PREVIA (los más repetidos)", UDim2.new(1, 0, 0, 16), nil, 11, C.Sub)
previewTag.Font = Enum.Font.GothamBold
previewTag.LayoutOrder = nextOrder()
local previewCard = card(pageScan, 130)
local previewLabel = makeLabel(previewCard, "", UDim2.new(1, -16, 1, -12), UDim2.new(0, 8, 0, 6), 11, C.Sub)
previewLabel.Font = Enum.Font.Code

local charBtn = bigButton(pageScan, "👤  Ver mi personaje y mochila (copia)", C.Accent, 42)
charBtn.TextSize = 12
local detailBtn = bigButton(pageScan, "🐾  Detalle objeto por objeto (filtro vacío = Pet_ y HeldPet_)", C.Accent, 46)
detailBtn.TextSize = 12
detailBtn.TextWrapped = true
detailBtn.Activated:Connect(function()
    if scan.busy then return end
    scan.busy = true
    scan.status = "Leyendo detalle…"
    task.spawn(function()
        local ok, text, found = pcall(detailReport, filterBox.Text)
        scan.busy = false
        if not ok then scan.status = "⚠ Error: " .. tostring(text):sub(1, 70) return end
        scan.report = text
        scan.preview = "Detalle: " .. found .. " objetos encontrados"
        scan.status = (copyText(text) and "📋 Copiado" or "⚠ No se pudo copiar (usa Guardar)")
            .. " — " .. found .. " objetos, " .. #text .. " car."
    end)
end)
local scanCopy = bigButton(pageScan, "📋  Copiar informe del scanner", C.Green, 50)
local scanSave = bigButton(pageScan, "💾  Guardar scanner (usa el nombre de arriba)", C.Btn, 40)
scanSave.TextSize = 12

scanGo.Activated:Connect(function()
    if scan.busy then return end
    task.spawn(runScan, filterBox.Text, radiusBox.Text)
end)

charBtn.Activated:Connect(function()
    local text = scrub(myCharReport())
    scan.status = copyText(text) and ("📋 Personaje copiado (" .. #text .. " car.)") or "⚠ No se pudo copiar."
end)

scanCopy.Activated:Connect(function()
    if scan.report == "" then scan.status = "Primero pulsa «Escanear»." return end
    scan.status = copyText(scan.report) and ("📋 Copiado (" .. #scan.report .. " caracteres). Pégalo en el chat.")
        or "⚠ No se pudo copiar. Usa «Guardar»."
end)

scanSave.Activated:Connect(function()
    if scan.report == "" then scan.status = "Primero pulsa «Escanear»." return end
    local ok, res = saveFile(scan.report, "WorkspaceScan_" .. game.PlaceId .. ".txt")
    scan.status = ok and ("💾 Guardado como " .. res .. ".") or ("⚠ No se pudo guardar: " .. res)
end)

----------------------------------------------------------------
-- PESTAÑA 3: INFO ÚTIL
----------------------------------------------------------------
local infoStatusCard = card(pageAll, 64)
local infoStatusLabel = makeLabel(infoStatusCard, "", UDim2.new(1, -20, 1, -12), UDim2.new(0, 10, 0, 6), 13)

local infoGo = bigButton(pageAll, "📦  RECOPILAR INFO ÚTIL (y guardar archivo)", C.Green, 56)

local infoCard = card(pageAll, 84)
makeLabel(infoCard,
    "Solo lo necesario para automatizar: remotes con ruta exacta, prompts, NPCs, atributos e IDs, "
    .. "botones de la interfaz y la jerarquía de contenedores. Los repetidos se agrupan (Pen_#_# x40).",
    UDim2.new(1, -16, 1, -12), UDim2.new(0, 8, 0, 6), 11, C.Sub)

local secTag = makeLabel(pageAll, "SECCIONES A INCLUIR", UDim2.new(1, 0, 0, 16), nil, 11, C.Sub)
secTag.Font = Enum.Font.GothamBold
secTag.LayoutOrder = nextOrder()
makeToggle(pageAll, "1 Remotes (rutas exactas)", opts.sec, "remotes", 34)
makeToggle(pageAll, "2 Capturas de 📡", opts.sec, "caps", 34)
makeToggle(pageAll, "3 Interactuables e IDs", opts.sec, "inter", 34)
makeToggle(pageAll, "4 Interfaz (PlayerGui)", opts.sec, "gui", 34)
makeToggle(pageAll, "5 Mis datos", opts.sec, "mine", 34)
makeToggle(pageAll, "6 Jerarquía (Workspace y RS)", opts.sec, "hier", 34)

local optTag = makeLabel(pageAll, "OPCIONES", UDim2.new(1, 0, 0, 16), nil, 11, C.Sub)
optTag.Font = Enum.Font.GothamBold
optTag.LayoutOrder = nextOrder()
makeToggle(pageAll, "Incluir textos de la interfaz", opts, "labels", 34)
makeToggle(pageAll, "Ocultar nombres de usuario", opts, "scrub", 34)
makeToggle(pageAll, "Ignorar personajes de jugadores", scan, "hidePlayers", 34)
makeToggle(pageAll, "No sobrescribir (añade _2, _3…)", opts, "safe", 34)

local infoCopy = bigButton(pageAll, "📋  Copiar informe", C.Accent, 46)
local infoSave = bigButton(pageAll, "💾  Guardar de nuevo con el nombre de arriba", C.Btn, 40)
infoSave.TextSize = 12

infoGo.Activated:Connect(function()
    if info.busy then return end
    info.busy = true
    info.status = "Recopilando… (puede tardar, no cierres)"
    task.spawn(function()
        local ok, text = pcall(buildInfo)
        info.busy = false
        if not ok then info.status = "⚠ Error: " .. tostring(text):sub(1, 80) return end
        info.text = text
        info.parts = splitParts(text)
        info.partIndex = 1
        local saved, res = saveFile(text, "InfoUtil_" .. game.PlaceId .. ".txt")
        info.status = (saved and ("💾 Guardado como " .. res) or ("⚠ No se pudo guardar: " .. res))
            .. " — " .. #text .. " car. en " .. #info.parts .. " parte(s)."
    end)
end)

infoCopy.Activated:Connect(function()
    if #info.parts == 0 then info.status = "Primero pulsa «Recopilar»." return end
    local i = info.partIndex
    if copyText(info.parts[i]) then
        info.status = string.format("📋 Copiada la parte %d de %d. Pégala en el chat%s.", i, #info.parts,
            #info.parts > 1 and " y vuelve por la siguiente" or "")
        info.partIndex = i % #info.parts + 1
    else
        info.status = "⚠ No se pudo copiar. Usa el archivo guardado."
    end
end)

infoSave.Activated:Connect(function()
    if info.text == "" then info.status = "Primero pulsa «Recopilar»." return end
    local ok, res = saveFile(info.text, "InfoUtil_" .. game.PlaceId .. ".txt")
    info.status = ok and ("💾 Guardado como " .. res .. ".") or ("⚠ No se pudo guardar: " .. res)
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
        infoStatusLabel.Text = info.status
        infoCopy.Text = #info.parts == 0 and "📋  Copiar informe"
            or string.format("📋  Copiar parte %d/%d", info.partIndex, #info.parts)
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
statusLabel.Text = hookOK and "Listo. Activa la captura y marca cada acción." or "⚠ Tu ejecutor no soporta hookmetamethod (Scanner e Info útil sí funcionan)."
