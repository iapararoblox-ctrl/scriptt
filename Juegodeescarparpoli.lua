--[[
  RIFT RECON UI — MOBILE
  - Layout responsive (se adapta a pantallas de móvil, vertical u horizontal)
  - Arrastrable con el dedo
  - Botones grandes para tocar
  - Guarda en /storage/emulated/0/Delta/Informaciónrecopilada/
--]]

local RS      = game:GetService("ReplicatedStorage")
local CS      = game:GetService("CollectionService")
local Players = game:GetService("Players")
local LP      = Players.LocalPlayer
local UIS     = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

-- =========================================================
-- CONFIG
-- =========================================================
local SAVE_FOLDERS = {
    "/storage/emulated/0/Delta/Informaciónrecopilada",
    "../Informaciónrecopilada",
    "Informaciónrecopilada",
    "Delta/Informaciónrecopilada",
}
local FILE_NAME     = "rift_capture_%s.txt"
local MAX_LINES     = 500
local HOOK_EXTRA    = true
local SCAN_ON_START = true

-- =========================================================
-- ESTADO
-- =========================================================
local State = {
    capturing = true,
    log       = {},
    hooks     = {},
    startedAt = os.time(),
}

-- =========================================================
-- UTILIDADES
-- =========================================================
local function ts()
    local t = os.date("*t")
    return string.format("%02d:%02d:%02d", t.hour, t.min, t.sec)
end

local function fmtVal(v)
    if typeof(v) == "Instance" then
        return v:GetFullName()
    elseif type(v) == "table" then
        local ok, s = pcall(function()
            return game:GetService("HttpService"):JSONEncode(v)
        end)
        if ok then return s end
        local parts = {}
        for k, val in pairs(v) do parts[#parts+1] = tostring(k).."="..tostring(val) end
        return "{"..table.concat(parts, ", ").."}"
    elseif typeof(v) == "Vector3" then
        return string.format("Vector3(%.1f,%.1f,%.1f)", v.X, v.Y, v.Z)
    else
        return tostring(v)
    end
end

-- =========================================================
-- UI RESPONSIVE PARA MÓVIL
-- =========================================================
local gui = Instance.new("ScreenGui")
gui.Name = "RiftReconUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
pcall(function() gui.Parent = CoreGui end)
if not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end

-- Tamaño relativo a la pantalla del móvil
local W, H = 0.92, 0.68          -- 92% ancho, 68% alto
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Size = UDim2.new(W, 0, H, 0)
panel.Position = UDim2.new(0.5, 0, 0.45, 0)
panel.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
panel.BorderSizePixel = 0
panel.Active = true
panel.Draggable = false          -- usamos drag manual táctil
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(90, 200, 255)
stroke.Thickness = 1.5
stroke.Parent = panel

-- ------------- HEADER -------------
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
title.Text = "RIFT RECON"
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

-- ------------- DRAG TÁCTIL -------------
do
    local dragging, dragStart, startPos
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = panel.Position
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
            local delta = input.Position - dragStart
            panel.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

-- ------------- ZONA LOG -------------
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -16, 1, -40 - 96)
scroll.Position = UDim2.new(0, 8, 0, 44)
scroll.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.ScrollingDirection = Enum.ScrollingDirection.Y
scroll.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
scroll.Parent = panel
Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 8)

local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 2)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = scroll

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 6)
pad.PaddingLeft = UDim.new(0, 8)
pad.PaddingRight = UDim.new(0, 8)
pad.PaddingBottom = UDim.new(0, 6)
pad.Parent = scroll

local function makeLine(text, color)
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(1, 0, 0, 0)
    lbl.AutomaticSize = Enum.AutomaticSize.Y
    lbl.Font = Enum.Font.Code
    lbl.TextSize = 12
    lbl.TextColor3 = color or Color3.fromRGB(200, 220, 255)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextYAlignment = Enum.TextYAlignment.Top
    lbl.TextWrapped = true
    lbl.Text = text
    lbl.Parent = scroll
    return lbl
end

-- ------------- BARRA DE BOTONES (2 filas para móvil) -------------
local bar = Instance.new("Frame")
bar.Size = UDim2.new(1, 0, 0, 92)
bar.Position = UDim2.new(0, 0, 1, -96)
bar.BackgroundTransparency = 1
bar.Parent = panel

local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.new(0.5, -8, 0, 40)
grid.CellPadding = UDim2.new(0, 6, 0, 6)
grid.SortOrder = Enum.SortOrder.LayoutOrder
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
    b.TextSize = 14
    b.BorderSizePixel = 0
    b.AutoButtonColor = true
    b.Parent = bar
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    return b
end

local btnToggle = makeBtn("⏸ Detener", Color3.fromRGB(80, 55, 40))
local btnClear  = makeBtn("🧹 Limpiar")
local btnSave   = makeBtn("💾 Guardar", Color3.fromRGB(30, 70, 45))
local btnCopy   = makeBtn("📋 Copiar")
local btnScan   = makeBtn("🔎 Escanear", Color3.fromRGB(40, 55, 80))
local btnReq    = makeBtn("📦 Require",  Color3.fromRGB(45, 45, 65))

-- =========================================================
-- LOG
-- =========================================================
local function pushLog(text, color)
    if not State.capturing and color ~= Color3.fromRGB(255, 180, 60) then return end
    local line = string.format("[%s] %s", ts(), text)
    table.insert(State.log, { t = line })
    if #State.log > MAX_LINES then
        table.remove(State.log, 1)
        local first = scroll:FindFirstChildOfClass("TextLabel")
        if first then first:Destroy() end
    end
    makeLine(line, color)
    task.defer(function()
        scroll.CanvasPosition = Vector2.new(0, scroll.AbsoluteCanvasSize.Y)
    end)
end

-- =========================================================
-- HOOKS
-- =========================================================
local function hookRemote(remote, label, isFunc)
    if not remote or State.hooks[remote] then return false end
    State.hooks[remote] = true

    if isFunc then
        local old = remote.InvokeServer
        remote.InvokeServer = function(self, ...)
            local args = {...}
            local pretty = {}
            for i = 1, #args do pretty[i] = fmtVal(args[i]) end
            pushLog(("[%s] INVOKE -> %s"):format(label, table.concat(pretty, " | ")),
                Color3.fromRGB(120, 200, 255))
            local ok, res = pcall(old, self, ...)
            if ok then
                if type(res) == "table" then
                    local parts, n = {}, 0
                    for k, v in pairs(res) do
                        n = n + 1
                        parts[#parts+1] = tostring(k).."="..fmtVal(v)
                        if n > 10 then parts[#parts+1] = "..."; break end
                    end
                    pushLog(("[%s] <- {%s}"):format(label, table.concat(parts, ", ")),
                        Color3.fromRGB(120, 255, 180))
                else
                    pushLog(("[%s] <- %s"):format(label, fmtVal(res)),
                        Color3.fromRGB(120, 255, 180))
                end
                return res
            else
                pushLog(("[%s] ERR <- %s"):format(label, tostring(res)),
                    Color3.fromRGB(255, 120, 120))
                return nil
            end
        end
    else
        local old = remote.FireServer
        remote.FireServer = function(self, ...)
            local args = {...}
            local pretty = {}
            for i = 1, #args do pretty[i] = fmtVal(args[i]) end
            pushLog(("[%s] FIRE -> %s"):format(label, table.concat(pretty, " | ")),
                Color3.fromRGB(255, 220, 120))
            return old(self, ...)
        end
    end
    return true
end

local function getNetworker()
    local pkg = RS:FindFirstChild("Packages")
    if not pkg then return nil end
    local idx = pkg:FindFirstChild("_Index")
    if not idx then return nil end
    for _, c in ipairs(idx:GetChildren()) do
        if c.Name:find("leifstout_networker") then
            local net = c:FindFirstChild("networker")
            if net and net:FindFirstChild("_remotes") then return net end
        end
    end
    return nil
end

local function installHooks()
    local net = getNetworker()
    if not net then
        pushLog("networker no encontrado", Color3.fromRGB(255, 100, 100))
        return false
    end
    local remotes = net:FindFirstChild("_remotes")
    if not remotes then return false end

    local okRift = false
    local rift = remotes:FindFirstChild("RiftService")
    if rift then
        if hookRemote(rift:FindFirstChild("RemoteEvent"),    "RiftEvent", false) then okRift = true end
        if hookRemote(rift:FindFirstChild("RemoteFunction"), "RiftFunc",  true)  then okRift = true end
        pushLog("RiftService hook OK", Color3.fromRGB(120, 255, 180))
    else
        pushLog("RiftService NO existe", Color3.fromRGB(255, 120, 120))
    end

    if HOOK_EXTRA then
        for _, name in ipairs({"GameService","EnemyService","EffectsService","CollectableService"}) do
            local svc = remotes:FindFirstChild(name)
            if svc then
                hookRemote(svc:FindFirstChild("RemoteEvent"),    name..".Event", false)
                hookRemote(svc:FindFirstChild("RemoteFunction"), name..".Func",  true)
            end
        end
        pushLog("Hooks extra OK", Color3.fromRGB(150, 200, 255))
    end
    return okRift
end

-- =========================================================
-- ESCANEOS
-- =========================================================
local function scanWorkspace()
    pushLog("=== SCAN WORKSPACE ===", Color3.fromRGB(180, 220, 255))
    local n = 0
    for _, d in ipairs(workspace:GetDescendants()) do
        local nm = d.Name:lower()
        if nm:find("rift") or nm:find("grieta") then
            local pos = d:IsA("BasePart") and (" pos="..tostring(d.Position)) or ""
            local attrs = ""
            for k, v in pairs(d:GetAttributes()) do attrs = attrs.." "..k.."="..tostring(v) end
            pushLog(("  %s [%s]%s%s"):format(d:GetFullName(), d.ClassName, pos, attrs),
                Color3.fromRGB(200, 230, 255))
            n = n + 1
        end
    end
    pushLog("Rift en workspace: "..n, Color3.fromRGB(180, 220, 255))
end

local function scanTags()
    pushLog("=== SCAN TAGS ===", Color3.fromRGB(180, 220, 255))
    local n = 0
    for _, tag in ipairs(CS:GetTags()) do
        local t = tag:lower()
        if t:find("rift") or t:find("grieta") then
            pushLog(("  TAG %s -> %d"):format(tag, #CS:GetTagged(tag)), Color3.fromRGB(255, 220, 150))
            n = n + 1
        end
    end
    pushLog("Tags rift: "..n, Color3.fromRGB(180, 220, 255))
end

local function scanGui()
    pushLog("=== SCAN GUI ===", Color3.fromRGB(180, 220, 255))
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg then return end
    local n = 0
    for _, d in ipairs(pg:GetDescendants()) do
        if d.Name:lower():find("rift") then
            pushLog(("  %s [%s] Vis=%s"):format(d:GetFullName(), d.ClassName, tostring(d.Visible)),
                Color3.fromRGB(200, 230, 255))
            n = n + 1
        end
    end
    pushLog("Rift en GUI: "..n, Color3.fromRGB(180, 220, 255))
end

local function tryRequires()
    pushLog("=== REQUIRES ===", Color3.fromRGB(180, 220, 255))
    local list = {
        {"RiftData",          function() return RS.Shared.Modules.Data.RiftData end},
        {"RiftServiceClient", function() return RS.Shared.Services.RiftService.RiftServiceClient end},
        {"RiftFade",          function() return RS.Shared.Modules.Game.RiftFade end},
        {"RiftBar",           function() return RS.Shared.UI.HUD.RiftBar end},
    }
    for _, e in ipairs(list) do
        local label, getter = e[1], e[2]
        local okI, inst = pcall(getter)
        if not okI or not inst then
            pushLog("  ✗ "..label, Color3.fromRGB(255, 120, 120))
        else
            local okM, mod = pcall(require, inst)
            if not okM then
                pushLog("  ✗ require "..label.." -> "..tostring(mod), Color3.fromRGB(255, 120, 120))
            else
                pushLog("  ✓ "..label.." ("..typeof(mod)..")", Color3.fromRGB(120, 255, 180))
                if type(mod) == "table" then
                    local count = 0
                    for k, v in pairs(mod) do
                        count = count + 1
                        pushLog(("      %s = %s"):format(tostring(k), typeof(v)),
                            Color3.fromRGB(160, 210, 255))
                        if count > 40 then
                            pushLog("      ...", Color3.fromRGB(160, 210, 255))
                            break
                        end
                    end
                end
            end
        end
    end
end

-- =========================================================
-- GUARDAR
-- =========================================================
local function buildText()
    local out = {}
    out[#out+1] = "=== RIFT RECON CAPTURE ==="
    out[#out+1] = "PlaceId: "..tostring(game.PlaceId)
    out[#out+1] = "JobId:   "..tostring(game.JobId)
    out[#out+1] = "Inicio:  "..os.date("%Y-%m-%d %H:%M:%S", State.startedAt)
    out[#out+1] = "Fin:     "..os.date("%Y-%m-%d %H:%M:%S")
    out[#out+1] = "Lineas:  "..tostring(#State.log)
    out[#out+1] = ""
    for _, l in ipairs(State.log) do out[#out+1] = l.t end
    return table.concat(out, "\n")
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
        if ok then saved = path break else errors[#errors+1] = folder.." -> "..tostring(err) end
    end
    if saved then
        pushLog("💾 "..saved, Color3.fromRGB(120, 255, 180))
    else
        pushLog("❌ No se pudo guardar", Color3.fromRGB(255, 120, 120))
        for _, e in ipairs(errors) do pushLog("   "..e, Color3.fromRGB(255, 150, 150)) end
    end
end

-- =========================================================
-- BOTONES
-- =========================================================
btnToggle.MouseButton1Click:Connect(function()
    State.capturing = not State.capturing
    if State.capturing then
        btnToggle.Text = "⏸ Detener"
        btnToggle.BackgroundColor3 = Color3.fromRGB(80, 55, 40)
        pushLog("▶ reanudado", Color3.fromRGB(255, 220, 120))
    else
        btnToggle.Text = "▶ Iniciar"
        btnToggle.BackgroundColor3 = Color3.fromRGB(30, 70, 45)
        pushLog("⏸ pausado", Color3.fromRGB(255, 220, 120))
    end
end)

btnClear.MouseButton1Click:Connect(function()
    State.log = {}
    for _, c in ipairs(scroll:GetChildren()) do
        if c:IsA("TextLabel") then c:Destroy() end
    end
    pushLog("🧹 limpio", Color3.fromRGB(255, 220, 120))
end)

btnSave.MouseButton1Click:Connect(saveToDisk)

btnCopy.MouseButton1Click:Connect(function()
    if setclipboard then
        pcall(setclipboard, buildText())
        pushLog("📋 copiado", Color3.fromRGB(120, 255, 180))
    else
        pushLog("❌ sin setclipboard", Color3.fromRGB(255, 120, 120))
    end
end)

btnScan.MouseButton1Click:Connect(function()
    scanWorkspace(); scanTags(); scanGui()
end)

btnReq.MouseButton1Click:Connect(tryRequires)

-- Minimizar / cerrar
local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    if minimized then
        panel.Size = UDim2.new(W, 0, 0, 40)
    else
        panel.Size = UDim2.new(W, 0, H, 0)
    end
    scroll.Visible = not minimized
    bar.Visible = not minimized
end)

closeBtn.MouseButton1Click:Connect(function() gui:Destroy() end)

-- =========================================================
-- ARRANQUE
-- =========================================================
pushLog("=== RIFT RECON (mobile) ===", Color3.fromRGB(120, 200, 255))
pushLog("PlaceId "..tostring(game.PlaceId), Color3.fromRGB(150, 200, 255))

local ok = installHooks()
title.Text = "RIFT RECON • "..(ok and "ON" or "read-only")

if SCAN_ON_START then
    task.spawn(function()
        task.wait(1)
        scanWorkspace(); scanTags(); scanGui(); tryRequires()
        pushLog("Listo. Juega la grieta.", Color3.fromRGB(120, 255, 180))
    end)
end

task.spawn(function()
    while gui.Parent do
        task.wait(25)
        if State.capturing then scanWorkspace() end
    end
end)
