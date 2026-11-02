-- src/main.lua

local Core = require(script.Core)
local UI = require(script.UI)

local function main()
    local trackSystem, audioManager = Core.TrackSystem, Core.AudioManager
    local uiWindow = UI.create_window()

    -- Main gameplay loop
    while true do
        if audioManager.is_playing() then
            local notes = trackSystem.get_notes()
            for _, note in ipairs(notes) do
                -- Implement note handling logic here
                print("Handling note: " .. tostring(note))
            end
        else
            -- Handle audio finished state
            print("Audio has finished")
        end
        wait(1) -- Adjust interval as needed
    end
end

main()
