class_name TankBotController
extends RefCounted

## Решения ИИ выполняются только сервером. Сложность меняет реакцию, ошибку
## наведения, упреждение и манёвры, не характеристики танка и урон.
const REACTION: Array[float] = [0.65, 0.28, 0.12]
const AIM_ERROR: Array[float] = [1.2, 0.65, 0.18]
const LEAD: Array[float] = [0.0, 0.5, 0.9]
const DESIRED_RANGE: Array[float] = [8.0, 11.0, 14.0]

var difficulty: int = 1
var target: Tank = null
var _tank: Tank
var _rng := RandomNumberGenerator.new()
var _think_timer: float = 0.0
var _path_timer: float = 0.0
var _strafe_timer: float = 0.0
var _strafe_sign: float = 1.0
var _aim: Vector3 = Vector3.ZERO
var _visible: bool = false
var _path := PackedVector3Array()
var _path_index: int = 0
var _stuck_time: float = 0.0
var _last_position: Vector3 = Vector3.ZERO
var _decision: Dictionary = {}

func _init(tank: Tank, level: int) -> void:
	_tank = tank
	difficulty = clampi(level, 0, 2)
	_rng.randomize()
	_strafe_sign = -1.0 if _rng.randf() < 0.5 else 1.0
	reset()

func reset() -> void:
	target = null
	_think_timer = 0.0
	_path_timer = 0.0
	_path.clear()
	_stuck_time = 0.0
	_last_position = _tank.global_position

func update(delta: float) -> Dictionary:
	_decision = {"move": Vector3.ZERO, "aim": _aim, "aim_valid": false,
		"jump": false, "fire": false, "block": false, "reload": false}
	if not Game.is_in_match or Game.match_state != "PLAYING" or not _tank.is_active or _tank.is_frozen:
		return _decision
	_think_timer -= delta
	_path_timer -= delta
	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = _rng.randf_range(0.8, 1.8)
		_strafe_sign *= -1.0
	if _think_timer <= 0.0:
		_think_timer = REACTION[difficulty]
		_choose_target()
		_update_aim()
	if not is_instance_valid(target) or not target.is_active:
		return _decision
	_decision.aim = _aim
	_decision.aim_valid = true
	_visible = _can_see(target)
	var to_target := target.global_position - _tank.global_position
	var flat := Vector3(to_target.x, 0, to_target.z)
	var distance := flat.length()
	var move := Vector3.ZERO
	if _visible and distance < DESIRED_RANGE[difficulty] + 2.0 and absf(to_target.y) < 1.5:
		if distance < DESIRED_RANGE[difficulty] - 2.0:
			move = -flat.normalized()
		elif difficulty > 0:
			move = Vector3(-flat.z, 0, flat.x).normalized() * _strafe_sign
	else:
		move = _follow_path(target.global_position)
	var intended_move := move
	move = _safe_direction(move)
	_decision.move = move
	if intended_move.length_squared() > 0.1 and _tank.global_position.distance_to(_last_position) < delta * 0.4:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	_last_position = _tank.global_position
	if _stuck_time > 0.7 and _tank.is_on_floor():
		_decision.jump = _can_jump_obstacle(intended_move)
		if _decision.jump:
			_decision.move = intended_move
		_path_timer = 0.0
		_strafe_sign *= -1.0
		_stuck_time = 0.0
	if _visible and _tank.turret:
		var direction := (_aim - _tank.turret.get_muzzle_position()).normalized()
		var barrel := -_tank.turret.muzzle.global_basis.z if _tank.turret.muzzle else -_tank.global_basis.z
		_decision.fire = barrel.normalized().dot(direction) > [0.96, 0.985, 0.995][difficulty]
		# Проверяем реальный сектор выстрела, чтобы не стрелять в союзника.
		if _decision.fire:
			var hit := _ray(_tank.turret.get_muzzle_position(), _aim, 11)
			if not hit.is_empty() and hit.collider is Tank and _is_ally(hit.collider):
				_decision.fire = false
	if difficulty > 0:
		_decision.block = _incoming_projectile()
		_decision.reload = not _visible and _tank.weapon and _tank.weapon.current_ammo <= 2
	return _decision

func _choose_target() -> void:
	var best_score := INF
	var chosen: Tank = null
	for node in _tank.get_parent().get_children():
		var candidate := node as Tank
		if candidate == null or candidate == _tank or not candidate.is_active or candidate.is_queued_for_deletion() or _is_ally(candidate):
			continue
		var score := _tank.global_position.distance_squared_to(candidate.global_position)
		if _can_see(candidate):
			score *= 0.35
		if candidate == target:
			score *= 0.85
		if score < best_score:
			best_score = score
			chosen = candidate
	if target != chosen:
		_path_timer = 0.0
	target = chosen

func _is_ally(other: Tank) -> bool:
	return Game.rules.is_team_mode and other.team_id == _tank.team_id

func _can_see(other: Tank) -> bool:
	var from := _tank.turret.get_muzzle_position() if _tank.turret else _tank.global_position + Vector3.UP * 0.6
	var point := other.global_position + Vector3.UP * 0.5
	for offset in [Vector3.ZERO, Vector3.DOWN * 0.15]:
		var hit := _ray(from + offset, point + offset, 11)
		if not hit.is_empty() and hit.collider != other:
			return false
	return true

func _update_aim() -> void:
	if not is_instance_valid(target):
		return
	var speed := _tank.stats.projectile_speed if _tank.stats else 24.0
	var travel := minf(1.0, _tank.global_position.distance_to(target.global_position) / maxf(speed, 1.0))
	_aim = target.global_position + Vector3.UP * 0.5 + target.velocity * travel * LEAD[difficulty]
	_aim += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.25, 0.25), _rng.randf_range(-1, 1)) * AIM_ERROR[difficulty]

func _follow_path(goal: Vector3) -> Vector3:
	if _path_timer <= 0.0:
		_path_timer = maxf(0.4, REACTION[difficulty])
		var navigation := _tank.get_tree().get_first_node_in_group("bot_navigation") as BotNavigation
		_path = navigation.find_firing_path(_tank.global_position, goal, DESIRED_RANGE[difficulty]) if navigation else PackedVector3Array()
		if _path.is_empty() and navigation:
			_path = navigation.find_path(_tank.global_position, goal)
		_path_index = 0
	while _path_index < _path.size():
		var waypoint := _path[_path_index]
		var offset := waypoint - _tank.global_position
		var distance := Vector2(offset.x, offset.z).length()
		var is_last := _path_index == _path.size() - 1
		if distance > (0.35 if is_last else 0.9):
			var speed := minf(1.0, distance / 2.0) if is_last else 1.0
			return Vector3(offset.x, 0, offset.z).normalized() * speed
		_path_index += 1
	if not _path.is_empty():
		return Vector3.ZERO
	var direct := goal - _tank.global_position
	return Vector3(direct.x, 0, direct.z).normalized()

func _safe_direction(desired: Vector3) -> Vector3:
	if desired.length_squared() < 0.01:
		return Vector3.ZERO
	for angle in [0.0, 0.6 * _strafe_sign, -0.6 * _strafe_sign, 1.2 * _strafe_sign, -1.2 * _strafe_sign]:
		var direction := desired.rotated(Vector3.UP, angle)
		var ahead := _tank.global_position + direction * 1.5
		var support := _ray(ahead + Vector3.UP * 1.3, ahead - Vector3.UP * 3.0, 9)
		if support.is_empty() or support.normal.y < 0.57:
			continue
		if _ray(_tank.global_position + Vector3.UP * 0.6, ahead + Vector3.UP * 0.6, 9).is_empty():
			return direction
	return Vector3.ZERO

func _can_jump_obstacle(direction: Vector3) -> bool:
	if direction.length_squared() < 0.1:
		return false
	var ahead := _tank.global_position + direction * 2.0
	return not _ray(ahead + Vector3.UP, ahead - Vector3.UP, 9).is_empty() and _ray(_tank.global_position + Vector3.UP * 1.8, ahead + Vector3.UP * 1.8, 9).is_empty()

func _incoming_projectile() -> bool:
	for node in _tank.get_tree().get_nodes_in_group("projectiles"):
		var projectile := node as Projectile
		if projectile == null or projectile.get_shooter_tank() == _tank:
			continue
		var shooter := projectile.get_shooter_tank()
		if shooter and _is_ally(shooter) and not Game.rules.friendly_fire:
			continue
		var towards := _tank.global_position + Vector3.UP * 0.4 - projectile.global_position
		var radius := 4.0 if difficulty == 1 else 7.0
		if towards.length() < radius and projectile.velocity.normalized().dot(towards.normalized()) > 0.9:
			return true
	return false

func _ray(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	query.exclude = [_tank.get_rid()]
	return _tank.get_world_3d().direct_space_state.intersect_ray(query)

func choose_card() -> CardDefinition:
	var offer := CardDatabase.generate_draft_offer(_tank.build)
	if offer.is_empty():
		return null
	if difficulty == 0:
		return offer[_rng.randi_range(0, offer.size() - 1)]
	var preferred := ["rapid_fire", "fastball", "tankier", "quick_reload", "regeneration", "bouncy", "heavy_shell"]
	for card in offer:
		if card.id in preferred:
			return card
	return offer[0]
