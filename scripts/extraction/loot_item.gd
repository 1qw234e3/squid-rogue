extends Node2D
## 撤离模式战利品(图纸 §二):白货碰触即拾;蓝/金按住 E 引导拾取——
## 引导期间不能开枪(player.channeling),翻滚直接取消进度。
## 金货带脉冲发光:看得见的奖励才构成贪婪决策。

signal collected(value: int, tier: String)

const TIERS := {
	"white": {"value": 1, "time": 0.0, "color": Color("d8dee6"), "size": Vector2(7, 7), "label": "白货"},
	"blue": {"value": 3, "time": -1.0, "color": Color("5aa4e8"), "size": Vector2(9, 9), "label": "蓝货"},
	"gold": {"value": 8, "time": -1.0, "color": Color("ffd86b"), "size": Vector2(11, 11), "label": "金货"},
}

var tier := "white"
var progress := 0.0
var done := false
var was_channeling := false


func _ready() -> void:
	add_to_group("loot_items")
	queue_redraw()
	if tier == "gold":
		# 金货脉冲:隔着视线缝也认得出
		var tw := create_tween().set_loops()
		tw.tween_property(self, "modulate:a", 0.45, 0.45)
		tw.tween_property(self, "modulate:a", 1.0, 0.45)


func pickup_time() -> float:
	match tier:
		"blue": return Tune.pickup_blue
		"gold": return Tune.pickup_gold
	return 0.0


func _process(delta: float) -> void:
	if done:
		return
	var p := get_tree().get_first_node_in_group("player")
	if p == null or not (p is Node2D) or not p.visible:
		return
	var dist: float = p.global_position.distance_to(global_position)
	if pickup_time() <= 0.0:
		if dist < 14.0:
			_collect(p)
		return
	# 引导拾取:范围内按住 E;翻滚取消;松手缓慢回退
	var holding: bool = dist < 18.0 and Input.is_action_pressed("interact") and not p.rolling
	if holding:
		progress += delta
		p.channeling = true
		was_channeling = true
		if progress >= pickup_time():
			p.channeling = false
			_collect(p)
	else:
		if p.rolling:
			progress = 0.0  # 翻滚 = 拾取作废
		else:
			progress = maxf(progress - delta * 2.0, 0.0)
		if was_channeling:
			p.channeling = false
			was_channeling = false
	queue_redraw()


func _collect(_p: Node) -> void:
	done = true
	var spec: Dictionary = TIERS[tier]
	Game.play_sfx("hit", 1.7)
	Game.float_text(global_position, "%s +%d" % [spec.label, spec.value], spec.color)
	collected.emit(spec.value, tier)
	queue_free()


func _draw() -> void:
	var spec: Dictionary = TIERS[tier]
	var s: Vector2 = spec.size
	draw_rect(Rect2(-s / 2.0, s), spec.color)
	if pickup_time() > 0.0 and progress > 0.0:
		# 引导进度环
		draw_arc(Vector2.ZERO, 12.0, -PI / 2.0, -PI / 2.0 + TAU * (progress / pickup_time()), 24, Color(1, 1, 1, 0.8), 2.0)
