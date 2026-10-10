-- Inert unless avanti_smoke = true. Prints machine-readable markers for the log parser.
if not core.settings:get_bool("avanti_smoke", false) then
	return
end

local max_steps = tonumber(core.settings:get("avanti_smoke_steps")) or 200
local steps, emerged = 0, false

core.register_on_mods_loaded(function()
	core.log("action", "[avanti_smoke] MODS_LOADED " .. table.concat(core.get_modnames(), ","))
end)

core.register_globalstep(function()
	steps = steps + 1
	if steps == 2 then
		core.emerge_area(vector.new(-48, -32, -48), vector.new(48, 32, 48), function(_, _, remaining)
			if remaining == 0 then
				emerged = true
				core.log("action", "[avanti_smoke] EMERGED")
			end
		end)
	end
	if (emerged and steps >= 20) or steps >= max_steps then
		core.log("action", "[avanti_smoke] " .. (emerged and "OK" or "TIMEOUT_EMERGE") .. " steps=" .. steps)
		core.request_shutdown("avanti smoke test finished", false, 0)
		steps = -math.huge
	end
end)
