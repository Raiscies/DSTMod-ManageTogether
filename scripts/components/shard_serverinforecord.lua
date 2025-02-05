-- a component for world to record history players and other useful data


local M = manage_together

-- M.usingnamespace(M)

local dbg, log, bool = M.dbg, M.log, M.bool
local IsPlayerOnline = M.IsPlayerOnline

local AddServerRPC = M.AddServerRPC
local AddClientRPC = M.AddClientRPC
local AddShardRPC = M.AddShardRPC
local SendRPCToServer = M.SendRPCToServer
local SendRPCToClient = M.SendRPCToClient
local SendRPCToShard = M.SendRPCToShard

local ShardServerInfoRecord = Class(
    function(self, inst)
        self.inst = inst -- inst is shard_network
        
        self.player_record = {}
        self.snapshot_info = {slots = {}}

        
        -- a ordered userid list for stable iterating
        -- notice: order might change while world reload
        self.player_record_userid_list = {}
        -- send a block in each requestion
        self.PLAYER_RECORD_BLOCK_SIZE = 12

        self:InitNetVars()
        self:RegisterShardRPCs()
        -- self:MasterOnlyInit()

        -- register event listeners

        -- ms_playerjoined is always push to master while 
        -- player is joining on the server, no metter they spawns on master or secondary shards 
        -- cuz they will migrate from master to secondary shard when join  




        if TheWorld.ismastershard then
            -- is master shard
            self.inst:ListenForEvent('ms_playerjoined', function(src, player)
                dbg('ms_playerjoined(master):', player.userid)
                TheWorld:DoTaskInTime(0, function()
                    self:RecordPlayer(player.userid) 
                    self:UpdateNewPlayerWallState() 
                end)
            end, TheWorld)

            self.inst:ListenForEvent('ms_playerleft_from_a_shard', function()
                dbg('ms_playerleft_from_a_shard on master')
                self:UpdateNewPlayerWallState() 
            end)

            TheWorld:DoTaskInTime(0, function()
                self:UpdateNewPlayerWallState(true) -- force update
            end)
        else

            -- is secondary shard
            self.inst:ListenForEvent('ms_playerjoined', function(src, player)
                dbg('ms_playerjoined: {player.userid = }')
                TheWorld:DoTaskInTime(0, function()
                    self:RecordPlayer(player.userid)
                end)
                
            end, TheWorld)
        end

        -- ms_playerleft will be push only when player is left from master,
        -- but not left from secondary shard, so we should handle propaly
        self.inst:ListenForEvent('ms_playerleft', function(src, player)
            dbg('ms_playerleft')
            self:PushNetEvent('playerleft_from_a_shard')
        end, TheWorld)

        self.inst:ListenForEvent('cycleschanged', function(src, data)
            self:ShardRecordOnlinePlayers(M.USER_PERMISSION_ELEVATE_IN_AGE)
        end, TheWorld)
  

        -- OnLoad will not be called if mod is firstly loaded 
        -- in this case, we should handle it properly
        TheWorld:DoTaskInTime(0, function()
            if #self.snapshot_info.slots ~= 0 then
                return
            end
            
            log('loading ShardServerInfoRecord the first time')
            self:LoadSaveInfo()
            self:LoadModeratorFile()
            
            self.netvar.auto_new_player_wall_min_level:set(M.DEFAULT_AUTO_NEW_PLAYER_WALL_MIN_LEVEL)
            self.netvar.auto_new_player_wall_enabled:set(false)
        end)
        
        if M.MOD_OUTOFDATE_HANDLER_ENABLED then
            self:InitModOutOfDateHandler()
        end
        
        M.shard_serverinforecord = self
    end
)

function ShardServerInfoRecord:InitModOutOfDateHandler()

    self.mod_out_of_date_handler = Class(function(self, recorder)

        self.recorder = recorder
        
        local triggered_once
        local callbacks
        if TheShard:IsMaster() then
                
            -- callbacks are only work at Master
            callbacks = {}        
            
            triggered_once = false

            function self:Add(fn, trig_once)
                table.insert(callbacks, {fn = fn, once = trig_once})
                return self
            end
            function self:Remove(fn)
                for i, v in ipairs(callbacks) do
                    if v.fn == fn then
                        return table.remove(callbacks, i)
                    end
                end
            end
        end

        local original_callback = _G.Networking_ModOutOfDateAnnouncement


        -- register netvars 
        recorder.netvar.is_announcement_suppressed = net_bool(recorder.inst.GUID, 'shard_serverinforecord.is_announcement_suppressed', 'ms_modoutofdate_announcement_state_changed')
        recorder.netvar.is_mod_outofdate = net_bool(recorder.inst.GUID, 'shard_serverinforecord.is_mod_outofdate', 'ms_modoutofdate_state_changed')

        local is_announcement_suppressed = false
        local is_mod_outofdate = false

        function self:SetSuppressAnnouncement(val)
            recorder:SetNetVar('is_announcement_suppressed', val)
        end
        function self:SetIsModOutofDate()
            recorder:SetNetVar('is_mod_outofdate', true)
        end
        
        function self:GetSuppressAnnouncement()
            return is_announcement_suppressed
        end

        function self:GetOriginalCallback()
            return original_callback
        end


        -- hook target function
        _G.Networking_ModOutOfDateAnnouncement = function(mod)
            -- suppress the announcement on server side is useless for clients,
            -- this should affects the server log, so we just remain it
            -- if not is_announcement_suppressed then
            original_callback(mod)
            -- end

            recorder.world:PushEvent('ms_modoutofdate', mod)

            dbg('Networking_ModOutOfDateAnnouncement is called')
        end

        -- raised from Networking_ModOutOfDateAnnouncement
        recorder.inst:ListenForEvent('ms_modoutofdate', function(src, modname)
            self:SetIsModOutofDate()
            dbg('ms_modoutofdate')
        end, recorder.world)

        -- netvar events
        recorder.inst:ListenForEvent('ms_modoutofdate_announcement_state_changed', function(src)
            is_announcement_suppressed = recorder.netvar.is_announcement_suppressed:value()
            if is_announcement_suppressed then
                log('mod out of date announcement is suppressed')

            else
                log('mod out of date announcement is recovered')
            end
        end)
        recorder.inst:ListenForEvent('ms_modoutofdate_state_changed', function(src)
            dbg('ms_modoutofdate_state_changed')
            is_mod_outofdate = recorder.netvar.is_mod_outofdate:value()
            if is_mod_outofdate then
                -- mod is out of date
                log(string.format('received an event from shard %s that mod is out of date', tostring(src)))
                
                if recorder.world.ismastersim then
                    
                    for _, v in ipairs(callbacks) do
                        if not (v.once and triggered_once) then
                            v.fn()
                        end
                    end

                    triggered_once = true
                end
            else
                -- state is reset
                dbg('received an event from shard ', tostring(src), ' that mod out of date state is reset')
            end
        end)

    end)(
        -- a sigleton instance
        self
    )
    

end

-- add a time stamp field, to optimize record data transmission costs between server & client 
-- everytime the function is called, timestamp will update
function ShardServerInfoRecord:ShardUpdateRecordTimeStamp(userid)
    self.player_record[userid].update_timestamp = GetTime()
end

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
        -- M.LevelHigherThan(M.PERMISSION.MODERATOR, record.permission_level))
        M.Level.higher(M.PERMISSION.MODERATOR, record.permission_level))
    then
        self:ShardSetPermission(userid, M.PERMISSION.MODERATOR)
    end
end


function ShardServerInfoRecord:SetPermission(userid, permission_level)
    -- broadcast to every shards
    SendRPCToShard(
        'SHARD_SET_PLAYER_PERMISSION', 
        nil, 
        userid, 
        permission_level
    )
end

function ShardServerInfoRecord:RecordPlayer(userid)
    SendRPCToShard(
        'SHARD_RECORD_PLAYER', 
        nil, 
        userid
    )
end

function ShardServerInfoRecord:RecordOnlinePlayers(do_permission_elevate)
    SendRPCToShard(
        'SHARD_RECORD_ONLINE_PLAYERS', 
        nil, 
        do_permission_elevate
    ) 
end

function ShardServerInfoRecord:SetNetVar(name, value, force_update)
    -- must be set on master
    if TheShard:IsMaster() then

        -- pass boolean from rpc will be cast to nil if it is false, 
        -- however netvar does not accept nil, it will cause crash
        -- so we have to cast it back
        value = value ~= nil and value or false

        if force_update then
            self.netvar[name]:set_local(value)
        end
        self.netvar[name]:set(value)
    else
        SendRPCToShard(
            'SHARD_SET_NET_VAR',
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
        SendRPCToShard(
            'SHARD_PUSH_NET_EVENT',
            SHARDID.MASTER, 
            name
        )
    end
end

local function send_player_record(acceptor_userid, record_userid, record)
    if IsPlayerOnline(record_userid) then
        SendRPCToClient(
            'ONLINE_PLAYER_RECORD_SYNC', acceptor_userid, 
            record_userid, record.permission_level
        )
    else
        SendRPCToClient(
            'OFFLINE_PLAYER_RECORD_SYNC', acceptor_userid, 
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
                send_player_record(userid, record_userid, record)
            end
        end
        SendRPCToClient(
            'PLAYER_RECORD_SYNC_COMPLETED', userid,
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
            SendRPCToClient(
                'ONLINE_PLAYER_RECORD_SYNC', userid, 
                record_userid, record.permission_level
            )
        elseif from <= i and i <= to then
            -- send this block's records
            -- this player still possibly a online player
            send_player_record(userid, record_userid, record)
        end
    end

    SendRPCToClient(
        'PLAYER_RECORD_SYNC_COMPLETED', userid,
        to < #self.player_record_userid_list -- has_more
    )

end

function ShardServerInfoRecord:PushSnapshotInfoTo(userid)
    local slots = self.snapshot_info.slots
    if not slots then return end

    for i, v in ipairs(slots) do
        SendRPCToClient(
            'SNAPSHOT_INFO_SYNC', userid, 
            i, v.snapshot_id, v.day, v.season, v.phase
        )
    end
end

function ShardServerInfoRecord:OnSave()
-- OnSave will be called every time the world is saved
-- not just when the server is shutting down

    -- we really need a delay
    TheWorld:DoTaskInTime(0, function()
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

    AddShardRPC('SHARD_RECORD_PLAYER', function(sender_shard_id, userid)
        self:ShardRecordPlayer(userid, tostring(sender_shard_id) == TheShard:GetShardId())
    end, true) -- no_response
    AddShardRPC('SHARD_RECORD_ONLINE_PLAYERS', function(sender_shard_id, do_permission_elevate)
        self:ShardRecordOnlinePlayers(do_permission_elevate)
    end, true)
    AddShardRPC('SHARD_SET_PLAYER_PERMISSION', function(sender_shard_id, userid, permission_level)
        self:ShardSetPermission(userid, permission_level)
    end, true)
    
    AddShardRPC('SHARD_SET_NET_VAR', function(sender_shard_id, name, value, force_update)
        self:SetNetVar(name, value, force_update)
    end, true)
    AddShardRPC('SHARD_PUSH_NET_EVENT', function(sender_shard_id, name)
        self:PushNetEvent(name)
    end, true)
    
end

function ShardServerInfoRecord:InitNetVars()
    self.netvar = {
        is_rolling_back = net_bool(self.inst.GUID, 'shard_serverinforecord.is_rolling_back'),
        auto_new_player_wall_min_level = net_byte(self.inst.GUID, 'shard_serverinforecord.auto_new_player_wall_min_level', 'ms_auto_new_player_wall_dirty'), 
        auto_new_player_wall_enabled = net_bool(self.inst.GUID, 'shard_serverinforecord.auto_new_player_wall_enabled', 'ms_auto_new_player_wall_dirty'),
        allow_new_players_to_connect = net_bool(self.inst.GUID, 'shard_serverinforecord.allow_new_players_to_connect', 'ms_new_player_joinability_dirty'),
        
        playerleft_from_a_shard = net_event(self.inst.GUID, 'ms_playerleft_from_a_shard')
    }

    self.inst:ListenForEvent('ms_auto_new_player_wall_dirty', function()

        local enabled, level = self:GetAutoNewPlayerWall()
        dbg('ms_auto_new_player_wall_dirty: enabled =', enabled, ', level =', level)
        local data = {
            enabled = enabled,
            level = level
        }

        TheWorld:PushEvent('ms_auto_new_player_wall_changed', data)
    end)

    self.inst:ListenForEvent('ms_new_player_joinability_dirty', function()
        local allowed = bool(self.netvar.allow_new_players_to_connect:value())
        dbg('ms_new_player_joinability_dirty: ', allowed)

        if TheWorld.ismastershard then
            TheNet:SetAllowNewPlayersToConnect(allowed)
        end

        TheWorld:PushEvent('ms_new_player_joinability_changed', allowed)
    end)

end
function ShardServerInfoRecord:SetIsRollingBack(b)
    if b == nil then
        b = true
    end

    if self:GetIsRollingBack() and b then
        return
    end
    self:SetNetVar('is_rolling_back', b)   
    
    if b == true then
        M.execute_in_time(60, function()
            -- reset the flag automatically
            self:SetNetVar('is_rolling_back', false)
        end)
    end
end

function ShardServerInfoRecord:GetIsRollingBack()
    return self.netvar.is_rolling_back:value()
end

function ShardServerInfoRecord:SetAllowNewPlayersToConnect(allowed, force_update)
    self:SetNetVar('allow_new_players_to_connect', allowed, force_update)
end
function ShardServerInfoRecord:GetAllowNewPlayersToConnect()
    return bool(self.netvar.allow_new_players_to_connect:value())
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
    -- enabled, min_level
    return bool(self.netvar.auto_new_player_wall_enabled:value()), self.netvar.auto_new_player_wall_min_level:value()
end

-- master side only
-- call this after player list changed
ShardServerInfoRecord.UpdateNewPlayerWallState = TheShard:IsMaster() and function(self, force_update)
    if not self.netvar.auto_new_player_wall_enabled:value() then
        -- new auto player wall is disabled
        return
    end
    
    local required_min_level = self.netvar.auto_new_player_wall_min_level:value()
    local old_state = self.netvar.allow_new_players_to_connect:value()
    local new_state

    if required_min_level == M.PERMISSION.MINIMUM then
        -- auto new player wall state: allow new players to join
        new_state = true
    else
        
        local current_highest_online_player_level = M.PERMISSION.MINIMUM
        for _, client in ipairs(GetPlayerClientTable()) do
            local record = self.player_record[client.userid] 
            -- in case record not exists
            local level = record and record.permission_level or M.PERMISSION.USER
            dbg('{client.name: }, {level: }')
            -- if M.LevelHigherThan(level, current_highest_online_player_level) then
            if M.Level.higher(level, current_highest_online_player_level) then
                current_highest_online_player_level = level
            end
            
        end
        
        -- if current_min_online_player_level is not satisfied the self.netvar.auto_new_player_wall_min_level, 
        -- then auto new player wall state: not allow new players to join
        -- new_state = M.LevelHigherThanOrEqual(current_highest_online_player_level, required_min_level)
        new_state = M.Level.higher_or_equal(current_highest_online_player_level, required_min_level)
    end
    -- judge the new_state ended

    self:SetAllowNewPlayersToConnect(new_state, force_update)

    dbg('finished to update new player wall state, old_state = ', old_state, ', new_state = ', new_state, ', required_min_level = ', required_min_level)
    TheWorld:PushEvent('master_newplayerwallupdate', {old_state = old_state, new_state = new_state, required_min_level = required_min_level})

end or function()
    
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
    --      .phase

    local function set_day_season_info(slot, worlddata)
        -- days & phase
        if worlddata.clock ~= nil then
            self.snapshot_info.slots[slot].day = (worlddata.clock.cycles or 0) + 1

            -- phase: {'day', 'dusk', 'night'}
            self.snapshot_info.slots[slot].phase = worlddata.clock.phase
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
            log('moderator file does not found or is empty, proberly this is really a new world :)')
            return
        end
        
        for _, userid in ipairs(moderator_userid_list) do
            self:ShardRecordPlayer(userid)
            self:ShardSetPermission(userid, M.PERMISSION.MODERATOR)
        end
        log('successfully re-record moderator data from persistent file')
    end
end

-- this should be call only after snapshot_info changed
-- 1. after OnSave
-- 2. after game started, OnSave may not be called before game started, 
--    eg. rollback, or game first generated
function ShardServerInfoRecord:UpadateSaveInfo()
    
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
                season = slot.season,
                phase = slot.phase
            })
        else
            -- this slot is new
            table.insert(new_slots, {
                snapshot_id = v.snapshot_id
            })
        end
    end
        
    -- set the newest slot's day and season data
    -- the data is just current day, season and phase
    
    -- do we really need a delay?
    -- cycle means the currently finished day-night cycles, so we should plus 1 to get the current day
    new_slots[1].day = TheWorld.state.cycles + 1
    new_slots[1].season = M.SEASONS[TheWorld.state.season]
    new_slots[1].phase = TheWorld:HasTag('cave') and TheWorld.state.cavephase or TheWorld.state.phase
    dbg('updated save info, {new_slots: }')

   
    self.snapshot_info.slots = new_slots
    if not self.snapshot_info.session_id then
        self.snapshot_info.session_id = index.session_id
    end

end

function ShardServerInfoRecord:BuildSnapshotBriefStringByIndex(fmt, index, substitute_table)
    index = index or 1
    return M.BuildSnapshotBriefString(fmt, self.snapshot_info.slots[index], substitute_table)
end
function ShardServerInfoRecord:BuildSnapshotBriefStringByID(fmt, snapshot_id, substitute_table)
    snapshot_id = snapshot_id or TheNet:GetCurrentSnapshot()
    for _, v in ipairs(self.snapshot_info.slots) do
        if v.snapshot_id == snapshot_id then
            return M.BuildSnapshotBriefString(fmt, v, substitute_table)
        end
    end
    return M.BuildSnapshotBriefString(fmt, {}, substitute_table) -- this function can correctly handle empty table arguments
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