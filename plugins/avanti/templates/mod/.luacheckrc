std = "luajit+minetest"
max_line_length = 120

globals = {
	"{{modname}}",
}

-- Globals of declared dependencies. Regenerate with: ldg globals .
read_globals = {
}

files["test/"] = {
	read_globals = { "mtt" },
}
