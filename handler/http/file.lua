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

local print = print
local setmetatable = setmetatable
local assert = assert
local io = io
local tconcat = table.concat
local ltn12 = require'ltn12'

local file_mt = { is_content_object = true, object_type = 'file' }
file_mt.__index = file_mt

function file_mt:get_content_type()
	return self.content_type
end

function file_mt:get_content_length()
	return self.size
end

function file_mt:get_source()
	return self.src
end

function file_mt:get_content()
	local data = {}
	local src = self:get_source()
	local sink = ltn12.sink.table(data)
	ltn12.pump.all(src, sink)
	return tconcat(data)
end

module(...)

function new(filename, content_type, upload_name)
	local file = assert(io.open(filename))

	-- get file size.
	local size = file:seek('end')
	file:seek('set', 0)

	-- make sure there is a content type.
	content_type = content_type or "application/octet-stream"

	-- check if we where given an upload name
	if not upload_name then
		-- default upload name to same as filename without the path.
		upload_name = filename:match('([^/]*)$')
		-- TOD: add support for windows
	end

	local self = {
		upload_name = upload_name,
		size = size,
		content_type = content_type,
		src = ltn12.source.file(file)
	}
	return setmetatable(self, file_mt)
end

function new_string(name, content_type, content)
	assert(content, "Missing content for file.")
	-- make sure there is a content type.
	content_type = content_type or "application/octet-stream"

	local self = {
		upload_name = name,
		size = #content,
		content_type = content_type,
		src = ltn12.source.string(content)
	}
	return setmetatable(self, file_mt)
end

