

local M = manage_together

local dbg, chain_get = M.dbg, M.chain_get

local ServerInfoRecord = Class(function(self, inst)
    -- inst is TheWorld.net, 'world_network'
    self.inst = inst
    self.world = TheWorld

    self.allow_new_players_to_connect = net_bool(inst.GUID, 'serverinforecord.allow_new_players_to_connect', 'new_player_joinability_changed')
    -- self.allow_incoming_conections = net_bool(inst.GUID, 'serverinforecord.allow_incoming_conections', 'player_joinability_changed')

    if TheWorld.ismastersim then
        -- on server side
        self.shard_serverinforecord = TheWorld.shard.components.shard_serverinforecord

        -- alias
        self.player_record = self.shard_serverinforecord.player_record
        self.snapshot_info = self.shard_serverinforecord.snapshot_info

        inst:ListenForEvent('ms_new_player_joinability_changed', function()
            -- master netvar -> secondary netvar -> client netvar
           self.allow_new_players_to_connect:set(
                self.shard_serverinforecord:GetAllowNewPlayersToConnect()
            ) 
        end, self.shard_serverinforecord.inst)

    else
        -- on client side  
        self.player_record = {}
        self.snapshot_info = {}
    end
    
    self:RegisterRPCs()
end)

function ServerInfoRecord:RegisterRPCs()
    AddClientModRPCHandler(M.RPC.NAMESPACE, M.RPC.OFFLINE_PLAYER_RECORD_SYNC, function(userid, netid, name, age, skin, permission_level)
        self.player_record[userid] = {
            netid = netid, 
            name = name, 
            age = age, 
            permission_level = permission_level, 
            skin = skin
        }
        dbg('received offline player record sync from server: ', self.player_record[userid])

        -- self:RecordClientData(userid)

        self.inst:PushEvent('player_record_updated', userid)
    end)
    
    AddClientModRPCHandler(M.RPC.NAMESPACE, M.RPC.ONLINE_PLAYER_RECORD_SYNC, function(userid, permission_level)
        if not self.player_record[userid] then
            self.player_record[userid] = {}
        end
        self.player_record[userid].permission_level = permission_level
        
        dbg('received online player record sync from server: ', self.player_record[userid])

        -- self:RecordClientData(userid)

        self.inst:PushEvent('player_record_updated', userid)
    end)

    AddClientModRPCHandler(M.RPC.NAMESPACE, M.RPC.SNAPSHOT_INFO_SYNC, function(index, snapshot_id, day, season)
        self.snapshot_info[index] = {
            snapshot_id = snapshot_id, 
            day = day, 
            season = season
        }

        dbg('received snapshot info sync from server: ', self.snapshot_info[index])

        self.inst:PushEvent('snapshot_info_updated', index)
    end)

end


function ServerInfoRecord:GetAllowNewPlayersToConnect()
    return self.allow_new_players_to_connect:value()
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

end


return ServerInfoRecord