extends Node2D
## 抢椅子(设计文档 §3.6,原创关):圆形竞技场。
## 音乐期全员必须移动(站定 >1.5s 吃狙击警告);音乐随机 8~20s 停 →
## 抢椅(站上 0.5s 锁定);没抢到的进清场期:弹幕越打越密,
## 期间升起一把"补刀椅"作绝境逆转点。E 可以把别人从椅子上推下去。

const PlayerScript := preload("res://scripts/actors/player.gd")
const ShakeCamera := preload("res://scripts/m0/shake_camera.gd")
const ChairsNpc := preload("res://scripts/actors/chairs_npc.gd")
const Bullet := preload("res://scripts/combat/bullet.gd")

const CENTER := Vector2(320, 180)
const ARENA_R := 150.0
const NPC_COUNT := 11
const CYCLES := [8, 5]        # 每轮椅子数:12人抢8把,幸存者抢5把
const LOCK_TIME := 0.5
const STILL_LIMIT := 1.5
const CLEAR_STATS := {"bullet_speed": 160.0, "damage": 2, "color": Color("ff5a5a")}

enum Phase { WARMUP, MUSIC, SCRAMBLE, CLEAR, DONE }

var phase := Phase.WARMUP
var phase_t := 2.5
var cycle := 0
var rng := RandomNumberGenerator.new()
var player: CharacterBody2D
var player_chair := -1
var chairs: Array = []   # {pos, claimed(Node|null), visual}
var lockers := {}        # entity -> {"chair": idx, "t": float}
var still_t := 0.0
var idle_laser := -1.0
var laser: Line2D
var volley_t := 0.0
var clear_elapsed := 0.0
var bonus_spawned := false
var finished := false
var hud_phase: Label
var hud_msg: Label
var hud_cast: Label
var cast_timer := 0.0


func _ready() -> void:
	rng.randomize()
	_build_arena()
	_spawn_player()
	_spawn_npcs()
	_make_chairs(CYCLES[0])
	_setup_hud()
	laser = Line2D.new()
	laser.width = 1.5
	laser.default_color = Color(1.0, 0.2, 0.2, 0.6)
	laser.visible = false
	add_child(laser)
	EventBus.player_died.connect(_on_player_died)
	_broadcast("热身。记住椅子的位置。")
	queue_redraw()


func _process(delta: float) -> void:
	if finished:
		return
	if cast_timer > 0.0:
		cast_timer -= delta
		if cast_timer <= 0.0:
			hud_cast.modulate.a = 0.0
	player.invulnerable = player_chair >= 0
	match phase:
		Phase.WARMUP:
			phase_t -= delta
			if phase_t <= 0.0:
				_start_music()
		Phase.MUSIC:
			_music_tick(delta)
		Phase.SCRAMBLE:
			phase_t -= delta
			_lock_logic(delta)
			if _all_chairs_claimed() or phase_t <= 0.0:
				_start_clear()
		Phase.CLEAR:
			clear_elapsed += delta
			_lock_logic(delta)
			_clear_volley(delta)
			if _everyone_resolved():
				_end_cycle()


# ---------- 阶段推进 ----------

func _start_music() -> void:
	phase = Phase.MUSIC
	phase_t = rng.randf_range(8.0, 20.0)
	still_t = 0.0
	hud_phase.text = "♪ 圆舞曲播放中 —— 保持移动"
	hud_phase.modulate = Color("9fd1c8")
	Game.play_music("waltz")  # 优雅的钢琴圆舞曲:音乐越好听,骤停越惊心
	_broadcast("音乐响起。站着不动的人,守卫会帮他动起来。")


func _music_tick(delta: float) -> void:
	phase_t -= delta
	_check_player_still(delta)
	if phase_t <= 0.0:
		phase = Phase.SCRAMBLE
		phase_t = 6.0
		laser.visible = false
		idle_laser = -1.0
		hud_phase.text = "音乐停!抢椅子!"
		hud_phase.modulate = Color("ffd86b")
		Game.stop_music()  # 骤停即指令
		Game.play_sfx("alert", 0.6)
		Game.shake(3.0)
		_broadcast("音乐停止。椅子数:%d。" % chairs.size())


func _start_clear() -> void:
	phase = Phase.CLEAR
	clear_elapsed = 0.0
	volley_t = 0.5
	bonus_spawned = false
	hud_phase.text = "清场弹幕 —— 没坐下的快找补刀椅"
	hud_phase.modulate = Color("ff7070")


func _clear_volley(delta: float) -> void:
	# 补刀椅:清场 1.2s 后升起,绝境逆转点
	if not bonus_spawned and clear_elapsed > 1.2:
		bonus_spawned = true
		_add_chair(_random_inner_point())
		_broadcast("补刀椅升起!")
		Game.play_sfx("alert", 1.3)
	volley_t -= delta
	if volley_t > 0.0:
		return
	# 弹幕越打越密:0.45s → 0.15s
	volley_t = maxf(0.45 - clear_elapsed * 0.03, 0.15)
	for e in _entities():
		if _is_seated(e) or _is_dead(e):
			continue
		var from := CENTER + Vector2.from_angle(rng.randf_range(0.0, TAU)) * (ARENA_R - 6.0)
		var target: Vector2 = e.global_position + e.velocity * 0.3  # 简单提前量
		var ang := (target - from).angle()
		var b := Bullet.new()
		add_child(b)
		b.launch(from, ang, CLEAR_STATS, "guards", 1 | 2)
	Game.play_sfx_at("shoot", CENTER + Vector2.from_angle(rng.randf()) * ARENA_R, 0.8)


func _end_cycle() -> void:
	cycle += 1
	if cycle >= CYCLES.size():
		_win()
		return
	# 下一轮:全员起立,撤掉旧椅,摆更少的新椅
	for e in _entities():
		_unclaim_silent(e)
	lockers.clear()
	for c in chairs:
		c.visual.queue_free()
	chairs.clear()
	_make_chairs(CYCLES[cycle])
	player_chair = -1
	phase = Phase.WARMUP
	phase_t = 2.0
	hud_phase.text = "全员起立。椅子变少了。"
	hud_phase.modulate = Color.WHITE
	_broadcast("第 %d 轮。椅子:%d 把。" % [cycle + 1, CYCLES[cycle]])


# ---------- 椅子与锁定 ----------

func _make_chairs(count: int) -> void:
	for i in count:
		var ang := TAU * i / count + rng.randf_range(-0.15, 0.15)
		var r := rng.randf_range(40.0, 85.0)
		_add_chair(CENTER + Vector2.from_angle(ang) * r)


func _add_chair(pos: Vector2) -> void:
	var visual := ColorRect.new()
	visual.size = Vector2(12, 12)
	visual.position = pos - visual.size / 2.0
	visual.color = Color("8a8f99")
	add_child(visual)
	chairs.append({"pos": pos, "claimed": null, "visual": visual})


func _lock_logic(delta: float) -> void:
	for e in _entities():
		if _is_dead(e) or _is_seated(e):
			continue
		var idx := -1
		for i in chairs.size():
			if chairs[i].claimed == null and chairs[i].pos.distance_to(e.global_position) < 10.0:
				idx = i
				break
		if idx < 0:
			lockers.erase(e)
			continue
		if not lockers.has(e) or lockers[e].chair != idx:
			lockers[e] = {"chair": idx, "t": 0.0}
		lockers[e].t += delta
		if lockers[e].t >= LOCK_TIME:
			lockers.erase(e)
			_claim(e, idx)
	# 玩家坐下后走开 = 主动放弃椅子
	if player_chair >= 0 and chairs[player_chair].pos.distance_to(player.global_position) > 12.0:
		_unclaim_silent(player)
		_broadcast("你离开了椅子。")


func _claim(e: Node, idx: int) -> void:
	chairs[idx].claimed = e
	if e == player:
		player_chair = idx
		chairs[idx].visual.color = Color("7fd1ff")
		Game.play_sfx("hit", 1.4)
		_broadcast("锁定。坐稳别动。")
	else:
		e.seated_chair = idx
		chairs[idx].visual.color = e.tint


func unclaim_entity(e: Node) -> void:
	_unclaim_silent(e)


func _unclaim_silent(e: Node) -> void:
	for i in chairs.size():
		if chairs[i].claimed == e:
			chairs[i].claimed = null
			chairs[i].visual.color = Color("8a8f99")
	if e == player:
		player_chair = -1
	elif "seated_chair" in e:
		e.seated_chair = -1


func _all_chairs_claimed() -> bool:
	for c in chairs:
		if c.claimed == null:
			return false
	return true


func _everyone_resolved() -> bool:
	for e in _entities():
		if not _is_dead(e) and not _is_seated(e):
			return false
	return true


# ---------- 玩家:站定判定 / 推人 ----------

func _check_player_still(delta: float) -> void:
	if player.velocity.length() < 10.0:
		still_t += delta
	else:
		still_t = 0.0
		if idle_laser >= 0.0:
			idle_laser = -1.0
			laser.visible = false
	if still_t > STILL_LIMIT and idle_laser < 0.0:
		idle_laser = 0.5
		laser.visible = true
		Game.play_sfx("alert", 1.5)
	if idle_laser >= 0.0:
		idle_laser -= delta
		var from := CENTER + (player.global_position - CENTER).normalized() * ARENA_R
		laser.points = PackedVector2Array([from, player.global_position])
		if idle_laser < 0.0:
			laser.visible = false
			still_t = 0.0
			Game.play_sfx("shoot_heavy", 0.9)
			Game.shake(3.0)
			player.take_damage(2, (player.global_position - CENTER).normalized())
			_broadcast("23 号,警告。下次不会只打腿。")


func _unhandled_input(event: InputEvent) -> void:
	if finished or not event.is_action_pressed("interact"):
		return
	# 推撞:把最近的 NPC 撞开;他若坐着,椅子就空出来了
	var best: Node2D = null
	for npc in get_tree().get_nodes_in_group("chairs_npcs"):
		if npc.dead:
			continue
		if npc.global_position.distance_to(player.global_position) < 22.0:
			if best == null or npc.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position):
				best = npc
	if best:
		var was_seated: bool = best.seated_chair >= 0
		best.shove((best.global_position - player.global_position).normalized())
		Game.play_sfx("melee_hit")
		Game.shake(1.5)
		if was_seated:
			_broadcast("第 %02d 号被推下了椅子!" % best.number)


# ---------- 结束 ----------

func _win() -> void:
	if finished:
		return
	finished = true
	phase = Phase.DONE
	Game.stop_music()
	hud_msg.text = "你抢到了活下去的位置"
	hud_msg.visible = true
	await get_tree().create_timer(1.8).timeout
	Run.minigame_finished(true)


func _on_player_died() -> void:
	if finished:
		return
	finished = true
	Game.stop_music()
	hud_msg.text = "淘汰:没有你的椅子"
	hud_msg.visible = true
	await get_tree().create_timer(1.8).timeout
	Run.minigame_finished(false)


# ---------- 工具 ----------

func _entities() -> Array:
	var list: Array = [player]
	list.append_array(get_tree().get_nodes_in_group("chairs_npcs"))
	return list


func _is_seated(e: Node) -> bool:
	if e == player:
		return player_chair >= 0
	return e.seated_chair >= 0


func _is_dead(e: Node) -> bool:
	if e == player:
		return player.hp <= 0
	return e.dead


func seeking_chairs() -> bool:
	return phase == Phase.SCRAMBLE or phase == Phase.CLEAR


func nearest_free_chair(pos: Vector2) -> int:
	var best := -1
	var best_d := INF
	for i in chairs.size():
		if chairs[i].claimed == null and chairs[i].pos.distance_to(pos) < best_d:
			best_d = chairs[i].pos.distance_to(pos)
			best = i
	return best


func chair_pos(idx: int) -> Vector2:
	return chairs[idx].pos


func arena_center() -> Vector2:
	return CENTER


func random_point() -> Vector2:
	return CENTER + Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(20.0, ARENA_R - 25.0)


## 补刀椅的落点:场地内圈,谁都有机会冲到
func _random_inner_point() -> Vector2:
	return CENTER + Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(25.0, 70.0)


func report_npc_death(number: int) -> void:
	_broadcast("第 %02d 号参赛者,淘汰。" % number)


func _broadcast(text: String) -> void:
	hud_cast.text = "【广播】" + text
	hud_cast.modulate.a = 1.0
	cast_timer = 3.0


# ---------- 搭场景 ----------

func _draw() -> void:
	draw_rect(Rect2(0, 0, 640, 360), Color("12151c"))
	draw_circle(CENTER, ARENA_R, Color("3d4452"))
	draw_arc(CENTER, ARENA_R, 0.0, TAU, 64, Color("171c24"), 6.0)


func _build_arena() -> void:
	# 圆形围墙:24 段小矩形拼出来,够圆也够便宜
	var body := StaticBody2D.new()
	body.collision_layer = 1
	add_child(body)
	for i in 24:
		var ang := TAU * i / 24
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(ARENA_R * TAU / 24 + 6.0, 10.0)
		shape.shape = rect
		shape.position = CENTER + Vector2.from_angle(ang) * (ARENA_R + 5.0)
		shape.rotation = ang + PI / 2.0
		body.add_child(shape)


func _spawn_player() -> void:
	player = PlayerScript.new()
	add_child(player)
	player.global_position = CENTER + Vector2(0, ARENA_R - 30.0)
	player.combat_enabled = false  # 这关的武器是腿和手肘
	var cam: Camera2D = ShakeCamera.new()
	cam.position = CENTER
	add_child(cam)
	cam.make_current()
	Game.camera = cam


func _spawn_npcs() -> void:
	for i in NPC_COUNT:
		var npc := ChairsNpc.new()
		npc.setup(self, i + 1 if i + 1 < 23 else i + 2)
		add_child(npc)
		npc.global_position = CENTER + Vector2.from_angle(TAU * i / NPC_COUNT) * (ARENA_R - 35.0)


func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud_phase = Game.make_label(layer, Vector2(0, 8), 12)
	hud_phase.size = Vector2(640, 20)
	hud_phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hint := Game.make_label(layer, Vector2(8, 344), 8, "音乐期保持移动 · 椅子上站 0.5s 锁定 · E 推人抢座")
	hint.modulate.a = 0.7
	hud_msg = Game.make_label(layer, Vector2(0, 150), 16)
	hud_msg.size = Vector2(640, 40)
	hud_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_msg.visible = false
	hud_cast = Game.make_label(layer, Vector2(0, 310), 9)
	hud_cast.size = Vector2(640, 16)
	hud_cast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_cast.modulate.a = 0.0
