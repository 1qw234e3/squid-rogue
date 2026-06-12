extends CharacterBody2D
## 守卫(设计文档 §3.7 守卫小队 AI):巡逻 → 视锥发现(120°、6 格)→
## 呼叫周围守卫包抄 → 沿 A* 路径追捕并射击。挨打也会立刻警觉并叫人。

const Weapon := preload("res://scripts/combat/weapon.gd")
const Pickup := preload("res://scripts/combat/pickup.gd")

enum State { PATROL, CHASE }

const PATROL_SPEED := 45.0
const CHASE_SPEED := 80.0
const VISION_RANGE := 96.0           # 6 格 × 16px,按设计文档 §2.4
const VISION_HALF_ANGLE := PI / 3.0  # 120° 视锥的一半
const FIRE_RANGE := 120.0
const CALL_RANGE := 150.0            # 呼叫包抄的广播半径

var state := State.PATROL
var hp := 3
var arena: Node2D
var target: CharacterBody2D
var patrol_a := Vector2.ZERO
var patrol_b := Vector2.ZERO
var patrol_to_b := true
var wait_timer := 0.0
var path := PackedVector2Array()
var path_index := 0
var repath_timer := 0.0
var facing := Vector2.RIGHT
var weapon: Node2D
var cone: Polygon2D
var body_rect: ColorRect


## 由场景在 add_child 之前调用,注入地图(寻路)、目标和巡逻路线
func setup(arena_: Node2D, target_: CharacterBody2D, a: Vector2, b: Vector2) -> void:
	arena = arena_
	target = target_
	patrol_a = a
	patrol_b = b


func _ready() -> void:
	add_to_group("guards")
	collision_layer = 4
	collision_mask = 1 | 2
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(12, 14)
	shape.shape = rect
	add_child(shape)
	# 视锥可视化:玩家能看见危险范围,潜行绕后才成立
	cone = Polygon2D.new()
	cone.polygon = _cone_points()
	cone.color = Color(1.0, 0.85, 0.3, 0.10)
	add_child(cone)
	body_rect = ColorRect.new()
	body_rect.size = Vector2(12, 18)
	body_rect.position = Vector2(-6, -11)
	body_rect.color = Color("b3543d")  # 铜盔守卫占位色(深海主题,设计文档 §9)
	add_child(body_rect)
	weapon = Weapon.new()
	weapon.setup(Weapon.GUARD_RIFLE, "guards", 1 | 2)  # 守卫子弹打墙和玩家
	add_child(weapon)


func _cone_points() -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2.ZERO])
	for i in 9:
		var ang := lerpf(-VISION_HALF_ANGLE, VISION_HALF_ANGLE, i / 8.0)
		pts.append(Vector2.from_angle(ang) * VISION_RANGE)
	return pts


func _physics_process(delta: float) -> void:
	if hp <= 0:
		return
	match state:
		State.PATROL:
			_patrol(delta)
		State.CHASE:
			_chase(delta)
	move_and_slide()
	if velocity.length() > 1.0:
		facing = velocity.normalized()
	cone.rotation = facing.angle()


func _patrol(delta: float) -> void:
	if wait_timer > 0.0:
		wait_timer -= delta
		velocity = Vector2.ZERO
	else:
		var goal := patrol_b if patrol_to_b else patrol_a
		var to := goal - global_position
		if to.length() < 6.0:
			patrol_to_b = not patrol_to_b
			wait_timer = randf_range(0.6, 1.6)  # 到点停一会儿,留出潜行窗口
			velocity = Vector2.ZERO
		else:
			velocity = to.normalized() * PATROL_SPEED
	if _can_see_target():
		_enter_chase()


func _chase(delta: float) -> void:
	if not is_instance_valid(target) or not target.visible:
		velocity = Vector2.ZERO  # 玩家已死,原地待命
		return
	var dist := global_position.distance_to(target.global_position)
	var sees := _los_clear(target.global_position)
	if dist < FIRE_RANGE and sees:
		# 看得见就开火;太近不再贴脸,保持压迫距离
		velocity = Vector2.ZERO if dist < 70.0 else (target.global_position - global_position).normalized() * CHASE_SPEED * 0.5
		var aim := (target.global_position - global_position).normalized()
		facing = aim
		weapon.set_aim(aim)
		weapon.try_fire()
	else:
		# 看不见就沿 A* 路径逼近,每 0.4s 重算一次
		repath_timer -= delta
		if repath_timer <= 0.0 or path_index >= path.size():
			path = arena.find_path(global_position, target.global_position)
			path_index = 0
			repath_timer = 0.4
		if path_index < path.size():
			var wp := path[path_index]
			if global_position.distance_to(wp) < 6.0:
				path_index += 1
				velocity = Vector2.ZERO
			else:
				velocity = (wp - global_position).normalized() * CHASE_SPEED
		else:
			velocity = (target.global_position - global_position).normalized() * CHASE_SPEED


func _can_see_target() -> bool:
	if not is_instance_valid(target) or not target.visible:
		return false
	var to := target.global_position - global_position
	if to.length() > VISION_RANGE:
		return false
	if absf(facing.angle_to(to)) > VISION_HALF_ANGLE:
		return false
	return _los_clear(target.global_position)


## 视线检测:只对墙(layer 1)打射线,没挡住就算看得见
func _los_clear(point: Vector2) -> bool:
	var params := PhysicsRayQueryParameters2D.create(global_position, point, 1)
	return get_world_2d().direct_space_state.intersect_ray(params).is_empty()


func force_chase() -> void:
	if state == State.CHASE or hp <= 0:
		return
	state = State.CHASE
	cone.color = Color(1.0, 0.25, 0.2, 0.14)  # 视锥变红 = 已警觉


func _enter_chase() -> void:
	force_chase()
	# 呼叫包抄:半径内的守卫一并进入追捕状态
	for g in get_tree().get_nodes_in_group("guards"):
		if g != self and g.global_position.distance_to(global_position) < CALL_RANGE:
			g.force_chase()


func take_damage(dmg: int, from_dir: Vector2) -> void:
	if hp <= 0:
		return
	hp -= dmg
	global_position += from_dir * 4.0  # 轻微击退
	modulate = Color(3, 3, 3)  # 受击白闪
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(1, 1, 1), 0.12)
	_enter_chase()  # 挨打立刻警觉并叫人
	if hp <= 0:
		_die()


func _die() -> void:
	EventBus.guard_died.emit(self)
	# 40% 掉武器:反杀的核心奖励(设计文档 §3.7:反杀守卫掉落)
	if randf() < 0.4:
		var p := Pickup.new()
		p.setup(Weapon.SMG if randf() < 0.5 else Weapon.SHOTGUN)
		get_tree().current_scene.add_child(p)
		p.global_position = global_position
	# 尸体占位:一块停留几秒后淡出的色块
	var corpse := ColorRect.new()
	corpse.size = Vector2(14, 8)
	corpse.color = Color("6e3a2c")
	get_tree().current_scene.add_child(corpse)
	corpse.global_position = global_position - Vector2(7, 4)
	var tw := corpse.create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(corpse, "modulate:a", 0.0, 1.0)
	tw.tween_callback(corpse.queue_free)
	queue_free()
