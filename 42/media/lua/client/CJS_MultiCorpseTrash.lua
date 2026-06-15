require "ISUI/ISWorldObjectContextMenu"
require "TimedActions/ISInventoryTransferAction"

CJSMultiCorpseTrash = CJSMultiCorpseTrash or {}
CJSMultiCorpseTrash.version = "0.1.0"

local unpackArgs = unpack or table.unpack

local trashNameTokens = {
    "dumpster",
    "garbage",
    "public garbage",
    "recycle bin",
    "round bin",
    "trash can",
    "wheeliebin",
    "wheelie bin",
}

local function call(object, methodName, ...)
    if not object then return nil end

    local method = object[methodName]
    if not method then return nil end

    local args = { ... }
    local ok, result = pcall(function()
        return method(object, unpackArgs(args))
    end)

    if ok then return result end
    return nil
end

local function lower(value)
    if value == nil then return "" end
    return string.lower(tostring(value))
end

local function hasText(value)
    return value ~= nil and value ~= false and tostring(value) ~= ""
end

local function isCorpseItem(item)
    local itemType = call(item, "getType")
    return itemType == "CorpseMale" or itemType == "CorpseFemale"
end

local function carriedCorpse(playerObj)
    local primary = call(playerObj, "getPrimaryHandItem")
    if isCorpseItem(primary) then return primary end

    local secondary = call(playerObj, "getSecondaryHandItem")
    if isCorpseItem(secondary) then return secondary end

    local inventory = call(playerObj, "getInventory")
    if inventory then
        return call(inventory, "getFirstEvalRecurse", isCorpseItem)
    end

    return nil
end

local function spriteProperties(object)
    local sprite = call(object, "getSprite")
    if not sprite then return nil end
    return call(sprite, "getProperties")
end

local function propertyIs(object, name)
    local props = spriteProperties(object)
    if not props then return false end

    local ok, result = pcall(function()
        return props:Is(name)
    end)

    return ok and result == true
end

local function propertyValue(object, name)
    local props = spriteProperties(object)
    if not props then return nil end

    local ok, result = pcall(function()
        if not props:Is(name) then return nil end
        return props:Val(name)
    end)

    if ok then return result end
    return nil
end

local function objectDisplayName(object)
    local customName = propertyValue(object, "CustomName")
    local groupName = propertyValue(object, "GroupName")

    if hasText(groupName) and hasText(customName) then
        return tostring(groupName) .. " " .. tostring(customName)
    end

    if hasText(customName) then return tostring(customName) end
    return tostring(call(object, "getName") or "")
end

local function containsTrashName(value)
    value = lower(value)
    if value == "" then return false end

    for _, token in ipairs(trashNameTokens) do
        if string.find(value, token, 1, true) then return true end
    end

    return false
end

local function isTrashCanObject(object)
    if not object then return false end
    if instanceof and instanceof(object, "IsoWorldInventoryObject") then return false end

    local container = call(object, "getContainer")
    if not container then return false end

    if propertyIs(object, "IsTrashCan") then return true end
    if containsTrashName(objectDisplayName(object)) then return true end
    if containsTrashName(call(container, "getType")) then return true end

    return false
end

local function squareKey(square)
    if not square then return nil end
    return tostring(call(square, "getX")) .. ":" .. tostring(call(square, "getY")) .. ":" .. tostring(call(square, "getZ"))
end

local function scanSquareForTrashCan(square)
    local objects = call(square, "getObjects")
    if not objects then return nil end

    for index = objects:size() - 1, 0, -1 do
        local object = objects:get(index)
        if isTrashCanObject(object) then
            return object
        end
    end

    return nil
end

local function scanAround(square, scan)
    if not square then return nil end

    local trashCan = scan(square)
    if trashCan then return trashCan end

    local cell = getCell and getCell()
    if not cell then return nil end

    local x = call(square, "getX")
    local y = call(square, "getY")
    local z = call(square, "getZ")
    if x == nil or y == nil or z == nil then return nil end

    for dx = -1, 1 do
        for dy = -1, 1 do
            if dx ~= 0 or dy ~= 0 then
                trashCan = scan(cell:getGridSquare(x + dx, y + dy, z))
                if trashCan then return trashCan end
            end
        end
    end

    return nil
end

local function findTrashCan(worldobjects, playerObj)
    local checked = {}

    local function scan(square)
        local key = squareKey(square)
        if not key or checked[key] then return nil end
        checked[key] = true
        return scanSquareForTrashCan(square)
    end

    for _, object in ipairs(worldobjects or {}) do
        local trashCan = scan(call(object, "getSquare"))
        if trashCan then return trashCan end
    end

    local fetch = ISWorldObjectContextMenu and ISWorldObjectContextMenu.fetchVars
    local trashCan = scanAround(fetch and fetch.clickedSquare, scan)
    if trashCan then return trashCan end

    return scanAround(call(playerObj, "getCurrentSquare"), scan)
end

local function addTooltip(option, name, description)
    if not option then return end

    local tip = ISWorldObjectContextMenu.addToolTip()
    tip:setName(name)
    tip.description = description
    option.toolTip = tip
end

local function putCorpseInTrash(playerObj, trashCan, corpse)
    if not playerObj or not trashCan or not isCorpseItem(corpse) then return end

    local container = call(trashCan, "getContainer")
    local source = call(corpse, "getContainer")
    if not container or not source then return end
    if call(container, "isItemAllowed", corpse) ~= true then return end

    local playerNum = call(playerObj, "getPlayerNum") or 0
    if luautils and luautils.walkToContainer then
        if not luautils.walkToContainer(container, playerNum) then return end
    elseif luautils and luautils.walkAdj then
        if not luautils.walkAdj(playerObj, call(trashCan, "getSquare"), true) then return end
    end

    ISTimedActionQueue.add(ISInventoryTransferAction:new(playerObj, corpse, source, container))
end

local function setContextTest()
    if ISWorldObjectContextMenu and ISWorldObjectContextMenu.setTest then
        return ISWorldObjectContextMenu.setTest()
    end

    return true
end

local function onFillWorldObjectContextMenu(player, context, worldobjects, test)
    if test and ISWorldObjectContextMenu.Test then return true end

    local playerObj = getSpecificPlayer(player)
    if not playerObj or call(playerObj, "getVehicle") then return end

    local corpse = carriedCorpse(playerObj)
    if not corpse then return end

    local trashCan = findTrashCan(worldobjects, playerObj)
    if not trashCan then return end

    local container = call(trashCan, "getContainer")
    if not container or call(container, "isItemAllowed", corpse) ~= true then return end

    if test then return setContextTest() end

    local optionName = "Put Corpse in Garbage"
    local option = context:addOption(optionName, playerObj, putCorpseInTrash, trashCan, corpse)
    if call(container, "hasRoomFor", playerObj, corpse) == false then
        option.notAvailable = true
        addTooltip(option, optionName, "This trash can does not have room for the carried corpse.")
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
print("[cjsMultiCorpseTrash] Loaded client " .. CJSMultiCorpseTrash.version)
