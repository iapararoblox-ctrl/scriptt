--[[
    AUTO-RECOLECTOR v3 para "Fusiona cualquier cosa en Brainrot"
    Delta (Mobile/PC)

    NUEVO v3:
    - Pestaña 🛒 Brainrot: comprar salvajes (WildService.BuyPet) y fusionar (WildService.FuseWildPet)
      automático o manual, con filtro de monedas/s mínimas y límite por ronda.
    - Copiar última respuesta de compra/fusión para depurar.
    - Diagnóstico ampliado.

    Incluye todo lo de v2: 3 modos de posición, pisos a elegir, salto de corrales vacíos,
    totales, Anti-AFK, extras, botón flotante 💰, tecla F8, ajustes guardados.
]]

----------------------------------------------------------------
-- CONFIGURACIÓN
----------------------------------------------------------------
local GUI_NAME = "AutoCollectGUI"
local FILE     = "AutoCollect_" .. game.PlaceId .. ".json"
local HEADER_H = 46
local HOTKEY   = Enum.KeyCode.F8

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
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser       = game:GetService("VirtualUser")

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
local S = {
    Interval = 15,     -- segundos entre rondas de cobro
    Delay = 400,       -- ms entre corrales
    Mode = 1,          -- 1 teletransportar, 2 mi personaje, 3 colector
    ReturnBack = true,
    SkipEmpty = true,
    AntiAFK = true,
    Scale = 100,
    Skip = {},         -- pisos desactivados: { ["3"] = true }

    -- Tienda / fusión
    AutoBuy = false,
    AutoFuse = false,
    BuyMinExp = 0,     -- mínimo de monedas/s = 10^N (0 = sin filtro)
    BuyMax = 3,        -- compras máximas por ronda
    FuseMax = 3,       -- fusiones máximas por ronda
    ShopInterval = 5,  -- segundos entre rondas de tienda
}

pcall(function()
    if isfile and isfile(FILE) then
        local d = HttpService:JSONDecode(readfile(FILE))
        if type(d) == "table" then
            for k, v in pairs(S) do
                if type(d[k]) == type(v) then S[k] = d[k] end
            end
        end
    end
end)
S.Interval     = clamp(S.Interval, 2, 300)
S.Delay        = clamp(S.Delay, 2, 2000)
S.Mode         = clamp(math.floor(S.Mode), 1, 3)
S.Scale        = clamp(S.Scale, 70, 150)
S.BuyMinExp    = clamp(math.floor(S.BuyMinExp), 0, 40)
S.BuyMax       = clamp(math.floor(S.BuyMax), 1, 20)
S.FuseMax      = clamp(math.floor(S.FuseMax), 1, 20)
S.ShopInterval = clamp(S.ShopInterval, 1, 120)

local function save()
    pcall(function() writefile(FILE, HttpService:JSONEncode(S)) end)
end
local saveQueued = false
local function saveSoon()
    if saveQueued then return end
    saveQueued = true
    task.delay(1, function() saveQueued = false save() end)
end

----------------------------------------------------------------
-- UTILIDADES
----------------------------------------------------------------
local function ser(v, depth, maxDepth, maxEntries)
    depth, maxDepth, maxEntries = depth or 0, maxDepth or 3, maxEntries or 20
    local t = typeof(v)
    if t == "string" then
        return '"' .. (#v > 80 and (v:sub(1, 80) .. "…") or v) .. '"'
    elseif t == "number" or t == "boolean" or t == "nil" then
        return tostring(v)
    elseif t == "Instance" then
        return "<" .. v.ClassName .. ":" .. v.Name .. ">"
    elseif t == "table" then
        if depth >= maxDepth then return "{…}" end
        local parts, n = {}, 0
        for k, val in pairs(v) do
            n += 1
            if n > maxEntries then parts[#parts + 1] = "…" break end
            parts[#parts + 1] = "[" .. ser(k, depth + 1, maxDepth, maxEntries) .. "]=" .. ser(val, depth + 1, maxDepth, maxEntries)
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

-- Las monedas pueden venir como número o como texto "mantisa|exponente"
local function parseNum(v)
    if type(v) == "number" then return v end
    if type(v) == "string" then
        local m, e = v:match("^([%d%.]+)|(%-?%d+)$")
        if m then return tonumber(m) * 10 ^ tonumber(e) end
        return tonumber(v) or 0
    end
    return 0
end

local SUF = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
local function fmt(n)
    if n < 1000 then return string.format("%.0f", n) end
    local i = math.floor(math.log10(n) / 3)
    if i >= #SUF then return string.format("%.2e", n) end
    return string.format("%.2f %s", n / 10 ^ (i * 3), SUF[i + 1])
end

local function copyText(text)
    local copier = setclipboard or toclipboard
    return copier ~= nil and pcall(copier, text)
end

----------------------------------------------------------------
-- ESTADO
----------------------------------------------------------------
local running, enabled, busy, minimized = true, false, false, false
local connections = {}
local function track(c) table.insert(connections, c) return c end

local pens, lastScan = {}, 0
local stats = { ok = 0, empty = 0, err = 0, skipped = 0, rounds = 0, coins = 0, lastRound = 0, active = 0 }
local lastError, statusText = "", "Listo."
local diag = {}

local function pushDiag(line)
    table.insert(diag, scrub(line))
    if #diag > 12 then table.remove(diag, 1) end
end

----------------------------------------------------------------
-- REMOTES (Knit: ReplicatedStorage...Services.<Servicio>.RF.<Nombre>)
----------------------------------------------------------------
local index, indexed = {}, false
local function buildIndex()
    local n = 0
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        n += 1
        if n % 500 == 0 then task.wait() end
        if d.ClassName == "RemoteFunction" and d.Parent and d.Parent.Name == "RF" and d.Parent.Parent then
            index[d.Parent.Parent.Name .. "." .. d.Name] = d
        end
    end
    indexed = true
end

local function getRemote(service, name)
    local key = service .. "." .. name
    local r = index[key]
    if r and r.Parent then return r end
    if not indexed or not r then buildIndex() end
    return index[key]
end

----------------------------------------------------------------
-- CORRALES
----------------------------------------------------------------
local function isMine(inst)
    local cur = inst
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
        if n % 500 == 0 then task.wait() end
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

local function getHRP()
    local char = player.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

----------------------------------------------------------------
-- RECOLECCIÓN
----------------------------------------------------------------
local function cycle(keepGoing)
    local remote = getRemote("PenService", "CollectCoins")
    if not remote then lastError = "No encontré PenService.CollectCoins" return end
    if #pens == 0 or os.clock() - lastScan > 120 then scanPens() end
    if #pens == 0 then lastError = "No encontré tus corrales" return end

    local startHRP = getHRP()
    local origin = startHRP and startHRP.CFrame
    local roundCoins = 0

    for _, p in ipairs(pens) do
        if not running or not keepGoing() then break end
        if S.Skip[tostring(p.floor)] then continue end
        if S.SkipEmpty and p.emptyUntil and os.clock() < p.emptyUntil then
            stats.skipped += 1
            continue
        end

        local hrp = getHRP()
        local pos
        if S.Mode == 1 then
            if not hrp then lastError = "No hay personaje" break end
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.CFrame = p.collector.CFrame + Vector3.new(0, 3, 0)
            task.wait(0.12)
            pos = hrp.Position
        elseif S.Mode == 2 then
            pos = hrp and hrp.Position or p.collector.Position
        else
            pos = p.collector.Position
        end

        local ok, res = pcall(remote.InvokeServer, remote, p.id, pos)
        if not ok then
            stats.err += 1
            lastError = tostring(res):sub(1, 60)
            pushDiag(p.id .. " => ERROR: " .. tostring(res))
        elseif type(res) == "table" then
            if res.success then
                stats.ok += 1
                local c = parseNum(res.coins)
                stats.coins += c
                roundCoins += c
                p.emptyUntil = nil
            elseif res.error == "no_coins" then
                stats.empty += 1
                if parseNum(res.coinsPerSecond) == 0 then p.emptyUntil = os.clock() + 300 end
            else
                stats.err += 1
                lastError = tostring(res.error)
                pushDiag(p.id .. " => " .. ser(res, 0, 3, 12))
            end
        else
            stats.err += 1
            lastError = "respuesta inesperada"
            pushDiag(p.id .. " => " .. ser(res))
        end
        task.wait(S.Delay / 1000)
    end

    if S.Mode == 1 and S.ReturnBack and origin then
        local hrp = getHRP()
        if hrp then
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.CFrame = origin
        end
    end
    stats.rounds += 1
    stats.lastRound = roundCoins
end

local function runCycle(keepGoing)
    if busy then return end
    busy = true
    local ok, err = pcall(cycle, keepGoing)
    busy = false
    if not ok then
        lastError = tostring(err):sub(1, 60)
        pushDiag("CICLO => " .. tostring(err))
    end
end

----------------------------------------------------------------
-- TIENDA: comprar y fusionar salvajes
----------------------------------------------------------------
local shop = { bought = 0, fused = 0, fail = 0, rounds = 0, last = "—", lastBuyRaw = "", lastFuseRaw = "" }
local shopBusy = false

-- Busca recursivamente los salvajes dentro de la respuesta (estructura desconocida)
local function findPets(res)
    local out, seen = {}, {}
    local function walk(t, depth)
        if depth > 6 or type(t) ~= "table" or seen[t] then return end
        seen[t] = true
        if type(t.id) == "string" and (t.coinsPerSecond ~= nil or t.type ~= nil) then
            out[#out + 1] = t
            return
        end
        for _, v in pairs(t) do walk(v, depth + 1) end
    end
    walk(res, 0)
    return out
end

local function getWild()
    local r = getRemote("WildService", "GetAllWildPets")
    if not r then shop.last = "No encontré GetAllWildPets" return nil end
    local ok, res = pcall(r.InvokeServer, r)
    if not ok then
        shop.last = "Error: " .. tostring(res):sub(1, 40)
        pushDiag("WILD => " .. tostring(res))
        return nil
    end
    local minCps = S.BuyMinExp == 0 and 0 or 10 ^ S.BuyMinExp
    local out = {}
    for _, p in ipairs(findPets(res)) do
        local cps = parseNum(p.coinsPerSecond)
        if cps >= minCps then
            out[#out + 1] = { id = p.id, cps = cps, kind = tostring(p.type or "?") }
        end
    end
    table.sort(out, function(a, b) return a.cps > b.cps end)
    return out
end

local function buyOne(p)
    local r = getRemote("WildService", "BuyPet")
    if not r then shop.last = "No encontré BuyPet" return false end
    local ok, res = pcall(r.InvokeServer, r, p.id, false)
    shop.lastBuyRaw = scrub(ok and ser(res, 0, 4, 20) or tostring(res))
    if ok and type(res) == "table" and res.pet and not res.error then
        shop.bought += 1
        shop.last = "Compré " .. p.kind .. " (" .. fmt(p.cps) .. "/s)"
        return true
    end
    shop.fail += 1
    local why = ok and (type(res) == "table" and tostring(res.error) or ser(res)) or tostring(res)
    shop.last = "No compré: " .. why:sub(1, 40)
    pushDiag("BUY " .. p.id .. " => " .. shop.lastBuyRaw)
    return false
end

local function fuseOne(p)
    local r = getRemote("WildService", "FuseWildPet")
    if not r then shop.last = "No encontré FuseWildPet" return false end
    local ok, res = pcall(r.InvokeServer, r, p.id, false)
    shop.lastFuseRaw = scrub(ok and ser(res, 0, 4, 20) or tostring(res))
    if ok and type(res) == "table" and res.success then
        shop.fused += 1
        shop.last = "Fusioné " .. p.kind .. " (" .. fmt(p.cps) .. "/s)"
        return true
    end
    shop.fail += 1
    local why = ok and (type(res) == "table" and tostring(res.error) or ser(res)) or tostring(res)
    shop.last = "No fusioné: " .. why:sub(1, 40)
    pushDiag("FUSE " .. p.id .. " => " .. shop.lastFuseRaw)
    return false
end

-- Una pasada: recorre los salvajes (mejores primero) hasta el límite o 3 fallos seguidos
local function shopPass(action, limit)
    local list = getWild()
    if not list or #list == 0 then
        if list then shop.last = "Sin salvajes que cumplan el filtro" end
        return
    end
    local n, fails = 0, 0
    for _, p in ipairs(list) do
        if not running or n >= limit or fails >= 3 then break end
        if action(p) then n += 1 fails = 0 else fails += 1 end
        task.wait(0.35)
    end
end

local function runShop(doBuy, doFuse, buyLimit, fuseLimit)
    if shopBusy then return end
    shopBusy = true
    local ok, err = pcall(function()
        if doBuy then shopPass(buyOne, buyLimit) end
        if doFuse then shopPass(fuseOne, fuseLimit) end
        shop.rounds += 1
    end)
    shopBusy = false
    if not ok then
        shop.last = "Error: " .. tostring(err):sub(1, 40)
        pushDiag("TIENDA => " .. tostring(err))
    end
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

local function confirmable(btn, idleText, action)
    local armed = false
    local idleColor = btn.BackgroundColor3
    btn.Activated:Connect(function()
        if not armed then
            armed = true
            btn.Text = "¿Seguro? Toca otra vez"
            btn.BackgroundColor3 = C.Red
            task.delay(2.5, function()
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

----------------------------------------------------------------
-- INTERFAZ: ventana y pestañas
----------------------------------------------------------------
local layoutFrame -- se define abajo

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
local uiScale = Instance.new("UIScale", frame)

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, HEADER_H)
header.BackgroundColor3 = C.Card
header.BorderSizePixel = 0
header.Active = true
header.Parent = frame
local grad = Instance.new("UIGradient")
grad.Color = ColorSequence.new(Color3.fromRGB(60, 80, 160), C.Card)
grad.Parent = header

makeLabel(header, "💰 Auto-Recolector v3", UDim2.new(1, -90, 0, 24), UDim2.new(0, 14, 0, 4), 16).Font = Enum.Font.GothamBold
makeLabel(header, "Fusiona cualquier cosa en Brainrot", UDim2.new(1, -90, 0, 16), UDim2.new(0, 14, 0, 26), 11, C.Sub)
local minBtn   = makeButton(header, "–", UDim2.fromOffset(32, 32), UDim2.new(1, -78, 0.5, -16))
local closeBtn = makeButton(header, "✕", UDim2.fromOffset(32, 32), UDim2.new(1, -40, 0.5, -16), C.Red)

local body = Instance.new("Frame")
body.Size = UDim2.new(1, 0, 1, -HEADER_H)
body.Position = UDim2.new(0, 0, 0, HEADER_H)
body.BackgroundTransparency = 1
body.Parent = frame

local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -16, 0, 38)
tabBar.Position = UDim2.new(0, 8, 0, 8)
tabBar.BackgroundTransparency = 1
tabBar.Parent = body
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 5)
tabLayout.Parent = tabBar

local content = Instance.new("Frame")
content.Size = UDim2.new(1, -16, 1, -62)
content.Position = UDim2.new(0, 8, 0, 54)
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

local pageMain, pageShop, pageExtra, pageSet = newPage(), newPage(), newPage(), newPage()
local tabs = {}
local function selectTab(i)
    for idx, t in ipairs(tabs) do
        t.page.Visible = (idx == i)
        t.btn.BackgroundColor3 = (idx == i) and C.Accent or C.Card
        t.btn.TextColor3 = (idx == i) and Color3.fromRGB(255, 255, 255) or C.Sub
    end
end
local function addTab(text, page)
    local b = makeButton(tabBar, text, UDim2.new(0.25, -4, 1, 0), nil, C.Card)
    b.TextSize = 11
    table.insert(tabs, { btn = b, page = page })
    local idx = #tabs
    b.Activated:Connect(function() selectTab(idx) end)
end
addTab("💰 Cobrar", pageMain)
addTab("🛒 Brainrot", pageShop)
addTab("🧰 Extras", pageExtra)
addTab("⚙ Ajustes", pageSet)

local function card(parent, h)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, 0, 0, h)
    f.BackgroundColor3 = C.Card
    f.LayoutOrder = nextOrder()
    f.Parent = parent
    corner(f, 12)
    return f
end

local function bigButton(parent, text, color, h)
    local b = makeButton(parent, text, UDim2.new(1, 0, 0, h or 44), nil, color)
    b.LayoutOrder = nextOrder()
    return b
end

local function addToggle(parent, text, get, set)
    local b = bigButton(parent, "", C.Btn, 42)
    b.TextSize = 12
    local function r()
        b.Text = text .. ":  " .. (get() and "SÍ" or "NO")
        b.BackgroundColor3 = get() and C.Green or C.Btn
    end
    b.Activated:Connect(function() set(not get()) r() saveSoon() end)
    r()
    return r
end

local function addStepper(parent, text, get, set, mn, mx, step, suffix, show)
    local row = card(parent, 48)
    makeLabel(row, text, UDim2.new(1, -160, 1, 0), UDim2.new(0, 12, 0, 8), 13)
    local minus = makeButton(row, "–", UDim2.fromOffset(40, 36), UDim2.new(1, -152, 0.5, -18))
    local val = makeLabel(row, "", UDim2.fromOffset(56, 36), UDim2.new(1, -108, 0.5, -10), 13)
    val.TextXAlignment = Enum.TextXAlignment.Center
    val.Font = Enum.Font.GothamBold
    local plus = makeButton(row, "+", UDim2.fromOffset(40, 36), UDim2.new(1, -48, 0.5, -18))
    local function refresh()
        val.Text = show and show(get()) or (tostring(get()) .. (suffix or ""))
    end
    local function change(d) set(clamp(get() + d, mn, mx)) refresh() saveSoon() end
    minus.Activated:Connect(function() change(-step) end)
    plus.Activated:Connect(function() change(step) end)
    refresh()
end

-- Avisos flotantes
local toastLabel = Instance.new("TextLabel")
toastLabel.AnchorPoint = Vector2.new(0.5, 1)
toastLabel.Position = UDim2.new(0.5, 0, 1, -28)
toastLabel.Size = UDim2.fromOffset(0, 36)
toastLabel.AutomaticSize = Enum.AutomaticSize.X
toastLabel.BackgroundColor3 = C.Bg
toastLabel.BackgroundTransparency = 1
toastLabel.TextTransparency = 1
toastLabel.TextColor3 = C.Text
toastLabel.Font = Enum.Font.GothamBold
toastLabel.TextSize = 14
toastLabel.ZIndex = 50
toastLabel.Parent = gui
corner(toastLabel, 18)
local tp = Instance.new("UIPadding", toastLabel)
tp.PaddingLeft, tp.PaddingRight = UDim.new(0, 18), UDim.new(0, 18)
local toastStroke = Instance.new("UIStroke", toastLabel)
toastStroke.Color, toastStroke.Transparency, toastStroke.Thickness = C.Accent, 1, 1.5

local toastToken = 0
local function toast(text)
    toastToken += 1
    local my = toastToken
    toastLabel.Text = text
    local info = TweenInfo.new(0.2)
    TweenService:Create(toastLabel, info, { BackgroundTransparency = 0.1, TextTransparency = 0 }):Play()
    TweenService:Create(toastStroke, info, { Transparency = 0.2 }):Play()
    task.delay(2.4, function()
        if toastToken == my and toastLabel.Parent then
            TweenService:Create(toastLabel, info, { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
            TweenService:Create(toastStroke, info, { Transparency = 1 }):Play()
        end
    end)
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
local fst = Instance.new("UIStroke", floatBtn)
fst.Color, fst.Transparency, fst.Thickness = Color3.fromRGB(255, 255, 255), 0.2, 2

----------------------------------------------------------------
-- PESTAÑA 1: COBRAR
----------------------------------------------------------------
local mainBtn = bigButton(pageMain, "", C.Red, 52)
mainBtn.TextSize = 17
local function refreshMain()
    mainBtn.Text = enabled and "💰  ACTIVADO" or "💰  DESACTIVADO"
    mainBtn.BackgroundColor3 = enabled and C.Green or C.Red
    floatBtn.BackgroundColor3 = enabled and C.Green or C.Red
end
local function setEnabled(v)
    if not running then return end
    enabled = v
    refreshMain()
    toast(enabled and "💰 Recolección activada" or "Recolección detenida")
end
mainBtn.Activated:Connect(function() setEnabled(not enabled) end)

local statusCard = card(pageMain, 150)
local statusLabel = makeLabel(statusCard, "", UDim2.new(1, -20, 1, -12), UDim2.new(0, 10, 0, 6), 12)

local nowBtn = bigButton(pageMain, "▶  Recolectar ahora (1 ronda)", C.Accent, 44)
nowBtn.Activated:Connect(function()
    if busy then statusText = "Ya hay una ronda en curso." return end
    statusText = "Recolectando…"
    task.spawn(function()
        runCycle(function() return true end)
        statusText = "Ronda completada."
    end)
end)

local floorTag = makeLabel(pageMain, "PISOS A RECOLECTAR (toca para activar/desactivar)", UDim2.new(1, 0, 0, 30), nil, 11, C.Sub)
floorTag.Font = Enum.Font.GothamBold
floorTag.LayoutOrder = nextOrder()
local floorCard = card(pageMain, 50)
local floorGrid = Instance.new("UIGridLayout", floorCard)
floorGrid.CellSize = UDim2.fromOffset(56, 36)
floorGrid.CellPadding = UDim2.fromOffset(6, 6)
local floorPad = Instance.new("UIPadding", floorCard)
floorPad.PaddingTop, floorPad.PaddingLeft = UDim.new(0, 7), UDim.new(0, 8)

local function rebuildFloors()
    for _, c in ipairs(floorCard:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end
    local floors, seen = {}, {}
    for _, p in ipairs(pens) do
        if not seen[p.floor] then seen[p.floor] = true floors[#floors + 1] = p.floor end
    end
    table.sort(floors)
    for _, f in ipairs(floors) do
        local b = makeButton(floorCard, "P" .. f, UDim2.fromOffset(56, 36), nil, C.Green)
        local function r() b.BackgroundColor3 = S.Skip[tostring(f)] and C.Btn or C.Green end
        r()
        b.Activated:Connect(function()
            S.Skip[tostring(f)] = (not S.Skip[tostring(f)]) or nil
            r()
            saveSoon()
        end)
    end
    local rows = math.max(1, math.ceil(#floors / 5))
    floorCard.Size = UDim2.new(1, 0, 0, 14 + rows * 42)
end

local scanBtn = bigButton(pageMain, "🔎  Volver a buscar mis corrales", C.Btn, 40)
scanBtn.Activated:Connect(function()
    statusText = "Buscando corrales…"
    task.spawn(function()
        scanPens()
        rebuildFloors()
        statusText = "Encontré " .. #pens .. " corrales."
        toast("🔎 " .. #pens .. " corrales")
    end)
end)

local resetBtn = bigButton(pageMain, "🧹  Reiniciar contadores y corrales vacíos", C.Btn, 40)
resetBtn.TextSize = 12
resetBtn.Activated:Connect(function()
    for k in pairs(stats) do stats[k] = 0 end
    for _, p in ipairs(pens) do p.emptyUntil = nil end
    shop.bought, shop.fused, shop.fail, shop.rounds = 0, 0, 0, 0
    lastError = ""
    toast("Contadores reiniciados")
end)

----------------------------------------------------------------
-- PESTAÑA 2: BRAINROT (comprar / fusionar)
----------------------------------------------------------------
local shopCard = card(pageShop, 92)
local shopLabel = makeLabel(shopCard, "", UDim2.new(1, -20, 1, -12), UDim2.new(0, 10, 0, 6), 12)

addToggle(pageShop, "🛒 Comprar salvajes automático", function() return S.AutoBuy end, function(v) S.AutoBuy = v end)
addToggle(pageShop, "🧬 Fusionar salvajes automático", function() return S.AutoFuse end, function(v) S.AutoFuse = v end)

addStepper(pageShop, "Mín. monedas/s", function() return S.BuyMinExp end, function(v) S.BuyMinExp = v end, 0, 40, 1, "",
    function(v) return v == 0 and "todos" or ("1e" .. v) end)
addStepper(pageShop, "Compras por ronda", function() return S.BuyMax end, function(v) S.BuyMax = v end, 1, 20, 1, "")
addStepper(pageShop, "Fusiones por ronda", function() return S.FuseMax end, function(v) S.FuseMax = v end, 1, 20, 1, "")
addStepper(pageShop, "Cada cuántos segundos", function() return S.ShopInterval end, function(v) S.ShopInterval = v end, 1, 120, 1, " s")

local buyNowBtn = bigButton(pageShop, "🛒  Comprar el mejor salvaje (1 vez)", C.Accent, 42)
buyNowBtn.TextSize = 12
buyNowBtn.Activated:Connect(function()
    if shopBusy then toast("Espera, hay una ronda en curso") return end
    task.spawn(function() runShop(true, false, 1, 0) toast(shop.last) end)
end)

local fuseNowBtn = bigButton(pageShop, "🧬  Fusionar el mejor salvaje (1 vez)", C.Accent, 42)
fuseNowBtn.TextSize = 12
fuseNowBtn.Activated:Connect(function()
    if shopBusy then toast("Espera, hay una ronda en curso") return end
    task.spawn(function() runShop(false, true, 0, 1) toast(shop.last) end)
end)

local rawBtn = bigButton(pageShop, "📋  Copiar última respuesta de compra/fusión", C.Amber, 42)
rawBtn.TextSize = 12
rawBtn.Activated:Connect(function()
    local text = scrub("BuyPet:\n" .. (shop.lastBuyRaw ~= "" and shop.lastBuyRaw or "(nada)")
        .. "\n\nFuseWildPet:\n" .. (shop.lastFuseRaw ~= "" and shop.lastFuseRaw or "(nada)"))
    toast(copyText(text) and "📋 Respuestas copiadas" or "⚠ No se pudo copiar")
end)

local shopInfo = makeLabel(pageShop,
    "Los salvajes se ordenan por monedas/s (el mejor primero). Si 3 intentos seguidos fallan (sin dinero, lejos, etc.) la ronda se corta. Si algo no funciona, copia la última respuesta.",
    UDim2.new(1, 0, 0, 70), nil, 11, C.Sub)
shopInfo.LayoutOrder = nextOrder()

----------------------------------------------------------------
-- PESTAÑA 3: EXTRAS
----------------------------------------------------------------
addToggle(pageExtra, "Anti-AFK (evita que te expulsen)", function() return S.AntiAFK end, function(v) S.AntiAFK = v end)

local datosTag = makeLabel(pageExtra, "VER DATOS DEL JUEGO (se copian al portapapeles para pasármelos)", UDim2.new(1, 0, 0, 30), nil, 11, C.Sub)
datosTag.Font = Enum.Font.GothamBold
datosTag.LayoutOrder = nextOrder()

local function explore(service, name, label)
    task.spawn(function()
        local r = getRemote(service, name)
        if not r then toast("No encontré " .. service .. "." .. name) return end
        local ok, res = pcall(r.InvokeServer, r)
        local text = ok and ser(res, 0, 5, 60) or ("error: " .. tostring(res))
        text = scrub(label .. " (" .. service .. "." .. name .. "):\n" .. text)
        if #text > 20000 then text = text:sub(1, 20000) .. "\n… (recortado)" end
        if copyText(text) then
            toast("📋 Copiado: " .. label .. " (" .. #text .. " car.)")
        else
            toast("⚠ No se pudo copiar")
        end
    end)
end

local wildBtn = bigButton(pageExtra, "🔍  Ver salvajes (GetAllWildPets)", C.Accent, 42)
wildBtn.TextSize = 12
wildBtn.Activated:Connect(function() explore("WildService", "GetAllWildPets", "Salvajes") end)
local bagBtn = bigButton(pageExtra, "🎒  Ver mochila (GetBagData)", C.Accent, 42)
bagBtn.TextSize = 12
bagBtn.Activated:Connect(function() explore("BagService", "GetBagData", "Mochila") end)
local ranchBtn = bigButton(pageExtra, "🏠  Ver mis brainrots (GetAllRanchPets)", C.Accent, 42)
ranchBtn.TextSize = 12
ranchBtn.Activated:Connect(function() explore("PetService", "GetAllRanchPets", "Rancho") end)

local sellTag = makeLabel(pageExtra, "ACCIONES MANUALES", UDim2.new(1, 0, 0, 20), nil, 11, C.Sub)
sellTag.Font = Enum.Font.GothamBold
sellTag.LayoutOrder = nextOrder()
local sellBtn = bigButton(pageExtra, "💸  Vender el brainrot que llevo en la mano", C.Btn, 44)
sellBtn.TextSize = 12
confirmable(sellBtn, "💸  Vender el brainrot que llevo en la mano", function()
    task.spawn(function()
        local r = getRemote("NPCService", "ExecuteNPCAction")
        if not r then toast("No encontré NPCService.ExecuteNPCAction") return end
        local ok, res = pcall(r.InvokeServer, r, "petSeller", "sellHeldPet", nil)
        if ok and type(res) == "table" and res.success then
            toast("💸 Vendido: " .. fmt(parseNum(res.totalAmount)))
        else
            toast("⚠ No se vendió: " .. tostring(ok and (type(res) == "table" and res.error) or res):sub(1, 40))
            pushDiag("VENDER => " .. ser(res))
        end
    end)
end)

local diagBtn = bigButton(pageExtra, "📋  Copiar diagnóstico (si algo falla)", C.Amber, 44)
diagBtn.TextSize = 12
diagBtn.Activated:Connect(function()
    local lines = {
        "DIAGNÓSTICO Auto-Recolector v3",
        "Modo: " .. S.Mode .. " | Corrales: " .. #pens .. " | Rondas: " .. stats.rounds,
        "Cobradas: " .. stats.ok .. " | Vacías: " .. stats.empty .. " | Errores: " .. stats.err,
        "Último error: " .. (lastError ~= "" and lastError or "ninguno"),
        "Tienda: compras " .. shop.bought .. " | fusiones " .. shop.fused .. " | fallos " .. shop.fail,
        "Tienda último: " .. shop.last,
        "",
    }
    for _, l in ipairs(diag) do lines[#lines + 1] = l end
    if #diag == 0 then lines[#lines + 1] = "(sin errores guardados)" end
    local text = scrub(table.concat(lines, "\n"))
    toast(copyText(text) and "📋 Diagnóstico copiado" or "⚠ No se pudo copiar")
end)

----------------------------------------------------------------
-- PESTAÑA 4: AJUSTES
----------------------------------------------------------------
addStepper(pageSet, "Intervalo entre rondas", function() return S.Interval end, function(v) S.Interval = v end, 5, 300, 5, " s")
addStepper(pageSet, "Pausa entre corrales", function() return S.Delay end, function(v) S.Delay = v end, 100, 2000, 100, " ms")
addStepper(pageSet, "Tamaño de interfaz", function() return S.Scale end, function(v) S.Scale = v layoutFrame() end, 70, 150, 10, "%")

local modeBtn = bigButton(pageSet, "", C.Btn, 54)
modeBtn.TextSize = 12
modeBtn.TextWrapped = true
local modeNames = {
    "Posición: TELETRANSPORTAR al colector (recomendado)",
    "Posición: MI PERSONAJE (sin moverme, hay que estar cerca)",
    "Posición: COLECTOR (desde lejos, puede fallar)",
}
local function refreshMode() modeBtn.Text = modeNames[S.Mode] .. "\nToca para cambiar" end
modeBtn.Activated:Connect(function() S.Mode = S.Mode % 3 + 1 refreshMode() saveSoon() end)
refreshMode()

addToggle(pageSet, "Volver a mi posición al terminar (modo 1)", function() return S.ReturnBack end, function(v) S.ReturnBack = v end)
addToggle(pageSet, "Saltar corrales vacíos 5 min", function() return S.SkipEmpty end, function(v) S.SkipEmpty = v end)

local info = makeLabel(pageSet,
    "Tecla rápida en PC: F8. Si falla la recolección, prueba otro modo de posición y usa «Copiar diagnóstico» en Extras.",
    UDim2.new(1, 0, 0, 56), nil, 11, C.Sub)
info.LayoutOrder = nextOrder()

----------------------------------------------------------------
-- BUCLES
----------------------------------------------------------------
-- Recolección automática
task.spawn(function()
    while running do
        if enabled and not busy then
            runCycle(function() return enabled end)
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

-- Compra / fusión automática
task.spawn(function()
    while running do
        if (S.AutoBuy or S.AutoFuse) and not shopBusy then
            runShop(S.AutoBuy, S.AutoFuse, S.BuyMax, S.FuseMax)
            local waited = 0
            while running and (S.AutoBuy or S.AutoFuse) and waited < S.ShopInterval do
                task.wait(0.25)
                waited += 0.25
            end
        else
            task.wait(0.3)
        end
    end
end)

-- Estado en pantalla
task.spawn(function()
    local last = os.clock()
    while running do
        task.wait(0.5)
        local now = os.clock()
        if enabled then stats.active += now - last end
        last = now
        local perMin = stats.active > 5 and (stats.coins / (stats.active / 60)) or 0
        statusLabel.Text = string.format(
            "%s\nCorrales: %d | Rondas: %d%s\nCobradas: %d | Vacías: %d | Saltadas: %d | Errores: %d\n💰 Total sesión: %s\nÚltima ronda: %s | ≈ %s/min%s",
            statusText, #pens, stats.rounds, busy and " (en curso)" or "",
            stats.ok, stats.empty, stats.skipped, stats.err,
            fmt(stats.coins), fmt(stats.lastRound), fmt(perMin),
            lastError ~= "" and ("\n⚠ Último error: " .. lastError) or "")
        shopLabel.Text = string.format(
            "Compradas: %d | Fusionadas: %d | Fallos: %d\nRondas tienda: %d%s\nÚltimo: %s",
            shop.bought, shop.fused, shop.fail, shop.rounds, shopBusy and " (en curso)" or "", shop.last)
    end
end)

-- Anti-AFK
track(player.Idled:Connect(function()
    if S.AntiAFK then
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end
end))

-- Tecla rápida (PC)
track(UserInputService.InputBegan:Connect(function(input, processed)
    if not processed and input.KeyCode == HOTKEY then setEnabled(not enabled) end
end))

----------------------------------------------------------------
-- VENTANA
----------------------------------------------------------------
function layoutFrame()
    local cam = Workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(800, 600)
    local sc = S.Scale / 100
    uiScale.Scale = sc
    local w = clamp(vp.X * 0.92 / sc, 270, 350)
    local h = clamp(vp.Y * 0.82 / sc, 240, 520)
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
    S.AutoBuy, S.AutoFuse = false, false
    save()
    for _, c in ipairs(connections) do c:Disconnect() end
    gui:Destroy()
end)

----------------------------------------------------------------
-- INICIO
----------------------------------------------------------------
layoutFrame()
selectTab(1)
refreshMain()
task.spawn(function()
    scanPens()
    rebuildFloors()
    statusText = #pens > 0 and ("Listo. Encontré " .. #pens .. " corrales.")
        or "No encontré corrales. Pulsa «Volver a buscar»."
end)
