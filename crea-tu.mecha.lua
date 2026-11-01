-- Panel Móvil · Construye un Mecha (Delta Executor Mobile)
-- Compacto, se minimiza a una burbuja y se vuelve a abrir con un toque.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local GUI_NAME = "MechaMobilePanel"
local PANEL_W, PANEL_H = 230, 250
local BUBBLE = 46
local SPEED_MIN, SPEED_MAX, SPEED_STEP = 10, 150, 10
local RANGO_RECOGER = 35

local COLOR = {
	bg = Color3.fromRGB(22, 23, 30),
	card = Color3.fromRGB(32, 34, 44),
	btn = Color3.fromRGB(44, 47, 62),
	accent = Color3.fromRGB(0, 200, 255),
	green = Color3.fromRGB(80, 230, 150),
	red = Color3.fromRGB(255, 100, 110),
	text = Color3.fromRGB(238, 240, 246),
	sub = Color3.fromRGB(135, 140, 160),
}

---------------------------------------------------------------
-- PADRE DE LA GUI (con fallback si el ejecutor no tiene gethui)
---------------------------------------------------------------
local function getParent()
	local ok, ui = pcall(function() return gethui and gethui() end)
	if ok and ui then return ui end
	local ok2, cg = pcall(function() return game:GetService("CoreGui") end)
	if ok2 and cg then return cg end
	return LocalPlayer:WaitForChild("PlayerGui")
end

local parent = getParent()
local old = parent:FindFirstChild(GUI_NAME)
if old then old:Destroy() end

---------------------------------------------------------------
-- HELPERS DE INTERFAZ
---------------------------------------------------------------
local function viewport()
	local cam = Workspace.CurrentCamera
	return cam and cam.ViewportSize or Vector2.new(390, 844)
end

local function clampPos(x, y, w, h)
	local vp = viewport()
	return math.clamp(x, 0, math.max(0, vp.X - w)), math.clamp(y, 0, math.max(0, vp.Y - h))
end

local function fitScale()
	local vp = viewport()
	local s = math.min(vp.X * 0.9 / PANEL_W, vp.Y * 0.7 / PANEL_H, 1.1)
	return math.clamp(s, 0.6, 1.1)
end

local function corner(obj, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = obj
end

local function btn(parentObj, text, size, pos, color, textSize)
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = pos or UDim2.new()
	b.BackgroundColor3 = color or COLOR.btn
	b.BorderSizePixel = 0
	b.Text = text
	b.TextColor3 = COLOR.text
	b.TextSize = textSize or 13
	b.Font = Enum.Font.GothamSemibold
	b.AutoButtonColor = true
	b.Parent = parentObj
	corner(b, 8)
	return b
end

local function lbl(parentObj, text, size, pos, textSize, color, font)
	local l = Instance.new("TextLabel")
	l.Size = size
	l.Position = pos or UDim2.new()
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = color or COLOR.text
	l.TextSize = textSize or 12
	l.Font = font or Enum.Font.GothamSemibold
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parentObj
	return l
end

-- Arrastrar con dedo o ratón. onTap = toque corto, onEnd = al soltar tras arrastrar
local function makeDrag(handle, target, onTap, onEnd)
	local dragging, moved = false, false
	local startInput, startPos

	handle.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1 then
			return
		end
		dragging, moved = true, false
		startInput = input.Position
		startPos = Vector2.new(target.Position.X.Offset, target.Position.Y.Offset)

		local conn
		conn = input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
				conn:Disconnect()
				if moved then
					if onEnd then onEnd() end
				elseif onTap then
					onTap()
				end
			end
		end)
	end)

	UserInputService.InputChanged:Connect(function(input)
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
	end)
end

---------------------------------------------------------------
-- LÓGICA DEL MECHA
---------------------------------------------------------------
local speed = 40

-- Modelos que son tuyos (por nombre o por el atributo OwnerName)
local function getMechas()
	local list = {}
	local name = LocalPlayer.Name
	for _, obj in ipairs(Workspace:GetChildren()) do
		if obj:IsA("Model") and (string.find(obj.Name, name, 1, true) or obj:GetAttribute("OwnerName") == name) then
			table.insert(list, obj)
		end
	end
	return list
end

-- Devuelve cuántos mechas se modificaron y si se encontró alguno
local function applySpeed()
	local mechas = getMechas()
	if #mechas == 0 then
		return 0, false
	end
	for _, m in ipairs(mechas) do
		if m:GetAttribute("WalkSpeed") ~= nil then
			m:SetAttribute("WalkSpeed", speed)
		end
		if m:GetAttribute("RunSpeed") ~= nil then
			m:SetAttribute("RunSpeed", speed + 20)
		end
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("Humanoid") then
				d.WalkSpeed = speed
			end
		end
	end
	return #mechas, true
end

-- Activa los ProximityPrompt de piezas cercanas. Devuelve -1 si no hay personaje o el ejecutor no lo soporta
local function recogerCercanas()
	local char = LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or not fireproximityprompt then
		return -1
	end
	local count = 0
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Enabled and d.Parent and d.Parent:IsA("BasePart") then
			if (d.Parent.Position - root.Position).Magnitude <= RANGO_RECOGER then
				pcall(fireproximityprompt, d)
				count += 1
			end
		end
	end
	return count
end

---------------------------------------------------------------
-- INTERFAZ
---------------------------------------------------------------
local screen = Instance.new("ScreenGui")
screen.Name = GUI_NAME
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 999998
screen.Parent = parent

-- Panel principal
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
panel.BackgroundColor3 = COLOR.bg
panel.BorderSizePixel = 0
panel.ClipsDescendants = true
panel.Parent = screen
corner(panel, 12)

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = COLOR.accent
panelStroke.Transparency = 0.5
panelStroke.Thickness = 1
panelStroke.Parent = panel

local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

-- Cabecera (zona para arrastrar)
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 36)
header.BackgroundTransparency = 1
header.Active = true
header.Parent = panel

lbl(header, "MECHA PANEL", UDim2.new(1, -80, 1, 0), UDim2.fromOffset(10, 0), 12, COLOR.accent, Enum.Font.GothamBold)

local minBtn = btn(header, "–", UDim2.fromOffset(28, 28), UDim2.new(1, -64, 0, 4), COLOR.btn, 15)
local closeBtn = btn(header, "✕", UDim2.fromOffset(28, 28), UDim2.new(1, -32, 0, 4), COLOR.btn, 12)
closeBtn.TextColor3 = COLOR.red

-- Tarjeta de velocidad
local speedCard = Instance.new("Frame")
speedCard.Position = UDim2.fromOffset(8, 42)
speedCard.Size = UDim2.new(1, -16, 0, 56)
speedCard.BackgroundColor3 = COLOR.card
speedCard.BorderSizePixel = 0
speedCard.Parent = panel
corner(speedCard, 8)

lbl(speedCard, "VELOCIDAD", UDim2.new(1, -20, 0, 14), UDim2.fromOffset(10, 6), 9, COLOR.sub, Enum.Font.GothamBold)

local minusBtn = btn(speedCard, "−", UDim2.fromOffset(34, 28), UDim2.new(0, 8, 0, 20), COLOR.btn, 16)
local plusBtn = btn(speedCard, "+", UDim2.fromOffset(34, 28), UDim2.new(1, -42, 0, 20), COLOR.btn, 16)

local speedValue = lbl(speedCard, "", UDim2.new(1, -92, 0, 30), UDim2.fromOffset(46, 20), 20, COLOR.green, Enum.Font.GothamBold)
speedValue.TextXAlignment = Enum.TextXAlignment.Center

-- Botones de acción
local applyBtn = btn(panel, "⚡  Aplicar velocidad", UDim2.new(1, -16, 0, 32), UDim2.fromOffset(8, 106), COLOR.btn, 12)
local pickBtn = btn(panel, "🧲  Recoger piezas cercanas", UDim2.new(1, -16, 0, 32), UDim2.fromOffset(8, 144), COLOR.btn, 12)
local statsBtn = btn(panel, "📊  Ver estadísticas", UDim2.new(1, -16, 0, 32), UDim2.fromOffset(8, 182), COLOR.btn, 12)

-- Línea de estado (aquí aparece el resultado de cada acción)
local statusLbl = lbl(panel, "Listo", UDim2.new(1, -16, 0, 18), UDim2.fromOffset(8, 222), 10, COLOR.sub, Enum.Font.Gotham)
statusLbl.TextXAlignment = Enum.TextXAlignment.Center

local statusToken = 0
local function setStatus(text, color)
	statusToken += 1
	local my = statusToken
	statusLbl.Text = text
	statusLbl.TextColor3 = color or COLOR.sub
	task.delay(2.5, function()
		if my == statusToken and statusLbl.Parent then
			statusLbl.Text = "Listo"
			statusLbl.TextColor3 = COLOR.sub
		end
	end)
end

local function refreshSpeed()
	speedValue.Text = tostring(speed)
end
refreshSpeed()

-- Burbuja (aparece al minimizar)
local bubble = Instance.new("TextButton")
bubble.Name = "Bubble"
bubble.Size = UDim2.fromOffset(BUBBLE, BUBBLE)
bubble.BackgroundColor3 = COLOR.accent
bubble.BorderSizePixel = 0
bubble.AutoButtonColor = false
bubble.Text = "🤖"
bubble.TextSize = 20
bubble.Font = Enum.Font.GothamBold
bubble.Visible = false
bubble.ZIndex = 10
bubble.Parent = screen
corner(bubble, BUBBLE / 2)

---------------------------------------------------------------
-- EVENTOS
---------------------------------------------------------------
minusBtn.Activated:Connect(function()
	speed = math.max(SPEED_MIN, speed - SPEED_STEP)
	refreshSpeed()
end)

plusBtn.Activated:Connect(function()
	speed = math.min(SPEED_MAX, speed + SPEED_STEP)
	refreshSpeed()
end)

applyBtn.Activated:Connect(function()
	local n, found = applySpeed()
	if found then
		setStatus("✅ Velocidad " .. speed .. " en " .. n .. " mecha(s)", COLOR.green)
	else
		setStatus("❌ No se encontró tu mecha", COLOR.red)
	end
end)

pickBtn.Activated:Connect(function()
	local n = recogerCercanas()
	if n < 0 then
		setStatus("❌ Sin personaje o sin fireproximityprompt", COLOR.red)
	else
		setStatus("✅ Piezas activadas: " .. n, COLOR.green)
	end
end)

statsBtn.Activated:Connect(function()
	local mechas = getMechas()
	if #mechas == 0 then
		setStatus("❌ No se encontró tu mecha", COLOR.red)
		return
	end
	for _, m in ipairs(mechas) do
		print("--- STATS DE MECHA ---")
		print("Nombre:", m.Name)
		print("CarryCapacity:", m:GetAttribute("CarryCapacity") or "N/A")
		print("CarryTotal:", m:GetAttribute("CarryTotal") or "N/A")
	end
	setStatus("✅ Estadísticas impresas (F9)", COLOR.green)
end)

closeBtn.Activated:Connect(function()
	screen:Destroy()
end)

---------------------------------------------------------------
-- MINIMIZAR A BURBUJA Y VOLVER A ABRIR
---------------------------------------------------------------
local minimized = false

local function setMinimized(v)
	minimized = v
	if v then
		local x, y = clampPos(panel.Position.X.Offset, panel.Position.Y.Offset, BUBBLE, BUBBLE)
		bubble.Position = UDim2.fromOffset(x, y)
	else
		local w = PANEL_W * panelScale.Scale
		local h = PANEL_H * panelScale.Scale
		local x, y = clampPos(bubble.Position.X.Offset, bubble.Position.Y.Offset, w, h)
		panel.Position = UDim2.fromOffset(x, y)
	end
	panel.Visible = not v
	bubble.Visible = v
end

minBtn.Activated:Connect(function()
	setMinimized(true)
end)

-- Toque corto en la burbuja = abrir; arrastrar = moverla
makeDrag(header, panel, nil, function()
	local w = PANEL_W * panelScale.Scale
	local h = PANEL_H * panelScale.Scale
	local x, y = clampPos(panel.Position.X.Offset, panel.Position.Y.Offset, w, h)
	panel.Position = UDim2.fromOffset(x, y)
end)

makeDrag(bubble, bubble,
	function() setMinimized(false) end,
	function()
		local x, y = clampPos(bubble.Position.X.Offset, bubble.Position.Y.Offset, BUBBLE, BUBBLE)
		bubble.Position = UDim2.fromOffset(x, y)
	end)

---------------------------------------------------------------
-- POSICIÓN INICIAL Y ADAPTACIÓN A LA PANTALLA
---------------------------------------------------------------
local function layout()
	panelScale.Scale = fitScale()
	local w = PANEL_W * panelScale.Scale
	local h = PANEL_H * panelScale.Scale
	if panel.Position == UDim2.new() then
		local vp = viewport()
		local x, y = clampPos((vp.X - w) / 2, vp.Y * 0.18, w, h)
		panel.Position = UDim2.fromOffset(x, y)
	else
		local x, y = clampPos(panel.Position.X.Offset, panel.Position.Y.Offset, w, h)
		panel.Position = UDim2.fromOffset(x, y)
	end
	if bubble.Position == UDim2.new() then
		local vp = viewport()
		bubble.Position = UDim2.fromOffset(vp.X - BUBBLE - 12, vp.Y * 0.45)
	end
end

layout()

local cam = Workspace.CurrentCamera
if cam then
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
end
