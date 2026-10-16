-- CFly + Noclip + Combate + TP + Auto-cofres + Cristales + Curar (manual/automático) + Jefes StarRune
-- LocalScript en StarterPlayer > StarterPlayerScripts (reemplaza el anterior)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

---------------------------------------------------------------------
-- CONFIGURACIÓN
---------------------------------------------------------------------
local SPEED = 60
local VERTICAL_SPEED = 50
local UP_KEY = Enum.KeyCode.Space
local DOWN_KEY = Enum.KeyCode.LeftShift
local TOGGLE_KEY = Enum.KeyCode.F

-- Combate
local ENEMIES_FOLDER = "BADEnemies"
local DETECT_RANGE = 1000000000
local MELEE_RANGE = 15
local SAFE_DISTANCE = 70
local EVADE_SPEED = 90
local ATTACK_INTERVAL = 0.1
local WEAPON_NAME = "Dungeon Blade"
local USE_TOOL_ACTIVATE = true
local FIRE_REMOTE = true
local ATTACK_STEPS = {
	{ arg = 6, count = 1 },
	{ arg = 5, count = 1 },
	{ arg = 7, count = 1 },
	{ arg = nil, count = 1 },
}
local TP_DISTANCE = 6

-- Cofres
local CHEST_ROOT = "Labyrinth"
local CHEST_NAME = "Chest"
local CHEST_OFFSET_Y = 3
local CHEST_TP_DELAY = 0.15
local CHEST_MAX_TRIES = 3

-- Cristales
local CRYSTAL_NAME = "Crystals"
local CRYSTAL_TP_DISTANCE = 5
local CRYSTAL_ATTACK_INTERVAL = 0.1
local CRYSTAL_TIMEOUT = 15
local CRYSTAL_SKIP_TIME = 20

-- Curación (Fountain)
local FOUNTAIN_NAME = "Fountain"
local HEAL_THRESHOLD = 0.2           -- modo automático: se activa al 20% de vida
local HEAL_DONE = 0.95               -- modo automático: no regresa hasta llegar a 95%
local HEAL_POLL = 0.2
local HEAL_RETURN_DIST = 12          -- modo automático: si te alejas, vuelves a la fuente
local HEAL_COOLDOWN = 5
local PROMPT_STAND_OFFSET = Vector3.new(0, 2.5, 1.5)
local PROMPT_NEARBY_RANGE = 15

-- Jefes
local BOSS_NAME = "StarRune"
local BOSS_FALLBACK_HEIGHT = 4

-- Barra rectangular (más pequeña)
local BAR_W = 150
local BAR_H = 26

-- Botón de minimizar (pequeño)
local MENU_SIZE = 36

---------------------------------------------------------------------
-- ESTADO
---------------------------------------------------------------------
local running = true
local flying, noclip = false, false
local autoAttack, tpAttack, tpEnemy, keepDistance = false, false, false, false
local autoChest, chestBusy = false, false
local crystalFarm, crystalBusy = false, false
local chestsCollected, crystalsCollected = 0, 0
local combatMode = "melee"
local moveButtonsEnabled = false

local healMode = "off"               -- "off" | "manual" | "auto"
local healBusy = false
local healToken = 0
local savedHealCF = nil              -- posición guardada antes de ir a Fountain
local atFountain = false
local featureSnapshot = nil          -- qué opciones estaban activas antes de curar (manual)

local bossEntries, bossButtons = {}, {}
local featureToggles = {}            -- opciones de Combate/Farm que se apagan al curarse

local currentTarget
local attackToken, chestToken, crystalToken = 0, 0, 0
local wasAiming = false
local enemyCache = {}
local chestAttempts = {}
local crystalSkip = {}

local connection, flyAttachment, flyVelocity
local noclipConn
local originalCollide = {}
local allConnections = {}

local bar, healBtn, flyBtn, menuBubble, panel, panelW, panelFullH
local setFlyRow, toggleFly, setFlyVisual, setHealVisual, setHealModeVisual
local chestSub, crystalSub, statusLabel
local refreshBosses
local healModeButtons = {}

local function isBusy()
	return chestBusy or crystalBusy or healBusy
end

local function setStatus(text)
	if statusLabel then
		statusLabel.Text = text
	end
end

---------------------------------------------------------------------
-- TEMA / HELPERS
---------------------------------------------------------------------
local COLORS = {
	panel = Color3.fromRGB(20, 22, 34),
	row = Color3.fromRGB(32, 35, 51),
	rowOn = Color3.fromRGB(32, 52, 58),
	text = Color3.fromRGB(240, 242, 255),
	subtext = Color3.fromRGB(150, 155, 180),
	on = Color3.fromRGB(72, 220, 150),
	off = Color3.fromRGB(70, 74, 96),
	accentA = Color3.fromRGB(140, 90, 255),
	accentB = Color3.fromRGB(60, 190, 255),
	red = Color3.fromRGB(255, 95, 110),
	yellow = Color3.fromRGB(255, 200, 70),
	flyOff = Color3.fromRGB(200, 60, 80),
	flyOn = Color3.fromRGB(50, 200, 110),
	heal = Color3.fromRGB(60, 150, 255),
	healBack = Color3.fromRGB(255, 170, 60),
}

local function corner(obj, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = obj
	return c
end

local function tween(obj, props, t)
	TweenService:Create(
		obj,
		TweenInfo.new(t or 0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		props
	):Play()
end

local function track(conn)
	table.insert(allConnections, conn)
	return conn
end

local warned = {}
local function warnOnce(key, message)
	if not warned[key] then
		warned[key] = true
		warn("[CFly] " .. message)
	end
end

-- GUI base
local gui = Instance.new("ScreenGui")
gui.Name = "CFlyGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 10
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local EDGE = 8
local TOP_EDGE = 44

local function placeAt(obj, x, y)
	local screen = gui.AbsoluteSize
	if screen.X <= 0 or screen.Y <= 0 then return end
	local size = obj.AbsoluteSize
	local maxX = math.max(EDGE, screen.X - size.X - EDGE)
	local maxY = math.max(TOP_EDGE, screen.Y - size.Y - EDGE)
	x = math.clamp(x, EDGE, maxX)
	y = math.clamp(y, TOP_EDGE, maxY)
	obj.Position = UDim2.fromOffset(
		x + obj.AnchorPoint.X * size.X,
		y + obj.AnchorPoint.Y * size.Y
	)
end

local function clampToScreen(obj)
	local p = obj.AbsolutePosition
	placeAt(obj, p.X, p.Y)
end

-- Arrastra "target" desde "handle". Si no hay movimiento, cuenta como toque.
local function makeDraggable(handle, target, onTap)
	local dragging, moved = false, false
	local dragStart, startAbs, activeInput

	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			moved = false
			activeInput = input
			dragStart = input.Position
			startAbs = target.AbsolutePosition
		end
	end)

	track(UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input == activeInput or input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position - dragStart
			if moveButtonsEnabled and delta.Magnitude > 8 then
				moved = true
			end
			if moved then
				placeAt(target, startAbs.X + delta.X, startAbs.Y + delta.Y)
			end
		end
	end))

	track(UserInputService.InputEnded:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
			if not moved and onTap then
				onTap()
			end
		end
	end))
end

---------------------------------------------------------------------
-- PERSONAJE
---------------------------------------------------------------------
local function getParts()
	local char = player.Character
	if not char then return nil, nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	return hum, root
end

-- Mueve TODO el modelo del personaje (no solo la raíz) y frena las velocidades
local function teleportCharacter(cf)
	local char = player.Character
	if not char then return end
	char:PivotTo(cf)
	for _, p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") then
			p.AssemblyLinearVelocity = Vector3.zero
			p.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

---------------------------------------------------------------------
-- COMBATE
---------------------------------------------------------------------
local function attackOn()
	return autoAttack or tpAttack
end

local function getEquippedTool()
	local char = player.Character
	return char and char:FindFirstChildOfClass("Tool")
end

local function getAttackRemote()
	local bad = ReplicatedStorage:FindFirstChild("BAD")
	local remotes = bad and bad:FindFirstChild("Remotes")
	return remotes and remotes:FindFirstChild("Action")
end

local function equipWeapon()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return nil end

	local tool = char:FindFirstChild(WEAPON_NAME)
	if tool and tool:IsA("Tool") then
		return tool
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	local inBackpack = backpack and backpack:FindFirstChild(WEAPON_NAME)
	if inBackpack and inBackpack:IsA("Tool") then
		hum:EquipTool(inBackpack)
		return inBackpack
	end

	return getEquippedTool()
end

local function fireAttack()
	local tool = equipWeapon()

	if USE_TOOL_ACTIVATE and tool and tool.Parent == player.Character then
		tool:Activate()
	end

	if FIRE_REMOTE then
		local remote = getAttackRemote()
		if not remote then
			warnOnce("remote", "No encontré ReplicatedStorage.BAD.Remotes.Action")
			return
		end
		for _, step in ipairs(ATTACK_STEPS) do
			for _ = 1, step.count do
				remote:FireServer("attack", step.arg)
			end
		end
	end
end

local function refreshEnemies()
	local folder = workspace:FindFirstChild(ENEMIES_FOLDER)
	if not folder then
		warnOnce("folder", "No encontré workspace." .. ENEMIES_FOLDER)
		enemyCache = {}
		return
	end
	local list = {}
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("Humanoid") then
			table.insert(list, d)
		end
	end
	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") and not model:FindFirstChildOfClass("Humanoid") then
			table.insert(list, model)
		end
	end
	enemyCache = list
end

local function getEnemyPart(entry)
	if not entry or not entry.Parent then return nil end
	local model = entry
	if entry:IsA("Humanoid") then
		if entry.Health <= 0 then return nil end
		model = entry.Parent
	end
	if not model or not model.Parent then return nil end
	return model:FindFirstChild("HumanoidRootPart")
		or (model:IsA("Model") and model.PrimaryPart)
		or model:FindFirstChildWhichIsA("BasePart", true)
end

local function findNearestEnemy()
	local _, root = getParts()
	if not root then return nil end

	local best, bestDist = nil, DETECT_RANGE
	for _, entry in ipairs(enemyCache) do
		local part = getEnemyPart(entry)
		if part then
			local d = (part.Position - root.Position).Magnitude
			if d < bestDist then
				best, bestDist = part, d
			end
		end
	end
	return best
end

local function getEvadeVector()
	if not keepDistance or combatMode ~= "ranged" or isBusy() then return nil end
	local _, root = getParts()
	if not root then return nil end

	local sum = Vector3.zero
	for _, entry in ipairs(enemyCache) do
		local part = getEnemyPart(entry)
		if part then
			local offset = root.Position - part.Position
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local d = flat.Magnitude
			if d < SAFE_DISTANCE then
				local dir = d > 0.01 and flat.Unit or Vector3.new(0, 0, 1)
				local weight = 0.35 + 0.65 * (1 - d / SAFE_DISTANCE)
				sum = sum + dir * weight
			end
		end
	end
	if sum.Magnitude < 0.01 then return nil end
	return sum.Unit
end

task.spawn(function()
	while running do
		if attackOn() or keepDistance or tpEnemy then
			refreshEnemies()
		end
		task.wait(0.25)
	end
end)

track(RunService.Heartbeat:Connect(function()
	if attackOn() or keepDistance or tpEnemy then
		currentTarget = findNearestEnemy()
	else
		currentTarget = nil
	end
end))

RunService:BindToRenderStep("CFlyCombat", Enum.RenderPriority.Input.Value + 1, function()
	local hum, root = getParts()
	if not hum or not root or flying or isBusy() then return end

	local evade = getEvadeVector()
	if evade then
		hum:Move(evade, false)
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(evade.X * EVADE_SPEED, v.Y, evade.Z * EVADE_SPEED)
	end

	local aiming = attackOn() and currentTarget ~= nil and currentTarget.Parent ~= nil
	if aiming then
		hum.AutoRotate = false
		wasAiming = true
		local p = currentTarget.Position
		local from = root.Position
		root.CFrame = CFrame.lookAt(from, Vector3.new(p.X, from.Y, p.Z))
	elseif wasAiming then
		hum.AutoRotate = true
		wasAiming = false
	end
end)

RunService:BindToRenderStep("CFlyTeleport", Enum.RenderPriority.Last.Value, function()
	if not (tpEnemy or tpAttack) or isBusy() then return end
	local hum, root = getParts()
	if not hum or not root then return end
	if not currentTarget or not currentTarget.Parent then return end

	local targetPos = currentTarget.Position
	local offset = root.Position - targetPos
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local away = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(0, 0, 1)

	local dest = targetPos + away * TP_DISTANCE
	root.CFrame = CFrame.lookAt(dest, Vector3.new(targetPos.X, dest.Y, targetPos.Z))
	root.AssemblyLinearVelocity = Vector3.zero
end)

local function startAttackLoop()
	attackToken += 1
	local token = attackToken
	task.spawn(function()
		while running and attackOn() and token == attackToken do
			local _, root = getParts()
			if root and currentTarget and currentTarget.Parent and not isBusy() then
				local dist = (currentTarget.Position - root.Position).Magnitude
				if combatMode == "ranged" or dist <= MELEE_RANGE then
					fireAttack()
				end
			end
			task.wait(ATTACK_INTERVAL)
		end
	end)
end

local function setAutoAttack(state)
	autoAttack = state
	if attackOn() then
		refreshEnemies()
		startAttackLoop()
	end
end

local function setTpAttack(state)
	tpAttack = state
	if attackOn() then
		refreshEnemies()
		startAttackLoop()
	end
end

local function setTpEnemy(state)
	tpEnemy = state
	if state then refreshEnemies() end
end

local function setKeepDistance(state)
	keepDistance = state
	if state then refreshEnemies() end
end

---------------------------------------------------------------------
-- PROMPTS (helpers compartidos)
---------------------------------------------------------------------
local function promptPosition(prompt)
	local par = prompt.Parent
	if not par then return nil end
	if par:IsA("Attachment") then
		return par.WorldPosition
	elseif par:IsA("BasePart") then
		return par.Position
	elseif par:IsA("Model") then
		return par:GetPivot().Position
	end
	local m = par:FindFirstAncestorOfClass("Model")
	return m and m:GetPivot().Position or nil
end

local function getPosition(obj)
	if obj:IsA("BasePart") then
		return obj.Position
	elseif obj:IsA("Model") then
		return obj:GetPivot().Position
	elseif obj:IsA("Attachment") then
		return obj.WorldPosition
	end
	local part = obj:FindFirstChildWhichIsA("BasePart", true)
	return part and part.Position or nil
end

local function findPromptIn(inst)
	if inst:IsA("ProximityPrompt") then return inst end
	return inst:FindFirstChildWhichIsA("ProximityPrompt", true)
end

-- Prompt dentro del objeto o, si no hay, el más cercano dentro del rango
local function findPromptFor(inst)
	local inside = findPromptIn(inst)
	if inside then return inside end

	local pos = getPosition(inst)
	if not pos then return nil end
	local closest, closestD
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			local pp = promptPosition(d)
			if pp then
				local dist = (pp - pos).Magnitude
				if dist <= PROMPT_NEARBY_RANGE and (not closestD or dist < closestD) then
					closest, closestD = d, dist
				end
			end
		end
	end
	return closest
end

-- CFrame desde el que el jugador puede usar el prompt
local function standCFrameFor(prompt)
	local pos = promptPosition(prompt)
	if not pos then return nil end
	local dest = pos + PROMPT_STAND_OFFSET
	return CFrame.lookAt(dest, Vector3.new(pos.X, dest.Y, pos.Z)), pos
end

---------------------------------------------------------------------
-- AUTO-COFRES
---------------------------------------------------------------------
local function getChestPrompts()
	local root = workspace:FindFirstChild(CHEST_ROOT)
	if not root then
		warnOnce("chestroot", "No encontré workspace." .. CHEST_ROOT)
		return {}
	end
	local list = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Enabled and d:FindFirstAncestor(CHEST_NAME) then
			table.insert(list, d)
		end
	end
	return list
end

local function collectChest(prompt)
	local _, root = getParts()
	if not root then return end
	local pos = promptPosition(prompt)
	if not pos then return end

	pcall(function()
		prompt.RequiresLineOfSight = false
		if prompt.MaxActivationDistance < 12 then
			prompt.MaxActivationDistance = 12
		end
	end)

	teleportCharacter(CFrame.new(pos + Vector3.new(0, CHEST_OFFSET_Y, 0)))
	task.wait(CHEST_TP_DELAY)

	if prompt.Parent and prompt.Enabled then
		pcall(function() prompt:InputHoldBegin() end)
		task.wait(math.max(prompt.HoldDuration, 0) + 0.2)
		pcall(function() prompt:InputHoldEnd() end)
	end
end

local function startChestLoop()
	chestToken += 1
	local token = chestToken
	task.spawn(function()
		local lastReset = os.clock()
		while running and autoChest and token == chestToken do
			local hum, root = getParts()
			if hum and root and hum.Health > 0 and not crystalBusy and not healBusy then
				local best, bestD
				for _, p in ipairs(getChestPrompts()) do
					if (chestAttempts[p] or 0) < CHEST_MAX_TRIES then
						local pos = promptPosition(p)
						if pos then
							local d = (pos - root.Position).Magnitude
							if not bestD or d < bestD then
								best, bestD = p, d
							end
						end
					end
				end

				if best then
					chestBusy = true
					pcall(collectChest, best)
					chestAttempts[best] = (chestAttempts[best] or 0) + 1
					if not best.Parent or not best.Enabled then
						chestsCollected += 1
						if chestSub then
							chestSub.Text = "Cofres recogidos: " .. chestsCollected
						end
					end
					chestBusy = false
				else
					if os.clock() - lastReset > 10 then
						chestAttempts = {}
						lastReset = os.clock()
					end
					task.wait(0.8)
				end
			end
			task.wait(0.15)
		end
		if token == chestToken then
			chestBusy = false
		end
	end)
end

local function setAutoChest(state)
	autoChest = state
	chestToken += 1
	if state then
		chestAttempts = {}
		startChestLoop()
	else
		chestBusy = false
	end
end

---------------------------------------------------------------------
-- CRISTALES
---------------------------------------------------------------------
local function getCrystalModels()
	local list = {}
	for _, m in ipairs(workspace:GetDescendants()) do
		if m:IsA("Model") and m.Name == CRYSTAL_NAME and m.Parent then
			table.insert(list, m)
		end
	end
	return list
end

local function crystalAlive(m)
	if not m or not m.Parent then return false end
	local hum = m:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health <= 0 then return false end
	return true
end

local function teleportNearCrystal(model)
	local _, root = getParts()
	if not root then return end
	local pos = model:GetPivot().Position
	local offset = root.Position - pos
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local away = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(0, 0, 1)
	local dest = pos + away * CRYSTAL_TP_DISTANCE + Vector3.new(0, 1.5, 0)
	teleportCharacter(CFrame.lookAt(dest, Vector3.new(pos.X, dest.Y, pos.Z)))
end

local function farmCrystal(model)
	local startT = os.clock()
	while running and crystalFarm and crystalAlive(model) and os.clock() - startT < CRYSTAL_TIMEOUT do
		local hum, root = getParts()
		if hum and root and hum.Health > 0 and not healBusy then
			teleportNearCrystal(model)
			fireAttack()
		end
		task.wait(CRYSTAL_ATTACK_INTERVAL)
	end
end

local function updateCrystalLabel()
	if crystalSub then
		crystalSub.Text = "Cristales rotos: " .. crystalsCollected
	end
end

local function startCrystalLoop()
	crystalToken += 1
	local token = crystalToken
	task.spawn(function()
		while running and crystalFarm and token == crystalToken do
			local hum, root = getParts()
			if hum and root and hum.Health > 0 and not healBusy then
				local best, bestD
				local now = os.clock()
				for _, m in ipairs(getCrystalModels()) do
					if not crystalSkip[m] or now > crystalSkip[m] then
						local d = (m:GetPivot().Position - root.Position).Magnitude
						if not bestD or d < bestD then
							best, bestD = m, d
						end
					end
				end

				if best then
					crystalBusy = true
					pcall(farmCrystal, best)
					if not crystalAlive(best) then
						crystalsCollected += 1
						updateCrystalLabel()
					else
						crystalSkip[best] = os.clock() + CRYSTAL_SKIP_TIME
					end
					crystalBusy = false
				else
					task.wait(1)
				end
			else
				task.wait(0.5)
			end
			task.wait(0.05)
		end
		crystalBusy = false
	end)
end

local function setCrystalFarm(state)
	crystalFarm = state
	crystalToken += 1
	if state then
		crystalSkip = {}
		startCrystalLoop()
	else
		crystalBusy = false
	end
end

---------------------------------------------------------------------
-- APAGAR / RESTAURAR OPCIONES AL CURARSE (modo manual)
---------------------------------------------------------------------
local function registerFeature(name, setFn, getFn)
	table.insert(featureToggles, { name = name, set = setFn, get = getFn })
end

-- Apaga todo lo de Combate y Farm que esté activo y guarda cuáles eran
local function disableFeatures()
	featureSnapshot = {}
	for _, f in ipairs(featureToggles) do
		if f.get() then
			featureSnapshot[f.name] = true
			f.set(false)
		end
	end
end

-- Vuelve a activar solo las que estaban encendidas antes
local function restoreFeatures()
	if not featureSnapshot then return end
	local snap = featureSnapshot
	featureSnapshot = nil
	for _, f in ipairs(featureToggles) do
		if snap[f.name] then
			f.set(true)
		end
	end
end

---------------------------------------------------------------------
-- CURACIÓN EN FOUNTAIN (manual y automática)
---------------------------------------------------------------------
local function findFountain()
	local found
	for _, d in ipairs(workspace:GetDescendants()) do
		if d.Name == FOUNTAIN_NAME and (d:IsA("BasePart") or d:IsA("Model")) then
			local prompt = findPromptIn(d)
			if prompt then
				return d, prompt
			end
			found = found or d
		end
	end

	if found then
		local pos = getPosition(found)
		local closest, closestD
		if pos then
			for _, p in ipairs(workspace:GetDescendants()) do
				if p:IsA("ProximityPrompt") then
					local pp = promptPosition(p)
					if pp then
						local dist = (pp - pos).Magnitude
						if dist < PROMPT_NEARBY_RANGE and (not closestD or dist < closestD) then
							closest, closestD = p, dist
						end
					end
				end
			end
		end
		return found, closest
	end
	return nil, nil
end

-- Lleva al personaje a la fuente y guarda su posición anterior
local function moveToFountain()
	local _, root = getParts()
	if not root then return false end

	local fountain, prompt = findFountain()
	if not fountain then
		setStatus("No encontré Fountain")
		return false
	end

	local cf
	if prompt then
		cf = standCFrameFor(prompt)
	end
	if not cf then
		local pos = getPosition(fountain)
		if not pos then
			setStatus("Fountain no tiene posición")
			return false
		end
		cf = CFrame.new(pos + PROMPT_STAND_OFFSET)
	end

	if not atFountain then
		savedHealCF = root.CFrame
	end
	teleportCharacter(cf)
	atFountain = true
	return true, fountain, prompt
end

local function returnFromFountain()
	if savedHealCF then
		teleportCharacter(savedHealCF)
		savedHealCF = nil
	end
	atFountain = false
	setHealVisual(false)
	restoreFeatures()
end

-- Botón manual: 1ª vez va a Fountain (y apaga lo de combate/farm), 2ª vez vuelve
local function onManualHealTap()
	if atFountain then
		returnFromFountain()
		setStatus("Regresaste a tu posición guardada.")
	else
		local ok = moveToFountain()
		if ok then
			disableFeatures()
			setHealVisual(true)
			setStatus("En Fountain. Activa el prompt; con ↩ Volver regresas.")
		end
	end
end

-- Automático: al bajar del 20% va a la fuente, espera a 95% y regresa
local function runAutoHeal()
	if healBusy or atFountain then return end
	local hum, root = getParts()
	if not hum or not root or hum.Health <= 0 then return end

	local ok, fountain, prompt = moveToFountain()
	if not ok then return end

	healBusy = true
	healToken += 1
	local token = healToken
	setHealVisual(true)
	setStatus("Curando automáticamente...")

	local fpos = getPosition(fountain)
	if prompt then fpos = promptPosition(prompt) or fpos end

	while running and healMode == "auto" and token == healToken do
		local h, r = getParts()
		if not h or not r or h.Health <= 0 then break end
		if h.Health >= h.MaxHealth * HEAL_DONE then break end

		-- Si te devolvieron sin curarte, vuelves a la fuente
		if fpos and (r.Position - fpos).Magnitude > HEAL_RETURN_DIST then
			local cf = prompt and standCFrameFor(prompt)
			teleportCharacter(cf or CFrame.new(fpos + PROMPT_STAND_OFFSET))
		end

		if prompt and prompt.Parent and prompt.Enabled then
			pcall(function() prompt.RequiresLineOfSight = false end)
			if typeof(fireproximityprompt) == "function" then
				pcall(fireproximityprompt, prompt)
			else
				pcall(function() prompt:InputHoldBegin() end)
				task.wait(math.max(prompt.HoldDuration, 0) + 0.3)
				pcall(function() prompt:InputHoldEnd() end)
			end
		end
		task.wait(HEAL_POLL)
	end

	if token == healToken then
		local h, r = getParts()
		if healMode == "auto" and h and r and h.Health > 0 and h.Health >= h.MaxHealth * HEAL_DONE then
			returnFromFountain()
			setStatus("Curado. Regresaste a tu posición.")
		elseif not (h and h.Health > 0) then
			savedHealCF = nil
			atFountain = false
		end
		healBusy = false
	end
end

local autoWatcherRunning = false
local function startAutoWatcher()
	if autoWatcherRunning then return end
	autoWatcherRunning = true
	task.spawn(function()
		while running do
			if healMode == "auto" and not healBusy and not atFountain then
				local hum = getParts()
				if hum and hum.Health > 0 and hum.Health <= hum.MaxHealth * HEAL_THRESHOLD then
					runAutoHeal()
					task.wait(HEAL_COOLDOWN)
				end
			end
			task.wait(0.2)
		end
		autoWatcherRunning = false
	end)
end

-- Cambia el modo: "manual", "auto" o "off"
local function setHealModeOption(mode)
	if healMode == mode then return end

	-- Si estabas en Fountain, regresa antes de cambiar de modo
	if atFountain then
		returnFromFountain()
	end

	healMode = mode

	for key, b in pairs(healModeButtons) do
		local active = key == mode
		tween(b, { BackgroundColor3 = active and COLORS.accentA or COLORS.off })
		b.TextColor3 = active and Color3.new(1, 1, 1) or COLORS.subtext
	end

	if mode == "off" then
		healBusy = false
		healToken += 1
	end
	setHealModeVisual()
	startAutoWatcher()
end

---------------------------------------------------------------------
-- JEFES (StarRune)
---------------------------------------------------------------------
local function normalizeName(s)
	return string.lower((string.gsub(s, "%s+", "")))
end

local function isBossName(name)
	local pattern = "^" .. string.lower(BOSS_NAME) .. "%d*$"
	return string.match(normalizeName(name), pattern) ~= nil
end

local function getStarRunes()
	local found, seen = {}, {}

	local function scan(root)
		for _, d in ipairs(root:GetDescendants()) do
			if not seen[d] and isBossName(d.Name) then
				seen[d] = true
				local nested = false
				local anc = d.Parent
				while anc and anc ~= game do
					if seen[anc] then
						nested = true
						break
					end
					anc = anc.Parent
				end
				if not nested then
					table.insert(found, d)
				end
			end
		end
	end

	scan(workspace)
	if #found == 0 then
		scan(ReplicatedStorage)
		scan(Lighting)
	end
	return found
end

local function fightBoss(index)
	local inst = bossEntries[index]
	if not inst or not inst.Parent then
		refreshBosses()
		inst = bossEntries[index]
		if not inst then
			setStatus("Jefe " .. index .. " no encontrado. Pulsa Buscar jefes.")
			return
		end
	end

	local prompt = findPromptFor(inst)
	if prompt then
		local cf = standCFrameFor(prompt)
		if cf then
			teleportCharacter(cf)
			setStatus("Jefe " .. index .. ": activa su prompt manualmente.")
			return
		end
	end

	local pos = getPosition(inst)
	if not pos then
		setStatus("Jefe " .. index .. " no tiene posición")
		return
	end
	teleportCharacter(CFrame.new(pos + Vector3.new(0, BOSS_FALLBACK_HEIGHT, 0)))
	setStatus("Jefe " .. index .. ": llegaste (sin prompt cercano).")
end

---------------------------------------------------------------------
-- VUELO (CFLY)
---------------------------------------------------------------------
setFlyVisual = function(on)
	if flyBtn then
		flyBtn.Text = on and "✈ ON" or "✈ OFF"
		tween(flyBtn, { BackgroundColor3 = on and COLORS.flyOn or COLORS.flyOff })
	end
end

setHealVisual = function(atF)
	if healBtn then
		healBtn.Text = atF and "↩ Volver" or "🏥 Curar"
		tween(healBtn, { BackgroundColor3 = atF and COLORS.healBack or COLORS.heal })
	end
end

-- Manual: barra dividida (Curar | FLY). Automático u off: solo FLY.
setHealModeVisual = function()
	if not healBtn then return end
	local manual = healMode == "manual"
	healBtn.Visible = manual
	flyBtn.Size = manual and UDim2.new(0.5, -5, 1, -6) or UDim2.new(1, -6, 1, -6)
	flyBtn.Position = manual and UDim2.new(0.5, 2, 0, 3) or UDim2.new(0, 3, 0, 3)
end

local function stopFly()
	flying = false
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if flyVelocity then
		flyVelocity:Destroy()
		flyVelocity = nil
	end
	if flyAttachment then
		flyAttachment:Destroy()
		flyAttachment = nil
	end
	local hum = getParts()
	if hum then
		hum.PlatformStand = false
	end
	setFlyVisual(false)
	if setFlyRow then setFlyRow(false, true) end
end

local function startFly()
	local hum, root = getParts()
	if not hum or not root then return end

	flying = true
	hum.PlatformStand = true

	flyAttachment = Instance.new("Attachment")
	flyAttachment.Name = "CFlyAttachment"
	flyAttachment.Parent = root

	flyVelocity = Instance.new("LinearVelocity")
	flyVelocity.Name = "CFlyVelocity"
	flyVelocity.Attachment0 = flyAttachment
	flyVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	flyVelocity.MaxForce = math.huge
	flyVelocity.VectorVelocity = Vector3.zero
	flyVelocity.Parent = root

	setFlyVisual(true)
	if setFlyRow then setFlyRow(true, true) end

	connection = RunService.RenderStepped:Connect(function(dt)
		local h, r = getParts()
		if not h or not r then return end

		if isBusy() then
			r.AssemblyLinearVelocity = Vector3.zero
			return
		end

		local camCF = camera.CFrame
		local look = camCF.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		local flatRight = Vector3.new(camCF.RightVector.X, 0, camCF.RightVector.Z)

		local move = h.MoveDirection
		local forward, side = 0, 0
		if flatLook.Magnitude > 0 then
			forward = move:Dot(flatLook.Unit)
		end
		if flatRight.Magnitude > 0 then
			side = move:Dot(flatRight.Unit)
		end

		local dir = Vector3.zero
		if flatRight.Magnitude > 0 then
			dir = (look * forward + flatRight.Unit * side) * SPEED
		end

		local evade = getEvadeVector()
		if evade then
			dir = dir + evade * EVADE_SPEED
		end

		local vertical = 0
		if UserInputService:IsKeyDown(UP_KEY) or h.Jump then
			vertical = VERTICAL_SPEED
		elseif UserInputService:IsKeyDown(DOWN_KEY) then
			vertical = -VERTICAL_SPEED
		end

		local velocity = dir + Vector3.new(0, vertical, 0)

		r.AssemblyLinearVelocity = Vector3.zero
		r.AssemblyAngularVelocity = Vector3.zero

		local pos = r.Position + velocity * dt

		local faceDir = flatLook
		if attackOn() and currentTarget and currentTarget.Parent then
			local d = currentTarget.Position - r.Position
			faceDir = Vector3.new(d.X, 0, d.Z)
		end
		if faceDir.Magnitude > 0 then
			r.CFrame = CFrame.lookAt(pos, pos + faceDir)
		else
			r.CFrame = CFrame.new(pos) * (r.CFrame - r.Position)
		end
	end)
end

toggleFly = function()
	if flying then
		stopFly()
	else
		startFly()
	end
end

---------------------------------------------------------------------
-- NOCLIP
---------------------------------------------------------------------
local function setNoclip(state)
	noclip = state
	if noclipConn then
		noclipConn:Disconnect()
		noclipConn = nil
	end

	if state then
		noclipConn = RunService.Stepped:Connect(function()
			local char = player.Character
			if not char then return end
			for _, part in ipairs(char:GetDescendants()) do
				if part:IsA("BasePart") then
					if originalCollide[part] == nil then
						originalCollide[part] = part.CanCollide
					end
					part.CanCollide = false
				end
			end
		end)
	else
		for part, original in pairs(originalCollide) do
			if part and part.Parent then
				part.CanCollide = original
			end
		end
		originalCollide = {}
	end
end

---------------------------------------------------------------------
-- CERRAR EL SCRIPT
---------------------------------------------------------------------
local function shutdown()
	running = false
	autoAttack, tpAttack, tpEnemy, keepDistance = false, false, false, false
	autoChest, crystalFarm = false, false
	chestBusy, crystalBusy, healBusy = false, false, false
	healMode = "off"
	savedHealCF = nil
	atFountain = false
	featureSnapshot = nil
	attackToken += 1
	chestToken += 1
	crystalToken += 1
	healToken += 1

	stopFly()
	setNoclip(false)

	pcall(function() RunService:UnbindFromRenderStep("CFlyCombat") end)
	pcall(function() RunService:UnbindFromRenderStep("CFlyTeleport") end)

	for _, c in ipairs(allConnections) do
		c:Disconnect()
	end
	table.clear(allConnections)

	local hum = getParts()
	if hum then
		hum.AutoRotate = true
	end

	gui:Destroy()
end

---------------------------------------------------------------------
-- BARRA RECTANGULAR (Curar | FLY)
---------------------------------------------------------------------
bar = Instance.new("Frame")
bar.Name = "CFlyBar"
bar.Size = UDim2.fromOffset(BAR_W, BAR_H)
bar.Position = UDim2.new(0.5, -BAR_W / 2, 0, 46)
bar.BackgroundColor3 = COLORS.panel
bar.BorderSizePixel = 0
bar.Parent = gui
corner(bar, UDim.new(0, 6))

local barStroke = Instance.new("UIStroke")
barStroke.Thickness = 1.2
barStroke.Color = Color3.new(1, 1, 1)
barStroke.Parent = bar

local barGrad = Instance.new("UIGradient")
barGrad.Color = ColorSequence.new(COLORS.accentA, COLORS.accentB)
barGrad.Rotation = 45
barGrad.Parent = barStroke

local function makeBarButton(text, color)
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Text = text
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 10
	b.AutoButtonColor = false
	b.Parent = bar
	corner(b, UDim.new(0, 4))
	return b
end

healBtn = makeBarButton("🏥 Curar", COLORS.heal)
healBtn.Size = UDim2.new(0.5, -5, 1, -6)
healBtn.Position = UDim2.new(0, 3, 0, 3)

flyBtn = makeBarButton("✈ OFF", COLORS.flyOff)

makeDraggable(healBtn, bar, function()
	if healMode == "manual" then
		onManualHealTap()
	end
end)
makeDraggable(flyBtn, bar, function() toggleFly() end)

---------------------------------------------------------------------
-- BURBUJA DE MINIMIZAR (pequeña, cuadrada)
---------------------------------------------------------------------
menuBubble = Instance.new("TextButton")
menuBubble.Name = "MenuBubble"
menuBubble.Size = UDim2.fromOffset(MENU_SIZE, MENU_SIZE)
menuBubble.Position = UDim2.fromOffset(20, 120)
menuBubble.BackgroundColor3 = COLORS.accentA
menuBubble.Text = "☰"
menuBubble.TextColor3 = Color3.new(1, 1, 1)
menuBubble.TextSize = 16
menuBubble.Font = Enum.Font.GothamBold
menuBubble.AutoButtonColor = false
menuBubble.Visible = false
menuBubble.Parent = gui
corner(menuBubble, UDim.new(0, 8))

local menuStroke = Instance.new("UIStroke")
menuStroke.Thickness = 1.5
menuStroke.Color = Color3.new(1, 1, 1)
menuStroke.Parent = menuBubble

---------------------------------------------------------------------
-- PANEL
---------------------------------------------------------------------
local PANEL_W = 300
local TITLE_H = 50
local TAB_H = 34
local FULL_H = 380
panelW, panelFullH = PANEL_W, FULL_H

panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.new(0.5, 0, 0, 100)
panel.Size = UDim2.fromOffset(PANEL_W, FULL_H)
panel.BackgroundColor3 = COLORS.panel
panel.BorderSizePixel = 0
panel.ClipsDescendants = true
panel.Parent = gui
corner(panel, UDim.new(0, 22))

local panelStroke = Instance.new("UIStroke")
panelStroke.Thickness = 2
panelStroke.Color = Color3.new(1, 1, 1)
panelStroke.Parent = panel

local strokeGradient = Instance.new("UIGradient")
strokeGradient.Color = ColorSequence.new(COLORS.accentA, COLORS.accentB)
strokeGradient.Rotation = 45
strokeGradient.Parent = panelStroke

local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, TITLE_H)
titleBar.BackgroundTransparency = 1
titleBar.Active = true
titleBar.Parent = panel

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(18, 0)
title.Size = UDim2.new(1, -120, 1, 0)
title.Text = "✈  CFly"
title.TextColor3 = COLORS.text
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextTruncate = Enum.TextTruncate.AtEnd
title.Parent = titleBar

local divider = Instance.new("Frame")
divider.Position = UDim2.new(0, 16, 0, TITLE_H)
divider.Size = UDim2.new(1, -32, 0, 2)
divider.BackgroundColor3 = Color3.new(1, 1, 1)
divider.BorderSizePixel = 0
divider.Parent = panel
corner(divider, UDim.new(1, 0))
local dividerGradient = Instance.new("UIGradient")
dividerGradient.Color = ColorSequence.new(COLORS.accentA, COLORS.accentB)
dividerGradient.Parent = divider

local function makeCircleButton(text, color, xOffset)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(30, 30)
	b.Position = UDim2.new(1, xOffset, 0, 10)
	b.BackgroundColor3 = color
	b.Text = text
	b.TextColor3 = Color3.fromRGB(30, 30, 40)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 15
	b.AutoButtonColor = true
	b.Parent = panel
	corner(b, UDim.new(1, 0))
	return b
end

local minBtn = makeCircleButton("−", COLORS.yellow, -76)
local closeBtn = makeCircleButton("✕", COLORS.red, -40)

-- Pestañas
local tabBar = Instance.new("Frame")
tabBar.Name = "Tabs"
tabBar.Position = UDim2.fromOffset(12, TITLE_H + 8)
tabBar.Size = UDim2.new(1, -24, 0, TAB_H)
tabBar.BackgroundTransparency = 1
tabBar.Parent = panel

local pagesHolder = Instance.new("Frame")
pagesHolder.Position = UDim2.fromOffset(12, TITLE_H + TAB_H + 18)
pagesHolder.Size = UDim2.new(1, -24, 1, -(TITLE_H + TAB_H + 26))
pagesHolder.BackgroundTransparency = 1
pagesHolder.Parent = panel

local pages, tabButtons = {}, {}

local function showTab(name)
	for key, page in pairs(pages) do
		page.Visible = key == name
	end
	for key, b in pairs(tabButtons) do
		local active = key == name
		tween(b, { BackgroundColor3 = active and COLORS.accentA or COLORS.off })
		b.TextColor3 = active and Color3.new(1, 1, 1) or COLORS.subtext
	end
end

local function makeTab(name, text, index)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0.25, -4, 1, 0)
	b.Position = UDim2.new(0.25 * (index - 1), 2, 0, 0)
	b.Text = text
	b.Font = Enum.Font.GothamBold
	b.TextSize = 12
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundColor3 = COLORS.off
	b.TextColor3 = COLORS.subtext
	b.Parent = tabBar
	corner(b, UDim.new(0, 10))
	b.Activated:Connect(function()
		showTab(name)
	end)
	tabButtons[name] = b

	local page = Instance.new("ScrollingFrame")
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.Size = UDim2.new(1, 0, 1, 0)
	page.CanvasSize = UDim2.new()
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.ScrollBarThickness = 3
	page.ScrollBarImageColor3 = COLORS.accentA
	page.Visible = false
	page.Parent = pagesHolder

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = page

	local pad = Instance.new("UIPadding")
	pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = page

	pages[name] = page
	return page
end

-- Fila con interruptor. Devuelve set, etiqueta de subtítulo y getter del estado.
local function createRow(page, order, titleText, subtitleText, initial, callback)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 56)
	row.BackgroundColor3 = COLORS.row
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.Parent = page
	corner(row, UDim.new(0, 14))

	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromOffset(14, 8)
	t.Size = UDim2.new(1, -92, 0, 20)
	t.Text = titleText
	t.TextColor3 = COLORS.text
	t.Font = Enum.Font.GothamBold
	t.TextSize = 14
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Parent = row

	local s = Instance.new("TextLabel")
	s.BackgroundTransparency = 1
	s.Position = UDim2.fromOffset(14, 29)
	s.Size = UDim2.new(1, -92, 0, 16)
	s.Text = subtitleText
	s.TextColor3 = COLORS.subtext
	s.Font = Enum.Font.Gotham
	s.TextSize = 11
	s.TextXAlignment = Enum.TextXAlignment.Left
	s.TextTruncate = Enum.TextTruncate.AtEnd
	s.Parent = row

	local sw = Instance.new("Frame")
	sw.Size = UDim2.fromOffset(50, 28)
	sw.Position = UDim2.new(1, -62, 0.5, -14)
	sw.BackgroundColor3 = COLORS.off
	sw.BorderSizePixel = 0
	sw.Parent = row
	corner(sw, UDim.new(1, 0))

	local knob = Instance.new("Frame")
	knob.Size = UDim2.fromOffset(22, 22)
	knob.Position = UDim2.new(0, 3, 0.5, -11)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BorderSizePixel = 0
	knob.Parent = sw
	corner(knob, UDim.new(1, 0))

	local hit = Instance.new("TextButton")
	hit.Size = UDim2.new(1, 0, 1, 0)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.ZIndex = 5
	hit.Parent = row

	local state = initial
	local function get()
		return state
	end
	local function set(value, silent)
		state = value
		tween(sw, { BackgroundColor3 = value and COLORS.on or COLORS.off })
		tween(row, { BackgroundColor3 = value and COLORS.rowOn or COLORS.row })
		tween(knob, { Position = value and UDim2.new(1, -25, 0.5, -11) or UDim2.new(0, 3, 0.5, -11) })
		if not silent and callback then
			callback(value)
		end
	end

	hit.Activated:Connect(function()
		set(not state)
	end)

	set(initial, true)
	return set, s, get
end

-- Botón de acción
local function createButtonRow(page, order, titleText, color, callback)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, 44)
	btn.BackgroundColor3 = color
	btn.Text = titleText
	btn.TextColor3 = Color3.fromRGB(30, 30, 40)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 14
	btn.AutoButtonColor = true
	btn.BorderSizePixel = 0
	btn.LayoutOrder = order
	btn.Parent = page
	corner(btn, UDim.new(0, 14))
	btn.Activated:Connect(callback)
	return btn
end

-- Selector de modo de curación: Apagado / Manual / Automático
local function createHealModeSelector(page, order)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 48)
	row.BackgroundColor3 = COLORS.row
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.Parent = page
	corner(row, UDim.new(0, 14))

	local function makeButton(mode, text, xScale)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1 / 3, -10, 0, 34)
		b.Position = UDim2.new(xScale, 5, 0.5, -17)
		b.Text = text
		b.Font = Enum.Font.GothamBold
		b.TextSize = 11
		b.AutoButtonColor = false
		b.BorderSizePixel = 0
		b.BackgroundColor3 = COLORS.off
		b.TextColor3 = COLORS.subtext
		b.Parent = row
		corner(b, UDim.new(0, 10))
		b.Activated:Connect(function()
			setHealModeOption(mode)
		end)
		healModeButtons[mode] = b
	end

	makeButton("off", "Apagado", 0)
	makeButton("manual", "Manual", 1 / 3)
	makeButton("auto", "Automático", 2 / 3)
	return row
end

-- Selector: cuerpo a cuerpo / a distancia
local function createModeSelector(page, order)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 48)
	row.BackgroundColor3 = COLORS.row
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.Parent = page
	corner(row, UDim.new(0, 14))

	local buttons = {}

	local function selectMode(mode)
		combatMode = mode
		for key, b in pairs(buttons) do
			local active = key == mode
			tween(b, { BackgroundColor3 = active and COLORS.accentA or COLORS.off })
			b.TextColor3 = active and Color3.new(1, 1, 1) or COLORS.subtext
		end
	end

	local function makeButton(mode, text, position)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0.5, -12, 0, 34)
		b.Position = position
		b.Text = text
		b.Font = Enum.Font.GothamBold
		b.TextSize = 12
		b.AutoButtonColor = false
		b.BorderSizePixel = 0
		b.BackgroundColor3 = COLORS.off
		b.Parent = row
		corner(b, UDim.new(0, 10))
		b.Activated:Connect(function()
			selectMode(mode)
		end)
		buttons[mode] = b
	end

	makeButton("melee", "⚔ Cuerpo a cuerpo", UDim2.new(0, 7, 0.5, -17))
	makeButton("ranged", "🏹 A distancia", UDim2.new(0.5, 5, 0.5, -17))
	selectMode(combatMode)
end

makeTab("move", "🏃 Mov", 1)
makeTab("combat", "⚔ Combate", 2)
makeTab("farm", "💎 Farm", 3)
makeTab("settings", "⚙ Ajustes", 4)

-- Página: Movimiento
local movePage = pages.move
createRow(movePage, 1, "Barra Curar / FLY", "Muestra u oculta la barra superior", true, function(value)
	bar.Visible = value
end)
setFlyRow = createRow(movePage, 2, "Volar (CFly)", "Sube y baja según tu mirada", false, function(value)
	if value ~= flying then
		toggleFly()
	end
end)
createRow(movePage, 3, "Atravesar paredes", "Noclip: pasa por todo", false, function(value)
	setNoclip(value)
end)

-- Página: Combate
local combatPage = pages.combat
createModeSelector(combatPage, 1)

local aaSet, _, aaGet = createRow(combatPage, 2, "Auto-ataque", "Apunta y ataca al más cercano", false, setAutoAttack)
registerFeature("autoAttack", aaSet, aaGet)

local tpaSet, _, tpaGet = createRow(combatPage, 3, "TP + Auto-ataque", "Va hasta el enemigo y ataca", false, setTpAttack)
registerFeature("tpAttack", tpaSet, tpaGet)

local tpeSet, _, tpeGet = createRow(combatPage, 4, "TP al enemigo", "Te lleva junto al más cercano", false, setTpEnemy)
registerFeature("tpEnemy", tpeSet, tpeGet)

local kdSet, _, kdGet = createRow(combatPage, 5, "Mantener distancia", "Esquiva rápido (modo a distancia)", false, setKeepDistance)
registerFeature("keepDistance", kdSet, kdGet)

-- Página: Farm
local farmPage = pages.farm
createHealModeSelector(farmPage, 0)

local chestSet, chestLabel, chestGet = createRow(farmPage, 1, "Auto-cofres", "Cofres recogidos: 0", false, setAutoChest)
chestSub = chestLabel
registerFeature("autoChest", chestSet, chestGet)

local crystalSet, crystalLabel, crystalGet = createRow(farmPage, 2, "Auto-cristales", "Cristales rotos: 0", false, setCrystalFarm)
crystalSub = crystalLabel
registerFeature("crystalFarm", crystalSet, crystalGet)

statusLabel = Instance.new("TextLabel")
statusLabel.Name = "StatusLabel"
statusLabel.BackgroundTransparency = 1
statusLabel.Size = UDim2.new(1, 0, 0, 30)
statusLabel.Text = "Buscando StarRunes..."
statusLabel.TextColor3 = COLORS.subtext
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 11
statusLabel.TextWrapped = true
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.LayoutOrder = 8
statusLabel.Parent = farmPage

refreshBosses = function()
	bossEntries = getStarRunes()
	for i = 1, #bossEntries do
		if not bossButtons[i] then
			bossButtons[i] = createButtonRow(farmPage, 10 + i, "Jefe " .. i, COLORS.accentB, function()
				fightBoss(i)
			end)
		end
		bossButtons[i].Visible = true
	end
	for i = #bossEntries + 1, #bossButtons do
		bossButtons[i].Visible = false
	end

	if #bossEntries > 0 then
		setStatus("StarRunes encontrados: " .. #bossEntries)
	else
		setStatus("No encontré StarRunes. Acércate a la zona y pulsa Buscar jefes.")
	end
end

createButtonRow(farmPage, 9, "🔄 Buscar jefes (StarRune)", COLORS.accentA, function()
	refreshBosses()
end)

task.spawn(function()
	for _ = 1, 15 do
		refreshBosses()
		if #bossEntries > 0 then break end
		task.wait(2)
	end
end)

-- Página: Ajustes
local settingsPage = pages.settings
createRow(settingsPage, 1, "Mover botones", "Actívalo para arrastrar la barra y el panel", false, function(value)
	moveButtonsEnabled = value
end)
createButtonRow(settingsPage, 2, "Cerrar script", COLORS.red, shutdown)

showTab("move")
setHealModeVisual()

---------------------------------------------------------------------
-- MINIMIZAR / RESTAURAR
---------------------------------------------------------------------
local function setMinimized(state)
	if state then
		local p = panel.AbsolutePosition
		panel.Visible = false
		menuBubble.Position = UDim2.fromOffset(p.X + panelW - MENU_SIZE, p.Y)
		menuBubble.Visible = true
		clampToScreen(menuBubble)
	else
		menuBubble.Visible = false
		panel.Visible = true
		clampToScreen(panel)
	end
end

makeDraggable(menuBubble, menuBubble, function()
	setMinimized(false)
end)

makeDraggable(titleBar, panel, nil)

minBtn.Activated:Connect(function()
	setMinimized(true)
end)

closeBtn.Activated:Connect(shutdown)

---------------------------------------------------------------------
-- AJUSTE DE TAMAÑO
---------------------------------------------------------------------
local function fitPanel()
	local screen = gui.AbsoluteSize
	if screen.X <= 0 then return end
	panelW = math.min(PANEL_W, screen.X - EDGE * 2)
	panelFullH = math.min(FULL_H, screen.Y - TOP_EDGE - EDGE)
	panel.Size = UDim2.fromOffset(panelW, panelFullH)
end

gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	fitPanel()
	if panel.Visible then clampToScreen(panel) end
	if menuBubble.Visible then clampToScreen(menuBubble) end
	clampToScreen(bar)
end)

panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	if panel.Visible then clampToScreen(panel) end
end)

fitPanel()
task.defer(function()
	fitPanel()
	clampToScreen(panel)
	clampToScreen(bar)
end)

-- Tecla F: volar on/off
track(UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == TOGGLE_KEY then
		toggleFly()
	end
end))

-- Al morir o reaparecer: se limpia el estado de curación
track(player.CharacterAdded:Connect(function()
	stopFly()
	originalCollide = {}
	chestBusy = false
	crystalBusy = false
	healBusy = false
	savedHealCF = nil
	atFountain = false
	healToken += 1
	setHealVisual(false)
	if featureSnapshot then
		task.delay(1, restoreFeatures)
	end
end))
