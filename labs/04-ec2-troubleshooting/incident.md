# Lab 04 — The Incident 🚨

> Read **only this file** first. Try to work it out yourself before you open anything else.
> No hints, no answer here — just what happened.

## The ticket

```
Ticket:    NB-0401
Reporter:  Marco (App team)
Severity:  SEV-2
Title:     "A web server shows healthy in EC2 but it's not serving pages — and
            I don't have an SSH key to get in and look."
```

## What happened

- One of the web servers is **not serving traffic** — the load balancer marks it unhealthy.
- But in the EC2 console the instance says **`running`** with green status checks. It *looks* fine.
- There's **no SSH key** configured for these servers, so Marco can't just log in to investigate.

## See it for yourself

The instance is up at the EC2 level, yet the app on it isn't answering:

```bash
aws ec2 describe-instance-status --instance-ids <instance-id>
```

## Your job

Figure out why a server that AWS calls "healthy" isn't actually serving the app — get in and look
**without** an SSH key — and bring it back to healthy.

## Rules of the game

- `running` and `healthy` are not the same thing. Keep that in mind.
- 🛑 **Don't open `GUIDE.md` yet** — try it cold first. Check your answer after.

---

*Environment deployed and the fault injected? Start diagnosing. If not, see [README.md](README.md).*
