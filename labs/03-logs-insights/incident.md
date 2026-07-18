# Lab 03 — The Incident 🚨

> Read **only this file** first. Try to work it out yourself before you open anything else.
> No hints, no answer here — just what happened.

## The ticket

```
Ticket:    NB-0301
Reporter:  Marco (App team)
Severity:  SEV-2
Title:     "Some banking transfers are failing on and off. The app just logs
            errors — we can't tell what's going on."
```

## What happened

- Customers report that **some** transfers fail — not all of them, and not every time.
- It's **intermittent**, so you can't reproduce it by clicking around.
- Nothing is obviously down. The only trail is a pile of application logs in CloudWatch.

## See it for yourself

The app ships its logs to a CloudWatch **log group** called `/northbank/app`. Somewhere in there
is the pattern behind the failures.

## Your job

Find out **which** requests are failing and the **common cause** behind them — using the logs, not
guesswork. Then say how you'd make this get noticed automatically next time.

## Rules of the game

- Don't `grep` on one box — the answer is a *pattern* across all of them.
- 🛑 **Don't open `GUIDE.md` yet** — try it cold first. Check your answer after.

---

*Environment deployed and the fault injected? Start diagnosing. If not, see [README.md](README.md).*
