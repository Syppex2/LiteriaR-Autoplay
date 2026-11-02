local Engine = {}
Engine.Holding = {}
Engine.Processed = setmetatable({}, { __mode = "k" })

local NoteResult = { Okay = 1, Great = 2, Perfect = 3, Miss = 4 }
pcall(function()
    NoteResult = require(game.ReplicatedStorage:WaitForChild("LiteriaRGameCore", 1).Enums.NoteResult)
end)

function Engine.releaseAll(trackSys)
    if trackSys then
        for tIdx, _ in pairs(Engine.Holding) do
            pcall(function() trackSys:release_track_index(tIdx) end)
        end
    end
    Engine.Holding = {}
end

function Engine.isAlive(ts)
    if not ts or type(ts) ~= "table" then return false end
    local ok, res = pcall(function()
        local t1 = ts:get_track(1)
        return t1 and t1.get_track_obj and t1:get_track_obj():IsDescendantOf(workspace)
    end)
    return ok and res == true
end

function Engine.findGame()
    local localElements = workspace:FindFirstChild("LocalElements")
    local proto = localElements and localElements:FindFirstChild("NoteTrackSystemProto")
    if not proto then return nil, nil end

    if not getgc then return nil, nil end

    local foundTS, foundAM = nil, nil
    for _, obj in ipairs(getgc(true)) do
        if type(obj) == "table" then
            if not foundTS and rawget(obj, "get_notes") and rawget(obj, "press_track_index") then
                if Engine.isAlive(obj) then
                    foundTS = obj
                end
            end
            if not foundAM and rawget(obj, "get_bgm") and rawget(obj, "get_mode") and rawget(obj, "load_song") then
                local ok, mode = pcall(function() return obj:get_mode() end)
                if ok and mode and mode >= 1 and mode <= 5 then
                    foundAM = obj
                end
            end
            if foundTS and foundAM then break end
        end
    end

    return foundTS, foundAM
end

function Engine.step(trackSys, audioMgr)
    local isPlaying, isFinished = false, false
    pcall(function()
        isPlaying = audioMgr:is_playing()
        isFinished = audioMgr:is_finished()
    end)

    if isFinished or not isPlaying then return isFinished end

    -- Liberación de notas sostenidas activas
    for tIdx, heldNote in pairs(Engine.Holding) do
        local mustRelease = false
        pcall(function()
            if not heldNote or heldNote:should_remove() or heldNote:test_release() then
                mustRelease = true
            end
        end)
        if mustRelease then
            pcall(function() trackSys:release_track_index(tIdx) end)
            Engine.Holding[tIdx] = nil
        end
    end

    local notesList
    pcall(function() notesList = trackSys:get_notes() end)
    if not notesList then return false end

    local count = 0
    pcall(function() count = notesList:count() end)
    if count == 0 then return false end

    for i = 1, count do
        local note
        pcall(function() note = notesList:get(i) end)

        if note and not note:should_remove() and not Engine.Processed[note] then
            local tIdx = note:get_track_index()

            if note.ClassName == "SingleNote" then
                local canHit = note:test_hit()
                local timeToEnd = 999
                pcall(function() timeToEnd = note:get_time_to_end() end)

                if canHit and timeToEnd <= 0 then
                    Engine.Processed[note] = true
                    trackSys:press_track_index(tIdx)
                    task.defer(function()
                        pcall(function() trackSys:release_track_index(tIdx) end)
                    end)
                end
            elseif note.ClassName == "HeldNote" then
                if not Engine.Holding[tIdx] then
                    local canHit = note:test_hit()
                    if canHit then
                        Engine.Processed[note] = true
                        Engine.Holding[tIdx] = note
                        trackSys:press_track_index(tIdx)
                    end
                end
            end
        end
    end

    return false
end

return Engine