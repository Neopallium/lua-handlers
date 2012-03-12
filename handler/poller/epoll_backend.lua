
local setmetatable = setmetatable
local pairs = pairs

local epoll = require"epoll"

local bit = require"bit"
local band = bit.band

local EPOLLIN = epoll.EPOLLIN
local EPOLLOUT = epoll.EPOLLOUT
local EPOLLERR = epoll.EPOLLERR

local poll_mt = {}
poll_mt.__index = poll_mt

function poll_mt:add(file, events)
	local fd = file:fileno()
	self.cbs[fd] = file
	return self.epoll:add(fd, events, fd)
end

function poll_mt:mod(file, events)
	local fd = file:fileno()
	self.cbs[fd] = file
	return self.epoll:mod(fd, events, fd)
end

function poll_mt:del(file)
	local fd = file:fileno()
	-- check if the file is registered.
	file = self.cbs[fd]
	if file then
		-- clear registered file.
		self.cbs[fd] = nil
		-- remove events for file.
		return self.epoll:del(fd)
	end
end

function poll_mt:file_read(file, wait)
	local io_read = file.io_read
	-- check if read state has changed.
	if wait == io_read then return end
	file.io_read = wait
	local events = file.io_events
	if wait then
		-- enable read events.
		if events then
			-- need to modify existing events for this fd.
			events = events + EPOLLIN
			file.io_events = events
			return self:mod(file, events)
		else
			-- new fd
			file.io_events = EPOLLIN
			return self:add(file, EPOLLIN)
		end
	elseif events then
		-- disable read events.
		if file.io_write then
			-- leave write events enabled.
			file.io_events = EPOLLOUT
			return self:mod(file, EPOLLOUT)
		else
			-- no events.
			file.io_events = nil
			return self:del(file)
		end
	end
end

function poll_mt:file_write(file, wait)
	local io_write = file.io_write
	-- check if write state has changed.
	if wait == io_write then return end
	file.io_write = wait
	local events = file.io_events
	if wait then
		-- enable write events.
		if events then
			-- need to modify existing events for this fd.
			events = events + EPOLLOUT
			file.io_events = events
			return self:mod(file, events)
		else
			-- new fd
			file.io_events = EPOLLOUT
			return self:add(file, EPOLLOUT)
		end
	elseif events then
		-- disable write events.
		if file.io_read then
			-- leave read events enabled.
			file.io_events = EPOLLIN
			return self:mod(file, EPOLLIN)
		else
			-- no events.
			file.io_events = nil
			return self:del(file)
		end
	end
end

function poll_mt:file_del(file)
	file.io_events = nil
	self:del(file)
end

local function make_event_callback(self, cbs)
	return function (fd, ev)
		-- call registered callback.
		local file = cbs[fd]
		if not file then return end
		-- check for read event.
		if band(ev, EPOLLIN) ~= 0 then
			local event_cb = file.on_io_read
			if event_cb then
				event_cb(file)
			else
				-- no callback disable read events.
				self:file_read(file, false)
			end
		end
		-- check for write event.
		if band(ev, EPOLLOUT) ~= 0 then
			local event_cb = file.on_io_write
			if event_cb then
				event_cb(file)
			else
				-- no callback disable write events.
				self:file_write(file, false)
			end
		end
	end
end

local timer_mt = {}
timer_mt.__index = timer_mt

function timer_mt:start()
end

function timer_mt:again(timeout)
end

function timer_mt:stop()
end

function poll_mt:create_timer(obj, after_secs, repeat_secs)
	local timer = {
		obj = obj,
	}
	return setmetatable(timer, timer_mt)
end

function poll_mt:step(timeout)
	assert(self.epoll:wait_callback(self.event_cb, timeout or -1))
end

function poll_mt:start()
	local epoll = self.epoll
	local cbs = self.cbs
	local event_cb = self.event_cb
	self.is_running = true
	while self.is_running do
		epoll:wait_callback(event_cb, -1)
	end
end

function poll_mt:stop()
	self.is_running = false
end

function poll_mt:close()
	local epoll = self.epoll
	self.epoll = nil
	return epoll:close()
end

function poll_mt:now()
	-- TODO: implement
	return 0
end

function poll_mt:update_now()
	-- TODO: implement
	return 0
end

module(...)

function new()
	local self
	local cbs = {}
	self = setmetatable({
		epoll = epoll.new(),
		event_cb = make_event_callback(self, cbs),
		cbs = cbs,
	}, poll_mt)
	return self
end

