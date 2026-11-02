local RunService = game:GetService("RunService")
local Engine = require("./core/engine")
local Window = require("./ui/window")

local Autoplay = {
    Enabled = false,
    TrackSystem = nil,
    AudioManager = nil,
    Connection = nil,
}

local function stopPlayback()
    if Autoplay.Connection then
        Autoplay.Connection:Disconnect()
        Autoplay.Connection = nil
    end
    Engine.releaseAll(Autoplay.TrackSystem)
    table.clear(Engine.Processed)
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
    end
end

-- Supervisor pasivo para enganchar partidas
task.spawn(function()
    while true do
        task.wait(0.5)
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

Window.create(function(enabled)
    Autoplay.Enabled = enabled
    if not enabled then
        stopPlayback()
    end
end)