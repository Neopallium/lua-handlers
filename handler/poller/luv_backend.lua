
local uv = require"luv"

local setmetatable = setmetatable
local pairs = pairs

local poll_mt = {}
poll_mt.__index = poll_mt

function poll_mt:file_read(file, wait)
	local io_read = file.io_read
	if wait then
		-- create poll for read events
		if not io_read then
			-- create poller
			local fd = file:fileno()
			io_read = uv.new_poll(fd)
			io_read:start("r", function()
				local event_cb = file.on_io_read
				if event_cb then
					event_cb(file)
				else
					io_read:stop()
				end
			end)
			file.io_read = io_read
		end
	elseif io_read then
		-- disable io_read poller
		io_read:stop()
	end
end

function poll_mt:file_write(file, wait)
	local io_write = file.io_write
	if wait then
		-- create poll for write events
		if not io_write then
			-- create poller
			local fd = file:fileno()
			io_write = uv.new_poll(fd)
			io_write:start("w", function()
				local event_cb = file.on_io_write
				if event_cb then
					event_cb(file)
				else
					io_write:stop()
				end
			end)
			file.io_write = io_write
		end
	elseif io_write then
		-- disable io_write poller
		io_write:stop()
	end
end

function poll_mt:file_del(file)
	local io_read = file.io_read
	if io_read then
		file.io_read = nil
		io_read:stop()
	end
	local io_write = file.io_write
	if io_write then
		file.io_write = nil
		io_write:stop()
	end
end

local timer_mt = {}
timer_mt.__index = timer_mt

function timer_mt:start()
	local obj = self.obj
	local function ontimeout()
		local event_cb = obj.on_timer
		if event_cb then
			event_cb(obj, timer)
		else
			timer:stop()
		end
	end
	uv.timer_start(self.timer, self.after_msecs, self.repeat_msecs, ontimeout)
end

function timer_mt:again(repeat_secs)
	self.repeat_msecs = repeat_secs * 1000
	uv.timer_set_repeat(self.timer, self.repeat_msecs)
end

function timer_mt:stop()
	uv.timer_stop(self.timer, timeout)
end

function poll_mt:create_timer(obj, after_secs, repeat_secs)
	local timer = {
		timer = uv.new_timer(),
		obj = obj,
		after_msecs = after_secs * 1000,
		repeat_msecs = repeat_secs * 1000,
	}
	return setmetatable(timer, timer_mt)
end

function poll_mt:step(timeout)
	return uv.run('once')
end

function poll_mt:start()
	return uv.run()
end

function poll_mt:stop()
	uv.stop()
end

function poll_mt:close()
	self:stop()
	uv.loop_close()
end

function poll_mt:now()
	return uv.now()
end

function poll_mt:update_now()
	uv.update_time()
end

function poll_mt:get_loop()
	return uv.backend_fd()
end

module(...)

function new()
	return setmetatable({
	}, poll_mt)
end

