
local backend = 'llnet'

local keep_alive = false
local requests = -1
local concurrent = 1
local profile = false
local url
local family = 'inet'

local i=1
while i <= #arg do
	local p = arg[i]
	if p == '-k' then
		keep_alive = true
	elseif p == '-p' then
		profile = true
	elseif p == '-n' then
		i = i + 1
		requests = tonumber(arg[i])
	elseif p == '-c' then
		i = i + 1
		concurrent = tonumber(arg[i])
	elseif p == '-b' then
		i = i + 1
		p = arg[i]
		backend = p
	else
		url = p
	end
	i = i + 1
end

local handler = require'handler'
handler.init{ backend = backend }
local connection = require'handler.connection'

local zmq = require"zmq"

assert(url, "missing <url>")
assert(requests > 0, "missing '-n num'")
assert(concurrent <= requests, "insane arguments")

--
-- Parse URL
--
local uri = require"handler.uri"
url = uri.parse(url)
local port = url.port or 80
local http_port = ''
if port ~= 80 then
	http_port = ':' .. tostring(port)
end
local host = url.host

--
-- Pre-make HTTP request.
--
local REQUEST =
  "GET " .. url.path .." HTTP/1.1\r\n" ..
	"Host: " .. url.host .. http_port .. "\r\n" ..
  "User-Agent: fake_http_client/0.1\r\n" ..
  "Connection: keep-alive\r\n\r\n"

print("using backend:", backend)
print(string.format("%d concurrent requests, %d total requests", concurrent, requests))

local sformat = string.format
local stdout = io.stdout

local started = 0
local connections = 0
local done = 0
local succeeded = 0
local failed = 0
local errored = 0
local clients = 0
local parsed = 0

local lhp = require 'http.parser'
local resp_parsed
local http_parser
local function create_parser()
	local parser
	parser = lhp.response({
---[[
	on_body = function(data)
	end,
--]]
	on_message_complete = function()
		resp_parsed.status = parser:status_code()
	end,
	})
	return parser
end
http_parser = create_parser()
local parsed_resps = setmetatable({},{
__index = function(tab, resp)
	resp_parsed = {}
	parsed = parsed + 1
	local parsed = http_parser:execute(resp)
	if parsed ~= #resp then
		local errno, err, errmsg = http_parser:error()
		resp_parsed.errno = errno
		resp_parsed.errmsg = errmsg
	else
		-- get keep alive flag.
		resp_parsed.keep_alive = http_parser:should_keep_alive()
		rawset(tab, resp, resp_parsed)
	end
	-- need to re-create parser.
	http_parser = create_parser()
	return resp_parsed
end
})

local http_client_mt = {}
http_client_mt.__index = http_client_mt

local new_client

local function next_request(self)
	if started >= requests then
		self.request_active = false
		self:close()
		return
	end
	started = started + 1
	self.request_active = true
	local len, err = self.sock:send(REQUEST)
	if not len then
		print("socket write error:", err)
		self.request_active = false
		self:close()
		return
	end
end

local progress_units = 10
local checkpoint = math.floor(requests / progress_units)
local percent = 0
local progress_timer
local last_done = 0
local function print_progress()
	local elapsed = progress_timer:stop()
	if elapsed == 0 then elapsed = 1 end

	local reqs = done - last_done
	local throughput = reqs / (elapsed / 1000000)
	last_done = done

	percent = percent + progress_units
	stdout:write(sformat([[
progress: %3i%% done, %7i requests, %5i open conns, %i.%03i%03i sec, %5i req/s
]], percent, done, clients,
(elapsed / 1000000), (elapsed / 1000) % 1000, (elapsed % 1000), throughput))
	-- start another progress_timer
	if percent < 100 then
		progress_timer = zmq.stopwatch_start()
	end
end

function http_client_mt:handle_data(data)
	-- check if socket has some partial data.
	if self.buf_data then
		data = self.buf_data .. data
		self.buf_data = nil
	end
	-- check resp.
	local resp = parsed_resps[data]
	if resp.status == 200 then
		succeeded = succeeded + 1
	elseif resp.status == nil then
		-- got partial response.
		self.buf_data = data
		return
	else
		failed = failed + 1
	end
	-- the request is finished.
	done = done + 1
	if (done % checkpoint) == 0 then
		print_progress()
	end
	-- check if we should close the connection.
	if not resp.keep_alive or not keep_alive then
		self:close()
		-- create a new client if we are not done.
		if clients < concurrent then
			local need = requests - started
			if need > clients then
				new_client()
			end
		end
		return
	end
	-- send a new request.
	if self.request_active then
		self.request_active = false
	end
	next_request(self)
end

function http_client_mt:close()
	clients = clients - 1
	assert(clients >= 0, "Can't close more clients then we create.")
	self.sock:close()
	if done == requests then
		-- we should be finished.
		handler.stop()
	end
end

local client_errs = {}
local has_client_errs = false

function http_client_mt:handle_error(err)
	if self.request_active then
		errored = errored + 1
		if err == 'CLOSED' then
			started = started - 1
			new_client()
		else
			client_errs[err] = (client_errs[err] or 0) + 1
			has_client_errs = true
		end
	end
	self:close()
	if clients == 0 then
		-- no clients, stop event loop
		handler.stop()
	end
end
-- send first request when connected
http_client_mt.handle_connected = next_request

new_client = function ()
	local self = setmetatable({}, http_client_mt)
	local sock, err = connection.tcp(self, host, port)
	if not sock then
		--print("Failed to create TCP connection:", err)
		return
	end
	self.sock = sock
	connections = connections + 1
	clients = clients + 1
	return self
end

--
-- Create clients.
--

progress_timer = zmq.stopwatch_start()
local timer = zmq.stopwatch_start()

for i=1,concurrent do
	new_client()
end

print()
if profile then
	local luatrace = require"luatrace"
	luatrace.tron()
	print("handler.run():", pcall(function()
		return handler.run()
	end))
	luatrace.troff()
else
	handler.run()
end

local elapsed = timer:stop()
if elapsed == 0 then elapsed = 1 end

local throughput = done / (elapsed / 1000000)

print(sformat([[

finished in %i sec, %i millisec and %i microsec, %i req/s
requests: %i total, %i started, %i done, %i succeeded, %i failed, %i errored, %i parsed
connections: %i total, %i concurrent
]],
(elapsed / 1000000), (elapsed / 1000) % 1000, (elapsed % 1000), throughput,
requests, started, done, succeeded, failed, errored, parsed,
connections, concurrent
))

if has_client_errs then
	print("socket read error with active request:")
	for err,cnt in pairs(client_errs) do
		print(err, cnt)
	end
end

