--[[  AUTO BURBUJAS
    - Auto recolección de burbujas según el nivel de oxígeno
    - TP aleatorio sin repetir ubicaciones
    - Evadir mobs: si un enemigo se acerca, hace TP a una zona lejos de él
--]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

---------------------------------------------------------------------
-- Configuración
---------------------------------------------------------------------
local RADIO = 100000                 -- radio de recolección
local INTERVALO = 1.5                -- segundos base entre ciclos
local INTERVALO_JITTER = 0.6         -- ±variación aleatoria
local INTERVALO_TP = 1.8             -- segundos entre TPs aleatorios
local DESTINO = Vector3.new(11, 49, -553)
local ALTURA_PLATAFORMA = 3.5        -- distancia centro del personaje -> centro de la plataforma

local VEL_MIN, VEL_MAX = 1, 15       -- burbujas por segundo
local UMBRAL_MIN, UMBRAL_MAX = 5, 95

local RADIO_TP = 120                 -- radio de TP aleatorio
local SEPARACION = 60
local CANDIDATOS = 60

local PAUSA_CADA = 15                -- cada N burbujas, pausa larga
local PAUSA_MIN, PAUSA_MAX = 4, 9    -- segundos de pausa
local BURBUJAS_POR_CICLO = 3         -- burbujas máximas por ciclo
local DETECTAR_INPUT = true          -- pausar si el jugador se mueve a mano (no aplica en modo rápido)
local BURBUJA_ENFRIAMIENTO = 1       -- segundos antes de volver a visitar la misma burbuja
local MIN_PERMANENCIA = 0.25         -- segundos mínimos sobre la burbuja (para que registre el toque)

-- Movimiento hacia las burbujas
local MOVIMIENTO_SUAVE = true        -- true = desliza con Tween; false = TP instantáneo
local VELOCIDAD_TWEEN = 300          -- studs por segundo del deslizamiento
local TWEEN_MAX = 0.5                -- duración máxima de cada desplazamiento (segundos)

-- Evadir mobs
local CARPETA_ENEMIGOS = "Enemies"   -- Workspace.<nombre> con los enemigos
local DISTANCIA_SEGURA = 25          -- si un mob está más cerca que esto, hace TP lejos
local DISTANCIA_DESTINO_MIN = 60     -- el punto de escape debe quedar al menos así de lejos de todos los mobs
local INTERVALO_EVASION = 0.1        -- cada cuánto revisa los mobs
local EVASION_COOLDOWN = 0.3         -- mínimo entre dos evasiones

-- Estado
local velocidad = 6
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
local evadirMobs = false
local evasiones = 0
local ultimaEvasion = 0
local visitaBurbuja = setmetatable({}, { __mode = "k" })
local dbg = { total = 0, rango = 0, tpOk = 0, tpFail = 0, motivo = "—" }

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
-- Detección de input (pausar si te mueves a mano)
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

-- Posición de la burbuja: usa su parte física (PrimaryPart o la primera BasePart);
-- el pivote del modelo puede quedar desplazado respecto a donde se detecta el toque.
local function posBurbuja(obj)
    if obj:IsA("Model") then
        local parte = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
        if parte then return parte.Position end
        return obj:GetPivot().Position
    elseif obj:IsA("BasePart") then
        return obj.Position
    end
end

-- Lista NEGRA: solo se bloquea cuando el personaje no está en condiciones.
local ESTADOS_BLOQUEADOS = {
    [Enum.HumanoidStateType.Dead] = true,
    [Enum.HumanoidStateType.Ragdoll] = true,
    [Enum.HumanoidStateType.FallingDown] = true,
}

local function estadoSeguro()
    local hum = getHumanoid()
    if not hum then return false end
    if hum.Health <= 0 then return false end
    return not ESTADOS_BLOQUEADOS[hum:GetState()]
end

-- Plataforma invisible: sostiene al personaje (ya no se ve el "cuerpo fantasma")
local function crearPlataforma(posicion)
    if not plataforma or not plataforma.Parent then
        plataforma = Instance.new("Part")
        plataforma.Name = "FloatPlatform"
        plataforma.Size = Vector3.new(12, 1, 12)
        plataforma.Anchored = true
        plataforma.CanCollide = true
        plataforma.CanQuery = false
        plataforma.CanTouch = false
        plataforma.Transparency = 1
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

-- Desliza al personaje (y opcionalmente la plataforma) hasta "meta".
-- Interpolación manual: si una evasión de mob ocurre a mitad de camino, se
-- detecta antes de cada paso y el deslizamiento se corta sin pisar el TP de escape.
local function deslizar(root, meta, dur, platDestino, continuar)
    local inicio = root.CFrame
    local platInicio = plataforma and plataforma.Parent and plataforma.Position
    local evasionInicial = ultimaEvasion
    local t0 = tick()
    while true do
        if cerrado or not root.Parent or ultimaEvasion ~= evasionInicial or not continuar() then
            return false
        end
        local a = math.min((tick() - t0) / dur, 1)
        root.CFrame = inicio:Lerp(meta, a)
        root.AssemblyLinearVelocity = Vector3.zero
        if platInicio and platDestino and plataforma and plataforma.Parent then
            plataforma.Position = platInicio:Lerp(platDestino, a)
        end
        if a >= 1 then return true end
        task.wait()
    end
end

local function duracionPara(dist)
    return math.clamp(dist / VELOCIDAD_TWEEN, 0.08, TWEEN_MAX)
end

-- Ir a una burbuja (suave o instantáneo según MOVIMIENTO_SUAVE).
local function teleportarA(root, destino)
    if not root or not root.Parent then return false end
    if not estadoSeguro() then return false end

    local rot = root.CFrame - root.CFrame.Position
    local meta = CFrame.new(destino) * rot
    local dist = (root.Position - destino).Magnitude

    if not MOVIMIENTO_SUAVE or dist < 4 then
        root.CFrame = meta
        local v = root.AssemblyLinearVelocity
        root.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
        return true
    end

    local llego = deslizar(root, meta, duracionPara(dist), nil, function() return activo end)
    if root.Parent then root.AssemblyLinearVelocity = Vector3.zero end
    return llego
end

-- Coloca la plataforma Y el personaje encima en el mismo instante (sin yield).
-- forzar = true ignora el estado del personaje (se usa para huir de mobs).
local function irAPlataforma(root, destino, forzar)
    if not root or not root.Parent then return false end
    if not forzar and not estadoSeguro() then return false end

    crearPlataforma(destino)

    local rot = root.CFrame - root.CFrame.Position
    root.CFrame = CFrame.new(destino) * rot
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    return true
end

-- Igual que irAPlataforma pero deslizando personaje y plataforma juntos (TP aleatorio).
local function irAPlataformaSuave(root, destino)
    if not root or not root.Parent then return false end
    if not estadoSeguro() then return false end

    local dist = (root.Position - destino).Magnitude
    if not MOVIMIENTO_SUAVE or dist < 4 then
        return irAPlataforma(root, destino)
    end

    crearPlataforma(root.Position) -- plataforma bajo los pies antes de empezar
    local rot = root.CFrame - root.CFrame.Position
    local meta = CFrame.new(destino) * rot
    local platDestino = destino - Vector3.new(0, ALTURA_PLATAFORMA, 0)

    local llego = deslizar(root, meta, duracionPara(dist), platDestino,
        function() return tpAleatorio and not ocupado end)
    if root.Parent then root.AssemblyLinearVelocity = Vector3.zero end
    return llego
end

-- Elige el candidato más lejano a todos los puntos ya usados
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
-- Mobs
---------------------------------------------------------------------
-- Posiciones de los enemigos (Workspace.Enemies)
local function posicionesEnemigos()
    local lista = {}
    local carpeta = Workspace:FindFirstChild(CARPETA_ENEMIGOS)
    if not carpeta then return lista end
    for _, enemigo in ipairs(carpeta:GetChildren()) do
        local r = enemigo:FindFirstChild("HumanoidRootPart")
        if r then
            local hum = enemigo:FindFirstChildOfClass("Humanoid")
            if not hum or hum.Health > 0 then
                table.insert(lista, r.Position)
            end
        end
    end
    return lista
end

local function distanciaMinima(punto, enemigos)
    local minD = math.huge
    for _, e in ipairs(enemigos) do
        local d = (e - punto).Magnitude
        if d < minD then minD = d end
    end
    return minD
end

-- Punto de escape: el más lejano a TODOS los mobs, alrededor del DESTINO.
-- Si ninguno cumple la distancia mínima, se queda con el mejor encontrado.
local function posicionSegura(enemigos, origen)
    local mejor, mejorDist = nil, -1
    for _ = 1, CANDIDATOS do
        local ang = math.random() * math.pi * 2
        local dist = math.sqrt(math.random()) * RADIO_TP
        local cand = DESTINO + Vector3.new(math.cos(ang) * dist, 0, math.sin(ang) * dist)
        local minD = distanciaMinima(cand, enemigos)
        -- desempate: a igual distancia a los mobs, prefiere el punto más cercano al jugador
        if minD > mejorDist then
            mejor, mejorDist = cand, minD
        end
    end
    return mejor, mejorDist
end

---------------------------------------------------------------------
-- Helpers de UI
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
panel.Size = UDim2.fromOffset(260, 384)
panel.Position = UDim2.new(0, 20, 0.5, -192)
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

local titulo = crearTexto(barra, "MAYK V1", 15, COL_TEXTO, Enum.Font.GothamBold)
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
        if not tpAleatorio and not evadirMobs then quitarPlataforma() end
    end
    lbl.Text = valor and "Auto burbujas: ON" or "Auto burbujas: OFF"
    burbuja.BackgroundColor3 = valor and COL_ON or COL_ACENTO
    if actualizarInfo then actualizarInfo() end
end)

crearFilaSwitch(panel, 82, "TP aleatorio: OFF", COL_ACENTO, false, function(valor, lbl)
    tpAleatorio = valor
    visitados = {}
    if not valor and not activo and not evadirMobs then quitarPlataforma() end
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

crearFilaSwitch(panel, 150, "Evadir mobs: OFF", COL_ROJO, false, function(valor, lbl)
    evadirMobs = valor
    if not valor and not activo and not tpAleatorio then quitarPlataforma() end
    lbl.Text = valor and "Evadir mobs: ON" or "Evadir mobs: OFF"
end)

local lblOxigeno = crearTexto(panel, "Oxígeno: …", 13, COL_SUB)
lblOxigeno.Size = UDim2.new(1, -28, 0, 18)
lblOxigeno.Position = UDim2.fromOffset(14, 182)

sliderUmbral = crearSlider(panel, 206, {
    min = UMBRAL_MIN, max = UMBRAL_MAX, paso = 5, inicial = umbralOxigeno,
    textoMin = "5%", textoMax = "95%",
    formato = function(v) return string.format("Recolectar si oxígeno ≤ %d%%", v) end,
    alCambiar = function(v)
        umbralOxigeno = v
        recolectando = false
        if actualizarInfo then actualizarInfo() end
    end,
})

crearSlider(panel, 262, {
    min = VEL_MIN, max = VEL_MAX, paso = 1, inicial = velocidad,
    textoMin = "Lento", textoMax = "Rápido",
    formato = function(v) return string.format("Velocidad: %d burb/s  (%.2fs)", v, 1 / v) end,
    alCambiar = function(v) velocidad = v end,
})

local lblContador = crearTexto(panel, "Recogidas: 0  ·  Evasiones: 0", 13, COL_SUB)
lblContador.Size = UDim2.new(1, -28, 0, 20)
lblContador.Position = UDim2.fromOffset(14, 324)

local function actualizarContador()
    lblContador.Text = string.format("Recogidas: %d  ·  Evasiones: %d", recogidas, evasiones)
end

local lblEstado = crearTexto(panel, "Estado: inactivo", 11, COL_SUB)
lblEstado.Size = UDim2.new(1, -28, 0, 28)
lblEstado.Position = UDim2.fromOffset(14, 346)
lblEstado.TextWrapped = true
lblEstado.TextYAlignment = Enum.TextYAlignment.Top

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
    local base
    if tick() < pausaHasta then
        base = string.format("pausa %.1fs", pausaHasta - tick())
    else
        base = activo and "activo" or "inactivo"
    end
    lblEstado.Text = string.format("%s · %s\nBurb %d · en rango %d · TP %d ok / %d fallo",
        base, dbg.motivo, dbg.total, dbg.rango, dbg.tpOk, dbg.tpFail)
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
    evadirMobs = false
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
-- Modo rápido: el oxígeno está bajo el umbral y hay que llenar cuanto antes.
local function esRapido()
    return controlOxigeno and recolectando
end

local function recogerBurbujas()
    if not debeRecolectar() then dbg.motivo = "oxígeno alto: en espera"; return end
    if tick() < pausaHasta then dbg.motivo = "pausa"; return end

    local root = getRoot()
    if not root or not root.Parent then dbg.motivo = "sin personaje"; return end
    if not estadoSeguro() then dbg.motivo = "estado no válido"; return end

    -- fuera del modo rápido, pausa si el jugador se mueve a mano
    if not esRapido() and DETECTAR_INPUT and (tick() - lastInputTime) < 0.8 then
        dbg.motivo = "pausa por input"
        return
    end

    local folder = Workspace:FindFirstChild("EnvironmentOxygenBubbles", true)
    if not folder then
        dbg.motivo = "no existe la carpeta de burbujas"
        actualizarContador()
        return
    end

    local hechas = 0
    local pasadas = 0

    repeat
        pasadas = pasadas + 1
        local enPasada = 0
        local rapido = esRapido()
        local limite = rapido and math.huge or BURBUJAS_POR_CICLO

        root = getRoot()
        if not root or not root.Parent then break end
        local origen = root.Position

        -- con "Evadir mobs" activo, no va a burbujas que tengan un mob encima
        local enemigos = evadirMobs and posicionesEnemigos() or {}

        -- lista de burbujas disponibles, la más cercana primero
        local lista = {}
        local total, enRango = 0, 0
        for _, bubble in ipairs(folder:GetChildren()) do
            total = total + 1
            local pos = posBurbuja(bubble)
            if pos then
                local d = (origen - pos).Magnitude
                if d <= RADIO then
                    enRango = enRango + 1
                    local ultima = visitaBurbuja[bubble]
                    local libre = not ultima or (tick() - ultima) >= BURBUJA_ENFRIAMIENTO
                    local segura = #enemigos == 0 or distanciaMinima(pos, enemigos) > DISTANCIA_SEGURA
                    if libre and segura then
                        table.insert(lista, { obj = bubble, pos = pos, d = d })
                    end
                end
            end
        end
        table.sort(lista, function(x, y) return x.d < y.d end)

        dbg.total, dbg.rango = total, enRango
        if #lista == 0 then
            if total == 0 then
                dbg.motivo = "carpeta vacía (sin burbujas)"
            elseif enRango == 0 then
                dbg.motivo = "burbujas fuera de rango"
            else
                dbg.motivo = "burbujas reapareciendo / mobs cerca"
            end
        end

        for _, item in ipairs(lista) do
            if not activo then break end
            if not debeRecolectar() then break end
            if tick() < pausaHasta then break end
            if hechas >= limite then break end
            if not item.obj.Parent then continue end

            root = getRoot()
            if not root or not root.Parent then break end

            -- la burbuja flota: toma su posición actual justo antes del TP
            local pos = posBurbuja(item.obj) or item.pos

            -- revisa otra vez que no haya un mob encima justo antes del TP
            if evadirMobs then
                local en = posicionesEnemigos()
                if #en > 0 and distanciaMinima(pos, en) <= DISTANCIA_SEGURA then
                    continue
                end
            end

            if teleportarA(root, pos) then
                visitaBurbuja[item.obj] = tick()
                recogidas = recogidas + 1
                hechas = hechas + 1
                enPasada = enPasada + 1
                dbg.tpOk = dbg.tpOk + 1
                dbg.motivo = "recolectando"
                actualizarContador()

                -- permanece un mínimo sobre la burbuja para que se registre el toque
                local espera = math.max(1 / velocidad, MIN_PERMANENCIA)
                task.wait(humanDelay(espera, espera * (rapido and 0.1 or 0.3)))

                if not rapido and recogidas % PAUSA_CADA == 0 then
                    local p = math.random() * (PAUSA_MAX - PAUSA_MIN) + PAUSA_MIN
                    pausaHasta = tick() + p
                    if actualizarInfo then actualizarInfo() end
                    task.wait(p)
                end
            else
                dbg.tpFail = dbg.tpFail + 1
                dbg.motivo = "TP bloqueado (estado del personaje)"
                task.wait(0.1)
            end
        end
    until not (esRapido() and activo and enPasada > 0 and pasadas < 30)

    -- Sin TP aleatorio: vuelve al destino y se queda encima de la plataforma.
    root = getRoot()
    if activo and hechas > 0 and not tpAleatorio and root and root.Parent then
        irAPlataforma(root, DESTINO)
    end
end

-- Bucle 1: auto burbujas
task.spawn(function()
    while not cerrado do
        if controlOxigeno then
            task.wait(0.3 + math.random() * 0.2)
        else
            task.wait(humanDelay(INTERVALO, INTERVALO_JITTER))
        end
        if not cerrado and activo and tick() >= pausaHasta then
            ocupado = true
            local ok, err = pcall(recogerBurbujas)
            ocupado = false
            if not ok then warn("[ERROR burbujas]", err) end
        end
    end
end)

-- Bucle 2: TP aleatorio (independiente del interruptor principal)
task.spawn(function()
    while not cerrado do
        task.wait(humanDelay(INTERVALO_TP, 0.4))
        if not cerrado and tpAleatorio and not ocupado
        and tick() >= pausaHasta
        and (not DETECTAR_INPUT or (tick() - lastInputTime) > 1.2) then
            local ok, err = pcall(function()
                local root = getRoot()
                if not root or not root.Parent then return end

                -- si hay mobs y "Evadir mobs" está activo, no cae cerca de ellos
                local destino = posicionAleatoria(root.Position)
                if evadirMobs then
                    local en = posicionesEnemigos()
                    if #en > 0 and distanciaMinima(destino, en) <= DISTANCIA_SEGURA then
                        destino = posicionSegura(en, root.Position)
                    end
                end
                irAPlataformaSuave(root, destino)
            end)
            if not ok then warn("[ERROR tp aleatorio]", err) end
        end
    end
end)

-- Bucle 3: evadir mobs por TELETRANSPORTE (independiente del resto)
task.spawn(function()
    while not cerrado do
        task.wait(INTERVALO_EVASION)
        if not cerrado and evadirMobs and (tick() - ultimaEvasion) >= EVASION_COOLDOWN then
            local ok, err = pcall(function()
                local root = getRoot()
                local hum = getHumanoid()
                if not root or not root.Parent then return end
                if hum and hum.Health <= 0 then return end

                local enemigos = posicionesEnemigos()
                if #enemigos == 0 then return end

                -- ¿algún mob demasiado cerca?
                if distanciaMinima(root.Position, enemigos) >= DISTANCIA_SEGURA then return end

                -- TP a la zona más lejana de todos los mobs
                local destino, dist = posicionSegura(enemigos, root.Position)
                if destino and irAPlataforma(root, destino, true) then
                    ultimaEvasion = tick()
                    evasiones = evasiones + 1
                    dbg.motivo = string.format("evadió mob (nuevo punto a %.0f)", dist == math.huge and 999 or dist)
                    actualizarContador()
                end
            end)
            if not ok then warn("[ERROR evadir mobs]", err) end
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
