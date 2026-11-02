local Engine = {}
Engine.Holding = {}
Engine.Processed = setmetatable({}, { __mode = "k" })

-- Carga segura de los enumeradores del juego
local NoteResult = { Okay = 1, Great = 2, Perfect = 3, Miss = 4 }
pcall(function()
    NoteResult = require(game.ReplicatedStorage:WaitForChild("LiteriaRGameCore", 1).Enums.NoteResult)
end)
if not NoteResult or not NoteResult.Perfect then
    pcall(function()
        NoteResult = require(game.ReplicatedStorage:WaitForChild("RobeatsGameCore", 1).Enums.NoteResult)
    end)
end
if not NoteResult or not NoteResult.Perfect then
    NoteResult = { Okay = 1, Great = 2, Perfect = 3, Miss = 4 }
end

function Engine.releaseAll(trackSys)
    if trackSys then
        for tIdx = 1, 4 do
            pcall(function() trackSys:release_track_index(tIdx) end)
        end
    end
    table.clear(Engine.Holding)
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

    -- 1. Control de soltado exacto en notas sostenidas activas
    for tIdx, heldNote in pairs(Engine.Holding) do
        local shouldRelease = false
        pcall(function()
            if not heldNote or heldNote:should_remove() then
                shouldRelease = true
            else
                local canRelease, relRating = heldNote:test_release()
                -- Soltar únicamente cuando la cola esté en ventana Perfect o Great
                if canRelease and (relRating == NoteResult.Perfect or relRating == 3 or relRating == NoteResult.Great or relRating == 2) then
                    shouldRelease = true
                end
            end
        end)

        if shouldRelease then
            pcall(function() trackSys:release_track_index(tIdx) end)
            Engine.Holding[tIdx] = nil
        end
    end

    -- 2. Procesamiento de notas en pista
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

            -- NOTA SIMPLE (SingleNote)
            if note.ClassName == "SingleNote" then
                local canHit, rating = note:test_hit()

                -- Se impacta en cuanto el motor nativo confirme Perfect (o Great si hubo un pico de lag)
                if canHit and (rating == NoteResult.Perfect or rating == 3 or rating == NoteResult.Great or rating == 2) then
                    Engine.Processed[note] = true
                    
                    -- Asegurar que el receptor no esté bloqueado antes de registrar el impacto
                    pcall(function() trackSys:release_track_index(tIdx) end)
                    trackSys:press_track_index(tIdx)
                    
                    task.defer(function()
                        if not Engine.Holding[tIdx] then
                            pcall(function() trackSys:release_track_index(tIdx) end)
                        end
                    end)
                end

            -- NOTA SOSTENIDA (HeldNote)
            elseif note.ClassName == "HeldNote" then
                if not Engine.Holding[tIdx] then
                    local canHit, rating = note:test_hit()
                    if canHit and (rating == NoteResult.Perfect or rating == 3 or rating == NoteResult.Great or rating == 2) then
                        Engine.Processed[note] = true
                        Engine.Holding[tIdx] = note
                        
                        pcall(function() trackSys:release_track_index(tIdx) end)
                        trackSys:press_track_index(tIdx)
                    end
                end
            end
        end
    end

    return false
end

return Engine