-- Camera driver for `avanti screenshot`. Inert unless avanti_camera_mode is "replay" or "record".
--
-- Shot list: <world>/avanti_shots.json (copied there by the CLI), format
--   { "shots": [ { "name": "cave_wide", "pos": [x, y, z], "yaw": 0, "pitch": 15,
--                  "look_at": [x, y, z], "time": 0.5, "fov": 72, "settle": 2 } ] }
-- pos is the camera (eye) position; give yaw/pitch in degrees or a look_at point.
--
-- replay: for each shot, move the camera, emerge the area, wait `settle` seconds, log
--   "[avanti_camera] READY <i> <name>", then wait until the CLI writes <i> to
--   <world>/avanti_camera_ack. Logs "[avanti_camera] DONE" at the end.
-- record: chat command /shot <name> appends the current view to <world>/avanti_shots.json.
local mode = core.settings:get("avanti_camera_mode") or ""
if mode ~= "replay" and mode ~= "record" then
	return
end

avanti_camera = {}
local world = core.get_worldpath()
local shots_file = world .. "/avanti_shots.json"
local ack_file = world .. "/avanti_camera_ack"
local scene_wait = tonumber(core.settings:get("avanti_camera_scene_wait")) or 10
local scene_is_ready = false

--- Scene builders (tools/showcase mods) call this once their scene is built.
function avanti_camera.scene_ready()
	scene_is_ready = true
end

local function read_shots()
	local f = io.open(shots_file, "r")
	if not f then
		return {}
	end
	local data = core.parse_json(f:read("*a")) or {}
	f:close()
	return data.shots or {}
end

local function eye_height(player)
	return player:get_properties().eye_height or 1.625
end

local function vec(t)
	return vector.new(t[1], t[2], t[3])
end

local function apply(player, shot)
	local eye = vec(shot.pos)
	local yaw, pitch
	if shot.look_at then
		local d = vector.subtract(vec(shot.look_at), eye)
		yaw = math.atan2(-d.x, d.z)
		pitch = -math.atan2(d.y, math.sqrt(d.x * d.x + d.z * d.z))
	else
		yaw = math.rad(shot.yaw or 0)
		pitch = math.rad(shot.pitch or 0)
	end
	player:set_physics_override({ gravity = 0, speed = 0, jump = 0 })
	player:set_pos(vector.offset(eye, 0, -eye_height(player), 0))
	player:set_look_horizontal(yaw)
	player:set_look_vertical(pitch)
	if shot.time then
		core.set_timeofday(shot.time)
	end
	player:set_fov(shot.fov or 0, false, 0)
end

-- --------------------------------------------------------------- replay

if mode == "replay" then
	local queue, index, waiting_ack, settle_left, player_name = nil, 0, false, nil, nil
	local since_join = 0

	local function next_shot(player)
		index = index + 1
		local shot = queue[index]
		if not shot then
			core.log("action", "[avanti_camera] DONE")
			queue = {}
			return
		end
		if not shot.pos then -- keep the scene's own camera
			settle_left = shot.settle or 2
			return
		end
		apply(player, shot)
		local eye = vec(shot.pos)
		settle_left = nil
		core.emerge_area(vector.offset(eye, -48, -32, -48), vector.offset(eye, 48, 32, 48), function(_, _, remaining)
			if remaining == 0 then
				settle_left = shot.settle or 2
			end
		end)
	end

	core.register_on_joinplayer(function(player)
		player_name = player:get_player_name()
	end)

	core.register_globalstep(function(dtime)
		local player = player_name and core.get_player_by_name(player_name)
		if not player then
			return
		end
		if not queue then
			since_join = since_join + dtime
			if scene_is_ready or since_join >= scene_wait then
				queue = read_shots()
				if #queue == 0 then
					queue = { { name = "main" } } -- one shot with the scene's own camera
				end
				next_shot(player)
			end
			return
		end
		if waiting_ack then
			local f = io.open(ack_file, "r")
			local ack = f and tonumber(f:read("*l"))
			if f then
				f:close()
			end
			if ack == index then
				waiting_ack = false
				next_shot(player)
			end
			return
		end
		if settle_left then
			settle_left = settle_left - dtime
			if settle_left <= 0 then
				settle_left = nil
				waiting_ack = true
				core.log("action", ("[avanti_camera] READY %d %s"):format(index, queue[index].name or index))
			end
		end
	end)
end

-- --------------------------------------------------------------- record

if mode == "record" then
	core.register_chatcommand("shot", {
		params = "<name>",
		description = "Save the current view as a screenshot shot for avanti",
		func = function(name, param)
			local player = core.get_player_by_name(name)
			local shot_name = param:trim():gsub("[^%w_%-]", "_")
			if not player or shot_name == "" then
				return false, "Usage: /shot <name>"
			end
			local pos = vector.offset(player:get_pos(), 0, eye_height(player), 0)
			local round = function(x, n) return math.floor(x * 10 ^ n + 0.5) / 10 ^ n end
			local fov = player:get_fov()
			local shot = {
				name = shot_name,
				pos = { round(pos.x, 2), round(pos.y, 2), round(pos.z, 2) },
				yaw = round(math.deg(player:get_look_horizontal()), 1),
				pitch = round(math.deg(player:get_look_vertical()), 1),
				time = round(core.get_timeofday(), 3),
				fov = fov ~= 0 and fov or nil,
				settle = 2,
			}
			local shots = read_shots()
			local replaced = false
			for i, s in ipairs(shots) do
				if s.name == shot_name then
					shots[i], replaced = shot, true
				end
			end
			if not replaced then
				shots[#shots + 1] = shot
			end
			core.safe_file_write(shots_file, core.write_json({ shots = shots }, true))
			return true, ("Saved shot '%s' (%d in list)%s"):format(shot_name, #shots, replaced and ", replaced" or "")
		end,
	})
	core.register_chatcommand("shots", {
		description = "List the recorded screenshot shots",
		func = function()
			local names = {}
			for _, s in ipairs(read_shots()) do
				names[#names + 1] = s.name
			end
			return true, #names == 0 and "No shots yet. Fly to a spot and use /shot <name>." or table.concat(names, ", ")
		end,
	})
	core.register_on_joinplayer(function(player)
		core.chat_send_player(player:get_player_name(),
			"[avanti] Record mode: fly (K), set the time with /time, then /shot <name>. /shots lists them. Quit when done.")
	end)
end
