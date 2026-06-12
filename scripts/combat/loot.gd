extends Node2D
## 场地稀有物(走过即拾,自轮询玩家距离,无需场景接线):
## 钱袋(配给券)/ 食物(回血)/ 稀有钱箱(大额,闪光提示——"幸运感"需要被看见)。

const KINDS := {
	"money": {"color": Color("e8c25a"), "size": Vector2(8, 6)},
	"food": {"color": Color("7fd17f"), "size": Vector2(7, 7)},
	"cache": {"color": Color("ffea7a"), "size": Vector2(12, 9)},
}

var kind := "money"
var amount := 30
var rect: ColorRect


func _ready() -> void:
	add_to_group("loot")
	var spec: Dictionary = KINDS[kind]
	rect = ColorRect.new()
	rect.size = spec.size
	rect.position = -spec.size / 2.0
	rect.color = spec.color
	add_child(rect)
	if kind == "cache":
		var tw := create_tween().set_loops()
		tw.tween_property(rect, "modulate:a", 0.45, 0.4)
		tw.tween_property(rect, "modulate:a", 1.0, 0.4)


func _process(_delta: float) -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p == null or not (p is Node2D) or not p.visible:
		return
	if p.global_position.distance_to(global_position) < 14.0:
		_collect(p)


func _collect(p: Node) -> void:
	set_process(false)
	var text := ""
	match kind:
		"money":
			Run.tickets += amount
			text = "配给券 +%d" % amount
		"cache":
			Run.tickets += amount
			text = "稀有钱箱!配给券 +%d" % amount
		"food":
			if p.has_method("heal"):
				p.heal(2)
			text = "食物:HP +2"
	Game.play_sfx("hit", 1.7)
	Game.float_text(global_position, text, Color("ffe07a"))
	queue_free()
