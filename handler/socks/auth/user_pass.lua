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
local type = type

local parse = require"handler.socks.parse"

local user_pass_mt = {}
user_pass_mt.__index = user_pass_mt

-- state machine
local sm = {
"VERSION",
"STATUS",
"UNAME",
"PASSWORD",
"DONE",
"ERROR",
}

local sm_VERSION

local function sm_ERROR(self, data, len)
	return sm_ERROR
end

local function sm_DONE(self, data, len)
	-- reset parsing
	self:reset()
	return sm_VERSION(self, data, len)
end

local function sm_PASSWORD(self, data)
	-- parse username
	local status, err = self.val:parse(data)
	if status then
		self.pass = self.val.value
	elseif err then
		return sm_ERROR, err
	end
	return sm_DONE
end

local function sm_UNAME(self, data)
	-- parse username
	local status, err = self.val:parse(data)
	if status then
		self.user = self.val.value
	elseif err then
		return sm_ERROR, err
	end
	return sm_PASSWORD(self, data)
end

local function sm_STATUS(self, data, len)
	if len < 1 then return sm_STATUS end
	-- parse status
	self.status = data:read_uint8()
	return sm_DONE
end

function sm_VERSION(self, data, len)
	if len < 1 then return sm_VERSION end
	-- parse Version
	local version = data:read_uint8()
	if version ~= 1 then
		return sm_ERROR, "Invalid Socks User/Pass verion."
	end
	if self.is_request then
		return sm_UNAME(self, data)
	else
		return sm_STATUS(self, data, len-1)
	end
end

function user_pass_mt:parse(data)
	local state, err = self:state(data, #data)
	self.state = state
	if state == sm_ERROR then
		return false, err
	end
	if state == sm_DONE then
		return true
	end
	-- need more data.
	return false
end

function user_pass_mt:reset()
	if self.is_request then
		self.user = ''
		self.pass = ''
	else
		self.status = 0
	end
	self.state = sm_VERSION
end

module(...)

local function new(is_request, self)
	self = self or {}
	-- new user/pass message
	self.is_request = is_request
	if is_request then
		self.val = parse.new_varlength()
		self.user = ''
		self.pass = ''
	else
		self.status = 0
	end
	self.state = sm_VERSION
	return setmetatable(self, user_pass_mt)
end

function new_request(self)
	return new(true, self)
end

function new_reply(self)
	return new(false, self)
end

function encode_request(buf, user, pass)
	-- Encode request message
	buf:append_uint8(1) -- User/Pass version 1
	-- Encode username
	parse.encode_varlength(buf, user)
	-- Encode password
	parse.encode_varlength(buf, pass)
end

function encode_reply(buf, status)
	-- Encode reply message
	buf:append_uint8(1) -- User/Pass version 1
	buf:append_uint8(status) -- Status
end

