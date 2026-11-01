-- MECHA PANEL v2 · Auto-recolección + retorno a la base (LocalScript móvil)
-- Compacto, minimizable a burbuja. Usa CarryTotal / CarryCapacity del mecha.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

---------------------------------------------------------------
-- CONFIGURACIÓN
---------------------------------------------------------------
local CFG = {
	GUI_NAME = "MechaMobilePanel",
	PANEL_W = 240,
	PANEL_H = 340,
	BUBBLE = 48,
	SPEED_MIN = 10,
	SPEED_MAX = 150,
	SPEED_STEP = 10,
	SPEED_DEFAULT = 40,
	RANGO_RECOGER = 40,      -- studs para activar piezas con ProximityPrompt
	CAP_DEFECTO = 16,        -- capacidad si el mecha no tiene CarryCapacity
	VUELO_VEL = 110,         -- studs por segundo al desplazarse
	ESPERA_PROMPT = 0.2,     -- pausa entre prompts
	COOLDOWN_PROMPT = 1.5,   -- segundos antes de volver a activar el mismo prompt
	ESPERA_DESCARGA = 6,     -- segundos máximos esperando que se vacíe en la base
	ALTURA = 4,              -- studs sobre el punto de destino
	TICK = 0.6,              -- espera entre ciclos si no hay piezas cerca
}

local COLOR = {
	bg = Color3.fromRGB(20, 22, 30),
	card = Color3.fromRGB(30, 33, 44),
	btn = Color3.fromRGB(42, 46, 62),
	accent = Color3.fromRGB(0, 200, 255),
	green = Color3.fromRGB(70, 220, 140),
	amber = Color3.fromRGB(255, 180, 60),
	red = Color3.fromRGB(255, 96, 108),
	cyan = Color3.fromRGB(90, 230, 255),
	text = Color3.fromRGB(238, 240, 246),
	sub = Color3.fromRGB(135, 140, 160),
	white = Color3.fromRGB(255, 255, 255),
	dark = Color3.fromRGB(12, 14, 20),
	track = Color3.fromRGB(44, 48, 64),
}

---------------------------------------------------------------
-- ESTADO
---------------------------------------------------------------
local S = {
	closed = false,
	on = false,
	speed = CFG.SPEED_DEFAULT,
	state = "Parado",
	total = 0,
	cap = CFG.CAP_DEFECTO,
	base = nil,        -- Vector3 guardado con el botón 📍 Base
	zone = nil,        -- Vector3 guardado con el botón 📍 Zona
	placed = false,
	minimized = false,
}

local cooldown = setmetatable({}, { __mode = "k" })
local ui = {}

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

local function row(parent, order, h)
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, 0, 0, h)
	f.BackgroundTransparency = 1
	f.LayoutOrder = order
	f.Parent = parent
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.Padding = UDim.new(0, 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = f
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
	return math.clamp(math.min(vp.X * 0.9 / CFG.PANEL_W, vp.Y * 0.75 / CFG.PANEL_H, 1.1), 0.6, 1.1)
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
-- MECHA Y PERSONAJE
---------------------------------------------------------------
local function hrpNow()
	local char = LocalPlayer.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

-- Prefiere el modelo que tenga CarryCapacity; si no, el que coincida con tu nombre
local function getMech()
	local name = LocalPlayer.Name
	local fallback
	for _, obj in ipairs(Workspace:GetChildren()) do
		if obj:IsA("Model") then
			local owned = obj:GetAttribute("OwnerName") == name or string.find(obj.Name, name, 1, true) ~= nil
			if owned then
				if obj:GetAttribute("CarryCapacity") ~= nil then
					return obj
				end
				fallback = fallback or obj
			end
		end
	end
	return fallback
end

-- Devuelve (total, capacidad) leídos de los atributos del mecha
local function getCarry(mech)
	local total = tonumber(mech:GetAttribute("CarryTotal")) or 0
	local cap = tonumber(mech:GetAttribute("CarryCapacity")) or CFG.CAP_DEFECTO
	return total, cap
end

-- Base: la que guardaste a mano, o workspace.YourBaseMarker
local function getBasePos()
	if S.base then
		return S.base
	end
	local m = Workspace:FindFirstChild("YourBaseMarker")
	if m then
		if m:IsA("BasePart") then return m.Position end
		if m:IsA("Model") then return m:GetPivot().Position end
	end
	return nil
end

local function applySpeed()
	local mech = getMech()
	if not mech then
		return 0, false
	end
	for _, m in ipairs({ mech }) do
		if m:GetAttribute("WalkSpeed") ~= nil then
			m:SetAttribute("WalkSpeed", S.speed)
		end
		if m:GetAttribute("RunSpeed") ~= nil then
			m:SetAttribute("RunSpeed", S.speed + 20)
		end
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("Humanoid") then
				d.WalkSpeed = S.speed
			end
		end
	end
	return 1, true
end

-- Activa los prompts de piezas cercanas. Devuelve cuántos activó, o -1 si el ejecutor no lo soporta
local function recogerCercanas()
	local root = hrpNow()
	if not root or not fireproximityprompt then
		return -1
	end
	local now = os.clock()
	local n = 0
	for _, d in ipairs(Workspace:GetDescendants()) do
		if S.closed or not S.on and S.state ~= "Manual" then
			-- Si se apaga el auto en mitad del ciclo, se corta
		end
		if d:IsA("ProximityPrompt") and d.Enabled and d.Parent and d.Parent:IsA("BasePart") then
			if (d.Parent.Position - root.Position).Magnitude <= CFG.RANGO_RECOGER then
				local last = cooldown[d]
				if not last or now - last >= CFG.COOLDOWN_PROMPT then
					cooldown[d] = now
					pcall(fireproximityprompt, d)
					n = n + 1
					task.wait(CFG.ESPERA_PROMPT)
				end
			end
		end
	end
	return n
end

-- Se desliza hasta el destino (sin teletransporte brusco). Devuelve true si llegó
local function glideTo(target)
	local t0 = os.clock()
	while S.on and not S.closed do
		local root = hrpNow()
		if not root then return false end
		local cur = root.Position
		local delta = target - cur
		local dist = delta.Magnitude
		if dist <= 2 then
			root.AssemblyLinearVelocity = Vector3.zero
			return true
		end
		if os.clock() - t0 > 40 then
			return false
		end
		local dt = RunService.Heartbeat:Wait()
		local step = math.min(dist, CFG.VUELO_VEL * dt)
		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = CFrame.new(cur + delta.Unit * step) * (root.CFrame - root.CFrame.Position)
	end
	return false
end

---------------------------------------------------------------
-- ESTADO EN PANTALLA
---------------------------------------------------------------
local function setState(text, color)
	S.state = text
	if ui.stateLbl then
		ui.stateLbl.Text = text
		ui.stateLbl.TextColor3 = color or COLOR.sub
	end
end

local msgToken = 0
local function setStatus(text, color)
	msgToken += 1
	local my = msgToken
	ui.msgLbl.Text = text
	ui.msgLbl.TextColor3 = color or COLOR.sub
	task.delay(3, function()
		if my == msgToken and ui.msgLbl and ui.msgLbl.Parent then
			ui.msgLbl.Text = ""
		end
	end)
end

local function refreshUI()
	if S.closed or not ui.carryNum then return end

	ui.carryNum.Text = S.total .. " / " .. S.cap
	local r = math.clamp(S.total / math.max(S.cap, 1), 0, 1)
	ui.fill.Size = UDim2.new(r, 0, 1, 0)
	ui.fill.BackgroundColor3 = (r >= 1 and COLOR.red) or (r >= 0.7 and COLOR.amber) or COLOR.green

	ui.speedVal.Text = tostring(S.speed)

	ui.autoBtn.Text = S.on and "■  DETENER AUTO" or "▶  AUTO RECOLECTAR"
	ui.autoBtn.BackgroundColor3 = S.on and COLOR.red or COLOR.green
	ui.bubble.BackgroundColor3 = S.on and COLOR.green or COLOR.accent

	local hasBase = S.base or getBasePos()
	local baseTxt = S.base and "guardada" or (hasBase and "marcador" or "✖")
	ui.infoLbl.Text = "Base: " .. baseTxt .. "   ·   Zona: " .. (S.zone and "✔" or "✖")
end

---------------------------------------------------------------
-- CICLO AUTOMÁTICO: recolecta, y si está lleno vuelve a la base
---------------------------------------------------------------
local function autoStep()
	local mech = getMech()
	if not mech then
		setState("Sin mecha", COLOR.red)
		task.wait(1.5)
		return
	end
	if not hrpNow() then
		setState("Esperando personaje", COLOR.sub)
		task.wait(1)
		return
	end

	local total, cap = getCarry(mech)
	S.total, S.cap = total, cap

	-- LLENO: volver a la base y esperar a que se vacíe
	if total >= cap then
		local base = getBasePos()
		if not base then
			setState("Lleno · guarda tu base", COLOR.red)
			task.wait(2)
			return
		end
		setState("Lleno · vuelvo a base", COLOR.amber)
		if glideTo(base + Vector3.new(0, CFG.ALTURA, 0)) then
			setState("Descargando...", COLOR.amber)
			local t0 = os.clock()
			while S.on and mech.Parent and os.clock() - t0 < CFG.ESPERA_DESCARGA do
				task.wait(0.5)
				total = getCarry(mech)
				S.total = total
				if total < cap then
					break
				end
			end
		end
		return
	end

	-- HAY ESPACIO: recoger lo que esté cerca
	setState("Recolectando", COLOR.green)
	local n = recogerCercanas()
	if n < 0 then
		setState("Sin fireproximityprompt", COLOR.red)
		task.wait(2)
		return
	end
	if n > 0 then
		task.wait(0.2)
		return
	end

	-- Sin piezas a la vista: ir a la zona guardada
	if S.zone and S.on then
		setState("Buscando en zona", COLOR.cyan)
		glideTo(S.zone + Vector3.new(0, CFG.ALTURA, 0))
	end
	task.wait(CFG.TICK)
end

local function setAuto(v)
	S.on = v
	if v then
		setState("Iniciando", COLOR.green)
	else
		setState("Parado", COLOR.sub)
	end
	refreshUI()
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
ui.screen = screen

-- Panel
local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(CFG.PANEL_W, CFG.PANEL_H)
panel.BackgroundColor3 = COLOR.bg
panel.BorderSizePixel = 0
panel.ClipsDescendants = true
panel.Parent = screen
corner(panel, 12)
stroke(panel, COLOR.accent, 0.5, 1)
ui.panel = panel
ui.panelScale = Instance.new("UIScale")
ui.panelScale.Parent = panel

-- Cabecera (zona para arrastrar)
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 38)
header.BackgroundTransparency = 1
header.Active = true
header.Parent = panel

lbl(header, "MECHA PANEL", UDim2.new(1, -80, 1, 0), UDim2.fromOffset(10, 0), 12, COLOR.accent, Enum.Font.GothamBold)
local minBtn = btn(header, "–", UDim2.fromOffset(28, 28), UDim2.new(1, -64, 0, 5), COLOR.btn, 15)
local closeBtn = btn(header, "✕", UDim2.fromOffset(28, 28), UDim2.new(1, -32, 0, 5), COLOR.btn, 12)
closeBtn.TextColor3 = COLOR.red

-- Contenido desplazable
local body = Instance.new("ScrollingFrame")
body.Position = UDim2.fromOffset(8, 42)
body.Size = UDim2.new(1, -16, 1, -50)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ScrollBarThickness = 2
body.ScrollBarImageColor3 = COLOR.accent
body.CanvasSize = UDim2.new()
body.AutomaticCanvasSize = Enum.AutomaticSize.Y
body.Parent = panel

local bodyLayout = Instance.new("UIListLayout")
bodyLayout.Padding = UDim.new(0, 6)
bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
bodyLayout.Parent = body

-- 1) Carga del mecha
local carga = card(body, 1, 64)
lbl(carga, "CARGA", UDim2.new(0.5, 0, 0, 12), UDim2.fromOffset(10, 6), 9, COLOR.sub, Enum.Font.GothamBold)
ui.stateLbl = lbl(carga, "Parado", UDim2.new(0.5, -10, 0, 12), UDim2.new(0.5, 0, 0, 6), 9, COLOR.sub, Enum.Font.GothamBold)
ui.stateLbl.TextXAlignment = Enum.TextXAlignment.Right
ui.carryNum = lbl(carga, "0 / 16", UDim2.new(1, -20, 0, 26), UDim2.fromOffset(10, 18), 20, COLOR.green, Enum.Font.GothamBlack)

local track = Instance.new("Frame")
track.Position = UDim2.fromOffset(10, 50)
track.Size = UDim2.new(1, -20, 0, 6)
track.BackgroundColor3 = COLOR.track
track.BorderSizePixel = 0
track.Parent = carga
corner(track, 3)

ui.fill = Instance.new("Frame")
ui.fill.Size = UDim2.new(0, 0, 1, 0)
ui.fill.BackgroundColor3 = COLOR.green
ui.fill.BorderSizePixel = 0
ui.fill.Parent = track
corner(ui.fill, 3)

-- 2) Velocidad
local spd = card(body, 2, 46)
lbl(spd, "VELOCIDAD", UDim2.new(0.5, 0, 0, 12), UDim2.fromOffset(10, 4), 9, COLOR.sub, Enum.Font.GothamBold)
local minusBtn = btn(spd, "−", UDim2.fromOffset(40, 26), UDim2.fromOffset(8, 16), COLOR.btn, 16)
local plusBtn = btn(spd, "+", UDim2.fromOffset(40, 26), UDim2.new(1, -48, 0, 16), COLOR.btn, 16)
ui.speedVal = lbl(spd, "40", UDim2.new(1, -110, 0, 26), UDim2.fromOffset(55, 16), 16, COLOR.cyan, Enum.Font.GothamBlack)
ui.speedVal.TextXAlignment = Enum.TextXAlignment.Center

-- 3) Botón principal de automatización
ui.autoBtn = btn(body, "▶  AUTO RECOLECTAR", UDim2.new(1, 0, 0, 40), nil, COLOR.green, 13)
ui.autoBtn.LayoutOrder = 3
ui.autoBtn.TextColor3 = COLOR.white

-- 4) Base y zona
local rBases = row(body, 4, 34)
ui.baseBtn = btn(rBases, "📍 Base", UDim2.new(0.5, -3, 1, 0), nil, COLOR.btn, 12)
ui.zoneBtn = btn(rBases, "📍 Zona", UDim2.new(0.5, -3, 1, 0), nil, COLOR.btn, 12)

-- 5) Acciones manuales
local rActs = row(body, 5, 34)
local applyBtn = btn(rActs, "⚡ Velocidad", UDim2.new(0.5, -3, 1, 0), nil, COLOR.btn, 12)
local pickBtn = btn(rActs, "🧲 Recoger", UDim2.new(0.5, -3, 1, 0), nil, COLOR.btn, 12)

-- 6) Estadísticas y limpieza
local rStats = row(body, 6, 30)
local statsBtn = btn(rStats, "📊 Stats", UDim2.new(0.5, -3, 1, 0), nil, COLOR.btn, 12)
local clearBtn = btn(rStats, "↺ Limpiar", UDim2.new(0.5, -3, 1, 0), nil, COLOR.btn, 12)
clearBtn.TextColor3 = COLOR.red

-- Mensajes e información
ui.msgLbl = lbl(body, "", UDim2.new(1, 0, 0, 16), nil, 10, COLOR.sub, Enum.Font.Gotham)
ui.msgLbl.LayoutOrder = 7
ui.msgLbl.TextXAlignment = Enum.TextXAlignment.Center

ui.infoLbl = lbl(body, "", UDim2.new(1, 0, 0, 14), nil, 9, COLOR.sub, Enum.Font.Gotham)
ui.infoLbl.LayoutOrder = 8
ui.infoLbl.TextXAlignment = Enum.TextXAlignment.Center

-- Burbuja (aparece al minimizar)
ui.bubble = Instance.new("TextButton")
ui.bubble.Name = "Bubble"
ui.bubble.Size = UDim2.fromOffset(CFG.BUBBLE, CFG.BUBBLE)
ui.bubble.BackgroundColor3 = COLOR.accent
ui.bubble.BorderSizePixel = 0
ui.bubble.AutoButtonColor = false
ui.bubble.Text = "🤖"
ui.bubble.TextSize = 20
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
	ui.panelScale.Scale = fitScale()
	local w = CFG.PANEL_W * ui.panelScale.Scale
	local h = CFG.PANEL_H * ui.panelScale.Scale
	local vp = viewport()

	if not S.placed then
		S.placed = true
		local x, y = clampPos((vp.X - w) / 2, vp.Y * 0.18, w, h)
		panel.Position = UDim2.fromOffset(x, y)
		ui.bubble.Position = UDim2.fromOffset(vp.X - CFG.BUBBLE - 12, vp.Y * 0.45)
	else
		local x, y = clampPos(panel.Position.X.Offset, panel.Position.Y.Offset, w, h)
		panel.Position = UDim2.fromOffset(x, y)
	end
end

local function setMinimized(v)
	S.minimized = v
	if v then
		local x, y = clampPos(panel.Position.X.Offset, panel.Position.Y.Offset, CFG.BUBBLE, CFG.BUBBLE)
		ui.bubble.Position = UDim2.fromOffset(x, y)
	else
		local w = CFG.PANEL_W * ui.panelScale.Scale
		local h = CFG.PANEL_H * ui.panelScale.Scale
		local x, y = clampPos(ui.bubble.Position.X.Offset, ui.bubble.Position.Y.Offset, w, h)
		panel.Position = UDim2.fromOffset(x, y)
	end
	panel.Visible = not v
	ui.bubble.Visible = v
end

---------------------------------------------------------------
-- EVENTOS
---------------------------------------------------------------
minusBtn.Activated:Connect(function()
	S.speed = math.max(CFG.SPEED_MIN, S.speed - CFG.SPEED_STEP)
	refreshUI()
end)

plusBtn.Activated:Connect(function()
	S.speed = math.min(CFG.SPEED_MAX, S.speed + CFG.SPEED_STEP)
	refreshUI()
end)

ui.autoBtn.Activated:Connect(function()
	setAuto(not S.on)
end)

ui.baseBtn.Activated:Connect(function()
	local root = hrpNow()
	if not root then
		setStatus("❌ Sin personaje", COLOR.red)
		return
	end
	S.base = root.Position
	setStatus("✅ Base guardada aquí", COLOR.green)
	refreshUI()
end)

ui.zoneBtn.Activated:Connect(function()
	local root = hrpNow()
	if not root then
		setStatus("❌ Sin personaje", COLOR.red)
		return
	end
	S.zone = root.Position
	setStatus("✅ Zona guardada aquí", COLOR.green)
	refreshUI()
end)

clearBtn.Activated:Connect(function()
	S.base, S.zone = nil, nil
	setStatus("↺ Base y zona borradas", COLOR.amber)
	refreshUI()
end)

applyBtn.Activated:Connect(function()
	local n, found = applySpeed()
	if found then
		setStatus("✅ Velocidad " .. S.speed .. " aplicada", COLOR.green)
	else
		setStatus("❌ No se encontró tu mecha", COLOR.red)
	end
end)

pickBtn.Activated:Connect(function()
	task.spawn(function()
		local n = recogerCercanas()
		if n < 0 then
			setStatus("❌ Tu ejecutor no tiene fireproximityprompt", COLOR.red)
		else
			setStatus("✅ Piezas activadas: " .. n, COLOR.green)
		end
	end)
end)

statsBtn.Activated:Connect(function()
	local mech = getMech()
	if not mech then
		setStatus("❌ No se encontró tu mecha", COLOR.red)
		return
	end
	local total, cap = getCarry(mech)
	print("--- STATS DE MECHA ---")
	print("Nombre:", mech.Name)
	print("CarryTotal:", total)
	print("CarryCapacity:", cap)
	setStatus("✅ Stats impresos (F9): " .. total .. "/" .. cap, COLOR.green)
end)

minBtn.Activated:Connect(function()
	setMinimized(true)
end)

closeBtn.Activated:Connect(function()
	S.closed = true
	S.on = false
	screen:Destroy()
end)

makeDrag(header, panel, nil, function()
	local w = CFG.PANEL_W * ui.panelScale.Scale
	local h = CFG.PANEL_H * ui.panelScale.Scale
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
-- Ciclo de recolección (solo corre cuando está encendido)
task.spawn(function()
	while not S.closed do
		if S.on then
			local ok, err = pcall(autoStep)
			if not ok then
				setState("Error", COLOR.red)
				warn("[MECHA] " .. tostring(err))
				task.wait(1)
			end
		else
			task.wait(0.2)
		end
	end
end)

-- Refresco de la interfaz
task.spawn(function()
	while not S.closed do
		refreshUI()
		task.wait(0.25)
	end
end)

layout()
local cam = Workspace.CurrentCamera
if cam then
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
end
setState("Parado", COLOR.sub)
refreshUI()
