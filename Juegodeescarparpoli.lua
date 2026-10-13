--[[  AUTO BURBUJAS — versión con mitigación anti-detección
  Cambios clave:
    - RADIO realista (no 500000)
    - Delays con jitter humano
    - Límite de burbujas por ciclo
    - Pausas largas periódicas
    - No anula AssemblyLinearVelocity
    - Pausa si te mueves a mano o si el estado del Humanoid no es "Running"
    - Chequeo de distancia mínima entre TPs
--]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

---------------------------------------------------------------------
-- Configuración (anti-detección)
---------------------------------------------------------------------
local RADIO = 250                    -- antes 500000. Radio realista de recolección
local INTERVALO = 1.5                -- segundos base entre ciclos
local INTERVALO_JITTER = 0.6         -- ±variación aleatoria
local INTERVALO_TP = 1.8             -- segundos entre TPs aleatorios
local DESTINO = Vector3.new(11, 49, -553)
local ALTURA_PLATAFORMA = 3.5

local VEL_MIN, VEL_MAX = 1, 4        -- antes 1..20. Ahora máximo 4 burb/s
local UMBRAL_MIN, UMBRAL_MAX = 5, 95

local RADIO_TP = 120                 -- antes 150. Radio de TP aleatorio
local SEPARACION = 60                -- antes 45
local CANDIDATOS = 60

-- Anti-detección
local PAUSA_CADA = 15                -- cada N burbujas, pausa larga
local PAUSA_MIN, PAUSA_MAX = 4, 9    -- segundos de pausa
local BURBUJAS_POR_CICLO = 3          -- no arrasar todas en un tick
local DIST_MIN_TP = 8                -- distancia mínima a la burbuja (no te pegues)
local OFFSET_TP = Vector3.new(0, 3, 0) -- TP a la altura de la cabeza, no al pivote
local DETECTAR_INPUT = true          -- pausar si el jugador se mueve a mano

-- Estado
local velocidad = 3
local umbralOxigeno = 50
local controlOxigeno = true
local recolectando = false
local activo = false
local tpAleatorio = false
local cerrado = false
local ocupado = false
local recogidas = 0
local plataforma = nil
local visitados = {}
local conexiones = {}
local actualizarInfo
local pausaHasta = 0
local lastInputTime = tick()
local lastTPTime = 0

-- Paleta
local COL_FONDO   = Color3.fromRGB(24, 26, 36)
local COL_BARRA   = Color3.fromRGB(34, 37, 52)
local COL_ACENTO  = Color3.fromRGB(80, 170, 255)
local COL_ON      = Color3.fromRGB(60, 200, 120)
local COL_OFF     = Color3.fromRGB(90, 94, 115)
local COL_ROJO    = Color3.fromRGB(220, 75, 80)
local COL_TEXTO   = Color3.fromRGB(235, 238, 250)
local COL_SUB     = Color3.fromRGB(150, 156, 180)

local function conectar(senal, fn)
    local c = senal:Connect(fn)
    table.insert(conexiones, c)
    return c
end

local function humanDelay(base, jitter)
    return base + (math.random() * 2 - 1) * jitter
end

---------------------------------------------------------------------
-- Detección de input humano (para pausar si te mueves)
---------------------------------------------------------------------
if DETECTAR_INPUT then
    conectar(UserInputService.InputBegan, function(input, gpe)
        if gpe then return end
        if input.UserInputType == Enum.UserInputType.Keyboard
        or input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
            lastInputTime = tick()
        end
    end)
end

---------------------------------------------------------------------
-- Oxígeno
---------------------------------------------------------------------
local function leerOxigeno()
    if LocalPlayer:GetAttribute("OxygenEnabled") == false then return nil end
    local ox = LocalPlayer:GetAttribute("Oxygen")
    local mx = LocalPlayer:GetAttribute("MaxOxygen")
    if typeof(ox) ~= "number" or typeof(mx) ~= "number" or mx <= 0 then
        return nil
    end
    return ox, mx
end

local function debeRecolectar()
    if not controlOxigeno then return true end
    local ox, mx = leerOxigeno()
    if not ox then return true end
    local pct = ox / mx * 100
    local antes = recolectando
    if recolectando then
        if pct >= 99.5 then recolectando = false end
    else
        if pct <= umbralOxigeno then recolectando = true end
    end
    if antes ~= recolectando and actualizarInfo then actualizarInfo() end
    return recolectando
end

---------------------------------------------------------------------
-- Utilidades de juego
---------------------------------------------------------------------
local function getRoot()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    return char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart", 5)
end

local function getHumanoid()
    local char = LocalPlayer.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function getPosition(obj)
    if obj:IsA("Model") then
        return obj:GetPivot().Position
    elseif obj:IsA("BasePart") then
        return obj.Position
    end
end

-- Estados del Humanoid que indican que NO debes teleportar
local ESTADOS_SEGUROS = {
    [Enum.HumanoidStateType.Running] = true,
    [Enum.HumanoidStateType.RunningNoPhysics] = true,
    [Enum.HumanoidStateType.Landed] = true,
    [Enum.HumanoidStateType.Seated] = true,
}

local function estadoSeguro()
    local hum = getHumanoid()
    if not hum then return false end
    if hum.Health <= 0 then return false end
    local st = hum:GetState()
    return ESTADOS_SEGUROS[st] == true
end

local function crearPlataforma(posicion)
    if not plataforma or not plataforma.Parent then
        plataforma = Instance.new("Part")
        plataforma.Name = "FloatPlatform"
        plataforma.Size = Vector3.new(10, 1, 10)
        plataforma.Anchored = true
        plataforma.CanCollide = true
        plataforma.Transparency = 0.6
        plataforma.Material = Enum.Material.Glass
        plataforma.Color = COL_ACENTO
        plataforma.Parent = Workspace
    end
    plataforma.Position = (posicion or DESTINO) - Vector3.new(0, ALTURA_PLATAFORMA, 0)
end

local function quitarPlataforma()
    if plataforma then
        plataforma:Destroy()
        plataforma = nil
    end
end

-- TP suave: usa PivotTo y NO toca AssemblyLinearVelocity (eso canta)
local function teleportarSuave(root, destino)
    if not root or not root.Parent then return false end
    if not estadoSeguro() then return false end

    -- Tween corto en vez de salto instantáneo (más humano, pero ojo:
    -- el tween sobre CFrame se puede detectar en el servidor. Mejor teletransporte
    -- a un punto cercano, y el desplazamiento final lo hace el personaje normal.)
    local actual = root.Position
    local dist = (actual - destino).Magnitude

    if dist < DIST_MIN_TP then
        return false -- ya estás lo bastante cerca, no hace falta TP
    end

    -- Solo teletransporta la mitad del camino, para que el resto sea caminar.
    -- Esto rompe la firma de "TP exacto a la burbuja".
    local salto = actual:Lerp(destino, 0.6) + OFFSET_TP
    root.CFrame = CFrame.new(salto, salto + (destino - salto))
    lastTPTime = tick()
    return true
end

local function posicionAleatoria(origen)
    if #visitados == 0 and origen then
        table.insert(visitados, Vector3.new(origen.X, DESTINO.Y, origen.Z))
    end
    local mejor
    for pasada = 1, 2 do
        local mejorDist = -1
        for _ = 1, CANDIDATOS do
            local ang = math.random() * math.pi * 2
            local dist = math.sqrt(math.random()) * RADIO_TP
            local cand = DESTINO + Vector3.new(math.cos(ang) * dist, 0, math.sin(ang) * dist)
            local minD = math.huge
            for _, v in ipairs(visitados) do
                local d = (v - cand).Magnitude
                if d < minD then minD = d end
            end
            if minD > mejorDist then
                mejor, mejorDist = cand, minD
            end
        end
        if mejorDist >= SEPARACION or pasada == 2 then break end
        local ultimo = visitados[#visitados]
        visitados = ultimo and { ultimo } or {}
    end
    table.insert(visitados, mejor)
    return mejor
end

---------------------------------------------------------------------
-- Helpers de UI (idénticos)
---------------------------------------------------------------------
local function redondear(obj, radio)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radio)
    c.Parent = obj
    return c
end

local function borde(obj, color, grosor, transp)
    local s = Instance.new("UIStroke")
    s.Color = color
    s.Thickness = grosor or 1
    s.Transparency = transp or 0
    s.Parent = obj
    return s
end

local function crearTexto(parent, texto, tam, color, fuente)
    local t = Instance.new("TextLabel")
    t.BackgroundTransparency = 1
    t.Text = texto
    t.TextSize = tam
    t.TextColor3 = color or COL_TEXTO
    t.Font = fuente or Enum.Font.GothamMedium
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.Parent = parent
    return t
end

local function esPuntero(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
end

local function hacerArrastrable(handle, target, alTocar)
    local arrastrando, movido = false, false
    local inicioInput, inicioPos
    conectar(handle.InputBegan, function(input)
        if esPuntero(input) then
            arrastrando, movido = true, false
            inicioInput = input.Position
            inicioPos = target.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    arrastrando = false
                    if not movido and alTocar then alTocar() end
                end
            end)
        end
    end)
    conectar(UserInputService.InputChanged, function(input)
        if arrastrando and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - inicioInput
            if d.Magnitude > 5 then movido = true end
            if movido then
                target.Position = UDim2.new(
                    inicioPos.X.Scale, inicioPos.X.Offset + d.X,
                    inicioPos.Y.Scale, inicioPos.Y.Offset + d.Y)
            end
        end
    end)
end

local function crearFilaSwitch(parent, y, textoInicial, colorOn, inicial, alCambiar)
    local lbl = crearTexto(parent, textoInicial, 14, inicial and colorOn or COL_SUB)
    lbl.Size = UDim2.new(1, -90, 0, 26)
    lbl.Position = UDim2.fromOffset(14, y)

    local sw = Instance.new("TextButton")
    sw.Size = UDim2.fromOffset(50, 26)
    sw.Position = UDim2.new(1, -64, 0, y)
    sw.BackgroundColor3 = inicial and colorOn or COL_OFF
    sw.Text = ""
    sw.AutoButtonColor = false
    sw.Parent = parent
    redondear(sw, 13)

    local perilla = Instance.new("Frame")
    perilla.Size = UDim2.fromOffset(20, 20)
    perilla.Position = UDim2.fromOffset(inicial and 27 or 3, 3)
    perilla.BackgroundColor3 = Color3.new(1, 1, 1)
    perilla.BorderSizePixel = 0
    perilla.Parent = sw
    redondear(perilla, 10)

    local estado = inicial == true
    sw.MouseButton1Click:Connect(function()
        estado = not estado
        local info = TweenInfo.new(0.18, Enum.EasingStyle.Quad)
        TweenService:Create(sw, info, { BackgroundColor3 = estado and colorOn or COL_OFF }):Play()
        TweenService:Create(perilla, info, { Position = UDim2.fromOffset(estado and 27 or 3, 3) }):Play()
        lbl.TextColor3 = estado and colorOn or COL_SUB
        alCambiar(estado, lbl)
    end)
    return lbl
end

local function crearSlider(parent, y, cfg)
    local cont = Instance.new("CanvasGroup")
    cont.Size = UDim2.new(1, -28, 0, 52)
    cont.Position = UDim2.fromOffset(14, y)
    cont.BackgroundTransparency = 1
    cont.Parent = parent

    local lbl = crearTexto(cont, "", 14, COL_TEXTO)
    lbl.Size = UDim2.new(1, 0, 0, 20)

    local track = Instance.new("Frame")
    track.Size = UDim2.new(1, -20, 0, 8)
    track.Position = UDim2.fromOffset(10, 26)
    track.BackgroundColor3 = COL_BARRA
    track.BorderSizePixel = 0
    track.Parent = cont
    redondear(track, 4)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.fromScale(0, 1)
    fill.BackgroundColor3 = COL_ACENTO
    fill.BorderSizePixel = 0
    fill.Parent = track
    redondear(fill, 4)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(18, 18)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.fromScale(0, 0.5)
    knob.BackgroundColor3 = Color3.new(1, 1, 1)
    knob.BorderSizePixel = 0
    knob.Parent = track
    redondear(knob, 9)
    borde(knob, COL_ACENTO, 2)

    local lMin = crearTexto(cont, cfg.textoMin, 11, COL_SUB)
    lMin.Size = UDim2.fromOffset(60, 14)
    lMin.Position = UDim2.fromOffset(10, 38)

    local lMax = crearTexto(cont, cfg.textoMax, 11, COL_SUB)
    lMax.Size = UDim2.fromOffset(60, 14)
    lMax.Position = UDim2.new(1, -70, 0, 38)
    lMax.TextXAlignment = Enum.TextXAlignment.Right

    local function setValor(valor)
        valor = math.clamp(valor, cfg.min, cfg.max)
        local a = (valor - cfg.min) / (cfg.max - cfg.min)
        fill.Size = UDim2.fromScale(a, 1)
        knob.Position = UDim2.fromScale(a, 0.5)
        lbl.Text = cfg.formato(valor)
        cfg.alCambiar(valor)
    end

    local function desdeX(x)
        local a = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        local v = cfg.min + a * (cfg.max - cfg.min)
        setValor(math.floor(v / cfg.paso + 0.5) * cfg.paso)
    end

    local deslizando = false
    for _, obj in ipairs({ track, knob }) do
        conectar(obj.InputBegan, function(input)
            if esPuntero(input) then
                deslizando = true
                desdeX(input.Position.X)
            end
        end)
    end
    conectar(UserInputService.InputChanged, function(input)
        if deslizando and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            desdeX(input.Position.X)
        end
    end)
    conectar(UserInputService.InputEnded, function(input)
        if esPuntero(input) then deslizando = false end
    end)
    setValor(cfg.inicial)
    return cont
end

---------------------------------------------------------------------
-- UI
---------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "BurbujasUI"
gui.ResetOnSpawn = false
gui.Parent = PlayerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(260, 340)
panel.Position = UDim2.new(0, 20, 0.5, -170)
panel.BackgroundColor3 = COL_FONDO
panel.BorderSizePixel = 0
panel.Parent = gui
redondear(panel, 14)
borde(panel, COL_ACENTO, 1.5, 0.5)

local barra = Instance.new("Frame")
barra.Size = UDim2.new(1, 0, 0, 38)
barra.BackgroundColor3 = COL_BARRA
barra.BorderSizePixel = 0
barra.Parent = panel
redondear(barra, 14)

local tapa = Instance.new("Frame")
tapa.Size = UDim2.new(1, 0, 0, 14)
tapa.Position = UDim2.new(0, 0, 1, -14)
tapa.BackgroundColor3 = COL_BARRA
tapa.BorderSizePixel = 0
tapa.Parent = barra

local titulo = crearTexto(barra, "🫧  Auto Burbujas (safe) V1", 15, COL_TEXTO, Enum.Font.GothamBold)
titulo.Size = UDim2.new(1, -80, 1, 0)
titulo.Position = UDim2.fromOffset(14, 0)

local function crearBotonBarra(texto, posX)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(26, 26)
    b.Position = UDim2.new(1, posX, 0.5, -13)
    b.BackgroundColor3 = COL_FONDO
    b.Text = texto
    b.TextColor3 = COL_TEXTO
    b.Font = Enum.Font.GothamBold
    b.TextSize = 16
    b.Parent = barra
    redondear(b, 8)
    return b
end

local btnCerrar = crearBotonBarra("✕", -34)
local btnMin = crearBotonBarra("–", -66)
btnCerrar.MouseEnter:Connect(function() btnCerrar.BackgroundColor3 = COL_ROJO end)
btnCerrar.MouseLeave:Connect(function() btnCerrar.BackgroundColor3 = COL_FONDO end)

local burbuja = Instance.new("TextButton")
burbuja.Name = "Burbuja"
burbuja.Size = UDim2.fromOffset(52, 52)
burbuja.Position = panel.Position
burbuja.BackgroundColor3 = COL_ACENTO
burbuja.BackgroundTransparency = 0.15
burbuja.Text = "🫧"
burbuja.TextSize = 26
burbuja.AutoButtonColor = false
burbuja.Visible = false
burbuja.Parent = gui
redondear(burbuja, 26)
borde(burbuja, Color3.new(1, 1, 1), 2, 0.4)

crearFilaSwitch(panel, 48, "Auto burbujas: OFF", COL_ON, false, function(valor, lbl)
    activo = valor
    if not activo then
        recolectando = false
        if not tpAleatorio then quitarPlataforma() end
    end
    lbl.Text = valor and "Auto burbujas: ON" or "Auto burbujas: OFF"
    burbuja.BackgroundColor3 = valor and COL_ON or COL_ACENTO
    if actualizarInfo then actualizarInfo() end
end)

crearFilaSwitch(panel, 82, "TP aleatorio: OFF", COL_ACENTO, false, function(valor, lbl)
    tpAleatorio = valor
    visitados = {}
    if not valor and not activo then quitarPlataforma() end
    lbl.Text = valor and "TP aleatorio: ON" or "TP aleatorio: OFF"
end)

local sliderUmbral
crearFilaSwitch(panel, 116, "Según oxígeno: ON", COL_ON, true, function(valor, lbl)
    controlOxigeno = valor
    recolectando = false
    lbl.Text = valor and "Según oxígeno: ON" or "Según oxígeno: OFF"
    if sliderUmbral then
        sliderUmbral.GroupTransparency = valor and 0 or 0.55
    end
    if actualizarInfo then actualizarInfo() end
end)

local lblOxigeno = crearTexto(panel, "Oxígeno: …", 13, COL_SUB)
lblOxigeno.Size = UDim2.new(1, -28, 0, 18)
lblOxigeno.Position = UDim2.fromOffset(14, 148)

sliderUmbral = crearSlider(panel, 172, {
    min = UMBRAL_MIN, max = UMBRAL_MAX, paso = 5, inicial = umbralOxigeno,
    textoMin = "5%", textoMax = "95%",
    formato = function(v) return string.format("Recolectar si oxígeno ≤ %d%%", v) end,
    alCambiar = function(v)
        umbralOxigeno = v
        recolectando = false
        if actualizarInfo then actualizarInfo() end
    end,
})

crearSlider(panel, 228, {
    min = VEL_MIN, max = VEL_MAX, paso = 1, inicial = velocidad,
    textoMin = "Lento", textoMax = "Rápido",
    formato = function(v) return string.format("Velocidad: %d burb/s  (%.2fs)", v, 1 / v) end,
    alCambiar = function(v) velocidad = v end,
})

local lblContador = crearTexto(panel, "Recogidas: 0", 13, COL_SUB)
lblContador.Size = UDim2.new(1, -28, 0, 20)
lblContador.Position = UDim2.fromOffset(14, 290)

local lblEstado = crearTexto(panel, "Estado: inactivo", 11, COL_SUB)
lblEstado.Size = UDim2.new(1, -28, 0, 16)
lblEstado.Position = UDim2.fromOffset(14, 312)

actualizarInfo = function()
    local ox, mx = leerOxigeno()
    if not ox then
        lblOxigeno.Text = "Oxígeno: sin datos (recolecta siempre)"
    else
        local estado
        if not activo then estado = "inactivo"
        elseif not controlOxigeno then estado = "recolección continua"
        elseif recolectando then estado = "recolectando"
        else estado = "en espera" end
        lblOxigeno.Text = string.format("Oxígeno: %.0f / %.0f  ·  %s", ox, mx, estado)
    end
    if tick() < pausaHasta then
        lblEstado.Text = string.format("Estado: pausa humana (%.1fs)", pausaHasta - tick())
    else
        lblEstado.Text = "Estado: " .. (activo and "activo" or "inactivo")
    end
end

conectar(LocalPlayer:GetAttributeChangedSignal("Oxygen"), actualizarInfo)
conectar(LocalPlayer:GetAttributeChangedSignal("MaxOxygen"), actualizarInfo)
actualizarInfo()

local function minimizar()
    burbuja.Position = panel.Position
    panel.Visible = false
    burbuja.Visible = true
end

local function restaurar()
    panel.Position = burbuja.Position
    burbuja.Visible = false
    panel.Visible = true
end

local function cerrar()
    cerrado = true
    activo = false
    tpAleatorio = false
    quitarPlataforma()
    for _, c in ipairs(conexiones) do c:Disconnect() end
    table.clear(conexiones)
    gui:Destroy()
end

btnMin.MouseButton1Click:Connect(minimizar)
btnCerrar.MouseButton1Click:Connect(cerrar)
hacerArrastrable(barra, panel)
hacerArrastrable(burbuja, burbuja, restaurar)

---------------------------------------------------------------------
-- Lógica principal
---------------------------------------------------------------------
local function recogerBurbujas()
    if not debeRecolectar() then return end
    if tick() < pausaHasta then return end

    local root = getRoot()
    if not root or not root.Parent then return end
    if not estadoSeguro() then return end

    -- Si el jugador se ha movido a mano recientemente, pausa un poco
    if DETECTAR_INPUT and (tick() - lastInputTime) < 0.8 then
        return
    end

    local folder = Workspace:FindFirstChild("EnvironmentOxygenBubbles", true)
    if not folder then
        lblContador.Text = "Recogidas: " .. recogidas .. "  (sin burbujas)"
        return
    end

    -- Recolectar solo unas pocas por ciclo
    local hechas = 0
    for _, bubble in ipairs(folder:GetChildren()) do
        if not activo then break end
        if not debeRecolectar() then break end
        if tick() < pausaHasta then break end
        if hechas >= BURBUJAS_POR_CICLO then break end
        if not bubble.Parent then continue end

        local pos = getPosition(bubble)
        if not pos then continue end
        local dist = (root.Position - pos).Magnitude
        if dist <= RADIO then
            local ok = teleportarSuave(root, pos)
            if ok then
                recogidas = recogidas + 1
                hechas = hechas + 1
                lblContador.Text = "Recogidas: " .. recogidas

                -- Pausa humana entre burbujas: 1/vel ± 40%
                local base = 1 / velocidad
                task.wait(humanDelay(base, base * 0.4))

                -- Pausa larga cada N burbujas
                if recogidas % PAUSA_CADA == 0 then
                    local p = math.random() * (PAUSA_MAX - PAUSA_MIN) + PAUSA_MIN
                    pausaHasta = tick() + p
                    if actualizarInfo then actualizarInfo() end
                    task.wait(p)
                end
            else
                -- No se pudo TP (estado inseguro o ya estamos cerca): saltar esta
                task.wait(0.1)
            end
        end
    end

    root = getRoot()
    if activo and hechas > 0 and not tpAleatorio and root and root.Parent then
        crearPlataforma(DESTINO)
        root.CFrame = CFrame.new(DESTINO)
        -- OJO: ya no ponemos AssemblyLinearVelocity = zero
    end
end

-- Bucle 1: auto burbujas
task.spawn(function()
    while not cerrado do
        task.wait(humanDelay(INTERVALO, INTERVALO_JITTER))
        if not cerrado and activo and tick() >= pausaHasta then
            ocupado = true
            local ok, err = pcall(recogerBurbujas)
            ocupado = false
            if not ok then warn("[ERROR burbujas]", err) end
        end
    end
end)

-- Bucle 2: TP aleatorio
task.spawn(function()
    while not cerrado do
        task.wait(humanDelay(INTERVALO_TP, 0.4))
        if not cerrado and tpAleatorio and not ocupado
        and tick() >= pausaHasta
        and (not DETECTAR_INPUT or (tick() - lastInputTime) > 1.2)
        and estadoSeguro() then
            local ok, err = pcall(function()
                local root = getRoot()
                if not root or not root.Parent then return end
                local destino = posicionAleatoria(root.Position)
                crearPlataforma(destino)
                teleportarSuave(root, destino)
            end)
            if not ok then warn("[ERROR tp aleatorio]", err) end
        end
    end
end)

-- Actualizar UI periódicamente
task.spawn(function()
    while not cerrado do
        task.wait(1)
        if actualizarInfo then actualizarInfo() end
    end
end)
