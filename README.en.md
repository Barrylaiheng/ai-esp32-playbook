# Building ESP32 Firmware with an AI Agent: A Repeatable Engineering Path

**[中文全文](./README.md) · English (condensed)**

> I built a real ESP32-S3 product firmware from scratch on Windows, driven by an AI coding assistant.
> This is not an enthusiastic "AI wrote my code" post — it is the record of turning that into a **stable pipeline**:
> the two fatal traps I hit, the 10 wrong hypotheses I disproved, and the six disciplines I ended up with.

![AI Agent](https://img.shields.io/badge/AI%20Agent-WorkBuddy-FF8C42)
![ESP-IDF](https://img.shields.io/badge/ESP--IDF-v6.0.1-blue)
![Target](https://img.shields.io/badge/target-ESP32--S3-green)
![Host](https://img.shields.io/badge/host-Windows%2010-0078D4)
![Docs](https://img.shields.io/badge/docs-MIT-lightgrey)
[![docs-check](https://github.com/Barrylaiheng/ai-esp32-playbook/actions/workflows/docs-check.yml/badge.svg)](https://github.com/Barrylaiheng/ai-esp32-playbook/actions/workflows/docs-check.yml)

> **What this method produced:** [`folo-ai-passport-voice-agent`](https://github.com/Barrylaiheng/folo-ai-passport-voice-agent)
> is an open-source project built on the discipline in section 6 and the Windows child-process rules
> above (compare its `AGENTS.md`). The ESP32-S3 product firmware itself (`dada-launcher`) is not
> open source — every screenshot and log in this repo comes from it.

> ⚠️ **The Chinese README is the source of truth.** This English page is a condensed version:
> conclusions, checklist and templates only. For the full narrative, evidence and the 10 disproved
> hypotheses, read [`README.md`](./README.md) (a translation tool gets you there fine).

---

## Who this is for

You drive embedded work with **WorkBuddy / Cursor / Claude Code / Codex** and you have noticed that
AI makes *writing* code fast but *making it run* is still where the days go. This repo is about the
second half: environment, build, verification and organization.

## The six stages at a glance

| Stage | What it covers | The one thing that matters |
| --- | --- | --- |
| 1 · Environment | Pin ESP-IDF / toolchain / Python env | Pin versions **with a reason**, never "latest" |
| 2 · Build | Never let the build descend from the assistant | A **resident build daemon**; the agent only drops a request file |
| 3 · Flash & verify | Bench evidence only | Give the agent **assert-like logs**, plus a merged image and one-click flash |
| 4 · UI | LVGL screenshot loop | edit → render → screenshot → **agent reviews it** → repeat. No blind edits |
| 5 · Component reuse | Vendor third-party code safely | **License first, hidden dependencies second** |
| 6 · Agent contract | `AGENTS.md` at repo root | Four-section delivery; `Unverified` must be specific |

## Trap #1 · The build that hung forever

**Symptom:** full builds launched by the AI assistant hang indefinitely — `gcc` threads sit in
`Suspended`, no error, no CPU, no disk activity. Launched by double-clicking the same script, it
always finishes.

**Root cause:** the AI host's **child-process sandbox** suspends compiler threads. The only variable
was *how the build was launched* — not antivirus, not drivers, not concurrency.

**Fix:** move the build into a resident daemon started once by a human, outside the sandbox.
The agent writes `build.request` (`full` / `inc`) and polls `build.status` until `DONE`.
**It never spawns a process — zero lineage to the build.**

> Diagnostic rule of thumb: for any "environment voodoo", run a **launch-method A/B test** first.
> And when you see a `Suspended` thread, ask **"who is the parent?"** before suspecting antivirus.

## Trap #2 · The hidden console inherited as stdin

Inside a hidden-window background service, `cmd.exe` launching `ninja` directly hands the hidden
console to the child as stdin — `ldgen` then dies **silently** with `errorcode -1`.

Fix: launch the child with **`stdin=DEVNULL`** (see `templates/daemon/run_ninja.py`).
The same lesson shows up again for any console child spawned from a GUI/no-console parent:
always pass `CREATE_NO_WINDOW` **and** redirect stdin/stdout/stderr.

## Conclusions

1. AI made writing code fast; it did not make "making it run" simple. The bottleneck moved to environment, build, verification and organization.
2. **Never let the AI assistant be an ancestor of the build process.** That was the whole hang.
3. The first diagnostic for "environment voodoo" is a **launch-method A/B test**.
4. Seeing `Suspended`, ask **"who is the parent?"** first. Suspecting antivirus cost me a day.
5. **Move the build into a resident daemon**; the agent only writes a request file and polls a status file.
6. In hidden-window builds, set the child's **stdin to `DEVNULL`** — otherwise `ldgen` dies silently.
7. Keep `cmd.exe` scripts **100% ASCII**. On zh-CN Windows they are parsed as GBK and non-ASCII bytes get executed as commands.
8. **UI iteration must close the loop until the agent can see it**: edit → render → screenshot → review → repeat.
9. Before reusing a component: **check its license, then hunt for hidden dependencies** its CMakeLists never declared.
10. **Humans own architecture and acceptance; the agent owns typing.** Anything that ships wrong is the human's responsibility.

## Reusable checklist

**Diagnosing "environment voodoo"**

- [ ] Always start with a **launch-method A/B test** (manual vs via the AI's tools).
- [ ] Seeing `Suspended`, ask **"who is the parent?"** first — not antivirus.
- [ ] Before accusing third-party software, demand **its own log evidence**.
- [ ] Drop any hypothesis that can't explain "why does changing the launch method fix it?".

**Designing an AI-driven build chain**

- [ ] Make sure the build's ancestor is **not** the AI assistant (daemon / scheduled task / service).
- [ ] The agent should only **drop files and poll status** — never spawn the build.
- [ ] Hidden-window builds: set the child's **stdin to `DEVNULL` / `NUL`**.
- [ ] Prefer "minimized" (style `7`) over "fully hidden" (style `0`).
- [ ] The daemon must be launchable by a **human** once, outside the sandbox, and auto-start at logon.
- [ ] Express state as **files** (simple, observable, protocol-free).

**Windows + ESP-IDF**

- [ ] `cmd.exe` script comments: **ASCII only**.
- [ ] `idf.py` does **not** accept `-j`; use `idf.py reconfigure` then drive ninja.
- [ ] Toolchain version must **match** the IDF version exactly.
- [ ] Long tasks: **redirect to a file**, never pipe through `| tail` (buffering).
- [ ] Freeze environment variables into **one script**.

**Working with an AI**

- [ ] `AGENTS.md` at repo root; the AI reads it before acting.
- [ ] Four-section delivery; `Unverified` must be specific.
- [ ] UI changes **must** be screenshot-checked — no blind edits.
- [ ] Before reusing third-party code: **license → architectural separability → hidden dependencies**.
- [ ] After major incidents, write a **public post-mortem** and distill it into a checklist.
- [ ] One milestone per plan execution; on failure **go back to planning**.

## Templates

| File | Usage |
| --- | --- |
| [`templates/AGENTS.md`](templates/AGENTS.md) | Copy to your repo root; fill in "what this repo is / directory conventions / environment notes" |
| [`templates/daemon/`](templates/daemon/) | The six daemon files. **Replace the placeholders at the top of each file**, then double-click `install-build-daemon.cmd` once |
| [`templates/mcp.example.json`](templates/mcp.example.json) | How to configure an MCP client (knowledge source and action source separately) |

```
One-time : double-click install-build-daemon.cmd   (resident from every logon afterwards)
Daily    : agent writes build.request = "inc" | "full"
           daemon builds → writes build.status
           agent polls build.status until DONE → reads build.log
```

Full walkthroughs (Chinese): [`docs/01-build-hang-postmortem.md`](docs/01-build-hang-postmortem.md) ·
[`docs/02-ui-simulator-workflow.md`](docs/02-ui-simulator-workflow.md) ·
[`docs/03-component-reuse.md`](docs/03-component-reuse.md).

## Known limitations

1. The sandbox phenomenon was verified on **WorkBuddy + Windows 10**. Mechanically, any agent host that manages child processes could hit it, but **I only measured it there**.
2. The daemon contract is **file polling, not events** — ~2 s latency, in exchange for zero dependencies and zero protocol.
3. **Windows always costs more than Linux** for embedded work (drivers, codepages, process management).
4. This document does not address "quality of AI-generated code" as a philosophy. My position: the human is accountable; quality is enforced by `AGENTS.md`, four-section delivery and on-device verification — not by hope.

## Contributing

Pitfalls are the most valuable contribution. Open an issue with the
[pitfall template](.github/ISSUE_TEMPLATE/pitfall.yml) — "have you reproduced it?" is a required field.
See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — text and templates. Attribution appreciated, not required.
