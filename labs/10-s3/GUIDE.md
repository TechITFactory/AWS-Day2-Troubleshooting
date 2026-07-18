# Lab 10 — S3 403s and the access model

Two labs about access — one at the network layer, one at the policy layer.

⚠️ **Important:** Lab 09 needs the database running. Turn it on before the lab, turn it off immediately after. RDS costs real money while it's up.

---

## Lab 10: S3 403s and the access model

### What we'll do in this lab

- Reproduce the 403 and run the four standard checks
- Read the bucket policy for an explicit Deny
- Check the ARN detail that trips people up: `bucket` vs `bucket/*`
- Check Block Public Access, and fix without making the bucket public
- Verify access is restored

### The ticket

```
Ticket:   NB-1001
Reporter: Marco (App team)
Severity: SEV-2
Title:    "Reading customer statements from the S3 bucket returns 403.
           Downloads worked yesterday."
```

S3 access is decided by four separate things at once. Learn the model, then walk it in order.

### Break the environment first

```bash
cd labs/10-s3
export AWS_REGION=us-east-1
./break.sh
```

The break script creates a bucket for customer statements, uploads a test object, and attaches a bucket policy with an explicit `Deny` on `s3:GetObject`. It prints the bucket name — save it.

### Step 1: Reproduce the 403, then the four checks

```bash
export BUCKET=$(jq -r .bucket .break-state.json)
export KEY=$(jq -r .object_key .break-state.json)

aws s3 cp "s3://$BUCKET/$KEY" -
```

```
fatal error: An error occurred (403) when calling the GetObject operation: Access Denied
```

You get 403 even as an admin with broad permissions. S3 access is decided by four things:

1. **Your IAM identity policy** — what you're allowed to do. As admin, this likely allows the read.
2. **The bucket policy** — attached to the bucket directly. Can grant cross-account access, deny actions, add conditions.
3. **Block Public Access (BPA)** — a master switch at bucket or account level. Overrides any bucket policy statement that would grant public access.
4. **Object Ownership and ACLs** — legacy access control, predates bucket policies and IAM. Modern practice: disable ACLs, use policies. Rarely the cause today.

An explicit `Deny` anywhere wins, even over an `Allow` elsewhere. Your IAM policy is fine as admin, so the cause is the bucket policy.

### Step 2: Read the bucket policy

```bash
aws s3api get-bucket-policy --bucket "$BUCKET" --query Policy --output text | jq .
```

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Deny",
    "Principal": "*",
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::northbank-statements-abc123/*"
  }]
}
```

There it is: `"Effect": "Deny"` on `s3:GetObject`. Same rule as the IAM lab — an explicit `Deny` beats everything, even admin rights.

### Step 3: The ARN detail that matters most

Look at the `Resource` in that deny statement:

```
arn:aws:s3:::northbank-statements-abc123/*
```

- **`arn:aws:s3:::bucket`** (no slash-star) = the **bucket itself**. Bucket-level actions: `s3:ListBucket`, `s3:GetBucketLocation`, `s3:PutBucketPolicy`.
- **`arn:aws:s3:::bucket/*`** (with slash-star) = the **objects inside**. Object-level actions: `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`.

This deny targets `bucket/*`, so it blocks object reads. Mixing up `bucket` and `bucket/*` is the most common cause of an S3 policy silently not doing what was intended.

### Step 4: Check Block Public Access, then fix without going public

```bash
aws s3api get-public-access-block --bucket "$BUCKET"
```

Output — four settings, all should be `true`:
- `BlockPublicAcls`
- `IgnorePublicAcls`
- `BlockPublicPolicy`
- `RestrictPublicBuckets`

Leave these **on**. Do not turn them off to fix the 403 — making the bucket public is never the right fix, especially for customer financial data.

Remove the bad policy instead:

```bash
aws s3api delete-bucket-policy --bucket "$BUCKET"
```

No bucket policy now means nothing overrides your IAM `Allow`. Access is granted.

### Step 5: Verify

```bash
aws s3 cp "s3://$BUCKET/$KEY" -
```

```
Customer statement for account 12345
```

Works. The 403 is gone.

### The KMS encryption aside

If objects use SSE-KMS encryption, the caller also needs `kms:Decrypt` on the KMS key. Full S3 permissions (`s3:*` on `*`) still gets a 403 without that key permission. The error looks like an S3 problem but the real cause is the KMS key policy.

Check the object's encryption:

```bash
aws s3api head-object --bucket "$BUCKET" --key "$KEY" \
  --query '{Encryption:ServerSideEncryption,KeyId:SSEKMSKeyId}'
```

`Encryption: AES256` = S3-managed encryption, no KMS involved. `Encryption: aws:kms` with a `KeyId` = KMS — check the key policy for `kms:Decrypt`.

### Cleanup

```bash
aws s3 rb "s3://$BUCKET" --force
```

`--force` empties the bucket first, then deletes it.

### The Day-2 lessons

- **S3 access is four things:** IAM identity policy, bucket policy, Block Public Access, object ownership/ACLs. An explicit `Deny` in any of them wins.
- **`bucket` vs `bucket/*` is the classic mistake.** List operations use `bucket`. Object operations use `bucket/*`.
- **Fix by scoping, never by making a bucket public.** Find what's denying access and fix it with least privilege.
- **Leave Block Public Access on.** Only disable it, selectively, for a bucket that genuinely needs to be public.
- **KMS-encrypted objects need `kms:Decrypt`.** A 403 that looks like S3 can actually be KMS.

---

## Quiz: RDS & S3

Quick check:

- What's the difference between "reach" and "refuse" for databases? (Timeout = can't reach it, network problem. Rejection = reached it, it said no, credentials or capacity problem.)
- What does "Available" status mean in RDS? (The database process is running. Doesn't mean your app can reach it.)
- What are the four things that decide S3 access? (IAM identity policy, bucket policy, Block Public Access, object ownership/ACLs.)
- What's the difference between `arn:aws:s3:::bucket` and `arn:aws:s3:::bucket/*`? (The bucket itself vs the objects inside it. List vs object operations.)
- Why not make a bucket public to fix a 403? (It's overly permissive, creates security risk. Fix by scoping access to the specific principal that needs it.)

---

## Quick reference — what break.sh did & how to reset

### Fault injected

- `break.sh` created a bucket + a sample object, then attached a **bucket policy** with an
  **explicit `Deny`** on `s3:GetObject` for `arn:aws:s3:::<bucket>/*`.
- Explicit Deny beats every Allow — including the account owner's — so all object reads → **403**.
- Details in `.break-state.json`.

### Root cause (in plain English)

- Someone added a bucket policy that **denies reading objects**.
- The `Resource` is `<bucket>/*` — the `/*` means "the objects inside," which is exactly what
  `GetObject` needs. So every read is blocked.
- Probably intended to restrict reads to a condition, but written as a blanket Deny.
