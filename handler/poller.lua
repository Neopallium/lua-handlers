
local require = require
local pcall = pcall
local print = print

local handler = require"handler"
local backend = handler.get_backend()

local mod_name = ...
local system = mod_name:match("%.(%w+)$")

local name = mod_name .. '.' .. backend[system] .. '_backend'
local status, mod = pcall(require, name)
if status then
	return mod
else
	print("----- error loading " .. system .. " backend:", name, mod)
end

error("FAILED TO LOAD backend for: " .. system)
