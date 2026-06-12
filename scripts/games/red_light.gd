extends Node2D
## 木头人(设计文档 §3.1):横向场地,左起点右终点,巨型娃娃在终点处。
## 绿灯自由移动 → 转头预警音 0.4s → 红灯扫描:速度超阈值累计 0.2s 触发
## 激光预瞄 0.5s,窗口内进掩体可免,否则狙杀。掩体可被打碎(HP3)。
## 手感核心:玩家自带 0.3s 惯性滑行——预判松杆,而不是看见红灯才松。

const PlayerScript := preload("res://scripts/actors/player.gd")
const ShakeCamera := preload("res://scripts/m0/shake_camera.gd")

const CELL := 16
const FIELD_W := 60
const FIELD_H := 20
const TIME_LIMIT := 120.0   # 总限时,逼迫怂包前进(§3.1)
const MOVE_EPS := 12.0      # 红灯期间的速度阈值(px/s)
const VIOLATE_TIME := 0.2   # 超阈值累计多久触发预瞄
const LASER_TIME := 0.5     # 预瞄到开枪的窗口
const COVER_COUNT := 12
const COVER_HP := 3

enum Light { GREEN, WARN, RED }

var light := Light.GREEN
var light_timer := 2.0
var time_left := TIME_LIMIT
var violate := 0.0
var laser_timer := -1.0
var finished := false
var rng := RandomNumberGenerator.new()
var player: CharacterBody2D
var covers: Array = []  # {body, visual, hp}
var doll_eye_pos := Vector2.ZERO
var doll_eye: ColorRect
var finish_x := 0.0
var laser: Line2D
var tint: CanvasModulate
var hud_light: Label
var hud_time: Label
var hud_msg: Label


func _ready() -> void:
	rng.randomize()
	finish_x = (FIELD_W - 4) * CELL
	_build_field()
	_spawn_player()
	_spawn_covers()
	_build_doll()
	_setup_hud()
	tint = CanvasModulate.new()
	add_child(tint)
	laser = Line2D.new()
	laser.width = 1.5
	laser.default_color = Color(1.0, 0.2, 0.2, 0.6)
	laser.visible = false
	add_child(laser)
	_set_light(Light.GREEN)
	queue_redraw()


func _process(delta: float) -> void:
	if finished:
		return
	time_left -= delta
	hud_time.text = "%d" % maxi(ceili(time_left), 0)
	if time_left <= 0.0:
		_snipe_player()  # 超时 = 直接清场
		_eliminate("超时")
		return
	light_timer -= delta
	match light:
		Light.GREEN:
			if light_timer <= 0.0:
				_set_light(Light.WARN)
		Light.WARN:
			if light_timer <= 0.0:
				_set_light(Light.RED)
		Light.RED:
			_check_violation(delta)
			if light_timer <= 0.0:
				_set_light(Light.GREEN)
	if laser_timer >= 0.0:
		laser_timer -= delta
		laser.points = PackedVector2Array([doll_eye_pos, player.global_position])
		if laser_timer < 0.0:
			_resolve_shot()
	if player.global_position.x >= finish_x and not finished:
		_win()


# ---------- 灯与判定 ----------

func _set_light(s: Light) -> void:
	light = s
	violate = 0.0
	match s:
		Light.GREEN:
			light_timer = rng.randf_range(2.5, 5.0)
			doll_eye.color = Color("4caf6e")
			tint.color = Color.WHITE
			hud_light.text = "绿 灯"
			hud_light.modulate = Color("7fe0a0")
		Light.WARN:
			light_timer = 0.4
			doll_eye.color = Color("ffd86b")
			hud_light.text = "· · ·"
			hud_light.modulate = Color("ffd86b")
			Game.play_sfx("alert", 1.0)  # 转头预警音:听到这个就该松杆了
		Light.RED:
			light_timer = rng.randf_range(1.5, 3.0)
			doll_eye.color = Color("ff4040")
			tint.color = Color(1.0, 0.86, 0.86)
			hud_light.text = "红 灯"
			hud_light.modulate = Color("ff7070")


func _check_violation(delta: float) -> void:
	if laser_timer >= 0.0:
		return  # 已被锁定,等判决
	if player.velocity.length() > MOVE_EPS:
		violate += delta
	else:
		violate = maxf(violate - delta * 2.0, 0.0)
	if violate >= VIOLATE_TIME:
		violate = 0.0
		laser_timer = LASER_TIME
		laser.visible = true
		Game.play_sfx("alert", 1.5)


func _resolve_shot() -> void:
	laser.visible = false
	laser_timer = -1.0
	# 从娃娃眼睛到玩家打射线:被掩体挡住 → 掩体挨这一枪;否则玩家挨
	var params := PhysicsRayQueryParameters2D.create(doll_eye_pos, player.global_position, 1)
	var hit := get_world_2d().direct_space_state.intersect_ray(params)
	Game.play_sfx("shoot_heavy", 0.9)
	Game.shake(3.0)
	if hit.is_empty():
		_snipe_player()
		if player.hp <= 0:
			_eliminate("红灯期间移动")
	else:
		_damage_cover(hit.collider)


func _snipe_player() -> void:
	player.take_damage(999, Vector2.DOWN)  # 翻滚无敌帧恰好顶上 = 极限闪避,留给玩家


func _damage_cover(body: Node) -> void:
	for c in covers:
		if c.body == body:
			c.hp -= 1
			c.visual.modulate = Color(3, 3, 3)
			var tw: Tween = c.visual.create_tween()
			tw.tween_property(c.visual, "modulate", Color.WHITE, 0.12)
			Game.play_sfx("hit", 0.8)
			if c.hp <= 0:
				c.body.queue_free()
				c.visual.queue_free()
				covers.erase(c)
			return


# ---------- 结束 ----------

func _win() -> void:
	finished = true
	hud_msg.text = "通过!剩余 %d 秒" % ceili(time_left)
	hud_msg.visible = true
	await get_tree().create_timer(1.8).timeout
	Run.minigame_finished(true)


func _eliminate(reason: String) -> void:
	finished = true
	hud_msg.text = "淘汰:" + reason
	hud_msg.visible = true
	await get_tree().create_timer(1.8).timeout
	Run.minigame_finished(false)


# ---------- 搭场景 ----------

func _draw() -> void:
	draw_rect(Rect2(0, 0, FIELD_W * CELL, FIELD_H * CELL), Color("171c24"))
	draw_rect(Rect2(CELL, CELL, (FIELD_W - 2) * CELL, (FIELD_H - 2) * CELL), Color("4a4438"))  # 沙土场地
	draw_rect(Rect2(finish_x, CELL, 2 * CELL, (FIELD_H - 2) * CELL), Color("2f5e41"))  # 终点区
	draw_rect(Rect2(3 * CELL, CELL, 4, (FIELD_H - 2) * CELL), Color(1, 1, 1, 0.25))  # 起跑线


func _build_field() -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	add_child(body)
	var walls := [
		Rect2(0, 0, FIELD_W * CELL, CELL),
		Rect2(0, (FIELD_H - 1) * CELL, FIELD_W * CELL, CELL),
		Rect2(0, 0, CELL, FIELD_H * CELL),
		Rect2((FIELD_W - 1) * CELL, 0, CELL, FIELD_H * CELL),
	]
	for w in walls:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = w.size
		shape.shape = rect
		shape.position = w.position + w.size / 2.0
		body.add_child(shape)


func _spawn_player() -> void:
	player = PlayerScript.new()
	add_child(player)
	player.global_position = Vector2(2 * CELL, FIELD_H * CELL / 2.0)
	player.combat_enabled = false
	player.use_inertia = true  # 0.3s 滑行:本关手感核心
	var cam: Camera2D = ShakeCamera.new()
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = FIELD_W * CELL
	cam.limit_bottom = FIELD_H * CELL
	player.add_child(cam)
	cam.make_current()
	Game.camera = cam


func _spawn_covers() -> void:
	for i in COVER_COUNT:
		var pos := Vector2(rng.randi_range(8, FIELD_W - 8), rng.randi_range(3, FIELD_H - 3)) * CELL
		var body := StaticBody2D.new()
		body.collision_layer = 1
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(14, 14)
		shape.shape = rect
		body.add_child(shape)
		add_child(body)
		body.global_position = pos
		var visual := ColorRect.new()
		visual.size = Vector2(14, 14)
		visual.position = pos - visual.size / 2.0
		visual.color = Color("7a5c36")  # 木箱
		add_child(visual)
		covers.append({"body": body, "visual": visual, "hp": COVER_HP})


func _build_doll() -> void:
	var doll_pos := Vector2((FIELD_W - 2) * CELL, FIELD_H * CELL / 2.0)
	var body := ColorRect.new()
	body.size = Vector2(24, 56)
	body.position = doll_pos - Vector2(12, 28)
	body.color = Color("5c2e3d")
	add_child(body)
	doll_eye = ColorRect.new()
	doll_eye.size = Vector2(12, 12)
	doll_eye.position = doll_pos - Vector2(6, 22)
	add_child(doll_eye)
	doll_eye_pos = doll_pos - Vector2(0, 16)


func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud_light = Game.make_label(layer, Vector2(0, 8), 16)
	hud_light.size = Vector2(640, 24)
	hud_light.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_time = Game.make_label(layer, Vector2(8, 6), 12)
	var hint := Game.make_label(layer, Vector2(8, 344), 8, "听到预警音就松杆——你有 0.3 秒滑行 · 木箱可挡狙击但会被打碎")
	hint.modulate.a = 0.7
	hud_msg = Game.make_label(layer, Vector2(0, 150), 16)
	hud_msg.size = Vector2(640, 40)
	hud_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_msg.visible = false
