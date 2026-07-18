# Lab 05 — The Incident 🚨

> Read **only this file** first. Try to work it out yourself before you open anything else.
> No hints, no answer here — just what happened.

## The ticket

```
Ticket:    NB-0501
Reporter:  Marco (App team)
Severity:  SEV-2
Title:     "Our app suddenly gets 'Access Denied' writing customer statements to
            its S3 bucket. We didn't change anything!"
```

## What happened

- The banking app runs on EC2 and writes customer statements to an S3 bucket.
- Those writes **worked yesterday**. Today they fail with **`AccessDenied`**.
- Marco insists nothing changed on the app side — but *something* changed. Your job is to find what.

## See it for yourself

Trying to write to the bucket (from an instance, or with the same role) returns a denial:

```bash
echo hi > /tmp/x && aws s3 cp /tmp/x s3://<bucket>/x
# -> AccessDenied
```

## Your job

Explain **why** the write is denied — exactly which rule is blocking it — and fix it so the app
can write again, **without** handing out more access than it needs.

## Rules of the game

- Read the denial before you touch any policy. It tells you who, what, and where.
- 🛑 **Don't open `GUIDE.md` yet** — try it cold first. Check your answer after.

---

*Environment deployed and the fault injected? Start diagnosing. If not, see [README.md](README.md).*
