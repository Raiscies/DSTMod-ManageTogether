
GLOBAL.manage_together = {}
local M = GLOBAL.manage_together

local lshift, bitor, bitand = GLOBAL.bit.lshift, GLOBAL.bit.bor, GLOBAL.bit.band
local UserCommands = require("usercommands")
local VoteUtil = require("voteutil")

-- constants

M.PERMISSION = table.invert({
    'ADMIN',          -- = 1
    'MODERATOR_VOTE', -- = 2
    'MODERATOR',      -- = ...
    'USER',
    'USER_BANNED'
})
-- use this to order the permission level, cuz M.PERMISSION's map relation shouldn't be change
-- currently the order is same as M.PERMISSION, but who knows in the future?
M.PERMISSION_ORDER = table.invert({
    -- the highest level
    M.PERMISSION.ADMIN,             -- = 1
    M.PERMISSION.MODERATOR_VOTE,    -- = 2
    M.PERMISSION.MODERATOR,         -- = ...
    M.PERMISSION.USER, 
    M.PERMISSION.USER_BANNED

    -- the lowest level
})

M.PERMISSION_VOTE_POSTFIX = '_VOTE'
function M.LevelHigherThan(a_lvl, b_lvl)
    -- a higher then b if:
    -- order(a_lvl) < order(b_lvl)                   (this is reversed)

    return M.PERMISSION_ORDER[a_lvl] < M.PERMISSION_ORDER[b_lvl]
end
function M.LevelHigherOrEqualThan(a_lvl, b_lvl)
    return M.PERMISSION_ORDER[a_lvl] <= M.PERMISSION_ORDER[b_lvl]
end

-- configs
-- this should be sync with modinfo.lua

 M.EXECUTION_CATEGORY = {
    NO = 0, 
    YES = 1, 
    VOTE_ONLY_AND_MAJORITY_YES = 2,   -- for config setting
    VOTE_ONLY_AND_UNANIMOUS_YES = 3,  -- for config setting
    VOTE_ONLY = 4,                    -- defaultly same as *_MAJORITY_YES
}
local moderator_config_map = {
    [M.EXECUTION_CATEGORY.NO]                          = {M.PERMISSION.ADMIN,          VoteUtil.YesNoMajorityVote},
    [M.EXECUTION_CATEGORY.YES]                         = {M.PERMISSION.MODERATOR,      VoteUtil.YesNoMajorityVote},
    [M.EXECUTION_CATEGORY.VOTE_ONLY]                   = {M.PERMISSION.MODERATOR_VOTE, VoteUtil.YesNoMajorityVote},
    [M.EXECUTION_CATEGORY.VOTE_ONLY_AND_MAJORITY_YES]  = {M.PERMISSION.MODERATOR_VOTE, VoteUtil.YesNoMajorityVote}, 
    [M.EXECUTION_CATEGORY.VOTE_ONLY_AND_UNANIMOUS_YES] = {M.PERMISSION.MODERATOR_VOTE, VoteUtil.YesNoUnanimousVote},
}
local function is_config_enabled(config) 
    local conf = GetModConfigData(config)
    return conf == true or conf == M.EXECUTION_CATEGORY.YES 
end

local function InitConfigs()
    
    -- USERs will elevate to MODERATOR if its living age is greater or equals to the bellow age
    -- nil means disable elevation 
    local user_elevate_in_age_config = GetModConfigData('user_elevate_in_age') or -1  
                            
    M.USER_PERMISSION_ELEVATE_IN_AGE = user_elevate_in_age_config ~= -1 and user_elevate_in_age_config or nil
    M.MINIMAP_TIPS_FOR_KILLED_PLAYER           = is_config_enabled('minimap_tips_for_killed_player')
    M.DEBUG                                    = is_config_enabled('debug')
    M.RESERVE_MODERATOR_DATA_WHILE_WORLD_REGEN = is_config_enabled('reserve_moderator_data_while_world_regen')
    M.SILENT_FOR_PERMISSION_DEINED = not M.DEBUG
    M.MODERATOR_FILE_NAME = 'manage_together_moderators'
    M.VOTE_MIN_PASSED_COUNT = GetModConfigData('vote_min_passed_count') or 3
    M.LANGUAGE = GetModConfigData('language')
    if M.LANGUAGE == 'en' then
        modimport('main_strings_en')
    else
        modimport('main_strings')
    end
end
InitConfigs()


local S = GLOBAL.STRINGS.UI.MANAGE_TOGETHER

modimport('utils')

local varg_pairs, dbg, chain_get = M.varg_pairs, M.dbg, M.chain_get


M.ERROR_CODE = table.invert({
    'PERMISSION_DENIED',  -- = 1
    'BAD_COMMAND',        -- = 2
    'BAD_ARGUMENT',       -- = ...
    'BAD_TARGET',
    'DATA_NOT_PRESENT',
    'VOTE_CONFLICT', 
    'COMMAND_NOT_VOTABLE',
    'INTERNAL_ERROR'
})
M.ERROR_CODE.SUCCESS = 0


local function moderator_config(name)
    local conf GetModConfigData('moderator_' .. string.lower(name))
    -- forwarding compatible
    if conf == true then 
        conf = M.EXECUTION_CATEGORY.YES
    elseif conf == false or conf == nil then
        conf = M.EXECUTION_CATEGORY.NO
    end

    return unpack(moderator_config_map[conf] or moderator_config_map[M.EXECUTION_CATEGORY.NO])
end

M.COMMAND_NUM = 0
M.COMMAND = {}
M.COMMAND_ENUM = {}

M.RPC = {}
M.RPC.NAMESPACE = 'ManageTogether'
local function GenerateCommandRPCName(tab)
    for _, v in ipairs(tab) do
        M.RPC[v] = v
    end
end
GenerateCommandRPCName({
    'QUERY_PERMISSION', 
    'SEND_COMMAND', 
    'SEND_VOTE_COMMAND', 
    'SHARD_SEND_COMMAND', 
    'SHARD_RECORD_PLAYER', 
    'SHARD_RECORD_ONLINE_PLAYERS',
    'SHARD_SET_PLAYER_PERMISSION',
    'SHARD_SET_NET_VAR',

    'RESULT_QUERY_PERMISSION', 
    'RESULT_SEND_COMMAND', 
    'RESULT_SEND_VOTE_COMMAND',
    'RESULT_QUERY_HISTORY_PLAYERS', 
    'RESULT_QUERY_HISTORY_PLAYERS_PERMISSION', 
    'RESULT_ROLLBACK_INFO', 
})

M.PERMISSION_MASK = {}

-- this table save some additional parameters for an on-going vote
-- cuz the original vote API is too limited
M.VOTE_ENVIRONMENT = {
    valid = false,
    arguments = nil
}
function M.SetVoteEnv(args_list)
    if not args_list then
        M.ResetVoteEnv()
        return
    end
    M.VOTE_ENVIRONMENT.arguments = args_list
    M.VOTE_ENVIRONMENT.valid = true  
end
function M.GetVoteEnv()
    if M.VOTE_ENVIRONMENT.valid and M.VOTE_ENVIRONMENT.arguments then
        return M.VOTE_ENVIRONMENT.arguments
    end
    return nil
end
function M.ResetVoteEnv()
    M.VOTE_ENVIRONMENT.arguments = nil
    M.VOTE_ENVIRONMENT.valid = false
end

-- simple get functions, only available at server side
local function GetServerInfoComponent()
    if not M.the_component then
        M.the_component = GLOBAL.TheWorld.shard.components.shard_serverinforecord    
    end
    return M.the_component
end
local function GetPlayerRecords()
    local comp = GetServerInfoComponent()
    return comp and comp.player_record or {}
end
local function GetSnapshotInfo()
    local comp = GetServerInfoComponent()
    return comp and comp.snapshot_info or {}
end
local function GetPlayerRecord(userid)
    return GetPlayerRecords()[userid]
end

local function SpawnMiniflareOnPlayerPosition(player)
    if not player then return end 
    local x, y, z = player.Transform:GetWorldPosition()
    local minimap = SpawnPrefab("miniflare_minimap")
    minimap.Transform:SetPosition(x, 0, z)
    minimap:DoTaskInTime(GLOBAL.TUNING.MINIFLARE.TIME * 2, function()
        minimap:Remove()
    end)
    return x, y, z
end

local function KillPlayer(player, announce_string)
    if player.components then
        -- drop everything first, in case some items would not drop
        if player.components.inventory then
            player.components.inventory:DropEverything()
        end

        if player.components.health then
            -- an offical bug cause we can't kill wanda correctly by Kill() function
            -- player.components.health:Kill()
            -- this bug is reported, but before it is fixed by klei:
            player.components.health:SetPercent(0)
            if announce_string then
                M.announce(announce_string)
            end
            if M.MINIMAP_TIPS_FOR_KILLED_PLAYER then
                SpawnMiniflareOnPlayerPosition(player)
            end
        end
        return 3 -- time of delay serializing, just for TemporarilyLoadOfflinePlayer()
    else
        dbg('failed to kill a player: player.components or player.components.health is nil')
        return nil
    end
end

local function AddOfficalVoteCommand(name, voteresultfn)
    
    -- register vote commands
    -- this shouldn't be use directly
    AddUserCommand('manage_together_' .. name,  {
        prettyname = nil, 
        desc = nil,
        permission = COMMAND_PERMISSION.ADMIN, -- command shouldn't be use directly
        confirm = false,
        slash = false,
        usermenu = false,
        servermenu = false,
        params = {'user'},
        vote = true,
        votetimeout = 30,
        voteminstartage = 0,
        voteminpasscount = M.VOTE_MIN_PASSED_COUNT ~= 0 and M.VOTE_MIN_PASSED_COUNT or nil, -- default is 3
        votecountvisible = true,
        voteallownotvoted = true,
        voteoptions = nil, -- { "Yes", "No" }

        votenamefmt = chain_get(S.VOTE, string.upper(name), 'FMT_NAME'),
        votetitlefmt = chain_get(S.VOTE, string.upper(name), 'TITLE'),
        votepassedfmt = nil,
        
        votecanstartfn = VoteUtil.DefaultCanStartVote,
        voteresultfn = voteresultfn or VoteUtil.YesNoMajorityVote,
        serverfn = function(fucking_useless_params, fucking_nil_caller_param)
            M.dbg('passed vote: serverfn')
            GLOBAL.TheWorld:DoTaskInTime(5, function()
                local env = M.GetVoteEnv()
                if not env then
                    M.log('error: failed to execute vote command: command arguments lost')
                    return
                end
                local result = M.ErrorCodeToName(M.ExecuteCommand(M.GetPlayerByUserid(env.starter_userid), M.COMMAND_ENUM[name], true, unpack(env.arg)))
                M.log('executed vote command: cmd = ', name, 'args = ', M.tolinekvstring(env.arg), ', result = ', result)
                M.ResetVoteEnv()
            end)
        end,
    })
end

--[[
    format: 
    M.AddCommand(
        {name = ..., permission = ...}, 
        function() ... end, 
        true/false 
    )
]]
local function DefaultArgsDescription(...) 
    return table.concat({...}, ', ')
end
local function DefaultUserTargettedArgsDescription(userid, ...)
    local user_desc = string.format('%s(%s)', GetPlayerRecord(userid).name, userid)
    return select('#', ...) == 0 and 
        user_desc or 
        user_desc .. ', ' .. DefaultArgsDescription(...)
end
function M.AddCommand(info_table, command_fn, regen_permission_mask)
    if M.COMMAND_NUM >= 64 then
        M.log('error: the number of commands exceeded limitation(64)')
        return
    end
    -- local name, permission, player_targeted = info_table.name, info_table.permission, info_table.player_targeted

    local name, permission, args_description, can_vote, user_targetted = 
        info_table.name, info_table.permission, info_table.args_description, info_table.can_vote, info_table.user_targetted


    local vote_result_fn
    if not permission then
        permission, vote_result_fn = moderator_config(name)
    end

    -- set command enum
    local cmd_enum = lshift(1, M.COMMAND_NUM)
    M.COMMAND_NUM = M.COMMAND_NUM + 1
    M.COMMAND_ENUM[name] = cmd_enum
    -- set command 
    M.COMMAND[cmd_enum] = {
        permission = permission, 
        args_description = args_description or (user_targetted and DefaultUserTargettedArgsDescription or DefaultArgsDescription),
        can_vote = can_vote or false, 
        user_targetted = user_targetted or false,
        fn = command_fn or info_table.fn

    }

    if can_vote then
        AddOfficalVoteCommand(name, vote_result_fn)
    end

    if regen_permission_mask == true then
        M.GeneratePermissionBitMasks()
    end
end


--[[
    format: 
    M.AddCommands(
        {
            name = ..., 
            permission = ..., 
            fn = function() ... end
        }, 
        {
            ...
        },
        ...
    )
]]
function M.AddCommands(...)
    for _, v in varg_pairs(...) do
        M.AddCommand(
            v,    -- info_table (actually .fn is redundent, but never mind it)
            v.fn, -- command_fn
            false
        )
    end
    
    M.GeneratePermissionBitMasks()
end

-- init M.PERMISSION_MASK
function M.GeneratePermissionBitMasks()
    -- initiallize
    for perm_name, perm_lvl in pairs(M.PERMISSION) do
        M.PERMISSION_MASK[perm_lvl] = 0
    end
    M.PERMISSION_MASK.VOTE = 0
    for cmd_name, cmd_enum in pairs(M.COMMAND_ENUM) do

        for perm_name, perm_lvl in pairs(M.PERMISSION) do
            if M.LevelHigherOrEqualThan(perm_lvl, M.COMMAND[cmd_enum].permission) then
                
                if not M.IsVotePermissionLevel(perm_name) or M.COMMAND[cmd_enum].can_vote then
                    -- 1. permission level is not a vote permission level
                    -- 2. permission level is a vote permission level and .can_vote is true
                    M.PERMISSION_MASK[perm_lvl] = bitor(M.PERMISSION_MASK[perm_lvl], cmd_enum) 
                   
                    if M.COMMAND[cmd_enum].can_vote then
                        M.PERMISSION_MASK.VOTE = bitor(M.PERMISSION_MASK.VOTE, cmd_enum) 
                    end
                end
            end
        end
    end
end

local function VotePermissionElevate(origin_level)
    -- player's permission level will elevate to its M.PERMISSION_VOTE_POSTFIX('_VOTE') level if exists
    -- this level is slightly higher then the origin level
    for name, level in pairs(M.PERMISSION) do
        if origin_level == level then
            local vote_level = M.PERMISSION[name .. M.PERMISSION_VOTE_POSTFIX]
            return vote_level ~= nil and vote_level or origin_level

        end
    end
    return origin_level
end
local function FiltUnvotableCommands(permission_mask)
    return bitand(permission_mask, M.PERMISSION_MASK.VOTE)
end


function M.ErrorCodeToName(code)
    for name, errc in pairs(M.ERROR_CODE) do
        if errc == code then
            return name
        end
    end
    return ''
end

function M.CommandEnumToName(cmd)
    for name, cmd_enum in pairs(M.COMMAND_ENUM) do
        if cmd_enum == cmd then
            return name
        end
    end
    return ''
end 

function M.CmdEnumToVoteHash(cmd)
    return smallhash('manage_together_' .. M.CommandEnumToName(cmd))
end

function M.IsVotePermissionLevel(lvl)
    if not M.PERMISSION[lvl] then return false end

    if type(lvl) == 'string' then
        return string.match(lvl, M.PERMISSION_VOTE_POSTFIX, #lvl - #M.PERMISSION_VOTE_POSTFIX + 1) ~= nil
    else
        for permission_name, permission_lvl in pairs(M.PERMISSION) do
            if permission_lvl == lvl then
                return string.match(name, M.PERMISSION_VOTE_POSTFIX, #name - #M.PERMISSION_VOTE_POSTFIX + 1) ~= nil
            end
        end
    end 
end

-- type checker

local function IsCommandEnum(cmd)
    return type(cmd) == 'number' and M.COMMAND[cmd] ~= nil
end

local function IsPermissionLevel(level)
    return type(level) == 'number' and table.contains(M.PERMISSION, level)
end

local function IsPermissionMask(mask)
    return type(mask) == 'number' and 0 <= mask and mask <= M.PERMISSION_MASK[M.PERMISSION.ADMIN]
end

local function IsUserid(userid)
    -- TODO: check if the string is actually a vaild user id
    return type(userid) == 'string'
end

local function IsRollbackNumber(num)
    if GLOBAL.TheNet:GetIsServer() then
        local max_roll_count = #GetSnapshotInfo().slots
        return type(num) == 'number' and (num <= max_roll_count or -num < max_roll_count)
    else
        return type(num) == 'number'
    end
end

local function IsErrorCode(error_code)
    if type(error_code) ~= 'number' then return false end
    for _, v in pairs(M.ERROR_CODE) do
        if v == error_code then
            return true
        end
    end
    return false
end

local function IsDay(day)
    return type(day) == 'number' and (day >= -1)
end

local function IsSeason(season)
    return type(season) == 'number' and 1 <= season and season <= 4
end

local function IsSnapshotID(id)
    return type(id) == 'number' and id > 0
end

local function PermissionLevel(userid)
    local record = GetPlayerRecord(userid)
    return record and record.permission_level or M.PERMISSION.USER
end

function M.HasPermission(cmd, permission_mask)
    return bitand(permission_mask, cmd) ~= 0
end

local BroadcastShardCommand

M.AddCommands(
    -- some technical commands
    {
        name = 'QUERY_PERMISSION',
        permission = M.PERMISSION.USER, 
        fn = function(doer, _) 
            local permission_level = PermissionLevel(doer.userid)
            SendModRPCToClient(
                GetClientModRPC(M.RPC.NAMESPACE, M.RPC.RESULT_QUERY_PERMISSION), doer.userid,
                permission_level, 
                M.PERMISSION_MASK[permission_level],                                               -- original permission_level
                FiltUnvotableCommands(M.PERMISSION_MASK[VotePermissionElevate(permission_level)])  -- vote permission_level 
            )
        end
    },
    {
        name = 'QUERY_HISTORY_PLAYERS', 
        permission = M.PERMISSION.MODERATOR, 
        fn = function(doer, query_category)
            -- query_category: nil or 0: query history players and rollback info
            --                        1: query history players only
            --                        2: query rollback info only

            if not query_category then query_category = 0 end
            
            if query_category == 0 or query_category == 1 then

                for userid, record in pairs(GetPlayerRecords()) do 
                    if M.IsPlayerOnline(userid) then
                        -- player is online
                        SendModRPCToClient(
                            GetClientModRPC(M.RPC.NAMESPACE, M.RPC.RESULT_QUERY_HISTORY_PLAYERS_PERMISSION), doer.userid, 
                            userid, record.permission_level
                        )
                    else
                        -- player is offline
                        SendModRPCToClient(
                            GetClientModRPC(M.RPC.NAMESPACE, M.RPC.RESULT_QUERY_HISTORY_PLAYERS), doer.userid, 
                            userid, record.netid, record.name, record.age, record.skin, record.permission_level
                        )
                    end
                end
            end
            if query_category == 0 or query_category == 2 then
                local slots = GetSnapshotInfo().slots
                if not slots then
                    return M.ERROR_CODE.DATA_NOT_PRESENT
                end
                for i, v in ipairs(slots) do
                    -- SendModRPCToClient(
                    --     GetClientModRPC(M.RPC.NAMESPACE, M.RPC.RESULT_ROLLBACK_INFO), doer.userid, 
                    --     i, v.day, v.season
                    -- )
                    SendModRPCToClient(
                        GetClientModRPC(M.RPC.NAMESPACE, M.RPC.RESULT_ROLLBACK_INFO), doer.userid, 
                        i, v.day, v.season, v.snapshot_id -- add a snapshot id, clients can clearly specify the rollback target they want
                    )
                end
            end
        end 
    },
    {
        name = 'REFRESH_RECORDS', 
        permission = M.PERMISSION.ADMIN, 
        fn = function(doer, _)
            local comp = GetServerInfoComponent()
            if comp then
                M.log('refreshing player records')
                comp:RecordOnlinePlayers()
                comp:LoadSaveInfo()
                comp:LoadModeratorFile()
            else
                M.log('world not exists or historyplayerrecord component not exists')
                return M.ERROR_CODE.DATA_NOT_PRESENT
            end
        end
    },
    {
        name = 'KICK',
        -- the 'permission' item is omitted, function will automatically get the permission limitation from mod config
        -- permission = M.PERMISSION.MODERATOR
        user_targetted = true, 
        can_vote = true, 
        fn = function(doer, target_userid)
            -- kick a player
            -- don't need to check target_userid, which has been checked on ExecuteCommand
            local target_record = GetPlayerRecord(target_userid)
            if not target_record or doer.userid == target_userid or not M.IsPlayerOnline(target_userid) then
                return M.ERROR_CODE.BAD_TARGET
            end
            -- elseif not M.LevelHigherThan(GetPlayerRecord(doer.userid).permission_level, target_record.permission_level) then
            --     return M.ERROR_CODE.PERMISSION_DENIED
            -- end 

            GLOBAL.TheNet:Kick(target_userid)
            M.announce_fmt(S.FMT_KICKED_PLAYER, target_record.name, target_userid)
        end
    },
    {
        name = 'KILL', 
        user_targetted = true,
        can_vote = true,
        fn = function(doer, target_userid)
            -- kill a player, and let it drop everything
            local target_record = GetPlayerRecord(target_userid)

            -- check if the target exists
            if not target_record or doer.userid == target_userid then
                return M.ERROR_CODE.BAD_TARGET
            end
            --   elseif not M.LevelHigherThan(GetPlayerRecord(doer.userid).permission_level, target_record.permission_level) then
            --       return M.ERROR_CODE.PERMISSION_DENIED
  
            BroadcastShardCommand(M.COMMAND_ENUM.KILL, target_userid)
        end
    },
    {
        name = 'BAN',
        user_targetted = true, 
        can_vote = true, 
        fn = function(doer, target_userid)
            -- ban a player
            local record = GetPlayerRecord(target_userid)
            if not record or doer.userid == target_userid or record.permission_level == M.PERMISSION.USER_BANNED then
                return M.ERROR_CODE.BAD_TARGET
            end
            -- elseif not M.LevelHigherThan(GetPlayerRecord(doer.userid).permission_level, record.permission_level) then
            --     return M.ERROR_CODE.PERMISSION_DENIED

            GetServerInfoComponent():SetPermission(target_userid, M.PERMISSION.USER_BANNED)
            GLOBAL.TheNet:Ban(target_userid)
            M.announce_fmt(S.FMT_BANNED_PLAYER, record.name, target_userid)
        end
    },
    {
        name = 'KILLBAN', 
        user_targetted = true, 
        can_vote = true, 
        fn = function(doer, target_userid)
            -- kill and ban a player
            local record = GetPlayerRecord(target_userid)

            -- check if the target exists
            if not record or doer.userid == target_userid and record.permission_level == M.PERMISSION.USER_BANNED then
                return M.ERROR_CODE.BAD_TARGET
            end
            -- elseif not M.LevelHigherThan(GetPlayerRecord(doer.userid).permission_level, record.permission_level) then
            --     return M.ERROR_CODE.PERMISSION_DENIED

            GetServerInfoComponent():SetPermission(target_userid, M.PERMISSION.USER_BANNED)
            BroadcastShardCommand(M.COMMAND_ENUM.KILLBAN, target_userid)

        end
    },
    {
        name = 'SAVE', 
        fn = function(doer, _)
            -- save the world
            GLOBAL.TheWorld:PushEvent('ms_save')
            M.announce_fmt(S.FMT_SENDED_SAVE_REQUEST, doer.name)
        end
    },
    {
        -- deprecated
        name = 'ROLLBACK',
        can_vote = true, 
        args_description = function(saving_point_index)
            return GetServerInfoComponent():BuildDaySeasonStringByInfoIndex(saving_point_index < 0 and (-saving_point_index + 1) or saving_point_index)
        end,
        fn = function(doer, saving_point_index)

            -- negative saving_point_index means this request is sended when
            -- a new save has just created

            -- rollback the world
            if not IsRollbackNumber(saving_point_index) then
                return M.ERROR_CODE.BAD_ARGUMENT
            end
            local comp = GetServerInfoComponent
            M.announce_fmt(S.FMT_SENDED_ROLLBACK_REQUEST, 
                doer.name, 
                math.abs(saving_point_index), 
                comp():BuildDaySeasonStringByInfoIndex(saving_point_index < 0 and (-saving_point_index + 1) or saving_point_index)
            )

            if saving_point_index < 0 then
                saving_point_index = -saving_point_index
                -- we expect M.IsNewestRollbackSlotValid is false 
                if M.IsNewestRollbackSlotValid(true) then
                    -- server's and client's data are inconsistent
                    M.announce(S.ERR_DATA_INCONSISTENT)
                    return
                end
            elseif saving_point_index > 0 then 
                -- we expect M.IsNewestRollbackSlotValid is true
                if not M.IsNewestRollbackSlotValid() then
                    M.announce(S.ERR_DATA_INCONSISTENT)
                    return
                end
            end
            -- if M.rollback_request_already_exists then
            if comp:GetIsRollingBack() then
                M.announce(S.ERR_REPEATED_REQUEST)
                return M.ERROR_CODE.REPEATED_REQUEST
            end

            GLOBAL.TheNet:SendWorldRollbackRequestToServer(saving_point_index)
            -- this flag will be automatically reset while world is reloading
            comp:SetIsRollingBack()
        end
    },
    {
        -- a better rollback command, which can let client specify the appointed rollback slot, but not saving point index
        name = 'ROLLBACK_TO', 
        can_vote = true, 
        args_description = function(target_snapshot_id)
            return GetServerInfoComponent():BuildDaySeasonStringBySnapshotID(target_snapshot_id)
        end,
        fn = function(doer, target_snapshot_id)
            local comp = GetServerInfoComponent()
            if not IsSnapshotID(target_snapshot_id) then
                return M.ERROR_CODE.BAD_ARGUMENT
            elseif comp:GetIsRollingBack() then
                M.announce(S.ERR_REPEATED_REQUEST)
                return M.ERROR_CODE.REPEATED_REQUEST
            end

            if M.RollbackBySnapshotID(target_snapshot_id) then
                -- this flag will be automatically reset while world is reloading
                comp:SetIsRollingBack()
                M.announce_fmt(S.FMT_SENDED_ROLLBACK2_REQUEST, 
                    doer.name, 
                    comp:BuildDaySeasonStringBySnapshotID(target_snapshot_id)
                )
                return M.ERROR_CODE.SUCCESS
            else
                return M.ERROR_CODE.BAD_TARGET
            end
        end
    },
    {
        name = 'REGENERATE_WORLD', 
        can_vote = true,
        fn = function(doer, delay_seconds)
            if not delay_seconds or delay_seconds < 0 then
                delay_seconds = 5
            end 
            M.announce(S.FMT_SENDED_REGENERATE_WORLD_REQUEST, doer.name, delay_seconds)
            GLOBAL.TheWorld:DoTaskInTime(delay_seconds, function()
                TheNet:SendWorldResetRequestToServer()
            end)

            
        end
    },
    {
        name = 'ADD_MODERATOR', 
        can_vote = true, 
        user_targetted = true, 
        fn = function(doer, target_userid)
            -- add a player as moderator
            local target_record = GetPlayerRecord(target_userid)
            if target_record.permission_level == M.PERMISSION.MODERATOR then
                -- target is alreay a moderator
                return M.ERROR_CODE.BAD_TARGET
            end
            -- elseif not M.LevelHigherThan(GetPlayerRecord(doer.userid).permission_level, target_record.permission_level) then
            --     return M.ERROR_CODE.PERMISSION_DENIED

            GetServerInfoComponent():SetPermission(target_userid, M.PERMISSION.MODERATOR)

            if M.IsPlayerOnline(target_userid) then
                GLOBAL.TheWorld:DoTaskInTime(1, function()
                    local permission_level = PermissionLevel(target_userid)
                    M.COMMAND.QUERY_PERMISSION.fn(doer, nil)
                end)
            end

        end
    },
    {
        name = 'REMOVE_MODERATOR', 
        can_vote = true,
        user_targetted = true,
        fn = function(doer, target_userid)
            -- remove a moderator 
            local target_record = GetPlayerRecord(target_userid)
            if target_record.permission_level ~= M.PERMISSION.MODERATOR then
                -- target is not a moderator
                return M.ERROR_CODE.BAD_TARGET
            end
            -- elseif not M.LevelHigherThan(GetPlayerRecord(doer.userid).permission_level, target_record.permission_level) then
            --     return M.ERROR_CODE.PERMISSION_DENIED

            GetServerInfoComponent():SetPermission(target_userid, M.PERMISSION.USER)

            if M.IsPlayerOnline(target_userid) then
                GLOBAL.TheWOrld:DoTaskInTime(1, function()
                    local permission_level = PermissionLevel(target_userid)
                    M.COMMAND.QUERY_PERMISSION.fn(doer, nil)
                end)
            end
        end
    }, 
    {
        name = 'SET_PLAYER_JOINABLE', 
        can_vote = true, 
        fn = function(doer, flag)
            -- flag representation:
            -- 2 or true or nil: all of the player is joinable
            -- 1               : only old player(not a new player) is joinable
            -- 0 or false      : does not accept new incoming connections

            if flag == nil or flag == true or flag == 2 then
                TheNet:SetAllowIncomingConnections(true)
                TheNet:SetAllowNewPlayersToConnect(true)
                M.log('set player joinable: all of the player is allowed')
            elseif flag == 1 then
                TheNet:SetAllowIncomingConnections(true)
                TheNet:SetAllowNewPlayersToConnect(false)
                M.log('set player joinable: only old player is allowed')
            elseif flag == 0 or flag == false then
                TheNet:SetAllowIncomingConnections(false)
                M.log('set player joinable: not allow incoming connections')
            else
                dbg('set player joinable: bad flag: ', flag)
            end
        end
    }
)

-- some commands are shard-unawared, we should handle it properly
M.SHARD_COMMAND = {
    [M.COMMAND_ENUM.KILL] = function(sender_shard_id, target_userid)
        local target = GetPlayerRecord(target_userid)
        
        if not target or not target.in_this_shard then return end

        local announce_string = string.format(S.FMT_KILLED_PLAYER, target.name, target_userid)
        if M.IsPlayerOnline(target_userid) then
            for _,v in pairs(GLOBAL.AllPlayers) do
                if v and v.userid == target_userid then
                    KillPlayer(v, announce_string)
                    return
                end
            end
        else
            if not M.TemporarilyLoadOfflinePlayer(target_userid, KillPlayer, announce_string) then
                dbg('error: failed to kill a offline player')
            end
        end
    end,

    [M.COMMAND_ENUM.KILLBAN] = function(sender_shard_id, target_userid)
        local target = GetPlayerRecord(target_userid)
        
        if not target or not target.in_this_shard then return end

        local announce_string = string.format(S.FMT_KILLBANNED_PLAYER, target.name, target_userid)
        if M.IsPlayerOnline(target_userid) then
            for _,v in pairs(GLOBAL.AllPlayers) do
                if v and v.userid == target_userid then
                    KillPlayer(v, announce_string)
                    GLOBAL.TheWorld:DoTaskInTime(3, function() GLOBAL.TheNet:Ban(target_userid) end)
                    return
                end
            end
        else
            GLOBAL.TheNet:Ban(target_userid)
            if not M.TemporarilyLoadOfflinePlayer(target_userid, KillPlayer, announce_string) then
                dbg('error: failed to killban a offline player')
            end
        end
    end,

    -- just for internal use
    -- this is attempted to be called on master shard
    START_VOTE = function(sender_shard_id, cmd, starter_userid, arg)
        if not TheShard:IsMaster() then
            -- this is not as excepted
            dbg('error: M.SHARD_COMMAND.START_VOTE() is called on secondary shard')
            dbg('sender_shard_id: ', sender_shard_id, ', cmd: ', M.CommandEnumToName(cmd), ', starter_userid: ', starter_userid, ', arg, ', arg)
            return
        end
        
        -- this is broken while it's called on server side
        -- GLOBAL.TheNet:StartVote(M.CmdEnumToVoteHash(cmd), M.COMMAND[cmd].user_targetted and arg or nil)
        
        
        -- arg will be target_userid if cmd is user_targetted
        -- the real arg are store to M.VOTE_ENVIRONMENT
        -- this is because the offical function ONLY accepts a target_userid or nil as a arg 
        -- and further more, vote command will be failed to execute if target is offline 
        -- so we just pass a fucking nil to offical function

        -- shardnetworking.lua
        M.SetVoteEnv({
            starter_userid = starter_userid, 
            arg = {arg}, 
        })
        Shard_StartVote(M.CmdEnumToVoteHash(cmd), starter_userid, nil)

        GLOBAL.TheWorld:DoTaskInTime(1, function()
            -- check if the vote is actually began
            local voter_state, is_get_failed = chain_get(GLOBAL.TheWorld, 'net', 'components', 'worldvoter', {'IsVoteActive'})
            if not is_get_failed and voter_state then

                local announce_string = string.format(
                    S.VOTE[M.CommandEnumToName(cmd)].FMT_ANNOUNCE, 
                    M.COMMAND[cmd].args_description(arg)
                )
                M.announce_vote_fmt(S.VOTE.FMT_START, GetPlayerRecord(starter_userid).name or S.UNKNOWN_PLAYER, announce_string)
            else
                -- clear vote env cuz vote is not actually starts
                M.ResetVoteEnv()
                dbg('failed to start a vote.')
            end
                
        end)
        dbg('Intent to Start a Vote, sender_shard_id: ', sender_shard_id, ', cmd: ', M.CommandEnumToName(cmd), ', starter_userid: ', starter_userid, ', arg, ', arg)
    end
}

local function RegisterRPCs()

    -- server rpcs

    -- handle send_command
    AddModRPCHandler(M.RPC.NAMESPACE, M.RPC.SEND_COMMAND, function(player, cmd, arg)
        local result = M.ExecuteCommand(player, cmd, false, arg)
        if result == M.ERROR_CODE.PERMISSION_DENIED and M.SILENT_FOR_PERMISSION_DEINED then
            return
        end

        SendModRPCToClient(
            GetClientModRPC(M.RPC.NAMESPACE, M.RPC.RESULT_SEND_COMMAND), player.userid,
            cmd, result
        )
    end)
    -- handle send_vote_command
    AddModRPCHandler(M.RPC.NAMESPACE, M.RPC.SEND_VOTE_COMMAND, function(player, cmd, arg)
        local result = M.StartCommandVote(player, cmd, arg)
        if result == M.ERROR_CODE.PERMISSION_DENIED and M.SILENT_FOR_PERMISSION_DEINED then
            return
        end

        SendModRPCToClient(
            GetClientModRPC(M.RPC.NAMESPACE, M.RPC.RESULT_SEND_VOTE_COMMAND), player.userid,
            cmd, result
        )
    end)

    -- client rpcs

    AddClientModRPCHandler(M.RPC.NAMESPACE, M.RPC.RESULT_QUERY_PERMISSION, 
    function(permission_level, permission_mask, vote_permission_mask)
        if not (IsPermissionLevel(permission_level) and IsPermissionMask(permission_mask) and IsPermissionMask(vote_permission_mask)) then
            dbg('received from server(query permission): server drunk')
            dbg('permission_level:', permission_level, ', permission_mask: ', permission_mask, ', vote_permission_mask: ', vote_permission_mask)
            return
        end
        dbg('received from server(query permission): permission_level:', permission_level, ', permission_mask: ', permission_mask, ', vote_permission_mask: ', vote_permission_mask)
        
        if M.self_permission_level ~= permission_level or M.self_permission_mask ~= permission_mask then
            M.self_permission_level = permission_level
            M.self_permission_mask = permission_mask
            M.self_vote_permission_mask = vote_permission_mask
            
            -- re-init playerstatusscreen if it is shown
            if GLOBAL.ThePlayer.HUD:IsStatusScreenOpen() then
                GLOBAL.ThePlayer.HUD.playerstatusscreen:DoInit()
            end
        end
    end
    )

    AddClientModRPCHandler(M.RPC.NAMESPACE, M.RPC.RESULT_SEND_COMMAND, 
    function(cmd, result) 
        if IsCommandEnum(cmd) and IsErrorCode(result) then
            dbg('received from server(send command), cmd = ', M.CommandEnumToName(cmd), ', result = ', M.ErrorCodeToName(result))
        else
            dbg('received from server(send command): server drunk')
        end
    end
    )
    AddClientModRPCHandler(M.RPC.NAMESPACE, M.RPC.RESULT_SEND_VOTE_COMMAND, 
    function(cmd, result) 
        if IsCommandEnum(cmd) and IsErrorCode(result) then
            dbg('received from server(send vote command), cmd = ', M.CommandEnumToName(cmd), ', result = ', M.ErrorCodeToName(result))
        else
            dbg('received from server(send vote command): server drunk')
        end
    end
    )
    

    AddClientModRPCHandler(M.RPC.NAMESPACE, M.RPC.RESULT_QUERY_HISTORY_PLAYERS, 
    function(userid, netid, name, age, skin, permission_level)
        if not (
            IsUserid(userid) and 
            (netid == nil or type(netid) == 'string') and
            (name  == nil or type(name ) == 'string') and
            (age   == nil or type(age  ) == 'number') and 
            (skin  == nil or type(skin ) == 'string') and 
            IsPermissionLevel(permission_level)
        ) then
            dbg('received from server(query history players(offline)): server drunk')
            dbg('userid: ', userid, ', netid: ', netid, ', name: ', name, ', age: ', age, ', skin: ', skin, ', permission_level: ', permission_level)
            dbg('type of: userid: ', type(userid), ', netid: ', type(netid), ', name: ', type(name), ', age: ', type(age), ', skin: ', type(skin), ', permission_level: ', type(permission_level))
            return
        end

        -- only offline players are excepted to receive
        M.player_record[userid] = {
            netid = netid,
            name = name or '',
            age = age or -1,
            permission_level = permission_level, 
            skin = skin, 
        }
        dbg('received from server(query history players(offline)): ', M.player_record[userid])

        -- re-init the history player screen
        -- ad-hoc, should simply update the player list
        if GLOBAL.ThePlayer.HUD.historyplayerscreen ~= nil and GLOBAL.ThePlayer.HUD.historyplayerscreen.shown then
            GLOBAL.ThePlayer.HUD.historyplayerscreen:DoInit()
        end
    end
    )
    AddClientModRPCHandler(M.RPC.NAMESPACE, M.RPC.RESULT_QUERY_HISTORY_PLAYERS_PERMISSION, 
    function(userid, permission_level)
        if not (IsUserid(userid) and IsPermissionLevel(permission_level)) then
            dbg('received from server(query history players(online)): server drunk')
            dbg('userid: ', userid, ', permission_level: ', permission_level)
            return
        end
        if M.player_record[userid] == nil then
            M.player_record[userid] = {}
        end
        M.player_record[userid].permission_level = permission_level

        dbg('received from server(query history players(online)): userid: ', userid, ', record: ', M.player_record[userid])
        
        if GLOBAL.ThePlayer.HUD.historyplayerscreen ~= nil and GLOBAL.ThePlayer.HUD.historyplayerscreen.shown then
            GLOBAL.ThePlayer.HUD.historyplayerscreen:DoInit()
        end
    end
    )

    AddClientModRPCHandler(M.RPC.NAMESPACE, M.RPC.RESULT_ROLLBACK_INFO, 
    function(index, day, season, snapshot_id)
        if not (IsRollbackNumber(index) and (day == nil or IsDay(day)) and (season == nil or IsSeason(season)) and IsSnapshotID(snapshot_id)) then
            dbg('received from server(rollback info): server drunk')
            dbg('index: ', index, ', day: ', day, ', season: ', season, ', snapshot_id: ', snapshot_id)
            return
        end
        if not index then return 
        elseif index == 1 then
            -- we assume the RPC receiving is same as sending time order
            ClearRollbackInfos()
        end
        M.rollback_info[index] = {
            day = day, 
            season = season, 
            snapshot_id = snapshot_id
        }

        -- re-init the rollback spinner
        if GLOBAL.ThePlayer.HUD.historyplayerscreen ~= nil and GLOBAL.ThePlayer.HUD.historyplayerscreen.shown then
            GLOBAL.ThePlayer.HUD.historyplayerscreen:DoInitRollbackSpinner()
        end
    end
    )

    -- shard rpcs

    AddShardModRPCHandler(M.RPC.NAMESPACE, M.RPC.SHARD_SEND_COMMAND, 
    function(sender_shard_id, cmd, ...)
        dbg('received shard command: ', M.CommandEnumToName(cmd), ', arg = ', ...)
        if M.SHARD_COMMAND[cmd] then
            M.SHARD_COMMAND[cmd](sender_shard_id, ...)
        else
            dbg('shard command not exists')
        end
    end)

end

RegisterRPCs()


if GLOBAL.TheNet and GLOBAL.TheNet:GetIsServer() then
-- Server codes begin ----------------------------------------------------------
-- it is hard to fully clearify which parts are for server and the others are for clients or both
-- so this is just a proximately seperation

local function ForwardToMasterShard(cmd, ...)
    
    if TheShard:IsMaster() then
        if M.SHARD_COMMAND[cmd] then
            M.SHARD_COMMAND[cmd](GLOBAL.SHARDID.MASTER, ...) 
            dbg('ForwardToMasterShard: Here Is Already Master Shard, cmd: ',  M.CommandEnumToName(cmd), ', argcount = ', select('#', ...), ', arg = ', ...)
        else   
            dbg('error at ForwardToMasterShard: SHARD_COMMAND[cmd] is not exists, cmd: ', M.CommandEnumToName(cmd) ', argcount = ', select('#', ...), ', arg = ', ...)
        end
    else
        SendModRPCToShard(
            GetShardModRPC(M.RPC.NAMESPACE, M.RPC.SHARD_SEND_COMMAND), 
            GLOBAL.SHARDID.MASTER, 
            cmd, ...
        )
        dbg('Forwarded Shard Command To Master, cmd: ',  M.CommandEnumToName(cmd), ', argcount = ', select('#', ...), ', arg = ', ...)
    end
end 
-- local, forward declared
BroadcastShardCommand = function(cmd, ...)
    SendModRPCToShard(
        GetShardModRPC(M.RPC.NAMESPACE, M.RPC.SHARD_SEND_COMMAND), 
        nil, 
        cmd, ...
    )
    dbg('Broadcasted Shard Command: ',  M.CommandEnumToName(cmd), ', argcount = ', select('#', ...), ', arg = ', ...)
end

function M.ExecuteCommand(executor, cmd, is_vote, arg)
    local permission_level = PermissionLevel(executor.userid)
    if is_vote then
        permission_level = VotePermissionElevate(permission_level)
    end

    -- check data validity: cmd, arg
    if not IsCommandEnum(cmd) then
        -- bad command type
        return M.ERROR_CODE.BAD_COMMAND
    elseif not M.HasPermission(cmd, M.PERMISSION_MASK[permission_level]) then
        return M.ERROR_CODE.PERMISSION_DENIED
    elseif M.COMMAND[cmd].player_targeted then
        -- arg will be target_userid if command is player targeted
        local target_record = GetPlayerRecord(arg)
        if not target_record then
            return M.ERROR_CODE.BAD_TARGET
        elseif not M.LevelHigherThan(permission_level, target_record.permission_level) then
            -- permission is not allowed if theirs level are the same
            return M.ERROR_CODE.PERMISSION_DENIED
        end
    end
    
    local result = M.COMMAND[cmd].fn(executor, arg)
    M.dbg('received command request from player: ', executor.name, ', cmd = ', M.CommandEnumToName(cmd), ', is_vote = ', (is_vote or false), ', arg = ', arg)
    -- nil(by default) means success
    return result == nil and M.ERROR_CODE.SUCCESS or result
    
end
function M.StartCommandVote(executor, cmd, arg)
    local permission_level = VotePermissionElevate(PermissionLevel(executor.userid))
    if not M.HasPermission(cmd, M.PERMISSION_MASK[permission_level]) then
        return M.ERROR_CODE.PERMISSION_DENIED
    elseif not IsCommandEnum(cmd) then
        return M.ERROR_CODE.BAD_COMMAND
    elseif not M.COMMAND[cmd].can_vote then
        return M.ERROR_CODE.COMMAND_NOT_VOTABLE
    end
    
    local voter_state, is_get_failed = chain_get(GLOBAL.TheWorld, 'net', 'components', 'worldvoter', {'IsVoteActive'})
    if is_get_failed then
        return M.ERROR_CODE.INTERNAL_ERROR
    elseif voter_state == true then
        return M.ERROR_CODE.VOTE_CONFLICT
    end

    ForwardToMasterShard('START_VOTE', cmd, executor.userid, arg)

    return M.ERROR_CODE.SUCCESS
end


AddPrefabPostInit('shard_network', function(inst)
    if not inst.components.shard_serverinforecord then
        inst:AddComponent('shard_serverinforecord')
    end
end)


-- Server codes end ------------------------------------------------------------
end

if GLOBAL.TheNet and GLOBAL.TheNet:GetIsClient() then
-- Client codes begin ----------------------------------------------------------

M.ATLAS = 'images/manage_together_integrated.xml'
Assets = {
    Asset('ATLAS', M.ATLAS), 
    Asset('IMAGE', 'images/manage_together_integrated.tex')
}


-- this table records all of the players that had joined the server from it starts 
M.player_record = {}
M.rollback_info = {}
M.self_permission_level = nil
M.self_permission_mask = 0
M.self_vote_permission_mask = 0
M.has_queried = false

function ClearRollbackInfos()
    M.rollback_info = {}
end

function QueryPermission()
    SendModRPCToServer(GetModRPC(M.RPC.NAMESPACE, M.RPC.SEND_COMMAND), M.COMMAND_ENUM.QUERY_PERMISSION, nil)
end

function RequestToExecuteCommand(cmd, arg)
    SendModRPCToServer(GetModRPC(M.RPC.NAMESPACE, M.RPC.SEND_COMMAND), cmd, arg)
end

function RequestToExecuteVoteCommand(cmd, arg)
    SendModRPCToServer(GetModRPC(M.RPC.NAMESPACE, M.RPC.SEND_VOTE_COMMAND), cmd, arg)
end

-- just for quick typing in console
function FromCmdName(name)
    return M.COMMAND_ENUM[string.upper(name)]
end

function HasPermission(cmd)
    return M.HasPermission(cmd, M.self_permission_mask)
end
function HasVotePermission(cmd)
    return M.HasPermission(cmd, M.self_vote_permission_mask)
end

function CommandApplyableForPlayerTarget(cmd, target_userid)
    if not chain_get(M.COMMAND[cmd], 'user_targetted') then
        return M.EXECUTION_CATEGORY.NO
    end
    
    local target_lvl = chain_get(M.player_record[target_userid], 'permission_level')
    if not target_lvl then return M.EXECUTION_CATEGORY.NO end
    if HasPermission(cmd) and M.LevelHigherThan(M.self_permission_level, target_lvl) then
        return M.EXECUTION_CATEGORY.YES
    elseif HasVotePermission(cmd) and M.LevelHigherThan(VotePermissionElevate(M.self_permission_level), target_lvl) then
        return M.EXECUTION_CATEGORY.VOTE_ONLY
    else
        return M.EXECUTION_CATEGORY.NO
    end
        
end

modimport('historyplayerscreen')

-- Client codes end ------------------------------------------------------------
end

