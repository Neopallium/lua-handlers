-- Copyright (c) 2014 by Robert G. Jakabosky <bobby@neoawareness.com>
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.

local setmetatable = setmetatable
local assert = assert

local request_reply_mt = {}
request_reply_mt.__index = request_reply_mt

-- state machine
local sm = {
"VERSION",
"REPLY",
"COMMAND",
"RESERVED",
"ADDRESS_TYPE",
"ADDRESS_LENGTH",
"ADDRESS",
"ADDRESS_PART",
"PORT",
"PORT2",
"DONE",
"ERROR",
}

local sm_VERSION

local function sm_ERROR(self, data, len)
	return sm_ERROR
end

local function sm_DONE(self, data, len)
	local status = self:on_complete()
	if status then
		return sm_VERSION(self, data, len)
	end
	-- stop parsing
	return sm_VERSION
end

local function sm_PORT2(self, data, len)
	if len < 1 then return sm_PORT2 end
	-- parse second port byte
	local port2 = data:read_uint8()
	self.port = self.port + port2
	return sm_DONE(self, data, len-1)
end

local function sm_PORT(self, data, len)
	if len < 1 then return sm_PORT end
	-- parse first port byte
	local port1 = data:read_uint8()
	self.port = port1 * 256
	return sm_PORT2(self, data, len-1)
end

local function sm_ADDRESS_PART(self, data, len)
	if len < 1 then return sm_ADDRESS_PART end
	local part = self.addr
	local need = self.addr_len - #part
	if len < need then
		-- got only part of the address
		self.addr = part .. data:read_data(len)
		return sm_ADDRESS_PART
	end
	self.addr = part .. data:read_data(need)

	return sm_PORT(self, data, len - need)
end

local function sm_ADDRESS(self, data, len)
	if len < 1 then return sm_ADDRESS end
	-- parse Address
	local addr_len = self.addr_len
	if len < addr_len then
		-- got only part of the address
		self.addr = data:read_data(len)
		return sm_ADDRESS_PART
	end
	self.addr = data:read_data(addr_len)

	return sm_PORT(self, data, len - addr_len)
end

local function sm_ADDRESS_LENGTH(self, data, len)
	if len < 1 then return sm_ADDRESS_LENGTH end
	-- parse Address Length byte.
	self.addr_len = data:read_uint8()
	return sm_ADDRESS(self, data, len-1)
end

local ADDR_TYPES = {
	"IPv4", nil, "HOSTNAME", "IPv6",
IPv4 = 4,
HOSTNAME = -1,
IPv6 = 16,
}
local function sm_ADDRESS_TYPE(self, data, len)
	if len < 1 then return sm_ADDRESS_TYPE end
	-- parse Address type
	local addr_type = data:read_uint8()
	addr_type = ADDR_TYPES[addr_type]
	if not addr_type then
		return sm_ERROR, "Unknown address type."
	end
	self.addr_type = addr_type
	-- get address length for fixed length types.
	local addr_len = ADDR_TYPES[addr_type]
	self.addr_len = addr_len
	if addr_len < 0 then
		return sm_ADDRESS_LENGTH(self, data, len-1)
	end
	return sm_ADDRESS(self, data, len-1)
end

local function sm_RESERVED(self, data, len)
	if len < 1 then return sm_RESERVED end
	-- parse Reserved byte
	local rsv = data:read_uint8()
	if rsv ~= 0 then
		return sm_ERROR, "Invalid Socks reply (Reserved byte not 0)."
	end
	return sm_ADDRESS_TYPE(self, data, len-1)
end

--[[
Reply types:
  X'00' succeeded
  X'01' general SOCKS server failure
  X'02' connection not allowed by ruleset
  X'03' Network unreachable
  X'04' Host unreachable
  X'05' Connection refused
  X'06' TTL expired
  X'07' Command not supported
  X'08' Address type not supported
  X'09' to X'FF' unassigned
--]]
local valid_REPLIES = {
	[0] = "Succeeded",
  [1] = "general SOCKS server failure",
  [2] = "Connection not allowed by ruleset",
  [3] = "Network unreachable",
  [4] = "Host unreachable",
  [5] = "Connection refused",
  [6] = "TTL expired",
  [7] = "Command not supported",
  [8] = "Address type not supported",
}
-- reverse map.
for k,v in pairs(valid_REPLIES) do valid_REPLIES[v] = k end

local function sm_REPLY(self, data, len)
	if len < 1 then return sm_REPLY end
	-- parse Command
	local reply = data:read_uint8()
	if not valid_REPLIES[reply] then
		return sm_ERROR, "Unknown reply."
	end
	self.reply = valid_REPLIES[reply]
	return sm_RESERVED(self, data, len-1)
end

local valid_CMDS = {
	"CONNECT", "BIND", "UDP ASSOCIATE",
}
for k,v in pairs(valid_CMDS) do valid_CMDS[v] = k end

local function sm_COMMAND(self, data, len)
	if len < 1 then return sm_COMMAND end
	-- parse Command
	local cmd = data:read_uint8()
	if not valid_CMDS[cmd] then
		return sm_ERROR, "Unknown request command."
	end
	self.cmd = valid_CMDS[cmd]
	return sm_RESERVED(self, data, len-1)
end

function sm_VERSION(self, data, len)
	if len < 1 then return sm_VERSION end
	-- parse Version
	local version = data:read_uint8()
	if version ~= 5 then
		return sm_ERROR, "Invalid Socks verion."
	end
	-- reset reply state.
	self.addr_type = 1
	self.addr = '\0\0\0\0'
	self.port = 0
	if self.is_request then
		self.cmd = 'Invalid'
		return sm_COMMAND(self, data, len-1)
	else
		self.reply = 'Invalid'
		return sm_REPLY(self, data, len-1)
	end
end

function request_reply_mt:parse(data)
	local state, err = self:state(data, #data)
	self.state = state
	if state == sm_ERROR then
		return false, err
	end
	return true
end

function request_reply_mt:encode(buf)
	-- build reply
	buf:append_uint8(5) -- Socks V5
	if self.is_request then
		if not valid_CMDS[self.cmd] then return false, "Invalid Request command" end
		buf:append_uint8(self.cmd) -- Request command
	else
		if not valid_REPLIES[self.reply] then return false, "Invalid Reply" end
		buf:append_uint8(self.reply) -- Reply
	end
	-- Reserved \0 and Address Type
	if self.addr_type == 1 or self.addr_type == 'IPv4' then
		buf:append_data("\0\1")
		buf:append_data(self.addr) -- BND.ADDR - IPv4 Address
	elseif self.addr_type == 3 or self.addr_type == 'HOSTNAME' then
		local addr_len = #self.addr
		buf:append_data("\0\3")
		if addr_len > 255 then return false, "Hostname too long" end
		buf:append_uint8(addr_len) -- Hostname length
		buf:append_data(self.addr) -- BND.ADDR - Hostname
	elseif self.addr_type == 4 or self.addr_type == 'IPv6' then
		if #self.addr ~= 16 then return false, "Invalid IPv6 address." end
		buf:append_data("\0\4")
		buf:append_data(self.addr) -- BND.ADDR - IPv6 Address
	else
		return false, "Invalid Address Type"
	end
	if self.port < 0 or self.port > 0xFFFF then return false, "Invalid port" end
	buf:append_uint16(self.port) -- BND.PORT

	return true
end

function request_reply_mt:reset()
	if self.is_request then
		self.cmd = 'Invalid'
	else
		self.reply = 'Invalid'
	end
	self.state = sm_VERSION
	self.addr_type = 1
	self.addr = '\0\0\0\0'
	self.port = 0
end

module(...)

function new(is_request, self)
	self = self or {}
	-- new request/reply message
	self.is_request = is_request
	if is_request then
		self.cmd = 'Invalid'
	else
		self.reply = 'Invalid'
	end
	self.state = sm_VERSION
	self.addr_type = 1
	self.addr = '\0\0\0\0'
	self.port = 0
	return setmetatable(self, request_reply_mt)
end

function new_request(self)
	return new(true, self)
end

function new_reply(self)
	return new(false, self)
end

