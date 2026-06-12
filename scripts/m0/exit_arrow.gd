extends Node2D
## 出口方向指示:挂在玩家身上的半透明小箭头。
## BSP 房间长得都一样,没有它找出口全靠瞎逛,迷路的烦躁会污染手感判断。

var target_pos := Vector2.ZERO


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var to := target_pos - global_position
	if to.length() < 120.0:
		return  # 出口已经进屏,不用指了
	var dir := to.normalized()
	var base := dir * 26.0  # 箭头悬在角色外圈
	var pts := PackedVector2Array([
		base + dir * 7.0,
		base + dir.orthogonal() * 3.5,
		base - dir.orthogonal() * 3.5,
	])
	draw_colored_polygon(pts, Color(0.3, 0.69, 0.43, 0.55))
