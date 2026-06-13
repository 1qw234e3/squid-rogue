extends Node
## 全局事件总线(autoload,设计文档 §10):淘汰、血量、武器、过关等事件全走这里,
## 系统之间不互相引用,只对信号做出反应——后续沙盒/社交系统都挂在这上面。

signal guard_died(guard: Node)
signal player_hp_changed(hp: int, max_hp: int)
signal player_died
signal weapon_equipped(stats: Dictionary)
signal exit_reached
## 噪音事件:潜行系统的统一货币(设计议题 1.3)。枪声、未来的偷窃失手、
## 通风管动静都从这里广播;守卫各自判断声源是否在自己可听范围内
signal noise_emitted(pos: Vector2, radius: float, source_group: String)
## 守卫进入追捕的瞬间(被发现次数统计/威胁系统用)
signal guard_alerted
