GLOBAL.setmetatable(env,{__index=function(t,k) return GLOBAL.rawget(GLOBAL,k) end})

-- string constants
STRINGS.UI.MANAGE_TOGETHER = {
    
    -- announcement
    ANNOUNCE_PREFIX = '[Manage Together] ',

    LEVEL_PRETTY_NAME = {
        ADMIN = 'Admin',
        MODERATOR = 'Moderator',
        USER = 'Player', 
    },

    FMT_KICKED_PLAYER = '%s(%s) is kicked from the server',
    FMT_BANNED_PLAYER = '%s(%s) is banned',
    FMT_KILLED_PLAYER = '%s(%s) is killed',
    FMT_KILLBANNED_PLAYER = '%s(%s) is killed and banned',
    FMT_SENDED_SAVE_REQUEST = '%s raised a save request',
    FMT_SENDED_ROLLBACK_REQUEST = '%s raised a rollback request, to the %dth saving point:%s',
    FMT_SENDED_ROLLBACK2_REQUEST = '%s raised a rollback request, to the saving point: %s',
    FMT_ROLLBACK_BRIEF = '{day}-{season} {phase}', -- eg: Day xx-Winter Night
    FMT_SENDED_REGENERATE_WORLD_REQUEST = '%s raised a world regenerating request, the world will regenerate in %d second(s)',

    FMT_SET_NEW_PLAYER_JOINABILITY = {
        ALLOW = '%s allowed new players to join the server',
        NOT_ALLOW  = '%s forbiddened new players to join the server'
    },
    ALLOW_NEW_PLAYER_JOIN = 'allow new players to join the server', 
    NOT_ALLOW_NEW_PLAYER_JOIN = 'forbidden new players to join the server',
    DISABLE_AUTO_NEW_PLAYER_WALL = 'disable auto new player wall',
    ENABLE_AUTO_NEW_PLAYER_WALL = 'enable auto new player wall',
    FMT_SET_AUTO_NEW_PLAYER_WALL_LEVEL = ', when %s, server will allow new players to join',
    AUTO_NEW_PLAYER_WALL_LEVEL = {
        [1] = 'admin online',
        [2] = 'admin or moderator online',
        [3] = 'any player online',
        UNKNOWN = '*unknown condition*'
    },

    FMT_AUTO_NEW_PLAYER_WALL_ENABLED = '%s enabled auto new player wall, server will forbidden new players to join when online players do not satisfiy the condition',  
    FMT_AUTO_NEW_PLAYER_WALL_DISABLED = '%s disabled auto new player wall',
    FMT_AUTO_NEW_PLAYER_WALL_STATE_NOT_ALLOW = 'currently no %s or higher permission level\'s player online, automatically forbiddened new players to join the server',
    AUTO_NEW_PLAYER_WALL_STATE_ALLOW = 'automatically allowed new player to join the server',
    
    
    FMT_MAKE_ITEM_STAT_HEAD = '%s raised a inventory item statistics request', 
    FMT_MAKE_ITEM_STAT_HEAD2 = 'target player(s): %s, target item(s): %s', 
    MAKE_ITEM_STAT_OPTIONS = {
        ALL_ONLINE_PLAYERS = 'All Online Players',
        ALL_OFFLINE_PLAYERS = 'All Offline Players',
        ALL_PLAYERS = 'All Players', 
    }, 

    FMT_MAKE_ITEM_STAT_HAS_ITEM = '%s(%s)%s owns: ',
    --                       name(prefab) × counts
    FMT_SINGLE_ITEM_RESULT = '%s(%s) × %d; ',
    FMT_MAKE_ITEM_STAT_DOES_NOT_HAVE_ITEM = '%s(%s) don\'t have any target item%s;',
    MAKE_ITEM_STAT_HAS_DEEPER_CONTAINER1 = ', the player exists deeper container(s) that haven\'t been search',
    MAKE_ITEM_STAT_HAS_DEEPER_CONTAINER2 = ' exists deeper container(s) that haven\'t been search, ',
    MAKE_ITEM_STAT_DELIM = '————————————————————',

    MAKE_ITEM_STAT_FINISHED_BUT_MISSING_RESPONSE = 'inventory item statistics has finished, but missing some server shard\'s response',
    MAKE_ITEM_STAT_FINISHED = 'inventory item statistics has finished',
    ERR_REPEATED_REQUEST = 'rollback request does not be accept: a rollback action is already exists',
    ERR_DATA_INCONSISTENT = 'rollback request does not be accept: the request might not consistant with the rollback index, please try again',

    UNKNOWN_PLAYER = 'Unknown Player',
    
    FMT_DAY = 'Day %d', 
    DAY_UNKNOWN = STRINGS.UI.SERVERADMINSCREEN.DAY_UNKNOWN, 
    SEASONS = STRINGS.UI.SERVERLISTINGSCREEN.SEASONS, 
    UNKNOWN_SEASON = STRINGS.UI.SERVERLISTINGSCREEN.UNKNOWN_SEASON,
    PHASES = STRINGS.UI.SERVERLISTINGSCREEN.PHASES, 
    PHASES_SHORTTEN = STRINGS.UI.SERVERLISTINGSCREEN.PHASES,

    -- PHASES_SHORTTEN = {
    --     any idea?
    --     DAY = 'M',  (Moon)
    --     DUSK = 'D', 
    --     NIGHT = 'N',
    -- },
    UNKNOWN_PHASE = 'Unknown Phase',
    MODOUTOFDATE_SHUTDOWN_WHEN_SERVER_EMPTY = 'server will restart when nobody online, currently the warning announcement is disabled',
    MODOUTOFDATE_SUPPRESSED_ANNOUNCEMENT = 'mod out of date warning is disabled',
    MODOUTOFDATE_REVOTE = 'mod out of date warning is disabled, vote will be start again in %d minute(s)',

    -- vote related strings
    VOTE = {
        FMT_START = '%s started a vote: %s?',
        FAILED_TO_START = 'failed to start a vote',
        -- only some of the command to vote has there's strings
        KICK = {
            -- for vote beginning announcement
            FMT_ANNOUNCE = 'should we kick %s',
            -- for vote result announcement
            -- FMT_NAME = ''
            -- for vote dialog
            TITLE = 'should we kick the player?'
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
        ROLLBACK_OLD = {
            FMT_ANNOUNCE = 'should we rollback to %s',
            TITLE = STRINGS.UI.BUILTINCOMMANDS.ROLLBACK.VOTETITLEFMT
        },
        ROLLBACK = {
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
        SET_NEW_PLAYER_JOINABILITY = {
            FMT_ANNOUNCE = 'should we %s',
            TITLE = 'should we modify new player connection setting?'
        },
        SET_AUTO_NEW_PLAYER_WALL = {
            FMT_ANNOUNCE = 'should we %s',
            TITLE = 'should we modify auto new player wall setting?'
        },
        MAKE_ITEM_STAT_IN_PLAYER_INVENTORIES = {
            FMT_ANNOUNCE = 'should we make a statistics for %s for these items: %s',
            TITLE = 'should we execute a inventory item statistics?'
        },
        MODOUTOFDATE = {
            FMT_ANNOUNCE = 'server mod is out of date, should we do something?', 
            TITLE = 'server mod is out of date, should we...', 
            SHUTDOWN = 'restart the server now', 
            SHUTDOWN_WHEN_NOBODY = 'restart the server when nobody online', 
            SUPPRESS_ANNOUNCEMENT = 'only suppress the warning', 
            DELAY = 'delay the decision',
        }
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
    FMT_URL_WAB_PAGE = 'https://itty.bitty.site/#ExportedPlayerData/data:text/plain;base64,%s',
    UNKNOWN = 'unknown',

    -- server commands
    SAVE = 'Save',

    ROLLBACK = 'Rollback',
    FMT_ROLLBACK_TO = 'rollback to %s',
    ERR_ROLLBACK_TITLE_BAD_INDEX = 'wrong rollback index',
    ERR_ROLLBACK_DESC_BAD_INDEX = 'this slot is not valid, please check it again',
    ROLLBACK_SPINNER_NEWEST = '(Most Recent)',
    ROLLBACK_SPINNER_SLOT_NEW_CREATED = 'this snapshot is just created(<30s)',
    ROLLBACK_SPINNER_EMPTY = 'Empty',
    FMT_ROLLBACK_SPINNER_BRIEF = '{day}-{season} {phase}', -- eg: Day xx-Winter Night

    REGENERATE_WORLD = 'Regengerate World',
    REGENERATE_WORLD_DESC = 'distory EVERYTHING of the world, and then generate a new world',
    REGENERATE_WORLD_REQUIRE_SERVER_NAME = 'server name',
    VOTE = 'Start a Vote...',
    NO_VOTE = 'Cancel to Start a Vote',
    START_A_VOTE = 'Start a Vote: ',
    MAKE_ITEM_STAT_IN_PLAYER_INVENTORIES = 'Execute Item Statistics',
    MAKE_ITEM_STAT_DESC = 'Search and make a Statistics for appointted items in all of the online/offline player\'s inventory\nitem name or its prefab name are both accepted',
    MAKE_ITEM_STAT_OPTIONS = STRINGS.UI.MANAGE_TOGETHER.MAKE_ITEM_STAT_OPTIONS,
    MAKE_ITEM_STAT_TEXT_PROMPT = 'cutgrass,yellowstaff',
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

    SET_NEW_PLAYER_JOINABILITY_TITLE = 'modify new player joinability',
    -- TODO FMT_SET_NEW_PLAYER_JOINABILITY_DESC = '%s, %s\nnew player ...',
    FMT_SET_NEW_PLAYER_JOINABILITY_DESC = '%s, %s\nif auto new player wall is enabled, server will allow new players to join when 「%s」, otherwise server will forbidden new players to join',
    
    -- button hovertext
    SET_NEW_PLAYER_JOINABILITY = {
        ALLOW_ALL_PLAYER = 'forbidden new players to join the server\ncurrently allow new players to join', 
        ALLOW_OLD_PLAYER = 'allow new players to join the server\nncurrently not allow new players to join', 
    },
    -- popup dialog button/desc
    DIALOG_SET_NEW_PLAYER_JOINABILITY = {
        ALLOW_ALL_PLAYER = 'currently allowed new players to join', 
        ALLOW_OLD_PLAYER = 'currently forbiddened new players to join',
    
        JOINABILITY_BUTTON = {
            -- button action inverts the current state
            ALLOW_ALL_PLAYER = 'forbidden new players', 
            ALLOW_OLD_PLAYER = 'allow new players', 
        },

        -- auto new player wall
        WALL_ENABLED = 'auto new player wall is enabled',
        WALL_DISABLED = 'auto new player wall is disabled',

        WALL_BUTTON = {
            -- button action inverts the current state
            WALL_ENABLED = 'disable wall',
            WALL_DISABLED = 'enable wall',
        },

        WALL_LEVEL = {
            ADMIN = 'admin online',
            MODERATOR = 'admin/moderator online',
            USER = 'any player online',
            UNKNOWN = '*unknown condition'
        }
    },
    AUTO_NEW_PLAYER_WALL_PROBALY_ENABLED = '\nyour setting may be covered while server player state changes if server enabled auto new player filter',
    COMFIRM_DIALOG_OFFLINE_PLAYER_DESC = '\nthe target player is offline currently, for some commands, server will temporarily load the player and execute the command',

    FMT_CONFIRM_DIALOG_TITLE = '%s the player', 
    FMT_CONFIRM_DIALOG_DESC  = 'execute command to player %s, command is: %s%s', -- player name, action, COMFIRM_DIALOG_OFFLINE_PLAYER_DESC or ''
    FMT_INPUT_TO_CONFIRM = 'input %s to confirm %s',

    LOAD_MORE_HISTORY_PLAYERS = 'Load more player records...',
    FMT_SERVER_WILL_SHUTDOWN = 'server will shutdown in %d second(s), reason: %s',
    SHUTDOWN_REASON_UPDATE_MOD = 'restart and update mods'
}