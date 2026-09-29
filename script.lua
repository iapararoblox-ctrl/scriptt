-- Carga la librería de interfaz
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- Crea la ventana principal
local Window = Rayfield:CreateWindow({
   Name = "Mi Primer Script",
   LoadingTitle = "Cargando...",
   LoadingSubtitle = "Creado desde GitHub",
   ConfigurationSaving = { Enabled = false }
})

-- Crea la pestaña principal
local Tab = Window:CreateTab("Inicio", 4483362458)

-- Botón 1: Modificar Velocidad
Tab:CreateButton({
   Name = "Velocidad Rapida (50)",
   Callback = function()
       game.Players.LocalPlayer.Character.Humanoid.WalkSpeed = 50
   end,
})

-- Botón 2: Modificar Salto
Tab:CreateButton({
   Name = "Super Salto (100)",
   Callback = function()
       game.Players.LocalPlayer.Character.Humanoid.JumpPower = 100
   end,
})

-- Notificación en pantalla
Rayfield:Notify({
   Title = "¡Script listo!",
   Content = "Cargado exitosamente desde GitHub.",
   Duration = 5
})
