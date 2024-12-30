
GLOBAL.manage_together = {}
local M = GLOBAL.manage_together

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
function M.LevelHigherThanOrEqual(a_lvl, b_lvl)
    return M.PERMISSION_ORDER[a_lvl] <= M.PERMISSION_ORDER[b_lvl]
end
function M.LevelEqual(a_lvl, b_lvl)
    return M.PERMISSION_ORDER[a_lvl] == M.PERMISSION_ORDER[b_lvl]
end
function M.LevelSameAs(a_lvl, b_lvl)
    return a_lvl == b_lvl
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
    M.CLEANER_ITEM_STAT_ANNOUNCEMENT = is_config_enabled('cleaner_item_stat_announcement')
    M.MOD_OUTOFDATE_HANDLER_ENABLED = is_config_enabled('modoutofdate_handler_enabled')
    M.MOD_OUTOFDATE_HANDLER_ADD_SHUTDOWN_OPTION = is_config_enabled('modoutofdate_handler_add_shutdown_option')
    M.MOD_OUTOFDATE_REVOTE_MINUTE = GetModConfigData('mod_out_of_date_revote_minute') or 5
    M.MOD_OUTOFDATE_VOTE_DEFAULT_ACTION = GetModConfigData('mod_outofdate_vote_default_action') or nil

    M.DEFAULT_AUTO_NEW_PLAYER_WALL_ENABLED = is_config_enabled('auto_new_player_wall_enabled')
    if type(auto_new_player_wall_min_level) == 'string' then
        -- config is permission level name
        -- this setting(config) is unable to set on in-game screen yet,
        -- but the command is implemented
        M.DEFAULT_AUTO_NEW_PLAYER_WALL_MIN_LEVEL = M.PERMISSION[string.upper(auto_new_player_wall_min_level)] or M.PERMISSION.MODERATOR
    else
        M.DEFAULT_AUTO_NEW_PLAYER_WALL_MIN_LEVEL = M.PERMISSION.MODERATOR
    end

    modimport('main_strings')
    M.LANGUAGE = GetModConfigData('language')
    local localization_lang = {
        en = 'main_strings_en'   
    }
    if localization_lang[M.LANGUAGE] then
        modimport(localization_lang[M.LANGUAGE])

        -- set metatables, so we can display default language strings while localized strings are missing
        setmetatable(GLOBAL.STRINGS.UI.MANAGE_TOGETHER, { __index = GLOBAL.STRINGS.UI.MANAGE_TOGETHER_DEFAULT })
        setmetatable(GLOBAL.STRINGS.UI.HISTORYPLAYERSCREEN, { __index = GLOBAL.STRINGS.UI.HISTORYPLAYERSCREEN_DEFAULT })
    else
        -- alias
        GLOBAL.STRINGS.UI.MANAGE_TOGETHER = GLOBAL.STRINGS.UI.MANAGE_TOGETHER_DEFAULT
        GLOBAL.STRINGS.UI.HISTORYPLAYERSCREEN = GLOBAL.STRINGS.UI.HISTORYPLAYERSCREEN_DEFAULT
    end

    M.RPC_RESPONSE_TIMEOUT = 10
end
InitConfigs()


local S = GLOBAL.STRINGS.UI.MANAGE_TOGETHER

modimport('utils')
-- modimport ('asyncutil') -- it is imported in utils
local Functional = require 'functional'

M.using_namespace(M, GLOBAL, Functional)

local lshift, rshift, bitor, bitand = bit.lshift, bit.rshift, bit.bor, bit.band



M.ERROR_CODE = table.invert({
    'PERMISSION_DENIED',  -- = 1
    'BAD_COMMAND',        -- = 2
    'BAD_ARGUMENT',       -- = ...
    'BAD_TARGET',
    'DATA_NOT_PRESENT',
    'VOTE_CONFLICT', 
    'COMMAND_NOT_VOTABLE',
    'INTERNAL_ERROR', 
    'MISSING_RESPONSE', 
    'HAS_MORE_DATA',
})
M.ERROR_CODE.SUCCESS = 0


local function moderator_config(name)
    config_name = 'moderator_' .. string.lower(name)
    local conf = GetModConfigData(config_name)
    if conf == nil then
        -- missing config, try to get default config from modinfo
        conf = LoadModInfoDefaultPermissionConfigs()[config_name]
    end

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
    dbg('{stat: }')
    for userid, v in pairs(stat) do
        local name = GetPlayerRecord(userid).name or '???'

        if IsTableEmpty(v.counts) then
            if not M.CLEANER_ITEM_STAT_ANNOUNCEMENT then     
                announce_fmt_no_head(S.FMT_MAKE_ITEM_STAT_DOES_NOT_HAVE_ITEM, 
                    name,
                    userid, 
                    v.has_deeper_container and S.MAKE_ITEM_STAT_HAS_DEEPER_CONTAINER1 or ''    
                )
            end
        else
            -- title
            local announcement_head = S.FMT_MAKE_ITEM_STAT_HAS_ITEM:format( 
                name, 
                userid, 
                v.has_deeper_container and S.MAKE_ITEM_STAT_HAS_DEEPER_CONTAINER2 or ''
            )
            -- details
            -- announce format:
            -- Name(Userid) have: 
            -- item1(prefab1): 1; item2(prefab2): 3;
            -- item3(prefab3): 3; ...
            local n = 0 -- for line feed
            local details = {}
            local line = ''
            for item, count in pairs(v.counts) do
                n = n + 1

                line = line .. S.FMT_SINGLE_ITEM_RESULT:format(STRINGS.NAMES[item:upper()] or STRINGS.NAMES.UNKNOWN, item, count)
                if n % 2 == 0 then
                    table.insert(details, line)
                    line = ''
                end
            end
            if n % 2 ~= 0 then
                table.insert(details, line)
            end
            -- an offical typo bug cause there is no length limitation of one single announcement, 
            -- bug is reported, 
            -- but I decide to abuse it😈 cuz klei probaly would not fix it
            local detail_string = table.concat(details, '\n')
             
            announce_no_head(announcement_head .. '\n' .. detail_string)
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

local execute_command_impl

local function AddOfficalVoteCommand(name, voteresultfn, override_args, forward_original_params)

    -- to modify more usercommand arguments, set arguments in override_args table 
    
    if not override_args then
        override_args = {}
    end

    local default_args = {
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
        serverfn = function(params, caller)
            local env = M.GetVoteEnv()
            if not env then
                log('error: failed to execute vote command: command arguments lost')
                return
            end

            if forward_original_params then
                table.insert(env.args, params)
                table.insert(env.args, caller)
            end

            async(execute_command_impl, M.GetPlayerByUserid(env.starter_userid), M.COMMAND_ENUM[name], true, unpack(env.args)):set_callback(function(result)
                log('executed vote command: cmd =', name, 'args =', M.tolinekvstring(env.args), ', result =', M.ErrorCodeToName(result))
            end)
            
            M.ResetVoteEnv()
        end,
    }

    AddUserCommand('MANAGE_TOGETHER_' .. name,  
        setmetatable(override_args, {__index = default_args})
    )
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

function M.AddCommand(command_info, command_fn, regen_permission_mask)
    assert(M.COMMAND_NUM < 64, 'error: the number of commands exceeded limitation(64)')


    local vote_result_fn
    if not command_info.permission then
        command_info.permission, vote_result_fn = moderator_config(command_info.name)
    end

    -- set command enum
    local cmd_enum = lshift(1, M.COMMAND_NUM)
    M.COMMAND_NUM = M.COMMAND_NUM + 1
    M.COMMAND_ENUM[command_info.name] = cmd_enum

    if not command_info.fn then
        command_info.fn = command_fn
    end

    if not command_info.args_description then
        command_info.args_description = (command_info.user_targetted and DefaultUserTargettedArgsDescription or DefaultArgsDescription)
    end

    -- set command info
    M.COMMAND[cmd_enum] = command_info

    if command_info.can_vote then
        AddOfficalVoteCommand(command_info.name, vote_result_fn, command_info.vote_override_args, command_info.vote_forward_original_params)
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
            v,    -- command_info
            nil,  -- command_fn, it is already passed by command_info.fn
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
            if M.LevelHigherThanOrEqual(perm_lvl, M.COMMAND[cmd_enum].permission) then
                
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
    return 'UNKNOWN_ERROR_CODE'
end
function M.CommandEnumToName(cmd)
    for name, cmd_enum in pairs(M.COMMAND_ENUM) do
        if cmd_enum == cmd then
            return name
        end
    end
    return 'UNKNOWN_COMMAND_ENUM'
end
function M.LevelEnumToName(level)
    for name, lvl in pairs(M.PERMISSION) do
        if lvl == level then
            return name
        end
    end
    return 'UNKNOWN_LEVEL_ENUM'
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

M.CHECKERS = {
    bool      = checkbool, 
    number    = checknumber, 
    uint      = checkuint, 
    string    = checkstring,
    optbool   = optbool,
    optnumber = optnumber, 
    optuint   = optuint, 
    optstring = optstring,
    
    table = function(val) return type(val) == 'table' end,
    opttable = function(val) return val == nil or type(val) == 'table' end,
    
    userid_recorded = function(val) return GetPlayerRecord(val) ~= nil end, 
    -- unfortunately, lua's regex does not support repeat counting syntex like [%w%-_]{8}, 
    -- so we have to write it manually
    userid_like = function(val) return checkstring(val) and val:match('^KU_[%w%-_][%w%-_][%w%-_][%w%-_][%w%-_][%w%-_][%w%-_][%w%-_]$') ~= nil end, 

    snapshot_id_like    = function(val) return checkuint(val) and val > 0 end,
    snapshot_id_existed = function(val) return checkuint(val) and GetServerInfoComponent():SnapshotIDExists(val) end,
    
    command_enum = function(val) return M.COMMAND[val] ~= nil end,
    error_code   = function(val)  
        if not checkuint(val) then return false end
        for _, v in pairs(M.ERROR_CODE) do
            if v == val then
                return true
            end
        end
        return false
    end,

    ['nil'] = function(val) return val == nil end, -- 'nil' is same as nil
    any = function() return true end,

}
M.CHECKERS.userid = M.CHECKERS.userid_like
M.CHECKERS.none   = M.CHECKERS['nil']
M.CHECKERS.same   = 'same' -- apply the last checkers to all of the varargs

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
        checker = {        'optnumber',          'optuint'}, 
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
                log('refreshing player records')
                comp:RecordOnlinePlayers()
                comp:LoadSaveInfo()
                comp:LoadModeratorFile()
            else
                log('world not exists or historyplayerrecord component not exists')
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
        checker = {         IsPlayerOnline },
        fn = function(doer, target_userid)
            -- kick a player
            -- don't need to check target_userid, which has been checked on ExecuteCommand

            TheNet:Kick(target_userid)
            announce_fmt(S.FMT_KICKED_PLAYER, GetPlayerRecord(target_userid).name, target_userid)
        end
    },
    {
        name = 'KILL', 
        user_targetted = true,
        can_vote = true,
        checker = {        'any' }, -- userid will be check on ExecuteCommand, so we don't need to check again
        fn = function(doer, target_userid)
            -- kill a player, and let it drop everything

            local missing_count, result_table = BroadcastShardCommand(M.COMMAND_ENUM.KILL, target_userid):get()
            
            if missing_count > 0 or result_table == nil then
                return M.ERROR_CODE.MISSING_RESPONSE
            end

            for shardid, res in pairs(result_table) do
                local status = res[1]
                if status == 2 then
                    -- player is killed in this shard, command executed successfully
                    return M.ERROR_CODE.SUCCESS
                elseif status == 1 then
                    return M.ERROR_CODE.INTERNAL_ERROR
                end
            end
            return M.ERROR_CODE.INTERNAL_ERROR
        end
    },
    {
        name = 'BAN',
        user_targetted = true, 
        can_vote = true,  
        checker = {         fun(PermissionLevel) * fun(LevelSameAs)[M.PERMISSION.USER_BANNED] * NOT },
        fn = function(doer, target_userid)
            -- ban a player

            GetServerInfoComponent():SetPermission(target_userid, M.PERMISSION.USER_BANNED)
            TheNet:Ban(target_userid)
            announce_fmt(S.FMT_BANNED_PLAYER, GetPlayerRecord(target_userid).name, target_userid)
        end
    },
    {
        name = 'KILLBAN', 
        user_targetted = true, 
        can_vote = true, 
        checker = {         fun(PermissionLevel) * fun(LevelSameAs)[M.PERMISSION.USER_BANNED] * NOT },
        fn = function(doer, target_userid)
            -- kill and ban a player

            GetServerInfoComponent():SetPermission(target_userid, M.PERMISSION.USER_BANNED)
            local missing_count, result_table = BroadcastShardCommand(M.COMMAND_ENUM.KILL, target_userid):get()
            execute_in_time_nonstatic(3, TheNet.Ban, TheNet, target_userid)
            if missing_count > 0 or result_table == nil then
                return M.ERROR_CODE.MISSING_RESPONSE
            end

            for shardid, res in pairs(result_table) do
                local status = res[1]
                if status == 2 then
                    -- player is killed in this shard, command executed successfully
                    return M.ERROR_CODE.SUCCESS
                elseif status == 1 then
                    return M.ERROR_CODE.INTERNAL_ERROR
                end
            end
            return M.ERROR_CODE.INTERNAL_ERROR
        end
    },
    {
        name = 'SAVE', 
        fn = function(doer)
            -- save the world
            TheWorld:PushEvent('ms_save')
            announce_fmt(S.FMT_SENDED_SAVE_REQUEST, doer.name)
        end
    },
    {
        -- a better rollback command, which can let client specify the appointed rollback slot, but not saving point index
        name = 'ROLLBACK', 
        can_vote = true, 
        checker = {                'snapshot_id_existed', 'optnumber'},
        args_description = function(target_snapshot_id, delay_seconds)
            return GetServerInfoComponent():BuildSnapshotBriefStringByID(S.FMT_ROLLBACK_BRIEF, target_snapshot_id)
        end,
        fn = function(doer, target_snapshot_id, delay_seconds)
            local comp = GetServerInfoComponent()
            if comp:GetIsRollingBack() then
                announce(S.ERR_REPEATED_REQUEST)
                return M.ERROR_CODE.REPEATED_REQUEST
            end

            announce_fmt(S.FMT_SENDED_ROLLBACK2_REQUEST, 
                doer.name, 
                comp:BuildSnapshotBriefStringByID(S.FMT_ROLLBACK_BRIEF, target_snapshot_id)
            )
            if not delay_seconds or delay_seconds < 0 then
                delay_seconds = 5
            end 
            -- this flag will be automatically reset when world is reloading
            -- or reset in 1 minutes, this means we failed to rollback 
            comp:SetIsRollingBack()

            execute_in_time(delay_seconds, M.RollbackBySnapshotID, target_snapshot_id)
        end
    },
    {
        name = 'REGENERATE_WORLD', 
        can_vote = true,
        checker = {        'optnumber'},
        fn = function(doer, delay_seconds)
            if not delay_seconds or delay_seconds < 0 then
                delay_seconds = 5
            end 
            announce_fmt(S.FMT_SENDED_REGENERATE_WORLD_REQUEST, doer.name, delay_seconds)
            execute_in_time(delay_seconds, TheNet.SendWorldResetRequestToServer, TheNet)

        end
    },
    {
        name = 'SHUTDOWN', 
        can_vote = true, 
        permission = M.PERMISSION.ADMIN,
        checker = {        'optnumber',      'optstring'},
        fn = function(doer, delay_seconds, reason)
            if not delay_seconds then
                delay_seconds = 0
            elseif delay_seconds < 0 then
                delay_seconds = 5
            end
            if reason then
                -- announce(reason)
                announce_fmt(S.FMT_SERVER_WILL_SHUTDOWN, delay_seconds, reason)
            end
            execute_in_time(delay_seconds, c_shutdown)
            -- if TheWorld then
            --     TheWorld:DoTaskInTime(delay_seconds, function()
            --         c_shutdown()
            --     end)
            -- else
            --     log('error: TheWorld is nil, server will shutdown immediactly regardless of delay_seconds param')
            --     c_shutdown()
            -- end

        end
    },
    {
        name = 'ADD_MODERATOR', 
        can_vote = true, 
        user_targetted = true, 
        checker = {         fun(LevelHigherThan)[M.PERMISSION.MODERATOR] * PermissionLevel},
        fn = function(doer, target_userid)
            -- add a player as moderator

            GetServerInfoComponent():SetPermission(target_userid, M.PERMISSION.MODERATOR)
            
        end
    },
    {
        name = 'REMOVE_MODERATOR', 
        can_vote = true,
        user_targetted = true,
        checker = {         fun(PermissionLevel) * fun(LevelSameAs)[M.PERMISSION.MODERATOR]},
        fn = function(doer, target_userid)
            -- remove a moderator 

            GetServerInfoComponent():SetPermission(target_userid, M.PERMISSION.USER)

        end
    }, 
    {
        name = 'SET_NEW_PLAYER_JOINABILITY', 
        can_vote = true, 
        checker = {                'bool'},
        args_description = function(allowed) return allowed and S.ALLOW_NEW_PLAYER_JOIN or S.NOT_ALLOW_NEW_PLAYER_JOIN end,
        fn = function(doer, allowed)
            if allowed ~= nil and type(allowed) ~= 'boolean' then return M.ERROR_CODE.BAD_ARGUMENT end
            allowed = bool(allowed)
            GetServerInfoComponent():SetAllowNewPlayersToConnect(allowed)
            M.announce_fmt(S.FMT_SET_NEW_PLAYER_JOINABILITY[allowed and 'ALLOW' or 'NOT_ALLOW'], doer.name)
        end
    },
    {
        name = 'SET_AUTO_NEW_PLAYER_WALL',
        can_vote = true, 
        checker = {         'bool',  fun(key_exists)[M.PERMISSION_ORDER]}, 
        fn = function(doer, enabled, min_online_player_level)

            -- only admin can set min_online_player_level
            -- if moderator passed a non-nil min_online_player_level, a whole command whil be failed to execute

            if PermissionLevel(doer.userid) ~= M.PERMISSION.ADMIN then
                if min_online_player_level ~= nil then
                    GetServerInfoComponent():SetAutoNewPlayerWall(enabled, nil) -- pass nil to ignore it
                else
                    dbg('a non-admin player is attempt to execute SET_AUTO_NEW_PLAYER_WALL command but min_online_player_level is not nil')
                    return M.ERROR_CODE.BAD_ARGUMENT
                end
            else
                GetServerInfoComponent():SetAutoNewPlayerWall(enabled, min_online_player_level)
            end
        end
    }, 
    {
        name = 'MAKE_ITEM_STAT_IN_PLAYER_INVENTORIES', 
        can_vote = true, 
        checker = {
            -- param userid_or_flag
            fun(CHECKERS.userid_recorded) *OR* fun(key_exists)[ITEM_STAT_CATEGORY],
            -- param item_prefab
            'string', 
            'same'
        },
        args_description = function(userid_or_flag, ...)
            local item_names = {}
            for _, prefab in varg_pairs(...) do
                table.insert(item_names, (STRINGS.NAMES[prefab:upper()] or STRINGS.NAMES.UNKNOWN) .. '(' .. prefab .. ')')
            end
            return 
                -- target string
                CHECKERS.uint(userid_or_flag) and ITEM_STAT_CATEGORY[userid_or_flag] or GetPlayerRecord(userid_or_flag).name, 
                table.concat(item_names, ', ')
        end,
        fn = function(doer, userid_or_flag, ...)
            -- userid_or_flag: a target userid or a flag
            -- flag representation:
            -- 0: all of the online players
            -- 1: all of the offline players(recorded offline players)
            -- 2: all of the online & offline(recorded) players

            local item_prefabs = {...}

            -- do announce

            local item_names = {}
            for _, prefab in ipairs(item_prefabs) do
               table.insert(item_names, (STRINGS.NAMES[string.upper(prefab)] or GLOBAL.STRINGS.NAMES.UNKNOWN) .. '(' .. prefab .. ')')
            end

            announce_fmt(S.FMT_MAKE_ITEM_STAT_HEAD, doer.name)
            if type(userid_or_flag) == 'string' then
                announce_fmt(S.FMT_MAKE_ITEM_STAT_HEAD2, 
                    string.format('%s(%s)', GetPlayerRecord(userid_or_flag).name, userid_or_flag), 
                    table.concat(item_names, ', ')
                )
            else
                announce_fmt(S.FMT_MAKE_ITEM_STAT_HEAD2, 
                    ITEM_STAT_CATEGORY[userid_or_flag], 
                    table.concat(item_names, ', ')
                )
            end
            announce_no_head(S.MAKE_ITEM_STAT_DELIM)
            local missing_count, result_table = BroadcastShardCommand(M.COMMAND_ENUM.MAKE_ITEM_STAT_IN_PLAYER_INVENTORIES, userid_or_flag, ...):get()
            
            announce_no_head(S.MAKE_ITEM_STAT_DELIM)
            if missing_count ~= 0 then
                announce(S.MAKE_ITEM_STAT_FINISHED_BUT_MISSING_RESPONSE)
            else
                announce(S.MAKE_ITEM_STAT_FINISHED)
            end
        end
    }, 
    {
        name = 'MODOUTOFDATE', 
        can_vote = true, 
        -- this command should only be call on server  
        permission = M.PERMISSION.ADMIN,
        vote_forward_original_params = true,
        vote_override_args = {
            voteresultfn = VoteUtil.DefaultMajorityVote,
            voteminpasscount = 1,
            voteoptions = {
                -- 1. do not shutdown, but suppress the announcement
                S.VOTE.MODOUTOFDATE.SUPPRESS_ANNOUNCEMENT,
    
                -- 2. do not shutdown, and start a vote again in ? minutes
                S.VOTE.MODOUTOFDATE.DELAY,
                
                -- 3. shutdown immediactly(with suppressing announcement)
                M.MOD_OUTOFDATE_HANDLER_ADD_SHUTDOWN_OPTION and S.VOTE.MODOUTOFDATE.SHUTDOWN or nil, 
                
                -- 4. shutdown immediactly when server is empty(with suppressing announcement);
                M.MOD_OUTOFDATE_HANDLER_ADD_SHUTDOWN_OPTION and S.VOTE.MODOUTOFDATE.SHUTDOWN_WHEN_NOBODY or nil
                
                --  (no explicit option) 5. do nothing
            }
        },
        checker = {        'optnumber', 'opttable', 'any'},
        fn = function(doer, selection, params, fucking_caller) -- params and caller is forwarded from the original vote params
            
            -- selection is used for directly command execution, 
            -- param is used for accept vote result 

            log(string.format('mod out of date command is being executed by %s(%s)', doer.userid, doer.name))

            if params then
                M.MOD_OUTOFDATE_VOTE_PASSED_FLAG = true
                if not selection then
                    selection = params.voteselection
                end
            end
            
            if not (CHECKERS.number(selection)) then
                dbg('failed to execute mod out of date command, params are bad')
                return M.ERROR_CODE.BAD_ARGUMENT
            end

            if selection ~= 2 then
                
                -- suppress annoying announcement anyway 
                GetServerInfoComponent().mod_out_of_date_handler:SetSuppressAnnouncement(true)

                if selection == 1 then
                    -- do suppress announcement
                    log('modoutofdate: suppress mod out of date announcement only')
                    announce(S.MODOUTOFDATE_SUPPRESSED_ANNOUNCEMENT)
                    -- do nothing, announcement is suppressed now

                elseif selection == 3 then
                    -- do shutdown immediactly
                    log('modoutofdate: do shutdown immediactly')
                    -- return ExecuteCommand(doer, M.COMMAND_ENUM.SHUTDOWN, true, 5, S.SHUTDOWN_REASON_UPDATE_MOD)

                elseif selection == 4 then
                    -- do shutdown when server is empty
                    log('modoutofdate: do shutdown when server is empty')
                    announce(S.MODOUTOFDATE_SHUTDOWN_WHEN_SERVER_EMPTY)
                    
                    local server_keeps_empty = false
                    local shutdown_task

                    local on_server_once_empty = function()
                        if not server_keeps_empty then 
                            server_keeps_empty = true
                            log('server is empty, it will shutdown if nobody join in 1 minute')

                            shutdown_task = execute_in_time(60, execute_command_impl, 
                                -- server is still empty in 60 seconds, 
                                -- or this task will be cancel
                                doer, M.COMMAND_ENUM.SHUTDOWN, true, 5, S.SHUTDOWN_REASON_UPDATE_MOD
                            )
                        end
                    end

                    -- test once
                    if TheWorld.shard.components.shard_players:GetNumPlayers() == 0 then
                        on_server_once_empty()
                    end

                    TheWorld:ListenForEvent('ms_playercounts', function(inst, data)
                        if data.total == 0 then
                            -- server is empty now, but we wait for one more minute
                            on_server_once_empty()
                        else
                            -- reset task
                            server_keeps_empty = false
                            if shutdown_task then
                                shutdown_task:Cancel()
                                shutdown_task = nil
                                log('shutdown task is cancelled')
                            end
                        end
                    end)
                end
                
            else
                -- selection == 2
                -- do re-vote in some minutes
                log('modoutofdate: start a vote again in', M.MOD_OUTOFDATE_REVOTE_MINUTE, 'minute(s)')
                announce_fmt(S.MODOUTOFDATE_REVOTE, M.MOD_OUTOFDATE_REVOTE_MINUTE)

                execute_in_time(M.MOD_OUTOFDATE_REVOTE_MINUTE * 60, StartCommandVote, 
                    doer, M.COMMAND_ENUM.MODOUTOFDATE
                )

            end
        end
    }
)

-- some commands are shard-unawared, we should handle it properly
M.SHARD_COMMAND = {
    [M.COMMAND_ENUM.KILL] = function(sender_shard_id, target_userid)

        -- return value: 
        -- 0: player is not in this shard
        -- 1: player is in this shard, but some error occured while killing it
        -- 2: successed to kill the target player

        local target = GetPlayerRecord(target_userid)
        
        if not target or not target.in_this_shard then return 0 end

        local announce_string = string.format(S.FMT_KILLED_PLAYER, target.name or '???', target_userid)
        if IsPlayerOnline(target_userid) then
            for _,v in pairs(GLOBAL.AllPlayers) do
                if v and v.userid == target_userid then
                    KillPlayer(v, announce_string)
                    return 2
                end
            end
            return 1
        else
            if not M.TemporarilyLoadOfflinePlayer(target_userid, KillPlayer, announce_string) then
                dbg('error: failed to kill a offline player')
                return 1
            end
            return 2
        end
    end,

    -- [M.COMMAND_ENUM.KILLBAN] = function(sender_shard_id, target_userid)

    --     -- return value: 
    --     -- 0: player is not in this shard
    --     -- 1: player is in this shard, but some error occured while killing it
    --     -- 2: successed to killban the target player

    --     local target = GetPlayerRecord(target_userid)
        
    --     if not target or not target.in_this_shard then return 0 end

    --     local announce_string = string.format(S.FMT_KILLBANNED_PLAYER, target.name or '???', target_userid)
    --     if IsPlayerOnline(target_userid) then
    --         for _,v in pairs(GLOBAL.AllPlayers) do
    --             if v and v.userid == target_userid then
    --                 KillPlayer(v, announce_string)
    --                 TheWorld:DoTaskInTime(3, TheNet.Ban, TheNet, target_userid)
    --                 return 2
    --             end
    --         end
    --         return 1
    --     else
    --         TheNet:Ban(target_userid)
    --         if not M.TemporarilyLoadOfflinePlayer(target_userid, KillPlayer, announce_string) then
    --             dbg('error: failed to killban a offline player')
    --             return 1
    --         end
    --     end
    -- end,
    [M.COMMAND_ENUM.MAKE_ITEM_STAT_IN_PLAYER_INVENTORIES] = function(sender_shard_id, userid_or_flag, ...)
        local item_prefabs = {...}
        if CHECKERS.userid_recorded(userid_or_flag) then
            if not GetPlayerRecord(userid_or_flag).in_this_shard then return true end
            AnnounceItemStat(M.MakePlayerInventoriesItemStat(userid_or_flag, item_prefabs))
            return true
        end

        -- userid_or_flag is a flag

        if userid_or_flag == 0 then
            -- all of the online players
            -- iterate AllPlayers list
            AnnounceItemStat(M.MakeOnlinePlayerInventoriesItemStat(item_prefabs))
        
        elseif userid_or_flag == 1 then
            -- all of the offline player
            local userid_list = {}
            for userid, record in pairs(GetPlayerRecords()) do
                if record.in_this_shard and IsPlayerOnline(userid) then table.insert(userid_list, userid) end
            end
            AnnounceItemStat(M.MakePlayerInventoriesItemStat(userid_list, item_prefabs))
        
        elseif userid_or_flag == 2 then
            -- all of the recorded player
            local userid_list  = {}
            for userid, record in pairs(GetPlayerRecords()) do
                if record.in_this_shard then table.insert(userid_list, userid) end
            end
            AnnounceItemStat(M.MakePlayerInventoriesItemStat(userid_list, item_prefabs))
        
        end

        return true -- return a non-nil value in order to forcely send a result to broadcast raiser
    end,

    -- just for internal use
    -- this is attempted to be called on master shard
    START_VOTE = function(sender_shard_id, cmd, starter_userid, ...)
        if not TheShard:IsMaster() then
            -- this is not as excepted
            dbg('error: M.SHARD_COMMAND.START_VOTE() is called on secondary shard')
            dbg('{sender_shard_id: }, cmd: ', M.CommandEnumToName(cmd), ', {starter_userid: }, {arg: }')
            return
        end
        
        -- this is broken while it's called on server side
        -- GLOBAL.TheNet:StartVote(M.CmdEnumToVoteHash(cmd), M.COMMAND[cmd].user_targetted and arg or nil)
        
        
        -- first arg will be target_userid if cmd is user_targetted
        -- the real arg are stored to M.VOTE_ENVIRONMENT
        -- this is because the offical function ONLY accepts a target_userid or nil as a arg 
        -- and further more, vote command will be failed to execute if target is offline 
        -- so we just pass a fucking nil to offical function

        -- shardnetworking.lua
        local args = {...}

        M.SetVoteEnv({
            starter_userid = starter_userid, 
            args = args, 
        })
        dbg('intent to start a vote, {sender_shard_id: }, cmd: ', M.CommandEnumToName(cmd), ', {starter_userid: }, {arg: }')

        local vote_started = false
        local taskself = staticScheduler:GetCurrentTask()
        local function on_vote_started()
            if not vote_started then 
                vote_started = true
                local announce_string = string.format(
                    S.VOTE[M.CommandEnumToName(cmd)].FMT_ANNOUNCE, 
                    M.COMMAND[cmd].args_description(unpack(args))
                )
                M.announce_vote_fmt(S.VOTE.FMT_START, GetPlayerRecord(starter_userid).name or S.UNKNOWN_PLAYER, announce_string)
                -- listen only once
                TheWorld:RemoveEventCallback('master_worldvoterupdate', on_vote_started)
                
                WakeTask(taskself)
            end
        end

        TheWorld:ListenForEvent('master_worldvoterupdate', on_vote_started)

        Shard_StartVote(M.CmdEnumToVoteHash(cmd), starter_userid, nil)

        Sleep(1)
        -- check for voting whether is filed to start
        if not vote_started then
            -- remove the event listener anyway
            M.ResetVoteEnv()
            M.announce_vote_fmt(S.VOTE.FAILED_TO_START)
            dbg('failed to start a vote.')
            TheWorld:RemoveEventCallback('master_worldvoterupdate', on_vote_started)
        end

        return vote_started
        
    end
}

local function RegisterRPCs()

    -- server rpcs

    AddServerRPC('SEND_COMMAND', function(player, cmd, ...)
        
        local result = ExecuteCommand(player, cmd, ...):get_before(M.RPC_RESPONSE_TIMEOUT)
        if (result == M.ERROR_CODE.PERMISSION_DENIED or result == M.ERROR_CODE.BAD_COMMAND) and M.SILENT_FOR_PERMISSION_DEINED then
            return nil
        end
        
        return result
    end)

    AddServerRPC('SEND_VOTE_COMMAND', function(player, cmd, ...)
        local result = StartCommandVote(player, cmd, ...):get_before(M.RPC_RESPONSE_TIMEOUT)
        if (result == M.ERROR_CODE.PERMISSION_DENIED or result == M.ERROR_CODE.BAD_COMMAND) and M.SILENT_FOR_PERMISSION_DEINED then
            return nil
        end

        return result
    end)

    
    -- shard rpcs

    AddShardRPC('SHARD_SEND_COMMAND', function(sender_shard_id, cmd, ...)
        dbg('received shard command: ', M.CommandEnumToName(cmd), ', {arg = }')
        if M.SHARD_COMMAND[cmd] then
            return async(M.SHARD_COMMAND[cmd], sender_shard_id, ...):get_before(M.RPC_RESPONSE_TIMEOUT)
            -- return M.SHARD_COMMAND[cmd](sender_shard_id, ...)
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
            dbg('ForwardToMasterShard: here is already Master shard, cmd: ',  M.CommandEnumToName(cmd), ', argcount = ', select('#', ...), ', {arg = }')
            
            -- this future holds simple results...
            return async(M.SHARD_COMMAND[cmd], SHARDID.MASTER, ...) --> future(or nil)
            -- M.SHARD_COMMAND[cmd](GLOBAL.SHARDID.MASTER, ...) 
            
        else   
            dbg('error at ForwardToMasterShard: SHARD_COMMAND[cmd] is not exists, cmd: ', M.CommandEnumToName(cmd) ', argcount = ', select('#', ...), ', {arg = }')
            return nil
        end
    else
        dbg('Forward Shard Command To Master, cmd: ',  M.CommandEnumToName(cmd), ', argcount = ', select('#', ...), ', {arg = }')

        return async(function(...)
            local missing_response_count, result_table = SendRPCToShard(
                'SHARD_SEND_COMMAND',
                SHARDID.MASTER, 
                cmd, ...
            ):get()

            if missing_response_count == 1 or not result_table then
                dbg('error on SHARD_SEND_COMMAND: missing result, {result_table: }')
                return nil
            end
            local master_result = result_table[SHARDID.MASTER]
            if not master_result then
                dbg('error no SHARD_SEND_COMMAND: missing master result: {result_table: }')
                return nil
            end
            return unpack(master_result)
        end, ...)
    end
end 
-- local, forward declared
BroadcastShardCommand = function(cmd, ...)
    dbg('Broadcast Shard Command: ',  M.CommandEnumToName(cmd), ', argcount = ', select('#', ...), ', {arg = }')
    return select_first(SendRPCToShard( 
        'SHARD_SEND_COMMAND',  
        nil, 
        cmd, ...
    )) --> future: missing_response_count, result_table[shardids]
end


function M.CheckArgs(checkers, ...)
    local checkertype = type(checkers)
    if checkertype == 'table' then
        local args = {...}
        local last_checker_fn = CHECKERS.none
        local same_as_below = false
        for i, this_checker in ipairs(checkers) do

            if this_checker == CHECKERS.same then
                --         checker: number, same(i == 2)
                -- (valid) args:    1,      nil, nil ... 
                -- (valid)          2,      3,   nil ... 
                
                -- no more args 
                if #args < i then return true end
                
                -- check remained args
                for j = i, #args do
                    if not last_checker_fn(args[j]) then return false end
                end
                return true
            end

            local this_arg = args[i]
            if this_checker == nil and this_arg ~= nil then
                if this_arg ~= nil then
                    return false    
                end
                last_checker_fn = CHECKERS.none
                -- this arg should be nil
            elseif type(this_checker) == 'function' then
                if not this_checker(this_arg) then
                    -- bad argument 
                    return false
                end
                last_checker_fn = this_checker
            elseif type(this_checker) == 'string' then
                local the_checker_fn = CHECKERS[this_checker]
                
                assert(the_checker_fn ~= nil)
                
                -- bad argument 
                if not the_checker_fn(this_arg) then
                    
                    return false
                end
                
                last_checker_fn = the_checker_fn
            end
        end
        -- check remained args
        -- no more checker, so not accept remained args
        return select('#', ...) <= #checkers

    elseif checkertype == 'function' then
        return checkers(...)
    elseif checkers == nil then
        return select('#', ...) == 0 -- no args
    end
    dbg('in M.CheckArgs: bad checker type')
    return false
end

execute_command_impl = function(executor, cmd, is_vote, ...)
    local permission_level = PermissionLevel(executor.userid)
    if is_vote then
        permission_level = VotePermissionElevate(permission_level)
    end
    
    -- check data validity: cmd, args
    if not CHECKERS.command_enum(cmd) then
        -- bad command type
        return M.ERROR_CODE.BAD_COMMAND
    elseif not M.HasPermission(cmd, M.PERMISSION_MASK[permission_level]) then
        return M.ERROR_CODE.PERMISSION_DENIED
    elseif M.COMMAND[cmd].user_targetted then
        -- the first argument will be target_userid if command is player targeted
        local target_record = GetPlayerRecord(select_one(1, ...))
        if not target_record then
            return M.ERROR_CODE.BAD_TARGET
        elseif not M.LevelHigherThan(permission_level, target_record.permission_level) then
            -- permission is not allowed if theirs level are the same
            -- which also makes sure a users can't target itself except they do it by starting a vote 
            return M.ERROR_CODE.PERMISSION_DENIED
        end
    elseif not CheckArgs(M.COMMAND[cmd].checker, ...) then
        return M.ERROR_CODE.BAD_ARGUMENT
    end


    dbg('received command request from player: {executor.name = }, cmd = ', CommandEnumToName(cmd), ', {is_vote = }, {arg = }')

    local result = M.COMMAND[cmd].fn(executor, ...)
    -- nil(by default) means success
    return result == nil and M.ERROR_CODE.SUCCESS or result

end    

local start_command_vote_impl = function(executor, cmd, ...)
    local permission_level = VotePermissionElevate(PermissionLevel(executor.userid))
    if not CHECKERS.command_enum(cmd) then
        return M.ERROR_CODE.BAD_COMMAND
    elseif not M.HasPermission(cmd, M.PERMISSION_MASK[permission_level]) then
        return M.ERROR_CODE.PERMISSION_DENIED
    elseif not M.COMMAND[cmd].can_vote then
        return M.ERROR_CODE.COMMAND_NOT_VOTABLE
    elseif M.COMMAND[cmd].user_targetted then
        -- the first argument will be target_userid if command is player targeted
        local target_record = GetPlayerRecord(select_one(1, ...))
        if not target_record then
            return M.ERROR_CODE.BAD_TARGET
        elseif not M.LevelHigherThan(permission_level, target_record.permission_level) then
            -- permission is not allowed if theirs level are the same
            -- which also makes sure a users can't target itself except they do it by starting a vote 
            return M.ERROR_CODE.PERMISSION_DENIED
        end
    elseif not CheckArgs(M.COMMAND[cmd].checker, ...) then
        return M.ERROR_CODE.BAD_ARGUMENT
    end
    
    local voter_state, is_get_failed = chain_get(TheWorld, 'net', 'components', 'worldvoter', {'IsVoteActive'})
    if is_get_failed then
        return M.ERROR_CODE.INTERNAL_ERROR
    elseif voter_state == true then
        return M.ERROR_CODE.VOTE_CONFLICT
    end

    -- future returns whether vote is started
    return ForwardToMasterShard('START_VOTE', cmd, executor.userid, ...):get() and M.ERROR_CODE.SUCCESS or M.ERROR_CODE.INTERNAL_ERROR
end

function M.ExecuteCommand(executor, cmd, ...)
    return async(execute_command_impl, executor, cmd, false, ...)
end

function M.StartCommandVote(executor, cmd, ...)
    return async(start_command_vote_impl, executor, cmd, ...)
end

function M.ExecuteCommandFromServer(cmd, start_vote, ...)
    local client_table = TheNet:GetClientTable()
    if not client_table then
        log('failed to execute a command from server: client table is nil, command =', M.CommandEnumToName(cmd))
        return
    end
    -- host client object should be the first element of the client table
    local admin_host = client_table[1]
    if not (admin_host and admin_host.admin and admin_host.userid and admin_host.name) then
        log('failed to execute a command from server: host object is bad, command =', M.CommandEnumToName(cmd))
        return
    end 
    local future
    if start_vote then
        future = StartCommandVote(admin_host, cmd, ...)
    else
        future = ExecuteCommand(admin_host, cmd, ...)
    end
    log('finished a command execution request from server, command =', M.CommandEnumToName(cmd), ', result =', M.ErrorCodeToName(future))
    return future
end

AddPrefabPostInit('shard_network', function(inst)
    if not inst.components.shard_serverinforecord then
        inst:AddComponent('shard_serverinforecord')

            
        if M.MOD_OUTOFDATE_HANDLER_ENABLED and TheShard:IsMaster() then
            
            local handler = GetServerInfoComponent().mod_out_of_date_handler
            
            -- add callbacks
            handler:Add(function(mod)
                ExecuteCommandFromServer(M.COMMAND_ENUM.MODOUTOFDATE, true, nil) -- start a vote_state
                M.MOD_OUTOFDATE_VOTE_PASSED_FLAG = false
                if M.MOD_OUTOFDATE_VOTE_DEFAULT_ACTION then
                    execute_in_time_nonstatic(35, function()
                        -- do default action while vote is failed to pass
                        if not M.MOD_OUTOFDATE_VOTE_PASSED_FLAG then
                            -- vote failed to pass
                            ExecuteCommandFromServer(M.COMMAND_ENUM.MODOUTOFDATE, false, M.MOD_OUTOFDATE_VOTE_DEFAULT_ACTION)
                        end
                        M.MOD_OUTOFDATE_VOTE_PASSED_FLAG = nil
                    end)
                end
            end, true) -- trigger only once
            
        end
        
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
    Asset('IMAGE', M.ATLAS:gsub('%.xml$', '%.tex'))
}

modimport('historyplayerscreen')

-- Client codes end ------------------------------------------------------------
end

local function HasVotePermission(classified, cmd)
    return M.HasPermission(cmd, classified.vote_permission_mask) or false
end

local function HasPermission(classified, cmd)
    return (M.HasPermission(cmd, classified.permission_mask) or false), HasVotePermission(classified, cmd) 
end

local function QueryHistoryPlayers(classified, block_index)
    if classified.last_query_player_record_timestamp and 
        GetTime() - classified.last_query_player_record_timestamp <= 1 then 
        dbg('Current Time: ', GetTime(), ', {classified.last_query_player_record_timestamp = }')
        dbg('ignored a request for query history record, because one request has just sended')
        return
    end

    SendRPCToServer('SEND_COMMAND', 
        M.COMMAND_ENUM.QUERY_HISTORY_PLAYERS, 
        classified.last_query_player_record_timestamp, 
        block_index or classified.next_query_player_record_block_index
    )

    -- update the query timestamp
    classified.last_query_player_record_timestamp = GetTime()

end

local function QuerySnapshotInformations(classified)
    -- SendModRPCToServer(GetModRPC(M.RPC.NAMESPACE, M.RPC.SEND_COMMAND), M.COMMAND_ENUM.QUERY_SNAPSHOT_INFORMATIONS)
    SendRPCToServer('SEND_COMMAND', M.COMMAND_ENUM.QUERY_SNAPSHOT_INFORMATIONS)
end

-- actually it just query history players and snapshot informations
local function QueryServerData(classified)
    QueryHistoryPlayers(classified)
    QuerySnapshotInformations(classified)
end

local function RequestToExecuteCommand(classified, cmd, ...)
    local future, success = SendRPCToServer('SEND_COMMAND', cmd, ...)
    future:set_callback(function(missing_response_count, retcode)
        local name = M.CommandEnumToName(cmd)
        if not retcode or missing_response_count == 1 then
            dbg('SEND_COMMAND: failed to get result from server, {name = }, {retcode = }, {missing_response_count = }')    
            return
        end

        if CHECKERS.error_code(retcode) then
            dbg('received result from server(send command), {name = }, result = ', M.ErrorCodeToName(retcode))
        else
            dbg('received result from server(send command): {name = }, server drunk, {retcode = }')
        end
        
    end)
end

local function RequestToExecuteVoteCommand(classified, cmd, ...)
    -- SendModRPCToServer(GetModRPC(M.RPC.NAMESPACE, M.RPC.SEND_VOTE_COMMAND), cmd, ...)
    SendRPCToServer('SEND_VOTE_COMMAND', cmd, ...):set_callback(function(missing_response_count, retcode)
        local name = M.CommandEnumToName(cmd)        
        if not retcode or missing_response_count == 1 then
            dbg('SEND_VOTE_COMMAND: failed to get result from server, command {name = } {retcode = }, {missing_response_count = }')   
            return 
        end
        
        if CHECKERS.error_code(retcode) then
            dbg('received from server(send vote command), {name = }, result = ', M.ErrorCodeToName(retcode))
        else
            dbg('received result from server(send vote command): {name = }, server drunk, {retcode =}')
        end
    end )
end

-- for server, 
-- notice: it is useless for the player itself, 
-- cause the real permission check is on the server, 
-- and it does not work for other players, 
-- cause the player_classified entity not exists on the other clients
local function SetPermission(classified, level)
    dbg('setting player permission: {classified = }, {level = }')

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
    if TheWorld then
        target_lvl = chain_get(TheWorld.net.components.serverinforecord.player_record, target_userid, 'permission_level')
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


local original_mod_out_of_date_callback = Networking_ModOutOfDateAnnouncement

-- this should be call on both server & client 
AddPrefabPostInit('player_classified', function(inst)
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


    inst.net_suppress_mod_outofdate_announcement = net_bool(inst.GUID, 'manage_together.suppress_mod_outofdate_annoucement', 'suppress_mod_outofdate_annoucement_state_changed')


    inst.permission_level = M.PERMISSION.USER
    inst.permission_mask = 0
    inst.vote_permission_mask = 0
    inst.allow_new_players_to_connect = false
    inst.auto_new_player_wall_enabled = false
    inst.last_query_player_record_timestamp = nil
    inst.next_query_player_record_block_index = 1

    inst.suppress_mod_outofdate_annoucement = false

    inst:ListenForEvent('permission_level_changed', function()
        inst.permission_level = inst.net_permission_level:value()
        dbg('player_classified: permission_level_changed: ', inst.permission_level)
    end)
    
    inst:ListenForEvent('permission_mask_changed', function()
        inst.permission_mask = M.concatbit32to64(inst.net_permission_masks[1]:value(), inst.net_permission_masks[2]:value())
        dbg('player_classified: permission_mask_changed: ', inst.permission_mask)
    end)
    
    inst:ListenForEvent('vote_permission_mask_changed', function()
        inst.vote_permission_mask = M.concatbit32to64(inst.net_vote_permission_masks[1]:value(), inst.net_vote_permission_masks[2]:value())
        dbg('player_classified: vote_permission_mask_changed: ', inst.vote_permission_mask)
    end)

    inst:ListenForEvent('suppress_mod_outofdate_annoucement_state_changed', function()
        inst.suppress_mod_outofdate_annoucement = inst.net_suppress_mod_outofdate_announcement:value()

        if not TheWorld.ismastersim then
            GLOBAL.Networking_ModOutOfDateAnnouncement = inst.suppress_mod_outofdate_annoucement and function()end or original_mod_out_of_date_callback
        end
    end)


    if TheWorld then
        inst:ListenForEvent('player_record_sync_completed', function(src, has_more)
            dbg('listened player_record_sync_completed, {has_more = }, this index = ', inst.next_query_player_record_block_index)
            if has_more then
                local last = inst.next_query_player_record_block_index
                inst.next_query_player_record_block_index = last and (last + 1) or 1
            else
                -- all of the existing records are received, 
                -- we just need to receive the updated reocrds now
                inst.next_query_player_record_block_index = nil
            end
        end, TheWorld)

        if TheWorld.ismastersim then
            --  server side of player_classified

            local recorder = TheWorld.shard.components.shard_serverinforecord

            if M.MOD_OUTOFDATE_HANDLER_ENABLED then
                 
                inst:ListenForEvent('ms_modoutofdate_announcement_state_changed', function()
                    dbg('player_classified: listened ms_modoutofdate_announcement_state_changed')
                    inst.net_suppress_mod_outofdate_announcement:set(recorder.mod_out_of_date_handler:GetSuppressAnnouncement())
                end, TheWorld.shard)
                
            end
        end
    end

    inst.HasPermission = HasPermission
    inst.HasVotePermission = HasVotePermission
    inst.SetPermission = SetPermission
    inst.QueryHistoryPlayers = QueryHistoryPlayers
    inst.QuerySnapshotInformations = QuerySnapshotInformations
    inst.QueryServerData = QueryServerData
    inst.RequestToExecuteCommand = RequestToExecuteCommand
    inst.RequestToExecuteVoteCommand = RequestToExecuteVoteCommand
    inst.CommandApplyableForPlayerTarget = CommandApplyableForPlayerTarget
    
    
end)



-- what a bad idea, this will cause netvar sync problem...
-- AddPrefabPostInit('world', function(inst)
--     dbg('AddPrefabPostInit: world')
--     -- inst:DoTaskInTime(1, function()
--     --     if inst.net then
--     --         inst.net:AddComponent('serverinforecord')
--     --         dbg('added component for inst.net')
--     --     else
--     --         dbg('error: failed to add component for inst.net')
--     --     end
--     -- end)
-- end)

AddPrefabPostInit('forest_network', function(inst)
    inst:AddComponent('serverinforecord')
end)

AddPrefabPostInit('cave_network', function(inst)
    inst:AddComponent('serverinforecord')
end)

