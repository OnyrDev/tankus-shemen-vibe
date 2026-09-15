class_name CardDefinition
extends Resource

## Определение карты способности TANKUS.
## Представляет отдельную карточку из пула способностей в стиле ROUNDS.

enum Category {
	SHOT,
	BLOCK,
	JUMP,
	GENERAL,
}

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var category: Category = Category.GENERAL
@export var icon: Texture2D = null
@export var unique: bool = false
@export var max_stacks: int = 99
@export var tags: Array[String] = []

## Словарь статических модификаторов характеристик танка:
## например: {"damage_mult": 1.45, "proj_speed_mult": 0.8, "magazine_flat": 1}
@export var stat_modifiers: Dictionary = {}

## Опциональный кастомный скрипт эффекта, наследующий CardEffect
@export var effect_script: Script = null

func get_category_name() -> String:
	match category:
		Category.SHOT:
			return "SHOT"
		Category.BLOCK:
			return "BLOCK"
		Category.JUMP:
			return "JUMP"
		Category.GENERAL:
			return "GENERAL"
		_:
			return "GENERAL"

func get_category_color() -> Color:
	match category:
		Category.SHOT:
			return Color(0.95, 0.3, 0.25) # Красный
		Category.BLOCK:
			return Color(0.2, 0.65, 0.95) # Голубой
		Category.JUMP:
			return Color(0.25, 0.85, 0.45) # Зеленый
		Category.GENERAL:
			return Color(0.95, 0.75, 0.2) # Золотисто-желтый
		_:
			return Color.WHITE
