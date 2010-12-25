-- Copyright (c) 2010 by Robert G. Jakabosky <bobby@neoawareness.com>
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

local print = print
local tostring = tostring
local setmetatable = setmetatable
local assert = assert
local tconcat = table.concat
local url = require"socket.url"
local urlencode = url.escape
local ltn12 = require"ltn12"

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

function form_mt:get_content_type()
	local content
	local c_type
	-- generate content now.
	if self.is_simple then
		content = {}
		for k,v in pairs(self.data) do
			content[#content+1] = urlencode(k) .. '=' .. urlencode(v)
		end
		-- concat fields together.
		content = tconcat(content, '&')
		-- Content-Type
		c_type = "application/x-www-form-urlencoded"
	else
		-- generate a boundry value
		local boundry = '---------------------------96099342416336326401898798819'
		self.boundry = boundry
		-- Content-Type
		c_type = 'multipart/form-data; boundary="' .. boundry .. '"'
		-- pre-append '--' to boundry string.
		boundry = '--' .. boundry
		-- encode form data
		content = {}
		for k,v in pairs(self.data) do
			-- add boundry
			content[#content+1] = boundry
			-- field headers
			content[#content+1] = '\r\nContent-Disposition: form-data; name="' .. k .. '"'
			-- field value
			if type(v) == 'string' then
				-- no extra headers, just append the value
				content[#content+1] = '\r\n\r\n' .. v .. '\r\n'
			else
				-- check if the value is a file object.
				if v.object_type == 'file' then
					-- append filename to headers
					content[#content+1] = '; filename="' .. v.filename
					-- append Content-Type header
					content[#content+1] = '"\r\nContent-Type: ' .. v:get_content_type() .. '\r\n\r\n'
					-- append file contents
					content[#content+1] = v:get_content() .. '\r\n'
				else
					assert(false, 'un-handled form value.')
				end
			end
		end
		-- mark end
		content[#content+1] = boundry .. '--\r\n'
		-- concat fields together.
		content = tconcat(content)
	end
	self.content = content
	return c_type
end

function form_mt:get_content_length()
	if self.content then
		return #self.content
	else
		return nil
	end
end

function form_mt:get_source()
	if self.content then
		return ltn12.source.string(self.content)
	else
		return nil
	end
end

function form_mt:get_content()
	local data = {}
	local src = self:get_source()
	local sink = ltn12.sink.table(data)
print('get_content:', src, sink)
	ltn12.pump.all(src, sink)
	return tconcat(data)
end

module'handler.http.form'

function new(data)
	self = { }
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

