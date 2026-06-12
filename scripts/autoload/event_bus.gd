extends Node
## 全局事件总线(autoload,设计文档 §10):淘汰、血量、武器、过关等事件全走这里,
## 系统之间不互相引用,只对信号做出反应——后续沙盒/社交系统都挂在这上面。

signal guard_died(guard: Node)
signal player_hp_changed(hp: int, max_hp: int)
signal player_died
signal weapon_equipped(stats: Dictionary)
signal exit_reached
