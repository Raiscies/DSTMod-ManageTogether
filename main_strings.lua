GLOBAL.setmetatable(env,{__index=function(t,k) return GLOBAL.rawget(GLOBAL,k) end})

-- string constants
STRINGS.UI.MANAGE_TOGETHER_DEFAULT = {
    
    -- announcement
    ANNOUNCE_PREFIX = '[共同管理] ',

    -- currently just for auto new player wall state changed
    LEVEL_PRETTY_NAME = {
        ADMIN = '管理员',
        MODERATOR = '监督员',
        USER = '普通玩家', 
    },

    FMT_KICKED_PLAYER = '%s(%s)已被踢出服务器',
    FMT_BANNED_PLAYER = '%s(%s)已被封禁',
    FMT_KILLED_PLAYER = '%s(%s)已被杀死',
    FMT_KILLBANNED_PLAYER = '%s(%s)已被杀死并封禁',
    FMT_SENDED_SAVE_REQUEST = '%s发起了存档请求',
    FMT_SENDED_ROLLBACK_REQUEST = '%s发起了回档请求, 到第%d个存档点:%s',
    FMT_SENDED_ROLLBACK2_REQUEST = '%s发起了到存档点:%s的回档请求',
    FMT_SENDED_REGENERATE_WORLD_REQUEST = '%s发起了世界重置请求, 世界将在%d秒后重新生成',

    FMT_SET_NEW_PLAYER_JOINABILITY = {
        ALLOW = '%s已允许新玩家加入服务器',
        NOT_ALLOW  = '%s已禁止新玩家加入服务器'
    },
    ALLOW_NEW_PLAYER_JOIN = '允许新玩家加入服务器', 
    NOT_ALLOW_NEW_PLAYER_JOIN = '禁止新玩家加入服务器',

    FMT_AUTO_NEW_PLAYER_WALL_ENABLED = '%s开启了新玩家自动过滤器, 当在线玩家不满足要求时服务器会禁止新玩家加入',  
    FMT_AUTO_NEW_PLAYER_WALL_DISABLED = '%s关闭了新玩家自动过滤器',
    FMT_AUTO_NEW_PLAYER_WALL_STATE_NOT_ALLOW = '服务器当前没有%s或更高权限的玩家在线, 已自动禁止新玩家加入服务器',
    AUTO_NEW_PLAYER_WALL_STATE_ALLOW = '已自动允许新玩家加入服务器',
    
    
    FMT_MAKE_ITEM_STAT_HEAD = '%s发起了物品栏统计请求', 
    FMT_MAKE_ITEM_STAT_HEAD2 = '目标玩家: %s, 目标物品: %s', 
    MAKE_ITEM_STAT_OPTIONS = {
        ALL_ONLINE_PLAYERS = '所有在线玩家',
        ALL_OFFLINE_PLAYERS = '所有离线玩家',
        ALL_PLAYERS = '所有玩家', 
    }, 
    --                           player(userid)[存在..., ]拥有: 
    FMT_MAKE_ITEM_STAT_HAS_ITEM = '%s(%s)%s拥有: ',
    --                       name(prefab) × counts
    FMT_SINGLE_ITEM_RESULT = '%s(%s) × %d; ',
    FMT_MAKE_ITEM_STAT_DOES_NOT_HAVE_ITEM = '%s(%s)无任何目标物品%s;',
    MAKE_ITEM_STAT_HAS_DEEPER_CONTAINER1 = ', 该玩家存在未执行统计的深层容器',
    MAKE_ITEM_STAT_HAS_DEEPER_CONTAINER2 = '存在未执行统计的深层容器, ',
    MAKE_ITEM_STAT_DELIM = '',
    -- unused: MAKE_ITEM_STAT_END = '物品栏统计结束',
    ERR_REPEATED_REQUEST = '回档请求未响应: 存在正在进行的回档操作',
    ERR_DATA_INCONSISTENT = '回档请求未响应: 请求与快照索引可能不一致, 请重试',

    UNKNOWN_PLAYER = '未知玩家',
    
    FMT_DAY = '第%d天', 
    DAY_UNKNOWN = STRINGS.UI.SERVERADMINSCREEN.DAY_UNKNOWN, 
    SEASONS = STRINGS.UI.SERVERLISTINGSCREEN.SEASONS, 
    UNKNOWN_SEASON = STRINGS.UI.SERVERLISTINGSCREEN.UNKNOWN_SEASON,

    -- vote related strings
    VOTE = {
        FMT_START = '%s 发起了一场投票: %s?',
        FAILED_TO_START = '发起投票失败',
        -- only some of the command to vote has there's strings 
        KICK = {
            -- for vote beginning announcement
            FMT_ANNOUNCE = '是否踢出%s',
            -- for vote result announcement
            -- FMT_NAME = ''
            -- for vote dialog
            TITLE = '我们应该踢掉该玩家吗?' -- vote title is not formattable
        },
        BAN = {
            FMT_ANNOUNCE = '是否封禁%s',
            TITLE = '我们应该封禁该玩家吗?',
        },
        KILL = {
            FMT_ANNOUNCE = '是否杀死%s',
            TITLE = '我们应该杀死该玩家吗?'
        },
        KILLBAN = {
            FMT_ANNOUNCE = '是否杀死并封禁%s',
            TITLE = '我们应该杀死并封禁该玩家吗?'
        }, 
        ROLLBACK_OLD = {
            FMT_ANNOUNCE = '是否回档到%s',
            TITLE = STRINGS.UI.BUILTINCOMMANDS.ROLLBACK.VOTETITLEFMT
        },
        ROLLBACK = {
            FMT_ANNOUNCE = '是否回档到%s',
            TITLE = STRINGS.UI.BUILTINCOMMANDS.ROLLBACK.VOTETITLEFMT
        },
        REGENERATE_WORLD = {
            FMT_ANNOUNCE = '是否重新生成世界',
            TITLE = STRINGS.UI.BUILTINCOMMANDS.REGENERATE.VOTETITLEFMT
        },
        ADD_MODERATOR = {
            FMT_ANNOUNCE = '是否提升%s为监督员',
            TITLE = '我们应该提升该玩家为监督员吗?'
        },        
        REMOVE_MODERATOR = {
            FMT_ANNOUNCE = '是否移除%s的监督员身份',
            TITLE = '我们应该移除该玩家的监督员身份吗?'
        },
        SET_NEW_PLAYER_JOINABILITY = {
            FMT_ANNOUNCE = '是否%s',
            TITLE = '我们应该修改新玩家可加入状态吗?'
        },
        MAKE_ITEM_STAT_IN_PLAYER_INVENTORIES = {
            FMT_ANNOUNCE = '是否对%s统计如下物品: %s',
            TITLE = '我们应该执行物品栏物品统计吗?'
        }
    }
}

STRINGS.UI.HISTORYPLAYERSCREEN_DEFAULT = {
    ADMIN = '管理员',
    MODERATOR = '监督员', 
    TOGGLE_BUTTON_TEXT = {
        '查看历史玩家', 
        '查看当前玩家',
    },
    TITLE = '历史玩家记录',
    FMT_PLAYER_NUMBER = '%d/%s/%d',
    FMT_PLAYER_NUMBER_HOVER = '在线%d/最多可在线%s/全部%d', 

    -- this website does not accept \n to return line, use <br> instead
    FMT_TEXT_WEB_PAGE = 'Name: %s<br>User ID: %s<br>Steam ID: %s',
    FMT_URL_WAB_PAGE = 'https://itty.bitty.site/#(页面空白请刷新)导出玩家数据/data:text/plain;base64,%s',
    UNKNOWN = 'unknown',

    -- server commands
    SAVE = '存档',

    ROLLBACK = '回档',
    FMT_ROLLBACK_TO = '回档到%s',
    ERR_ROLLBACK_TITLE_BAD_INDEX = '错误的回档索引',
    ERR_ROLLBACK_DESC_BAD_INDEX = '这个存档槽不是合法的, 请重新检查',
    ROLLBACK_SPINNER_NEWEST = '(最近)',
    ROLLBACK_SPINNER_NEWEST_SLOT_INVALID = '这个快照由于距离存档时间太近而被禁用(<30s)',
    ROLLBACK_SPINNER_EMPTY = '空',
    REGENERATE_WORLD = '重新生成世界',
    REGENERATE_WORLD_DESC = '毁掉这个世界的一切, 然后生成一个新的. ',
    REGENERATE_WORLD_REQUIRE_SERVER_NAME = '服务器名称',
    VOTE = '发起投票...',
    NO_VOTE = '取消发起投票',
    START_A_VOTE = '发起投票: ',
    MAKE_ITEM_STAT = '执行物品栏物品统计',
    MAKE_ITEM_STAT_DESC = '在所有(在线/离线)玩家的物品栏中搜索并统计指定的物品\n搜索支持当前语言的物品名和物品预制件名. ',
    MAKE_ITEM_STAT_OPTIONS = STRINGS.UI.MANAGE_TOGETHER_DEFAULT.MAKE_ITEM_STAT_OPTIONS,
    MAKE_ITEM_STAT_TEXT_PROMPT = '采下的草,yellowstaff',
    REFRESH_RECORDS = '更新数据',
    REFRESH_RECORDS_DESC = '大多数时候你并不需要点击这个按钮, 但是如果发现有些显示数据有问题, 可以点一下试试', 
    -- player commands
    VIEWPROFILE = STRINGS.UI.PLAYERSTATUSSCREEN.VIEWPROFILE, 
    KICK = STRINGS.UI.PLAYERSTATUSSCREEN.KICK, 
    VIEWSTEAMPROFILE = '查看Steam信息', 
    KILL = '杀死', 
    BAN = STRINGS.UI.PLAYERSTATUSSCREEN.BAN,
    KILLBAN = '杀死并封禁',
    ADD_MODERATOR = '添加为监督员', 
    REMOVE_MODERATOR = '移除监督员',

    SET_NEW_PLAYER_JOINABILITY_TITLE = '切换新玩家可加入状态',
    SET_NEW_PLAYER_JOINABILITY = {
        ALLOW_ALL_PLAYER = '禁止新玩家加入\n当前已允许新玩家加入', 
        ALLOW_OLD_PLAYER = '允许新玩家加入\n当前已禁止新玩家加入', 
    },
    AUTO_NEW_PLAYER_WALL_PROBALY_ENABLED = '\n新玩家指不曾加入过该服务器的玩家. 如果服务器启用了新玩家自动过滤器, 那么你的设置将可能在玩家数量变动时被覆盖',

    COMFIRM_DIALOG_OFFLINE_PLAYER_DESC = '\n目标玩家目前离线. 对于部分命令, 服务器将短暂地加载目标玩家并执行该命令',

    FMT_CONFIRM_DIALOG_TITLE = '%s玩家', 
    FMT_CONFIRM_DIALOG_DESC  = '将玩家%s %s%s',
    FMT_INPUT_TO_CONFIRM = '输入%s以确认%s',

    LOAD_MORE_HISTORY_PLAYERS = '加载更多玩家...'
}