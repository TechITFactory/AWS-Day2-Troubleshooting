# Section 00 — Prerequisites & Environment Setup (do this once, before Section 5)


---

## Lesson 00.1 — What you need before you start [~2m]

Before touching AWS, confirm you have a personal or sandbox AWS account — never a
shared or production one — with a card on file, since the free tier doesn't fully cover this
course. No prior AWS experience is assumed; every command is explained the first time it's used.

Check your tools are installed:
```bash
aws --version        # must show aws-cli/2.x
terraform version     # any recent 1.x
jq --version          # recommended, not required
```

---

## Lesson 00.2 — Set a budget alarm first [~1m]

Do this before creating anything — it's the safety net if a lab gets left running.

```bash
aws budgets create-budget --account-id <account-id> \
  --budget '{"BudgetName":"aws-day2","BudgetLimit":{"Amount":"20","Unit":"USD"},"TimeUnit":"MONTHLY","BudgetType":"COST"}' \
  --notifications-with-subscribers '[{"Notification":{"NotificationType":"ACTUAL","ComparisonOperator":"GREATER_THAN","Threshold":80,"ThresholdType":"PERCENTAGE"},"Subscribers":[{"SubscriptionType":"EMAIL","Address":"<email>"}]}]'
```

---

## Lesson 00.3 — Deploy the sandbox environment [~4m]

This is the one Terraform root every lab reads from. Apply it once; each lab's
`break.sh` breaks a small part of it, and you fix that part — you don't rebuild between labs.

```bash
cd envs/sandbox
terraform init
terraform apply            # ~3-5 min: builds the VPC, ALB, Auto Scaling group, NAT Gateway
terraform output           # note app_url and asg_name — later labs read these
```

Open `app_url` in a browser. You should see the NorthBank page. If it's not there yet, wait
~60 seconds — the servers need to boot and pass their first health check.

---

## Lesson 00.4 — Know the cost before you start [~2m]

The full stack costs about $2.15/day (ALB + NAT Gateway + 2 small servers); add ~$0.40/day
when the database is on for Labs 9, 11, 15. Tear down after each session and the whole course
runs $5-15 total.

```bash
terraform -chdir=envs/sandbox destroy
```

Find anything left behind (everything is tagged `Project=NorthBank`):
```bash
aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=NorthBank \
  --query 'ResourceTagMappingList[].ResourceARN' --output table
```

---

## Lesson 00.5 — The database toggle [~1m]

The database is off by default. Only Labs 9, 11, and 15 need it.

```bash
terraform apply -var="create_database=true"     # before those labs
terraform apply -var="create_database=false"    # right after — this is the biggest cost risk
```

---

You're ready when: the budget alarm is set, `app_url` loads the NorthBank page, and you know
the destroy command and the leftover-finder command by heart.
