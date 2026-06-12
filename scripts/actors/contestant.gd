extends CharacterBody2D
## 木头人关的 AI 参赛者(设计文档 §3.1):按勇气参数决定激进度。
## 勇气高 → 绿灯冲刺、红灯反应及时;勇气低 → 怂,赖在原地直到限时逼迫。
## 反应慢的会在红灯里滑出违规、被守卫狙杀——他们的死是给玩家的规则教学。

var number := 0
var courage := 0.5
var speed := 60.0
var reaction := 0.1     # 本轮红灯的反应延迟,场景每次红灯重掷
var dead := false
var done := false
var arena: Node2D
var lane_y := 0.0
var body_rect: ColorRect


func setup(arena_: Node2D, number_: int, courage_: float) -> void:
	arena = arena_
	number = number_
	courage = courage_
	speed = 45.0 + courage * 45.0


func _ready() -> void:
	add_to_group("contestants")
	collision_layer = 0
	collision_mask = 1  # 只撞墙和掩体,不挡玩家也不互相挤
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(10, 12)
	shape.shape = rect
	add_child(shape)
	body_rect = ColorRect.new()
	body_rect.size = Vector2(10, 16)
	body_rect.position = Vector2(-5, -10)
	body_rect.color = Color.from_hsv(randf(), 0.25, 0.55)  # 灰扑扑的随机色:背景板,不抢玩家视觉
	add_child(body_rect)
	lane_y = global_position.y


func _physics_process(delta: float) -> void:
	if dead or done:
		velocity = Vector2.ZERO
		return
	if arena.is_green():
		# 怂包(勇气<0.35)赖着不动,直到限时开始逼人(§3.1:总限时逼迫全员)
		if courage < 0.35 and arena.time_left > 45.0:
			velocity = Vector2.ZERO
		else:
			var target_y: float = lane_y + sin(Time.get_ticks_msec() / 700.0 + number) * 10.0
			velocity = Vector2(speed, clampf(target_y - global_position.y, -20.0, 20.0))
	else:
		# 预警/红灯:reaction 秒内还在慢吞吞地减速——这段滑行就是死因
		if arena.time_in_light < reaction:
			velocity = velocity.move_toward(Vector2.ZERO, 150.0 * delta)
		else:
			velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
	move_and_slide()
	if global_position.x >= arena.finish_x:
		done = true
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.6)  # 到达终点,退场


func die() -> void:
	dead = true
	velocity = Vector2.ZERO
	body_rect.color = Color("5e2c2c")
	body_rect.size = Vector2(16, 8)  # 倒下
	body_rect.position = Vector2(-8, -4)
