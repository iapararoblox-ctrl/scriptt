-- TP DESTINOS · LocalScript (móvil)
-- Colócalo en StarterPlayer > StarterPlayerScripts o ejecútalo con tu ejecutor

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

---------------------------------------------------------------
-- CONFIGURACIÓN
---------------------------------------------------------------
local GUI_NAME = "TPDestinosPanel"
local OFFSET_Y = 4          -- studs por encima del punto de destino (evita quedar dentro del suelo)
local USAR_EN_VIVO = true   -- true: usa la posición del objeto si existe; false: usa solo la coordenada fija

-- ruta: carpetas desde Workspace hasta el objeto
-- pos: coordenada fija de respaldo
local DESTINOS = {
	{ nombre = "FrostIsland",     ruta = { "BluePort", "FrostIsland" }, pos = Vector3.new(-1414.68, 10.46, -2056.04) },
	{ nombre = "BluePort",        ruta = { "BluePort" },                pos = Vector3.new(-1385.82, 67.84, -2035.29) },
	{ nombre = "GreenPort",       ruta = { "GreenPort" },               pos = Vector3.new(547.06, 24.74, -2120.70) },
	{ nombre = "MutationIsland",  ruta = { "MutationIsland" },          pos = Vector3.new(-1330.35, 12.04, 1987.75) },
	{ nombre = "RedPort",         ruta = { "Model", "RedPort" },        pos = Vector3.new(-218.95, 16.03, -231.16) },
	{ nombre = "SmugglersCave",   ruta = { "Model", "SmugglersCave" },  pos = Vector3.new(-3325.72, 0, 633.30) },
	{ nombre = "Lighthouse",      ruta = { "Lighthouse" },              pos = Vector3.new(-3480.29, 41.40, -1604.03) },
	{ nombre = "Island1 (Bases)", ruta = { "Bases", "Island1" },        pos = Vector3.new(1021.92, 18.86, -167.86) },
}

local C = {
	bg = Color3.fromRGB(18, 20, 28),
	card = Color3.fromRGB(30, 33, 46),
	row = Color3.fromRGB(38, 42, 58),
	accent = Color3.fromRGB(0, 200, 255),
	green = Color3.fromRGB(70, 220, 140),
	amber = Color3.fromRGB(255, 180, 60),
	red = Color3.fromRGB(255, 96, 108),
	text = Color3.fromRGB(238, 240, 246),
	sub = Color3.fromRGB(135, 140, 160),
	white = Color3.fromRGB(255, 255, 255),
}

---------------------------------------------------------------
-- UTILIDADES
---------------------------------------------------------------
local function ruta(root, pasos)
	local cur = root
	for _, p in ipairs(pasos) do
		cur = cur and cur:FindFirstChild(p)
		if not cur then return nil end
	end
	return cur
end

local function posOf(obj)
	if obj:IsA("Model") then
		return obj:GetPivot().Position
	end
	if obj:IsA("BasePart") then
		return obj.Position
	end
	local bp = obj:FindFirstChildWhichIsA("BasePart", true)
	return bp and bp.Position
end

-- Devuelve la posición del destino y de dónde salió
local function resolve(d)
	if USAR_EN_VIVO then
		local obj = ruta(Workspace, d.ruta)
		if obj then
			local p = posOf(obj)
			if p then
				return p, "en vivo"
			end
		end
	end
	return d.pos, "fija"
end

-- La parte que se mueve: el asiento si estás sentado en algo, si no tu personaje
local function moverRoot()
	local char = LocalPlayer.Character
	if not char then return nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and hum.SeatPart then
		return hum.SeatPart
	end
	return char:FindFirstChild("HumanoidRootPart")
end

local function tpTo(pos)
	local root = moverRoot()
	if not root then
		return false
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.CFrame = CFrame.new(pos + Vector3.new(0, OFFSET_Y, 0))
	return true
end

local function fmt(v)
	return string.format("%.0f, %.0f, %.0f", v.X, v.Y, v.Z)
end

---------------------------------------------------------------
-- INTERFAZ
---------------------------------------------------------------
local function corner(obj, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = obj
end

local function label(parent, text, size, pos, textSize, color, bold)
	local l = Instance.new("TextLabel")
	l.Size = size
	l.Position = pos or UDim2.new()
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = color or C.text
	l.TextSize = textSize or 12
	l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Parent = parent
	return l
end

local function button(parent, text, size, pos, color, textSize)
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = pos or UDim2.new()
	b.BackgroundColor3 = color or C.card
	b.BorderSizePixel = 0
	b.Text = text
	b.TextColor3 = C.text
	b.TextSize = textSize or 13
	b.Font = Enum.Font.GothamBold
	b.AutoButtonColor = true
	b.Parent = parent
	corner(b, 10)
	return b
end

-- Arrastrar el panel desde la cabecera
local function makeDrag(handle, target)
	local UIS = game:GetService("UserInputService")
	local dragging, startInput, startPos = false, nil, nil
	handle.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			dragging = true
			startInput = input.Position
			startPos = Vector2.new(target.Position.X.Offset, target.Position.Y.Offset)
			local conn
			conn = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					conn:Disconnect()
				end
			end)
		end
	end)
	UIS.InputChanged:Connect(function(input)
		if not dragging then return end
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseMovement then
			local d = input.Position - startInput
			target.Position = UDim2.fromOffset(startPos.X + d.X, startPos.Y + d.Y)
		end
	end)
end

local old = PlayerGui:FindFirstChild(GUI_NAME)
if old then old:Destroy() end

local screen = Instance.new("ScreenGui")
screen.Name = GUI_NAME
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 999997
screen.Parent = PlayerGui

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(260, 420)
panel.Position = UDim2.fromOffset(12, 90)
panel.BackgroundColor3 = C.bg
panel.BorderSizePixel = 0
panel.ClipsDescendants = true
panel.Parent = screen
corner(panel, 14)

local uiScale = Instance.new("UIScale")
uiScale.Parent = panel
do
	local vp = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(390, 844)
	uiScale.Scale = math.clamp(math.min(vp.X * 0.92 / 260, vp.Y * 0.8 / 420), 0.6, 1)
end

-- Cabecera
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 42)
header.BackgroundColor3 = C.card
header.BorderSizePixel = 0
header.Active = true
header.Parent = panel
corner(header, 14)

label(header, "📍 Destinos", UDim2.new(1, -60, 1, 0), UDim2.fromOffset(14, 0), 15, C.text, true)

local closeBtn = button(header, "✕", UDim2.fromOffset(30, 30), UDim2.new(1, -36, 0, 6), Color3.fromRGB(60, 30, 36), 13)
closeBtn.TextColor3 = C.red

-- Buscador
local search = Instance.new("TextBox")
search.Size = UDim2.new(1, -24, 0, 30)
search.Position = UDim2.fromOffset(12, 50)
search.BackgroundColor3 = C.card
search.BorderSizePixel = 0
search.PlaceholderText = "Buscar destino..."
search.PlaceholderColor3 = C.sub
search.Text = ""
search.TextColor3 = C.text
search.TextSize = 13
search.Font = Enum.Font.Gotham
search.ClearTextOnFocus = false
search.Parent = panel
corner(search, 8)

-- Estado
local statusLbl = label(panel, "Listo", UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 86), 11, C.sub)

-- Lista
local list = Instance.new("ScrollingFrame")
list.Position = UDim2.fromOffset(12, 108)
list.Size = UDim2.new(1, -24, 1, -118)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 3
list.ScrollBarImageColor3 = C.accent
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

local statusToken = 0
local function setStatus(text, color)
	statusToken += 1
	local my = statusToken
	statusLbl.Text = text
	statusLbl.TextColor3 = color or C.sub
	task.delay(3, function()
		if my == statusToken and statusLbl.Parent then
			statusLbl.Text = "Listo"
			statusLbl.TextColor3 = C.sub
		end
	end)
end

local rows = {}
for i, d in ipairs(DESTINOS) do
	local f = Instance.new("TextButton")
	f.LayoutOrder = i
	f.Size = UDim2.new(1, -6, 0, 52)
	f.BackgroundColor3 = C.row
	f.BorderSizePixel = 0
	f.Text = ""
	f.AutoButtonColor = true
	f.Parent = list
	corner(f, 10)

	local nombre = label(f, d.nombre, UDim2.new(1, -20, 0, 20), UDim2.fromOffset(12, 6), 13, C.text, true)
	local info = label(f, "", UDim2.new(1, -20, 0, 16), UDim2.fromOffset(12, 28), 10, C.sub)

	f.Activated:Connect(function()
		local pos, fuente = resolve(d)
		if tpTo(pos) then
			setStatus("✅ Llegaste a " .. d.nombre .. " (" .. fuente .. ")", C.green)
		else
			setStatus("❌ No tengo personaje", C.red)
		end
	end)

	rows[i] = { frame = f, nombre = nombre, info = info, data = d }
end

-- Actualiza las coordenadas mostradas (en vivo o fijas) cada cierto tiempo
local function refreshRows()
	for _, r in ipairs(rows) do
		local pos, fuente = resolve(r.data)
		r.info.Text = fmt(pos) .. "  ·  " .. fuente
	end
end

-- Filtro por nombre
search:GetPropertyChangedSignal("Text"):Connect(function()
	local q = string.lower(search.Text)
	for _, r in ipairs(rows) do
		r.frame.Visible = (q == "") or (string.find(string.lower(r.data.nombre), q, 1, true) ~= nil)
	end
end)

closeBtn.Activated:Connect(function()
	screen:Destroy()
end)

makeDrag(header, panel)

refreshRows()
task.spawn(function()
	while screen.Parent do
		refreshRows()
		task.wait(1)
	end
end)
