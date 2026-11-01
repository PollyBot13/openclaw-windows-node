# Current runtime proof for PR #1968

Product head: `c98608cf0dd934d3a29ff79111ec2c65da6f8a4c`.
Tree: `1881b78edf3334d473e155733c3e8f58e4b94eca`.
Collected on Windows x64, 2026-11-01. No production source changes were made for these checks. Existing build/test/source-review evidence remains in the separate narrowed-proof package.

## Results and limits

| Check | Observed result | Limit |
|---|---|---|
| Fish Read Aloud | Native chat action, actual UI provider `fish-audio`, target process rendered audio | Current-run human audibility confirmation pending |
| Fish automatic reply | Automatic voice enabled through native UI; synthetic reply rendered without clicking Read Aloud; UI identified `fish-audio` | Current-run human confirmation pending; automatic voice was turned back off |
| Fish early Stop | Counting passage rendered; native Stop returned the control to Read Aloud; subsequent measured window had no active or above-threshold render samples | Human confirmation that counting stopped before forty pending |
| Issued read-only principal | Actual `operator.read` hello, working `tts.status`, production-client preflight `PermissionRequired`, separate real Gateway denial, no provider invocation in either negative | Current product assemblies in a helper; not a shipped-UI refusal or Fish check |
| Permission revoke/restore | Persisted revoke closed the original authenticated transport. Held audio could not be forwarded. Restore did not replay; a fresh explicit request rendered on a new connection | Does not prove late bytes were delivered on the revoked connection |
| Stop before late response | Genuine successful WAV held; native Stop confirmed; unchanged bytes forwarded on the still-open original connection; measured silence; fresh request rendered on that same connection | Send completion is not direct observation of app JSON parsing; subsequent ordered recovery supports consumer-advancement inference |
| Old application/data upgrade | Official signed v2026.9.8-1 portable application wrote a synthetic Windows-provider profile; current app loaded identical old settings bytes and retained that provider/preferences, defaulting Gateway voice off | One profile; not installer/MSIX or every-provider upgrade proof |

All audio observers reported zero query errors. They inspect only target-PID render-session state and peak metadata: no recording, microphone access, volume change, or unrelated endpoint details. Their zero samples establish bounded render absence, not a native playback API invocation count. Compact observer reports preserve metadata, transitions and phase statistics. Individual samples remain in the local originals bound by SHA256.

## Artifact map

- `build-identity.json` records the frozen product build. `loaded-*-binaries.json` binds live processes to its four module hashes. Preparation-time `automaticSpeechEnabled=false` is not a claim that automatic voice stayed off during its explicit check.
- `A-*` contains filtered native UI output, screenshots, measured Fish results and current human-confirmation status. The remote Gateway address, profiles and credentials are excluded.
- `B/current-verified-run.json` contains the provenance-strengthened real authorization run. Positive synthesis moved the synthetic backend counter 1→2; both denials left it at 2. `B/helper-build-provenance.json` records the exact helper and product association. The broader original ledger retains earlier runs and setup attempts locally.
- `C-correlated-events.json` preserves speech request/response identities and hashes and every connection open/close event between the first positive and final recovery. C uses a disposable real Gateway (`2026.10.10-beta.3`, `15dffe5`), a transparent relay and local synthetic OpenAI-compatible backend returning the same 128,044-byte, four-second 660 Hz WAV. It is not a Fish provider test. The relay forwards protocol bytes without rewriting authentication or speech payloads.
- `C-outcomes.json` distinguishes permission-driven transport retirement from same-connection Stop retirement. Permission-only settings classify as `CapabilityReload`, whose existing coordinator reconnects. Native Permissions, tray and MCP writers share that production path; no permission field or normal reconnect was bypassed to manufacture a test topology.
- C2 held request `a78acf80…` was forwarded at `13:23:44.255Z`, about 34.4 seconds after its genuine response was held and within the synthesis deadline. The no-replay phase spans about 16.7 seconds, 269 samples, with zero active/above-threshold samples. Fresh request `3d2012c8…` rendered on the same connection with 65 active and 65 above-threshold samples.
- `old-release-*` are preparation/download identity snapshots (their `executed=false` was true at capture). The later `upgrade-windows-*-loaded-binaries.json` records actual execution of the old and current applications. No release binaries are included.
- The original failed unchanged-Piper assertion remains in `upgrade-migration-attempt001.json`. `upgrade-piper-disposition.json` explains the intentional unchanged-main migration of schema-v1 Piper without downloaded assets to Kokoro. Downloaded-Piper runtime upgrade was not exercised.

## Still unresolved

Current human listening confirmations, maintainer ownership/decision for the default-off opt-in, dependency #1949 landing, and the required hosted CI investigation/retry. The old full-CI UI-host crash remains unclassified; a local main control also crashed, but that does not establish the same root cause. Repository-admin retry was denied by GitHub. No Diamond rating or merge readiness is claimed.

These files contain synthetic task data and sanitized proof only. Raw paired profiles, setup codes, credentials, histories, non-public hostnames, release binaries and private state locators are excluded.
