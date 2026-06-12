extends Node2D
## 近战挥砍弧光:一道快速淡出的圆弧,半径 = 攻击距离,扫角 = 攻击弧度。
## 玩家得看见自己打了多大一片,近战判定才不显得玄学。

const DURATION := 0.12

var arc := PI * 0.7
var range_px := 24.0
var color := Color.WHITE
var t := 0.0


func _process(delta: float) -> void:
	t += delta
	if t >= DURATION:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := 1.0 - t / DURATION
	draw_arc(Vector2.ZERO, range_px, -arc / 2.0, arc / 2.0, 16, Color(color.r, color.g, color.b, 0.55 * k), 3.0)
