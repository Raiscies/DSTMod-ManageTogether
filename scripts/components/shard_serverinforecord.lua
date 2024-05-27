-- a component for world to record history players and other useful data


local M = manage_together

local dbg, chain_get = M.dbg, M.chain_get

local IsPlayerOnline = M.IsPlayerOnline

local ShardServerInfoRecord = Class(
    function(self, inst)
        self.inst = inst -- inst is shard_network
        self.world = TheWorld
        
        self.player_record = {}
        self.snapshot_info = {slots = {}}

        
        -- a ordered userid list for stable iterating
        -- notice: order might change while world reload
        self.player_record_userid_list = {}
        -- send a block in each requestion
        self.PLAYER_RECORD_BLOCK_SIZE = 12

        self:InitNetVars()
        self:RegisterShardRPCs()
        self:MasterOnlyInit()

        -- register event listeners

        -- ms_playerjoined is always push to master while 
        -- player is joining on the server, no metter they spawns on master or secondary shards 
        -- cuz they will migrate from master to secondary shard when join  
        self.inst:ListenForEvent('ms_playerjoined', function(src, player)
            dbg('ms_playerjoined:', player.userid)
            self:RecordPlayer(player.userid)
        end, self.world)

        -- ms_playerleft will be push only when player is left from master,
        -- but not left from secondary shard, so we should handle propaly
        self.inst:ListenForEvent('ms_playerleft', function(src, player)
            dbg('ms_playerleft')
            self:PushNetEvent('playerleft_from_a_shard')
        end, self.world)

        self.inst:ListenForEvent('cycleschanged', function(src, data)
            self:ShardRecordOnlinePlayers(M.USER_PERMISSION_ELEVATE_IN_AGE)
        end, self.world)
  

        -- OnLoad will not be called if mod is firstly loaded 
        -- in this case, we should handle it properly
        self.world:DoTaskInTime(0, function()
            if #self.snapshot_info.slots ~= 0 then
                return
            end
            
            M.log('loading ShardServerInfoRecord the first time')
            self:LoadSaveInfo()
            self:LoadModeratorFile()
            
            self.netvar.auto_new_player_wall_min_level:set(M.DEFAULT_AUTO_NEW_PLAYER_WALL_MIN_LEVEL)
            self.netvar.auto_new_player_wall_enabled:set(false)
        end)

    end
)

-- add a time stamp field, to optimize record data transmission costs between server & client 
-- everytime the function is called, timestamp will update
function ShardServerInfoRecord:ShardUpdateRecordTimeStamp(userid)
    self.player_record[userid].update_timestamp = GetTime()
end

ShardServerInfoRecord.MasterOnlyInit = TheShard:IsMaster() and function(self)
    -- master only

    self.inst:ListenForEvent('ms_playerjoined', function(src, player)
        dbg('ms_playerjoined on master')
        self:UpdateNewPlayerWallState()
    end, self.world)

    self.inst:ListenForEvent('ms_playerleft_from_a_shard', function()
        dbg('ms_playerleft_from_a_shard on master')
        self:UpdateNewPlayerWallState()
    end)

    self.inst:ListenForEvent('ms_new_player_joinability_changed', function()
        local allowed = not not self.netvar.allow_new_players_to_connect:value()
        dbg('event: ms_new_player_joinability_changed: ', allowed)
        TheNet:SetAllowNewPlayersToConnect(allowed)
    end)

    self:SetAllowNewPlayersToConnect(TheNet:GetAllowNewPlayersToConnect(), true) -- force update

    self.world:DoTaskInTime(0, function()
          -- update once
        dbg('update once new player wall')
        self:UpdateNewPlayerWallState()
    end)

end or function() end

function ShardServerInfoRecord:ShardSetPermission(userid, permission_level)
    
    local record = self.player_record[userid]
    if not record then return end

    local current = record.permission_level
    -- ADMIN is un-changeable
    if current == M.PERMISSION.ADMIN then  
        -- do nothing
    elseif M.USER_PERMISSION_ELEVATE_IN_AGE and              -- enabled auto elevation
        current == M.PERMISSION.MODERATOR and                -- current is moderator
        permission_level == M.PERMISSION.USER and            -- new is user
        record.age >= M.USER_PERMISSION_ELEVATE_IN_AGE then  -- elevation age is satisfied
        
        -- in this special case, we should set a flag to keep the player's USER permission in case it changes by auto elevation
        record.no_elevate_in_age = true
        record.permission_level = M.PERMISSION.USER
    elseif permission_level ~= nil then
        -- this flag will be reset only when new permission_level is not nil
        record.no_elevate_in_age = nil
        
        -- 1. set new permission_level if it is not nil
        -- 2. keep the old permission_level it is if not nil
        -- 3. initialize the permission_level to USER 
        record.permission_level = permission_level
    else
        record.permission_level = current or M.PERMISSION.USER
    end

    -- update netvers for target player
    -- M.SetPlayerClassifiedPermission(userid, record.permission_level)
    local player = M.GetPlayerByUserid(userid)
    if player and player.player_classified then
        player.player_classified:SetPermission(record.permission_level)
    end

    self:ShardUpdateRecordTimeStamp(userid)
end


function ShardServerInfoRecord:ShardSetShardLocation(userid, in_this_shard)
    local record = self.player_record[userid]
    if not record then return end

    -- keep the current flag
    if in_this_shard == nil then return end

    record.in_this_shard = in_this_shard

    self:ShardUpdateRecordTimeStamp(userid)
end

function ShardServerInfoRecord:ShardRecordPlayer(userid, in_this_shard, client)
    --[[
        recorded history player data:
        [userid]:
        name:                    client.name                               (string)
        netid:                   client.netid                              (string)
        age:                     client.playerage                          (number)
        permission_level                                                   (number)
        character base_skin:     client.base_skin                          (string)
        in_this_shard                                                      (boolean)
        no_elevate_in_age                                                  (boolean/nil)

        -- does not record, this is already indirectly recorded by base_skin
        -- character             client.prefab                              (string/number)
    ]]--

    if not client then client = TheNet:GetClientTableForUser(userid) end

    if not self.player_record[userid] then
        self.player_record[userid] = {}
        table.insert(self.player_record_userid_list, userid)
    end
    local record = self.player_record[userid]

    if client then
        record.name = client.name or ''
        record.netid = client.netid
        record.skin = client.base_skin
        record.age = client.playerage or 0
        self:ShardSetPermission(userid, client.admin and M.PERMISSION.ADMIN or nil)
    else
        self:ShardSetPermission(userid)
    end 

    self:ShardSetShardLocation(userid, in_this_shard)

    -- no need for call it, ShardServerInfoRecord() or ShardSetPermission() did
    -- self:ShardUpdateRecordTimeStamp(userid)
end

function ShardServerInfoRecord:ShardRecordOnlinePlayers(do_permission_elevate)
    local online_clients = GetPlayerClientTable()
    if do_permission_elevate then
        for _, client in ipairs(online_clients) do
            self:ShardRecordPlayer(client.userid, nil, client)
            self:ShardTryElevateUserPermissionByAge(client.userid)
        end
    else
        for _, client in ipairs(online_clients) do
            self:ShardRecordPlayer(client.userid, nil, client)
        end
    end
end

function ShardServerInfoRecord:ShardTryElevateUserPermissionByAge(userid)

    local record = self.player_record[userid]
    if not record or not M.USER_PERMISSION_ELEVATE_IN_AGE then return end

    if (record.age >= M.USER_PERMISSION_ELEVATE_IN_AGE and 
        not record.no_elevate_in_age and
        M.LevelHigherThan(M.PERMISSION.MODERATOR, record.permission_level))
    then
        self:ShardSetPermission(userid, M.PERMISSION.MODERATOR)
    end
end


function ShardServerInfoRecord:SetPermission(userid, permission_level)
    -- broadcast to every shards
    SendModRPCToShard(
        GetShardModRPC(M.RPC.NAMESPACE, M.RPC.SHARD_SET_PLAYER_PERMISSION), 
        nil, 
        userid, 
        permission_level
    )
end

function ShardServerInfoRecord:RecordPlayer(userid)
    SendModRPCToShard(
        GetShardModRPC(M.RPC.NAMESPACE, M.RPC.SHARD_RECORD_PLAYER), 
        nil, 
        userid
    )
end

function ShardServerInfoRecord:RecordOnlinePlayers(do_permission_elevate)
    SendModRPCToShard(
        GetShardModRPC(M.RPC.NAMESPACE, M.RPC.SHARD_RECORD_ONLINE_PLAYERS), 
        nil, 
        do_permission_elevate
    ) 
end

function ShardServerInfoRecord:SetNetVar(name, value, force_update)
    -- must be set on master
    if TheShard:IsMaster() then
        if force_update then
            self.netvar[name]:set_local(value)
        end
        self.netvar[name]:set(value)
    else
        SendModRPCToShard(
            GetShardModRPC(M.RPC.NAMESPACE, M.RPC.SHARD_SET_NET_VAR),
            SHARDID.MASTER, 
            name, value, force_update
        )
    end
end
function ShardServerInfoRecord:PushNetEvent(name)
    -- must be set on master
    if TheShard:IsMaster() then
        self.netvar[name]:push()
    else
        SendModRPCToShard(
            GetShardModRPC(M.RPC.NAMESPACE, M.RPC.SHARD_PUSH_NET_EVENT),
            SHARDID.MASTER, 
            name
        )
    end
end

local function SendPlayerRecord(acceptor_userid, record_userid, record)
    if IsPlayerOnline(record_userid) then
        SendModRPCToClient(
            GetClientModRPC(M.RPC.NAMESPACE, M.RPC.ONLINE_PLAYER_RECORD_SYNC), acceptor_userid, 
            record_userid, record.permission_level
        )
    else
        SendModRPCToClient(
            GetClientModRPC(M.RPC.NAMESPACE, M.RPC.OFFLINE_PLAYER_RECORD_SYNC), acceptor_userid, 
            record_userid, record.netid, record.name, record.age, record.skin, record.permission_level
        )
    end
end

function ShardServerInfoRecord:PushPlayerRecordTo(userid, last_query_timestamp, block_index)
    -- block_index only works for offline players, online player's records are always being sended(if it is updated)

    if not last_query_timestamp then
        last_query_timestamp = 0
    end
    if block_index == nil then

        for record_userid, record in pairs(self.player_record) do
            if record.update_timestamp >= last_query_timestamp then
                -- record is newer
                SendPlayerRecord(userid, record_userid, record)
            end
        end
        SendModRPCToClient(
            GetClientModRPC(M.RPC.NAMESPACE, M.RPC.PLAYER_RECORD_SYNC_COMPLETED), userid,
            false -- has_more
        )

        return
    end
    
    local from = (block_index - 1) * self.PLAYER_RECORD_BLOCK_SIZE + 1
    local to = block_index * self.PLAYER_RECORD_BLOCK_SIZE

    for i, record_userid in ipairs(self.player_record_userid_list) do
        local record = self.player_record[record_userid]
        if IsPlayerOnline(record_userid) and 
            record.update_timestamp >= last_query_timestamp then

            -- always push the updated online player records
            SendModRPCToClient(
                GetClientModRPC(M.RPC.NAMESPACE, M.RPC.ONLINE_PLAYER_RECORD_SYNC), userid, 
                record_userid, record.permission_level
            )
        elseif from <= i and i <= to then
            -- send this block's records
            -- this player still possibly a online player
            SendPlayerRecord(userid, record_userid, record)
        end
    end

    SendModRPCToClient(
        GetClientModRPC(M.RPC.NAMESPACE, M.RPC.PLAYER_RECORD_SYNC_COMPLETED), userid,
        to < #self.player_record_userid_list -- has_more
    )

end

function ShardServerInfoRecord:PushSnapshotInfoTo(userid)
    local slots = self.snapshot_info.slots
    if not slots then return end

    for i, v in ipairs(slots) do
        SendModRPCToClient(
            GetClientModRPC(M.RPC.NAMESPACE, M.RPC.SNAPSHOT_INFO_SYNC), userid, 
            i, v.snapshot_id, v.day, v.season
        )
    end
end

function ShardServerInfoRecord:OnSave()
    dbg('ShardServerInfoRecord OnSave')

    -- OnSave will be call everytime while world is saved
    -- not just while server is shutting down

    self.world:DoTaskInTime(3, function()
        self:UpadateSaveInfo()
    end)

    if M.RESERVE_MODERATOR_DATA_WHILE_WORLD_REGEN then
        M.WriteModeratorDataToPersistentFile(self:MakeModeratorUseridList())
    end
    
    if TheShard:IsMaster() then
        return {
            player_record = self.player_record, 
            snapshot_info = self.snapshot_info,
            auto_new_player_wall_min_level = self.netvar.auto_new_player_wall_min_level:value(), 
            auto_new_player_wall_enabled = self.netvar.auto_new_player_wall_enabled:value()
        }
    else
        return {
            player_record = self.player_record, 
            snapshot_info = self.snapshot_info
        }
    end

end

function ShardServerInfoRecord:OnLoad(data)
    dbg('ShardServerInfoRecord OnLoad')
    if data ~= nil then 
        if data.player_record ~= nil then
            for userid, player in pairs(data.player_record) do
                self.player_record[userid] = {
                    netid             = player.netid,
                    name              = player.name,
                    age               = player.age,
                    skin              = player.skin,
                    permission_level  = player.permission_level, 
                    in_this_shard     = player.in_this_shard,
                    no_elevate_in_age = player.no_elevate_in_age,
                    update_timestamp  = 0
                }
                table.insert(self.player_record_userid_list, userid)
            end
        end
        
        if data.snapshot_info then
            dbg('assigning snapshot_info')
            self.snapshot_info = data.snapshot_info
            self:UpadateSaveInfo()
        else
            self:LoadSaveInfo()
        end        
    else
        -- we dont have any info of snapshots, so we should load it from save file
        -- which is a time spanding operation
        self:LoadSaveInfo()
        
    end

    self.netvar.auto_new_player_wall_min_level:set(
        data and data.auto_new_player_wall_min_level or M.DEFAULT_AUTO_NEW_PLAYER_WALL_MIN_LEVEL
    )
    self.netvar.auto_new_player_wall_enabled:set(
        data and data.auto_new_player_wall_enabled or M.DEFAULT_AUTO_NEW_PLAYER_WALL_ENABLED
    )

end



function ShardServerInfoRecord:RegisterShardRPCs()
    AddShardModRPCHandler(M.RPC.NAMESPACE, M.RPC.SHARD_RECORD_PLAYER, function(sender_shard_id, userid)
        self:ShardRecordPlayer(userid, tostring(sender_shard_id) == TheShard:GetShardId())
    end)

    AddShardModRPCHandler(M.RPC.NAMESPACE, M.RPC.SHARD_RECORD_ONLINE_PLAYERS, function(sender_shard_id, do_permission_elevate)
        self:ShardRecordOnlinePlayers(do_permission_elevate)
    end)

    AddShardModRPCHandler(M.RPC.NAMESPACE, M.RPC.SHARD_SET_PLAYER_PERMISSION, function(sender_shard_id, userid, permission_level)
        self:ShardSetPermission(userid, permission_level)
    end)

    AddShardModRPCHandler(M.RPC.NAMESPACE, M.RPC.SHARD_SET_NET_VAR, function(sender_shard_id, name, value, force_update)
        self:SetNetVar(name, value, force_update)
    end)
    AddShardModRPCHandler(M.RPC.NAMESPACE, M.RPC.SHARD_PUSH_NET_EVENT, function(sender_shard_id, name)
        self:PushNetEvent(name)
    end)
end

function ShardServerInfoRecord:InitNetVars()
    self.netvar = {
        is_rolling_back = net_bool(self.inst.GUID, 'shard_serverinforecord.is_rolling_back'),
        auto_new_player_wall_min_level = net_byte(self.inst.GUID, 'shard_serverinforecord.auto_new_player_wall_min_level'), 
        auto_new_player_wall_enabled = net_bool(self.inst.GUID, 'shard_serverinforecord.auto_new_player_wall_enabled'),
        allow_new_players_to_connect = net_bool(self.inst.GUID, 'shard_serverinforecord.allow_new_players_to_connect', 'ms_new_player_joinability_changed'),
        
        playerleft_from_a_shard = net_event(self.inst.GUID, 'ms_playerleft_from_a_shard')
    }

end
function ShardServerInfoRecord:SetIsRollingBack(b)
    if b == nil then
        self:SetNetVar('is_rolling_back', true) 
    else
        self:SetNetVar('is_rolling_back', b)   
    end
end
function ShardServerInfoRecord:GetIsRollingBack()
    return self.netvar.is_rolling_back:value()
end

function ShardServerInfoRecord:SetAllowNewPlayersToConnect(allowed, force_update)
    self:SetNetVar('allow_new_players_to_connect', allowed, force_update)
end
function ShardServerInfoRecord:GetAllowNewPlayersToConnect()
    return self.netvar.allow_new_players_to_connect:value()
end

function ShardServerInfoRecord:SetAutoNewPlayerWall(enabled, min_level)
    if enabled ~= nil then
        self:SetNetVar('auto_new_player_wall_enabled', enabled)
    end
    if min_level ~= nil then
        self:SetNetVar('auto_new_player_wall_min_level', min_level)
    end
end
function ShardServerInfoRecord:GetAutoNewPlayerWall()
    return {
        enabled = self.netvar.auto_new_player_wall_enabled:value(), 
        min_level = self.netvar.auto_new_player_wall_min_level:value()
    }
end

-- master side only
-- call this after player list changed
ShardServerInfoRecord.UpdateNewPlayerWallState = TheShard:IsMaster() and function(self)    
    if not self.netvar.auto_new_player_wall_enabled:value() then
        -- new auto player wall is disabled
        return
    end
    
    dbg('updating new player wall state...')
    local required_min_level = self.netvar.auto_new_player_wall_min_level:value()
    local old_state = TheNet:GetAllowNewPlayersToConnect()
    local new_state

    if required_min_level == M.PERMISSION.MINIMUM then
        -- auto new player wall state: allow new players to join
        new_state = true
    else
        dbg('judging...')
        local current_highest_online_player_level = M.PERMISSION.MINIMUM
        for _, client in ipairs(GetPlayerClientTable()) do
            local level = self.player_record[client.userid].permission_level
            dbg('client: ', client, ', level: ', level)
            if M.LevelHigherThan(level, current_highest_online_player_level) then
                current_highest_online_player_level = level
            end
            dbg('current_highest_online_player_level: ', current_highest_online_player_level)
        end
        dbg('required_min_level:', required_min_level)
        -- if current_min_online_player_level is not satisfied the self.netvar.auto_new_player_wall_min_level, 
        -- then auto new player wall state: not allow new players to join
        new_state = M.LevelHigherThanOrEqual(current_highest_online_player_level, required_min_level)
    end
    -- judge the new_state ended

    if old_state ~= new_state then
        self:SetAllowNewPlayersToConnect(new_state)
    end
    dbg('finished to update new player wall state, old_state = ', old_state, ', new_state = ', new_state, ', required_min_level = ', required_min_level)
    self.world:PushEvent('master_newplayerwallupdate', {old_state = old_state, new_state = new_state, required_min_level = required_min_level})

end or function() end

-- this function is expensive
function ShardServerInfoRecord:LoadSaveInfo()
    -- 不得不说饥荒的存档设计真的是很抽象, 每个用于回档的快照就是一个巨大的lua文件, 
    -- 要加载的时候扔沙盒里跑一遍就拿到存档数据 
    -- 有一种简单粗暴的美

    -- self.snapshot_info:
    --  .session_id
    --  .slots:
    --      .snapshot_id 
    --      .day
    --      .season

    local function set_day_season_info(slot, worlddata)
        -- days
        if worlddata.clock ~= nil then
            self.snapshot_info.slots[slot].day = (worlddata.clock.cycles or 0) + 1
        end
        
        -- seasons
        if worlddata.seasons ~= nil and worlddata.seasons.season ~= nil then
            self.snapshot_info.slots[slot].season = M.SEASONS[worlddata.seasons.season]
        end
    end

    local function make_on_read_world_file(slot)
        return function(read_success, s)
            if not read_success or s == nil then
                return
            end
            local run_success, savedata = RunInSandbox(s)
            if not run_success or savedata == nil then
                dbg('failed to run the world file')
                return
            end
             
            
            -- this is for loading the whole world file
            -- if savedata.world_network then
            --     set_day_season_info(slot, savedata.world_network.persistdata)
            -- else
            --     self.snapshot_info.slots[slot].day = 1
            -- end

            -- this is for loading world meta file
            set_day_season_info(slot, savedata)
        end
    end
    
    local index = ShardGameIndex
    -- I don't know why, but it just works...
    local snapshot_info = TheNet:ListSnapshots(index.session_id, index.server.online_mode, 10)
     
    self.snapshot_info = {
        session_id = index.session_id, 
        slots = {}
    }

    for i, v in ipairs(snapshot_info) do
        if v.snapshot_id ~= nil then
            self.snapshot_info.slots[i] = {
                snapshot_id = v.snapshot_id
            }
            
            if v.world_file ~= nil then
                -- fortunately, we don't need to load a whole world file, 
                -- .meta file is enough
                local world_meta_file = v.world_file .. '.meta'
                TheSim:GetPersistentString(world_meta_file, make_on_read_world_file(i))
                
            end
        end
    end

    
end

function ShardServerInfoRecord:LoadModeratorFile()
    -- try to load moderator list data
    if M.RESERVE_MODERATOR_DATA_WHILE_WORLD_REGEN then
        local moderator_userid_list = M.ReadModeratorDataFromPersistentFile()
        if not moderator_userid_list or #moderator_userid_list == 0 then
            M.log('moderator file does not found or is empty, proberly this is really a new world :)')
            return
        end
        
        for _, userid in ipairs(moderator_userid_list) do
            self:ShardRecordPlayer(userid)
            self:ShardSetPermission(userid, M.PERMISSION.MODERATOR)
        end
        M.log('successfully re-record moderator data from persistent file')
    end
end

-- this should be call only after snapshot_info changed
-- 1. after OnSave
-- 2. after game started, OnSave may not be called before game started, 
--    eg. rollback, or game first generated

function ShardServerInfoRecord:UpadateSaveInfo()
    dbg('UpadateSaveInfo')
    local index = ShardGameIndex
    local snapshot_info = TheNet:ListSnapshots(index.session_id, index.server.online_mode, 10)
    local new_slots = {}
    
    local existed_snapshot_ids = {}
    for i, v in ipairs(self.snapshot_info.slots) do
        existed_snapshot_ids[v.snapshot_id] = i
    end
    for _, v in ipairs(snapshot_info) do
        if existed_snapshot_ids[v.snapshot_id] then
            local slot = self.snapshot_info.slots[existed_snapshot_ids[v.snapshot_id]]
            table.insert(new_slots, {
                snapshot_id = v.snapshot_id, 
                day = slot.day,             -- -slot's day and season data might missing, it will be nil, but never mind it
                season = slot.season
            })
        else
            -- this slot is new
            table.insert(new_slots, {
                snapshot_id = v.snapshot_id
            })
        end
    end

    -- if not new_slots[1].day then
        -- the current slot's snapshot_id is new 
        
    -- set the newest slot's day and season data
    -- the data is just current day and season
    self.world:DoTaskInTime(0, function()
        -- cycle means the currently finished day-night cycles, so we should plus 1 to get the current day
        self.snapshot_info.slots[1].day = self.world.state.cycles + 1
        self.snapshot_info.slots[1].season = M.SEASONS[self.world.state.season]
    end)
   
    self.snapshot_info.slots = new_slots
    if not self.snapshot_info.session_id then
        self.snapshot_info.session_id = index.session_id
    end

end

function ShardServerInfoRecord:BuildDaySeasonStringByInfoIndex(index)
    index = index or 1
    return M.BuildDaySeasonString(self.snapshot_info.slots[index].day, self.snapshot_info.slots[index].season)
end
function ShardServerInfoRecord:BuildDaySeasonStringBySnapshotID(snapshot_id)
    snapshot_id = snapshot_id or TheNet:GetCurrentSnapshot()
    for _, v in ipairs(self.snapshot_info.slots) do
        if v.snapshot_id == snapshot_id then
            return M.BuildDaySeasonString(v.day, v.season)
        end
    end
    return M.BuildDaySeasonString(nil, nil) -- this function can correctly handle nil arguments
end

function ShardServerInfoRecord:SnapshotIDExists(snapshot_id)
    for _, v in ipairs(self.snapshot_info.slots) do
        if v.snapshot_id == snapshot_id then
            return true
        end
    end
    return false
end

function ShardServerInfoRecord:MakeModeratorUseridList()
    local result = {}
    for userid, player in pairs(self.player_record) do
        if player.permission_level == M.PERMISSION.MODERATOR then
            table.insert(result, userid)
        end
    end
    return result
end

return ShardServerInfoRecord