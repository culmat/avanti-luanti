-- Works with every luacheck version (no reliance on the newer built-in "minetest" std).
std = "luajit"
max_line_length = 120
unused_args = false

globals = {
	"{{modname}}",
}

read_globals = {
	-- Engine API
	"core", "minetest", "vector", "ItemStack", "VoxelArea", "VoxelManip", "Settings", "AreaStore",
	"PseudoRandom", "PcgRandom", "SecureRandom", "PerlinNoise", "PerlinNoiseMap", "ValueNoise",
	"ValueNoiseMap", "Raycast", "dump", "dump2", "DIR_DELIM", "INIT",
	string = { fields = { "split", "trim" } },
	table = { fields = { "copy", "copy_with_metatables", "indexof", "keyof", "insert_all", "key_value_swap", "shuffle" } },
	math = { fields = { "hypot", "sign", "factorial", "round", "isfinite" } },

	-- Globals of declared dependencies. Regenerate with: ldg globals .
}

files["test/"] = {
	read_globals = { "mtt" },
}
