-- Inert unless avanti_smoke = true. Prints machine-readable markers for the log parser.
if not core.settings:get_bool("avanti_smoke", false) then
	return
end

-- Wait by time, not server steps: Lua map generators (e.g. Mineclonia's) can be slow.
local timeout = tonumber(core.settings:get("avanti_smoke_timeout")) or 120
local elapsed, steps, emerged, done = 0, 0, false, false

core.register_on_mods_loaded(function()
	core.log("action", "[avanti_smoke] MODS_LOADED " .. table.concat(core.get_modnames(), ","))
end)

core.register_globalstep(function(dtime)
	if done then
		return
	end
	elapsed = elapsed + dtime
	steps = steps + 1
	if steps == 2 then
		core.emerge_area(vector.new(-16, -16, -16), vector.new(16, 16, 16), function(_, _, remaining)
			if remaining == 0 then
				emerged = true
				core.log("action", "[avanti_smoke] EMERGED")
			end
		end)
	end
	if (emerged and steps >= 20) or elapsed >= timeout then
		done = true
		core.log("action", ("[avanti_smoke] %s steps=%d seconds=%.1f"):format(emerged and "OK" or "TIMEOUT_EMERGE",
			steps, elapsed))
		core.request_shutdown("avanti smoke test finished", false, 0)
	end
end)
