# Lab 12 — The Incident 🚨

> Read **only this file** first. Try to work it out yourself before you open anything else.
> No hints, no answer here — just what happened.

## The ticket

```
Ticket:    NB-1201
Reporter:  Aisha (Security/GRC)
Severity:  SEV-3 / weekly patch review
Title:     "Web servers are missing critical patches — and some instances have
            vanished from Systems Manager entirely. Patch them, via a
            maintenance window."
```

## What happened

- The weekly patch-compliance report says the web servers are **missing critical patches.**
- Worse: some instances have **completely disappeared** from Systems Manager. They don't even show
  up to be managed or patched.
- You can't patch what you can't see — so first you have to get them back under management.

## See it for yourself

The web servers aren't in the managed-instances list:

```bash
aws ssm describe-instance-information \
  --query 'InstanceInformationList[].{Id:InstanceId,Ping:PingStatus}'
```

## Your job

Find out **why** the instances dropped out of Systems Manager, get them back, then run a patch
**scan** and remediate through a **maintenance window** (not an ad-hoc patch of prod).

## Rules of the game

- Systems Manager needs a few specific things from an instance. Which one is missing?
- 🛑 **Don't open `GUIDE.md` yet** — try it cold first. Check your answer after.
- (Give it a few minutes after setup — dropped instances take a moment to disappear.)

---

*Environment deployed and the fault injected? Start diagnosing. If not, see [README.md](README.md).*
