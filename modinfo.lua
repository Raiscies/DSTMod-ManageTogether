
-- option enum constants 
local NO, YES, VOTE_ONLY_AND_MAJORITY_YES, VOTE_ONLY_AND_UNANIMOUS_YES = 0, 1, 2, 3

default_permission_configs = {
	moderator_save = YES,
	moderator_rollback = YES,
	moderator_kick = YES,
	moderator_kill = VOTE_ONLY_AND_MAJORITY_YES,
	moderator_ban = VOTE_ONLY_AND_MAJORITY_YES,
	moderator_killban = VOTE_ONLY_AND_MAJORITY_YES,
	moderator_add_moderator = VOTE_ONLY_AND_UNANIMOUS_YES,
	moderator_remove_moderator = VOTE_ONLY_AND_UNANIMOUS_YES,
	moderator_regenerate_world = NO,
	moderator_set_new_player_joinability = VOTE_ONLY_AND_MAJORITY_YES,
	moderator_make_item_stat_in_player_inventories = VOTE_ONLY_AND_MAJORITY_YES,
}

if LOAD_FOR_DEFAULT_PERMISSION_CONFIG then
	return
end


local trans = ChooseTranslationTable({
	{
		name = '共同管理-历史玩家信息(GUI)',
		description = [[
通过GUI管理你的服务器.
在(默认)按住Tab打开的在线玩家信息窗口中, 管理员或者监督员的窗口左上角会出现一个打开历史玩家记录窗口的按钮,
点击打开GUI, 可以通过各种按钮管理服务器和在线或离线的玩家;
大部分命令都可以作用于离线玩家;
部分设置如果没有你想要的选项, 请到存档的模组配置文件中修改.

* 如果模组没有记录到一个玩家的信息, 那么模组将不能对该玩家进行操作. 
	例如在一个已存在的存档中途启用本模组, 那么在启用本模组之前曾加入过服务器的玩家将不会被记录到.
	在启用模组之后玩家再加入服务器, 该玩家就会被成功记录.
* 监督员投票选项中的'一致同意'指没有投票反对的玩家, 但是允许弃权.
		]],
		options = {
			yes = '是', 
			no = '否',
			disabled = '禁用', 
			vote_only_and_majority_yes = '仅允许发起投票(多数同意)',
			vote_only_and_unanimous_yes = '仅允许发起投票(一致同意)',
			vote_only_detail = '',
			head_title = '通用选项',
			language = {
				label = '语言/Language',  	
			},
			reserve_moderator_data_while_world_regen = {
				label = '世界重置时保留监督员数据', 
				hover = '当前世界的监督员在世界重置后依旧保留他们的权限, 而非重置为普通玩家'
			},
			minimap_tips_for_killed_player = {
				label = '提示玩家死亡位置', 
				hover = '在使用命令杀死玩家时在地图上短暂地显示玩家死亡位置(信号弹标志)\n需要目标玩家与自己在同一世界才能显示'
			},
			vote_min_passed_count = {
				label = '投票通过最低所需要的同意玩家人数', 
				hover = '如果同意的玩家总人数低于该指定值, 那么投票无论如何都不会通过, 并且若当前在线的玩家总人数已经不满足该条件, 那么投票将不会被发起',
				any = '任意'
			},
			cleaner_item_stat_announcement = {
				label = '干净的物品栏统计公告',
				hover = '不公告未搜索出任何目标物品的玩家, 使聊天栏更干净清晰一些'
			},
			moderator_title = '监督员可用命令', 
			moderator_save     = { label = '允许监督员存档' }, 
			moderator_rollback = { label = '允许监督员回档' },
			moderator_kick     = { label = '允许监督员踢出玩家', hover = '只有权限低于监督员的玩家才能被踢出' }, 
			moderator_kill     = { label = '允许监督员杀死玩家', hover = '只有权限低于监督员的玩家才能被杀死' },
			moderator_ban      = { label = '允许监督员封禁玩家', hover = '只有权限低于监督员的玩家才能被封禁' },
			moderator_killban  = { label = '允许监督员杀死并封禁玩家', hover = '只有权限低于监督员的玩家才能被杀死并封禁' }, 
			moderator_add_moderator = {label = '允许监督员添加其它玩家为监督员' },
			moderator_remove_moderator = {label = '允许监督员移除其他监督员的权限' }, 
			moderator_regenerate_world = {label = '允许监督员重新生成世界' },
			moderator_set_new_player_joinability = {label = '允许监督员设置新玩家是否可加入', hover = '如果启用了新玩家连接性自动设置, 则执行的命令将于在线玩家状态改变时被覆盖' }, 
			moderator_make_item_stat_in_player_inventories = {label = '允许监督员执行物品栏单项物品统计'},
			auto_control_title = '自动控制选项', 
			user_elevate_in_age = {
				label = '老玩家自动添加为监督员',
				hover = '存活天数大于等于指定天数的玩家被添加为监督员, 0天表示任何加入的新玩家都会自动添加为监督员',
				day = '天'
			},
			auto_new_player_wall_enabled = {
				label = '启用新玩家连接性自动设置', 
				hover = '当在线玩家中不存在指定或更高权限的玩家时自动禁止新玩家加入, 反之允许新玩家加入\n新玩家指未曾加入过服务器的玩家, 曾加入过服务器的玩家不受限制' 
			},
			auto_new_player_wall_min_level = {
				label = '新玩家连接性自动设置的条件',
				hover = '当在线玩家中不存在选项中的权限或更高权限的玩家时禁止新玩家加入, 反之允许新玩家加入', 
				admin = '管理员不在线时',
				moderator = '监督员/管理员都不在线时',
				user = '任意玩家都不在线时',
			},
			others_title = '其它',
			debug = {
				label = '开启调试'
			}
		}
	},
	en = {
		name = 'Manage Together-History Player Information(GUI)',
		description = [[
Manage your server by GUI screen.
press scoreboard key(Tab by default) to open scoreboard, if you're a admin or moderator, 
there will be a button on the left top side of scoreboard screen, click it to open the history player record screen.
you can manage server and online/offline player in this screen by using command buttons.
most of the commands are available applying to offline player.

* 'Vote' options of the moderator config means moderator can start a vote, but is not allowed to execute command directly. 
		]],
		options = {
			yes = 'Yes', 
			no = 'No',
			disabled = 'Disabled',
			vote_only_and_majority_yes = 'Vote(Majority Yes)',
			vote_only_and_unanimous_yes = 'Vote(Unanimous Yes)',
			vote_only_detail = '',
			head_title = 'General',
			language = {
				label = '语言/Language', 
				hover = 'English translation is not complete',
			},
			reserve_moderator_data_while_world_regen = {
				label = 'reserve moderator data while reset', 
				hover = 'reserve moderator\'s permission while a world reseting, but not reset there permission to normal player'
			},
			minimap_tips_for_killed_player = {
				label = 'hint player position of being killed', 
				hover = '在使用命令杀死玩家时在地图上短暂地显示玩家死亡位置(信号弹标志)\n需要目标玩家与自己在同一世界才能显示'
			},
			vote_min_passed_count = {
				label = 'minimum player number of agree a vote ', 
				hover = '如果同意的玩家总人数低于该指定值, 那么投票无论如何都不会通过, 并且若当前在线的玩家总人数已经不满足该条件, 那么投票将不会被发起',
				any = 'Any'
			},
			cleaner_item_stat_announcement = {
				label = 'cleaner item stat announcement',
				hover = '不公告未搜索出任何物品的玩家, 使聊天栏更干净清晰一些'
			},
			moderator_title = 'Moderator Commands', 
			moderator_save     = { label = 'save' }, 
			moderator_rollback = { label = 'rollback', hover = '投票中的一致同意指没有投票反对的玩家, 但是允许弃权' },
			moderator_kick     = { label = 'kick', hover = '只有权限低于监督员的玩家才能被踢出\n投票中的一致同意指没有投票反对的玩家, 但是允许弃权'}, 
			moderator_kill     = { label = 'kill', hover = '只有权限低于监督员的玩家才能被杀死\n投票中的一致同意指没有投票反对的玩家, 但是允许弃权' },
			moderator_ban      = { label = 'ban', hover = '只有权限低于监督员的玩家才能被封禁\n投票中的一致同意指没有投票反对的玩家, 但是允许弃权' },
			moderator_killban  = { label = 'kill-ban', hover = '只有权限低于监督员的玩家才能被杀死并封禁\n投票中的一致同意指没有投票反对的玩家, 但是允许弃权' }, 
			moderator_add_moderator = {label = 'add another player to be moderator', hover = '投票中的一致同意指没有投票反对的玩家, 但是允许弃权' },
			moderator_remove_moderator = {label = 'remove another player\'s permission', hover = '投票中的一致同意指没有投票反对的玩家, 但是允许弃权' }, 
			moderator_regenerate_world = {label = 'regenerate world', hover = '投票中的一致同意指没有投票反对的玩家, 但是允许弃权' },
			moderator_set_new_player_joinability = {label = 'set new player joinability', hover = '如果启用了新玩家过滤器, 则执行的命令将于在线玩家状态改变时被覆盖' }, 
			moderator_make_item_stat_in_player_inventories = {label = 'make item statistics'},
			auto_control_title = 'Automatic Controls', 
			user_elevate_in_age = {
				label = 'auto add old player to be moderator',
				hover = 'the old player whose alive days is greater or equal then appointed days will be automatically add to moderator',
				day = 'Day(s)'
			},
			auto_new_player_wall_enabled = {
				label = '启用新玩家过滤器', 
				hover = '当在线玩家中不存在指定或更高权限的玩家时禁止新玩家加入, 反之允许新玩家加入\n新玩家指未曾加入过服务器的玩家, 曾加入过服务器的玩家不受限制' 
			},
			auto_new_player_wall_min_level = {
				label = '新玩家过滤器的条件',
				hover = '当在线玩家中不存在选项中的权限或更高权限的玩家时禁止新玩家加入, 反之允许新玩家加入', 
				admin = '管理员不在线时',
				moderator = '监督员和管理员都不在线时',
				user = '任意玩家都不在线时',
			},
			others_title = 'Others',
			debug = {
				label = 'Enable Debug Mode'
			}
		}
	}
})

local function opt(name, subfield, fallback)
	return name and trans.options[name] and trans.options[name][subfield] or fallback
end
local function opt_label(name) return opt(name, 'label', '') end
local function opt_hover(name) return opt(name, 'hover', '') end

local function option(name, label, hover, selections, default_selection)
	return {
		name = name, 
		label = label or opt_label(name), 
		hover = hover or opt_hover(name), 
		options = selections,
		default = default_selection or selections[1].data
	}
end
local function title(field_name, label)
	if trans.options[field_name] and not trans.options[field_name].label then
		-- assume trans.options[field_name] is a string 
		return {
			name = '', 
			label = trans.options[field_name] or label or '', 
			options = {{description = '', data = 0}}, 
			default = 0
		}
	else
		return {
			name = '', -- name param is only for indexing
			label = label or opt(name, 'label'),
			options = {{description = '', data = 0}}, 
			default = 0
		}
	end
	
end



local function binary_option(name, default_selection, label, hover)
	if default_selection == nil then	
		default_selection = default_permission_configs[name]
	end
	
	-- handle boolean input	
	if default_selection == nil or default_selection == false then
		default_selection = NO
	elseif default_selection == true then
		default_selection = YES
	end

	return {
		name = name, 
		label = label or opt_label(name), 
		hover = hover or opt_hover(name), 
		options = {
			{description = opt(name, 'yes', trans.options.yes), data = YES}, 
			{description = opt(name, 'no', trans.options.no),  data = NO}
		},
		default = default_selection
	}
end

local function moderator_option(name, label, hover, disable_yes_option)
	-- if default_selection == nil then default_selection = NO end
	default_selection = default_permission_configs[name] or NO
	local options = {
		{description = opt(name, 'vote_only_and_majority_yes', trans.options.vote_only_and_majority_yes), data = VOTE_ONLY_AND_MAJORITY_YES},
		{description = opt(name, 'vote_only_and_unanimous_yes', trans.options.vote_only_and_unanimous_yes), data = VOTE_ONLY_AND_UNANIMOUS_YES},
		{description = opt(name, 'no', trans.options.no),  data = NO}
	}
	if not disable_yes_option then
		options[4] = {description = opt(name, 'yes', trans.options.yes), data = YES}
	end 
	return {
		name = name, 
		label = label or opt_label(name), 
		hover = hover or opt_hover(name), 
		options = options,
		default = default_selection
	}
end

name = trans.name
description = trans.description
author = 'Raiscies'
version = '0.3.3'

forumthread = ''

api_version = 10

all_clients_require_mod = true
client_only_mod = false
dst_compatible = true

icon_atlas = 'modicon.xml'
icon = 'modicon.tex'

configuration_options = {
	title('head_title'),
	option('language', nil, nil, {
		{description = '中文', data = 'zh'}, 
		{description = 'English', data = 'en'}
	}, 'zh'),
	binary_option('reserve_moderator_data_while_world_regen', YES),
	binary_option('minimap_tips_for_killed_player', YES),
	option('vote_min_passed_count', nil, nil, {
		{description = trans.options.vote_min_passed_count.any, data = 0},
		{description = '1', data = 1},
		{description = '2', data = 2},
		{description = '3', data = 3},
		{description = '4', data = 4},
		{description = '5', data = 5},
		{description = '6', data = 6},
		{description = '7', data = 7},
		{description = '8', data = 8},
		{description = '9', data = 9},
		{description = '10', data = 10},
		{description = '11', data = 11},
		{description = '12', data = 12},
	}, 3),
	binary_option('cleaner_item_stat_announcement', NO),
	title('moderator_title'),
	binary_option('moderator_save'), 
	moderator_option('moderator_rollback'), 
	moderator_option('moderator_kick'),
	moderator_option('moderator_kill'), 
	moderator_option('moderator_ban'), 
	moderator_option('moderator_killban'),
	moderator_option('moderator_add_moderator', nil, nil, true), 
	moderator_option('moderator_remove_moderator', nil, nil, true),
	moderator_option('moderator_regenerate_world'),
	moderator_option('moderator_set_new_player_joinability'),
	moderator_option('moderator_make_item_stat_in_player_inventories'),
	title('auto_control_title'), 
	option('user_elevate_in_age', nil, nil, {
		{description =          trans.options.disabled, data = -1},
		{description = '0'   .. trans.options.user_elevate_in_age.day, data = 0}, 
		{description = '3'   .. trans.options.user_elevate_in_age.day, data = 3}, 
		{description = '5'   .. trans.options.user_elevate_in_age.day, data = 5}, 
		{description = '10'  .. trans.options.user_elevate_in_age.day, data = 10}, 
		{description = '20'  .. trans.options.user_elevate_in_age.day, data = 20}, 
		{description = '30'  .. trans.options.user_elevate_in_age.day, data = 30}, 
		{description = '50'  .. trans.options.user_elevate_in_age.day, data = 50}, 
		{description = '70'  .. trans.options.user_elevate_in_age.day, data = 70}, 
		{description = '100' .. trans.options.user_elevate_in_age.day, data = 100}, 
		{description = '150' .. trans.options.user_elevate_in_age.day, data = 150}, 
		{description = '200' .. trans.options.user_elevate_in_age.day, data = 200},
		{description = '300' .. trans.options.user_elevate_in_age.day, data = 300}, 
		{description = '500' .. trans.options.user_elevate_in_age.day, data = 500},
		{description = '1000' .. trans.options.user_elevate_in_age.day, data = 1000}
	}),
	binary_option('auto_new_player_wall_enabled', NO), 
	option('auto_new_player_wall_min_level', nil, nil, {
		{description = trans.options.auto_new_player_wall_min_level.user, data = 'user'},
		{description = trans.options.auto_new_player_wall_min_level.moderator, data = 'moderator'},
		{description = trans.options.auto_new_player_wall_min_level.admin, data = 'admin'},
	}, 'moderator'),
	title('others_title'),
	binary_option('debug', NO), 
}
