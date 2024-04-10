-- deprecated, just for backward compatibling
-- will be remove in next update

local M = manage_together

local ServerInfoRecord = Class(
    function(self, inst)
        self.inst = inst

        self.player_record = {}
    end
)

function ServerInfoRecord:OnSave()
    if self.data_migrated then
        return {data_migrated = self.data_migrated}
    end

    return {player_record = self.player_record}
end

-- helper function for migrating data
local function set_if_nil(src, dist, name_list)
    for _, name in ipairs(name_list) do
        if dist[name] == nil then
            dist[name] = src[name]
        end
    end
end 
function ServerInfoRecord:OnLoad(data)
    if not data or data.data_migrated then 
        self.data_migrated = true
        return 
    end
    
    M.log('ServerInfoRecord: Migrating Data')
    if data.player_record then 
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
            M.dbg('got record data: userid = ', userid, ', record = ', player)
        end
    end
    self.inst:DoTaskInTime(1, function()
        local new_component, get_failed = M.chain_get(TheWorld, 'shard', 'components', 'shard_serverinforecord')
        M.dbg('ServerInfoRecord: try to migrate, new_component is nil?', new_component == nil, ', get_failed = ', get_failed)
        if get_failed then return end

        for userid, record in pairs(self.player_record) do
            M.dbg('migrating: userid = ', userid, ', record = ', record)
            if not new_component.player_record[userid] then
                new_component.player_record[userid] = record
            else
                set_if_nil(record, new_component.player_record[userid], {
                    'netid', 'name', 'age', 'skin', 'permission_level', 'in_this_shard', 'no_elevate_in_age'
                })
            end
        end
        self.data_migrated = true
    end)
end

return ServerInfoRecord