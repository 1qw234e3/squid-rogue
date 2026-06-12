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
const ExitArrow := preload("res://scripts/m0/exit_arrow.gd")

const CELL := 16
const GRID_W := 44
const GRID_H := 28
const MAX_GUARDS := 6

const COLOR_FLOOR := Color("39424f")
const COLOR_WALL := Color("171c24")
# 地标房间的地面染色(设计议题 1.4):紫/绿/红,给玩家可指认的"那个房间"
const ROOM_TINTS: Array = [Color("46394f"), Color("394f41"), Color("4f3a39")]

var rng := RandomNumberGenerator.new()
var run_seed := 0
var grid: Array = []
var rooms: Array = []
var astar := AStarGrid2D.new()
var player: CharacterBody2D
var guards_total := 0
var guards_left := 0
var elapsed := 0.0
var finished := false
var room_tints := {}  # 房间下标 -> 地标染色

var hud_hp: Label
var hud_weapon: Label
var hud_guards: Label
var hud_msg: Label


func _ready() -> void:
	rng.randomize()
	run_seed = rng.seed  # 种子打在 HUD 上,方便复现某一张图
	var maze: Dictionary = BspMaze.generate(GRID_W, GRID_H, rng)
	grid = maze.grid
	rooms = maze.rooms
	_pick_landmark_rooms()
	_setup_astar()
	_build_walls()
	_setup_hud()  # HUD 先建好,玩家 _ready 里发的初始信号才能被接到
	_spawn_player()
	_setup_camera()
	_spawn_exit()
	_spawn_guards()
	_spawn_weapon_crates()
	EventBus.guard_died.connect(_on_guard_died)
	EventBus.player_died.connect(_on_player_died)
	EventBus.exit_reached.connect(_on_exit_reached)
	queue_redraw()


func _process(delta: float) -> void:
	if not finished:
		elapsed += delta


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
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
			else:
				x += 1


# ---------- 生成 ----------

func _random_floor_in_room(room: Rect2i) -> Vector2:
	var c := Vector2i(
		rng.randi_range(room.position.x, room.position.x + room.size.x - 1),
		rng.randi_range(room.position.y, room.position.y + room.size.y - 1)
	)
	return _cell_center(c)


func _spawn_player() -> void:
	player = PlayerScript.new()
	add_child(player)
	player.global_position = _cell_center((rooms[0] as Rect2i).get_center())


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
	add_child(exit)
	exit.global_position = _cell_center(room.get_center())
	exit.body_entered.connect(func(_body: Node) -> void: EventBus.exit_reached.emit())
	# 出口方向箭头挂在玩家身上(设计议题 1.4:没有它找出口全靠瞎逛)
	var arrow := ExitArrow.new()
	arrow.target_pos = exit.global_position
	player.add_child(arrow)


func _spawn_guards() -> void:
	var count := mini(rooms.size() - 1, MAX_GUARDS)
	for i in count:
		var room: Rect2i = rooms[1 + (i % (rooms.size() - 1))]
		var g := GuardScript.new()
		g.setup(self, player, _random_floor_in_room(room), _random_floor_in_room(room))
		add_child(g)
		g.global_position = _random_floor_in_room(room)
	guards_total = count
	guards_left = count
	_refresh_guard_label()


func _spawn_weapon_crates() -> void:
	# 迷宫里预放两把强力武器,验证"捡随机武器"的循环
	var pool := [WeaponScript.SHOTGUN, WeaponScript.SMG]
	for i in pool.size():
		if rooms.size() < 3:
			break
		var room: Rect2i = rooms[rng.randi_range(1, rooms.size() - 2)]
		var p := PickupScript.new()
		p.setup(pool[i])
		add_child(p)
		p.global_position = _random_floor_in_room(room)


# ---------- HUD ----------

func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud_hp = _make_label(layer, Vector2(8, 6), 10)
	hud_weapon = _make_label(layer, Vector2(8, 20), 10)
	hud_guards = _make_label(layer, Vector2(8, 34), 10)
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
	hud_guards.text = "守卫 %d/%d" % [guards_left, guards_total]


func _on_guard_died(_guard: Node) -> void:
	guards_left -= 1
	_refresh_guard_label()


func _on_player_died() -> void:
	finished = true
	hud_msg.text = "你被淘汰了 —— 按 R 重开"
	hud_msg.visible = true


func _on_exit_reached() -> void:
	if finished:
		return
	finished = true
	hud_msg.text = "逃出迷宫!用时 %.1f 秒,击杀守卫 %d/%d —— 按 R 再来一局" % [elapsed, guards_total - guards_left, guards_total]
	hud_msg.visible = true
