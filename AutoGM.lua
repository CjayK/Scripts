script_name("AutoGM v2.2")
script_author("Cjay La Muerte")
script_version("2.2")

require "lib.moonloader"
local sampev = require "lib.samp.events"
local ok_imgui, imgui = pcall(require, "mimgui")
local ok_inicfg, inicfg = pcall(require, "inicfg")

-- ============================================================
-- CONFIG
-- ============================================================
local configDir = getWorkingDirectory() .. "/config/AutoGM/"
local configFile = configDir .. "AutoGM.ini"

local defaultCfg = {
    Options = {
        enabled = true,
     mp1 = {
        cen_x=1423.66, cen_y=-1320.59, cen_z=13.55, rad=6,
        isPlayerWithinSupZone_Y = function() return true end,
        isPlayerNotWithinSupZone_X = function() return false end,
        playerIsntInRequiredVeh = function() return false end
    },   spamMode = false,
        pauseUnit = 1000,            -- ms between /getmats attempts when repeating
        cooldownAfterSuccess = 500,  -- ms after success before flags reset
        deliveryTimeout = 60000      -- ms to wait for delivery after purchase (safety)
    },
    Pickups = {
        mp1 = true,
        mp2 = true,
        air = true,
        boat = true
    },
    Message = {
        agpickup = "/s Got it!",     -- pickup reply
        agdelivered = "/s Delivered!" -- delivery reply
    }
}

local cfg = nil
local agpickup_text = defaultCfg.Message.agpickup
local agdelivered_text = defaultCfg.Message.agdelivered
local debugMode = false

local function ensureConfigDir()
    if not doesDirectoryExist(configDir) then
        createDirectory(configDir)
    end
end

local function loadConfig()
    if ok_inicfg then
        ensureConfigDir()
        cfg = inicfg.load(defaultCfg, configFile)
        if not cfg then
            cfg = defaultCfg
            inicfg.save(cfg, configFile)
            sampAddChatMessage("{FF0000}[AutoGM] {FFFFFF}AutoGM.ini created.", -1)
        end
    else
        cfg = defaultCfg
        sampAddChatMessage("{FF0000}[AutoGM] {FFFFFF}inicfg not available — using defaults in RAM.", -1)
    end

    if not cfg.Options then cfg.Options = defaultCfg.Options end
    if not cfg.Pickups then cfg.Pickups = defaultCfg.Pickups end
    if not cfg.Message then cfg.Message = defaultCfg.Message end

    agpickup_text = cfg.Message.agpickup or defaultCfg.Message.agpickup
    agdelivered_text = cfg.Message.agdelivered or defaultCfg.Message.agdelivered
end

local function saveConfig()
    if ok_inicfg and cfg then
        ensureConfigDir()
        inicfg.save(cfg, configFile)
    end
end

loadConfig()

-- ============================================================
-- GLOBAL VARS
-- ============================================================
local posX, posY, posZ = 0,0,0
local dontPickup = false
local detectPickupAttemptResponse = false
local detectFirstSpamResponse = false
local awaitSpamCooldown = false
local isPlayerMuted = false
local playerLacksRequiredJobs = false
local doesACheckpointExist = false
local playerLacksFunds = false

local awaiting_purchase = false
local awaiting_delivery = false

local gm_cmd = "/getmats"

local function resetAutoGMFlags()
    -- position tracking
    posX, posY, posZ = 0, 0, 0

    -- pickup / spam control
    dontPickup = false
    detectPickupAttemptResponse = false
    detectFirstSpamResponse = false
    awaitSpamCooldown = false

    -- player state
    isPlayerMuted = false
    playerLacksRequiredJobs = false
    playerLacksFunds = false

    -- checkpoint / delivery
    doesACheckpointExist = false
    awaiting_purchase = false
    awaiting_delivery = false

    -- optional debug
    if cfg and cfg.debug then
        sampAddChatMessage("{AAAAAA}[AutoGM] State reset after delivery.", -1)
    end
end
-- ============================================================
-- VEHICLE CHECKS
-- ============================================================
local function is_aircraft_model(model_id)
    if not model_id then return false end
    if model_id >= 511 and model_id <= 514 then return true end
    local aircrafts = {417,425,447,469,487,488,519,520,521,548,563,564,577,593,608}
    for _,v in ipairs(aircrafts) do if model_id == v then return true end end
    if model_id >= 601 and model_id <= 603 then return true end
    return false
end

local function is_boat_model(model_id)
    if not model_id then return false end
    local boats = {430,446,452,453,454,455,472,473,484,595,596}
    for _,v in ipairs(boats) do if model_id == v then return true end end
    return false
end

function isPlayerInFlyingVehicle(ped)
    if not isCharInAnyCar(ped) then return false end
    local veh = getCarCharIsUsing(ped)
    if not veh then return false end
    return is_aircraft_model(getCarModel(veh))
end

function isCharInAnyBoat(ped)
    if not isCharInAnyCar(ped) then return false end
    local veh = getCarCharIsUsing(ped)
    if not veh then return false end
    return is_boat_model(getCarModel(veh))
end

function isCharInLandVehicle(ped)
    if not isCharInAnyCar(ped) then return false end
    local veh = getCarCharIsUsing(ped)
    if not veh then return false end
    local model = getCarModel(veh)
    return not (is_aircraft_model(model) or is_boat_model(model))
end

-- ============================================================
-- VEHICLE MOVEMENT SAFETY
-- ============================================================
local function isVehicleMovingFast(ped)
    if not isCharInAnyCar(ped) then return false end
    local veh = getCarCharIsUsing(ped)
    if not veh then return false end

    -- Android MoonLoader supports getCarSpeed
    local speed = getCarSpeed(veh)

    -- Require vehicle to be almost stopped
    return speed > 1.0
end

-- ============================================================
-- PICKUPS (with super-zone helpers for MP1/MP2)
-- ============================================================
local pickups = {
    mp2 = {
        cen_x=2390.51, cen_y=-2007.94, cen_z=13.55, rad=3,
        isPlayerWithinSupZone_Y = function()
            local _, y, _ = getCharCoordinates(PLAYER_PED)
            return (y < -1990) and (y > -2060)
        end,
        isPlayerNotWithinSupZone_X = function()
            local x, _, _ = getCharCoordinates(PLAYER_PED)
            return (x < 2360) or (x > 2420)
        end,
        playerIsntInRequiredVeh = function() return false end
    },

    mp1 = {
    -- center coordinates
    cen_x = 1423.66,
    cen_y = -1320.59,
    cen_z = 13.55,

    -- box size (half-extents)
    size_x = 4,   -- half-width in X (so full width = 8)
    size_y = 3,   -- half-length in Y (so full length = 6)
    size_z = 2,   -- half-height in Z (so full height = 4)

    -- superzone checks
    isPlayerWithinSupZone_Y = function()
        local _, y, _ = getCharCoordinates(PLAYER_PED)
        return (y > -1323) and (y < -1317)  -- tighter box in Y
    end,
    isPlayerNotWithinSupZone_X = function()
        local x, _, _ = getCharCoordinates(PLAYER_PED)
        return (x < 1420) or (x > 1427)      -- tighter box in X
    end,

    -- vehicle requirement
    playerIsntInRequiredVeh = function() return false end,

    -- box-based pickup detection
    containsPlayer = function()
        local px, py, pz = getCharCoordinates(PLAYER_PED)
        return (px > 1423.66 - 4 and px < 1423.66 + 4)
           and (py > -1320.59 - 3 and py < -1320.59 + 3)
           and (pz > 13.55 - 2 and pz < 13.55 + 2)
    end
},

    air = {
    cen_x = 1418.94,
    cen_y = -2593.28,
    cen_z = 13.46,
    rad = 100,  -- increased radius

    -- Allow player within a larger Y range
    isPlayerWithinSupZone_Y = function()
        local _, y, _ = getCharCoordinates(PLAYER_PED)
        return (y > -2720) and (y < -2460)
    end,

    -- Allow player within a larger X range
    isPlayerWithinSupZone_X = function()
        local x, _, _ = getCharCoordinates(PLAYER_PED)
        return (x > 1300) and (x < 1550)
    end,

    -- Must be in flying vehicle
    playerIsntInRequiredVeh = function()
        return not isPlayerInFlyingVehicle(PLAYER_PED)
    end
},

    boat = {
        cen_x=2102.01, cen_y=-104.07, cen_z=3.11, rad=24,
        isPlayerWithinSupZone_Y = function()
            local _, y, _ = getCharCoordinates(PLAYER_PED)
            return (y > -210) and (y < -60)
        end,
        isPlayerNotWithinSupZone_X = function()
            local x, _, _ = getCharCoordinates(PLAYER_PED)
            return (x < 2030) or (x > 2130)
        end,
        playerIsntInRequiredVeh = function() return not isCharInAnyBoat(PLAYER_PED) end
    }
}

-- ============================================================
-- DEBUG SETUP
-- ============================================================
debugMode = false       -- <-- make sure this is enabled
gm_cmd = "/getmats"    -- <-- your command to send

-- ============================================================
-- UTILITIES
-- ============================================================
-- ============================================================
-- SAFE SEND CHAT
-- ============================================================
local function safeSendChat(cmd)
    if cmd and cmd ~= "" then
        if sampProcessChatInput then sampProcessChatInput(cmd) else sampSendChat(cmd) end
    end
end

-- ============================================================
-- PICKUP DETECTION
-- ============================================================
local function isPlayerInPickupZone(pickup)
    if not pickup then return false end

    local px, py, pz = getCharCoordinates(PLAYER_PED)

    -- BOX check first (if defined)
    if pickup.containsPlayer and type(pickup.containsPlayer) == "function" then
        if not pickup.containsPlayer() then return false end
    else
        -- fallback to old circle detection
        local dx = px - pickup.cen_x
        local dy = py - pickup.cen_y
        local dz = pz - pickup.cen_z
        if (pickup.rad or 0) <= 0 then return false end
        if (dx*dx + dy*dy + dz*dz) > (pickup.rad * pickup.rad) then
            return false
        end
    end

    -- superzone checks
    if pickup.isPlayerWithinSupZone_Y and type(pickup.isPlayerWithinSupZone_Y) == "function" then
        if not pickup.isPlayerWithinSupZone_Y() then return false end
    end
    if pickup.isPlayerNotWithinSupZone_X and type(pickup.isPlayerNotWithinSupZone_X) == "function" then
        if pickup.isPlayerNotWithinSupZone_X() then return false end
    end

    return true
end

local function isInPickup(pick)
    return isPlayerInPickupZone(pick)
end
-- ============================================================
-- ATTEMPT PICKUP ONCE
-- ============================================================
local function attemptPickupOnce(pick)
    if not pick then return end
    if detectPickupAttemptResponse or dontPickup or awaiting_purchase or awaiting_delivery then
        if debugMode then sampAddChatMessage("{FF00FF}[DEBUG] attemptPickupOnce skipped - blocked.", -1) end
        return
    end

    detectPickupAttemptResponse = true
    awaiting_purchase = true
    dontPickup = true

    if debugMode then sampAddChatMessage("{FF00FF}[DEBUG] Starting repeated /getmats for pickup: "..tostring(pick), -1) end

    local thread_pick = pick
    lua_thread.create(function()
        local pause = cfg.Options.pauseUnit or 1000

        while awaiting_purchase do
            -- STOP CONDITIONS
            if playerLacksFunds or isPlayerMuted or doesACheckpointExist or playerLacksRequiredJobs then
                if debugMode then sampAddChatMessage("{FF00FF}[DEBUG] Aborting /getmats due to block.", -1) end
                awaiting_purchase = false
                break
            end

            if not isInPickup(thread_pick) then
                if debugMode then sampAddChatMessage("{FF00FF}[DEBUG] Player left pickup zone — stopping /getmats.", -1) end
                awaiting_purchase = false
                break
            end

            -- SEND /GETMATS
            safeSendChat(gm_cmd)
            if debugMode then sampAddChatMessage("{FF00FF}[DEBUG] Sent /getmats", -1) end
            wait(pause)
        end

        -- WAIT FOR DELIVERY
        if awaiting_delivery then
            if debugMode then sampAddChatMessage("{FF00FF}[DEBUG] Waiting for delivery...", -1) end
            local waited = 0
            local deliveryTimeout = cfg.Options.deliveryTimeout or 60000
            while awaiting_delivery and waited < deliveryTimeout do
                wait(250)
                waited = waited + 250
            end
            if awaiting_delivery then
                awaiting_delivery = false
                if debugMode then sampAddChatMessage("{FF00FF}[DEBUG] Delivery timeout reached, resetting flags.", -1) end
            end
        end

        -- COOLDOWN
        wait(cfg.Options.cooldownAfterSuccess or 500)

        -- RESET FLAGS
        detectPickupAttemptResponse = false
        dontPickup = false
        awaiting_purchase = false
        awaiting_delivery = false
        detectFirstSpamResponse = false
        awaitSpamCooldown = false

        if debugMode then sampAddChatMessage("{FF00FF}[DEBUG] Pickup flow finished, flags reset.", -1) end
    end)
end

-- ============================================================
-- ATTEMPTS ARE SPAMMED (SPAM MODE)
-- ============================================================
local function attemptsAreSpammed()
    if cfg.Options.spamMode then
        detectFirstSpamResponse = true
        awaitSpamCooldown = true
        for i = 1, 3 do
            safeSendChat(gm_cmd)
            wait(cfg.Options.pauseUnit or 1000)
        end
        return true
    end
    return false
end

-- ============================================================
-- STOP ALL PICKUP ATTEMPTS
-- ============================================================
local function stopAllPickupAttempts()
    awaiting_purchase = false
    awaiting_delivery = false
    detectPickupAttemptResponse = false
    detectFirstSpamResponse = false
    awaitSpamCooldown = false
    dontPickup = false
    playerLacksRequiredJobs = false
    if debugMode then sampAddChatMessage("{FF00FF}[DEBUG] Forced stop: left pickup zone.", -1) end
end
-- ============================================================
-- SERVER MESSAGE HANDLER (pickup/purchase + delivery patterns)
-- ============================================================
function sampev.onServerMessage(color, text)
    if not text then return end
    local plain = tostring(text)
    local tl = plain:lower()

    ------------------------------------------------------------
    -- CHECKPOINT RESET
    ------------------------------------------------------------
    if tl:find("all current checkpoints, trackers and accepted fares have been reset") then
        doesACheckpointExist=false
        dontPickup=false
        detectPickupAttemptResponse=false
        detectFirstSpamResponse=false
        awaitSpamCooldown=false
        playerLacksFunds=false
        awaiting_purchase = false
        awaiting_delivery = false
        sampAddChatMessage("{FF0000}[AutoGM] {FFFFFF}Checkpoint cleared, resuming /getmats.", -1)

        lua_thread.create(function()
            wait(60)
            for name, pick in pairs(pickups) do
                if cfg.Pickups[name] and isInPickup(pick) and not pick.playerIsntInRequiredVeh() then
                    attemptPickupOnce(pick)  -- fixed
                    break
                end
            end
        end)
        return
    end

    ------------------------------------------------------------
    -- PURCHASE / PICKUP SUCCESS
    ------------------------------------------------------------
    if (tl:find("you bought") and tl:find("material")) or tl:find("package secured") or tl:find("you picked up") then
        if debugMode then sampAddChatMessage("{FF00FF}[DEBUG] PURCHASE/PICKUP detected: " .. plain, -1) end

        if agpickup_text and agpickup_text ~= "" then
            safeSendChat(agpickup_text)
        end

        awaiting_purchase = false
        awaiting_delivery = true
        dontPickup = true

        return
    end

    ------------------------------------------------------------
-- DELIVERY MESSAGE
------------------------------------------------------------
if tl:find("the factory gave you")
and tl:find("materials")
and tl:find("delivery") then

    if debugMode then
        sampAddChatMessage(
            "{FF00FF}[DEBUG] DELIVERY detected: " .. plain,
            -1
        )
    end

    -- reset all AutoGM flags safely
    resetAutoGMFlags()

    if agdelivered_text and agdelivered_text ~= "" then
        safeSendChat(agdelivered_text)
    end

    lua_thread.create(function()
        wait(150)
        for name, pick in pairs(pickups) do
            if cfg.Pickups[name]
            and isInPickup(pick)
            and not pick.playerIsntInRequiredVeh() then
                attemptPickupOnce(pick)
                break
            end
        end
    end)
    return
end

    ------------------------------------------------------------
    -- MUTED
    ------------------------------------------------------------
    if plain:find("You have been muted automatically for spamming") then
        if not isPlayerMuted then
            isPlayerMuted = true
            sampAddChatMessage("{FF0000}[AutoGM] {FFFFFF}Muted for spamming. Waiting 12 seconds...", -1)
            lua_thread.create(function()
                wait(12000)
                isPlayerMuted = false
                if debugMode then sampAddChatMessage("{FF00FF}[DEBUG] Mute cooldown ended.", -1) end
            end)
        end
    end

    ------------------------------------------------------------
    -- INSUFFICIENT FUNDS
    ------------------------------------------------------------
    if tl:find("you do not have enough money")
    or tl:find("you don't have enough money")
    or tl:find("you do not have enough cash")
    or tl:find("you can't afford") then
        playerLacksFunds = true
        sampAddChatMessage("{FF0000}[AutoGM] {FFFFFF}Holy brother you're too broke! Time to hit that /findjob!", -1)
        lua_thread.create(function() wait(5000); playerLacksFunds=false end)
    end

    ------------------------------------------------------------
-- GM CHECKPOINT FOUND (FILTERED)
------------------------------------------------------------
if tl:find("checkpoint")
and (
    tl:find("materials")
    or tl:find("factory")
    or tl:find("delivery")
) then
    doesACheckpointExist = true
end

    ------------------------------------------------------------
-- LACK OF REQUIRED JOB (HARD STOP)
------------------------------------------------------------
if tl:find("not an arms dealer")
and tl:find("craftsman") then

    playerLacksRequiredJobs = true
    dontPickup = true
    awaiting_purchase = false
    awaiting_delivery = false

    sampAddChatMessage(
        "{FF0000}[AutoGM] {FFFFFF}Required job missing, Please get either Arms Dealer or Craftsman.",
        -1
    )
    return
end
    ------------------------------------------------------------
    -- JOB ACQUIRED (restart /getmats)
    ------------------------------------------------------------
    if plain:find("You are now a Craftsman, type /help to see your new commands") or
       plain:find("You are now an Arms Dealer, type /help to see your new commands") then
        playerLacksRequiredJobs = false
        if debugMode then sampAddChatMessage("{FF00FF}[DEBUG] Job acquired — resuming /getmats.", -1) end

        lua_thread.create(function()
            wait(150)
            for name, pick in pairs(pickups) do
                if cfg.Pickups[name] and isInPickup(pick) and not pick.playerIsntInRequiredVeh() then
                    attemptPickupOnce(pick)  -- fixed
                    break
                end
            end
        end)
    end
end

-- ============================================================
-- /agmpickup (set pickup/purchase reply)
-- ============================================================
sampRegisterChatCommand("agmpickup",function(param)
    if not param or #param==0 then
        sampAddChatMessage("{FF0000}[AutoGM] {FFFFFF}Usage: /agmpickup <message>",-1)
        return
    end
    agpickup_text=param
    if not cfg.Message then cfg.Message={} end
    cfg.Message.agpickup=param
    saveConfig()
    sampAddChatMessage("{FF0000}[AutoGM] {FFFFFF}/agmpickup saved: "..param,-1)
end)

-- ============================================================
-- /agmdelivered (set delivered reply — fires on delivery detection)
-- ============================================================
sampRegisterChatCommand("agmdelivered",function(param)
    if not param or #param==0 then
        sampAddChatMessage("{FF0000}[AutoGM] {FFFFFF}Usage: /agmdelivered <message>",-1)
        return
    end
    agdelivered_text=param
    if not cfg.Message then cfg.Message={} end
    cfg.Message.agdelivered=param
    saveConfig()
    sampAddChatMessage("{FF0000}[AutoGM] {FFFFFF}/agmdelivered saved: "..param,-1)
end)

-- ============================================================
-- /agmconfig (GUI)
-- ============================================================
local menu,pointers={},{}
if ok_imgui then
    menu.config_open=menu.config_open or imgui.new.bool(false)
    pointers.pick_mp1=pointers.pick_mp1 or imgui.new.bool(cfg.Pickups.mp1)
    pointers.pick_mp2=pointers.pick_mp2 or imgui.new.bool(cfg.Pickups.mp2)
    pointers.pick_air=pointers.pick_air or imgui.new.bool(cfg.Pickups.air)
    pointers.pick_boat=pointers.pick_boat or imgui.new.bool(cfg.Pickups.boat)
    pointers.spam_mode=pointers.spam_mode or imgui.new.bool(cfg.Options.spamMode)
    pointers.pause_unit=pointers.pause_unit or imgui.new.int(cfg.Options.pauseUnit or 1000)
    pointers.cooldown_after=pointers.cooldown_after or imgui.new.int(cfg.Options.cooldownAfterSuccess or 500)

    local function applyPointersToCfg()
        cfg.Pickups.mp1=pointers.pick_mp1[0]
        cfg.Pickups.mp2=pointers.pick_mp2[0]
        cfg.Pickups.air=pointers.pick_air[0]
        cfg.Pickups.boat=pointers.pick_boat[0]
        cfg.Options.spamMode=pointers.spam_mode[0]
        cfg.Options.pauseUnit=pointers.pause_unit[0]
        cfg.Options.cooldownAfterSuccess=pointers.cooldown_after[0]
        -- keep message keys in sync
        cfg.Message = cfg.Message or {}
        cfg.Message.agpickup = cfg.Message.agpickup or agpickup_text
        cfg.Message.agdelivered = cfg.Message.agdelivered or agdelivered_text
        saveConfig()
        -- refresh runtime variables
        agpickup_text = cfg.Message.agpickup or defaultCfg.Message.agpickup
        agdelivered_text = cfg.Message.agdelivered or defaultCfg.Message.agdelivered
    end

    local function drawConfigGUI()
        if imgui.Begin("AutoGM Config v2.2", menu.config_open, imgui.WindowFlags.NoResize) then
            imgui.TextColored(imgui.ImVec4(1,0,0,1), "AutoGM Config v2.2")
            imgui.Spacing()

            imgui.Text("Pickups")
            imgui.Separator()
            imgui.Checkbox("MP1", pointers.pick_mp1)
            imgui.Checkbox("MP2", pointers.pick_mp2)
            imgui.Checkbox("AIR", pointers.pick_air)
            imgui.Checkbox("BOAT", pointers.pick_boat)
            imgui.Spacing()

            imgui.Text("Options")
            imgui.Separator()
            imgui.Checkbox("Spam Mode", pointers.spam_mode)
            imgui.InputInt("Pause Unit (ms)", pointers.pause_unit)
            imgui.InputInt("Cooldown After Success (ms)", pointers.cooldown_after)
            imgui.Spacing()

            if imgui.Button("Save & Close") then
                applyPointersToCfg()
                menu.config_open[0] = false
                sampAddChatMessage("{FF0000}[AutoGM] {FFFFFF}Configuration saved!", -1)
            end

            imgui.SameLine()

            if imgui.Button("Reset Defaults") then
                -- Reset pointers to defaultCfg values
                pointers.pick_mp1[0] = defaultCfg.Pickups.mp1
                pointers.pick_mp2[0] = defaultCfg.Pickups.mp2
                pointers.pick_air[0] = defaultCfg.Pickups.air
                pointers.pick_boat[0] = defaultCfg.Pickups.boat
                pointers.spam_mode[0] = defaultCfg.Options.spamMode
                pointers.pause_unit[0] = defaultCfg.Options.pauseUnit
                pointers.cooldown_after[0] = defaultCfg.Options.cooldownAfterSuccess

                -- Reset message defaults in cfg
                cfg.Pickups = defaultCfg.Pickups
                cfg.Options = defaultCfg.Options
                cfg.Message = defaultCfg.Message

                -- Apply & save defaults
                applyPointersToCfg()

                -- Update runtime message variables
                agpickup_text = cfg.Message.agpickup or defaultCfg.Message.agpickup
                agdelivered_text = cfg.Message.agdelivered or defaultCfg.Message.agdelivered

                sampAddChatMessage("{FF0000}[AutoGM] {FFFFFF}Configuration reset to defaults.", -1)
            end

            imgui.End()
        end
    end

    imgui.OnInitialize(function() imgui.GetIO().IniFilename=nil end)
    imgui.OnFrame(function() return menu.config_open[0] end,function() drawConfigGUI() end)
end

sampRegisterChatCommand("agmconfig",function()
    if ok_imgui then menu.config_open[0]=true
    else sampAddChatMessage("{FF0000}[AutoGM] {FFFFFF}GUI unavailable.",-1) end
end)

-- ============================================================
-- /autogm toggle + debug commands
-- ============================================================
local autogm_active=cfg.Options.enabled
local function saveAndAnnounceToggle(state)
    cfg.Options.enabled=state
    saveConfig()
    if state then sampAddChatMessage("{FF0000}[AutoGM] {FFFFFF}AutoGM ON",-1)
    else sampAddChatMessage("{FF0000}[AutoGM] {FFFFFF}AutoGM OFF",-1) end
end
function toggleAutoGM()
    autogm_active=not autogm_active
    saveAndAnnounceToggle(autogm_active)
end
sampRegisterChatCommand("autogm",toggleAutoGM)

sampRegisterChatCommand("autogmdebug",function()
    debugMode=not debugMode
    if debugMode then sampAddChatMessage("{FF00FF}[DEBUG] Debug mode ON",-1)
    else sampAddChatMessage("{FF00FF}[DEBUG] Debug mode OFF",-1) end
end)

sampRegisterChatCommand("autogmhelp", function()
    sampAddChatMessage("{FF0000}[AutoGM] {FFFFFF}Available commands:", -1)
    sampAddChatMessage("{FF0000}/autogm {FFFFFF}- Toggle AutoGM ON/OFF", -1)
    sampAddChatMessage("{FF0000}/autogmdebug {FFFFFF}- Toggle debug messages", -1)
    sampAddChatMessage("{FF0000}/agmconfig {FFFFFF}- Open configuration GUI", -1)
    sampAddChatMessage("{FF0000}/agmpickup <msg> {FFFFFF}- Set pickup reply", -1)
    sampAddChatMessage("{FF0000}/agmdelivered <msg> {FFFFFF}- Set delivered reply", -1)
    sampAddChatMessage("{FF0000}/autogmhelp {FFFFFF}- Show this help message", -1)
end)

-- ============================================================
-- MAIN LOOP
-- ============================================================
function main()
    repeat wait(0) until isSampAvailable()
    agpickup_text = cfg.Message and cfg.Message.agpickup or agpickup_text
    agdelivered_text = cfg.Message and cfg.Message.agdelivered or agdelivered_text
    sampAddChatMessage("{FF0000}[AutoGM] {FFFFFF}AutoGM v2.2 by {FFFF00}Cjay La Muerte {FF0000}[/autogmhelp]", -1)

    -- Initialize per-pickup zone flags using isInPickup (respects superzones)
    for name, pick in pairs(pickups) do
        local inside = isInPickup(pick)
        pick.inZone = inside
        if inside then
            if debugMode then
                sampAddChatMessage(string.format("{FF00FF}[DEBUG] Already in pickup zone: %s", tostring(name)), -1)
            end
            if not attemptsAreSpammed() then
                attemptPickupOnce(pick)  -- <-- pass pick!
            end
        end
    end

    while true do
        wait(0)
        if not autogm_active or dontPickup or isPlayerMuted or playerLacksFunds or doesACheckpointExist then
            wait(500)
            goto continue
        end

        for name, pick in pairs(pickups) do
            if cfg.Pickups[name] and not pick.playerIsntInRequiredVeh() then
                local inside = isInPickup(pick)

                -- ENTER zone
                if inside and not pick.inZone then
                    pick.inZone = true
                    if debugMode then
                        sampAddChatMessage(string.format("{FF00FF}[DEBUG] Entered pickup zone: %s", tostring(name)), -1)
                    end
                    if not attemptsAreSpammed() then
                        attemptPickupOnce(pick)  -- <-- pass pick!
                    end

                -- LEAVE zone
                elseif not inside and pick.inZone then
                    pick.inZone = false
                    if debugMode then
                        sampAddChatMessage(string.format("{FF00FF}[DEBUG] Left pickup zone: %s", tostring(name)), -1)
                    end
                    
                    -- STOP ANY /getmats SPAM WHEN LEAVING ZONE
                    stopAllPickupAttempts()
                end
            end
        end

        ::continue::
    end
end