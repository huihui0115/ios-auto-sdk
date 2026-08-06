# Bootstrap rewrite history

These scripts were used in earlier rounds to rewrite the embedded bootstrap
`Sources/AutoSDK/AutoBootstrapScript.m` via decode → string-replace → encode.
They are kept for reference only.

**Current workflow (single source of truth):**

1. Edit `tools/bootstrap-source.js` (the decoded bootstrap JavaScript).
2. Run `npm run regenerate:bootstrap` (→ `tools/regenerate-bootstrap.mjs`),
   which re-encodes it into `AutoBootstrapScript.m` with 4000-char Objective-C
   string literals, verifies the round-trip, and checks the 60 KiB budget.
3. `npm run verify` enforces that the committed `.m` file matches
   `tools/bootstrap-source.js` exactly.

## Scripts

- `rewrite_bootstrap_T01-T27.mjs` — the original T1–T27 pipeline (from git
  base 4b14029): helper compaction (_ff/_pc/_dv/_md/_av/_nn), fileApi/storage
  compaction, stringsApi additions, timer/thread helpers, export compaction.
- `rewrite_r39_T32.mjs` — Round 39 additions: arr() helper, stringsApi
  forEach batch exports, EasyClick color tools (pCol/int2Hex/colorsApi).
- `rewrite_r40.mjs` — Round 40: dvf/avf/hsh/hsh2 helper compaction and the
  thread/utils namespaces + global aliases.
- `extract_bootstrap.py` — decode helper (extracts the JS from the .m file).
- `bracket_check.py` — brace-balance sanity check for Objective-C files.

> Note: never run the historical scripts against the current committed
> bootstrap — they assume an older starting point and would double-apply.
