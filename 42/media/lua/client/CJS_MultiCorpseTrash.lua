require "ISUI/ISWorldObjectContextMenu"
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISGrabCorpseAction"
require "TimedActions/ISInventoryTransferAction"
pcall(require, "PickupCorpse/TimedActions/ISPickupCorpseAction")

CJSMultiCorpseTrash = CJSMultiCorpseTrash or {}
CJSMultiCorpseTrash.version = "0.1.11"
CJSMultiCorpseTrash.draggedCorpseByPlayer = CJSMultiCorpseTrash.draggedCorpseByPlayer or {}

local unpackArgs = unpack or table.unpack

local defaults = {
    DebugLogging = false,
}

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

local zuperCartItemTypes = {
    ["TMC.CartContainer"] = true,
    ["TMC.CartContainer2"] = true,
    ["TMC.TrolleyContainer"] = true,
    ["TMC.TrolleyContainer2"] = true,
}

local saucedCartItemTypes = {
    ["SaucedCarts.ShoppingCart"] = true,
}

local function isObjectLike(object)
    local objectType = type(object)
    return objectType == "table" or objectType == "userdata"
end

local function call(object, methodName, ...)
    if not object then return nil end
    if not isObjectLike(object) then return nil end

    local okMethod, method = pcall(function()
        return object[methodName]
    end)
    if not okMethod then return nil end
    if not method then return nil end

    local argCount = select("#", ...)
    local args = { ... }
    local ok, result = pcall(function()
        return method(object, unpackArgs(args, 1, argCount))
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

local function getSandboxVars()
    return SandboxVars and SandboxVars.CJSMultiCorpseTrash or nil
end

local function option(key)
    local vars = getSandboxVars()
    if vars and vars[key] ~= nil then
        return vars[key]
    end

    return defaults[key]
end

local function isDebugLoggingEnabled()
    return option("DebugLogging") == true
end

local function debugLog(message)
    if not isDebugLoggingEnabled() then return end

    if type(message) == "function" then
        message = message()
    end

    print("[cjsMultiCorpseTrash] " .. tostring(message))
end

local function sizeOf(list)
    if not list then return 0 end

    local result = tonumber(call(list, "size"))
    if result then return result end

    local ok, result = pcall(function()
        return #list
    end)
    if ok and result then return result end

    return 0
end

local function describeSquare(square)
    if not square then return "nil" end
    return tostring(call(square, "getX")) .. "," .. tostring(call(square, "getY")) .. "," .. tostring(call(square, "getZ"))
end

local function describeObject(object)
    if not object then return "nil" end

    local className = nil
    local class = call(object, "getClass")
    if class then
        className = call(class, "getName")
    end

    local parts = {
        tostring(object),
        "class=" .. tostring(className),
        "objectName=" .. tostring(call(object, "getObjectName")),
        "name=" .. tostring(call(object, "getName")),
        "type=" .. tostring(call(object, "getType")),
        "square=" .. describeSquare(call(object, "getSquare") or call(object, "getCurrentSquare")),
    }

    return table.concat(parts, " ")
end

local function describeItem(item)
    if not item then return "nil" end
    return tostring(item)
        .. " type=" .. tostring(call(item, "getType"))
        .. " fullType=" .. tostring(call(item, "getFullType"))
        .. " name=" .. tostring(call(item, "getName"))
end

local function tableValue(object, key)
    if not object then return nil end

    local ok, result = pcall(function()
        return object[key]
    end)

    if ok then return result end
    return nil
end

local isCorpseItem

local function describeValue(value)
    if value == nil then return "nil" end
    if isCorpseItem(value) then return describeItem(value) end
    if type(value) == "table" then
        return tostring(value) .. " Type=" .. tostring(tableValue(value, "Type")) .. " type=" .. tostring(tableValue(value, "type"))
    end
    return describeObject(value)
end

function isCorpseItem(item)
    local itemType = call(item, "getType")
    return itemType == "CorpseMale" or itemType == "CorpseFemale"
end

local function isDeadBody(object)
    if not object then return false end
    if instanceof and instanceof(object, "IsoDeadBody") then return true end
    return call(object, "getObjectName") == "DeadBody" and isCorpseItem(call(object, "getItem"))
end

local function corpseItemForBody(body)
    local item = call(body, "getItem")
    if isCorpseItem(item) then return item end
    return nil
end

local function playerNum(playerObj)
    return call(playerObj, "getPlayerNum") or 0
end

local function cacheDraggedCorpse(playerObj, corpse, corpseBody, source)
    if not playerObj or not isCorpseItem(corpse) then return end

    local body = corpseBody or call(corpse, "getDeadBodyObject")
    CJSMultiCorpseTrash.draggedCorpseByPlayer[playerNum(playerObj)] = {
        corpse = corpse,
        corpseBody = body,
        source = source,
    }

    debugLog(
        "cache-dragged-corpse source="
        .. tostring(source)
        .. " player="
        .. tostring(playerNum(playerObj))
        .. " corpse="
        .. describeItem(corpse)
        .. " body="
        .. describeObject(body)
    )
end

local function cachedDraggedCorpse(playerObj)
    if call(playerObj, "isDraggingCorpse") ~= true then return nil end

    local cached = CJSMultiCorpseTrash.draggedCorpseByPlayer[playerNum(playerObj)]
    if cached and isCorpseItem(cached.corpse) then
        debugLog(
            "cache-dragged-corpse hit player="
            .. tostring(playerNum(playerObj))
            .. " source="
            .. tostring(cached.source)
            .. " corpse="
            .. describeItem(cached.corpse)
            .. " body="
            .. describeObject(cached.corpseBody)
        )
        return cached
    end

    debugLog("cache-dragged-corpse miss player=" .. tostring(playerNum(playerObj)))
    return nil
end

local function clearCachedDraggedCorpse(playerObj)
    if playerObj then
        CJSMultiCorpseTrash.draggedCorpseByPlayer[playerNum(playerObj)] = nil
    end
end

local function deadBodyOnSquare(square)
    local body = call(square, "getDeadBody")
    if isDeadBody(body) then return body end

    local movingObjects = call(square, "getStaticMovingObjects")
    if movingObjects then
        for index = 0, movingObjects:size() - 1 do
            body = movingObjects:get(index)
            if isDeadBody(body) then return body end
        end
    end

    return nil
end

local function scanAroundForDeadBody(square)
    if not square then return nil end

    local body = deadBodyOnSquare(square)
    if body then return body end

    local cell = getCell and getCell()
    if not cell then return nil end

    local x = call(square, "getX")
    local y = call(square, "getY")
    local z = call(square, "getZ")
    if x == nil or y == nil or z == nil then return nil end

    for dx = -1, 1 do
        for dy = -1, 1 do
            if dx ~= 0 or dy ~= 0 then
                body = deadBodyOnSquare(cell:getGridSquare(x + dx, y + dy, z))
                if body then return body end
            end
        end
    end

    return nil
end

local function deadBodyFromCandidate(object)
    if isDeadBody(object) then return object end

    local size = tonumber(call(object, "size"))
    if not size then return nil end

    for index = 0, size - 1 do
        local candidate = call(object, "get", index)
        if isDeadBody(candidate) then return candidate end
    end

    return nil
end

local dragBodyKeys = {
    "corpseBody",
    "deadBody",
    "body",
    "corpse",
    "WItem",
    "worldItem",
    "item",
    "object",
    "target",
    "dragObject",
}

local function describeDragState(dragState)
    if not dragState then return "nil" end

    local parts = {
        tostring(dragState),
        "Type=" .. tostring(tableValue(dragState, "Type")),
        "type=" .. tostring(tableValue(dragState, "type")),
        "class=" .. tostring(call(call(dragState, "getClass"), "getName")),
    }

    for _, key in ipairs(dragBodyKeys) do
        local value = tableValue(dragState, key)
        if value ~= nil and type(value) ~= "function" then
            table.insert(parts, key .. "=" .. describeValue(value))
        end
    end

    local ok = pcall(function()
        local count = 0
        for key, value in pairs(dragState) do
            if type(value) ~= "function" then
                count = count + 1
                if count <= 12 then
                    table.insert(parts, "pair." .. tostring(key) .. "=" .. describeValue(value))
                end
            end
        end
    end)
    if not ok then table.insert(parts, "pairs=unavailable") end

    return table.concat(parts, " ")
end

local function activeCellDrag(player)
    local cell = getCell and getCell()
    local dragState = call(cell, "getDrag", player)
    debugLog(function()
        return "cell-drag player=" .. tostring(player) .. " drag=" .. describeDragState(dragState)
    end)
    return dragState
end

local function deadBodyFromDragState(dragState)
    if not dragState then return nil end

    for _, key in ipairs(dragBodyKeys) do
        local body = deadBodyFromCandidate(tableValue(dragState, key))
        if body then
            debugLog("corpse-detect hit cell-drag field " .. key .. " " .. describeObject(body))
            return body
        end
    end

    for _, methodName in ipairs({ "getCorpseBody", "getDeadBody", "getBody", "getCorpse", "getObject", "getItem" }) do
        local body = deadBodyFromCandidate(call(dragState, methodName))
        if body then
            debugLog("corpse-detect hit cell-drag method " .. methodName .. " " .. describeObject(body))
            return body
        end
    end

    local ok, hitKey, body = pcall(function()
        for key, value in pairs(dragState) do
            local body = deadBodyFromCandidate(value)
            if body then
                return key, body
            end
        end
        return nil, nil
    end)

    if ok and body then
        debugLog("corpse-detect hit cell-drag pair " .. tostring(hitKey) .. " " .. describeObject(body))
        return body
    end

    debugLog(function()
        return "corpse-detect no body in cell-drag " .. describeDragState(dragState)
    end)
    return nil
end

local function draggedCorpseBody(playerObj, dragState)
    local corpseBody = deadBodyFromDragState(dragState)
    if corpseBody then return corpseBody end

    local hasDraggingMethod = call(playerObj, "isDraggingCorpse") ~= nil
    local draggingValue = call(playerObj, "isDraggingCorpse")
    local dragObject = call(playerObj, "getDragObject")
    local dragCharacter = call(playerObj, "getDragCharacter")

    debugLog(
        "corpse-detect start hasIsDraggingCorpse="
        .. tostring(hasDraggingMethod)
        .. " isDraggingCorpse="
        .. tostring(draggingValue)
        .. " dragObject="
        .. describeObject(dragObject)
        .. " dragCharacter="
        .. describeObject(dragCharacter)
    )

    corpseBody = deadBodyFromCandidate(dragObject)
    if corpseBody then
        debugLog("corpse-detect hit getDragObject " .. describeObject(corpseBody))
        return corpseBody
    end

    corpseBody = deadBodyFromCandidate(dragCharacter)
    if corpseBody then
        debugLog("corpse-detect hit getDragCharacter " .. describeObject(corpseBody))
        return corpseBody
    end

    corpseBody = scanAroundForDeadBody(call(playerObj, "getCurrentSquare"))
    debugLog("corpse-detect adjacent result " .. describeObject(corpseBody))
    return corpseBody
end

local function clearDraggedCorpse(playerObj)
    call(playerObj, "setDragObject", nil)
    call(playerObj, "setDragCharacter", nil)
    call(playerObj, "setDraggingCorpse", false)
    call(playerObj, "setIsDraggingCorpse", false)
    call(playerObj, "stopDraggingCorpse")

    local cell = getCell and getCell()
    call(cell, "setDrag", nil, call(playerObj, "getPlayerNum") or 0)
end

local function carriedCorpse(playerObj)
    local primary = call(playerObj, "getPrimaryHandItem")
    local secondary = call(playerObj, "getSecondaryHandItem")
    local inventory = call(playerObj, "getInventory")

    debugLog(
        "carried-corpse check primary="
        .. describeItem(primary)
        .. " secondary="
        .. describeItem(secondary)
        .. " inventory="
        .. tostring(inventory)
        .. " maleCount="
        .. tostring(call(inventory, "getItemCount", "Base.CorpseMale"))
        .. " femaleCount="
        .. tostring(call(inventory, "getItemCount", "Base.CorpseFemale"))
    )

    if isCorpseItem(primary) then return primary end

    if isCorpseItem(secondary) then return secondary end

    if inventory then
        local corpse = call(inventory, "getFirstEvalRecurse", isCorpseItem)
        debugLog("carried-corpse inventory result " .. describeItem(corpse))
        return corpse
    end

    return nil
end

if ISGrabCorpseAction and ISGrabCorpseAction.perform and not CJSMultiCorpseTrash.grabCorpseActionWrapped then
    local vanillaGrabCorpsePerform = ISGrabCorpseAction.perform
    ISGrabCorpseAction.perform = function(self)
        debugLog("grab-corpse perform before corpse=" .. describeItem(self.corpse) .. " body=" .. describeObject(self.corpseBody))
        cacheDraggedCorpse(self.character, self.corpse, self.corpseBody, "ISGrabCorpseAction.perform.before")
        local result = vanillaGrabCorpsePerform(self)
        cacheDraggedCorpse(self.character, self.corpse, self.corpseBody, "ISGrabCorpseAction.perform.after")
        debugLog(
            "grab-corpse perform after primary="
            .. describeItem(call(self.character, "getPrimaryHandItem"))
            .. " secondary="
            .. describeItem(call(self.character, "getSecondaryHandItem"))
            .. " maleCount="
            .. tostring(call(call(self.character, "getInventory"), "getItemCount", "Base.CorpseMale"))
            .. " femaleCount="
            .. tostring(call(call(self.character, "getInventory"), "getItemCount", "Base.CorpseFemale"))
        )
        return result
    end
    CJSMultiCorpseTrash.grabCorpseActionWrapped = true
end

if ISPickupCorpseAction and not CJSMultiCorpseTrash.pickupCorpseActionWrapped then
    if ISPickupCorpseAction.perform then
        local pickupPerform = ISPickupCorpseAction.perform
        ISPickupCorpseAction.perform = function(self)
            cacheDraggedCorpse(self.character, self.corpse, self.corpseBody, "ISPickupCorpseAction.perform.before")
            local result = pickupPerform(self)
            cacheDraggedCorpse(self.character, self.corpse, self.corpseBody, "ISPickupCorpseAction.perform.after")
            return result
        end
    end

    if ISPickupCorpseAction.complete then
        local pickupComplete = ISPickupCorpseAction.complete
        ISPickupCorpseAction.complete = function(self)
            cacheDraggedCorpse(self.character, self.corpse, self.corpseBody, "ISPickupCorpseAction.complete.before")
            local result = pickupComplete(self)
            cacheDraggedCorpse(self.character, self.corpse, self.corpseBody, "ISPickupCorpseAction.complete.after")
            return result
        end
    end

    CJSMultiCorpseTrash.pickupCorpseActionWrapped = true
end

local function spriteProperties(object)
    local sprite = call(object, "getSprite")
    if not sprite then return nil end
    return call(sprite, "getProperties")
end

local function propertyIs(object, name)
    local props = spriteProperties(object)
    if not props then return false end

    return props:has(name) == true
end

local function propertyValue(object, name)
    local props = spriteProperties(object)
    if not props then return nil end

    if not props:has(name) then return nil end
    return props:get(name)
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

local function worldInventoryItem(object)
    if not object then return nil end
    if instanceof and not instanceof(object, "IsoWorldInventoryObject") then return nil end
    return call(object, "getItem")
end

local function isZuperCartItem(item)
    local fullType = call(item, "getFullType")
    return fullType ~= nil and zuperCartItemTypes[tostring(fullType)] == true
end

local function isZuperCartObject(object)
    return isZuperCartItem(worldInventoryItem(object))
end

local function isSaucedCartItem(item)
    local fullType = call(item, "getFullType")
    if fullType ~= nil and saucedCartItemTypes[tostring(fullType)] == true then
        return true
    end

    if SaucedCarts and SaucedCarts.safeIsCart then
        local ok, result = pcall(function()
            return SaucedCarts.safeIsCart(item)
        end)
        return ok and result == true
    end

    return false
end

local function isSaucedCartObject(object)
    return isSaucedCartItem(worldInventoryItem(object))
end

local function isCartTargetObject(object)
    return isZuperCartObject(object) or isSaucedCartObject(object)
end

local function targetContainerForCartItem(item)
    if not isZuperCartItem(item) and not isSaucedCartItem(item) then return nil end

    local container = call(item, "getItemContainer")
    if container then return container end

    return call(item, "getInventory")
end

local function targetContainerForObject(object)
    local item = worldInventoryItem(object)
    if item then
        local container = targetContainerForCartItem(item)
        if container then return container end
    end

    local container = call(object, "getContainer")
    if container then return container end

    return nil
end

local function isTrashCanObject(object)
    if not object then return false end

    local container = targetContainerForObject(object)
    if not container then return false end

    if isCartTargetObject(object) then return true end
    if instanceof and instanceof(object, "IsoWorldInventoryObject") then return false end

    if propertyIs(object, "IsTrashCan") then return true end
    if containsTrashName(objectDisplayName(object)) then return true end
    if containsTrashName(call(container, "getType")) then return true end

    return false
end

local function scanObjectListForTrashCan(objects)
    if not objects then return nil end

    for index = sizeOf(objects) - 1, 0, -1 do
        local object = call(objects, "get", index)
        if isTrashCanObject(object) then
            return object
        end
    end

    return nil
end

local function squareKey(square)
    if not square then return nil end
    return tostring(call(square, "getX")) .. ":" .. tostring(call(square, "getY")) .. ":" .. tostring(call(square, "getZ"))
end

local function scanSquareForTrashCan(square)
    local trashCan = scanObjectListForTrashCan(call(square, "getObjects"))
    if trashCan then return trashCan end

    return scanObjectListForTrashCan(call(square, "getWorldObjects"))
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
        if isTrashCanObject(object) then
            debugLog("trash-detect hit worldobject " .. describeObject(object))
            return object
        end

        local trashCan = scan(call(object, "getSquare"))
        if trashCan then
            debugLog("trash-detect hit worldobjects " .. describeObject(trashCan))
            return trashCan
        end
    end

    local fetch = ISWorldObjectContextMenu and ISWorldObjectContextMenu.fetchVars
    local trashCan = scanAround(fetch and fetch.clickedSquare, scan)
    if trashCan then
        debugLog("trash-detect hit clickedSquare " .. describeObject(trashCan))
        return trashCan
    end

    trashCan = scanAround(call(playerObj, "getCurrentSquare"), scan)
    if trashCan then
        debugLog("trash-detect hit player-adjacent " .. describeObject(trashCan))
    else
        debugLog(
            "trash-detect miss worldobjects="
            .. tostring(sizeOf(worldobjects))
            .. " playerSquare="
            .. describeSquare(call(playerObj, "getCurrentSquare"))
        )
    end

    return trashCan
end

local function addTooltip(option, name, description)
    if not option then return end

    local tip = ISWorldObjectContextMenu.addToolTip()
    tip:setName(name)
    tip.description = description
    option.toolTip = tip
end

local function containerHasCapacity(container, playerObj, item)
    local capacity = tonumber(call(container, "getEffectiveCapacity", playerObj))
    if not capacity then
        capacity = tonumber(call(container, "getCapacity"))
    end
    if not capacity then return true end

    local contentsWeight = tonumber(call(container, "getCapacityWeight"))
    if not contentsWeight then
        contentsWeight = tonumber(call(container, "getContentsWeight")) or 0
    end
    local itemWeight = tonumber(call(item, "getUnequippedWeight"))
    if not itemWeight then
        itemWeight = tonumber(call(item, "getActualWeight")) or 0
    end

    return contentsWeight + itemWeight <= capacity
end

local function canStoreCorpse(container, playerObj, corpse)
    return container
        and isCorpseItem(corpse)
        and call(container, "isItemAllowed", corpse) == true
        and containerHasCapacity(container, playerObj, corpse)
end

local function storableDeadBodyFromCandidate(object, container, playerObj, skipBody)
    local body = deadBodyFromCandidate(object)
    if not body or body == skipBody then return nil end

    local corpse = corpseItemForBody(body)
    if canStoreCorpse(container, playerObj, corpse) then return body end
    return nil
end

local function storableDeadBodyOnSquare(square, container, playerObj, skipBody)
    if not square then return nil end

    local body = storableDeadBodyFromCandidate(call(square, "getDeadBody"), container, playerObj, skipBody)
    if body then return body end

    local movingObjects = call(square, "getStaticMovingObjects")
    for index = 0, sizeOf(movingObjects) - 1 do
        body = storableDeadBodyFromCandidate(call(movingObjects, "get", index), container, playerObj, skipBody)
        if body then return body end
    end

    return nil
end

local function scanAroundForStorableDeadBody(square, container, playerObj, skipBody, checked)
    if not square then return nil end

    local key = squareKey(square)
    if key and checked and checked[key] then return nil end
    if key and checked then checked[key] = true end

    local body = storableDeadBodyOnSquare(square, container, playerObj, skipBody)
    if body then return body end

    local cell = getCell and getCell()
    if not cell then return nil end

    local x = call(square, "getX")
    local y = call(square, "getY")
    local z = call(square, "getZ")
    if x == nil or y == nil or z == nil then return nil end

    for dx = -1, 1 do
        for dy = -1, 1 do
            if dx ~= 0 or dy ~= 0 then
                local nearbySquare = call(cell, "getGridSquare", x + dx, y + dy, z)
                key = squareKey(nearbySquare)
                if not key or not checked or not checked[key] then
                    if key and checked then checked[key] = true end
                    body = storableDeadBodyOnSquare(nearbySquare, container, playerObj, skipBody)
                    if body then return body end
                end
            end
        end
    end

    return nil
end

local function nextNearbyCorpseBody(playerObj, trashCan, skipBody)
    local container = targetContainerForObject(trashCan)
    if not container then return nil end

    local checked = {}
    local body = scanAroundForStorableDeadBody(call(trashCan, "getSquare"), container, playerObj, skipBody, checked)
    if body then return body end

    return scanAroundForStorableDeadBody(call(playerObj, "getCurrentSquare"), container, playerObj, skipBody, checked)
end

local function updateContainerAfterAdd(container, trashCan, playerObj)
    call(container, "setDrawDirty", true)
    call(container, "setHasBeenLooted", true)

    if not isClient() and trashCan and call(trashCan, "getOverlaySprite") and ItemPicker then
        ItemPicker.updateOverlaySprite(trashCan)
    end

    local item = worldInventoryItem(trashCan)
    if isSaucedCartItem(item) and SaucedCarts and SaucedCarts.updateCartVisual then
        pcall(function()
            SaucedCarts.updateCartVisual(item, playerObj)
        end)
    end

    local corpseStorage = SaucedCarts and SaucedCarts.CorpseStorage
    if isSaucedCartItem(item) and corpseStorage and corpseStorage.reconcile then
        pcall(function()
            local square = nil
            if corpseStorage.cartTargetSquare then
                square = corpseStorage.cartTargetSquare(item, playerObj)
            end
            corpseStorage.reconcile(item, square or call(trashCan, "getSquare"))
        end)
    end
end

local function stampSaucedCartCorpse(trashCan, corpse, corpseBody)
    local item = worldInventoryItem(trashCan)
    if not isSaucedCartItem(item) then return end
    if not SaucedCarts or not SaucedCarts.CorpseStorage then return end

    local stampDeathTime = SaucedCarts.CorpseStorage.stampDeathTime
    if not stampDeathTime then return end

    pcall(function()
        stampDeathTime(corpse, corpseBody)
    end)
end

local queueNextNearbyCorpseInTrash

local function putCorpseInTrash(playerObj, trashCan, corpse)
    if not playerObj or not trashCan or not isCorpseItem(corpse) then return end

    local container = targetContainerForObject(trashCan)
    local source = call(corpse, "getContainer")
    if not container or not source then return end
    if not canStoreCorpse(container, playerObj, corpse) then return end

    local playerNum = call(playerObj, "getPlayerNum") or 0
    if luautils and luautils.walkToContainer then
        if not luautils.walkToContainer(container, playerNum) then return end
    elseif luautils and luautils.walkAdj then
        if not luautils.walkAdj(playerObj, call(trashCan, "getSquare"), true) then return end
    end

    ISTimedActionQueue.add(ISInventoryTransferAction:new(playerObj, corpse, source, container))
    if CJSPutNextNearbyCorpseInTrashAction then
        ISTimedActionQueue.add(CJSPutNextNearbyCorpseInTrashAction:new(playerObj, trashCan))
    end
end

CJSPutCachedCorpseInTrashAction = ISBaseTimedAction:derive("CJSPutCachedCorpseInTrashAction")

function CJSPutCachedCorpseInTrashAction:isValid()
    local container = targetContainerForObject(self.trashCan)
    if not container or not isCorpseItem(self.corpse) then
        debugLog("cached-action invalid missing container/corpse container=" .. tostring(container) .. " corpse=" .. describeItem(self.corpse))
        return false
    end
    if call(container, "isItemAllowed", self.corpse) ~= true then
        debugLog("cached-action invalid item not allowed " .. describeItem(self.corpse))
        return false
    end
    if not containerHasCapacity(container, self.character, self.corpse) then
        debugLog("cached-action invalid no capacity " .. describeItem(self.corpse))
        return false
    end

    local cached = CJSMultiCorpseTrash.draggedCorpseByPlayer[playerNum(self.character)]
    local valid = call(self.character, "isDraggingCorpse") == true or (cached and cached.corpse == self.corpse)
    debugLog("cached-action isValid valid=" .. tostring(valid) .. " corpse=" .. describeItem(self.corpse))
    return valid
end

function CJSPutCachedCorpseInTrashAction:waitToStart()
    self.character:faceThisObject(self.trashCan)
    return self.character:shouldBeTurning()
end

function CJSPutCachedCorpseInTrashAction:update()
    self.corpse:setJobDelta(self:getJobDelta())
    self.character:faceThisObject(self.trashCan)
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function CJSPutCachedCorpseInTrashAction:start()
    debugLog("cached-action start trashCan=" .. describeObject(self.trashCan) .. " corpse=" .. describeItem(self.corpse) .. " body=" .. describeObject(self.corpseBody))
    self.corpse:setJobType("Putting corpse in garbage")
    self.corpse:setJobDelta(0.0)
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
    self.character:reportEvent("EventLootItem")
end

function CJSPutCachedCorpseInTrashAction:stop()
    self.corpse:setJobDelta(0.0)
    ISBaseTimedAction.stop(self)
end

function CJSPutCachedCorpseInTrashAction:perform()
    local container = targetContainerForObject(self.trashCan)
    local stored = false
    debugLog("cached-action perform container=" .. tostring(container) .. " corpse=" .. describeItem(self.corpse) .. " body=" .. describeObject(self.corpseBody))
    if container and isCorpseItem(self.corpse) then
        self.corpse:setJobDelta(0.0)

        local source = call(self.corpse, "getContainer")
        if source and source ~= container then
            call(source, "Remove", self.corpse)
        end

        if isClient() and call(container, "isInCharacterInventory", self.character) ~= true then
            call(container, "addItemOnServer", self.corpse)
        end

        if call(self.corpse, "getContainer") ~= container then
            call(container, "AddItem", self.corpse)
        end

        local square = call(self.corpseBody, "getSquare")
        if square then
            square:removeCorpse(self.corpseBody, false)
        end

        clearDraggedCorpse(self.character)
        clearCachedDraggedCorpse(self.character)
        stampSaucedCartCorpse(self.trashCan, self.corpse, self.corpseBody)
        updateContainerAfterAdd(container, self.trashCan, self.character)
        stored = true
    end

    if stored and queueNextNearbyCorpseInTrash then
        queueNextNearbyCorpseInTrash(self.character, self.trashCan, self.corpseBody)
    end

    ISBaseTimedAction.perform(self)
end

function CJSPutCachedCorpseInTrashAction:new(character, trashCan, corpse, corpseBody)
    local o = ISBaseTimedAction.new(self, character)
    o.trashCan = trashCan
    o.corpse = corpse
    o.corpseBody = corpseBody or call(corpse, "getDeadBodyObject")
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = 50
    o.forceProgressBar = true
    if character:isTimedActionInstant() then
        o.maxTime = 1
    end
    return o
end

local function putCachedDraggedCorpseInTrash(playerObj, trashCan, corpse, corpseBody)
    if not playerObj or not trashCan or not isCorpseItem(corpse) then return end

    local container = targetContainerForObject(trashCan)
    if not container then return end
    if call(container, "isItemAllowed", corpse) ~= true then return end

    if luautils and luautils.walkAdj then
        if not luautils.walkAdj(playerObj, call(trashCan, "getSquare"), true) then return end
    end

    ISTimedActionQueue.add(CJSPutCachedCorpseInTrashAction:new(playerObj, trashCan, corpse, corpseBody))
end

CJSPutDraggedCorpseInTrashAction = ISBaseTimedAction:derive("CJSPutDraggedCorpseInTrashAction")

function CJSPutDraggedCorpseInTrashAction:isValid()
    local container = targetContainerForObject(self.trashCan)
    local corpse = corpseItemForBody(self.corpseBody)
    if not container or not corpse then
        debugLog("action invalid missing container/corpse container=" .. tostring(container) .. " corpse=" .. describeItem(corpse))
        return false
    end
    if call(container, "isItemAllowed", corpse) ~= true then
        debugLog("action invalid item not allowed " .. describeItem(corpse))
        return false
    end
    if not containerHasCapacity(container, self.character, corpse) then
        debugLog("action invalid no capacity " .. describeItem(corpse))
        return false
    end

    if self.allowGroundCorpse then
        local valid = isDeadBody(self.corpseBody) and call(self.corpseBody, "getSquare") ~= nil
        debugLog("action isValid repeat=true body=" .. describeObject(self.corpseBody) .. " valid=" .. tostring(valid))
        return valid
    end

    local activeCorpse = draggedCorpseBody(self.character, self.dragState)
    local valid = activeCorpse == self.corpseBody or (self.dragState ~= nil and isDeadBody(self.corpseBody))
    debugLog("action isValid active=" .. describeObject(activeCorpse) .. " expected=" .. describeObject(self.corpseBody) .. " valid=" .. tostring(valid))
    return valid
end

function CJSPutDraggedCorpseInTrashAction:waitToStart()
    self.character:faceThisObject(self.trashCan)
    return self.character:shouldBeTurning()
end

function CJSPutDraggedCorpseInTrashAction:update()
    local corpse = corpseItemForBody(self.corpseBody)
    if corpse then corpse:setJobDelta(self:getJobDelta()) end

    self.character:faceThisObject(self.trashCan)
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function CJSPutDraggedCorpseInTrashAction:start()
    debugLog("action start trashCan=" .. describeObject(self.trashCan) .. " corpseBody=" .. describeObject(self.corpseBody))

    local corpse = corpseItemForBody(self.corpseBody)
    if corpse then
        corpse:setJobType("Putting corpse in garbage")
        corpse:setJobDelta(0.0)
    end

    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
    self.character:reportEvent("EventLootItem")
end

function CJSPutDraggedCorpseInTrashAction:stop()
    local corpse = corpseItemForBody(self.corpseBody)
    if corpse then corpse:setJobDelta(0.0) end
    ISBaseTimedAction.stop(self)
end

function CJSPutDraggedCorpseInTrashAction:perform()
    local container = targetContainerForObject(self.trashCan)
    local corpse = corpseItemForBody(self.corpseBody)
    local stored = false
    debugLog("action perform container=" .. tostring(container) .. " corpse=" .. describeItem(corpse) .. " body=" .. describeObject(self.corpseBody))
    if container and corpse then
        corpse:setJobDelta(0.0)

        if isClient() and call(container, "isInCharacterInventory", self.character) ~= true then
            call(container, "addItemOnServer", corpse)
        end

        call(container, "AddItem", corpse)

        local square = call(self.corpseBody, "getSquare")
        if square then
            square:removeCorpse(self.corpseBody, false)
        else
            call(self.corpseBody, "removeFromWorld")
            call(self.corpseBody, "removeFromSquare")
        end

        clearDraggedCorpse(self.character)
        stampSaucedCartCorpse(self.trashCan, corpse, self.corpseBody)
        updateContainerAfterAdd(container, self.trashCan, self.character)
        stored = true
    end

    if stored and queueNextNearbyCorpseInTrash then
        queueNextNearbyCorpseInTrash(self.character, self.trashCan, self.corpseBody)
    end

    ISBaseTimedAction.perform(self)
end

function CJSPutDraggedCorpseInTrashAction:new(character, trashCan, corpseBody, dragState, allowGroundCorpse)
    local o = ISBaseTimedAction.new(self, character)
    o.trashCan = trashCan
    o.corpseBody = corpseBody
    o.dragState = dragState
    o.allowGroundCorpse = allowGroundCorpse == true
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = 50
    o.forceProgressBar = true
    if character:isTimedActionInstant() then
        o.maxTime = 1
    end
    return o
end

function queueNextNearbyCorpseInTrash(playerObj, trashCan, previousBody)
    local nextBody = nextNearbyCorpseBody(playerObj, trashCan, previousBody)
    if not nextBody then
        debugLog("repeat-action stop no nearby storable corpse")
        return false
    end

    debugLog("repeat-action queue body=" .. describeObject(nextBody) .. " trashCan=" .. describeObject(trashCan))
    ISTimedActionQueue.add(CJSPutDraggedCorpseInTrashAction:new(playerObj, trashCan, nextBody, nil, true))
    return true
end

CJSPutNextNearbyCorpseInTrashAction = ISBaseTimedAction:derive("CJSPutNextNearbyCorpseInTrashAction")

function CJSPutNextNearbyCorpseInTrashAction:isValid()
    return self.character ~= nil and targetContainerForObject(self.trashCan) ~= nil
end

function CJSPutNextNearbyCorpseInTrashAction:perform()
    local container = targetContainerForObject(self.trashCan)
    if container then
        updateContainerAfterAdd(container, self.trashCan, self.character)
    end

    if queueNextNearbyCorpseInTrash then
        queueNextNearbyCorpseInTrash(self.character, self.trashCan)
    end

    ISBaseTimedAction.perform(self)
end

function CJSPutNextNearbyCorpseInTrashAction:new(character, trashCan)
    local o = ISBaseTimedAction.new(self, character)
    o.trashCan = trashCan
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = 1
    o.forceProgressBar = false
    return o
end

local function putDraggedCorpseInTrash(playerObj, trashCan, corpseBody, dragState)
    if not playerObj or not trashCan or not isDeadBody(corpseBody) then return end

    local container = targetContainerForObject(trashCan)
    local corpse = corpseItemForBody(corpseBody)
    if not container or not corpse then return end
    if call(container, "isItemAllowed", corpse) ~= true then return end

    if luautils and luautils.walkAdj then
        if not luautils.walkAdj(playerObj, call(trashCan, "getSquare"), true) then return end
    end

    ISTimedActionQueue.add(CJSPutDraggedCorpseInTrashAction:new(playerObj, trashCan, corpseBody, dragState))
end

local function setContextTest()
    if ISWorldObjectContextMenu and ISWorldObjectContextMenu.setTest then
        return ISWorldObjectContextMenu.setTest()
    end

    return true
end

local function buildCorpseTrashOffer(player, worldobjects, dragState)
    local playerObj = getSpecificPlayer(player)
    debugLog(function()
        return "offer start player="
            .. tostring(player)
            .. " worldobjects="
            .. tostring(sizeOf(worldobjects))
            .. " playerObj="
            .. tostring(playerObj)
            .. " dragState="
            .. describeDragState(dragState)
    end)
    if not playerObj then
        debugLog("offer fail no playerObj")
        return
    end
    if call(playerObj, "getVehicle") then
        debugLog("offer fail player in vehicle")
        return
    end

    local corpseBody = draggedCorpseBody(playerObj, dragState)
    local corpse = corpseItemForBody(corpseBody)
    local cachedCorpse = nil

    if not corpse then
        cachedCorpse = cachedDraggedCorpse(playerObj)
        if cachedCorpse then
            corpse = cachedCorpse.corpse
            corpseBody = corpseBody or cachedCorpse.corpseBody
        end
    end

    if not corpse then
        corpse = carriedCorpse(playerObj)
    end

    if not corpse then
        debugLog("offer fail no corpse corpseBody=" .. describeObject(corpseBody))
        return
    end
    debugLog("offer corpse body=" .. describeObject(corpseBody) .. " corpseItem=" .. describeItem(corpse) .. " cached=" .. tostring(cachedCorpse ~= nil))

    local trashCan = findTrashCan(worldobjects, playerObj)
    if not trashCan then
        debugLog("offer fail no trash can")
        return
    end

    local container = targetContainerForObject(trashCan)
    if not container then
        debugLog("offer fail target has no container " .. describeObject(trashCan))
        return
    end
    if call(container, "isItemAllowed", corpse) ~= true then
        debugLog("offer fail corpse not allowed container=" .. tostring(container) .. " corpse=" .. describeItem(corpse))
        return
    end

    debugLog("offer success trashCan=" .. describeObject(trashCan) .. " container=" .. tostring(container))

    return {
        playerObj = playerObj,
        corpse = corpse,
        corpseBody = corpseBody,
        cachedCorpse = cachedCorpse,
        trashCan = trashCan,
        container = container,
        dragState = dragState,
    }
end

local function addCorpseTrashOption(player, context, worldobjects, test, forceVisible, prebuiltOffer)
    debugLog("add-option start test=" .. tostring(test) .. " forceVisible=" .. tostring(forceVisible) .. " context=" .. tostring(context))
    if test and ISWorldObjectContextMenu.Test then return true end

    local offer = prebuiltOffer or buildCorpseTrashOffer(player, worldobjects)
    if not offer then return false end

    if test then return setContextTest() end
    if not context then return false end

    local optionName = "Put Corpse in Garbage"
    if isSaucedCartObject(offer.trashCan) then
        optionName = "Put Corpse in Cart"
    elseif isZuperCartObject(offer.trashCan) then
        optionName = "Put Corpse in Cart/Trolley"
    end
    if context:getOptionFromName(optionName) then
        if forceVisible then context:setVisible(true) end
        debugLog("add-option skipped duplicate")
        return true
    end

    local option
    if offer.cachedCorpse then
        option = context:addOption(optionName, offer.playerObj, putCachedDraggedCorpseInTrash, offer.trashCan, offer.corpse, offer.corpseBody)
    elseif offer.corpseBody then
        option = context:addOption(optionName, offer.playerObj, putDraggedCorpseInTrash, offer.trashCan, offer.corpseBody, offer.dragState)
    else
        option = context:addOption(optionName, offer.playerObj, putCorpseInTrash, offer.trashCan, offer.corpse)
    end

    if not containerHasCapacity(offer.container, offer.playerObj, offer.corpse) then
        option.notAvailable = true
        local capacityDescription = "This trash can does not have room for the corpse."
        if isSaucedCartObject(offer.trashCan) then
            capacityDescription = "This cart does not have room for the corpse."
        elseif isZuperCartObject(offer.trashCan) then
            capacityDescription = "This cart/trolley does not have room for the corpse."
        end
        addTooltip(option, optionName, capacityDescription)
    end

    if forceVisible then context:setVisible(true) end
    debugLog("add-option success option=" .. optionName .. " notAvailable=" .. tostring(option and option.notAvailable))
    return true
end

local function onFillWorldObjectContextMenu(player, context, worldobjects, test)
    debugLog("event OnFillWorldObjectContextMenu player=" .. tostring(player) .. " test=" .. tostring(test) .. " worldobjects=" .. tostring(sizeOf(worldobjects)))
    return addCorpseTrashOption(player, context, worldobjects, test, false)
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)

local vanillaCreateMenu = ISWorldObjectContextMenu.createMenu
ISWorldObjectContextMenu.createMenu = function(player, worldobjects, x, y, test)
    debugLog("createMenu wrapper start player=" .. tostring(player) .. " test=" .. tostring(test) .. " x=" .. tostring(x) .. " y=" .. tostring(y) .. " worldobjects=" .. tostring(sizeOf(worldobjects)))
    local preDragState = activeCellDrag(player)
    local preOffer = buildCorpseTrashOffer(player, worldobjects, preDragState)
    debugLog("createMenu pre-vanilla offer=" .. tostring(preOffer ~= nil))

    local result = vanillaCreateMenu(player, worldobjects, x, y, test)
    debugLog("createMenu vanilla result=" .. tostring(result))

    if test then
        if result then return result end
        if addCorpseTrashOption(player, nil, worldobjects, true, false, preOffer) then return true end
        return result
    end

    local context = nil
    if type(result) == "table" and result.addOption then
        context = result
    elseif preOffer and ISContextMenu then
        context = ISContextMenu.get(player, x or 0, y or 0)
    elseif buildCorpseTrashOffer(player, worldobjects) and ISContextMenu then
        context = ISContextMenu.get(player, x or 0, y or 0)
    end

    if context and addCorpseTrashOption(player, context, worldobjects, false, true, preOffer) then
        debugLog("createMenu returning forced context")
        return context
    end

    debugLog("createMenu returning vanilla result")
    return result
end

local debugUpdateCounter = 0
Events.OnPlayerUpdate.Add(function(playerObj)
    if not option("DebugLogging") then return end
    if not playerObj then return end
    local isLocalPlayer = call(playerObj, "isLocalPlayer")
    if isLocalPlayer == false then return end

    debugUpdateCounter = debugUpdateCounter + 1
    if debugUpdateCounter % 120 ~= 0 then return end

    local square = call(playerObj, "getCurrentSquare")
    local body = scanAroundForDeadBody(square)
    local trashCan = scanAround(square, scanSquareForTrashCan)
    local dragObject = call(playerObj, "getDragObject")
    local dragCharacter = call(playerObj, "getDragCharacter")
    local primary = call(playerObj, "getPrimaryHandItem")
    local secondary = call(playerObj, "getSecondaryHandItem")

    if body or trashCan or dragObject or dragCharacter or isCorpseItem(primary) or isCorpseItem(secondary) then
        debugLog(
            "tick playerSquare="
            .. describeSquare(square)
            .. " body="
            .. describeObject(body)
            .. " trashCan="
            .. describeObject(trashCan)
            .. " dragObject="
            .. describeObject(dragObject)
            .. " dragCharacter="
            .. describeObject(dragCharacter)
            .. " primary="
            .. describeItem(primary)
            .. " secondary="
            .. describeItem(secondary)
        )
    end
end)

print("[cjsMultiCorpseTrash] Loaded client " .. CJSMultiCorpseTrash.version)
