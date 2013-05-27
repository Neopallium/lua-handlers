
local error = error
local require = require

local backends = {
llnet = {
	name = "llnet",
	connection = "llnet",
	acceptor = "llnet",
	poller = "epoll",
},
nixio = {
	name = "nixio",
	connection = "nixio",
	acceptor = "nixio",
	poller = "epoll",
},
llnet_ev = {
	name = "llnet",
	connection = "llnet",
	acceptor = "llnet",
	poller = "ev",
},
nixio_ev = {
	name = "nixio",
	connection = "nixio",
	acceptor = "nixio",
	poller = "ev",
},
}

local default

--default = backends.nixio
default = backends.llnet

local backend
local poller
local is_initialized = false

local mod_name = ...
local _M = {}

-- get backend
function _M.get_backend()
	if not backend then
		backend = default
		print("Use default backend: ", backend.name)
	end
	return backend
end

-- get poller
function _M.get_poller()
	if poller then return poller end
	-- make sure handler is initialized.
	_M.init()
	-- create poller
	local pmod = require(mod_name .. '.poller')
	poller = pmod.new()
	return poller
end

function _M.init(options)
	if is_initialized then return end
	is_initialized = true
	options = options or {}
	-- setup backend.
	if options.backend then
		backend = backends[options.backend]
	else
		-- use default backend
		_M.get_backend()
	end
	return _M.get_poller()
end

function _M.run()
	local stat, rc = pcall(function()
		local poll = _M.get_poller()
		return poll:start()
	end)
	if not stat then
		print("Error catch from poller:", rc)
		return stat, rc
	end
	return rc
end
_M.start = _M.run

function _M.stop()
	return poller:stop()
end

return _M
