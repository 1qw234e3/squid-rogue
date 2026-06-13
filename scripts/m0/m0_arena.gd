extends Node2D
## M0 手感切片场景(设计文档 §11):BSP 迷宫 + 双摇杆射击 + 守卫追捕。
## 验收问题只有一个:打枪爽不爽?
## 地图绘制用 _draw、碰撞用合并后的矩形,不引入 TileMap——M0 不需要。

const BspMaze := preload("res://scripts/m0/bsp_maze.gd")
const PlayerScript := preload("res://scripts/actors/player.gd")
const GuardScript := preload("res://scripts/actors/guard.gd")
const PickupScript := preload("res://scripts/combat/pickup.gd")
const WeaponScript := preload("res://scripts/combat/weapon.gd")
const ShakeCamera := preload("res://scripts/m0/shake_camera.gd")
const Loot := preload("res://scripts/combat/loot.gd")
const Door := preload("res://scripts/m0/door.gd")

const CELL := 16
const GRID_W := 72
const GRID_H := 44
const GUARD_CAP := 9         # 场上守卫常驻数(死了会增援补满)
const GUARD_CAP_FINALE := 13
const RESPAWN_MIN := 6.0     # 增援间隔
const RESPAWN_MAX := 10.0
const TIME_LIMIT := 180.0    # 限时找到出口,超时即淘汰

const COLOR_FLOOR := Color("39424f")
const COLOR_WALL := Color("171c24")
# 地标房间的地面染色(设计议题 1.4):给玩家可指认的"那个房间"
const ROOM_TINTS: Array = [Color("46394f"), Color("394f41"), Color("4f3a39"), Color("3a4a52"), Color("4d4a35")]

var rng := RandomNumberGenerator.new()
var run_seed := 0
var grid: Array = []
var rooms: Array = []
var astar := AStarGrid2D.new()
var player: CharacterBody2D
var guard_cap := GUARD_CAP
var kills := 0
var respawn_times: Array = []  # 待增援的时间点(elapsed 时间轴)
var elapsed := 0.0
var time_left := TIME_LIMIT
var warned := false
var finished := false
var room_tints := {}  # 房间下标 -> 地标染色

var hud_hp: Label
var hud_weapon: Label
var hud_guards: Label
var hud_msg: Label
var hud_time: Label


func _ready() -> void:
	rng.randomize()
	run_seed = rng.seed  # 种子打在 HUD 上,方便复现某一张图
	var maze: Dictionary = BspMaze.generate(GRID_W, GRID_H, rng)
	grid = maze.grid
	rooms = maze.rooms
	_pick_landmark_rooms()
	_setup_astar()
	_build_walls()
	_spawn_doors()
	_setup_darkness()
	_setup_hud()  # HUD 先建好,玩家 _ready 里发的初始信号才能被接到
	_spawn_player()
	_setup_camera()
	_spawn_exit()
	_spawn_guards()
	_spawn_weapon_crates()
	_spawn_loot()
	EventBus.guard_died.connect(_on_guard_died)
	EventBus.player_died.connect(_on_player_died)
	EventBus.exit_reached.connect(_on_exit_reached)
	queue_redraw()


func _process(delta: float) -> void:
	if finished:
		return
	elapsed += delta
	time_left -= delta
	hud_time.text = "%d" % maxi(ceili(time_left), 0)
	hud_time.modulate = Color("ff7070") if time_left < 30.0 else Color.WHITE
	if time_left < 30.0 and not warned:
		warned = true
		Game.play_sfx("alert", 0.8)
		Game.float_text(player.global_position + Vector2(0, -30), "剩余 30 秒,找到绿灯!", Color("ff8080"))
	if time_left <= 0.0:
		_on_timeout()
		return
	# 守卫增援:到点且场上没满编,就在远离玩家的房间刷一个
	for t in respawn_times.duplicate():
		if elapsed >= t:
			respawn_times.erase(t)
			if get_tree().get_nodes_in_group("guards").size() < guard_cap:
				_spawn_one_guard(true)
				Game.float_text(player.global_position + Vector2(0, -30), "守卫增援抵达", Color("ff8080"))


func _unhandled_input(event: InputEvent) -> void:
	# R 重开仅限独立调试;一局之中不允许重打本轮
	if event.is_action_pressed("restart") and not Run.active:
		get_tree().reload_current_scene()


# ---------- 地图与寻路 ----------

func _draw() -> void:
	draw_rect(Rect2(0, 0, GRID_W * CELL, GRID_H * CELL), COLOR_WALL)
	for y in GRID_H:
		for x in GRID_W:
			if grid[y][x] == 0:
				draw_rect(Rect2(x * CELL, y * CELL, CELL, CELL), COLOR_FLOOR)
	# 地标房间整块盖一层染色(房间必为矩形地面,直接盖最省事)
	for idx in room_tints:
		var r: Rect2i = rooms[idx]
		draw_rect(Rect2(r.position.x * CELL, r.position.y * CELL, r.size.x * CELL, r.size.y * CELL), room_tints[idx])


func _pick_landmark_rooms() -> void:
	# 从中段房间里挑最多 3 个染色(避开出生房和出口房,它们已有自己的身份)
	var candidates: Array = []
	for i in range(1, rooms.size() - 1):
		candidates.append(i)
	for c in ROOM_TINTS.size():
		if candidates.is_empty():
			break
		var pick := rng.randi_range(0, candidates.size() - 1)
		room_tints[candidates[pick]] = ROOM_TINTS[c]
		candidates.remove_at(pick)


func _setup_astar() -> void:
	astar.region = Rect2i(0, 0, GRID_W, GRID_H)
	astar.cell_size = Vector2(CELL, CELL)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for y in GRID_H:
		for x in GRID_W:
			if grid[y][x] == 1:
				astar.set_point_solid(Vector2i(x, y), true)


## 守卫追捕用的寻路接口:返回一串世界坐标路点
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


func _build_walls() -> void:
	# 每行连续的墙合并成一个矩形碰撞体:几百个格子降到几十个 shape
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
				# 同一段墙再挂一个遮光体:光被墙挡住,拐角后面真的看不见
				var occluder := LightOccluder2D.new()
				var poly := OccluderPolygon2D.new()
				var half := rect.size / 2.0
				poly.polygon = PackedVector2Array([
					Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
					Vector2(half.x, half.y), Vector2(-half.x, half.y),
				])
				occluder.occluder = poly
				occluder.position = shape.position
				body.add_child(occluder)
			else:
				x += 1


# ---------- 生成 ----------

func _random_floor_in_room(room: Rect2i) -> Vector2:
	var c := Vector2i(
		rng.randi_range(room.position.x, room.position.x + room.size.x - 1),
		rng.randi_range(room.position.y, room.position.y + room.size.y - 1)
	)
	return _cell_center(c)


## 全场压黑:环境漆黑,地图只在玩家手电的光里呈现(§3.2 夜战变体常驻本关)
func _setup_darkness() -> void:
	var dark := CanvasModulate.new()
	dark.color = Color(0.13, 0.14, 0.18)
	add_child(dark)


func _spawn_player() -> void:
	player = PlayerScript.new()
	add_child(player)
	player.global_position = _cell_center((rooms[0] as Rect2i).get_center())
	# 手电:跟着玩家走的光源,被墙遮挡出真实视线
	var torch := PointLight2D.new()
	torch.texture = Game.radial_light_texture()
	torch.texture_scale = 1.5  # 光圈半径约 190px(12 格)
	torch.energy = 1.4
	torch.shadow_enabled = true
	player.add_child(torch)


func _setup_camera() -> void:
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


func _spawn_exit() -> void:
	# 出口放在最后一个房间:离出生点拓扑距离最远
	var room: Rect2i = rooms[rooms.size() - 1]
	var exit := Area2D.new()
	exit.collision_layer = 0
	exit.collision_mask = 2  # 只检测玩家
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(CELL, CELL)
	shape.shape = rect
	exit.add_child(shape)
	var mark := ColorRect.new()
	mark.size = Vector2(CELL - 2, CELL - 2)
	mark.position = -mark.size / 2.0
	mark.color = Color("4caf6e")
	exit.add_child(mark)
	# 出口常亮一盏绿灯:黑暗里远远的一点绿光,就是导航
	var beacon := PointLight2D.new()
	beacon.texture = Game.radial_light_texture()
	beacon.texture_scale = 0.7
	beacon.energy = 1.1
	beacon.color = Color("6bdF8e")
	beacon.shadow_enabled = true
	exit.add_child(beacon)
	add_child(exit)
	exit.global_position = _cell_center(room.get_center())
	exit.body_entered.connect(func(_body: Node) -> void: EventBus.exit_reached.emit())


func _spawn_guards() -> void:
	guard_cap = GUARD_CAP_FINALE if Run.is_finale() else GUARD_CAP
	for i in mini(rooms.size() - 1, guard_cap):
		_spawn_one_guard(false)
	_refresh_guard_label()


## far_from_player:增援不会刷脸上,挑 180px 以外的房间
func _spawn_one_guard(far_from_player: bool) -> void:
	var room: Rect2i = rooms[rng.randi_range(1, rooms.size() - 1)]
	if far_from_player:
		for attempt in 12:
			room = rooms[rng.randi_range(1, rooms.size() - 1)]
			if _cell_center(room.get_center()).distance_to(player.global_position) > 180.0:
				break
	var g := GuardScript.new()
	g.setup(self, player, _random_floor_in_room(room), _random_floor_in_room(room))
	add_child(g)
	g.global_position = _random_floor_in_room(room)


## 给每个房间装一道门:扫描房间四边的走廊开口,挑一个装上
func _spawn_doors() -> void:
	for room_v in rooms:
		var room: Rect2i = room_v
		var gaps := _collect_gaps(room)
		var candidates: Array = []
		for g in gaps:
			if g.cells.size() <= 3:  # 太宽的开口不是门洞,是房间相连
				candidates.append(g)
		if candidates.is_empty():
			continue
		var gap: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
		var first: Vector2i = gap.cells[0]
		var last: Vector2i = gap.cells[gap.cells.size() - 1]
		var center := (_cell_center(first) + _cell_center(last)) / 2.0
		var span: int = gap.cells.size() * CELL
		var door := Door.new()
		door.setup(Vector2(span, 6) if gap.horizontal else Vector2(6, span), self, gap.cells)
		add_child(door)
		door.global_position = center
		set_door_cells_solid(gap.cells, true)  # 门初始关闭,寻路即刻认账


## 门开关时同步 A*:关着的门对守卫的寻路来说就是墙
func set_door_cells_solid(cells: Array, solid: bool) -> void:
	for c in cells:
		astar.set_point_solid(c, solid)


## 找出房间边界外一圈上的地面开口(走廊入口),按连续段分组
func _collect_gaps(room: Rect2i) -> Array:
	var gaps: Array = []
	var edges := [
		{"horizontal": true, "y": room.position.y - 1},
		{"horizontal": true, "y": room.position.y + room.size.y},
	]
	for e in edges:
		var run: Array = []
		for x in range(room.position.x, room.position.x + room.size.x):
			if e.y >= 0 and e.y < GRID_H and grid[e.y][x] == 0:
				run.append(Vector2i(x, e.y))
			elif not run.is_empty():
				gaps.append({"cells": run.duplicate(), "horizontal": true})
				run.clear()
		if not run.is_empty():
			gaps.append({"cells": run, "horizontal": true})
	var vedges := [room.position.x - 1, room.position.x + room.size.x]
	for vx in vedges:
		var run: Array = []
		for y in range(room.position.y, room.position.y + room.size.y):
			if vx >= 0 and vx < GRID_W and grid[y][vx] == 0:
				run.append(Vector2i(vx, y))
			elif not run.is_empty():
				gaps.append({"cells": run.duplicate(), "horizontal": false})
				run.clear()
		if not run.is_empty():
			gaps.append({"cells": run, "horizontal": false})
	return gaps


func _spawn_weapon_crates() -> void:
	# 每局从武器池随机预放 3 把(去重),验证"捡随机武器"的循环;
	# 近战必出 1 把——无声击杀流不该看运气脸色
	# 地图变大了:近战保底 1 把 + 三把枪全放,但散得更开
	var melee_pool: Array = [WeaponScript.KNIFE, WeaponScript.AXE]
	var picks: Array = [melee_pool[rng.randi_range(0, melee_pool.size() - 1)],
		WeaponScript.SHOTGUN, WeaponScript.SMG, WeaponScript.RIFLE]
	for stats in picks:
		if rooms.size() < 3:
			break
		var room: Rect2i = rooms[rng.randi_range(1, rooms.size() - 2)]
		var p := PickupScript.new()
		p.setup(stats)
		add_child(p)
		p.global_position = _random_floor_in_room(room)


func _spawn_loot() -> void:
	# 迷宫里的稀有物:这关挨枪子,食物(回血)和钱对半分
	for i in 6:
		if rooms.size() < 3:
			break
		var room: Rect2i = rooms[rng.randi_range(1, rooms.size() - 2)]
		var loot := Loot.new()
		if rng.randf() < 0.5:
			loot.kind = "food"
		else:
			loot.kind = "money"
			loot.amount = rng.randi_range(20, 40)
		add_child(loot)
		loot.global_position = _random_floor_in_room(room)


# ---------- HUD ----------

func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud_hp = _make_label(layer, Vector2(8, 6), 10)
	hud_weapon = _make_label(layer, Vector2(8, 20), 10)
	hud_guards = _make_label(layer, Vector2(8, 34), 10)
	hud_time = _make_label(layer, Vector2(0, 8), 14)
	hud_time.size = Vector2(640, 20)
	hud_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hint := _make_label(layer, Vector2(8, 344), 8)
	hint.text = "WASD 移动 · 鼠标瞄准 · 左键射击 · 空格翻滚 · E 拾取 · R 重开    种子 %d" % run_seed
	hint.modulate.a = 0.7
	hud_msg = _make_label(layer, Vector2(0, 150), 16)
	hud_msg.size = Vector2(640, 60)
	hud_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_msg.visible = false
	EventBus.player_hp_changed.connect(_on_hp_changed)
	EventBus.weapon_equipped.connect(_on_weapon_equipped)


func _make_label(parent: Node, pos: Vector2, font_size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_override("font", Game.ui_font())  # 默认字体不含中文
	l.add_theme_font_size_override("font_size", font_size)
	parent.add_child(l)
	return l


func _on_hp_changed(hp: int, max_hp: int) -> void:
	hud_hp.text = "HP " + "#".repeat(maxi(hp, 0)) + "-".repeat(max_hp - maxi(hp, 0))


func _on_weapon_equipped(stats: Dictionary) -> void:
	hud_weapon.text = "武器 " + str(stats.get("name", "?"))


func _refresh_guard_label() -> void:
	hud_guards.text = "击杀 %d · 守卫增援不断" % kills


func _on_guard_died(_guard: Node) -> void:
	kills += 1
	if not finished:
		respawn_times.append(elapsed + rng.randf_range(RESPAWN_MIN, RESPAWN_MAX))
	_refresh_guard_label()


func _on_timeout() -> void:
	finished = true
	Game.play_sfx("shoot_heavy", 0.7)
	hud_msg.text = "超时 —— 广播宣布你出局" if Run.active else "超时 —— 按 R 重开"
	hud_msg.visible = true
	if Run.active:
		await get_tree().create_timer(1.8).timeout
		Run.minigame_finished(false)


func _on_player_died() -> void:
	finished = true
	hud_msg.text = "你被淘汰了" if Run.active else "你被淘汰了 —— 按 R 重开"
	hud_msg.visible = true
	if Run.active:
		await get_tree().create_timer(1.8).timeout
		Run.minigame_finished(false)


func _on_exit_reached() -> void:
	if finished:
		return
	finished = true
	var stats_line := "逃出迷宫!用时 %.1f 秒,击杀守卫 %d" % [elapsed, kills]
	hud_msg.text = stats_line if Run.active else stats_line + " —— 按 R 再来一局"
	hud_msg.visible = true
	if Run.active:
		await get_tree().create_timer(1.8).timeout
		Run.minigame_finished(true)
