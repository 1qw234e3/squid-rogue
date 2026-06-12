extends CharacterBody2D
## 抢椅子关的 AI 参赛者:音乐期游走,抢椅期冲向最近空椅,
## 清场期惊慌寻找补刀椅;坐上椅子即安全。可被玩家推开(椅子会被抢走)。

var arena: Node2D
var number := 0
var hp := 2
var dead := false
var seated_chair := -1
var speed := 80.0
var wander_target := Vector2.ZERO
var wander_t := 0.0
var stagger := 0.0
var push_vel := Vector2.ZERO
var tint := Color.WHITE
var body_rect: ColorRect


func setup(arena_: Node2D, number_: int) -> void:
	arena = arena_
	number = number_
	speed = 70.0 + randf() * 35.0
	tint = Color.from_hsv(randf(), 0.3, 0.6)


func _ready() -> void:
	add_to_group("chairs_npcs")
	collision_layer = 2  # 与玩家同层:清场弹幕(mask 1|2)打得到
	collision_mask = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(10, 12)
	shape.shape = rect
	add_child(shape)
	body_rect = ColorRect.new()
	body_rect.size = Vector2(10, 16)
	body_rect.position = Vector2(-5, -10)
	body_rect.color = tint
	add_child(body_rect)


func _physics_process(delta: float) -> void:
	if dead:
		velocity = Vector2.ZERO
		return
	stagger -= delta
	push_vel = push_vel.move_toward(Vector2.ZERO, 600.0 * delta)
	if seated_chair >= 0:
		velocity = push_vel  # 坐着不动,除非被推
		move_and_slide()
		return
	var mv := Vector2.ZERO
	if stagger <= 0.0:
		if arena.seeking_chairs():
			var idx: int = arena.nearest_free_chair(global_position)
			if idx >= 0:
				mv = (arena.chair_pos(idx) - global_position).normalized() * speed * 1.25
			else:
				# 没椅子可抢:绕场惊慌打转,等补刀椅或等死
				mv = (global_position - arena.arena_center()).orthogonal().normalized() * speed
		else:
			_wander(delta)
			mv = (wander_target - global_position).normalized() * speed * 0.6
	velocity = mv + push_vel
	move_and_slide()


func _wander(delta: float) -> void:
	wander_t -= delta
	if wander_t <= 0.0 or global_position.distance_to(wander_target) < 12.0:
		wander_target = arena.random_point()
		wander_t = randf_range(0.8, 2.0)


## 被推开:打断锁定、让出椅子
func shove(dir: Vector2) -> void:
	push_vel = dir * 200.0
	stagger = 0.5
	if seated_chair >= 0:
		arena.unclaim_entity(self)


func take_damage(dmg: int, dir: Vector2) -> void:
	if dead or seated_chair >= 0:
		return  # 坐着 = 安全区
	hp -= dmg
	push_vel = dir * 80.0
	modulate = Color(3, 3, 3)
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(1, 1, 1), 0.12)
	if hp <= 0:
		die()


func die() -> void:
	dead = true
	collision_layer = 0
	body_rect.color = Color("5e2c2c")
	body_rect.size = Vector2(16, 8)
	body_rect.position = Vector2(-8, -4)
	arena.report_npc_death(number)
