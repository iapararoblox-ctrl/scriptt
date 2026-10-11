--[[
    AUTO FARM (hecho a partir de tu informe Eee.txt) — Delta Mobile/PC
    Rutas, atributos y nombres tomados tal cual del INFO.

    Funciones (cada una con su botón ON/OFF):
      1. Auto cobrar   -> toca el Hitbox de "Collect" de cada slot de TU plot (+ ClaimAllEarnings)
      2. Auto rebirth  -> Remotes.Server.Rebirth:FireServer()  (el servidor decide si te alcanza)
      3. Auto robar    -> va a los prompts "Steal?" del stage elegido y vuelve a colocar en tu plot
      4. Anti-AFK

    OJO: no capturaste llamadas con 📡, así que NO conozco los argumentos reales de los remotes.
    Aquí los remotes se llaman sin argumentos. Si alguno no hace nada, captura la acción
    (botón Marcar + 📡) y se ajusta con el argumento exacto.
    No se usan los remotes de Admin (Remotes.Admin.*).
]]

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local CFG = {
    collectEvery = 5,     -- segundos entre cobros
    rebirthEvery = 15,    -- segundos entre intentos de rebirth
    stealDelay   = 0.45,  -- espera tras cada robo
    placeDelay   = 0.35,  -- espera tras cada colocación
}

----------------------------------------------------------------
-- SERVICIOS Y RUTAS (del informe)
----------------------------------------------------------------
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser       = game:GetService("VirtualUser")
local CoreGui           = game:GetService("CoreGui")

local lp = Players.LocalPlayer
local Server = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Server")
local R = {
    ClaimAll = Server:WaitForChild("ClaimAllEarnings"),
    Rebirth  = Server:WaitForChild("Rebirth"),
}

local function hrp()
    local c = lp.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function myPlot()
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end
    for _, p in ipairs(plots:GetChildren()) do
        if p:GetAttribute("OwnerId") == lp.UserId then return p end
    end
end

local function tp(pos)
    local h = hrp()
    if h then h.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0)) end
end

local function fire(prompt)
    if fireproximityprompt then
        fireproximityprompt(prompt)
    else
        prompt:InputHoldBegin()
        task.wait(prompt.HoldDuration + 0.05)
        prompt:InputHoldEnd()
    end
end

local function touch(part)
    local h = hrp()
    if not h then return end
    if firetouchinterest then
        firetouchinterest(h, part, 0)
        task.wait()
        firetouchinterest(h, part, 1)
    else
        local back = h.CFrame
        h.CFrame = part.CFrame
        task.wait(0.15)
        h.CFrame = back
    end
end

----------------------------------------------------------------
-- ESTADO
----------------------------------------------------------------
local on = { collect = false, rebirth = false, steal = false, afk = true }
local stageName
local status = "Listo."

local function stages()
    local list = {}
    local s = workspace:FindFirstChild("Stages")
    if s then
        for _, st in ipairs(s:GetChildren()) do list[#list + 1] = st.Name end
    end
    table.sort(list)
    return list
end
local stageList = stages()
stageName = table.find(stageList, "Modern Bank") and "Modern Bank" or stageList[1] -- el informe muestra ahí los prompts "Steal?"

----------------------------------------------------------------
-- LÓGICA
----------------------------------------------------------------
-- 1) Cobrar: Collect.Hitbox de cada slot de mi plot
local function collectAll()
    local plot = myPlot()
    if not plot then status = "No encuentro tu plot (OwnerId)." return end
    local n = 0
    for _, d in ipairs(plot:GetDescendants()) do
        if d.Name == "Hitbox" and d:IsA("BasePart") and d.Parent and d.Parent.Name == "Collect" then
            touch(d)
            n += 1
        end
    end
    pcall(function() R.ClaimAll:FireServer() end)
    status = "Cobrado: " .. n .. " hitbox(es) + ClaimAllEarnings."
end

-- 3) Robar en un stage y colocar en mi plot
local function stealPrompts(stage)
    local out = {}
    local folder = workspace.Stages:FindFirstChild(stage)
    folder = folder and folder:FindFirstChild("Spawnpoints")
    if not folder then return out end
    for _, d in ipairs(folder:GetDescendants()) do
        if d:IsA("ProximityPrompt") and d.Enabled and d.ActionText == "Steal?" then
            out[#out + 1] = d
        end
    end
    return out
end

local function placeAll()
    local plot = myPlot()
    if not plot then return end
    for _, d in ipairs(plot:GetDescendants()) do
        if d:IsA("ProximityPrompt") and d.Enabled and d.ActionText == "Place" then
            local part = d.Parent
            if part and part:IsA("BasePart") then
                tp(part.Position)
                task.wait(0.15)
                fire(d)
                task.wait(CFG.placeDelay)
                return true
            end
        end
    end
    return false
end

local function stealLoopOnce()
    local list = stealPrompts(stageName)
    if #list == 0 then status = "Sin prompts 'Steal?' libres en " .. tostring(stageName) task.wait(2) return end
    local home = hrp() and hrp().Position
    for _, p in ipairs(list) do
        if not on.steal then break end
        local part = p.Parent
        if p.Enabled and part and part:IsA("BasePart") then
            status = "Robando en " .. stageName .. "…"
            tp(part.Position)
            task.wait(0.15)
            fire(p)
            task.wait(CFG.stealDelay)
            -- volver y colocar lo que llevo
            local plot = myPlot()
            if plot then
                placeAll()
            elseif home then
                tp(home)
            end
        end
    end
end

task.spawn(function() -- cobro
    while task.wait(CFG.collectEvery) do
        if on.collect then pcall(collectAll) end
    end
end)

task.spawn(function() -- rebirth
    while task.wait(CFG.rebirthEvery) do
        if on.rebirth then pcall(function() R.Rebirth:FireServer() end) end
    end
end)

task.spawn(function() -- robar
    while task.wait(0.5) do
        if on.steal then
            local ok, err = pcall(stealLoopOnce)
            if not ok then status = "Error: " .. tostring(err):sub(1, 60) task.wait(2) end
        end
    end
end)

lp.Idled:Connect(function() -- anti-AFK
    if on.afk then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end
end)

----------------------------------------------------------------
-- INTERFAZ
----------------------------------------------------------------
local parent
do
    local ok, ui = pcall(function() return gethui and gethui() end)
    parent = (ok and ui) or CoreGui
end
local old = parent:FindFirstChild("AutoFarmGUI")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn = "AutoFarmGUI", false
gui.Parent = parent

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(250, 292)
frame.Position = UDim2.new(0, 10, 0, 60)
frame.BackgroundColor3 = Color3.fromRGB(16, 18, 26)
frame.Active, frame.Draggable = true, true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)

local layout = Instance.new("UIListLayout", frame)
layout.Padding = UDim.new(0, 6)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
local pad = Instance.new("UIPadding", frame)
pad.PaddingTop, pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 8)

local function btn(text, color)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 38)
    b.BackgroundColor3 = color or Color3.fromRGB(44, 48, 64)
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font, b.TextSize, b.Text = Enum.Font.GothamBold, 13, text
    b.Parent = frame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    return b
end

local function toggle(label, key)
    local b = btn("")
    local function refresh()
        b.Text = label .. ": " .. (on[key] and "ON" or "OFF")
        b.BackgroundColor3 = on[key] and Color3.fromRGB(46, 160, 105) or Color3.fromRGB(44, 48, 64)
    end
    b.Activated:Connect(function() on[key] = not on[key] refresh() end)
    refresh()
end

toggle("💰 Auto cobrar", "collect")
toggle("🔁 Auto rebirth", "rebirth")
toggle("🕵 Auto robar", "steal")
toggle("😴 Anti-AFK", "afk")

local stageBtn = btn("")
local function refreshStage() stageBtn.Text = "Stage: " .. tostring(stageName) .. "  (toca para cambiar)" end
stageBtn.Activated:Connect(function()
    stageList = stages()
    if #stageList == 0 then return end
    local idx = table.find(stageList, stageName) or 0
    stageName = stageList[idx % #stageList + 1]
    refreshStage()
end)
refreshStage()

local stat = Instance.new("TextLabel")
stat.Size = UDim2.new(1, 0, 0, 44)
stat.BackgroundTransparency = 1
stat.TextColor3 = Color3.fromRGB(150, 158, 178)
stat.Font, stat.TextSize = Enum.Font.Gotham, 12
stat.TextWrapped = true
stat.Parent = frame

local close = btn("✕ Cerrar y detener", Color3.fromRGB(200, 70, 80))
close.Activated:Connect(function()
    on.collect, on.rebirth, on.steal = false, false, false
    gui:Destroy()
end)

task.spawn(function()
    while gui.Parent do
        stat.Text = status
        task.wait(0.5)
    end
end)
