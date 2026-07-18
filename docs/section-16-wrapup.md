# Section 16 — Wrap-Up & Next Steps  (~10m)

> The close. Send them off with a portable model, not a pile of commands. Reference:
> `labs/CHEATSHEET.md`.

---

## Lesson 16.1 — The one-page troubleshooting cheat sheet  [🎬 · ~3m]

You made it through fifteen incidents. Before you go, here's the whole course compressed onto one
page you can print and pin next to your desk.

The heart of it is the triage spine — the thing you run for *any* incident, on any service, even one
you've never seen: **who and where am I → what changed → read the symptom front-door-in → one
hypothesis → test it → smallest fix → verify and communicate.**

Then a handful of rules that will save you over and over:

- **Explicit Deny always wins** (IAM and bucket policies).
- **`running` is not `healthy`** — check the app, not just the instance state.
- **"Available" is not "reachable"** — an RDS that's up isn't the same as an app that can connect,
  and an "available" volume is attached to nothing.
- **Reach vs refuse** is the first question for any datastore — timeout means network, rejection
  means capacity or credentials.
- **Walk the network path in order** — security group → NACL → route → is it listening.
- **A backup you've never restored is a hope, not a backup.**
- **You can't patch what you can't manage** — SSM needs agent, role, and network.
- **Every security finding gets a disposition** — fixed, suppressed with a reason, or accepted with
  an owner.
- **Real incidents have layered causes** — verify after every fix and re-read the symptom.

### Show on screen
- `labs/CHEATSHEET.md` — read the rules aloud; tell them to keep it open on day one.

---

## Lesson 16.2 — The maturity climb: where NorthBank goes next  [🎬 · ~3m]

Think back to the loops from Section 3. Everything you fixed in these labs was a step on the same
climb: from manual and reactive in month one, to automated and proactive by month six.

Look at what changed across the course. We started by learning we were down from a customer complaint
(Lab 01). By Lab 02 the environment paged us on unhealthy hosts. By Lab 03 it paged us on 500s in the
logs. We proved our backups actually restore (Lab 11), put patching on a schedule through change
control (Lab 12), and started dispositioning security findings instead of ignoring them (Lab 13).

That is the maturity climb, made concrete. Every incident you close should leave behind an alarm, a
runbook, or a guardrail — so the next version of that incident is smaller, or never pages a human at
all. NorthBank keeps climbing: more of the platform as code, more automated remediation, tighter
least privilege, cleaner DR drills. The migration finishes, and the operating model it leaves behind
is the real deliverable.

---

## Lesson 16.3 — Your first 90 days on the job  [🎬 · ~3m]

Practical send-off. Here's how to be useful fast without being overwhelmed.

- **Weeks 1–2:** learn to log in the real way, read the board, and shadow on-call. Ask where the
  runbooks live. Run `get-caller-identity` until it's a reflex.
- **Weeks 3–6:** take scoped tickets — access requests, a small alarm, a documented runbook task.
  When an incident happens, watch a senior work it and map what they do onto the triage spine.
- **Weeks 7–12:** take your first on-call shadow, then a real shift. When you fix something, write
  the runbook or add the alarm. That's how you start contributing to the maturity climb, not just
  riding it.

You won't panic on your first real page, because you have the loop: orient, ask what changed, read
front-door-in, one hypothesis, fix, verify, close the loop. That's what the job actually looks like.

---

## Lesson 16.4 — Where the series goes next  [📄 · ~1m]

### 🎙️ Deliver this
- This course is the operations foundation. The same NorthBank platform carries forward into the
  next courses in the series (deeper automation, infrastructure as code, and a full migration arc).
- Thank them, point them at the cheat sheet and the repo, and encourage them to actually build the
  labs in a sandbox — the muscle memory only comes from doing it.
