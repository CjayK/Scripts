script_name("AutoLawyer Mobile")
script_author("Cjay La Muerte")
script_version("1.3-fixed")

require "lib.moonloader"
local sampev = require "lib.samp.events"

-- CONFIG ---------------------------------------------------------------------

local isEnabled = false
local default_delay = 1000
local closestMode = true
local inmateId = -1
local prisonerSkin = 50
local ignoreList = {}

local nextFreeAttempt = 0
local isPausedForJail = false
local lastFreeTarget = -1

-- AutoDefend -----------------------------------------------------------------
local isAutoDefendEnabled = false
local defendRetryUsed = false
local defendPausedNoLawyer = false
local DEFEND_DISTANCE = 2.0
local nextDefendAttempt = 0
local defendDelay = 1500
local lastDefendTarget = -1

-- COMMANDS -------------------------------------------------------------------

function toggleAutoLawyer()
    isEnabled = not isEnabled
    local status = isEnabled and "{33FF33}Enabled" or "{FF3333}Disabled"
    sampAddChatMessage("{FFA500}[AutoLawyer]{FFFFFF} AutoLawyer is now "..status..".", -1)
    if isEnabled then nextFreeAttempt = os.time() end
end

function toggleAutoDefend()
    isAutoDefendEnabled = not isAutoDefendEnabled
    defendRetryUsed = false
    local status = isAutoDefendEnabled and "{33FF33}Enabled" or "{FF3333}Disabled"
    sampAddChatMessage("{FFA500}[AutoDefend]{FFFFFF} AutoDefend is now "..status..".", -1)
    if isAutoDefendEnabled then nextDefendAttempt = os.time() end
end

function cmd_help()
    sampAddChatMessage("{FFA500}[AutoLawyer Help]{FFFFFF}", -1)
    sampAddChatMessage("/al - Toggle AutoLawyer", -1)
    sampAddChatMessage("/adefend - Toggle AutoDefend", -1)
    sampAddChatMessage("/adefenddelay [sec] - Set defend delay", -1)
    sampAddChatMessage("/alid [id] - Target inmate", -1)
    sampAddChatMessage("/alreset - Reset ignore list", -1)
    sampAddChatMessage("/aldelay [sec] - Set free delay", -1)
end

function cmd_setId(param)
    local id = tonumber(param)
    if id and sampIsPlayerConnected(id) then
        inmateId = id
        closestMode = false
        sampAddChatMessage("{FFA500}[AutoLawyer]{FFFFFF} Targeting ID "..id..".", -1)
    end
end

function cmd_reset()
    ignoreList = {}
    inmateId = -1
    closestMode = true
    lastFreeTarget = -1
    sampAddChatMessage("{FFA500}[AutoLawyer]{FFFFFF} Reset done.", -1)
end

function cmd_delay(param)
    local sec = tonumber(param)
    if sec and sec >= 1 then
        default_delay = sec * 1000
        sampAddChatMessage("{FFA500}[AutoLawyer]{FFFFFF} Delay set to "..sec.."s.", -1)
    end
end

function cmd_defendDelay(param)
    local sec = tonumber(param)
    if sec and sec >= 1 then
        defendDelay = sec * 1000
        sampAddChatMessage("{FFA500}[AutoDefend]{FFFFFF} Delay set to "..sec.."s.", -1)
    end
end

-- UTILS ----------------------------------------------------------------------

function getClosestPrisonerId(maxDistance)
    local myX,myY,myZ = getCharCoordinates(PLAYER_PED)
    local best, bestDist = -1, maxDistance
    for i = 0, MAX_PLAYERS do
        if sampIsPlayerConnected(i) and not ignoreList[i] then
            local ok, ped = sampGetCharHandleBySampPlayerId(i)
            if ok and doesCharExist(ped) and getCharModel(ped) == prisonerSkin then
                local x,y,z = getCharCoordinates(ped)
                local d = getDistanceBetweenCoords3d(myX,myY,myZ,x,y,z)
                if d < bestDist then
                    bestDist = d
                    best = i
                end
            end
        end
    end
    return best
end

function getClosestNearbyPlayer(maxDistance)
    local myX,myY,myZ = getCharCoordinates(PLAYER_PED)
    local best, bestDist = -1, maxDistance
    for i = 0, MAX_PLAYERS do
        if sampIsPlayerConnected(i) and not ignoreList[i] then
            local ok, ped = sampGetCharHandleBySampPlayerId(i)
            if ok and doesCharExist(ped) then
                local x,y,z = getCharCoordinates(ped)
                local d = getDistanceBetweenCoords3d(myX,myY,myZ,x,y,z)
                if d < bestDist then
                    bestDist = d
                    best = i
                end
            end
        end
    end
    return best
end

function getDistanceToPlayer(playerId)
    local ok, ped = sampGetCharHandleBySampPlayerId(playerId)
    if ok and doesCharExist(ped) then
        local px, py, pz = getCharCoordinates(ped)
        local mx, my, mz = getCharCoordinates(PLAYER_PED)
        return getDistanceBetweenCoords3d(mx,my,mz,px,py,pz)
    end
    return math.huge
end

-- MAIN -----------------------------------------------------------------------

function main()
    repeat wait(0) until isSampAvailable()

    sampRegisterChatCommand("al", toggleAutoLawyer)
    sampRegisterChatCommand("adefend", toggleAutoDefend)
    sampRegisterChatCommand("alhelp", cmd_help)
    sampRegisterChatCommand("alid", cmd_setId)
    sampRegisterChatCommand("alreset", cmd_reset)
    sampRegisterChatCommand("aldelay", cmd_delay)
    sampRegisterChatCommand("adefenddelay", cmd_defendDelay)

    sampAddChatMessage("{FFA500}[AutoLawyer]{FFFFFF} Loaded. Use {FFA500}[/alhelp].", -1)

    while true do
        wait(200)
        if isPausedForJail then goto skip end

        -- AUTO LAWYER
        if isEnabled and os.time() >= nextFreeAttempt then
            local id = closestMode and getClosestPrisonerId(7.0) or inmateId
            if id ~= -1 and not ignoreList[id] then
                local dist = getDistanceToPlayer(id)
                if dist <= 7.0 then
                    lastFreeTarget = id
                    sampAddChatMessage("{AAAAAA}[AutoLawyer] Offering /free to ID "..id.." (Distance: "..string.format("%.1f", dist).."m)", -1)
                    sampSendChat("/free "..id)
                    nextFreeAttempt = os.time() + math.floor(default_delay / 1000)
                else
                    sampAddChatMessage("{FFAA00}[AutoLawyer] ID "..id.." too far (Distance: "..string.format("%.1f", dist).."m), waiting...", -1)
                    nextFreeAttempt = os.time() + 1 -- retry soon
                end
            end
        end

        -- AUTO DEFEND
        if isAutoDefendEnabled and not defendPausedNoLawyer and os.time() >= nextDefendAttempt then
            local id = getClosestNearbyPlayer(DEFEND_DISTANCE)
            if id ~= -1 and not ignoreList[id] and id ~= lastDefendTarget and not isCharInAnyCar(PLAYER_PED) then
                lastDefendTarget = id
                defendRetryUsed = false
                sampAddChatMessage("{AAAAAA}[AutoDefend] Offering /defend to ID "..id, -1)
                sampSendChat("/defend "..id.." 200")
                nextDefendAttempt = os.time() + math.floor(defendDelay / 1000)
            end
        end

        ::skip::
    end
end

-- SERVER MESSAGES ------------------------------------------------------------

sampev.onServerMessage = function(color, text)

    -- FREE COOLDOWN
    local sec = text:match("You must wait (%d+) seconds before you can free again")
    if sec then
        nextFreeAttempt = os.time() + tonumber(sec)
        sampAddChatMessage("{AAAAAA}[AutoLawyer] Cooldown "..sec.."s.", -1)
        return
    end

    -- FREE REJECTIONS
    if text == "That player is not wanted!" or
       text == "This player has already had half of their jail/prison time reduced by lawyers." then
        if lastFreeTarget ~= -1 then
            ignoreList[lastFreeTarget] = true
            sampAddChatMessage("{FFAA00}[AutoLawyer] Ignoring ID "..lastFreeTarget.." (server refused).", -1)
            lastFreeTarget = -1
            nextFreeAttempt = os.time() + math.floor(default_delay / 1000) -- prevent spam
        end
        return
    end
    
-- NO JAIL TIME LEFT (IGNORE & FIND NEXT)
    if text == "This player has no jail/prison time left and is set to be released." then
        if lastFreeTarget ~= -1 then
            ignoreList[lastFreeTarget] = true
            sampAddChatMessage(
                "{FFAA00}[AutoLawyer] ID "..lastFreeTarget.." has no jail time left. Ignoring.",
                -1
            )
            lastFreeTarget = -1
            nextFreeAttempt = os.time() + math.floor(default_delay / 1000)
        end
        return
    end
    
-- NOT JAILED / DOESN'T NEED LAWYER (HARD STOP)
local clean = text:gsub("{.-}", ""):lower()

if clean:find("doesn't need a lawyer", 1, true) or
   clean:find("isn't jailed", 1, true) then

    if lastFreeTarget ~= -1 then
        ignoreList[lastFreeTarget] = true
        sampAddChatMessage(
            "{FFAA00}[AutoLawyer] ID "..lastFreeTarget.." doesn't need a lawyer. Pausing attempts.",
            -1
        )
        lastFreeTarget = -1
    end

    -- 🔒 GLOBAL PAUSE (THIS STOPS SPAM)
    lawyerGlobalPauseUntil = os.time() + math.floor(default_delay / 1000)

    return
end

    -- TOO FAR
    if text == "You are too far away." and lastFreeTarget ~= -1 then
        local dist = getDistanceToPlayer(lastFreeTarget)
        sampAddChatMessage("{FFAA00}[AutoLawyer] ID "..lastFreeTarget.." too far ("..string.format("%.1f", dist).."m), will retry when closer.", -1)
        nextFreeAttempt = os.time() + 1
        return
    end

    -- AUTO DEFEND SERVER RESPONSES
    if text == "That player isn't near you." and isAutoDefendEnabled then
        if not defendRetryUsed then
            local id = getClosestNearbyPlayer(DEFEND_DISTANCE)
            if id ~= -1 then
                sampAddChatMessage("{FFFF00}[AutoDefend] Retrying /defend for ID "..id, -1)
                sampSendChat("/defend "..id.." 200")
                nextDefendAttempt = os.time() + math.floor(defendDelay / 1000)
                defendRetryUsed = true
            end
        end
        return
    end

    if text == "You are not a Lawyer!" then
        defendPausedNoLawyer = true
        sampAddChatMessage("{FF3333}[AutoDefend] Paused (not a lawyer).", -1)
        return
    end

    if text:find("You are now a Lawyer", 1, true) then
        defendPausedNoLawyer = false
        sampAddChatMessage("{33FF33}[AutoDefend] Resumed (lawyer).", -1)
        return
    end

    -- JAILED
    if text:find("jail or prison yourself", 1, true) then
        isPausedForJail = true
        sampAddChatMessage("{FF3333}[AutoLawyer] Paused (you are jailed).", -1)
        return
    end

    if text:find("You may now type /leaveprison", 1, true) then
        isPausedForJail = false
        sampAddChatMessage("{33FF33}[AutoLawyer] Resumed.", -1)
        return
    end
end