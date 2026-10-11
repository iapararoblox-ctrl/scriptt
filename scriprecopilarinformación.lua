--[[
    REMOTE CAPTURE + SCANNER + VOLCADO TOTAL v2 para Delta (Mobile/PC)

    📡 CAPTURA
    - Captura RemoteEvent / RemoteFunction que TÚ disparas, con argumentos, respuesta y script que lo llamó
    - Botón "Marcar acción", ocultar ruido, copiar / guardar informe

    🔍 SCANNER
    - Nombres de modelos agrupados (Pen_#_#), atributos, hijos, filtro, radio, prompts,
      mi personaje / mochila, detalle objeto por objeto

    📦 TODO (NUEVO)
    - Recopila TODO en un solo informe:
        · info del juego y del ejecutor (qué funciones soporta)
        · mi personaje, mochila, atributos, leaderstats
        · lista completa de Remotes / Bindables (aunque no los hayas disparado)
        · todos los scripts y módulos, ProximityPrompts, ClickDetectors, NPCs (Humanoids), Tools
        · clases más comunes, instancias nil, módulos cargados
        · ÁRBOL COMPLETO de Workspace, ReplicatedStorage, ReplicatedFirst, Lighting,
          StarterGui, StarterPack, StarterPlayer, Teams, SoundService, Chat y tu Player
        · + lo capturado en 📡 y el último informe de 🔍
    - Lo más útil va al principio (resumen), el árbol al final

    📝 NOMBRE DE ARCHIVO (NUEVO)
    - Escribe el nombre arriba (ej: mapa_zombies). Se añade .txt si no pones extensión.
    - Opción "No sobrescribir": si existe, guarda como nombre_2.txt, nombre_3.txt…
    - Carpeta de destino: ver SAVE_DIRS en la configuración (/storage/emulated/0/Delta/Informaciónrecopilada)
]]

----------------------------------------------------------------
-- CONFIGURACIÓN
----------------------------------------------------------------
local GUI_NAME      = "RemoteCaptureGUI"
local MAX_CALLS     = 150
local MAX_REPORT    = 30000
local MAX_SCAN      = 40000
local MAX_GROUPS    = 250
local MAX_ALL_LINES = 250000     -- líneas máximas del árbol completo
local MAX_ALL_CHARS = 4000000    -- tamaño máximo del archivo TODO
local MAX_CLIP      = 100000     -- el portapapeles móvil no aguanta más
local MAX_DEPTH     = 30
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

-- Opciones globales (se cambian con botones en la pestaña TODO)
local opts = { scrub = true, group = true, safe = true }

----------------------------------------------------------------
-- SERVICIOS
----------------------------------------------------------------
local Players            = game:GetService("Players")
local UserInputService   = game:GetService("UserInputService")
local CoreGui            = game:GetService("CoreGui")
local Workspace          = game:GetService("Workspace")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
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

-- Oculta nombres de usuario y IDs de todos los jugadores del servidor
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

-- Personaje, mochila y lo que llevas en la mano (sin scrub: lo aplica quien llama)
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
                -- no repetir hijos de algo ya descrito
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
-- VOLCADO TOTAL (pestaña 📦 TODO)
----------------------------------------------------------------
local full = { busy = false, report = "", summary = "", status = "Pulsa «Recopilar TODO»." }

local function bump(tbl, key, sample)
    local g = tbl[key]
    if g then g.count += 1 else tbl[key] = { count = 1, sample = sample } end
end

local function listGroups(title, tbl, out, cap, noSample)
    local list = {}
    for k, g in pairs(tbl) do list[#list + 1] = { k = k, g = g } end
    table.sort(list, function(a, b)
        if a.g.count ~= b.g.count then return a.g.count > b.g.count end
        return a.k < b.k
    end)
    out[#out + 1] = "## " .. title .. " (" .. #list .. " distintos)"
    for i, e in ipairs(list) do
        if i > cap then out[#out + 1] = "… (" .. (#list - cap) .. " más)" break end
        local line = e.k .. (e.g.count > 1 and (" x" .. e.g.count) or "")
        if not noSample then line = line .. "  ej: " .. relPath(e.g.sample) end
        out[#out + 1] = line
    end
    if #list == 0 then out[#out + 1] = "(ninguno)" end
    out[#out + 1] = ""
end

local function infoSection(out)
    local exName = "?"
    if identifyexecutor then
        local okE, n, v = pcall(identifyexecutor)
        if okE then exName = tostring(n) .. (v and (" " .. tostring(v)) or "") end
    end
    local caps = {}
    for _, f in ipairs({ "hookmetamethod", "getnamecallmethod", "getcallingscript", "writefile", "appendfile",
        "isfile", "setclipboard", "getnilinstances", "getloadedmodules", "getgc", "getscripts",
        "fireproximityprompt", "firetouchinterest", "fireclickdetector", "getconnections", "decompile" }) do
        caps[#caps + 1] = f .. "=" .. (env[f] ~= nil and "sí" or "no")
    end
    local streaming = tryGet(function() return Workspace.StreamingEnabled end)
    out[#out + 1] = "=== VOLCADO TOTAL ==="
    out[#out + 1] = "Fecha: " .. os.date("%Y-%m-%d %H:%M:%S")
    out[#out + 1] = "Juego: " .. gameName()
    out[#out + 1] = "PlaceId: " .. game.PlaceId .. " | GameId: " .. game.GameId .. " | PlaceVersion: " .. tostring(game.PlaceVersion)
    out[#out + 1] = "JobId: " .. tostring(game.JobId)
    out[#out + 1] = "Jugadores: " .. #Players:GetPlayers() .. "/" .. tostring(Players.MaxPlayers)
    out[#out + 1] = "Gravedad: " .. tostring(tryGet(function() return Workspace.Gravity end))
    out[#out + 1] = "StreamingEnabled: " .. tostring(streaming)
        .. (streaming and "  (⚠ solo ves lo cercano a tu personaje; vuelve a recopilar en otra zona)" or "")
    out[#out + 1] = "Ejecutor: " .. exName
    out[#out + 1] = "Funciones: " .. table.concat(caps, ", ")
    out[#out + 1] = "Opciones: ocultar usuarios=" .. (opts.scrub and "sí" or "no")
        .. " | agrupar repetidos=" .. (opts.group and "sí" or "no")
        .. " | ignorar personajes=" .. (scan.hidePlayers and "sí" or "no")
    out[#out + 1] = ""
end

local function inventory(roots, skipSet)
    local inv = { classes = {}, remotes = {}, scripts = {}, prompts = {}, clicks = {}, npcs = {}, tools = {}, checked = 0 }
    local n = 0
    for _, r in ipairs(roots) do
        local checkSkip = (r.inst == Workspace) or (r.inst == player)
        for _, d in ipairs(r.inst:GetDescendants()) do
            n += 1
            if n % 400 == 0 then
                task.wait()
                full.status = "Inventario… " .. n .. " instancias"
            end
            local skip = false
            if checkSkip then
                if skipSet[d] then
                    skip = true
                else
                    local a = d.Parent
                    while a and a ~= r.inst do
                        if skipSet[a] then skip = true break end
                        a = a.Parent
                    end
                end
            end
            if skip then continue end

            inv.checked += 1
            local cn = d.ClassName
            inv.classes[cn] = (inv.classes[cn] or 0) + 1
            if cn == "RemoteEvent" or cn == "RemoteFunction" or cn == "UnreliableRemoteEvent"
                or cn == "BindableEvent" or cn == "BindableFunction" then
                bump(inv.remotes, cn .. "  " .. path(d), d)
            elseif d:IsA("LuaSourceContainer") then
                bump(inv.scripts, cn .. "  " .. normName(relPath(d)), d)
            elseif cn == "ProximityPrompt" then
                bump(inv.prompts, tostring(d.ActionText) .. " | " .. tostring(d.ObjectText)
                    .. " | en " .. normName(d.Parent and d.Parent.Name or "?"), d)
            elseif cn == "ClickDetector" then
                bump(inv.clicks, "en " .. normName(d.Parent and d.Parent.Name or "?"), d)
            elseif cn == "Humanoid" then
                local par = d.Parent
                bump(inv.npcs, normName(par and par.Name or "?"), par or d)
            elseif cn == "Tool" then
                bump(inv.tools, normName(d.Name), d)
            end
        end
    end
    return inv
end

-- Propiedades útiles según tipo de objeto
local function instProps(d)
    local bits = {}
    if d:IsA("ValueBase") then
        bits[#bits + 1] = "= " .. valueOf(d)
    elseif d:IsA("BasePart") then
        local p, s = d.Position, d.Size
        bits[#bits + 1] = string.format("pos %.0f,%.0f,%.0f size %.1f,%.1f,%.1f", p.X, p.Y, p.Z, s.X, s.Y, s.Z)
        bits[#bits + 1] = "Anchored=" .. tostring(d.Anchored) .. " CanCollide=" .. tostring(d.CanCollide)
    elseif d:IsA("Model") then
        local pv = tryGet(function() return d:GetPivot().Position end)
        if pv then bits[#bits + 1] = string.format("pos %.0f,%.0f,%.0f", pv.X, pv.Y, pv.Z) end
        if d.PrimaryPart then bits[#bits + 1] = "Primary=" .. d.PrimaryPart.Name end
    elseif d:IsA("Humanoid") then
        bits[#bits + 1] = "Health=" .. tostring(tryGet(function() return d.Health end))
            .. "/" .. tostring(tryGet(function() return d.MaxHealth end))
            .. " WalkSpeed=" .. tostring(tryGet(function() return d.WalkSpeed end))
    elseif d:IsA("ProximityPrompt") then
        bits[#bits + 1] = "Action=" .. ser(d.ActionText) .. " Object=" .. ser(d.ObjectText)
            .. " Hold=" .. tostring(d.HoldDuration) .. " Dist=" .. tostring(d.MaxActivationDistance)
            .. " Enabled=" .. tostring(d.Enabled)
    elseif d:IsA("ClickDetector") then
        bits[#bits + 1] = "Dist=" .. tostring(d.MaxActivationDistance)
    elseif d:IsA("Sound") then
        bits[#bits + 1] = "SoundId=" .. ser(d.SoundId)
    elseif d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
        bits[#bits + 1] = "Text=" .. ser(d.Text) .. " Visible=" .. tostring(d.Visible)
    elseif d:IsA("GuiObject") then
        bits[#bits + 1] = "Visible=" .. tostring(d.Visible)
    end
    local okA, attrs = pcall(d.GetAttributes, d)
    if okA and attrs and next(attrs) then bits[#bits + 1] = "attrs=" .. ser(attrs, 0) end
    local tags = tryGet(function() return CollectionService:GetTags(d) end)
    if tags and #tags > 0 then bits[#bits + 1] = "tags=" .. table.concat(tags, ",") end
    return table.concat(bits, " | ")
end

local dumpChildren

local function dumpNode(d, depth, st)
    if st.lines >= MAX_ALL_LINES then st.truncated = true return end
    st.n += 1
    if st.n % 300 == 0 then
        task.wait()
        full.status = "Árbol… " .. st.lines .. " líneas"
    end
    local extra = instProps(d)
    st.out[#st.out + 1] = string.rep("  ", depth) .. d.ClassName .. ' "' .. d.Name .. '"'
        .. (extra ~= "" and ("  " .. extra) or "")
    st.lines += 1
    if depth >= MAX_DEPTH then
        st.out[#st.out + 1] = string.rep("  ", depth + 1) .. "… (profundidad máxima)"
        return
    end
    local kids = d:GetChildren()
    if #kids > 0 then dumpChildren(kids, depth + 1, st) end
end

dumpChildren = function(kids, depth, st)
    if opts.group then
        local order, groups = {}, {}
        for _, c in ipairs(kids) do
            if st.skip[c] then
                st.skipped += 1
            else
                local nn = normName(c.Name)
                local k = nn .. "|" .. c.ClassName
                local g = groups[k]
                if g then
                    g.count += 1
                else
                    g = { count = 1, first = c, name = nn }
                    groups[k] = g
                    order[#order + 1] = g
                end
            end
        end
        for _, g in ipairs(order) do
            if st.truncated then return end
            if g.count == 1 then
                dumpNode(g.first, depth, st)
            else
                local extra = instProps(g.first)
                st.out[#st.out + 1] = string.rep("  ", depth) .. g.first.ClassName .. ' "' .. g.name .. '" x' .. g.count
                    .. "  (ej: " .. g.first.Name .. ")" .. (extra ~= "" and ("  " .. extra) or "")
                st.lines += 1
                if depth < MAX_DEPTH then
                    local sub = g.first:GetChildren()
                    if #sub > 0 then dumpChildren(sub, depth + 1, st) end
                end
            end
        end
    else
        for _, c in ipairs(kids) do
            if st.truncated then return end
            if st.skip[c] then st.skipped += 1 else dumpNode(c, depth, st) end
        end
    end
end

local function runFullDump(guiRef)
    full.status = "Recopilando info…"
    local out = {}

    -- Personajes a ignorar + nuestra propia GUI
    local skipSet = {}
    if scan.hidePlayers then
        for _, pl in ipairs(Players:GetPlayers()) do
            if pl.Character then skipSet[pl.Character] = true end
        end
    end
    skipSet[guiRef] = true

    -- Raíces a recorrer
    local roots = {}
    for _, nm in ipairs({ "Workspace", "ReplicatedStorage", "ReplicatedFirst", "Lighting", "StarterGui",
        "StarterPack", "StarterPlayer", "Teams", "SoundService", "TextChatService", "Chat" }) do
        local okS, svc = pcall(game.GetService, game, nm)
        if okS and svc then roots[#roots + 1] = { name = nm, inst = svc } end
    end
    roots[#roots + 1] = { name = "Players.LocalPlayer", inst = player }

    -- 1) Info + jugador
    infoSection(out)
    out[#out + 1] = myCharReport()
    out[#out + 1] = ""

    -- 2) Inventario
    local inv = inventory(roots, skipSet)
    out[#out + 1] = "Instancias revisadas: " .. inv.checked
    out[#out + 1] = ""
    listGroups("REMOTES / BINDABLES (todos, aunque no los hayas usado)", inv.remotes, out, 1500, true)
    listGroups("PROXIMITY PROMPTS (acción | objeto | en)", inv.prompts, out, 300)
    listGroups("CLICK DETECTORS", inv.clicks, out, 150)
    listGroups("NPCs / HUMANOIDS (nombre del modelo)", inv.npcs, out, 200)
    listGroups("TOOLS", inv.tools, out, 150)
    listGroups("SCRIPTS / MÓDULOS (clase  ruta)", inv.scripts, out, 800)

    local cl = {}
    for k, v in pairs(inv.classes) do cl[#cl + 1] = { k, v } end
    table.sort(cl, function(a, b) return a[2] > b[2] end)
    out[#out + 1] = "## CLASES MÁS COMUNES"
    local cparts = {}
    for i = 1, math.min(40, #cl) do cparts[#cparts + 1] = cl[i][1] .. " x" .. cl[i][2] end
    out[#out + 1] = table.concat(cparts, ", ")
    out[#out + 1] = ""

    -- 3) Cosas extra del ejecutor
    full.status = "Instancias nil y módulos…"
    if getnilinstances then
        local okN, nils = pcall(getnilinstances)
        if okN and type(nils) == "table" then
            local g = {}
            for i, inst in ipairs(nils) do
                if i % 400 == 0 then task.wait() end
                local okc, key = pcall(function() return inst.ClassName .. "  " .. normName(inst.Name) end)
                if okc then bump(g, key, inst) end
            end
            listGroups("INSTANCIAS SIN PADRE (nil)", g, out, 100, true)
        end
    end
    if getloadedmodules then
        local okM, mods = pcall(getloadedmodules)
        if okM and type(mods) == "table" then
            local g = {}
            for _, m in ipairs(mods) do
                local okc, key = pcall(function() return normName(path(m)) end)
                if okc and not key:find("^CoreGui") and not key:find("^CorePackages") then bump(g, key, m) end
            end
            listGroups("MÓDULOS CARGADOS (sin CoreGui)", g, out, 200, true)
        end
    end

    -- 4) Capturas y scanner previos
    if state.total > 0 then
        out[#out + 1] = buildReport()
        out[#out + 1] = ""
    end
    if scan.report ~= "" then
        out[#out + 1] = scan.report
        out[#out + 1] = ""
    end

    local summary = scrub(table.concat(out, "\n"))

    -- 5) Árbol completo
    local st = { out = {}, lines = 0, n = 0, skip = skipSet, skipped = 0, truncated = false }
    st.out[#st.out + 1] = "=============================="
    st.out[#st.out + 1] = "ÁRBOL COMPLETO" .. (opts.group and " (repetidos agrupados: «xN», se muestra un ejemplo)" or " (cada objeto)")
    st.out[#st.out + 1] = "=============================="
    for _, r in ipairs(roots) do
        if st.truncated then break end
        local kids = r.inst:GetChildren()
        st.out[#st.out + 1] = ""
        st.out[#st.out + 1] = "### " .. r.name .. " (" .. #kids .. " hijos directos)"
        full.status = "Árbol: " .. r.name .. "…"
        dumpChildren(kids, 1, st)
    end
    st.out[#st.out + 1] = ""
    st.out[#st.out + 1] = "Líneas del árbol: " .. st.lines .. " | Personajes/GUI omitidos: " .. st.skipped
        .. (st.truncated and "  ⚠ LÍMITE DE LÍNEAS ALCANZADO" or "")

    local text = summary .. "\n\n" .. scrub(table.concat(st.out, "\n"))
    if #text > MAX_ALL_CHARS then text = text:sub(1, MAX_ALL_CHARS) .. "\n… (recortado por tamaño)" end
    return summary, text, st.lines
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

makeLabel(header, "📡 Remote Capture + Scanner v2", UDim2.new(1, -90, 0, 24), UDim2.new(0, 14, 0, 4), 16).Font = Enum.Font.GothamBold
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
addTab("📦 TODO", pageAll)

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
-- PESTAÑA 3: TODO
----------------------------------------------------------------
local fullStatusCard = card(pageAll, 64)
local fullStatusLabel = makeLabel(fullStatusCard, "", UDim2.new(1, -20, 1, -12), UDim2.new(0, 10, 0, 6), 13)

local fullGo = bigButton(pageAll, "📦  RECOPILAR TODO (y guardar archivo)", C.Green, 56)

local infoCard = card(pageAll, 96)
makeLabel(infoCard,
    "Incluye: info del juego y ejecutor, mi personaje, TODOS los remotes, scripts, prompts, NPCs, tools, "
    .. "clases, nil, módulos y el ÁRBOL COMPLETO de todos los servicios, más lo capturado en 📡 y 🔍. "
    .. "El archivo se guarda con el nombre de arriba.",
    UDim2.new(1, -16, 1, -12), UDim2.new(0, 8, 0, 6), 11, C.Sub)

makeToggle(pageAll, "Ocultar nombres de usuario", opts, "scrub", 36)
makeToggle(pageAll, "Agrupar repetidos (Pen_#_# → xN)", opts, "group", 36)
makeToggle(pageAll, "Ignorar personajes de jugadores", scan, "hidePlayers", 36)
makeToggle(pageAll, "No sobrescribir (añade _2, _3…)", opts, "safe", 36)

local fullCopySum = bigButton(pageAll, "📋  Copiar RESUMEN (sin árbol)", C.Accent, 44)
local fullCopyAll = bigButton(pageAll, "📋  Copiar todo (primeros " .. MAX_CLIP .. " car.)", C.Btn, 40)
fullCopyAll.TextSize = 12
local fullSave = bigButton(pageAll, "💾  Guardar de nuevo con el nombre de arriba", C.Btn, 40)
fullSave.TextSize = 12

fullGo.Activated:Connect(function()
    if full.busy then return end
    full.busy = true
    full.status = "Recopilando… (puede tardar, no cierres)"
    task.spawn(function()
        local ok, a, b, c = pcall(runFullDump, gui)
        full.busy = false
        if not ok then full.status = "⚠ Error: " .. tostring(a):sub(1, 80) return end
        full.summary, full.report = a, b
        local saved, res = saveFile(b, "FullDump_" .. game.PlaceId .. ".txt")
        full.status = (saved and ("💾 Guardado como " .. res) or ("⚠ No se pudo guardar: " .. res))
            .. " — " .. #b .. " car., " .. c .. " líneas de árbol."
    end)
end)

fullCopySum.Activated:Connect(function()
    if full.summary == "" then full.status = "Primero pulsa «Recopilar TODO»." return end
    local t = full.summary
    if #t > MAX_CLIP then t = t:sub(1, MAX_CLIP) .. "\n… (recortado)" end
    full.status = copyText(t) and ("📋 Resumen copiado (" .. #t .. " car.). Pégalo en el chat.") or "⚠ No se pudo copiar."
end)

fullCopyAll.Activated:Connect(function()
    if full.report == "" then full.status = "Primero pulsa «Recopilar TODO»." return end
    local t = full.report:sub(1, MAX_CLIP)
    full.status = copyText(t) and ("📋 Copiados los primeros " .. #t .. " car. (el archivo tiene todo).") or "⚠ No se pudo copiar."
end)

fullSave.Activated:Connect(function()
    if full.report == "" then full.status = "Primero pulsa «Recopilar TODO»." return end
    local ok, res = saveFile(full.report, "FullDump_" .. game.PlaceId .. ".txt")
    full.status = ok and ("💾 Guardado como " .. res .. ".") or ("⚠ No se pudo guardar: " .. res)
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
        fullStatusLabel.Text = full.status
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
statusLabel.Text = hookOK and "Listo. Activa la captura y marca cada acción." or "⚠ Tu ejecutor no soporta hookmetamethod (Scanner y TODO sí funcionan)."
