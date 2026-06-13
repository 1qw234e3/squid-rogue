extends Node2D
## 撤离模式 V0 灰盒(图纸全篇):保护的体验是"贪婪决策"——
## 手里已经有货、面前还有更肥的一间房,撤还是进。
## 梯子型固定手工图:双主路 + 横向连接;三段纵深 白→蓝→金;
## 近撤离在 1 区侧室,远撤离在 3 区尽头紧邻金货房(激励是纯位置性的)。

const PlayerScript := preload("res://scripts/actors/player.gd")
const GuardScript := preload("res://scripts/actors/guard.gd")
const ShakeCamera := preload("res://scripts/m0/shake_camera.gd")
const LootItem := preload("res://scripts/extraction/loot_item.gd")
const ExtractionZone := preload("res://scripts/extraction/extraction_zone.gd")
const ThreatMeter := preload("res://scripts/extraction/threat_meter.gd")
const SpawnDirector := preload("res://scripts/extraction/spawn_director.gd")

const CELL := 16
const GRID_W := 120
const GRID_H := 44

# 固定手工地图:全部地面矩形(格子坐标)。改图就改这张表
const FLOORS := [
	Rect2i(4, 8, 112, 3),    # 上主路
	Rect2i(4, 32, 112, 3),   # 下主路
	Rect2i(18, 11, 2, 21),   # 梯1
	Rect2i(44, 11, 2, 21),   # 梯2
	Rect2i(60, 11, 1, 21),   # 窄捷径(1.5 身位:滚不出花样,逼你用走的)
	Rect2i(74, 11, 2, 21),   # 梯3
	Rect2i(100, 11, 2, 21),  # 梯4
	Rect2i(2, 18, 10, 8),    # 出生区(西)
	Rect2i(6, 11, 2, 7),     # 出生→上路
	Rect2i(6, 26, 2, 6),     # 出生→下路
	Rect2i(12, 14, 6, 5),    # 近撤离侧室(1区,不与入口重合)
	Rect2i(14, 11, 1, 3),    # 侧室门缝
	Rect2i(24, 2, 10, 5),    # 1区白货房(上)
	Rect2i(28, 7, 2, 1),
	Rect2i(22, 37, 10, 5),   # 1区白货房(下)
	Rect2i(26, 35, 2, 2),
	Rect2i(52, 2, 12, 5),    # 2区蓝货房(上)
	Rect2i(57, 7, 2, 1),
	Rect2i(54, 37, 12, 5),   # 2区蓝货房(下)
	Rect2i(59, 35, 2, 2),
	Rect2i(56, 18, 12, 8),   # 2区中庭
	Rect2i(61, 11, 2, 7),
	Rect2i(61, 26, 2, 6),
	Rect2i(104, 17, 10, 10), # 3区金货房
	Rect2i(107, 11, 2, 6),   # 金货房北门(主入口)
	Rect2i(102, 21, 2, 1),   # 西墙 1 格视线缝:门口看得见金货,才有贪婪决策
	Rect2i(112, 4, 6, 4),    # 远撤离间:上主路东尽头,紧邻金货房
]

# 点位池(图纸 §二):随局随机实刷,地图知识的来源
const WHITE_POOL := [Vector2i(27, 4), Vector2i(31, 4), Vector2i(25, 39), Vector2i(29, 39), Vector2i(15, 9), Vector2i(38, 33)]
const BLUE_POOL := [Vector2i(56, 4), Vector2i(60, 4), Vector2i(58, 40), Vector2i(63, 39), Vector2i(61, 22)]
const GOLD_POOL := [Vector2i(106, 19), Vector2i(110, 22), Vector2i(106, 25)]

const GUARD_SPAWNS := [  # 底数 9:1区2 / 2区4 / 3区3,深处更密
	Vector2i(20, 9), Vector2i(30, 33),
	Vector2i(50, 9), Vector2i(63, 33), Vector2i(75, 20), Vector2i(45, 20),
	Vector2i(98, 9), Vector2i(106, 21), Vector2i(95, 33),
]

const COLOR_FLOOR := Color("3d4450")
const COLOR_WALL := Color("171c24")

var rng := RandomNumberGenerator.new()
var grid: Array = []
var astar := AStarGrid2D.new()
var player: CharacterBody2D
var threat: Node
var director: Node
var finished := false
# —— RunStats(图纸 §五):排行榜原料兼测试数据 ——
var carried := 0
var items: Array = []   # 本局已拾取的物品名
var kills := 0
var shots := 0
var spotted := 0
var elapsed := 0.0

var hud_carried: Label
var hud_threat: Label
var hud_hp: Label
var hud_msg: Label
var screen_layer: CanvasLayer
var pulse_rect: ColorRect


func _ready() -> void:
	rng.randomize()
	_build_grid()
	_setup_astar()
	_build_walls()
	_spawn_player()
	_spawn_guards()
	_spawn_loot()
	_spawn_zones()
	threat = ThreatMeter.new()
	add_child(threat)
	threat.tier_changed.connect(_on_tier_changed)
	threat.sustain_spawn.connect(func() -> void: director.spawn_squad(int(Tune.t3_squad)))
	director = SpawnDirector.new()
	director.arena = self
	director.player = player
	add_child(director)
	_setup_hud()
	EventBus.player_died.connect(_on_player_died)
	EventBus.guard_died.connect(func(_g: Node) -> void: kills += 1)
	EventBus.guard_alerted.connect(func() -> void: spotted += 1)
	EventBus.noise_emitted.connect(func(_p: Vector2, _r: float, group: String) -> void:
		if group != "guards":
			shots += 1
	)
	_check_connectivity()
	queue_redraw()


func _process(delta: float) -> void:
	if finished:
		return
	elapsed += delta
	hud_carried.text = "携带  %d 分" % carried
	hud_threat.text = "威胁 " + ("▲".repeat(threat.tier) if threat.tier > 0 else "—")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()
	if finished and event.is_action_pressed("ui_accept"):
		get_tree().change_scene_to_file("res://scenes/run/Lobby.tscn")


# ---------- 威胁与增援 ----------

func _on_tier_changed(tier: int) -> void:
	# 升档瞬间:全图警报 + 屏幕边缘脉冲(隐藏数值,过渡极响)
	Game.play_sfx("alert", 0.5)
	Game.shake(2.0)
	pulse_rect.modulate.a = 0.3
	var tw := pulse_rect.create_tween()
	tw.tween_property(pulse_rect, "modulate:a", 0.0, 0.5)
	var squad := 0
	match tier:
		1: squad = int(Tune.t1_squad)
		2: squad = int(Tune.t2_squad)
		3: squad = int(Tune.t3_squad)
	director.spawn_squad(squad)
	Game.float_text(player.global_position + Vector2(0, -30), "威胁升级 T%d" % tier, Color("ff8080"))


# ---------- 拾取与撤离 ----------

func _on_loot_collected(value: int, tier: String) -> void:
	carried += value
	items.append(LootItem.TIERS[tier].label)


func _on_extracted(zone_name: String) -> void:
	if finished:
		return
	finished = true
	_save_stats("extracted", zone_name)
	_show_screen("撤 离 成 功",
		"结算得分:%d\n%s\n\n用时 %d 秒 · 击杀 %d · 开枪 %d · 被发现 %d · 威胁 T%d" % [
			carried, "(空手撤离)" if carried == 0 else "带出:" + ", ".join(items),
			int(elapsed), kills, shots, spotted, threat.tier,
		], Color("7fe0a0"))


func _on_player_died() -> void:
	if finished:
		return
	finished = true
	_save_stats("died", "")
	# 图纸 §五:死亡画面必须把刺痛做清楚——丢了什么,一件件列出来
	_show_screen("阵 亡",
		"本局丢失:%d 分\n%s\n\n用时 %d 秒 · 击杀 %d · 开枪 %d · 被发现 %d · 威胁 T%d" % [
			carried, "(两手空空,倒也无牵无挂)" if carried == 0 else "物品清单:" + ", ".join(items),
			int(elapsed), kills, shots, spotted, threat.tier,
		], Color("ff6b6b"))


func _show_screen(title_text: String, body_text: String, color: Color) -> void:
	var bg := ColorRect.new()
	bg.size = Vector2(640, 360)
	bg.color = Color(0.04, 0.05, 0.07, 0.88)
	screen_layer.add_child(bg)
	var title := Game.make_label(screen_layer, Vector2(0, 90), 24, title_text)
	title.modulate = color
	var body := Game.make_label(screen_layer, Vector2(0, 150), 10, body_text)
	var hint := Game.make_label(screen_layer, Vector2(0, 320), 9, "Enter 回大厅 · R 再来一局")
	hint.modulate.a = 0.6
	for l in [title, body, hint]:
		l.size = Vector2(640, 100)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## 每局落盘(图纸 §五):JSONL 追加,既是排行榜原料也是测试数据
func _save_stats(result: String, zone: String) -> void:
	var f := FileAccess.open("user://extraction_stats.jsonl", FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open("user://extraction_stats.jsonl", FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify({
		"result": result, "zone": zone, "score": carried, "kills": kills,
		"shots": shots, "spotted": spotted, "threat_tier": threat.tier,
		"duration": snappedf(elapsed, 0.1), "items": items,
	}))
	f.close()


# ---------- 生成 ----------

func _spawn_loot() -> void:
	_seed_pool(WHITE_POOL, 4, "white")
	_seed_pool(BLUE_POOL, 3, "blue")
	_seed_pool(GOLD_POOL, 2, "gold")


func _seed_pool(pool: Array, count: int, tier: String) -> void:
	var candidates := pool.duplicate()
	for i in count:
		if candidates.is_empty():
			return
		var pick: Vector2i = candidates[rng.randi_range(0, candidates.size() - 1)]
		candidates.erase(pick)
		var item := LootItem.new()
		item.tier = tier
		add_child(item)
		item.global_position = _cell_center(pick)
		item.collected.connect(_on_loot_collected)


func _spawn_zones() -> void:
	var near := ExtractionZone.new()
	near.zone_name = "近点(1区侧室)"
	add_child(near)
	near.global_position = _cell_center(Vector2i(14, 16))
	near.extracted.connect(_on_extracted)
	var far := ExtractionZone.new()
	far.zone_name = "远点(3区尽头)"
	add_child(far)
	far.global_position = _cell_center(Vector2i(114, 6))
	far.extracted.connect(_on_extracted)


func _spawn_player() -> void:
	player = PlayerScript.new()
	add_child(player)
	player.global_position = _cell_center(Vector2i(6, 21))
	var cam: Camera2D = ShakeCamera.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = GRID_W * CELL
	cam.limit_bottom = GRID_H * CELL
	player.add_child(cam)
	cam.make_current()
	Game.camera = cam


func _spawn_guards() -> void:
	for c in GUARD_SPAWNS:
		var g := GuardScript.new()
		g.setup(self, player, random_floor_near(c, 5), random_floor_near(c, 5))
		g.vision_range = 96.0  # 亮图标准视野
		g.track_range = 192.0
		add_child(g)
		g.global_position = _cell_center(c)


# ---------- 地图构建(与守卫猎杀同构,但全固定)----------

func _build_grid() -> void:
	for y in GRID_H:
		var row: Array = []
		row.resize(GRID_W)
		row.fill(1)
		grid.append(row)
	for r in FLOORS:
		for y in range(r.position.y, r.position.y + r.size.y):
			for x in range(r.position.x, r.position.x + r.size.x):
				grid[y][x] = 0


func _setup_astar() -> void:
	astar.region = Rect2i(0, 0, GRID_W, GRID_H)
	astar.cell_size = Vector2(CELL, CELL)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for y in GRID_H:
		for x in GRID_W:
			if grid[y][x] == 1:
				astar.set_point_solid(Vector2i(x, y), true)


func find_path(from_world: Vector2, to_world: Vector2) -> PackedVector2Array:
	var from := _world_to_cell(from_world)
	var to := _world_to_cell(to_world)
	var result := PackedVector2Array()
	if astar.is_point_solid(from) or astar.is_point_solid(to):
		return result
	for c in astar.get_id_path(from, to):
		result.append(_cell_center(c))
	return result


func _world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(p.x / CELL), 0, GRID_W - 1), clampi(int(p.y / CELL), 0, GRID_H - 1))


func _cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * CELL + CELL / 2.0, c.y * CELL + CELL / 2.0)


func random_floor_position() -> Vector2:
	for attempt in 200:
		var c := Vector2i(rng.randi_range(1, GRID_W - 2), rng.randi_range(1, GRID_H - 2))
		if grid[c.y][c.x] == 0:
			return _cell_center(c)
	return _cell_center(Vector2i(6, 21))


func random_floor_near(cell: Vector2i, radius: int) -> Vector2:
	for attempt in 40:
		var c := cell + Vector2i(rng.randi_range(-radius, radius), rng.randi_range(-radius, radius))
		if c.x > 0 and c.y > 0 and c.x < GRID_W - 1 and c.y < GRID_H - 1 and grid[c.y][c.x] == 0:
			return _cell_center(c)
	return _cell_center(cell)


func _build_walls() -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for y in GRID_H:
		var x := 0
		while x < GRID_W:
			if grid[y][x] == 1:
				var start := x
				while x < GRID_W and grid[y][x] == 1:
					x += 1
				var shape := CollisionShape2D.new()
				var rect := RectangleShape2D.new()
				rect.size = Vector2((x - start) * CELL, CELL)
				shape.shape = rect
				shape.position = Vector2((start + x) * CELL / 2.0, y * CELL + CELL / 2.0)
				body.add_child(shape)
			else:
				x += 1


func _draw() -> void:
	draw_rect(Rect2(0, 0, GRID_W * CELL, GRID_H * CELL), COLOR_WALL)
	for y in GRID_H:
		for x in GRID_W:
			if grid[y][x] == 0:
				var col := COLOR_FLOOR
				if x >= 100:
					col = Color("46414f")   # 3区:地面色温区分纵深
				elif x >= 44:
					col = Color("40464e")   # 2区
				draw_rect(Rect2(x * CELL, y * CELL, CELL, CELL), col)


## 地图改动后的保险丝:出生点到三处关键位置必须连通
func _check_connectivity() -> void:
	for target in [Vector2i(14, 16), Vector2i(114, 6), Vector2i(106, 21)]:
		if find_path(player.global_position, _cell_center(target)).is_empty():
			push_error("撤离图断路:出生点 → %s 不可达" % target)


# ---------- HUD ----------

func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud_hp = Game.make_label(layer, Vector2(8, 6), 10)
	hud_carried = Game.make_label(layer, Vector2(0, 6), 14)
	hud_carried.size = Vector2(640, 20)
	hud_carried.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_carried.modulate = Color("ffd86b")  # 揣着多少要显眼:丢失感来自看得见
	hud_threat = Game.make_label(layer, Vector2(560, 6), 10)
	var hint := Game.make_label(layer, Vector2(8, 344), 8, "搜刮:白货碰拾 · 蓝/金按住E · 圈内站5秒撤离 · 枪声会引来增援 · R 重开")
	hint.modulate.a = 0.7
	hud_msg = Game.make_label(layer, Vector2(0, 150), 16)
	hud_msg.size = Vector2(640, 40)
	hud_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_msg.visible = false
	EventBus.player_hp_changed.connect(func(hp: int, max_hp: int) -> void:
		hud_hp.text = "HP " + "#".repeat(maxi(hp, 0)) + "-".repeat(max_hp - maxi(hp, 0))
	)
	EventBus.player_hp_changed.emit(player.hp, player.MAX_HP)
	# 威胁升档的屏幕边缘脉冲
	pulse_rect = ColorRect.new()
	pulse_rect.size = Vector2(640, 360)
	pulse_rect.color = Color(1.0, 0.2, 0.2)
	pulse_rect.modulate.a = 0.0
	pulse_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(pulse_rect)
	screen_layer = CanvasLayer.new()
	screen_layer.layer = 50
	add_child(screen_layer)
