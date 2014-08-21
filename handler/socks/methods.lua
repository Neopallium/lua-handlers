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

local methods_mt = {}
methods_mt.__index = methods_mt

-- state machine
local sm = {
"VERSION",
"METHOD",
"METHODS",
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

local function sm_METHODS(self, data)
	-- parse list of supported methods
	local status, err = self.val:parse(data)
	if status then
		self.methods = self.val.value
	elseif err then
		return sm_ERROR, err
	end
	return sm_DONE
end

local function sm_METHOD(self, data, len)
	if len < 1 then return sm_METHOD end
	-- parse method
	self.method = data:read_uint8()
	return sm_DONE
end

function sm_VERSION(self, data, len)
	if len < 1 then return sm_VERSION end
	-- parse Version
	local version = data:read_uint8()
	if version ~= 5 then
		return sm_ERROR, "Invalid Socks verion."
	end
	if self.is_methods then
		return sm_METHODS(self, data, len-1)
	else
		return sm_METHOD(self, data, len-1)
	end
end

function methods_mt:parse(data)
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

function methods_mt:encode(buf)
	-- Encode methods/method message
	buf:append_uint8(5) -- Socks V5
	if self.is_methods then
		-- Encode list of supported methods
		parse.encode_varlength(buf, self.methods)
	else
		buf:append_uint8(self.method) -- Method
	end
end

local function update_map(self)
	local methods = self.methods
	local map = self.map
	for i=1,#methods do
		local m = methods:byte(i)
		map[m] = m
	end
end

local function reset_map(self)
	self.map = {}
	update_map(self)
end

function methods_mt:get_nmethods()
	return #self.methods
end

function methods_mt:get_method(idx)
	return self.methods:byte(idx)
end

function methods_mt:add_method(method)
	self.methods = self.methods .. string.char(method)
	if self.map then
		self.map[method] = method
	end
end

function methods_mt:add_methods(method, ...)
	self.methods = self.methods .. string.char(method, ...)
	if self.map then
		update_map(self)
	end
end

function methods_mt:find_method(method)
	if not self.map then
		reset_map(self)
	end
	return self.map[method]
end

function methods_mt:reset()
	if self.is_methods then
		self.methods = ''
	else
		self.method = 0
	end
	self.state = sm_VERSION
end

module(...)

local function new(is_methods, self)
	self = self or {}
	-- new methods/method message
	self.is_methods = is_methods
	if is_methods then
		self.val = parse.new_varlength()
		self.methods = ''
	else
		self.method = 0
	end
	self.state = sm_VERSION
	return setmetatable(self, methods_mt)
end

function new_methods(self)
	return new(true, self)
end

function new_method(self)
	return new(false, self)
end

function encode_methods(buf, methods)
	-- Encode methods message
	buf:append_uint8(5) -- Socks V5
	-- Encode list of supported methods
	parse.encode_varlength(buf, methods)
end

function encode_method(buf, method)
	-- Encode method message
	buf:append_uint8(5) -- Socks V5
	buf:append_uint8(method) -- Method
end

