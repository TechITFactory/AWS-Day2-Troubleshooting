# Lab 08 — The Incident 🚨

> Read **only this file** first. Try to work it out yourself before you open anything else.
> No hints, no answer here — just what happened.

## The ticket

```
Ticket:    NB-0801
Reporter:  Priya (Team lead)
Severity:  SEV-2
Title:     "We lost a web instance overnight and Auto Scaling never replaced it.
            We're running below capacity and nobody got a new box."
```

## What happened

- An Auto Scaling group is supposed to **self-heal** — lose a server, get a new one automatically.
- Overnight a web server died. **No replacement was launched.**
- We're now running with **one** instance instead of two, and it's been that way for hours. No
  alarm, no error — it just quietly stopped healing.

## See it for yourself

The group is sitting below the capacity it's supposed to keep:

```bash
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names <asg-name>
```

## Your job

Find out **why** the group won't replace the missing instance, restore self-healing, and watch
capacity climb back to where it should be.

## Rules of the game

- When a group won't heal, ask what would stop it from acting at all.
- 🛑 **Don't open `GUIDE.md` yet** — try it cold first. Check your answer after.

---

*Environment deployed and the fault injected? Start diagnosing. If not, see [README.md](README.md).*
