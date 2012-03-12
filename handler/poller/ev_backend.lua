
local ev = require"ev"

local setmetatable = setmetatable
local pairs = pairs

local poll_mt = {}
poll_mt.__index = poll_mt

function poll_mt:file_read(file, wait)
	local io_read = file.io_read
	if wait then
		-- enable io_read watcher.
		if not io_read then
			-- create watcher.
			local fd = file:fileno()
			io_read = ev.IO.new(function()
				local event_cb = file.on_io_read
				if event_cb then
					event_cb(file)
				else
					io_read:stop(self.loop)
				end
			end, fd, ev.READ)
			file.io_read = io_read
		end
		io_read:start(self.loop)
	elseif io_read then
		-- disable io_read watcher.
		io_read:stop(self.loop)
	end
end

function poll_mt:file_write(file, wait)
	local io_write = file.io_write
	if wait then
		-- enable io_write watcher.
		if not io_write then
			-- create watcher.
			local fd = file:fileno()
			io_write = ev.IO.new(function()
				local event_cb = file.on_io_write
				if event_cb then
					event_cb(file)
				else
					io_write:stop(self.loop)
				end
			end, fd, ev.WRITE)
			file.io_write = io_write
		end
		io_write:start(self.loop)
	elseif io_write then
		-- disable io_write watcher.
		io_write:stop(self.loop)
	end
end

function poll_mt:file_del(file)
	local io_read = file.io_read
	if io_read then
		file.io_read = nil
		io_read:stop(self.loop)
	end
	local io_write = file.io_write
	if io_write then
		file.io_write = nil
		io_write:stop(self.loop)
	end
end

local timer_mt = {}
timer_mt.__index = timer_mt

function timer_mt:start()
	self.timer:start(self.loop)
end

function timer_mt:again(timeout)
	self.timer:again(self.loop, timeout)
end

function timer_mt:stop()
	self.timer:stop(self.loop)
end

function poll_mt:create_timer(obj, after_secs, repeat_secs)
	local timer = {
		loop = self.loop,
	}
	timer.timer = ev.Timer.new(function()
		local event_cb = obj.on_timer
		if event_cb then
			event_cb(obj, timer)
		else
			timer:stop()
		end
	end, after_secs, repeat_secs)
	return setmetatable(timer, timer_mt)
end

function poll_mt:step(timeout)
	error("Not implemented!")
end

function poll_mt:start()
	return self.loop:loop()
end

function poll_mt:stop()
	return self.loop:unloop()
end

function poll_mt:close()
	self:stop()
	self.loop = nil
end

function poll_mt:now()
	return self.loop:now()
end

function poll_mt:update_now()
	return self.loop:update_now()
end

function poll_mt:get_loop()
	return self.loop
end

module(...)

function new(ev_loop)
	return setmetatable({
		loop = ev_loop or ev.Loop.default,
	}, poll_mt)
end

