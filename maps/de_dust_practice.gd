extends TestSandbox

## Быстрый запуск тренировки на карте Dust I (F6).
func _ready() -> void:
	Game.rules.selected_map = "de_dust"
	Game.is_solo_practice = true
	super._ready()

