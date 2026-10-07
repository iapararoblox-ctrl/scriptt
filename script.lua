-- Poly Loot Hub v3 (corregido para Delta)
-- Filtro de aliados/enemigos, escaner de mobs, ESP, retirada por vida, skills y mas.
if not game:IsLoaded() then game.Loaded:Wait() end

local function svc(n)
    local ok, s = pcall(function() return game:GetService(n) end)
    return ok and s or nil
end

local Players = svc("Players")
local UIS = svc("UserInputService")
local RunService = svc("RunService")
local TweenService = svc("TweenService")
local PPS = svc("ProximityPromptService")
local Lighting = svc("Lighting")
local VirtualUser = svc("VirtualUser")
local TeleportService = svc("TeleportService")
local VIM = svc("VirtualInputManager")
local LP = Players.LocalPlayer
while not LP do task.wait(0.1); LP = Players.LocalPlayer end

-- Conexiones globales (se limpian al cerrar o re-ejecutar)
local conns = {}
local function bind(sig, fn)
    local c = sig:Connect(fn)
    conns[#conns + 1] = c
    return c
end

-- Padre de la GUI: gethui -> CoreGui -> PlayerGui
local function candidates()
    local list = {}
    local ok, h = pcall(function() return gethui and gethui() end)
    if ok and h then list[#list + 1] = h end
    local ok2, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok2 and cg then list[#list + 1] = cg end
    local pg = LP:FindFirstChildOfClass("PlayerGui") or LP:WaitForChild("PlayerGui", 10)
    if pg then list[#list + 1] = pg end
    return list
end
for _, p in ipairs(candidates()) do
    pcall(function()
        local old = p:FindFirstChild("PolyLootHub")
        if old then old:Destroy() end
    end)
end

local function showError(msg)
    warn("[PolyLootHub] ERROR: " .. tostring(msg))
    pcall(function()
        for _, p in ipairs(candidates()) do
            local ok = pcall(function()
                local g = Instance.new("ScreenGui")
                g.Name = "PolyLootHubError"; g.ResetOnSpawn = false; g.Parent = p
                local l = Instance.new("TextLabel")
                l.Size = UDim2.new(1, -20, 0, 120); l.Position = UDim2.new(0, 10, 0, 10)
                l.BackgroundColor3 = Color3.fromRGB(60, 10, 10); l.TextColor3 = Color3.new(1, 1, 1)
                l.TextWrapped = true; l.TextSize = 13; l.TextXAlignment = Enum.TextXAlignment.Left
                l.TextYAlignment = Enum.TextYAlignment.Top
                l.Text = "PolyLootHub fallo:\n" .. tostring(msg); l.Parent = g
                task.delay(20, function() g:Destroy() end)
            end)
            if ok then break end
        end
    end)
end

local function main()
----------------------------------------------------------------------
-- ESTADO
----------------------------------------------------------------------
local S = {
    -- farm
    farm = false, autoEquip = true, clickVirtual = true,
    farmRange = 150, farmDist = 4, farmHeight = 0,
    farmPos = 1, priority = 1,
    retreat = false, retreatPct = 30,
    -- skills
    skillZ = false, skillX = false, skillC = false, skillV = false, skillF = false, skillDelay = 3,
    -- loot
    loot = false, lootRange = 30, instant = false, lootSkipNpc = true,
    lootTp = false, lootTpRange = 150,
    -- objetivos
    strict = false, esp = false, scanRange = 250,
    override = {},
    -- jugador
    speedOn = false, speed = 32, jumpOn = false, jump = 80,
    noclip = false, infJump = false, fly = false, flySpeed = 60,
    -- extras
    antiAfk = true, fullbright = false,
}

local POS_OPTIONS = {"Detras", "Encima", "Frente"}
local PRIO_OPTIONS = {"Mas cercano", "Menos vida", "Mas vida"}

local C = {
    bg = Color3.fromRGB(16, 16, 22),
    panel = Color3.fromRGB(25, 25, 35),
    item = Color3.fromRGB(34, 34, 48),
    accent = Color3.fromRGB(0, 220, 130),
    good = Color3.fromRGB(0, 220, 130),
    bad = Color3.fromRGB(255, 85, 100),
    text = Color3.fromRGB(235, 235, 245),
    dim = Color3.fromRGB(140, 140, 160),
    off = Color3.fromRGB(70, 70, 90),
}

----------------------------------------------------------------------
-- UTILIDADES
----------------------------------------------------------------------
local function new(class, props, children)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    for _, c in ipairs(children or {}) do c.Parent = o end
    return o
end
local function corner(r) return new("UICorner", {CornerRadius = UDim.new(0, r)}) end
local function stroke(col, t) return new("UIStroke", {Color = col, Thickness = t or 1, Transparency = 0.4}) end

local function getChar() return LP.Character end
local function getRoot() local c = LP.Character; return c and c:FindFirstChild("HumanoidRootPart") end
local function getHum() local c = LP.Character; return c and c:FindFirstChildOfClass("Humanoid") end

local function rootOf(m)
    return m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart or m:FindFirstChild("Torso")
        or m:FindFirstChild("UpperTorso") or m:FindFirstChildWhichIsA("BasePart")
end

local function makeDraggable(handle, target)
    local dragging, startPos, startInput = false, nil, nil
    handle.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; startPos = target.Position; startInput = i.Position
        end
    end)
    bind(UIS.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - startInput
            target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    bind(UIS.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
end

----------------------------------------------------------------------
-- REGISTRO DE HUMANOIDS Y PROMPTS (sin escanear el workspace cada ciclo)
----------------------------------------------------------------------
local Humanoids, Prompts = {}, {}
local function track(o)
    if o:IsA("Humanoid") then Humanoids[o] = true
    elseif o:IsA("ProximityPrompt") then Prompts[o] = true end
end
task.spawn(function()
    local n = 0
    for _, o in ipairs(workspace:GetDescendants()) do
        track(o)
        n = n + 1
        if n % 1500 == 0 then task.wait() end
    end
end)
bind(workspace.DescendantAdded, track)
bind(workspace.DescendantRemoving, function(o) Humanoids[o] = nil; Prompts[o] = nil end)

----------------------------------------------------------------------
-- CLASIFICACION ALIADO / ENEMIGO
----------------------------------------------------------------------
local OWNER_KEYS = {"owner", "master", "summoner", "creator", "player", "user", "tamer", "leader"}
local ALLY_WORDS = {"pet", "ally", "allies", "minion", "companion", "summon", "follower", "friend", "mascot", "squad", "party"}

local function hasWord(s, list)
    s = s:lower()
    for _, w in ipairs(list) do
        if s:find(w, 1, true) then return true end
    end
    return false
end

local function matchesMe(v)
    if v == nil then return false end
    if v == LP or v == LP.Character then return true end
    local t = typeof(v)
    if t == "string" then
        local l = v:lower()
        return l == LP.Name:lower() or l == LP.DisplayName:lower() or l == tostring(LP.UserId)
    end
    if t == "number" then return v == LP.UserId end
    return false
end

local function isAutoAlly(m)
    if m == LP.Character or Players:GetPlayerFromCharacter(m) then return true end
    local lname = LP.Name:lower()
    if m.Name:lower():find(lname, 1, true) or hasWord(m.Name, ALLY_WORDS) then return true end

    -- atributos con dueno
    for an, val in pairs(m:GetAttributes()) do
        if hasWord(an, OWNER_KEYS) and matchesMe(val) then return true end
    end
    -- valores hijos (ObjectValue / StringValue / IntValue...)
    for _, ch in ipairs(m:GetChildren()) do
        if ch:IsA("ObjectValue") then
            if matchesMe(ch.Value) then return true end
        elseif ch:IsA("StringValue") or ch:IsA("IntValue") or ch:IsA("NumberValue") then
            if hasWord(ch.Name, OWNER_KEYS) and matchesMe(ch.Value) then return true end
        end
    end
    -- carpetas padre (Pets, Allies, carpeta con tu nombre...)
    local a = m.Parent
    while a and a ~= workspace do
        if a.Name == LP.Name or hasWord(a.Name, ALLY_WORDS) then return true end
        a = a.Parent
    end
    return false
end

local allyCache = setmetatable({}, {__mode = "k"})
local function isAllyCached(m)
    local now = os.clock()
    local c = allyCache[m]
    if c and now - c.t < 3 then return c.v end
    local v = isAutoAlly(m)
    allyCache[m] = {t = now, v = v}
    return v
end

local function isEnemy(m)
    local ov = S.override[m.Name]
    if ov == "enemy" then return true end
    if ov == "ally" then return false end
    if S.strict then return false end
    return not isAllyCached(m)
end

----------------------------------------------------------------------
-- GUI BASE
----------------------------------------------------------------------
local Gui = new("ScreenGui", {Name = "PolyLootHub", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
do
    local placed = false
    for _, p in ipairs(candidates()) do
        if pcall(function() Gui.Parent = p end) and Gui.Parent then placed = true; break end
    end
    if not placed then error("No se pudo colocar la GUI en ningun contenedor") end
end

local Main = new("Frame", {
    Name = "Main", Parent = Gui, BackgroundColor3 = C.bg,
    Size = UDim2.new(0, 330, 0, 400), Position = UDim2.new(0.5, -165, 0.5, -200),
    BorderSizePixel = 0, ClipsDescendants = true,
}, {corner(14), stroke(C.accent, 1.5)})

local Header = new("Frame", {Parent = Main, BackgroundColor3 = C.panel, Size = UDim2.new(1, 0, 0, 44), BorderSizePixel = 0})
new("TextLabel", {
    Parent = Header, BackgroundTransparency = 1, Position = UDim2.new(0, 14, 0, 0), Size = UDim2.new(1, -110, 1, 0),
    Text = "POLY LOOT HUB v3", TextColor3 = C.accent, Font = Enum.Font.GothamBold, TextSize = 15,
    TextXAlignment = Enum.TextXAlignment.Left,
})
local MinBtn = new("TextButton", {
    Parent = Header, Text = "-", Font = Enum.Font.GothamBold, TextSize = 20, TextColor3 = C.text,
    BackgroundColor3 = C.item, Size = UDim2.new(0, 30, 0, 30), Position = UDim2.new(1, -74, 0, 7),
}, {corner(8)})
local CloseBtn = new("TextButton", {
    Parent = Header, Text = "X", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C.bad,
    BackgroundColor3 = C.item, Size = UDim2.new(0, 30, 0, 30), Position = UDim2.new(1, -38, 0, 7),
}, {corner(8)})
makeDraggable(Header, Main)

local Bubble = new("TextButton", {
    Parent = Gui, Text = "PL", Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = Color3.new(0, 0, 0),
    BackgroundColor3 = C.accent, Size = UDim2.new(0, 52, 0, 52), Position = UDim2.new(0, 16, 0.4, 0), Visible = false,
}, {corner(26), stroke(Color3.new(1, 1, 1), 2)})
makeDraggable(Bubble, Bubble)
MinBtn.MouseButton1Click:Connect(function() Main.Visible = false; Bubble.Visible = true end)
Bubble.MouseButton1Click:Connect(function() Main.Visible = true; Bubble.Visible = false end)
bind(UIS.InputBegan, function(i, gp)
    if not gp and i.KeyCode == Enum.KeyCode.RightShift then
        Main.Visible = not Main.Visible; Bubble.Visible = not Main.Visible
    end
end)

-- Aviso (toast)
local Toast = new("TextLabel", {
    Parent = Main, BackgroundColor3 = C.panel, TextColor3 = C.text, Font = Enum.Font.GothamMedium, TextSize = 12,
    Size = UDim2.new(1, -20, 0, 26), Position = UDim2.new(0, 10, 1, -36), Visible = false, ZIndex = 20,
}, {corner(8), stroke(C.accent)})
local toastId = 0
local function notify(t)
    toastId = toastId + 1
    local id = toastId
    Toast.Text = t; Toast.Visible = true
    task.delay(2.5, function() if id == toastId then Toast.Visible = false end end)
end

-- Pestanas
local TabBar = new("Frame", {Parent = Main, BackgroundTransparency = 1, Position = UDim2.new(0, 10, 0, 52), Size = UDim2.new(1, -20, 0, 30)},
    {new("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4)})})
local Pages, TabBtns = {}, {}

local function selectTab(name)
    for n, p in pairs(Pages) do p.Visible = (n == name) end
    for n, b in pairs(TabBtns) do
        TweenService:Create(b, TweenInfo.new(0.15), {
            BackgroundColor3 = (n == name) and C.accent or C.item,
            TextColor3 = (n == name) and Color3.new(0, 0, 0) or C.dim,
        }):Play()
    end
end

local function addTab(name)
    local btn = new("TextButton", {
        Parent = TabBar, Text = name, Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C.dim,
        BackgroundColor3 = C.item, Size = UDim2.new(0.2, -3, 1, 0),
    }, {corner(8)})
    local page = new("ScrollingFrame", {
        Parent = Main, BackgroundTransparency = 1, Position = UDim2.new(0, 10, 0, 90), Size = UDim2.new(1, -20, 1, -100),
        ScrollBarThickness = 3, ScrollBarImageColor3 = C.accent, CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, BorderSizePixel = 0, Visible = false,
    }, {new("UIListLayout", {Padding = UDim.new(0, 7)}), new("UIPadding", {PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 30)})})
    Pages[name], TabBtns[name] = page, btn
    btn.MouseButton1Click:Connect(function() selectTab(name) end)
    return page
end

----------------------------------------------------------------------
-- COMPONENTES
----------------------------------------------------------------------
local function addLabel(page, text)
    return new("TextLabel", {
        Parent = page, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), Text = text,
        TextColor3 = C.accent, Font = Enum.Font.GothamBold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
    })
end

local function addToggle(page, text, key, onChange)
    local row = new("TextButton", {Parent = page, Text = "", BackgroundColor3 = C.item, Size = UDim2.new(1, 0, 0, 38), AutoButtonColor = false}, {corner(10)})
    new("TextLabel", {
        Parent = row, BackgroundTransparency = 1, Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -70, 1, 0),
        Text = text, TextColor3 = C.text, Font = Enum.Font.GothamMedium, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
    })
    local track = new("Frame", {Parent = row, BackgroundColor3 = C.off, Size = UDim2.new(0, 38, 0, 20), Position = UDim2.new(1, -50, 0.5, -10)}, {corner(10)})
    local knob = new("Frame", {Parent = track, BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(0, 16, 0, 16), Position = UDim2.new(0, 2, 0.5, -8)}, {corner(8)})
    local function refresh()
        local on = S[key]
        TweenService:Create(track, TweenInfo.new(0.15), {BackgroundColor3 = on and C.accent or C.off}):Play()
        TweenService:Create(knob, TweenInfo.new(0.15), {Position = on and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)}):Play()
    end
    row.MouseButton1Click:Connect(function()
        S[key] = not S[key]; refresh()
        if onChange then onChange(S[key]) end
    end)
    refresh()
end

local function addSlider(page, text, min, max, key)
    local row = new("Frame", {Parent = page, BackgroundColor3 = C.item, Size = UDim2.new(1, 0, 0, 50)}, {corner(10)})
    local label = new("TextLabel", {
        Parent = row, BackgroundTransparency = 1, Position = UDim2.new(0, 12, 0, 3), Size = UDim2.new(1, -24, 0, 22),
        Text = text .. ": " .. S[key], TextColor3 = C.text, Font = Enum.Font.GothamMedium, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
    })
    local bar = new("Frame", {Parent = row, BackgroundColor3 = C.off, Position = UDim2.new(0, 12, 0, 33), Size = UDim2.new(1, -24, 0, 6)}, {corner(3)})
    local fill = new("Frame", {Parent = bar, BackgroundColor3 = C.accent, Size = UDim2.new((S[key] - min) / (max - min), 0, 1, 0)}, {corner(3)})
    local dragging = false
    local function set(x)
        local rel = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        local v = math.floor(min + (max - min) * rel + 0.5)
        S[key] = v; fill.Size = UDim2.new(rel, 0, 1, 0); label.Text = text .. ": " .. v
    end
    row.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = true; set(i.Position.X) end
    end)
    bind(UIS.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then set(i.Position.X) end
    end)
    bind(UIS.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
end

local function addCycle(page, text, options, key)
    local row = new("TextButton", {Parent = page, Text = "", BackgroundColor3 = C.item, Size = UDim2.new(1, 0, 0, 38), AutoButtonColor = false}, {corner(10)})
    new("TextLabel", {
        Parent = row, BackgroundTransparency = 1, Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(0.5, 0, 1, 0),
        Text = text, TextColor3 = C.text, Font = Enum.Font.GothamMedium, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
    })
    local val = new("TextLabel", {
        Parent = row, BackgroundTransparency = 1, Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(0.5, -12, 1, 0),
        Text = "", TextColor3 = C.accent, Font = Enum.Font.GothamBold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right,
    })
    local function refresh() val.Text = options[S[key]] end
    row.MouseButton1Click:Connect(function() S[key] = S[key] % #options + 1; refresh() end)
    refresh()
end

local function addButton(page, text, cb)
    local b = new("TextButton", {
        Parent = page, Text = text, Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = Color3.new(0, 0, 0),
        BackgroundColor3 = C.accent, Size = UDim2.new(1, 0, 0, 36),
    }, {corner(10)})
    b.MouseButton1Click:Connect(cb)
    return b
end

----------------------------------------------------------------------
-- PAGINAS
----------------------------------------------------------------------
local FarmPage = addTab("Farm")
local LootPage = addTab("Loot")
local MobsPage = addTab("Mobs")
local PlayerPage = addTab("Player")
local ExtraPage = addTab("Extras")

local savedCF, retreating = nil, false

-- FARM
addLabel(FarmPage, "COMBATE")
addToggle(FarmPage, "Auto Farm", "farm", function(on) if not on then retreating = false end end)
addToggle(FarmPage, "Auto equipar arma", "autoEquip")
addToggle(FarmPage, "Click virtual (si no hay arma)", "clickVirtual")
addCycle(FarmPage, "Posicion", POS_OPTIONS, "farmPos")
addCycle(FarmPage, "Prioridad", PRIO_OPTIONS, "priority")
addSlider(FarmPage, "Rango de busqueda", 20, 600, "farmRange")
addSlider(FarmPage, "Distancia al mob", 1, 15, "farmDist")
addSlider(FarmPage, "Altura extra", 0, 15, "farmHeight")
addLabel(FarmPage, "SUPERVIVENCIA")
addToggle(FarmPage, "Retirada con vida baja", "retreat")
addSlider(FarmPage, "Retirar bajo (%)", 10, 80, "retreatPct")
addButton(FarmPage, "Guardar posicion segura", function()
    local r = getRoot()
    if r then savedCF = r.CFrame; notify("Posicion guardada") end
end)
addLabel(FarmPage, "SKILLS AUTOMATICAS")
addToggle(FarmPage, "Skill Z", "skillZ")
addToggle(FarmPage, "Skill X", "skillX")
addToggle(FarmPage, "Skill C", "skillC")
addToggle(FarmPage, "Skill V", "skillV")
addToggle(FarmPage, "Skill F", "skillF")
addSlider(FarmPage, "Intervalo skills (s)", 1, 15, "skillDelay")

-- LOOT
addLabel(LootPage, "RECOGER ITEMS")
addToggle(LootPage, "Auto PickUp", "loot")
addToggle(LootPage, "Instant PickUp (sin espera)", "instant")
addToggle(LootPage, "Ignorar prompts de NPC", "lootSkipNpc")
addSlider(LootPage, "Rango de recogida", 5, 120, "lootRange")
addLabel(LootPage, "IR A LOS DROPS")
addToggle(LootPage, "Teletransportar a items", "lootTp")
addSlider(LootPage, "Rango de busqueda", 20, 500, "lootTpRange")

-- MOBS (escaner)
addLabel(MobsPage, "ENEMIGOS Y ALIADOS")
addToggle(MobsPage, "ESP (rojo=enemigo, verde=aliado)", "esp")
addToggle(MobsPage, "Modo estricto (solo marcados)", "strict")
addSlider(MobsPage, "Rango de escaneo", 30, 600, "scanRange")

local ScanBox = new("Frame", {
    Parent = nil, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
}, {new("UIListLayout", {Padding = UDim.new(0, 6)})})

local function stateInfo(name, autoAlly)
    local ov = S.override[name]
    if ov == "enemy" then return "ENEMIGO", C.bad end
    if ov == "ally" then return "ALIADO", C.good end
    if autoAlly then return "Auto: aliado", C.dim end
    return "Auto: enemigo", C.dim
end

local function addScanRow(name, g)
    local row = new("Frame", {Parent = ScanBox, BackgroundColor3 = C.item, Size = UDim2.new(1, 0, 0, 38)}, {corner(10)})
    new("TextLabel", {
        Parent = row, BackgroundTransparency = 1, Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(0.5, -12, 1, 0),
        Text = name .. "  x" .. g.count, TextColor3 = C.text, Font = Enum.Font.GothamMedium, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
    })
    local btn = new("TextButton", {
        Parent = row, Font = Enum.Font.GothamBold, TextSize = 11, BackgroundColor3 = C.panel,
        Size = UDim2.new(0.5, -10, 0, 26), Position = UDim2.new(0.5, 2, 0.5, -13), Text = "",
    }, {corner(8)})
    local function refresh()
        local t, col = stateInfo(name, g.ally)
        btn.Text = t; btn.TextColor3 = col
    end
    btn.MouseButton1Click:Connect(function()
        local ov = S.override[name]
        if ov == nil then S.override[name] = "enemy"
        elseif ov == "enemy" then S.override[name] = "ally"
        else S.override[name] = nil end
        refresh()
    end)
    refresh()
end

local function scan()
    for _, c in ipairs(ScanBox:GetChildren()) do
        if c:IsA("GuiObject") then c:Destroy() end
    end
    local root = getRoot()
    if not root then return end
    local groups, order = {}, {}
    for h in pairs(Humanoids) do
        local m = h.Parent
        if m and m:IsA("Model") and m ~= LP.Character and not Players:GetPlayerFromCharacter(m) then
            local r = rootOf(m)
            if r and (r.Position - root.Position).Magnitude <= S.scanRange then
                local g = groups[m.Name]
                if not g then
                    g = {count = 0, ally = isAutoAlly(m)}
                    groups[m.Name] = g
                    table.insert(order, m.Name)
                end
                g.count = g.count + 1
            end
        end
    end
    table.sort(order)
    for _, name in ipairs(order) do addScanRow(name, groups[name]) end
    notify(#order .. " tipos encontrados")
end

addButton(MobsPage, "Escanear cercanos", scan)
addButton(MobsPage, "Limpiar marcas", function() S.override = {}; scan() end)
addLabel(MobsPage, "Toca el estado para cambiarlo: Auto > Enemigo > Aliado")
ScanBox.Parent = MobsPage

-- PLAYER
addLabel(PlayerPage, "MOVIMIENTO")
addToggle(PlayerPage, "Velocidad", "speedOn")
addSlider(PlayerPage, "Valor velocidad", 16, 200, "speed")
addToggle(PlayerPage, "Salto alto", "jumpOn")
addSlider(PlayerPage, "Valor salto", 50, 300, "jump")
addToggle(PlayerPage, "Noclip", "noclip")
addToggle(PlayerPage, "Salto infinito", "infJump")
addToggle(PlayerPage, "Volar (saltar=subir, Ctrl=bajar)", "fly")
addSlider(PlayerPage, "Velocidad de vuelo", 20, 200, "flySpeed")

-- EXTRAS
addLabel(ExtraPage, "UTILIDADES")
addToggle(ExtraPage, "Anti-AFK", "antiAfk")
local oldLight = {Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime, FogEnd = Lighting.FogEnd, GlobalShadows = Lighting.GlobalShadows}
addToggle(ExtraPage, "Fullbright", "fullbright", function(on)
    if not on then for k, v in pairs(oldLight) do Lighting[k] = v end end
end)
addButton(ExtraPage, "Boost de FPS", function()
    pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
    for _, o in ipairs(workspace:GetDescendants()) do
        if o:IsA("BasePart") then o.Material = Enum.Material.SmoothPlastic; o.CastShadow = false
        elseif o:IsA("Decal") or o:IsA("Texture") then o.Transparency = 1
        elseif o:IsA("ParticleEmitter") or o:IsA("Trail") then o.Enabled = false end
    end
    notify("FPS boost aplicado")
end)
addButton(ExtraPage, "Reconectar al juego", function()
    TeleportService:Teleport(game.PlaceId, LP)
end)

selectTab("Farm")

CloseBtn.MouseButton1Click:Connect(function()
    for k, v in pairs(S) do if v == true then S[k] = false end end
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    Gui:Destroy()
end)

----------------------------------------------------------------------
-- LOGICA: FARM
----------------------------------------------------------------------
local currentTarget = nil
local visited = {}

local function pickTarget(root)
    local best, bestScore = nil, nil
    for h in pairs(Humanoids) do
        local m = h.Parent
        if m and h.Health > 0 and m:IsA("Model") and m ~= LP.Character then
            local r = rootOf(m)
            if r and isEnemy(m) then
                local d = (r.Position - root.Position).Magnitude
                if d <= S.farmRange then
                    local score = d
                    if S.priority == 2 then score = h.Health
                    elseif S.priority == 3 then score = -h.Health end
                    if bestScore == nil or score < bestScore then best, bestScore = m, score end
                end
            end
        end
    end
    return best
end

local function underHumanoidModel(p)
    local a = p.Parent
    while a and a ~= workspace do
        if a:IsA("Model") and a:FindFirstChildOfClass("Humanoid") then return true end
        a = a.Parent
    end
    return false
end

local function promptPos(p)
    local par = p.Parent
    if par:IsA("BasePart") then return par.Position end
    if par:IsA("Attachment") then return par.WorldPosition end
    local part = par:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position
end

local function goLoot(root)
    local best, bestD = nil, S.lootTpRange
    local now = os.clock()
    for p in pairs(Prompts) do
        if p.Enabled and not (visited[p] and now - visited[p] < 6) and not (S.lootSkipNpc and underHumanoidModel(p)) then
            local pos = promptPos(p)
            if pos then
                local d = (pos - root.Position).Magnitude
                if d < bestD and d > 4 then best, bestD = p, d end
            end
        end
    end
    if best then
        visited[best] = now
        root.CFrame = CFrame.new(promptPos(best) + Vector3.new(0, 3, 0))
    end
end

local function targetCFrame(tr)
    local up = Vector3.new(0, 1, 0)
    local cf
    if S.farmPos == 1 then cf = tr.CFrame * CFrame.new(0, S.farmHeight, S.farmDist)
    elseif S.farmPos == 2 then cf = tr.CFrame * CFrame.new(0, S.farmDist + S.farmHeight, 0); up = Vector3.new(0, 0, 1)
    else cf = tr.CFrame * CFrame.new(0, S.farmHeight, -S.farmDist) end
    return CFrame.lookAt(cf.Position, tr.Position, up)
end

task.spawn(function()
    while Gui.Parent do
        if S.farm then
            local ok, err = pcall(function()
                local root, hum = getRoot(), getHum()
                if not root or not hum or hum.Health <= 0 then currentTarget = nil; return end
                local hp = hum.Health / math.max(hum.MaxHealth, 1)

                if retreating then
                    if hp >= 0.9 then retreating = false; notify("Vida recuperada")
                    else currentTarget = nil; return end
                elseif S.retreat and savedCF and hp < S.retreatPct / 100 then
                    retreating = true; currentTarget = nil
                    root.CFrame = savedCF; notify("Retirada: vida baja"); return
                end

                local t = currentTarget
                if t then
                    local th, tr = t:FindFirstChildOfClass("Humanoid"), rootOf(t)
                    if not th or th.Health <= 0 or not tr or not t:IsDescendantOf(workspace)
                        or (tr.Position - root.Position).Magnitude > S.farmRange + 30 or not isEnemy(t) then
                        t = nil
                    end
                end
                if not t then t = pickTarget(root); currentTarget = t end

                if t then
                    local tr = rootOf(t)
                    root.CFrame = targetCFrame(tr)
                    root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)

                    local char = LP.Character
                    local tool = char:FindFirstChildOfClass("Tool")
                    if not tool and S.autoEquip then
                        local bp = LP:FindFirstChildOfClass("Backpack")
                        local tl = bp and bp:FindFirstChildOfClass("Tool")
                        if tl then hum:EquipTool(tl); tool = tl end
                    end
                    if tool then
                        tool:Activate()
                    elseif S.clickVirtual and VIM then
                        local cam = workspace.CurrentCamera
                        local c = cam and cam.ViewportSize / 2 or Vector2.new(300, 300)
                        VIM:SendMouseButtonEvent(c.X, c.Y, 0, true, game, 1)
                        VIM:SendMouseButtonEvent(c.X, c.Y, 0, false, game, 1)
                    end
                elseif S.lootTp then
                    goLoot(root)
                end
            end)
            if not ok then warn("[PolyLootHub] farm: " .. tostring(err)) end
        else
            currentTarget = nil
        end
        task.wait(0.08)
    end
end)

-- Skills automaticas (solo con objetivo activo)
local SKILL_KEYS = {
    {"skillZ", Enum.KeyCode.Z}, {"skillX", Enum.KeyCode.X}, {"skillC", Enum.KeyCode.C},
    {"skillV", Enum.KeyCode.V}, {"skillF", Enum.KeyCode.F},
}
task.spawn(function()
    local last = 0
    while Gui.Parent do
        if S.farm and currentTarget and os.clock() - last >= S.skillDelay then
            last = os.clock()
            for _, sk in ipairs(SKILL_KEYS) do
                if S[sk[1]] then
                    pcall(function()
                        if not VIM then return end
                        VIM:SendKeyEvent(true, sk[2], false, game)
                        task.wait(0.05)
                        VIM:SendKeyEvent(false, sk[2], false, game)
                    end)
                    task.wait(0.15)
                end
            end
        end
        task.wait(0.2)
    end
end)

----------------------------------------------------------------------
-- LOGICA: LOOT
----------------------------------------------------------------------
task.spawn(function()
    while Gui.Parent do
        if S.loot then
            pcall(function()
                local root = getRoot()
                if not root then return end
                for p in pairs(Prompts) do
                    if p.Enabled and not (S.lootSkipNpc and underHumanoidModel(p)) then
                        local pos = promptPos(p)
                        if pos and (pos - root.Position).Magnitude <= math.min(S.lootRange, p.MaxActivationDistance + 8) then
                            if S.instant then p.HoldDuration = 0 end
                            if fireproximityprompt then fireproximityprompt(p) end
                        end
                    end
                end
            end)
        end
        task.wait(0.35)
    end
end)

bind(PPS.PromptShown, function(prompt)
    if S.instant then prompt.HoldDuration = 0 end
end)

----------------------------------------------------------------------
-- LOGICA: ESP
----------------------------------------------------------------------
local espFolder = new("Folder", {Name = "ESP", Parent = Gui})
local highlights = {}
task.spawn(function()
    while Gui.Parent do
        if S.esp then
            local root = getRoot()
            local used, n = {}, 0
            if root then
                for h in pairs(Humanoids) do
                    local m = h.Parent
                    if n < 28 and m and m:IsA("Model") and h.Health > 0 and m ~= LP.Character and not Players:GetPlayerFromCharacter(m) then
                        local r = rootOf(m)
                        if r and (r.Position - root.Position).Magnitude <= 300 then
                            local hl = highlights[m]
                            if not hl then
                                hl = new("Highlight", {
                                    Parent = espFolder, Adornee = m, FillTransparency = 0.6, OutlineTransparency = 0,
                                    DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
                                })
                                highlights[m] = hl
                            end
                            local col = isEnemy(m) and C.bad or C.good
                            hl.FillColor = col; hl.OutlineColor = col
                            used[m] = true; n = n + 1
                        end
                    end
                end
            end
            for m, hl in pairs(highlights) do
                if not used[m] then hl:Destroy(); highlights[m] = nil end
            end
        else
            for m, hl in pairs(highlights) do hl:Destroy(); highlights[m] = nil end
        end
        task.wait(0.7)
    end
end)

----------------------------------------------------------------------
-- LOGICA: JUGADOR
----------------------------------------------------------------------
bind(RunService.Stepped, function()
    if S.noclip and LP.Character then
        for _, p in ipairs(LP.Character:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
    end
    if S.fullbright then
        Lighting.Brightness = 2; Lighting.ClockTime = 14; Lighting.FogEnd = 1e6; Lighting.GlobalShadows = false
    end
end)

bind(RunService.Heartbeat, function()
    local hum, root = getHum(), getRoot()
    if not hum or not root then return end
    if S.speedOn then hum.WalkSpeed = S.speed end
    if S.jumpOn then hum.UseJumpPower = true; hum.JumpPower = S.jump end
    if S.fly and not (S.farm and currentTarget) then
        local cam = workspace.CurrentCamera
        local vy = 0
        if hum.Jump or UIS:IsKeyDown(Enum.KeyCode.Space) then vy = S.flySpeed
        elseif UIS:IsKeyDown(Enum.KeyCode.LeftControl) then vy = -S.flySpeed end
        local dir = hum.MoveDirection
        root.AssemblyLinearVelocity = Vector3.new(dir.X * S.flySpeed, vy, dir.Z * S.flySpeed)
    end
end)

bind(UIS.JumpRequest, function()
    if S.infJump then
        local hum = getHum()
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end)

bind(LP.Idled, function()
    if S.antiAfk then
        if VirtualUser then VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new()) end
    end
end)

notify("Hub cargado. Usa la pestana Mobs para marcar aliados")

end

local ok, err = xpcall(main, debug.traceback)
if not ok then showError(err) end
