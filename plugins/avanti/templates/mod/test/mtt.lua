-- Integration tests, run inside the engine by `avanti test` (https://github.com/BuckarooBanzay/mtt).
mtt.register("{{modname}}: API table exists", function(callback)
	assert(type({{modname}}) == "table", "{{modname}} global missing")
	callback()
end)
