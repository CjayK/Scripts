-- AutoVester Android (Option A patched - full script)
script_name("AutoVester Android")
script_author("Cjay La Muerte (patched)")
script_version("0.6-patched")

require "lib.moonloader"
local sampev = require "lib.samp.events"
local ok_imgui, imgui = pcall(require, "mimgui")
local lfs = require("lfs")
local ffi = require("ffi")

-- ============================================================
-- CONFIG
-- ============================================================
local configDir = getWorkingDirectory() .. "/config"
local configPath = string.format("%s/guardnear.ini", configDir)

local gangs = {
    { name = "The Bastards Motorcycle Club", short = "TBMC", skins = {1, 100, 181, 192, 236, 247, 248}, colorHex = "#491818" },
    { name = "Grove Street Families", short = "GSF", skins = {0,107,195,270,269,271,106,293}, colorHex = "#00FF00" },
    { name = "Yakuza", short = "YAK", skins = {49,193,60,123,263,186,210,122}, colorHex = "#FF0000" },
    { name = "Pirates", short = "CN", skins = {132,134,32,209,225,230,58}, colorHex = "#FF19D1" },
    { name = "Lynch Mob Ballas", short = "LMB", skins = {102,103,104,185,216,296,38}, colorHex = "#A120F0" },
    { name = "Bisaya Hand Triads", short = "BHT", skins = {294,59,117,118,120,141,169,208}, colorHex = "#BFBFBF" },
    { name = "East Side Bloods", short = "ESB", skins = {19,13,67,144,28,190,22}, colorHex = "#FF3300" },
    { name = "Extrema Nostra Tule", short = "ENT", skins = {91,125,124,126,94,93,249}, colorHex = "#00B0FF" },
    { name = "Varrios Los Aztecas", short = "VLA", skins = {175,268,114,115,116,174,44,53}, colorHex = "#00FFFF" },
    { name = "Genovese Mafia Family", short = "GMF", skins = {127,111,112,95,184,56,}, colorHex = "#34778a" }
}

local defaultCfg = {
    enabled = true,
    armorCheck = true,
    armorLevel = 50,
    price = 200,
    cooldown = 12,
    silent = false,
    debug = false,
    allyguard = true,
    selectedGangs = {}
}

local function ensureConfigDir()
    if not lfs.attributes(configDir, "mode") then lfs.mkdir(configDir) end
end

local function saveCfg()
    ensureConfigDir()
    local f = io.open(configPath, "w")
    if not f then return end
    f:write("enabled="..tostring(cfg.enabled).."\n")
    f:write("armorCheck="..tostring(cfg.armorCheck).."\n")
    f:write("armorLevel="..tostring(cfg.armorLevel).."\n")
    f:write("price="..tostring(cfg.price).."\n")
    f:write("cooldown="..tostring(cfg.cooldown).."\n")
    f:write("silent="..tostring(cfg.silent).."\n")
    f:write("debug="..tostring(cfg.debug).."\n")
    f:write("allyguard="..tostring(cfg.allyguard).."\n")

    -- save gangs (name, short, skins, color)
    for i=1,#gangs do
        local g = gangs[i]
        f:write(string.format("gang_%d_name=%s\n", i, tostring(g.name)))
        f:write(string.format("gang_%d_short=%s\n", i, tostring(g.short)))
        f:write(string.format("gang_%d_color=%s\n", i, tostring(g.colorHex or "#FFFFFF")))
        f:write(string.format("gang_%d_skins=%s\n", i, table.concat(g.skins, ",")))
    end

    -- save selected indices
    local sel = {}
    for i=1,#gangs do if cfg.selectedGangs[i] then table.insert(sel, tostring(i)) end end
    f:write("selectedGangs="..table.concat(sel, ",").."\n")
    f:close()
end

local function loadCfg()
    ensureConfigDir()
    local c = {}
    for k,v in pairs(defaultCfg) do c[k] = v end

    local f = io.open(configPath, "r")
    if not f then return c end

    local filedata = {}
    for line in f:lines() do
        local k,v = line:match("^(.-)=(.*)$")
        if k then filedata[k] = v end
    end
    f:close()

    if filedata["enabled"] then c.enabled = filedata["enabled"] == "true" end
    if filedata["armorCheck"] then c.armorCheck = filedata["armorCheck"] == "true" end
    if filedata["armorLevel"] then c.armorLevel = tonumber(filedata["armorLevel"]) or c.armorLevel end
    if filedata["price"] then c.price = tonumber(filedata["price"]) or c.price end
    if filedata["cooldown"] then c.cooldown = tonumber(filedata["cooldown"]) or c.cooldown end
    if filedata["silent"] then c.silent = filedata["silent"] == "true" end
    if filedata["debug"] then c.debug = filedata["debug"] == "true" end
    if filedata["allyguard"] then c.allyguard = filedata["allyguard"] == "true" end

    -- load gangs from file if present
    local i = 1
    local newGangs = {}
    while filedata[string.format("gang_%d_name", i)] do
        local name = filedata[string.format("gang_%d_name", i)] or ("Gang"..i)
        local short = filedata[string.format("gang_%d_short", i)] or ("G"..i)
        local color = filedata[string.format("gang_%d_color", i)] or "#FFFFFF"
        local skinsStr = filedata[string.format("gang_%d_skins", i)] or ""
        local skins = {}
        for n in skinsStr:gmatch("%d+") do table.insert(skins, tonumber(n)) end
        table.insert(newGangs, { name = name, short = short, colorHex = color, skins = skins })
        i = i + 1
    end
    -- remove "Everyone" entry if present
local filteredGangs = {}
for _, g in ipairs(newGangs) do
    if g.name ~= "Everyone" and g.short ~= "EVERY" then
        table.insert(filteredGangs, g)
    end
end
if #filteredGangs > 0 then gangs = filteredGangs end

    if filedata["selectedGangs"] then
        c.selectedGangs = {}
        for n in filedata["selectedGangs"]:gmatch("%d+") do c.selectedGangs[tonumber(n)] = true end
    end

    return c
end

-- load
cfg = loadCfg()
for i=1,#gangs do if cfg.selectedGangs[i] == nil then cfg.selectedGangs[i] = false end end

-- ============================================================
-- UTILITIES
-- ============================================================
local function msg(t) if not cfg.silent then sampAddChatMessage(t, -1) end end
local function dmsg(t) if cfg.debug then sampAddChatMessage("{00AFFF}[GuardNear DEBUG]{FFFFFF} "..t, -1) end end

local function anyGangSelected()
    for i=1,#gangs do if cfg.selectedGangs[i] then return true end end
    return false
end

local function skinAllowed(skin)
    -- if no gang selected -> allow all
    if not anyGangSelected() then return true end
    for gid,enabled in pairs(cfg.selectedGangs) do
        if enabled then
            local g = gangs[gid]
            if g and g.skins then
                for _,sid in ipairs(g.skins) do
                    if sid == skin then return true end
                end
            end
        end
    end
    return false
end

-- ============================================================
-- NEAREST PLAYER + SEND
-- ============================================================
local GUARD_RANGE = 10.0

local function isCoordsValid(x,y,z)
    return x and y and z and not (x==0 and y==0 and z==0) and x==x and y==y and z==z
end

local function send_guard_chat(cmd)
    if sampSendChat then sampSendChat(cmd) return true end
    if sampProcessChatInput then sampProcessChatInput(cmd) return true end
    return false
end

local function safeSendGuard(targetId)
    if not targetId or targetId < 0 then dmsg("invalid targetId") return false end
    local price = tonumber(cfg.price) or 0
    if price <= 0 then dmsg("invalid price "..tostring(cfg.price)) return false end

    local px,py,pz = getCharCoordinates(PLAYER_PED)
    if not isCoordsValid(px,py,pz) then dmsg("invalid player coords") return false end

    local ok,ped = sampGetCharHandleBySampPlayerId(targetId)
    if not ok or not ped or not doesCharExist(ped) then dmsg("target ped missing "..tostring(targetId)) return false end

    local tx,ty,tz = getCharCoordinates(ped)
    if not isCoordsValid(tx,ty,tz) then
        wait(60)
        tx,ty,tz = getCharCoordinates(ped)
        if not isCoordsValid(tx,ty,tz) then dmsg("target coords invalid") return false end
    end

    local dist = getDistanceBetweenCoords3d(px,py,pz,tx,ty,tz)
    if dist <= GUARD_RANGE then
        local cmd = string.format("/guard %d %d", targetId, price)
        if send_guard_chat(cmd) then dmsg("Guard sent id="..targetId) end
        return true
    end

    if dist <= GUARD_RANGE + 2 then
        for attempt=1,2 do
            wait(60)
            px,py,pz = getCharCoordinates(PLAYER_PED)
            ok,ped = sampGetCharHandleBySampPlayerId(targetId)
            if not ok or not ped or not doesCharExist(ped) then dmsg("ped lost during retry") return false end
            tx,ty,tz = getCharCoordinates(ped)
            if not isCoordsValid(tx,ty,tz) then dmsg("coords invalid on retry") return false end
            dist = getDistanceBetweenCoords3d(px,py,pz,tx,ty,tz)
            if dist <= GUARD_RANGE then
                local cmd = string.format("/guard %d %d", targetId, price)
                if send_guard_chat(cmd) then dmsg("Guard sent (retry) id="..targetId) end
                return true
            end
        end
    end

    return false
end

local function getClosestValidPlayer(maxDist)
    local px,py,pz = getCharCoordinates(PLAYER_PED)
    if not px then return -1 end
    local bestId, bestDist = -1, maxDist
    local maxId = sampGetMaxPlayerId and sampGetMaxPlayerId() or 0
    for id=0,maxId do
        if sampIsPlayerConnected(id) then
            if sampIsPlayerPaused and sampIsPlayerPaused(id) then goto continue end
            local ok,ped = sampGetCharHandleBySampPlayerId(id)
            if not ok or not ped or not doesCharExist(ped) then goto continue end
            local skin = getCharModel(ped)
            if not skinAllowed(skin) then dmsg("skip skin "..skin.." id "..id) goto continue end
            local tx,ty,tz = getCharCoordinates(ped)
            if not tx then goto continue end
            local dist = getDistanceBetweenCoords3d(px,py,pz,tx,ty,tz)
            if dist >= bestDist then goto continue end
            local armor = 0
            if sampGetPlayerArmor then armor = tonumber(sampGetPlayerArmor(id)) or 0 end
            if cfg.armorCheck and armor >= cfg.armorLevel then dmsg("ignored armor "..armor.." id "..id) goto continue end
            bestDist = dist
            bestId = id
        end
        ::continue::
    end
    return bestId
end

-- ============================================================
-- JOB CHECK STATE (NEW)
-- ============================================================
local awaitingStatsCheck = false
local statsLinesLeft = 0
local foundBodyguardInStats = false
-- ============================================================
-- COMMANDS & SERVER MSG
-- ============================================================
function toggle_guard() cfg.enabled = not cfg.enabled saveCfg() msg("{00AFFF}[GuardNear] "..(cfg.enabled and "enabled" or "disabled")) end
function toggle_silent() cfg.silent = not cfg.silent saveCfg() msg("{00AFFF}[GuardNear] Silent "..(cfg.silent and "enabled" or "disabled")) end
function toggle_debug() cfg.debug = not cfg.debug saveCfg() msg("{00AFFF}[GuardNear] Debug "..(cfg.debug and "on" or "off")) end

function cmd_help()
    sampAddChatMessage("{00AFFF}[GuardNear Commands]", -1)
    sampAddChatMessage("{00AFFF}/guardnear {FFFFFF}- toggle auto guard", -1)
    sampAddChatMessage("{00AFFF}/allyguard {FFFFFF}- open gang filter menu", -1)
    sampAddChatMessage("{00AFFF}/silentguard {FFFFFF}- toggle silent mode", -1)
    sampAddChatMessage("{00AFFF}/guarddebug {FFFFFF}- toggle debug mode", -1)
end

local isBodyguard = true

function sampev.onServerMessage(color, text)
    if not text then return end
    local clean = tostring(text):gsub("{.-}", "")
    local t = clean:lower()

    -- LOGIN / SPAWN DETECT → TRIGGER /stats
if not awaitingStatsCheck then
    if clean:match("^Welcome to Horizon Roleplay,") then

        awaitingStatsCheck = true
        statsLinesLeft = 6
        foundBodyguardInStats = false

        lua_thread.create(function()
            wait(800) -- Android-safe delay
            sampSendChat("/stats")
        end)

        dmsg("Spawn detected (Horizon RP) → requesting /stats")
        return
    end
end

    --------------------------------------------------
    -- STATS CAPTURE WINDOW (NEXT 6 MESSAGES)
    --------------------------------------------------
    if awaitingStatsCheck and statsLinesLeft > 0 then
        statsLinesLeft = statsLinesLeft - 1

        if t:find("bodygu") then
            foundBodyguardInStats = true
        end

        if statsLinesLeft <= 0 then
            awaitingStatsCheck = false

            if not foundBodyguardInStats then
                isBodyguard = false
                cfg.enabled = false
                saveCfg()
                msg("{FF0000}[GuardNear] Auto-guard paused (Bodyguard job not detected).")
            else
                isBodyguard = true
                cfg.enabled = true
                saveCfg()
                msg("{00FF00}[GuardNear] Bodyguard job confirmed. Auto-guard active.")
            end
        end

        return
    end

    --------------------------------------------------
    -- JOB LOST
    --------------------------------------------------
    if t:find("you are not a bodyguard") then
        isBodyguard = false
        cfg.enabled = false
        saveCfg()
        msg("{FF0000}[GuardNear] Auto-guard paused. (Not bodyguard)")
        return
    end

    --------------------------------------------------
    -- JOB GAINED
    --------------------------------------------------
    if t:find("you are now a bodyguard") then
        isBodyguard = true
        cfg.enabled = true
        saveCfg()
        msg("{00FF00}[GuardNear] Auto-guard resumed.")
        return
    end

    --------------------------------------------------
    -- DISTANCE FAIL RETRY
    --------------------------------------------------
    if t:find("isn't near you") or t:find("is not near you") then
        forceRetry = true
        dmsg("Distance fail → will retry nearest player immediately")
        return
    end
end

-- Thread to retry nearest player if distance fails
lua_thread.create(function()
    while true do
        wait(500)  -- check every 0.5 seconds
        if forceRetry and cfg.enabled and isBodyguard then
            local id = getClosestValidPlayer(GUARD_RANGE + 5)
            if id >= 0 then
                if safeSendGuard(id) then
                    forceRetry = false  -- reset after successful retry
                end
            end
        end
    end
end)
-- ============================================================
-- UI STATE
-- ============================================================
local menu = {}
local gangPtrs = {}
local gangSkinInputs = {}
local gangColorInputs = {}
local cfgPtrs = {}
local prevMenuOpen = false
local editingIdx = 0 -- 0=no popup, >0 gang index to edit skins
local skinEditBuf = imgui and imgui.new.char and imgui.new.char[512]("") or nil
local addNameBuf, addShortBuf, addColorBuf, addSkinsBuf

if ok_imgui then
    menu.open = imgui.new.bool(false)
    for i=1,#gangs do
        gangPtrs[i] = imgui.new.bool(cfg.selectedGangs[i] or false)
        gangSkinInputs[i] = imgui.new.char[256](table.concat(gangs[i].skins,","))
        gangColorInputs[i] = imgui.new.char[16](gangs[i].colorHex or "#FFFFFF")
    end
    addNameBuf = imgui.new.char[64]("")
    addShortBuf = imgui.new.char[8]("")
    addColorBuf = imgui.new.char[16]("#FFFFFF")
    addSkinsBuf = imgui.new.char[256]("")

    cfgPtrs = {
        cooldown = imgui.new.int(cfg.cooldown),
        price    = imgui.new.int(cfg.price),
        armor    = imgui.new.int(cfg.armorLevel)
    }
end

local function parseHexToRGB(hex)
    if not hex then return 1,1,1 end
    hex = tostring(hex):gsub("#","")
    if #hex ~= 6 then return 1,1,1 end
    local r = tonumber(hex:sub(1,2),16)/255
    local g = tonumber(hex:sub(3,4),16)/255
    local b = tonumber(hex:sub(5,6),16)/255
    return r,g,b
end

local function hexToChatColor(h)
    if not h then return "FFFFFF" end
    h = tostring(h):gsub("#","")
    if #h ~= 6 then return "FFFFFF" end
    return h:upper()
end

-- ============================================================
-- GANG EDITING FUNCTIONS
-- ============================================================
local function addEmptyGang()
    local new = { name = "New Gang", short = "NEW", skins = {}, colorHex = "#FFFFFF" }
    table.insert(gangs, new)
    local idx = #gangs
    cfg.selectedGangs[idx] = false
    if ok_imgui then
        gangPtrs[idx] = imgui.new.bool(false)
        gangSkinInputs[idx] = imgui.new.char[256]("")
        gangColorInputs[idx] = imgui.new.char[16]("#FFFFFF")
    end
    saveCfg()
    sampAddChatMessage("{00FF00}[GuardNear] Added empty gang (index "..idx..")", -1)
end

local function addGangFromInputs()
    local name = ffi.string(addNameBuf):gsub("^%s*(.-)%s*$","%1")
    local short = ffi.string(addShortBuf):gsub("^%s*(.-)%s*$","%1")
    local color = ffi.string(addColorBuf):gsub("%s*","")
    local skinsStr = ffi.string(addSkinsBuf)
    if name == "" or short == "" then sampAddChatMessage("{FFCC00}[GuardNear] Add Gang: name and short required.", -1) return end
    short = short:upper()
    for _,g in ipairs(gangs) do if g.short == short then sampAddChatMessage("{FF0000}[GuardNear] Shortname exists.", -1) return end end
    local skins = {}
    for n in skinsStr:gmatch("%d+") do table.insert(skins, tonumber(n)) end
    color = color:match("^#?%x%x%x%x%x%x$") and ("#"..color:gsub("#","")) or "#FFFFFF"
    table.insert(gangs, { name = name, short = short, skins = skins, colorHex = color })
    local idx = #gangs
    cfg.selectedGangs[idx] = false
    if ok_imgui then
        gangPtrs[idx] = imgui.new.bool(false)
        gangSkinInputs[idx] = imgui.new.char[256](table.concat(skins,","))
        gangColorInputs[idx] = imgui.new.char[16](color)
    end
    saveCfg()
    sampAddChatMessage("{00FF00}[GuardNear] Added gang: "..name.." ("..short..") "..color, -1)
    ffi.copy(addNameBuf,"")
    ffi.copy(addShortBuf,"")
    ffi.copy(addSkinsBuf,"")
    ffi.copy(addColorBuf,"#FFFFFF")
end

local function removeGang(index)
    if index < 1 or index > #gangs then return end
    -- allow removal, but ensure at least one gang remains
    if #gangs <= 1 then sampAddChatMessage("{FFCC00}[GuardNear] Cannot remove final gang.", -1) return end
    local name = gangs[index].name
    table.remove(gangs, index)
    table.remove(cfg.selectedGangs, index)
    if ok_imgui then
        table.remove(gangPtrs, index)
        table.remove(gangSkinInputs, index)
        table.remove(gangColorInputs, index)
    end
    saveCfg()
    sampAddChatMessage("{FF0000}[GuardNear] Removed gang: "..name.." (index "..index..")", -1)
end

-- skin editor actions
local function openSkinEditor(idx)
    if not ok_imgui then return end
    editingIdx = idx
    -- initialize the popup buffer with current skins joined
    local s = table.concat(gangs[idx].skins, ",")
    if not gangSkinInputs[idx] then gangSkinInputs[idx] = imgui.new.char[256](s) end
    -- use that buffer as the edit buffer in popup
end

local function saveSkinEditor(idx)
    if not idx or not gangSkinInputs[idx] then return end
    local str = ffi.string(gangSkinInputs[idx])
    local arr = {}
    for n in str:gmatch("%d+") do table.insert(arr, tonumber(n)) end
    gangs[idx].skins = arr
    saveCfg()
end

local function sendAllySummary()
    local sel = {}
    for i=1,#gangs do
        if cfg.selectedGangs[i] and gangs[i] then
            local colorCode = hexToChatColor(gangs[i].colorHex)
            table.insert(sel, string.format("{%s}%s{FFFFFF}", colorCode, gangs[i].short or "?"))
        end
    end
    if #sel == 0 then
        msg("{00AFFF}[GuardNear] Allies: NONE selected — vesting anyone nearby.")
    else
        msg("{00AFFF}[GuardNear] Allies: " .. table.concat(sel, ", "))
    end
end

-- ============================================================
-- UI RENDER (big window)
-- ============================================================
-- ensure menu.open is a bool pointer
if not menu.open or type(menu.open) ~= "cdata" then
    menu.open = imgui.new.bool(false)
end

local skinEditorOpen = imgui.new.bool(false)

local function renderMenu()
    if not ok_imgui then return end

    imgui.SetNextWindowSize(imgui.ImVec2(1200, 680), imgui.Cond.FirstUseEver)

    if not imgui.Begin("Ally Guard Menu", menu.open, imgui.WindowFlags.NoResize) then
        imgui.End()
        return
    end

    -- two main columns (this is fine)
    imgui.Columns(2, "MainCols", true)
    imgui.SetColumnWidth(0, 800)
    imgui.SetColumnWidth(1, 380)

    -- LEFT: gangs
    imgui.TextColored(imgui.ImVec4(0.0, 0.6, 1.0, 1.0), "Gangs")
    imgui.Separator()

    imgui.BeginChild("GangsScroll", imgui.ImVec2(0, 0), true)

    for i = 1, #gangs do
        local g = gangs[i]

        if not gangPtrs[i] then
            gangPtrs[i] = imgui.new.bool(cfg.selectedGangs[i] or false)
        end
        if not gangSkinInputs[i] then
            gangSkinInputs[i] = imgui.new.char[256](table.concat(g.skins, ","))
        end
        if not gangColorInputs[i] then
            gangColorInputs[i] = imgui.new.char[16](g.colorHex or "#FFFFFF")
        end

        -- row 1
        if imgui.Checkbox("##chk"..i, gangPtrs[i]) then
            cfg.selectedGangs[i] = gangPtrs[i][0]
            saveCfg()
        end
        imgui.SameLine()
        imgui.Text(string.format("%s [%s]", g.name or ("Gang"..i), g.short or ""))

        imgui.SameLine(imgui.GetWindowWidth() - 200)
        if imgui.SmallButton("Edit##"..i) then
            editingIdx = i
            skinEditorOpen[0] = true
        end
        imgui.SameLine()
        if imgui.SmallButton("X##"..i) then
            removeGang(i)
            break
        end

        -- row 2
        imgui.SetNextItemWidth(100)
        if imgui.InputText("##color"..i, gangColorInputs[i], 16) then
            local s = ffi.string(gangColorInputs[i]):gsub("%s*", "")
            if s:match("^#?%x%x%x%x%x%x$") then
                if s:sub(1,1) ~= "#" then s = "#" .. s end
                g.colorHex = s
                saveCfg()
            end
        end

        local r, gc, b = parseHexToRGB(g.colorHex or "#FFFFFF")
        imgui.SameLine()
        imgui.ColorButton(
            "##preview"..i,
            imgui.ImVec4(r, gc, b, 1.0),
            imgui.ColorEditFlags.NoTooltip + imgui.ColorEditFlags.NoDragDrop
        )

        imgui.TextDisabled(
            "Skins: " .. ((#g.skins > 0) and table.concat(g.skins, ", ") or "(none)")
        )

        imgui.Separator()
    end

    imgui.EndChild()
    imgui.NextColumn()

    -- RIGHT: config
    imgui.TextColored(imgui.ImVec4(0.1, 0.6, 0.9, 1.0), "Add Gang / Guard Config")
    imgui.Separator()

    imgui.BeginChild("ConfigScroll", imgui.ImVec2(0, 0), false)

    imgui.Text("Add Empty Gang (quick)")
    if imgui.Button("Add Empty Gang", imgui.ImVec2(-1, 28)) then
        addEmptyGang()
    end

    imgui.Separator()
    imgui.Text("Add Gang (full)")

    imgui.Text("Name")
    imgui.InputText("##addName", addNameBuf, 64)
    imgui.Text("Short")
    imgui.InputText("##addShort", addShortBuf, 8)
    imgui.Text("Color Hex")
    imgui.InputText("##addColor", addColorBuf, 16)
    imgui.Text("Skins (comma separated)")
    imgui.InputText("##addSkins", addSkinsBuf, 256)

    if imgui.Button("Add Gang (create)", imgui.ImVec2(-1, 28)) then
        addGangFromInputs()
    end

    imgui.Separator()
    imgui.Text("Guard Config")

    imgui.PushItemWidth(120)
    if imgui.InputInt("Cooldown (sec)", cfgPtrs.cooldown) then
        cfg.cooldown = cfgPtrs.cooldown[0]
        saveCfg()
    end
    if imgui.InputInt("Price", cfgPtrs.price) then
        cfg.price = cfgPtrs.price[0]
        saveCfg()
    end
    if imgui.InputInt("Armor Level", cfgPtrs.armor) then
        cfg.armorLevel = cfgPtrs.armor[0]
        saveCfg()
    end
    imgui.PopItemWidth()

    if imgui.Button("Save Config", imgui.ImVec2(-1, 28)) then
        saveCfg()
        sampAddChatMessage("{00FF00}[GuardNear] Config saved.", -1)
    end

    imgui.EndChild()
    imgui.Columns(1)
    imgui.End()

    -- Skin editor popup
    if skinEditorOpen[0] and editingIdx > 0 and gangs[editingIdx] then
        local g = gangs[editingIdx]
        imgui.SetNextWindowSize(imgui.ImVec2(480, 360), imgui.Cond.FirstUseEver)
        if imgui.Begin("Skin Editor - "..(g.name or ""), skinEditorOpen, imgui.WindowFlags.NoResize) then
            imgui.InputTextMultiline(
                "##skinEditorBuf",
                gangSkinInputs[editingIdx],
                256,
                imgui.ImVec2(-1, 220)
            )

            if imgui.Button("Save Skins") then
                saveSkinEditor(editingIdx)
            end
            imgui.SameLine()
            if imgui.Button("Close") then
                saveSkinEditor(editingIdx)
                editingIdx = 0
                skinEditorOpen[0] = false
            end
            imgui.End()
        end
    end

    if prevMenuOpen and not menu.open[0] then
        sendAllySummary()
    end
    prevMenuOpen = menu.open[0]
end

if ok_imgui then
    imgui.OnInitialize(function()
        imgui.GetIO().IniFilename = nil
    end)
    imgui.OnFrame(function()
        return menu.open[0] and not isPauseMenuActive()
    end, renderMenu)
end

-- ============================================================
-- MAIN LOOP
-- ============================================================
function main()
    repeat wait(0) until isSampAvailable()

    sampAddChatMessage(
        "{00AFFF}[GuardNear] {FFFFFF}loaded | Author: {FFFF00}Cjay La Muerte - {00AFFF}[/guardnearhelp]",
        -1
    )

    sampRegisterChatCommand("guardnear", toggle_guard)
    sampRegisterChatCommand("allyguard", function()
        if not ok_imgui then
            msg("{FFCC00}[GuardNear] GUI not available.")
            return
        end
        menu.open[0] = not menu.open[0]
        if menu.open[0] then
            for i = 1, #gangs do
                if gangPtrs[i] then
                    gangPtrs[i][0] = cfg.selectedGangs[i] or false
                end
            end
        else
            sendAllySummary()
        end
    end)

    sampRegisterChatCommand("guardcfg", function()
        if ok_imgui then menu.cfg_open = not menu.cfg_open end
    end)
    sampRegisterChatCommand("silentguard", toggle_silent)
    sampRegisterChatCommand("guarddebug", toggle_debug)
    sampRegisterChatCommand("guardnearhelp", cmd_help)

    local forceRetry = false -- retry nearest immediately if distance fail occurs

    while true do
        wait(120)

        if not cfg.enabled or not isBodyguard then
            goto continue
        end

        -- ALWAYS re-evaluate nearest player
        local id = getClosestValidPlayer(12.0)

        if id and id ~= -1 then
            dmsg("Candidate id=" .. id .. " found for guard attempt")

            local sent = safeSendGuard(id)
            if sent then
                dmsg("Guard sent successfully to id=" .. id)
                forceRetry = false
                wait((tonumber(cfg.cooldown) or 8) * 1000)
            else
                if forceRetry then
                    -- ignore cooldown, retry nearest immediately
                    wait(120)
                else
                    wait(150)
                end
            end
        end

        ::continue::
    end
end