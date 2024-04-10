
GLOBAL.setmetatable(env, {__index = function(t, k) return GLOBAL.rawget(GLOBAL, k) end})



-- GUI - clients only
if not (TheNet and TheNet:GetIsClient()) then return end

local M = manage_together
local S = STRINGS.UI.HISTORYPLAYERSCREEN

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
local PlayerBadge = require 'widgets/playerbadge'
local ScrollableList = require 'widgets/scrollablelist'

local PlayerStatusScreen = require 'screens/playerstatusscreen'

local PlayerHud = require 'screens/playerhud'
local PopupDialogScreen = require 'screens/redux/popupdialog'
local InputDialogScreen  = require 'screens/redux/inputdialog'

-- local UserCommands = require 'usercommands'

local TEMPLATES = require('widgets/redux/templates')

-- local BAN_ENABLED = true

local REFRESH_INTERVAL = .5


local function GetBasePrefabFromSkin(skin)
    -- the simplist and cheapest way to get the prefab name
    return skin and string.match(skin, '^(%w+)_[%w_]+$') or nil
end

local function IsSelf(userid)
    return ThePlayer and (ThePlayer.userid == userid) or false
end

local function SelectCommandToExecute(vote_state, cmd, ...)
    (vote_state and RequestToExecuteVoteCommand or RequestToExecuteCommand)(cmd, unpack(arg))
end

local function DumpToWebPage(userid)
    local record = M.player_record[userid]
    local encoded_data = M.EncodeToBase64(string.format(S.FMT_TEXT_WEB_PAGE, record.name or S.UNKNOWN, userid or S.UNKNOWN, record.netid or S.UNKNOWN))
    VisitURL(string.format(S.FMT_URL_WAB_PAGE, encoded_data))
end

local function RecordClientData(userid, client)
    if not client then
        M.player_record[userid].online = false    
        M.player_record[userid].colour = DEFAULT_PLAYER_COLOUR 
        M.player_record[userid].userflags = 0
    else
        -- player is online
        local permission_level = M.player_record[userid].permission_level
        M.player_record[userid] = {
            online = true, 
            name = client.name,
            netid = client.netid, 
            skin = client.base_skin, 
            age = client.playerage, 
            permission_level = permission_level,

            colour = client.colour,
            userflags = client.userflags 
        }
    end

end

local sorted_userkey_list
local function GenerateSortedKeyList()
    -- generate a sorted key list with the following rules:
    -- 1. by online status: onlined players first
    -- 2. by permission level: admins and moderators first
    -- 3. by player age: elder players first 

    sorted_userkey_list = {}
    local offline = {}
    
    for userid, player in pairs(M.player_record) do
        if M.IsPlayerOnline(userid) then
            table.insert(sorted_userkey_list, userid)
        else
            table.insert(offline, userid)
        end
    end

    local sort_fn = function(a, b)
        -- a < b if:

        if M.player_record[a].permission_level == M.player_record[b].permission_level then
            local a_age, b_age = M.player_record[a].age or 0, M.player_record[b].age or 0
            return a_age > b_age
        else
            return M.LevelHigherThan(M.player_record[a].permission_level, M.player_record[b].permission_level)
        end
    end

    table.sort(sorted_userkey_list, sort_fn)
    table.sort(offline, sort_fn)

    for _, v in ipairs(offline) do
        table.insert(sorted_userkey_list, v)
    end
    
end


local function RequestToUpdateRollbackInfo()
    RequestToExecuteCommand(M.COMMAND_ENUM.QUERY_HISTORY_PLAYERS, 2)
end

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
                    RequestToExecuteCommand(M.COMMAND_ENUM.QUERY_HISTORY_PLAYERS, nil)
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
    local button_ok_item     = {text=STRINGS.UI.PLAYERSTATUSSCREEN.OK, cb = function() TheFrontEnd:PopScreen() callback_on_confirmed(unpack(arg)) end}
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
                    on_confirmed_fn()
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
    
    self.bg.actions:DisableItem(1)
end)
function InputVerificationDialog:OnControl(control, down)
    if self:Verify() then
        self.bg.actions:EnableItem(1)
    else
        self.bg.actions:DisableItem(1)
    end
    InputVerificationDialog._base.OnControl(self, control, down)
end
function InputVerificationDialog:Verify()
    return self.verify_fn(self:GetText())
end

VotableImageButton = Class(ImageButton, function(self, atlas, normal, focus, disabled, down, selected, scale, offset)
    ImageButton._ctor(self, atlas, normal, focus, disabled, down, selected, scale, offset)

    self.normal_textures = {
        atlas, normal, focus, disabled, down, selected, scale, offset
    }
    self.vote_state = false
    self.vote_tip_image = self:AddChild(Image('images/button_icons.xml', 'vote.tex'))
    self.vote_tip_image:SetPosition(-11,-10,0)
    self.vote_tip_image:SetScale(.4)
    self.vote_tip_image:Hide()

    self.hover_text_at_vote = ''
    self.hover_text_at_normal = ''
    
    self:SetOnClick(function()
        if self.vote_state then
            if self.onclick_at_vote then
                self.onclick_at_vote()
            end
        else
            if self.onclick_at_normal then
                self.onclick_at_normal()
            end
        end
    end)
end)

function VotableImageButton:SetTexturesAtVote(atlas, normal, focus, disabled, down, selected, scale, offset)
    if not atlas then
        self.vote_textures = nil 
        return
    end
    self.vote_textures = {
        atlas, normal, focus, disabled, down, selected, scale, offset
    }
end

function VotableImageButton:SetOnClickAtNormal(fn)
    self.onclick_at_normal = fn
end
function VotableImageButton:SetOnClickAtVote(fn)
    self.onclick_at_vote = fn
end
function VotableImageButton:SetHoverTextAtVote(text, params)
    self.hover_text_at_vote = text or self.hover_text_at_normal
    self.hover_text_params_at_vote = params or self.hover_text_params_at_normal
    if self.vote_state then
        self:SetHoverText(self.hover_text_at_vote, params)
    end
end
function VotableImageButton:SetHoverTextAtNormal(text, params)
    self.hover_text_at_normal = text or ''
    self.hover_text_params_at_normal = params
    if not self.vote_state then
        self:SetHoverText(self.hover_text_at_normal, params)
    end
end

function VotableImageButton:UpdateVoteState(state)
    if state == nil then
        state = self.vote_state 
    else
        self.vote_state = state
    end

    if state then
        if self.vote_textures then
            self:SetTextures(unpack(self.vote_textures))
        else
            self.vote_tip_image:Show()
        end
        self:SetHoverText(self.hover_text_at_vote, self.hover_text_params_at_vote)
    else
        if self.vote_textures then
            self:SetTextures(unpack(self.normal_textures))
        end
        self.vote_tip_image:Hide()
        self:SetHoverText(self.hover_text_at_normal, self.hover_text_params_at_normal)
    end
end

function VotableImageButton:EnableVote()
    self:UpdateVoteState(true)
end 
function VotableImageButton:DisableVote()
    self:UpdateVoteState(false)
end

local function PopupInputConfirmDialog(action_name, required_text_tips, verify_fn, on_confirmed_fn)
    TheFrontEnd:PushScreen(InputVerificationDialog(
        -- title
        string.format(S.FMT_INPUT_TO_CONFIRM, required_text_tips, action_name),
        verify_fn, 
        on_confirmed_fn
    ))
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
                {text=STRINGS.UI.PLAYERSTATUSSCREEN.CANCEL, cb = function() TheFrontEnd:PopScreen() end}
            }
        )
    )
end

local function BuildDaySeasonStringByInfoIndex(index)
    return M.BuildDaySeasonString(M.rollback_info[index].day, M.rollback_info[index].season)
end

local function DoInitServerRelatedCommnadButtons(screen)

    local button_offset = 48
    local button_x = -329

    -- local function shift_button_x(offset)
    --     button_x = button_x + (offset or button_offset)
    --     return button_x
    -- end

    local function CreateButtonOfServer(name, img_src, close_on_clicked, command_fn, vote_command_fn)
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
            end
            --                                               atlas.xml, normal.tex, hover.tex, disabled.tex             , select.tex              ,
            button = screen.root:AddChild(VotableImageButton(img_src[1], img_src[2], img_src[3], img_src[4] or img_src[2], img_src[5] or img_src[2], nil, { .4, .4 }, { 0, 0 }))
            
            -- this flag affects:g
            -- hover_text
            -- onclick_fn
            button.name = name
            table.insert(screen.votable_buttons, button)

            screen[name] = button
            if not vote_command_fn then
                button:SetOnClick(function()
                    if close_on_clicked then screen:Close() end
                    command_fn(button.vote_state)
                end)
            else
                button:SetOnClickAtNormal(function()
                    if close_on_clicked then screen:Close() end
                    command_fn()
                end)
                button:SetOnClickAtVote(function()
                    if close_on_clicked then screen:Close() end
                    vote_command_fn()
                end)
            end

            button:SetHoverTextAtNormal(
                S[string.upper(name)] or '',
                { font = GLOBAL.NEWFONT_OUTLINE, offset_x = 0, offset_y = 38, colour = GLOBAL.WHITE }
            )
            button:SetHoverTextAtVote(
                (S.START_A_VOTE .. (S[string.upper(name)] or ''))
            )
   
            screen.servermenunumbtns = screen.servermenunumbtns + 1 
            button_x = button_x + button_offset

            local cmd = M.COMMAND_ENUM[string.upper(name)]
            if cmd == nil or HasPermission(cmd) then
                button:SetPosition(button_x, 200)
                button:Show()
            elseif HasVotePermission(cmd) then
                button:EnableVote()
                button:SetPosition(button_x, 200)
                button:Show()
            else
                button:Hide()
            end
        end

    end

    CreateButtonOfServer('save', nil, false, function()
        RequestToExecuteCommand(M.COMMAND_ENUM.SAVE, nil)
    end)

    CreateButtonOfServer('rollback', nil, false, function(vote_state)
        if screen.rollback_spinner:GetSelected().data == nil then
            PopupDialog(S.ERR_ROLLBACK_TITLE_BAD_INDEX, S.ERR_ROLLBACK_DESC_BAD_INDEX)
        else
            -- needs to confirm
            PopupConfirmDialog(
                vote_state and (S.START_A_VOTE .. S.ROLLBACK) or S.ROLLBACK, 
                string.format(S.FMT_ROLLBACK_TO, screen.rollback_spinner:GetSelected().text), 
                function() 
                    -- for command ROLLBACK
                    -- (vote_state and RequestToExecuteVoteCommand or RequestToExecuteCommand)(M.COMMAND_ENUM.ROLLBACK, screen.rollback_spinner:GetSelected().data)
                    -- for command ROLLBACK_TO
                    M.dbg('confirmed to rollback to: ', screen.rollback_spinner:GetSelected().text)
                    M.dbg('real target: data = ', screen.rollback_spinner:GetSelected().data, ', info = ', M.rollback_info[screen.rollback_spinner:GetSelected().data])

                    SelectCommandToExecute(vote_state, M.COMMAND_ENUM.ROLLBACK_TO, M.rollback_info[screen.rollback_spinner:GetSelected().data].snapshot_id)
                end
            )
        end
    end, nil)
    screen:DoInitRollbackSpinner()

    CreateButtonOfServer('regenerate_world',nil, true, function(vote_state)
        PopupConfirmDialog(
            vote_state and (S.START_A_VOTE .. S.REGENERATE_WORLD) or S.REGENERATE_WORLD, 
            S.REGENERATE_WORLD_DESC,
            function() 
                -- double popup confirm dialogs :)
                PopupInputConfirmDialog(
                    S.REGENERATE_WORLD,
                    S.REGENERATE_WORLD_REQUIRE_SERVER_NAME,
                    function(text) return text == TheNet:GetServerName() end,  
                    function() SelectCommandToExecute(vote_state, M.COMMAND_ENUM.REGENERATE_WORLD, nil) end
                )
            end
        )
    end)

    CreateButtonOfServer('vote', nil, false, function()
        for _, btn in ipairs(screen.votable_buttons) do
            local cmd = M.COMMAND_ENUM[string.upper(btn.name)]
            if cmd and HasVotePermission(cmd) then
                btn:EnableVote()
            end
        end
        screen.vote:EnableVote()
    end, function() 
            for _, btn in ipairs(screen.votable_buttons) do
                local cmd = M.COMMAND_ENUM[string.upper(btn.name)]
                if cmd and HasPermission(cmd) then
                   btn:DisableVote() 
                end
            end
            screen.vote:DisableVote()
    end)
    screen.vote:SetHoverTextAtVote(S.NO_VOTE)
    screen.vote:SetTexturesAtVote(M.ATLAS, 'no_vote_normal.tex', 'no_vote_hover.tex', 'no_vote_select.tex', 'no_vote_select.tex', nil, { .4, .4 }, { 0, 0 })
    
    CreateButtonOfServer('refresh_records', nil, true, function()
        RequestToExecuteCommand(M.COMMAND_ENUM.REFRESH_RECORDS, nil)
    end)
    
end

local HistoryPlayerScreen = Class(Screen, function(self, owner)
    Screen._ctor(self, 'HistoryPlayerScreen')
    self.owner = owner
    self.time_to_refresh = REFRESH_INTERVAL
    self.usercommandpickerscreen = nil
    self.show_player_badge = not TheFrontEnd:GetIsOfflineMode() and TheNet:IsOnlineMode()

end)

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

    if TheWorld and TheWorld.net then
        self.owner:RemoveEventCallback('issavingdirty', RequestToUpdateRollbackInfo, TheWorld.net)
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
    if #M.rollback_info ~= 0 then
        
        -- for new command ROLLBACK_TO
        if M.IsNewestRollbackSlotValid() then
            table.insert(self.rollback_slots, {text = BuildDaySeasonStringByInfoIndex(1) .. S.ROLLBACK_SPINNER_NEWEST, data = 1})
            for i = 2, #M.rollback_info do
                table.insert(self.rollback_slots, {text = BuildDaySeasonStringByInfoIndex(i) .. '(' .. tostring(i) .. ')', data = i})
            end
        else
            table.insert(self.rollback_slots, {text = BuildDaySeasonStringByInfoIndex(1) .. S.ROLLBACK_SPINNER_NEWEST, data = nil})
            for i = 2, #M.rollback_info do
                table.insert(self.rollback_slots, {text = BuildDaySeasonStringByInfoIndex(i) .. '(' .. tostring(i - 1) .. ')', data = i}) -- data keeps its real index, cuz we use new rollback command(ROLLBACK_TO)
            end

        -- old: for command ROLLBACK
        --     -- negative saving_point_index means this request is sended when
        --     -- a new save has just created, which means server will automatically skip the newest slot, 
        --     -- but this is not we wants, we should correct it 
        --     table.insert(self.rollback_slots, {text = BuildDaySeasonStringByInfoIndex(1) .. S.ROLLBACK_SPINNER_NEWEST, data = nil})
        --     for i = 2, #M.rollback_info do
        --         table.insert(self.rollback_slots, {text = BuildDaySeasonStringByInfoIndex(i) .. '(' .. tostring(i - 1) .. ')', data = -(i - 1)})
        --     end
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
        sp = Spinner(self.rollback_slots, 240, nil, {font = CHATFONT, size = 25}, nil, 'images/global_redux.xml', spinner_lean_images, true)
        sp:SetTextColour(UICOLOURS.GOLD)
        self.rollback_spinner = self.bg_rollback_spinner:AddChild(sp)

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
        if self.rollback_spinner then

            if not self.rollback:IsSelected() and not M.IsNewestRollbackSlotValid() and self.rollback_spinner:GetSelectedIndex() == 1 then
                -- disable this option
                self.rollback_spinner:SetHoverText(S.ROLLBACK_SPINNER_NEWEST_SLOT_INVALID)
                self.rollback_spinner:SetTextColour(UICOLOURS.GREY)
                self.rollback:Select()
            elseif self.rollback:IsSelected() and (M.IsNewestRollbackSlotValid() or self.rollback_spinner:GetSelectedIndex() ~= 1) then
                self.rollback_spinner:ClearHoverText()
                self.rollback_spinner:SetTextColour(UICOLOURS.GOLD)
                self.rollback:Unselect()
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

    GenerateSortedKeyList()

    local num_online_players, num_all_players  = #GetPlayerClientTable(), #sorted_userkey_list


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
        local modsStr = TheNet:GetServerModsDescription()
        self.servermods = self.root:AddChild(Text(UIFONT,25))
        self.servermods:SetPosition(20,-250,0)
        self.servermods:SetColour(1,1,1,1)
        self.servermods:SetTruncatedString(STRINGS.UI.PLAYERSTATUSSCREEN.MODSLISTPRE..' '..modsStr, 650, 146, true)

        self.bg:SetScale(.95,.95)
        self.bg:SetPosition(0,-10)
    end

    -- what does this function do?
    local function doButtonFocusHookups(playerListing)
        local buttons = {}
        if playerListing.viewprofile:IsVisible() then table.insert(buttons, playerListing.viewprofile) end
        if playerListing.kick:IsVisible() then table.insert(buttons, playerListing.kick) end
        if playerListing.ban:IsVisible() then table.insert(buttons, playerListing.ban) end
        -- if playerListing.useractions:IsVisible() then table.insert(buttons, playerListing.useractions) end

        local focusforwardset = false
        for i,button in ipairs(buttons) do
            if not focusforwardset then
                focusforwardset = true
                playerListing.focus_forward = button
            end
            if buttons[i-1] then
                button:SetFocusChangeDir(MOVE_LEFT, buttons[i-1])
            end
            if buttons[i+1] then
                button:SetFocusChangeDir(MOVE_RIGHT, buttons[i+1])
            end
        end
    end
    
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
                    local online = M.player_record[playerListing.userid].online
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
                    SelectCommandToExecute(vote_state, M.COMMAND_ENUM.KICK, playerListing.userid)
                    
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
                    SelectCommandToExecute(vote_state, M.COMMAND_ENUM.KILL, playerListing.userid)
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
                    SelectCommandToExecute(vote_state, M.COMMAND_ENUM.BAN, playerListing.userid)
                    
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
                    SelectCommandToExecute(vote_state, M.COMMAND_ENUM.KILLBAN, playerListing.userid)
                    
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
                    SelectCommandToExecute(vote_state, M.COMMAND_ENUM.ADD_MODERATOR, playerListing.userid)
                
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
                    SelectCommandToExecute(vote_state, M.COMMAND_ENUM.REMOVE_MODERATOR, playerListing.userid)
                    
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
        end
        

        local client = TheNet:GetClientTableForUser(userid)
        RecordClientData(userid, client)
        local record = M.player_record[userid]
        
        playerListing:Show()

        playerListing.displayName = (record.name or '???') .. '('.. userid ..')'

        playerListing.userid = userid
        playerListing.netid = record.netid

        playerListing.characterBadge:Set(
            GetBasePrefabFromSkin(record.skin) or '',     -- prefab name
            record.colour,                                -- colour 
            false,                                        -- is_host
            record.userflags,                             -- userflags 
            record.skin or ''                             -- base_skin
        )
        playerListing.characterBadge:Show()

        if self.show_player_badge then
            if client then
                local _, _, _, profileflair, rank = GetSkinsDataFromClientTableData(client)
                playerListing.profileFlair:SetRank(profileflair, rank)
                playerListing.profileFlair:Show()
            else
                playerListing.profileFlair:Hide()
            end
        end

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
            DumpToWebPage(userid)
        end)

        playerListing.age:SetString(
            record.age ~= nil and 
            record.age > 0 and
            (tostring(record.age) .. (record.age == 1 and STRINGS.UI.PLAYERSTATUSSCREEN.AGE_DAY or STRINGS.UI.PLAYERSTATUSSCREEN.AGE_DAYS)) 
            or ''
        )
    
        
        local button_start = 50
        local button_x = button_start
        local button_x_offset = 42

        local function ShowButtonIfAvailable(name)
            
            local cmd = M.COMMAND_ENUM[string.upper(name)]
            if cmd then
                local category = CommandApplyableForPlayerTarget(cmd, userid)
                if category == M.EXECUTION_CATEGORY.YES then
                    playerListing[name]:DisableVote()
                elseif category == M.EXECUTION_CATEGORY.VOTE_ONLY then
                    playerListing[name]:EnableVote()
                else -- category == M.EXECUTION_CATEGORY.NO
                    -- don't show the button
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

        doButtonFocusHookups(playerListing)
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

    DoInitScreenToggleButton(self, 2)
    DoInitServerRelatedCommnadButtons(self)
    if TheWorld and TheWorld.net then
        self.owner:ListenForEvent('issavingdirty', RequestToUpdateRollbackInfo, TheWorld.net)
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

function PlayerStatusScreen:DoInit(ClientObjs)
    
    OldDoInit(self, ClientObjs)
    
    if not M.has_queried then
        QueryPermission()
        M.has_queried = true
    end
    
    -- once the request is sent, 
    -- rpc will wait for a respose from server and re-init the screen in the callback while the reponse is received
    if HasPermission(M.COMMAND_ENUM.QUERY_HISTORY_PLAYERS) then
        DoInitScreenToggleButton(self, 1)
    end

end
