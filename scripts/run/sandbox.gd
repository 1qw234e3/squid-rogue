extends Node2D
## 沙盒阶段(阶段A占位版):一间屋子 + 倒计时 + 搜刮箱 + 情报屋 + 集合点。
## 完整海岛(宿舍/食堂/黑市/通风管)在阶段C替换进来,这里先把
## "松弛-决策-被广播打断"的节奏立住。

const PlayerScript := preload("res://scripts/actors/player.gd")
const ShakeCamera := preload("res://scripts/m0/shake_camera.gd")

const CELL := 16
const ROOM_W := 36
const ROOM_H := 18
const COUNTDOWN := 45.0
const INTEL_PRICE := 50

var player: CharacterBody2D
var time_left := COUNTDOWN
var done := false
var crates: Array = []
var kiosk_pos := Vector2.ZERO
var pad_rect := Rect2()
var hud_info: Label
var hud_time: Label
var hud_cast: Label
var cast_timer := 0.0


func _ready() -> void:
	_build_room()
	player = PlayerScript.new()
	add_child(player)
	player.global_position = Vector2(ROOM_W * CELL * 0.2, ROOM_H * CELL * 0.5)
	player.combat_enabled = false  # 沙盒收枪(设计文档 §6:掏枪=敌对宣告,阶段C再做)
	var cam: Camera2D = ShakeCamera.new()
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = ROOM_W * CELL
	cam.limit_bottom = ROOM_H * CELL
	player.add_child(cam)
	cam.make_current()
	Game.camera = cam
	_spawn_props()
	_setup_hud()
	_broadcast("自由活动时间。搜刮、打探,然后到集合点等待广播。")


func _process(delta: float) -> void:
	if done:
		return
	time_left -= delta
	hud_time.text = "%d" % maxi(ceili(time_left), 0)
	hud_info.text = "存活 %d        奖金池 %d        配给券 %d" % [Run.survivors, Run.prize_pool, Run.tickets]
	if cast_timer > 0.0:
		cast_timer -= delta
		if cast_timer <= 0.0:
			hud_cast.modulate.a = 0.0
	# 站上集合点 = 提前出发(把等待的控制权还给玩家)
	if pad_rect.has_point(player.global_position) and time_left > 3.0:
		time_left = 3.0
		_broadcast("已确认集合,传送即将开始。")
	if time_left <= 0.0:
		done = true
		Run.go_briefing()
	if Input.is_action_just_pressed("interact"):
		_interact()


# ---------- 房间与道具 ----------

func _build_room() -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	add_child(body)
	# 四面墙,厚一格
	var walls := [
		Rect2(0, 0, ROOM_W * CELL, CELL),
		Rect2(0, (ROOM_H - 1) * CELL, ROOM_W * CELL, CELL),
		Rect2(0, 0, CELL, ROOM_H * CELL),
		Rect2((ROOM_W - 1) * CELL, 0, CELL, ROOM_H * CELL),
	]
	for w in walls:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = w.size
		shape.shape = rect
		shape.position = w.position + w.size / 2.0
		body.add_child(shape)


func _draw() -> void:
	draw_rect(Rect2(0, 0, ROOM_W * CELL, ROOM_H * CELL), Color("171c24"))
	draw_rect(Rect2(CELL, CELL, (ROOM_W - 2) * CELL, (ROOM_H - 2) * CELL), Color("3a4150"))
	draw_rect(pad_rect, Color("2f5e41"))  # 集合点


func _spawn_props() -> void:
	# 搜刮箱 ×3
	var spots := [Vector2(7, 4), Vector2(28, 5), Vector2(14, 13)]
	for s in spots:
		var pos: Vector2 = s * CELL
		var visual := ColorRect.new()
		visual.size = Vector2(12, 10)
		visual.position = pos - visual.size / 2.0
		visual.color = Color("8a6a3d")
		add_child(visual)
		crates.append({"pos": pos, "amount": randi_range(20, 40), "opened": false, "visual": visual})
	# 情报屋
	kiosk_pos = Vector2(30, 13) * CELL
	var kiosk := ColorRect.new()
	kiosk.size = Vector2(16, 12)
	kiosk.position = kiosk_pos - kiosk.size / 2.0
	kiosk.color = Color("3d6a8a")
	add_child(kiosk)
	var tag := Game.make_label(self, kiosk_pos + Vector2(-24, -26), 8, "情报屋 E·%d券" % INTEL_PRICE)
	tag.modulate.a = 0.8
	# 集合点(右墙中段)
	pad_rect = Rect2((ROOM_W - 5) * CELL, (ROOM_H / 2.0 - 1.5) * CELL, 3 * CELL, 3 * CELL)
	var pad_tag := Game.make_label(self, pad_rect.position + Vector2(2, -14), 8, "集合点")
	pad_tag.modulate.a = 0.8
	queue_redraw()


func _interact() -> void:
	for c in crates:
		if not c.opened and c.pos.distance_to(player.global_position) < 22.0:
			c.opened = true
			c.visual.color = Color("4a3a22")
			Run.tickets += c.amount
			Game.play_sfx("hit", 1.5)
			_broadcast("搜刮到 %d 配给券。" % c.amount)
			return
	if kiosk_pos.distance_to(player.global_position) < 28.0:
		if Run.intel_known:
			_broadcast("你已经知道了:下一场是【%s】。" % Run.current_game().name)
		elif Run.tickets >= INTEL_PRICE:
			Run.tickets -= INTEL_PRICE
			Run.intel_known = true
			Game.play_sfx("alert", 1.2)
			_broadcast("情报:下一场游戏是【%s】。" % Run.current_game().name)
		else:
			_broadcast("配给券不足(需要 %d)。" % INTEL_PRICE)


# ---------- HUD ----------

func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud_info = Game.make_label(layer, Vector2(8, 6), 10)
	hud_time = Game.make_label(layer, Vector2(0, 22), 18)
	hud_time.size = Vector2(640, 24)
	hud_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hint := Game.make_label(layer, Vector2(8, 344), 8, "WASD 移动 · E 互动 · 倒计时归零强制传送")
	hint.modulate.a = 0.7
	hud_cast = Game.make_label(layer, Vector2(0, 310), 9)
	hud_cast.size = Vector2(640, 16)
	hud_cast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _broadcast(text: String) -> void:
	hud_cast.text = "【广播】" + text
	hud_cast.modulate.a = 1.0
	cast_timer = 3.5
