-- MECHA PANEL v6 · Delta (móvil)
-- LocalScript en StarterPlayer > StarterPlayerScripts, o ejecutado con Delta

local function main()
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local UserInputService = game:GetService("UserInputService")
	local Workspace = game:GetService("Workspace")
	local LocalPlayer = Players.LocalPlayer
	local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

	-- Función de recogida del ejecutor (nil si tu Delta no la tiene)
	local firePrompt = fireproximityprompt

	---------------------------------------------------------------
	-- CONFIGURACIÓN
	---------------------------------------------------------------
	local GUI_NAME = "MechaPanelV6"
	local PANEL_W, PANEL_H = 250, 440
	local BUBBLE = 48

	local ARENAS = { "World", "Arenas" }
	local LEVELS = {
		"Level1_ScrapYard", "Level2_RustyRails", "Level3_SkylineHeights", "Level4_ToxicBog",
		"Level5_OutpostZero", "Level9_KaijuBay", "Level10_EmpireCity",
	}
	local LEVEL_LABELS = {
		"Scrap Yard", "Rusty Rails", "Skyline Heights", "Toxic Bog",
		"Outpost Zero", "Kaiju Bay", "Empire City",
	}
	local PILES = {
		"Chunk", "LightPartPile", "ScrapPartPile", "HeavyPartPile",
		"MediumPartPile", "ColossalPartPile", "TitanPartPile", "BigScrapPartPile",
	}
	local PILE_LABELS = { "Chunk", "Ligera", "Chatarra", "Pesada", "Media", "Colosal", "Titán", "G.Chat" }

	local VEL_MIN, VEL_MAX, VEL_STEP, VEL_DEFAULT = 20, 250, 10, 90
	local ALTURA = 3          -- studs sobre la pila o la base
	local LLEGADA = 5         -- distancia para considerar que llegaste
	local RANGO_PROMPT = 20
	local ESPERA_CARGA = 1.5  -- segundos esperando que suba CarryTotal
	local ESPERA_DESCARGA = 25
	local COOLDOWN_OK = 2
	local COOLDOWN_FALLO = 6
	local REVISAR_MECHA = 2
	local BASE_MARCADOR = "YourBaseMarker"

	local PILE_INDEX = {}
	for i, n in ipairs(PILES) do
		PILE_INDEX[n] = i
	end

	local C = {
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
		vel = VEL_DEFAULT,
		levelIdx = 0,
		pileOn = { true, true, true, true, true, true, true, true },
		mech = nil,
		mechCheck = 0,
		total = 0,
		cap = 16,
		ligero = 0,
		chatarra = 0,
		max = 0,
		base = nil,
		placed = false,
	}

	local cooldown = {}
	local ui = { piles = {} }

	---------------------------------------------------------------
	-- HELPERS
	---------------------------------------------------------------
	local function num(v, d)
		return tonumber(v) or d
	end

	local function ruta(root, pasos)
		local cur = root
		for _, p in ipairs(pasos) do
			cur = cur and cur:FindFirstChild(p)
			if not cur then return nil end
		end
		return cur
	end

	local function viewport()
		local cam = Workspace.CurrentCamera
		local v = cam and cam.ViewportSize or Vector2.new(0, 0)
		if v.X < 100 or v.Y < 100 then
			return Vector2.new(390, 844)
		end
		return v
	end

	local function clampPos(x, y, w, h)
		local vp = viewport()
		return math.clamp(x, 0, math.max(0, vp.X - w)), math.clamp(y, 0, math.max(0, vp.Y - h))
	end

	local function fitScale()
		local vp = viewport()
		return math.clamp(math.min(vp.X * 0.9 / PANEL_W, vp.Y * 0.78 / PANEL_H, 1.1), 0.6, 1.1)
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

	---------------------------------------------------------------
	-- MECHA
	---------------------------------------------------------------
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
		local candidato = nil
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d:IsA("Model") and (d:GetAttribute("MechId") ~= nil or d:GetAttribute("CarryCapacity") ~= nil) and esMio(d) then
				if d:GetAttribute("MechId") ~= nil then
					return d
				end
				candidato = candidato or d
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
		S.mechCheck = ahora + REVISAR_MECHA
		return S.mech
	end

	-- Devuelve: total, capacidad, ligera, chatarra, máximo
	local function leerCarga(m)
		local cap = num(m:GetAttribute("CarryCapacity"), 16)
		return
			num(m:GetAttribute("CarryTotal"), 0),
			cap,
			num(m:GetAttribute("Carry_Light"), 0),
			num(m:GetAttribute("Carry_Scrap"), 0),
			num(m:GetAttribute("CarryMax"), cap)
	end

	-- La parte que se mueve: el asiento del mecha si pilotas, si no tu personaje
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
		local m = Workspace:FindFirstChild(BASE_MARCADOR)
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
	-- PILAS (solo World.Arenas.<nivel>.PartPiles)
	---------------------------------------------------------------
	-- Devuelve la lista de pilas (la más cercana primero) y si existe World.Arenas
	local function listarPilas()
		local lista = {}
		local arenas = ruta(Workspace, ARENAS)
		if not arenas then
			return lista, false
		end

		local origen = parteMovil()
		local origenPos = origen and origen.Position or Vector3.zero
		local ahora = os.clock()

		for li, nombreNivel in ipairs(LEVELS) do
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
									nombre = PILE_LABELS[ti],
									dist = (pos - origenPos).Magnitude,
								})
							end
						end
					end
				end
			end
		end

		table.sort(lista, function(a, b)
			return a.dist < b.dist
		end)
		return lista, true
	end

	-- Activa el ProximityPrompt. Devuelve false si tu ejecutor no tiene la función
	local function activarPrompt(prompt)
		if not firePrompt then
			return false
		end
		pcall(function()
			prompt.RequiresLineOfSight = false
			if prompt.MaxActivationDistance < RANGO_PROMPT then
				prompt.MaxActivationDistance = RANGO_PROMPT
			end
		end)
		pcall(firePrompt, prompt)
		return true
	end

	-- Va a la pila, la activa y espera a que suba la carga. Devuelve ok, motivo
	local function recolectar(p, mech)
		if not glideTo(p.pos + Vector3.new(0, ALTURA, 0), LLEGADA) then
			return false, "no llegué"
		end
		if not S.on then
			return false, "parado"
		end
		if not activarPrompt(p.prompt) then
			return false, "tu Delta no tiene fireproximityprompt"
		end

		local antes = leerCarga(mech)
		local t0 = os.clock()
		while S.on and os.clock() - t0 < ESPERA_CARGA do
			task.wait(0.1)
			if not p.prompt.Parent then
				return true
			end
			if leerCarga(mech) > antes then
				cooldown[p.prompt] = os.clock() + COOLDOWN_OK
				return true
			end
		end

		cooldown[p.prompt] = os.clock() + COOLDOWN_FALLO
		return false, "la carga no subió"
	end

	---------------------------------------------------------------
	-- TEXTOS
	---------------------------------------------------------------
	local function setEstado(texto, color)
		if ui.estado then
			ui.estado.Text = texto
			ui.estado.TextColor3 = color or C.sub
		end
	end

	local msgId = 0
	local function setMsg(texto, color)
		msgId = msgId + 1
		local my = msgId
		if ui.msg then
			ui.msg.Text = texto
			ui.msg.TextColor3 = color or C.sub
		end
		task.delay(3, function()
			if my == msgId and ui.msg then
				ui.msg.Text = ""
			end
		end)
	end

	local function refreshUI()
		if S.closed or not ui.carry then return end

		ui.carry.Text = S.total .. " / " .. S.cap
		local r = math.clamp(S.total / math.max(S.cap, 1), 0, 1)
		ui.fill.Size = UDim2.new(r, 0, 1, 0)
		ui.fill.BackgroundColor3 = (r >= 1 and C.red) or (r >= 0.7 and C.amber) or C.green

		ui.sub.Text = "Ligera " .. S.ligero .. "  ·  Chatarra " .. S.chatarra .. "  ·  Máx " .. S.max
		ui.auto.Text = S.on and "■  DETENER" or "▶  AUTO RECOLECTAR"
		ui.auto.BackgroundColor3 = S.on and C.red or C.green
		ui.bubble.BackgroundColor3 = S.on and C.green or C.accent

		ui.level.Text = (S.levelIdx == 0) and "Todos los niveles" or LEVEL_LABELS[S.levelIdx]

		for i, b in ipairs(ui.piles) do
			b.BackgroundColor3 = S.pileOn[i] and C.accent or C.btn
			b.TextColor3 = S.pileOn[i] and C.dark or C.text
		end

		ui.vel.Text = tostring(S.vel)

		if S.mech then
			local id = tostring(S.mech:GetAttribute("MechId") or S.mech.Name)
			local pilot = tostring(S.mech:GetAttribute("PilotMode") or "—")
			ui.mech.Text = id .. "  ·  " .. pilot
		else
			ui.mech.Text = "Sin mecha detectado"
		end

		local tieneBase = (S.base ~= nil) or (getBase() ~= nil)
		if S.base then
			ui.base.Text = "Base: guardada aquí"
		elseif tieneBase then
			ui.base.Text = "Base: marcador del mapa"
		else
			ui.base.Text = "Base: ✖ sin base"
		end
	end

	---------------------------------------------------------------
	-- CICLO AUTOMÁTICO
	---------------------------------------------------------------
	local function autoStep()
		local mech = getMech()
		if not mech then
			setEstado("Sin mecha", C.red)
			task.wait(1.5)
			return
		end
		if not parteMovil() then
			setEstado("Esperando personaje", C.sub)
			task.wait(1)
			return
		end

		local total, cap, lig, chat, max = leerCarga(mech)
		S.total, S.cap, S.ligero, S.chatarra, S.max = total, cap, lig, chat, max

		-- LLENO: volver a la base y esperar a que baje la carga
		if total >= cap then
			local base = getBase()
			if not base then
				setEstado("Lleno · guarda tu base", C.red)
				task.wait(2)
				return
			end
			setEstado("Lleno · vuelvo a la base", C.amber)
			if glideTo(base + Vector3.new(0, ALTURA, 0), LLEGADA) then
				setEstado("Descargando...", C.amber)
				local t0 = os.clock()
				while S.on and os.clock() - t0 < ESPERA_DESCARGA do
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
			setEstado("No encuentro World.Arenas", C.red)
			task.wait(2)
			return
		end

		local p = lista[1]
		if not p then
			setEstado("Sin pilas en la selección", C.cyan)
			task.wait(1.5)
			return
		end

		setEstado("Yendo a " .. p.nombre, C.green)
		local ok, motivo = recolectar(p, mech)
		if ok then
			setMsg("✅ " .. p.nombre .. " recogida", C.green)
		elseif motivo == "parado" then
			setEstado("Parado", C.sub)
		else
			setMsg("⚠ " .. p.nombre .. ": " .. tostring(motivo), C.amber)
		end
	end

	local function setAuto(v)
		S.on = v
		setEstado(v and "Iniciando" or "Parado", v and C.green or C.sub)
		refreshUI()
	end

	---------------------------------------------------------------
	-- INTERFAZ
	---------------------------------------------------------------
	local function corner(obj, r)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, r)
		c.Parent = obj
	end

	local function stroke(obj, color, transparency, thickness)
		local s = Instance.new("UIStroke")
		s.Color = color
		s.Transparency = transparency or 0
		s.Thickness = thickness or 1
		s.Parent = obj
	end

	local function btn(parent, text, size, color, textSize)
		local b = Instance.new("TextButton")
		b.Size = size
		b.BackgroundColor3 = color or C.btn
		b.BorderSizePixel = 0
		b.Text = text
		b.TextColor3 = C.text
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
		l.TextColor3 = color or C.text
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
		f.BackgroundColor3 = C.card
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

	local screen = Instance.new("ScreenGui")
	screen.Name = GUI_NAME
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 999998

	local old = PlayerGui:FindFirstChild(GUI_NAME)
	if old then old:Destroy() end
	screen.Parent = PlayerGui

	-- Panel
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
	panel.BackgroundColor3 = C.bg
	panel.BorderSizePixel = 0
	panel.ClipsDescendants = true
	panel.Parent = screen
	corner(panel, 12)
	stroke(panel, C.accent, 0.5, 1)
	ui.panel = panel
	ui.panelScale = Instance.new("UIScale")
	ui.panelScale.Parent = panel

	-- Cabecera (zona para arrastrar)
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 38)
	header.BackgroundTransparency = 1
	header.Active = true
	header.Parent = panel

	lbl(header, "MECHA PANEL", UDim2.new(1, -80, 1, 0), UDim2.fromOffset(10, 0), 12, C.accent, Enum.Font.GothamBold)
	local minBtn = btn(header, "–", UDim2.fromOffset(28, 28), C.btn, 15)
	minBtn.Position = UDim2.new(1, -64, 0, 5)
	local closeBtn = btn(header, "✕", UDim2.fromOffset(28, 28), C.btn, 12)
	closeBtn.Position = UDim2.new(1, -32, 0, 5)
	closeBtn.TextColor3 = C.red

	-- Contenido desplazable
	local body = Instance.new("ScrollingFrame")
	body.Position = UDim2.fromOffset(8, 42)
	body.Size = UDim2.new(1, -16, 1, -50)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.ScrollBarThickness = 2
	body.ScrollBarImageColor3 = C.accent
	body.CanvasSize = UDim2.new()
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.Parent = panel

	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.Padding = UDim.new(0, 6)
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLayout.Parent = body

	-- 1) Carga
	local carga = card(body, 1, 66)
	lbl(carga, "CARGA", UDim2.new(0.5, 0, 0, 12), UDim2.fromOffset(10, 6), 9, C.sub, Enum.Font.GothamBold)
	ui.estado = lbl(carga, "Parado", UDim2.new(0.5, -10, 0, 12), UDim2.new(0.5, 0, 0, 6), 9, C.sub, Enum.Font.GothamBold)
	ui.estado.TextXAlignment = Enum.TextXAlignment.Right
	ui.carry = lbl(carga, "0 / 16", UDim2.new(1, -20, 0, 24), UDim2.fromOffset(10, 18), 19, C.green, Enum.Font.GothamBlack)

	local track = Instance.new("Frame")
	track.Position = UDim2.fromOffset(10, 45)
	track.Size = UDim2.new(1, -20, 0, 6)
	track.BackgroundColor3 = C.track
	track.BorderSizePixel = 0
	track.Parent = carga
	corner(track, 3)

	ui.fill = Instance.new("Frame")
	ui.fill.Size = UDim2.new(0, 0, 1, 0)
	ui.fill.BackgroundColor3 = C.green
	ui.fill.BorderSizePixel = 0
	ui.fill.Parent = track
	corner(ui.fill, 3)

	ui.sub = lbl(carga, "", UDim2.new(1, -20, 0, 12), UDim2.fromOffset(10, 52), 9, C.sub, Enum.Font.Gotham)

	-- 2) Botón principal
	ui.auto = btn(body, "▶  AUTO RECOLECTAR", UDim2.new(1, 0, 0, 40), C.green, 13)
	ui.auto.LayoutOrder = 2
	ui.auto.TextColor3 = C.white
	ui.auto.Activated:Connect(function()
		setAuto(not S.on)
	end)

	-- 3) Nivel
	local nivelTitulo = lbl(body, "NIVEL", UDim2.new(1, 0, 0, 14), nil, 9, C.sub, Enum.Font.GothamBold)
	nivelTitulo.LayoutOrder = 3

	local nivelRow = hRow(body, 4, 34)
	local prevBtn = btn(nivelRow, "◀", UDim2.fromOffset(40, 34), C.btn, 14)
	prevBtn.LayoutOrder = 1
	ui.level = btn(nivelRow, "", UDim2.new(1, -88, 1, 0), C.card, 12)
	ui.level.LayoutOrder = 2
	local nextBtn = btn(nivelRow, "▶", UDim2.fromOffset(40, 34), C.btn, 14)
	nextBtn.LayoutOrder = 3

	prevBtn.Activated:Connect(function()
		S.levelIdx = S.levelIdx - 1
		if S.levelIdx < 0 then S.levelIdx = #LEVELS end
		refreshUI()
	end)
	nextBtn.Activated:Connect(function()
		S.levelIdx = S.levelIdx + 1
		if S.levelIdx > #LEVELS then S.levelIdx = 0 end
		refreshUI()
	end)
	ui.level.Activated:Connect(function()
		S.levelIdx = (S.levelIdx + 1) % (#LEVELS + 1)
		refreshUI()
	end)

	-- 4) Tipos de pila
	local pilasTitulo = lbl(body, "PILAS A RECOGER", UDim2.new(1, 0, 0, 14), nil, 9, C.sub, Enum.Font.GothamBold)
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

	for i, nombre in ipairs(PILE_LABELS) do
		local b = btn(grid, nombre, UDim2.fromOffset(54, 26), C.accent, 9)
		b.LayoutOrder = i
		b.Activated:Connect(function()
			S.pileOn[i] = not S.pileOn[i]
			refreshUI()
		end)
		ui.piles[i] = b
	end

	-- 5) Velocidad
	local velCard = card(body, 7, 38)
	lbl(velCard, "Vuelo", UDim2.new(0, 60, 1, 0), UDim2.fromOffset(10, 0), 11, C.sub, Enum.Font.GothamBold)
	local velMinus = btn(velCard, "−", UDim2.fromOffset(36, 28), C.btn, 16)
	velMinus.Position = UDim2.new(1, -116, 0.5, -14)
	ui.vel = lbl(velCard, "", UDim2.fromOffset(44, 28), UDim2.new(1, -78, 0.5, -14), 14, C.cyan, Enum.Font.GothamBlack)
	ui.vel.TextXAlignment = Enum.TextXAlignment.Center
	local velPlus = btn(velCard, "+", UDim2.fromOffset(36, 28), C.btn, 16)
	velPlus.Position = UDim2.new(1, -40, 0.5, -14)

	velMinus.Activated:Connect(function()
		S.vel = math.max(VEL_MIN, S.vel - VEL_STEP)
		refreshUI()
	end)
	velPlus.Activated:Connect(function()
		S.vel = math.min(VEL_MAX, S.vel + VEL_STEP)
		refreshUI()
	end)

	-- 6) Base
	local acciones = hRow(body, 8, 30)
	local baseBtn = btn(acciones, "📍 Guardar base", UDim2.new(0.5, -3, 1, 0), C.btn, 11)
	baseBtn.LayoutOrder = 1
	local limpiarBtn = btn(acciones, "↺ Borrar base", UDim2.new(0.5, -3, 1, 0), C.btn, 11)
	limpiarBtn.LayoutOrder = 2
	limpiarBtn.TextColor3 = C.red

	baseBtn.Activated:Connect(function()
		local part = parteMovil()
		if not part then
			setMsg("❌ Sin personaje", C.red)
			return
		end
		S.base = part.Position
		setMsg("✅ Base guardada aquí", C.green)
		refreshUI()
	end)
	limpiarBtn.Activated:Connect(function()
		S.base = nil
		setMsg("↺ Base borrada", C.amber)
		refreshUI()
	end)

	-- 7) Stats
	local statsBtn = btn(body, "📊 Ver stats del mecha (F9)", UDim2.new(1, 0, 0, 28), C.btn, 11)
	statsBtn.LayoutOrder = 9
	statsBtn.Activated:Connect(function()
		local mech = getMech()
		if not mech then
			setMsg("❌ No encuentro tu mecha", C.red)
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
		setMsg("✅ Stats impresos en F9", C.green)
	end)

	-- 8) Información
	ui.base = lbl(body, "", UDim2.new(1, 0, 0, 14), nil, 9, C.sub, Enum.Font.Gotham)
	ui.base.LayoutOrder = 10
	ui.base.TextXAlignment = Enum.TextXAlignment.Center

	ui.mech = lbl(body, "", UDim2.new(1, 0, 0, 14), nil, 9, C.sub, Enum.Font.Gotham)
	ui.mech.LayoutOrder = 11
	ui.mech.TextXAlignment = Enum.TextXAlignment.Center

	ui.msg = lbl(body, "", UDim2.new(1, 0, 0, 16), nil, 10, C.sub, Enum.Font.Gotham)
	ui.msg.LayoutOrder = 12
	ui.msg.TextXAlignment = Enum.TextXAlignment.Center

	-- Burbuja
	local bubble = Instance.new("TextButton")
	bubble.Name = "Bubble"
	bubble.Size = UDim2.fromOffset(BUBBLE, BUBBLE)
	bubble.BackgroundColor3 = C.accent
	bubble.BorderSizePixel = 0
	bubble.AutoButtonColor = false
	bubble.Text = "🤖"
	bubble.TextSize = 20
	bubble.Font = Enum.Font.GothamBold
	bubble.Visible = false
	bubble.ZIndex = 10
	bubble.Parent = screen
	corner(bubble, BUBBLE / 2)
	stroke(bubble, C.white, 0.4, 1.5)
	ui.bubble = bubble

	local function setMinimized(v)
		if v then
			local x, y = clampPos(panel.Position.X.Offset, panel.Position.Y.Offset, BUBBLE, BUBBLE)
			bubble.Position = UDim2.fromOffset(x, y)
		else
			local w = PANEL_W * ui.panelScale.Scale
			local h = PANEL_H * ui.panelScale.Scale
			local x, y = clampPos(bubble.Position.X.Offset, bubble.Position.Y.Offset, w, h)
			panel.Position = UDim2.fromOffset(x, y)
		end
		panel.Visible = not v
		bubble.Visible = v
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
		local w = PANEL_W * ui.panelScale.Scale
		local h = PANEL_H * ui.panelScale.Scale
		local x, y = clampPos(panel.Position.X.Offset, panel.Position.Y.Offset, w, h)
		panel.Position = UDim2.fromOffset(x, y)
	end)

	makeDrag(bubble, bubble,
		function() setMinimized(false) end,
		function()
			local x, y = clampPos(bubble.Position.X.Offset, bubble.Position.Y.Offset, BUBBLE, BUBBLE)
			bubble.Position = UDim2.fromOffset(x, y)
		end)

	-- Posición y escala según la pantalla
	local function layout()
		ui.panelScale.Scale = fitScale()
		local w = PANEL_W * ui.panelScale.Scale
		local h = PANEL_H * ui.panelScale.Scale
		local vp = viewport()

		if not S.placed then
			S.placed = true
			local x, y = clampPos((vp.X - w) / 2, vp.Y * 0.14, w, h)
			panel.Position = UDim2.fromOffset(x, y)
			bubble.Position = UDim2.fromOffset(vp.X - BUBBLE - 12, vp.Y * 0.45)
		else
			local x, y = clampPos(panel.Position.X.Offset, panel.Position.Y.Offset, w, h)
			panel.Position = UDim2.fromOffset(x, y)
		end
	end

	layout()
	local cam = Workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	end

	setEstado("Parado", C.sub)
	refreshUI()
	print("[MECHA] Panel creado correctamente")

	---------------------------------------------------------------
	-- BUCLES
	---------------------------------------------------------------
	-- Ciclo de recolección (solo cuando está encendido)
	task.spawn(function()
		while not S.closed do
			if S.on then
				local ok, err = pcall(autoStep)
				if not ok then
					setEstado("Error", C.red)
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
end

local okMain, errMain = pcall(main)
if not okMain then
	warn("[MECHA] Error: " .. tostring(errMain))
end
