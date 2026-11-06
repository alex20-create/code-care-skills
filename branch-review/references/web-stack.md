# Web stack reference: React, TypeScript, ProseMirror, Dexie, Vitest, Playwright

Read this when `package.json` names any of these. Each section lists the failures this stack has actually produced in local-first editors and trackers, and the check that finds them. They are additions to the two lenses in `SKILL.md`, not replacements.

## Where these projects go wrong

The pattern across several of them: **the editor layer is where it fails**, and **green tests proved nothing about the editor**. Hundreds of unit tests and a handful of end-to-end flows passed while the app was unusable, because the flows typed each burst of text in one go and never hit the bug a person hits by pausing. Later, a fresh reviewer found seven defects in that layer in one pass: block ids colliding on enter mid-scene and aborting the write, a shortcut minting an empty record per keystroke, select-all and retype wiping the document beyond undo, a reorder reporting that nothing had changed. Weigh anything the diff touches in the editor, the store or the flows accordingly.

## React

- **Effects without cleanup, or with the wrong dependency list.** A listener added on mount and never removed, a timer that keeps firing after unmount, an effect that re-runs on every render because it depends on a freshly built object. Trace what happens on the second mount or after navigation.
- **Stale closures.** A callback captured with an old value of state and used after the state changed. Look at anything stored in a ref or passed to a library that holds on to it.
- **Keys.** Lists keyed by index or by a value that can repeat; a duplicate key means a dropped or duplicated row and sometimes a crash in development only.
- **State that should be one value split across several `useState`s** that must agree, then one branch updates only some of them.
- **An update on an unmounted component, or a `setState` after an awaited call** whose component is already gone: silent in production, a warning in development.

## TypeScript

- **`as`, `!` and `any` in the diff** are each a promise the compiler is not allowed to check. Follow every one to the runtime value and ask what happens when the promise is false.
- **`noUncheckedIndexedAccess`**: when it is on (it is in these projects), `arr[i]` is `T | undefined`. A diff that narrows it with `!` instead of a check has decided the index is valid; find who guarantees that.
- **Unions handled with `if` chains and no exhaustiveness check.** A new member of the union falls through to the last branch, silently.
- **Types that encode less than the code assumes:** a `string` id where the code assumes a prefix, a `number` where the code assumes an integer index, an optional field the code reads without checking.

## ProseMirror

- **The document is a projection of the store, not a second copy.** A write path that changes the document without going through the store, or changes the store without re-projecting, leaves the two disagreeing. Trace every `dispatch` and every store write the diff adds and check they meet.
- **Transactions built from stale state.** A transaction created from a `state` captured earlier than the dispatch, or a plugin reading `view.state` in a callback that runs after another transaction. The symptom is a mapping error or a step applied to the wrong position.
- **Selection timing.** A click and a keystroke in the same millisecond read the old caret, because the view takes in a mouse selection on the browser's own schedule. Code that reads the selection right after a programmatic focus or click, or a flow that types right after clicking, is suspect.
- **Rebuilding the view when the data saves.** An autosave that destroys and recreates the editor loses everything typed after the save started, and is invisible to tests that type without pausing.
- **Ids minted inside keymaps and commands.** Enter, Mod-Enter and paste handlers that create records must produce ids that cannot collide with existing ones and must not mint a record per keystroke.

## Dexie and IndexedDB

- **A quota error must leave the previous records where they were.** Follow every write path on `QuotaExceededError`: a transaction that writes several tables in sequence outside one `db.transaction` can leave half of them written. The same for a failed `bulkPut`.
- **Writes with colliding keys abort the whole transaction**, and the abort may surface only as a rejected promise nobody awaits. Check that the caller sees it.
- **Version upgrades are migrations in code** (`db.version(n).upgrade(...)`). They run once on data the user already has; a diff that edits one is a critical-review item in itself.
- **Reads that assume the record exists.** `get` returns `undefined`; a diff that dereferences it has decided the id is always present.
- **Booting with IndexedDB refused** (private mode, a policy): what does the app show, and does it say why?

## Vitest

- **Environment per file.** A test that needs a DOM says `// @vitest-environment jsdom` in its own first line; a diff that adds DOM code to a test running in `node` fails for the wrong reason, or passes because the DOM is never touched.
- **Tests that pin the happy path only.** For a store change, look for the failure-path test (quota, collision, missing record); its absence is not a finding by itself, but a defect found by the lenses with no test covering it is more likely to ship.
- **Fake timers and async.** A test that advances fake timers without awaiting the microtask queue passes while the real code still has a race.

## Playwright

- **Flows must imitate a person.** A flow that types a whole paragraph in one `fill` or one `type` call never meets the bug that lives between keystrokes. Waiting a fixed number of milliseconds is the weaker fix; waiting for the editor to have taken the selection, or for the saved indicator, is the one that holds across machines.
- **A running dev server from another checkout.** A config that reuses an existing server tests whatever is listening on the port. These projects build and serve their own production build on a strict port on purpose; a diff that relaxes that reopens the problem.
- **Geometry assertions against the wrong box.** Text sized in `ch` may lawfully overrun a centimetre box into the padding; assertions belong against the sheet's edge, not the inner box. Font rendering differs by a hair between Linux and Windows.
- **One worker, one project, on purpose.** Parallel workers raced over the port; a diff that raises the worker count without changing the server strategy brings the race back.

## Export and print

- **Fountain cannot start a scene without a heading**: a headingless scene merges into the one above on export, silently. Any diff that lets a scene exist without a heading needs an answer for export.
- **Nothing is written to disk by design**; the app warns after a week without an export. A diff that touches that warning or the export path is touching the only safety net the data has.
