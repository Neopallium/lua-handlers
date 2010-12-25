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

local ipairs = ipairs
local pairs = pairs
local rawget = rawget
local rawset = rawset
local print = print
local setmetatable = setmetatable
local getmetatable = getmetatable
local assert = assert

local common_headers = {
	"Accept",
	"Accept-Charset",
	"Accept-Encoding",
	"Accept-Language",
	"Accept-Ranges",
	"Age",
	"Allow",
	"Authorization",
	"Cache-Control",
	"Connection",
	"Content-Disposition",
	"Content-Encoding",
	"Content-Language",
	"Content-Length",
	"Content-Location",
	"Content-MD5",
	"Content-Range",
	"Content-Type",
	"Cookie",
	"Date",
	"ETag",
	"Expect",
	"Expires",
	"From",
	"Host",
	"If-Match",
	"If-Modified-Since",
	"If-None-Match",
	"If-Range",
	"If-Unmodified-Since",
	"Last-Modified",
	"Link",
	"Location",
	"Max-Forwards",
	"Pragma",
	"Proxy-Authenticate",
	"Proxy-Authorization",
	"Range",
	"Referer",
	"Refresh",
	"Retry-After",
	"Server",
	"Set-Cookie",
	"TE",
	"Trailer",
	"Transfer-Encoding",
	"Upgrade",
	"User-Agent",
	"Vary",
	"Via",
	"WWW-Authenticate",
	"Warning",
}
-- create header normalize table.
local normalized = {}
for _,name in ipairs(common_headers) do
	normalized[name:lower()] = name
end

local headers_mt = {}

headers_mt.__index = function(headers, name)
	-- normalize header name
	local norm = normalized[name:lower()]
	-- if normalized name is nil or the same as name
	if norm == nil or norm == name then
		-- then no value exists for this header.
		return nil
	end
	-- get normalized header's value.
	return rawget(headers, norm)
end

headers_mt.__newindex = function(headers, name, value)
	-- normalize header name
	local norm = normalized[name:lower()] or name
	rawset(headers, norm, value)
end

module'handler.http.headers'

function new(headers)
	-- check if 'headers' has the same metatable already.
	if getmetatable(headers) == headers_mt then
		-- no need to re-convert this table.
		return headers
	end

	-- normalize existing headers
	if headers then
		for name,val in pairs(headers) do
			-- get normalized name
			local norm = normalized[name:lower()]
			-- if normalized name is different then current name.
			if norm and norm ~= name then
				-- then move value to normalized name.
				headers[norm] = val
				headers[name] = nil
			end
		end
	else
		headers = {}
	end

	return setmetatable(headers, headers_mt)
end

