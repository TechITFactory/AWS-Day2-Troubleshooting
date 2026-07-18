# Lab 11 — The Task 📋

> Read **only this file** first. This one isn't a break/fix incident — it's a monthly task.
> Try it yourself before you open anything else.

## The ticket

```
Ticket:    NB-1101
Reporter:  Aisha (Security/GRC)
Severity:  Task (monthly compliance loop)
Title:     "Audit needs evidence our banking DB backups actually work. Do a real
            restore test this month and capture the proof."
```

## What's being asked

- Compliance needs **proof** that the banking database's backups can actually be restored — not
  just that backups *exist*.
- A backup you've never restored is a hope, not a backup. So this month you run a **real restore
  test.**
- You'll bring a backup back to life, confirm it's good, and capture evidence for the auditor.

## The starting point

- Backups are configured on the database. There's a snapshot to restore from.
- Existing ≠ restorable — that's exactly what you're going to prove.

## Your job

**Restore a snapshot to a brand-new database**, confirm it comes up healthy, capture the evidence
(snapshot ID, timestamps, how long it took), then clean up the restore.

## Rules of the game

- **Never** restore over the original — always to a new instance.
- This lab uses a real RDS database — tear the restore (and the DB) down when you're done.
- 🛑 **Don't open `GUIDE.md` yet** — try it cold first. Check your answer after.

---

*This lab needs the database on (`create_database=true`). Set up? Start the restore. If not, see
[README.md](README.md).*
