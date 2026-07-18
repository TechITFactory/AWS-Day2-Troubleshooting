# Lab 01 — The Incident 🚨

> Read **only this file** first. Try to work it out yourself before you open anything else.
> No hints, no answer here — just what happened.

## The ticket

```
Ticket:    NB-0101
Reporter:  Marco (App team)
Severity:  SEV-1  (customer-facing outage)
Title:     "Customers can't reach internet banking — site returns 503"
```

## What happened

- It's **09:40**. You're on the NorthBank Cloud Platform team.
- Marco messages the channel: *"Internet banking is **down** — customers are getting a 503.
  Nothing changed on our side."*
- Customers can't log in or move money. The clock is running.

## See it for yourself

Open the banking URL (or curl it):

```bash
curl -i http://<alb-dns-name>/
```

```
HTTP/1.1 503 Service Temporarily Unavailable
```

The site really is returning **503**.

## Your job

Get NorthBank internet banking healthy again — back to a **200** — and be able to say **what
went wrong** and **what you changed to fix it**.

## Rules of the game

- Work the **first five minutes** like a real on-call engineer: orient before you act.
- Don't guess-and-poke. Have a reason for every command you run.
- 🛑 **Don't open `GUIDE.md` yet** — try it cold first. Check your answer after.

---

*Environment already deployed and the fault injected? Good — start diagnosing. If not, see
[README.md](README.md) for setup.*
