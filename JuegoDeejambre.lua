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
local velocidad = 7            -- ~0.14s entre burbujas

local activo = false
local recogidas = 0
local plataforma = nil

-- Paleta
local COL_FONDO = Color3.fromRGB(24, 26, 36)
local COL_BARRA = Color3.fromRGB(34, 37, 52)
local COL_ACENTO = Color3.fromRGB(80, 170, 255)
local COL_ON = Color3.fromRGB(60, 200, 120)
local COL_OFF = Color3.fromRGB(90, 94, 115)
local COL_TEXTO = Color3.fromRGB(235, 238, 250)
local COL_SUB = Color3.fromRGB(150, 156, 180)

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
	t.Parent = parent
	return t
end

local function hacerArrastrable(handle, target, alTocar)
	local arrastrando, movido = false, false
	local inicioInput, inicioPos

	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
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

	UserInputService.InputChanged:Connect(function(input)
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

---------------------------------------------------------------------
-- UI
---------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "BurbujasUI"
gui.ResetOnSpawn = false
gui.Parent = PlayerGui

-- Panel principal
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(250, 190)
panel.Position = UDim2.new(0, 20, 0.5, -95)
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

-- Tapa las esquinas inferiores redondeadas de la barra
local tapa = Instance.new("Frame")
tapa.Size = UDim2.new(1, 0, 0, 14)
tapa.Position = UDim2.new(0, 0, 1, -14)
tapa.BackgroundColor3 = COL_BARRA
tapa.BorderSizePixel = 0
tapa.Parent = barra

local titulo = crearTexto(barra, "🫧  Auto Burbujas", 15, COL_TEXTO, Enum.Font.GothamBold)
titulo.Size = UDim2.new(1, -50, 1, 0)
titulo.Position = UDim2.fromOffset(14, 0)
titulo.TextXAlignment = Enum.TextXAlignment.Left

local btnMin = Instance.new("TextButton")
btnMin.Size = UDim2.fromOffset(26, 26)
btnMin.Position = UDim2.new(1, -34, 0.5, -13)
btnMin.BackgroundColor3 = COL_FONDO
btnMin.Text = "–"
btnMin.TextColor3 = COL_TEXTO
btnMin.Font = Enum.Font.GothamBold
btnMin.TextSize = 18
btnMin.AutoButtonColor = true
btnMin.Parent = barra
redondear(btnMin, 8)

-- Fila: interruptor
local filaToggle = Instance.new("Frame")
filaToggle.Size = UDim2.new(1, -28, 0, 30)
filaToggle.Position = UDim2.fromOffset(14, 52)
filaToggle.BackgroundTransparency = 1
filaToggle.Parent = panel

local lblEstado = crearTexto(filaToggle, "Estado: apagado", 14, COL_SUB)
lblEstado.Size = UDim2.new(1, -60, 1, 0)
lblEstado.TextXAlignment = Enum.TextXAlignment.Left

local switch = Instance.new("TextButton")
switch.Size = UDim2.fromOffset(50, 26)
switch.Position = UDim2.new(1, -50, 0.5, -13)
switch.BackgroundColor3 = COL_OFF
switch.Text = ""
switch.AutoButtonColor = false
switch.Parent = filaToggle
redondear(switch, 13)

local perilla = Instance.new("Frame")
perilla.Size = UDim2.fromOffset(20, 20)
perilla.Position = UDim2.fromOffset(3, 3)
perilla.BackgroundColor3 = Color3.new(1, 1, 1)
perilla.BorderSizePixel = 0
perilla.Parent = switch
redondear(perilla, 10)

-- Fila: velocidad
local lblVel = crearTexto(panel, "", 14, COL_TEXTO)
lblVel.Size = UDim2.new(1, -28, 0, 20)
lblVel.Position = UDim2.fromOffset(14, 94)
lblVel.TextXAlignment = Enum.TextXAlignment.Left

local track = Instance.new("Frame")
track.Size = UDim2.new(1, -28, 0, 8)
track.Position = UDim2.fromOffset(14, 124)
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

-- Marcas min / max
local lblMin = crearTexto(panel, "Lento", 11, COL_SUB)
lblMin.Size = UDim2.fromOffset(60, 14)
lblMin.Position = UDim2.fromOffset(14, 138)
lblMin.TextXAlignment = Enum.TextXAlignment.Left

local lblMax = crearTexto(panel, "Rápido", 11, COL_SUB)
lblMax.Size = UDim2.fromOffset(60, 14)
lblMax.Position = UDim2.new(1, -74, 0, 138)
lblMax.TextXAlignment = Enum.TextXAlignment.Right

-- Contador
local lblContador = crearTexto(panel, "Recogidas: 0", 13, COL_SUB)
lblContador.Size = UDim2.new(1, -28, 0, 20)
lblContador.Position = UDim2.fromOffset(14, 160)
lblContador.TextXAlignment = Enum.TextXAlignment.Left

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

---------------------------------------------------------------------
-- Comportamiento de la UI
---------------------------------------------------------------------
local function actualizarToggle()
	local info = TweenInfo.new(0.18, Enum.EasingStyle.Quad)
	if activo then
		TweenService:Create(switch, info, { BackgroundColor3 = COL_ON }):Play()
		TweenService:Create(perilla, info, { Position = UDim2.fromOffset(27, 3) }):Play()
		lblEstado.Text = "Estado: activo"
		lblEstado.TextColor3 = COL_ON
		burbuja.BackgroundColor3 = COL_ON
	else
		TweenService:Create(switch, info, { BackgroundColor3 = COL_OFF }):Play()
		TweenService:Create(perilla, info, { Position = UDim2.fromOffset(3, 3) }):Play()
		lblEstado.Text = "Estado: apagado"
		lblEstado.TextColor3 = COL_SUB
		burbuja.BackgroundColor3 = COL_ACENTO
	end
end

local function quitarPlataforma()
	if plataforma then
		plataforma:Destroy()
		plataforma = nil
	end
end

switch.MouseButton1Click:Connect(function()
	activo = not activo
	if not activo then
		quitarPlataforma()
	end
	actualizarToggle()
end)

-- Slider de velocidad
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
local function desdeInput(posX)
	setVelocidad((posX - track.AbsolutePosition.X) / track.AbsoluteSize.X)
end

local function esPuntero(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

for _, objeto in ipairs({ track, knob }) do
	objeto.InputBegan:Connect(function(input)
		if esPuntero(input) then
			deslizando = true
			desdeInput(input.Position.X)
		end
	end)
end

UserInputService.InputChanged:Connect(function(input)
	if deslizando and (input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch) then
		desdeInput(input.Position.X)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if esPuntero(input) then
		deslizando = false
	end
end)

-- Minimizar / restaurar
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

btnMin.MouseButton1Click:Connect(minimizar)

hacerArrastrable(barra, panel)
hacerArrastrable(burbuja, burbuja, restaurar)

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
			root.CFrame = CFrame.new(pos)
			recogio = true
			recogidas += 1
			lblContador.Text = "Recogidas: " .. recogidas
			task.wait(1 / velocidad) -- se lee en cada iteración: el slider aplica al instante
		end
	end

	if activo and recogio and root.Parent then
		crearPlataforma()
		root.CFrame = CFrame.new(DESTINO)
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

task.spawn(function()
	while task.wait(INTERVALO) do
		if activo then
			local ok, err = pcall(recogerBurbujas)
			if not ok then
				warn("[ERROR]", err)
			end
		end
	end
end)

actualizarToggle()
