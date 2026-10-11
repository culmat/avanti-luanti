-- Camera driver for `avanti screenshot`. Inert unless avanti_camera_mode is "replay" or "record".
--
-- Shot list: <world>/avanti_shots.json (copied there by the CLI), format
--   { "shots": [
--     { "name": "cave_wide", "pos": [x, y, z], "yaw": 0, "pitch": 15,
--       "look_at": [x, y, z], "time": 0.5, "fov": 72, "settle": 2 },
--     { "name": "flythrough", "fps": 30, "duration": 8, "ease": "inout",
--       "keys": [ { "t": 0, "pos": [x, y, z], "look_at": [x, y, z], "time": 0.25 }, { "t": 8, ... } ] },
--     { "name": "spin", "duration": 10, "orbit": { "center": [x, y, z], "radius": 6, "height": 2, "turns": 1 } }
--   ] }
-- pos is the camera (eye) position; give yaw/pitch in degrees or a look_at point.
-- Shots with "keys" or "orbit" are videos: the camera follows a smooth path through the keys.
--
-- replay: for each still, move the camera, emerge the area, wait `settle` seconds, log
--   "[avanti_camera] READY <i> <name>", then wait until the CLI writes <i> to
--   <world>/avanti_camera_ack. For a video, log "[avanti_camera] VIDEO <i> <frames> <fps> <name>",
--   then for each frame k move the camera, log "[avanti_camera] FRAME <k>" and wait until the
--   capture helper writes k to <world>/avanti_camera_frame_ack. Logs "[avanti_camera] DONE" at the end.
-- record: /shot <name> saves the current view as a still, /key <name> [gap] appends it as a video
--   keyframe, /preview <name> plays a video in game.
local mode = core.settings:get("avanti_camera_mode") or ""
if mode ~= "replay" and mode ~= "record" then
	return
end

avanti_camera = {}
local world = core.get_worldpath()
local shots_file = world .. "/avanti_shots.json"
local ack_file = world .. "/avanti_camera_ack"
local frame_ack_file = world .. "/avanti_camera_frame_ack"
local scene_wait = tonumber(core.settings:get("avanti_camera_scene_wait")) or 10
-- Seconds between moving the camera and asking for the frame, so the client has rendered it.
local frame_wait = tonumber(core.settings:get("avanti_camera_frame_wait")) or 0.04
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

local function write_shots(shots)
	core.safe_file_write(shots_file, core.write_json({ shots = shots }, true))
end

local function read_number(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local n = tonumber(f:read("*l"))
	f:close()
	return n
end

local function eye_height(player)
	return player:get_properties().eye_height or 1.625
end

local function vec(t)
	return vector.new(t[1], t[2], t[3])
end

local function look_angles(eye, target)
	local d = vector.subtract(target, eye)
	return math.atan2(-d.x, d.z), -math.atan2(d.y, math.sqrt(d.x * d.x + d.z * d.z))
end

local function is_video(shot)
	return shot.keys ~= nil or shot.orbit ~= nil
end

-- A camera is { pos = eye vector, yaw, pitch (radians), time, fov }.
local function still_camera(shot)
	local eye = vec(shot.pos)
	local yaw, pitch
	if shot.look_at then
		yaw, pitch = look_angles(eye, vec(shot.look_at))
	else
		yaw, pitch = math.rad(shot.yaw or 0), math.rad(shot.pitch or 0)
	end
	return { pos = eye, yaw = yaw, pitch = pitch, time = shot.time, fov = shot.fov }
end

local function apply(player, cam)
	player:set_physics_override({ gravity = 0, speed = 0, jump = 0 })
	player:set_pos(vector.offset(cam.pos, 0, -eye_height(player), 0))
	player:set_look_horizontal(cam.yaw)
	player:set_look_vertical(cam.pitch)
	if cam.time then
		core.set_timeofday(cam.time % 1) -- times above 1 wrap, so 0.8 -> 1.2 runs through midnight
	end
	player:set_fov(cam.fov or 0, false, 0)
end

-- --------------------------------------------------------------- camera paths

local function ease(u, kind)
	u = math.min(math.max(u, 0), 1)
	if kind == "linear" then
		return u
	end
	return u * u * (3 - 2 * u) -- "inout": start and stop gently
end

-- Index i with ts[i] <= t < ts[i + 1] (ts has at least two entries).
local function segment(ts, t)
	local i = 1
	while i < #ts - 1 and ts[i + 1] <= t do
		i = i + 1
	end
	return i
end

-- Cubic Hermite spline through (ts[i], vs[i]) with Catmull-Rom tangents (uneven spacing is fine).
local function spline(ts, vs, t)
	local n = #ts
	if n == 1 or t <= ts[1] then
		return vs[1]
	elseif t >= ts[n] then
		return vs[n]
	end
	local function tangent(j)
		local p, q = math.max(j - 1, 1), math.min(j + 1, n)
		return (vs[q] - vs[p]) / (ts[q] - ts[p])
	end
	local i = segment(ts, t)
	local h = ts[i + 1] - ts[i]
	local s = (t - ts[i]) / h
	local s2, s3 = s * s, s * s * s
	return (2 * s3 - 3 * s2 + 1) * vs[i] + (s3 - 2 * s2 + s) * h * tangent(i)
		+ (-2 * s3 + 3 * s2) * vs[i + 1] + (s3 - s2) * h * tangent(i + 1)
end

local function linear(ts, vs, t)
	local n = #ts
	if n == 1 or t <= ts[1] then
		return vs[1]
	elseif t >= ts[n] then
		return vs[n]
	end
	local i = segment(ts, t)
	local s = (t - ts[i]) / (ts[i + 1] - ts[i])
	return vs[i] + (vs[i + 1] - vs[i]) * s
end

-- Per-key optional values: missing ones repeat the nearest earlier (or first) given value.
local function fill(keys, field)
	local out, last = {}, nil
	for _, k in ipairs(keys) do
		if k[field] ~= nil then
			last = last or k[field]
		end
	end
	if last == nil then
		return nil
	end
	for i, k in ipairs(keys) do
		last = k[field] ~= nil and k[field] or last
		out[i] = last
	end
	return out
end

-- prepare_video(shot) -> { frames, fps, duration, at = function(t) -> camera, min, max } or nil, error
local function prepare_video(shot)
	local fps = shot.fps or 30
	local video = { fps = fps }
	if shot.orbit then
		local o = shot.orbit
		if not o.center then
			return nil, "orbit needs a center"
		end
		local c = vec(o.center)
		local r, h = o.radius or 6, o.height or 2
		local turns, start = o.turns or 1, math.rad(o.start or 0)
		local dur, kind = shot.duration or 10, shot.ease or "linear"
		local t0 = type(shot.time) == "table" and shot.time[1] or shot.time
		local t1 = type(shot.time) == "table" and shot.time[2] or t0
		video.duration = dur
		video.at = function(t)
			local u = ease(t / dur, kind)
			local angle = start + turns * 2 * math.pi * u
			local eye = vector.new(c.x + r * math.sin(angle), c.y + h, c.z - r * math.cos(angle))
			local yaw, pitch = look_angles(eye, c)
			return { pos = eye, yaw = yaw, pitch = pitch, time = t0 and t0 + (t1 - t0) * u, fov = shot.fov }
		end
		video.min = vector.offset(c, -r, math.min(h, 0), -r)
		video.max = vector.offset(c, r, math.max(h, 0), r)
	else
		local keys = shot.keys
		local n = #keys
		if n == 0 then
			return nil, "no keys"
		end
		local dur = shot.duration or keys[n].t or 2 * (n - 1)
		local ts, px, py, pz, lx, ly, lz, yaws, pitches = {}, {}, {}, {}, {}, {}, {}, {}, {}
		local all_look = true
		for i, k in ipairs(keys) do
			if not k.pos then
				return nil, "key " .. i .. " has no pos"
			end
			ts[i] = keys[n].t and k.t or (n > 1 and dur * (i - 1) / (n - 1) or 0)
			if i > 1 and ts[i] <= ts[i - 1] then
				return nil, "key times must increase"
			end
			px[i], py[i], pz[i] = k.pos[1], k.pos[2], k.pos[3]
			all_look = all_look and k.look_at ~= nil
			local cam = still_camera(k)
			-- unwrap so that each turn takes the short way round
			if i > 1 then
				cam.yaw = yaws[i - 1] + (cam.yaw - yaws[i - 1] + math.pi) % (2 * math.pi) - math.pi
			end
			yaws[i], pitches[i] = cam.yaw, cam.pitch
			if k.look_at then
				lx[i], ly[i], lz[i] = k.look_at[1], k.look_at[2], k.look_at[3]
			end
		end
		local times, fovs = fill(keys, "time"), fill(keys, "fov")
		local kind = shot.ease or "inout"
		video.duration = dur
		video.at = function(t)
			local tk = ts[1] + (dur > 0 and ease(t / dur, kind) or 0) * (ts[n] - ts[1])
			local eye = vector.new(spline(ts, px, tk), spline(ts, py, tk), spline(ts, pz, tk))
			local yaw, pitch
			if all_look then
				yaw, pitch = look_angles(eye, vector.new(spline(ts, lx, tk), spline(ts, ly, tk), spline(ts, lz, tk)))
			else
				yaw, pitch = spline(ts, yaws, tk), spline(ts, pitches, tk)
			end
			return {
				pos = eye,
				yaw = yaw,
				pitch = pitch,
				time = times and linear(ts, times, tk),
				fov = fovs and linear(ts, fovs, tk),
			}
		end
		video.min = vector.new(math.min(unpack(px)), math.min(unpack(py)), math.min(unpack(pz)))
		video.max = vector.new(math.max(unpack(px)), math.max(unpack(py)), math.max(unpack(pz)))
	end
	video.frames = math.floor(video.duration * fps + 0.5) + 1
	if shot.orbit and (shot.orbit.turns or 1) % 1 == 0 and (shot.ease or "linear") == "linear" then
		video.frames = video.frames - 1 -- the last frame would repeat the first: loops seamlessly
	end
	return video
end

-- --------------------------------------------------------------- replay

if mode == "replay" then
	local queue, index, waiting_ack, settle_left, player_name = nil, 0, false, nil, nil
	local since_join = 0
	local video = nil -- { spec, frame, wait, steps, waiting, started }

	local function next_shot(player)
		index = index + 1
		local shot = queue[index]
		video = nil
		if not shot then
			core.log("action", "[avanti_camera] DONE")
			queue = {}
			return
		end
		local lo, hi
		if is_video(shot) then
			local spec, err = prepare_video(shot)
			if not spec then
				core.log("error", ("[avanti_camera] skipping video %s: %s"):format(shot.name or index, err))
				return next_shot(player)
			end
			video = { spec = spec, frame = 0, started = false }
			apply(player, spec.at(0))
			lo, hi = spec.min, spec.max
		elseif shot.pos then
			apply(player, still_camera(shot))
			lo, hi = vec(shot.pos), vec(shot.pos)
		else -- keep the scene's own camera
			settle_left = shot.settle or 2
			return
		end
		settle_left = nil
		core.emerge_area(vector.offset(lo, -48, -32, -48), vector.offset(hi, 48, 32, 48), function(_, _, remaining)
			if remaining == 0 then
				settle_left = shot.settle or 2
			end
		end)
	end

	local function video_step(player, dtime)
		local spec = video.spec
		if video.waiting then
			if read_number(frame_ack_file) ~= video.frame then
				return
			end
			video.frame = video.frame + 1
			if video.frame >= spec.frames then
				return next_shot(player)
			end
			apply(player, spec.at(math.min(video.frame / spec.fps, spec.duration)))
			video.waiting, video.wait, video.steps = false, frame_wait, 0
			return
		end
		video.wait = video.wait - dtime
		video.steps = video.steps + 1
		if video.wait <= 0 and video.steps >= 2 then
			video.waiting = true
			core.log("action", "[avanti_camera] FRAME " .. video.frame)
		end
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
		if video and video.started then
			return video_step(player, dtime)
		end
		if waiting_ack then
			if read_number(ack_file) == index then
				waiting_ack = false
				next_shot(player)
			end
			return
		end
		if settle_left then
			settle_left = settle_left - dtime
			if settle_left <= 0 then
				settle_left = nil
				local name = queue[index].name or index
				if video then
					local spec = video.spec
					video.started, video.waiting, video.wait, video.steps = true, false, frame_wait, 0
					os.remove(frame_ack_file)
					core.log("action", ("[avanti_camera] VIDEO %d %d %d %s"):format(index, spec.frames, spec.fps, name))
				else
					waiting_ack = true
					core.log("action", ("[avanti_camera] READY %d %s"):format(index, name))
				end
			end
		end
	end)
end

-- --------------------------------------------------------------- record

if mode == "record" then
	local round = function(x, n)
		return math.floor(x * 10 ^ n + 0.5) / 10 ^ n
	end

	local function current_view(player)
		local pos = vector.offset(player:get_pos(), 0, eye_height(player), 0)
		local fov = player:get_fov()
		return {
			pos = { round(pos.x, 2), round(pos.y, 2), round(pos.z, 2) },
			yaw = round(math.deg(player:get_look_horizontal()), 1),
			pitch = round(math.deg(player:get_look_vertical()), 1),
			time = round(core.get_timeofday(), 3),
			fov = fov ~= 0 and fov or nil,
		}
	end

	local function find(shots, name)
		for i, s in ipairs(shots) do
			if s.name == name then
				return i, s
			end
		end
	end

	local function clean_name(param)
		return (param:trim():gsub("[^%w_%-]", "_"))
	end

	core.register_chatcommand("shot", {
		params = "<name>",
		description = "Save the current view as a screenshot shot for avanti",
		func = function(name, param)
			local player = core.get_player_by_name(name)
			local shot_name = clean_name(param)
			if not player or shot_name == "" then
				return false, "Usage: /shot <name>"
			end
			local shot = current_view(player)
			shot.name, shot.settle = shot_name, 2
			local shots = read_shots()
			local i = find(shots, shot_name)
			shots[i or #shots + 1] = shot
			write_shots(shots)
			return true, ("Saved shot '%s' (%d in list)%s"):format(shot_name, #shots, i and ", replaced" or "")
		end,
	})

	core.register_chatcommand("key", {
		params = "<video> [seconds after the previous key, default 2]",
		description = "Append the current view as a keyframe of a video for avanti",
		func = function(name, param)
			local player = core.get_player_by_name(name)
			local video_name, gap = param:match("^%s*(%S+)%s*(%S*)")
			video_name = video_name and clean_name(video_name)
			gap = tonumber(gap) or 2
			if not player or not video_name or gap <= 0 then
				return false, "Usage: /key <video> [seconds]"
			end
			local shots = read_shots()
			local _, shot = find(shots, video_name)
			if shot and not shot.keys then
				return false, ("'%s' is a still shot; pick another name"):format(video_name)
			end
			if not shot then
				shot = { name = video_name, fps = 30, keys = {} }
				shots[#shots + 1] = shot
			end
			local key = current_view(player)
			key.t = #shot.keys == 0 and 0 or shot.keys[#shot.keys].t + gap
			shot.keys[#shot.keys + 1] = key
			shot.duration = key.t
			write_shots(shots)
			return true, ("Key %d of video '%s' at %gs. /preview %s plays it, /unkey %s drops the last key.")
				:format(#shot.keys, video_name, key.t, video_name, video_name)
		end,
	})

	core.register_chatcommand("unkey", {
		params = "<video>",
		description = "Drop the last keyframe of a video",
		func = function(_, param)
			local shots = read_shots()
			local i, shot = find(shots, clean_name(param))
			if not shot or not shot.keys then
				return false, "No such video"
			end
			shot.keys[#shot.keys] = nil
			if #shot.keys == 0 then
				table.remove(shots, i)
			else
				shot.duration = shot.keys[#shot.keys].t
			end
			write_shots(shots)
			return true, ("'%s' has %d key(s)"):format(shot.name, #shot.keys)
		end,
	})

	local preview = nil -- { player, spec, t, physics, fov }

	core.register_chatcommand("preview", {
		params = "<video>",
		description = "Play a recorded video's camera path (choppier than the real render)",
		func = function(name, param)
			local player = core.get_player_by_name(name)
			local _, shot = find(read_shots(), clean_name(param))
			if not player or not shot or not is_video(shot) then
				return false, "No such video"
			end
			local spec, err = prepare_video(shot)
			if not spec then
				return false, err
			end
			preview = { player = name, spec = spec, t = 0, physics = player:get_physics_override(), fov = player:get_fov() }
			return true, ("Playing '%s' (%gs)"):format(shot.name, spec.duration)
		end,
	})

	core.register_globalstep(function(dtime)
		local player = preview and core.get_player_by_name(preview.player)
		if not player then
			preview = nil
			return
		end
		preview.t = math.min(preview.t + dtime, preview.spec.duration)
		apply(player, preview.spec.at(preview.t))
		if preview.t >= preview.spec.duration then
			player:set_physics_override(preview.physics)
			player:set_fov(preview.fov, false, 0)
			preview = nil
		end
	end)

	core.register_chatcommand("shots", {
		description = "List the recorded screenshot shots and videos",
		func = function()
			local names = {}
			for _, s in ipairs(read_shots()) do
				names[#names + 1] = s.keys and ("%s (video, %d keys)"):format(s.name, #s.keys) or s.name
			end
			return true, #names == 0 and "No shots yet. Fly to a spot and use /shot <name> or /key <video>."
				or table.concat(names, ", ")
		end,
	})

	core.register_on_joinplayer(function(player)
		core.chat_send_player(player:get_player_name(), "[avanti] Record mode: fly (K), set the time with /time, then "
			.. "/shot <name> for a still or /key <video> [seconds] per keyframe of a video (/preview <video> plays it). "
			.. "/shots lists them. Quit when done.")
	end)
end
