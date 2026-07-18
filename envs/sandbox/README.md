# envs/sandbox — the environment the labs run against

> 📘 **New to the Terraform here?** Read
> [delivery/terraform-explained.md](../../delivery/terraform-explained.md) — a plain-English,
> file-by-file walkthrough of *everything* these `.tf` files deploy (this root + both modules).

- This is **one Terraform root** that builds the whole NorthBank app: network + web tier (+ optional database).
- You apply it **once**, then each lab's `break.sh` breaks part of it and you fix it.
- Every lab reads values from here, for example:
  ```bash
  terraform -chdir=../../envs/sandbox output -raw asg_name
  terraform -chdir=../../envs/sandbox output -raw alb_arn
  ```

## Deploy it

```bash
cd envs/sandbox
terraform init
terraform apply            # ~3-5 min (ALB + ASG + NAT)
terraform output           # see app_url, asg_name, alb_arn, etc.
```

Open the `app_url` in a browser — you should see the NorthBank banking page.

## Turn the database on (only for labs 9, 11, 15)

```bash
terraform apply -var="create_database=true"    # adds RDS MySQL (costs more)
# ...do the lab...
terraform apply -var="create_database=false"   # remove the DB when done
```

## Tear it all down

```bash
terraform destroy
```

## Things to know

- **Sandbox account only.** The `break.sh` scripts deliberately break this environment.
- **Cost:** ALB + 2× t3.micro + 1 NAT Gateway while applied; RDS on top when enabled. Small, but
  not free — `destroy` when you're done for the day.
- **Everything is tagged** `Project=NorthBank` so you can find leftovers:
  ```bash
  aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=NorthBank \
    --query 'ResourceTagMappingList[].ResourceARN' --output table
  ```

## Outputs (what the labs consume)

`app_url` · `alb_dns_name` · `alb_arn` · `target_group_arn` · `asg_name` · `instance_role_name` ·
`vpc_id` · `app_security_group_id` · `alb_security_group_id` · `db_security_group_id` ·
`private_route_table_id` · `db_instance_id` · `db_endpoint`
