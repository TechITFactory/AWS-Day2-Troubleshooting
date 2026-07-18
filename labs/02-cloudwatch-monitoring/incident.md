# Lab 02 — The Incident 🚨

> Read **only this file** first. Try to work it out yourself before you open anything else.
> No hints, no answer here — just what happened.

## The ticket

```
Ticket:    NB-0201
Reporter:  Priya (Team lead)
Severity:  SEV-3  (post-incident action)
Title:     "The alarm we added after last week's outage never fired during our
            failover test. Find out why."
```

## What happened

- After last week's 503 outage (NB-0101), Priya added a CloudWatch alarm called
  **`northbank-unhealthy-hosts`** so we'd get paged automatically next time.
- The team then ran a **failover test** — they deliberately made the targets unhealthy to check
  the alarm.
- The alarm **stayed green.** No page. No email. It never changed state.
- A monitor you can't trust is worse than no monitor — it gives false comfort.

## See it for yourself

The alarm exists and looks configured — yet it did nothing while the environment was broken:

```bash
aws cloudwatch describe-alarms --alarm-names northbank-unhealthy-hosts
```

## Your job

Explain **why** the alarm never fired, rebuild it so it's **trustworthy** (and actually pages
someone), and **prove it works** by testing it.

## Rules of the game

- Have a reason for every command you run.
- 🛑 **Don't open `GUIDE.md` yet** — try it cold first. Check your answer after.

---

*Environment deployed and the fault injected? Start diagnosing. If not, see [README.md](README.md).*
