# CJS Multi-Corpse Trash

Adds a world context-menu action for putting a dragged or carried corpse into a nearby trash can. While dragging a corpse, right-click the trash can or an adjacent square and choose **Put Corpse in Garbage**.

This mod does not change trash-can capacity; pair it with a storage-capacity mod when you want a can to hold multiple corpses.

Version 0.1.2 wraps the vanilla world-context menu creation so the action can still appear while a corpse is being dragged and vanilla returns before late mod hooks run.

Version 0.1.3-debug adds verbose Lua console logging for menu creation, corpse detection, trash detection, and action execution.
