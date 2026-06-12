extends Node2D
## 木头人(设计文档 §3.1):横向场地,左起点右终点,巨型娃娃在终点处。
## 绿灯自由移动 → 转头预警音 0.4s → 红灯扫描:速度超阈值累计 0.2s 触发
## 激光预瞄 0.5s,窗口内进掩体可免,否则狙杀。掩体可被打碎(HP3)。
## 手感核心:玩家自带 0.3s 惯性滑行——预判松杆,而不是看见红灯才松。

const PlayerScript := preload("res://scripts/actors/player.gd")
const ShakeCamera := preload("res://scripts/m0/shake_camera.gd")
const Contestant := preload("res://scripts/actors/contestant.gd")
const Loot := preload("res://scripts/combat/loot.gd")

const CELL := 16
const FIELD_W := 60
const FIELD_H := 20
const TIME_LIMIT := 120.0   # 总限时,逼迫怂包前进(§3.1)
const MOVE_EPS := 12.0      # 红灯期间的速度阈值(px/s)
const VIOLATE_TIME := 0.2   # 超阈值累计多久触发预瞄
const LASER_TIME := 0.5     # 预瞄到开枪的窗口
const COVER_COUNT := 12
const COVER_HP := 3
const NPC_COUNT := 14
const LOOT_COUNT := 4

enum Light { GREEN, WARN, RED }

var light := Light.GREEN
var light_timer := 2.0
var time_in_light := 0.0   # 进入当前灯态多久了(NPC 反应判定用)
var contestants: Array = []
var kill_queue: Array = []  # {npc, t}:已被判违规、等待处决的 NPC
var guard_posts: Array = [] # 场边守卫哨位坐标,处决枪从最近哨位打出
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
var hud_cast: Label
var cast_timer := 0.0


func _ready() -> void:
	rng.randomize()
	finish_x = (FIELD_W - 4) * CELL
	_build_field()
	_spawn_player()
	_spawn_covers()
	_build_doll()
	_build_guard_posts()
	_spawn_contestants()
	_spawn_loot()
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
	time_in_light += delta
	hud_time.text = "%d" % maxi(ceili(time_left), 0)
	_process_kill_queue(delta)
	if cast_timer > 0.0:
		cast_timer -= delta
		if cast_timer <= 0.0:
			hud_cast.modulate.a = 0.0
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
		laser.points = PackedVector2Array([_nearest_post(player.global_position), player.global_position])
		if laser_timer < 0.0:
			_resolve_shot()
	if player.global_position.x >= finish_x and not finished:
		_win()


# ---------- 灯与判定 ----------

func is_green() -> bool:
	return light == Light.GREEN


func _set_light(s: Light) -> void:
	light = s
	violate = 0.0
	time_in_light = 0.0
	if s == Light.RED:
		_roll_npc_violations()
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
	# 处决枪从最近的场边守卫哨位打出:被掩体挡住 → 掩体挨这一枪;否则玩家挨
	var post := _nearest_post(player.global_position)
	var params := PhysicsRayQueryParameters2D.create(post, player.global_position, 1)
	var hit := get_world_2d().direct_space_state.intersect_ray(params)
	Game.play_sfx("shoot_heavy", 0.9)
	Game.shake(3.0)
	_tracer(post, player.global_position)
	if hit.is_empty():
		_snipe_player()
		if player.hp <= 0:
			_eliminate("红灯期间移动")
	else:
		_damage_cover(hit.collider)


# ---------- 参赛者 NPC 与处决 ----------

## 红灯落下的瞬间,给每个活着的 NPC 掷反应延迟;滑出太多的进处决队列
func _roll_npc_violations() -> void:
	for npc in contestants:
		if npc.dead or npc.done:
			continue
		npc.reaction = maxf(0.0, (1.0 - npc.courage) * rng.randf_range(0.0, 0.4))
		if npc.reaction > 0.15 and rng.randf() < 0.5:
			kill_queue.append({"npc": npc, "t": npc.reaction + 0.35})


func _process_kill_queue(delta: float) -> void:
	for entry in kill_queue.duplicate():
		entry.t -= delta
		if entry.t > 0.0:
			continue
		kill_queue.erase(entry)
		var npc: CharacterBody2D = entry.npc
		if npc.dead or npc.done:
			continue
		var post := _nearest_post(npc.global_position)
		# 躲到掩体后的 NPC 也能逃过一劫——规则对所有人一致,玩家看得懂
		var params := PhysicsRayQueryParameters2D.create(post, npc.global_position, 1)
		if not get_world_2d().direct_space_state.intersect_ray(params).is_empty():
			continue
		_tracer(post, npc.global_position)
		Game.play_sfx_at("shoot_heavy", npc.global_position, 0.9)
		npc.die()
		_broadcast("第 %02d 号参赛者,淘汰。" % npc.number)
		# 死者遗物:35% 掉一小袋配给券,绿灯里去舔包是风险换钱
		if rng.randf() < 0.35:
			_drop_loot("money", rng.randi_range(10, 30), npc.global_position + Vector2(8, 0))


func _nearest_post(pos: Vector2) -> Vector2:
	var best: Vector2 = guard_posts[0]
	for p in guard_posts:
		if p.distance_to(pos) < best.distance_to(pos):
			best = p
	return best


## 处决弹道:一条瞬间画满、快速淡出的亮线
func _tracer(from: Vector2, to: Vector2) -> void:
	var line := Line2D.new()
	line.width = 1.5
	line.default_color = Color(1.0, 0.9, 0.7, 0.9)
	line.points = PackedVector2Array([from, to])
	add_child(line)
	var tw := line.create_tween()
	tw.tween_property(line, "modulate:a", 0.0, 0.15)
	tw.tween_callback(line.queue_free)


func _broadcast(text: String) -> void:
	hud_cast.text = "【广播】" + text
	hud_cast.modulate.a = 1.0
	cast_timer = 3.0


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


func _build_guard_posts() -> void:
	# 场边四个守卫哨位:上下各两个,处决枪从这里打出——"谁在执法"看得见
	var xs := [FIELD_W * 0.35, FIELD_W * 0.7]
	for x in xs:
		guard_posts.append(Vector2(x * CELL, CELL * 1.5))
		guard_posts.append(Vector2(x * CELL, (FIELD_H - 1.5) * CELL))
	for p in guard_posts:
		var g := ColorRect.new()
		g.size = Vector2(12, 18)
		g.position = p - Vector2(6, 9)
		g.color = Color("b3543d")  # 铜盔守卫占位色
		add_child(g)


func _spawn_contestants() -> void:
	for i in NPC_COUNT:
		var npc := Contestant.new()
		npc.setup(self, i + 1 if i + 1 < 23 else i + 2, rng.randf())  # 23 号留给玩家
		add_child(npc)
		npc.global_position = Vector2(
			rng.randf_range(1.5, 3.0) * CELL,
			rng.randf_range(2.0, FIELD_H - 2.0) * CELL
		)
		contestants.append(npc)


func _spawn_loot() -> void:
	# 稀有物以钱和食物为主:60% 钱袋 / 25% 稀有钱箱 / 15% 食物
	for i in LOOT_COUNT:
		var roll := rng.randf()
		var pos := Vector2(rng.randf_range(10.0, FIELD_W - 10.0), rng.randf_range(3.0, FIELD_H - 3.0)) * CELL
		if roll < 0.6:
			_drop_loot("money", rng.randi_range(20, 50), pos)
		elif roll < 0.85:
			_drop_loot("cache", rng.randi_range(120, 180), pos)
		else:
			_drop_loot("food", 0, pos)


func _drop_loot(kind: String, amount: int, pos: Vector2) -> void:
	var loot := Loot.new()
	loot.kind = kind
	loot.amount = amount
	add_child(loot)
	loot.global_position = pos


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
	hud_cast = Game.make_label(layer, Vector2(0, 310), 9)
	hud_cast.size = Vector2(640, 16)
	hud_cast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_cast.modulate.a = 0.0
