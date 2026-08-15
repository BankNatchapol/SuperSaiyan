[14:21:36] super-board run started — config=sandbox variant=full base=main tick=20s max_workers=1 backends: build=cursor-agent qa=cursor-agent review=cursor-agent
[14:21:36] worker config path (embedded in every dispatch_lane prompt): /Users/banknatchapol/Desktop/Codes/supersaiyan-gitlab-sandbox/.supersaiyan/configs/sandbox.json
[14:21:37] initial Ready count: 1
[14:21:39] tick — Ready=1 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[14:21:40] claim failed on #10 (race or gh api error) — skipping this tick
[14:23:57] super-board run started — config=sandbox variant=full base=main tick=20s max_workers=1 backends: build=cursor-agent qa=cursor-agent review=cursor-agent
[14:23:57] worker config path (embedded in every dispatch_lane prompt): /Users/banknatchapol/Desktop/Codes/supersaiyan-gitlab-sandbox/.supersaiyan/configs/sandbox.json
[14:23:59] initial Ready count: 2
[14:24:00] tick — Ready=2 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[14:24:02] dispatch lane=build issue=#11 backend=cursor-agent pid=9589 claim=BankNatchapol
[14:25:26] super-board run started — config=sandbox variant=full base=main tick=20s max_workers=1 backends: build=cursor-agent qa=cursor-agent review=cursor-agent
[14:25:26] worker config path (embedded in every dispatch_lane prompt): /Users/banknatchapol/Desktop/Codes/supersaiyan-gitlab-sandbox/.supersaiyan/configs/sandbox.json
[14:25:28] initial Ready count: 1
[14:25:29] tick — Ready=1 Building=0 QA=0 Review=0 Blocked=0 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[14:25:32] dispatch lane=build issue=#10 backend=cursor-agent pid=11532 claim=BankNatchapol
[14:26:27] super-board run started — config=sandbox variant=full base=main tick=20s max_workers=1 backends: build=cursor-agent qa=cursor-agent review=cursor-agent
[14:26:27] worker config path (embedded in every dispatch_lane prompt): /Users/banknatchapol/Desktop/Codes/supersaiyan-gitlab-sandbox/.supersaiyan/configs/sandbox.json
[14:26:28] initial Ready count: 1
[14:26:30] tick — Ready=1 Building=0 QA=0 Review=0 Blocked=1 lanes: b_idle=1(#_) q_idle=1(#_) r_idle=1(#_)
[14:26:30] ⚠ block-rate alert: 1/1 (100%)
[14:26:32] dispatch lane=build issue=#10 backend=cursor-agent pid=13486 claim=BankNatchapol
[14:26:52] tick — cap reached (1/1 busy) — skipping GraphQL fetch, sleeping 20s
[14:27:12] tick — cap reached (1/1 busy) — skipping GraphQL fetch, sleeping 20s
[14:27:32] tick — cap reached (1/1 busy) — skipping GraphQL fetch, sleeping 20s
[14:27:52] tick — cap reached (1/1 busy) — skipping GraphQL fetch, sleeping 20s
[14:28:12] tick — cap reached (1/1 busy) — skipping GraphQL fetch, sleeping 20s
[14:28:32] tick — cap reached (1/1 busy) — skipping GraphQL fetch, sleeping 20s
[14:28:54] tick — Ready=0 Building=0 QA=1 Review=0 Blocked=1 lanes: b_idle=1(#10) q_idle=1(#_) r_idle=1(#_)
[14:28:56] dispatch lane=qa issue=#10 backend=cursor-agent pid=17368 claim=BankNatchapol
[14:29:16] tick — cap reached (1/1 busy) — skipping GraphQL fetch, sleeping 20s
[14:29:36] tick — cap reached (1/1 busy) — skipping GraphQL fetch, sleeping 20s
[14:29:56] tick — cap reached (1/1 busy) — skipping GraphQL fetch, sleeping 20s
[14:30:16] tick — cap reached (1/1 busy) — skipping GraphQL fetch, sleeping 20s
[14:30:36] tick — cap reached (1/1 busy) — skipping GraphQL fetch, sleeping 20s
[14:30:56] tick — cap reached (1/1 busy) — skipping GraphQL fetch, sleeping 20s
[14:31:16] tick — cap reached (1/1 busy) — skipping GraphQL fetch, sleeping 20s
[14:31:36] tick — cap reached (1/1 busy) — skipping GraphQL fetch, sleeping 20s
[14:31:56] tick — cap reached (1/1 busy) — skipping GraphQL fetch, sleeping 20s
[14:32:17] reaped stale lock + swept assignee on #10 (pid=17368)
[14:32:18] tick — Ready=0 Building=0 QA=0 Review=1 Blocked=1 lanes: b_idle=1(#10) q_idle=1(#10) r_idle=1(#_)
[14:32:21] dispatch lane=review issue=#10 backend=cursor-agent pid=21848 claim=BankNatchapol
[14:32:41] tick — cap reached (1/1 busy) — skipping GraphQL fetch, sleeping 20s
[14:33:01] tick — cap reached (1/1 busy) — skipping GraphQL fetch, sleeping 20s
[14:33:21] tick — cap reached (1/1 busy) — skipping GraphQL fetch, sleeping 20s
[14:33:41] tick — cap reached (1/1 busy) — skipping GraphQL fetch, sleeping 20s
[14:34:01] tick — cap reached (1/1 busy) — skipping GraphQL fetch, sleeping 20s
[14:34:21] tick — cap reached (1/1 busy) — skipping GraphQL fetch, sleeping 20s
[14:34:41] tick — cap reached (1/1 busy) — skipping GraphQL fetch, sleeping 20s
[14:35:01] tick — cap reached (1/1 busy) — skipping GraphQL fetch, sleeping 20s
[14:35:21] tick — cap reached (1/1 busy) — skipping GraphQL fetch, sleeping 20s
[14:35:41] tick — cap reached (1/1 busy) — skipping GraphQL fetch, sleeping 20s
[14:36:01] tick — cap reached (1/1 busy) — skipping GraphQL fetch, sleeping 20s
[14:36:21] tick — cap reached (1/1 busy) — skipping GraphQL fetch, sleeping 20s
[14:36:42] tick — Ready=0 Building=0 QA=0 Review=0 Blocked=1 lanes: b_idle=1(#10) q_idle=1(#10) r_idle=1(#10)
[14:36:42] ✅ all active-pipeline columns empty and all lanes idle — exiting cleanly
[14:36:42] super-board run finished. manifest: docs/supersaiyan/runs/2026-08-15-sandbox.md
