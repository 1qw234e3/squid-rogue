extends RefCounted
## BSP 迷宫生成(设计文档 §3.7:守卫猎杀是全游戏唯一的程序化地图)。
## generate() 返回 {"grid": 行数组(1=墙 0=地), "rooms": Array[Rect2i]}。
## 走廊宽 2 格,保证追逐战里能侧身躲子弹。

const MIN_LEAF := 7
const CORRIDOR_WIDTH := 2


static func generate(w: int, h: int, rng: RandomNumberGenerator) -> Dictionary:
	var grid: Array = []
	for y in h:
		var row: Array = []
		row.resize(w)
		row.fill(1)
		grid.append(row)
	var rooms: Array = []
	_split(Rect2i(1, 1, w - 2, h - 2), rng, rooms)
	for r in rooms:
		_carve_rect(grid, r)
	# 按生成顺序把相邻房间串起来,保证全图连通
	for i in rooms.size() - 1:
		_carve_corridor(grid, w, h, rooms[i].get_center(), rooms[i + 1].get_center(), rng)
	# 再加两条随机环路,避免纯树状结构全是死路(被追进死路 = 必死,体验太差)
	for i in 2:
		if rooms.size() > 3:
			var a: Rect2i = rooms[rng.randi_range(0, rooms.size() - 1)]
			var b: Rect2i = rooms[rng.randi_range(0, rooms.size() - 1)]
			_carve_corridor(grid, w, h, a.get_center(), b.get_center(), rng)
	return {"grid": grid, "rooms": rooms}


static func _split(area: Rect2i, rng: RandomNumberGenerator, rooms: Array) -> void:
	var can_split_x := area.size.x > MIN_LEAF * 2
	var can_split_y := area.size.y > MIN_LEAF * 2
	if not can_split_x and not can_split_y:
		rooms.append(_make_room(area, rng))
		return
	var split_x: bool
	if can_split_x and can_split_y:
		split_x = area.size.x > area.size.y  # 沿长边切,房间更方正
	else:
		split_x = can_split_x
	if split_x:
		var cut := rng.randi_range(MIN_LEAF, area.size.x - MIN_LEAF)
		_split(Rect2i(area.position, Vector2i(cut, area.size.y)), rng, rooms)
		_split(Rect2i(area.position + Vector2i(cut, 0), Vector2i(area.size.x - cut, area.size.y)), rng, rooms)
	else:
		var cut := rng.randi_range(MIN_LEAF, area.size.y - MIN_LEAF)
		_split(Rect2i(area.position, Vector2i(area.size.x, cut)), rng, rooms)
		_split(Rect2i(area.position + Vector2i(0, cut), Vector2i(area.size.x, area.size.y - cut)), rng, rooms)


static func _make_room(leaf: Rect2i, rng: RandomNumberGenerator) -> Rect2i:
	var rw := mini(rng.randi_range(4, maxi(4, leaf.size.x - 2)), leaf.size.x - 1)
	var rh := mini(rng.randi_range(4, maxi(4, leaf.size.y - 2)), leaf.size.y - 1)
	var rx := leaf.position.x + rng.randi_range(0, leaf.size.x - rw)
	var ry := leaf.position.y + rng.randi_range(0, leaf.size.y - rh)
	return Rect2i(rx, ry, rw, rh)


static func _carve_rect(grid: Array, r: Rect2i) -> void:
	for y in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			grid[y][x] = 0


static func _carve_corridor(grid: Array, w: int, h: int, from: Vector2i, to: Vector2i, rng: RandomNumberGenerator) -> void:
	# L 形走廊:拐点随机选"先横后竖"或"先竖后横"
	var mid := Vector2i(to.x, from.y) if rng.randf() < 0.5 else Vector2i(from.x, to.y)
	_carve_line(grid, w, h, from, mid)
	_carve_line(grid, w, h, mid, to)


static func _carve_line(grid: Array, w: int, h: int, from: Vector2i, to: Vector2i) -> void:
	var cur := from
	var step := (to - cur).sign()
	while true:
		for dy in CORRIDOR_WIDTH:
			for dx in CORRIDOR_WIDTH:
				var x := clampi(cur.x + dx, 1, w - 2)
				var y := clampi(cur.y + dy, 1, h - 2)
				grid[y][x] = 0
		if cur == to:
			break
		cur += step
