# Lab 05 — "Access Denied" ⭐

---

## Lab 05: "Access Denied" ⭐

### What we'll do in this lab

- Read the AccessDenied message for the clues it already gives you
- Use the IAM policy simulator instead of guessing
- Find the specific statement causing the explicit deny
- Remove the bad Deny and grant least-privilege access instead of a wildcard
- Verify the fix with the simulator before touching anything live

### The ticket

```
Ticket:   NB-0501
Reporter: Marco (App team)
Severity: SEV-2
Title:    "Our app suddenly gets 'Access Denied' writing customer statements to
           its S3 bucket. We didn't change anything!"
```

This is the most common ticket in cloud operations. "Access Denied." Every cloud team sees this ticket multiple times a week.

Most people "fix" it by adding `s3:*` to the role and calling it done. That works. It also fails the next security audit and creates a finding in Lab 13. So today we're going to do it properly: read the denial, find the exact cause, fix it with least privilege.

### The symptom

The NorthBank banking app runs on EC2 instances. Those instances assume an IAM role. The app tries to write customer account statements to an S3 bucket. The write fails with `AccessDenied`.

Marco says "we didn't change anything." But something changed. Your job is to find what.

### Break the environment first

```bash
cd labs/05-iam-access-denied
export AWS_REGION=us-east-1
export ROLE_NAME=$(terraform -chdir=../../envs/sandbox output -raw instance_role_name)
./break.sh
```

The break script creates an S3 bucket for storing statements, then attaches an inline policy to the instance role. That policy has an explicit `Deny` on `s3:PutObject` for the bucket. The script prints the bucket name — save it, you'll need it.

### Step 1: Read the AccessDenied message

An `AccessDenied` error tells you three things:
- **Who** tried to do something — the principal (the role ARN)
- **What** action they tried — the API call (like `s3:PutObject`)
- **Which** resource they tried it on — the ARN (like `arn:aws:s3:::bucket-name/file`)

You can reproduce the denial from an instance via SSM Session Manager, or you can use the IAM policy simulator. The simulator is faster and doesn't require actual access to an instance.

### Step 2: Use the policy simulator — no guessing

The IAM policy simulator lets you ask: "If this principal tries to do this action on this resource, what happens?" It evaluates all attached policies and tells you whether the action is allowed or denied, and why.

Get the role ARN:

```bash
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)
```

Get the bucket name (printed by the break script, or read from the state file):

```bash
BUCKET=$(jq -r .bucket .break-state.json)
```

Now simulate the write:

```bash
aws iam simulate-principal-policy \
  --policy-source-arn "$ROLE_ARN" \
  --action-names s3:PutObject \
  --resource-arns "arn:aws:s3:::$BUCKET/test" \
  --query 'EvaluationResults[].{Action:EvalActionName,Decision:EvalDecision}' \
  --output table
```

The output shows:
- `Action: s3:PutObject`
- `Decision: explicitDeny`

That word — **`explicitDeny`** — is the tell. This is not an implicit deny. An implicit deny means "no policy explicitly allowed this, so it's denied by default." An explicit deny means "a policy statement is actively saying no."

### The golden rule: explicit Deny always wins

IAM policies are evaluated in a specific order:
1. **Service Control Policies (SCPs)** at the organization or account level
2. **Resource-based policies** on the S3 bucket
3. **Identity-based policies** attached to the role
4. **Permission boundaries** on the role

At every layer, AWS checks for an explicit `Deny` first. If it finds one, evaluation stops. The action is denied. Period. No `Allow` statement anywhere can override an explicit `Deny`.

If there's no explicit `Deny`, AWS looks for an explicit `Allow`. If it finds one, the action is allowed. If it finds neither an explicit `Deny` nor an explicit `Allow`, the result is an implicit deny — denied by default.

So when the simulator says `explicitDeny`, you know: somewhere in that evaluation chain, a policy statement has `"Effect": "Deny"` on this action.

### Step 3: Find the denying statement

The deny could be in several places. Start with the most common: inline policies on the role.

List inline policies on the role:

```bash
aws iam list-role-policies --role-name "$ROLE_NAME"
```

You'll see a policy named something like `nb-0501-deny-statements-writes`. That's suspicious. Read it:

```bash
aws iam get-role-policy --role-name "$ROLE_NAME" \
  --policy-name nb-0501-deny-statements-writes
```

The output shows a policy document with:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Deny",
    "Action": "s3:PutObject",
    "Resource": "arn:aws:s3:::northbank-statements-*/*"
  }]
}
```

There it is. An explicit `Deny` on `s3:PutObject` for any resource matching that pattern. This policy is blocking the write, and no `Allow` statement anywhere else can override it.

Someone added this policy. Maybe it was a compliance control that went too broad. Maybe it was a temporary restriction that was never cleaned up. Maybe it was a mistake. Doesn't matter. It's blocking legitimate app functionality, so it needs to go.

### Step 4: Remove the bad Deny

Delete the inline policy:

```bash
aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name nb-0501-deny-statements-writes
```

The explicit `Deny` is gone. But we're not done yet. Now we need to make sure there's an explicit `Allow` for the action the app actually needs.

### Step 5: Grant least privilege — not a wildcard

The wrong fix is to add `"Action": "s3:*"` and call it done. That grants every S3 action — read, write, delete, bucket configuration, access point management, everything. That's too broad.

The right fix is to add exactly the actions the app needs, on exactly the resources the app touches. For this app:
- It needs to **write** statements to the bucket — `s3:PutObject`
- It probably needs to **read** statements back — `s3:GetObject`
- It does **not** need to delete objects, list all buckets, modify bucket policies, or any of the other hundred S3 actions

Create an inline policy with least privilege:

```bash
aws iam put-role-policy --role-name "$ROLE_NAME" --policy-name nb-statements-write \
  --policy-document "$(cat <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:PutObject", "s3:GetObject"],
    "Resource": "arn:aws:s3:::BUCKET_NAME_HERE/*"
  }]
}
JSON
)"
```

Replace `BUCKET_NAME_HERE` with the actual bucket name from the break script output. Or better yet, substitute it with a variable:

```bash
aws iam put-role-policy --role-name "$ROLE_NAME" --policy-name nb-statements-write \
  --policy-document "{
  \"Version\":\"2012-10-17\",
  \"Statement\":[{
    \"Effect\":\"Allow\",
    \"Action\":[\"s3:PutObject\",\"s3:GetObject\"],
    \"Resource\":\"arn:aws:s3:::$BUCKET/*\"
  }]
}"
```

This grants:
- `s3:PutObject` — the app can write files
- `s3:GetObject` — the app can read files it wrote
- Only on `arn:aws:s3:::$BUCKET/*` — only objects in this one bucket, not every bucket in the account

That's least privilege. Exactly what's needed, nothing more.

### Step 6: Verify with the simulator

Run the simulator again:

```bash
aws iam simulate-principal-policy --policy-source-arn "$ROLE_ARN" \
  --action-names s3:PutObject \
  --resource-arns "arn:aws:s3:::$BUCKET/test" \
  --query 'EvaluationResults[].EvalDecision' \
  --output text
```

```
allowed
```

The decision is now `allowed`. The explicit `Deny` is gone, and an explicit `Allow` exists for the exact action on the exact resource.

If you want to verify it from an actual instance, start a Session Manager session and try the write:

```bash
echo "test statement" > /tmp/test.txt
aws s3 cp /tmp/test.txt s3://$BUCKET/test.txt
```

It succeeds. The file uploads. The app can write again.

### Cleanup

When you're done with the lab, clean up the policies and bucket:

```bash
aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name nb-0501-deny-statements-writes 2>/dev/null || true
aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name nb-statements-write 2>/dev/null || true
aws s3 rb "s3://$BUCKET" --force
```

### The Day-2 lessons

**Read the denial message.** It tells you who, what action, and what resource. The answer is usually right there. Don't ignore the error message and start guessing.

**An explicit `Deny` beats everything.** If the simulator says `explicitDeny`, stop looking at `Allow` statements. Hunt for the `Deny`. It could be in an inline policy, a managed policy, an SCP, a resource policy, or a permission boundary. Find it and decide: is this `Deny` protecting something important, or is it blocking legitimate access?

**Use `simulate-principal-policy`.** It tells you the decision — allowed, explicit deny, implicit deny — without touching anything, without making test API calls, without needing access to an actual instance. It evaluates all the policies and shows you the result. This is how you diagnose permissions without guessing.

**Fix with least privilege.** Add the exact action the app needs, on the exact resource the app touches. Reaching for `s3:*` or `Resource: "*"` fixes today's ticket and creates next month's security finding. You'll see this again in Lab 13 when Security Hub flags overly permissive policies.

**"We didn't change anything" usually means "we changed something and forgot."** IAM policies don't change themselves. Someone added that `Deny`. Someone removed an `Allow`. Something changed. CloudTrail remembers. Use the triage spine from Lab 01: what changed?

### Why this matters

IAM is the most common blocker in cloud operations. Developers deploy code and hit `AccessDenied`. Automated processes fail with permissions errors. Terraform applies fail halfway through because the role doesn't have the right actions.

Learning to read IAM denials quickly, simulate policies without guessing, and fix with least privilege is the skill that separates someone who copies wildcard policies from Stack Overflow from someone who can actually secure a production environment.

---

## Quiz: Reading an AccessDenied

Quick check:

- What's the difference between explicit deny and implicit deny? (Explicit deny: a policy actively says `"Effect": "Deny"`. Implicit deny: no policy allows it, so it's denied by default.)
- What three things does an `AccessDenied` message tell you? (Who tried, what action, which resource.)
- Why not just grant `s3:*` and move on? (It's overly permissive, fails audits, creates security findings, violates least privilege.)
- What does the IAM policy simulator do? (Evaluates all policies for a principal and tells you whether an action on a resource would be allowed or denied, without making a real API call.)
- What's the golden rule? (An explicit `Deny` always wins, over any `Allow`, at any layer.)

---

## Quick reference — what break.sh did & how to reset

### Fault injected

- `break.sh` created an S3 bucket and attached an **inline policy** to the app's instance role.
- That policy has an **explicit `Deny`** on `s3:PutObject` for the bucket.
- Result: the app can't write, even if other policies allow S3. Details in `.break-state.json`.

### Root cause (in plain English)

- Someone added a policy with `"Effect": "Deny"` on the write action.
- **An explicit `Deny` always wins** — it can't be overridden by any `Allow`.
- So the app is blocked no matter what else is attached.
