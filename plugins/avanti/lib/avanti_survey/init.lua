-- Map generation survey for `avanti survey`. Inert unless avanti_survey = true.
--
-- Generates square rings of tiles (3x3 mapchunks, two chunk layers around sea level) around the
-- origin until a chunk budget is spent, counts the surface biomes, and records structures:
--   * generically: core.place_schematic / place_schematic_on_vmanip calls (by schematic file name)
--     and named schematic decorations (via gennotify), if the schematic is at least 10 nodes wide
--     and 4 high;
--   * from bridge mods: avanti_survey.report(kind, id, pos, extra).
-- At the end it writes <world>/avanti_survey.json, logs "[avanti_survey] DONE" and shuts down.
-- Not seen: structures placed in the mapgen environment (core.register_mapgen_script, 5.9+).
--
-- API for a mod's dev-only bridge (optional_depends = avanti_survey):
--   avanti_survey.report(kind, id, pos[, extra])  one placed feature; extra is a JSON-able table
--   avanti_survey.register_on_finish(fn)  fn() returns a table stored under mods.<modname>
--   avanti_survey.finding(level, code, message)  "info" | "warn" | "fail"
--   avanti_survey.ignore(pattern)  schematic files matching this Lua pattern are not reported
--     generically (the bridge reports them itself, under its own names)
if not core.settings:get_bool("avanti_survey", false) then
	return
end

local settings = core.settings
local CHUNKS = math.max(9, tonumber(settings:get("avanti_survey_chunks")) or 1800)
local SPACING = math.max(0, tonumber(settings:get("avanti_survey_spacing")) or 0)
local TIMEOUT = tonumber(settings:get("avanti_survey_timeout")) or 900
local SETTLE = tonumber(settings:get("avanti_survey_settle")) or 5
local MAX_PLACEMENTS = 5000
local SAMPLE = 4 -- census: every 4th column in x and z

avanti_survey = {}
local features = {} -- list of {kind, id, pos, biome, extra}
local findings = {}
local finishers = {}
local census = { chunks = 0, samples = 0, biomes = {} }
local started = os.clock()
local wall_start = core.get_us_time()

local function log(msg, ...)
	core.log("action", "[avanti_survey] " .. msg:format(...))
end

local function biome_at(pos)
	local bd = core.get_biome_data(pos)
	return bd and core.get_biome_name(bd.biome) or nil
end

function avanti_survey.report(kind, id, pos, extra)
	features[#features + 1] = {
		kind = tostring(kind),
		id = tostring(id),
		pos = vector.round(pos),
		biome = biome_at(pos),
		extra = extra,
	}
end

function avanti_survey.register_on_finish(fn)
	finishers[#finishers + 1] = { mod = core.get_current_modname() or "?", fn = fn }
end

function avanti_survey.finding(level, code, msg)
	findings[#findings + 1] = { level = level, code = code, message = msg }
end

local ignored = {}
function avanti_survey.ignore(pattern)
	ignored[#ignored + 1] = pattern
end

-- ------------------------------------------------------------ generic detection

-- Smaller or flatter schematics are trees, bushes, rocks and fallen logs, not structures.
local MIN_FOOTPRINT, MIN_HEIGHT = 10, 4
local function structure_sized(size)
	return size ~= nil and math.max(size.x, size.z) >= MIN_FOOTPRINT and size.y >= MIN_HEIGHT
end
local sizes = {} -- schematic file -> size (or false)

local function schematic_size(schematic)
	if type(schematic) == "table" then
		return schematic.size
	elseif type(schematic) == "string" then
		if sizes[schematic] == nil then
			local s = core.read_schematic(schematic, {})
			sizes[schematic] = s and s.size or false
		end
		return sizes[schematic] or nil
	end
end

-- Name of a structure-sized schematic, or nil for small ones and unknown sizes.
local function structure_name(schematic)
	local size = schematic_size(schematic)
	if not structure_sized(size) then
		return nil
	end
	if type(schematic) == "string" then
		return (schematic:match("([^/\\]+)%.mts$") or schematic:match("([^/\\]+)$") or schematic)
	end
	return ("(table %dx%dx%d)"):format(size.x, size.y, size.z)
end

for _, fname in ipairs({ "place_schematic", "place_schematic_on_vmanip" }) do
	local orig = core[fname]
	core[fname] = function(...)
		local a = { ... }
		local pos = fname == "place_schematic" and a[1] or a[2]
		local schematic = fname == "place_schematic" and a[2] or a[3]
		local skip = type(pos) ~= "table" or pos.x == nil
		for _, pattern in ipairs(ignored) do
			if type(schematic) == "string" and schematic:find(pattern) then
				skip = true
			end
		end
		local name = not skip and structure_name(schematic)
		if name then
			avanti_survey.report("schematic", name, pos)
		end
		return orig(...)
	end
end

local decorations = {} -- deco id -> name
core.register_on_mods_loaded(function()
	local ids = {}
	for _, def in pairs(core.registered_decorations) do
		if def.deco_type == "schematic" and def.name then
			local size = schematic_size(def.schematic)
			local id = core.get_decoration_id(def.name)
			if id and structure_sized(size) then
				decorations[id] = def.name
				ids[#ids + 1] = id
			end
		end
	end
	if #ids > 0 then
		core.set_gen_notify({ decoration = true }, ids)
	end
	log("watching %d schematic decoration(s), %d chunk(s) budget", #ids, CHUNKS)
end)

core.register_on_generated(function(minp, maxp)
	census.chunks = census.chunks + 1
	local heightmap = core.get_mapgen_object("heightmap")
	local biomemap = core.get_mapgen_object("biomemap")
	if heightmap then
		local csx = maxp.x - minp.x + 1
		for z = 0, maxp.z - minp.z, SAMPLE do
			for x = 0, csx - 1, SAMPLE do
				local i = z * csx + x + 1
				local h = heightmap[i]
				if h and h >= minp.y and h < maxp.y then
					local name = biomemap and biomemap[i] and core.get_biome_name(biomemap[i]) or "(none)"
					census.samples = census.samples + 1
					census.biomes[name] = (census.biomes[name] or 0) + 1
				end
			end
		end
	end
	if next(decorations) then
		local gn = core.get_mapgen_object("gennotify") or {}
		for id, name in pairs(decorations) do
			for _, pos in ipairs(gn["decoration#" .. id] or {}) do
				avanti_survey.report("decoration", name, pos)
			end
		end
	end
end)

-- ------------------------------------------------------------ tiles

local chunksize = tonumber(core.get_mapgen_setting("chunksize")) or 5
local C = chunksize * 16
local OFF = -math.floor(chunksize / 2) * 16
local water = tonumber(core.get_mapgen_setting("water_level")) or 1
local function chunk_min(v)
	return math.floor((v - OFF) / C) * C + OFF
end
local Y1 = chunk_min(water)
local Y2 = Y1 + 2 * C - 1
local TILE = 3 * C
local STEP = math.max(TILE, SPACING)
local PER_TILE = 3 * 3 * 2

local function ring_tiles(r)
	if r == 0 then
		return { { 0, 0 } }
	end
	local out = {}
	for d = -r, r - 1 do
		out[#out + 1] = { d, -r }
		out[#out + 1] = { r, d }
		out[#out + 1] = { -d, r }
		out[#out + 1] = { -r, -d }
	end
	return out
end

local tiles_total = math.max(1, math.floor(CHUNKS / PER_TILE))
local state = { r = 0, k = 1, ring = ring_tiles(0), done = 0, finished = false, timed_out = false }
local bounds

local function nn(points)
	if #points < 2 then
		return nil, nil
	end
	local sum, min = 0, math.huge
	for i, a in ipairs(points) do
		local best = math.huge
		for j, b in ipairs(points) do
			if i ~= j then
				local dx, dz = a.x - b.x, a.z - b.z
				best = math.min(best, math.sqrt(dx * dx + dz * dz))
			end
		end
		sum, min = sum + best, math.min(min, best)
	end
	return sum / #points, min
end

local function finish()
	if state.finished then
		return
	end
	state.finished = true
	local km2 = census.samples * SAMPLE * SAMPLE / 1e6
	local mods = {}
	for _, f in ipairs(finishers) do
		local ok, res = pcall(f.fn, { surface_km2 = km2, features = features, bounds = bounds })
		if ok then
			mods[f.mod] = res
		else
			avanti_survey.finding("fail", "AS001", ("%s: survey report failed: %s"):format(f.mod, tostring(res)))
		end
	end
	local biomes = {}
	for name, n in pairs(census.biomes) do
		biomes[#biomes + 1] = { name = name, km2 = n * SAMPLE * SAMPLE / 1e6, share = n / math.max(1, census.samples) }
	end
	table.sort(biomes, function(a, b)
		return a.km2 > b.km2
	end)
	local groups, order = {}, {}
	for _, f in ipairs(features) do
		local key = f.kind .. "\0" .. f.id
		if not groups[key] then
			groups[key] = { kind = f.kind, id = f.id, points = {}, biomes = {} }
			order[#order + 1] = key
		end
		local g = groups[key]
		g.points[#g.points + 1] = f.pos
		if f.biome then
			g.biomes[f.biome] = (g.biomes[f.biome] or 0) + 1
		end
	end
	local summary = {}
	for _, key in ipairs(order) do
		local g = groups[key]
		local mean, min = nn(g.points)
		summary[#summary + 1] = {
			kind = g.kind,
			id = g.id,
			count = #g.points,
			per_km2 = km2 > 0 and #g.points / km2 or 0,
			nn_mean = mean,
			nn_min = min,
			biomes = g.biomes,
		}
	end
	table.sort(summary, function(a, b)
		if a.kind ~= b.kind then
			return a.kind < b.kind
		end
		return a.count > b.count
	end)
	if state.timed_out then
		local msg = ("timed out after %d s: %d of %d tiles"):format(TIMEOUT, state.done, tiles_total)
		avanti_survey.finding("warn", "AS002", msg)
	end
	local placements = {}
	for i = 1, math.min(#features, MAX_PLACEMENTS) do
		placements[i] = features[i]
	end
	local info = core.get_game_info and core.get_game_info() or {}
	local report = {
		version = 1,
		game = info.id,
		seed = core.get_mapgen_setting("seed"),
		mg_name = core.get_mapgen_setting("mg_name"),
		chunks = census.chunks,
		tiles = state.done,
		tile_size = TILE,
		spacing = STEP,
		y = { Y1, Y2 },
		bounds = bounds,
		seconds = (core.get_us_time() - wall_start) / 1e6,
		cpu_seconds = os.clock() - started,
		surface_km2 = km2,
		biomes = biomes,
		features = summary,
		placements = placements,
		placements_truncated = #features > MAX_PLACEMENTS,
		mods = mods,
		findings = findings,
	}
	core.safe_file_write(core.get_worldpath() .. "/avanti_survey.json", core.write_json(report, true))
	log(
		"DONE chunks=%d tiles=%d km2=%.2f features=%d seconds=%.1f",
		census.chunks,
		state.done,
		km2,
		#features,
		report.seconds
	)
	core.request_shutdown("avanti survey finished", false, 0)
end

local function next_tile()
	if state.done >= tiles_total or state.timed_out then
		core.after(SETTLE, finish)
		return
	end
	if state.k > #state.ring then
		state.r, state.k = state.r + 1, 1
		state.ring = ring_tiles(state.r)
	end
	local t = state.ring[state.k]
	state.k = state.k + 1
	local x1, z1 = chunk_min(t[1] * STEP), chunk_min(t[2] * STEP)
	local p1 = { x = x1 - C, y = Y1, z = z1 - C }
	local p2 = { x = x1 + 2 * C - 1, y = Y2, z = z1 + 2 * C - 1 }
	if bounds then
		bounds.min = { x = math.min(bounds.min.x, p1.x), z = math.min(bounds.min.z, p1.z) }
		bounds.max = { x = math.max(bounds.max.x, p2.x), z = math.max(bounds.max.z, p2.z) }
	else
		bounds = { min = { x = p1.x, z = p1.z }, max = { x = p2.x, z = p2.z } }
	end
	core.emerge_area(p1, p2, function(_, _, remaining)
		if remaining > 0 then
			return
		end
		state.done = state.done + 1
		log("TILE %d/%d chunks=%d", state.done, tiles_total, census.chunks)
		core.after(0, next_tile)
	end)
end

local elapsed = 0
core.register_globalstep(function(dtime)
	elapsed = elapsed + dtime
	if not state.finished and not state.timed_out and elapsed >= TIMEOUT then
		state.timed_out = true
		core.after(0, finish)
	end
end)

core.after(1, next_tile)
