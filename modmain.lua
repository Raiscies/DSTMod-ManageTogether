
GLOBAL.manage_together = {}
local M = GLOBAL.manage_together

local lshift, rshift, bitor, bitand = GLOBAL.bit.lshift, GLOBAL.bit.rshift, GLOBAL.bit.bor, GLOBAL.bit.band
local UserCommands = require("usercommands")
local VoteUtil = require("voteutil")

local assert, GetTableSize = GLOBAL.assert, GLOBAL.GetTableSize
-- constants

M.PERMISSION = table.invert({
    'ADMIN',          -- = 1
    'MODERATOR_VOTE', -- = 2
    'MODERATOR',      -- = ...
    'USER',
    'USER_BANNED',
    'MINIMUM'
})

assert(GetTableSize(M.PERMISSION) <= 255, 'permission level amount exceeded the limitation(255)')

-- use this to order the permission level, cuz M.PERMISSION's map relation shouldn't be change
-- currently the order is same as M.PERMISSION, but who knows in the future?
M.PERMISSION_ORDER = {
    -- the highest level
    [M.PERMISSION.ADMIN]              = 1,
    [M.PERMISSION.MODERATOR_VOTE]     = 2,
    [M.PERMISSION.MODERATOR]          = 3,
    [M.PERMISSION.USER]               = 4, 
    [M.PERMISSION.USER_BANNED]        = 5,
    
    [M.PERMISSION.MINIMUM]            = 255
    -- the lowest level
}

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
    local auto_new_player_wall_min_level = GetModConfigData('auto_new_player_wall_min_level')
    M.USER_PERMISSION_ELEVATE_IN_AGE = user_elevate_in_age_config ~= -1 and user_elevate_in_age_config or nil
    M.MINIMAP_TIPS_FOR_KILLED_PLAYER           = is_config_enabled('minimap_tips_for_killed_player')
    M.DEBUG                                    = is_config_enabled('debug')
    M.RESERVE_MODERATOR_DATA_WHILE_WORLD_REGEN = is_config_enabled('reserve_moderator_data_while_world_regen')
    M.SILENT_FOR_PERMISSION_DEINED = not M.DEBUG
    M.MODERATOR_FILE_NAME = 'manage_together_moderators'
    M.VOTE_MIN_PASSED_COUNT = GetModConfigData('vote_min_passed_count') or 3


    M.DEFAULT_AUTO_NEW_PLAYER_WALL_ENABLED = is_config_enabled('auto_new_player_wall_enabled')
    if type(auto_new_player_wall_min_level) == 'string' then
        -- config is permission level name
        -- this setting(config) is unable to set on in-game screen yet,
        -- but the command is implemented
        M.DEFAULT_AUTO_NEW_PLAYER_WALL_MIN_LEVEL = M.PERMISSION[string.upper(auto_new_player_wall_min_level)] or M.PERMISSION.MODERATOR
    else
        M.DEFAULT_AUTO_NEW_PLAYER_WALL_MIN_LEVEL = M.PERMISSION.MODERATOR
    end

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

local varg_pairs, dbg, chain_get, select_one, partial, in_range, in_int_range, in_table = 
    M.varg_pairs, M.dbg, M.chain_get, M.select_one, M.partial, M.in_range, M.in_int_range, M.in_table
local one_of, both_of, not_of = M.one_of, M.both_of, M.not_of
local announce, announce_fmt = M.announce, M.announce_fmt
local IsPlayerOnline = M.IsPlayerOnline

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
    local conf = GetModConfigData('moderator_' .. string.lower(name))
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
    -- 'QUERY_PERMISSION', 
    'SEND_COMMAND', 
    'SEND_VOTE_COMMAND', 
    'SHARD_SEND_COMMAND', 
    'SHARD_RECORD_PLAYER', 
    'SHARD_RECORD_ONLINE_PLAYERS',
    'SHARD_SET_PLAYER_PERMISSION',
    'SHARD_SET_NET_VAR',

    -- 'RESULT_QUERY_PERMISSION', 
    'RESULT_SEND_COMMAND', 
    'RESULT_SEND_VOTE_COMMAND',

    'OFFLINE_PLAYER_RECORD_SYNC', 
    'ONLINE_PLAYER_RECORD_SYNC', 
    'PLAYER_RECORD_SYNC_COMPLETED',
    'SNAPSHOT_INFO_SYNC',

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
                announce(announce_string)
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


local function AnnounceItemStat(stat)
    for userid, v in pairs(stat) do
        local name = GetPlayerRecord(userid).name or '???'
        if v.count == 0 then
            announce_fmt(S.FMT_MAKE_ITEM_STAT_DOES_NOT_HAVE_ITEM, 
                name,
                userid, 
                v.has_deeper_container and S.MAKE_ITEM_STAT_HAS_DEEPER_CONTAINER or ''    
            )
        else
            announce_fmt(S.FMT_MAKE_ITEM_STAT_HAS_ITEM, 
                name, 
                userid, 
                v.count, 
                v.has_deeper_container and S.MAKE_ITEM_STAT_HAS_DEEPER_CONTAINER or ''
            )
        end
    end
end

-- for the argument of command MAKE_ITEM_STAT_IN_PLAYER_INVENTORIES 
local ITEM_STAT_CATEGORY = {
    -- userid_or_flag: a target userid or a flag
    -- flag representation:
    -- 0: all of the online players
    -- 1: all of the offline players(recorded offline players)
    -- 2: all of the online & offline(recorded) players

    [0] = S.MAKE_ITEM_STAT_OPTIONS.ALL_ONLINE_PLAYERS, 
    [1] = S.MAKE_ITEM_STAT_OPTIONS.ALL_OFFLINE_PLAYERS,
    [2] = S.MAKE_ITEM_STAT_OPTIONS.ALL_PLAYERS
}

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
                local result = M.ErrorCodeToName(M.ExecuteCommand(M.GetPlayerByUserid(env.starter_userid), M.COMMAND_ENUM[name], true, unpack(env.args)))
                M.log('executed vote command: cmd = ', name, 'args = ', M.tolinekvstring(env.args), ', result = ', result)
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
    assert(M.COMMAND_NUM < 64, 'error: the number of commands exceeded limitation(64)')
    
    -- local name, permission, player_targeted = info_table.name, info_table.permission, info_table.player_targeted

    local name, permission, args_description, checker, can_vote, user_targetted = 
        info_table.name, info_table.permission, info_table.args_description, info_table.checker, info_table.can_vote, info_table.user_targetted


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
        checker = checker,
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
function M.LevelEnumToName(level)
    for name, lvl in pairs(M.PERMISSION) do
        if lvl == level then
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


M.CHECKER_TYPES = {
    bool = GLOBAL.checkbool, 
    number = GLOBAL.checknumber, 
    uint = GLOBAL.checkuint, 
    string = GLOBAL.checkstring,
    optbool = GLOBAL.optbool,
    optnumber = GLOBAL.optnumber, 
    optuint = GLOBAL.optuint, 
    optstring = GLOBAL.optstring,

    
    userid_recorded = function(val) return GetPlayerRecord(val) ~= nil end, 
    -- unfortunately, lua's regex does not support repeat counting syntex like [%w%-_]{8}, 
    -- so we have to write it manually
    userid_like = function(val) return GLOBAL.checkstring(val) and val:match('^KU_[%w%-_][%w%-_][%w%-_][%w%-_][%w%-_][%w%-_][%w%-_][%w%-_]$') ~= nil end, 

    
    snapshot_id_like    = function(val) return GLOBAL.checkuint(val) and val > 0 end,
    snapshot_id_existed = function(val) return GLOBAL.checkuint(val) and GetServerInfoComponent():SnapshotIDExists(val) end,
    
    ['nil'] = function(val) return val == nil end, 
    any = function() return true end,
}
M.CHECKER_TYPES.userid = M.CHECKER_TYPES.userid_like
M.CHECKER_TYPES.none   = M.CHECKER_TYPES['nil']

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
        name = 'QUERY_HISTORY_PLAYERS', 
        permission = M.PERMISSION.MODERATOR, 
        checker = {        'optnumber',             'optuint'}, 
        fn = function(doer, last_query_timestamp, block_index)
            return GetServerInfoComponent():PushPlayerRecordTo(doer.userid, last_query_timestamp, block_index)
        end 
    },
    {
        name = 'QUERY_SNAPSHOT_INFORMATIONS',
        permission = M.PERMISSION.MODERATOR, 
        fn = function(doer)
            return GetServerInfoComponent():PushSnapshotInfoTo(doer.userid)
        end
    },
    {
        name = 'REFRESH_RECORDS', 
        permission = M.PERMISSION.ADMIN, 
        fn = function(doer)
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
        checker = {         function(val) return M.CHECKER_TYPES.userid_recorded(val) and IsPlayerOnline(val) end},
        fn = function(doer, target_userid)
            -- kick a player
            -- don't need to check target_userid, which has been checked on ExecuteCommand
            if doer.userid == target_userid then
                return M.ERROR_CODE.BAD_TARGET
            end

            GLOBAL.TheNet:Kick(target_userid)
            announce_fmt(S.FMT_KICKED_PLAYER, GetPlayerRecord(target_userid).name, target_userid)
        end
    },
    {
        name = 'KILL', 
        user_targetted = true,
        can_vote = true,
        fn = function(doer, target_userid)
            -- kill a player, and let it drop everything

            -- check if the target exists
            if doer.userid == target_userid then
                return M.ERROR_CODE.BAD_TARGET
            end

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
            if doer.userid == target_userid or record.permission_level == M.PERMISSION.USER_BANNED then
                return M.ERROR_CODE.BAD_TARGET
            end

            GetServerInfoComponent():SetPermission(target_userid, M.PERMISSION.USER_BANNED)
            GLOBAL.TheNet:Ban(target_userid)
            announce_fmt(S.FMT_BANNED_PLAYER, record.name, target_userid)
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

            GetServerInfoComponent():SetPermission(target_userid, M.PERMISSION.USER_BANNED)
            BroadcastShardCommand(M.COMMAND_ENUM.KILLBAN, target_userid)

        end
    },
    {
        name = 'SAVE', 
        fn = function(doer)
            -- save the world
            GLOBAL.TheWorld:PushEvent('ms_save')
            announce_fmt(S.FMT_SENDED_SAVE_REQUEST, doer.name)
        end
    },
    {
        -- a better rollback command, which can let client specify the appointed rollback slot, but not saving point index
        name = 'ROLLBACK', 
        can_vote = true, 
        checker = {                'snapshot_id_existed'},
        args_description = function(target_snapshot_id)
            return GetServerInfoComponent():BuildDaySeasonStringBySnapshotID(target_snapshot_id)
        end,
        fn = function(doer, target_snapshot_id)
            local comp = GetServerInfoComponent()
            if not IsSnapshotID(target_snapshot_id) then
                return M.ERROR_CODE.BAD_ARGUMENT
            elseif comp:GetIsRollingBack() then
                announce(S.ERR_REPEATED_REQUEST)
                return M.ERROR_CODE.REPEATED_REQUEST
            end

            if M.RollbackBySnapshotID(target_snapshot_id) then
                -- this flag will be automatically reset while world is reloading
                comp:SetIsRollingBack()
                announce_fmt(S.FMT_SENDED_ROLLBACK2_REQUEST, 
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
        checker = {        'number'},
        fn = function(doer, delay_seconds)
            if delay_seconds < 0 then
                delay_seconds = 5
            end 
            announce(S.FMT_SENDED_REGENERATE_WORLD_REQUEST, doer.name, delay_seconds)
            GLOBAL.TheWorld:DoTaskInTime(delay_seconds, function()
                GLOBAL.TheNet:SendWorldResetRequestToServer()
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

            GetServerInfoComponent():SetPermission(target_userid, M.PERMISSION.MODERATOR)

            -- if IsPlayerOnline(target_userid) then
            --     GLOBAL.TheWorld:DoTaskInTime(1, function()
            --         local permission_level = PermissionLevel(target_userid)
            --         M.COMMAND[M.COMMAND_ENUM.QUERY_PERMISSION].fn(doer, nil)
            --     end)
            -- end

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

            GetServerInfoComponent():SetPermission(target_userid, M.PERMISSION.USER)

            -- if M.IsPlayerOnline(target_userid) then
            --     GLOBAL.TheWorld:DoTaskInTime(1, function()
            --         local permission_level = PermissionLevel(target_userid)
            --         M.COMMAND[M.COMMAND_ENUM.QUERY_PERMISSION].fn(doer, nil)
            --     end)
            -- end
        end
    }, 
    {
        name = 'SET_NEW_PLAYER_JOINABILITY', 
        can_vote = true, 
        checker = {                'bool'},
        args_description = function(allowed) return allowed and S.ALLOW_NEW_PLAYER_JOIN or S.NOT_ALLOW_NEW_PLAYER_JOIN end,
        fn = function(doer, allowed)

            dbg('type of allowed: ', type(allowed), 'value: ', allowed)
            if allowed ~= nil and type(allowed) ~= 'boolean' then return M.ERROR_CODE.BAD_ARGUMENT end
            allowed = not not allowed
            GetServerInfoComponent():SetAllowNewPlayersToConnect(allowed)
            M.announce_fmt(S.FMT_SET_NEW_PLAYER_JOINABILITY[allowed and 'ALLOW' or 'NOT_ALLOW'], doer.name)
        end
    },
    {
        name = 'SET_AUTO_NEW_PLAYER_WALL',
        can_vote = true, 
        checker = {         'bool',  partial(in_table, M.PERMISSION_ORDER)}, 
        fn = function(doer, enabled, min_online_player_level)

            -- if not M.PERMISSION_ORDER[min_online_player_level] then
            --     return M.ERROR_CODE.BAD_ARGUMENT
            -- end

            -- only admin can set min_online_player_level
            -- moderator's argument of this will be ignore

            if PermissionLevel(doer.userid) ~= M.PERMISSION.ADMIN then
                GetServerInfoComponent():SetAutoNewPlayerWall(enabled, nil) -- pass nil to ignore it
                dbg('a non-admin player executed SET_AUTO_NEW_PLAYER_WALL command, min_online_player_level argument is ignored')
            else
                GetServerInfoComponent():SetAutoNewPlayerWall(enabled, min_online_player_level)
            end
        end
    }, 
    {
        name = 'MAKE_ITEM_STAT_IN_PLAYER_INVENTORIES', 
        can_vote = true, 
        checker = { partial(one_of, M.CHECKER_TYPES.userid_recorded, partial(in_table, ITEM_STAT_CATEGORY)), 'string'},
        args_description = function(userid_or_flag, item_prefab)
            return 
                type(userid_or_flag) == 'number' and ITEM_STAT_CATEGORY[userid_or_flag] or GetPlayerRecord(userid_or_flag).name,  
                (STRINGS.NAMES[item_prefab:upper()] or STRINGS.NAMES.UNKNOWN), 
                item_prefab
        end,
        fn = function(doer, userid_or_flag, item)
            -- userid_or_flag: a target userid or a flag
            -- flag representation:
            -- 0: all of the online players
            -- 1: all of the offline players(recorded offline players)
            -- 2: all of the online & offline(recorded) players

            -- local target_players_string = {
            --     [0] = S.MAKE_ITEM_STAT_OPTIONS.ALL_ONLINE_PLAYERS, 
            --     [1] = S.MAKE_ITEM_STAT_OPTIONS.ALL_OFFLINE_PLAYERS,
            --     [2] = S.MAKE_ITEM_STAT_OPTIONS.ALL_PLAYERS
            -- }

            -- if not type(item) == 'string' or
            --     not (IsUserid(userid_or_flag) or type(userid_or_flag) == 'number' and ITEM_STAT_CATEGORY[userid_or_flag])
            -- then
            --     return M.ERROR_CODE.BAD_ARGUMENT
            -- end
            -- do announce
            local item_name = GLOBAL.STRINGS.NAMES[string.upper(item)] or GLOBAL.STRINGS.NAMES.UNKNOWN
            if type(userid_or_flag) == 'string' then
                local record = GetPlayerRecord(userid_or_flag)
                if not record then return M.ERROR_CODE.BAD_TARGET end
                
                announce_fmt(S.FMT_MAKE_ITEM_STAT_HEAD, doer.name)
                announce_fmt(S.FMT_MAKE_ITEM_STAT_HEAD2, string.format('%s(%s)', record.name, userid_or_flag), item_name, item)
            else
                announce_fmt(S.FMT_MAKE_ITEM_STAT_HEAD, doer.name)
                announce_fmt(S.FMT_MAKE_ITEM_STAT_HEAD2, ITEM_STAT_CATEGORY[userid_or_flag], item_name, item)
            end
            BroadcastShardCommand(M.COMMAND_ENUM.MAKE_ITEM_STAT_IN_PLAYER_INVENTORIES, userid_or_flag, item)
        end
    }
)

-- some commands are shard-unawared, we should handle it properly
M.SHARD_COMMAND = {
    [M.COMMAND_ENUM.KILL] = function(sender_shard_id, target_userid)
        local target = GetPlayerRecord(target_userid)
        
        if not target or not target.in_this_shard then return end

        local announce_string = string.format(S.FMT_KILLED_PLAYER, target.name, target_userid)
        if IsPlayerOnline(target_userid) then
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
        if IsPlayerOnline(target_userid) then
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
    [M.COMMAND_ENUM.MAKE_ITEM_STAT_IN_PLAYER_INVENTORIES] = function(sender_shard_id, userid_or_flag, item)
        
        if IsUserid(userid_or_flag) then
            local record = GetPlayerRecord(userid_or_flag)
            if not record or not record.in_this_shard then return end
            AnnounceItemStat(M.MakePlayerInventoriesItemStat(userid_or_flag, item))
            return
        end

        -- userid_or_flag is a flag

        if userid_or_flag == 0 then
            -- all of the online players
            -- iterate AllPlayers list
            AnnounceItemStat(M.MakeOnlinePlayerInventoriesItemStat(item))
        
        elseif userid_or_flag == 1 then
            -- all of the offline player
            local userid_list = {}
            for userid, record in pairs(GetPlayerRecords()) do
                if record.in_this_shard and IsPlayerOnline(userid) then table.insert(userid_list, userid) end
            end
            AnnounceItemStat(M.MakePlayerInventoriesItemStat(userid_list, item))
        
        elseif userid_or_flag == 2 then
            -- all of the recorded player
            local userid_list  = {}
            for userid, record in pairs(GetPlayerRecords()) do
                if record.in_this_shard then table.insert(userid_list, userid) end
            end
            AnnounceItemStat(M.MakePlayerInventoriesItemStat(userid_list, item))
        
        end
    end,

    -- just for internal use
    -- this is attempted to be called on master shard
    START_VOTE = function(sender_shard_id, cmd, starter_userid, ...)
        if not TheShard:IsMaster() then
            -- this is not as excepted
            dbg('error: M.SHARD_COMMAND.START_VOTE() is called on secondary shard')
            dbg('sender_shard_id: ', sender_shard_id, ', cmd: ', M.CommandEnumToName(cmd), ', starter_userid: ', starter_userid, ', arg, ', ...)
            return
        end
        
        -- this is broken while it's called on server side
        -- GLOBAL.TheNet:StartVote(M.CmdEnumToVoteHash(cmd), M.COMMAND[cmd].user_targetted and arg or nil)
        
        
        -- first arg will be target_userid if cmd is user_targetted
        -- the real arg are store to M.VOTE_ENVIRONMENT
        -- this is because the offical function ONLY accepts a target_userid or nil as a arg 
        -- and further more, vote command will be failed to execute if target is offline 
        -- so we just pass a fucking nil to offical function

        -- shardnetworking.lua
        local args = {...}

        M.SetVoteEnv({
            starter_userid = starter_userid, 
            args = args, 
        })
        Shard_StartVote(M.CmdEnumToVoteHash(cmd), starter_userid, nil)

        GLOBAL.TheWorld:DoTaskInTime(1, function()
            -- check if the vote is actually began
            local voter_state, is_get_failed = chain_get(GLOBAL.TheWorld, 'net', 'components', 'worldvoter', {'IsVoteActive'})
            if not is_get_failed and voter_state then

                local announce_string = string.format(
                    S.VOTE[M.CommandEnumToName(cmd)].FMT_ANNOUNCE, 
                    M.COMMAND[cmd].args_description(unpack(args))
                )
                M.announce_vote_fmt(S.VOTE.FMT_START, GetPlayerRecord(starter_userid).name or S.UNKNOWN_PLAYER, announce_string)
            else
                -- clear vote env cuz vote is not actually starts
                M.ResetVoteEnv()
                M.announce_vote_fmt(S.VOTE.FAILED_TO_START)
                dbg('failed to start a vote.')
            end
                
        end)
        dbg('Intent to Start a Vote, sender_shard_id: ', sender_shard_id, ', cmd: ', M.CommandEnumToName(cmd), ', starter_userid: ', starter_userid, ', arg, ', ...)
    end
}

local function RegisterRPCs()

    -- server rpcs

    -- handle send_command
    AddModRPCHandler(M.RPC.NAMESPACE, M.RPC.SEND_COMMAND, function(player, cmd, ...)
        local result = M.ExecuteCommand(player, cmd, false, ...)
        if (result == M.ERROR_CODE.PERMISSION_DENIED or result == M.ERROR_CODE.BAD_COMMAND) and M.SILENT_FOR_PERMISSION_DEINED then
            return
        end

        SendModRPCToClient(
            GetClientModRPC(M.RPC.NAMESPACE, M.RPC.RESULT_SEND_COMMAND), player.userid,
            cmd, result
        )
    end)
    -- handle send_vote_command
    AddModRPCHandler(M.RPC.NAMESPACE, M.RPC.SEND_VOTE_COMMAND, function(player, cmd, ...)
        local result = M.StartCommandVote(player, cmd, ...)
        if (result == M.ERROR_CODE.PERMISSION_DENIED or result == M.ERROR_CODE.BAD_COMMAND) and M.SILENT_FOR_PERMISSION_DEINED then
            return
        end

        SendModRPCToClient(
            GetClientModRPC(M.RPC.NAMESPACE, M.RPC.RESULT_SEND_VOTE_COMMAND), player.userid,
            cmd, result
        )
    end)

    -- client rpcs

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

if GLOBAL.TheNet:GetIsServer() then
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


function M.CheckArgs(checkers, ...)
    local checkertype = type(checkers)
    local checkertypes_category = M.CHECKER_TYPES
    if checkertype == 'table' then
        for i, v in varg_pairs(...) do
            local the_checker = checkers[i]
            -- checker[i] is nil means don't check the type
            if the_checker then
                if type(the_checker) == 'function' and not the_checker(v) then
                    -- bad argument 
                    return false
                elseif type(the_checker) == 'string' then
                    local the_cheker_fn = checkertypes_category[the_checker]
                    -- bad argument 
                    if the_cheker_fn and not the_cheker_fn(v) then
                        return false
                    end
                end 
            end
        end
        return true
    elseif checkertype == 'function' then
        return checkers(...)
    end
    dbg('in M.CheckArgs: bad checker type')
    return false
end

function M.ExecuteCommand(executor, cmd, is_vote, ...)
    local permission_level = PermissionLevel(executor.userid)
    if is_vote then
        permission_level = VotePermissionElevate(permission_level)
    end

    -- check data validity: cmd, args
    if not IsCommandEnum(cmd) then
        -- bad command type
        return M.ERROR_CODE.BAD_COMMAND
    elseif not M.HasPermission(cmd, M.PERMISSION_MASK[permission_level]) then
        return M.ERROR_CODE.PERMISSION_DENIED
    elseif M.COMMAND[cmd].player_targeted then
        -- the first argument will be target_userid if command is player targeted
        local target_record = GetPlayerRecord(select_one(1, ...))
        if not target_record then
            return M.ERROR_CODE.BAD_TARGET
        elseif not M.LevelHigherThan(permission_level, target_record.permission_level) then
            -- permission is not allowed if theirs level are the same
            return M.ERROR_CODE.PERMISSION_DENIED
        end
    end

    local checker = M.COMMAND[cmd].checker
    if checker and not M.CheckArgs(checker, ...) then
        return M.ERROR_CODE.BAD_ARGUMENT
    end
    
    local result = M.COMMAND[cmd].fn(executor, ...)
    M.dbg('received command request from player: ', executor.name, ', cmd = ', M.CommandEnumToName(cmd), ', is_vote = ', (is_vote or false), ', arg = ', ...)
    -- nil(by default) means success
    return result == nil and M.ERROR_CODE.SUCCESS or result
    
end
function M.StartCommandVote(executor, cmd, ...)
    local permission_level = VotePermissionElevate(PermissionLevel(executor.userid))
    if not IsCommandEnum(cmd) then
        return M.ERROR_CODE.BAD_COMMAND
    elseif not M.HasPermission(cmd, M.PERMISSION_MASK[permission_level]) then
        return M.ERROR_CODE.PERMISSION_DENIED
    elseif not M.COMMAND[cmd].can_vote then
        return M.ERROR_CODE.COMMAND_NOT_VOTABLE
    elseif M.COMMAND[cmd].player_targeted then
        -- the first argument will be target_userid if command is player targeted
        local target_record = GetPlayerRecord(select_one(1, ...))
        if not target_record then
            return M.ERROR_CODE.BAD_TARGET
        elseif not M.LevelHigherThan(permission_level, target_record.permission_level) then
            -- permission is not allowed if theirs level are the same
            return M.ERROR_CODE.PERMISSION_DENIED
        end
    end
    
    local checker = M.COMMAND[cmd].checker
    if checker and not M.CheckArgs(checker, ...) then
        return M.ERROR_CODE.BAD_ARGUMENT
    end
    
    local voter_state, is_get_failed = chain_get(GLOBAL.TheWorld, 'net', 'components', 'worldvoter', {'IsVoteActive'})
    if is_get_failed then
        return M.ERROR_CODE.INTERNAL_ERROR
    elseif voter_state == true then
        return M.ERROR_CODE.VOTE_CONFLICT
    end

    ForwardToMasterShard('START_VOTE', cmd, executor.userid, ...)

    return M.ERROR_CODE.SUCCESS
end


AddPrefabPostInit('shard_network', function(inst)
    if not inst.components.shard_serverinforecord then
        inst:AddComponent('shard_serverinforecord')
    end
end)

-- master only
if TheShard:IsMaster() then

-- listen for newplayerwall state change
AddPrefabPostInit('world', function(inst)
    inst:ListenForEvent('master_newplayerwallupdate', function(src, data)
        
        -- redirect MINIMUM level to USER
        local required_min_level = data.required_min_level == M.PERMISSION.MINIMUM and M.PERMISSION.USER or data.required_min_level
        if data.old_state == data.new_state then return end
        if data.new_state then
            -- allow new players to join
            M.announce(S.AUTO_NEW_PLAYER_WALL_STATE_ALLOW)
        else
            -- not allow new players to join
            M.announce_fmt(
                S.FMT_AUTO_NEW_PLAYER_WALL_STATE_NOT_ALLOW, 
                S.LEVEL_PRETTY_NAME[M.LevelEnumToName(required_min_level)]
            )
        end
    end)
end)

end


-- Server codes end ------------------------------------------------------------
end


if GLOBAL.TheNet:GetIsClient() then
-- Client codes begin ----------------------------------------------------------

M.ATLAS = 'images/manage_together_integrated.xml'
Assets = {
    Asset('ATLAS', M.ATLAS), 
    Asset('IMAGE', 'images/manage_together_integrated.tex')
}

modimport('historyplayerscreen')

-- Client codes end ------------------------------------------------------------
end

local function HasPermission(classified, cmd)
    return M.HasPermission(cmd, classified.permission_mask) or false 
end
local function HasVotePermission(classified, cmd)
    return M.HasPermission(cmd, classified.vote_permission_mask) or false
end

local function GetAllowNewPlayersToConnect(classified)
    return classified.allow_new_players_to_connect
end

local function QueryHistoryPlayers(classified, block_index)
    if classified.last_query_player_record_timestamp and 
        GetTime() - classified.last_query_player_record_timestamp <= 3 then 
        dbg('Current Time: ', GetTime(), 'Last Query Time: ', classified.last_query_player_record_timestamp)
        dbg('ignored a request for query history record, because one request has just sended')
        return
    end

    SendModRPCToServer(GetModRPC(M.RPC.NAMESPACE, M.RPC.SEND_COMMAND), 
        M.COMMAND_ENUM.QUERY_HISTORY_PLAYERS, 
        classified.last_query_player_record_timestamp, 
        block_index or classified.next_query_player_record_block_index
    )

    -- update the query timestamp
    classified.last_query_player_record_timestamp = GetTime()

end

local function QuerySnapshotInformations(classified)
    SendModRPCToServer(GetModRPC(M.RPC.NAMESPACE, M.RPC.SEND_COMMAND), M.COMMAND_ENUM.QUERY_SNAPSHOT_INFORMATIONS)
end

-- actually it just query history players and snapshot informations
local function QueryServerData(classified)
    QueryHistoryPlayers(classified)
    QuerySnapshotInformations(classified)
end

local function RequestToExecuteCommand(classified, cmd, ...)
    SendModRPCToServer(GetModRPC(M.RPC.NAMESPACE, M.RPC.SEND_COMMAND), cmd, ...)
end

local function RequestToExecuteVoteCommand(classified, cmd, ...)
    SendModRPCToServer(GetModRPC(M.RPC.NAMESPACE, M.RPC.SEND_VOTE_COMMAND), cmd, ...)
end

-- for server, 
-- notice: it is useless for the player itself, 
-- cause the real permission check is on the server, 
-- and it does not work for other players, 
-- cause the player_classified entity not exists on the other clients
local function SetPermission(classified, level)

    -- permission level
    classified.net_permission_level:set(level)

    local mask = M.PERMISSION_MASK[level]
    local vote_mask = FiltUnvotableCommands(M.PERMISSION_MASK[VotePermissionElevate(level)])

    -- permission mask
    local low32, high32 = M.splitbit64to32(mask)
    classified.net_permission_masks[1]:set(low32)
    classified.net_permission_masks[2]:set(high32)

    -- vote permission mask
    low32, high32 = M.splitbit64to32(vote_mask)
    classified.net_vote_permission_masks[1]:set(low32)
    classified.net_vote_permission_masks[2]:set(high32)

end

local function CommandApplyableForPlayerTarget(classified, cmd, target_userid)
    if not chain_get(M.COMMAND[cmd], 'user_targetted') then
        return M.EXECUTION_CATEGORY.NO
    end

    local target_lvl
    if GLOBAL.TheWorld then
        target_lvl = chain_get(GLOBAL.TheWorld.components.serverinforecord.player_record, target_userid, 'permission_level')
    end
    if not target_lvl then return M.EXECUTION_CATEGORY.NO end
    if classified:HasPermission(cmd) and M.LevelHigherThan(classified.permission_level, target_lvl) then
        return M.EXECUTION_CATEGORY.YES
    elseif classified:HasVotePermission(cmd) and M.LevelHigherThan(VotePermissionElevate(classified.permission_level), target_lvl) then
        return M.EXECUTION_CATEGORY.VOTE_ONLY
    else
        return M.EXECUTION_CATEGORY.NO
    end
        
end

-- this should be call on both server & client 
AddPrefabPostInit('player_classified', function(inst)
    dbg('postinit player_classified')
    inst.net_permission_level = net_byte(inst.GUID, 'manage_together.permission_level', 'permission_level_changed')
    
    -- to tell the truth, I don't think the commands will more than 64 in the future...
    -- so we just make a happy hard code.
    -- lua integer size have 64 bits, however netver does not supports 64 bits integer type,
    -- so we should add 2 net_uint(32 bits) variables 
    inst.net_permission_masks = {
        net_uint(inst.GUID, 'manage_together.permission_masks[1]', 'permission_mask_changed'),
        net_uint(inst.GUID, 'manage_together.permission_masks[2]', 'permission_mask_changed')
    }
    inst.net_vote_permission_masks = {
        net_uint(inst.GUID, 'manage_together.vote_permission_masks[1]', 'vote_permission_mask_changed'),
        net_uint(inst.GUID, 'manage_together.vote_permission_masks[2]', 'vote_permission_mask_changed')
    }
    inst.net_allow_new_players_to_connect = net_bool(inst.GUID, 'manage_together.allow_new_players_to_connect', 'new_player_joinability_changed')

    inst.permission_level = M.PERMISSION.USER
    inst.permission_mask = 0
    inst.vote_permission_mask = 0
    inst.allow_new_players_to_connect = false
    inst.last_query_player_record_timestamp = nil
    inst.next_query_player_record_block_index = 1

    inst:ListenForEvent('permission_level_changed', function()
        inst.permission_level = inst.net_permission_level:value()
    end)
    
    inst:ListenForEvent('permission_mask_changed', function()
        inst.permission_mask = M.concatbit32to64(inst.net_permission_masks[1]:value(), inst.net_permission_masks[2]:value())
    end)
    
    inst:ListenForEvent('vote_permission_mask_changed', function()
        inst.vote_permission_mask = M.concatbit32to64(inst.net_vote_permission_masks[1]:value(), inst.net_vote_permission_masks[2]:value())
    end)
    
    inst:ListenForEvent('new_player_joinability_changed', function()
        inst.allow_new_players_to_connect = inst.net_allow_new_players_to_connect:value()
        dbg('player_classified: new_player_joinability_changed: ', inst.allow_new_players_to_connect)
    end)


    if GLOBAL.TheWorld then
        inst:ListenForEvent('player_record_sync_completed', function(src, has_more)
            dbg('listened player_record_sync_completed, has_more = ', has_more, 'this index = ', inst.next_query_player_record_block_index)
            if has_more then
                local last = inst.next_query_player_record_block_index
                inst.next_query_player_record_block_index = last and (last + 1) or 1
            else
                -- all of the existing records are received, 
                -- we just need to receive the updated reocrds now
                inst.next_query_player_record_block_index = nil
            end
        end, GLOBAL.TheWorld)

        if GLOBAL.TheWorld.ismastersim then
            local recorder = GLOBAL.TheWorld.shard.components.shard_serverinforecord

            inst:ListenForEvent('ms_new_player_joinability_changed', function()
                dbg('player_classified: listened ms_new_player_joinability_changed: ', recorder:GetAllowNewPlayersToConnect())
                if HasPermission(inst, M.COMMAND_ENUM.QUERY_HISTORY_PLAYERS) then
                    inst.net_allow_new_players_to_connect:set(recorder:GetAllowNewPlayersToConnect())
                end
            end, GLOBAL.TheWorld.shard)

            -- update once
            inst:DoTaskInTime(0, function()
                dbg('player_classified: update new player joinability once: ', recorder:GetAllowNewPlayersToConnect())
                local mask = M.PERMISSION_MASK[PermissionLevel(inst._parent.userid)]
                dbg('inst._parent: ', inst._parent, 'userid: ', inst._parent.userid, 'mask: ', mask)
                if M.HasPermission(M.COMMAND_ENUM.QUERY_HISTORY_PLAYERS, mask) then
                    inst.net_allow_new_players_to_connect:set(recorder:GetAllowNewPlayersToConnect())
                    dbg('finished to set new player joinability')
                end
            end)
        end
    end



    inst.HasPermission = HasPermission
    inst.HasVotePermission = HasVotePermission
    inst.GetAllowNewPlayersToConnect = GetAllowNewPlayersToConnect
    inst.SetPermission = SetPermission
    inst.QueryHistoryPlayers = QueryHistoryPlayers
    inst.QuerySnapshotInformations = QuerySnapshotInformations
    inst.QueryServerData = QueryServerData
    inst.RequestToExecuteCommand = RequestToExecuteCommand
    inst.RequestToExecuteVoteCommand = RequestToExecuteVoteCommand
    inst.CommandApplyableForPlayerTarget = CommandApplyableForPlayerTarget
    
    
end)


AddPrefabPostInit('world', function(inst)
    dbg('AddPrefabPostInit: world')

    inst:AddComponent('serverinforecord')
    
end)

