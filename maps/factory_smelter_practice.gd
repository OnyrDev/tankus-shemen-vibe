extends TestSandbox

## Быстрый запуск карты «Завод — Плавильня» по F6 в соло-режиме без перезаписи настроек.
func _ready() -> void:
	Game.rules.selected_map = "factory_smelter"
	Game.is_solo_practice = true
	super._ready()
