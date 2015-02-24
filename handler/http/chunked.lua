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

local setmetatable = setmetatable
local format = string.format

local ltn12 = require"ltn12"

--
-- Chunked Transfer Encoding
--
local function encode(chunk)
	if chunk == "" then
		return ""
	elseif chunk then
		local len = #chunk
		-- prepend chunk length
		return format('%x\r\n', len) .. chunk .. '\r\n'
	else
		-- return zero-length chunk.
		return '0\r\n\r\n'
	end
	return nil
end

--
-- Chunked Transfer Encoding filter
--
local function chunked()
	local is_eof = false
	return function(chunk)
		if chunk == "" then
			return ""
		elseif chunk then
			local len = #chunk
			-- prepend chunk length
			return format('%x\r\n', len) .. chunk .. '\r\n'
		elseif not is_eof then
			-- nil chunk, mark stream EOF
			is_eof = true
			-- return zero-length chunk.
			return '0\r\n\r\n'
		end
		return nil
	end
end

module(...)

function new(src)
	return ltn12.filter.chain(src, chunked())
end

_M.encode = encode

setmetatable(_M, { __call = function(tab, ...) return new(...) end })

