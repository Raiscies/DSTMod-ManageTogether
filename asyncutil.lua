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
    self._value = nil
    self._valid = false
    self._callback = nil
    self._waiting_tasks = {}

    self._fn = fn
    
end)

local function add_waiting_task(future)
    table.insert(future._waiting_tasks, staticScheduler.tasks[coroutine.running()])
end
local function wake_all_waiting_tasks(future)
    for _, t in ipairs(future._waiting_tasks) do
        wake(t)
    end
    future._waiting_tasks = {}
end

-- this task will be packaged to scheduler.Task - a coroutine
function Future:get_nowait()
    -- return _value ~= nil and unpack(_value)
    if self._value ~= nil then
        return unpack(self._value)
    end
    return nil
end

function Future:wait()
    add_waiting_task(self)

    -- wait for the future's return value
    repeat
        hibernate()
    until self._valid
end
function Future:wait_for(time)
    if not time then time = 0 end

    add_waiting_task(self)
    sleep(time)
    -- coroutine has slept for time second or being interrupted for finished task 
end
function Future:set_callback(cb)
    if not type(cb) == 'function' then
        return false, self._callback
    end
    local old = self._callback
    self._callback = cb
    return true, old
end
function Future:get_callback()
    return self._callback
end

function Future:get()
    if not self._valid then
        self:wait()
    end
    return self:get_nowait()
end

function Future:get_within(time)
    if not self._valid then
        self:wait_for(time)
    end
    return self:get_nowait()
end

function Future:valid()
    return self._valid
end

function Future._target(param)
    local self = param[1]
    self._value = {self._fn(unpack(param, 2))} -- target is asynced with main thread, but sync with its Task(fn) thread
    self._valid = true
    
    wake_all_waiting_tasks(self)
    if self._callback then
        self._callback(self:get_nowait())
    end
end

local promise_target = function(future)
    repeat
        hibernate()
    until future._valid

    if future._callback then
        future._callback(future:get_nowait())
    end
end

-- a promise class
local Promise = Class(function(self)
    self._future = Future()
    self._future._target = promise_target
    
end)


function Promise:set_value(...)
    self._future._value = {...}
    self._future._valid = true
    wake_all_waiting_tasks(self._future)
end

function Promise:has_set()
    return self._future:valid()
end

function Promise:get_future()
    return self._future
end
M.Promise = Promise


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

function M.async(fn, ...)
    local future = Future(fn)
    StartStaticThread(future._target, nil, {future, ...})
    return future
end
function M.async_nonstatic(fn, ...)
    local future = Future(fn)
    StartThread(future._target, nil, {future, ...})
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

        local context = self.contexts[RPC_CATEGORY.SERVER][id]
        context.expected_response_count = 0
        wake(context.task)
        
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

        -- note: type(sender_shard_id) == 'number', however we use a string to specify the shard target we want to send
        if not self:AddContextResult(RPC_CATEGORY.SHARD, id, tostring(sender_shard_id), {...}) then
            dbg('failed to get return value from shard rpc, {id = }, context is not exists')
            return
        end
        local context = self.contexts[RPC_CATEGORY.SHARD][id]
        context.expected_response_count = context.expected_response_count - 1
        if context.expected_response_count <= 0 then
            wake(context.task)
        end
        dbg('on RESULT_SHARD_RPC: {sender_shard_id = }, {id = } {context.expected_response_count = }, args: ', ...)
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
            
            async(fn, player, ...):set_callback(function(...)
                if select('#', ...) ~= 0 then
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
                if select('#', ...) ~= 0 then
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
                dbg('on sended shard rpc: return result to other shard: sender_shard_id = ', sender_shard_id, ', id = ', id, 'args: ', ...)
                if select('#', ...) ~= 0 then
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

    SendModRPCToServer(GetModRPC(rpc_manager.namespace, name), id, ...)
    
    sleep(rpc_manager.timeout)
    local result_table, missing_response_count = rpc_manager:PopContextResult(RPC_CATEGORY.SERVER, id)

    -- server rpc is always only one responsor, so just returns an unpacked result
    return missing_response_count, (result_table and unpack(result_table))
end

local send_client_rpc_impl = function(rpc_manager, name, target, expected_response_count, ...)
    local id = rpc_manager:CreateContext(RPC_CATEGORY.CLIENT, staticScheduler.tasks[coroutine.running()], expected_response_count)

    SendModRPCToClient(GetClientModRPC(rpc_manager.namespace, name), target, id, ...)

    sleep(rpc_manager.timeout)
    local result_table, missing_response_count = rpc_manager:PopContextResult(RPC_CATEGORY.CLIENT, id)
    -- client rpc could have more than one responsor, directly return a result_table(or nil)
    return missing_response_count, result_table
end

local send_shard_rpc_impl = function(rpc_manager, name, target, expected_response_count, ...)
    local id = rpc_manager:CreateContext(RPC_CATEGORY.SHARD, staticScheduler.tasks[coroutine.running()], expected_response_count)

    SendModRPCToShard(GetShardModRPC(rpc_manager.namespace, name), target, id, ...)
    
    sleep(rpc_manager.timeout)
    local result_table, missing_response_count = rpc_manager:PopContextResult(RPC_CATEGORY.SHARD, id)
    -- shard rpc could have more than one responsor, directly return a result_table(or nil)
    return missing_response_count, result_table
end

function AsyncRPCManager:SendRPCToServer(name, ...)
    local rpc = self.rpc_names[RPC_CATEGORY.SERVER][name]
    if not rpc then
        dbg('error: failed to send a RPC to server: RPC {name } not found.')
        return nil, false
    end
    if rpc.no_response then
        
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