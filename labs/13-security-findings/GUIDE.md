# Lab 13 — Triage the security findings

The lesson here is triage. Your job is not to reach zero findings — it's to find the one real problem in a noisy list, fix it, and record a decision on the rest.

---

## Lab 13: Triage the security findings

### What we'll do in this lab

- Turn on GuardDuty, Config, and Security Hub if they aren't already
- List findings, worst severity first
- Separate the real exposure from the noise
- Fix the real finding with least privilege
- Suppress the noise findings — with a documented reason

### The ticket

```
Ticket:   NB-1301
Reporter: Aisha (Security/GRC)
Severity: SEV-2 / weekly findings backlog
Title:    "Security Hub is lighting up on the banking account. Triage the
           findings, fix the real one, and tell me which are noise."
```

### Why we are doing this lab

- Turn on AWS security tools and you get dozens of findings — most are noise, one or two are real.
- A real security engineer's weekly job is **triage**: pick out the real exposure, fix it, and document a decision on everything else.
- Zero findings is impossible. A decision on every finding is the actual goal — that's what auditors check.

### What we'll do in this lab

- Turn on Security Hub and GuardDuty (if not already on)
- Break the environment: open SSH (port 22) to the whole internet — the one REAL finding
- Generate GuardDuty SAMPLE findings — the fake noise we practice triage on
- List all findings, worst first
- Separate the real finding from the sample noise
- Fix the real one: remove the open SSH rule
- Suppress the sample findings with a documented reason
- Verify the fix and clean up

### Why fake (SAMPLE) findings? Why not real ones?

- Real GuardDuty findings only appear during a real attack (crypto mining, port scans, stolen keys). We can't run a real attack in a lab.
- So we use `create-sample-findings` — an AWS API that fills the console with realistic fake findings, each titled `[SAMPLE]`.
- The samples are the **noise**. The open SSH port is the **signal**. Telling them apart is the whole skill.

### Step 0: Turn on the tools (skip if already on)

**What to check first:** are they already enabled?

```bash
aws securityhub describe-hub --region us-east-1        # error = not enabled
aws guardduty list-detectors --region us-east-1        # empty list = not enabled
```

**Enable them if needed:**

```bash
aws securityhub enable-security-hub --region us-east-1 --tags Purpose=lab13
aws guardduty create-detector --enable --region us-east-1
```

**One more required step — subscribe to a standard:**

```bash
aws securityhub batch-enable-standards --region us-east-1 \
  --standards-subscription-requests StandardsArn=arn:aws:securityhub:us-east-1::standards/aws-foundational-security-best-practices/v/1.0.0
```

- Why: enabling Security Hub only turns the service on. The **standard** is the rulebook that actually checks your resources.
- Without a standard, the "open SSH" control never runs — the real finding will never appear, no matter how long you wait.
- Cost: both tools have a 30-day free trial per account/region. We turn them off at the end.

### Break the environment

```bash
cd labs/13-security-findings
export AWS_REGION=us-east-1
export APP_SG=$(terraform -chdir=../../envs/sandbox output -raw app_security_group_id)
./break.sh
```

What the break script does:

- Opens SSH (port 22) to `0.0.0.0/0` on the app security group — a real, high-severity exposure
- Generates GuardDuty sample findings — the fake noise

### Step 1: Know the three tools

- **GuardDuty** = bad actors. Detects suspicious behavior: crypto mining, scans from bad IPs, stolen credentials.
- **Config** = bad configuration. Checks resources against rules: is the bucket encrypted? is a security group open to the world?
- **Security Hub** = the dashboard over both. Collects all findings in one place and scores you against standards.

### Step 2: List findings, worst first

```bash
aws securityhub get-findings \
  --filters '{"RecordState":[{"Value":"ACTIVE","Comparison":"EQUALS"}]}' \
  --query 'Findings[].{Severity:Severity.Label,Type:Types[0],Title:Title,Resource:Resources[0].Id}' \
  --output table
```

**What to check:**

- Sort by severity — CRITICAL and HIGH first
- Ignore everything else for now

**If the list is empty or the SSH finding is missing:**

- Check a standard is subscribed: `aws securityhub get-enabled-standards --region us-east-1` — empty means go back to Step 0.
- Be patient: the first check run after subscribing can take up to a couple of hours on a fresh account. Sample findings sync faster (minutes).
- Confirm the samples exist in GuardDuty directly:
  ```bash
  DETECTOR_ID=$(aws guardduty list-detectors --region us-east-1 --query 'DetectorIds[0]' --output text)
  aws guardduty list-findings --detector-id "$DETECTOR_ID" --region us-east-1
  ```
  Finding IDs back = samples exist, just not synced yet. Empty = rerun `break.sh`.

### Step 3: Separate the real finding from the noise

**What to check on each finding:**

- Title starts with `[SAMPLE]`? → fake, don't chase it
- Points at a made-up IP (`198.51.100.x`) or an instance ID that doesn't exist in your account? → fake
- Points at a **real resource you own**? → investigate

One finding is different: **"Security group allows unrestricted SSH"** — HIGH/CRITICAL, and it points at your real app security group. Port 22 open to the world on a banking app is a genuine exposure. That's the one that matters.

Confirm it on the resource:

```bash
aws ec2 describe-security-groups --group-ids "$APP_SG" \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`]' \
  --output json
```

Output shows `"CidrIp": "0.0.0.0/0"` on port 22 — confirmed, SSH is open to the whole internet.

### Step 4: Fix the real one

```bash
aws ec2 revoke-security-group-ingress \
  --group-id "$APP_SG" \
  --ip-permissions 'IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=0.0.0.0/0}]'
```

- Why remove SSH entirely instead of narrowing it to one IP? This fleet uses **SSM Session Manager** (Lab 04) for shell access — no keys, no open ports, fully logged.
- Rule: fix with least privilege, and prefer managed access (SSM) over legacy SSH.

### Step 5: Suppress the noise, with a reason

Every finding must end with a **decision** (a disposition). There are only three:

1. **Fixed** — remediated. Mark RESOLVED.
2. **Suppressed** — noise or false positive. Mark SUPPRESSED **with a note saying why**.
3. **Accepted risk** — real, but not fixing now. Assign an owner and a review date.

"I ignored it" is not a decision. Auditors want a decision on every finding, not zero findings.

Suppress the sample findings:

```bash
aws securityhub batch-update-findings \
  --finding-identifiers '[{"Id":"<finding-id>","ProductArn":"arn:aws:securityhub:us-east-1:<account>:product/aws/guardduty"}]' \
  --workflow '{"Status":"SUPPRESSED"}' \
  --note '{"Text":"GuardDuty sample finding - not real threat. Suppressed per NB-1301 weekly review.","UpdatedBy":"platform-team"}'
```

Replace `<finding-id>` with a real ID from Step 2. The note documents why; `UpdatedBy` says who decided.

### Verify

```bash
aws ec2 describe-security-groups --group-ids "$APP_SG" \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`]' \
  --output json
```

- Output is empty `[]` — no SSH rules remain
- Security Hub re-checks on its next scan and the control passes

### Cleanup

If you only turned the tools on for this lab, turn them off:

```bash
aws securityhub disable-security-hub --region us-east-1
aws guardduty delete-detector --detector-id <detector-id> --region us-east-1
```

Cost if left on: a few cents/day on a quiet sandbox (both are free for the first 30 days). The real risk is forgetting them enabled across many accounts.

### The Day-2 lessons

- **Triage beats whack-a-mole.** New findings appear constantly. Fix the real exposures, decide deliberately on the rest.
- **Know the tools.** GuardDuty = threats. Config = misconfiguration. Security Hub = the dashboard over both.
- **Every finding gets a decision.** Fixed, suppressed with a reason, or accepted risk with an owner.
- **Fix with least privilege.** Close SSH entirely and use SSM — don't just narrow the rule.
- **Findings often trace back to earlier shortcuts** — a port opened during troubleshooting and never closed. Review changes made under pressure.

### The weekly findings review (the routine this lab teaches)

1. **List** new findings — sort by severity
2. **Triage** — real exposure vs noise
3. **Fix** the CRITICAL/HIGH real ones now
4. **Decide** on the rest — suppress with reason, or accept with an owner
5. **Report** — update the dashboard, summarize for the security team

---

## Quiz: Findings triage

Quick check:

- What does GuardDuty detect versus Config versus Security Hub? (GuardDuty = suspicious behavior/threats. Config = compliance/misconfiguration. Security Hub = aggregates both and scores against standards.)
- Why isn't "zero findings" the goal? (It's impossible. New findings appear constantly. The goal is triage — fix what's real, decide deliberately on the rest.)
- What are the three dispositions for a finding? (Fixed/resolved. Suppressed with a reason. Accepted risk with an owner and reason.)
- Why is "I ignored it" not a valid disposition? (Auditors want to see you made a decision. Document why you took no action.)
- Why close SSH entirely instead of scoping it to a specific IP? (The fleet uses SSM Session Manager, so SSH isn't needed. Closing it removes the attack surface entirely.)

---

## Quick reference — what break.sh did & how to reset

### Fault injected

- **Real exposure:** `break.sh` opened **SSH (tcp/22) to `0.0.0.0/0`** on the app security group.
  Security Hub / Config flag this (e.g. "security group allows unrestricted SSH", a CIS/FSBP
  control).
- **Noise:** if GuardDuty is enabled, it generated **sample findings** — realistic-looking but
  harmless — so you have to separate signal from noise.
- Details in `.break-state.json`.

### Root cause (in plain English)

- Someone opened SSH to the whole internet on the app tier — a genuine, high-severity exposure.
- Alongside it, a bunch of sample/informational findings that look scary but aren't actionable.
- The job is **triage**: find the one that matters, fix it, disposition the rest.
