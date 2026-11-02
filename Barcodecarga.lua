-- BOAT PANEL v1 · Velocidad y altura máxima del barco (panel para móvil)
-- Barcos: modelos en Workspace con nombre "Boat_...".
-- Usa TU barco: el que tienes como asiento, o uno con tu nombre, o el más cercano (<80 studs).
-- Los valores de velocidad y altura se guardan en BoatPanel.json (writefile).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

---------------------------------------------------------------
-- CONFIGURACIÓN
---------------------------------------------------------------
local CFG = {
	GUI_NAME = "BoatMobilePanel",
	SAVE_FILE = "BoatPanel.json",
	PANEL_W = 250,
	PANEL_H = 392,
	BUBBLE = 48,

	SPEED_MIN = 10,
	SPEED_MAX = 400,
	SPEED_STEP = 10,
	SPEED_DEFAULT = 80,

	HEIGHT_MIN = 1,
	HEIGHT_MAX = 300,
	HEIGHT_STEP = 5,
	HEIGHT_DEFAULT = 15,

	RISE_SPEED = 25,      -- studs por segundo al subir/bajar
	BOAT_RANGE = 80,      -- distancia máxima para elegir un barco cercano
	ACCEL = 0.2,          -- qué tan rápido llega a la velocidad elegida (0-1)
}

local COLOR = {
	bg = Color3.fromRGB(16, 22, 32),
	card = Color3.fromRGB(26, 35, 50),
	btn = Color3.fromRGB(40, 52, 72),
	accent = Color3.fromRGB(0, 190, 255),
	green = Color3.fromRGB(70, 220, 140),
	amber = Color3.fromRGB(255, 180, 60),
	red = Color3.fromRGB(255, 96, 108),
	cyan = Color3.fromRGB(90, 230, 255),
	text = Color3.fromRGB(238, 242, 248),
	sub = Color3.fromRGB(135, 148, 170),
	white = Color3.fromRGB(255, 255, 255),
	track = Color3.fromRGB(44, 56, 78),
}

---------------------------------------------------------------
-- ESTADO
---------------------------------------------------------------
local S = {
	closed = false,
	placed = false,
	speed = CFG.SPEED_DEFAULT,
	speedOn = false,
	height = CFG.HEIGHT_DEFAULT,
	elevOn = false,
	boat = nil,
	seated = false,
}

local E = { boat = nil, baseY = 0 } -- estado de la elevación
local ui = {}

---------------------------------------------------------------
-- GUARDADO / CARGA
---------------------------------------------------------------
local function saveNow()
	if not writefile then return end
	pcall(function()
		writefile(CFG.SAVE_FILE, HttpService:JSONEncode({
			speed = S.speed,
			height = S.height,
		}))
	end)
end

local saveTok = 0
local function save()
	saveTok += 1
	local my = saveTok
	task.delay(0.5, function()
		if my == saveTok then saveNow() end
	end)
end

do
	if readfile and isfile then
		local ok, data = pcall(function()
			if isfile(CFG.SAVE_FILE) then
				return HttpService:JSONDecode(readfile(CFG.SAVE_FILE))
			end
		end)
		if ok and type(data) == "table" then
			if tonumber(data.speed) then
				S.speed = math.clamp(math.floor(tonumber(data.speed)), CFG.SPEED_MIN, CFG.SPEED_MAX)
			end
			if tonumber(data.height) then
				S.height = math.clamp(math.floor(tonumber(data.height)), CFG.HEIGHT_MIN, CFG.HEIGHT_MAX)
			end
		end
	end
end

---------------------------------------------------------------
-- BARCO
---------------------------------------------------------------
local function hrpNow()
	local char = LocalPlayer.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function humNow()
	local char = LocalPlayer.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function mainPart(boat)
	local p = boat:FindFirstChild("submerge", true)
	if p and p:IsA("BasePart") then return p end
	if boat.PrimaryPart then return boat.PrimaryPart end
	return boat:FindFirstChildWhichIsA("BasePart", true)
end

local function seatOf(boat)
	local s = boat:FindFirstChild("DriverSeat", true)
	if s and s:IsA("BasePart") then return s end
	return boat:FindFirstChildWhichIsA("VehicleSeat", true)
end

local function isSeatedIn(boat)
	local hum = humNow()
	return hum ~= nil and hum.SeatPart ~= nil and hum.SeatPart:IsDescendantOf(boat)
end

local function findBoat()
	local list = {}
	for _, o in ipairs(Workspace:GetChildren()) do
		if o:IsA("Model") and o.Name:match("^Boat_") then
			table.insert(list, o)
		end
	end

	for _, b in ipairs(list) do
		if isSeatedIn(b) then return b, true end
	end
	for _, b in ipairs(list) do
		if string.find(b.Name, LocalPlayer.Name, 1, true) then return b, false end
	end

	local root = hrpNow()
	if root then
		local best, bestD
		for _, b in ipairs(list) do
			local d = (b:GetPivot().Position - root.Position).Magnitude
			if d <= CFG.BOAT_RANGE and (not bestD or d < bestD) then
				best, bestD = b, d
			end
		end
		if best then return best, false end
	end
	return nil, false
end

---------------------------------------------------------------
-- VELOCIDAD (reversible)
---------------------------------------------------------------
local origMax = setmetatable({}, { __mode = "k" })

local function applyMaxSpeed(boat)
	for _, d in ipairs(boat:GetDescendants()) do
		if d:IsA("VehicleSeat") then
			if origMax[d] == nil then origMax[d] = d.MaxSpeed end
			if d.MaxSpeed ~= S.speed then d.MaxSpeed = S.speed end
		end
	end
	local a = boat:GetAttribute("MaxSpeed")
	if a ~= nil and tonumber(a) then
		if origMax[boat] == nil then origMax[boat] = a end
		if a ~= S.speed then boat:SetAttribute("MaxSpeed", S.speed) end
	end
end

local function restoreMaxSpeed()
	for inst, v in pairs(origMax) do
		if inst.Parent then
			if inst:IsA("VehicleSeat") then
				inst.MaxSpeed = v
			else
				inst:SetAttribute("MaxSpeed", v)
			end
		end
		origMax[inst] = nil
	end
end

local function speedStep(boat)
	if not isSeatedIn(boat) then return end
	local part = mainPart(boat)
	if not part then return end

	local seat = seatOf(boat)
	local throttle = 0
	if seat and seat:IsA("VehicleSeat") then
		throttle = seat.ThrottleFloat
	end
	if throttle == 0 then
		local hum = humNow()
		if hum and hum.MoveDirection.Magnitude > 0.1 then
			throttle = 1
		end
	end
	if throttle == 0 then return end

	local vel = part.AssemblyLinearVelocity
	local flat = Vector3.new(vel.X, 0, vel.Z)
	local mag = flat.Magnitude
	local dir
	if mag > 3 then
		dir = flat.Unit
	else
		local look = part.CFrame.LookVector
		local f = Vector3.new(look.X, 0, look.Z)
		if f.Magnitude < 0.01 then return end
		dir = f.Unit * (throttle >= 0 and 1 or -1)
	end

	local newMag = mag + (S.speed - mag) * CFG.ACCEL
	part.AssemblyLinearVelocity = Vector3.new(dir.X * newMag, vel.Y, dir.Z * newMag)
end

---------------------------------------------------------------
-- ELEVACIÓN (sube hasta la altura elegida y se queda ahí)
---------------------------------------------------------------
local function moveY(boat, targetY, dt)
	local cf = boat:GetPivot()
	local diff = targetY - cf.Position.Y
	local maxStep = CFG.RISE_SPEED * dt
	local step = math.clamp(diff, -maxStep, maxStep)
	if math.abs(diff) < 0.05 then step = diff end
	boat:PivotTo(cf + Vector3.new(0, step, 0))

	local part = mainPart(boat)
	if part then
		local v = part.AssemblyLinearVelocity
		part.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
	end
end

local function elevStep(dt)
	if S.elevOn then
		local boat = S.boat
		if not boat then return end
		if E.boat ~= boat then
			E.boat = boat
			E.baseY = boat:GetPivot().Position.Y
		end
		moveY(boat, E.baseY + S.height, dt)
	elseif E.boat then
		local boat = E.boat
		if not boat.Parent then
			E.boat = nil
			return
		end
		if boat:GetPivot().Position.Y - E.baseY <= 0.5 then
			E.boat = nil
		else
			moveY(boat, E.baseY, dt)
		end
	end
end

---------------------------------------------------------------
-- HELPERS DE INTERFAZ
---------------------------------------------------------------
local function getParent()
	local ok, h = pcall(function() return gethui and gethui() end)
	if ok and h then return h end
	local ok2, cg = pcall(function() return game:GetService("CoreGui") end)
	if ok2 and cg then return cg end
	return LocalPlayer:WaitForChild("PlayerGui")
end

local function corner(obj, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = obj
	return c
end

local function stroke(obj, color, transparency, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Transparency = transparency or 0
	s.Thickness = thickness or 1
	s.Parent = obj
	return s
end

local function btn(parent, text, size, pos, color, textSize)
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
	b.Parent = parent
	corner(b, 8)
	return b
end

local function lbl(parent, text, size, pos, textSize, color, font)
	local l = Instance.new("TextLabel")
	l.Size = size
	l.Position = pos or UDim2.new()
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = color or COLOR.text
	l.TextSize = textSize or 12
	l.Font = font or Enum.Font.GothamSemibold
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Parent = parent
	return l
end

local function card(parent, order, h)
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, 0, 0, h)
	f.BackgroundColor3 = COLOR.card
	f.BorderSizePixel = 0
	f.LayoutOrder = order
	f.Parent = parent
	corner(f, 10)
	return f
end

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
	return math.clamp(math.min(vp.X * 0.9 / CFG.PANEL_W, vp.Y * 0.8 / CFG.PANEL_H, 1.1), 0.6, 1.1)
end

local dragConns = {}
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

	table.insert(dragConns, UserInputService.InputChanged:Connect(function(input)
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
	end))
end

---------------------------------------------------------------
-- CONSTRUCCIÓN DE LA INTERFAZ
---------------------------------------------------------------
local parent = getParent()
local old = parent:FindFirstChild(CFG.GUI_NAME)
if old then old:Destroy() end

local screen = Instance.new("ScreenGui")
screen.Name = CFG.GUI_NAME
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 999998
screen.Parent = parent

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(CFG.PANEL_W, CFG.PANEL_H)
panel.BackgroundColor3 = COLOR.bg
panel.BorderSizePixel = 0
panel.ClipsDescendants = true
panel.Parent = screen
corner(panel, 14)
stroke(panel, COLOR.accent, 0.45, 1.2)

local scale = Instance.new("UIScale")
scale.Parent = panel

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 40)
header.BackgroundTransparency = 1
header.Active = true
header.Parent = panel

lbl(header, "🚤  BOAT PANEL", UDim2.new(1, -80, 1, 0), UDim2.fromOffset(12, 0), 13, COLOR.accent, Enum.Font.GothamBold)
local minBtn = btn(header, "–", UDim2.fromOffset(28, 28), UDim2.new(1, -66, 0, 6), COLOR.btn, 15)
local closeBtn = btn(header, "✕", UDim2.fromOffset(28, 28), UDim2.new(1, -34, 0, 6), COLOR.btn, 12)
closeBtn.TextColor3 = COLOR.red

local page = Instance.new("ScrollingFrame")
page.Position = UDim2.fromOffset(8, 42)
page.Size = UDim2.new(1, -16, 1, -50)
page.BackgroundTransparency = 1
page.BorderSizePixel = 0
page.ScrollBarThickness = 2
page.ScrollBarImageColor3 = COLOR.accent
page.CanvasSize = UDim2.new()
page.AutomaticCanvasSize = Enum.AutomaticSize.Y
page.Parent = panel
do
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, 8)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = page
end

-- Tarjeta de estado
local status = card(page, 1, 58)
lbl(status, "BARCO", UDim2.new(0.4, 0, 0, 12), UDim2.fromOffset(10, 6), 9, COLOR.sub, Enum.Font.GothamBold)
ui.boatLbl = lbl(status, "Buscando...", UDim2.new(1, -20, 0, 16), UDim2.fromOffset(10, 18), 12, COLOR.cyan, Enum.Font.GothamBold)
ui.statLbl = lbl(status, "", UDim2.new(1, -20, 0, 14), UDim2.fromOffset(10, 38), 10, COLOR.sub, Enum.Font.Gotham)

-- Control con − / valor / + y botón de encendido
local function control(order, title, step, min, max, unitText, getVal, setVal, onToggle)
	local c = card(page, order, 102)
	lbl(c, title, UDim2.new(1, -20, 0, 12), UDim2.fromOffset(10, 6), 9, COLOR.sub, Enum.Font.GothamBold)

	local minus = btn(c, "−", UDim2.fromOffset(42, 30), UDim2.fromOffset(8, 22), COLOR.btn, 18)
	local plus = btn(c, "+", UDim2.fromOffset(42, 30), UDim2.new(1, -50, 0, 22), COLOR.btn, 18)

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, -112, 0, 30)
	box.Position = UDim2.fromOffset(56, 22)
	box.BackgroundColor3 = COLOR.bg
	box.BorderSizePixel = 0
	box.Text = tostring(getVal())
	box.TextColor3 = COLOR.cyan
	box.TextSize = 18
	box.Font = Enum.Font.GothamBlack
	box.ClearTextOnFocus = true
	box.Parent = c
	corner(box, 8)

	local toggle = btn(c, "", UDim2.new(1, -16, 0, 36), UDim2.fromOffset(8, 60), COLOR.btn, 12)

	lbl(c, unitText, UDim2.new(0, 60, 0, 10), UDim2.new(0.5, -30, 0, 52), 8, COLOR.sub, Enum.Font.Gotham).TextXAlignment = Enum.TextXAlignment.Center

	local function apply(v)
		v = math.clamp(math.floor(v + 0.5), min, max)
		setVal(v)
		box.Text = tostring(v)
		save()
	end

	minus.Activated:Connect(function() apply(getVal() - step) end)
	plus.Activated:Connect(function() apply(getVal() + step) end)
	box.FocusLost:Connect(function()
		local n = tonumber(box.Text)
		apply(n or getVal())
	end)
	toggle.Activated:Connect(onToggle)

	return {
		refresh = function(on)
			if not box:IsFocused() then
				box.Text = tostring(getVal())
			end
			toggle.Text = on and "●  ACTIVADO  (tocar = apagar)" or "○  APAGADO  (tocar = activar)"
			toggle.BackgroundColor3 = on and COLOR.green or COLOR.btn
			toggle.TextColor3 = on and COLOR.bg or COLOR.text
		end,
	}
end

local speedCtl, heightCtl

speedCtl = control(2, "VELOCIDAD MÁXIMA", CFG.SPEED_STEP, CFG.SPEED_MIN, CFG.SPEED_MAX, "studs/seg",
	function() return S.speed end,
	function(v)
		S.speed = v
		if S.speedOn and S.boat then applyMaxSpeed(S.boat) end
	end,
	function()
		S.speedOn = not S.speedOn
		if S.speedOn then
			if S.boat then applyMaxSpeed(S.boat) end
		else
			restoreMaxSpeed()
		end
		speedCtl.refresh(S.speedOn)
	end)

heightCtl = control(3, "ALTURA MÁXIMA", CFG.HEIGHT_STEP, CFG.HEIGHT_MIN, CFG.HEIGHT_MAX, "studs sobre el agua",
	function() return S.height end,
	function(v) S.height = v end,
	function()
		S.elevOn = not S.elevOn
		heightCtl.refresh(S.elevOn)
	end)

local resetBtn = btn(page, "↺  Valores por defecto", UDim2.new(1, 0, 0, 32), nil, COLOR.btn, 11)
resetBtn.LayoutOrder = 4
resetBtn.TextColor3 = COLOR.amber

local tip = Instance.new("TextLabel")
tip.Size = UDim2.new(1, 0, 0, 0)
tip.AutomaticSize = Enum.AutomaticSize.Y
tip.BackgroundTransparency = 1
tip.TextColor3 = COLOR.sub
tip.TextSize = 10
tip.Font = Enum.Font.Gotham
tip.TextXAlignment = Enum.TextXAlignment.Left
tip.TextYAlignment = Enum.TextYAlignment.Top
tip.TextWrapped = true
tip.LayoutOrder = 5
tip.Text = "Sube a tu barco para usarlo. La velocidad solo empuja mientras aceleras. Al apagar la altura, el barco baja suave al agua."
tip.Parent = page

-- Burbuja
ui.bubble = Instance.new("TextButton")
ui.bubble.Size = UDim2.fromOffset(CFG.BUBBLE, CFG.BUBBLE)
ui.bubble.BackgroundColor3 = COLOR.accent
ui.bubble.BorderSizePixel = 0
ui.bubble.AutoButtonColor = false
ui.bubble.Text = "🚤"
ui.bubble.TextSize = 22
ui.bubble.Font = Enum.Font.GothamBold
ui.bubble.Visible = false
ui.bubble.ZIndex = 10
ui.bubble.Parent = screen
corner(ui.bubble, CFG.BUBBLE / 2)
stroke(ui.bubble, COLOR.white, 0.4, 1.5)

---------------------------------------------------------------
-- POSICIÓN, ESCALA Y MINIMIZADO
---------------------------------------------------------------
local function layout()
	scale.Scale = fitScale()
	local w = CFG.PANEL_W * scale.Scale
	local h = CFG.PANEL_H * scale.Scale
	local vp = viewport()

	if not S.placed then
		S.placed = true
		local x, y = clampPos((vp.X - w) / 2, vp.Y * 0.1, w, h)
		panel.Position = UDim2.fromOffset(x, y)
		ui.bubble.Position = UDim2.fromOffset(vp.X - CFG.BUBBLE - 12, vp.Y * 0.45)
	else
		local x, y = clampPos(panel.Position.X.Offset, panel.Position.Y.Offset, w, h)
		panel.Position = UDim2.fromOffset(x, y)
	end
end

local function setMinimized(v)
	if v then
		local x, y = clampPos(panel.Position.X.Offset, panel.Position.Y.Offset, CFG.BUBBLE, CFG.BUBBLE)
		ui.bubble.Position = UDim2.fromOffset(x, y)
	else
		local w = CFG.PANEL_W * scale.Scale
		local h = CFG.PANEL_H * scale.Scale
		local x, y = clampPos(ui.bubble.Position.X.Offset, ui.bubble.Position.Y.Offset, w, h)
		panel.Position = UDim2.fromOffset(x, y)
	end
	panel.Visible = not v
	ui.bubble.Visible = v
end

---------------------------------------------------------------
-- EVENTOS
---------------------------------------------------------------
resetBtn.Activated:Connect(function()
	S.speed = CFG.SPEED_DEFAULT
	S.height = CFG.HEIGHT_DEFAULT
	if S.speedOn and S.boat then applyMaxSpeed(S.boat) end
	saveNow()
	speedCtl.refresh(S.speedOn)
	heightCtl.refresh(S.elevOn)
end)

minBtn.Activated:Connect(function() setMinimized(true) end)

local hb
closeBtn.Activated:Connect(function()
	S.closed = true
	S.speedOn = false
	S.elevOn = false
	restoreMaxSpeed()
	if hb then hb:Disconnect() end
	for _, c in ipairs(dragConns) do c:Disconnect() end
	saveNow()
	screen:Destroy()
end)

makeDrag(header, panel, nil, function()
	local w = CFG.PANEL_W * scale.Scale
	local h = CFG.PANEL_H * scale.Scale
	local x, y = clampPos(panel.Position.X.Offset, panel.Position.Y.Offset, w, h)
	panel.Position = UDim2.fromOffset(x, y)
end)

makeDrag(ui.bubble, ui.bubble,
	function() setMinimized(false) end,
	function()
		local x, y = clampPos(ui.bubble.Position.X.Offset, ui.bubble.Position.Y.Offset, CFG.BUBBLE, CFG.BUBBLE)
		ui.bubble.Position = UDim2.fromOffset(x, y)
	end)

---------------------------------------------------------------
-- BUCLES
---------------------------------------------------------------
hb = RunService.Heartbeat:Connect(function(dt)
	if S.closed then return end
	local boat = S.boat
	if boat and not boat.Parent then
		S.boat = nil
		return
	end
	if boat and S.speedOn then
		pcall(speedStep, boat)
	end
	pcall(elevStep, dt)
end)

-- Detección del barco y mantenimiento de MaxSpeed
task.spawn(function()
	while not S.closed do
		local ok = pcall(function()
			local boat, seated = findBoat()
			if boat ~= S.boat then
				restoreMaxSpeed()
				S.boat = boat
			end
			S.seated = seated
			if S.speedOn and S.boat then
				applyMaxSpeed(S.boat)
			end
		end)
		task.wait(0.5)
	end
end)

-- Refresco de la interfaz
task.spawn(function()
	while not S.closed do
		pcall(function()
			if S.boat then
				ui.boatLbl.Text = S.boat.Name .. (S.seated and "  ✔" or "  (cerca)")
				ui.boatLbl.TextColor3 = COLOR.cyan
				local part = mainPart(S.boat)
				local v = part and part.AssemblyLinearVelocity or Vector3.zero
				local spd = math.floor(Vector3.new(v.X, 0, v.Z).Magnitude + 0.5)
				local h = 0
				if E.boat == S.boat then
					h = math.floor(S.boat:GetPivot().Position.Y - E.baseY + 0.5)
				end
				ui.statLbl.Text = "Velocidad: " .. spd .. " · Altura: +" .. h
			else
				ui.boatLbl.Text = "No encuentro tu barco"
				ui.boatLbl.TextColor3 = COLOR.red
				ui.statLbl.Text = "Sube a tu barco o acércate a él"
			end
			speedCtl.refresh(S.speedOn)
			heightCtl.refresh(S.elevOn)
		end)
		task.wait(0.25)
	end
end)

layout()
local cam = Workspace.CurrentCamera
if cam then
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
end
speedCtl.refresh(false)
heightCtl.refresh(false)
