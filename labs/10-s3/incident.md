# Lab 10 — The Incident 🚨

> Read **only this file** first. Try to work it out yourself before you open anything else.
> No hints, no answer here — just what happened.

## The ticket

```
Ticket:    NB-1001
Reporter:  Marco (App team)
Severity:  SEV-2
Title:     "Reading customer statements from the S3 bucket suddenly returns 403
            Access Denied. Downloads worked yesterday."
```

## What happened

- The app reads customer statements from an S3 bucket.
- Yesterday it worked. Today, reading an object returns **403 AccessDenied**.
- Something in the bucket's permissions changed. You need to find it and fix it **without** making
  the bucket public.

## See it for yourself

Reading an object from the bucket now fails:

```bash
aws s3 cp s3://<bucket>/statements/2026-06/customer-12345.txt -
# -> 403 AccessDenied
```

## Your job

Work out **what** is blocking the read, fix it so objects can be read again, and keep the bucket
locked down (never public).

## Rules of the game

- S3 access is decided by more than one thing. Walk them, don't guess.
- 🛑 **Don't open `GUIDE.md` yet** — try it cold first. Check your answer after.

---

*Environment / fault set up (this lab is standalone — `break.sh` makes the bucket)? Start
diagnosing. If not, see [README.md](README.md).*
