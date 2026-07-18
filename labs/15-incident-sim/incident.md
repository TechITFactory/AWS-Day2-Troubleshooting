# Lab 15 — The Incident 🚨 (Capstone)

> Read **only this file** first. This is the final exam — try to work it fully on your own.
> No hints, no answer here — just what happened.

## The ticket

```
Ticket:    NB-1501
Reporter:  PagerDuty (automated) → you are on-call
Severity:  SEV-1
Title:     "Internet banking is DOWN. Customers can't log in or move money.
            The clock is running."
```

## What happened

- The pager just went off. It's the middle of the night and **you're on call.**
- Internet banking is **down** — customers can't log in or move money.
- This is the real thing: unlike the earlier labs, **more than one thing is broken.** Fixing the
  first problem you find will **not** bring the service all the way back.

## See it for yourself

```bash
curl -i http://<alb-dns-name>/
# -> HTTP/1.1 503 Service Temporarily Unavailable
```

## Your job

Get NorthBank internet banking **fully** healthy again — the homepage loads **and** customers can
actually complete a transfer — then write up what went wrong.

## Rules of the game

- **Fix one thing, verify, then re-read the symptom** before touching the next. Don't assume one
  fix solved everything.
- One hypothesis at a time. Under a SEV-1, changing five things at once turns one incident into
  three.
- 🛑 **Don't open `GUIDE.md` yet** — this is the exam. Try it cold; check after.

---

*This lab needs the full stack including the database (`create_database=true`). Set up and faults
injected? Work the incident. If not, see [README.md](README.md).*
