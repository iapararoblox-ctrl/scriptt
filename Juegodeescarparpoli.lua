local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

---------------------------------------------------------------------
-- Configuraciónn
---------------------------------------------------------------------
local RADIO = 500000
local INTERVALO = 1
local DESTINO = Vector3.new(11, 49, -553)
local ALTURA_PLATAFORMA = 3.5

local VEL_MIN, VEL_MAX = 1, 20      -- burbujas por segundo
local GIRO_MIN, GIRO_MAX = 10, 360  -- grados por segundo (velocidad del recorrido)
local ORB_MIN, ORB_MAX = 2, 40      -- radio del círculo en studs

-- Estado
local velocidad = 7
local velGiro = 90
local radioOrbita = 10
local angulo = 0
local girar = false
local activo = false
local enDestino = false
local vivo = true
local recogidas = 0
local plataforma = nil
local conexiones = {}

-- Paleta
local COL_FONDO = Color3.fromRGB(24, 26, 36)
local COL_BARRA = Color3.fromRGB(34, 37, 52)
local COL_ACENTO = Color3.fromRGB(80, 170, 255)
local COL_ON = Color3.fromRGB(60, 200, 120)
local COL_OFF = Color3.fromRGB(90, 94, 115)
local COL_ROJO = Color3.fromRGB(220, 75, 80)
local COL_TEXTO = Color3.fromRGB(235, 238, 250)
local COL_SUB = Color3.fromRGB(150, 156, 180)

local function conectar(senal, fn)
	local c = senal:Connect(fn)
	table.insert(conexiones, c)
	return c
end

---------------------------------------------------------------------
-- Utilidades de juego
---------------------------------------------------------------------
local function getRoot()
	local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	return char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart", 5)
end

local function getPosition(obj)
	if obj:IsA("Model") then
		return obj:GetPivot().Position
	elseif obj:IsA("BasePart") then
		return obj.Position
	end
end

local function crearPlataforma()
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
	plataforma.Position = DESTINO - Vector3.new(0, ALTURA_PLATAFORMA, 0)
end

local function quitarPlataforma()
	if plataforma then
		plataforma:Destroy()
		plataforma = nil
	end
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
					if not movido and alTocar then
						alTocar()
					end
				end
			end)
		end
	end)

	conectar(UserInputService.InputChanged, function(input)
		if arrastrando and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - inicioInput
			if d.Magnitude > 5 then
				movido = true
			end
			if movido then
				target.Position = UDim2.new(
					inicioPos.X.Scale, inicioPos.X.Offset + d.X,
					inicioPos.Y.Scale, inicioPos.Y.Offset + d.Y
				)
			end
		end
	end)
end

-- Interruptor reutilizable. Devuelve una función set(valor)
local function crearSwitch(parent, posicion, alCambiar)
	local sw = Instance.new("TextButton")
	sw.Size = UDim2.fromOffset(50, 26)
	sw.Position = posicion
	sw.BackgroundColor3 = COL_OFF
	sw.Text = ""
	sw.AutoButtonColor = false
	sw.Parent = parent
	redondear(sw, 13)

	local perilla = Instance.new("Frame")
	perilla.Size = UDim2.fromOffset(20, 20)
	perilla.Position = UDim2.fromOffset(3, 3)
	perilla.BackgroundColor3 = Color3.new(1, 1, 1)
	perilla.BorderSizePixel = 0
	perilla.Parent = sw
	redondear(perilla, 10)

	local estado = false
	local function set(valor)
		estado = valor
		local info = TweenInfo.new(0.18, Enum.EasingStyle.Quad)
		TweenService:Create(sw, info, { BackgroundColor3 = estado and COL_ON or COL_OFF }):Play()
		TweenService:Create(perilla, info, { Position = UDim2.fromOffset(estado and 27 or 3, 3) }):Play()
	end

	sw.MouseButton1Click:Connect(function()
		set(not estado)
		alCambiar(estado)
	end)

	return set
end

-- Slider reutilizable. Devuelve el contenedor (CanvasGroup) para poder atenuarlo
local function crearSlider(parent, y, cfg)
	local cont = Instance.new("CanvasGroup")
	cont.Size = UDim2.new(1, -28, 0, 56)
	cont.Position = UDim2.fromOffset(14, y)
	cont.BackgroundTransparency = 1
	cont.Parent = parent

	local lbl = crearTexto(cont, "", 14, COL_TEXTO)
	lbl.Size = UDim2.new(1, 0, 0, 20)

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, -20, 0, 8)
	track.Position = UDim2.fromOffset(10, 28)
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
	lMin.Position = UDim2.fromOffset(10, 42)

	local lMax = crearTexto(cont, cfg.textoMax, 11, COL_SUB)
	lMax.Size = UDim2.fromOffset(60, 14)
	lMax.Position = UDim2.new(1, -70, 0, 42)
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
		v = math.floor(v / cfg.paso + 0.5) * cfg.paso
		setValor(v)
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
		if esPuntero(input) then
			deslizando = false
		end
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
panel.Size = UDim2.fromOffset(250, 356)
panel.Position = UDim2.new(0, 20, 0.5, -178)
panel.BackgroundColor3 = COL_FONDO
panel.BorderSizePixel = 0
panel.Parent = gui
redondear(panel, 14)
borde(panel, COL_ACENTO, 1.5, 0.5)

-- Barra de título
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

local titulo = crearTexto(barra, "🫧  Auto Burbujas", 15, COL_TEXTO, Enum.Font.GothamBold)
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

-- Burbujita (UI minimizada)
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

-- Fila 1: interruptor principal
local lblEstado = crearTexto(panel, "Estado: apagado", 14, COL_SUB)
lblEstado.Size = UDim2.new(1, -90, 0, 26)
lblEstado.Position = UDim2.fromOffset(14, 50)

local setPrincipal
setPrincipal = crearSwitch(panel, UDim2.new(1, -64, 0, 50), function(valor)
	activo = valor
	if not activo then
		enDestino = false
		quitarPlataforma()
	end
	lblEstado.Text = activo and "Estado: activo" or "Estado: apagado"
	lblEstado.TextColor3 = activo and COL_ON or COL_SUB
	burbuja.BackgroundColor3 = activo and COL_ON or COL_ACENTO
end)

-- Fila 2: velocidad de recolección
crearSlider(panel, 88, {
	min = VEL_MIN, max = VEL_MAX, paso = 1, inicial = velocidad,
	textoMin = "Lento", textoMax = "Rápido",
	formato = function(v) return string.format("Velocidad: %d burb/s  (%.2fs)", v, 1 / v) end,
	alCambiar = function(v) velocidad = v end,
})

-- Separador
local sep = Instance.new("Frame")
sep.Size = UDim2.new(1, -28, 0, 1)
sep.Position = UDim2.fromOffset(14, 152)
sep.BackgroundColor3 = COL_BARRA
sep.BorderSizePixel = 0
sep.Parent = panel

-- Fila 3: girar en el aire
local lblGirar = crearTexto(panel, "Dar vueltas en el aire", 14, COL_TEXTO)
lblGirar.Size = UDim2.new(1, -90, 0, 26)
lblGirar.Position = UDim2.fromOffset(14, 162)

local sliderGiro, sliderRadio
crearSwitch(panel, UDim2.new(1, -64, 0, 162), function(valor)
	girar = valor
	sliderGiro.GroupTransparency = girar and 0 or 0.55
	sliderRadio.GroupTransparency = girar and 0 or 0.55
end)

-- Fila 4: velocidad de giro
sliderGiro = crearSlider(panel, 200, {
	min = GIRO_MIN, max = GIRO_MAX, paso = 10, inicial = velGiro,
	textoMin = "Suave", textoMax = "Turbo",
	formato = function(v) return string.format("Vel. recorrido: %d°/s (%.2f v/s)", v, v / 360) end,
	alCambiar = function(v) velGiro = v end,
})
sliderGiro.GroupTransparency = 0.55

-- Fila 5: tamaño del círculo
sliderRadio = crearSlider(panel, 262, {
	min = ORB_MIN, max = ORB_MAX, paso = 1, inicial = radioOrbita,
	textoMin = "Pequeño", textoMax = "Grande",
	formato = function(v) return string.format("Radio del círculo: %d studs", v) end,
	alCambiar = function(v) radioOrbita = v end,
})
sliderRadio.GroupTransparency = 0.55

-- Contador
local lblContador = crearTexto(panel, "Recogidas: 0", 13, COL_SUB)
lblContador.Size = UDim2.new(1, -28, 0, 20)
lblContador.Position = UDim2.fromOffset(14, 328)

---------------------------------------------------------------------
-- Minimizar / cerrar
---------------------------------------------------------------------
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
	vivo = false
	activo = false
	enDestino = false
	quitarPlataforma()
	for _, c in ipairs(conexiones) do
		c:Disconnect()
	end
	table.clear(conexiones)
	gui:Destroy()
end

btnMin.MouseButton1Click:Connect(minimizar)
btnCerrar.MouseButton1Click:Connect(cerrar)
hacerArrastrable(barra, panel)
hacerArrastrable(burbuja, burbuja, restaurar)

---------------------------------------------------------------------
-- Recorrido circular en el aire (solo mientras está en el destino)
---------------------------------------------------------------------
conectar(RunService.Heartbeat, function(dt)
	if not (activo and girar and enDestino) then return end
	local char = LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	angulo = (angulo + math.rad(velGiro) * dt) % (math.pi * 2)
	local c, sn = math.cos(angulo), math.sin(angulo)
	local pos = DESTINO + Vector3.new(c * radioOrbita, 0, sn * radioOrbita)
	local tangente = Vector3.new(-sn, 0, c) -- mira hacia donde avanza

	root.CFrame = CFrame.lookAt(pos, pos + tangente)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	-- la plataforma acompaña al personaje para que no caiga
	if plataforma and plataforma.Parent then
		plataforma.Position = pos - Vector3.new(0, ALTURA_PLATAFORMA, 0)
	end
end)

---------------------------------------------------------------------
-- Lógica principal
---------------------------------------------------------------------
local function recogerBurbujas()
	local folder = Workspace:FindFirstChild("EnvironmentOxygenBubbles", true)
	if not folder then return end

	local root = getRoot()
	if not root then return end

	local recogio = false

	for _, bubble in ipairs(folder:GetChildren()) do
		if not activo then break end
		if not bubble.Parent then continue end

		local pos = getPosition(bubble)
		if pos and (root.Position - pos).Magnitude <= RADIO then
			enDestino = false -- deja de girar mientras recoge
			root.CFrame = CFrame.new(pos)
			recogio = true
			recogidas += 1
			lblContador.Text = "Recogidas: " .. recogidas
			task.wait(1 / velocidad)
		end
	end

	if activo and recogio and root.Parent then
		crearPlataforma()
		root.CFrame = CFrame.new(DESTINO)
		root.AssemblyLinearVelocity = Vector3.zero
		enDestino = true
	end
end

task.spawn(function()
	while vivo do
		task.wait(INTERVALO)
		if vivo and activo then
			local ok, err = pcall(recogerBurbujas)
			if not ok then
				warn("[ERROR]", err)
			end
		end
	end
end)
