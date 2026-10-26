class_name MatchRules
extends Resource

const MAP_SCENES: Dictionary = {
	"sky_courtyard": "res://maps/sky_courtyard.tscn",
	"iceworks": "res://maps/iceworks.tscn",
	"pendulum_yard": "res://maps/pendulum_yard.tscn",
	"shift": "res://maps/shift.tscn",
	"atrium": "res://maps/atrium.tscn",
	"ceramic_garden": "res://maps/ceramic_garden.tscn",
	"radio_station": "res://maps/radio_station.tscn"
}

# 8 означает автоматическое заполнение всех свободных мест ботами.
@export_range(0, 8) var bot_count: int = 0
@export_range(0, 2) var bot_difficulty: int = 1

@export var target_round_wins: int = 5
@export var is_team_mode: bool = false
@export var team_count: int = 2
@export var friendly_fire: bool = false
@export var draft_timeout_sec: float = 20.0
@export var initial_draft_count: int = 5
@export var round_time_limit_sec: float = 0.0 # 0.0 = unlimited
@export var selected_map: String = "sky_courtyard"

func to_dict() -> Dictionary:
	return {
		"target_round_wins": target_round_wins,
		"bot_count": bot_count,
		"bot_difficulty": bot_difficulty,
		"is_team_mode": is_team_mode,
		"team_count": team_count,
		"friendly_fire": friendly_fire,
		"draft_timeout_sec": draft_timeout_sec,
		"initial_draft_count": initial_draft_count,
		"round_time_limit_sec": round_time_limit_sec,
		"selected_map": selected_map
	}

func load_dict(d: Dictionary) -> void:
	bot_count = clampi(d.get("bot_count", bot_count), 0, 8)
	bot_difficulty = clampi(d.get("bot_difficulty", bot_difficulty), 0, 2)
	target_round_wins = d.get("target_round_wins", target_round_wins)
	is_team_mode = d.get("is_team_mode", is_team_mode)
	team_count = clampi(d.get("team_count", team_count), 2, 4)
	friendly_fire = d.get("friendly_fire", friendly_fire)
	draft_timeout_sec = d.get("draft_timeout_sec", draft_timeout_sec)
	initial_draft_count = d.get("initial_draft_count", initial_draft_count)
	round_time_limit_sec = d.get("round_time_limit_sec", round_time_limit_sec)
	selected_map = d.get("selected_map", selected_map)

## Выбор делает только сервер; предыдущая арена исключается из кандидатов.
func pick_random_map(previous_map: String = "") -> String:
	var candidates: Array = MAP_SCENES.keys()
	if candidates.size() > 1:
		candidates.erase(previous_map)
	return candidates.pick_random()
