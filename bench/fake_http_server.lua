
local backends = {
llnet = true,
nixio = true,
llnet_ev = true,
nixio_ev = true,
}
local backend = 'llnet'

-- check first command line argument for backend type
if backends[arg[1]] then
	backend = arg[1]
	table.remove(arg, 1)
end

print("using backend:", backend)

local RESPONSE =
  "HTTP/1.0 200 OK\r\n" ..
  "Content-Type: text/plain\r\n" ..
  "Content-Length: 13\r\n" ..
	"Connection: keep-alive\r\n" ..
  "\r\n" ..
  "Hello,world!\n"

local handler = require'handler'
local poll = handler.init{ backend = backend }
local acceptor = require'handler.acceptor'

local http_client_mt = {}
http_client_mt.__index = http_client_mt

function http_client_mt:close()
	self.sock:close()
end
function http_client_mt:handle_error(err)
	return self:close()
end
function http_client_mt:handle_connected()
end
function http_client_mt:handle_data(data)
	self.sock:send(RESPONSE)
end

local MAX_ACCEPT = 100
local function new_client(sock)
	local self = setmetatable({}, http_client_mt)
	sock:sethandler(self)
	self.sock = sock

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

--local luatrace = require"luatrace"
--luatrace.tron()
--print(pcall(function()
handler.run()
--end))
--luatrace.troff()

