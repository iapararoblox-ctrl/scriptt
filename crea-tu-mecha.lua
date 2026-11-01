-- MECHA PANEL v3 · Auto-recolección por arenas + retorno a la base (LocalScript móvil)
-- Piezas: Workspace.World.Arenas.<Nivel>.PartPiles
-- Mecha: modelo en Workspace con tu OwnerName/Owner. Carga: CarryTotal / CarryCapacity / CarryMax.

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
	PANEL_H = 360,
	BUBBLE = 48,

	SPEED_MIN = 10,
	SPEED_MAX = 150,
	SPEED_STEP = 10,
	SPEED_DEFAULT = 40,

	CAP_DEFECTO = 16,        -- límite si el mecha no tiene CarryCapacity ni CarryMax
	VUELO_VEL = 110,         -- studs por segundo al deslizarse
	MAX_VUELO = 60,          -- segundos máximos por trayecto
	ALTURA = 4,              -- studs sobre el punto de destino
	RANGO_RECOGER = 40,      -- studs para el botón manual 🧲 Recoger

	ESPERA_PROMPT = 0.25,    -- pausa entre intentos de recoger una pila
	SIN_PROGRESO = 3,        -- segundos sin que suba la carga para dar por terminada una pila
	TIMEOUT_PILA = 12,       -- máximo de segundos por pila
	BLOQUEO = 30,            -- segundos que se ignora una pila que no se pudo recoger
	FALLOS_LLENO = 3,        -- pilas seguidas sin recoger (con carga encima) = se considera lleno
	ESPERA_DESCARGA = 8,     -- segundos máximos esperando que se vacíe en la base
	RESCAN = 2,              -- segundos entre escaneos de PartPiles
	TICK = 0.6,              -- espera entre ciclos si no hay piezas
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
	track = Color3.fromRGB(44, 48, 64),
}

-- Tipos de pieza dentro de PartPiles
local TYPES = {
	{ key = "Chunk", es = "Trozo" },
	{ key = "LightPartPile", es = "Pila ligera" },
	{ key = "ScrapPartPile", es = "Pila de chatarra" },
	{ key = "HeavyPartPile", es = "Pila pesada" },
	{ key = "MediumPartPile", es = "Pila media" },
	{ key = "ColossalPartPile", es = "Pila colosal" },
	{ key = "TitanPartPile", es = "Pila titán" },
	{ key = "BigScrapPartPile", es = "Pila de chatarra grande" },
}

-- Áreas conocidas (se usan solo si no se puede leer Workspace.World.Arenas)
local STATIC_AREAS = {
	"Level1_ScrapYard",
	"Level2_RustyRails",
	"Level3_SkylineHeights",
	"Level4_ToxicBog",
	"Level5_OutpostZero",
	"Level9_KaijuBay",
	"Level10_EmpireCity",
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
	limit = CFG.CAP_DEFECTO,
	base = nil,            -- Vector3 guardado con 📍 Base
	zone = nil,            -- Vector3 guardado con 📍 Zona (se va ahí si no hay piezas cargadas)
	placed = false,
	minimized = false,

	areaName = "*ALL",     -- "*ALL" o el nombre de la carpeta del nivel
	types = {},            -- tipo -> true/false
	limitMode = "MAX",     -- "MAX" = CarryMax, "CAP" = CarryCapacity
	moveMode = "GLIDE",    -- "GLIDE" = deslizar, "TP" = teletransporte

	mech = nil,
	mechTime = -100,
	deepTime = -100,

	pileCache = nil,
	pileTime = -100,
	pileDirty = true,
	black = setmetatable({}, { __mode = "k" }),  -- pila -> hora hasta la que se ignora

	collected = 0,
	fails = 0,
}
for _, t in ipairs(TYPES) do
	S.types[t.key] = true
end

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

-- Texto largo que crece hacia abajo
local function note(parent, order, textSize)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.BackgroundTransparency = 1
	l.Text = ""
	l.TextColor3 = COLOR.sub
	l.TextSize = textSize or 10
	l.Font = Enum.Font.Gotham
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.TextWrapped = true
	l.LayoutOrder = order
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

local function toggleRow(parent, order, text, initial, onChange)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 30)
	b.BackgroundColor3 = COLOR.card
	b.BorderSizePixel = 0
	b.Text = ""
	b.AutoButtonColor = false
	b.LayoutOrder = order
	b.Parent = parent
	corner(b, 8)

	lbl(b, text, UDim2.new(1, -44, 1, 0), UDim2.fromOffset(10, 0), 12, COLOR.text)

	local box = Instance.new("Frame")
	box.Size = UDim2.fromOffset(18, 18)
	box.Position = UDim2.new(1, -28, 0.5, -9)
	box.BorderSizePixel = 0
	box.Parent = b
	corner(box, 5)

	local tick = lbl(box, "✓", UDim2.new(1, 0, 1, 0), nil, 13, COLOR.white, Enum.Font.GothamBold)
	tick.TextXAlignment = Enum.TextXAlignment.Center

	local state = initial
	local function paint()
		box.BackgroundColor3 = state and COLOR.green or COLOR.track
		tick.Visible = state
	end
	b.Activated:Connect(function()
		state = not state
		paint()
		onChange(state)
	end)
	paint()

	return {
		set = function(v)
			state = v
			paint()
		end,
	}
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
-- MECHA ACTIVO (modelo en Workspace con tu OwnerName / Owner)
---------------------------------------------------------------
local function hrpNow()
	local char = LocalPlayer.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

-- ¿El modelo es tuyo? Atributos OwnerName/Owner o nombre tipo MechId_Jugador_N
local function ownedBy(m)
	local name = LocalPlayer.Name
	local display = LocalPlayer.DisplayName
	local uid = tostring(LocalPlayer.UserId)

	local function eq(v)
		if v == nil then return false end
		local s = tostring(v)
		return s == name or s == display or s == uid or s == "LocalPlayer"
	end

	for _, key in ipairs({ "OwnerName", "Owner", "OwnerId", "UserId" }) do
		if eq(m:GetAttribute(key)) then
			return true
		end
	end

	local n = m.Name
	if string.find(n, "_" .. name .. "_", 1, true) or string.find(n, "_LocalPlayer_", 1, true) then
		return true
	end
	return false
end

local function scoreMech(m)
	local s = 0
	if m:GetAttribute("CarryCapacity") ~= nil or m:GetAttribute("CarryMax") ~= nil or m:GetAttribute("CarryTotal") ~= nil then
		s += 4
	end
	if m:GetAttribute("MechId") ~= nil then
		s += 2
	end
	if m:GetAttribute("PilotMode") == "Seat" then
		s += 2
	end
	local pilot = m:GetAttribute("Pilot")
	if pilot ~= nil and pilot ~= "" and pilot ~= false then
		s += 3
	end
	return s
end

local function findMech()
	local best, bestScore
	local function consider(m)
		if m:IsA("Model") and ownedBy(m) then
			local sc = scoreMech(m)
			if sc > 0 and (not bestScore or sc > bestScore) then
				best, bestScore = m, sc
			end
		end
	end

	for _, o in ipairs(Workspace:GetChildren()) do
		consider(o)
	end

	-- Respaldo (cada 5 s): por si el mecha está dentro de otra carpeta
	if not best and os.clock() - S.deepTime > 5 then
		S.deepTime = os.clock()
		for _, o in ipairs(Workspace:GetDescendants()) do
			if o:IsA("Model") and o:GetAttribute("MechId") ~= nil then
				consider(o)
			end
		end
	end
	return best
end

local function getMech()
	local now = os.clock()
	if S.mech and S.mech.Parent and now - S.mechTime < 2 then
		return S.mech
	end
	S.mech = findMech()
	S.mechTime = now
	return S.mech
end

-- Devuelve total, límite activo, CarryCapacity, CarryMax
local function getCarry(mech)
	local total = tonumber(mech:GetAttribute("CarryTotal")) or 0
	local cap = tonumber(mech:GetAttribute("CarryCapacity"))
	local max = tonumber(mech:GetAttribute("CarryMax"))
	local limit
	if S.limitMode == "MAX" then
		limit = max or cap or CFG.CAP_DEFECTO
	else
		limit = cap or max or CFG.CAP_DEFECTO
	end
	return total, limit, cap, max
end

-- ¿Estás pilotando el mecha?
local function pilotActive(mech)
	local p = mech:GetAttribute("Pilot")
	if p ~= nil then
		return p ~= "" and p ~= false and p ~= 0
	end
	local char = LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.SeatPart and hum.SeatPart:IsDescendantOf(mech) then
		return true
	end
	return mech:GetAttribute("PilotMode") == "Seat"
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
		return false
	end
	if mech:GetAttribute("WalkSpeed") ~= nil then
		mech:SetAttribute("WalkSpeed", S.speed)
	end
	if mech:GetAttribute("RunSpeed") ~= nil then
		mech:SetAttribute("RunSpeed", S.speed + 20)
	end
	for _, d in ipairs(mech:GetDescendants()) do
		if d:IsA("Humanoid") then
			d.WalkSpeed = S.speed
		end
	end
	return true
end

---------------------------------------------------------------
-- MOVIMIENTO (mueve el mecha si lo pilotas; si no, tu personaje)
---------------------------------------------------------------
local function currentPos(mech)
	if pilotActive(mech) then
		return mech:GetPivot().Position
	end
	local r = hrpNow()
	return r and r.Position
end

local function placeAt(mech, pos)
	if pilotActive(mech) then
		local cf = mech:GetPivot()
		mech:PivotTo(CFrame.new(pos) * (cf - cf.Position))
		local pp = mech.PrimaryPart or mech:FindFirstChildWhichIsA("BasePart", true)
		if pp then
			pp.AssemblyLinearVelocity = Vector3.zero
			pp.AssemblyAngularVelocity = Vector3.zero
		end
	else
		local root = hrpNow()
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
			root.CFrame = CFrame.new(pos) * (root.CFrame - root.CFrame.Position)
		end
	end
end

-- Va hasta "target". Devuelve true si llegó
local function moveTo(mech, target)
	if S.moveMode == "TP" then
		placeAt(mech, target)
		task.wait(0.15)
		return true
	end

	local first = currentPos(mech)
	if not first then return false end
	local timeout = math.clamp((target - first).Magnitude / CFG.VUELO_VEL * 1.5 + 5, 10, CFG.MAX_VUELO)
	local t0 = os.clock()

	while S.on and not S.closed and mech.Parent do
		local cur = currentPos(mech)
		if not cur then return false end
		local delta = target - cur
		local dist = delta.Magnitude
		if dist <= 2 then
			placeAt(mech, target)
			return true
		end
		if os.clock() - t0 > timeout then
			return false
		end
		local dt = RunService.Heartbeat:Wait()
		placeAt(mech, cur + delta.Unit * math.min(dist, CFG.VUELO_VEL * dt))
	end
	return false
end

---------------------------------------------------------------
-- PIEZAS: Workspace.World.Arenas.<Nivel>.PartPiles
---------------------------------------------------------------
local function getArenas()
	local world = Workspace:FindFirstChild("World")
	return world and world:FindFirstChild("Arenas")
end

local function splitCamel(s)
	return (s:gsub("(%l)(%u)", "%1 %2"))
end

-- Lista de áreas para el selector: "Todas" + las que existan en Arenas
local function buildAreaOptions()
	local opts = { { name = "*ALL", label = "Todas las áreas" } }
	local found = {}

	local function add(folderName)
		local n, rest = folderName:match("^Level(%d+)_(.+)$")
		if n then
			table.insert(found, { name = folderName, num = tonumber(n), label = "Nivel " .. n .. ": " .. splitCamel(rest) })
		end
	end

	local arenas = getArenas()
	if arenas then
		for _, a in ipairs(arenas:GetChildren()) do
			add(a.Name)
		end
	end
	if #found == 0 then
		for _, name in ipairs(STATIC_AREAS) do
			add(name)
		end
	end

	table.sort(found, function(a, b) return a.num < b.num end)
	for _, f in ipairs(found) do
		table.insert(opts, f)
	end
	return opts
end

local function areaLabel()
	if S.areaName == "*ALL" then
		return "Todas las áreas"
	end
	for _, o in ipairs(buildAreaOptions()) do
		if o.name == S.areaName then
			return o.label
		end
	end
	return S.areaName
end

local function typeLabel(key)
	for _, t in ipairs(TYPES) do
		if t.key == key then
			return t.es
		end
	end
	return key
end

-- Tipo de pieza según el nombre (acepta sufijos, p. ej. LightPartPile_12)
local function typeOf(name)
	for _, t in ipairs(TYPES) do
		if name == t.key or name:sub(1, #t.key) == t.key then
			return t.key
		end
	end
	return nil
end

-- Piezas recolectables dentro de un PartPiles. Cada una: { inst, kind, area }
local function collectCandidates(partPiles, areaName)
	local isCand = {}
	local descendants = partPiles:GetDescendants()

	for _, d in ipairs(descendants) do
		if d:IsA("Model") or d:IsA("BasePart") then
			local k = typeOf(d.Name)
			if k then
				isCand[d] = k
			end
		end
	end
	-- Carpetas con el nombre del tipo: sus hijos son las piezas
	for _, d in ipairs(descendants) do
		if d:IsA("Folder") then
			local k = typeOf(d.Name)
			if k then
				for _, c in ipairs(d:GetChildren()) do
					if (c:IsA("Model") or c:IsA("BasePart")) and not typeOf(c.Name) then
						isCand[c] = k
					end
				end
			end
		end
	end

	local list = {}
	for inst, k in pairs(isCand) do
		-- Si está dentro de otra pieza, solo cuenta la de fuera
		local nested = false
		local p = inst.Parent
		while p and p ~= partPiles do
			if isCand[p] then
				nested = true
				break
			end
			p = p.Parent
		end
		if not nested then
			table.insert(list, { inst = inst, kind = k, area = areaName })
		end
	end
	return list
end

-- Piezas cargadas ahora en el área elegida (se cachea unos segundos)
local function getPiles()
	local now = os.clock()
	if S.pileCache and not S.pileDirty and now - S.pileTime < CFG.RESCAN then
		return S.pileCache
	end

	local list = {}
	local arenas = getArenas()
	if arenas then
		for _, area in ipairs(arenas:GetChildren()) do
			if S.areaName == "*ALL" or area.Name == S.areaName then
				local pp = area:FindFirstChild("PartPiles", true)
				if pp then
					for _, e in ipairs(collectCandidates(pp, area.Name)) do
						table.insert(list, e)
					end
				end
			end
		end
	end

	S.pileCache = list
	S.pileTime = now
	S.pileDirty = false
	return list
end

local function pileAlive(inst)
	return inst ~= nil and inst.Parent ~= nil and inst:IsDescendantOf(Workspace)
end

local function pilePos(inst)
	if inst:IsA("Model") then
		return inst:GetPivot().Position
	elseif inst:IsA("BasePart") then
		return inst.Position
	end
	return nil
end

local function promptsOf(inst)
	local list = {}
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			table.insert(list, d)
		end
	end
	return list
end

local function firstPart(inst)
	if inst:IsA("BasePart") then
		return inst
	end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end

-- Intenta recoger una pieza: prompts y, si no tiene, contacto. Devuelve true si intentó algo
local function triggerPile(inst)
	local fired = false
	if fireproximityprompt then
		for _, p in ipairs(promptsOf(inst)) do
			if p.Enabled then
				pcall(function()
					p.HoldDuration = 0
					p.RequiresLineOfSight = false
					if p.MaxActivationDistance < 30 then
						p.MaxActivationDistance = 30
					end
				end)
				pcall(fireproximityprompt, p)
				fired = true
			end
		end
	end
	if fired then
		return true
	end

	if firetouchinterest then
		local part = firstPart(inst)
		local root = hrpNow()
		if part and root then
			pcall(firetouchinterest, root, part, 0)
			pcall(firetouchinterest, root, part, 1)
			return true
		end
	end
	return false
end

-- Pieza válida más cercana (según área, tipos activos y bloqueos)
local function nextPile(origin)
	local now = os.clock()
	local best, bestDist
	for _, e in ipairs(getPiles()) do
		local expiry = S.black[e.inst]
		local blocked = expiry ~= nil and expiry > now
		if S.types[e.kind] and not blocked and pileAlive(e.inst) then
			local p = pilePos(e.inst)
			if p then
				local d = (p - origin).Magnitude
				if not bestDist or d < bestDist then
					best, bestDist = e, d
				end
			end
		end
	end
	return best
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

local function carryBreakdown(mech)
	local items = {}
	for k, v in pairs(mech:GetAttributes()) do
		if k:sub(1, 6) == "Carry_" then
			table.insert(items, { k = k:sub(7), v = v })
		end
	end
	table.sort(items, function(a, b) return a.k < b.k end)
	local parts = {}
	for _, it in ipairs(items) do
		table.insert(parts, it.k .. " " .. tostring(it.v))
	end
	return table.concat(parts, " · ")
end

local function refreshMechInfo()
	if not ui.mechNote then return end
	local mech = getMech()
	if not mech then
		ui.mechNote.Text = "No encuentro tu mecha. Debe ser un modelo en Workspace con tu OwnerName/Owner y atributos Carry*."
		return
	end
	local total, limit, cap, max = getCarry(mech)
	local lines = {}
	table.insert(lines, "Mecha: " .. mech.Name)
	table.insert(lines, "MechId: " .. tostring(mech:GetAttribute("MechId"))
		.. " · Piloto: " .. (pilotActive(mech) and "sí" or "no")
		.. " (PilotMode=" .. tostring(mech:GetAttribute("PilotMode")) .. ")")
	table.insert(lines, "Carga: " .. total .. " · CarryCapacity: " .. tostring(cap) .. " · CarryMax: " .. tostring(max))
	local br = carryBreakdown(mech)
	if br ~= "" then
		table.insert(lines, "Detalle: " .. br)
	end
	ui.mechNote.Text = table.concat(lines, "\n")
end

local function refreshUI()
	if S.closed or not ui.carryNum then return end

	ui.carryNum.Text = S.total .. " / " .. S.limit
	local r = math.clamp(S.total / math.max(S.limit, 1), 0, 1)
	ui.fill.Size = UDim2.new(r, 0, 1, 0)
	ui.fill.BackgroundColor3 = (r >= 1 and COLOR.red) or (r >= 0.7 and COLOR.amber) or COLOR.green

	ui.speedVal.Text = tostring(S.speed)

	ui.autoBtn.Text = S.on and "■  DETENER AUTO" or "▶  AUTO RECOLECTAR"
	ui.autoBtn.BackgroundColor3 = S.on and COLOR.red or COLOR.green
	ui.bubble.BackgroundColor3 = S.on and COLOR.green or COLOR.accent

	ui.areaLbl.Text = areaLabel()
	ui.limitBtn.Text = S.limitMode == "MAX" and "Límite: CarryMax" or "Límite: CarryCapacity"
	ui.moveBtn.Text = S.moveMode == "GLIDE" and "Mover: Deslizar" or "Mover: Teletransporte"

	local baseTxt = S.base and "guardada" or (getBasePos() and "marcador" or "✖")
	ui.infoLbl.Text = "Base: " .. baseTxt .. " · Zona: " .. (S.zone and "✔" or "✖") .. " · Recogidas: " .. S.collected
end

---------------------------------------------------------------
-- AUTO-RECOLECCIÓN (nueva)
--   1. Elige la pieza válida más cercana del área/tipos elegidos
--   2. Se mueve hasta ella y la recoge hasta que sube la carga, desaparece o se agota el tiempo
--   3. Si CarryTotal llega al límite (o varias pilas seguidas no se pueden recoger), vuelve a la base
--   4. Espera a que se vacíe y repite
---------------------------------------------------------------
local function collectPile(mech, entry)
	local inst = entry.inst
	local name = typeLabel(entry.kind)

	setState("Yendo: " .. name, COLOR.cyan)
	local pos = pilePos(inst)
	if not pos or not moveTo(mech, pos + Vector3.new(0, CFG.ALTURA, 0)) then
		S.black[inst] = os.clock() + CFG.BLOQUEO
		S.fails += 1
		return
	end

	setState("Recolectando: " .. name, COLOR.green)
	local last = (getCarry(mech))
	local progressed = false
	local t0 = os.clock()
	local tProg = t0

	while S.on and not S.closed and mech.Parent do
		triggerPile(inst)
		task.wait(CFG.ESPERA_PROMPT)

		local total, limit = getCarry(mech)
		S.total, S.limit = total, limit

		if total > last then
			progressed = true
			last = total
			tProg = os.clock()
		end
		if total >= limit then
			break
		end
		if not pileAlive(inst) then
			progressed = true
			break
		end
		local now = os.clock()
		if now - tProg > CFG.SIN_PROGRESO or now - t0 > CFG.TIMEOUT_PILA then
			break
		end
	end

	if progressed then
		S.collected += 1
		S.fails = 0
	else
		S.black[inst] = os.clock() + CFG.BLOQUEO
		S.fails += 1
	end
end

local function unloadStep(mech)
	local base = getBasePos()
	if not base then
		setState("Lleno · guarda tu base", COLOR.red)
		task.wait(2)
		return
	end

	setState("Lleno · vuelvo a base", COLOR.amber)
	if not moveTo(mech, base + Vector3.new(0, CFG.ALTURA, 0)) then
		return
	end

	setState("Descargando...", COLOR.amber)
	local startTotal = (getCarry(mech))
	local t0 = os.clock()
	local lastChange = t0
	local lowest = startTotal

	while S.on and not S.closed and mech.Parent and os.clock() - t0 < CFG.ESPERA_DESCARGA do
		task.wait(0.4)
		local total, limit = getCarry(mech)
		S.total, S.limit = total, limit
		if total <= 0 then
			break
		end
		if total < lowest then
			lowest = total
			lastChange = os.clock()
		end
		-- Ya bajó y lleva un rato estable: se da por descargado
		if lowest < startTotal and os.clock() - lastChange > 2 then
			break
		end
	end

	local finalTotal = (getCarry(mech))
	if finalTotal < startTotal then
		S.fails = 0
	else
		setStatus("⚠ No se vació en la base: revisa tu 📍 Base", COLOR.amber)
		task.wait(2)
	end
end

local function autoStep()
	local mech = getMech()
	if not mech then
		setState("Sin mecha", COLOR.red)
		task.wait(1.5)
		return
	end

	local origin = currentPos(mech)
	if not origin then
		setState("Esperando personaje", COLOR.sub)
		task.wait(1)
		return
	end

	local total, limit = getCarry(mech)
	S.total, S.limit = total, limit

	-- Lleno, o varias pilas seguidas sin poder recoger con carga encima: a la base
	if total >= limit or (S.fails >= CFG.FALLOS_LLENO and total > 0) then
		unloadStep(mech)
		return
	end

	local entry = nextPile(origin)
	if entry then
		collectPile(mech, entry)
		return
	end

	-- Sin piezas cargadas en el área: ir a la zona guardada para que carguen
	if S.zone and (S.zone - origin).Magnitude > 30 then
		setState("Sin piezas · voy a la zona", COLOR.cyan)
		moveTo(mech, S.zone + Vector3.new(0, CFG.ALTURA, 0))
		S.pileDirty = true
		return
	end

	-- Ya no quedan piezas y llevas carga: descargar
	if total > 0 then
		unloadStep(mech)
		return
	end

	setState("Sin piezas en " .. areaLabel(), COLOR.sub)
	S.pileDirty = true
	task.wait(CFG.TICK)
end

local function setAuto(v)
	S.on = v
	S.fails = 0
	S.pileDirty = true
	if v then
		setState("Iniciando", COLOR.green)
	else
		setState("Parado", COLOR.sub)
	end
	refreshUI()
end

-- Botón manual: activa las piezas que tengas cerca (según tipos activos)
local function recogerCercanas()
	if not fireproximityprompt and not firetouchinterest then
		return -1
	end
	local root = hrpNow()
	local mech = getMech()
	local center = root and root.Position or (mech and mech:GetPivot().Position)
	if not center then
		return 0
	end

	S.pileDirty = true
	local n = 0
	for _, e in ipairs(getPiles()) do
		if S.types[e.kind] and pileAlive(e.inst) then
			local p = pilePos(e.inst)
			if p and (p - center).Magnitude <= CFG.RANGO_RECOGER then
				if triggerPile(e.inst) then
					n += 1
				end
				task.wait(CFG.ESPERA_PROMPT)
			end
		end
	end
	return n
end

-- Diagnóstico: qué hay en cada PartPiles y si tiene prompts
local function scanPiles()
	local arenas = getArenas()
	if not arenas then
		ui.scanNote.Text = "No encuentro Workspace.World.Arenas"
		return
	end

	local lines = {}
	local totalPiles, withPrompt = 0, 0
	for _, area in ipairs(arenas:GetChildren()) do
		local pp = area:FindFirstChild("PartPiles", true)
		if not pp then
			table.insert(lines, area.Name .. ": sin PartPiles")
		else
			local list = collectCandidates(pp, area.Name)
			local counts, order = {}, {}
			for _, e in ipairs(list) do
				if not counts[e.kind] then
					counts[e.kind] = 0
					table.insert(order, e.kind)
				end
				counts[e.kind] += 1
				totalPiles += 1
				if #promptsOf(e.inst) > 0 then
					withPrompt += 1
				end
			end
			table.sort(order)
			local parts = {}
			for _, k in ipairs(order) do
				table.insert(parts, k .. "×" .. counts[k])
			end

			if #list == 0 then
				-- Muestra qué hijos hay, para ver cómo se llaman
				local seen, names = {}, {}
				for _, c in ipairs(pp:GetChildren()) do
					local key = c.Name .. "(" .. c.ClassName .. ")"
					if not seen[key] and #names < 5 then
						seen[key] = true
						table.insert(names, key)
					end
				end
				table.insert(lines, area.Name .. ": 0 reconocidas. Hijos: " .. (#names > 0 and table.concat(names, ", ") or "ninguno"))
			else
				table.insert(lines, area.Name .. ": " .. #list .. " (" .. table.concat(parts, ", ") .. ")")
			end
		end
	end

	table.insert(lines, 1, "Piezas cargadas: " .. totalPiles .. " · con prompt: " .. withPrompt)
	ui.scanNote.Text = table.concat(lines, "\n")

	print("--- ESCANEO DE PARTPILES ---")
	for _, l in ipairs(lines) do
		print(l)
	end
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

-- Pestañas
local tabRow = Instance.new("Frame")
tabRow.Position = UDim2.fromOffset(8, 40)
tabRow.Size = UDim2.new(1, -16, 0, 26)
tabRow.BackgroundTransparency = 1
tabRow.Parent = panel
do
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.Padding = UDim.new(0, 4)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = tabRow
end

local tabNames = { "Auto", "Tipos", "Mecha" }
local tabButtons, pages = {}, {}

local function newPage()
	local p = Instance.new("ScrollingFrame")
	p.Position = UDim2.fromOffset(8, 70)
	p.Size = UDim2.new(1, -16, 1, -78)
	p.BackgroundTransparency = 1
	p.BorderSizePixel = 0
	p.ScrollBarThickness = 2
	p.ScrollBarImageColor3 = COLOR.accent
	p.CanvasSize = UDim2.new()
	p.AutomaticCanvasSize = Enum.AutomaticSize.Y
	p.Visible = false
	p.Parent = panel
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = p
	table.insert(pages, p)
	return p
end

local pageAuto = newPage()
local pageTipos = newPage()
local pageMecha = newPage()

local function showTab(i)
	for idx, p in ipairs(pages) do
		p.Visible = (idx == i)
	end
	for idx, b in ipairs(tabButtons) do
		b.BackgroundColor3 = (idx == i) and COLOR.accent or COLOR.btn
		b.TextColor3 = (idx == i) and COLOR.bg or COLOR.text
	end
end

for i, name in ipairs(tabNames) do
	local b = btn(tabRow, name, UDim2.new(1 / #tabNames, -3, 1, 0), nil, COLOR.btn, 12)
	b.LayoutOrder = i
	tabButtons[i] = b
	b.Activated:Connect(function() showTab(i) end)
end

---------------------------------------------------------------
-- PESTAÑA AUTO
---------------------------------------------------------------
-- Carga del mecha
local carga = card(pageAuto, 1, 64)
lbl(carga, "CARGA", UDim2.new(0.4, 0, 0, 12), UDim2.fromOffset(10, 6), 9, COLOR.sub, Enum.Font.GothamBold)
ui.stateLbl = lbl(carga, "Parado", UDim2.new(0.6, -10, 0, 12), UDim2.new(0.4, 0, 0, 6), 9, COLOR.sub, Enum.Font.GothamBold)
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

-- Botón principal
ui.autoBtn = btn(pageAuto, "▶  AUTO RECOLECTAR", UDim2.new(1, 0, 0, 40), nil, COLOR.green, 13)
ui.autoBtn.LayoutOrder = 2
ui.autoBtn.TextColor3 = COLOR.white

-- Selector de área
local areaCard = card(pageAuto, 3, 34)
local prevArea = btn(areaCard, "◀", UDim2.fromOffset(34, 26), UDim2.fromOffset(4, 4), COLOR.btn, 13)
local nextArea = btn(areaCard, "▶", UDim2.fromOffset(34, 26), UDim2.new(1, -38, 0, 4), COLOR.btn, 13)
ui.areaLbl = lbl(areaCard, "", UDim2.new(1, -84, 1, 0), UDim2.fromOffset(42, 0), 11, COLOR.cyan, Enum.Font.GothamBold)
ui.areaLbl.TextXAlignment = Enum.TextXAlignment.Center

-- Base y zona
local rBases = row(pageAuto, 4, 34)
ui.baseBtn = btn(rBases, "📍 Base", UDim2.new(0.5, -3, 1, 0), nil, COLOR.btn, 12)
ui.zoneBtn = btn(rBases, "📍 Zona", UDim2.new(0.5, -3, 1, 0), nil, COLOR.btn, 12)

-- Acciones manuales
local rActs = row(pageAuto, 5, 34)
local pickBtn = btn(rActs, "🧲 Recoger", UDim2.new(0.5, -3, 1, 0), nil, COLOR.btn, 12)
local clearBtn = btn(rActs, "↺ Limpiar", UDim2.new(0.5, -3, 1, 0), nil, COLOR.btn, 12)
clearBtn.TextColor3 = COLOR.red

ui.msgLbl = lbl(pageAuto, "", UDim2.new(1, 0, 0, 16), nil, 10, COLOR.sub, Enum.Font.Gotham)
ui.msgLbl.LayoutOrder = 6
ui.msgLbl.TextXAlignment = Enum.TextXAlignment.Center

ui.infoLbl = lbl(pageAuto, "", UDim2.new(1, 0, 0, 14), nil, 9, COLOR.sub, Enum.Font.Gotham)
ui.infoLbl.LayoutOrder = 7
ui.infoLbl.TextXAlignment = Enum.TextXAlignment.Center

---------------------------------------------------------------
-- PESTAÑA TIPOS
---------------------------------------------------------------
local typeToggles = {}
for i, t in ipairs(TYPES) do
	typeToggles[t.key] = toggleRow(pageTipos, i, t.es .. "  (" .. t.key .. ")", S.types[t.key], function(v)
		S.types[t.key] = v
		S.pileDirty = true
	end)
end

local rAll = row(pageTipos, #TYPES + 1, 32)
local allBtn = btn(rAll, "✔ Todos", UDim2.new(0.5, -3, 1, 0), nil, COLOR.btn, 12)
local noneBtn = btn(rAll, "✖ Ninguno", UDim2.new(0.5, -3, 1, 0), nil, COLOR.btn, 12)

local typeNote = note(pageTipos, #TYPES + 2)
typeNote.Text = "Solo se recogen los tipos marcados. Si una pila no se puede recoger (por ejemplo, pesa más de lo que te cabe), se ignora unos segundos y sigue con otra."

---------------------------------------------------------------
-- PESTAÑA MECHA
---------------------------------------------------------------
local spd = card(pageMecha, 1, 46)
lbl(spd, "VELOCIDAD", UDim2.new(0.5, 0, 0, 12), UDim2.fromOffset(10, 4), 9, COLOR.sub, Enum.Font.GothamBold)
local minusBtn = btn(spd, "−", UDim2.fromOffset(40, 26), UDim2.fromOffset(8, 16), COLOR.btn, 16)
local plusBtn = btn(spd, "+", UDim2.fromOffset(40, 26), UDim2.new(1, -48, 0, 16), COLOR.btn, 16)
ui.speedVal = lbl(spd, "40", UDim2.new(1, -110, 0, 26), UDim2.fromOffset(55, 16), 16, COLOR.cyan, Enum.Font.GothamBlack)
ui.speedVal.TextXAlignment = Enum.TextXAlignment.Center

local applyBtn = btn(pageMecha, "⚡ Aplicar velocidad", UDim2.new(1, 0, 0, 32), nil, COLOR.btn, 12)
applyBtn.LayoutOrder = 2

ui.limitBtn = btn(pageMecha, "", UDim2.new(1, 0, 0, 32), nil, COLOR.btn, 12)
ui.limitBtn.LayoutOrder = 3

ui.moveBtn = btn(pageMecha, "", UDim2.new(1, 0, 0, 32), nil, COLOR.btn, 12)
ui.moveBtn.LayoutOrder = 4

local rDiag = row(pageMecha, 5, 32)
local statsBtn = btn(rDiag, "📊 Stats", UDim2.new(0.5, -3, 1, 0), nil, COLOR.btn, 12)
local scanBtn = btn(rDiag, "🔎 Escanear", UDim2.new(0.5, -3, 1, 0), nil, COLOR.btn, 12)

ui.mechNote = note(pageMecha, 6)
ui.scanNote = note(pageMecha, 7)

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
		local x, y = clampPos((vp.X - w) / 2, vp.Y * 0.12, w, h)
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
ui.autoBtn.Activated:Connect(function()
	setAuto(not S.on)
end)

local function cycleArea(step)
	local opts = buildAreaOptions()
	local idx = 1
	for i, o in ipairs(opts) do
		if o.name == S.areaName then
			idx = i
			break
		end
	end
	idx += step
	if idx < 1 then idx = #opts end
	if idx > #opts then idx = 1 end
	S.areaName = opts[idx].name
	S.pileDirty = true
	S.fails = 0
	refreshUI()
end

prevArea.Activated:Connect(function() cycleArea(-1) end)
nextArea.Activated:Connect(function() cycleArea(1) end)

ui.baseBtn.Activated:Connect(function()
	local root = hrpNow()
	if not root then
		setStatus("❌ Sin personaje", COLOR.red)
		return
	end
	-- Si pilotas, la base se guarda donde está el mecha
	local mech = getMech()
	if mech and pilotActive(mech) then
		S.base = mech:GetPivot().Position
	else
		S.base = root.Position
	end
	setStatus("✅ Base guardada aquí", COLOR.green)
	refreshUI()
end)

ui.zoneBtn.Activated:Connect(function()
	local root = hrpNow()
	if not root then
		setStatus("❌ Sin personaje", COLOR.red)
		return
	end
	local mech = getMech()
	if mech and pilotActive(mech) then
		S.zone = mech:GetPivot().Position
	else
		S.zone = root.Position
	end
	setStatus("✅ Zona guardada aquí", COLOR.green)
	refreshUI()
end)

clearBtn.Activated:Connect(function()
	S.base, S.zone = nil, nil
	setStatus("↺ Base y zona borradas", COLOR.amber)
	refreshUI()
end)

pickBtn.Activated:Connect(function()
	task.spawn(function()
		local n = recogerCercanas()
		if n < 0 then
			setStatus("❌ Tu ejecutor no soporta fireproximityprompt", COLOR.red)
		elseif n == 0 then
			setStatus("No hay piezas a menos de " .. CFG.RANGO_RECOGER .. " studs", COLOR.amber)
		else
			setStatus("✅ Piezas activadas: " .. n, COLOR.green)
		end
	end)
end)

allBtn.Activated:Connect(function()
	for _, t in ipairs(TYPES) do
		S.types[t.key] = true
		typeToggles[t.key].set(true)
	end
	S.pileDirty = true
end)

noneBtn.Activated:Connect(function()
	for _, t in ipairs(TYPES) do
		S.types[t.key] = false
		typeToggles[t.key].set(false)
	end
	S.pileDirty = true
end)

minusBtn.Activated:Connect(function()
	S.speed = math.max(CFG.SPEED_MIN, S.speed - CFG.SPEED_STEP)
	refreshUI()
end)

plusBtn.Activated:Connect(function()
	S.speed = math.min(CFG.SPEED_MAX, S.speed + CFG.SPEED_STEP)
	refreshUI()
end)

applyBtn.Activated:Connect(function()
	if applySpeed() then
		setStatus("✅ Velocidad " .. S.speed .. " aplicada", COLOR.green)
	else
		setStatus("❌ No se encontró tu mecha", COLOR.red)
	end
end)

ui.limitBtn.Activated:Connect(function()
	S.limitMode = (S.limitMode == "MAX") and "CAP" or "MAX"
	refreshUI()
end)

ui.moveBtn.Activated:Connect(function()
	S.moveMode = (S.moveMode == "GLIDE") and "TP" or "GLIDE"
	refreshUI()
end)

statsBtn.Activated:Connect(function()
	local mech = getMech()
	if not mech then
		setStatus("❌ No se encontró tu mecha", COLOR.red)
		return
	end
	local total, limit = getCarry(mech)
	print("--- STATS DE MECHA ---")
	print("Nombre:", mech.Name)
	local keys = {}
	for k in pairs(mech:GetAttributes()) do
		table.insert(keys, k)
	end
	table.sort(keys)
	for _, k in ipairs(keys) do
		print(k .. ":", mech:GetAttribute(k))
	end
	refreshMechInfo()
	setStatus("✅ Stats impresos (F9): " .. total .. "/" .. limit, COLOR.green)
end)

scanBtn.Activated:Connect(function()
	task.spawn(scanPiles)
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
	local tick = 0
	while not S.closed do
		-- Con el auto apagado también se actualiza la carga mostrada
		if not S.on then
			local mech = getMech()
			if mech then
				local total, limit = getCarry(mech)
				S.total, S.limit = total, limit
			end
		end
		refreshUI()
		tick += 1
		if tick % 4 == 0 then
			pcall(refreshMechInfo)
		end
		task.wait(0.25)
	end
end)

showTab(1)
layout()
local cam = Workspace.CurrentCamera
if cam then
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
end
setState("Parado", COLOR.sub)
refreshUI()
