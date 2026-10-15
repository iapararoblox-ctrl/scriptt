-- LocalScript en StarterPlayer > StarterPlayerScripts

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- ================= CONFIGURACIÓN (solo desde el código) =================
local VELOCIDAD_TP = 60 -- studs por segundo para el viaje suave
local COLOR_PRINCIPAL = Color3.fromRGB(88, 101, 242)
local COLOR_FONDO = Color3.fromRGB(22, 24, 34)
local COLOR_CAMPO = Color3.fromRGB(35, 38, 52)
local COLOR_ERROR = Color3.fromRGB(255, 110, 110)
local COLOR_AVISO = Color3.fromRGB(255, 170, 90)
local COLOR_OK = Color3.fromRGB(110, 230, 150)
-- =======================================================================

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Helpers para crear objetos
local function crear(clase, propiedades, hijos)
	local obj = Instance.new(clase)
	for k, v in pairs(propiedades or {}) do
		obj[k] = v
	end
	for _, hijo in ipairs(hijos or {}) do
		hijo.Parent = obj
	end
	return obj
end

local function redondear(radio)
	return crear("UICorner", { CornerRadius = UDim.new(0, radio) })
end

-- ================= GUI =================
local gui = crear("ScreenGui", {
	Name = "TeleportUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})

-- Botón flotante para abrir/cerrar
local botonAbrir = crear("TextButton", {
	Name = "AbrirTP",
	Size = UDim2.fromOffset(48, 48),
	Position = UDim2.fromOffset(16, 16),
	BackgroundColor3 = COLOR_PRINCIPAL,
	Text = "📍",
	TextSize = 24,
	Font = Enum.Font.GothamBold,
	TextColor3 = Color3.new(1, 1, 1),
	AutoButtonColor = true,
	Parent = gui,
}, { redondear(12) })

-- Panel principal
local PANEL_TAM = UDim2.fromOffset(300, 260)
local panel = crear("Frame", {
	Name = "Panel",
	Size = PANEL_TAM,
	Position = UDim2.new(0.5, 0, 0.5, 0),
	AnchorPoint = Vector3.new(0.5, 0.5),
	BackgroundColor3 = COLOR_FONDO,
	Visible = false,
	Parent = gui,
}, {
	redondear(16),
	crear("UIStroke", { Color = COLOR_PRINCIPAL, Thickness = 2 }),
})

-- Título
crear("TextLabel", {
	Size = UDim2.new(1, -60, 0, 50),
	Position = UDim2.fromOffset(16, 0),
	BackgroundTransparency = 1,
	Text = "Teleporte",
	TextColor3 = Color3.new(1, 1, 1),
	Font = Enum.Font.GothamBold,
	TextSize = 20,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = panel,
})

-- Botón cerrar
local botonCerrar = crear("TextButton", {
	Size = UDim2.fromOffset(30, 30),
	Position = UDim2.new(1, -40, 0, 10),
	BackgroundColor3 = COLOR_CAMPO,
	Text = "✕",
	TextSize = 16,
	Font = Enum.Font.GothamBold,
	TextColor3 = Color3.new(1, 1, 1),
	Parent = panel,
}, { redondear(8) })

-- Cajas de texto X, Y, Z
local function crearCaja(texto, posX)
	return crear("TextBox", {
		Size = UDim2.new(0.27, 0, 0, 44),
		Position = UDim2.new(posX, 0, 0, 70),
		BackgroundColor3 = COLOR_CAMPO,
		PlaceholderText = texto,
		PlaceholderColor3 = Color3.fromRGB(140, 140, 160),
		Text = "",
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamMedium,
		TextSize = 18,
		ClearTextOnFocus = false,
		Parent = panel,
	}, { redondear(10) })
end

local cajaX = crearCaja("X", 0.05)
local cajaY = crearCaja("Y", 0.365)
local cajaZ = crearCaja("Z", 0.68)

-- Texto de estado
local estado = crear("TextLabel", {
	Size = UDim2.new(0.9, 0, 0, 30),
	Position = UDim2.new(0.05, 0, 0, 124),
	BackgroundTransparency = 1,
	Text = "Ingresa las coordenadas",
	TextColor3 = Color3.fromRGB(180, 180, 200),
	Font = Enum.Font.Gotham,
	TextSize = 14,
	Parent = panel,
})

local function mostrarEstado(texto, color)
	estado.Text = texto
	estado.TextColor3 = color or Color3.fromRGB(180, 180, 200)
end

-- Botón principal
local boton = crear("TextButton", {
	Size = UDim2.new(0.9, 0, 0, 48),
	Position = UDim2.new(0.05, 0, 0, 170),
	BackgroundColor3 = COLOR_PRINCIPAL,
	Text = "Teleportar",
	TextColor3 = Color3.new(1, 1, 1),
	Font = Enum.Font.GothamBold,
	TextSize = 18,
	AutoButtonColor = false,
	Parent = panel,
}, {
	redondear(12),
	crear("UIGradient", {
		Color = ColorSequence.new(COLOR_PRINCIPAL, Color3.fromRGB(140, 80, 255)),
		Rotation = 90,
	}),
})

-- ================= ANIMACIÓN DEL PANEL =================
local abierto = false

local function alternarPanel()
	abierto = not abierto
	if abierto then
		panel.Visible = true
		panel.Size = UDim2.fromOffset(0, 0)
		TweenService:Create(panel, TweenInfo.new(0.25, Enum.EasingStyle.Back), {
			Size = PANEL_TAM,
		}):Play()
	else
		local tween = TweenService:Create(panel, TweenInfo.new(0.2), {
			Size = UDim2.fromOffset(0, 0),
		})
		tween:Play()
		tween.Completed:Once(function()
			if not abierto then
				panel.Visible = false
			end
		end)
	end
end

botonAbrir.MouseButton1Click:Connect(alternarPanel)
botonCerrar.MouseButton1Click:Connect(alternarPanel)

-- ================= MOVIMIENTO SUAVE =================
local viajando = false
local conexion = nil

local function terminarViaje(mensaje, color)
	if conexion then
		conexion:Disconnect()
		conexion = nil
	end
	viajando = false
	boton.Text = "Teleportar"
	mostrarEstado(mensaje, color)
end

local function teleportarSuave(destino)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if not hrp or not humanoid or humanoid.Health <= 0 then
		mostrarEstado("No se encontró tu personaje", COLOR_ERROR)
		return
	end

	viajando = true
	boton.Text = "Cancelar"
	mostrarEstado("Viajando...", COLOR_PRINCIPAL)

	conexion = RunService.Heartbeat:Connect(function(dt)
		if not hrp.Parent or humanoid.Health <= 0 then
			terminarViaje("Viaje interrumpido", COLOR_ERROR)
			return
		end

		local diferencia = destino - hrp.Position
		local distancia = diferencia.Magnitude
		local paso = VELOCIDAD_TP * dt
		local rotacion = hrp.CFrame - hrp.CFrame.Position

		hrp.AssemblyLinearVelocity = Vector3.zero

		if distancia <= paso then
			hrp.CFrame = CFrame.new(destino) * rotacion
			terminarViaje("Llegaste al destino", COLOR_OK)
			return
		end

		local nuevaPos = hrp.Position + diferencia.Unit * paso
		hrp.CFrame = CFrame.new(nuevaPos) * rotacion
	end)
end

boton.MouseButton1Click:Connect(function()
	if viajando then
		terminarViaje("Viaje cancelado", COLOR_AVISO)
		return
	end

	local x = tonumber(cajaX.Text)
	local y = tonumber(cajaY.Text)
	local z = tonumber(cajaZ.Text)

	if not (x and y and z) then
		mostrarEstado("Ingresa coordenadas válidas (números)", COLOR_ERROR)
		return
	end

	teleportarSuave(Vector3.new(x, y, z))
end)
