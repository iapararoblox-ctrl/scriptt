-- Caza de bosses (TP): HE IRON TYRANT y Celestial Serpent
-- Botín de World.Dynamic.Loot llevado al barco; primero deposita el cofre que quede en la mano
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

local CONFIG = {
    DISTANCIA = 4,
    ALTURA_MIN = -20,
    ALTURA_MAX = 40,
    LADO_MIN = -30,
    LADO_MAX = 30,
    PASO = 1,
    ARCHIVO = "BossConfig.json",
    ESPERA_STREAMING = 2,
    ESPERA_CARGA_BOSS = 20,
    ESPERA_ATAQUE = 0.15,
    ESPERA_RESPAWN = 3,
    ESPERA_BOTIN = 12,
    CAPACIDAD = 81,
    ALTURA_COFRE = 3,
    ALTURA_BARCO = 0,
    ESPERA_POSICION = 0.25,
    ESPERA_RECOGER = 0.3,
    INTENTOS_RECOGER = 2,
    ESPERA_GUARDADO = 3,
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
local botinRecogido = 0
local statusText = "Listo"
local objetivoCF = nil
local cachedShip = nil

---------------------------------------------------------------
-- AJUSTES (altura y lado por boss, botón de botín) guardados en archivo
---------------------------------------------------------------
local ajustes = {}
pcall(function()
    if readfile and isfile and isfile(CONFIG.ARCHIVO) then
        local d = HttpService:JSONDecode(readfile(CONFIG.ARCHIVO))
        if type(d) == "table" then ajustes = d end
    end
end)

local function ajusteDe(b)
    if not ajustes[b.nombre] then
        ajustes[b.nombre] = { altura = 0, lado = 0 }
    end
    return ajustes[b.nombre]
end

local function botinActivo()
    return ajustes._botin ~= false
end

local function guardarAjustes()
    if not writefile then return end
    pcall(function()
        writefile(CONFIG.ARCHIVO, HttpService:JSONEncode(ajustes))
    end)
end

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
    if obj:IsA("Model") then return obj:GetPivot().Position end
    if obj:IsA("BasePart") then return obj.Position end
    for _, d in ipairs(obj:GetDescendants()) do
        if d:IsA("BasePart") then return d.Position end
    end
    return nil
end

local function tpTo(cf)
    local root = getRoot()
    if not root then return end
    root.AssemblyLinearVelocity = Vector3.zero
    root.CFrame = cf
    task.wait(0.2)
end

-- Solo mientras hay un boss vivo: deja al personaje en el objetivo
RunService.Heartbeat:Connect(function()
    if not objetivoCF then return end
    local root = getRoot()
    if root then
        root.AssemblyLinearVelocity = Vector3.zero
        root.CFrame = objetivoCF
    end
end)

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

local function fmt(v)
    return string.format("%.0f,%.0f,%.0f", v.X, v.Y, v.Z)
end

---------------------------------------------------------------
-- ISLAS
---------------------------------------------------------------
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

local function islandTop(island)
    if island:IsA("Model") then
        local cf, size = island:GetBoundingBox()
        return cf.Position + Vector3.new(0, size.Y / 2 + 5, 0)
    end
    return island.Position + Vector3.new(0, island.Size.Y / 2 + 5, 0)
end

---------------------------------------------------------------
-- BOSS
---------------------------------------------------------------
local function posicionBoss(b)
    local boss = getPath(b.ruta)
    if not boss then return nil, nil end

    local suma, n = Vector3.zero, 0
    local carpeta = boss:FindFirstChild(b.parte)
    if carpeta then
        if carpeta:IsA("BasePart") or carpeta:IsA("Model") then
            suma += posOf(carpeta)
            n += 1
        else
            for _, d in ipairs(carpeta:GetDescendants()) do
                if d:IsA("BasePart") then
                    suma += d.Position
                    n += 1
                end
            end
        end
    end

    if n == 0 then return boss:GetPivot().Position, boss end
    return suma / n, boss
end

local function bossMuerto(ref)
    if not ref or not ref.Parent then return true end
    local hum = ref:FindFirstChildWhichIsA("Humanoid", true)
    if hum and hum.Health <= 0 then return true end
    local hp = ref:GetAttribute("Health")
    if type(hp) == "number" and hp <= 0 then return true end
    return false
end

---------------------------------------------------------------
-- BARCO (misma lógica que el script de cofres)
---------------------------------------------------------------
local function isMyShip(ship)
    local name = LocalPlayer.Name
    local displayName = LocalPlayer.DisplayName
    local userId = tostring(LocalPlayer.UserId)

    for _, attr in ipairs({ "Owner", "OwnerName", "OwnerId", "Player", "PlayerName", "UserId" }) do
        local v = ship:GetAttribute(attr)
        if v ~= nil then
            local s = tostring(v)
            if s == name or s == displayName or s == userId then
                return true
            end
        end
    end

    for _, d in ipairs(ship:GetDescendants()) do
        if d:IsA("ObjectValue") and d.Value == LocalPlayer then
            return true
        elseif d:IsA("StringValue") and (d.Value == name or d.Value == userId) then
            return true
        elseif (d:IsA("IntValue") or d:IsA("NumberValue")) and tostring(d.Value) == userId then
            return true
        end
    end

    if ship.Name == name or ship.Name == displayName then
        return true
    end
    if ship.Name:find(userId, 1, true) then
        return true
    end
    return false
end

local function getMyShip()
    if cachedShip and cachedShip.Parent then
        return cachedShip
    end
    cachedShip = nil

    local ships = getPath({ "World", "Dynamic", "Ships" })
    if not ships then return nil end

    for _, child in ipairs(ships:GetChildren()) do
        local candidates = {}
        if child:IsA("Model") or child:IsA("BasePart") then
            table.insert(candidates, child)
        elseif child:IsA("Folder") then
            for _, d in ipairs(child:GetChildren()) do
                if d:IsA("Model") or d:IsA("BasePart") then
                    table.insert(candidates, d)
                end
            end
        end
        for _, c in ipairs(candidates) do
            if isMyShip(c) then
                cachedShip = c
                return c
            end
        end
    end
    return nil
end

local function getChestSize(obj)
    local v = obj:GetAttribute("CargoSize")
    if v == nil then
        local child = obj:FindFirstChild("CargoSize")
        if child and child:IsA("ValueBase") then v = child.Value end
    end
    return tonumber(v) or 1
end

local function usedSpaceOn(barco)
    if not barco then return 0 end
    local total = 0
    local cargo = barco:FindFirstChild("CargoVisuals")
    if cargo then
        for _, c in ipairs(cargo:GetChildren()) do
            if c:IsA("Model") then total += getChestSize(c) end
        end
    end
    return total
end

local function getShipTop(barco)
    local center, size
    if barco:IsA("Model") then
        center, size = barco:GetBoundingBox()
    else
        center, size = barco.CFrame, barco.Size
    end
    return Vector3.new(center.Position.X, center.Position.Y + size.Y / 2 + CONFIG.ALTURA_BARCO, center.Position.Z)
end

---------------------------------------------------------------
-- COFRE EN LA MANO (el que suelta el boss o uno recogido)
---------------------------------------------------------------
local function cofreEnMano()
    local char = LocalPlayer.Character
    if not char then return nil end
    for _, c in ipairs(char:GetChildren()) do
        if c:IsA("Tool") or c:IsA("Model") then
            local tieneCarga = c:GetAttribute("CargoSize") ~= nil
                or c:FindFirstChild("CargoSize") ~= nil
            if tieneCarga or c.Name:find("Treasure") then
                return c
            end
        end
    end
    return nil
end

-- Si tienes un cofre en la mano, lo llevas al barco antes de hacer cualquier otra cosa
local function depositarEnMano(barco)
    if not cofreEnMano() then return true end

    setStatus("Llevando el cofre de la mano al barco...")
    setHover(false)
    local antes = usedSpaceOn(barco)
    tpTo(CFrame.new(getShipTop(barco)))

    local t0 = os.clock()
    while os.clock() - t0 < CONFIG.ESPERA_GUARDADO do
        if not cofreEnMano() or usedSpaceOn(barco) > antes then
            task.wait(0.5)
            return true
        end
        task.wait(0.25)
    end

    setStatus("El cofre de la mano no se guardó")
    return false
end

---------------------------------------------------------------
-- BOTÍN (World.Dynamic.Loot)
-- Estructura: Loot > Treasure_xxx > Base > PromptAttachment > TreasurePrompt
---------------------------------------------------------------
local function findPrompt(item)
    local base = item:FindFirstChild("Base")
    local att = base and base:FindFirstChild("PromptAttachment")
    local p = att and att:FindFirstChild("TreasurePrompt")
    if p and p:IsA("ProximityPrompt") then return p end
    for _, d in ipairs(item:GetDescendants()) do
        if d:IsA("ProximityPrompt") then return d end
    end
    return nil
end

local function listaBotin(loot)
    local lista = {}
    for _, c in ipairs(loot:GetChildren()) do
        local p = findPrompt(c)
        if p then table.insert(lista, { item = c, prompt = p }) end
    end
    return lista
end

local function esperarBotin(loot)
    local t0 = os.clock()
    while not closed and cazando and os.clock() - t0 < CONFIG.ESPERA_BOTIN do
        local lista = listaBotin(loot)
        if #lista > 0 then return lista end
        task.wait(0.5)
    end
    return listaBotin(loot)
end

local function recogerBotin()
    local loot = getPath({ "World", "Dynamic", "Loot" })
    if not loot then
        setStatus("No encuentro World.Dynamic.Loot")
        return
    end

    local barco = getMyShip()
    if not barco then
        setStatus("No encuentro tu barco")
        return
    end

    -- Primero el cofre que traes en la mano
    if not depositarEnMano(barco) then return end

    setStatus("Esperando el botín...")
    local lista = esperarBotin(loot)
    if #lista == 0 then
        setStatus("No apareció botín en Loot")
        return
    end
    setStatus("Botín encontrado: " .. #lista)

    local recogidos = 0
    for _, entry in ipairs(lista) do
        if closed or not cazando then break end
        local item, prompt = entry.item, entry.prompt

        -- Antes de cada recogida, deja el cofre que tengas en la mano
        if not depositarEnMano(barco) then break end

        if prompt:IsDescendantOf(Workspace) then
            local size = getChestSize(item)
            if usedSpaceOn(barco) + size > CONFIG.CAPACIDAD then
                setStatus("Bóveda llena: vacíala para seguir")
                break
            end

            local padre = prompt.Parent
            local anchorPos = (padre and padre:IsA("Attachment")) and padre.WorldPosition or posOf(item)

            if anchorPos then
                -- 1) Ir al botín y activar el prompt
                setStatus("Recogiendo " .. item.Name .. "...")
                tpTo(CFrame.new(anchorPos + Vector3.new(0, CONFIG.ALTURA_COFRE, 0)))

                pcall(function()
                    prompt.RequiresLineOfSight = false
                    if prompt.MaxActivationDistance < 25 then
                        prompt.MaxActivationDistance = 25
                    end
                end)

                task.wait(CONFIG.ESPERA_POSICION)

                for _ = 1, CONFIG.INTENTOS_RECOGER do
                    pcall(fireproximityprompt, prompt)
                    task.wait(CONFIG.ESPERA_RECOGER)
                    if not prompt:IsDescendantOf(Workspace) then break end
                end

                -- 2) Llevarlo al barco
                if depositarEnMano(barco) then
                    recogidos += 1
                    botinRecogido += 1
                end
            end
        end
    end

    setHover(true)
    setStatus("Botín guardado: " .. recogidos)
end

---------------------------------------------------------------
-- CAZA
---------------------------------------------------------------
local function cazar(b)
    -- 1) TP a la isla
    setStatus("TP a " .. b.isla .. " (" .. b.mar .. ")...")
    local isla = getIsla(b.isla)
    if not isla then
        setStatus("No encuentro la isla " .. b.isla)
        cazando = false
        return
    end
    tpTo(CFrame.new(posOf(isla) + Vector3.new(0, 10, 0)))
    setHover(true)
    task.wait(CONFIG.ESPERA_STREAMING)

    -- 2) Esperar al boss
    local ref
    local t0 = os.clock()
    while not closed and cazando and os.clock() - t0 < CONFIG.ESPERA_CARGA_BOSS do
        local p, bo = posicionBoss(b)
        if p and not bossMuerto(bo) then
            ref = bo
            break
        end
        setStatus("Esperando a " .. b.nombre .. "...")
        task.wait(0.5)
    end
    if not ref then
        setStatus(b.nombre .. " no apareció en la ruta")
        task.wait(2)
        return
    end

    -- 3) Atacar
    local murio = false
    while not closed and cazando do
        local p, bo = posicionBoss(b)
        if bo then ref = bo end
        if not p or bossMuerto(ref) then
            murio = true
            break
        end

        local a = ajusteDe(b)
        objetivoCF = CFrame.lookAt(
            p + Vector3.new(a.lado, a.altura, CONFIG.DISTANCIA),
            p
        )

        local tool = herramienta()
        if not tool then
            setStatus("No tienes ninguna tool en la mano")
            cazando = false
            break
        end

        pcall(function() tool:Activate() end)
        setStatus("Atacando " .. b.nombre .. " (" .. fmt(p) .. ")")
        task.wait(CONFIG.ESPERA_ATAQUE)
    end

    -- 4) Soltar al boss y subir a la parte alta de la isla
    objetivoCF = nil

    if murio and cazando and not closed then
        kills += 1
        setStatus(b.nombre .. " derrotado (" .. kills .. ")")

        local isla2 = getIsla(b.isla)
        if isla2 then
            tpTo(CFrame.new(islandTop(isla2) + Vector3.new(0, 10, 0)))
        end
        setHover(true)

        if botinActivo() then
            task.wait(1)
            recogerBotin()
        end
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

local bossBtn, toggleBtn, botinBtn, killsLbl, statusLbl, alturaLbl, ladoLbl

local function construirUI()
    local gui = crearGui()

    local main = mk("Frame", {
        Size = UDim2.fromOffset(150, 178),
        Position = UDim2.new(0, 8, 0.3, 0),
        BackgroundColor3 = BG,
        BorderSizePixel = 0,
        Active = true,
        Draggable = true,
    }, gui)
    mk("UICorner", { CornerRadius = UDim.new(0, 8) }, main)

    mk("TextLabel", {
        Size = UDim2.new(1, -28, 0, 14), Position = UDim2.new(0, 6, 0, 4),
        BackgroundTransparency = 1, Text = "Bosses v2", TextColor3 = TEXT,
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

    local function fila(y, onMinus, onPlus, txtMinus, txtPlus)
        boton(UDim2.new(0, 6, 0, y), UDim2.fromOffset(34, 20), CARD, 10, onMinus).Text = txtMinus
        boton(UDim2.new(1, -40, 0, y), UDim2.fromOffset(34, 20), CARD, 10, onPlus).Text = txtPlus
        return mk("TextLabel", {
            Position = UDim2.new(0, 42, 0, y), Size = UDim2.new(1, -84, 0, 20),
            BackgroundTransparency = 1, TextColor3 = TEXT, TextSize = 9,
            Font = Enum.Font.GothamBold, Text = "",
        }, main)
    end

    bossBtn = boton(UDim2.new(0, 6, 0, 34), UDim2.new(1, -12, 0, 22), CARD, 9, function()
        bossIndex = bossIndex % #BOSSES + 1
    end)

    toggleBtn = boton(UDim2.new(0, 6, 0, 60), UDim2.new(1, -12, 0, 26), GREEN, 10, function()
        cazando = not cazando
        if not cazando then
            objetivoCF = nil
            setHover(false)
            setStatus("Caza detenida")
        end
    end)

    alturaLbl = fila(90,
        function()
            local a = ajusteDe(BOSSES[bossIndex])
            a.altura = math.max(CONFIG.ALTURA_MIN, a.altura - CONFIG.PASO)
            guardarAjustes()
        end,
        function()
            local a = ajusteDe(BOSSES[bossIndex])
            a.altura = math.min(CONFIG.ALTURA_MAX, a.altura + CONFIG.PASO)
            guardarAjustes()
        end,
        "▼", "▲")

    ladoLbl = fila(114,
        function()
            local a = ajusteDe(BOSSES[bossIndex])
            a.lado = math.max(CONFIG.LADO_MIN, a.lado - CONFIG.PASO)
            guardarAjustes()
        end,
        function()
            local a = ajusteDe(BOSSES[bossIndex])
            a.lado = math.min(CONFIG.LADO_MAX, a.lado + CONFIG.PASO)
            guardarAjustes()
        end,
        "◀", "▶")

    botinBtn = boton(UDim2.new(0, 6, 0, 138), UDim2.new(1, -12, 0, 20), CARD, 9, function()
        ajustes._botin = not botinActivo()
        guardarAjustes()
    end)

    killsLbl = mk("TextLabel", {
        Size = UDim2.new(1, -12, 0, 12), Position = UDim2.new(0, 6, 0, 162),
        BackgroundTransparency = 1, TextColor3 = TEXT, TextSize = 8, Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, main)

    local closeBtn = boton(UDim2.new(1, -20, 0, 3), UDim2.fromOffset(17, 17), RED, 9, function()
        closed = true
        cazando = false
        objetivoCF = nil
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
            local a = ajusteDe(b)
            bossBtn.Text = b.nombre
            toggleBtn.Text = cazando and "■ Parar" or "▶ Cazar"
            toggleBtn.BackgroundColor3 = cazando and RED or GREEN
            alturaLbl.Text = "Altura: " .. a.altura
            ladoLbl.Text = "Lado: " .. a.lado
            botinBtn.Text = "Botín: " .. (botinActivo() and "ON" or "OFF")
            botinBtn.BackgroundColor3 = botinActivo() and GREEN or CARD
            statusLbl.Text = statusText
            killsLbl.Text = "Derrotados: " .. kills .. " · Botín: " .. botinRecogido
        end

        if cazando then
            local ok, err = pcall(cazar, b)
            if not ok then
                objetivoCF = nil
                setStatus("Error: " .. tostring(err))
                task.wait(2)
            end
        else
            task.wait(0.3)
        end
    end
end)
