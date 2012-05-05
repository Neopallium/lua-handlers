
local backends = {
llnet = true,
nixio = true,
llnet_ev = true,
nixio_ev = true,
}
local backend = 'llnet'

local full_parse = true

-- check first command line argument for backend type
if backends[arg[1]] then
	backend = arg[1]
	table.remove(arg, 1)
end

print("using backend:", backend)

local handler = require'handler'
local poll = handler.init{ backend = backend }
local acceptor = require'handler.acceptor'

local lhp = require 'http.parser'

local print_stats

local clients = 0
local peak_clients = 0

local http_client_mt = {}
http_client_mt.__index = http_client_mt

function http_client_mt:close(keep_parser)
	clients = clients - 1
	--if keep_parser then
	self.parser:close()
	--end
	self.sock:close()
	if clients <= 0 then
		print_stats()
	end
end
function http_client_mt:handle_error(err)
	return self:close(true)
end
function http_client_mt:handle_connected()
end
function http_client_mt:handle_data(data)
	local parsed = self.parser:execute(data)
	if parsed ~= #data then
		print('http parse error:', self.parser:error())
		self:close(false)
		return false
	end
end

local cnt = 0
function sent_response()
	--[[
	cnt = cnt + 1; if cnt >= 4000 then
		collectgarbage"collect"
		cnt = 1
		print("GCed: mem=", collectgarbage"count")
	end
	--]]
	--cnt = cnt + 1; if cnt >= 40000 then os.exit(); handler.stop() end
end

local RESPONSE =
  "HTTP/1.0 200 OK\r\n" ..
  "Content-Type: text/plain\r\n" ..
  "Content-Length: 13\r\n" ..
	"Connection: keep-alive\r\n" ..
  "\r\n" ..
  "Hello,world!\n"

local parser_cache = {}
local parser_mt = {}
parser_mt.__index = parser_mt

function parser_mt:execute(data)
	return self.lhp:execute(data)
end
function parser_mt:error()
	return self.lhp:error()
end
function parser_mt:close()
	-- can't re-use active parser.
	if self.active then return end
	self.sock = nil
	self.body = nil
	self.url = nil
	self.method = nil
	self.major = nil
	self.minor = nil
	parser_cache[#parser_cache + 1] = self
	self.lhp:reset()
end
if full_parse then
	function parser_mt:on_message_begin()
		self.active = true
		self.headers = {}
	end
	function parser_mt:on_url(url)
		self.method = self.lhp:method()
		self.url = url
	end
	function parser_mt:on_header(header, val)
		self.headers[header] = val
	end
	function parser_mt:on_headers_complete()
		local lhp = self.lhp
		self.major, self.minor = lhp:version()
	end
	function parser_mt:on_body(data)
		local body = self.body
		if body then
			self.body = body .. data
		else
			self.body = data
		end
	end
	function parser_mt:on_message_complete()
		self.active = false
		local sock = self.sock
		sock.sock:send(RESPONSE)
		sent_response()
		if not self.lhp:should_keep_alive() then
			sock:close(true)
		end
		self.body = nil
		self.url = nil
	end
else
	function parser_mt:on_message_begin()
		self.active = true
	end
	function parser_mt:on_message_complete()
		self.active = false
		local sock = self.sock
		sock.sock:send(RESPONSE)
		sent_response()
		if not self.lhp:should_keep_alive() then
			sock:close(true)
		end
	end
end

local function create_parser()
	local parser
	local count = #parser_cache
	if count > 0 then
		parser = parser_cache[count]
		parser_cache[count] = nil
		return parser
	end
	parser = setmetatable({}, parser_mt)
	local cbs = {}
	function cbs.on_message_begin()
		return parser:on_message_begin()
	end
	if full_parse then
		function cbs.on_url(url)
			return parser:on_url(url)
		end
		function cbs.on_header(header, val)
			return parser:on_header(header, val)
		end
		function cbs.on_headers_complete()
			return parser:on_headers_complete()
		end
		function cbs.on_body(data)
			return parser:on_body(data)
		end
	end
	function cbs.on_message_complete()
		return parser:on_message_complete()
	end
	parser.cbs = cbs
	parser.lhp = lhp.request(cbs)
	return parser
end

function print_stats()
	print("clients", clients, "peak_clients", peak_clients, "mem", collectgarbage"count", "parsers", #parser_cache)
	collectgarbage"collect"
	collectgarbage"collect"
end

local MAX_ACCEPT = 100
local function new_client(sock)
	local self = setmetatable({}, http_client_mt)
	sock:sethandler(self)
	self.sock = sock

	clients = clients + 1
	if clients > peak_clients then
		peak_clients = clients
	end
	self.parser = create_parser()
	self.parser.sock = self
	return self
end

local function new_server(port)
	print("listen on:", port)
	return acceptor.tcp(new_client, '*', port, 1024)
end

for i=1,#arg do
	new_server(arg[i])
end

if #arg == 0 then
	new_server("1080")
end

handler.run()

