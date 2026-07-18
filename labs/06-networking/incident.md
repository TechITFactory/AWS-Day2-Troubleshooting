# Lab 06 — The Incident 🚨

> Read **only this file** first. Try to work it out yourself before you open anything else.
> No hints, no answer here — just what happened.

## The ticket

```
Ticket:    NB-0601
Reporter:  Marco (App team)
Severity:  SEV-1
Title:     "Internet banking is timing out. Requests to the app just hang, then
            fail. Network problem?"
```

## What happened

- Internet banking **hangs and then times out** for customers.
- The load balancer shows **all targets unhealthy** — but the web servers themselves look fine
  (they're running, and the app works when you check it on the box).
- So traffic isn't *reaching* the app. Something in the network path is blocking it.

## See it for yourself

The site doesn't respond — it just hangs until it times out:

```bash
curl -i --max-time 15 http://<alb-dns-name>/
```

## Your job

Find the **one hop** in the network path that's blocking traffic, fix it with the **narrowest**
rule possible, and confirm the site recovers.

## Rules of the game

- Walk the path methodically — don't start opening ports at random.
- 🛑 **Don't open `GUIDE.md` yet** — try it cold first. Check your answer after.

---

*Environment deployed and the fault injected? Start diagnosing. If not, see [README.md](README.md).*
