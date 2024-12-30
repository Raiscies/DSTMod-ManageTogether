

local M = manage_together

local dbg = M.dbg
local bool = M.bool
local AddServerRPC = M.AddServerRPC
local AddClientRPC = M.AddClientRPC
local AddShardRPC = M.AddShardRPC
local SendRPCToServer = M.SendRPCToServer
local SendRPCToClient = M.SendRPCToClient
local SendRPCToShard = M.SendRPCToShard

local ServerInfoRecord = Class(function(self, inst)
    dbg('ServerInfoRecord: init: ', inst)
    self.inst = inst -- TheWorld.net, or say xx_network
    -- self.world = TheWorld

    if TheWorld.ismastersim then
        TheWorld:DoTaskInTime(0, function()
             
            -- on server side
            self.shard_recorder = TheWorld.shard.components.shard_serverinforecord

            -- alias
            self.player_record = self.shard_recorder.player_record
            self.snapshot_info = self.shard_recorder.snapshot_info

        end)
    else
        -- on client side  
        self.player_record = {}
        self.snapshot_info = {}

        self.has_more_player_records = true
    end
    
    self:RegisterRPCs()
    self:InitNetVars()
end)

function ServerInfoRecord:RegisterRPCs()
    

    AddClientRPC('OFFLINE_PLAYER_RECORD_SYNC', function(userid, netid, name, age, skin, permission_level)
        self.player_record[userid] = {
            netid = netid, 
            name = name, 
            age = age, 
            permission_level = permission_level, 
            skin = skin
        }
        dbg('received offline player record sync from server: ', self.player_record[userid])

        self.inst:PushEvent('player_record_updated', userid)
    end, true) -- no response
    
    AddClientRPC('ONLINE_PLAYER_RECORD_SYNC', function(userid, permission_level)
        if not self.player_record[userid] then
            self.player_record[userid] = {}
        end
        self.player_record[userid].permission_level = permission_level
        
        dbg('received online player record sync from server: ', self.player_record[userid])

        self.inst:PushEvent('player_record_updated', userid)
    end, true)

    AddClientRPC('PLAYER_RECORD_SYNC_COMPLETED', function(has_more)
        self.has_more_player_records = has_more
        self.inst:PushEvent('player_record_sync_completed', has_more)
        
    end, true)

    AddClientRPC('SNAPSHOT_INFO_SYNC', function(index, snapshot_id, day, season, phase)
        if index == 1 then
            -- clear all of the old snapshot info
            self.snapshot_info = {}
        end

        self.snapshot_info[index] = {
            snapshot_id = snapshot_id, 
            day = day, 
            season = season, 
            phase = phase
        }

        dbg('received snapshot info sync from server: ', self.snapshot_info[index])

        self.inst:PushEvent('snapshot_info_updated', index)
    end, true)

end


function ServerInfoRecord:InitNetVars()

    

    -- all of these netvars are in public area - all of the clients are available to accept it
    self.netvar = {
        allow_new_players_to_connect = net_bool(self.inst.GUID, 'manage_together.allow_new_players_to_connect', 'new_player_joinability_changed'),
        auto_new_player_wall_enabled = net_bool(self.inst.GUID, 'manage_together.auto_new_player_wall_enabled', 'auto_new_player_wall_changed'),
        auto_new_player_wall_min_level = net_byte(self.inst.GUID, 'manage_together.auto_new_player_wall_min_level', 'auto_new_player_wall_changed')
    }

    local force_update = function(var, value)
        if value == nil then
            value = false
        end
        self.netvar[var]:set_local(value)
        self.netvar[var]:set(value)
    end

    if TheWorld.ismastersim then

        -- listen for events from shard_network - shard_serverinforecord forwarded by TheWorld, and then forward to every clients
        self.inst:ListenForEvent('ms_new_player_joinability_changed', function(inst, connectable)
            -- local connectable = self.shard_recorder:GetAllowNewPlayersToConnect()
            dbg('event ms_new_player_joinability_changed: ', connectable)
            
            force_update('allow_new_players_to_connect', connectable)
            -- self.netvar.allow_new_players_to_connect:set(connectable)
        end, TheWorld) 
        
        self.inst:ListenForEvent('ms_auto_new_player_wall_changed', function(inst, data)
            -- local enabled, min_level = self.shard_recorder:GetAutoNewPlayerWall()
            local enabled, min_level = data.enabled, data.level
            
            dbg('event ms_auto_new_player_wall_changed: enabled =', enabled, ', min_level =', min_level)
            force_update('auto_new_player_wall_enabled', enabled)
            force_update('auto_new_player_wall_min_level', min_level)
        end, TheWorld)

    else

        -- on client side
        self.inst:ListenForEvent('new_player_joinability_changed', function()
            local connectable = self:GetAllowNewPlayersToConnect()
            dbg('client event new_player_joinability_changed: ', connectable)
        end)

        self.inst:ListenForEvent('auto_new_player_wall_changed', function()
            local enabled, min_level = self:GetAutoNewPlayerWall()
            dbg('client event auto_new_player_wall_changed: enabled =', enabled, ', min_level =', min_level)
        end)
    end
end

function ServerInfoRecord:GetAllowNewPlayersToConnect()
    return bool(self.netvar.allow_new_players_to_connect:value())
end

function ServerInfoRecord:GetAutoNewPlayerWall()
    return bool(self.netvar.auto_new_player_wall_enabled:value()), self.netvar.auto_new_player_wall_min_level:value()
end

if not TheWorld.ismastersim then
    -- client side
    
function ServerInfoRecord:RecordClientData(userid)
    local client = TheNet:GetClientTableForUser(userid)
    local record = self.player_record[userid]
    if not client then
        record.online = false    
    else
        -- player is online
        local permission_level = record.permission_level
        self.player_record[userid] = {
            online = true, 
            name = client.name,
            netid = client.netid, 
            skin = client.base_skin, 
            age = client.playerage, 
            permission_level = permission_level,

            client = client
        }
    end
end

function ServerInfoRecord:HasMorePlayerRecords()
    return self.has_more_player_records
end

end


return ServerInfoRecord