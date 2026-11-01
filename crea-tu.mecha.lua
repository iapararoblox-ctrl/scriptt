-- MECHA PANEL v3 · Recolección por pilas reales + retorno a la base
-- LocalScript móvil (StarterPlayer > StarterPlayerScripts)

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
	PANEL_W = 250,
	PANEL_H = 440,
	BUBBLE = 48,

	-- Dónde están las pilas: Workspace.World.Arenas.<nivel>.PartPiles.<tipo>
	ARENAS = { "World", "Arenas" },
	LEVELS = {
		"Level1_ScrapYard",
		"Level2_RustyRails",
		"Level3_SkylineHeights",
		"Level4_ToxicBog",
		"Level5_OutpostZero",
		"Level9_KaijuBay",
		"Level10_EmpireCity",
	},
	LEVEL_LABELS = {
		"Scrap Yard", "Rusty Rails", "Skyline Heights", "Toxic Bog",
		"Outpost Zero", "Kaiju Bay", "Empire City",
	},
	PILES = {
		"Chunk", "LightPartPile", "ScrapPartPile", "HeavyPartPile",
		"MediumPartPile", "ColossalPartPile", "TitanPartPile", "BigScrapPartPile",
	},
	PILE_LABELS = {
		"Chunk", "Ligera", "Chatarra", "Pesada",
		"Media", "Colosal", "Titán", "G.Chat",
	},

	VEL_MIN = 20,
	VEL_MAX = 250,
	VEL_STEP = 10,
	VEL_DEFAULT = 90,     -- studs por segundo al desplazarse

	ALTURA = 3,           -- studs sobre la pila o la base
	LLEGADA = 5,          -- distancia para considerar que llegaste
	RANGO_PROMPT = 20,    -- alcance que se da al ProximityPrompt
	ESPERA_CARGA = 1.5,   -- segundos esperando que suba CarryTotal tras activar la pila
	ESPERA_DESCARGA = 25, -- segundos máximos esperando a descargar en la base
	COOLDOWN_OK = 2,      -- segundos sin tocar una pila recogida
	COOLDOWN_FALLO = 6,   -- segundos sin tocar una pila que no dio carga
	REVISAR_MECHA = 2,    -- cada cuántos segundos se vuelve a buscar el mecha
	BASE_MARCADOR = "YourBaseMarker",
}

local PILE_INDEX = {}
for i, n in ipairs(CFG.PILES) do
	PILE_INDEX[n] = i
end

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
	vel = CFG.VEL_DEFAULT,
	levelIdx = 0,                 -- 0 = todos los niveles, 1..7 = un nivel
	pileOn = { true, true, true, true, true, true, true, true },
	mech = nil,
	mechCheck = 0,
	total = 0,
	cap = 16,
	ligero = 0,
	chatarra = 0,
	max = 0,
	base = nil,                   -- Vector3 guardado con el botón 📍 Base
	estado = "Parado",
	placed = false,
	minimized = false,
}

local cooldown = setmetatable({}, { __mode = "k" })
local ui = { piles = {} }

---------------------------------------------------------------
-- HELPERS GENERALES
---------------------------------------------------------------
local function ruta(root, pasos)
	local cur = root
	for _, p in ipairs(pasos) do
		cur = cur and cur:FindFirstChild(p)
		if not cur then return nil end
	end
	return cur
end

local function getParent()
	local ok, h = pcall(function() return gethui and gethui() end)
	if ok and h then return h end
	local ok2, cg = pcall(function() return game:GetService("CoreGui") end)
	if ok2 and cg then return cg end
	return LocalPlayer:WaitForChild("PlayerGui")
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
	return math.clamp(math.min(vp.X * 0.9 / CFG.PANEL_W, vp.Y * 0.78 / CFG.PANEL_H, 1.1), 0.6, 1.1)
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

local function num(v, d)
	return tonumber(v) or d
end

---------------------------------------------------------------
-- MECHA
---------------------------------------------------------------
-- ¿Este modelo es mío? Compara OwnerName/Owner con tu nombre, DisplayName o UserId
local function esMio(m)
	local nombre = LocalPlayer.Name
	local dueño = m:GetAttribute("OwnerName") or m:GetAttribute("Owner")
	if dueño ~= nil then
		local s = tostring(dueño)
		return s == "LocalPlayer" or s == nombre or s == LocalPlayer.DisplayName or s == tostring(LocalPlayer.UserId)
	end
	return string.find(m.Name, nombre, 1, true) ~= nil
end

local function buscarMecha()
	local candidato
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and (d:GetAttribute("MechId") ~= nil or d:GetAttribute("CarryCapacity") ~= nil) then
			if esMio(d) then
				if d:GetAttribute("MechId") ~= nil then
					return d
				end
				candidato = candidato or d
			end
		end
	end
	return candidato
end

local function getMech()
	local ahora = os.clock()
	if S.mech and S.mech.Parent and ahora < S.mechCheck then
		return S.mech
	end
	S.mech = buscarMecha()
	S.mechCheck = ahora + CFG.REVISAR_MECHA
	return S.mech
end

-- Lee la carga del mecha: total, capacidad, ligera, chatarra y máximo
local function leerCarga(m)
	local total = num(m:GetAttribute("CarryTotal"), 0)
	local cap = num(m:GetAttribute("CarryCapacity"), 16)
	local ligero = num(m:GetAttribute("Carry_Light"), 0)
	local chatarra = num(m:GetAttribute("Carry_Scrap"), 0)
	local max = num(m:GetAttribute("CarryMax"), cap)
	return total, cap, ligero, chatarra, max
end

-- Parte que se mueve: el asiento del mecha si estás pilotando, si no tu personaje
local function parteMovil()
	local char = LocalPlayer.Character
	if not char then return nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and hum.SeatPart then
		return hum.SeatPart:GetRootPart() or hum.SeatPart
	end
	return char:FindFirstChild("HumanoidRootPart")
end

local function getBase()
	if S.base then
		return S.base
	end
	local m = Workspace:FindFirstChild(CFG.BASE_MARCADOR)
	if m then
		return posOf(m)
	end
	return nil
end

---------------------------------------------------------------
-- MOVIMIENTO SUAVE
---------------------------------------------------------------
local function glideTo(target, tolerancia)
	local inicio = parteMovil()
	if not inicio then return false end
	local dist0 = (target - inicio.Position).Magnitude
	local limite = os.clock() + math.max(6, dist0 / math.max(S.vel, 1) * 3)

	while S.on and not S.closed do
		local part = parteMovil()
		if not part or not part.Parent then return false end

		local cur = part.Position
		local delta = target - cur
		local dist = delta.Magnitude
		if dist <= tolerancia then
			part.AssemblyLinearVelocity = Vector3.zero
			return true
		end
		if os.clock() > limite then return false end

		local dt = RunService.Heartbeat:Wait()
		local paso = math.min(dist, S.vel * dt)
		part.AssemblyLinearVelocity = Vector3.zero
		part.CFrame = CFrame.new(cur + delta.Unit * paso) * (part.CFrame - part.CFrame.Position)
	end
	return false
end

---------------------------------------------------------------
-- PILAS (solo dentro de PartPiles)
---------------------------------------------------------------
-- Devuelve la lista de pilas disponibles (más cercana primero) y si existe World.Arenas
local function listarPilas()
	local lista = {}
	local arenas = ruta(Workspace, CFG.ARENAS)
	if not arenas then
		return lista, false
	end

	local origen = parteMovil()
	local origenPos = origen and origen.Position or Vector3.zero
	local ahora = os.clock()

	for li, nombreNivel in ipairs(CFG.LEVELS) do
		if S.levelIdx == 0 or S.levelIdx == li then
			local nivel = arenas:FindFirstChild(nombreNivel)
			local piles = nivel and nivel:FindFirstChild("PartPiles")
			if piles then
				for _, pile in ipairs(piles:GetChildren()) do
					local ti = PILE_INDEX[pile.Name]
					if ti and S.pileOn[ti] then
						local prompt = pile:FindFirstChildWhichIsA("ProximityPrompt", true)
						local pos = posOf(pile)
						if prompt and prompt.Enabled and pos and (not cooldown[prompt] or cooldown[prompt] <= ahora) then
							table.insert(lista, {
								prompt = prompt,
								pos = pos,
								nombre = CFG.PILE_LABELS[ti],
								dist = (pos - origenPos).Magnitude,
							})
						end
					end
				end
			end
		end
	end

	table.sort(lista, function(a, b) return a.dist < b.dist end)
	return lista, true
end

local function activarPrompt(prompt)
	pcall(function()
		prompt.RequiresLineOfSight = false
		if prompt.MaxActivationDistance < CFG.RANGO_PROMPT then
			prompt.MaxActivationDistance = CFG.RANGO_PROMPT
		end
	end)
	if fireproximityprompt then
		pcall(fireproximityprompt, prompt)
		return true
	end
	return false
end

-- Va a la pila, la activa y espera a que suba CarryTotal. Devuelve ok, motivo
local function recolectar(p, mech)
	if not glideTo(p.pos + Vector3.new(0, CFG.ALTURA, 0), CFG.LLEGADA) then
		return false, "no llegué"
	end
	if not S.on then
		return false, "parado"
	end
	if not activarPrompt(p.prompt) then
		return false, "sin fireproximityprompt"
	end

	local antes = leerCarga(mech)
	local t0 = os.clock()
	while S.on and os.clock() - t0 < CFG.ESPERA_CARGA do
		task.wait(0.1)
		if not p.prompt.Parent then
			return true -- la pila desapareció: se recogió
		end
		if leerCarga(mech) > antes then
			cooldown[p.prompt] = os.clock() + CFG.COOLDOWN_OK
			return true
		end
	end

	cooldown[p.prompt] = os.clock() + CFG.COOLDOWN_FALLO
	return false, "la carga no subió"
end

---------------------------------------------------------------
-- ESTADO EN PANTALLA
---------------------------------------------------------------
local function setEstado(texto, color)
	S.estado = texto
	if ui.estado then
		ui.estado.Text = texto
		ui.estado.TextColor3 = color or COLOR.sub
	end
end

local msgId = 0
local function setMsg(texto, color)
	msgId += 1
	local my = msgId
	if ui.msg then
		ui.msg.Text = texto
		ui.msg.TextColor3 = color or COLOR.sub
	end
	task.delay(3, function()
		if my == msgId and ui.msg and ui.msg.Parent then
			ui.msg.Text = ""
		end
	end)
end

local function refreshUI()
	if S.closed or not ui.carry then return end

	ui.carry.Text = S.total .. " / " .. S.cap
	local r = math.clamp(S.total / math.max(S.cap, 1), 0, 1)
	ui.fill.Size = UDim2.new(r, 0, 1, 0)
	ui.fill.BackgroundColor3 = (r >= 1 and COLOR.red) or (r >= 0.7 and COLOR.amber) or COLOR.green

	ui.sub.Text = "Ligera " .. S.ligero .. "  ·  Chatarra " .. S.chatarra .. "  ·  Máx " .. S.max

	ui.auto.Text = S.on and "■  DETENER" or "▶  AUTO RECOLECTAR"
	ui.auto.BackgroundColor3 = S.on and COLOR.red or COLOR.green
	ui.bubble.BackgroundColor3 = S.on and COLOR.green or COLOR.accent

	ui.level.Text = (S.levelIdx == 0) and "Todos los niveles" or CFG.LEVEL_LABELS[S.levelIdx]

	for i, b in ipairs(ui.piles) do
		b.BackgroundColor3 = S.pileOn[i] and COLOR.accent or COLOR.btn
		b.TextColor3 = S.pileOn[i] and COLOR.dark or COLOR.text
	end

	ui.vel.Text = tostring(S.vel)

	local mech = S.mech
	if mech then
		local id = tostring(mech:GetAttribute("MechId") or mech.Name)
		local pilot = tostring(mech:GetAttribute("PilotMode") or "—")
		ui.mech.Text = id .. "  ·  " .. pilot
	else
		ui.mech.Text = "Sin mecha detectado"
	end

	local tieneBase = S.base ~= nil or getBase() ~= nil
	ui.base.Text = "Base: " .. (S.base and "guardada aquí" or (tieneBase and "marcador del mapa" or "✖ sin base"))
end

---------------------------------------------------------------
-- CICLO AUTOMÁTICO
---------------------------------------------------------------
local function autoStep()
	local mech = getMech()
	if not mech then
		setEstado("Sin mecha", COLOR.red)
		task.wait(1.5)
		return
	end
	if not parteMovil() then
		setEstado("Esperando personaje", COLOR.sub)
		task.wait(1)
		return
	end

	local total, cap, lig, chat, max = leerCarga(mech)
	S.total, S.cap, S.ligero, S.chatarra, S.max = total, cap, lig, chat, max

	-- LLENO: volver a la base y esperar a que baje la carga
	if total >= cap then
		local base = getBase()
		if not base then
			setEstado("Lleno · guarda tu base", COLOR.red)
			task.wait(2)
			return
		end
		setEstado("Lleno · vuelvo a la base", COLOR.amber)
		if glideTo(base + Vector3.new(0, CFG.ALTURA, 0), CFG.LLEGADA) then
			setEstado("Descargando...", COLOR.amber)
			local t0 = os.clock()
			while S.on and os.clock() - t0 < CFG.ESPERA_DESCARGA do
				task.wait(0.5)
				if leerCarga(mech) < cap then
					break
				end
			end
		end
		return
	end

	-- HAY ESPACIO: ir a la pila más cercana de las seleccionadas
	local lista, existe = listarPilas()
	if not existe then
		setEstado("No encuentro World.Arenas", COLOR.red)
		task.wait(2)
		return
	end

	local p = lista[1]
	if not p then
		setEstado("Sin pilas en la selección", COLOR.cyan)
		task.wait(1.5)
		return
	end

	setEstado("Yendo a " .. p.nombre, COLOR.green)
	local ok, motivo = recolectar(p, mech)
	if ok then
		setMsg("✅ " .. p.nombre .. " recogida", COLOR.green)
	elseif motivo == "parado" then
		setEstado("Parado", COLOR.sub)
	else
		setMsg("⚠ " .. p.nombre .. ": " .. tostring(motivo), COLOR.amber)
	end
end

local function setAuto(v)
	S.on = v
	setEstado(v and "Iniciando" or "Parado", v and COLOR.green or COLOR.sub)
	refreshUI()
end

---------------------------------------------------------------
-- INTERFAZ (todo con Instance.new)
---------------------------------------------------------------
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

local function hRow(parent, order, h)
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

-- Ventana
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

-- 1) Carga
local carga = card(body, 1, 66)
lbl(carga, "CARGA", UDim2.new(0.5, 0, 0, 12), UDim2.fromOffset(10, 6), 9, COLOR.sub, Enum.Font.GothamBold)
ui.estado = lbl(carga, "Parado", UDim2.new(0.5, -10, 0, 12), UDim2.new(0.5, 0, 0, 6), 9, COLOR.sub, Enum.Font.GothamBold)
ui.estado.TextXAlignment = Enum.TextXAlignment.Right

ui.carry = lbl(carga, "0 / 16", UDim2.new(1, -20, 0, 24), UDim2.fromOffset(10, 18), 19, COLOR.green, Enum.Font.GothamBlack)

local track = Instance.new("Frame")
track.Position = UDim2.fromOffset(10, 45)
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

ui.sub = lbl(carga, "", UDim2.new(1, -20, 0, 12), UDim2.fromOffset(10, 52), 9, COLOR.sub, Enum.Font.Gotham)

-- 2) Botón principal
ui.auto = btn(body, "▶  AUTO RECOLECTAR", UDim2.new(1, 0, 0, 40), nil, COLOR.green, 13)
ui.auto.LayoutOrder = 2
ui.auto.TextColor3 = COLOR.white
ui.auto.Activated:Connect(function()
	setAuto(not S.on)
end)

-- 3) Nivel (◀ nivel ▶)
local nivelTitulo = lbl(body, "NIVEL", UDim2.new(1, 0, 0, 14), nil, 9, COLOR.sub, Enum.Font.GothamBold)
nivelTitulo.LayoutOrder = 3

local nivelRow = hRow(body, 4, 34)
local prevBtn = btn(nivelRow, "◀", UDim2.fromOffset(40, 34), nil, COLOR.btn, 14)
prevBtn.LayoutOrder = 1
ui.level = btn(nivelRow, "", UDim2.new(1, -88, 1, 0), nil, COLOR.card, 12)
ui.level.LayoutOrder = 2
local nextBtn = btn(nivelRow, "▶", UDim2.fromOffset(40, 34), nil, COLOR.btn, 14)
nextBtn.LayoutOrder = 3

prevBtn.Activated:Connect(function()
	S.levelIdx = S.levelIdx - 1
	if S.levelIdx < 0 then S.levelIdx = #CFG.LEVELS end
	refreshUI()
end)
nextBtn.Activated:Connect(function()
	S.levelIdx = S.levelIdx + 1
	if S.levelIdx > #CFG.LEVELS then S.levelIdx = 0 end
	refreshUI()
end)
ui.level.Activated:Connect(function()
	S.levelIdx = (S.levelIdx + 1) % (#CFG.LEVELS + 1)
	refreshUI()
end)

-- 4) Tipos de pila (cuadrícula 4 x 2)
local pilasTitulo = lbl(body, "PILAS A RECOGER", UDim2.new(1, 0, 0, 14), nil, 9, COLOR.sub, Enum.Font.GothamBold)
pilasTitulo.LayoutOrder = 5

local grid = Instance.new("Frame")
grid.Size = UDim2.new(1, 0, 0, 58)
grid.BackgroundTransparency = 1
grid.LayoutOrder = 6
grid.Parent = body
local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.fromOffset(54, 26)
gridLayout.CellPadding = UDim2.fromOffset(4, 4)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = grid

for i, nombre in ipairs(CFG.PILE_LABELS) do
	local b = btn(grid, nombre, UDim2.fromOffset(54, 26), nil, COLOR.accent, 9)
	b.LayoutOrder = i
	b.Activated:Connect(function()
		S.pileOn[i] = not S.pileOn[i]
		refreshUI()
	end)
	ui.piles[i] = b
end

-- 5) Velocidad de desplazamiento
local velCard = card(body, 7, 38)
lbl(velCard, "Vuelo", UDim2.new(0, 60, 1, 0), UDim2.fromOffset(10, 0), 11, COLOR.sub, Enum.Font.GothamBold)
local velMinus = btn(velCard, "−", UDim2.fromOffset(36, 28), UDim2.new(1, -116, 0.5, -14), COLOR.btn, 16)
ui.vel = lbl(velCard, "", UDim2.fromOffset(44, 28), UDim2.new(1, -78, 0.5, -14), 14, COLOR.cyan, Enum.Font.GothamBlack)
ui.vel.TextXAlignment = Enum.TextXAlignment.Center
local velPlus = btn(velCard, "+", UDim2.fromOffset(36, 28), UDim2.new(1, -40, 0.5, -14), COLOR.btn, 16)

velMinus.Activated:Connect(function()
	S.vel = math.max(CFG.VEL_MIN, S.vel - CFG.VEL_STEP)
	refreshUI()
end)
velPlus.Activated:Connect(function()
	S.vel = math.min(CFG.VEL_MAX, S.vel + CFG.VEL_STEP)
	refreshUI()
end)

-- 6) Base y acciones
local acciones = hRow(body, 8, 30)
local baseBtn = btn(acciones, "📍 Guardar base", UDim2.new(0.5, -3, 1, 0), nil, COLOR.btn, 11)
baseBtn.LayoutOrder = 1
local limpiarBtn = btn(acciones, "↺ Borrar base", UDim2.new(0.5, -3, 1, 0), nil, COLOR.btn, 11)
limpiarBtn.LayoutOrder = 2
limpiarBtn.TextColor3 = COLOR.red

baseBtn.Activated:Connect(function()
	local part = parteMovil()
	if not part then
		setMsg("❌ Sin personaje", COLOR.red)
		return
	end
	S.base = part.Position
	setMsg("✅ Base guardada aquí", COLOR.green)
	refreshUI()
end)

limpiarBtn.Activated:Connect(function()
	S.base = nil
	setMsg("↺ Base borrada", COLOR.amber)
	refreshUI()
end)

local statsBtn = btn(body, "📊 Ver stats del mecha (F9)", UDim2.new(1, 0, 0, 28), nil, COLOR.btn, 11)
statsBtn.LayoutOrder = 9
statsBtn.Activated:Connect(function()
	local mech = getMech()
	if not mech then
		setMsg("❌ No encuentro tu mecha", COLOR.red)
		return
	end
	print("--- STATS DE MECHA ---")
	print("Nombre:", mech.Name)
	print("MechId:", mech:GetAttribute("MechId"))
	print("PilotMode:", mech:GetAttribute("PilotMode"))
	print("CarryTotal:", mech:GetAttribute("CarryTotal"))
	print("CarryCapacity:", mech:GetAttribute("CarryCapacity"))
	print("CarryMax:", mech:GetAttribute("CarryMax"))
	print("Carry_Light:", mech:GetAttribute("Carry_Light"))
	print("Carry_Scrap:", mech:GetAttribute("Carry_Scrap"))
	setMsg("✅ Stats impresos en F9", COLOR.green)
end)

-- 7) Información y mensajes
ui.base = lbl(body, "", UDim2.new(1, 0, 0, 14), nil, 9, COLOR.sub, Enum.Font.Gotham)
ui.base.LayoutOrder = 10
ui.base.TextXAlignment = Enum.TextXAlignment.Center

ui.mech = lbl(body, "", UDim2.new(1, 0, 0, 14), nil, 9, COLOR.sub, Enum.Font.Gotham)
ui.mech.LayoutOrder = 11
ui.mech.TextXAlignment = Enum.TextXAlignment.Center

ui.msg = lbl(body, "", UDim2.new(1, 0, 0, 16), nil, 10, COLOR.sub, Enum.Font.Gotham)
ui.msg.LayoutOrder = 12
ui.msg.TextXAlignment = Enum.TextXAlignment.Center

-- Burbuja
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
		local x, y = clampPos((vp.X - w) / 2, vp.Y * 0.14, w, h)
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
				setEstado("Error", COLOR.red)
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
		getMech()
		refreshUI()
		task.wait(0.25)
	end
end)

layout()
local cam = Workspace.CurrentCamera
if cam then
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
end
setEstado("Parado", COLOR.sub)
refreshUI()
