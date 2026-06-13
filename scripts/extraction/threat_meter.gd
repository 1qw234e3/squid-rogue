extends Node
## 威胁表(图纸 §四,本模式的节拍器):隐藏数值,只露档位。
## 来源:枪声 +1/0.5s 窗(不按发数,保护 SMG)、击杀 +2、
## 开局 90s 后每 drip_interval 秒 +1(软计时器,防无限蹲点)。
## V0 不做衰减、不做尸体感知。

signal tier_changed(tier: int)
signal sustain_spawn  # T3 之后每 45s 续援

const THRESHOLDS := [6.0, 14.0, 24.0]
const DRIP_DELAY := 90.0
const SUSTAIN_INTERVAL := 45.0

var value := 0.0
var tier := 0
var elapsed := 0.0
var _shot_window := 0.0
var _drip_acc := 0.0
var _sustain_acc := 0.0


func _ready() -> void:
	EventBus.noise_emitted.connect(_on_noise)
	EventBus.guard_died.connect(_on_kill)


func _process(delta: float) -> void:
	elapsed += delta
	_shot_window = maxf(_shot_window - delta, 0.0)
	if elapsed > DRIP_DELAY:
		_drip_acc += delta
		if _drip_acc >= Tune.drip_interval:
			_drip_acc = 0.0
			value += 1.0
			_check_tier()
	if tier >= 3:
		_sustain_acc += delta
		if _sustain_acc >= SUSTAIN_INTERVAL:
			_sustain_acc = 0.0
			sustain_spawn.emit()


func _on_noise(_pos: Vector2, _radius: float, source_group: String) -> void:
	if source_group == "guards":
		return
	if _shot_window <= 0.0:
		_shot_window = 0.5
		value += Tune.threat_shot
		_check_tier()


func _on_kill(_guard: Node) -> void:
	value += Tune.threat_kill
	_check_tier()


func _check_tier() -> void:
	var new_tier := 0
	for i in THRESHOLDS.size():
		if value >= THRESHOLDS[i]:
			new_tier = i + 1
	while tier < new_tier:
		tier += 1
		tier_changed.emit(tier)  # 逐档触发,跳档也不漏增援
