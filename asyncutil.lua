require 'scheduler'

-- if GLOBAL then    
GLOBAL.setmetatable(env, {__index = function(t, k) return GLOBAL.rawget(GLOBAL, k) end})
-- end

local M = GLOBAL.manage_together
local dbg = M.dbg
local log = M.log

local create = coroutine.create
local yield = coroutine.yield
local resume = coroutine.resume
local status = coroutine.status

-- scheduler.lua
local hibernate = Hibernate
local wake = WakeTask
local sleep = Sleep

-- a future class, maintain a return value from a coroutine when it is finished to execute
local Future = Class(function(self, fn)
    local value_ = nil
    local valid_ = false
    local callback_ = nil
    
    local waiting_tasks_ = {}

    self.fn = fn


    local function add_waiting_task()
        table.insert(waiting_tasks_, staticScheduler.tasks[coroutine.running()])
    end
    local function wake_all_waiting_tasks()
        for _, t in ipairs(waiting_tasks_) do
            wake(t)
        end
    end

    -- this task will be packaged to scheduler.Task - a coroutine
    function self:get_nowait()
        return value_ ~= nil and unpack(value_)
    end

    function self:wait()
        add_waiting_task()

        -- wait for the future's return value
        repeat
            hibernate()
        until valid_
    end
    function self:wait_for(time)
        if not time then time = 0 end

        add_waiting_task()
        sleep(time)
        -- coroutine has slept for time second or being interrupted for finished task 
    end
    function self:set_callback(cb)
        if not type(cb) == 'function' then
            return false, callback_
        end
        local old = callback_
        callback_ = cb
        return true, old
    end
    function self:get_callback()
        return callback_
    end

    function self:get()
        if not valid_ then
            self:wait()
        end
        return self:get_nowait()
    end

    function self:get_before(time)
        if not valid_ then
            self:wait_for(time)
        end
        return self:get_nowait()
    end

    function self:valid()
        return valid_
    end

    self.target = function(param)
        value_ = {fn(unpack(param))} -- target is asynced with main thread, but sync with its Task(fn) thread
        valid_ = true
        
        wake_all_waiting_tasks()
        if callback_ then
            dbg('async future value: ', value_)
            dbg('future.get_nowait: ', self:get_nowait())
            callback_(self:get_nowait())
        end
    end
    
end)


--[[
    usage:

    local val = async(function(...)
        function will run immediactly, 
        it is possible to be blocked, 
        but future function will also return a future object immediactly
        use future object to get the function's return value

        function logic...
    end, params...)


]]


-- async is non-static 
function M.async(fn, ...)
    local future = Future(fn)
    StartStaticThread(future.target, nil, {...})
    return future
end
function M.async_nonstatic(fn, ...)
    local future = Future(fn)
    StartThread(future.target, nil, {...})
    return future
end

local async = M.async
local async_nonstatic = M.async_nonstatic

function M.execute_in_time(time, fn, ...)
    -- local scheduler = staticScheduler
    staticScheduler:ExecuteInTime(time, fn, nil, ...)
end

function M.execute_in_time_nonstatic(time, fn, ...)
    -- but normal scheduler will pause when server is paused 
    -- while staticScheduler will ignore it 
    scheduler:ExecuteInTime(time, fn, nil, ...)
end


-- a warpper of immediactate values
function M.future_value(...)
    local future = Future(function(...)
        return ...
    end)
    future:run_task(...)
    return future
end

function M.is_future(val)
    return Future.is_instance(val)
end


local RPC_CATEGORY
if M.DEBUG then
    RPC_CATEGORY = {
        SERVER = 'server', 
        CLIENT = 'client', 
        SHARD  = 'shard'
    }

else
    RPC_CATEGORY = {
        SERVER = 1, 
        CLIENT = 2, 
        SHARD  = 3
    }
end

local AsyncRPCManager = Class(function(self, namespace, context_expire_timeout)
    self.namespace = namespace
    self.timeout = context_expire_timeout

    self.rpc_names = {
        [RPC_CATEGORY.SERVER] = {}, 
        [RPC_CATEGORY.CLIENT] = {}, 
        [RPC_CATEGORY.SHARD ] = {}, 
    }


    self.contexts = {
        [RPC_CATEGORY.SERVER] = {}, 
        [RPC_CATEGORY.CLIENT] = {}, 
        [RPC_CATEGORY.SHARD ] = {}, 
    }

    self.context_max_id = {
        [RPC_CATEGORY.SERVER] = 1, 
        [RPC_CATEGORY.CLIENT] = 1, 
        [RPC_CATEGORY.SHARD ] = 1, 

    }

    self:AddClientRPC('RESULT_SERVER_RPC', function(id, ...)
        --  client -serverRPC-> server (call) 
        --  server -clientRPC-> client (return value)

        -- here is client side
        if not self:SetContextResult(RPC_CATEGORY.SERVER, id, {...}) then
            dbg('failed to get return value from server rpc, {id = }, context is not exists')
            return
        end
        wake(self.contexts[RPC_CATEGORY.SERVER][id].task)
    end, true)
    
    -- async return value handler
    self:AddServerRPC('RESULT_CLIENT_RPC', function(player, id, ...)
        --  server -clientRPC-> clients(call) could be more than one target 
        --  clients -serverRPC-> server(return value)

        -- here is server side
        if not self:AddContextResult(RPC_CATEGORY.CLIENT, id, player, {...}) then
            dbg('failed to get return value from client rpc, {id = }, context is not exists')
            return
        end
        local context = self.contexts[RPC_CATEGORY.CLIENT][id]
        context.expected_response_count = context.expected_response_count - 1
        if context.expected_response_count <= 0 then
            wake(context.task)
        end
    end, true)
    
    
    self:AddShardRPC('RESULT_SHARD_RPC', function(sender_shard_id, id, ...)
        -- shard1 -shardRPC-> shardn (call) could be more than one target
        -- shardnetworking -shardRPC-> shard1 (return value)
        if not self:AddContextResult(RPC_CATEGORY.SHARD, id, sender_shard_id, {...}) then
            dbg('failed to get return value from shard rpc, {id = }, context is not exists')
            return
        end
        
        local context = self.contexts[RPC_CATEGORY.SHARD][id]
        context.expected_response_count = context.expected_response_count - 1

        if context.expected_response_count <= 0 then
            wake(context.task)
        end
    end, true)
end)

function AsyncRPCManager:CreateContext(category, the_task, expected_response_count)
    local this_id = self.context_max_id[category]
    self.context_max_id[category] = this_id + 1
    self.contexts[category][this_id] = {
        task = the_task,
        result = nil,
        expected_response_count = expected_response_count or 1
    }
    return this_id
end
function AsyncRPCManager:SetContextResult(category, id, value)
    if not self.contexts[category][id] then
        return false
    end
    self.contexts[category][id].result = value
    return true
end

function AsyncRPCManager:AddContextResult(category, id, key, value)
    local context = self.contexts[category][id]
    if not context then
        return false
    end
    if not context.result then
        context.result = {}
    end
    context.result[key] = value
    return true
end

function AsyncRPCManager:PopContextResult(category, id)
    local context = self.contexts[category][id]
    if not context then
        return nil, nil
    end
    self.contexts[category][id] = nil

    return context.result, context.expected_response_count -- expected_response_count now is equals to missing response count
end

function AsyncRPCManager:AddServerRPC(name, fn, no_response)
    if no_response then
        AddModRPCHandler(self.namespace, name, fn)
    else
        AddModRPCHandler(self.namespace, name, function(player, id, ...)
            -- here is server side
            -- return results to client
            dbg('on server rpc: {player = }, {id = }, {arg = }')
            async(fn, player, ...):set_callback(function(...)
                local result = {...}
                if #result ~= 0 then
                    -- return value is not empty
                    self:SendRPCToClient('RESULT_SERVER_RPC', player.userid, id, ...)
                end
            end)
        end)
    end

    self.rpc_names[RPC_CATEGORY.SERVER][name] = {
        name = name, 
        no_response = no_response
    }
end

function AsyncRPCManager:AddClientRPC(name, fn, no_response)
    if no_response then
        AddClientModRPCHandler(self.namespace, name, fn)
    else
        AddClientModRPCHandler(self.namespace, name, function(id, ...)
            -- here is client side
            -- return results to server
            async(fn, ...):set_callback(function(...)
                local result = {...}
                if #result ~= 0 then
                    self:SendRPCToServer('RESULT_CLIENT_RPC', id, ...)
                end
            end)
        end)
    end
    self.rpc_names[RPC_CATEGORY.CLIENT][name] = {
        name = name,
        no_response = no_response
    }
end

function AsyncRPCManager:AddShardRPC(name, fn, no_response)
    if no_response then
        AddShardModRPCHandler(self.namespace, name, fn)
    else
        AddShardModRPCHandler(self.namespace, name, function(sender_shard_id, id, ...)
            async(fn, sender_shard_id, ...):set_callback(function(...)
                local result = {...}
                if #result ~= 0 then
                    self:SendRPCToShard('RESULT_SHARD_RPC', sender_shard_id, id, ...) 
                end
                
            end)
        end)
    end
    self.rpc_names[RPC_CATEGORY.SHARD][name] = {
        name = name, 
        no_response = no_response
    }
end

local send_server_rpc_impl = function(rpc_manager, name, ...)
    local id = rpc_manager:CreateContext(RPC_CATEGORY.SERVER, staticScheduler.tasks[coroutine.running()], 1)
    
    dbg('sending async server RPC: {name = }')

    SendModRPCToServer(GetModRPC(rpc_manager.namespace, name), id, ...)
    
    sleep(rpc_manager.timeout)
    local result_table, missing_response_count = rpc_manager:PopContextResult(RPC_CATEGORY.SERVER, id)

    -- server rpc is always only one responsor, so just returns an unpacked result
    return missing_response_count, (result_table and unpack(result_table))
end

local send_client_rpc_impl = function(rpc_manager, name, target, expected_response_count, ...)
    local id = rpc_manager:CreateContext(RPC_CATEGORY.CLIENT, staticScheduler.tasks[coroutine.running()], expected_response_count)

    dbg('sending async client RPC: {name = }')

    SendModRPCToClient(GetClientModRPC(rpc_manager.namespace, name), target, id, ...)

    sleep(rpc_manager.timeout)
    local result_table, missing_response_count = rpc_manager:PopContextResult(RPC_CATEGORY.CLIENT, id)
    -- client rpc could have more than one responsor, directly return a result_table(or nil)
    return missing_response_count, result_table
end

local send_shard_rpc_impl = function(rpc_manager, name, target, expected_response_count, ...)
    local id = rpc_manager:CreateContext(RPC_CATEGORY.SHARD, staticScheduler.tasks[coroutine.running()], expected_response_count)

    dbg('sending async shard RPC: {name = }')

    SendModRPCToShard(GetShardModRPC(rpc_manager.namespace, name), target, id, ...)
    
    sleep(rpc_manager.timeout)
    local result_table, missing_response_count = rpc_manager:PopContextResult(RPC_CATEGORY.SHARD, id)
    -- client rpc could have more than one responsor, directly return a result_table(or nil)
    return missing_response_count, result_table
end

function AsyncRPCManager:SendRPCToServer(name, ...)
    local rpc = self.rpc_names[RPC_CATEGORY.SERVER][name]
    if not rpc then
        dbg('error: failed to send a RPC to server: RPC {name } not found.')
        return nil, false
    end
    if rpc.no_response then
        dbg('sending no response server RPC: {name = }')
        SendModRPCToServer(GetModRPC(self.namespace, name), ...)
        return nil, true
    else
        dbg('try asyncly send server RPC, {name = }')
        return async(send_server_rpc_impl, self, name, ...), true
    end
end

function AsyncRPCManager:SendRPCToClient(name, target, ...)
    local rpc = self.rpc_names[RPC_CATEGORY.CLIENT][name]
    if not rpc then
        dbg('error: failed to send a RPC to client {target = } RPC {name } not found.')
        return nil, false
    end
    if rpc.no_response then
        dbg('sending no response client RPC: {name = }')
        SendModRPCToClient(GetClientModRPC(self.namespace, name), target, ...)
        return nil, true
    end
    
    -- calculate the response count that sender should receive
    local expected_response_count
    if target == nil then
        expected_response_count = TheNet:GetPlayerCount() -- non-public api
    elseif type(target) == 'string' then
        expected_response_count = 1
    elseif type(target) == 'table' then
        expected_response_count = #target
    else
        dbg('bad RPC target: ', target)
        return nil, false
    end
    dbg('try asyncly send client RPC, {name = }, {expected_response_count = }')
    return async(send_client_rpc_impl, self, name, target, expected_response_count, ...), true
end

function AsyncRPCManager:SendRPCToShard(name, target, ...)
    local rpc = self.rpc_names[RPC_CATEGORY.SHARD][name]
    if not rpc then
        dbg('error: failed to send a RPC to shard, {target = }: RPC {name } not found.')
        return nil, false
    end
    if rpc.no_response then
        -- here, arg1 is a normal argument of rpc
        dbg('sending no response shard RPC: {name = }')
        SendModRPCToShard(GetShardModRPC(self.namespace, name), target, ...)
        return nil, true
    end
    
    local expected_response_count
    if target == nil then
        expected_response_count = GetTableSize(ShardList) + 1 -- shardnetworking.lua -- + 1: including sender itself
    elseif type(target) == 'string' then
        expected_response_count = 1
    elseif type(target) == 'table' then
        expected_response_count = #target
    else
        dbg('bad RPC {target: }')
        return nil, false
    end

    dbg('try asyncly send shard RPC, {name = }, {expected_response_count = }')
    return async(send_shard_rpc_impl, self, name, target, expected_response_count, ...), true

end


M.RPCManager = AsyncRPCManager('manage_together', M.RPC_RESPONSE_TIMEOUT)

M.AddServerRPC = function(...) return M.RPCManager:AddServerRPC(...) end
M.AddClientRPC = function(...) return M.RPCManager:AddClientRPC(...) end
M.AddShardRPC = function(...) return M.RPCManager:AddShardRPC(...) end
M.SendRPCToServer = function(...) return M.RPCManager:SendRPCToServer(...) end
M.SendRPCToClient = function(...) return M.RPCManager:SendRPCToClient(...) end
M.SendRPCToShard  = function(...) return M.RPCManager:SendRPCToShard(...)  end