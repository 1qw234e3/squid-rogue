extends CharacterBody2D
## 守卫(设计议题 1.1/1.2/1.3 的载体):
## 巡逻 → 视锥发现(120°/6格)→ 呼叫包抄 → 追捕 → 跟丢转搜索 → 回巡逻。
## - 追捕只追"最后目击点",不开全图透视——玩家断视线就有逃脱窗口
## - 开枪前 0.3s 红色预瞄线,方向锁定,翻滚/横移可躲(与木头人预瞄同一设计语言)
## - 听到噪音(枪声等)会赶去查看声源

const Weapon := preload("res://scripts/combat/weapon.gd")
const Pickup := preload("res://scripts/combat/pickup.gd")

enum State { PATROL, CHASE, SEARCH }

const PATROL_SPEED := 45.0
const CHASE_SPEED := 80.0
const SEARCH_SPEED := 60.0
const VISION_HALF_ANGLE := PI / 3.0  # 120° 视锥的一半
const FIRE_RANGE := 110.0
const CALL_RANGE := 150.0            # 呼叫包抄的广播半径
const TELEGRAPH_TIME := 0.3          # 开枪前摇
const LOSE_SIGHT_TIME := 5.0         # 跟丢多久放弃追捕转搜索
const SEARCH_TIME := 8.0             # 到达搜索点后原地张望多久
const SEARCH_SPIN := 1.8             # 张望时视锥旋转速度(弧度/秒)

const CONE_PATROL := Color(1.0, 0.85, 0.3, 0.10)   # 黄:平静
const CONE_SEARCH := Color(1.0, 0.6, 0.2, 0.12)    # 橙:起疑
const CONE_CHASE := Color(1.0, 0.25, 0.2, 0.14)    # 红:警觉

var state := State.PATROL
var hp := 3
## 视野距离:黑暗关里被压到很短——守卫在黑暗里同样看不远,
## 他们随身的小灯就是他们的视野范围,玩家远远看到光团就知道躲哪
var vision_range := 60.0
var track_range := 120.0  # 追捕中保持目击的最大距离
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
var last_seen := Vector2.ZERO    # 最后目击点:追捕的真正目标
var lose_timer := 0.0            # 持续看不见目标的累计时间
var search_pos := Vector2.ZERO
var search_timer := 0.0
var search_arrived := false
var telegraph_timer := -1.0      # >=0 表示正在前摇
var telegraph_dir := Vector2.RIGHT
var weapon: Node2D
var cone: Polygon2D
var aim_line: Line2D
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
	# 视锥可视化:颜色即状态(黄/橙/红),玩家不用看血条就知道自己暴露没有
	cone = Polygon2D.new()
	cone.polygon = _cone_points()
	cone.color = CONE_PATROL
	add_child(cone)
	# 开枪预瞄线:前摇期间显示,方向已锁定
	aim_line = Line2D.new()
	aim_line.width = 1.5
	aim_line.default_color = Color(1.0, 0.2, 0.2, 0.5)
	aim_line.visible = false
	add_child(aim_line)
	body_rect = ColorRect.new()
	body_rect.size = Vector2(12, 18)
	body_rect.position = Vector2(-6, -11)
	body_rect.color = Color("b3543d")  # 铜盔守卫占位色(深海主题,设计文档 §9)
	add_child(body_rect)
	weapon = Weapon.new()
	weapon.setup(Weapon.GUARD_RIFLE, "guards", 1 | 2)
	add_child(weapon)
	# 随身小灯:照亮的范围 ≈ 他的视野,黑暗里这就是"危险的形状"
	var lamp := PointLight2D.new()
	lamp.texture = Game.radial_light_texture()
	lamp.texture_scale = vision_range / 110.0
	lamp.energy = 0.9
	lamp.color = Color(1.0, 0.85, 0.65)
	lamp.shadow_enabled = true
	add_child(lamp)
	EventBus.noise_emitted.connect(_on_noise)


func _cone_points() -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2.ZERO])
	for i in 9:
		var ang := lerpf(-VISION_HALF_ANGLE, VISION_HALF_ANGLE, i / 8.0)
		pts.append(Vector2.from_angle(ang) * vision_range)
	return pts


func _physics_process(delta: float) -> void:
	if hp <= 0:
		return
	match state:
		State.PATROL:
			_patrol(delta)
		State.CHASE:
			_chase(delta)
		State.SEARCH:
			_search(delta)
	move_and_slide()
	if velocity.length() > 1.0:
		facing = velocity.normalized()
	cone.rotation = facing.angle()


# ---------- 三态行为 ----------

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
		_spot_and_call()


func _chase(delta: float) -> void:
	if not is_instance_valid(target) or not target.visible:
		_to_patrol()  # 玩家已死,收队
		return
	# 前摇进行中:站定、维持锁定方向,倒计时归零就开火(断视线也照打,打空很正常)
	if telegraph_timer >= 0.0:
		telegraph_timer -= delta
		velocity = Vector2.ZERO
		facing = telegraph_dir
		aim_line.points = PackedVector2Array([Vector2.ZERO, telegraph_dir * FIRE_RANGE])
		if telegraph_timer <= 0.0:
			_cancel_telegraph()
			weapon.set_aim(telegraph_dir)
			weapon.try_fire()
		return
	var dist := global_position.distance_to(target.global_position)
	var sees := dist < track_range and _los_clear(target.global_position)
	if sees:
		last_seen = target.global_position  # 持续刷新最后目击点
		lose_timer = 0.0
	else:
		lose_timer += delta
		if lose_timer > LOSE_SIGHT_TIME:
			_begin_search(last_seen)  # 跟丢太久,转搜索
			return
	if sees and dist < FIRE_RANGE:
		# 进入射程:开始前摇;等冷却时保持压迫距离
		if weapon.cooldown <= 0.0:
			telegraph_timer = TELEGRAPH_TIME
			telegraph_dir = (target.global_position - global_position).normalized()
			facing = telegraph_dir
			aim_line.visible = true
			velocity = Vector2.ZERO
		else:
			velocity = Vector2.ZERO if dist < 70.0 else (target.global_position - global_position).normalized() * CHASE_SPEED * 0.5
	else:
		# 看不见或太远:奔向最后目击点;到了还没人就地转搜索
		if _move_along_path(last_seen, CHASE_SPEED, delta) and not sees:
			_begin_search(last_seen)


func _search(delta: float) -> void:
	if _can_see_target():
		_spot_and_call()  # 搜到了!重新追捕并叫人
		return
	if not search_arrived:
		search_arrived = _move_along_path(search_pos, SEARCH_SPEED, delta)
	else:
		# 原地缓慢旋转张望:视锥扫一圈,扫到就是真的被找到了
		velocity = Vector2.ZERO
		facing = facing.rotated(SEARCH_SPIN * delta)
		search_timer -= delta
		if search_timer <= 0.0:
			_to_patrol()


# ---------- 寻路与感知 ----------

## 沿 A* 路径走向 goal,到达返回 true
func _move_along_path(goal: Vector2, speed: float, delta: float) -> bool:
	if global_position.distance_to(goal) < 8.0:
		velocity = Vector2.ZERO
		return true
	repath_timer -= delta
	if repath_timer <= 0.0 or path_index >= path.size():
		path = arena.find_path(global_position, goal)
		path_index = 0
		repath_timer = 0.4
	if path_index < path.size():
		var wp := path[path_index]
		if global_position.distance_to(wp) < 6.0:
			path_index += 1
			velocity = Vector2.ZERO
		else:
			velocity = (wp - global_position).normalized() * speed
	else:
		velocity = (goal - global_position).normalized() * speed
	return false


func _can_see_target() -> bool:
	if not is_instance_valid(target) or not target.visible:
		return false
	var to := target.global_position - global_position
	if to.length() > vision_range:
		return false
	if absf(facing.angle_to(to)) > VISION_HALF_ANGLE:
		return false
	return _los_clear(target.global_position)


## 视线检测:只对墙(layer 1)打射线,没挡住就算看得见
func _los_clear(point: Vector2) -> bool:
	var params := PhysicsRayQueryParameters2D.create(global_position, point, 1)
	return get_world_2d().direct_space_state.intersect_ray(params).is_empty()


# ---------- 状态切换 ----------

## 进入追捕(也是"呼叫包抄"让别的守卫调用的公共入口)
## 猎人模式(撤离模式的增援):不巡逻,直奔指定位置,到点搜索后原地转巡逻
func hunt(pos: Vector2) -> void:
	patrol_a = pos + Vector2(24, 0)
	patrol_b = pos - Vector2(24, 0)
	_begin_search(pos)


func force_chase() -> void:
	if hp <= 0 or state == State.CHASE:
		return
	state = State.CHASE
	lose_timer = 0.0
	_cancel_telegraph()
	if is_instance_valid(target):
		last_seen = target.global_position
	cone.color = CONE_CHASE
	EventBus.guard_alerted.emit()
	Game.play_sfx_at("alert", global_position)


## 亲眼发现:自己进入追捕,并广播叫附近守卫包抄
func _spot_and_call() -> void:
	force_chase()
	for g in get_tree().get_nodes_in_group("guards"):
		if g != self and g.global_position.distance_to(global_position) < CALL_RANGE:
			g.force_chase()


func _begin_search(pos: Vector2) -> void:
	state = State.SEARCH
	search_pos = pos
	search_timer = SEARCH_TIME
	search_arrived = false
	_cancel_telegraph()
	cone.color = CONE_SEARCH


func _to_patrol() -> void:
	state = State.PATROL
	_cancel_telegraph()
	cone.color = CONE_PATROL


func _cancel_telegraph() -> void:
	telegraph_timer = -1.0
	if aim_line:
		aim_line.visible = false


## 噪音响应(设计议题 1.3),分级感应:
## - 追捕中:每声枪响刷新"最后目击点"——边逃边开枪 = 一路报坐标
## - 近距离(噪音半径 55% 内):听声辨人,直接锁定开枪者进入追捕
## - 远距离:只知道大概方位,赶去查看声源
func _on_noise(pos: Vector2, radius: float, source_group: String) -> void:
	if hp <= 0 or source_group == "guards":
		return
	var dist := global_position.distance_to(pos)
	if dist > radius:
		return
	if state == State.CHASE:
		last_seen = pos
		lose_timer = 0.0
		return
	if dist <= radius * 0.55:
		force_chase()
	else:
		_begin_search(pos)


# ---------- 受击与死亡 ----------

func take_damage(dmg: int, from_dir: Vector2) -> void:
	if hp <= 0:
		return
	hp -= dmg
	global_position += from_dir * 4.0 * Tune.knockback_scale  # 击退,力度走调参面板
	modulate = Color(3, 3, 3)  # 受击白闪
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(1, 1, 1), 0.12)
	_spot_and_call()  # 挨打立刻警觉并叫人(知道大致来向)
	if hp <= 0:
		_die()


func _die() -> void:
	EventBus.guard_died.emit(self)
	Game.play_sfx_at("kill", global_position)
	# 40% 掉武器:反杀的核心奖励(设计文档 §3.7)
	if randf() < 0.4:
		var drop_pool: Array = [Weapon.SMG, Weapon.SHOTGUN, Weapon.RIFLE]
		var p := Pickup.new()
		p.setup(drop_pool[randi() % drop_pool.size()])
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
