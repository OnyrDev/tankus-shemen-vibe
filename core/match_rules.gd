class_name MatchRules
extends Resource

@export var target_round_wins: int = 5
@export var is_team_mode: bool = false
@export var team_count: int = 2
@export var friendly_fire: bool = false
@export var draft_timeout_sec: float = 20.0
@export var initial_draft_count: int = 5
@export var round_time_limit_sec: float = 0.0 # 0.0 = unlimited

func to_dict() -> Dictionary:
	return {
		"target_round_wins": target_round_wins,
		"is_team_mode": is_team_mode,
		"team_count": team_count,
		"friendly_fire": friendly_fire,
		"draft_timeout_sec": draft_timeout_sec,
		"initial_draft_count": initial_draft_count,
		"round_time_limit_sec": round_time_limit_sec
	}

func load_dict(d: Dictionary) -> void:
	target_round_wins = d.get("target_round_wins", target_round_wins)
	is_team_mode = d.get("is_team_mode", is_team_mode)
	team_count = d.get("team_count", team_count)
	friendly_fire = d.get("friendly_fire", friendly_fire)
	draft_timeout_sec = d.get("draft_timeout_sec", draft_timeout_sec)
	initial_draft_count = d.get("initial_draft_count", initial_draft_count)
	round_time_limit_sec = d.get("round_time_limit_sec", round_time_limit_sec)
