--[[
  RIFT CORE — solo grieta y portal
  - Hookea RiftService.RemoteEvent / RemoteFunction
  - Hookea GameService.RemoteEvent (para ver EnterPortal y compañía
  - Botones: EnterPortal, AutoPortal, RiftProbe, Guardar
  - Guarda en /storage/emulated/0/Delta/Informaciónrecopilada/
--]]

local RS      = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LP      = Players.LocalPlayer
local UIS     = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

-- ============ CONFIG ============
local SAVE_FOLDERS = {
    "/storage/emulated/0/Delta/Informaciónrecopilada",
    "../Informaciónrecopilada",
    "Informaciónrecopilada",
}
local FILE_NAME = "rift_%s.txt"
local MAX_LINES = 400
-- ================================

-- ============ REMOTES ============
local net = RS.Packages._Index["leifstout_networker@0.3.0"].networker
local R   = net._remotes

local RiftEvent  = R.RiftService.RemoteEvent
local RiftFunc   = R.RiftService.RemoteFunction
local GameEvent  = R.GameService.RemoteEvent
-- =================================

local State = {
    capturing  = true,
    log        = {},
    hooks      = {},
    startedAt  = os.time(),
    autoPortal = false,
}

-- ============ UTIL ============
local function ts()
    local t = os.date("*t")
    return string.format("%02d:%02d:%02d", t.hour, t.min, t.sec)
end

local function fmtVal(v)
    if typeof(v) == "Instance" then return v:GetFullName() end
    if type(v) == "table" then
        local ok, s = pcall(function()
            return game:GetService("HttpService"):JSONEncode(v)
        end)
        return ok and s or tostring(v)
    end
    if typeof(v) == "Vector3" then
        return string.format("V3(%.1f,%.1f,%.1f)", v.X, v.Y, v.Z)
    end
    return tostring(v)
end

-- ============ UI ============
local gui = Instance.new("ScreenGui")
gui.Name = "RiftCoreUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
pcall(function() gui.Parent = CoreGui end)
if not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end

local W, H = 0.94, 0.7
local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Size = UDim2.new(W, 0, H, 0)
panel.Position = UDim2.new(0.5, 0, 0.45, 0)
panel.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
panel.BorderSizePixel = 0
panel.Active = true
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
Instance.new("UIStroke", panel).Color = Color3.fromRGB(90, 200, 255)

-- HEADER
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 40)
header.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
header.BorderSizePixel = 0
header.Parent = panel
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -100, 1, 0)
title.Position = UDim2.new(0, 14, 0, 0)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextColor3 = Color3.fromRGB(90, 200, 255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "RIFT CORE"
title.Parent = header

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 40, 0, 30)
minBtn.Position = UDim2.new(1, -90, 0, 5)
minBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
minBtn.Text = "▁"
minBtn.TextColor3 = Color3.fromRGB(230, 230, 230)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 18
minBtn.BorderSizePixel = 0
minBtn.Parent = header
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 8)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 40, 0, 30)
closeBtn.Position = UDim2.new(1, -46, 0, 5)
closeBtn.BackgroundColor3 = Color3.fromRGB(70, 34, 34)
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(255, 200, 200)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 16
closeBtn.BorderSizePixel = 0
closeBtn.Parent = header
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)

-- DRAG táctil
do
    local dragging, dragStart, startPos
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging, dragStart, startPos = true, input.Position, panel.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseMovement then
            local d = input.Position - dragStart
            panel.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end

-- LOG
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -16, 1, -40 - 96)
scroll.Position = UDim2.new(0, 8, 0, 44)
scroll.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = panel
Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 8)

local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 2)
list.Parent = scroll

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 6)
pad.PaddingLeft = UDim.new(0, 8)
pad.PaddingRight = UDim.new(0, 8)
pad.PaddingBottom = UDim.new(0, 6)
pad.Parent = scroll

local function makeLine(text, color)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Size = UDim2.new(1, 0, 0, 0)
    l.AutomaticSize = Enum.AutomaticSize.Y
    l.Font = Enum.Font.Code
    l.TextSize = 12
    l.TextColor3 = color or Color3.fromRGB(200, 220, 255)
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Top
    l.TextWrapped = true
    l.Text = text
    l.Parent = scroll
    return l
end

-- BARRA DE BOTONES (2 filas x 2 columnas + fila simple)
local bar = Instance.new("Frame")
bar.Size = UDim2.new(1, 0, 0, 96)
bar.Position = UDim2.new(0, 0, 1, -100)
bar.BackgroundTransparency = 1
bar.Parent = panel

local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.new(0.5, -8, 0, 40)
grid.CellPadding = UDim2.new(0, 6, 0, 6)
grid.Parent = bar

local padBar = Instance.new("UIPadding")
padBar.PaddingLeft = UDim.new(0, 8)
padBar.PaddingRight = UDim.new(0, 8)
padBar.PaddingTop = UDim.new(0, 4)
padBar.PaddingBottom = UDim.new(0, 4)
padBar.Parent = bar

local function makeBtn(text, color)
    local b = Instance.new("TextButton")
    b.BackgroundColor3 = color or Color3.fromRGB(40, 40, 50)
    b.Text = text
    b.TextColor3 = Color3.fromRGB(235, 235, 245)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.BorderSizePixel = 0
    b.Parent = bar
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    return b
end

local btnEnter    = makeBtn("🚪 Enter Portal", Color3.fromRGB(60, 45, 80))
local btnAutoPort = makeBtn("⚡ AutoPortal OFF", Color3.fromRGB(45, 45, 55))
local btnProbe    = makeBtn("📡 Rift Probe",  Color3.fromRGB(50, 40, 70))
local btnInfo     = makeBtn("ℹ Estado Rift",  Color3.fromRGB(40, 55, 70))
local btnSave     = makeBtn("💾 Guardar",     Color3.fromRGB(30, 70, 45))
local btnClear    = makeBtn("🧹 Limpiar")

-- ============ LOG ============
local function pushLog(text, color)
    if not State.capturing and color ~= Color3.fromRGB(255, 180, 60) then return end
    local line = string.format("[%s] %s", ts(), text)
    table.insert(State.log, { t = line })
    if #State.log > MAX_LINES then
        table.remove(State.log, 1)
        local f = scroll:FindFirstChildOfClass("TextLabel")
        if f then f:Destroy() end
    end
    makeLine(line, color)
    task.defer(function()
        scroll.CanvasPosition = Vector2.new(0, scroll.AbsoluteCanvasSize.Y)
    end)
end

-- ============ HOOKS ============
local function hookRemote(remote, label, isFunc)
    if not remote or State.hooks[remote] then return false end
    State.hooks[remote] = true
    if isFunc then
        local old = remote.InvokeServer
        remote.InvokeServer = function(self, ...)
            local args = {...}
            local p = {}
            for i = 1, #args do p[i] = fmtVal(args[i]) end
            pushLog(("[%s] INVOKE -> %s"):format(label, table.concat(p, " | ")),
                Color3.fromRGB(120, 200, 255))
            local ok, res = pcall(old, self, ...)
            if ok then
                if type(res) == "table" then
                    local parts, n = {}, 0
                    for k, v in pairs(res) do
                        n = n + 1
                        parts[#parts+1] = tostring(k).."="..fmtVal(v)
                        if n > 8 then parts[#parts+1] = "..."; break end
                    end
                    pushLog(("[%s] <- {%s}"):format(label, table.concat(parts, ", ")),
                        Color3.fromRGB(120, 255, 180))
                else
                    pushLog(("[%s] <- %s"):format(label, fmtVal(res)),
                        Color3.fromRGB(120, 255, 180))
                end
                return res
            end
            pushLog(("[%s] ERR %s"):format(label, tostring(res)), Color3.fromRGB(255, 120, 120))
        end
    else
        local old = remote.FireServer
        remote.FireServer = function(self, ...)
            local args = {...}
            local p = {}
            for i = 1, #args do p[i] = fmtVal(args[i]) end
            pushLog(("[%s] FIRE -> %s"):format(label, table.concat(p, " | ")),
                Color3.fromRGB(255, 220, 120))
            return old(self, ...)
        end
    end
    return true
end

-- ============ ACCIONES ============
local function actEnter()
    GameEvent:FireServer("EnterPortal")
    pushLog("🚪 EnterPortal enviado", Color3.fromRGB(180, 255, 180))
end

local function actAutoPortal()
    State.autoPortal = not State.autoPortal
    if State.autoPortal then
        btnAutoPort.Text = "⚡ AutoPortal ON"
        btnAutoPort.BackgroundColor3 = Color3.fromRGB(70, 60, 90)
        pushLog("AutoPortal ON (esperando PortalOpen)", Color3.fromRGB(180, 200, 255))
        task.spawn(function()
            while State.autoPortal and gui.Parent do
                task.wait(0.5)
                local map = workspace:FindFirstChild("Map")
                local portal = map and map:FindFirstChild("BossPortal")
                if portal and portal:GetAttribute("PortalOpen") == true then
                    pcall(function() GameEvent:FireServer("EnterPortal") end)
                    pushLog("⚡ Portal abierto -> EnterPortal", Color3.fromRGB(180, 255, 180))
                    State.autoPortal = false
                    btnAutoPort.Text = "⚡ AutoPortal OFF"
                    btnAutoPort.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
                    break
                end
            end
        end)
    else
        btnAutoPort.Text = "⚡ AutoPortal OFF"
        btnAutoPort.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
        pushLog("AutoPortal OFF", Color3.fromRGB(180, 200, 255))
    end
end

local function actProbe()
    pushLog("📡 Probing RiftFunc...", Color3.fromRGB(180, 200, 255))
    local names = {
        "GetState","GetData","GetRiftData","GetInfo","Get",
        "FetchData","RequestState","QueryState","Sync","Status",
    }
    task.spawn(function()
        for _, name in ipairs(names) do
            local ok, res = pcall(function() return RiftFunc:InvokeServer(name) end)
            if ok then
                pushLog(("  ✓ %s -> %s %s"):format(name, typeof(res), tostring(res):sub(1, 80)),
                    Color3.fromRGB(120, 255, 180))
            else
                pushLog(("  ✗ %s -> %s"):format(name, tostring(res):sub(1, 60)),
                    Color3.fromRGB(255, 150, 150))
            end
            task.wait(0.2)
        end
        pushLog("📡 Probe terminado", Color3.fromRGB(180, 200, 255))
    end)
end

local function actInfo()
    pushLog("ℹ Estado actual", Color3.fromRGB(180, 200, 255))
    local map = workspace:FindFirstChild("Map")
    local portal = map and map:FindFirstChild("BossPortal")
    if portal then
        for k, v in pairs(portal:GetAttributes()) do
            pushLog(("  BossPortal.%s = %s"):format(k, tostring(v)),
                Color3.fromRGB(200, 230, 255))
        end
    else
        pushLog("  BossPortal no visible (streaming)", Color3.fromRGB(255, 200, 150))
    end
end

-- ============ GUARDAR ============
local function buildText()
    local o = {}
    o[#o+1] = "=== RIFT CORE CAPTURE ==="
    o[#o+1] = "PlaceId: "..tostring(game.PlaceId)
    o[#o+1] = "JobId:   "..tostring(game.JobId)
    o[#o+1] = "Inicio:  "..os.date("%Y-%m-%d %H:%M:%S", State.startedAt)
    o[#o+1] = "Fin:     "..os.date("%Y-%m-%d %H:%M:%S")
    o[#o+1] = "Lineas:  "..tostring(#State.log)
    o[#o+1] = ""
    for _, l in ipairs(State.log) do o[#o+1] = l.t end
    return table.concat(o, "\n")
end

local function saveToDisk()
    local content = buildText()
    local fname = string.format(FILE_NAME, os.date("%Y%m%d_%H%M%S"))
    local saved, errors = nil, {}
    for _, folder in ipairs(SAVE_FOLDERS) do
        local path = folder.."/"..fname
        local ok, err = pcall(function()
            if makefolder then pcall(makefolder, folder) end
            writefile(path, content)
        end)
        if ok then saved = path break
        else errors[#errors+1] = folder.." -> "..tostring(err) end
    end
    if saved then
        pushLog("💾 "..saved, Color3.fromRGB(120, 255, 180))
    else
        pushLog("❌ No se pudo guardar", Color3.fromRGB(255, 120, 120))
        for _, e in ipairs(errors) do pushLog("   "..e, Color3.fromRGB(255, 150, 150)) end
    end
end

-- ============ EVENTOS UI ============
btnEnter.MouseButton1Click:Connect(actEnter)
btnAutoPort.MouseButton1Click:Connect(actAutoPortal)
btnProbe.MouseButton1Click:Connect(actProbe)
btnInfo.MouseButton1Click:Connect(actInfo)
btnSave.MouseButton1Click:Connect(saveToDisk)
btnClear.MouseButton1Click:Connect(function()
    State.log = {}
    for _, c in ipairs(scroll:GetChildren()) do
        if c:IsA("TextLabel") then c:Destroy() end
    end
    pushLog("🧹 limpio", Color3.fromRGB(255, 220, 120))
end)

local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    panel.Size = minimized and UDim2.new(W, 0, 0, 40) or UDim2.new(W, 0, H, 0)
    scroll.Visible = not minimized
    bar.Visible = not minimized
end)
closeBtn.MouseButton1Click:Connect(function() gui:Destroy() end)

-- ============ ARRANQUE ============
pushLog("=== RIFT CORE ===", Color3.fromRGB(120, 200, 255))
pushLog("PlaceId "..tostring(game.PlaceId), Color3.fromRGB(150, 200, 255))

hookRemote(RiftEvent, "RiftEvent", false)
hookRemote(RiftFunc,  "RiftFunc",  true)
hookRemote(GameEvent, "GameEvent", false)
pushLog("Hooks: RiftEvent / RiftFunc / GameEvent", Color3.fromRGB(120, 255, 180))
pushLog("Listo. 🚪 para entrar, ⚡ para automático.", Color3.fromRGB(120, 255, 180))
