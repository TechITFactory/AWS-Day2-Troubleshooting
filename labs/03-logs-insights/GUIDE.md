# Lab 03 — Find the error in the logs

Two labs that pair naturally. Alarms tell you *that* something's wrong. Logs tell you *why*.

---

## Lab 03: Find the error in the logs

### What we'll do in this lab

- Understand how log groups and streams map to your fleet
- Query Logs Insights to count requests by status code
- Filter to the failures and group by endpoint to isolate the fault
- Read the actual error message behind the failures
- Turn the pattern into a metric filter and an alarm

### The ticket

```
Ticket:   NB-0301
Reporter: Marco (App team)
Severity: SEV-2
Title:    "Some banking transfers fail intermittently. The app just logs errors."
```

The alarm from Lab 02 is quiet. No pages. But customers report that some transfers fail. Not all transfers — some. It's intermittent, which is the worst kind of failure because you can't reproduce it by clicking around in the UI.

All you have is a pile of application logs in CloudWatch. Thousands of log lines. Good requests mixed with failing requests. So we're not going to click around the app trying to catch the error. We're going to query the logs and let them tell us the pattern.

### Break the environment first

```bash
cd labs/03-logs-insights
export AWS_REGION=us-east-1
./break.sh
```

This seeds a CloudWatch log group named `/northbank/app` with a realistic mix of log lines. In production, the CloudWatch agent running on your instances ships these logs up automatically. For the lab, we pre-load a sample so we can focus on the skill that matters: querying.

### Step 1: Understand where logs live

A log **group** is the application. For example, `/northbank/app` is the log group for the NorthBank banking app.

A log **stream** is one instance inside that group. Each EC2 instance writes to its own stream. So if you have two instances, you have two streams in the same group.

**Logs Insights** is the CloudWatch feature that lets you query across all streams — all instances — at once. You don't SSH to each box and run `grep`. You write a query, and CloudWatch scans millions of log lines in seconds and returns the answer.

Open the AWS console. Go to **CloudWatch → Logs → Logs Insights**. Select the `/northbank/app` log group. Set the time range to the last 30 minutes.

### Step 2: Count by status — what's the shape?

The first query is always: what's the distribution? How many 200s versus 500s?

```
fields @timestamp, status
| stats count(*) as hits by status
| sort hits desc
```

This counts log lines by status code and sorts by count, descending.

Run the query. The results show:
- `status=200`: several thousand hits
- `status=500`: several hundred hits

So the app is mostly healthy, but there's a solid block of 500 errors. Something is genuinely failing, hidden in the noise of normal traffic.

### Step 3: Which endpoint is failing?

Now narrow it down. Filter to just the 500s and group by endpoint:

```
filter status = 500
| stats count(*) as fails by endpoint
| sort fails desc
```

Run the query. The results show:
- `endpoint=/transfer`: all the failures
- `endpoint=/login`: zero failures
- `endpoint=/balance`: zero failures

All the 500s are on `/transfer`. Login and balance endpoints are healthy. That's a huge clue: it's not the whole app. It's the one path that talks to the database most heavily.

### Step 4: Read the actual error

Now look at the actual error messages in the failing requests:

```
filter status = 500
| fields @timestamp, endpoint, error, latency_ms
| sort @timestamp desc | limit 20
```

This filters to 500 errors, selects specific fields, sorts by timestamp descending, and limits to the most recent 20 lines.

Run the query. Every failing line shows:
- `error = DBConnectionTimeout`
- `latency_ms` pegged at around 30,000 milliseconds (30 seconds)

We went from "transfers fail sometimes" to "the `/transfer` endpoint times out getting a database connection" in three queries. Five minutes of log analysis, and you know exactly what's wrong.

This points forward to Lab 09, which covers RDS troubleshooting. The database connection pool is exhausted, or the database is slow, or the security group is blocking the connection. But the logs told you exactly where to look.

### Step 5: Make it automatic — turn logs into metrics

You found the problem this time by querying manually. But you shouldn't have to notice errors by hand. Turn "500s in the logs" into a metric, then alarm on it.

Create a metric filter:

```bash
aws logs put-metric-filter --log-group-name /northbank/app \
  --filter-name northbank-app-500s \
  --filter-pattern '{ $.status = 500 }' \
  --metric-transformations metricName=App5xxCount,metricNamespace=NorthBank/App,metricValue=1,defaultValue=0
```

This watches the `/northbank/app` log group for any log line where the `status` field equals 500. Each matching line increments a custom CloudWatch metric called `App5xxCount` in the `NorthBank/App` namespace.

Now create an alarm on that metric:

```bash
TOPIC_ARN=$(aws sns list-topics --query "Topics[?contains(TopicArn, 'northbank-alerts')].TopicArn | [0]" --output text)

aws cloudwatch put-metric-alarm --alarm-name northbank-app-500s \
  --namespace NorthBank/App --metric-name App5xxCount \
  --statistic Sum --period 60 --evaluation-periods 2 \
  --threshold 10 --comparison-operator GreaterThanThreshold \
  --treat-missing-data notBreaching \
  --alarm-actions "$TOPIC_ARN"
```

This alarms if you see more than 10 error-level log lines in two consecutive one-minute periods. You can tune the threshold based on your traffic and tolerance. The point is: now if it spikes again, you get paged. You don't wait for Marco to tell you. The logs tell you directly.

### Cleanup

When you're done with the lab, delete the log group to avoid storage charges:

```bash
aws logs delete-log-group --log-group-name /northbank/app
```

### The Day-2 lesson

**Alarms say *that* something's wrong. Logs say *why.***

Don't SSH to a box and run `grep`. That's one instance. You have a fleet. Query all instances at once with Logs Insights.

The pattern that solves most log-based incidents:
1. **Count by status** — what's the shape? Mostly good with some bad?
2. **Filter the failures** — focus only on the error codes.
3. **Group by endpoint** — which path is affected?
4. **Read the error** — what's the actual error message?

This takes five minutes and gives you the answer. Then turn the pattern into a metric filter and alarm so nobody has to notice it by hand next time.

---

## Quiz: Alarms & logs

Quick check to lock in the concepts:

- What does `INSUFFICIENT_DATA` really mean? (The alarm is getting no data — it's watching a metric or dimension that doesn't exist. Not "fine.")
- Why do you test every alarm by breaching it? (An untested alarm is a guess, not a safety net. Break it on purpose to prove it fires.)
- What's the Logs Insights query pattern for finding errors? (Count by status → filter to failures → group by endpoint → read the error.)
- Why create metric filters from logs? (Turn log patterns into metrics you can alarm on, so errors page you automatically instead of waiting for a user report.)

---

These two labs together form the monitoring foundation: alarms that actually fire when things break, and logs that tell you exactly what broke and why. Build both, and you're on your way to month-six maturity: the environment tells you first.

---

## Quick reference — what break.sh did & how to reset

### Fault simulated

- `break.sh` seeded the `/northbank/app` log group with ~60 JSON log lines.
- About **1 in 7** are `500` errors on the **`/transfer`** endpoint.
- Every failure has the same cause: `"error": "DBConnectionTimeout..."`.
- Details in `.break-state.json`.

### Root cause (in plain English)

- The app can't get a database connection from its pool within 30 seconds on `/transfer`.
- Only `/transfer` is hit because it's the DB-heavy path.
- It's intermittent because it only fails when the pool is exhausted.
- (In the real course this points forward to Lab 09 — RDS/connection issues.)
