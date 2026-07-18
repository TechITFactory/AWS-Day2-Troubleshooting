# Lab 14 — The Task 📋

> Read **only this file** first. This one is a monthly cost task, not a break/fix incident.
> Try it yourself before you open anything else.

## The ticket

```
Ticket:    NB-1401
Reporter:  Tom (Finance)
Severity:  Task (monthly cost review)
Title:     "The banking account's bill went up this month. Find what's driving
            it and bring it back down."
```

## What's being asked

- Finance says the banking account's bill is **up this month** — and Tom doesn't know why.
- He can see the total went up; he can't see **what's driving it.** Now it's your ticket.
- Somewhere there's **waste**: something allocated or running that nobody is actually using.

## The starting point

- Everything in the account is tagged `Project=NorthBank`, so spend is attributable.
- The usual culprits are things that quietly cost money while doing nothing.

## Your job

Track down the **wasteful resources**, confirm they're truly unused, remove them, and set up a
guardrail so a spike **pages you** before it reaches Finance next time.

## Rules of the game

- "Available" and "unattached" often mean "costing money for nothing." Go look there.
- Confirm before you delete — don't destroy something that's only *temporarily* detached.
- 🛑 **Don't open `GUIDE.md` yet** — try it cold first. Check your answer after.

---

*Fault set up (`break.sh` creates the waste)? Start hunting. If not, see [README.md](README.md).*
