# Multi-Account SSO Demo — options (planning notes)

Note before reading: this file is a planning document, not something already built. The actual
scripts in access/, `00-bootstrap-NOTES.md`, and the delivery narration all use the simple
option — one sandbox account, two roles. Nothing here about a real 5-account org has been set
up or tested. Treat this as "here's a fancier version you could build later," not a step you
need to do.

## The problem this is solving

Students in a personal sandbox can't easily spin up 5 real AWS accounts — that needs 5 emails,
sometimes 5 cards on file, and time to wire up an Organization. But at a real company, that's
exactly what the login screen looks like: many accounts, one identity.

## Option 1 — a real 5-account setup (what the course demo shows)

The course demo uses a full 5-account setup created once — that is the "this is what it
really looks like" moment.

One-time setup (about 30 minutes): create 5 member accounts under one AWS Organization
(management, security, logging, prod, nonprod), enable Identity Center in the management
account, create three permission sets (PowerUserAccess for nonprod, ReadOnlyAccess for prod,
SecurityAuditor for the security account), then create one test user and assign it to all 5
accounts with the right role in each.

What you'd show: the Identity Center portal with 5 tiles, one per account. Click
"nonprod," the console opens with PowerUserAccess. Click "prod," it opens with ReadOnlyAccess
instead. Same person, different permissions depending on which account they're in. Then show
the CLI side — five profiles in `~/.aws/config`, each pointing at a different account and
role, and run `aws sts get-caller-identity` against a couple of them to prove it live. A nice
closing beat: try `aws s3 mb s3://test-bucket` against the nonprod profile (succeeds) and the
prod profile (fails with Access Denied, because that role is read-only).

Ongoing cost: roughly $5/month to keep 5 mostly-empty accounts sitting around for future
use.

## Option 2 — simulate accounts with roles inside one account

Students create several IAM roles inside their single account (with names like
`Nonprod-PowerUser`, `Prod-ReadOnly`, `Security-Auditor`) and switch between them with
`aws sts assume-role`.

This works fine in one account and does teach the assume-role mechanics, but it's not really
multi-account, and it skips the Identity Center portal experience entirely — which is the part
that actually surprises new hires.

## Option 3 — hybrid (this is the one worth doing, if you ever build it out)

You record a short video segment showing your own real 5-account setup (so students see the
real thing), then students build a simplified single-account version themselves using the
access/ scripts.

Video segment: show your 5-account Identity Center portal, show billing rolled up per account
in Cost Explorer, show the AWS Organizations console listing all 5. Say plainly: "this is the
full enterprise setup."

Hands-on part: students run the access/ scripts in their own one-account sandbox, create two
permission sets (PowerUser and ReadOnly), and assign both to that same account — so
`~/.aws/config` ends up with two profiles pointing at the same account ID but different roles,
simulating the nonprod/prod split without needing separate accounts.

Either way, the point to make is this: in the video you showed 5 accounts because that's what
a real job looks like. In the sandbox it's one account with two roles instead. The login
mechanics — SSO, permission sets, assume-role, sessions expiring — are identical. The account
count scales up at a real job; the muscle memory being built right now is the same.

## If you decide to build this later

- Set up the 5-account demo org once
- Record the console + CLI walkthrough described in Option 3
- Update `00-bootstrap-NOTES.md` to reference it
- Test the student-facing scripts fresh, in a clean single sandbox account
- Add an FAQ answer for "why can't I create 5 accounts like in the video?"
