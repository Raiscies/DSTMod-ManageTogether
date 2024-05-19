
GLOBAL.setmetatable(env, {__index = function(t, k) return GLOBAL.rawget(GLOBAL, k) end})

local M = GLOBAL.manage_together
local S = GLOBAL.STRINGS.UI.MANAGE_TOGETHER

local lshift, rshift, bitor, bitand = GLOBAL.bit.lshift, GLOBAL.bit.rshift, GLOBAL.bit.bor, GLOBAL.bit.band
local insert, concat = table.insert, table.concat
local byte = string.byte

function M.varg_iter(arr, i)
    i = i + 1
    if i <= arr.n then
        return i, arr[i]
    end
end

function M.varg_pairs(...)
    return M.varg_iter, {n = select('#', ...), ...}, 0
end

local varg_pairs = M.varg_pairs

function M.chain_get(root, ...) 

    if not root then return nil, root end
    local current = root
    for i, node in varg_pairs(...) do
        if type(node) == 'table' then
            -- node[1] is function name
            -- node[2...] are function args
            current = current[node[1]](current, select(2, ...)) -- current:Fn(args...)
        else
            current = current[node]                                    -- current.node
        end
        if i < select('#', ...) and type(current) ~= 'table' then
            return nil, node 
        end
    end
    return current
end

-- select the n-th argument of a vararg
function M.select_one(n, ...)
    return ({select(n, ...)})[1]
end

function M.moretostring(obj)
    if type(obj) == 'table' then
        if obj.is_a == nil then
            return '\n' .. PrintTable(obj)
        else
            -- don't print a class instance like a table! or we are very possible to print a huge string and then OOM
            return 'ClassInstance:' .. tostring(obj) 
        end
    else
        return tostring(obj)
    end
end

function M.tolinekvstring(tab)
    -- assume tab is a table
    -- all of the key and value shouldn't be a table
    local s = ''
    for k, v in pairs(tab) do
        s = s .. string.format('%s = %s, ', tostring(k), tostring(v))
    end
    return string.format('{%s}', s)
end

function M.in_range(x, a, b)
    return type(x) == 'number' and
        a <= x and x <= b
end
function M.in_int_range(x, a, b)
    return type(x) == 'number' and 
        math.type(x) == 'integer' and
        a <= x and x <= b
end

-- little endian
function M.concatbit32to64(low32, high32)
    -- low32 | high32 << 32
    return bitor(low32, lshift(high32, 32))
end

function M.splitbit64to32(value64)
    -- low32  = value64 & 0xff'ff'ff'ff
    -- high32 = value64 >> 32
    return bitand(value64, 0xffffffff), rshift(value64, 32)
end

-- log print
function M.log(...)
    print('[ManageTogether]', ...)
end

function M.GetPlayerByUserid(userid)
    for _, player in ipairs(AllPlayers) do
        if player.userid == userid then
            return player
        end
    end
    return nil
end

-- debug print
M.dbg = M.DEBUG and function(...)
    local s = ''
    for _, v in varg_pairs(...) do
        s = s .. ' ' .. M.moretostring(v)
    end
    print('[ManageTogether] ' .. s)
end or function(...) end

local dbg, log, chain_get = M.dbg, M.log, M.chain_get



function M.announce(s, ...)
    TheNet:Announce(S.ANNOUNCE_PREFIX .. s, ...)
end

function M.announce_fmt(pattern, ...)
    M.announce(string.format(pattern, ...))
end

function M.announce_vote(s)
    M.announce(s, nil, nil, 'vote')
end
function M.announce_vote_fmt(pattern, ...)
    M.announce(string.format(pattern, ...), nil, nil, 'vote')
end

function M.IsPlayerOnline(userid)
    return userid and TheNet:GetClientTableForUser(userid) ~= nil or false
end
function M.GetPlayerFromUserid(userid)
    for _, v in ipairs(AllPlayers) do
        if v.userid == userid then
            return v
        end
    end
    return nil
end

-- this is come from seasons.lua
-- which doesn't exports from the file so we just simply make a copy 
M.SEASON_NAMES = {
    'autumn',
    'winter',
    'spring',
    'summer',
}
M.SEASONS = table.invert(M.SEASON_NAMES)

-- util functions
function M.BuildDayString(day)
    return (day and day > -1) and
        string.format(S.FMT_DAY, day) or S.DAY_UNKNOWN
end

function M.BuildSeasonString(season_enum)
    return (season_enum and 1 <= season_enum and season_enum <= 4) and 
        S.SEASONS[string.upper(M.SEASON_NAMES[season_enum])] or 
        S.UNKNOWN_SEASON
end

function M.BuildDaySeasonString(day, season_enum)
    return M.BuildDayString(day) .. '-' .. M.BuildSeasonString(season_enum)
end

function M.IsNewestRollbackSlotValid()
    if TheWorld.net == nil or 
        TheWorld.net.components.autosaver == nil or 
        GetTime() - TheWorld.net.components.autosaver:GetLastSaveTime() < 30 then
        return false
    else
        return true
    end
end



-- some utils for client
if TheNet:GetIsClient() then


local base64 = {
    [0] = 
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 
    'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', 
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '+', '/'
} 
local base64_padding = '='

function M.EncodeToBase64(s)
    if type(s) ~= 'string' then return end
    local len = #s
    if len == 0 then return '' end
    local result = {}
    local remain = len % 3

    for i = 1, len - remain, 3 do
        local c0, c1, c2 = byte(s, i, i + 2)
        -- c0 >> 2
        insert(result, base64[rshift(c0, 2)]) 
        -- ((c0 << 4) | (c1 >> 4)) & 0x3f
        insert(result, base64[bitand(bitor(lshift(c0, 4), rshift(c1, 4)), 0x3f)])
        -- ((c1 << 2) | (c2 >> 6)) & 0x3f
        insert(result, base64[bitand(bitor(lshift(c1, 2), rshift(c2, 6)), 0x3f)])
        -- c2 & 0x3f
        insert(result, base64[bitand(c2, 0x3f)])
    end

    if remain == 2 then
        local c0, c1 = byte(s, len - 1, len)
        -- c0 >> 2
        insert(result, base64[rshift(c0, 2)])
        -- ((c0 << 4) | (c1 >> 4)) & 0x3f
        insert(result, base64[bitand(bitor(lshift(c0, 4), rshift(c1, 4)), 0x3f)])
        -- (c1 << 2) & 0x3f
        insert(result, base64[bitand(lshift(c1, 2), 0x3f)])
        -- padding '='
        insert(result, base64_padding)
        
    elseif remain == 1 then
        local c0 = byte(s, len)
        -- c0 >> 2
        insert(result, base64[rshift(c0, 2)])
        -- (c0 << 4) & 0x3f
        insert(result, base64[bitand(lshift(c0, 4), 0x3f)])
        -- double padding '=='
        insert(result, base64_padding)
        insert(result, base64_padding)
    end

    return concat(result)
end

function M.GetItemDictionaries()
    if not (M.ITEM_PREFAB_DICTIONARY and M.ITEM_LOCAL_NAME_DICTIONARY and M.LOCAL_NAME_REFERENCES) then
        
        local names = STRINGS.NAMES
        for prefab, _ in pairs(Prefabs) do
            table.insert(M.ITEM_PREFAB_DICTIONARY, prefab)

            local local_name = names[string.upper(prefab)]
            table.insert(M.ITEM_LOCAL_DICTIONARY, local_name)
            -- keep a reference from localized name to prefab name
            M.LOCAL_NAME_REFERENCES[local_name] = prefab
        end
        
    end
    
    return {M.ITEM_PREFAB_DICTIONARY, M.ITEM_LOCAL_NAME_DICTIONARY}
end

function M.ToPrefabName(s) 
    -- a valid item representation is:
    -- a item prefab;
    -- a localized item name;
    
    -- try to generate the refs in case the tables haven't exist yet
    M.GetItemDictionaries()
    
    if M.LOCAL_NAME_REFERENCES[s] then
        return M.LOCAL_NAME_REFERENCES[s] --> prefab name
    elseif Prefabs[s] then
        return s
    end

    return nil
end

end -- is client

-- some utils for server
if TheNet:GetIsServer() then

function M.TemporarilyLoadOfflinePlayer(userid, fn, ...)
    -- assume the shard that invokes this function is the shard that the offline player the last joined

    -- make sure this player is not loaded now
    for _, v in ipairs(AllPlayers) do
        if v.userid == userid then
            return false
        end
    end
    
    log('temporarily loading offline user: ', userid)
    RestoreSnapshotUserSession(TheNet:GetSessionIdentifier(), userid)
    for _, v in ipairs(AllPlayers) do
        if v.userid == userid then
            local delay_serialize_time = fn(v, ...) or 0
            TheWorld:DoTaskInTime(delay_serialize_time, function()
                v:OnDespawn()
                SerializeUserSession(v)
                v:Remove()
            end)
            
            return true
        end
    end
    
    -- failed to restore the player
    return false
end

-- only load the player's data, but not create a player prefab
function M.GetSnapshotPlayerData(userid, component_name)
    local file = TheNet:GetUserSessionFile(TheNet:GetSessionIdentifier(), userid)
    if not file then return end
    log('loading user data: ' .. file)

    local data = nil

    TheNet:DeserializeUserSession(file, function(success, str)
        if not success or not str or #str <= 0 then return end
        
        local playerdata, prefab = ParseUserSessionData(str)
        if not playerdata or not prefab or prefab == '' then return end

        if type(component_name) == 'string' then
            data = playerdata.data[component_name] -- .data saves all of the components' OnSave() data
        else
            data = playerdata
        end
    end)
    
    return data
end

function M.RollbackBySnapshotID(snapshot_id, delay)
    local current_id = TheNet:GetCurrentSnapshot()
    if snapshot_id > current_id then
        -- bad snapshot id
        return nil
    elseif snapshot_id == current_id then
        -- do a reset
        -- if the index is zero, server will not do the following judgement
        TheNet:SendWorldRollbackRequestToServer(0)
    else -- snapshot_id < current_id
        local index = ShardGameIndex
        local snapshot_list = TheNet:ListSnapshots(index.session_id, index.server.online_mode, 10)
        -- make sure the snapshot id is exists
        for i, v in ipairs(snapshot_list) do
            if v.snapshot_id == snapshot_id then
                -- snapshot exists
                -- calculate the rollback index we needs 
                local rollback_index = current_id - snapshot_id -- >= 1 
                if M.IsNewestRollbackSlotValid() then
                    TheNet:SendWorldRollbackRequestToServer(rollback_index)
                elseif rollback_index ~= 1 then
                    TheNet:SendWorldRollbackRequestToServer(rollback_index - 1)
                else
                    -- rollback_index - 1 == 0
                    -- this snapshot is un-reachable, cuz it is too new
                    return nil
                end
                return i
            end
        end
        -- does not exists
        return nil
    end
end

-- we should correctly handle item containers, 
-- but we don't hope to have a very deep recursion for iterate container chain(if it is possible)
M.STAT_ITEM_CONTAINER_MAX_RECURSION_DEPTH = 3
local function count_item_in_slots(itemslots, item, current_depth, has_deeper_container)
    local count = 0

    for _, item in pairs(itemslots) do
        local stackable = item.components.stackable
       
        if item.prefab == item then
            count = count + (stackable and stackable:StackSize() or 1)
        end
       
        -- we always assume a container is impossible to be stackable, obviously :)
        -- a container which is stackable is crazy!
        if not stackable then
            local container = item.components.container
            if container then
                -- this item is a container
                if current_depth <= M.STAT_ITEM_CONTAINER_MAX_RECURSION_DEPTH then
                    local count_in_container
                    count_in_container, has_deeper_container = count_item_in_slots(container.slots, item, current_depth + 1, has_deeper_container)
                    count = count + count_in_container
                else
                    has_deeper_container = true
                end
            end
        end
    end
    
    return count, has_deeper_container
end

-- for online players in this shard
function M.CountItemInPlayerInventory(player, item)
    local inv = player.components.inventory
    if not inv then return 0, false end

    local itemslots_count, itemslots_has_deeper_container = count_item_in_slots(inv.itemslots, item, 1, false)
    local equipslots_count, equipslots_has_deeper_container = count_item_in_slots(inv.equipslots, item, 1, false)
    local activeitem_count, activeitem_has_deeper_container = 0, false
    if inv.activeitem then
        activeitem_count, activeitem_has_deeper_container = count_item_in_slots({inv.activeitem}, item, 1, false)
    end
    return itemslots_count + equipslots_count + activeitem_count, 
        itemslots_has_deeper_container or equipslots_has_deeper_container or activeitem_has_deeper_container
end

-- for offline players in this shard
function M.CountItemInOfflinePlayerInventory(player_userid, item)
    local inv = M.GetSnapshotPlayerData(player_userid, 'inventory')
    if not inv then return 0, false end

    -- notice: slots names are different from online player's inventory
    -- this inv comes from OnSave()
    local itemslots_count, itemslots_has_deeper_container = count_item_in_slots(inv.items, item, 1, false)
    local equipslots_count, equipslots_has_deeper_container = count_item_in_slots(inv.equip, item, 1, false)
    local activeitem_count, activeitem_has_deeper_container = 0, false
    if inv.activeitem then
        activeitem_count, activeitem_has_deeper_container =count_item_in_slots({inv.activeitem}, item, 1, false)
    end
    return itemslots_count + equipslots_count + activeitem_count, 
        itemslots_has_deeper_container or equipslots_has_deeper_container or activeitem_has_deeper_container
end

-- an expensive function!
function M.MakeOnlinePlayerInventoriesItemStat(item)
    local stat = {}
    for _, player in ipairs(AllPlayers) do
        local count, has_deeper_container = M.CountItemInPlayerInventory(player, item)
        stat[player.userid] = {
            count = count, 
            has_deeper_container = has_deeper_container
        }
    end
    return stat
end

-- another expensive function!
-- for a list of players(by passing a table of userid)
-- or a single player(by passing a userid)
function M.MakePlayerInventoriesItemStat(userid_or_list, item)
    if type(userid_or_list) == 'table' then
        
        local stat = {}
        -- make a quick ref
        local allplayers_by_userid_key = {}
        for _, player in ipairs(AllPlayers) do
            allplayers_by_userid_key[player.userid] = player
        end
        for _, userid in ipairs(userid_or_list) do
            local player = allplayers_by_userid_key[userid]
            local count, has_deeper_container
            if player then
                -- player is online
                count, has_deeper_container = M.CountItemInPlayerInventory(player, item)
            else
                -- player is offline
                count, has_deeper_container = M.CountItemInOfflinePlayerInventory(userid, item)
            end
            stat[userid] = {
                count = count, 
                has_deeper_container = has_deeper_container
            }
        end
        return stat
    
    elseif type(userid_or_list) == 'string' then
        -- is a userid(single player)
        local player
        if M.IsPlayerOnline(userid_or_list) then
            -- player is online
            player = M.GetPlayerByUserid(userid_or_list)
            if player then
                local count, has_deeper_container = M.CountItemInPlayerInventory(player, item)
                return {count = count, has_deeper_container = has_deeper_container}
            end
        end

        -- player is offline
        local count, has_deeper_container = M.CountItemInOfflinePlayerInventory(userid_or_list, item)
        return {count = count, has_deeper_container = has_deeper_container}
    else
        return nil
    end
end

-- file created in this way will not be delete while world regenerating
-- data: table, data will be serialize as a json file
function M.WriteModeratorDataToPersistentFile(userid_list)
    if type(userid_list) ~= 'table' then return end
    log('writing moderator data to persistent file:', M.MODERATOR_FILE_NAME)
    TheSim:SetPersistentString(M.MODERATOR_FILE_NAME, json.encode(userid_list), false) -- what does false means?

end

function M.ReadModeratorDataFromPersistentFile()
    log('reading moderator data from persistent file:', M.MODERATOR_FILE_NAME)
    local result_list
    TheSim:GetPersistentString(M.MODERATOR_FILE_NAME, function(load_success, data)
        if load_success and data then
            local decode_success, userid_list = pcall( function() return json.decode(data) end )
            if decode_success and userid_list then
                result_list = userid_list
            else
                log('error: failed to decode moderator data from persistent file')
            end
        else
            -- this might not a error
            dbg('failed to read moderator data from persistent file')
        end
    end)
    return result_list or {}
end


end -- is server