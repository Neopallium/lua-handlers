
local require = require
local pcall = pcall

local backends = {
	"llnet",
	"nixio",
}

local mod_name = ...

for i=1,#backends do
	local name = mod_name .. '.' .. backends[i] .. '_backend'
	local status, mod = pcall(require, name)
	if status then
		print("--------- Loaded backend:", name)
		return mod
	end
end

