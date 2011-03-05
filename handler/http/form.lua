-- Copyright (c) 2010-2011 by Robert G. Jakabosky <bobby@neoawareness.com>
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

local socket = require"socket"
local url = require"socket.url"
local urlencode = url.escape
local ltn12 = require"ltn12"

local type = type
local print = print
local pairs = pairs
local tostring = tostring
local time = socket.gettime
local randomseed = math.randomseed
local random = math.random
local floor = math.floor
local format = string.format
local setmetatable = setmetatable
local assert = assert
local tconcat = table.concat

local valid_types = {
	number = true,
	boolean = true,
	string = true,
	table = true,
	-- we don't support these types
	['function'] = false,
	userdata = false,
	thread = false,
}

local simple_types = {
	number = true,
	boolean = true,
	string = true,
	table = false,
}

local function check_form_format(data)
	local is_simple = true
	for k,v in pairs(data) do
		local t = type(v)
		assert(valid_types[t], 'Invalid value type for field: ' .. k)
		if not simple_types[t] then
			is_simple = false
			break
		end
	end
	return is_simple
end

local function content_source(t)
	local last_src
	local i = 1
	return function(...)
		local chunk
		-- check for eof
		if t == nil then
			return nil
		end
		repeat
			if last_src then
				local err
				-- process current sub-source
				chunk, err = last_src()
				if chunk ~= nil then
					break
				else
					-- check for sub-source error
					if err then
						return nil, err
					end
					-- sub-source finished
					last_src = nil
				end
			end
			-- get next chunk from table
			chunk = t[i]
			i = i + 1
			if chunk == nil then
				t = nil
				return nil
			elseif type(chunk) == 'function' then
				last_src = chunk
				chunk = nil
			end
		until chunk
		return chunk
	end
end

local form_mt = { is_content_object = true, object_type = 'form' }
form_mt.__index = form_mt

function form_mt:add(field, value)
	assert(type(field) == 'string', 'field name must be a string')
	-- check if field value is complex
	local t = type(value)
	assert(valid_types[t], 'Invalid value type for field: ' .. field)
	if not simple_types[t] then
		self.is_simple = false
	end
	self.data[field] = value
end

function form_mt:remove(field)
	self.data[field] = nil
end

local function append(t,idx, len, data)
	idx = idx + 1
	t[idx] = data
	return idx, len + #data
end

local function fixate_form_content(self)
	-- check if already generated the form content.
	if self.content then
		return
	end
	local content = {}
	local c_length = 0
	local c_type
	local parts = 0
	-- generate content now.
	if self.is_simple then
		for k,v in pairs(self.data) do
			parts, c_length = append(content, parts, c_length,
				urlencode(k) .. '=' .. urlencode(v))
		end
		-- concat fields together.
		if parts > 1 then
			content = tconcat(content, '&')
			c_length = c_length + (1 * parts) - 1
		else
			content = tconcat(content)
		end
		-- Content-Type
		c_type = "application/x-www-form-urlencoded"
		-- create content ltn12 source
		content = ltn12.source.string(content)
	else
		-- generate a boundry value
		local boundry = '---------------------------'
		-- gen. long random number for boundry
		randomseed(time())
		for i=1,15 do
			boundry = boundry .. format('%x',floor(10000 * random()))
		end
		-- limit boundry length to 65 chars max
		if #boundry > 65 then
			boundry = boundry:sub(1,65)
		end
		-- Content-Type
		c_type = 'multipart/form-data; boundary=' .. boundry .. ''
		-- pre-append '--' to boundry string.
		boundry = '--' .. boundry

		-- encode form data
		local boundry_len = #boundry
		for key,val in pairs(self.data) do
			-- add boundry
			parts, c_length = append(content, parts, c_length, boundry)
			-- field headers
			parts, c_length = append(content, parts, c_length,
				'\r\nContent-Disposition: form-data; name="' .. key .. '"')
			-- field value
			if type(val) == 'string' then
				-- no extra headers, just append the value
				parts, c_length = append(content, parts, c_length,
					'\r\n\r\n' .. val .. '\r\n')
			else
				-- check if the value is a file object.
				if val.object_type == 'file' then
					local d
					-- append filename to headers
					parts, c_length = append(content, parts, c_length,
						'; filename="' .. val.upload_name)
					-- append Content-Type header
					parts, c_length = append(content, parts, c_length,
						'"\r\nContent-Type: ' .. val:get_content_type() .. '\r\n\r\n')
					-- append file contents
					parts = parts + 1
					c_length = c_length + val:get_content_length()
					--content[parts] = val:get_content()
					content[parts] = val:get_source()
					-- value end
					parts, c_length = append(content, parts, c_length, '\r\n')
				else
					assert(false, 'un-handled form value.')
				end
			end
		end
		-- mark end
		parts, c_length = append(content, parts, c_length, boundry .. '--\r\n')
		-- create content ltn12 source
		content = content_source(content)
	end
	self.content_length = c_length
	self.content = content
	self.content_type = c_type
end

function form_mt:get_content_type()
	fixate_form_content(self)
	return self.content_type
end

function form_mt:get_content_length()
	fixate_form_content(self)
	return self.content_length
end

function form_mt:get_source()
	fixate_form_content(self)
	return self.content
end

function form_mt:get_content()
	local data = {}
	local src = self:get_source()
	local sink = ltn12.sink.table(data)
	ltn12.pump.all(src, sink)
	return tconcat(data)
end

module(...)

function new(data)
	local self = { }
	if data then
		self.is_simple = check_form_format(data)
		self.data = data
	else
		self.is_simple = true
		self.data = {}
	end
	return setmetatable(self, form_mt)
end

function parser()
	assert(false, "Not implemented yet!")
end

