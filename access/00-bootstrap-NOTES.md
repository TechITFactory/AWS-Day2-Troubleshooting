# 00 — Bootstrap: the one-time console clicks

Read this before running any script in access/. This is the only part of the whole SSO setup
that can't be automated. Platform teams really do work this way: bootstrap the one thing by
hand, then let scripts handle everything after it.

## Why this part can't be scripted

Turning on AWS Organizations and IAM Identity Center are account-level, first-time actions.
AWS deliberately gates them behind the console for the management account — there's no clean
API call to "turn the feature on" from zero. So you click twice, once, ever. Then the scripts
take over completely.

## The clicks (do these in the management account, as an admin)

Step 1 — enable AWS Organizations:
Console → AWS Organizations → Create an organization → keep "All features" (the default).
That's it. If your account is already inside an Org, skip this step entirely.

Step 2 — enable IAM Identity Center:
Console → IAM Identity Center → Enable. Choose your home Region deliberately — use the same
one you'll set as `AWS_REGION` below (these examples use `us-east-1`). The Identity Center
instance is permanently tied to whichever Region you pick here.

When it finishes, you'll land on a Settings page showing a start URL (something like
`https://d-xxxxxxxxxx.awsapps.com/start`) and an Instance ARN. You don't need to copy either of
these down by hand — `lib/common.sh` looks them both up automatically.

Step 3 — the sandbox simplification:
A real company would have separate prod, nonprod, security, and logging accounts. In a
personal sandbox you almost certainly have just one account, and that's fine — you'll assign
the permission set to that single account instead. At work it's more accounts and more roles,
but the mechanics are identical.

## After the clicks — run the scripts in this order

```bash
cd access/

./01-create-permission-sets.sh     # creates the role (permission set)
./02-create-users-groups.sh        # creates a user + group in the Identity Store
./03-assign-access.sh              # the grant: group + permission set + account
./04-setup-profile.sh              # writes ~/.aws/config and runs aws sso login
./05-verify.sh                     # confirms who you are, per profile
```

Each script prints the exact AWS command it's about to run before running it, and all of them
are safe to re-run.

Want to wipe this back to nothing and redo it (e.g. to start over)? `./06-teardown.sh`
removes the permission set, group, user, and account assignment created by 01-03, in reverse
order, then you can run 01-03 again fresh. It does not touch the Organization or the Identity
Center instance itself — those are still the console clicks above.

## What you need before starting

- AWS CLI v2 — SSO login requires it. Check with `aws --version`, should show `aws-cli/2.x`.
- You're logged into the management account as an admin. Scripts 01 through 03 create org-level
  resources, so a local admin profile or `aws configure` is enough to get going.
- `jq` is recommended but not required — the scripts fall back to `--query` if it's missing.

## The settings these scripts use

All of these have working defaults already, in `lib/common.sh`. You only need to export
something yourself if you want to change a name.

| Variable | Default | What it's for |
|---|---|---|
| `AWS_REGION` | `us-east-1` | Must match the Region you enabled Identity Center in |
| `NB_PERMSET_NAME` | `NorthBankPowerUser` | The permission set (role) that gets created |
| `NB_PERMSET_POLICY` | `arn:aws:iam::aws:policy/PowerUserAccess` | The managed policy attached to it |
| `NB_GROUP` | `NorthBank-Platform` | The Identity Store group name |
| `NB_USER` | `northbank.newjoiner` | The test user's name |
| `NB_USER_EMAIL` | `newjoiner@example.com` | The test user's email (Identity Store requires one) |
| `NB_ACCOUNT_ID` | your current account | Which account gets the grant |
| `NB_PROFILE` | `northbank` | The local profile name written into `~/.aws/config` |

One more thing worth repeating: these scripts create real IAM Identity Center resources. Run
them in a throwaway or personal sandbox account — never against a production Org.
