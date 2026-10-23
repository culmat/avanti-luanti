-- Used by `avanti play`, a debug tool: inert unless avanti_play_admin = true. Grants every registered
-- privilege to every joining player, like /grantme all. Singleplayer doesn't get fly, fast, noclip,
-- settime, teleport, give, server, debug and others from the engine, and most games don't grant
-- them in creative mode either. Only adds privileges, never revokes any.
if not core.settings:get_bool("avanti_play_admin", false) then
	return
end

core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	local privs = core.get_player_privs(name)
	local added = {}
	for priv in pairs(core.registered_privileges) do
		if not privs[priv] then
			privs[priv] = true
			added[#added + 1] = priv
		end
	end
	if #added > 0 then
		table.sort(added)
		core.set_player_privs(name, privs)
		core.log("action", "[avanti_play] granted " .. table.concat(added, ", ") .. " to " .. name)
	end
end)
