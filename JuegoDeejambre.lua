local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local RADIO = 500000
local ESPERA = 0.15
local INTERVALO = 1
local DESTINO = Vector3.new(11, 49, -553)
local ALTURA_PLATAFORMA = 3.5  -- distancia entre el centro del personaje y el centro de la plataforma

local activo = false
local plataforma = nil

---------------------------------------------------------------------
-- UI local
---------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "BurbujasUI"
gui.ResetOnSpawn = false
gui.Parent = PlayerGui

local boton = Instance.new("TextButton")
boton.Size = UDim2.fromOffset(200, 50)
boton.Position = UDim2.new(0, 20, 0.5, -25)
boton.BackgroundColor3 = Color3.fromRGB(170, 50, 50)
boton.Text = "Auto burbujas: OFF"
boton.TextColor3 = Color3.new(1, 1, 1)
boton.Font = Enum.Font.GothamBold
boton.TextSize = 15
boton.Parent = gui
Instance.new("UICorner", boton).CornerRadius = UDim.new(0, 10)

---------------------------------------------------------------------
-- Utilidades
---------------------------------------------------------------------
local function getRoot()
	local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	return char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart", 5)
end

local function getPosition(obj)
	if obj:IsA("Model") then
		return obj:GetPivot().Position
	elseif obj:IsA("BasePart") then
		return obj.Position
	end
end

-- Float: crea (o recoloca) la plataforma bajo el destino
local function crearPlataforma()
	if not plataforma or not plataforma.Parent then
		plataforma = Instance.new("Part")
		plataforma.Name = "FloatPlatform"
		plataforma.Size = Vector3.new(10, 1, 10)
		plataforma.Anchored = true
		plataforma.CanCollide = true
		plataforma.Transparency = 0.6
		plataforma.Material = Enum.Material.Glass
		plataforma.Color = Color3.fromRGB(90, 170, 255)
		plataforma.Parent = Workspace
	end
	plataforma.Position = DESTINO - Vector3.new(0, ALTURA_PLATAFORMA, 0)
end

local function quitarPlataforma()
	if plataforma then
		plataforma:Destroy()
		plataforma = nil
	end
end

---------------------------------------------------------------------
-- Botón
---------------------------------------------------------------------
boton.MouseButton1Click:Connect(function()
	activo = not activo
	if activo then
		boton.Text = "Auto burbujas: ON"
		boton.BackgroundColor3 = Color3.fromRGB(50, 150, 70)
	else
		boton.Text = "Auto burbujas: OFF"
		boton.BackgroundColor3 = Color3.fromRGB(170, 50, 50)
		quitarPlataforma()
	end
end)

---------------------------------------------------------------------
-- Lógica
---------------------------------------------------------------------
local function recogerBurbujas()
	local folder = Workspace:FindFirstChild("EnvironmentOxygenBubbles", true)
	if not folder then return end

	local root = getRoot()
	if not root then return end

	local recogio = false

	for _, bubble in ipairs(folder:GetChildren()) do
		if not activo then break end
		if not bubble.Parent then continue end

		local pos = getPosition(bubble)
		if pos and (root.Position - pos).Magnitude <= RADIO then
			root.CFrame = CFrame.new(pos)
			recogio = true
			task.wait(ESPERA)
		end
	end

	-- Va al destino y se queda sobre la plataforma
	if activo and recogio and root.Parent then
		crearPlataforma()
		root.CFrame = CFrame.new(DESTINO)
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

task.spawn(function()
	while task.wait(INTERVALO) do
		if activo then
			local ok, err = pcall(recogerBurbujas)
			if not ok then
				warn("[ERROR]", err)
			end
		end
	end
end)
