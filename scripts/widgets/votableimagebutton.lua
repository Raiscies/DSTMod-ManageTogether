
-- GLOBAL.setmetatable(env, {__index = function(t, k) return GLOBAL.rawget(GLOBAL, k) end})


local Widget = require 'widgets/widget'
local Image = require 'widgets/image'
local ImageButton = require 'widgets/imagebutton'

local VotableImageButton = Class(ImageButton, function(self, ...)
    ImageButton._ctor(self, ...)

    self.normal_textures = {...}
    self.vote_state = false
    self.vote_tip_image = self:AddChild(Image('images/button_icons.xml', 'vote.tex'))
    self.vote_tip_image:SetPosition(-11,-10,0)
    self.vote_tip_image:SetScale(.4)
    self.vote_tip_image:Hide()

    self.hover_text_at_vote = ''
    self.hover_text_at_normal = ''
    
end)

function VotableImageButton:SetTexturesAtNormal(...)
    if select('#', ...) == 0 then
        -- we can't set the normal textures to nil 
        -- self.normal_textures = nil
        return
    end
    self.normal_textures = {...}
end

function VotableImageButton:SetTexturesAtVote(...)
    if select('#', ...) then
        self.vote_textures = nil 
        return
    end
    self.vote_textures = {...}
end


function VotableImageButton:SetOnClick(fn)
    self._base.SetOnClick(self, function()
        fn(self.vote_state)
    end)
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

function VotableImageButton:UpdateVoteState(state, force_update)
    if state == nil then
        -- always update
        state = self.vote_state
    else
        if self.vote_state ~= state then
            self.vote_state = state
        elseif not force_update then 
            return
        end
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

----------------------------------------------

-- local VotableStatefulImageButton = Class(VotableImageButton, function(self, default_state_name, ...)
--     VotableImageButton._ctor(self, ...)
--     self.states = {}


--     if select('#', ...) ~= 0 and default_state_name == nil then 
--         self:AddState(self.current_state, ...)
--     end
--     self.current_state = default_state_name or 'default'
-- end)

-- function VotableStatefulImageButton:SetStateTexturesAtNormal(state, ...)
--     if not self.states[state] then return end
--     self.states[state].non_vote.textures = {...}

--     if self.current_state == state then
--         self._base.SetTexturesAtNormal(self, ...)
--     end
-- end
-- function VotableStatefulImageButton:SetStateTexturesAtVote(state, ...)
--     if not self.states[state] then return end
--     self.states[state].vote.textures = {...}

--     if self.current_state == state then
--         self._base.SetTexturesAtVote(self, ...)
--     end
-- end


-- function VotableStatefulImageButton:StateExists(state)
--     return self.states[state] ~= nil
-- end

-- function VotableStatefulImageButton:AddState(state, ...)
--     if self:StateExists(state) then
--         return false
--     end 
--     self.states[state] = {
--         non_vote = {
--             textures = {...}
--         }, 
--         vote = {}
--     }
--     return true
-- end

-- function VotableStatefulImageButton:SetState(state, non_vote_content, vote_content)
--     if not self:StateExists(state) then
--         return 
--     end 
--     self.states[state] = {
--         non_vote = non_vote_content,
--         vote = vote_content
--     }
--     return true
-- end

-- function VotableStatefulImageButton:SwitchToState(state, force_update)
--     if not self:StateExists(state) or (self.current_state == state and not force_update) then
--         return self.current_state
--     end
--     local nonvote, vote = self.states[state].non_vote, self.states[state].vote
--     -- replace the textures, onclick functions and hover texts
--     self._base.SetTexturesAtNormal(self, unpack(nonvote.textures))
--     if vote.textures then
--         self._base.SetTexturesAtVote(self, unpack(vote.textures)) 
--     end
--     self._base.SetOnClickAtNormal(self, nonvote.onclick)
--     self._base.SetOnClickAtVote(self, vote.onclick)
--     self._base.SetHoverTextAtNormal(self, nonvote.hover_text, nonvote.hover_text_params)
--     self._base.SetHoverTextAtVote(self, vote.hover_text, vote.hover_text_params) 

--     self.current_state = state

--     return state
-- end


-- -- goto the next state(the state order is unsequenced)
-- function VotableStatefulImageButton:NextState()
--     next_state = next(self.states, self.current_state) or next(self.states)
--     self:SwitchToState(next_state)
--     return next_state
-- end

-- -- use this function, button will ignore other onclick functions
-- function VotableStatefulImageButton:SetOnClick(fn)
--     self._base.SetOnClick(self, function(vote_state)
--         fn(vote_state, self.current_state)
--     end)
-- end

-- function VotableStatefulImageButton:SetStateHoverTextAtNormal(state, text, params)
--     if not self:StateExists(state) then
--         return
--     end
--     self.states[state].non_vote.hover_text = text
--     self.states[state].non_vote.hover_text_params = params
--     if state == self.current_state then
--         self._base.SetHoverTextAtNormal(self, text, params)
--     end
-- end
-- function VotableStatefulImageButton:SetStateHoverTextAtVote(state, text, params)
--     if not self:StateExists(state) then
--         return
--     end
--     self.states[state].vote.hover_text = text
--     self.states[state].vote.hover_text_params = params

--     if state == self.current_state then
--         self._base.SetHoverTextAtVote(self, text, params)
--     end
-- end


-- function VotableStatefulImageButton:SetHoverTextAtVote(text, params)
--     self:SetStateHoverTextAtNormal('default', text, params)
-- end
-- function VotableStatefulImageButton:SetHoverTextAtNormal(text, params)
--    self:SetStateHoverTextAtVote('default', text, params)
-- end

-- a binary states button: ON(true)/OFF(false)
local VotableImageSwitch = Class(ImageButton, function(self, on_state_res, off_state_res)
    ImageButton._ctor(self)
    
    self.switch_state = false
    self.vote_state = false
    self.vote_tip_image = self:AddChild(Image('images/button_icons.xml', 'vote.tex'))
    self.vote_tip_image:SetPosition(-11,-10,0)
    self.vote_tip_image:SetScale(.4)
    self.vote_tip_image:Hide()

    self.state_res = {
        [false] = off_state_res, 
        [true] = on_state_res
    }
    self:Update()
    -- res format:
    -- {
    --      textures = {...},
    --      textures_at_vote = {...}, -- ignorable
    --      hover_text = {
    --          text = '...', 
    --          params = {...}
    --      },
    --      hover_text_at_vote = {
    --          text = '...', 
    --          params = {...}
    --      },
end)

function VotableImageSwitch:SetTurnOnStateTextures(tex, tex_at_vote)
    self.state_res[true].textures = tex
    self.state_res[true].textures_at_vote = tex_at_vote
end
function VotableImageSwitch:SetTurnOffStateTextures(tex, tex_at_vote)
    self.state_res[false].textures = tex
    self.state_res[false].textures_at_vote = tex_at_vote
end
function VotableImageSwitch:SetTurnOnStateHoverText(text, params, text_at_vote, params_at_vote)
    self.state_res[true].hover_text = {
        text = text, 
        params = params
    }
    self.state_res[true].hover_text_at_vote = {
        text = text_at_vote, 
        params = params_at_vote
    }
end
function VotableImageSwitch:SetTurnOffStateHoverText(text, params, text_at_vote, params_at_vote)
    self.state_res[false].hover_text = {
        text = text, 
        params = params
    }
    self.state_res[false].hover_text_at_vote = {
        text = text_at_vote, 
        params = params_at_vote
    }
end

function VotableImageSwitch:SetOnClick(fn)
    self._base.SetOnClick(self, function()
        fn(self.switch_state, self.vote_state)
    end)
end

function VotableImageSwitch:Update()
    local res = self.state_res[self.switch_state]
    
    if self.vote_state then
        if not res.textures_at_vote then
            self:SetTextures(unpack(res.textures))
            self.vote_tip_image:Show()
        else
            self:SetTextures(unpack(res.textures_at_vote))
            self.vote_tip_image:Hide()
        end
        local hover_text, hover_text_params = '', {}
        if res.hover_text_at_vote then
            hover_text, hover_text_params = res.hover_text_at_vote.text, res.hover_text_at_vote.params 
        elseif res.hover_text then
            hover_text, hover_text_params = res.hover_text.text, res.hover_text.params
        end
        self:SetHoverText(hover_text, unpack(hover_text_params))
    else
        self:SetTextures(unpack(res.textures))
        local hover_text, hover_text_params = '', {}
        if res.hover_text then
            hover_text, hover_text_params = res.hover_text.text, res.hover_text.params
        end
        self:SetHoverText(hover_text, unpack(hover_text_params))
        self.vote_tip_image:Hide()
    end
end

function VotableImageSwitch:Switch()
    self.switch_state = not self.switch_state
    self:Uptate()
    return self.switch_state
end
function VotableImageSwitch:TurnOn()
    if not self.switch_state then
        self.switch_state = true
        self:Update()
    end
end
function VotableImageSwitch:TurnOff()
    if self.switch_state then
        self.switch_state = false
        self:Update()
    end
end
function VotableImageSwitch:State()
    return self.switch_state
end
function VotableImageSwitch:VoteState()
    return self.vote_state
end
function VotableImageSwitch:EnableVote()
    if not self.vote_state then
        self.vote_state = true
        self:Update()
    end
end
function VotableImageSwitch:DisableVote()
    if self.vote_state then
        self.vote_state = false
        self:Uptate()
    end
end

return {VotableImageButton, VotableImageSwitch}