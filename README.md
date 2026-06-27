# CJS Multi-Corpse Trash

Adds a world context-menu action for putting a dragged or carried corpse into a nearby trash can or ZuperCarts cart/trolley. While dragging a corpse, right-click the target or an adjacent square and choose **Put Corpse in Garbage** or **Put Corpse in Cart/Trolley**.

This mod does not change trash-can capacity; pair it with a storage-capacity mod when you want a can to hold multiple corpses.

Version 0.1.2 wraps the vanilla world-context menu creation so the action can still appear while a corpse is being dragged and vanilla returns before late mod hooks run.

Version 0.1.8 avoids building drag-state diagnostics unless debug logging is enabled, preventing random right-clicks from producing Lua stack traces.

Version 0.1.9 lets ZuperCarts carts and trolleys use the same corpse-to-container context action.
