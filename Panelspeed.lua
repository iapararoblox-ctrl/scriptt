--[[
    NEON MOVE · Panel móvil (LocalScript)
    Ubicación: StarterPlayer > StarterPlayerScripts

    • Velocidad (detecta cómo estás):
        - A pie / sobre una Part: cambia Humanoid.WalkSpeed
        - En un VehicleSeat: cambia MaxSpeed y Torque del vehículo
        - En un Seat normal: impulso del ensamblaje en la dirección que te mueves
    • Noclip: desactiva CanCollide de todo el personaje (se restaura al apagarlo)
    • Volar: usa el joystick del juego para moverte y ▲ / ▼ para subir y bajar
    • Minimizar: el panel se reduce a una burbuja. Un toque la vuelve a abrir.
]]

----------------------------------------------------------------
-- SERVICIOS
----------------------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- CONFIGURACIÓN
----------------------------------------------------------------
local CFG = {
    PANEL_W = 300,
    PANEL_H = 480,
    SPEED_MIN = 4,
    SPEED_MAX = 500,
    SPEED_STEP = 10,
    SPEED_DEFAULT = 16,
    SPEED_PRESETS = { 16, 60, 150, 400 },
    FLY_MIN = 10,
    FLY_MAX = 400,
    FLY_STEP = 10,
    FLY_DEFAULT = 60,
    FLY_RESPONSE = 12,     -- firmeza del vuelo (más alto = responde más rápido)
    HOLD_DELAY = 0.35,     -- segundos antes de repetir al mantener pulsado
    HOLD_RATE = 0.08,      -- segundos entre repeticiones
    RAY_DEPTH = 6,         -- studs que se mira hacia abajo para saber sobre qué estás
}

local COL = {
    bg = Color3.fromRGB(9, 11, 17),
    card = Color3.fromRGB(17, 20, 30),
    card2 = Color3.fromRGB(26, 30, 44),
    track = Color3.fromRGB(36, 41, 58),
    cyan = Color3.fromRGB(0, 229, 255),
    magenta = Color3.fromRGB(255, 70, 190),
    amber = Color3.fromRGB(255, 190, 60),
    green = Color3.fromRGB(80, 230, 150),
    text = Color3.fromRGB(236, 240, 250),
    sub = Color3.fromRGB(128, 136, 162),
    dark = Color3.fromRGB(8, 10, 16),
    white = Color3.fromRGB(255, 255, 255),
    danger = Color3.fromRGB(255, 110, 125),
}

local TI_FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TI_MED = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

----------------------------------------------------------------
-- ESTADO
----------------------------------------------------------------
local S = {
    closed = false,
    panelOpen = true,
    panelPos = nil,
    bubblePos = nil,

    speedOn = false,
    speed = CFG.SPEED_DEFAULT,
    speedApplied = false,
    origWalk = 16,
    origVehicle = {},      -- [VehicleSeat] = { MaxSpeed, Torque } originales

    noclipOn = false,
    origCollide = setmetatable({}, { __mode = "k" }),

    flyOn = false,
    flySpeed = CFG.FLY_DEFAULT,
    flyUp = false,
    flyDown = false,
    flyForce = nil,
    flyAtt = nil,
}

local conns = {}
local function track(c)
    table.insert(conns, c)
    return c
end

local ui = {}            -- referencias a los elementos de la interfaz
local refreshUI          -- se define más abajo

----------------------------------------------------------------
-- HELPERS DE INTERFAZ (todo se crea con Instance.new)
----------------------------------------------------------------
local function make(class, props)
    local obj = Instance.new(class)
    if props then
        for k, v in pairs(props) do
            if k ~= "Parent" then
                obj[k] = v
            end
        end
        if props.Parent then
            obj.Parent = props.Parent
        end
    end
    return obj
end

local function corner(obj, r)
    return make("UICorner", { CornerRadius = UDim.new(0, r), Parent = obj })
end

local function stroke(obj, color, transparency, thickness)
    return make("UIStroke", {
        Color = color,
        Transparency = transparency or 0,
        Thickness = thickness or 1,
        Parent = obj,
    })
end

local function gradient(obj, c1, c2, rot)
    return make("UIGradient", {
        Color = ColorSequence.new(c1, c2),
        Rotation = rot or 0,
        Parent = obj,
    })
end

local function label(parent, text, props)
    local l = make("TextLabel", {
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = COL.text,
        Font = Enum.Font.GothamMedium,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = parent,
    })
    for k, v in pairs(props or {}) do
        l[k] = v
    end
    return l
end

-- Guarda el color base del botón para el efecto al pulsar
local function setBase(b, color)
    b:SetAttribute("Base", color)
    b.BackgroundColor3 = color
end

local function button(parent, text, props)
    local b = make("TextButton", {
        Text = text,
        TextColor3 = COL.text,
        Font = Enum.Font.GothamBold,
        TextSize = 18,
        AutoButtonColor = false,
        BorderSizePixel = 0,
        Parent = parent,
    })
    corner(b, 12)
    for k, v in pairs(props or {}) do
        b[k] = v
    end
    setBase(b, (props and props.BackgroundColor3) or COL.card2)

    b.MouseButton1Down:Connect(function()
        TweenService:Create(b, TI_FAST, {
            BackgroundColor3 = b:GetAttribute("Base"):Lerp(COL.white, 0.18),
        }):Play()
    end)
    b.MouseButton1Up:Connect(function()
        TweenService:Create(b, TI_FAST, { BackgroundColor3 = b:GetAttribute("Base") }):Play()
    end)
    return b
end

-- Repite la acción mientras el dedo siga pulsando el botón
local function holdRepeat(b, fn)
    local token = 0
    b.MouseButton1Down:Connect(function()
        token += 1
        local my = token
        fn()
        task.spawn(function()
            task.wait(CFG.HOLD_DELAY)
            while token == my and b.Parent do
                fn()
                task.wait(CFG.HOLD_RATE)
            end
        end)
    end)
    local function stop()
        token += 1
    end
    b.MouseButton1Up:Connect(stop)
    b.MouseLeave:Connect(stop)
end

-- Activa un valor (true) mientras se mantiene pulsado y lo desactiva al soltar
local function holdFlag(b, setFn)
    b.MouseButton1Down:Connect(function() setFn(true) end)
    local function up() setFn(false) end
    b.MouseButton1Up:Connect(up)
    b.MouseLeave:Connect(up)
end

-- Interruptor tipo píldora con brillo neón cuando está activo
local function switch(parent, pos, onChange)
    local trk = make("Frame", {
        Size = UDim2.fromOffset(52, 30),
        Position = pos,
        BackgroundColor3 = COL.track,
        BorderSizePixel = 0,
        Parent = parent,
    })
    corner(trk, 15)
    local ring = stroke(trk, COL.cyan, 1, 1.5)
    ring.Transparency = 1

    local knob = make("Frame", {
        Size = UDim2.fromOffset(24, 24),
        Position = UDim2.fromOffset(3, 3),
        BackgroundColor3 = COL.sub,
        BorderSizePixel = 0,
        Parent = trk,
    })
    corner(knob, 12)

    -- Área de toque más grande que el interruptor (fácil de pulsar con el dedo)
    local hit = make("TextButton", {
        Size = UDim2.fromOffset(76, 52),
        Position = UDim2.fromOffset(-12, -11),
        BackgroundTransparency = 1,
        Text = "",
        Parent = trk,
    })

    local on = false
    local function paint()
        TweenService:Create(trk, TI_MED, { BackgroundColor3 = on and COL.cyan or COL.track }):Play()
        TweenService:Create(knob, TI_MED, {
            Position = on and UDim2.fromOffset(25, 3) or UDim2.fromOffset(3, 3),
            BackgroundColor3 = on and COL.dark or COL.sub,
        }):Play()
        TweenService:Create(ring, TI_MED, { Transparency = on and 0.1 or 1 }):Play()
    end

    hit.Activated:Connect(function()
        on = not on
        paint()
        if onChange then
            onChange(on)
        end
    end)

    return {
        set = function(v)
            on = v
            paint()
        end,
        get = function()
            return on
        end,
    }
end

local function card(parent, order, h)
    local f = make("Frame", {
        Size = UDim2.new(1, 0, 0, h),
        BackgroundColor3 = COL.card,
        BorderSizePixel = 0,
        LayoutOrder = order,
        Parent = parent,
    })
    corner(f, 16)
    stroke(f, COL.white, 0.9, 1)
    return f
end

local function cardHead(c, title, sub)
    label(c, title, {
        Position = UDim2.fromOffset(16, 12),
        Size = UDim2.new(1, -100, 0, 20),
        TextSize = 15,
        Font = Enum.Font.GothamBold,
    })
    label(c, sub, {
        Position = UDim2.fromOffset(16, 32),
        Size = UDim2.new(1, -100, 0, 16),
        TextSize = 11,
        TextColor3 = COL.sub,
    })
end

-- Arrastrar con dedo o ratón. onTap = toque corto, onDrop = al soltar tras arrastrar
local function makeDrag(handle, target, onTap, onDrop)
    local dragging, moved = false, false
    local startInput, startPos = nil, nil

    track(handle.InputBegan:Connect(function(input)
        local t = input.UserInputType
        if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1 then
            return
        end
        dragging, moved = true, false
        startInput = input.Position
        startPos = Vector2.new(target.Position.X.Offset, target.Position.Y.Offset)

        local endConn
        endConn = input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
                if moved then
                    if onDrop then onDrop() end
                elseif onTap then
                    onTap()
                end
                endConn:Disconnect()
            end
        end)
    end))

    track(UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        local t = input.UserInputType
        if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseMovement then
            return
        end
        local d = input.Position - startInput
        if not moved and d.Magnitude > 8 then
            moved = true
        end
        if moved then
            target.Position = UDim2.fromOffset(startPos.X + d.X, startPos.Y + d.Y)
        end
    end))
end

----------------------------------------------------------------
-- LÓGICA: VELOCIDAD
----------------------------------------------------------------
-- Devuelve los valores originales de los vehículos y del WalkSpeed
local function restoreSpeed(hum)
    if hum and hum.Parent then
        hum.WalkSpeed = S.origWalk
    end
    for seat, base in pairs(S.origVehicle) do
        if seat.Parent then
            seat.MaxSpeed = base.MaxSpeed
            seat.Torque = base.Torque
        end
    end
    S.origVehicle = {}
end

-- Restaura un vehículo cuando ya no estás subido a él
local function releaseVehiclesExcept(keep)
    for seat, base in pairs(S.origVehicle) do
        if seat ~= keep then
            if seat.Parent then
                seat.MaxSpeed = base.MaxSpeed
                seat.Torque = base.Torque
            end
            S.origVehicle[seat] = nil
        end
    end
end

-- Aplica la velocidad según dónde estés
local function applySpeed(hum, root)
    local seat = hum.SeatPart

    if seat and seat:IsA("VehicleSeat") then
        -- Vehículo: guardamos sus valores originales y los escalamos
        local base = S.origVehicle[seat]
        if not base then
            base = { MaxSpeed = seat.MaxSpeed, Torque = seat.Torque }
            S.origVehicle[seat] = base
        end
        local mult = math.clamp(S.speed / math.max(base.MaxSpeed, 1), 0.1, 50)
        seat.MaxSpeed = S.speed
        seat.Torque = base.Torque * mult

    elseif seat then
        -- Seat normal: no se conduce, así que empujamos el ensamblaje al moverte
        local asm = seat:GetRootPart()
        local md = hum.MoveDirection
        if asm and not asm.Anchored and md.Magnitude > 0.05 then
            local dir = md.Unit
            local v = asm.AssemblyLinearVelocity
            asm.AssemblyLinearVelocity = Vector3.new(dir.X * S.speed, v.Y, dir.Z * S.speed)
        end

    else
        -- A pie o sobre una Part
        hum.WalkSpeed = S.speed
    end
end

-- Detecta cómo estás: a pie, sobre una Part, en un vehículo, en un asiento o en el aire
local function currentMode()
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not (hum and root) then
        return "Sin personaje"
    end

    local seat = hum.SeatPart
    if seat then
        if seat:IsA("VehicleSeat") then
            return "Vehículo"
        end
        return "Asiento"
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { char }
    local hit = Workspace:Raycast(root.Position, Vector3.new(0, -CFG.RAY_DEPTH, 0), params)

    if hit and hit.Instance then
        if hit.Instance:IsA("Terrain") then
            return "A pie"
        end
        return "Sobre Part"
    end
    return "En el aire"
end

local function setSpeed(v)
    S.speed = math.clamp(math.floor(v + 0.5), CFG.SPEED_MIN, CFG.SPEED_MAX)
    refreshUI()
end

----------------------------------------------------------------
-- LÓGICA: NOCLIP
----------------------------------------------------------------
local function restoreCollide()
    for part, was in pairs(S.origCollide) do
        if part.Parent then
            part.CanCollide = was
        end
    end
    S.origCollide = setmetatable({}, { __mode = "k" })
end

----------------------------------------------------------------
-- LÓGICA: VUELO
----------------------------------------------------------------
-- Compensa la gravedad con una VectorForce para que el vuelo sea suave
local function startFlyObjects(root)
    if S.flyForce then return end
    local att = make("Attachment", { Name = "NeonMoveAtt", Parent = root })
    local vf = make("VectorForce", {
        Name = "NeonMoveAntiG",
        Attachment0 = att,
        RelativeTo = Enum.ActuatorRelativeTo.World,
        ApplyAtCenterOfMass = true,
        Force = Vector3.zero,
        Parent = root,
    })
    S.flyAtt, S.flyForce = att, vf
end

local function destroyFlyObjects()
    if S.flyForce then S.flyForce:Destroy() end
    if S.flyAtt then S.flyAtt:Destroy() end
    S.flyForce, S.flyAtt = nil, nil
end

local function setFlyCard(open)
    ui.flyCtl.Visible = open
    TweenService:Create(ui.flyCard, TI_MED, {
        Size = UDim2.new(1, 0, 0, open and 200 or 66),
    }):Play()
end

local function setFly(on)
    S.flyOn = on
    if not on then
        S.flyUp, S.flyDown = false, false
        destroyFlyObjects()
        local char = player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if hum then hum.PlatformStand = false end
        if root then root.AssemblyLinearVelocity = Vector3.zero end
    end
    ui.flySwitch.set(on)
    setFlyCard(on)
    refreshUI()
end

----------------------------------------------------------------
-- CERRAR TODO (restaura el personaje antes de destruir la GUI)
----------------------------------------------------------------
local function closeAll()
    if S.closed then return end
    S.closed = true

    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")

    restoreSpeed(hum)
    restoreCollide()
    S.speedOn, S.noclipOn, S.flyOn = false, false, false
    destroyFlyObjects()
    if hum then hum.PlatformStand = false end

    for _, c in ipairs(conns) do
        c:Disconnect()
    end
    if ui.gui then
        ui.gui:Destroy()
    end
end

----------------------------------------------------------------
-- CONSTRUCCIÓN DE LA INTERFAZ
----------------------------------------------------------------
local oldGui = playerGui:FindFirstChild("NeonMove")
if oldGui then oldGui:Destroy() end

local gui = make("ScreenGui", {
    Name = "NeonMove",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 999998,
    Parent = playerGui,
})
ui.gui = gui

-- Panel principal
local panel = make("Frame", {
    Name = "Panel",
    Size = UDim2.fromOffset(CFG.PANEL_W, CFG.PANEL_H),
    BackgroundColor3 = COL.bg,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Parent = gui,
})
corner(panel, 22)
gradient(panel, Color3.fromRGB(16, 20, 34), COL.bg, 90)
local panelStroke = stroke(panel, COL.cyan, 0.35, 1.5)
gradient(panelStroke, COL.cyan, COL.magenta, 45)
ui.uiScale = make("UIScale", { Parent = panel })
ui.panel = panel

-- Cabecera
local header = make("Frame", {
    Size = UDim2.new(1, 0, 0, 62),
    BackgroundTransparency = 1,
    Active = true,
    Parent = panel,
})

local logo = make("Frame", {
    Size = UDim2.fromOffset(38, 38),
    Position = UDim2.fromOffset(14, 12),
    BackgroundColor3 = COL.cyan,
    BorderSizePixel = 0,
    Parent = header,
})
corner(logo, 12)
gradient(logo, COL.cyan, COL.magenta, 45)
label(logo, "⚡", {
    Size = UDim2.fromScale(1, 1),
    TextXAlignment = Enum.TextXAlignment.Center,
    TextSize = 18,
    Font = Enum.Font.GothamBold,
    TextColor3 = COL.dark,
})

label(header, "NEON MOVE", {
    Position = UDim2.fromOffset(62, 11),
    Size = UDim2.new(1, -140, 0, 22),
    TextSize = 16,
    Font = Enum.Font.GothamBlack,
})

local chip = make("Frame", {
    Position = UDim2.fromOffset(62, 35),
    Size = UDim2.fromOffset(138, 18),
    BackgroundColor3 = COL.card2,
    BorderSizePixel = 0,
    Parent = header,
})
corner(chip, 9)
ui.chipLbl = label(chip, "A pie", {
    Position = UDim2.fromOffset(10, 0),
    Size = UDim2.new(1, -14, 1, 0),
    TextSize = 11,
    Font = Enum.Font.GothamBold,
    TextColor3 = COL.cyan,
})

local minBtn = button(header, "–", {
    Size = UDim2.fromOffset(34, 34),
    Position = UDim2.new(1, -80, 0, 14),
    BackgroundColor3 = COL.card2,
})
local closeBtn = button(header, "✕", {
    Size = UDim2.fromOffset(34, 34),
    Position = UDim2.new(1, -40, 0, 14),
    BackgroundColor3 = Color3.fromRGB(64, 26, 36),
    TextColor3 = COL.danger,
})

-- Línea neón bajo la cabecera
local neonLine = make("Frame", {
    Size = UDim2.new(1, -28, 0, 2),
    Position = UDim2.new(0, 14, 0, 61),
    BackgroundColor3 = COL.cyan,
    BorderSizePixel = 0,
    Parent = panel,
})
gradient(neonLine, COL.cyan, COL.magenta, 0)

-- Contenido desplazable
local body = make("ScrollingFrame", {
    Position = UDim2.fromOffset(12, 72),
    Size = UDim2.new(1, -24, 1, -82),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = COL.cyan,
    CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    Parent = panel,
})
make("UIListLayout", {
    Padding = UDim.new(0, 10),
    SortOrder = Enum.SortOrder.LayoutOrder,
    Parent = body,
})
make("UIPadding", {
    PaddingBottom = UDim.new(0, 8),
    PaddingRight = UDim.new(0, 6),
    Parent = body,
})

-- TARJETA: VELOCIDAD
local speedCard = card(body, 1, 186)
cardHead(speedCard, "Velocidad", "Aplica a pie, en Part, vehículo o asiento")
ui.speedSwitch = switch(speedCard, UDim2.new(1, -68, 0, 14), function(on)
    S.speedOn = on
    refreshUI()
end)

ui.speedMinus = button(speedCard, "−", {
    Size = UDim2.fromOffset(52, 46),
    Position = UDim2.fromOffset(16, 60),
    BackgroundColor3 = COL.card2,
    TextSize = 22,
})
ui.speedPlus = button(speedCard, "+", {
    Size = UDim2.fromOffset(52, 46),
    Position = UDim2.new(1, -68, 0, 60),
    BackgroundColor3 = COL.card2,
    TextSize = 22,
})
ui.speedValue = label(speedCard, "16", {
    Position = UDim2.fromOffset(72, 58),
    Size = UDim2.new(1, -144, 0, 34),
    TextSize = 28,
    Font = Enum.Font.GothamBlack,
    TextXAlignment = Enum.TextXAlignment.Center,
    TextColor3 = COL.cyan,
})
label(speedCard, "studs por segundo", {
    Position = UDim2.fromOffset(72, 92),
    Size = UDim2.new(1, -144, 0, 14),
    TextSize = 10,
    TextColor3 = COL.sub,
    TextXAlignment = Enum.TextXAlignment.Center,
})

local presetRow = make("Frame", {
    Position = UDim2.fromOffset(16, 118),
    Size = UDim2.new(1, -32, 0, 34),
    BackgroundTransparency = 1,
    Parent = speedCard,
})
make("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder,
    Parent = presetRow,
})
ui.presetBtns = {}
for i, v in ipairs(CFG.SPEED_PRESETS) do
    local b = button(presetRow, tostring(v), {
        Size = UDim2.new(0.25, -5, 1, 0),
        BackgroundColor3 = COL.card2,
        TextSize = 13,
        LayoutOrder = i,
    })
    b.Activated:Connect(function()
        setSpeed(v)
    end)
    ui.presetBtns[i] = { btn = b, value = v }
end

ui.speedDetect = label(speedCard, "Detectado: —", {
    Position = UDim2.fromOffset(16, 160),
    Size = UDim2.new(1, -32, 0, 16),
    TextSize = 11,
    TextColor3 = COL.sub,
})

-- TARJETA: NOCLIP
local noclipCard = card(body, 2, 66)
cardHead(noclipCard, "Noclip", "Atraviesa paredes y objetos")
ui.noclipSwitch = switch(noclipCard, UDim2.new(1, -68, 0, 18), function(on)
    S.noclipOn = on
    refreshUI()
end)

-- TARJETA: VOLAR
local flyCard = card(body, 3, 66)
cardHead(flyCard, "Volar", "Joystick para moverte")
ui.flyCard = flyCard
ui.flySwitch = switch(flyCard, UDim2.new(1, -68, 0, 18), function(on)
    setFly(on)
end)

local flyCtl = make("Frame", {
    Position = UDim2.fromOffset(0, 70),
    Size = UDim2.new(1, 0, 0, 126),
    BackgroundTransparency = 1,
    Visible = false,
    Parent = flyCard,
})
ui.flyCtl = flyCtl

ui.flyMinus = button(flyCtl, "−", {
    Size = UDim2.fromOffset(52, 44),
    Position = UDim2.fromOffset(16, 0),
    BackgroundColor3 = COL.card2,
    TextSize = 22,
})
ui.flyPlus = button(flyCtl, "+", {
    Size = UDim2.fromOffset(52, 44),
    Position = UDim2.new(1, -68, 0, 0),
    BackgroundColor3 = COL.card2,
    TextSize = 22,
})
ui.flyValue = label(flyCtl, "60 st/s", {
    Position = UDim2.fromOffset(72, 0),
    Size = UDim2.new(1, -144, 0, 44),
    TextSize = 20,
    Font = Enum.Font.GothamBlack,
    TextXAlignment = Enum.TextXAlignment.Center,
    TextColor3 = COL.magenta,
})
ui.flyDown = button(flyCtl, "▼  Bajar", {
    Size = UDim2.new(0.5, -22, 0, 46),
    Position = UDim2.fromOffset(16, 64),
    BackgroundColor3 = COL.card2,
    TextSize = 14,
})
ui.flyUp = button(flyCtl, "▲  Subir", {
    Size = UDim2.new(0.5, -22, 0, 46),
    Position = UDim2.new(0.5, 6, 0, 64),
    BackgroundColor3 = COL.card2,
    TextSize = 14,
})

-- TARJETA: RESTABLECER
local resetCard = card(body, 4, 56)
ui.resetBtn = button(resetCard, "↺  Restablecer todo", {
    Size = UDim2.new(1, -24, 0, 40),
    Position = UDim2.fromOffset(12, 8),
    BackgroundColor3 = COL.card2,
    TextSize = 14,
})

-- BURBUJA FLOTANTE (aparece al minimizar)
ui.bubble = make("TextButton", {
    Name = "Bubble",
    Size = UDim2.fromOffset(58, 58),
    BackgroundColor3 = COL.cyan,
    Text = "⚡",
    TextSize = 24,
    Font = Enum.Font.GothamBlack,
    TextColor3 = COL.dark,
    AutoButtonColor = false,
    BorderSizePixel = 0,
    Visible = false,
    ZIndex = 20,
    Parent = gui,
})
corner(ui.bubble, 29)
gradient(ui.bubble, COL.cyan, COL.magenta, 45)
stroke(ui.bubble, COL.white, 0.3, 2)

-- Insignia con el número de funciones activas
ui.badge = make("Frame", {
    Size = UDim2.fromOffset(20, 20),
    Position = UDim2.new(1, -14, 0, -6),
    BackgroundColor3 = COL.green,
    BorderSizePixel = 0,
    Visible = false,
    ZIndex = 21,
    Parent = ui.bubble,
})
corner(ui.badge, 10)
ui.badgeLbl = label(ui.badge, "0", {
    Size = UDim2.fromScale(1, 1),
    TextXAlignment = Enum.TextXAlignment.Center,
    TextSize = 11,
    Font = Enum.Font.GothamBold,
    TextColor3 = COL.dark,
    ZIndex = 22,
})

----------------------------------------------------------------
-- ACTUALIZAR TEXTOS Y ESTADOS DE LA INTERFAZ
----------------------------------------------------------------
refreshUI = function()
    if S.closed then return end

    local mode = currentMode()
    local chipText, chipColor
    if S.flyOn then
        chipText, chipColor = "Volando", COL.green
    elseif mode == "Vehículo" or mode == "Asiento" then
        chipText, chipColor = mode, COL.amber
    elseif mode == "Sobre Part" then
        chipText, chipColor = "Sobre Part", COL.magenta
    else
        chipText, chipColor = mode, COL.cyan
    end
    if S.noclipOn then
        chipText = chipText .. " · Noclip"
    end
    ui.chipLbl.Text = chipText
    ui.chipLbl.TextColor3 = chipColor

    ui.speedValue.Text = tostring(S.speed)
    ui.speedDetect.Text = "Detectado: " .. mode .. (S.speedOn and ("  ·  aplicando " .. S.speed) or "")
    ui.flyValue.Text = S.flySpeed .. " st/s"

    for _, p in ipairs(ui.presetBtns) do
        local activo = (p.value == S.speed)
        setBase(p.btn, activo and COL.cyan or COL.card2)
        p.btn.TextColor3 = activo and COL.dark or COL.text
    end

    local count = (S.speedOn and 1 or 0) + (S.noclipOn and 1 or 0) + (S.flyOn and 1 or 0)
    ui.badge.Visible = count > 0
    ui.badgeLbl.Text = tostring(count)
end

----------------------------------------------------------------
-- EVENTOS DE BOTONES
----------------------------------------------------------------
holdRepeat(ui.speedMinus, function() setSpeed(S.speed - CFG.SPEED_STEP) end)
holdRepeat(ui.speedPlus, function() setSpeed(S.speed + CFG.SPEED_STEP) end)

holdRepeat(ui.flyMinus, function()
    S.flySpeed = math.clamp(S.flySpeed - CFG.FLY_STEP, CFG.FLY_MIN, CFG.FLY_MAX)
    refreshUI()
end)
holdRepeat(ui.flyPlus, function()
    S.flySpeed = math.clamp(S.flySpeed + CFG.FLY_STEP, CFG.FLY_MIN, CFG.FLY_MAX)
    refreshUI()
end)

holdFlag(ui.flyUp, function(v) S.flyUp = v end)
holdFlag(ui.flyDown, function(v) S.flyDown = v end)

ui.resetBtn.Activated:Connect(function()
    S.speed = CFG.SPEED_DEFAULT
    S.flySpeed = CFG.FLY_DEFAULT
    S.speedOn = false
    ui.speedSwitch.set(false)
    S.noclipOn = false
    ui.noclipSwitch.set(false)
    setFly(false)
    refreshUI()
end)

----------------------------------------------------------------
-- POSICIÓN, MINIMIZAR Y BURBUJA
----------------------------------------------------------------
local function viewport()
    local cam = Workspace.CurrentCamera
    return cam and cam.ViewportSize or Vector2.new(390, 844)
end

local function layoutPanel()
    local vp = viewport()
    local sc = math.clamp(math.min(vp.X * 0.94 / CFG.PANEL_W, vp.Y * 0.88 / CFG.PANEL_H), 0.55, 1.05)
    ui.uiScale.Scale = sc
    local w, h = CFG.PANEL_W * sc, CFG.PANEL_H * sc

    if not S.panelPos then
        S.panelPos = Vector2.new((vp.X - w) / 2, math.max(40, (vp.Y - h) / 2))
    end
    S.panelPos = Vector2.new(
        math.clamp(S.panelPos.X, 0, math.max(0, vp.X - w)),
        math.clamp(S.panelPos.Y, 0, math.max(0, vp.Y - h))
    )
    ui.panel.Position = UDim2.fromOffset(S.panelPos.X, S.panelPos.Y)

    if not S.bubblePos then
        S.bubblePos = Vector2.new(vp.X - 74, vp.Y * 0.45)
    end
    ui.bubble.Position = UDim2.fromOffset(
        math.clamp(S.bubblePos.X, 0, math.max(0, vp.X - 58)),
        math.clamp(S.bubblePos.Y, 0, math.max(0, vp.Y - 58))
    )
end

local function setPanelOpen(open)
    S.panelOpen = open
    ui.panel.Visible = open
    ui.bubble.Visible = not open
    if not open then
        -- Pequeña animación al aparecer la burbuja
        ui.bubble.Size = UDim2.fromOffset(30, 30)
        TweenService:Create(ui.bubble, TI_MED, { Size = UDim2.fromOffset(58, 58) }):Play()
    end
end

minBtn.Activated:Connect(function()
    setPanelOpen(false)
end)

closeBtn.Activated:Connect(function()
    closeAll()
end)

makeDrag(header, panel, nil, function()
    S.panelPos = Vector2.new(panel.Position.X.Offset, panel.Position.Y.Offset)
end)

makeDrag(ui.bubble, ui.bubble,
    function() setPanelOpen(true) end,
    function()
        S.bubblePos = Vector2.new(ui.bubble.Position.X.Offset, ui.bubble.Position.Y.Offset)
    end)

----------------------------------------------------------------
-- BUCLE DE FÍSICA: velocidad, noclip y vuelo
----------------------------------------------------------------
track(RunService.Heartbeat:Connect(function(dt)
    if S.closed then return end

    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not (hum and root) or hum.Health <= 0 then return end

    -- VELOCIDAD
    releaseVehiclesExcept(hum.SeatPart)
    if S.speedOn then
        applySpeed(hum, root)
        S.speedApplied = true
    elseif S.speedApplied then
        restoreSpeed(hum)
        S.speedApplied = false
    end

    -- NOCLIP: desactiva la colisión de todas las partes del personaje
    if S.noclipOn then
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("BasePart") then
                if S.origCollide[d] == nil then
                    S.origCollide[d] = d.CanCollide
                end
                if d.CanCollide then
                    d.CanCollide = false
                end
            end
        end
    elseif next(S.origCollide) ~= nil then
        restoreCollide()
    end

    -- VUELO
    if S.flyOn then
        if hum.SeatPart then
            setFly(false) -- no se vuela sentado
        else
            hum.PlatformStand = true
            startFlyObjects(root)

            -- Horizontal: dirección del joystick del juego (ya relativa a la cámara)
            -- Vertical: botones ▲ y ▼
            local md = hum.MoveDirection
            local vert = (S.flyUp and 1 or 0) - (S.flyDown and 1 or 0)
            local target = md * S.flySpeed + Vector3.new(0, vert * S.flySpeed, 0)

            -- Suavizado independiente de los FPS
            local alpha = 1 - math.exp(-CFG.FLY_RESPONSE * dt)
            root.AssemblyLinearVelocity = root.AssemblyLinearVelocity:Lerp(target, alpha)

            if S.flyForce then
                S.flyForce.Force = Vector3.new(0, root.AssemblyMass * Workspace.Gravity, 0)
            end

            -- Mira hacia donde mira la cámara (solo en horizontal)
            local cam = Workspace.CurrentCamera
            if cam then
                local look = cam.CFrame.LookVector
                local flat = Vector3.new(look.X, 0, look.Z)
                if flat.Magnitude > 0.01 then
                    root.CFrame = CFrame.new(root.Position, root.Position + flat)
                end
            end
        end
    end
end))

-- Al reaparecer: se reinician las partes temporales y se apaga el vuelo
local function onCharacter(char)
    local hum = char:WaitForChild("Humanoid", 10)
    if not hum then return end
    char:WaitForChild("HumanoidRootPart", 10)

    S.origWalk = hum.WalkSpeed
    S.origVehicle = {}
    S.origCollide = setmetatable({}, { __mode = "k" })
    S.speedApplied = false
    S.flyAtt, S.flyForce = nil, nil

    if S.flyOn then
        S.flyOn = false
        S.flyUp, S.flyDown = false, false
        ui.flySwitch.set(false)
        setFlyCard(false)
    end
    refreshUI()
end

track(player.CharacterAdded:Connect(onCharacter))
if player.Character then
    task.spawn(onCharacter, player.Character)
end

-- Actualiza los textos cinco veces por segundo
task.spawn(function()
    while not S.closed do
        refreshUI()
        task.wait(0.2)
    end
end)

-- Se adapta al tamaño de la pantalla
local cam = Workspace.CurrentCamera
if cam then
    track(cam:GetPropertyChangedSignal("ViewportSize"):Connect(layoutPanel))
end

----------------------------------------------------------------
-- INICIO
----------------------------------------------------------------
layoutPanel()
setPanelOpen(true)
refreshUI()
