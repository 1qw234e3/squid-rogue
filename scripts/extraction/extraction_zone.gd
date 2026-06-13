extends Node2D
## 撤离圈状态机(图纸 §三):idle / channeling / paused / complete。
## 圈内站桩计时;出圈暂停不清零;挨打不打断(惩罚来自伤害本身)。
## 每秒一声升调哔,最后一秒换音色——耳朵盯进度,眼睛盯敌人。

signal extracted(zone_name: String)

const RADIUS := 26.0

var zone_name := "撤离点"
var progress := 0.0
var complete := false
var _last_beep := -1


func _process(delta: float) -> void:
	if complete:
		return
	var p := get_tree().get_first_node_in_group("player")
	if p == null or not (p is Node2D) or not p.visible:
		return
	if p.global_position.distance_to(global_position) <= RADIUS:
		progress += delta
		var sec := int(progress)
		if sec != _last_beep:
			_last_beep = sec
			# 升调哔;最后一秒明显换音色
			if progress >= Tune.extract_time - 1.0:
				Game.play_sfx("alert", 1.8)
			else:
				Game.play_sfx("hit", 1.2 + sec * 0.2)
		if progress >= Tune.extract_time:
			complete = true
			extracted.emit(zone_name)
	# 出圈:暂停,不清零
	queue_redraw()


func _draw() -> void:
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 40, Color(0.42, 0.78, 0.55, 0.7), 2.0)
	draw_circle(Vector2.ZERO, 3.0, Color(0.42, 0.78, 0.55, 0.7))
	if progress > 0.0 and not complete:
		# 圈上方进度条
		var w := 36.0
		var k: float = clampf(progress / Tune.extract_time, 0.0, 1.0)
		draw_rect(Rect2(-w / 2.0, -RADIUS - 12.0, w, 4.0), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(-w / 2.0, -RADIUS - 12.0, w * k, 4.0), Color("7fe0a0"))
