extends Node2D
## 过关结算插页:广播用黑色幽默把数字砸到你脸上——
## 淘汰人数、奖金涨幅,加一句怂恿你继续往下走的话。
## 主办方的声音要有人格:殷勤、算计、永远在劝你"再玩一轮"。


func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.size = Vector2(640, 360)
	bg.color = Color("0a0c10")
	layer.add_child(bg)

	var title := Game.make_label(layer, Vector2(0, 60), 18, "第 %d 场游戏 —— 通过" % Run.rounds_survived)
	var line1 := Game.make_label(layer, Vector2(0, 110), 12, "本场淘汰  %d 人" % Run.last_eliminated)
	line1.modulate = Color("ff8080")
	var line2 := Game.make_label(layer, Vector2(0, 134), 14, "奖金池  +%d   →   %d" % [Run.last_gain, Run.prize_pool])
	line2.modulate = Color("ffd86b")
	var line3 := Game.make_label(layer, Vector2(0, 162), 10, "剩余参赛者:%d" % Run.survivors)
	line3.modulate.a = 0.8

	var taunts := [
		"他们的死,每条命折价 100。别让它贬值。",
		"又少了 %d 个和你分钱的人。你说巧不巧。" % Run.last_eliminated,
		"你已经踩着 %d 具尸体走到这里了。现在退出,他们就白死了。" % (48 - Run.survivors),
		"干得漂亮,23 号。投资人开始记住你的编号了。",
		"记住刚才的心跳。这种东西,外面花钱买不到。",
		"奖金池 %d 了。够还清外面的债吗?不够吧。那就继续。" % Run.prize_pool,
		"剩下的 %d 个人此刻也在看这块屏幕。他们在算你能活几轮。" % (Run.survivors - 1),
	]
	var taunt := Game.make_label(layer, Vector2(0, 220), 11, "【广播】" + taunts[randi() % taunts.size()])
	taunt.modulate = Color("9fd1c8")

	var hint := Game.make_label(layer, Vector2(0, 320), 9, "按 Enter 返回宿舍区")
	hint.modulate.a = 0.0

	for l in [title, line1, line2, line3, taunt, hint]:
		l.size = Vector2(640, 30)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 逐行亮起:数字一行一行砸出来
	var order := [title, line1, line2, line3, taunt, hint]
	for i in order.size():
		var l: Label = order[i]
		var target_a := 0.6 if l == hint else l.modulate.a
		l.modulate.a = 0.0
		var tw := l.create_tween()
		tw.tween_interval(0.35 * i)
		tw.tween_callback(func() -> void: Game.play_sfx("hit", 1.8))
		tw.tween_property(l, "modulate:a", target_a, 0.18)
	Game.play_sfx("alert", 0.7)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		Run.report_done()
