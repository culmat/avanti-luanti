-- {{title}}: {{description}}
local modname = core.get_current_modname()
local modpath = core.get_modpath(modname)
-- Wrap player-facing strings in S("...") and list them in locale/template.txt.
local S = core.get_translator(modname) -- luacheck: ignore 211 (unused until the first string)

-- The mod's only global: its API table. Keep everything else local.
{{modname}} = {}

core.log("action", "[" .. modname .. "] loaded")

if core.get_modpath("mtt") and mtt.enabled then
	dofile(modpath .. "/test/mtt.lua")
end
