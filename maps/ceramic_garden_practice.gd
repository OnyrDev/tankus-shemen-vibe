extends TestSandbox

## F6 / direct command-line entry to the new map without changing saved defaults.
func _ready() -> void:
	Game.rules.selected_map = "ceramic_garden"
	Game.is_solo_practice = true
	super._ready()
