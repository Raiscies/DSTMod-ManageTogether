-- a component for world to record history players and other useful data


local M = manage_together

local dbg, chain_get = M.dbg, M.chain_get


local ShardServerInfoRecord = Class(
    function(self, inst)
        self.inst = inst -- inst is shard_network
        self.world = TheWorld
        self.player_record = {}
        self.snapshot_info = {slots = {}}

        self:InitNetVars()
        self:RegisterShardRPCs()

        -- register event listeners
        self.world:ListenForEvent('ms_playerjoined', function(src, player)
            dbg('ms_playerjoined:', player.userid)
            self:RecordPlayer(player.userid)
        end)
        self.world:ListenForEvent('ms_playerdespawn', function(src, player)
            dbg('ms_playerdespawn: player == nil: ', player == nil, ', player.userid: ', player and player.userid or '--')
        end)

        self.world:ListenForEvent('cycleschanged', function(src, data)
            self:ShardRecordOnlinePlayers(M.USER_PERMISSION_ELEVATE_IN_AGE)
        end)

        -- OnLoad will not be called if mod is firstly loaded 
        -- in this case, we should handle it properly
        self.world:DoTaskInTime(3, function()
            if #self.snapshot_info.slots ~= 0 then
                return
            end
            
            M.log('loading ShardServerInfoRecord the first time')
            self:LoadSaveInfo()
            self:LoadModeratorFile()
        
        end)
    end
)

function ShardServerInfoRecord:ShardSetPermission(userid, permission_level)
    local record = self.player_record[userid]
    if not record then return end

    local current = record.permission_level
    -- ADMIN is un-changeable
    if current == M.PERMISSION.ADMIN then return end

    if M.USER_PERMISSION_ELEVATE_IN_AGE and 
        current == M.PERMISSION.MODERATOR and 
        permission_level == M.PERMISSION.USER and
        record.age >= M.USER_PERMISSION_ELEVATE_IN_AGE
    then
        -- in this case, we should set a flag to keep the player's USER permission 
        self.player_record[userid].no_elevate_in_age = true
    else
        -- any other of the SetPermission operations will clear the flag  
        self.player_record[userid].no_elevate_in_age = nil
    end
    self.player_record[userid].permission_level = permission_level or M.PERMISSION.USER
end

function ShardServerInfoRecord:ShardSetShardLocation(userid, in_this_shard)
    local record = self.player_record[userid]
    if not record then return end

    -- keep the current flag
    if in_this_shard == nil then return end

    self.player_record[userid].in_this_shard = in_this_shard
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
    end

    if client then
        self.player_record[userid].name = client.name or ''
        self.player_record[userid].netid = client.netid
        self.player_record[userid].skin = client.base_skin
        self.player_record[userid].age = client.playerage or 0
        self:ShardSetPermission(userid, client.admin and M.PERMISSION.ADMIN or nil)
    else
        self:ShardSetPermission(userid)
    end

    self:ShardSetShardLocation(userid, in_this_shard)
end

function ShardServerInfoRecord:ShardRecordOnlinePlayers(do_permission_elevate)
    local online_clients = GetPlayerClientTable()
    if do_permission_elevate then
        for _, client in ipairs(online_clients) do
            self:ShardRecordPlayer(client.userid, client)
            self:ShardTryElevateUserPermissionByAge(client.userid, client.playerage)
        end
    else
        for _, client in ipairs(online_clients) do
            self:ShardRecordPlayer(client.userid, client)
        end
    end
end

function ShardServerInfoRecord:ShardTryElevateUserPermissionByAge(userid, newage)

    local record = self.player_record[userid]
    if not record or not M.USER_PERMISSION_ELEVATE_IN_AGE then return end

    if (newage >= M.USER_PERMISSION_ELEVATE_IN_AGE and 
        not record.no_elevate_in_age and
        M.LevelHigherThen(M.PERMISSION.MODERATOR, record.permission_level))
    then
        self:ShardSetPermission(M.PERMISSION.MODERATOR)
    end
end
 

function ShardServerInfoRecord:SetPermission(userid, permission_level)
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

function ShardServerInfoRecord:SetNetVar(name, value)
    -- must be set on master
    if TheShard:IsMaster() then
        self.netvar[name]:set(value)
    else
        SendModRPCToShard(
            GetShardModRPC(M.RPC.NAMESPACE, M.RPC.SHARD_SET_NET_VAR),
            SHARDID.MASTER, 
            name, value
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
    -- else
    --     M.WriteModeratorDataToPersistentFile({})
    end

    return {player_record = self.player_record, snapshot_info = self.snapshot_info}
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
                }
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

    AddShardModRPCHandler(M.RPC.NAMESPACE, M.RPC.SHARD_SET_NET_VAR, function(sender_shard_id, name, var)
        self.netvar[name]:set(var)
    end)
end

function ShardServerInfoRecord:InitNetVars()
    self.netvar = {
        is_rolling_back = net_bool(self.inst.GUID, 'shard_serverinforecord.is_rolling_back')
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
            -- dbg('slot: ', slot, ', savedata: ', savedata)
            
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
    -- dbg('list snapshots end, info: ', snapshot_info)
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