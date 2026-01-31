script_author("CjayK")
script_version("0.5.0")

local ok_sampev, sampev = pcall(require, "samp.events")
local ok_imgui, imgui = pcall(require, "mimgui")
local ok_fa, fa = pcall(require, "fAwesome6")

require "monetloader"
local encoding = require "encoding"
encoding.default = "CP1251"
u8 = encoding.UTF8


---

-- CONFIG

local cfgDir = getWorkingDirectory() .. "/config"
local cfgPath = cfgDir .. "/trucker.cfg"

local defaultConfig = {
enable = 0,
truckMode = 1,
loadRP = "loads the cargo carefully.",
unloadRP = "unloads the cargo carefully."
}

local function ensureConfigDir()
local ok = os.rename(cfgDir, cfgDir)
if not ok then os.execute("mkdir " .. cfgDir) end
end

local function loadCFG()
ensureConfigDir()
local cfg = {}

local file = io.open(cfgPath, "r")  
if file then  
    for line in file:lines() do  
        local key, value = line:match("^(.-)=(.+)$")  
        if key and value then  
            value = tonumber(value) or value  
            cfg[key] = value  
        end  
    end  
    file:close()  
end  

for k,v in pairs(defaultConfig) do  
    if cfg[k] == nil then cfg[k] = v end  
end  

return cfg

end

local function saveCFG(cfg)
ensureConfigDir()
local file = io.open(cfgPath, "w")
if not file then return end
for k, v in pairs(cfg) do
file:write(string.format("%s=%s\n", k, tostring(v)))
end
file:close()
end

local trucker = loadCFG()


---

-- AUTO ROLEPLAY FUNCTIONS

local function sendLoadRP()
if trucker.loadRP and trucker.loadRP ~= "" then
sampSendChat("/me " .. trucker.loadRP)
end
end

local function sendUnloadRP()
if trucker.unloadRP and trucker.unloadRP ~= "" then
sampSendChat("/me " .. trucker.unloadRP)
end
end


---

-- TRUCK COMMANDS

local goods = 0

local function sendLoad(code)
goods = code
sendLoadRP() -- Trigger load RP
if sampProcessChatInput then
sampProcessChatInput("/loadtruck")
else
sampSendChat("/loadtruck")
end
end

function cmd_autoload()
sampAddChatMessage("{FF0000}Loading selected cargo...", -1)
local map = { [1]=912, [2]=914, [3]=913, [4]=911 }
local code = map[trucker.truckMode] or 912
sendLoad(code)
end

function cmd_canceltruck()
sendUnloadRP() -- Trigger unload RP
if sampProcessChatInput then
sampProcessChatInput("/cancel truck")
else
sampSendChat("/cancel truck")
end
end


---

-- OLD LOAD COMMANDS (kept)

function cmd_bloadtruck() sampAddChatMessage("{CFCFCF}Loading legal materials...", -1); sendLoad(912) end
function cmd_wloadtruck() sampAddChatMessage("{CFCFCF}Loading illegal weapons...", -1); sendLoad(914) end
function cmd_cloadtruck() sampAddChatMessage("{CFCFCF}Loading narcotics...", -1); sendLoad(913) end
function cmd_mloadtruck() sampAddChatMessage("{CFCFCF}Loading illegal materials...", -1); sendLoad(911) end


---

-- DIALOG HANDLER

if ok_sampev then
function sampev.onShowDialog(id, style, title, btn1, btn2, text)
if goods == 0 then return true end
if goods == 911 then
if id == 185 then sampSendDialogResponse(185,1,1,nil) return false end
if id == 187 then sampSendDialogResponse(187,1,2,nil) goods=0 return false end
end
if goods == 912 then
if id == 185 then sampSendDialogResponse(185,1,0,nil) return false end
if id == 186 then sampSendDialogResponse(186,1,3,nil) goods=0 return false end
end
if goods == 913 then
if id == 185 then sampSendDialogResponse(185,1,1,nil) return false end
if id == 187 then sampSendDialogResponse(187,1,1,nil) goods=0 return false end
end
if goods == 914 then
if id == 185 then sampSendDialogResponse(185,1,1,nil) return false end
if id == 187 then sampSendDialogResponse(187,1,0,nil) goods=0 return false end
end
return true
end
end


---

-- IMGUi MENU

local menu = {}
if ok_imgui then
menu.enable = imgui.new.bool(false)
menu.truckMode = imgui.new.int(trucker.truckMode)
menu.loadText = imgui.new.char[256](trucker.loadRP or "")
menu.unloadText = imgui.new.char[256](trucker.unloadRP or "")
end

local ffi = require "ffi"

local function RadioButton(label, ptr, value)
local clicked = false
local DL = imgui.GetWindowDrawList()
local size = imgui.ImVec2(22,22)
local pos = imgui.GetCursorScreenPos()
local center = imgui.ImVec2(pos.x + 11, pos.y + 11)

DL:AddCircle(center, 10, imgui.GetColorU32Vec4(imgui.ImVec4(1,0,0,1)), 32, 2)  
if ptr[0] == value then  
    DL:AddCircleFilled(center, 6, imgui.GetColorU32Vec4(imgui.ImVec4(1,0,0,1)), 32)  
end  

if imgui.InvisibleButton(label.."##RB"..value, size) then  
    ptr[0] = value  
    clicked = true  
end  

imgui.SameLine()  
imgui.TextColored(imgui.ImVec4(0.84,0.84,0.84,1.0), label)  
return clicked

end

local function render_menu()
imgui.SetNextWindowSize(imgui.ImVec2(480,0), imgui.Cond.FirstUseEver) -- width fixed, height auto

if menu.enable[0] and imgui.Begin("Auto Truck Menu##ATM", menu.enable) then  

    --------------------------------------------------  
    -- Quick Actions  
    --------------------------------------------------  
    imgui.TextColored(imgui.ImVec4(1,0,0,1), "Quick Actions")  
    imgui.Spacing()  
    if imgui.Button("Load", imgui.ImVec2(240, 70)) then cmd_autoload() end  
    imgui.SameLine()  
    if imgui.Button("Unload", imgui.ImVec2(240, 70)) then cmd_canceltruck() end  
    imgui.Spacing()  
    imgui.Separator()  
    imgui.Spacing()  

    --------------------------------------------------  
    -- Collapsible Truck Mode  
    --------------------------------------------------  
    if imgui.CollapsingHeader("Truck Mode", true, imgui.TreeNodeFlags.DefaultOpen) then  
        local labels = {  
            "Legal Business Materials",  
            "Illegal Weapons",  
            "Illegal Narcotics",  
            "Illegal Materials"  
        }  
        for i, label in ipairs(labels) do  
            if RadioButton(label, menu.truckMode, i) then  
                trucker.truckMode = i  
                saveCFG(trucker)  
            end  
        end  
        imgui.Spacing()  
    end  

    --------------------------------------------------  
    -- Collapsible Auto Roleplay  
    --------------------------------------------------  
    if imgui.CollapsingHeader("Auto Roleplay", true, imgui.TreeNodeFlags.DefaultOpen) then  
        imgui.Text("Load RP")  
        if imgui.InputText("##LOADRPINPUT", menu.loadText, 256) then  
            trucker.loadRP = ffi.string(menu.loadText)  
            saveCFG(trucker)  
        end  

        imgui.Text("Unload RP")  
        if imgui.InputText("##UNLOADRPINPUT", menu.unloadText, 256) then  
            trucker.unloadRP = ffi.string(menu.unloadText)  
            saveCFG(trucker)  
        end  
        imgui.Spacing()  
    end  

    imgui.End()  
end

end

if ok_imgui then
imgui.OnInitialize(function() imgui.GetIO().IniFilename = nil end)
imgui.OnFrame(function() return menu.enable[0] and not isPauseMenuActive() end, render_menu)
end


---

-- MAIN

function onScriptTerminate(scr)
if scr == thisScript() then saveCFG(trucker) end
end

function main()
while not isSampAvailable() do wait(0) end

sampRegisterChatCommand("truckmenu", function()  
    if not ok_imgui then  
        sampAddChatMessage("{FF0000}Menu unavailable (mimgui missing)", -1)  
        return  
    end  
    menu.enable[0] = not menu.enable[0]  
end)  

sampRegisterChatCommand("autoload", cmd_autoload)  
sampRegisterChatCommand("canceltruck", cmd_canceltruck)  

sampRegisterChatCommand("bloadtruck", cmd_bloadtruck)  
sampRegisterChatCommand("wloadtruck", cmd_wloadtruck)  
sampRegisterChatCommand("cloadtruck", cmd_cloadtruck)  
sampRegisterChatCommand("mloadtruck", cmd_mloadtruck)  

sampRegisterChatCommand("loadtruckhelp", function()  
    sampAddChatMessage("{CFCFCF}------------------------------", -1)  
    sampAddChatMessage("{FF0000}/autoload {CFCFCF}- load via menu mode", -1)  
    sampAddChatMessage("{FF0000}/canceltruck {CFCFCF}- cancel current delivery", -1)  
    sampAddChatMessage("{FF0000}/truckmenu {CFCFCF}- open menu", -1)  
    sampAddChatMessage("{CFCFCF}------------------------------", -1)  
end)  

sampAddChatMessage("{FF0000}[TruckMenu] {CFCFCF}Loaded. Use {FF0000}/truckmenu", -1)  

while true do wait(0) end

end