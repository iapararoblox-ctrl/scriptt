local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

---------------------------------------------------------------------
-- Configuración
---------------------------------------------------------------------
local RADIO = 500000
local INTERVALO = 1
local DESTINO = Vector3.new(11, 49, -553)
local ALTURA_PLATAFORMA = 3.5

local VEL_MIN, VEL_MAX = 1, 20 -- burbujas por segundo

-- TP aleatorio
local RADIO_TP = 60    -- radio alrededor del DESTINO donde se generan los puntos
local SEPARACION = 12  -- distancia mínima para que dos puntos cuenten como "distintos"

-- Estado
local velocidad = 7
local activo = false
local tpAleatorio = false
local cerrado = false
local recogidas = 0
local plataforma = nil
local visitados = {}   -- ubicaciones a las que ya se teletransportó
local conexiones = {}  -- conexiones globales (se desconectan al cerrar)

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

-- Devuelve una ubicación que no se parezca a ninguna ya visitada.
-- Si ya no quedan ubicaciones libres, reinicia el historial.
local function posicionAleatoria()
	for _ = 1, 2 do
		for _ = 1, 40 do
			local ang = math.random() * math.pi * 2
			local dist = math.sqrt(math.random()) * RADIO_TP
			local cand = DESTINO + Vector3.new(math.cos(ang) * dist, 0, math.sin(ang) * dist)

			local libre = true
			for _, v in ipairs(visitados) do
				if (v - cand).Magnitude < SEPARACION then
					libre = false
					break
				end
			end

			if libre then
				table.insert(visitados, cand)
				return cand
			end
		end
		visitados = {} -- se agotaron los puntos libres: empezar de nuevo
	end
	return DESTINO
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

-- Interruptor reutilizable
local function crearSwitch(parent, posicion, colorOn, alCambiar)
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
	sw.MouseButton1Click:Connect(function()
		estado = not estado
		local info = TweenInfo.new(0.18, Enum.EasingStyle.Quad)
		TweenService:Create(sw, info, { BackgroundColor3 = estado and colorOn or COL_OFF }):Play()
		TweenService:Create(perilla, info, { Position = UDim2.fromOffset(estado and 27 or 3, 3) }):Play()
		alCambiar(estado)
	end)
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
panel.Size = UDim2.fromOffset(250, 222)
panel.Position = UDim2.new(0, 20, 0.5, -111)
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

crearSwitch(panel, UDim2.new(1, -64, 0, 50), COL_ON, function(valor)
	activo = valor
	if not activo then
		quitarPlataforma()
	end
	lblEstado.Text = activo and "Estado: activo" or "Estado: apagado"
	lblEstado.TextColor3 = activo and COL_ON or COL_SUB
	burbuja.BackgroundColor3 = activo and COL_ON or COL_ACENTO
end)

-- Fila 2: TP aleatorio
local lblRandom = crearTexto(panel, "TP aleatorio: OFF", 14, COL_SUB)
lblRandom.Size = UDim2.new(1, -90, 0, 26)
lblRandom.Position = UDim2.fromOffset(14, 88)

crearSwitch(panel, UDim2.new(1, -64, 0, 88), COL_ACENTO, function(valor)
	tpAleatorio = valor
	visitados = {} -- historial limpio al activar o desactivar
	lblRandom.Text = valor and "TP aleatorio: ON" or "TP aleatorio: OFF"
	lblRandom.TextColor3 = valor and COL_ACENTO or COL_SUB
end)

-- Fila 3: velocidad (slider)
local lblVel = crearTexto(panel, "", 14, COL_TEXTO)
lblVel.Size = UDim2.new(1, -28, 0, 20)
lblVel.Position = UDim2.fromOffset(14, 130)

local track = Instance.new("Frame")
track.Size = UDim2.new(1, -28, 0, 8)
track.Position = UDim2.fromOffset(14, 160)
track.BackgroundColor3 = COL_BARRA
track.BorderSizePixel = 0
track.Parent = panel
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

local lblMin = crearTexto(panel, "Lento", 11, COL_SUB)
lblMin.Size = UDim2.fromOffset(60, 14)
lblMin.Position = UDim2.fromOffset(14, 174)

local lblMax = crearTexto(panel, "Rápido", 11, COL_SUB)
lblMax.Size = UDim2.fromOffset(60, 14)
lblMax.Position = UDim2.new(1, -74, 0, 174)
lblMax.TextXAlignment = Enum.TextXAlignment.Right

local lblContador = crearTexto(panel, "Recogidas: 0", 13, COL_SUB)
lblContador.Size = UDim2.new(1, -28, 0, 20)
lblContador.Position = UDim2.fromOffset(14, 196)

local function setVelocidad(alpha)
	alpha = math.clamp(alpha, 0, 1)
	velocidad = math.floor(VEL_MIN + alpha * (VEL_MAX - VEL_MIN) + 0.5)
	local a = (velocidad - VEL_MIN) / (VEL_MAX - VEL_MIN)
	fill.Size = UDim2.fromScale(a, 1)
	knob.Position = UDim2.fromScale(a, 0.5)
	lblVel.Text = string.format("Velocidad: %d burb/s  (%.2fs)", velocidad, 1 / velocidad)
end
setVelocidad((velocidad - VEL_MIN) / (VEL_MAX - VEL_MIN))

local deslizando = false
local function desdeX(x)
	setVelocidad((x - track.AbsolutePosition.X) / track.AbsoluteSize.X)
end

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
	cerrado = true
	activo = false
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
-- Lógica principal
---------------------------------------------------------------------
local function recogerBurbujas()
	local root = getRoot()
	if not root then return end

	local recogio = false
	local folder = Workspace:FindFirstChild("EnvironmentOxygenBubbles", true)

	if folder then
		for _, bubble in ipairs(folder:GetChildren()) do
			if not activo then break end
			if not bubble.Parent then continue end

			local pos = getPosition(bubble)
			if pos and (root.Position - pos).Magnitude <= RADIO then
				root.CFrame = CFrame.new(pos)
				recogio = true
				recogidas += 1
				lblContador.Text = "Recogidas: " .. recogidas
				task.wait(1 / velocidad) -- se lee en cada burbuja: el slider aplica al instante
			end
		end
	else
		lblContador.Text = "Recogidas: " .. recogidas .. "  (sin burbujas)"
	end

	-- el personaje pudo reaparecer mientras recogía
	if not root.Parent then
		root = getRoot()
		if not root then return end
	end

	if activo and root.Parent then
		if tpAleatorio then
			-- en vez de quedarse quieto, salta a una ubicación nueva cada ciclo
			local destino = posicionAleatoria()
			crearPlataforma(destino)
			root.CFrame = CFrame.new(destino)
			root.AssemblyLinearVelocity = Vector3.zero
		elseif recogio then
			crearPlataforma(DESTINO)
			root.CFrame = CFrame.new(DESTINO)
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end
end

task.spawn(function()
	while not cerrado do
		task.wait(INTERVALO)
		if not cerrado and activo then
			local ok, err = pcall(recogerBurbujas)
			if not ok then
				warn("[ERROR]", err)
			end
		end
	end
end)
