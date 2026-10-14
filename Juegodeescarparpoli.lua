-----------------------------------------------------------------------------
-----------------------------MAYKEL CREADOR ---------------------------------
-----------------------------------------------------------------------------
--[[  AUTO BURBUJAS (móvil + PC) · UI MODULAR · SOLO DESPLAZAMIENTO

    Ya no hay ningún TP: TODO el movimiento (ir a burbujas, moverse al azar,
    evadir mobs, huir por daño y volver al punto base) se hace desplazándose
    de forma continua, avanzando a una velocidad fija (studs/s) frame a frame.
    Nunca se salta de un punto a otro de golpe.

    Pestañas:
      • BURBUJAS   → auto burbujas, "según oxígeno" y umbral
      • MOVIMIENTO → movimiento aleatorio y evadir mobs

    Velocidades y demás se ajustan en las secciones "AJUSTES" de abajo.

    Secciones marcadas para localizarlas rápido:
      [CAMBIO 1] burbuja más alejada de los enemigos (con "Evadir mobs")
      [CAMBIO 2] movimiento aleatorio con sesgo al centro
      [CAMBIO 3] modo EMERGENCIA cuando el oxígeno baja del 5 %
--]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

---------------------------------------------------------------------
-- ╔═══════════════════════════════════════════════════════════════╗
-- ║              AJUSTES DE VELOCIDAD (EDITA AQUÍ)                ║
-- ╚═══════════════════════════════════════════════════════════════╝
-- VELOCIDAD_BURBUJAS     = burbujas por segundo (1 lento, 2 normal, 3 rápido)
-- VELOCIDAD_ALEATORIO    = movimientos aleatorios por segundo (0.5 = 1 cada 2 s)
-- TIEMPO_SOBRE_BURBUJA   = segundos mínimos sobre cada burbuja
-- VELOCIDAD_MOV_BURBUJAS = studs/s al desplazarse hacia una burbuja
-- VELOCIDAD_MOV_ALEATORIO= studs/s en el movimiento aleatorio
-- VELOCIDAD_HUIDA        = studs/s al huir de un mob
-- HUIR_AL_RECIBIR_DANO   = true/false
-- VELOCIDAD_HUIDA_DANO   = studs/s al huir por daño
-- DANO_MINIMO            = vida mínima perdida de golpe para activar la huida
---------------------------------------------------------------------
local VELOCIDAD_BURBUJAS = 2
local VELOCIDAD_ALEATORIO = 0.5
local TIEMPO_SOBRE_BURBUJA = 0.35
local VELOCIDAD_MOV_BURBUJAS = 80
local VELOCIDAD_MOV_ALEATORIO = 50
local VELOCIDAD_HUIDA = 65
local HUIR_AL_RECIBIR_DANO = true
local VELOCIDAD_HUIDA_DANO = 100
local DANO_MINIMO = 1

-- [CAMBIO 3] MODO EMERGENCIA (oxígeno crítico)
-- EMERGENCIA_OXIGENO = % de oxígeno por debajo (o igual) del cual se recolecta
--                      sí o sí (ignora umbral, "Según oxígeno", pausas, input
--                      manual y enemigos cerca). Solo actúa con "Auto burbujas" ON.
-- EMERGENCIA_SALIDA  = % al que debe subir el oxígeno para volver a lo normal
--                      (99.5 = igual que "recolectando"; pon 6 para salir apenas
--                      supere el 5 %).
local EMERGENCIA_OXIGENO = 5
local EMERGENCIA_SALIDA = 99.5
---------------------------------------------------------------------
-- FIN DE LOS AJUSTES DE VELOCIDAD
---------------------------------------------------------------------

---------------------------------------------------------------------
-- Configuración general (no hace falta tocar)
---------------------------------------------------------------------
local RADIO = 100000
local INTERVALO = 1.5
local INTERVALO_JITTER = 1.2
local DESTINO = Vector3.new(11, 49, -553)
local ALTURA_PLATAFORMA = 3.5

local UMBRAL_MIN, UMBRAL_MAX = 5, 95

local RADIO_ALEATORIO = 300
local SEPARACION = 60
local CANDIDATOS = 60

-- [CAMBIO 2] Movimiento aleatorio inteligente
local SESGO_CENTRO = 0.8     -- si el jugador está a más de RADIO_ALEATORIO * esto del centro, vuelve hacia él
local SESGO_ANGULO = 45      -- grados de dispersión alrededor de la dirección al centro
local MAX_VISITADOS = 12     -- máximo de puntos recordados en "visitados"
local CAIDA_MAXIMA = 30      -- studs: no elegir destinos más bajos que esto respecto al jugador

local PAUSA_CADA = 8
local PAUSA_MIN, PAUSA_MAX = 4, 9
local BURBUJAS_POR_CICLO = 3
local DETECTAR_INPUT = true
local BURBUJA_ENFRIAMIENTO = 1

-- Evadir mobs
local CARPETA_ENEMIGOS = "Enemies"
local DISTANCIA_SEGURA = 6
local INTERVALO_EVASION = 0.02
local EVASION_COOLDOWN = 0.3

-- Tamaño base del panel (se escala solo en pantallas pequeñas)
local PANEL_W, PANEL_H = 300, 400
local BURBUJA_TAM = 56

-- Estado
local velocidad = math.max(0.1, VELOCIDAD_BURBUJAS)
local velocidadAleatoria = math.max(0.1, VELOCIDAD_ALEATORIO)
local MIN_PERMANENCIA = math.max(0, TIEMPO_SOBRE_BURBUJA)
local umbralOxigeno = 50
local controlOxigeno = true
local recolectando = false
local activo = false
local moverAleatorio = false
local cerrado = false
local ocupado = false
local recogidas = 0
local plataforma = nil
local visitados = {}
local conexiones = {}
local actualizarInfo
local pausaHasta = 0
local lastInputTime = 0
local evadirMobs = false
local evasiones = 0
local ultimaEvasion = 0
local evadiendo = false
local emergencia = false          -- [CAMBIO 3]
local visitaBurbuja = setmetatable({}, { __mode = "k" })
local dbg = { total = 0, rango = 0, movOk = 0, movFail = 0, motivo = "—" }

-- Paleta
local COL_FONDO   = Color3.fromRGB(18, 20, 30)
local COL_BARRA   = Color3.fromRGB(26, 29, 43)
local COL_CARD    = Color3.fromRGB(33, 37, 56)
local COL_ACENTO  = Color3.fromRGB(88, 166, 255)
local COL_ON      = Color3.fromRGB(52, 199, 120)
local COL_OFF     = Color3.fromRGB(84, 90, 114)
local COL_ROJO    = Color3.fromRGB(235, 87, 87)
local COL_TEXTO   = Color3.fromRGB(240, 243, 252)
local COL_SUB     = Color3.fromRGB(148, 155, 182)

local function conectar(senal, fn)
    local c = senal:Connect(fn)
    table.insert(conexiones, c)
    return c
end

local function humanDelay(base, jitter)
    return base + (math.random() * 2 - 1) * jitter
end

local function viewport()
    local cam = Workspace.CurrentCamera
    return cam and cam.ViewportSize or Vector2.new(800, 400)
end

---------------------------------------------------------------------
-- Detección de movimiento manual (joystick / teclado)
---------------------------------------------------------------------
if DETECTAR_INPUT then
    task.spawn(function()
        while not cerrado do
            task.wait(0.1)
            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum and hum.MoveDirection.Magnitude > 0.1 then
                lastInputTime = tick()
            end
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

-- [CAMBIO 3] Detecta / mantiene el modo emergencia (histéresis: entra en
-- EMERGENCIA_OXIGENO, sale en EMERGENCIA_SALIDA). Solo cuenta con auto burbujas ON.
local function actualizarEmergencia()
    local antes = emergencia
    local ox, mx = leerOxigeno()
    if not activo or not ox then
        emergencia = false
    else
        local pct = ox / mx * 100
        if emergencia then
            if pct >= EMERGENCIA_SALIDA then emergencia = false end
        elseif pct <= EMERGENCIA_OXIGENO then
            emergencia = true
        end
    end
    if emergencia and not antes then pausaHasta = 0 end -- cancela cualquier pausa humana
    if antes ~= emergencia and actualizarInfo then actualizarInfo() end
    return emergencia
end

local function debeRecolectar()
    if actualizarEmergencia() then return true end -- [CAMBIO 3] emergencia: recolecta sí o sí
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

local function posBurbuja(obj)
    if obj:IsA("Model") then
        local parte = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
        if parte then return parte.Position end
        return obj:GetPivot().Position
    elseif obj:IsA("BasePart") then
        return obj.Position
    end
end

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

---------------------------------------------------------------------
-- DESPLAZAMIENTO CONTINUO (sin TP)
-- Avanza hacia el destino a "vel" studs por segundo, frame a frame.
-- Si "seguirPlataforma" es true, la plataforma acompaña al personaje.
---------------------------------------------------------------------
local function desplazar(root, destino, vel, seguirPlataforma, continuar)
    local rot = root.CFrame - root.CFrame.Position
    local evasionInicial = ultimaEvasion
    vel = math.max(vel, 1)

    while true do
        if cerrado or not root.Parent or ultimaEvasion ~= evasionInicial or not continuar() then
            return false
        end

        local dt = RunService.Heartbeat:Wait()
        dt = math.min(dt, 0.1) -- evita saltos grandes si hay lag

        local pos = root.Position
        local falta = destino - pos
        local dist = falta.Magnitude
        local paso = vel * dt

        local nueva
        local llego = false
        if dist <= paso then
            nueva = destino
            llego = true
        else
            nueva = pos + falta.Unit * paso
        end

        root.CFrame = CFrame.new(nueva) * rot
        root.AssemblyLinearVelocity = Vector3.zero

        if seguirPlataforma and plataforma and plataforma.Parent then
            plataforma.Position = nueva - Vector3.new(0, ALTURA_PLATAFORMA, 0)
        end

        if llego then return true end
    end
end

-- [CAMBIO 3] En emergencia se usa la velocidad más alta disponible
local function velocidadEmergencia()
    return math.max(VELOCIDAD_HUIDA, VELOCIDAD_HUIDA_DANO)
end

-- Ir hacia una burbuja
local function desplazarA(root, destino, obj)
    if not root or not root.Parent then return false end
    if evadiendo or not estadoSeguro() then return false end

    local vel = emergencia and velocidadEmergencia() or VELOCIDAD_MOV_BURBUJAS
    local llego = desplazar(root, destino, vel, false, function()
        return activo and not evadiendo and (not obj or obj.Parent ~= nil)
    end)
    if root.Parent then root.AssemblyLinearVelocity = Vector3.zero end
    return llego
end

-- Ir a un punto llevando la plataforma debajo
local function irAPlataformaSuave(root, destino, opc)
    opc = opc or {}
    if not root or not root.Parent then return false end
    if not opc.forzar and not estadoSeguro() then return false end

    crearPlataforma(root.Position)
    local continuar = opc.continuar or function()
        return moverAleatorio and not ocupado and not evadiendo
    end

    local vel = opc.velocidad or (opc.rapido and VELOCIDAD_HUIDA) or VELOCIDAD_MOV_ALEATORIO
    local llego = desplazar(root, destino, vel, true, continuar)
    if root.Parent then root.AssemblyLinearVelocity = Vector3.zero end
    return llego
end

-- [CAMBIO 2] Candidato alrededor de DESTINO. Si el jugador está lejos del
-- centro (> RADIO_ALEATORIO * SESGO_CENTRO) el punto se genera EN DIRECCIÓN al
-- centro (con algo de dispersión) y más cerca de él, para que vuelva a la zona.
local function generarCandidato(origen)
    local plano = origen and Vector3.new(origen.X, DESTINO.Y, origen.Z) or DESTINO
    local aCentro = DESTINO - plano
    local distCentro = aCentro.Magnitude

    if distCentro > RADIO_ALEATORIO * SESGO_CENTRO then
        local dir = aCentro.Unit
        local ang = (math.random() * 2 - 1) * math.rad(SESGO_ANGULO)
        local c, sn = math.cos(ang), math.sin(ang)
        local rotada = Vector3.new(dir.X * c - dir.Z * sn, 0, dir.X * sn + dir.Z * c)
        local paso = distCentro * (0.4 + math.random() * 0.5)
        local cand = plano + rotada * paso
        local desdeCentro = cand - DESTINO
        if desdeCentro.Magnitude > RADIO_ALEATORIO then
            cand = DESTINO + desdeCentro.Unit * RADIO_ALEATORIO
        end
        return cand
    end

    local ang = math.random() * math.pi * 2
    local dist = math.sqrt(math.random()) * RADIO_ALEATORIO
    return DESTINO + Vector3.new(math.cos(ang) * dist, 0, math.sin(ang) * dist)
end

-- [CAMBIO 2] "Picado vertical": descarta destinos muy por debajo del jugador
local function candidatoValido(cand, origen)
    return not origen or (origen.Y - cand.Y) <= CAIDA_MAXIMA
end

-- Si ningún candidato fue válido, se sube el destino para no quedar cayendo
local function ajustarAltura(cand, origen)
    if origen and (origen.Y - cand.Y) > CAIDA_MAXIMA then
        return Vector3.new(cand.X, origen.Y - CAIDA_MAXIMA, cand.Z)
    end
    return cand
end

local function posicionAleatoria(origen)
    if #visitados == 0 and origen then
        table.insert(visitados, Vector3.new(origen.X, DESTINO.Y, origen.Z))
    end
    local mejor
    for pasada = 1, 2 do
        local mejorDist = -1
        for _ = 1, CANDIDATOS do
            local cand = generarCandidato(origen)
            if candidatoValido(cand, origen) then
                local minD = math.huge
                for _, v in ipairs(visitados) do
                    local d = (v - cand).Magnitude
                    if d < minD then minD = d end
                end
                if minD > mejorDist then
                    mejor, mejorDist = cand, minD
                end
            end
        end
        if (mejor and mejorDist >= SEPARACION) or pasada == 2 then break end
        local ultimo = visitados[#visitados]
        visitados = ultimo and { ultimo } or {}
    end
    if not mejor then
        mejor = ajustarAltura(generarCandidato(origen), origen)
    end
    table.insert(visitados, mejor)
    while #visitados > MAX_VISITADOS do
        table.remove(visitados, 1)
    end
    return mejor
end

---------------------------------------------------------------------
-- Mobs
---------------------------------------------------------------------
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

-- [CAMBIO 2] Elige, entre CANDIDATOS puntos (con el mismo sesgo al centro y el
-- filtro de caída), el de MAYOR distancia al enemigo más cercano.
local function posicionSegura(enemigos, origen)
    local mejor, mejorDist = nil, -1
    for _ = 1, CANDIDATOS do
        local cand = generarCandidato(origen)
        if candidatoValido(cand, origen) then
            local minD = distanciaMinima(cand, enemigos)
            if minD > mejorDist then
                mejor, mejorDist = cand, minD
            end
        end
    end
    if not mejor then
        mejor = ajustarAltura(generarCandidato(origen), origen)
        mejorDist = distanciaMinima(mejor, enemigos)
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
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
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

local function esMovimiento(input)
    return input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
end

local function clampear(obj, tam)
    local vs = viewport()
    local x = math.clamp(obj.Position.X.Offset, 0, math.max(0, vs.X - tam.X))
    local y = math.clamp(obj.Position.Y.Offset, 0, math.max(0, vs.Y - tam.Y))
    obj.Position = UDim2.fromOffset(x, y)
end

local function hacerArrastrable(handle, target, alTocar, tamano)
    local arrastrando, movido = false, false
    local inicioInput, inicioPos, inputDrag
    conectar(handle.InputBegan, function(input)
        if esPuntero(input) and not arrastrando then
            arrastrando, movido = true, false
            inputDrag = input
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
        if arrastrando and esMovimiento(input)
            and (input == inputDrag or input.UserInputType == Enum.UserInputType.MouseMovement) then
            local d = input.Position - inicioInput
            if d.Magnitude > 8 then movido = true end
            if movido then
                target.Position = UDim2.fromOffset(inicioPos.X.Offset + d.X, inicioPos.Y.Offset + d.Y)
                clampear(target, tamano())
            end
        end
    end)
end

-- Tarjeta con interruptor (toda la tarjeta es táctil)
local function crearFilaSwitch(parent, orden, titulo, subtitulo, colorOn, inicial, alCambiar)
    local card = Instance.new("TextButton")
    card.Size = UDim2.new(1, 0, 0, 54)
    card.BackgroundColor3 = COL_CARD
    card.BorderSizePixel = 0
    card.Text = ""
    card.AutoButtonColor = false
    card.LayoutOrder = orden
    card.Parent = parent
    redondear(card, 12)
    local trazo = borde(card, colorOn, 1.5, inicial and 0.45 or 1)

    local t = crearTexto(card, titulo, 15, COL_TEXTO, Enum.Font.GothamBold)
    t.Size = UDim2.new(1, -86, 0, 20)
    t.Position = UDim2.fromOffset(14, 9)

    local sub = crearTexto(card, subtitulo, 12, COL_SUB)
    sub.Size = UDim2.new(1, -86, 0, 16)
    sub.Position = UDim2.fromOffset(14, 30)
    sub.TextTruncate = Enum.TextTruncate.AtEnd

    local sw = Instance.new("Frame")
    sw.Size = UDim2.fromOffset(52, 30)
    sw.AnchorPoint = Vector2.new(1, 0.5)
    sw.Position = UDim2.new(1, -12, 0.5, 0)
    sw.BackgroundColor3 = inicial and colorOn or COL_OFF
    sw.BorderSizePixel = 0
    sw.Parent = card
    redondear(sw, 15)

    local perilla = Instance.new("Frame")
    perilla.Size = UDim2.fromOffset(24, 24)
    perilla.Position = UDim2.fromOffset(inicial and 25 or 3, 3)
    perilla.BackgroundColor3 = Color3.new(1, 1, 1)
    perilla.BorderSizePixel = 0
    perilla.Parent = sw
    redondear(perilla, 12)

    local estado = inicial == true
    card.MouseButton1Click:Connect(function()
        estado = not estado
        local info = TweenInfo.new(0.16, Enum.EasingStyle.Quad)
        TweenService:Create(sw, info, { BackgroundColor3 = estado and colorOn or COL_OFF }):Play()
        TweenService:Create(perilla, info, { Position = UDim2.fromOffset(estado and 25 or 3, 3) }):Play()
        TweenService:Create(trazo, info, { Transparency = estado and 0.45 or 1 }):Play()
        alCambiar(estado)
    end)
    return card
end

-- Tarjeta informativa (sin interruptor)
local function crearInfo(parent, orden, titulo, subtitulo)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, 54)
    card.BackgroundColor3 = COL_CARD
    card.BackgroundTransparency = 0.35
    card.BorderSizePixel = 0
    card.LayoutOrder = orden
    card.Parent = parent
    redondear(card, 12)

    local t = crearTexto(card, titulo, 14, COL_TEXTO, Enum.Font.GothamBold)
    t.Size = UDim2.new(1, -28, 0, 20)
    t.Position = UDim2.fromOffset(14, 9)

    local sub = crearTexto(card, subtitulo, 12, COL_SUB)
    sub.Size = UDim2.new(1, -28, 0, 16)
    sub.Position = UDim2.fromOffset(14, 30)
    sub.TextTruncate = Enum.TextTruncate.AtEnd
    return card
end

-- Slider grande para dedo. cfg.scroll = ScrollingFrame que se bloquea al arrastrar.
local function crearSlider(parent, y, cfg)
    local cont = Instance.new("CanvasGroup")
    cont.Size = UDim2.new(1, -28, 0, 46)
    cont.Position = UDim2.fromOffset(14, y)
    cont.BackgroundTransparency = 1
    cont.Parent = parent

    local lbl = crearTexto(cont, "", 13, COL_TEXTO, Enum.Font.GothamBold)
    lbl.Size = UDim2.new(1, 0, 0, 18)

    local track = Instance.new("Frame")
    track.Size = UDim2.new(1, -28, 0, 12)
    track.Position = UDim2.fromOffset(14, 26)
    track.BackgroundColor3 = COL_BARRA
    track.BorderSizePixel = 0
    track.Parent = cont
    redondear(track, 6)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.fromScale(0, 1)
    fill.BackgroundColor3 = COL_ACENTO
    fill.BorderSizePixel = 0
    fill.Parent = track
    redondear(fill, 6)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(28, 28)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.fromScale(0, 0.5)
    knob.BackgroundColor3 = Color3.new(1, 1, 1)
    knob.BorderSizePixel = 0
    knob.Parent = track
    redondear(knob, 14)
    borde(knob, COL_ACENTO, 3)

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

    local function bloquearScroll(bloquear)
        if cfg.scroll then cfg.scroll.ScrollingEnabled = not bloquear end
    end

    local deslizando, inputSlider = false, nil
    conectar(cont.InputBegan, function(input)
        if esPuntero(input) and not deslizando then
            deslizando = true
            inputSlider = input
            bloquearScroll(true)
            desdeX(input.Position.X)
        end
    end)
    conectar(UserInputService.InputChanged, function(input)
        if deslizando and esMovimiento(input)
            and (input == inputSlider or input.UserInputType == Enum.UserInputType.MouseMovement) then
            desdeX(input.Position.X)
        end
    end)
    conectar(UserInputService.InputEnded, function(input)
        if deslizando and (input == inputSlider or input.UserInputType == Enum.UserInputType.MouseButton1) then
            deslizando = false
            inputSlider = nil
            bloquearScroll(false)
        end
    end)
    setValor(cfg.inicial)
    return cont
end

---------------------------------------------------------------------
-- UI
---------------------------------------------------------------------
local function padreGui()
    local ok, h = pcall(function() return gethui and gethui() end)
    if ok and h then return h end
    return PlayerGui
end
local destinoGui = padreGui()
for _, p in ipairs({ PlayerGui, destinoGui }) do
    local viejo = p:FindFirstChild("BurbujasUI")
    if viejo then viejo:Destroy() end
end

local gui = Instance.new("ScreenGui")
gui.Name = "BurbujasUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 999
gui.Parent = destinoGui

local CAB_ALTO = 46
local TABS_Y = 54
local PAGINA_Y = 98
local PIE_ALTO = 74

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
panel.AnchorPoint = Vector2.new(0, 0)
panel.BackgroundColor3 = COL_FONDO
panel.BorderSizePixel = 0
panel.Active = true -- evita que tocar el panel mueva la cámara en el móvil
panel.Parent = gui
redondear(panel, 16)
borde(panel, COL_ACENTO, 1.5, 0.55)

local escala = Instance.new("UIScale")
escala.Parent = panel

local function calcularEscala()
    local vs = viewport()
    return math.clamp(math.min((vs.X - 16) / PANEL_W, (vs.Y - 16) / PANEL_H), 0.6, 1)
end
local function tamPanel()
    return Vector2.new(PANEL_W * escala.Scale, PANEL_H * escala.Scale)
end
local function tamBurbuja()
    return Vector2.new(BURBUJA_TAM, BURBUJA_TAM)
end

escala.Scale = calcularEscala()
panel.Position = UDim2.fromOffset(10, math.max(8, (viewport().Y - tamPanel().Y) / 2))
clampear(panel, tamPanel())

-- Cabecera
local barra = Instance.new("Frame")
barra.Size = UDim2.new(1, 0, 0, CAB_ALTO)
barra.BackgroundColor3 = COL_BARRA
barra.BorderSizePixel = 0
barra.Parent = panel
redondear(barra, 16)

local tapa = Instance.new("Frame")
tapa.Size = UDim2.new(1, 0, 0, 16)
tapa.Position = UDim2.new(0, 0, 1, -16)
tapa.BackgroundColor3 = COL_BARRA
tapa.BorderSizePixel = 0
tapa.Parent = barra

local punto = Instance.new("Frame")
punto.Size = UDim2.fromOffset(10, 10)
punto.AnchorPoint = Vector2.new(0, 0.5)
punto.Position = UDim2.new(0, 14, 0.5, 0)
punto.BackgroundColor3 = COL_OFF
punto.BorderSizePixel = 0
punto.Parent = barra
redondear(punto, 5)

local titulo = crearTexto(barra, "MAYKEL DEV2", 15, COL_TEXTO, Enum.Font.GothamBold)
titulo.Size = UDim2.new(1, -130, 1, 0)
titulo.Position = UDim2.fromOffset(32, 0)

local function crearBotonBarra(texto, posX)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(36, 36)
    b.Position = UDim2.new(1, posX, 0.5, -18)
    b.BackgroundColor3 = COL_FONDO
    b.Text = texto
    b.TextColor3 = COL_TEXTO
    b.Font = Enum.Font.GothamBold
    b.TextSize = 18
    b.AutoButtonColor = true
    b.Parent = barra
    redondear(b, 10)
    return b
end

local btnCerrar = crearBotonBarra("x", -44)
local btnMin = crearBotonBarra("–", -84)
btnCerrar.MouseEnter:Connect(function() btnCerrar.BackgroundColor3 = COL_ROJO end)
btnCerrar.MouseLeave:Connect(function() btnCerrar.BackgroundColor3 = COL_FONDO end)

-- Botón flotante (minimizado)
local burbuja = Instance.new("TextButton")
burbuja.Name = "Burbuja"
burbuja.Size = UDim2.fromOffset(BURBUJA_TAM, BURBUJA_TAM)
burbuja.Position = panel.Position
burbuja.BackgroundColor3 = COL_ACENTO
burbuja.BackgroundTransparency = 0.15
burbuja.Text = ""
burbuja.AutoButtonColor = false
burbuja.Visible = false
burbuja.Parent = gui
redondear(burbuja, BURBUJA_TAM / 2)
borde(burbuja, Color3.new(1, 1, 1), 2, 0.4)

local imagenBurbuja = Instance.new("ImageLabel")
imagenBurbuja.Name = "Imagen"
imagenBurbuja.AnchorPoint = Vector2.new(0.5, 0.5)
imagenBurbuja.Position = UDim2.fromScale(0.5, 0.5)
imagenBurbuja.Size = UDim2.fromScale(1, 1)
imagenBurbuja.BackgroundTransparency = 1
imagenBurbuja.Image = "rbxthumb://type=Asset&id=86998528745950&w=420&h=420"
imagenBurbuja.ScaleType = Enum.ScaleType.Stretch
imagenBurbuja.Parent = burbuja

---------------------------------------------------------------------
-- Pestañas (módulos)
---------------------------------------------------------------------
local tabsFondo = Instance.new("Frame")
tabsFondo.Size = UDim2.new(1, -20, 0, 38)
tabsFondo.Position = UDim2.fromOffset(10, TABS_Y)
tabsFondo.BackgroundColor3 = COL_CARD
tabsFondo.BorderSizePixel = 0
tabsFondo.Parent = panel
redondear(tabsFondo, 11)

local paginas, botonesTab = {}, {}
local function mostrarPagina(nombre)
    for n, pg in pairs(paginas) do
        pg.Visible = (n == nombre)
    end
    for n, b in pairs(botonesTab) do
        local sel = (n == nombre)
        b.BackgroundColor3 = sel and COL_ACENTO or COL_CARD
        b.TextColor3 = sel and Color3.new(1, 1, 1) or COL_SUB
    end
end

local function crearPagina(nombre, texto, indice)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0.5, -6, 1, -6)
    b.Position = UDim2.new((indice - 1) * 0.5, 3, 0, 3)
    b.BackgroundColor3 = COL_CARD
    b.Text = texto
    b.TextColor3 = COL_SUB
    b.Font = Enum.Font.GothamBold
    b.TextSize = 14
    b.AutoButtonColor = false
    b.Parent = tabsFondo
    redondear(b, 9)
    botonesTab[nombre] = b

    local pg = Instance.new("ScrollingFrame")
    pg.Name = "Pagina_" .. nombre
    pg.Position = UDim2.fromOffset(10, PAGINA_Y)
    pg.Size = UDim2.new(1, -20, 1, -(PAGINA_Y + PIE_ALTO + 4))
    pg.BackgroundTransparency = 1
    pg.BorderSizePixel = 0
    pg.ScrollBarThickness = 3
    pg.ScrollBarImageColor3 = COL_ACENTO
    pg.ScrollingDirection = Enum.ScrollingDirection.Y
    pg.CanvasSize = UDim2.new()
    pg.AutomaticCanvasSize = Enum.AutomaticSize.Y
    pg.Visible = false
    pg.Parent = panel

    local lista = Instance.new("UIListLayout")
    lista.Padding = UDim.new(0, 8)
    lista.SortOrder = Enum.SortOrder.LayoutOrder
    lista.Parent = pg

    local pad = Instance.new("UIPadding")
    pad.PaddingRight = UDim.new(0, 5)
    pad.PaddingBottom = UDim.new(0, 4)
    pad.Parent = pg

    paginas[nombre] = pg
    b.MouseButton1Click:Connect(function() mostrarPagina(nombre) end)
    return pg
end

local pgBurbujas = crearPagina("burbujas", "Burbujas", 1)
local pgMov = crearPagina("mov", "Movimiento", 2)

-- ===== MÓDULO 1: BURBUJAS =====
crearFilaSwitch(pgBurbujas, 1, "Auto burbujas", "Recoge burbujas por ti", COL_ON, false, function(valor)
    activo = valor
    if not activo then
        recolectando = false
        if not moverAleatorio and not evadirMobs then quitarPlataforma() end
    end
    burbuja.BackgroundColor3 = valor and COL_ON or COL_ACENTO
    if actualizarInfo then actualizarInfo() end
end)

local sliderUmbral
crearFilaSwitch(pgBurbujas, 2, "Según oxígeno", "Solo recoge cuando baja el oxígeno", COL_ON, true, function(valor)
    controlOxigeno = valor
    recolectando = false
    if sliderUmbral then
        sliderUmbral.GroupTransparency = valor and 0 or 0.55
    end
    if actualizarInfo then actualizarInfo() end
end)

-- Tarjeta de oxígeno: estado + barra + umbral
local tarjetaOx = Instance.new("Frame")
tarjetaOx.Size = UDim2.new(1, 0, 0, 100)
tarjetaOx.BackgroundColor3 = COL_CARD
tarjetaOx.BorderSizePixel = 0
tarjetaOx.LayoutOrder = 3
tarjetaOx.Parent = pgBurbujas
redondear(tarjetaOx, 12)

local lblOxigeno = crearTexto(tarjetaOx, "Oxígeno: …", 12, COL_SUB)
lblOxigeno.Size = UDim2.new(1, -28, 0, 16)
lblOxigeno.Position = UDim2.fromOffset(14, 8)
lblOxigeno.TextTruncate = Enum.TextTruncate.AtEnd

local barraOx = Instance.new("Frame")
barraOx.Size = UDim2.new(1, -28, 0, 8)
barraOx.Position = UDim2.fromOffset(14, 29)
barraOx.BackgroundColor3 = COL_BARRA
barraOx.BorderSizePixel = 0
barraOx.Parent = tarjetaOx
redondear(barraOx, 4)

local barraOxFill = Instance.new("Frame")
barraOxFill.Size = UDim2.fromScale(0, 1)
barraOxFill.BackgroundColor3 = COL_ACENTO
barraOxFill.BorderSizePixel = 0
barraOxFill.Parent = barraOx
redondear(barraOxFill, 4)

local marcaUmbral = Instance.new("Frame")
marcaUmbral.Size = UDim2.fromOffset(3, 16)
marcaUmbral.AnchorPoint = Vector2.new(0.5, 0.5)
marcaUmbral.Position = UDim2.fromScale(umbralOxigeno / 100, 0.5)
marcaUmbral.BackgroundColor3 = Color3.new(1, 1, 1)
marcaUmbral.BorderSizePixel = 0
marcaUmbral.Parent = barraOx
redondear(marcaUmbral, 2)

sliderUmbral = crearSlider(tarjetaOx, 46, {
    min = UMBRAL_MIN, max = UMBRAL_MAX, paso = 5, inicial = umbralOxigeno,
    scroll = pgBurbujas,
    formato = function(v) return string.format("Recolectar si oxígeno ≤ %d%%", v) end,
    alCambiar = function(v)
        umbralOxigeno = v
        recolectando = false
        marcaUmbral.Position = UDim2.fromScale(v / 100, 0.5)
        if actualizarInfo then actualizarInfo() end
    end,
})

-- ===== MÓDULO 2: MOVIMIENTO =====
crearFilaSwitch(pgMov, 1, "Mov. aleatorio", "Se desplaza por la zona", COL_ACENTO, false, function(valor)
    moverAleatorio = valor
    visitados = {}
    if not valor and not activo and not evadirMobs then quitarPlataforma() end
    if actualizarInfo then actualizarInfo() end
end)

crearFilaSwitch(pgMov, 2, "Evadir mobs", "Se aleja si hay enemigos cerca", COL_ROJO, false, function(valor)
    evadirMobs = valor
    if not valor and not activo and not moverAleatorio then quitarPlataforma() end
    if actualizarInfo then actualizarInfo() end
end)

crearInfo(pgMov, 3,
    "Huir por daño: " .. (HUIR_AL_RECIBIR_DANO and "activado" or "apagado"),
    "Se configura en el código")

---------------------------------------------------------------------
-- Pie (visible en todas las pestañas)
---------------------------------------------------------------------
local pie = Instance.new("Frame")
pie.Size = UDim2.new(1, -20, 0, PIE_ALTO - 8)
pie.Position = UDim2.new(0, 10, 1, -PIE_ALTO)
pie.BackgroundTransparency = 1
pie.Parent = panel

local function crearChip(indice, texto)
    local chip = Instance.new("Frame")
    chip.Size = UDim2.new(0.5, -3, 0, 34)
    chip.Position = UDim2.new((indice - 1) * 0.5, indice == 2 and 3 or 0, 0, 0)
    chip.BackgroundColor3 = COL_CARD
    chip.BorderSizePixel = 0
    chip.Parent = pie
    redondear(chip, 10)

    local l = crearTexto(chip, texto, 12, COL_SUB)
    l.Size = UDim2.new(0.6, 0, 1, 0)
    l.Position = UDim2.fromOffset(10, 0)

    local v = crearTexto(chip, "0", 16, COL_TEXTO, Enum.Font.GothamBold)
    v.Size = UDim2.new(0.4, -10, 1, 0)
    v.Position = UDim2.new(0.6, 0, 0, 0)
    v.TextXAlignment = Enum.TextXAlignment.Right
    return v
end

local lblRecogidas = crearChip(1, "Recogidas")
local lblEvasiones = crearChip(2, "Evasiones")

local lblEstado = crearTexto(pie, "Estado: inactivo", 11, COL_SUB)
lblEstado.Size = UDim2.new(1, -4, 0, 28)
lblEstado.Position = UDim2.fromOffset(2, 38)
lblEstado.TextWrapped = true
lblEstado.TextTruncate = Enum.TextTruncate.AtEnd
lblEstado.TextYAlignment = Enum.TextYAlignment.Top

local function actualizarContador()
    lblRecogidas.Text = tostring(recogidas)
    lblEvasiones.Text = tostring(evasiones)
end

actualizarInfo = function()
    local ox, mx = leerOxigeno()
    if not ox then
        lblOxigeno.Text = "Oxígeno: sin datos (recolecta siempre)"
        barraOxFill.Size = UDim2.fromScale(0, 1)
    else
        local estado
        if emergencia then estado = "EMERGENCIA"
        elseif not activo then estado = "inactivo"
        elseif not controlOxigeno then estado = "continuo"
        elseif recolectando then estado = "recolectando"
        else estado = "en espera" end
        lblOxigeno.Text = string.format("Oxígeno %.0f / %.0f  ·  %s", ox, mx, estado)
        barraOxFill.Size = UDim2.fromScale(math.clamp(ox / mx, 0, 1), 1)
    end

    punto.BackgroundColor3 = (activo or moverAleatorio or evadirMobs) and COL_ON or COL_OFF

    local base
    if emergencia then
        base = "EMERGENCIA"
    elseif tick() < pausaHasta then
        base = string.format("pausa %.1fs", pausaHasta - tick())
    else
        base = activo and "activo" or "inactivo"
    end
    lblEstado.Text = string.format("%s · %s\nBurb %d · en rango %d · mov %d ok / %d fallo",
        base, dbg.motivo, dbg.total, dbg.rango, dbg.movOk, dbg.movFail)
    actualizarContador()
end

conectar(LocalPlayer:GetAttributeChangedSignal("Oxygen"), actualizarInfo)
conectar(LocalPlayer:GetAttributeChangedSignal("MaxOxygen"), actualizarInfo)
mostrarPagina("burbujas")
actualizarInfo()

local function minimizar()
    burbuja.Position = panel.Position
    clampear(burbuja, tamBurbuja())
    panel.Visible = false
    burbuja.Visible = true
end

local function restaurar()
    panel.Position = burbuja.Position
    clampear(panel, tamPanel())
    burbuja.Visible = false
    panel.Visible = true
end

local function cerrar()
    cerrado = true
    activo = false
    moverAleatorio = false
    evadirMobs = false
    quitarPlataforma()
    for _, c in ipairs(conexiones) do c:Disconnect() end
    table.clear(conexiones)
    gui:Destroy()
end

btnMin.MouseButton1Click:Connect(minimizar)
btnCerrar.MouseButton1Click:Connect(cerrar)
hacerArrastrable(barra, panel, nil, tamPanel)
hacerArrastrable(burbuja, burbuja, restaurar, tamBurbuja)

local function reajustar()
    if cerrado then return end
    escala.Scale = calcularEscala()
    clampear(panel, tamPanel())
    clampear(burbuja, tamBurbuja())
end
local camActual
local function vincularCamara()
    local cam = Workspace.CurrentCamera
    if cam and cam ~= camActual then
        camActual = cam
        conectar(cam:GetPropertyChangedSignal("ViewportSize"), reajustar)
    end
end
vincularCamara()
conectar(Workspace:GetPropertyChangedSignal("CurrentCamera"), function()
    vincularCamara()
    reajustar()
end)

---------------------------------------------------------------------
-- Lógica principal
---------------------------------------------------------------------
local function esRapido()
    return emergencia or (controlOxigeno and recolectando) -- [CAMBIO 3]
end

-- [CAMBIO 3] Espera la pausa humana, pero se corta al entrar en emergencia
local function esperarPausa(segundos)
    local fin = tick() + segundos
    while not cerrado and tick() < fin do
        if actualizarEmergencia() then break end
        task.wait(0.1)
    end
end

local function recogerBurbujas()
    if not debeRecolectar() then dbg.motivo = "oxígeno alto: en espera"; return end
    if not emergencia and tick() < pausaHasta then dbg.motivo = "pausa"; return end

    local root = getRoot()
    if not root or not root.Parent then dbg.motivo = "sin personaje"; return end
    if not estadoSeguro() then dbg.motivo = "estado no válido"; return end

    if not esRapido() and DETECTAR_INPUT and (tick() - lastInputTime) < 0.8 then
        dbg.motivo = "pausa por movimiento"
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

        -- [CAMBIO 1] / [CAMBIO 3] en emergencia se ignoran los enemigos
        local evitar = evadirMobs and not emergencia
        local enemigos = evitar and posicionesEnemigos() or {}

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
                    -- [CAMBIO 1] distancia al enemigo más cercano (huge si no hay)
                    local dEnemigo = #enemigos > 0 and distanciaMinima(pos, enemigos) or math.huge
                    local segura = dEnemigo > DISTANCIA_SEGURA
                    if libre and segura then
                        table.insert(lista, { obj = bubble, pos = pos, d = d, dEnemigo = dEnemigo, segura = segura })
                    end
                end
            end
        end
        -- [CAMBIO 1] Con evadirMobs: primero seguras, luego la más lejos de los
        -- enemigos, y de desempate la más cercana al jugador. Sin evadirMobs: solo por d.
        table.sort(lista, function(x, y)
            if evitar then
                if x.segura ~= y.segura then return x.segura end
                if x.dEnemigo ~= y.dEnemigo then return x.dEnemigo > y.dEnemigo end
            end
            return x.d < y.d
        end)

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
            if not emergencia and tick() < pausaHasta then break end
            if hechas >= limite then break end
            if not item.obj.Parent then continue end

            root = getRoot()
            if not root or not root.Parent then break end

            local pos = posBurbuja(item.obj) or item.pos

            if desplazarA(root, pos, item.obj) then
                visitaBurbuja[item.obj] = tick()
                recogidas = recogidas + 1
                hechas = hechas + 1
                enPasada = enPasada + 1
                dbg.movOk = dbg.movOk + 1
                dbg.motivo = emergencia and "EMERGENCIA: recolectando" or "recolectando"
                actualizarContador()

                if emergencia then
                    -- [CAMBIO 3] velocidad máxima: solo el tiempo mínimo sobre la burbuja
                    task.wait(MIN_PERMANENCIA)
                else
                    local espera = math.max(1 / velocidad, MIN_PERMANENCIA)
                    task.wait(humanDelay(espera, espera * (rapido and 0.1 or 0.3)))
                end

                if not rapido and recogidas % PAUSA_CADA == 0 then
                    local p = math.random() * (PAUSA_MAX - PAUSA_MIN) + PAUSA_MIN
                    pausaHasta = tick() + p
                    if actualizarInfo then actualizarInfo() end
                    esperarPausa(p)
                end
            else
                dbg.movFail = dbg.movFail + 1
                dbg.motivo = "movimiento bloqueado (estado del personaje)"
                task.wait(0.1)
            end
        end
    until not (esRapido() and activo and enPasada > 0 and pasadas < 30)

    root = getRoot()
    if activo and hechas > 0 and not moverAleatorio and root and root.Parent then
        irAPlataformaSuave(root, DESTINO, {
            velocidad = emergencia and velocidadEmergencia() or VELOCIDAD_MOV_BURBUJAS,
            continuar = function() return activo and not moverAleatorio and not evadiendo end,
        })
    end
end

-- Bucle 1: auto burbujas
task.spawn(function()
    while not cerrado do
        if emergencia then
            task.wait(0.05) -- [CAMBIO 3] sin esperas largas en emergencia
        elseif controlOxigeno then
            task.wait(0.3 + math.random() * 0.2)
        else
            task.wait(humanDelay(INTERVALO, INTERVALO_JITTER))
        end
        local okE, enEmergencia = pcall(actualizarEmergencia)
        if not okE then enEmergencia = false end
        if not cerrado and activo and (enEmergencia or tick() >= pausaHasta) then
            ocupado = true
            local ok, err = pcall(recogerBurbujas)
            ocupado = false
            if not ok then warn("[ERROR burbujas]", err) end
        end
    end
end)

-- Bucle 2: movimiento aleatorio (desplazamiento continuo)
task.spawn(function()
    while not cerrado do
        local intervalo = 1 / velocidadAleatoria
        task.wait(math.max(0.05, humanDelay(intervalo, intervalo * 0.22)))
        if not cerrado and moverAleatorio and not ocupado
        and tick() >= pausaHasta
        and (not DETECTAR_INPUT or (tick() - lastInputTime) > 1.2) then
            local ok, err = pcall(function()
                local root = getRoot()
                if not root or not root.Parent then return end

                local destino = posicionAleatoria(root.Position)
                if evadirMobs then
                    local en = posicionesEnemigos()
                    if #en > 0 and distanciaMinima(destino, en) <= DISTANCIA_SEGURA then
                        destino = posicionSegura(en, root.Position)
                    end
                end
                irAPlataformaSuave(root, destino)
            end)
            if not ok then warn("[ERROR mov aleatorio]", err) end
        end
    end
end)

-- Bucle 3: evadir mobs
task.spawn(function()
    while not cerrado do
        task.wait(INTERVALO_EVASION)
        if not cerrado and evadirMobs and not emergencia and not evadiendo and (tick() - ultimaEvasion) >= EVASION_COOLDOWN then
            local ok, err = pcall(function()
                local root = getRoot()
                local hum = getHumanoid()
                if not root or not root.Parent then return end
                if hum and hum.Health <= 0 then return end

                local enemigos = posicionesEnemigos()
                if #enemigos == 0 then return end

                if distanciaMinima(root.Position, enemigos) >= DISTANCIA_SEGURA then return end

                local destino, dist = posicionSegura(enemigos, root.Position)
                if destino then
                    evadiendo = true
                    ultimaEvasion = tick()
                    local llego = irAPlataformaSuave(root, destino, {
                        rapido = true,
                        forzar = true,
                        continuar = function() return evadirMobs end,
                    })
                    evadiendo = false
                    ultimaEvasion = tick()
                    if llego then
                        evasiones = evasiones + 1
                        dbg.motivo = string.format("evadió mob (nuevo punto a %.0f)", dist == math.huge and 999 or dist)
                        actualizarContador()
                    end
                end
            end)
            evadiendo = false
            if not ok then warn("[ERROR evadir mobs]", err) end
        end
    end
end)

-- Bucle 4: huir al recibir daño (se configura SOLO desde el código)
local function posicionLejosDe(origen, enemigos)
    local plano = Vector3.new(origen.X, DESTINO.Y, origen.Z)
    local mejor, mejorPuntaje = nil, -1
    for _ = 1, CANDIDATOS do
        local ang = math.random() * math.pi * 2
        local dist = math.sqrt(math.random()) * RADIO_ALEATORIO
        local cand = DESTINO + Vector3.new(math.cos(ang) * dist, 0, math.sin(ang) * dist)
        local puntaje = math.min((cand - plano).Magnitude, distanciaMinima(cand, enemigos))
        if puntaje > mejorPuntaje then
            mejor, mejorPuntaje = cand, puntaje
        end
    end
    return mejor
end

task.spawn(function()
    local humPrev, vidaPrev = nil, 0
    while not cerrado do
        task.wait(0.05)
        if cerrado then break end
        if HUIR_AL_RECIBIR_DANO then
            local ok, err = pcall(function()
                local hum = getHumanoid()
                if not hum then
                    humPrev = nil
                    return
                end
                if hum ~= humPrev then
                    humPrev, vidaPrev = hum, hum.Health
                    return
                end

                local vida = hum.Health
                local perdida = vidaPrev - vida
                if vida <= 0 or perdida < DANO_MINIMO or evadiendo then
                    vidaPrev = vida
                    return
                end

                local root = hum.Parent and hum.Parent:FindFirstChild("HumanoidRootPart")
                if not root then
                    vidaPrev = vida
                    return
                end

                local destino = posicionLejosDe(root.Position, posicionesEnemigos())
                if not destino then
                    vidaPrev = vida
                    return
                end

                evadiendo = true
                ultimaEvasion = tick()
                local llego = irAPlataformaSuave(root, destino, {
                    forzar = true,
                    velocidad = VELOCIDAD_HUIDA_DANO,
                    continuar = function() return not cerrado end,
                })
                evadiendo = false
                ultimaEvasion = tick()

                local h = getHumanoid()
                vidaPrev = h and h.Health or 0
                if llego then
                    dbg.motivo = string.format("huyó por daño (-%.0f vida)", perdida)
                end
            end)
            evadiendo = false
            if not ok then warn("[ERROR huir por daño]", err) end
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
