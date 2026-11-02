local Engine = {}
Engine.Holding = {}

function Engine.hitNote(trackSys, note, targetRating)
    local trackIndex = note:get_track_index()
    
    if note.ClassName == "SingleNote" then
        trackSys:press_track_index(trackIndex)
        task.defer(function()
            pcall(function() trackSys:release_track_index(trackIndex) end)
        end)
    elseif note.ClassName == "HeldNote" then
        Engine.Holding[trackIndex] = note
        trackSys:press_track_index(trackIndex)
    end
end

function Engine.releaseNote(trackSys, trackIndex)
    pcall(function() trackSys:release_track_index(trackIndex) end)
    Engine.Holding[trackIndex] = nil
end

return Engine