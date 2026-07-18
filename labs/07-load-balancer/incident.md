# Lab 07 — The Incident 🚨

> Read **only this file** first. Try to work it out yourself before you open anything else.
> No hints, no answer here — just what happened.

## The ticket

```
Ticket:    NB-0701
Reporter:  Priya (Team lead)
Severity:  SEV-2
Title:     "The ALB says every target is unhealthy, but I can curl the app on
            the instances directly and it works. What's going on?"
```

## What happened

- The load balancer marks **every** target unhealthy, so the site is down.
- But the instances are up, the web service is running, and curling the app **on the box** works
  fine.
- So the app is healthy — yet the load balancer refuses to send it traffic.

## See it for yourself

The load balancer's own view of the targets says they're all unhealthy:

```bash
aws elbv2 describe-target-health --target-group-arn <tg-arn>
```

## Your job

Work out why a **healthy** app is being marked unhealthy, fix it, and get the targets back to
healthy — without touching the app itself.

## Rules of the game

- The load balancer will tell you *why* it thinks a target is unhealthy. Read that first.
- 🛑 **Don't open `GUIDE.md` yet** — try it cold first. Check your answer after.

---

*Environment deployed and the fault injected? Start diagnosing. If not, see [README.md](README.md).*
