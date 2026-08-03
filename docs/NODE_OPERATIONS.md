# Node Operations

Selectors can be strings or objects. Object fields are combined with AND.
Exact fields are `id`, `label`, `name`/`text`, `value`, and `type`. Their
`*Match` or `*Regex` variants accept regular expressions. State and structural
filters include `enabled`/`enable`, `visible`, `selected`, `accessible`,
`index`, `depth`, `childCount`, and `bounds`:

`AutoWDAHTTPAdapter` additionally accepts `xpath`, `predicate`, and
`classChain`. WDA element descriptors include `elementId`, `wdElementId`, and
`sessionId`; those handles are valid only for that WDA session. Parent/child
descriptors returned by WDA source traversal are marked `sourceDerived` and
use an absolute XPath selector, so refresh them after the UI changes.

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
  UIKit mode or the WDA element scroll route in WDA mode.

UIKit descriptors contain stable, non-retaining handles associated with live
views. A handle stops matching after that view is deallocated. Re-query after
navigation or when a framework replaces a view instance.

Inspector snapshots are pre-order flat trees. `nodeId` identifies the node in
that snapshot, `parentId` links it to its parent, `depth` controls indentation,
and `order` is the sibling order. These fields are for inspection and should
not be persisted as selectors.
