# Lab 13 — The Incident 🚨

> Read **only this file** first. Try to work it out yourself before you open anything else.
> No hints, no answer here — just what happened.

## The ticket

```
Ticket:    NB-1301
Reporter:  Aisha (Security/GRC)
Severity:  SEV-2 / weekly findings backlog
Title:     "Security Hub is lighting up on the banking account. Triage the
            findings, fix the real one, and tell me which are noise."
```

## What happened

- Security Hub / GuardDuty are showing a **pile of findings** on the banking account.
- Some look scary but are just noise; at least one is a **real exposure**.
- The skill here isn't fixing everything — it's **triage**: separate signal from noise, fix what
  matters, and make a clear decision about the rest.

## See it for yourself

There's a wall of active findings to sort through:

```bash
aws securityhub get-findings \
  --filters '{"RecordState":[{"Value":"ACTIVE","Comparison":"EQUALS"}]}'
```

## Your job

Sort the findings by severity, identify the **real** exposure among the noise, **fix** it (least
privilege), and give every other finding a **disposition** (with a reason).

## Rules of the game

- Zero findings isn't the goal. A decision on every finding is.
- 🛑 **Don't open `GUIDE.md` yet** — try it cold first. Check your answer after.

---

*Environment deployed and the fault injected (GuardDuty/Security Hub enabled helps)? Start
diagnosing. If not, see [README.md](README.md).*
