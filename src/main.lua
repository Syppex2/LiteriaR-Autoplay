local RunService = game:GetService("RunService")
local Engine = require("./core/engine")
local Window = require("./ui/window")

local Autoplay = {
    Enabled = false,
    TrackSystem = nil,
    AudioManager = nil,
    Connection = nil,
    UI = nil,
}

local function stopPlayback()
    if Autoplay.Connection then
        Autoplay.Connection:Disconnect()
        Autoplay.Connection = nil
    end
    Engine.releaseAll(Autoplay.TrackSystem)
    Autoplay.TrackSystem = nil
    Autoplay.AudioManager = nil
end

local function onRenderStep()
    if not Autoplay.Enabled then
        stopPlayback()
        return
    end

    if not Engine.isAlive(Autoplay.TrackSystem) or not Autoplay.AudioManager then
        stopPlayback()
        return
    end

    local finished = Engine.step(Autoplay.TrackSystem, Autoplay.AudioManager)
    if finished then
        stopPlayback()
        return
    end

    -- Actualización de estadísticas en tiempo real
    if Autoplay.UI and Autoplay.UI.StatsLabel then
        local acc = Engine.calculate_accuracy()
        Autoplay.UI.StatsLabel.Text = string.format("ACC: %.2f%% | P:%d G:%d", acc, Engine.Stats.Perfects, Engine.Stats.Greats)
    end
end

-- Supervisor de enganche pasivo
task.spawn(function()
    while true do
        task.wait(0.3)
        if Autoplay.Enabled and not Autoplay.Connection then
            local ts, am = Engine.findGame()
            if ts and am then
                Autoplay.TrackSystem = ts
                Autoplay.AudioManager = am
                Autoplay.Connection = RunService.RenderStepped:Connect(onRenderStep)
            end
        end
    end
end)

Autoplay.UI = Window.create(function(enabled)
    Autoplay.Enabled = enabled
    if not enabled then
        stopPlayback()
    end
end)