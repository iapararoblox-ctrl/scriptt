-- MECHA PANEL v4 · Auto-recolección con capacidad manual + conteo por pieza (count)
-- LocalScript móvil. Piezas: Workspace.World.Arenas.<Nivel>.PartPiles
-- Todo lo que cambies se guarda en MechaPanel_v3.json (writefile)

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
	GUI_NAME = "MechaMobilePanel",
	SAVE_FILE = "MechaPanel_v3.json",
	PANEL_W = 250,
	PANEL_H = 380,
	BUBBLE = 48,

	SPEED_MIN = 10,
	SPEED_MAX = 150,
	SPEED_STEP = 10,
	SPEED_DEFAULT = 40,
	SPEED_REAPPLY = 1,

	CAP_DEFECTO = 16,        -- límite si el mecha no tiene CarryCapacity ni CarryMax
	MANUAL_DEFECTO = 16,     -- capacidad manual inicial
	VUELO_VEL = 110,
	MAX_VUELO = 60,
	ALTURA = 4,
	RANGO_RECOGER = 40,

	ESPERA_PROMPT = 0.25,
	SIN_PROGRESO = 3,
	TIMEOUT_PILA = 12,
	BLOQUEO = 30,
	FALLOS_LLENO = 3,
	ESPERA_DESCARGA = 8,     -- modo automático: espera máxima a que baje CarryTotal
	ESPERA_DESCARGA_MANUAL = 4, -- modo manual: segundos en la base antes de poner el contador a 0
	RESCAN = 2,
	TICK = 0.6,
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

local STATIC_AREAS = {
	"Level1_ScrapYard",
	"Level2_RustyRails",
	"Level3_SkylineHeights",
	"Level4_ToxicBog",
	"Level5_OutpostZero",
	"Level9_KaijuBay",
	"Level10_EmpireCity",
}

local LIMIT_LABEL = {
	MAX = "Límite: CarryMax",
	CAP = "Límite: CarryCapacity",
	MANUAL = "Límite: Manual (tu número)",
}

---------------------------------------------------------------
-- ESTADO
---------------------------------------------------------------
local S = {
	closed = false,
	on = false,
	speed = CFG.SPEED_DEFAULT,
	speedOn = false,
	speedMech = nil,
	state = "Parado",
	total = 0,
	limit = CFG.CAP_DEFECTO,
	base = nil,
	zone = nil,
	placed = false,
	minimized = false,

	areaName = "*ALL",
	types = {},
	caps = {},
	session = {},          -- tipo -> cantidad recogida en la carga actual
	limitMode = "MAX",     -- MAX | CAP | MANUAL
	moveMode = "GLIDE",
	manualCap = CFG.MANUAL_DEFECTO,  -- capacidad que escribes tú
	carried = 0,           -- piezas contadas en la carga actual (modo manual)

	mechPick = nil,
	mechPickName = nil,
	mech = nil,
	mechTime = -100,
	deepTime = -100,

	pileCache = nil,
	pileTime = -100,
	pileDirty = true,
	black = setmetatable({}, { __mode = "k" }),

	collected = 0,
	fails = 0,
}
for _, t in ipairs(TYPES) do
	S.types[t.key] = true
end

local ui = {}

---------------------------------------------------------------
-- GUARDADO / CARGA
---------------------------------------------------------------
local function saveNow()
	if not writefile then return end
	local data = {
		speed = S.speed,
		speedOn = S.speedOn,
		limitMode = S.limitMode,
		moveMode = S.moveMode,
		areaName = S.areaName,
		types = S.types,
		caps = S.caps,
		manualCap = S.manualCap,
		carried = S.carried,
		session = S.session,
		mech = S.mechPickName,
		base = S.base and { S.base.X, S.base.Y, S.base.Z } or nil,
		zone = S.zone and { S.zone.X, S.zone.Y, S.zone.Z } or nil,
	}
	pcall(function()
		writefile(CFG.SAVE_FILE, HttpService:JSONEncode(data))
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

local function loadSaved()
	if not (readfile and isfile) then return end
	local ok, data = pcall(function()
		if isfile(CFG.SAVE_FILE) then
			return HttpService:JSONDecode(readfile(CFG.SAVE_FILE))
		end
	end)
	if not ok or type(data) ~= "table" then return end

	if tonumber(data.speed) then
		S.speed = math.clamp(tonumber(data.speed), CFG.SPEED_MIN, CFG.SPEED_MAX)
	end
	S.speedOn = data.speedOn == true
	if data.limitMode == "MAX" or data.limitMode == "CAP" or data.limitMode == "MANUAL" then
		S.limitMode = data.limitMode
	end
	if data.moveMode == "GLIDE" or data.moveMode == "TP" then S.moveMode = data.moveMode end
	if type(data.areaName) == "string" then S.areaName = data.areaName end
	if type(data.types) == "table" then
		for _, t in ipairs(TYPES) do
			if data.types[t.key] ~= nil then S.types[t.key] = data.types[t.key] == true end
		end
	end
	if type(data.caps) == "table" then
		for _, t in ipairs(TYPES) do
			local v = tonumber(data.caps[t.key])
			if v and v > 0 then S.caps[t.key] = math.floor(v) end
		end
	end
	local mc = tonumber(data.manualCap)
	if mc and mc >= 1 then S.manualCap = math.floor(mc) end
	local ca = tonumber(data.carried)
	if ca and ca >= 0 then S.carried = math.floor(ca) end
	if type(data.session) == "table" then
		for _, t in ipairs(TYPES) do
			local v = tonumber(data.session[t.key])
			if v and v > 0 then S.session[t.key] = math.floor(v) end
		end
	end
	if type(data.mech) == "string" and data.mech ~= "" then S.mechPickName = data.mech end
	if type(data.base) == "table" and #data.base == 3 then
		S.base = Vector3.new(data.base[1], data.base[2], data.base[3])
	end
	if type(data.zone) == "table" and #data.zone == 3 then
		S.zone = Vector3.new(data.zone[1], data.zone[2], data.zone[3])
	end
end
loadSaved()

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
-- MECHA (automático o elegido a mano)
---------------------------------------------------------------
local function hrpNow()
	local char = LocalPlayer.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

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

local function listMechs()
	local out, seen = {}, {}
	local function consider(m)
		if m:IsA("Model") and not seen[m] and scoreMech(m) > 0 then
			seen[m] = true
			table.insert(out, m)
		end
	end
	for _, o in ipairs(Workspace:GetChildren()) do
		consider(o)
	end
	for _, o in ipairs(Workspace:GetDescendants()) do
		if o:IsA("Model") and o:GetAttribute("MechId") ~= nil then
			consider(o)
		end
	end
	table.sort(out, function(a, b)
		local oa, ob = ownedBy(a), ownedBy(b)
		if oa ~= ob then return oa end
		return a.Name < b.Name
	end)
	return out
end

local function findByName(name)
	for _, o in ipairs(Workspace:GetChildren()) do
		if o:IsA("Model") and o.Name == name and scoreMech(o) > 0 then
			return o
		end
	end
	if os.clock() - S.deepTime > 5 then
		S.deepTime = os.clock()
		for _, o in ipairs(Workspace:GetDescendants()) do
			if o:IsA("Model") and o.Name == name and o:GetAttribute("MechId") ~= nil then
				return o
			end
		end
	end
	return nil
end

local function getMech()
	local now = os.clock()

	if S.mechPickName then
		if S.mechPick and S.mechPick.Parent then
			S.mech = S.mechPick
			return S.mech
		end
		if now - S.mechTime >= 2 then
			S.mechTime = now
			S.mechPick = findByName(S.mechPickName)
		end
		S.mech = S.mechPick
		return S.mech
	end

	if S.mech and S.mech.Parent and now - S.mechTime < 2 then
		return S.mech
	end
	S.mech = findMech()
	S.mechTime = now
	return S.mech
end

local function setMechPick(m)
	S.mechPick = m
	S.mechPickName = m and m.Name or nil
	S.mech = m
	S.mechTime = os.clock()
	if S.limitMode ~= "MANUAL" then
		S.session = {}
	end
	S.fails = 0
	save()
end

-- Devuelve: total actual, límite activo
-- En modo MANUAL usa tu conteo (S.carried) y tu capacidad (S.manualCap)
local function getCarry(mech)
	if S.limitMode == "MANUAL" then
		return S.carried, math.max(1, S.manualCap)
	end

	local total = tonumber(mech:GetAttribute("CarryTotal")) or 0
	local cap = tonumber(mech:GetAttribute("CarryCapacity"))
	local max = tonumber(mech:GetAttribute("CarryMax"))
	local limit
	if S.limitMode == "MAX" then
		limit = max or cap or CFG.CAP_DEFECTO
	else
		limit = cap or max or CFG.CAP_DEFECTO
	end
	if total <= 0 and next(S.session) ~= nil then
		S.session = {}
	end
	return total, limit
end

local function shortName(key)
	return (key:gsub("PartPile$", ""))
end

-- Cantidad que lleva de un tipo. En modo manual siempre usa tu conteo.
local function typeCount(mech, key)
	if S.limitMode == "MANUAL" or not mech then
		return S.session[key] or 0
	end
	for _, n in ipairs({ "Carry_" .. shortName(key), "Carry_" .. key }) do
		local v = mech:GetAttribute(n)
		if v ~= nil then
			return tonumber(v) or 0
		end
	end
	return S.session[key] or 0
end

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

---------------------------------------------------------------
-- VELOCIDAD (reversible)
---------------------------------------------------------------
local origSpeed = setmetatable({}, { __mode = "k" })

local function applySpeed(mech)
	local o = origSpeed[mech]
	if not o then
		o = { attrs = {}, hums = {} }
		origSpeed[mech] = o
		for _, k in ipairs({ "WalkSpeed", "RunSpeed" }) do
			local v = mech:GetAttribute(k)
			if v ~= nil then o.attrs[k] = v end
		end
	end

	if mech:GetAttribute("WalkSpeed") ~= nil and mech:GetAttribute("WalkSpeed") ~= S.speed then
		mech:SetAttribute("WalkSpeed", S.speed)
	end
	if mech:GetAttribute("RunSpeed") ~= nil and mech:GetAttribute("RunSpeed") ~= S.speed + 20 then
		mech:SetAttribute("RunSpeed", S.speed + 20)
	end
	for _, d in ipairs(mech:GetDescendants()) do
		if d:IsA("Humanoid") then
			if o.hums[d] == nil then
				o.hums[d] = d.WalkSpeed
			end
			if d.WalkSpeed ~= S.speed then
				d.WalkSpeed = S.speed
			end
		end
	end
end

local function restoreSpeed(mech)
	local o = mech and origSpeed[mech]
	if not o then return false end
	for k, v in pairs(o.attrs) do
		if mech.Parent then mech:SetAttribute(k, v) end
	end
	for h, v in pairs(o.hums) do
		if h.Parent then h.WalkSpeed = v end
	end
	origSpeed[mech] = nil
	return true
end

---------------------------------------------------------------
-- MOVIMIENTO
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

local function typeOf(name)
	for _, t in ipairs(TYPES) do
		if name == t.key or name:sub(1, #t.key) == t.key then
			return t.key
		end
	end
	return nil
end

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

-- Lee el atributo "count" de la pila (cuántas piezas quedan). Si no existe, cuenta 1.
local function readCount(inst)
	local cur, depth = inst, 0
	while cur and depth < 2 do
		local v = cur:GetAttribute("count")
		if v == nil then
			local c = cur:FindFirstChild("count")
			if c and c:IsA("ValueBase") then
				v = c.Value
			end
		end
		local n = tonumber(v)
		if n then
			return math.max(0, math.floor(n))
		end
		cur = cur.Parent
		depth += 1
	end
	return 1
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

-- Pila válida más cercana. Salta los tipos cuyo cupo ya está completo.
local function nextPile(mech, origin)
	local now = os.clock()
	local best, bestDist
	local capBlocked = false
	local full = {}

	for _, e in ipairs(getPiles()) do
		local expiry = S.black[e.inst]
		local blocked = expiry ~= nil and expiry > now
		if S.types[e.kind] and not blocked and pileAlive(e.inst) then
			local cap = S.caps[e.kind]
			local isFull = false
			if cap then
				if full[e.kind] == nil then
					full[e.kind] = typeCount(mech, e.kind) >= cap
				end
				isFull = full[e.kind]
			end
			if isFull then
				capBlocked = true
			else
				local p = pilePos(e.inst)
				if p then
					local d = (p - origin).Magnitude
					if not bestDist or d < bestDist then
						best, bestDist = e, d
					end
				end
			end
		end
	end
	return best, capBlocked
end

---------------------------------------------------------------
-- CONTADOR MANUAL
---------------------------------------------------------------
-- Suma piezas recogidas al contador (y al conteo por tipo) y guarda
local function addCarried(kind, n)
	if n <= 0 then return end
	S.carried += n
	S.session[kind] = (S.session[kind] or 0) + n
	save()
end

local function resetCarry()
	S.carried = 0
	S.session = {}
	S.total = 0
	S.fails = 0
	save()
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
		if S.mechPickName then
			ui.mechNote.Text = "No encuentro el mecha elegido: " .. S.mechPickName .. ". Pulsa 🔄 o vuelve a Automático."
		else
			ui.mechNote.Text = "No encuentro tu mecha. Debe ser un modelo en Workspace con tu OwnerName/Owner y atributos Carry*."
		end
		return
	end
	local lines = {}
	table.insert(lines, "Mecha (" .. (S.mechPickName and "manual" or "auto") .. "): " .. mech.Name)
	table.insert(lines, "MechId: " .. tostring(mech:GetAttribute("MechId"))
		.. " · Piloto: " .. (pilotActive(mech) and "sí" or "no")
		.. " (PilotMode=" .. tostring(mech:GetAttribute("PilotMode")) .. ")")
	table.insert(lines, "CarryTotal: " .. tostring(mech:GetAttribute("CarryTotal"))
		.. " · CarryCapacity: " .. tostring(mech:GetAttribute("CarryCapacity"))
		.. " · CarryMax: " .. tostring(mech:GetAttribute("CarryMax")))
	local br = carryBreakdown(mech)
	if br ~= "" then
		table.insert(lines, "Detalle: " .. br)
	end
	local o = origSpeed[mech]
	if o then
		table.insert(lines, "Velocidad original: WalkSpeed " .. tostring(o.attrs.WalkSpeed) .. " · RunSpeed " .. tostring(o.attrs.RunSpeed))
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
	ui.speedBtn.Text = S.speedOn and "Velocidad: ENCENDIDA (tocar = original)" or "Velocidad: APAGADA (original)"
	ui.speedBtn.BackgroundColor3 = S.speedOn and COLOR.green or COLOR.btn
	ui.speedBtn.TextColor3 = S.speedOn and COLOR.white or COLOR.text

	ui.autoBtn.Text = S.on and "■  DETENER AUTO" or "▶  AUTO RECOLECTAR"
	ui.autoBtn.BackgroundColor3 = S.on and COLOR.red or COLOR.green
	ui.bubble.BackgroundColor3 = S.on and COLOR.green or COLOR.accent

	if ui.manualBox and not ui.manualBox:IsFocused() then
		ui.manualBox.Text = tostring(S.manualCap)
	end
	if ui.manualInfo then
		ui.manualInfo.Text = "Llevas " .. S.carried .. " de " .. S.manualCap
			.. (S.limitMode == "MANUAL" and "" or "  (límite activo: " .. S.limitMode .. ")")
	end

	ui.areaLbl.Text = areaLabel()
	ui.limitBtn.Text = LIMIT_LABEL[S.limitMode] or LIMIT_LABEL.MAX
	ui.moveBtn.Text = S.moveMode == "GLIDE" and "Mover: Deslizar" or "Mover: Teletransporte"
	ui.mechLbl.Text = S.mechPickName or "Automático"

	local baseTxt = S.base and "guardada" or (getBasePos() and "marcador" or "✖")
	ui.infoLbl.Text = "Base: " .. baseTxt .. " · Zona: " .. (S.zone and "✔" or "✖") .. " · Recogidas: " .. S.collected

	local mech = S.mech
	local sum = 0
	for _, t in ipairs(TYPES) do
		local cap = S.caps[t.key]
		if cap then sum += cap end
		local cnt = typeCount(mech, t.key)
		local l = ui.capLbl[t.key]
		if l then
			l.Text = t.es .. "  " .. cnt .. (cap and ("/" .. cap) or "")
			l.TextColor3 = (cap and cnt >= cap) and COLOR.amber or COLOR.text
		end
	end
	if ui.capSum then
		local txt = "Suma de cupos: " .. sum .. " · Capacidad activa: " .. S.limit
		if sum > S.limit then
			txt = txt .. "\n(la capacidad total manda)"
		end
		ui.capSum.Text = txt
	end
end

---------------------------------------------------------------
-- AUTO-RECOLECCIÓN
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
	local manual = S.limitMode == "MANUAL"
	local last = (getCarry(mech))
	local c0 = readCount(inst)      -- piezas que quedan en esta pila
	local progressed = false
	local t0 = os.clock()
	local tProg = t0

	while S.on and not S.closed and mech.Parent do
		triggerPile(inst)
		task.wait(CFG.ESPERA_PROMPT)

		if manual then
			-- Validación por pieza: lo que bajó el "count" es lo que recogiste
			if not pileAlive(inst) then
				addCarried(entry.kind, c0)
				c0 = 0
				progressed = true
				break
			end
			local c1 = readCount(inst)
			if c1 < c0 then
				addCarried(entry.kind, c0 - c1)
				c0 = c1
				progressed = true
				tProg = os.clock()
			end
			if c0 <= 0 then
				break
			end
		else
			local total = getCarry(mech)
			if total > last then
				progressed = true
				S.session[entry.kind] = (S.session[entry.kind] or 0) + (total - last)
				last = total
				tProg = os.clock()
			end
		end

		local total, limit = getCarry(mech)
		S.total, S.limit = total, limit
		if total >= limit then
			break
		end

		local cap = S.caps[entry.kind]
		if cap and typeCount(mech, entry.kind) >= cap then
			progressed = true
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

	-- MODO MANUAL: espera en la base y pone tu contador a 0
	if S.limitMode == "MANUAL" then
		setState("Descargando...", COLOR.amber)
		local t0 = os.clock()
		while S.on and not S.closed and os.clock() - t0 < CFG.ESPERA_DESCARGA_MANUAL do
			task.wait(0.2)
		end
		if S.on and not S.closed then
			resetCarry()
			setStatus("✅ Descargado: contador a 0", COLOR.green)
		end
		return
	end

	-- MODO AUTOMÁTICO: espera a que baje CarryTotal
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

	if total >= limit or (S.fails >= CFG.FALLOS_LLENO and total > 0) then
		unloadStep(mech)
		return
	end

	local entry, capBlocked = nextPile(mech, origin)
	if entry then
		collectPile(mech, entry)
		return
	end

	if capBlocked and total > 0 then
		setState("Cupos completos", COLOR.amber)
		unloadStep(mech)
		return
	end

	if S.zone and (S.zone - origin).Magnitude > 30 then
		setState("Sin piezas · voy a la zona", COLOR.cyan)
		moveTo(mech, S.zone + Vector3.new(0, CFG.ALTURA, 0))
		S.pileDirty = true
		return
	end

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

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 38)
header.BackgroundTransparency = 1
header.Active = true
header.Parent = panel

lbl(header, "MECHA PANEL", UDim2.new(1, -80, 1, 0), UDim2.fromOffset(10, 0), 12, COLOR.accent, Enum.Font.GothamBold)
local minBtn = btn(header, "–", UDim2.fromOffset(28, 28), UDim2.new(1, -64, 0, 5), COLOR.btn, 15)
local closeBtn = btn(header, "✕", UDim2.fromOffset(28, 28), UDim2.new(1, -32, 0, 5), COLOR.btn, 12)
closeBtn.TextColor3 = COLOR.red

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

local tabNames = { "Auto", "Tipos", "Cupos", "Mecha" }
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
local pageCupos = newPage()
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
	local b = btn(tabRow, name, UDim2.new(1 / #tabNames, -3, 1, 0), nil, COLOR.btn, 11)
	b.LayoutOrder = i
	tabButtons[i] = b
	b.Activated:Connect(function() showTab(i) end)
end

---------------------------------------------------------------
-- PESTAÑA AUTO
---------------------------------------------------------------
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

ui.autoBtn = btn(pageAuto, "▶  AUTO RECOLECTAR", UDim2.new(1, 0, 0, 40), nil, COLOR.green, 13)
ui.autoBtn.LayoutOrder = 2
ui.autoBtn.TextColor3 = COLOR.white

-- Capacidad manual: la escribes tú y el contador se guarda
local manualCard = card(pageAuto, 3, 84)
lbl(manualCard, "CAPACIDAD DE TU ROBOT (manual)", UDim2.new(1, -20, 0, 12), UDim2.fromOffset(10, 6), 9, COLOR.sub, Enum.Font.GothamBold)

local manualBox = Instance.new("TextBox")
manualBox.Size = UDim2.fromOffset(90, 26)
manualBox.Position = UDim2.fromOffset(10, 22)
manualBox.BackgroundColor3 = COLOR.btn
manualBox.BorderSizePixel = 0
manualBox.Text = tostring(S.manualCap)
manualBox.TextColor3 = COLOR.cyan
manualBox.TextSize = 14
manualBox.Font = Enum.Font.GothamBold
manualBox.ClearTextOnFocus = false
manualBox.Parent = manualCard
corner(manualBox, 6)
ui.manualBox = manualBox

ui.manualInfo = lbl(manualCard, "", UDim2.new(1, -118, 0, 26), UDim2.fromOffset(110, 22), 10, COLOR.text, Enum.Font.GothamBold)

local resetCarryBtn = btn(manualCard, "↺ Vaciar contador", UDim2.new(1, -20, 0, 24), UDim2.fromOffset(10, 54), COLOR.btn, 11)
resetCarryBtn.TextColor3 = COLOR.red

local areaCard = card(pageAuto, 4, 34)
local prevArea = btn(areaCard, "◀", UDim2.fromOffset(34, 26), UDim2.fromOffset(4, 4), COLOR.btn, 13)
local nextArea = btn(areaCard, "▶", UDim2.fromOffset(34, 26), UDim2.new(1, -38, 0, 4), COLOR.btn, 13)
ui.areaLbl = lbl(areaCard, "", UDim2.new(1, -84, 1, 0), UDim2.fromOffset(42, 0), 11, COLOR.cyan, Enum.Font.GothamBold)
ui.areaLbl.TextXAlignment = Enum.TextXAlignment.Center

local rBases = row(pageAuto, 5, 34)
ui.baseBtn = btn(rBases, "📍 Base", UDim2.new(0.5, -3, 1, 0), nil, COLOR.btn, 12)
ui.zoneBtn = btn(rBases, "📍 Zona", UDim2.new(0.5, -3, 1, 0), nil, COLOR.btn, 12)

local rActs = row(pageAuto, 6, 34)
local pickBtn = btn(rActs, "🧲 Recoger", UDim2.new(0.5, -3, 1, 0), nil, COLOR.btn, 12)
local clearBtn = btn(rActs, "↺ Limpiar", UDim2.new(0.5, -3, 1, 0), nil, COLOR.btn, 12)
clearBtn.TextColor3 = COLOR.red

ui.msgLbl = lbl(pageAuto, "", UDim2.new(1, 0, 0, 16), nil, 10, COLOR.sub, Enum.Font.Gotham)
ui.msgLbl.LayoutOrder = 7
ui.msgLbl.TextXAlignment = Enum.TextXAlignment.Center

ui.infoLbl = lbl(pageAuto, "", UDim2.new(1, 0, 0, 14), nil, 9, COLOR.sub, Enum.Font.Gotham)
ui.infoLbl.LayoutOrder = 8
ui.infoLbl.TextXAlignment = Enum.TextXAlignment.Center

---------------------------------------------------------------
-- PESTAÑA TIPOS
---------------------------------------------------------------
local typeToggles = {}
for i, t in ipairs(TYPES) do
	typeToggles[t.key] = toggleRow(pageTipos, i, t.es .. "  (" .. t.key .. ")", S.types[t.key], function(v)
		S.types[t.key] = v
		S.pileDirty = true
		save()
	end)
end

local rAll = row(pageTipos, #TYPES + 1, 32)
local allBtn = btn(rAll, "✔ Todos", UDim2.new(0.5, -3, 1, 0), nil, COLOR.btn, 12)
local noneBtn = btn(rAll, "✖ Ninguno", UDim2.new(0.5, -3, 1, 0), nil, COLOR.btn, 12)

local typeNote = note(pageTipos, #TYPES + 2)
typeNote.Text = "Solo se recogen los tipos marcados. Si una pila no se puede recoger, se ignora unos segundos y sigue con otra."

---------------------------------------------------------------
-- PESTAÑA CUPOS
---------------------------------------------------------------
ui.capLbl = {}
local capBoxes = {}

local capNote = note(pageCupos, 1)
capNote.Text = "Escribe cuántas piezas de cada tipo puede llevar. Vacío o 0 = sin límite."

for i, t in ipairs(TYPES) do
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, 0, 0, 30)
	f.BackgroundColor3 = COLOR.card
	f.BorderSizePixel = 0
	f.LayoutOrder = i + 1
	f.Parent = pageCupos
	corner(f, 8)

	ui.capLbl[t.key] = lbl(f, t.es, UDim2.new(1, -78, 1, 0), UDim2.fromOffset(10, 0), 11, COLOR.text)

	local tb = Instance.new("TextBox")
	tb.Size = UDim2.fromOffset(58, 22)
	tb.Position = UDim2.new(1, -66, 0.5, -11)
	tb.BackgroundColor3 = COLOR.btn
	tb.BorderSizePixel = 0
	tb.Text = S.caps[t.key] and tostring(S.caps[t.key]) or ""
	tb.PlaceholderText = "∞"
	tb.PlaceholderColor3 = COLOR.sub
	tb.TextColor3 = COLOR.cyan
	tb.TextSize = 13
	tb.Font = Enum.Font.GothamBold
	tb.ClearTextOnFocus = false
	tb.Parent = f
	corner(tb, 6)
	capBoxes[t.key] = tb

	tb.FocusLost:Connect(function()
		local n = tonumber(tb.Text)
		if n and n >= 1 then
			n = math.floor(n)
			S.caps[t.key] = n
			tb.Text = tostring(n)
		else
			S.caps[t.key] = nil
			tb.Text = ""
		end
		save()
	end)
end

ui.capSum = note(pageCupos, #TYPES + 2)

local clearCapsBtn = btn(pageCupos, "✖ Quitar todos los cupos", UDim2.new(1, 0, 0, 30), nil, COLOR.btn, 12)
clearCapsBtn.LayoutOrder = #TYPES + 3
clearCapsBtn.TextColor3 = COLOR.red

---------------------------------------------------------------
-- PESTAÑA MECHA
---------------------------------------------------------------
local spd = card(pageMecha, 1, 46)
lbl(spd, "VELOCIDAD", UDim2.new(0.5, 0, 0, 12), UDim2.fromOffset(10, 4), 9, COLOR.sub, Enum.Font.GothamBold)
local minusBtn = btn(spd, "−", UDim2.fromOffset(40, 26), UDim2.fromOffset(8, 16), COLOR.btn, 16)
local plusBtn = btn(spd, "+", UDim2.fromOffset(40, 26), UDim2.new(1, -48, 0, 16), COLOR.btn, 16)
ui.speedVal = lbl(spd, "40", UDim2.new(1, -110, 0, 26), UDim2.fromOffset(55, 16), 16, COLOR.cyan, Enum.Font.GothamBlack)
ui.speedVal.TextXAlignment = Enum.TextXAlignment.Center

ui.speedBtn = btn(pageMecha, "", UDim2.new(1, 0, 0, 32), nil, COLOR.btn, 11)
ui.speedBtn.LayoutOrder = 2

ui.limitBtn = btn(pageMecha, "", UDim2.new(1, 0, 0, 32), nil, COLOR.btn, 12)
ui.limitBtn.LayoutOrder = 3

ui.moveBtn = btn(pageMecha, "", UDim2.new(1, 0, 0, 32), nil, COLOR.btn, 12)
ui.moveBtn.LayoutOrder = 4

local mechCard = card(pageMecha, 5, 34)
local prevMech = btn(mechCard, "◀", UDim2.fromOffset(34, 26), UDim2.fromOffset(4, 4), COLOR.btn, 13)
local nextMech = btn(mechCard, "▶", UDim2.fromOffset(34, 26), UDim2.new(1, -38, 0, 4), COLOR.btn, 13)
ui.mechLbl = lbl(mechCard, "Automático", UDim2.new(1, -84, 1, 0), UDim2.fromOffset(42, 0), 10, COLOR.cyan, Enum.Font.GothamBold)
ui.mechLbl.TextXAlignment = Enum.TextXAlignment.Center

local rMech = row(pageMecha, 6, 32)
local autoMechBtn = btn(rMech, "🤖 Automático", UDim2.new(0.5, -3, 1, 0), nil, COLOR.btn, 11)
local listMechBtn = btn(rMech, "🔄 Ver mechas", UDim2.new(0.5, -3, 1, 0), nil, COLOR.btn, 11)

local rDiag = row(pageMecha, 7, 32)
local statsBtn = btn(rDiag, "📊 Stats", UDim2.new(0.5, -3, 1, 0), nil, COLOR.btn, 12)
local scanBtn = btn(rDiag, "🔎 Escanear", UDim2.new(0.5, -3, 1, 0), nil, COLOR.btn, 12)

ui.mechNote = note(pageMecha, 8)
ui.scanNote = note(pageMecha, 9)

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
-- VELOCIDAD: encender / apagar
---------------------------------------------------------------
local function setSpeedOn(v)
	if v then
		local mech = getMech()
		if not mech then
			setStatus("❌ No se encontró el mecha", COLOR.red)
			return
		end
		S.speedOn = true
		S.speedMech = mech
		applySpeed(mech)
		setStatus("✅ Velocidad " .. S.speed .. " activada", COLOR.green)
	else
		S.speedOn = false
		local mech = S.speedMech or getMech()
		if restoreSpeed(mech) then
			setStatus("↩ Velocidad original restaurada", COLOR.amber)
		else
			setStatus("Velocidad apagada", COLOR.sub)
		end
		S.speedMech = nil
	end
	save()
	refreshUI()
end

---------------------------------------------------------------
-- EVENTOS
---------------------------------------------------------------
ui.autoBtn.Activated:Connect(function()
	setAuto(not S.on)
end)

manualBox.FocusLost:Connect(function()
	local n = tonumber(manualBox.Text)
	if n and n >= 1 then
		S.manualCap = math.floor(n)
	end
	manualBox.Text = tostring(S.manualCap)
	saveNow()
	refreshUI()
end)

resetCarryBtn.Activated:Connect(function()
	resetCarry()
	setStatus("↺ Contador a 0", COLOR.amber)
	refreshUI()
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
	save()
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
	local mech = getMech()
	if mech and pilotActive(mech) then
		S.base = mech:GetPivot().Position
	else
		S.base = root.Position
	end
	saveNow()
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
	saveNow()
	setStatus("✅ Zona guardada aquí", COLOR.green)
	refreshUI()
end)

clearBtn.Activated:Connect(function()
	S.base, S.zone = nil, nil
	saveNow()
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
	saveNow()
end)

noneBtn.Activated:Connect(function()
	for _, t in ipairs(TYPES) do
		S.types[t.key] = false
		typeToggles[t.key].set(false)
	end
	S.pileDirty = true
	saveNow()
end)

clearCapsBtn.Activated:Connect(function()
	for _, t in ipairs(TYPES) do
		S.caps[t.key] = nil
		capBoxes[t.key].Text = ""
	end
	saveNow()
	setStatus("✖ Cupos quitados", COLOR.amber)
end)

minusBtn.Activated:Connect(function()
	S.speed = math.max(CFG.SPEED_MIN, S.speed - CFG.SPEED_STEP)
	save()
	refreshUI()
end)

plusBtn.Activated:Connect(function()
	S.speed = math.min(CFG.SPEED_MAX, S.speed + CFG.SPEED_STEP)
	save()
	refreshUI()
end)

ui.speedBtn.Activated:Connect(function()
	setSpeedOn(not S.speedOn)
end)

-- Ciclo de límite: CarryMax -> CarryCapacity -> Manual -> CarryMax
ui.limitBtn.Activated:Connect(function()
	if S.limitMode == "MAX" then
		S.limitMode = "CAP"
	elseif S.limitMode == "CAP" then
		S.limitMode = "MANUAL"
	else
		S.limitMode = "MAX"
	end
	S.fails = 0
	saveNow()
	refreshUI()
end)

ui.moveBtn.Activated:Connect(function()
	S.moveMode = (S.moveMode == "GLIDE") and "TP" or "GLIDE"
	saveNow()
	refreshUI()
end)

local function cycleMech(step)
	local list = listMechs()
	local idx = 0
	for i, m in ipairs(list) do
		if m == S.mechPick or (S.mechPickName and m.Name == S.mechPickName) then
			idx = i
			break
		end
	end
	idx += step
	if idx < 0 then idx = #list end
	if idx > #list then idx = 0 end
	if idx == 0 then
		setMechPick(nil)
		setStatus("🤖 Mecha: automático", COLOR.cyan)
	else
		setMechPick(list[idx])
		setStatus("🤖 Mecha: " .. list[idx].Name, COLOR.cyan)
	end
	refreshMechInfo()
	refreshUI()
end

prevMech.Activated:Connect(function() cycleMech(-1) end)
nextMech.Activated:Connect(function() cycleMech(1) end)

autoMechBtn.Activated:Connect(function()
	setMechPick(nil)
	setStatus("🤖 Mecha: automático", COLOR.cyan)
	refreshMechInfo()
	refreshUI()
end)

listMechBtn.Activated:Connect(function()
	local list = listMechs()
	local lines = { "Mechas encontrados: " .. #list }
	for i, m in ipairs(list) do
		table.insert(lines, i .. ". " .. m.Name .. (ownedBy(m) and " (tuyo)" or ""))
	end
	ui.scanNote.Text = table.concat(lines, "\n")
	print("--- MECHAS ---")
	for _, l in ipairs(lines) do print(l) end
end)

statsBtn.Activated:Connect(function()
	local mech = getMech()
	if not mech then
		setStatus("❌ No se encontró el mecha", COLOR.red)
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
	if S.speedOn then
		restoreSpeed(S.speedMech or S.mech)
	end
	saveNow()
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

-- Mantiene la velocidad aplicada mientras esté encendida
task.spawn(function()
	while not S.closed do
		if S.speedOn then
			local mech = getMech()
			if mech then
				if S.speedMech and S.speedMech ~= mech then
					restoreSpeed(S.speedMech)
				end
				S.speedMech = mech
				pcall(applySpeed, mech)
			end
		end
		task.wait(CFG.SPEED_REAPPLY)
	end
end)

-- Refresco de la interfaz
task.spawn(function()
	local tick = 0
	while not S.closed do
		local mech = getMech()
		if not S.on and (mech or S.limitMode == "MANUAL") then
			local total, limit = getCarry(mech)
			S.total, S.limit = total, limit
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
