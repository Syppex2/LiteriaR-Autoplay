-- Se importan los submódulos usando rutas relativas
local Engine = require("./core/engine")
local Window = require("./ui/window")

local AutoplayState = false

-- Inicializar UI
Window.create(function(enabled)
    AutoplayState = enabled
    print("Estado cambiado a:", enabled)
end)

print("[LiteriaR Autoplay]: Inicializado con éxito.")