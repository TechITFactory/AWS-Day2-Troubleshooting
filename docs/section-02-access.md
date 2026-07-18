# Section 2 — Real-World AWS Access  (~22m)  🎁 FREE PREVIEW

---

## Lesson 2.1 — Root/admin vs how the job logs in  [🎬 · ~2m · 🎁]

Almost every AWS tutorial teaches you to log in as root, or create one admin user, in one account, and start clicking. And then you get a real job — and none of it looks like that.

At work you don't have a root password. You log in through a company portal, you get dropped into one of dozens of accounts, and the permissions you have are deliberately less than the person sitting next to you. The single biggest thing that trips up new hires isn't a service — it's just logging in the way the job actually does it.

Here's the gap between practice and reality:

| Practice (every tutorial) | Reality (every job) |
|---------------------------|----------------------|
| One root login | No root day-to-day — it's locked in a safe |
| One account | Many accounts (Prod, Non-Prod, Security, Logging…) |
| One admin user | You assume a role; least privilege |
| Static access keys in a file | Short-lived SSO sessions that expire |

You've been practicing in a garage. The job is a car factory. Same tools, different scale — and the way you get in the door is completely different.

By the end of this section you'll have set up real Single Sign-On, across multiple accounts, with roles — the same mechanics a bank like NorthBank uses — in your own account. Let's close that gap.

---

## Lesson 2.2 — Why companies use many accounts  [🎬 · ~3m]

NorthBank doesn't run everything in one account. It uses **AWS Organizations** to split into many accounts on purpose.

There are three main reasons:

**Blast radius** — a mistake in the test environment can't touch production. Accounts are the hard boundary. If someone accidentally deletes a bunch of resources in nonprod, production keeps running. The isolation is absolute.

**Separation of duties** — security and logging live in their own accounts so even a production admin can't quietly delete the audit trail. Auditors love this. Regulators require it. If CloudTrail logs live in a separate logging account with restricted access, nobody can cover their tracks.

**Billing** — cost rolls up per account, so Finance can see exactly what production versus nonprod costs. When the monthly bill arrives, you can immediately tell which environments are spending what.

Here's what NorthBank's account structure looks like:

| Account | Purpose |
|---------|---------|
| `northbank-management` | Organization root, billing, IAM Identity Center |
| `northbank-security` | GuardDuty and Security Hub aggregation, log archive |
| `northbank-logging` | Centralized CloudTrail and Config logs |
| `northbank-prod` | Customer-facing banking platform |
| `northbank-nonprod` | Dev, test, and staging environments |

This isn't unique to NorthBank. Large organizations typically run dozens of accounts — sometimes hundreds — all managed through AWS Organizations.

---

## Lesson 2.3 — IAM Identity Center: the real front door  [🎬 · ~3m]

This is what replaces "log in as root." **IAM Identity Center** (formerly called AWS SSO) is the portal every employee uses to access AWS accounts.

Here's what you get:

A **start URL** — something like `https://northbank.awsapps.com/start`. This is your portal. You bookmark this URL and that's where you go every morning.

A tile for **each account you're assigned to**. When you log into the portal, you see a dashboard with tiles for nonprod, prod, maybe logging — only the accounts you're allowed into.

A **permission set** per account. That's the role you assume when you click on a tile. Your nonprod tile might give you PowerUserAccess, while your prod tile gives you ReadOnlyAccess.

You authenticate once — with your email and MFA — and from that portal you reach every account you're allowed into. One identity, many accounts. No juggling passwords. No storing access keys in files.

When you click on an account tile, IAM Identity Center issues short-lived credentials and logs you into the console for that account with that role. The same system works for the CLI — we'll set that up next.

---

## Lesson 2.4 — Roles & permission sets: why your access differs  [🎬 · ~3m]

You are never handed "admin." You're granted access to a **role** — called a **permission set** in Identity Center — scoped to your job.

Here's what that looks like in practice:

A junior engineer on the Cloud Platform team might get **PowerUserAccess** in the nonprod account — they can create and manage almost everything — but only **ReadOnlyAccess** in production. They can read logs, check dashboards, and investigate issues, but they can't make changes. Changes in production require a senior engineer or go through an approval process.

A senior engineer gets a broader permission set in production because they own incident response. When something breaks at 2am, they have the access needed to fix it.

If you can do something your teammate can't — or vice versa — that's not a bug. That's **least privilege** working as designed. Your access matches your job, not your ego.

When you look at a permission set in IAM Identity Center, you'll see it's just a collection of managed policies — like `PowerUserAccess` or `ReadOnlyAccess` — plus any custom policies the organization has written. The permission set is the template. When you assume that role in an account, you get those permissions.

---

## Lesson 2.5 — The CLI login flow (write the config by hand)  [🎬 · ~5m]

The console SSO experience is point-and-click. The part people fumble is the CLI. We'll write the AWS config file by hand first, because typing it once demystifies it forever.

### The config file structure

Open up `~/.aws/config` in a text editor. There are two pieces: one `[sso-session]` block that's shared, and one `[profile]` block per account and role you want to reach.

Here's what it looks like:

```ini
# ~/.aws/config

[sso-session northbank]
sso_start_url = https://northbank.awsapps.com/start
sso_region    = us-east-1
sso_registration_scopes = sso:account:access

[profile nonprod]
sso_session   = northbank
sso_account_id = 222222222222
sso_role_name  = PowerUserAccess
region         = us-east-1

[profile prod]
sso_session   = northbank
sso_account_id = 333333333333
sso_role_name  = ReadOnlyAccess
region         = us-east-1
```

Notice the pattern: same `sso-session` named `northbank`, but the `nonprod` and `prod` profiles point to different account IDs and different roles. The prod profile uses `ReadOnlyAccess` — that's on purpose. Least privilege.

### Logging in

Once the config is written, you log in like this:

```bash
aws sso login --profile prod
```

This command opens a browser window. You'll see a device authorization page asking you to confirm a code. You approve it — with MFA — and then the browser says "you're logged in." That human-in-the-loop is intentional. It's how short-lived, MFA-backed credentials get issued.

The CLI session is now active. It will last for a few hours (often 1–8 hours depending on how your organization configured it), and then it expires.

### Switching accounts

Every AWS CLI command takes a `--profile` flag:

```bash
aws s3 ls --profile nonprod        # list buckets in nonprod
aws s3 ls --profile prod           # list buckets in prod — read-only allows this
aws s3 rb s3://something --profile prod   # DENIED — prod is read-only for you
```

That last command fails with an `AccessDenied` error. This is the lesson: your role decides what works, not the command. The command is valid. The service exists. You just don't have permission — and that's by design.

### Session expiration

Here's the number one support question from new hires:

"My CLI was working an hour ago and now everything says `ExpiredToken` or `The security token included in the request is expired`. Did I break something?"

No. SSO sessions are short-lived by design. When the session expires, you just log in again — `aws sso login --profile prod`. Nothing is broken. This is normal. You'll do this several times a day.

### Prove who and where you are

The first thing you should run after logging in, every time:

```bash
aws sts get-caller-identity --profile prod
```

This returns:

```json
{
  "UserId": "AROA...:you@northbank.com",
  "Account": "333333333333",
  "Arn": "arn:aws:sts::333333333333:assumed-role/AWSReservedSSO_ReadOnlyAccess_.../you@northbank.com"
}
```

Read that ARN out loud: `assumed-role`, in account `333333333333` (that's prod), as `ReadOnlyAccess`.

Before you run anything, confirm **who you are** and **which account you're pointing at**. Ninety percent of "why did this fail?" is "you were in the wrong account." This exact check reappears as the first step of Lab 1's triage flow. Make it muscle memory.

### What happened to root?

Root still exists — it's just locked away. At NorthBank the root credentials and MFA device live in a safe, and using them triggers an alarm. Root is used for almost nothing day-to-day: closing an account, changing the support plan, a handful of tasks only root can do.

If you're reaching for root, something has gone very wrong. In a year on the job you might touch it zero times.

---

## Lesson 2.6 — Hands-on: automate your own SSO setup  [🧪 lab · ~5m]

Here's how platform teams actually work: the one thing you can't script, you do by hand once. Everything after that is a script you can re-run and hand to a teammate.

The repository includes automation scripts in the `access/` folder that set up IAM Identity Center step by step:

```
access/
├── 00-bootstrap-NOTES.md         # the one-time console clicks
├── lib/common.sh                 # shared helper functions
├── 01-create-permission-sets.sh  # create roles (permission sets) and attach policies
├── 02-create-users-groups.sh     # create users and groups in the Identity Store
├── 03-assign-access.sh           # assign "group + permission set + account"
├── 04-setup-profile.sh           # write ~/.aws/config and run aws sso login
└── 05-verify.sh                  # run aws sts get-caller-identity per profile
```

### The one-time manual step

You cannot enable AWS Organizations or turn on IAM Identity Center via the CLI. You have to do this in the console once. Open `access/00-bootstrap-NOTES.md` and follow the two-step process:

1. Enable **AWS Organizations** in your sandbox account
2. Enable **IAM Identity Center**

That's it. Two clicks. Then everything else automates.

### Run the automation

Once Identity Center is enabled, run the scripts in order:

**Step 1:** Create permission sets — `./access/01-create-permission-sets.sh`  
This creates roles like `PowerUserAccess` and `ReadOnlyAccess` and attaches the appropriate AWS managed policies to them. You'll see the permission sets appear in the IAM Identity Center console.

**Step 2:** Create users and groups — `./access/02-create-users-groups.sh`  
This creates a user (you) and a group in the Identity Center Identity Store. The user gets added to the group.

**Step 3:** Assign access — `./access/03-assign-access.sh`  
This is the grant step. It says: this group gets this permission set in this account. This is what actually gives you access.

**Step 4:** Write the CLI config — `./access/04-setup-profile.sh`  
This script writes the `~/.aws/config` blocks we showed earlier, then runs `aws sso login` to authenticate you. A browser opens, you approve the code with MFA, and you're in.

**Step 5:** Verify your identity — `./access/05-verify.sh`  
This runs `aws sts get-caller-identity` for each profile you set up. You'll see your assumed role, account ID, and user ID print out. If this works, everything is configured correctly.

### The honest caveat

You can't fully replicate a big corporate organization in a personal sandbox account. You won't have five real accounts and forty roles. So this automation demonstrates the full multi-account experience in a simplified-but-real version: real Identity Center, real permission sets, real SSO login.

At work it's bigger — more accounts, more roles — but the mechanics are identical. Learn them here and your first day on the job, the login screen is the one thing that isn't new.

---

## Lesson 2.7 — Quiz: Access & login  [❓ · ~1m]

Quick check to lock in the concepts:

- What does "session expired" mean? (Your SSO session timed out — just log in again with `aws sso login`)
- Why do companies use many AWS accounts? (Blast radius, separation of duties, billing)
- What command proves who you are and which account you're in? (`aws sts get-caller-identity`)
- What's the difference between a user and a role? (You authenticate as a user; you work as a role with specific permissions)

---

So that's the front door. You now log in like the job does: SSO, multiple accounts, a role that's scoped to what you actually do, sessions that expire and just need a fresh login.

Next question: once you're in — what do you actually do all day? Where do you sit in the organization, what does a normal day look like, and how does a project like NorthBank's migration keep moving over six months? That's what we cover next.
