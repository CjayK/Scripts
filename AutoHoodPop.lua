script_name("AutoHoodPop")
script_author("Cjay La Muerte")
script_version("1.2-fixed")

require "moonloader"
local sampev = require "samp.events"

-- =========================
-- DEFAULT VALUES (FALLBACK)
-- =========================
local enabled = true
local paused = false
local dangerHP = 500
local maxRepairPrice = 500

local shouldFix = false
local lastVehicle = nil

local fixCooldown = 0
local cooldownRunning = false

-- =========================
-- CONFIG (SAFE INIT)
-- =========================
local configDir  = getWorkingDirectory() .. "/config/AutoHoodPop/"
local configFile = configDir .. "AutoHoodPop.ini"

local inicfg
local cfg

-- =========================
-- MAIN
-- =========================
function main()
    while not isSampAvailable() do wait(100) end

    -- SAFE inicfg load (Android-safe)
    local ok
    ok, inicfg = pcall(require, "inicfg")

    if ok and inicfg then
        if not doesDirectoryExist(configDir) then
            createDirectory(configDir)
        end

        cfg = inicfg.load({
            Main = {
                enabled = true,
                dangerHP = 500,
                maxRepairPrice = 500
            }
        }, configFile)

        inicfg.save(cfg, configFile)

        -- 🔧 CRITICAL FIX: force correct types
        enabled = cfg.Main.enabled and true or false
        dangerHP = tonumber(cfg.Main.dangerHP) or 500
        maxRepairPrice = tonumber(cfg.Main.maxRepairPrice) or 500
    end

    sampAddChatMessage(
        "{33CCFF}AutoHoodPop Loaded{FFFFFF} | DangerHP: "
        .. dangerHP .. " | MaxRepair: $" .. maxRepairPrice,
        -1
    )

    sampRegisterChatCommand("ahp", toggleScript)
    sampRegisterChatCommand("ahphelp", showHelp)
    sampRegisterChatCommand("ahphealth", changeDangerHP)
    sampRegisterChatCommand("ahpmaxprice", changeMaxRepairPrice)

    while true do
        wait(200)

        if not enabled or paused then goto continue end

        local ped = PLAYER_PED
        if not ped then goto continue end

        -- =========================
        -- INSIDE VEHICLE
        -- =========================
        if isCharInAnyCar(ped) then
            local veh = storeCarCharIsInNoSave(ped)

            if veh ~= 0 then
                lastVehicle = veh
                local hp = getCarHealth(veh)

                if hp > 0 and hp <= dangerHP then
                    if not shouldFix then
                        sampSendChat("/car hood")
                        sampAddChatMessage(
                            "{33CCFF}Car damaged,{FFFFFF} exit to auto-fix.",
                            -1
                        )
                    end
                    shouldFix = true
                end
            end

        -- =========================
        -- OUTSIDE VEHICLE
        -- =========================
        else
            if shouldFix and lastVehicle ~= nil then
                if doesVehicleExist(lastVehicle) then
                    local hp = getCarHealth(lastVehicle)

                    if hp < 255 then
                        sampAddChatMessage(
                            "{33CCFF}AutoHoodPop:{FFFFFF} Fix canceled (HP < 255).",
                            -1
                        )
                    elseif isCarOnFire(lastVehicle) then
                        sampAddChatMessage(
                            "{33CCFF}AutoHoodPop:{FFFFFF} Fix canceled (on fire).",
                            -1
                        )
                    else
                        sampSendChat("/fix")
                    end
                end

                shouldFix = false
                lastVehicle = nil
            end
        end

        ::continue::
    end
end

-- =========================
-- COMMANDS
-- =========================
function toggleScript()
    enabled = not enabled
    if cfg then
        cfg.Main.enabled = enabled
        inicfg.save(cfg, configFile)
    end
    sampAddChatMessage(
        "{33CCFF}AutoHoodPop → {FFFFFF}" ..
        (enabled and "Enabled" or "Disabled"),
        -1
    )
end

function changeDangerHP(arg)
    local num = tonumber(arg)
    if not num or num < 250 or num > 999 then
        sampAddChatMessage(
            "{33CCFF}Usage:{FFFFFF} /ahphealth 250-999",
            -1
        )
        return
    end

    dangerHP = num
    if cfg then
        cfg.Main.dangerHP = num
        inicfg.save(cfg, configFile)
    end

    sampAddChatMessage(
        "{33CCFF}Danger HP updated to {FFFFFF}" .. dangerHP,
        -1
    )
end

function changeMaxRepairPrice(arg)
    local num = tonumber(arg)
    if not num or num < 0 then
        sampAddChatMessage(
            "{33CCFF}Usage:{FFFFFF} /ahpmaxprice <amount>",
            -1
        )
        return
    end

    maxRepairPrice = num
    if cfg then
        cfg.Main.maxRepairPrice = num
        inicfg.save(cfg, configFile)
    end

    sampAddChatMessage(
        "{33CCFF}Max repair price set to {FFFFFF}$" .. maxRepairPrice,
        -1
    )
end

function showHelp()
    sampAddChatMessage("{33CCFF}--- AutoHoodPop Commands ---", -1)
    sampAddChatMessage("{FFFFFF}/ahp {33CCFF}- Enable/Disable", -1)
    sampAddChatMessage("{FFFFFF}/ahphealth <hp> {33CCFF}- Set danger HP", -1)
    sampAddChatMessage("{FFFFFF}/ahpmaxprice <amount> {33CCFF}- Max repair accept price", -1)
    sampAddChatMessage("{FFFFFF}/ahphelp {33CCFF}- Show help", -1)
end

-- =========================
-- SERVER MESSAGE HANDLER
-- =========================
function sampev.onServerMessage(color, text)
    if not text then return end
    local lower = text:lower()

    if lower:find("you are not a mechanic") then
        paused = true
        sampAddChatMessage(
            "{33CCFF}AutoHoodPop → {FFFFFF}Paused (Not a mechanic)",
            -1
        )
        return
    end

    if lower:find("you are now a car mechanic") then
        paused = false
        sampAddChatMessage(
            "{33CCFF}AutoHoodPop → {FFFFFF}Resumed (Mechanic detected)",
            -1
        )
        return
    end

    -- Repair price filter
    local price = lower:match("%$(%d+)")
    if lower:find("wants to repair your car") and price then
        price = tonumber(price)
        if price <= maxRepairPrice then
            sampSendChat("/accept repair")
            sampAddChatMessage(
                "{33CCFF}AutoHoodPop → {FFFFFF}Accepted repair ($" .. price .. ")",
                -1
            )
        else
            sampAddChatMessage(
                "{33CCFF}AutoHoodPop → {FFFFFF}Repair declined ($" .. price .. ")",
                -1
            )
        end
        return
    end

    -- Fix cooldown
    local sec = text:match("You must wait (%d+) seconds!")
    if sec and not cooldownRunning then
        cooldownRunning = true
        lua_thread.create(function()
            local t = tonumber(sec)
            while t > 0 do wait(1000) t = t - 1 end
            sampAddChatMessage(
                "{33CCFF}AutoHoodPop → {FFFFFF}You may fix again.",
                -1
            )
            cooldownRunning = false
        end)
    end
end