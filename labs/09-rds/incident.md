# Lab 09 — The Incident 🚨

> Read **only this file** first. Try to work it out yourself before you open anything else.
> No hints, no answer here — just what happened.

## The ticket

```
Ticket:    NB-0901
Reporter:  Marco (App team)
Severity:  SEV-1
Title:     "Transfers are failing — the app can't connect to the database.
            Connections just hang and time out."
```

## What happened

- Customers can log in and see balances, but **transfers fail**.
- The app reports it **can't connect to the database** — connection attempts hang, then time out.
- Confusingly, the RDS console shows the database as **Available**. It's up… but the app can't
  reach it.

## See it for yourself

The database says it's healthy:

```bash
aws rds describe-db-instances --db-instance-identifier <db-id> \
  --query 'DBInstances[0].DBInstanceStatus'
# -> available
```

…yet the app's connections to it hang and time out.

## Your job

Work out why an **available** database is **unreachable** from the app, fix it, and confirm the app
can connect again.

## Rules of the game

- First decide: is this "can't reach it" or "reached it and got rejected"? That changes everything.
- 🛑 **Don't open `GUIDE.md` yet** — try it cold first. Check your answer after.

---

*This lab needs the database on (`create_database=true`). Environment ready and the fault injected?
Start diagnosing. If not, see [README.md](README.md).*
