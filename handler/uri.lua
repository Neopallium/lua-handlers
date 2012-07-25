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
local print = print
local tonumber = tonumber
local char = string.char
local type = type

local function parse_scheme(uri, off)
	local scheme, off = uri:match('^(%a[%w.+-]*):()', off)
	-- force scheme to canonical form
	scheme = scheme:lower()
	return scheme, off
end

local function parse_authority(uri, off)
	local authority, auth_end = uri:match('([^/]*)()', off)
	local userinfo, host, port
	-- check if authority has userinfo
	off = authority:find('@', 1, true)
	if off then
		-- parser userinfo
		userinfo = authority:sub(1,off)
		off = off + 1
	else
		off = 1
	end
	-- check if host is an IPv6 address
	if authority:sub(off, off) == '[' then
		-- parse IPv6 address
		host, off = authority:match('(%[[%x:]*%])()', off)
	else
		-- parse IPv4 address or hostname
		host, off = authority:match('([^:]*)()', off)
	end
	-- parse port
	port, off = authority:match(':(%d*)', off)
	port = tonumber(port)
	return userinfo, host, port, auth_end
end

local function parse_path_query_fragment(uri, off)
	local path, query, fragment
	-- parse path
	path, off = uri:match('([^?#]*)()', off)
	-- parse query
	if uri:sub(off, off) == '?' then
		query, off = uri:match('([^#]*)()', off + 1)
	end
	-- parse fragment
	if uri:sub(off, off) == '#' then
		fragment = uri:sub(off + 1)
		off = #uri
	end
	return path or '/', query, fragment, off
end

module(...)

function parse(uri, info, path_only)
	local off = 1
	info = info or {}
	-- check if uri has a scheme
	if uri:sub(off, 1) ~= '/' then
		-- parse scheme
		info.scheme, off = parse_scheme(uri, off)
	end
	-- check if uri has an authority
	if uri:sub(off, off + 1) == '//' then
		-- parse authority
		info.userinfo, info.host, info.port, off = parse_authority(uri, off + 2)
	end
	-- parse path
	if path_only then
		-- don't split path/query/fragment, keep them whole.
		info.path = uri:sub(off)
	else
		-- parse path, query, and fragment
		info.path, info.query, info.fragment, off = parse_path_query_fragment(uri, off)
	end
	-- check for zero-length path
	if #info.path == 0 then
		info.path = "/"
	end
	-- return parsed uri
	return info
end

local function urldecode(val)
	return val:gsub("%%(%x%x)", function(hex) return char(tonumber(hex, 16)) end)
end
_M.urldecode = urldecode

--
-- Create url encoding table.
--
local enc_map = {}
for i=0,255 do
	local c = char(i)
	local enc = c
	if c == '-' or c == '_' or c == '.' then
	elseif 'a' <= c and c <= 'z' then
	elseif 'A' <= c and c <= 'Z' then
	elseif '0' <= c and c <= '9' then
	else
		enc = ("%%%02x"):format(i)
	end
	if c ~= enc then
		enc_map[c] = enc
	end
end

local function urlencode(val)
	return val:gsub("([^%a])", enc_map)
end
_M.urlencode = urlencode

function parse_query(query, values)
	query = query or ''
	values = values or {}
	-- parse name/value pairs
	for k,v in query:gmatch('([^=]+)=([^&]*)&?') do
		-- url decode value
		v = urldecode(v)
		local v1 = values[k]
		if v1 then
			-- multiple values with same key
			if type(v1) == 'string' then
				-- switch to a table to hold all values.
				v1 = { v1 }
			end
			v1[#v1 + 1] = v
			values[k] = v1
		else
			values[k] = v
		end
	end
	return values
end

setmetatable(_M, { __call = function(tab, ...) return parse(...) end })

