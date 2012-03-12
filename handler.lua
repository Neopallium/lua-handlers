
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

default = backends.nixio
--default = backends.llnet

local backend
local poller

local mod_name = ...
local _M = {}

-- set/get backend
function _M.set_backend(name)
	if backend then
		error("Backend already set to: ", backend)
	end
	backend = backends[name]
end
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
	-- create poller
	local pmod = require(mod_name .. '.poller')
	poller = pmod.new()
	return poller
end

function _M.init(options)
	options = options or {}
	-- setup backend.
	if options.backend then
		_M.set_backend(options.backend)
	else
		-- use default backend
		_M.get_backend()
	end
	return _M.get_poller()
end

return _M
