extends Camera2D
## 屏震相机:trauma 累积、随时间衰减,开火约 2px、受击更大(设计文档 §6)。

var trauma := 0.0


func add_shake(amount: float) -> void:
	trauma = minf(trauma + amount, 8.0)


func _process(delta: float) -> void:
	if trauma > 0.0:
		trauma = maxf(trauma - 26.0 * delta, 0.0)
		offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * trauma
	else:
		offset = Vector2.ZERO
