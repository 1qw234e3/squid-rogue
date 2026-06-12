extends Node2D
## 噪音圈可视化:开枪时从枪口扩散一圈白环,半径 = 守卫能听到的范围。
## 玩家必须"看得见"噪音机制,才会把它纳入决策。

const DURATION := 0.35

var max_radius := 120.0
var t := 0.0


func _process(delta: float) -> void:
	t += delta
	if t >= DURATION:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := t / DURATION
	draw_arc(Vector2.ZERO, max_radius * k, 0.0, TAU, 48, Color(1, 1, 1, 0.20 * (1.0 - k)), 1.5)
