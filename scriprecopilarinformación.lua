--[[
    REMOTE CAPTURE + SCANNER + INFO ÚTIL v4 para Delta (Mobile/PC)

    CAMBIO PRINCIPAL EN v4: el informe ya NO es un volcado de texto.
    Ahora sale como DATOS en Lua (tablas), con rutas ya resueltas y listas para pegar en un script:

      INFO.meta       juego, PlaceId, StreamingEnabled, funciones del ejecutor
      INFO.remotes    { path = <expresión Lua>, class, seen }
      INFO.calls      acciones marcadas -> steps { code = "<remote>:FireServer(args)", ret, count, caller }
      INFO.prompts    ProximityPrompts: action, object, hold, distance, example, pos
      INFO.clicks     ClickDetectors
      INFO.touch      objetos con TouchInterest (coleccionables, zonas, puertas)
      INFO.npcs       Humanoids (enemigos/NPCs): pattern, health, attrs, example, parent, pos
      INFO.attrs      objetos con atributos (IDs y datos)
      INFO.tags       tags de CollectionService
      INFO.screens / INFO.buttons / INFO.labels   interfaz de PlayerGui
      INFO.me         posición, humanoid, atributos, valores, tools
      INFO.workspaceTree / INFO.replicatedTree    jerarquía anidada (root + children)

    Los objetos repetidos (Pen_3_12, Pen_4_1…) se agrupan con un `pattern` de string.match y un `parent`:
      for _, o in ipairs(<parent>:GetChildren()) do if o.Name:match(pattern) then ... end end

    Cada sección es independiente y el archivo entero es Lua válido (return INFO).
    Cada sección se puede activar/desactivar. El informe sale por partes para copiar.

    Nombre de archivo: escríbelo arriba (ej: mapa_zombies). Se añade .txt si no pones extensión.
    "No sobrescribir": si existe, guarda como nombre_2.txt, nombre_3.txt…  Carpetas: ver SAVE_DIRS
]]

----------------------------------------------------------------
-- CONFIGURACIÓN
----------------------------------------------------------------
local GUI_NAME   = "RemoteCaptureGUI"
local MAX_CALLS  = 150
local MAX_SCAN   = 60000
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
-- UTILIDADES: serialización a Lua (datos listos para usar)
----------------------------------------------------------------
local function clamp(n, lo, hi) return math.max(lo, math.min(hi, n)) end

local function path(inst)
    local ok, p = pcall(function() return inst:GetFullName() end)
    return ok and p or tostring(inst)
end

local KEYWORDS = {}
for w in ("and break do else elseif end false for function if in local nil not or repeat return then true until while"):gmatch("%a+") do
    KEYWORDS[w] = true
end
local PROPS = { Name = true, Parent = true, ClassName = true }
local serviceOK = {}

local function isService(cn)
    local v = serviceOK[cn]
    if v == nil then
        v = pcall(game.GetService, game, cn)
        serviceOK[cn] = v
    end
    return v
end

-- string -> literal Lua ("..." con escapes)
local function q(s)
    s = tostring(s)
    if #s > 300 then s = s:sub(1, 300) .. "…" end
    s = s:gsub('[%c"\\]', function(c)
        if c == "\n" then return "\\n"
        elseif c == '"' then return '\\"'
        elseif c == "\\" then return "\\\\"
        else return string.format("\\%03d", c:byte()) end
    end)
    return '"' .. s .. '"'
end

local function num(x)
    if x ~= x then return "0/0" end
    if x == math.huge then return "math.huge" elseif x == -math.huge then return "-math.huge" end
    if x % 1 == 0 and math.abs(x) < 1e15 then return string.format("%d", x) end
    local s = string.format("%.4f", x):gsub("0+$", ""):gsub("%.$", "")
    if s == "" or s == "-0" then return "0" end
    return s
end

-- Instancia -> expresión Lua exacta (game:GetService("X").A.B / workspace.A / ...LocalPlayer...)
local function pathExpr(inst)
    if typeof(inst) ~= "Instance" then return "nil" end
    if inst == game then return "game" end
    local chain, cur = {}, inst
    for _ = 1, 100 do
        if not cur or cur == game then break end
        table.insert(chain, 1, cur)
        local okp, par = pcall(function() return cur.Parent end)
        cur = okp and par or nil
    end
    if cur ~= game or #chain == 0 then
        return "nil --[[" .. tostring(inst.Name):gsub("[%]%[]", "") .. " (fuera de game)]]"
    end
    local top = chain[1]
    local expr, start
    if top == Workspace then
        expr, start = "workspace", 2
        if player.Character and chain[2] == player.Character then
            expr, start = 'game:GetService("Players").LocalPlayer.Character', 3
        end
    elseif isService(top.ClassName) then
        expr, start = 'game:GetService("' .. top.ClassName .. '")', 2
        if top == Players and chain[2] == player then
            expr, start = expr .. ".LocalPlayer", 3
        end
    else
        expr, start = "game[" .. q(top.Name) .. "]", 2
    end
    for i = start, #chain do
        local nm = chain[i].Name
        if PROPS[nm] then
            expr = expr .. ":FindFirstChild(" .. q(nm) .. ")"
        elseif nm:match("^[%a_][%w_]*$") and not KEYWORDS[nm] then
            expr = expr .. "." .. nm
        else
            expr = expr .. "[" .. q(nm) .. "]"
        end
    end
    return expr
end

-- Valor cualquiera -> literal Lua
local function lv(v, depth)
    depth = depth or 0
    local t = typeof(v)
    if t == "string" then return q(v)
    elseif t == "number" then return num(v)
    elseif t == "boolean" or t == "nil" then return tostring(v)
    elseif t == "Instance" then return pathExpr(v)
    elseif t == "Vector3" then return "Vector3.new(" .. num(v.X) .. ", " .. num(v.Y) .. ", " .. num(v.Z) .. ")"
    elseif t == "Vector2" then return "Vector2.new(" .. num(v.X) .. ", " .. num(v.Y) .. ")"
    elseif t == "CFrame" then
        local p = {}
        for i, x in ipairs({ v:GetComponents() }) do p[i] = num(x) end
        return "CFrame.new(" .. table.concat(p, ", ") .. ")"
    elseif t == "Color3" then
        return string.format("Color3.fromRGB(%d, %d, %d)", math.floor(v.R * 255 + 0.5), math.floor(v.G * 255 + 0.5), math.floor(v.B * 255 + 0.5))
    elseif t == "UDim2" then
        return "UDim2.new(" .. num(v.X.Scale) .. ", " .. num(v.X.Offset) .. ", " .. num(v.Y.Scale) .. ", " .. num(v.Y.Offset) .. ")"
    elseif t == "UDim" then return "UDim.new(" .. num(v.Scale) .. ", " .. num(v.Offset) .. ")"
    elseif t == "EnumItem" then return tostring(v)
    elseif t == "BrickColor" then return "BrickColor.new(" .. q(v.Name) .. ")"
    elseif t == "table" then
        if depth >= 3 then return "{--[[…]]}" end
        local parts, len, isArr = {}, #v, true
        for k in pairs(v) do
            if type(k) ~= "number" or k < 1 or k > len or k % 1 ~= 0 then isArr = false break end
        end
        if isArr then
            for i = 1, len do
                if i > 25 then parts[#parts + 1] = "--[[…]]" break end
                parts[#parts + 1] = lv(v[i], depth + 1)
            end
        else
            local n = 0
            for k, val in pairs(v) do
                n += 1
                if n > 25 then parts[#parts + 1] = "--[[…]]" break end
                local key = (type(k) == "string" and k:match("^[%a_][%w_]*$") and not KEYWORDS[k]) and k
                    or ("[" .. lv(k, depth + 1) .. "]")
                parts[#parts + 1] = key .. " = " .. lv(val, depth + 1)
            end
        end
        return "{ " .. table.concat(parts, ", ") .. " }"
    else
        return "nil --[[" .. t .. "]]"
    end
end

local function joinLv(t)
    local list = {}
    for i = 1, t.n do list[i] = lv(t[i], 0) end
    return table.concat(list, ", ")
end

-- Long-bracket string (para guardar código Lua dentro de una tabla sin escapes)
local function lb(s)
    local lvl = ""
    while s:find("]" .. lvl .. "]", 1, true) do lvl = lvl .. "=" end
    return "[" .. lvl .. "[" .. s .. "]" .. lvl .. "]"
end

-- Fila de tabla en una sola línea: row("  ", { {"clave", <literal ya serializado o nil>}, ... })
local function row(indent, fields)
    local parts = {}
    for _, kv in ipairs(fields) do
        if kv[2] ~= nil then parts[#parts + 1] = kv[1] .. " = " .. kv[2] end
    end
    return indent .. "{ " .. table.concat(parts, ", ") .. " },"
end
-- Igual, pero deja abierta la lista children = { (hay que cerrarla con "}, ... },")
local function rowOpen(indent, fields)
    local parts = {}
    for _, kv in ipairs(fields) do
        if kv[2] ~= nil then parts[#parts + 1] = kv[1] .. " = " .. kv[2] end
    end
    return indent .. "{ " .. table.concat(parts, ", ") .. ", children = {"
end

-- "Pen_3_12" -> "Pen_#_#" ; uuid -> <uuid>  (clave de agrupación)
local function normName(n)
    n = n:gsub("%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x", "<uuid>")
    n = n:gsub("^(HeldPet_).+(_%a+)$", "%1<usuario>%2")
    n = n:gsub("%d+", "#")
    return n
end

-- Patrón string.match anclado: "Pen_3_12" -> "^Pen%_%d+%_%d+$"
local UUID_PAT = "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x"
local function namePattern(n)
    n = tostring(n)
    if n:match("^HeldPet_.+_%a+$") then return "^HeldPet%_.+%_%a+$" end
    n = n:gsub(UUID_PAT, "\1")
    n = n:gsub("%p", "%%%0")
    n = n:gsub("%d+", "%%d+")
    n = n:gsub("\1", "%%x+%%-%%x+%%-%%x+%%-%%x+%%-%%x+")
    return "^" .. n .. "$"
end

local function instPos(d)
    local ok, pos = pcall(function()
        if d:IsA("Model") then return d:GetPivot().Position end
        if d:IsA("BasePart") then return d.Position end
        return nil
    end)
    return ok and pos or nil
end

-- Posición del objeto o del primer ancestro que tenga (Prompt -> su Part)
local function posLv(inst)
    local cur = inst
    for _ = 1, 4 do
        if not cur or cur == Workspace or cur == game then return nil end
        local p = instPos(cur)
        if p then return lv(p) end
        cur = cur.Parent
    end
    return nil
end

local function valueLv(inst)
    local ok, v = pcall(function() return inst.Value end)
    return ok and lv(v, 0) or "nil"
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

-- Corta por líneas completas (el archivo sigue siendo Lua válido hasta ese punto)
local function capText(text, max)
    if #text <= max then return text end
    local cut = text:sub(1, max):match("^(.*)\n") or text:sub(1, max)
    return cut .. "\n-- … recortado por tamaño (faltan secciones o filas; usa filtros o desactiva secciones)"
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

local LEGEND = {
    "--[[ LEYENDA — este archivo es Lua válido; cada sección INFO.xxx es independiente (puede faltar o estar recortada).",
    "  path / example / parent / root = expresiones Lua YA RESUELTAS: se pegan tal cual en un script.",
    "  pattern = string.match anclado para reconocer los objetos de un grupo (Pen_3_12 -> ^Pen%_%d+%_%d+$); count = cuántos hay.",
    "  Recorrer un grupo: for _, o in ipairs(<parent>:GetChildren()) do if o.Name:match(pattern) then ... end end",
    "  Remotes: <path>:FireServer(...) / <path>:InvokeServer(...)  |  INFO.calls: steps[].code = la llamada exacta observada.",
    "  Interactuar: fireproximityprompt(p) · fireclickdetector(cd) · firetouchinterest(hrp, part, 0) y luego (…, 1) · firesignal(btn.Activated)",
    "  pos = Vector3 del objeto (para teletransportar). Árboles: ruta = root + nombres de los children anidados.",
    "  visible=false en un botón: la ruta existe pero hay que abrir antes su menú.",
    "]]",
}

local function startReport(title, extra)
    local out = {}
    for _, l in ipairs(LEGEND) do out[#out + 1] = l end
    out[#out + 1] = "local INFO = {}"
    out[#out + 1] = "INFO.meta = { title = " .. q(title) .. ", game = " .. q(gameName()) .. ", placeId = " .. game.PlaceId
        .. ", date = " .. q(os.date("%Y-%m-%d %H:%M")) .. (extra or "") .. " }"
    out[#out + 1] = ""
    return out
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

state.record = function(remote, method, args, res, caller)
    if not running then return end
    local full = path(remote)
    state.seen[full] = (state.seen[full] or 0) + 1 -- para marcar `seen` en la lista de remotes
    local short = full:match("Services%.(.+)$") or full
    if state.hide then
        for _, pat in ipairs(NOISE) do
            if remote.Name:find(pat) then return end
        end
    end
    local argStr = joinLv(args)
    local resStr = res and joinLv(res) or nil

    state.total += 1
    state.dirty = true
    local key = state.marker .. "|" .. short .. "|" .. method .. "|" .. argStr
    local e = state.map[key]
    if e then
        e.count += 1
        if resStr and not e.res then e.res = resStr end
    elseif state.calls < MAX_CALLS then
        e = { kind = "call", path = short, expr = pathExpr(remote), method = method, args = argStr, res = resStr,
              count = 1, caller = caller and pathExpr(caller) or nil }
        state.map[key] = e
        table.insert(state.seq, e)
    end
end

local function addMarker(label)
    state.marker += 1
    table.insert(state.seq, { kind = "mark", label = label })
    state.dirty = true
end

-- INFO.calls: una entrada por acción marcada; cada paso trae la línea de código exacta
local function capturesLines(out)
    local groups, cur = {}, nil
    for _, e in ipairs(state.seq) do
        if e.kind == "mark" then
            cur = { label = e.label, steps = {} }
            groups[#groups + 1] = cur
        else
            if not cur then
                cur = { label = "(sin marcar)", steps = {} }
                groups[#groups + 1] = cur
            end
            cur.steps[#cur.steps + 1] = e
        end
    end
    out[#out + 1] = "INFO.calls = {   -- en orden; action = lo que marcaste con el botón Marcar"
    for _, g in ipairs(groups) do
        out[#out + 1] = "  { action = " .. q(g.label) .. ", steps = {"
        for _, e in ipairs(g.steps) do
            out[#out + 1] = row("    ", {
                { "code", lb(e.expr .. ":" .. e.method .. "(" .. e.args .. ")") },
                { "count", tostring(e.count) },
                { "ret", e.res and ("{ " .. e.res .. " }") or nil },
                { "caller", e.caller },
            })
        end
        out[#out + 1] = "  } },"
    end
    out[#out + 1] = "}"
end

local function buildReport()
    local out = startReport("CAPTURAS", ", totalCalls = " .. state.total .. ", distinct = " .. state.calls)
    capturesLines(out)
    out[#out + 1] = ""
    out[#out + 1] = "return INFO"
    return scrub(table.concat(out, "\n"))
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

local function relPath(inst)
    local p = path(inst)
    p = p:gsub("^Workspace%.", "")
    return #p > 100 and ("…" .. p:sub(-99)) or p
end

-- Campos extra de un objeto de muestra: attrs, children, humanoid, primary, pos
local function sampleFields(d, f)
    local okA, attrs = pcall(d.GetAttributes, d)
    if okA and attrs and next(attrs) then f[#f + 1] = { "attrs", lv(attrs) } end
    local kids, seen, n = {}, {}, 0
    for _, c in ipairs(d:GetChildren()) do
        local k = normName(c.Name) .. "|" .. c.ClassName
        if not seen[k] then
            seen[k] = true
            n += 1
            if n <= 8 then kids[#kids + 1] = q(c.ClassName .. ":" .. c.Name) end
        end
    end
    if n > 0 then
        f[#f + 1] = { "children", "{ " .. table.concat(kids, ", ") .. (n > 8 and ", --[[…]]" or "") .. " }" }
    end
    if d:IsA("Model") then
        if d:FindFirstChildOfClass("Humanoid") then f[#f + 1] = { "humanoid", "true" } end
        if d.PrimaryPart then f[#f + 1] = { "primary", q(d.PrimaryPart.Name) } end
    end
    local pos = posLv(d)
    if pos then f[#f + 1] = { "pos", pos } end
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

        local out = startReport("SCANNER")
        out[#out + 1] = "INFO.scan = { zone = " .. q(zoneNames[scan.zone]) .. ", mode = " .. q(modeNames[scan.mode])
            .. ", filter = " .. q(filter) .. ", radius = " .. (center and tostring(radius) or "nil")
            .. ", playersHidden = " .. tostring(scan.hidePlayers) .. ", checked = " .. checked .. ", groups = " .. #list .. " }"
        out[#out + 1] = ""

        if scan.zone == 1 or scan.zone == 3 then
            local direct, dorder = {}, {}
            for _, c in ipairs(Workspace:GetChildren()) do
                local isChar = false
                for _, ch in ipairs(chars) do if c == ch then isChar = true break end end
                if not isChar then
                    local k = keyOf(c.Name) .. "|" .. c.ClassName
                    local g = direct[k]
                    if g then g.count += 1 else direct[k] = { count = 1, sample = c } dorder[#dorder + 1] = k end
                end
            end
            table.sort(dorder)
            out[#out + 1] = "INFO.workspaceChildren = {   -- hijos directos de workspace"
            for i, k in ipairs(dorder) do
                if i > 80 then out[#out + 1] = "  -- … (más)" break end
                local g = direct[k]
                out[#out + 1] = row("  ", {
                    { "class", q(g.sample.ClassName) },
                    g.count > 1 and { "pattern", q(namePattern(g.sample.Name)) } or { "name", q(g.sample.Name) },
                    { "count", tostring(g.count) },
                })
            end
            out[#out + 1] = "}"
            out[#out + 1] = ""
        end

        local previewLines = {}
        out[#out + 1] = "INFO.names = {   -- grupos de objetos con el mismo patrón de nombre (los más repetidos primero)"
        for i, g in ipairs(list) do
            if i > MAX_GROUPS then
                out[#out + 1] = "  -- … (" .. (#list - MAX_GROUPS) .. " grupos más; usa filtro o radio)"
                break
            end
            local s = g.sample
            local f = {
                { "pattern", q(namePattern(s.Name)) }, { "class", q(g.class) }, { "count", tostring(g.count) },
                { "example", pathExpr(s) }, { "parent", pathExpr(s.Parent) },
            }
            if g.dist then f[#f + 1] = { "nearest", num(g.dist) } end
            sampleFields(s, f)
            out[#out + 1] = row("  ", f)
            if i <= 8 then previewLines[#previewLines + 1] = g.name .. " x" .. g.count end
        end
        out[#out + 1] = "}"
        out[#out + 1] = ""

        local pl = {}
        for _, v in pairs(prompts) do pl[#pl + 1] = v end
        table.sort(pl, function(a, b) return a.count > b.count end)
        out[#out + 1] = "INFO.prompts = {   -- fireproximityprompt(<example>)"
        for i, e in ipairs(pl) do
            if i > 40 then out[#out + 1] = "  -- … (más)" break end
            local d = e.sample
            out[#out + 1] = row("  ", {
                { "action", q(d.ActionText) }, { "object", q(d.ObjectText) }, { "count", tostring(e.count) },
                { "ownerPattern", q(namePattern(d.Parent and d.Parent.Name or "?")) },
                { "example", pathExpr(d) }, { "pos", posLv(d) },
            })
        end
        out[#out + 1] = "}"
        out[#out + 1] = ""
        out[#out + 1] = "return INFO"

        local text = capText(scrub(table.concat(out, "\n")), MAX_SCAN)
        scan.report = text
        scan.preview = #previewLines > 0 and scrub(table.concat(previewLines, "\n")) or "(ninguno)"
        scan.status = "✅ " .. #list .. " grupos, " .. checked .. " objetos revisados. Copia o guarda el informe."
    end)

    scan.busy = false
    if not ok then scan.status = "⚠ Error: " .. tostring(err):sub(1, 70) end
end

-- Detalle objeto por objeto: árbol anidado con atributos y valores
local DETAIL_MAX = 60

local function describeLua(d, indent, depth, out, extra)
    local pad = string.rep("  ", indent)
    local f = { { "class", q(d.ClassName) }, { "name", q(d.Name) } }
    if extra then for _, kv in ipairs(extra) do f[#f + 1] = kv end end
    if d:IsA("ValueBase") then f[#f + 1] = { "value", valueLv(d) } end
    local okA, attrs = pcall(d.GetAttributes, d)
    if okA and attrs and next(attrs) then f[#f + 1] = { "attrs", lv(attrs) } end
    if depth <= 0 then out[#out + 1] = row(pad, f) return end

    local kids, counts, n = {}, {}, 0
    for _, c in ipairs(d:GetChildren()) do
        if c:IsA("ValueBase") or c:IsA("Folder") or c:IsA("Model") or c:IsA("Configuration")
            or c:IsA("Tool") or c:IsA("ProximityPrompt") then
            n += 1
            if n <= 25 then kids[#kids + 1] = c end
        else
            counts[c.ClassName] = (counts[c.ClassName] or 0) + 1
        end
    end
    local parts = {}
    for k, v in pairs(counts) do parts[#parts + 1] = k .. " = " .. v end
    table.sort(parts)
    local otherStr = #parts > 0 and ("{ " .. table.concat(parts, ", ") .. " }") or nil

    if n == 0 and not otherStr then
        out[#out + 1] = row(pad, f)
    else
        out[#out + 1] = rowOpen(pad, f)
        for _, k in ipairs(kids) do describeLua(k, indent + 1, depth - 1, out) end
        if n > 25 then out[#out + 1] = pad .. "  -- … (" .. (n - 25) .. " más)" end
        out[#out + 1] = pad .. "}" .. (otherStr and (", other = " .. otherStr) or "") .. " },"
    end
end

local function detailReport(filterText)
    local filter = (filterText or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local needles = filter ~= "" and { filter } or { "pet_", "heldpet_" }
    local qn = {}
    for _, nd in ipairs(needles) do qn[#qn + 1] = q(nd) end
    local out = startReport("DETALLE DE OBJETOS", ", needles = { " .. table.concat(qn, ", ") .. " }")
    out[#out + 1] = "INFO.details = {   -- cada objeto: path + árbol de contenedores (attrs, valores)"

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
                        local extra = { { "path", pathExpr(d) } }
                        if mine then extra[#extra + 1] = { "mine", "true" } end
                        local pos = posLv(d)
                        if pos then extra[#extra + 1] = { "pos", pos } end
                        describeLua(d, 1, 2, out, extra)
                    end
                end
            end
        end
    end
    out[#out + 1] = "}"
    out[#out + 1] = "INFO.detailsFound = " .. found .. (found > DETAIL_MAX and ("   -- mostrando " .. DETAIL_MAX .. "; usa un filtro más concreto") or "")
    out[#out + 1] = ""
    out[#out + 1] = "return INFO"
    return capText(scrub(table.concat(out, "\n")), MAX_SCAN), found
end

----------------------------------------------------------------
-- INFO ÚTIL (pestaña 📦)
----------------------------------------------------------------
local info = { busy = false, text = "", parts = {}, partIndex = 1, status = "Pulsa «Recopilar»." }

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

-- 1) REMOTES
local function collectRemotes()
    local found, n = {}, 0
    for _, root in ipairs({ ReplicatedStorage, ReplicatedFirst }) do
        for _, d in ipairs(root:GetDescendants()) do
            n += 1
            if n % 500 == 0 then task.wait() info.status = "Buscando remotes… " .. n end
            local cn = d.ClassName
            if cn == "RemoteEvent" or cn == "RemoteFunction" or cn == "UnreliableRemoteEvent" then
                found[#found + 1] = { inst = d, key = path(d), class = cn }
            end
        end
    end
    return found
end

local function secRemotes(out)
    local list = collectRemotes()
    table.sort(list, function(a, b) return a.key < b.key end)
    out[#out + 1] = "INFO.remotes = {   -- RemoteFunction -> :InvokeServer(...)  |  RemoteEvent -> :FireServer(...)  |  seen = veces capturado con 📡"
    for _, r in ipairs(list) do
        local seen = state.seen[r.key]
        out[#out + 1] = row("  ", {
            { "path", pathExpr(r.inst) }, { "class", q(r.class) }, { "seen", seen and tostring(seen) or nil },
        })
    end
    out[#out + 1] = "}"
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

local function ownerPat(inst)
    local o = inst and inst.Parent
    return q(namePattern(o and o.Name or "?"))
end

local function secInter(out, R)
    out[#out + 1] = "INFO.prompts = {   -- fireproximityprompt(<example>)"
    for _, key in ipairs(R.po) do
        local g = R.prompts[key]
        local p = g.p
        out[#out + 1] = row("  ", {
            { "action", q(p.ActionText) }, { "object", q(p.ObjectText) }, { "count", tostring(g.count) },
            { "hold", num(p.HoldDuration) }, { "distance", num(p.MaxActivationDistance) }, { "enabled", tostring(p.Enabled) },
            { "ownerPattern", ownerPat(p) }, { "example", pathExpr(p) }, { "pos", posLv(p) },
        })
    end
    out[#out + 1] = "}"
    out[#out + 1] = ""

    out[#out + 1] = "INFO.clicks = {   -- fireclickdetector(<example>)"
    for _, key in ipairs(R.co) do
        local g = R.clicks[key]
        out[#out + 1] = row("  ", {
            { "count", tostring(g.count) }, { "ownerPattern", ownerPat(g.p) },
            { "example", pathExpr(g.p) }, { "pos", posLv(g.p) },
        })
    end
    out[#out + 1] = "}"
    out[#out + 1] = ""

    out[#out + 1] = "INFO.touch = {   -- objetos con TouchInterest (coleccionables, zonas, puertas): firetouchinterest(hrp, example, 0/1)"
    for _, key in ipairs(R.to) do
        local g = R.touch[key]
        local owner = g.p.Parent or g.p
        out[#out + 1] = row("  ", {
            { "pattern", q(namePattern(owner.Name)) }, { "class", q(owner.ClassName) }, { "count", tostring(g.count) },
            { "example", pathExpr(owner) }, { "parent", pathExpr(owner.Parent) }, { "pos", posLv(owner) },
        })
    end
    out[#out + 1] = "}"
    out[#out + 1] = ""

    out[#out + 1] = "INFO.npcs = {   -- NPCs / enemigos (Humanoid)"
    for _, key in ipairs(R.no) do
        local g = R.npcs[key]
        local h = g.p
        local m = g.model or h
        local f = {
            { "pattern", q(namePattern(m.Name)) }, { "count", tostring(g.count) },
            { "health", lv(tryGet(function() return h.Health end)) },
            { "maxHealth", lv(tryGet(function() return h.MaxHealth end)) },
        }
        local okA, a = pcall(function() return m:GetAttributes() end)
        if okA and a and next(a) then f[#f + 1] = { "attrs", lv(a) } end
        f[#f + 1] = { "example", pathExpr(m) }
        f[#f + 1] = { "parent", pathExpr(m.Parent) }
        f[#f + 1] = { "pos", posLv(m) }
        out[#out + 1] = row("  ", f)
    end
    out[#out + 1] = "}"
    out[#out + 1] = ""

    out[#out + 1] = "INFO.attrs = {   -- objetos con atributos (IDs y datos): inst:GetAttribute(nombre)"
    for _, key in ipairs(R.ao) do
        local g = R.attrs[key]
        out[#out + 1] = row("  ", {
            { "pattern", q(namePattern(g.p.Name)) }, { "class", q(g.p.ClassName) }, { "count", tostring(g.count) },
            { "attrs", lv(g.a) }, { "example", pathExpr(g.p) }, { "parent", pathExpr(g.p.Parent) },
        })
    end
    out[#out + 1] = "}"
    out[#out + 1] = ""

    out[#out + 1] = "INFO.tags = {   -- CollectionService:GetTagged(tag)"
    local okT, tags = pcall(function() return CollectionService:GetAllTags() end)
    local shown = 0
    if okT and type(tags) == "table" then
        table.sort(tags)
        for _, tag in ipairs(tags) do
            local okG, tagged = pcall(function() return CollectionService:GetTagged(tag) end)
            if okG and #tagged > 0 then
                shown += 1
                if shown > 80 then out[#out + 1] = "  -- … (más)" break end
                out[#out + 1] = row("  ", { { "tag", q(tag) }, { "count", tostring(#tagged) }, { "example", pathExpr(tagged[1]) } })
            end
        end
    end
    out[#out + 1] = "}"
end

-- 4) INTERFAZ
local function secGui(out)
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then out[#out + 1] = "INFO.screens = {}   -- sin PlayerGui" return end

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
                        local rel = (path(c):gsub(prefix, ""))
                        local text = c:IsA("TextButton") and c.Text or ""
                        local key = normName(rel) .. "|" .. normName(text) .. "|" .. tostring(vis)
                        grp(btnGroups, border, key, 250, function()
                            return { inst = c, text = text, vis = vis, class = c.ClassName }
                        end)
                    elseif opts.labels and c:IsA("TextLabel") and c.Text ~= "" and #c.Text <= 50 then
                        local rel = (path(c):gsub(prefix, ""))
                        grp(lblGroups, lorder, normName(rel), 150, function() return { inst = c, text = c.Text } end)
                    end
                end
            end
        end
    end

    out[#out + 1] = "INFO.screens = {"
    for _, s in ipairs(screens) do
        out[#out + 1] = row("  ", { { "name", q(s.name) }, { "enabled", tostring(s.enabled) }, { "buttons", tostring(s.buttons) } })
    end
    out[#out + 1] = "}"
    out[#out + 1] = ""

    out[#out + 1] = "INFO.buttons = {   -- pulsar: firesignal(btn.Activated) o firesignal(btn.MouseButton1Click)"
    for _, key in ipairs(border) do
        local g = btnGroups[key]
        out[#out + 1] = row("  ", {
            { "class", q(g.class) }, { "text", q((g.text:gsub("\n", " ")):sub(1, 40)) }, { "visible", tostring(g.vis) },
            { "count", tostring(g.count) }, { "example", pathExpr(g.inst) },
            g.count > 1 and { "pattern", q(namePattern(g.inst.Name)) } or { "pattern", nil },
        })
    end
    out[#out + 1] = "}"

    if opts.labels then
        out[#out + 1] = ""
        out[#out + 1] = "INFO.labels = {   -- textos de la interfaz"
        for _, key in ipairs(lorder) do
            local g = lblGroups[key]
            out[#out + 1] = row("  ", { { "text", q((g.text:gsub("\n", " "))) }, { "count", tostring(g.count) }, { "example", pathExpr(g.inst) } })
        end
        out[#out + 1] = "}"
    end
end

-- 5) MIS DATOS (se usa también en «Ver mi personaje»)
local function secMine(out)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    out[#out + 1] = "INFO.me = {"
    out[#out + 1] = '  player = game:GetService("Players").LocalPlayer,'
    if hrp then out[#out + 1] = "  position = " .. lv(hrp.Position) .. "," end
    if hum then
        out[#out + 1] = "  humanoid = { health = " .. lv(tryGet(function() return hum.Health end))
            .. ", maxHealth = " .. lv(tryGet(function() return hum.MaxHealth end))
            .. ", walkSpeed = " .. lv(tryGet(function() return hum.WalkSpeed end))
            .. ", jumpPower = " .. lv(tryGet(function() return hum.JumpPower end)) .. " },"
    end
    local okP, pattrs = pcall(player.GetAttributes, player)
    if okP and pattrs and next(pattrs) then out[#out + 1] = "  attributes = " .. lv(pattrs) .. "," end

    -- Valores (leaderstats, Data, etc.) sin entrar en PlayerGui / Backpack
    local values, stack = {}, { player }
    while #stack > 0 and #values < 40 do
        local inst = table.remove(stack)
        for _, c in ipairs(inst:GetChildren()) do
            if c.Name ~= "PlayerGui" and c.Name ~= "Backpack" and c.Name ~= "PlayerScripts" then
                if c:IsA("ValueBase") then
                    if #values < 40 then values[#values + 1] = c end
                elseif c:IsA("Folder") or c:IsA("Configuration") then
                    stack[#stack + 1] = c
                end
            end
        end
    end
    out[#out + 1] = "  values = {"
    for _, v in ipairs(values) do
        out[#out + 1] = row("    ", { { "path", pathExpr(v) }, { "value", valueLv(v) } })
    end
    out[#out + 1] = "  },"

    out[#out + 1] = "  tools = {"
    local bp = player:FindFirstChildOfClass("Backpack")
    for _, pair in ipairs({ { bp, "Backpack" }, { char, "Character" } }) do
        local container = pair[1]
        if container then
            for _, t in ipairs(container:GetChildren()) do
                if t:IsA("Tool") then
                    local okA, a = pcall(t.GetAttributes, t)
                    out[#out + 1] = row("    ", {
                        { "name", q(t.Name) }, { "where", q(pair[2]) }, { "path", pathExpr(t) },
                        { "attrs", (okA and a and next(a)) and lv(a) or nil },
                    })
                end
            end
        end
    end
    out[#out + 1] = "  },"

    out[#out + 1] = "  characterChildren = {   -- hijos no-parte del personaje"
    if char then
        for _, c in ipairs(char:GetChildren()) do
            if not c:IsA("BasePart") and not c:IsA("Accessory") and not c:IsA("Humanoid") and not c:IsA("Tool") then
                local okA, a = pcall(c.GetAttributes, c)
                out[#out + 1] = row("    ", {
                    { "class", q(c.ClassName) }, { "name", q(c.Name) },
                    { "attrs", (okA and a and next(a)) and lv(a) or nil },
                })
            end
        end
    end
    out[#out + 1] = "  },"
    out[#out + 1] = "}"
end

local function myCharReport()
    local out = startReport("MI PERSONAJE")
    secMine(out)
    out[#out + 1] = ""
    out[#out + 1] = "return INFO"
    return scrub(table.concat(out, "\n"))
end

-- 6) JERARQUÍA: árbol anidado de contenedores (root + children), repetidos agrupados
local CONTAINER = {
    Folder = true, Model = true, Configuration = true, Tool = true, ModuleScript = true, Script = true,
    LocalScript = true, RemoteEvent = true, RemoteFunction = true, UnreliableRemoteEvent = true,
    BindableEvent = true, BindableFunction = true,
}
local OMIT = { Packages = true, _Index = true }

local function hierarchy(root, maxDepth, cap, skipSet, varName, out)
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
            if st.lines >= cap then
                out[#out + 1] = pad .. "-- … límite de " .. cap .. " líneas"
                break
            end
            st.lines += 1
            st.n += 1
            if st.n % 300 == 0 then task.wait() info.status = "Jerarquía… " .. st.lines .. " líneas" end
            local c = g.first
            local f = { { "class", q(c.ClassName) } }
            if g.count > 1 then
                f[#f + 1] = { "pattern", q(namePattern(c.Name)) }
                f[#f + 1] = { "count", tostring(g.count) }
                f[#f + 1] = { "example", q(c.Name) }
            else
                f[#f + 1] = { "name", q(c.Name) }
            end
            if c:IsA("ValueBase") then f[#f + 1] = { "value", valueLv(c) } end
            local omit = OMIT[c.Name]
            if omit then f[#f + 1] = { "omitted", "true" } end
            if not omit and depth < maxDepth and #c:GetChildren() > 0 then
                out[#out + 1] = rowOpen(pad, f)
                local o = node(c, depth + 1)
                out[#out + 1] = pad .. "}" .. (o and (", other = " .. o) or "") .. " },"
            else
                out[#out + 1] = row(pad, f)
            end
        end
        if next(other) then
            local parts = {}
            for k, v in pairs(other) do parts[#parts + 1] = k .. " = " .. v end
            table.sort(parts)
            return "{ " .. table.concat(parts, ", ") .. " }"
        end
        return nil
    end

    out[#out + 1] = varName .. " = { root = " .. pathExpr(root) .. ", children = {"
    local o = node(root, 1)
    out[#out + 1] = "}" .. (o and (", other = " .. o) or "") .. " }"
end

-- Construye el informe completo
local function buildInfo()
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
        funcs[#funcs + 1] = f .. " = " .. (env[f] ~= nil and "true" or "false")
    end
    local out = startReport("INFO ÚTIL", ", streaming = " .. tostring(streaming)
        .. ", executor = { " .. table.concat(funcs, ", ") .. " }")
    if streaming then
        out[#out + 1] = "-- ⚠ StreamingEnabled: solo se ve lo cercano al personaje; repite en otra zona si falta algo"
        out[#out + 1] = ""
    end

    local function run(name, fn)
        info.status = name .. "…"
        local ok, err = pcall(fn)
        if not ok then
            out[#out + 1] = "-- (error en «" .. name .. "»: " .. tostring(err):gsub("%s+", " "):sub(1, 80) .. ")"
        end
        out[#out + 1] = ""
    end

    if sec.remotes then run("Remotes", function() secRemotes(out) end) end
    if sec.caps and state.total > 0 then
        run("Capturas", function() capturesLines(out) end)
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
            hierarchy(Workspace, 3, 250, skipSet, "INFO.workspaceTree", out)
        end)
        run("Jerarquía de ReplicatedStorage", function()
            hierarchy(ReplicatedStorage, 6, 400, {}, "INFO.replicatedTree", out)
        end)
    end
    out[#out + 1] = "return INFO"

    return capText(scrub(table.concat(out, "\n")), MAX_INFO)
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
-- INTERFAZ (en un bloque para no pasar el límite de variables locales)
----------------------------------------------------------------
do
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

makeLabel(header, "📡 Capture + Scanner + Info v4", UDim2.new(1, -90, 0, 24), UDim2.new(0, 14, 0, 4), 16).Font = Enum.Font.GothamBold
makeLabel(header, "Informe en datos Lua · solo lee, no modifica", UDim2.new(1, -90, 0, 16), UDim2.new(0, 14, 0, 26), 11, C.Sub)
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
    "Genera datos Lua estructurados (INFO.remotes, INFO.prompts, INFO.npcs, INFO.buttons…) con rutas "
    .. "ya resueltas, listos para que una IA escriba el script. Los repetidos se agrupan con un pattern.",
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
end
