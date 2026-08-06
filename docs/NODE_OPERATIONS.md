# Node Operations

Selectors can be strings or objects. Object fields are combined with AND.
Exact fields are `id`, `label`, `name`/`text`, `value`, and `type`. Their
`*Match` or `*Regex` variants accept regular expressions. State and structural
filters include `enabled`/`enable`, `visible`, `selected`, `accessible`,
`index`, `depth`, `childCount`, and `bounds`:

The built-in no-WDA adapter (`AutoBuiltinAdapter`) accepts the same exact and
regex fields; its descriptors carry `handle`/`parentHandle` identifiers derived
from accessibility tree paths. Handles stop matching after the UI changes, so
re-query after navigation. `xpath`/`predicate` selectors are not supported by
the built-in adapter and return a clear error (the legacy WDA adapter was
removed in v1.17.0).

```javascript
const login = auto.findElement({id: "login-button", type: "Button"});
if (login && auto.exists(login)) {
  auto.click(login);
}
```

`findElement` returns a JSON-safe descriptor:

```json
{
  "selector": {"handle": "B174..."},
  "handle": "B174...",
  "nodeId": "B174...",
  "parentId": "A063...",
  "id": "login-button",
  "label": "登录",
  "value": null,
  "text": "登录",
  "type": "Button",
  "className": "UIButton",
  "enabled": true,
  "visible": true,
  "selected": false,
  "accessible": true,
  "index": 2,
  "order": 2,
  "depth": 5,
  "childCount": 0,
  "bounds": {"x": 20, "y": 80, "width": 120, "height": 44, "centerX": 80, "centerY": 102}
}
```

Available operations:

- `auto.exists(selector)` returns a boolean without throwing for a missing node.
- `auto.findElements(selector)` returns up to `maxResults` descriptors (500 by default).
- `auto.waitFor(selector, timeoutMs)` polls until the node exists or raises `AutoSDKErrorWaitTimeout`.
- `auto.getAttribute(selector, name)` reads `id`, `label`, `value`, `text`, `type`, `className`, `enabled`, `visible`, or `bounds`.
- `auto.getBounds(selector)` returns screen-coordinate bounds in points.
- `auto.getChildren(selector)` returns direct visible child descriptors.
- `auto.getParent(selector)` returns the parent descriptor or `null`.
- `auto.getChild(node, index)`, `auto.getSiblings(node)`,
  `auto.getPreviousSiblings(node)`, and `auto.getNextSiblings(node)` navigate
  the current UIKit hierarchy.
- `auto.clickCenter(node)` and `auto.clickRandom(node)` activate a point inside
  a descriptor through the current adapter.
- `auto.scrollIntoView(selector)` scrolls the nearest ancestor `UIScrollView` in
  UIKit mode; the built-in no-WDA adapter scrolls with real injected swipes.

UIKit descriptors contain stable, non-retaining handles associated with live
views. A handle stops matching after that view is deallocated. Re-query after
navigation or when a framework replaces a view instance.

Inspector snapshots are pre-order flat trees. `nodeId` identifies the node in
that snapshot, `parentId` links it to its parent, `depth` controls indentation,
and `order` is the sibling order. These fields are for inspection and should
not be persisted as selectors.
