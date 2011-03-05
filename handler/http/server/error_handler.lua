-- Copyright (c) 2011 by Robert G. Jakabosky <bobby@neoawareness.com>
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

local http_error_codes = {
-- Redirection 3xx
[300] = "Multiple Choices",
[301] = "Moved Permanently",
[302] = "Found",
[303] = "See Other",
[304] = "Not Modified",
[305] = "Use Proxy",
[306] = "(Unused)",
[307] = "Temporary Redirect",
-- Client Error 4xx
[400] = "Bad Request",
[401] = "Unauthorized",
[402] = "Payment Required",
[403] = "Forbidden",
[404] = "Not Found",
[405] = "Method Not Allowed",
[406] = "Not Acceptable",
[407] = "Proxy Authentication Required",
[408] = "Request Timeout",
[409] = "Conflict",
[410] = "Gone",
[411] = "Length Required",
[412] = "Precondition Failed",
[413] = "Request Entity Too Large",
[414] = "Request-URI Too Long",
[415] = "Unsupported Media Type",
[416] = "Requested Range Not Satisfiable",
[417] = "Expectation Failed",
-- Server Error 5xx
[500] = "Internal Server Error",
[501] = "Not Implemented",
[502] = "Bad Gateway",
[503] = "Service Unavailable",
[504] = "Gateway Timeout",
[505] = "HTTP Version Not Supported",
}

local function render_response(title, message)
	return [[<html><head><title>]] ..
		title .. [[</title></head><body>]] ..
		message .. [[</body></html>]]
end

local function handle_redirection(resp, status)
	local reason = http_error_codes[status] or ''
	local msg = "Redirection " .. status .. " " .. reason
	return render_response(msg, msg)
end

local function handle_error(resp, status)
	local reason = http_error_codes[status] or ''
	local msg = "Error " .. status .. " " .. reason
	return render_response(msg, msg)
end

return function(server, resp)
	-- check for a response body.
	if resp.body ~= nil then
		-- don't replace a custom response body.
		return false
	end
	local status = resp.status
	-- check for redirection response.
	local body
	if status >= 300 and status < 400 then
		body = handle_redirection(resp, status)
	else
		body = handle_error(resp, status)
	end
	resp:set_header('Content-Type', 'text/html')
	resp:set_body(body)
	return true
end

