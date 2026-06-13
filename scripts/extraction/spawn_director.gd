extends Node
## 增援导演(图纸 §四):预算 + 收敛目标 + 最小距离两条铁律——
## 1. 刷新点离玩家 ≥1.5 屏(960px),入场前 1s 从来向播画外提示音
## 2. 增援是"猎人":不巡逻,直奔最后枪声位置,到点搜索后原地转巡逻

const Guard := preload("res://scripts/actors/guard.gd")

const MIN_DIST := 960.0 * 0.85  # 地图对角不足 1.5 屏时按比例放宽,先取 ~816px
const MAX_CONCURRENT := 15      # 底数 9 + 增援并发 6

var arena: Node2D
var player: CharacterBody2D
var last_noise_pos := Vector2.ZERO
var has_noise := false


func _ready() -> void:
	EventBus.noise_emitted.connect(_on_noise)


func _on_noise(pos: Vector2, _radius: float, source_group: String) -> void:
	if source_group != "guards":
		last_noise_pos = pos
		has_noise = true


func spawn_squad(count: int) -> void:
	for i in count:
		if get_tree().get_nodes_in_group("guards").size() >= MAX_CONCURRENT:
			return
		_spawn_hunter()


func _spawn_hunter() -> void:
	# 选点:远离玩家;多次尝试取最远的合格点
	var best := Vector2.ZERO
	var best_d := 0.0
	for attempt in 24:
		var pos: Vector2 = arena.random_floor_position()
		var d := pos.distance_to(player.global_position)
		if d > best_d:
			best_d = d
			best = pos
		if d >= MIN_DIST:
			best = pos
			break
	# 铁律 1 后半:入场前 1s 从来向播画外提示音(守卫哔哔降调)
	Game.play_sfx_at("alert", best, 0.55)
	await get_tree().create_timer(1.0).timeout
	if not is_instance_valid(arena) or not is_instance_valid(player):
		return
	var g := Guard.new()
	var hunt_pos := last_noise_pos if has_noise else player.global_position
	g.setup(arena, player, best + Vector2(24, 0), best - Vector2(24, 0))
	g.vision_range = 96.0   # 撤离模式是亮图,恢复标准视野
	g.track_range = 192.0
	arena.add_child(g)
	g.global_position = best
	g.hunt(hunt_pos)
