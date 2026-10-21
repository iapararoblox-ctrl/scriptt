-- Sesión de caza de bosses (TP): HE IRON TYRANT y Celestial Serpent
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local CONFIG = {
    DISTANCIA = 4,
    ALTURA = 0,
    ESPERA_CARGA_BOSS = 20,
    ESPERA_ATAQUE = 0.15,
    ESPERA_RESPAWN = 3,
    DEBUG = true,
}

local BOSSES = {
    {
        nombre = "HE IRON TYRANT",
        mar = "Ironbound",
        isla = "TheAnvil",
        ruta = { "World", "Dynamic", "Bosses", "Boss_IronTyrant" },
        parte = "captain",
    },
    {
        nombre = "Celestial Serpent",
        mar = "Celestial",
        isla = "AuroraRift",
        ruta = { "World", "Dynamic", "Bosses", "Boss_CelestialSerpent" },
        parte = "Head.Body",
    },
}

local bossIndex = 1
local cazando = false
local closed = false
local kills = 0
local statusText = "Listo"

---------------------------------------------------------------
-- UTILIDADES
---------------------------------------------------------------
local function setStatus(text)
    statusText = text
    if CONFIG.DEBUG then print("[BOSS]", text) end
end

local function getRoot()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getPath(parts)
    local obj = Workspace
    for _, name in ipairs(parts) do
        obj = obj and obj:FindFirstChild(name)
    end
    return obj
end

local function posOf(obj)
    if obj:IsA("Model") then
        return obj:GetPivot().Position
    end
    return obj.Position
end

local islaCache = {}
local function getIsla(nombre)
    local c = islaCache[nombre]
    if c and c.Parent then return c end
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if (obj:IsA("Model") or obj:IsA("BasePart")) and obj.Name == nombre then
            islaCache[nombre] = obj
            return obj
        end
    end
    return nil
end

local function getAnchor(boss, parteName)
    local carpeta = boss:FindFirstChild(parteName)
    if not carpeta then return nil end
    if carpeta:IsA("Model") or carpeta:IsA("BasePart") then
        return carpeta
    end
    local mejor, mejorVol = nil, -1
    for _, d in ipairs(carpeta:GetDescendants()) do
        if d:IsA("BasePart") then
            local vol = d.Size.X * d.Size.Y * d.Size.Z
            if vol > mejorVol then
                mejor, mejorVol = d, vol
            end
        end
    end
    return mejor
end

local function bossVivo(boss)
    if not boss or not boss.Parent then return false end
    local hum = boss:FindFirstChildWhichIsA("Humanoid", true)
    if hum and hum.Health <= 0 then return false end
    local hp = boss:GetAttribute("Health")
    if type(hp) == "number" and hp <= 0 then return false end
    return true
end

local function tpTo(cf)
    local root = getRoot()
    if not root then return false end
    root.AssemblyLinearVelocity = Vector3.zero
    root.CFrame = cf
    return true
end

local HOVER = "BossHover"
local function setHover(on)
    local root = getRoot()
    if not root then return end
    local old = root:FindFirstChild(HOVER)
    if on and not old then
        local bv = Instance.new("BodyVelocity")
        bv.Name = HOVER
        bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
        bv.Velocity = Vector3.zero
        bv.Parent = root
    elseif not on and old then
        old:Destroy()
    end
end

local function herramienta()
    local char = LocalPlayer.Character
    if not char then return nil end
    local t = char:FindFirstChildOfClass("Tool")
    if t then return t end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local mochila = LocalPlayer:FindFirstChildOfClass("Backpack")
    local nueva = mochila and mochila:FindFirstChildOfClass("Tool")
    if hum and nueva then
        pcall(function() hum:EquipTool(nueva) end)
        task.wait(0.25)
        return char:FindFirstChildOfClass("Tool")
    end
    return nil
end

local function cfAtaque(anchor)
    local pos = posOf(anchor)
    local p = pos + Vector3.new(0, CONFIG.ALTURA, CONFIG.DISTANCIA)
    return CFrame.lookAt(p, pos)
end

---------------------------------------------------------------
-- CAZA
---------------------------------------------------------------
local function cazar(b)
    setStatus("TP a " .. b.isla .. " (" .. b.mar .. ")...")
    local isla = getIsla(b.isla)
    if not isla then
        setStatus("No encuentro la isla " .. b.isla)
        cazando = false
        return
    end
    tpTo(CFrame.new(posOf(isla) + Vector3.new(0, 10, 0)))
    setHover(true)

    local boss, anchor
    local t0 = os.clock()
    while not closed and cazando and os.clock() - t0 < CONFIG.ESPERA_CARGA_BOSS do
        boss = getPath(b.ruta)
        anchor = boss and getAnchor(boss, b.parte)
        if anchor and bossVivo(boss) then break end
        setStatus("Esperando a " .. b.nombre .. "...")
        task.wait(0.5)
    end

    if not anchor then
        setStatus(b.nombre .. " no apareció. Revisa la ruta o la carpeta " .. b.parte)
        task.wait(2)
        return
    end

    while not closed and cazando do
        boss = getPath(b.ruta)
        anchor = boss and getAnchor(boss, b.parte)
        if not anchor or not bossVivo(boss) then break end

        local tool = herramienta()
        if not tool then
            setStatus("No tienes ninguna tool en la mano")
            cazando = false
            break
        end

        tpTo(cfAtaque(anchor))
        setStatus("Atacando " .. b.nombre)
        pcall(function() tool:Activate() end)
        task.wait(CONFIG.ESPERA_ATAQUE)
    end

    if cazando and not closed and boss and not bossVivo(boss) then
        kills += 1
        setStatus(b.nombre .. " derrotado (" .. kills .. ")")
        task.wait(CONFIG.ESPERA_RESPAWN)
    end
end

---------------------------------------------------------------
-- UI (compacta, táctil)
---------------------------------------------------------------
local BG = Color3.fromRGB(18, 20, 28)
local CARD = Color3.fromRGB(30, 33, 46)
local GREEN = Color3.fromRGB(80, 200, 130)
local RED = Color3.fromRGB(225, 85, 95)
local TEXT = Color3.fromRGB(240, 242, 250)
local MUTED = Color3.fromRGB(140, 146, 170)

local function mk(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end

local function crearGui()
    local gui = Instance.new("ScreenGui")
    gui.Name = "BossHunterUI"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 999
    gui.IgnoreGuiInset = true
    local ok = pcall(function()
        gui.Parent = game:GetService("CoreGui")
    end)
    if not ok or not gui.Parent then
        gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
    return gui
end

local bossBtn, toggleBtn, killsLbl, statusLbl

local function construirUI()
    local gui = crearGui()

    local main = mk("Frame", {
        Size = UDim2.fromOffset(150, 108),
        Position = UDim2.new(0, 8, 0.3, 0),
        BackgroundColor3 = BG,
        BorderSizePixel = 0,
        Active = true,
        Draggable = true,
    }, gui)
    mk("UICorner", { CornerRadius = UDim.new(0, 8) }, main)

    mk("TextLabel", {
        Size = UDim2.new(1, -28, 0, 14), Position = UDim2.new(0, 6, 0, 4),
        BackgroundTransparency = 1, Text = "Bosses", TextColor3 = TEXT,
        TextSize = 11, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left,
    }, main)

    statusLbl = mk("TextLabel", {
        Size = UDim2.new(1, -12, 0, 12), Position = UDim2.new(0, 6, 0, 18),
        BackgroundTransparency = 1, TextColor3 = MUTED, TextSize = 8,
        Font = Enum.Font.Gotham, TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, main)

    local function boton(pos, size, color, textSize, onClick)
        local b = mk("TextButton", {
            Position = pos, Size = size, BackgroundColor3 = color,
            TextColor3 = TEXT, TextSize = textSize, Font = Enum.Font.GothamBold, BorderSizePixel = 0,
        }, main)
        mk("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
        b.Activated:Connect(onClick)
        return b
    end

    bossBtn = boton(UDim2.new(0, 6, 0, 34), UDim2.new(1, -12, 0, 22), CARD, 9, function()
        bossIndex = bossIndex % #BOSSES + 1
    end)

    toggleBtn = boton(UDim2.new(0, 6, 0, 60), UDim2.new(1, -12, 0, 26), GREEN, 10, function()
        cazando = not cazando
        if not cazando then
            setHover(false)
            setStatus("Caza detenida")
        end
    end)

    killsLbl = mk("TextLabel", {
        Size = UDim2.new(1, -12, 0, 12), Position = UDim2.new(0, 6, 0, 90),
        BackgroundTransparency = 1, TextColor3 = TEXT, TextSize = 8, Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, main)

    local closeBtn = boton(UDim2.new(1, -20, 0, 3), UDim2.fromOffset(17, 17), RED, 9, function()
        closed = true
        cazando = false
        setHover(false)
        gui:Destroy()
    end)
    closeBtn.Text = "✕"
end

local okUI, errUI = pcall(construirUI)
if not okUI then
    warn("[BOSS] No se pudo crear la UI: " .. tostring(errUI))
end

---------------------------------------------------------------
-- BUCLE PRINCIPAL
---------------------------------------------------------------
task.spawn(function()
    while not closed do
        local b = BOSSES[bossIndex]
        if bossBtn then
            bossBtn.Text = b.nombre
            toggleBtn.Text = cazando and "■ Parar" or "▶ Cazar"
            toggleBtn.BackgroundColor3 = cazando and RED or GREEN
            statusLbl.Text = statusText
            killsLbl.Text = "Derrotados: " .. kills
        end

        if cazando then
            local ok, err = pcall(cazar, b)
            if not ok then
                setStatus("Error: " .. tostring(err))
                task.wait(2)
            end
        else
            setHover(false)
            task.wait(0.3)
        end
    end
end)
