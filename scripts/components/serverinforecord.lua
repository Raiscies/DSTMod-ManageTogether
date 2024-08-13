

local M = manage_together

M.usingnamespace(M)

local ServerInfoRecord = Class(function(self, inst)
    dbg('ServerInfoRecord: init')
    self.inst = inst
    self.world = TheWorld

    if TheWorld.ismastersim then
        inst:DoTaskInTime(0, function()
             
            -- on server side
            self.shard_serverinforecord = TheWorld.shard.components.shard_serverinforecord
            
            -- alias
            self.player_record = self.shard_serverinforecord.player_record
            self.snapshot_info = self.shard_serverinforecord.snapshot_info
        
        end)
    else
        -- on client side  
        self.player_record = {}
        self.snapshot_info = {}

        self.has_more_player_records = true
    end
    
    self:RegisterRPCs()
end)

function ServerInfoRecord:RegisterRPCs()
    dbg('ServerInfoRecord:RegisterRPCs()')

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
        dbg('player record sync completed, has_more = ', has_more)
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