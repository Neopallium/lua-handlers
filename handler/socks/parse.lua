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

local varlength_mt = {}
varlength_mt.__index = varlength_mt

-- state machine
local sm = {
"LENGTH",
"VALUE",
"VALUE_PART",
"DONE",
"ERROR",
}

local sm_LENGTH

local function sm_DONE(self, data, len)
	-- reset parsing
	self:reset()
	return sm_LENGTH(self, data, len)
end

local function sm_VALUE_PART(self, data, len)
	if len < 1 then return sm_VALUE_PART end
	local part = self.value
	local need = self.length - #part
	if len < need then
		-- got only part of the value list
		self.value = part .. data:read_data(len)
		return sm_VALUE_PART
	end
	self.value = part .. data:read_data(need)

	return sm_DONE
end

local function sm_VALUE(self, data, len)
	if len < 1 then return sm_VALUE end
	-- parse the value list
	local length = self.length
	if len < length then
		-- got only part of the value list
		self.value = data:read_data(len)
		return sm_VALUE_PART
	end
	self.value = data:read_data(length)

	return sm_DONE
end

function sm_LENGTH(self, data, len)
	if len < 1 then return sm_LENGTH end
	-- parse number of value field.
	self.length = data:read_uint8()
	if self.length > 0 then
		return sm_VALUE(self, data, len-1)
	end
	return sm_DONE
end

function varlength_mt:parse(data)
	local state, err = self:state(data, #data)
	self.state = state
	if state == sm_DONE then
		return true
	end
	-- need more data.
	return false
end

function varlength_mt:reset()
	self.state = sm_LENGTH
	self.length = 0
	self.value = ''
end

module(...)

function new_varlength(self)
	self = self or {}
	self.state = sm_LENGTH
	self.length = 0
	self.value = ''
	return setmetatable(self, varlength_mt)
end

function encode_varlength(buf, value)
	local len = #value
	-- Encode length of value
	if len > 255 then
		len = 255
	end
	buf:append_uint8(len)
	if type(value) == 'string' then
		if #value > 255 then
			value = value:sub(1,255)
		end
		-- Enocde value
		buf:append_data(value)
	else
		for i=1,len do
			buf:append_uint8(value[i])
		end
	end
end

