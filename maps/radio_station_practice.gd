extends TestSandbox

func _ready() -> void:
	Game.rules.selected_map = "radio_station"
	Game.is_solo_practice = true
	super._ready()
