class_name OfflineProgress
extends RefCounted

# Offline item generation REMOVED 2026-06-06 per user direction. The
# previous behavior — simulating floors-while-away and dumping a fully-
# affixed inventory + gold on every relaunch — let players reach Lv 57
# in 4 runs because every session boot pumped ~16 fully-rolled items.
# User said "i never liked it." Stripped to a no-op so launch flow
# stays unchanged but no items/gold materialize.
#
# 2026-06-09: dead `_legacy_apply` body and helpers deleted per user.
# `apply()` is kept (callers in main.gd / main_menu.gd reference it)
# but always returns an empty summary. The banner UI early-returns
# when summary.is_empty() / summary.floors == 0, so no UI thread to
# untangle.
static func apply(_state: Dictionary, _items_db: Dictionary) -> Dictionary:
	return {}
