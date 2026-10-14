-- ============================================================
-- AUTO BURBUJAS + VERIFICADOR ANTI-CHEAT
-- Si falla la verificación, NO se ejecuta el script principal
-- ============================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- ============================================================
-- 1) UI DE CARGA
-- ============================================================
local function padreGui()
    local ok, h = pcall(function() return gethui and gethui() end)
    if ok and h then return h end
    return PlayerGui
end

local destinoGui = padreGui()

for _, p in ipairs({ PlayerGui, destinoGui }) do
    local viejo = p:FindFirstChild("CargaUI")
    if viejo then viejo:Destroy() end
    local viejo2 = p:FindFirstChild("BurbujasUI")
    if viejo2 then viejo2:Destroy() end
end

local guiCarga = Instance.new("ScreenGui")
guiCarga.Name = "CargaUI"
guiCarga.ResetOnSpawn = false
guiCarga.IgnoreGuiInset = true
guiCarga.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
guiCarga.DisplayOrder = 5000
guiCarga.Parent = destinoGui

local fondo = Instance.new("Frame")
fondo.Size = UDim2.fromScale(1, 1)
fondo.BackgroundColor3 = Color3.fromRGB(12, 14, 22)
fondo.BorderSizePixel = 0
fondo.Parent = guiCarga

local panelCarga = Instance.new("Frame")
panelCarga.Size = UDim2.fromOffset(340, 200)
panelCarga.Position = UDim2.fromScale(0.5, 0.5)
panelCarga.AnchorPoint = Vector2.new(0.5, 0.5)
panelCarga.BackgroundColor3 = Color3.fromRGB(24, 26, 36)
panelCarga.BorderSizePixel = 0
panelCarga.Parent = fondo

local uicorner = Instance.new("UICorner")
uicorner.CornerRadius = UDim.new(0, 14)
uicorner.Parent = panelCarga

local borde = Instance.new("UIStroke")
borde.Color = Color3.fromRGB(80, 170, 255)
borde.Thickness = 1.5
borde.Transparency = 0.4
borde.Parent = panelCarga

local titulo = Instance.new("TextLabel")
titulo.Size = UDim2.new(1, -20, 0, 34)
titulo.Position = UDim2.fromOffset(10, 12)
titulo.BackgroundTransparency = 1
titulo.Text = "MAYKEL DEV1"
titulo.TextColor3 = Color3.fromRGB(235, 238, 250)
titulo.Font = Enum.Font.GothamBold
titulo.TextSize = 18
titulo.Parent = panelCarga

local subtitulo = Instance.new("TextLabel")
subtitulo.Size = UDim2.new(1, -20, 0, 22)
subtitulo.Position = UDim2.fromOffset(10, 44)
subtitulo.BackgroundTransparency = 1
subtitulo.Text = "Verificando anti-cheat..."
subtitulo.TextColor3 = Color3.fromRGB(150, 156, 180)
subtitulo.Font = Enum.Font.Gotham
subtitulo.TextSize = 13
subtitulo.Parent = panelCarga

-- Barra de progreso
local barraFondo = Instance.new("Frame")
barraFondo.Size = UDim2.new(1, -40, 0, 12)
barraFondo.Position = UDim2.new(0, 20, 0, 90)
barraFondo.BackgroundColor3 = Color3.fromRGB(34, 37, 52)
barraFondo.BorderSizePixel = 0
barraFondo.Parent = panelCarga

local uicorner2 = Instance.new("UICorner")
uicorner2.CornerRadius = UDim.new(0, 6)
uicorner2.Parent = barraFondo

local barraFill = Instance.new("Frame")
barraFill.Size = UDim2.fromScale(0, 1)
barraFill.BackgroundColor3 = Color3.fromRGB(80, 170, 255)
barraFill.BorderSizePixel = 0
barraFill.Parent = barraFondo

local uicorner3 = Instance.new("UICorner")
uicorner3.CornerRadius = UDim.new(0, 6)
uicorner3.Parent = barraFill

local porcentaje = Instance.new("TextLabel")
porcentaje.Size = UDim2.new(1, -40, 0, 20)
porcentaje.Position = UDim2.new(0, 20, 0, 108)
porcentaje.BackgroundTransparency = 1
porcentaje.Text = "0%"
porcentaje.TextColor3 = Color3.fromRGB(235, 238, 250)
porcentaje.Font = Enum.Font.GothamMedium
porcentaje.TextSize = 13
porcentaje.TextXAlignment = Enum.TextXAlignment.Left
porcentaje.Parent = panelCarga

local logLabel = Instance.new("TextLabel")
logLabel.Size = UDim2.new(1, -40, 0, 44)
logLabel.Position = UDim2.new(0, 20, 0, 132)
logLabel.BackgroundTransparency = 1
logLabel.Text = ""
logLabel.TextColor3 = Color3.fromRGB(150, 156, 180)
logLabel.Font = Enum.Font.Code
logLabel.TextSize = 12
logLabel.TextXAlignment = Enum.TextXAlignment.Left
logLabel.TextYAlignment = Enum.TextYAlignment.Top
logLabel.TextWrapped = true
logLabel.Parent = panelCarga

local progreso = 0
local function setProgreso(p, texto)
    progreso = math.clamp(p, 0, 1)
    TweenService:Create(barraFill, TweenInfo.new(0.25), {
        Size = UDim2.fromScale(progreso, 1)
    }):Play()
    porcentaje.Text = string.format("%d%%", math.floor(progreso * 100))
    if texto then subtitulo.Text = texto end
end

local function log(msg)
    logLabel.Text = msg
    print("[CARGA] " .. msg)
end

-- ============================================================
-- 2) DESACTIVADOR DE ANTI-CHEAT
-- ============================================================
local SERVICIOS_BLOQUEADOS = {
    "AntiCheatService",
    "ChallengeService",
    "RaidService",
    "SandboxService",
    "AdminAbuseService",
}

local MODULOS_ADMIN_PELIGROSOS = {
    "AdminLagClient",
    "AdminCrashClient",
    "AdminKillBrickClient",
}

local function vaciarModulo(m)
    if typeof(m) == "Instance" and m:IsA("ModuleScript") then
        pcall(function() m:ClearAllChildren() end)
    end
end

local function matarServicio(nombre)
    local encontrado = false
    -- ReplicatedStorage
    local rs = ReplicatedStorage:FindFirstChild(nombre)
    if rs then
        encontrado = true
        for _, hijo in ipairs(rs:GetDescendants()) do
            if hijo:IsA("ModuleScript") then vaciarModulo(hijo) end
            if hijo:IsA("RemoteEvent") or hijo:IsA("RemoteFunction") then
                pcall(function() hijo:Destroy() end)
            end
        end
        pcall(function() rs:Destroy() end)
    end

    -- PlayerScripts / PlayerGui
    for _, cont in ipairs({
        LocalPlayer:FindFirstChild("PlayerScripts"),
        LocalPlayer:FindFirstChild("PlayerGui"),
    }) do
        if cont then
            local s = cont:FindFirstChild(nombre)
            if s then
                encontrado = true
                pcall(function() s:Destroy() end)
            end
        end
    end
    return encontrado
end

local function desactivarAntiCheat()
    local destruidos, faltantes = 0, 0

    for _, nombre in ipairs(SERVICIOS_BLOQUEADOS) do
        if matarServicio(nombre) then
            destruidos = destruidos + 1
            log("OK " .. nombre .. " destruido")
        else
            faltantes = faltantes + 1
            log("-- " .. nombre .. " no encontrado")
        end
        task.wait(0.05)
    end

    -- Módulos admin peligrosos
    for _, nombre in ipairs(MODULOS_ADMIN_PELIGROSOS) do
        for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
            if d.Name:find(nombre) then
                pcall(function() d:Destroy() end)
            end
        end
        task.wait(0.05)
    end

    return destruidos, faltantes
end

-- ============================================================
-- 3) VERIFICACIÓN
-- ============================================================
local function verificar()
    local ok = true
    local detalles = {}

    -- 3.1) ¿Existen todavía los servicios?
    for _, nombre in ipairs(SERVICIOS_BLOQUEADOS) do
        local existe = ReplicatedStorage:FindFirstChild(nombre)
        if existe then
            ok = false
            table.insert(detalles, "X " .. nombre .. " sigue vivo")
        end
    end

    -- 3.2) ¿Hay scripts del servidor accesibles? (server-side = no podemos)
    local ss = game:GetService("ServerScriptService")
    for _, s in ipairs(ss:GetDescendants()) do
        if s.Name:find("AntiCheat") or s.Name:find("Anti_Cheat") then
            table.insert(detalles, "! " .. s.Name .. " corre en servidor")
            -- No marcamos como fallo, solo avisamos
        end
    end

    -- 3.3) Prueba de TP brusco
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        local posOriginal = hrp.Position
        local destinoPrueba = posOriginal + Vector3.new(0, 0, -100)

        hrp.CFrame = CFrame.new(destinoPrueba)
        task.wait(1.2)

        local hrpAhora = LocalPlayer.Character
            and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrpAhora then
            ok = false
            table.insert(detalles, "X Personaje desapareció tras TP de prueba")
        else
            local dist = (hrpAhora.Position - destinoPrueba).Magnitude
            if dist > 30 then
                ok = false
                table.insert(detalles, "X Anti-cheat devolvió al jugador")
                -- Volver a posición original para no quedar raro
                pcall(function() hrpAhora.CFrame = CFrame.new(posOriginal) end)
            end
        end
    else
        table.insert(detalles, "! Sin personaje, prueba TP omitida")
    end

    return ok, detalles
end

-- ============================================================
-- 4) SCRIPT PRINCIPAL (AUTO BURBUJAS)
-- ============================================================
local function ejecutarBurbujas()
    --[[  AUTO BURBUJAS (versión móvil) ]]
    -- Los AJUSTES DE VELOCIDAD van aquí dentro:
    local VELOCIDAD_BURBUJAS = 2
    local VELOCIDAD_TP = 0.5
    local TIEMPO_SOBRE_BURBUJA = 0.35
    local VELOCIDAD_MOV_BURBUJAS = 80
    local VELOCIDAD_MOV_TP = 50
    local VELOCIDAD_HUIDA = 65
    local HUIR_AL_RECIBIR_DANO = true
    local VELOCIDAD_HUIDA_DANO = 100
    local DANO_MINIMO = 1

    local RADIO = 100000
    local INTERVALO = 1.5
    local INTERVALO_JITTER = 1.2
    local DESTINO = Vector3.new(11, 49, -553)
    local ALTURA_PLATAFORMA = 3.5
    local UMBRAL_MIN, UMBRAL_MAX = 5, 95
    local RADIO_TP = 300
    local SEPARACION = 60
    local CANDIDATOS = 60
    local PAUSA_CADA = 8
    local PAUSA_MIN, PAUSA_MAX = 4, 9
    local BURBUJAS_POR_CICLO = 3
    local DETECTAR_INPUT = true
    local BURBUJA_ENFRIAMIENTO = 1
    local CARPETA_ENEMIGOS = "Enemies"
    local DISTANCIA_SEGURA = 6
    local DISTANCIA_DESTINO_MIN = 60
    local INTERVALO_EVASION = 0.02
    local EVASION_COOLDOWN = 0.3
    local PANEL_W, PANEL_H = 260, 326
    local BURBUJA_TAM = 56

    local velocidad = math.max(0.1, VELOCIDAD_BURBUJAS)
    local velocidadTP = math.max(0.1, VELOCIDAD_TP)
    local MIN_PERMANENCIA = math.max(0, TIEMPO_SOBRE_BURBUJA)
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
    local lastInputTime = 0
    local evadirMobs = false
    local evasiones = 0
    local ultimaEvasion = 0
    local evadiendo = false
    local visitaBurbuja = setmetatable({}, { __mode = "k" })
    local dbg = { total = 0, rango = 0, tpOk = 0, tpFail = 0, motivo = "—" }

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
    local function viewport()
        local cam = Workspace.CurrentCamera
        return cam and cam.ViewportSize or Vector2.new(800, 400)
    end

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
    local function duracionPara(dist, vel)
        return math.max(dist / math.max(vel, 1), 0.03)
    end

    local function teleportarA(root, destino, obj)
        if not root or not root.Parent then return false end
        if evadiendo or not estadoSeguro() then return false end
        local rot = root.CFrame - root.CFrame.Position
        local meta = CFrame.new(destino) * rot
        local dist = (root.Position - destino).Magnitude
        local llego = deslizar(root, meta, duracionPara(dist, VELOCIDAD_MOV_BURBUJAS), nil, function()
            return activo and not evadiendo and (not obj or obj.Parent ~= nil)
        end)
        if root.Parent then root.AssemblyLinearVelocity = Vector3.zero end
        return llego
    end

    local function irAPlataformaSuave(root, destino, opc)
        opc = opc or {}
        if not root or not root.Parent then return false end
        if not opc.forzar and not estadoSeguro() then return false end
        local dist = (root.Position - destino).Magnitude
        crearPlataforma(root.Position)
        local rot = root.CFrame - root.CFrame.Position
        local meta = CFrame.new(destino) * rot
        local platDestino = destino - Vector3.new(0, ALTURA_PLATAFORMA, 0)
        local continuar = opc.continuar or function()
            return tpAleatorio and not ocupado and not evadiendo
        end
        local vel = opc.velocidad or (opc.rapido and VELOCIDAD_HUIDA) or VELOCIDAD_MOV_TP
        local llego = deslizar(root, meta, duracionPara(dist, vel), platDestino, continuar)
        if root.Parent then root.AssemblyLinearVelocity = Vector3.zero end
        return llego
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
    local function posicionSegura(enemigos, origen)
        local mejor, mejorDist = nil, -1
        for _ = 1, CANDIDATOS do
            local ang = math.random() * math.pi * 2
            local dist = math.sqrt(math.random()) * RADIO_TP
            local cand = DESTINO + Vector3.new(math.cos(ang) * dist, 0, math.sin(ang) * dist)
            local minD = distanciaMinima(cand, enemigos)
            if minD > mejorDist then
                mejor, mejorDist = cand, minD
            end
        end
        return mejor, mejorDist
    end

    local function redondear(obj, radio)
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, radio)
        c.Parent = obj
        return c
    end
    local function bordeUI(obj, color, grosor, transp)
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
    local function crearFilaSwitch(parent, y, textoInicial, colorOn, inicial, alCambiar)
        local fila = Instance.new("TextButton")
        fila.Size = UDim2.new(1, -16, 0, 32)
        fila.Position = UDim2.fromOffset(8, y - 3)
        fila.BackgroundTransparency = 1
        fila.Text = ""
        fila.AutoButtonColor = false
        fila.Parent = parent
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
        local function alternar()
            estado = not estado
            local info = TweenInfo.new(0.18, Enum.EasingStyle.Quad)
            TweenService:Create(sw, info, { BackgroundColor3 = estado and colorOn or COL_OFF }):Play()
            TweenService:Create(perilla, info, { Position = UDim2.fromOffset(estado and 27 or 3, 3) }):Play()
            lbl.TextColor3 = estado and colorOn or COL_SUB
            alCambiar(estado, lbl)
        end
        sw.MouseButton1Click:Connect(alternar)
        fila.MouseButton1Click:Connect(alternar)
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
        track.Size = UDim2.new(1, -20, 0, 10)
        track.Position = UDim2.fromOffset(10, 25)
        track.BackgroundColor3 = COL_BARRA
        track.BorderSizePixel = 0
        track.Parent = cont
        redondear(track, 5)
        local fill = Instance.new("Frame")
        fill.Size = UDim2.fromScale(0, 1)
        fill.BackgroundColor3 = COL_ACENTO
        fill.BorderSizePixel = 0
        fill.Parent = track
        redondear(fill, 5)
        local knob = Instance.new("Frame")
        knob.Size = UDim2.fromOffset(22, 22)
        knob.AnchorPoint = Vector2.new(0.5, 0.5)
        knob.Position = UDim2.fromScale(0, 0.5)
        knob.BackgroundColor3 = Color3.new(1, 1, 1)
        knob.BorderSizePixel = 0
        knob.Parent = track
        redondear(knob, 11)
        bordeUI(knob, COL_ACENTO, 2)
        local lMin = crearTexto(cont, cfg.textoMin, 12, COL_SUB)
        lMin.Size = UDim2.fromOffset(60, 14)
        lMin.Position = UDim2.fromOffset(10, 38)
        local lMax = crearTexto(cont, cfg.textoMax, 12, COL_SUB)
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
        local deslizando, inputSlider = false, nil
        conectar(cont.InputBegan, function(input)
            if esPuntero(input) and not deslizando then
                deslizando = true
                inputSlider = input
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
            end
        end)
        setValor(cfg.inicial)
        return cont
    end

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

    local panel = Instance.new("Frame")
    panel.Name = "Panel"
    panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
    panel.AnchorPoint = Vector2.new(0, 0)
    panel.BackgroundColor3 = COL_FONDO
    panel.BorderSizePixel = 0
    panel.Parent = gui
    redondear(panel, 14)
    bordeUI(panel, COL_ACENTO, 1.5, 0.5)

    local escala = Instance.new("UIScale")
    escala.Parent = panel
    local function calcularEscala()
        local vs = viewport()
        return math.clamp(math.min((vs.X - 16) / PANEL_W, (vs.Y - 16) / PANEL_H), 0.55, 1)
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
    local tituloPanel = crearTexto(barra, "MAYKEL DEV1", 15, COL_TEXTO, Enum.Font.GothamBold)
    tituloPanel.Size = UDim2.new(1, -90, 1, 0)
    tituloPanel.Position = UDim2.fromOffset(14, 0)
    local function crearBotonBarra(texto, posX)
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(32, 32)
        b.Position = UDim2.new(1, posX, 0.5, -16)
        b.BackgroundColor3 = COL_FONDO
        b.Text = texto
        b.TextColor3 = COL_TEXTO
        b.Font = Enum.Font.GothamBold
        b.TextSize = 17
        b.Parent = barra
        redondear(b, 9)
        return b
    end
    local btnCerrar = crearBotonBarra("x", -38)
    local btnMin = crearBotonBarra("–", -76)
    btnCerrar.MouseEnter:Connect(function() btnCerrar.BackgroundColor3 = COL_ROJO end)
    btnCerrar.MouseLeave:Connect(function() btnCerrar.BackgroundColor3 = COL_FONDO end)

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
    bordeUI(burbuja, Color3.new(1, 1, 1), 2, 0.4)
    local imagenBurbuja = Instance.new("ImageLabel")
    imagenBurbuja.Name = "Imagen"
    imagenBurbuja.AnchorPoint = Vector2.new(0.5, 0.5)
    imagenBurbuja.Position = UDim2.fromScale(0.5, 0.5)
    imagenBurbuja.Size = UDim2.fromScale(1, 1)
    imagenBurbuja.BackgroundTransparency = 1
    imagenBurbuja.Image = "rbxthumb://type=Asset&id=86998528745950&w=420&h=420"
    imagenBurbuja.ScaleType = Enum.ScaleType.Stretch
    imagenBurbuja.Parent = burbuja

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
    local lblContador = crearTexto(panel, "Recogidas: 0  ·  Evasiones: 0", 13, COL_SUB)
    lblContador.Size = UDim2.new(1, -28, 0, 20)
    lblContador.Position = UDim2.fromOffset(14, 268)
    local function actualizarContador()
        lblContador.Text = string.format("Recogidas: %d  ·  Evasiones: %d", recogidas, evasiones)
    end
    local lblEstado = crearTexto(panel, "Estado: inactivo", 12, COL_SUB)
    lblEstado.Size = UDim2.new(1, -28, 0, 32)
    lblEstado.Position = UDim2.fromOffset(14, 290)
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
        tpAleatorio = false
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

    local function esRapido()
        return controlOxigeno and recolectando
    end

    local function recogerBurbujas()
        if not debeRecolectar() then dbg.motivo = "oxígeno alto: en espera"; return end
        if tick() < pausaHasta then dbg.motivo = "pausa"; return end
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
            local enemigos = evadirMobs and posicionesEnemigos() or {}
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
                local pos = posBurbuja(item.obj) or item.pos
                if evadirMobs then
                    local en = posicionesEnemigos()
                    if #en > 0 and distanciaMinima(pos, en) <= DISTANCIA_SEGURA then
                        continue
                    end
                end
                if teleportarA(root, pos, item.obj) then
                    visitaBurbuja[item.obj] = tick()
                    recogidas = recogidas + 1
                    hechas = hechas + 1
                    enPasada = enPasada + 1
                    dbg.tpOk = dbg.tpOk + 1
                    dbg.motivo = "recolectando"
                    actualizarContador()
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
        root = getRoot()
        if activo and hechas > 0 and not tpAleatorio and root and root.Parent then
            irAPlataformaSuave(root, DESTINO, {
                velocidad = VELOCIDAD_MOV_BURBUJAS,
                continuar = function() return activo and not tpAleatorio and not evadiendo end,
            })
        end
    end

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

    task.spawn(function()
        while not cerrado do
            local intervaloTP = 1 / velocidadTP
            task.wait(math.max(0.05, humanDelay(intervaloTP, intervaloTP * 0.22)))
            if not cerrado and tpAleatorio and not ocupado
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
                if not ok then warn("[ERROR tp aleatorio]", err) end
            end
        end
    end)

    task.spawn(function()
        while not cerrado do
            task.wait(INTERVALO_EVASION)
            if not cerrado and evadirMobs and not evadiendo and (tick() - ultimaEvasion) >= EVASION_COOLDOWN then
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

    local function posicionLejosDe(origen, enemigos)
        local plano = Vector3.new(origen.X, DESTINO.Y, origen.Z)
        local mejor, mejorPuntaje = nil, -1
        for _ = 1, CANDIDATOS do
            local ang = math.random() * math.pi * 2
            local dist = math.sqrt(math.random()) * RADIO_TP
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

    task.spawn(function()
        while not cerrado do
            task.wait(1)
            if actualizarInfo then actualizarInfo() end
        end
    end)

    print("[BURBUJAS] Script principal iniciado correctamente.")
end

-- ============================================================
-- 5) SECUENCIA PRINCIPAL
-- ============================================================
task.spawn(function()
    setProgreso(0.05, "Iniciando...")
    log("Preparando entorno...")
    task.wait(0.4)

    setProgreso(0.15, "Desactivando anti-cheat...")
    log("Destruyendo servicios de protección...")
    task.wait(0.3)

    local ok, destruidos, faltantes = pcall(desactivarAntiCheat)
    if not ok then
        log("ERROR al desactivar: " .. tostring(destruidos))
        setProgreso(1, "Error crítico")
        task.wait(2)
        guiCarga:Destroy()
        return
    end
    log(string.format("Destruidos: %d | No encontrados: %d", destruidos, faltantes))

    setProgreso(0.45, "Verificando neutralización...")
    log("Ejecutando prueba de TP...")
    task.wait(0.3)

    local valido, detalles = verificar()

    setProgreso(0.75, valido and "Verificación OK" or "Verificación FALLIDA")
    if #detalles > 0 then
        log(table.concat(detalles, "\n"))
    else
        log("Sin incidencias detectadas.")
    end
    task.wait(0.6)

    if not valido then
        -- Mostrar error y NO ejecutar el script
        setProgreso(1, "❌ ANTI-CHEAT ACTIVO")
        subtitulo.TextColor3 = Color3.fromRGB(220, 75, 80)
        logLabel.TextColor3 = Color3.fromRGB(220, 75, 80)
        log("El anti-cheat sigue activo.\nScript NO ejecutado por seguridad.")
        task.wait(3)
        guiCarga:Destroy()
        return
    end

    setProgreso(0.9, "Cargando script...")
    log("Anti-cheat neutralizado. Ejecutando...")
    task.wait(0.4)

    setProgreso(1, "✅ Listo")
    subtitulo.TextColor3 = Color3.fromRGB(60, 200, 120)
    task.wait(0.8)

    guiCarga:Destroy()

    local ok2, err2 = pcall(ejecutarBurbujas)
    if not ok2 then
        warn("[ERROR script principal] " .. tostring(err2))
    end
end)
