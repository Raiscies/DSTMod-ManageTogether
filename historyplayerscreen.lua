
-- GUI - clients only
if not TheNet:GetIsClient() then return end

-- shortened aliasis

local M = GLOBAL.manage_together
local S = GLOBAL.STRINGS.UI.HISTORYPLAYERSCREEN

M.using_namespace(M, GLOBAL)

string.trim = M.trim

require 'util'
local Screen = require 'widgets/screen'
local Widget = require 'widgets/widget'
local Text = require 'widgets/text'
local TextEdit = require 'widgets/textedit'
local TextButton = require 'widgets/textbutton'
local Spinner = require 'widgets/spinner'
local spinner_lean_images = {
    arrow_left_normal = "arrow2_left.tex",
    arrow_left_over = "arrow2_left_over.tex",
    arrow_left_disabled = "arrow_left_disabled.tex",
    arrow_left_down = "arrow2_left_down.tex",
    arrow_right_normal = "arrow2_right.tex",
    arrow_right_over = "arrow2_right_over.tex",
    arrow_right_disabled = "arrow_right_disabled.tex",
    arrow_right_down = "arrow2_right_down.tex",
    bg_middle = "blank.tex",
    bg_middle_focus = "blank.tex",      -- disable on-focus background image
    bg_middle_changing = "blank.tex",
    bg_end = "blank.tex",
    bg_end_focus = "blank.tex",
    bg_end_changing = "blank.tex",
    bg_modified = "option_highlight.tex",
}

local Image = require 'widgets/image'
local ImageButton = require 'widgets/imagebutton'
local RadioButtons = require 'widgets/radiobuttons'
local PlayerBadge = require 'widgets/playerbadge'
local ScrollableList = require 'widgets/scrollablelist'

local PlayerStatusScreen = require 'screens/playerstatusscreen'

local PlayerHud = require 'screens/playerhud'
local PopupDialogScreen = require 'screens/redux/popupdialog'
local InputDialogScreen  = require 'screens/redux/inputdialog'

local VotableImageButton, VotableImageSwitch = unpack(require 'widgets/votableimagebutton')

local TEMPLATES = require('widgets/redux/templates')

local REFRESH_INTERVAL = .5

-- a flag used in sorted_userkey_list, to indicate that we need a button to load more player records 
local LIST_IS_INCOMPLETE = 0

local function GetBasePrefabFromSkin(skin)
    -- the simplist and cheapest way to get the prefab name
    return skin and string.match(skin, '^(%w+)_[%w_]+$') or nil
end

local function IsSelf(userid)
    return ThePlayer and (ThePlayer.userid == userid) or false
end

local function ExecuteOrStartVote(vote_state, cmd, ...)
    if vote_state then 
        ThePlayer.player_classified:RequestToExecuteVoteCommand(cmd, ...)
    else
        ThePlayer.player_classified:RequestToExecuteCommand(cmd, ...)
    end
end


local sorted_userkey_list

local function DoInitScreenToggleButton(screen, current_or_history_index)
    if not TheInput:ControllerAttached() then

        if screen.toggle_button == nil then
            screen.toggle_button = screen.root:AddChild(ImageButton('images/scoreboard.xml', 'more_actions_normal.tex', 'more_actions_hover.tex', 'more_actions.tex', 'more_actions.tex', nil, { .4, .4 }, { 0, 0 }))
            screen.toggle_button:SetOnClick(function()

                screen:Close()
                if current_or_history_index == 1 then
                    -- is current
                    -- toggle to history player screen now
                    -- query for history player list data from server
                    ThePlayer.player_classified:QueryServerData()
                    screen.owner.HUD:ShowHistoryPlayerScreeen(true)
                else
                    -- is history
                    -- toggle to current player screen now
                    screen.owner.HUD:ShowPlayerStatusScreen(true)
                
                end

            end)
        end
        screen.toggle_button:SetHoverText(
            S.TOGGLE_BUTTON_TEXT[current_or_history_index],
            { font = GLOBAL.NEWFONT_OUTLINE, offset_x = 0, offset_y = 38, colour = GLOBAL.WHITE }
        )
    elseif screen.toggle_button ~= nil then
        screen.toggle_button:Kill()
        screen.toggle_button = nil
    end

    local servermenux = -329
    local servermenubtnoffs = 24
    local button_x = servermenux
    if current_or_history_index == 1 then
        button_x = button_x + (screen.servermenunumbtns > 1 and servermenubtnoffs * 4 or servermenubtnoffs * 2)
    end

    if screen.toggle_button ~= nil then
        screen.toggle_button:SetPosition(button_x, 200)
    end
end

local function PopupConfirmDialog(action_name, action_desc, callback_on_confirmed, ...)
    local args = {...}
    local button_ok_item     = {text=STRINGS.UI.PLAYERSTATUSSCREEN.OK, cb = function() TheFrontEnd:PopScreen() callback_on_confirmed(unpack(args)) end}
    local button_cancel_item = {text=STRINGS.UI.PLAYERSTATUSSCREEN.CANCEL, cb = function() TheFrontEnd:PopScreen() end}
            
    TheFrontEnd:PushScreen(
        PopupDialogScreen(
            -- name
            string.format(STRINGS.UI.COMMANDSSCREEN.CONFIRMTITLE, action_name), 
            -- text
            action_desc,
            -- buttons
            {button_ok_item, button_cancel_item}
        )
    )
end

local InputVerificationDialog = Class(InputDialogScreen, function(self, title, verify_fn, on_confirmed_fn)
    
    InputDialogScreen._ctor(self, title, {
        {
            text = STRINGS.UI.PLAYERSTATUSSCREEN.OK, 
            cb = function() 
                if self:Verify() then
                    on_confirmed_fn(self:GetText())
                    TheFrontEnd:PopScreen() 
                end
            end
        },
        {text = STRINGS.UI.PLAYERSTATUSSCREEN.CANCEL, cb = function() TheFrontEnd:PopScreen() end}
    }, true)
    self.black = self:AddChild(TEMPLATES.BackgroundTint())
    self.black:MoveToBack()

    self.verify_fn = verify_fn

    self.bg:SetPosition(0, 20)
    local width, height = self.bg:GetSize()
    self.bg:SetSize(width, 120)
    
    self.bg.actions:DisableItem(1)


    local edit_text_on_control = self.edit_text.OnControl
    self.edit_text.OnControl = function(edit, control, down)
        if self:Verify() then
            self.bg.actions:EnableItem(1)
        else
            self.bg.actions:DisableItem(1)
        end
        return edit_text_on_control(edit, control, down)
    end
end)
function InputVerificationDialog:OnControl(control, down)
    if self:Verify() then
        self.bg.actions:EnableItem(1)
    else
        self.bg.actions:DisableItem(1)
    end
    return InputVerificationDialog._base.OnControl(self, control, down)
end

function InputVerificationDialog:Verify()
    return self.verify_fn(self:GetText())
end


local ItemStatDialog = Class(InputVerificationDialog, function(self, title, desc, on_submitted)
    -- M.ToPrefabName: returns nil if the name is not valid or else returns non-nil item prefab name string
    local verify_fn = function(text)
        -- eg1: prefab1, prefab2, prefab3
        local target_prefabs = {}
        text = text:trim()
        for _, word in ipairs(text:split(',')) do
            word = word:trim()
             
            local result = ToPrefabName(word)
            if result then
                if type(result) == 'string' then
                    -- table.insert(self.the_item_prefabs, result)
                    target_prefabs[result] = true
                else
                    -- result is a table
                    for _, v in ipairs(result) do
                        target_prefabs[v] = true
                    end
                end
            else
                -- this word is bad
                return false
            end
        end
        
        self.the_item_prefabs = {}
        for prefab, _ in pairs(target_prefabs) do
            table.insert(self.the_item_prefabs, prefab)
        end
        -- self.the_item_prefabs = M.ToPrefabName(text:rtrim())
         
        return #self.the_item_prefabs ~= 0
    end
    local submitted_fn = function()
        on_submitted(self.the_item_prefabs, self.search_range)
    end
    InputVerificationDialog._ctor(self, title, verify_fn, submitted_fn)
    local width, height = self.bg:GetSize()
    self.bg:SetSize(width, 250)

    self.edit_text:SetTextPrompt(S.MAKE_ITEM_STAT_TEXT_PROMPT, {0, 0, 0, .4})
    
    self.desc_text = desc
    -- description text
    self.desc = self.proot:AddChild(Text(NEWFONT, 28))
    self.desc:SetPosition(0, 110, 0)
    self.desc:SetString(self.desc_text)
    self.desc:SetColour(1, 1, 1, 1)
    self.desc:EnableWordWrap(true)
    self.desc:SetRegionSize(500, 160)
    self.desc:SetVAlign(ANCHOR_MIDDLE)

    local radio_button_settings = {
        width = 170,
        height = 40,
        font = NEWFONT,
        font_size = 23,
        image_scale = 0.6,
        atlas = "images/ui.xml",
        on_image = "radiobutton_on.tex",
        off_image = "radiobutton_off.tex",
        normal_colour = {1, 1, 1, 1}, 
        selected_colour = {1, 1, 1, 1},
        hover_colour = {1, 1, 1, 1}
    }
    local radio_options = {
        {text = S.MAKE_ITEM_STAT_OPTIONS.ALL_ONLINE_PLAYERS,  data = 0},
        {text = S.MAKE_ITEM_STAT_OPTIONS.ALL_OFFLINE_PLAYERS, data = 1},
        {text = S.MAKE_ITEM_STAT_OPTIONS.ALL_PLAYERS,         data = 2},
    }
    self.search_range = 0
    self.search_range_radio = self.proot:AddChild(RadioButtons(radio_options,  #radio_options * 170, 40, radio_button_settings, true))
    self.search_range_radio:SetPosition(-90, 70, 0)
  
    self.search_range_radio:SetOnChangedFn(function(data)
        self.search_range = data
    end)

    -- enable item text prediction
    self.edit_text:EnableWordPrediction({width = 800, mode = 'enter', pad_y = -75})
    
    
    -- tweak the RefreshPredictions and Apply functions
    -- add a implicit 'begin' character, to help the predictor correctly apply the predictted word to the textedit
    local implicit_begin = '\0'
    local OldRefreshPredictions = self.edit_text.prediction_widget.word_predictor.RefreshPredictions
    self.edit_text.prediction_widget.word_predictor.RefreshPredictions = function(predictor, text, cursor_pos)
        OldRefreshPredictions(predictor, implicit_begin .. text, cursor_pos + 1)
    end
    self.edit_text.prediction_widget.word_predictor.Apply = function(predictor, prediction_index)
        local new_text = nil
        local new_cursor_pos = nil
        if predictor.prediction ~= nil then
            local new_word = predictor.prediction.matches[math.clamp(prediction_index or 1, 1, #predictor.prediction.matches)]

            -- no implicit_begin char in the application
            new_text = predictor.text:sub(2, predictor.prediction.start_pos) .. new_word .. ','
            new_cursor_pos = #new_text
        end

        predictor:Clear()
        return new_text, new_cursor_pos
    end
    
    local get_display_string = function(word)
        if _G.Prefabs[word] then
            -- word is a prefab string
            local name = STRINGS.NAMES[word:upper()] 
            return name and (word .. '(' .. name .. ')') or word
        else
            local prefab_names = M.LOCAL_NAME_REFERENCES[word]
            if prefab_names then
                if type(prefab_names) == 'table' then
                    prefab_names = table.concat(prefab_names, ', ')
                end
                return word .. '(' .. prefab_names .. ')'
            else
                return name
            end
        end
    end
    
    for _, dict in ipairs(M.GetItemDictionaries()) do
        self.edit_text:AddWordPredictionDictionary({
            words = dict, 
            delim = implicit_begin, 
            num_chars = 1,
            skip_pre_delim_check = true, 
            GetDisplayString = get_display_string
        })
        self.edit_text:AddWordPredictionDictionary({
            words = dict, 
            delim = ',', 
            num_chars = 1, 
            skip_pre_delim_check = true, 
            GetDisplayString = get_display_string
        })
    end

end)

function ItemStatDialog:GetItemPrefabs()
    self:Verify()
    return self.the_item_prefabs
end

local function PopupDialog(title, text)
    TheFrontEnd:PushScreen(
        PopupDialogScreen(
            -- name
            title, 
            -- text
            text,
            -- buttons
            {
                {text = STRINGS.UI.PLAYERSTATUSSCREEN.CANCEL, cb = function() TheFrontEnd:PopScreen() end}
            }
        )
    )
end

local function PopupInputConfirmDialog(action_name, required_text_tips, verify_fn, on_confirmed_fn)
    TheFrontEnd:PushScreen(InputVerificationDialog(
        -- title
        string.format(S.FMT_INPUT_TO_CONFIRM, required_text_tips, action_name),
        verify_fn, 
        on_confirmed_fn
    ))
end

local function PopupItemStatDialog(title, desc, on_submitted_fn)
    TheFrontEnd:PushScreen(ItemStatDialog(title, desc, on_submitted_fn))
end


local function CreateButtonOfServer(screen, name, img_src, close_on_clicked, command_fn)
    local button = screen[name]
    if button ~= nil and TheInput:ControllerAttached() then
        button:Kill()
        button = nil
    elseif button == nil and not TheInput:ControllerAttached() then
        if not img_src then
            img_src = {
                M.ATLAS,
                name .. '_normal.tex', 
                name .. '_hover.tex', 
                name .. '_select.tex', -- disabled.tex 
                name .. '_select.tex'
            }
        elseif type(img_src) == 'string' then
            img_src = {
                M.ATLAS,
                img_src .. '_normal.tex', 
                img_src .. '_hover.tex', 
                img_src .. '_select.tex', -- disabled.tex 
                img_src .. '_select.tex'
            }
        end
        --                                                        atlas.xml, normal.tex, hover.tex, disabled.tex             , select.tex              ,
        button = screen.root:AddChild(VotableImageButton(img_src[1], img_src[2], img_src[3], img_src[4] or img_src[2], img_src[5] or img_src[2], nil, { .4, .4 }, { 0, 0 }))
        
        -- this flag affects:
        -- hover_text
        -- onclick_fn
        button.name = name
        table.insert(screen.votable_buttons, button)

        screen[name] = button
        button:SetOnClick(function(vote_state)
            if close_on_clicked then screen:Close() end
            command_fn(vote_state)
        end)

        button:SetHoverTextAtNormal(
            S[name:upper()] or '',
            { font = GLOBAL.NEWFONT_OUTLINE, offset_x = 0, offset_y = 38, colour = GLOBAL.WHITE }
        )
        button:SetHoverTextAtVote(
            (S.START_A_VOTE .. (S[name:upper()] or ''))
        )


        screen.servermenunumbtns = screen.servermenunumbtns + 1 
        
        local cmd = M.COMMAND_ENUM[name:upper()]
        if cmd == nil or ThePlayer.player_classified:HasPermission(cmd) then
            screen.server_button_x = screen.server_button_x + screen.server_button_offset
            button:SetPosition(screen.server_button_x, 200)
            button:Show()
        elseif ThePlayer.player_classified:HasVotePermission(cmd) then
            button:EnableVote()
            screen.server_button_x = screen.server_button_x + screen.server_button_offset
            button:SetPosition(screen.server_button_x, 200)
            button:Show()
        else
            button:Hide()
        end
    end
end

local function CreateSwitchOfServer(screen, name, turned_on_name, turned_off_name, close_on_clicked, command_fn)

    local button = screen[name]
    if button ~= nil and TheInput:ControllerAttached() then
        button:Kill()
        button = nil
    elseif button == nil and not TheInput:ControllerAttached() then
        
        local on_state_res = {
            textures = {
                M.ATLAS, 
                turned_on_name .. '_normal.tex', 
                turned_on_name .. '_hover.tex', 
                turned_on_name .. '_select.tex', -- disabled.tex 
                turned_on_name .. '_select.tex', 
                nil, {.4, .4}, {0, 0}
            },
            hover_text = {
                text = M.chain_get(S, name:upper(), turned_on_name:upper()) or '',
                params = { font = GLOBAL.NEWFONT_OUTLINE, offset_x = 0, offset_y = 38, colour = GLOBAL.WHITE }
            },
            hover_text_at_vote = {
                text = S.START_A_VOTE .. (M.chain_get(S, name:upper(), turned_on_name:upper()) or ''),
                params = { font = GLOBAL.NEWFONT_OUTLINE, offset_x = 0, offset_y = 38, colour = GLOBAL.WHITE }    
            }
        }
        local off_state_res = {
            textures = {
                M.ATLAS, 
                turned_off_name .. '_normal.tex', 
                turned_off_name .. '_hover.tex', 
                turned_off_name .. '_select.tex', -- disabled.tex 
                turned_off_name .. '_select.tex', 
                nil, {.4, .4}, {0, 0}
            },
            hover_text = {
                text = M.chain_get(S, name:upper(), turned_off_name:upper()) or '',
                params = { font = GLOBAL.NEWFONT_OUTLINE, offset_x = 0, offset_y = 38, colour = GLOBAL.WHITE }
            },
            hover_text_at_vote = {
                text = S.START_A_VOTE .. (M.chain_get(S, name:upper(), turned_off_name:upper()) or ''),
                params = { font = GLOBAL.NEWFONT_OUTLINE, offset_x = 0, offset_y = 38, colour = GLOBAL.WHITE }    
            }
        }

        button = screen.root:AddChild(VotableImageSwitch(on_state_res, off_state_res))

        button.name = name
        table.insert(screen.votable_buttons, button)

        screen[name] = button
        button:SetOnClick(function(current_state, vote_state)
            if close_on_clicked then screen:Close() end
            command_fn(current_state, vote_state)
        end)

        screen.servermenunumbtns = screen.servermenunumbtns + 1 
        
        local cmd = M.COMMAND_ENUM[name:upper()]
        if cmd ~= nil and not ThePlayer.player_classified:HasPermission(cmd) then
            button:Hide()
            return
        end
        screen.server_button_x = screen.server_button_x + screen.server_button_offset
        button:SetPosition(screen.server_button_x, 200)
        button:Show()
        if not ThePlayer.player_classified:HasPermission(cmd) and ThePlayer.player_classified:HasVotePermission(cmd) then
            button:EnableVote()
        end
    end
end

local function DoInitServerRelatedCommnadButtons(screen)

    screen.server_button_offset = 48
    screen.server_button_x = -329

    CreateButtonOfServer(screen, 'save', nil, false, function()
        ThePlayer.player_classified:RequestToExecuteCommand(M.COMMAND_ENUM.SAVE)
    end)

    CreateButtonOfServer(screen, 'rollback', nil, false, function(vote_state)
        if screen.rollback_spinner:GetSelected().data == nil then
            PopupDialog(S.ERR_ROLLBACK_TITLE_BAD_INDEX, S.ERR_ROLLBACK_DESC_BAD_INDEX)
        else
            PopupConfirmDialog(
                vote_state and (S.START_A_VOTE .. S.ROLLBACK) or S.ROLLBACK, 
                string.format(S.FMT_ROLLBACK_TO, screen.rollback_spinner:GetSelected().text), 
                function() 
                    ExecuteOrStartVote(vote_state, M.COMMAND_ENUM.ROLLBACK, screen.recorder.snapshot_info[screen.rollback_spinner:GetSelected().data].snapshot_id)
                end
            )
        end
    end)
    screen:DoInitRollbackSpinner()

    CreateButtonOfServer(screen, 'regenerate_world', nil, true, function(vote_state)
        PopupConfirmDialog(
            vote_state and (S.START_A_VOTE .. S.REGENERATE_WORLD) or S.REGENERATE_WORLD, 
            S.REGENERATE_WORLD_DESC,
            function() 
                -- double popup confirm dialogs :)
                PopupInputConfirmDialog(
                    S.REGENERATE_WORLD,
                    S.REGENERATE_WORLD_REQUIRE_SERVER_NAME,
                    function(text) return text == TheNet:GetServerName() end,  
                    function() ExecuteOrStartVote(vote_state, M.COMMAND_ENUM.REGENERATE_WORLD, nil) end
                )
            end
        )
    end)

    CreateSwitchOfServer(screen, 'set_new_player_joinability', 'allow_all_player', 'allow_old_player',
        false, 
        function(current_state, vote_state)
            local current_state_text = screen.set_new_player_joinability.state_res[current_state].hover_text.text

            PopupConfirmDialog(
                (vote_state and S.START_A_VOTE or '') .. S.SET_NEW_PLAYER_JOINABILITY_TITLE, 
                current_state_text .. S.AUTO_NEW_PLAYER_WALL_PROBALY_ENABLED, 
                function() ExecuteOrStartVote(vote_state, M.COMMAND_ENUM.SET_NEW_PLAYER_JOINABILITY, not current_state) end
            )
             
        end
    )
    -- modify 'disabled' texture
    screen.set_new_player_joinability.state_res[true].textures[4] = 'not_allow_all_select.tex'
    screen.set_new_player_joinability.state_res[false].textures[4] = 'not_allow_all_select.tex'
    local new_player_joinability = ThePlayer.player_classified:GetAllowNewPlayersToConnect()
    if new_player_joinability then
        screen.set_new_player_joinability:TurnOn()
    else
        screen.set_new_player_joinability:TurnOff()
    end

    CreateButtonOfServer(screen, 'make_item_stat_in_player_inventories', 'make_item_stat', false, function(vote_state)
        PopupItemStatDialog(
            vote_state and (S.START_A_VOTE .. S.MAKE_ITEM_STAT_IN_PLAYER_INVENTORIES) or S.MAKE_ITEM_STAT_IN_PLAYER_INVENTORIES, 
            S.MAKE_ITEM_STAT_DESC, 
            -- on_submitted
            function(item_prefabs, search_range)
                 

                ExecuteOrStartVote(vote_state, M.COMMAND_ENUM.MAKE_ITEM_STAT_IN_PLAYER_INVENTORIES, search_range, unpack(item_prefabs))
            end
        )
    end)

    CreateButtonOfServer(screen, 'vote', nil, false, function(vote_state)
        if vote_state then
            for _, btn in ipairs(screen.votable_buttons) do
                local cmd = M.COMMAND_ENUM[string.upper(btn.name)]
                if cmd and ThePlayer.player_classified:HasPermission(cmd) then
                    btn:DisableVote() 
                end
            end
            screen.vote:DisableVote()
        else
            for _, btn in ipairs(screen.votable_buttons) do
                local cmd = M.COMMAND_ENUM[string.upper(btn.name)]
                if cmd and ThePlayer.player_classified:HasVotePermission(cmd) then
                    btn:EnableVote()
                end
            end
            screen.vote:EnableVote()
        end
    end)
    screen.vote:SetHoverTextAtVote(S.NO_VOTE)
    screen.vote:SetTexturesAtVote(M.ATLAS, 'no_vote_normal.tex', 'no_vote_hover.tex', 'no_vote_select.tex', 'no_vote_select.tex', nil, { .4, .4 }, { 0, 0 })

    CreateButtonOfServer(screen, 'refresh_records', nil, true, function()
        PopupConfirmDialog(S.REFRESH_RECORDS, S.REFRESH_RECORDS_DESC, function()
            ThePlayer.player_classified:RequestToExecuteCommand(M.COMMAND_ENUM.REFRESH_RECORDS)
        end)
    end)
end

local HistoryPlayerScreen = Class(Screen, function(self, owner)
    Screen._ctor(self, 'HistoryPlayerScreen')
    self.owner = owner
    self.time_to_refresh = REFRESH_INTERVAL
    self.usercommandpickerscreen = nil
    self.show_player_badge = not TheFrontEnd:GetIsOfflineMode() and TheNet:IsOnlineMode()

    self.recorder = TheWorld.components.serverinforecord

    self.on_snapshot_info_dirty = function()
        if not self.needs_update_snapshot_info then
            ThePlayer.player_classified:QuerySnapshotInformations() 
            -- make a flag, in case the event broadcast frequently in a short time
            self.needs_update_snapshot_info = true
            self.owner:DoTaskInTime(1, function()
                self.needs_update_snapshot_info = nil
            end)
        end
    end

    self.on_snapshot_info_updated = function()
         
        if self.shown then 
            self:DoInitRollbackSpinner()
        end
    end

    self.on_server_data_updated = function()
         
        if self.shown then 
            self:DoInit()
        end
    end

    self.on_new_player_joinability_updated = function()
         
        if self.shown then
            local new_player_joinability = ThePlayer.player_classified:GetAllowNewPlayersToConnect()
            if new_player_joinability then
                self.set_new_player_joinability:TurnOn()
            else
                self.set_new_player_joinability:TurnOff()
            end
        end
    end
end)

function HistoryPlayerScreen:GenerateSortedKeyList()
    -- generate a sorted key list with the following rules:
    -- 1. by online status: onlined players first
    -- 2. by permission level: admins and moderators first
    -- 3. by player age: elder players first 

    sorted_userkey_list = {}
    local offline = {}
    
    local player_record = self.recorder.player_record
    for userid, player in pairs(player_record) do
        if M.IsPlayerOnline(userid) then
            table.insert(sorted_userkey_list, userid)
        else
            table.insert(offline, userid)
        end
    end

    local sort_fn = function(a, b)
        -- a < b if:

        if player_record[a].permission_level == player_record[b].permission_level then
            local a_age, b_age = player_record[a].age or 0, player_record[b].age or 0
            return a_age > b_age
        else
            return M.LevelHigherThan(player_record[a].permission_level, player_record[b].permission_level)
        end
    end

    table.sort(sorted_userkey_list, sort_fn)
    table.sort(offline, sort_fn)

    for _, v in ipairs(offline) do
        table.insert(sorted_userkey_list, v)
    end
    
end

-- function HistoryPlayerScreen:BuildDaySeasonStringByInfoIndex(index)
--     return M.BuildDaySeasonString(self.recorder.snapshot_info[index].day, self.recorder.snapshot_info[index].season)
-- end

function HistoryPlayerScreen:BuildSnapshotBriefStringByInfoIndex(index)
    return M.BuildSnapshotBriefString(S.FMT_ROLLBACK_SPINNER_BRIEF, self.recorder.snapshot_info[index])
end

function HistoryPlayerScreen:DumpToWebPage(userid)
    local record = self.recorder.player_record[userid]
    local encoded_data = M.EncodeToBase64(string.format(S.FMT_TEXT_WEB_PAGE, record.name or S.UNKNOWN, userid or S.UNKNOWN, record.netid or S.UNKNOWN))
    VisitURL(string.format(S.FMT_URL_WAB_PAGE, encoded_data), false) -- past a false, in order to raise client's default web browser but not Steam's browser
end

function HistoryPlayerScreen:OnBecomeActive()
    HistoryPlayerScreen._base.OnBecomeActive(self)
    self:DoInit()
    self.time_to_refresh = REFRESH_INTERVAL
    self.scroll_list:SetFocus()

    SetAutopaused(true)
end

function HistoryPlayerScreen:OnBecomeInactive()

    SetAutopaused(false)

    HistoryPlayerScreen._base.OnBecomeInactive(self)
end

function HistoryPlayerScreen:OnDestroy()
    --Overridden so we do part of Widget:Kill() but keeps the screen around hidden
    self:ClearFocus()
    self:StopFollowMouse()
    self:Hide()

    if TheWorld then
       if TheWorld.net then
            self.owner:RemoveEventCallback('issavingdirty', self.on_snapshot_info_dirty, TheWorld.net)
        end
        self.owner:RemoveEventCallback('snapshot_info_updated', self.on_snapshot_info_updated, TheWorld)
        self.owner:RemoveEventCallback('player_record_sync_completed', self.on_server_data_updated, TheWorld)
    end

    if ThePlayer.player_classified then 
        self.owner:RemoveEventCallback('permission_level_changed', self.on_server_data_updated, ThePlayer.player_classified)
        self.owner:RemoveEventCallback('new_player_joinability_changed', self.on_new_player_joinability_updated, ThePlayer.player_classified)
    end
    
    if self.onclosefn ~= nil then
        self.onclosefn()
    end
end

function HistoryPlayerScreen:OnControl(control, down)
    if not self:IsVisible() then
        return false
    elseif HistoryPlayerScreen._base.OnControl(self, control, down) then
        return true
    elseif control == CONTROL_OPEN_DEBUG_MENU then
        --jcheng: don't allow debug menu stuff going on right now
        return true
    elseif not down then
        if control == CONTROL_SHOW_PLAYER_STATUS
			or (control == CONTROL_TOGGLE_PLAYER_STATUS and not TheInput:IsControlPressed(CONTROL_SHOW_PLAYER_STATUS))
			or (self.click_to_close and (control == CONTROL_PAUSE or control == CONTROL_CANCEL))
        then
            self:Close()
            return true
        elseif control == CONTROL_MENU_MISC_2 and self.server_group ~= '' then
            TheNet:ViewNetProfile(self.server_group)
            return true
        end
    end
end

function HistoryPlayerScreen:OnRawKey(key, down)
    if not self:IsVisible() then
        return false
    elseif HistoryPlayerScreen._base.OnRawKey(self, key, down) then
        return true
    end
    return not down
end

function HistoryPlayerScreen:Close()
    TheInput:EnableDebugToggle(true)
    TheFrontEnd:PopScreen(self)
end

function HistoryPlayerScreen:DoInitRollbackSpinner()
    -- if not screen.rollback_slots then
    self.rollback_slots = {}
    
    -- build/rebuild rollback_slots anyway
    local first_slot_is_new = M.IsNewestRollbackSlotValid()
    
    if #self.recorder.snapshot_info ~= 0 then
        -- for new command ROLLBACK
        if first_slot_is_new then
            table.insert(self.rollback_slots, {text = self:BuildSnapshotBriefStringByInfoIndex(1) .. S.ROLLBACK_SPINNER_NEWEST, data = 1})
            for i = 2, #self.recorder.snapshot_info do
                table.insert(self.rollback_slots, {text = self:BuildSnapshotBriefStringByInfoIndex(i) .. '(' .. tostring(i) .. ')', data = i})
            end
        else
            table.insert(self.rollback_slots, {text = self:BuildSnapshotBriefStringByInfoIndex(1) .. S.ROLLBACK_SPINNER_NEWEST, data = 1})
            for i = 2, #self.recorder.snapshot_info do
                table.insert(self.rollback_slots, {text = self:BuildSnapshotBriefStringByInfoIndex(i) .. '(' .. tostring(i - 1) .. ')', data = i}) -- data keeps its real index, cuz we use new rollback command
            end
        end
        
    else
        table.insert(self.rollback_slots, {text = S.ROLLBACK_SPINNER_EMPTY, data = nil})
    end
   
    if self.bg_rollback_spinner ~= nil then
        if TheInput:ControllerAttached() then
            self.bg_rollback_spinner:Kill()
            self.bg_rollback_spinner = nil
        else
            self.rollback_spinner:SetOptions(self.rollback_slots)
        end
    elseif self.bg_rollback_spinner == nil and not TheInput:ControllerAttached() then
        self.bg_rollback_spinner = self.root:AddChild(Image(M.ATLAS, 'bg_rollback_spinner.tex'))
        sp = Spinner(self.rollback_slots, 240, nil, {font = CHATFONT, size = 22}, nil, 'images/global_redux.xml', spinner_lean_images, true)
        sp:SetTextColour(UICOLOURS.GOLD)
        self.rollback_spinner = self.bg_rollback_spinner:AddChild(sp)
        self.rollback_spinner.first_slot_is_new = first_slot_is_new
        self.rollback_spinner.has_moved_to_first_slot = false

        local x, y = self.rollback:GetPositionXYZ()

        self.bg_rollback_spinner:SetPosition(x, y - 50)
        self.rollback_spinner:SetPosition(0, -3)
        self.bg_rollback_spinner:Hide()

        local show_state, hide_state = {r = 1, g = 1, b = 1, a = 1}, {r = 1, g = 1, b = 1, a = 0}
        local function TintShow()
            self.bg_rollback_spinner:Show()
            self.bg_rollback_spinner:TintTo(hide_state, show_state, .3)
            self.rollback_spinner.leftimage.image:TintTo(hide_state, show_state, .3)
            self.rollback_spinner.rightimage.image:TintTo(hide_state, show_state, .3)
            -- self.rollback_spinner.text:TintTo(hide_state, show_state, .3)
        end
        local function TintHide()
            self.rollback_spinner.leftimage.image:TintTo(show_state, hide_state, .3)
            self.rollback_spinner.rightimage.image:TintTo(show_state, hide_state, .3)
            -- self.rollback_spinner.text:TintTo(show_state, hide_state, .3)
            self.bg_rollback_spinner:TintTo(show_state, hide_state, .3, function()
                self.bg_rollback_spinner:Hide()
            end)
        end

        self.rollback:SetOnGainFocus(function()
            TintShow() 
        end)

        self.bg_rollback_spinner:SetOnLoseFocus(function()
            if not self.rollback.focus then
                TintHide()
            end
        end)
        self.rollback:SetOnLoseFocus(function()
            if not self.bg_rollback_spinner.focus then
                TintHide()
            end
        end)
    end
end

function HistoryPlayerScreen:OnUpdate(dt)
    if TheFrontEnd:GetFadeLevel() > 0 then
        self:Close()
    else
        -- no need to disable the newest slot 
        if self.rollback_spinner then
            local first_slot_is_new = M.IsNewestRollbackSlotValid()

            if first_slot_is_new ~= self.rollback_spinner.first_slot_is_new then
                -- needs rebuild rollback_spinner
                self:DoInitRollbackSpinner()
                self.rollback_spinner.first_slot_is_new = first_slot_is_new
            else
                if not self.rollback_spinner.has_moved_to_first_slot and not first_slot_is_new and self.rollback_spinner:GetSelectedIndex() == 1 then
                    -- disable this option
                    self.rollback_spinner:SetHoverText(S.ROLLBACK_SPINNER_SLOT_NEW_CREATED)
                    self.rollback_spinner:SetTextColour(UICOLOURS.GOLD_SELECTED)
                    -- self.rollback:Select()
                    self.rollback_spinner.has_moved_to_first_slot = true
                elseif self.rollback_spinner.has_moved_to_first_slot and (first_slot_is_new or self.rollback_spinner:GetSelectedIndex() ~= 1) then
                    self.rollback_spinner:ClearHoverText()
                    self.rollback_spinner:SetTextColour(UICOLOURS.GOLD)
                    -- self.rollback:Unselect()
                    self.rollback_spinner.has_moved_to_first_slot = false
                end
            end
        end

        if self.time_to_refresh > dt then
            self.time_to_refresh = self.time_to_refresh - dt
            -- something needs refresh immediactly 
        else
            self.time_to_refresh = REFRESH_INTERVAL
            -- list refresh
        end
    end
end



function HistoryPlayerScreen:DoInit()
    TheInput:EnableDebugToggle(false)
    
    if not self.votable_buttons then
        self.votable_buttons = {}
    end
    self.time_to_refresh = 0

    if not self.black then
        --darken everything behind the dialog
        --bleed outside the screen a bit, otherwise it may not cover
        --the edge of the screen perfectly when scaled to some sizes

        -- nobody knows what does this lonely variable do 
        -- local bleeding = 4
        self.black = self:AddChild(ImageButton('images/global.xml', 'square.tex'))
        self.black.image:SetVRegPoint(ANCHOR_MIDDLE)
        self.black.image:SetHRegPoint(ANCHOR_MIDDLE)
        self.black.image:SetVAnchor(ANCHOR_MIDDLE)
        self.black.image:SetHAnchor(ANCHOR_MIDDLE)
        self.black.image:SetScaleMode(SCALEMODE_FILLSCREEN)
        self.black.image:SetTint(0,0,0,0) -- invisible, but clickable!

	    self.black:SetHelpTextMessage('')
	    self.black:SetOnClick(function() if self.click_to_close then TheFrontEnd:PopScreen(self) end end)
		self.black:MoveToBack()
    end

    if not self.root then
        self.root = self:AddChild(Widget('ROOT'))
        self.root:SetScaleMode(SCALEMODE_PROPORTIONAL)
        self.root:SetHAnchor(ANCHOR_MIDDLE)
        self.root:SetVAnchor(ANCHOR_MIDDLE)
    end

    if not self.bg then
        self.bg = self.root:AddChild(Image( 'images/scoreboard.xml', 'scoreboard_frame.tex' ))
        self.bg:SetScale(.96,.9)
    end

    if not self.servertitle then
        self.servertitle = self.root:AddChild(Text(UIFONT,45))
        self.servertitle:SetHAlign(ANCHOR_RIGHT)
        self.servertitle:SetColour(1,1,1,1)
    end

    if not self.serverstate then
        self.serverstate = self.root:AddChild(Text(UIFONT,30))
        self.serverstate:SetColour(1,1,1,1)
    end

	if TheNet:GetServerGameMode() == 'lavaarena' then
		self.serverstate:SetString(subfmt(STRINGS.UI.PLAYERSTATUSSCREEN.LAVAARENA_SERVER_MODE, {mode=GetGameModeString(TheNet:GetServerGameMode()), num = TheWorld.net.components.lavaarenaeventstate:GetCurrentRound()}))
	else
		self.serverage = TheWorld.state.cycles + 1
		local modeStr = GetGameModeString(TheNet:GetServerGameMode()) ~= nil and GetGameModeString(TheNet:GetServerGameMode())..' - ' or ''
		self.serverstate:SetString(modeStr..' '..STRINGS.UI.PLAYERSTATUSSCREEN.AGE_PREFIX..self.serverage)
	end

    self.servermenunumbtns = 0

    self.server_group = TheNet:GetServerClanID()

    self:GenerateSortedKeyList()
    
    local num_online_players, num_all_players  = #GetPlayerClientTable(), #sorted_userkey_list

    if self.recorder:HasMorePlayerRecords() then 
        table.insert(sorted_userkey_list, LIST_IS_INCOMPLETE)
    end

    if not self.players_number then
        self.players_number = self.root:AddChild(Text(UIFONT, 25))
        self.players_number:SetPosition(318,170)
        self.players_number:SetRegionSize(100,30)
        self.players_number:SetHAlign(ANCHOR_RIGHT)
        self.players_number:SetColour(1,1,1,1)
    end
    self.players_number:SetString(
        string.format(S.FMT_PLAYER_NUMBER, num_online_players, tostring(TheNet:GetServerMaxPlayers()) or '?' , num_all_players)
    )
    self.players_number:SetHoverText(
        string.format(S.FMT_PLAYER_NUMBER_HOVER, num_online_players, tostring(TheNet:GetServerMaxPlayers()) or '?' , num_all_players), 
        { font = NEWFONT_OUTLINE, offset_x = 0, offset_y = 40, colour = {1,1,1,1}}
    )

    if not self.divider then
        self.divider = self.root:AddChild(Image('images/scoreboard.xml', 'white_line.tex'))
    end

    local servermenux = -329
    local servermenubtnoffs = 24

    self.servertitle:SetPosition(200,200)
    self.servertitle:SetTruncatedString(S.TITLE, 550, 100, true)

    self.serverstate:SetPosition(0,163)
    self.serverstate:SetSize(23)
    self.players_number:SetPosition(318,160)
    self.players_number:SetSize(20)
    self.divider:SetPosition(0,149)

    if not self.servermods and TheNet:GetServerModsEnabled() then
        local mods_desc = TheNet:GetServerModsDescription()
        self.servermods = self.root:AddChild(Text(UIFONT,25))
        self.servermods:SetPosition(20,-250,0)
        self.servermods:SetColour(1,1,1,1)
        self.servermods:SetTruncatedString(STRINGS.UI.PLAYERSTATUSSCREEN.MODSLISTPRE..' '..mods_desc, 650, 146, true)
        
        local mods_desc_table = {}
        local count = 0
        for w in string.gmatch(mods_desc, '[^,]+,') do
            count = count + 1
            table.insert(mods_desc_table, w)
            if count % 2 == 0 then
                table.insert(mods_desc_table, '\n')
            end
        end
        self.servermods:SetHoverText(table.concat(mods_desc_table, ''), {bg_texture = 'char_shadow.tex'})
        if self.servermods.hovertext_bg then    
            self.servermods.hovertext_bg:SetTint(1, 1, 1, 1)
        end

        self.bg:SetScale(.95,.95)
        self.bg:SetPosition(0,-10)
    end

    DoInitScreenToggleButton(self, 2)
    DoInitServerRelatedCommnadButtons(self)

    -- -- what does this function do?
    -- local function doButtonFocusHookups(playerListing)
    --     local buttons = {}
    --     if playerListing.viewprofile:IsVisible() then table.insert(buttons, playerListing.viewprofile) end
    --     if playerListing.kick:IsVisible() then table.insert(buttons, playerListing.kick) end
    --     if playerListing.ban:IsVisible() then table.insert(buttons, playerListing.ban) end
    --     -- if playerListing.useractions:IsVisible() then table.insert(buttons, playerListing.useractions) end

    --     local focusforwardset = false
    --     for i,button in ipairs(buttons) do
    --         if not focusforwardset then
    --             focusforwardset = true
    --             playerListing.focus_forward = button
    --         end
    --         if buttons[i-1] then
    --             button:SetFocusChangeDir(MOVE_LEFT, buttons[i-1])
    --         end
    --         if buttons[i+1] then
    --             button:SetFocusChangeDir(MOVE_RIGHT, buttons[i+1])
    --         end
    --     end
    -- end


    
    local function listingConstructor(i, parent)
        local playerListing =  parent:AddChild(Widget('playerListing'))

        playerListing.highlight = playerListing:AddChild(Image('images/scoreboard.xml', 'row_goldoutline.tex'))
        playerListing.highlight:SetPosition(22, 5)
        playerListing.highlight:Hide()

        if self.show_player_badge then
            playerListing.profileFlair = playerListing:AddChild(TEMPLATES.RankBadge())
            playerListing.profileFlair:SetPosition(-388,-14,0)
            playerListing.profileFlair:SetScale(.6)
        end

        playerListing.characterBadge = nil
        playerListing.characterBadge = playerListing:AddChild(PlayerBadge('', DEFAULT_PLAYER_COLOUR, false, 0))
        playerListing.characterBadge:SetScale(.8)
        playerListing.characterBadge:SetPosition(-328,5,0)
        playerListing.characterBadge:Hide()

        playerListing.number = playerListing:AddChild(Text(UIFONT, 35))
        playerListing.number:SetPosition(-422,0,0)
        playerListing.number:SetHAlign(ANCHOR_MIDDLE)
        playerListing.number:SetColour(1,1,1,1)
        playerListing.number:Hide()

        playerListing.adminBadge = playerListing:AddChild(ImageButton('images/avatars.xml', 'avatar_admin.tex', 'avatar_admin.tex', 'avatar_admin.tex', nil, nil, {.3,.3}, {0,0}))
        playerListing.adminBadge:Disable()
        playerListing.adminBadge:SetPosition(-355,-13,0)
        playerListing.adminBadge.scale_on_focus = false
        playerListing.adminBadge:Hide()

        playerListing.name = playerListing:AddChild(TextButton())
        playerListing.name:SetFont(UIFONT)
        playerListing.name:SetTextSize(35)
        playerListing.name._align = {
            maxwidth = 215,
            maxchars = 36,
            x = -286,
        }

        playerListing.load_more_records = playerListing:AddChild(TextButton())
        playerListing.load_more_records:SetFont(UIFONT)
        playerListing.load_more_records:SetTextSize(35)
        playerListing.load_more_records._align = {
            maxwidth = 215,
            maxchars = 36,
            x = -286,
        }
        playerListing.load_more_records:SetText(S.LOAD_MORE_HISTORY_PLAYERS)
        playerListing.load_more_records:SetOnClick(function()
            -- query server to load more player records
            ThePlayer.player_classified:QueryHistoryPlayers()
        end)
        playerListing.load_more_records:Hide()


        playerListing.age = playerListing:AddChild(Text(UIFONT, 35, ''))
        playerListing.age:SetPosition(-20,0,0)
        playerListing.age:SetHAlign(ANCHOR_MIDDLE)
		if TheNet:GetServerGameMode() == 'lavaarena' then
			playerListing.age:Hide()
		end
         
        playerListing.button_list = {}
        local function CreateButtonOfPlayer(name, image_button, hover_text, on_click, needs_confirm)
            hover_text = hover_text or S[string.upper(name)] or ''
            local button = playerListing:AddChild(image_button)
            button.name = name
            if VotableImageButton.is_instance(button) then
                table.insert(self.votable_buttons, button)

                button:SetHoverTextAtNormal(
                    S[string.upper(name)] or '',
                    { font = GLOBAL.NEWFONT_OUTLINE, offset_x = 0, offset_y = 38, colour = GLOBAL.WHITE }
                )
                button:SetHoverTextAtVote(
                    (S.START_A_VOTE .. (S[string.upper(name)] or '')) 
                )
            else
                button:SetHoverText(
                    hover_text, 
                    { font = NEWFONT_OUTLINE, offset_x = 0, offset_y = 30, colour = {1,1,1,1}}
                )
            end
            playerListing[name] = button
            button:SetNormalScale(0.39)
            button:SetFocusScale(0.39*1.1)
            button:SetFocusSound('dontstarve/HUD/click_mouseover', nil, ClickMouseoverSoundReduction())
   
            if needs_confirm then
                button:SetOnClick(function()
                    local online = self.recorder.player_record[playerListing.userid].online
                    PopupConfirmDialog(
                        string.format(S.FMT_CONFIRM_DIALOG_TITLE, hover_text),
                        string.format(S.FMT_CONFIRM_DIALOG_DESC, playerListing.displayName, hover_text, online and '' or S.COMFIRM_DIALOG_OFFLINE_PLAYER_DESC), 
                        on_click, 
                        button.vote_state -- will be nil if button is a normal ImageButton, it is ok
                    )
                end)
            else
                button:SetOnClick(function()
                    on_click(button.vote_state)
                end)
            end
            button:Hide()

            table.insert(playerListing.button_list, name)
        end


        -- available commands

        CreateButtonOfPlayer('viewprofile', 
            ImageButton('images/scoreboard.xml', 'addfriend.tex', 'addfriend.tex', 'addfriend.tex', 'addfriend.tex', nil, {1,1}, {0,0}), 
            nil,
            function()
                if playerListing.displayName and playerListing.userid then
                    TheFrontEnd:PopScreen()
                    self.owner.HUD:TogglePlayerInfoPopup(playerListing.displayName, TheNet:GetClientTableForUser(playerListing.userid), true, true)
                end
            end
        )
        CreateButtonOfPlayer('viewsteamprofile', 
            ImageButton(M.ATLAS, 'view_steam_profile.tex', 'view_steam_profile.tex', 'view_steam_profile.tex', 'view_steam_profile.tex', nil, {1,1}, {0,0}), 
            nil,
            function()
                if playerListing.netid then
                    TheNet:ViewNetProfile(playerListing.netid)
                end
            end
        )

        CreateButtonOfPlayer('kick', 
            VotableImageButton('images/scoreboard.xml', 'kickout.tex', 'kickout.tex', 'kickout_disabled.tex', 'kickout.tex', nil, {1,1}, {0,0}), 
            nil, 
            function(vote_state)
                if playerListing.userid then
                    ExecuteOrStartVote(vote_state, M.COMMAND_ENUM.KICK, playerListing.userid)
                    
                    TheFrontEnd:PopScreen()
                end
            end,
            true
        )
        CreateButtonOfPlayer('kill', 
            VotableImageButton(M.ATLAS, 'kill.tex', 'kill.tex', 'kill.tex', 'kill.tex', nil, {1,1}, {0,0}),
            nil, 
            function(vote_state)
                if playerListing.userid then
                    ExecuteOrStartVote(vote_state, M.COMMAND_ENUM.KILL, playerListing.userid)
                    -- ^  v these two statement shell not swap places or it will cause lua syntex ambiguous 
                    TheFrontEnd:PopScreen()
                end
            end,
            true
        )
        CreateButtonOfPlayer('ban', 
            VotableImageButton('images/scoreboard.xml', 'banhammer.tex', 'banhammer.tex', 'banhammer.tex', 'banhammer.tex', nil, {1,1}, {0,0}), 
            nil, 
            function(vote_state)
                if playerListing.userid then
                    ExecuteOrStartVote(vote_state, M.COMMAND_ENUM.BAN, playerListing.userid)
                    
                    TheFrontEnd:PopScreen()
                end
            end, 
            true
        )
        CreateButtonOfPlayer('killban', 
            VotableImageButton(M.ATLAS, 'killban.tex', 'killban.tex', 'killban.tex', 'killban.tex', nil, {1,1}, {0,0}),
            nil, 
            function(vote_state)
                if playerListing.userid then
                    ExecuteOrStartVote(vote_state, M.COMMAND_ENUM.KILLBAN, playerListing.userid)
                    
                    TheFrontEnd:PopScreen()
                end
            end, 
            true
        )
        CreateButtonOfPlayer('add_moderator', 
            VotableImageButton(M.ATLAS, 'add_moderator.tex', 'add_moderator.tex', 'add_moderator.tex', 'add_moderator.tex', nil, {1,1}, {0,0}), 
            nil, 
            function(vote_state)
                if playerListing.userid then
                    ExecuteOrStartVote(vote_state, M.COMMAND_ENUM.ADD_MODERATOR, playerListing.userid)
                
                    TheFrontEnd:PopScreen()
                end
            end, 
            true
        )
        CreateButtonOfPlayer('remove_moderator', 
            VotableImageButton(M.ATLAS, 'remove_moderator.tex', 'remove_moderator.tex', 'remove_moderator.tex', 'remove_moderator.tex', nil, {1,1}, {0,0}), 
            nil, 
            function(vote_state)
                if playerListing.userid then
                    ExecuteOrStartVote(vote_state, M.COMMAND_ENUM.REMOVE_MODERATOR, playerListing.userid)
                    
                    TheFrontEnd:PopScreen()
                end
            end, 
            true
        )

        playerListing.OnGainFocus = function()
            playerListing.highlight:Show()
        end
        playerListing.OnLoseFocus = function()
            playerListing.highlight:Hide()
        end

        return playerListing
    end

    local function HideAllButtonsOfPlayer(playerListing)
        if not playerListing.button_list then return end
        for _, button in ipairs(playerListing.button_list) do
            if playerListing[button] then
                playerListing[button]:Hide()
            end
        end
    end

    local function UpdatePlayerListing(playerListing, userid, i)
        if userid == nil then
            playerListing:Hide()
            return
        elseif userid == LIST_IS_INCOMPLETE then
            
            -- show a tips button for load more players
            playerListing.load_more_records:Show()
            -- hide a dozen of elements 
            playerListing.profileFlair:Hide()
            playerListing.characterBadge:Hide()
            playerListing.number:Hide()
            playerListing.adminBadge:Hide()
            playerListing.name:Hide()
            playerListing.age:Hide()
            HideAllButtonsOfPlayer(playerListing)
            playerListing:Show()
            return
        end
        playerListing.load_more_records:Hide()
        
        self.recorder:RecordClientData(userid)
        local record = self.recorder.player_record[userid]
        
        playerListing:Show()
        playerListing.displayName = (record.name or '???') .. '('.. userid ..')'

        playerListing.userid = userid
        playerListing.netid = record.netid

        local colour = record.client and record.client.colour or DEFAULT_PLAYER_COLOUR
        local userflags = record.client and record.client.userflags or 0

        -- if record.client then
        playerListing.characterBadge:Set(
            GetBasePrefabFromSkin(record.skin) or '',       -- prefab name
            colour,                                         -- colour 
            false,                                          -- is_host
            userflags,                                      -- userflags 
            record.skin or ''                               -- base_skin
        )

        if self.show_player_badge then
            if record.client then
                local _, _, _, profileflair, rank = GetSkinsDataFromClientTableData(record.client)
                playerListing.profileFlair:SetRank(profileflair, rank)
                playerListing.profileFlair:Show()
            else
                playerListing.profileFlair:Hide()
            end
        end

        playerListing.characterBadge:Show()

        if record.permission_level == M.PERMISSION.ADMIN then
            playerListing.adminBadge:SetTextures(M.ATLAS, 'admin_badge.tex', 'admin_badge.tex', 'admin_badge.tex', nil, nil, {.3,.3}, {0,0})        
            playerListing.adminBadge:SetHoverText(
                S.ADMIN, { font = NEWFONT_OUTLINE, offset_x = 0, offset_y = 30, colour = {1,1,1,1}}
            )
            playerListing.adminBadge:Show()
        elseif record.permission_level == M.PERMISSION.MODERATOR then
            playerListing.adminBadge:SetTextures('images/avatars.xml', 'avatar_admin.tex', 'avatar_admin.tex', 'avatar_admin.tex', nil, nil, {.3,.3}, {0,0})
            playerListing.adminBadge:SetHoverText(
                S.MODERATOR, { font = NEWFONT_OUTLINE, offset_x = 0, offset_y = 30, colour = {1,1,1,1}}
            )
            playerListing.adminBadge:Show()
        else
            -- is user or lower level
            playerListing.adminBadge:Hide()
        end

        -- host listing will not be shown
        playerListing.number:SetString(i)

        -- playerListing.name.text:SetTruncatedString(playerListing.displayName, playerListing.name._align.maxwidth, playerListing.name._align.maxchars, true)
        playerListing.name:SetText(playerListing.displayName)
        local w, h = playerListing.name.text:GetRegionSize()
        playerListing.name:SetPosition(playerListing.name._align.x + w * .5, 0, 0)
        playerListing.name:SetColour(unpack(record.colour or DEFAULT_PLAYER_COLOUR))
        playerListing.name:SetOnClick(function()
            self:DumpToWebPage(userid)
        end)
        playerListing.name:Show()

        playerListing.age:SetString(
            record.age ~= nil and 
            record.age > 0 and
            (tostring(record.age) .. (record.age == 1 and STRINGS.UI.PLAYERSTATUSSCREEN.AGE_DAY or STRINGS.UI.PLAYERSTATUSSCREEN.AGE_DAYS)) 
            or ''
        )
        playerListing.age:Show()
    
        
        local button_start = 50
        local button_x = button_start
        local button_x_offset = 42

        local function ShowButtonIfAvailable(name)
            
            local cmd = M.COMMAND_ENUM[string.upper(name)]
            if cmd then
                local category = ThePlayer.player_classified:CommandApplyableForPlayerTarget(cmd, userid)
                if category == M.EXECUTION_CATEGORY.YES then
                    if self.vote.vote_state then
                        playerListing[name]:EnableVote()
                    else -- vote_state == false
                        playerListing[name]:DisableVote()
                    end
                elseif category == M.EXECUTION_CATEGORY.VOTE_ONLY then
                    -- always in vote state
                    playerListing[name]:EnableVote()
                else -- category == M.EXECUTION_CATEGORY.NO
                    -- always don't show the button
                    return
                end
            end
            playerListing[name]:Show()
            playerListing[name]:SetPosition(button_x, 3, 0)
            button_x = button_x + button_x_offset
        end

        -- button visibility tests

        HideAllButtonsOfPlayer(playerListing)
        if record.online then
            ShowButtonIfAvailable('viewprofile')
        elseif record.netid then
            ShowButtonIfAvailable('viewsteamprofile')
        end

        if not IsSelf(userid) or M.DEBUG then
            
            if record.online then
                ShowButtonIfAvailable('kick')
            end

            ShowButtonIfAvailable('kill')
            
            if record.permission_level ~= M.PERMISSION.USER_BANNED then
            -- these commands are only for un-banned player

                ShowButtonIfAvailable('ban')
            
                ShowButtonIfAvailable('killban')
            

                if not M.LevelHigherThan(record.permission_level, M.PERMISSION.USER) then
                    ShowButtonIfAvailable('add_moderator')
                elseif record.permission_level == M.PERMISSION.MODERATOR then
                    ShowButtonIfAvailable('remove_moderator')
                end
            end
        end

        -- doButtonFocusHookups(playerListing)
    end

    if not self.scroll_list then
        self.list_root = self.root:AddChild(Widget('list_root'))
        self.list_root:SetPosition(210, -35)

        self.row_root = self.root:AddChild(Widget('row_root'))
        self.row_root:SetPosition(210, -35)

        self.player_widgets = {}
        for i=1,6 do
            table.insert(self.player_widgets, listingConstructor(i, self.row_root))
            UpdatePlayerListing(self.player_widgets[i], sorted_userkey_list[i] or nil, i)
        end

        self.scroll_list = self.list_root:AddChild(ScrollableList(sorted_userkey_list, 380, 370, 60, 5, UpdatePlayerListing, self.player_widgets, nil, nil, nil, -15))
        self.scroll_list:LayOutStaticWidgets(-15)
        self.scroll_list:SetPosition(0,-10)

        self.focus_forward = self.scroll_list
        self.default_focus = self.scroll_list
    else
        self.scroll_list:SetList(sorted_userkey_list)
    end

    self.bg_rollback_spinner:MoveToFront()

    if not self.bgs then
        self.bgs = {}
    end
    if #self.bgs > #sorted_userkey_list then
        for i = #sorted_userkey_list + 1, #self.bgs do
            table.remove(self.bgs):Kill()
        end
    else
        local maxbgs = math.min(self.scroll_list.widgets_per_view, #sorted_userkey_list)
        if #self.bgs < maxbgs then
            for i = #self.bgs + 1, maxbgs do
                local bg = self.scroll_list:AddChild(Image('images/scoreboard.xml', 'row.tex'))
                bg:SetTint(1, 1, 1, (i % 2) == 0 and .85 or .5)
                bg:SetPosition(-170, 165 - 65 * (i - 1))
                bg:MoveToBack()
                table.insert(self.bgs, bg)
            end
        end
    end

    if TheWorld then
        if TheWorld.net then
            self.owner:ListenForEvent('issavingdirty', self.on_snapshot_info_dirty, TheWorld.net)
        end 
        self.owner:ListenForEvent('snapshot_info_updated', self.on_snapshot_info_updated, TheWorld)
        self.owner:ListenForEvent('player_record_sync_completed', self.on_server_data_updated, TheWorld)
    end

    if ThePlayer.player_classified then 
        self.owner:ListenForEvent('permission_level_changed', self.on_server_data_updated, ThePlayer.player_classified)
        self.owner:ListenForEvent('new_player_joinability_changed', self.on_new_player_joinability_updated, ThePlayer.player_classified)
    end

end



function PlayerHud:ShowHistoryPlayerScreeen(click_to_close, onclosefn)
    if self.playerstatusscreen ~= nil and self.playerstatusscreen.shown then
        return
    end

    if self.historyplayerscreen == nil then
        self.historyplayerscreen = HistoryPlayerScreen(self.owner)
    end
	self.historyplayerscreen.onclosefn = onclosefn
	self.historyplayerscreen.click_to_close = click_to_close
    TheFrontEnd:PushScreen(self.historyplayerscreen)
    self.historyplayerscreen:MoveToFront()
    self.historyplayerscreen:Show()
end

local OldShowPlayerStatusScreen = PlayerHud.ShowPlayerStatusScreen

function PlayerHud:ShowPlayerStatusScreen(click_to_close, onclosefn)
    if self.historyplayerscreen ~= nil and self.historyplayerscreen.shown then
        return
    end
    OldShowPlayerStatusScreen(self, click_to_close, onclosefn)
end

local OldDoInit = PlayerStatusScreen.DoInit

function PlayerStatusScreen:DoInit(clients)
    
    OldDoInit(self, clients)
    
    -- once the request is sent, 
    -- rpc will wait for a respose from server and re-init the screen in the callback while the reponse is received
    if ThePlayer.player_classified:HasPermission(M.COMMAND_ENUM.QUERY_HISTORY_PLAYERS) then
        DoInitScreenToggleButton(self, 1)
    else
        dbg('no permission to query history players')
    end

end
