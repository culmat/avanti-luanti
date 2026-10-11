-- Inert unless avanti_showcase = true. Generic scene for `avanti screenshot`: every node the
-- mods in avanti_showcase_mods register (up to 12) stands on a daylit platform, the player
-- looks at them with the HUD hidden. Mods can ship their own scene in tools/showcase instead.
if not core.settings:get_bool("avanti_showcase", false) then
	return
end

local wanted = {}
for _, name in ipairs(string.split(core.settings:get("avanti_showcase_mods") or "", ",")) do
	wanted[name:trim()] = true
end
-- Above terrain and the default cloud layer (y = 120), inside the MineClone-like games' height limit.
local origin = vector.new(0, 180, 0)

local function showcase_nodes()
	local names = {}
	for name, def in pairs(core.registered_nodes) do
		local modname = name:match("^([^:]+):")
		if modname and wanted[modname] and (def.groups.not_in_creative_inventory or 0) == 0 then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	return { unpack(names, 1, math.min(#names, 12)) }
end

-- Mods without nodes (tools, items): show the first one in the player's hand instead.
local function showcase_item()
	local names = {}
	for name, def in pairs(core.registered_items) do
		local modname = name:match("^([^:]+):")
		if modname and wanted[modname] and not core.registered_nodes[name]
				and (def.groups.not_in_creative_inventory or 0) == 0 then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	return names[1]
end

local function floor_node()
	for _, name in ipairs({ "default:stone", "mcl_core:stone", "basenodes:stone" }) do
		if core.registered_nodes[name] then
			return name
		end
	end
	return "air"
end

core.register_on_joinplayer(function(player)
	local nodes = showcase_nodes()
	local half = math.max(#nodes, 3)
	local pos1, pos2 = vector.offset(origin, -half - 4, -2, -8), vector.offset(origin, half + 4, 9, 8)
	core.emerge_area(pos1, pos2, function(_, _, remaining)
		if remaining > 0 then
			return
		end
		local floor = floor_node()
		for x = -half - 2, half + 2 do
			for z = -6, 4 do
				core.set_node(vector.offset(origin, x, 0, z), { name = floor })
				for y = 1, 8 do
					core.set_node(vector.offset(origin, x, y, z), { name = "air" })
				end
			end
		end
		local start = -(#nodes - 1)
		for i, name in ipairs(nodes) do
			core.set_node(vector.offset(origin, start + (i - 1) * 2, 1, 2), { name = name })
		end
		local item = #nodes == 0 and showcase_item()
		if item then
			-- new players have the first hotbar slot selected
			player:get_inventory():set_stack("main", 1, ItemStack(item))
		end
		core.set_timeofday(0.5)
		player:set_pos(vector.offset(origin, 0, 1, -2 - math.ceil(#nodes / 2)))
		player:set_look_horizontal(0)
		player:set_look_vertical(0.18)
		player:hud_set_flags({
			hotbar = false, healthbar = false, crosshair = false, wielditem = item and true or false,
			breathbar = false, minimap = false, basic_debug = false, chat = false,
		})
		local holding = item and (", holding " .. item) or ""
		core.log("action", "[avanti_showcase] READY " .. #nodes .. " node(s)" .. holding)
	end)
end)
