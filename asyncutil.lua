require 'scheduler'

GLOBAL.setmetatable(env, {__index = function(t, k) return GLOBAL.rawget(GLOBAL, k) end})

local M = GLOBAL.manage_together
local dbg = M.dbg
local log = M.log

local create = coroutine.create
local yield = coroutine.yield
local resume = coroutine.resume
local status = coroutine.status

-- scheduler.lua
local hibernate = Hibernate -- hibernate a task until it is being wake up
local wake = WakeTask
local sleep = Sleep

-- a future class, maintain a return value from a coroutine when it is finished to execute
local Future = Class(function(self, fn)
    local value_ = nil
    local valid_ = false
    local callback_ = nil
    
    local waiting_tasks_ = {}

    self.fn = fn

    self.target = function(param)
        value_ = {self.fn(unpack(param))} -- target is asynced with main thread, but sync with its Task(fn) thread
        valid_ = true
        
        self:wake_all_waiting_tasks()
        if self.callback_ then
            self.callback_(self:get_nowait())
        end
    end
    

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
    staticScheduler:ExecuteInTime(time, fn, staticScheduler:GetCurrentTask().id, ...)
end

function M.execute_in_time_nonstatic(time, fn, ...)
    -- but normal scheduler will pause when server is paused 
    -- while staticScheduler will ignore it 
    scheduler:ExecuteInTime(time, fn, scheduler:GetCurrentTask().id, ...)
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
            dbg('failed to get return value from server rpc, id =', id, ', context is not exists')
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
            dbg('failed to get return value from client rpc, id =', id, ', context is not exists')
            return
        end
        local context = self.contexts[RPC_CATEGORY.CLIENT][id]
        context.attempted_response_count = context.attempted_response_count - 1
        if context.attempted_response_count <= 0 then
            wake(context.task)
        end
    end, true)
    
    
    self:AddShardRPC('RESULT_SHARD_RPC', function(sender_shard_id, id, ...)
        -- shard1 -shardRPC-> shardn (call) could be more than one target
        -- shardnetworking -shardRPC-> shard1 (return value)
        if not self:AddContextResult(RPC_CATEGORY.SHARD, id, sender_shard_id, {...}) then
            dbg('failed to get return value from shard rpc, id =', id, ', context is not exists')
            return
        end
        
        local context = self.contexts[RPC_CATEGORY.SHARD][id]
        context.attempted_response_count = context.attempted_response_count - 1

        if context.attempted_response_count <= 0 then
            wake(context.task)
        end
    end, true)
end)

function AsyncRPCManager:CreateContext(category, the_task, attempted_response_count)
    local this_id = self.context_max_id[category]
    self.context_max_id[category] = this_id + 1
    self.contexts[category][this_id] = {
        task = the_task,
        result = nil,
        attempted_response_count = attempted_response_count or 1
    }
    return this_id
end
function AsyncRPCManager:SetContextResult(category, id, value)
    if not self.contexts[category][id] then
        return false
    end
    self.contexts[category][id].result = {value}
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

    return context.result, context.attempted_response_count -- attempted_response_count now is equals to missing response count
end

function AsyncRPCManager:AddServerRPC(name, fn, no_response)
    if no_response then
        -- dbg('registering server RPC: ', name, ', with no response')
        AddModRPCHandler(self.namespace, name, fn)
    else
        -- dbg('registering server RPC: ', name, ', with response')
        AddModRPCHandler(self.namespace, name, function(player, ...)
            -- here is server side
            -- return results to client
            local result = {fn(player, ...)}
            if #result ~= 0 then
                -- return value is not empty
                self:SendRPCToClient('RESULT_SERVER_RPC', player.userid, 1, unpack(result))
            end
        end)
    end

    self.rpc_names[RPC_CATEGORY.SERVER][name] = {
        name = name, 
        no_response = no_response
    }
end

function AsyncRPCManager:AddClientRPC(name, fn, no_response)
    if no_response then
        -- dbg('registering client RPC: ', name, ', with no response')
        AddClientModRPCHandler(self.namespace, name, fn)
    else
        -- dbg('registering client RPC: ', name, ', with response')
        AddClientModRPCHandler(self.namespace, name, function(...)
            -- here is client side
            -- return results to server
            local result = {fn(...)}
            if #result ~= 0 then
                self:SendRPCToServer('RESULT_CLIENT_RPC', unpack(result))
            end
        end)
    end
    self.rpc_names[RPC_CATEGORY.CLIENT][name] = {
        name = name,
        no_response = no_response
    }
end

function AsyncRPCManager:AddShardRPC(name, fn, no_response)
    if no_response then
        -- dbg('registering shard RPC: ', name, ', with no response')
        AddShardModRPCHandler(self.namespace, name, fn)
    else
        -- dbg('registering shard RPC: ', name, ', with response')
        AddShardModRPCHandler(self.namespace, name, function(sender_shard_id, ...)
            local result = {fn(sender_shard_id, ...)}
            if #result ~= 0 then
                self:SendRPCToShard('RESULT_SHARD_RPC', sender_shard_id, 1, unpack(result)) 
            end
        end)
    end
    self.rpc_names[RPC_CATEGORY.SHARD][name] = {
        name = name, 
        no_response = no_response
    }
end

local do_send_rpc = function(rpc_manager, category, rpc_name, attempted_response_count, ...)
    local id = rpc_manager:CreateContext(category, staticScheduler.tasks[coroutine.running()], attempted_response_count)

    dbg('sending async RPC: category =', category, ', name =', rpc_name)

    if category == RPC_CATEGORY.SERVER then
        SendModRPCToServer(GetModRPC(rpc_manager.namespace, rpc_name), id, ...)
    elseif category == RPC_CATEGORY.CLIENT then
        SendModRPCToClient(GetClientModRPC(rpc_manager.namespace, rpc_name), id, ...)
    elseif category == RPC_CATEGORY.SHARD then
        SendModRPCToShard(GetShardModRPC(rpc_manager.namespace, rpc_name), id, ...)
    else
        dbg('error: in do_send_rpc: category', category, ' is bad')
        rpc_manager:PopContextResult(category, id)
        return
    end

    local timeout = rpc_manager.timeout
    
    sleep(timeout)
    return rpc_manager:PopContextResult(category, id)
end

function AsyncRPCManager:SendRPCToServer(name, ...)
    local rpc = self.rpc_names[RPC_CATEGORY.SERVER][name]
    if not rpc then
        dbg('error: failed to send a RPC to server: RPC name(', name, ') not found.')
        return nil, false
    end
    if rpc.no_response then
        dbg('sending RPC: category =', RPC_CATEGORY.SERVER, ', name =', name)
        SendModRPCToServer(GetModRPC(self.namespace, name), ...)
        return nil, true
    else
        dbg('try asyncly send RPC...')
        return async(do_send_rpc, self, RPC_CATEGORY.SERVER, name, 1, ...), true
    end
end

function AsyncRPCManager:SendRPCToClient(name, target, ...)
    local rpc = self.rpc_names[RPC_CATEGORY.CLIENT][name]
    if not rpc then
        dbg('error: failed to send a RPC to client(', target, '): RPC name(', name, ') not found.')
        return nil, false
    end
    if rpc.no_response then
        dbg('sending RPC: category =', RPC_CATEGORY.CLIENT, ', name =', name)
        SendModRPCToClient(GetClientModRPC(self.namespace, name),  target, ...)
        return nil, true
    end
    
    local attempted_response_count
    if target == nil then
        attempted_response_count = #GetPlayerClientTable()
    elseif type(target) == 'string' then
        attempted_response_count = 1
    elseif type(target) == 'table' then
        attempted_response_count = #target
    else
        dbg('bad RPC target: ', target)
        return nil, false
    end
    dbg('try asyncly send RPC...')
    return async(do_send_rpc, self, RPC_CATEGORY.CLIENT, name, target, attempted_response_count, ...), true
end

function AsyncRPCManager:SendRPCToShard(name, target, ...)
    local rpc = self.rpc_names[RPC_CATEGORY.SHARD][name]
    if not rpc then
        dbg('error: failed to send a RPC to shard(', target, '): RPC name(', name, ') not found.')
        return nil, false
    end
    if rpc.no_response then
        -- here, arg1 is a normal argument of rpc
        dbg('sending RPC: category =', RPC_CATEGORY.SHARD, ', name =', name)
        SendModRPCToShard(GetShardModRPC(self.namespace, name), target, ...)
        return nil, true
    end
    
    local attempted_response_count
    if target == nil then
        attempted_response_count = #Shard_GetConnectedShards()
    elseif type(target) == 'string' then
        attempted_response_count = 1
    elseif type(target) == 'table' then
        attempted_response_count = #target
    else
        dbg('bad RPC target: ', target)
        return nil, false
    end

    dbg('try asyncly send RPC...')
    return async(do_send_rpc, self, RPC_CATEGORY.SHARD, name, target, attempted_response_count, ...), true

end


M.RPCManager = AsyncRPCManager('manage_together', M.RPC_RESPONSE_TIMEOUT)

M.AddServerRPC = function(...) M.RPCManager:AddServerRPC(...) end
M.AddClientRPC = function(...) M.RPCManager:AddClientRPC(...) end
M.AddShardRPC = function(...) M.RPCManager:AddShardRPC(...) end
M.SendRPCToServer = function(...) M.RPCManager:SendRPCToServer(...) end
M.SendRPCToClient = function(...) M.RPCManager:SendRPCToClient(...) end
M.SendRPCToShard  = function(...) M.RPCManager:SendRPCToShard(...)  end