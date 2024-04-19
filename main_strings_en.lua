GLOBAL.setmetatable(env,{__index=function(t,k) return GLOBAL.rawget(GLOBAL,k) end})

-- string constants
STRINGS.UI.MANAGE_TOGETHER = {
    
    -- announcement
    ANNOUNCE_PREFIX = '[Manage Together] ',
    FMT_KICKED_PLAYER = '%s(%s) is kicked from the server',
    FMT_BANNED_PLAYER = '%s(%s) is banned',
    FMT_KILLED_PLAYER = '%s(%s) is killed',
    FMT_KILLBANNED_PLAYER = '%s(%s) is killed and banned',
    FMT_SENDED_SAVE_REQUEST = '%s raised a save request',
    FMT_SENDED_ROLLBACK_REQUEST = '%s raised a rollback request, to the %dth saving point:%s',
    FMT_SENDED_ROLLBACK2_REQUEST = '%s raised a rollback request, to the saving point: %s',
    FMT_SENDED_REGENERATE_WORLD_REQUEST = '%s raised a world regenerating request, the world will regenerate in %d second(s)',
    ERR_REPEATED_REQUEST = 'rollback request does not be accept: a rollback action is already exists',
    ERR_DATA_INCONSISTENT = 'rollback request does not be accept: the request might not consistant with the rollback index, please try again',

    UNKNOWN_PLAYER = 'Unknown Player',
    
    FMT_DAY = 'Day %d', 
    DAY_UNKNOWN = STRINGS.UI.SERVERADMINSCREEN.DAY_UNKNOWN, 
    SEASONS = STRINGS.UI.SERVERLISTINGSCREEN.SEASONS, 
    UNKNOWN_SEASON = STRINGS.UI.SERVERLISTINGSCREEN.UNKNOWN_SEASON,

    -- vote related strings
    VOTE = {
        FMT_START = '%s started a vote: %s?',
        -- only some of the command to vote has there's strings 
        KICK = {
            -- for vote beginning announcement
            FMT_ANNOUNCE = 'should we kick %s',
            -- for vote result announcement
            -- FMT_NAME = ''
            -- for vote dialog
            FMT_TITLE = 'should we kick the player?'
        },
        BAN = {
            FMT_ANNOUNCE = 'should we ban %s',
            TITLE = 'should we ban the player?',
        },
        KILL = {
            FMT_ANNOUNCE = 'should we kill %s',
            TITLE = 'should we kill the player?'
        },
        KILLBAN = {
            FMT_ANNOUNCE = 'should we kill and ban %s',
            TITLE = 'should we kill and ban the player?'
        }, 
        ROLLBACK = {
            FMT_ANNOUNCE = 'should we rollback to %s',
            TITLE = STRINGS.UI.BUILTINCOMMANDS.ROLLBACK.VOTETITLEFMT
        },
        ROLLBACK_TO = {
            FMT_ANNOUNCE = 'should we rollback to %s',
            TITLE = STRINGS.UI.BUILTINCOMMANDS.ROLLBACK.VOTETITLEFMT
        },
        REGENERATE_WORLD = {
            FMT_ANNOUNCE = 'should we regenerate the world',
            TITLE = STRINGS.UI.BUILTINCOMMANDS.REGENERATE.VOTETITLEFMT
        },
        ADD_MODERATOR = {
            FMT_ANNOUNCE = 'should we elevate %s to be a moderator',
            TITLE = 'should we elevate the player to be a moderator?'
        },        
        REMOVE_MODERATOR = {
            FMT_ANNOUNCE = 'should we remove %s\'s moderator permission',
            TITLE = 'should we remove the player\'s moderator permission?'
        },
    }
}

STRINGS.UI.HISTORYPLAYERSCREEN = {
    ADMIN = 'Admin',
    MODERATOR = 'Moderator', 
    TOGGLE_BUTTON_TEXT = {
        'View History Players', 
        'View Online Players',
    },
    TITLE = 'History Player Record',
    FMT_PLAYER_NUMBER = '%d/%s/%d',
    FMT_PLAYER_NUMBER_HOVER = 'Online %d/Max Can Online %s/All %d', 

    -- this website does not accept \n to return line, use <br> instead
    FMT_TEXT_WEB_PAGE = 'Name: %s<br>User ID: %s<br>Steam ID: %s',
    FMT_URL_WAB_PAGE = 'https://itty.bitty.site/#(Refresh_If_Blank_Page)DumpedPlayerData/data:text/plain;base64,%s',
    UNKNOWN = 'unknown',

    -- server commands
    SAVE = 'Save',

    ROLLBACK = 'Rollback',
    FMT_ROLLBACK_TO = 'rollback to %s',
    ERR_ROLLBACK_TITLE_BAD_INDEX = 'wrong rollback index',
    ERR_ROLLBACK_DESC_BAD_INDEX = 'this slot is not valid, please check it again',
    ROLLBACK_SPINNER_NEWEST = '(Most Recent)',
    ROLLBACK_SPINNER_NEWEST_SLOT_INVALID = 'this snapshot is disabled due to a very recent saving time(<30s)',
    ROLLBACK_SPINNER_EMPTY = 'Empty',
    REGENERATE_WORLD = 'regengerate world',
    REGENERATE_WORLD_DESC = 'distory EVERYTHING of the world, and then generate a new world',
    REGENERATE_WORLD_REQUIRE_SERVER_NAME = 'server name',
    VOTE = 'Start a Vote...',
    NO_VOTE = 'Cancel to Start a Vote',
    START_A_VOTE = 'Start a Vote: ',
    REFRESH_RECORDS = 'Update Data',
    REFRESH_RECORDS_DESC = 'most of the situation you don\'t need to click this button, but if you found something wrong about display, just try it', 
    -- player commands
    VIEWPROFILE = STRINGS.UI.PLAYERSTATUSSCREEN.VIEWPROFILE, 
    KICK = STRINGS.UI.PLAYERSTATUSSCREEN.KICK, 
    VIEWSTEAMPROFILE = 'View Steam Profile', 
    KILL = 'Kill', 
    BAN = STRINGS.UI.PLAYERSTATUSSCREEN.BAN,
    KILLBAN = 'Kill and Ban',
    ADD_MODERATOR = 'Add Moderator', 
    REMOVE_MODERATOR = 'Remove Moderator',

    COMFIRM_DIALOG_OFFLINE_PLAYER_DESC = '\nthe target player is offline currently, for some commands, server will temporarily load the player and execute the command',

    FMT_CONFIRM_DIALOG_TITLE = '%s the player', 
    FMT_CONFIRM_DIALOG_DESC  = 'execute command to player %s, command is: %s%s', -- player name, action, COMFIRM_DIALOG_OFFLINE_PLAYER_DESC or ''
    FMT_INPUT_TO_CONFIRM = 'input %s to confirm %s'
}