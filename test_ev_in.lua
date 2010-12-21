local ev = require'ev'
local ioworker = require'ioworker'
local loop = ev.Loop.default

local function io_in_cb()
print("read line")
	local line = io.read("*l")
print("read: ", line)
end
local io_in = ev.IO.new(io_in_cb, 0, ev.READ)
io_in:start(loop)

print('started')
loop:loop()

