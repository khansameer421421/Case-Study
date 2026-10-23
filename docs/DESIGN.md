# Design decisions and trade-offs

## Why keep both a pull path (Ansible) and a push path (CloudWatch)?

Leadership asked to use the existing stack first and add cloud-native services only where they clearly help. The two paths fail in different ways, so each covers the other's weak spots.

| | Ansible pull (hourly) | CloudWatch push (60 s) |
|---|---|---|
| Detection latency | Up to one schedule interval | About 5–10 min (2 × 300 s alarm periods) |
| Depends on the controller | Yes | No: the agent and alarms run without it |
| Finds VMs that are *not* reporting | **Yes** (coverage gaps) | No: a silent VM simply has no data |
| Cost | About $0 | Per metric and per alarm (see the README) |
| History and trends | `history.csv`, per-run reports | 15 months of metrics, anomaly detection |

The Ansible path is also the **audit of the CloudWatch path**. If the agent dies on a VM, the alarm sees *missing data*, and the hourly report still lists that VM.

## Why SSM Session Manager instead of SSH?

* No key distribution or rotation across dozens of acquired estates, each with different key hygiene.
* No bastions per VPC and no inbound security-group rules. Overlapping CIDRs from acquisitions don't matter.
* Access is controlled with IAM (`ssm:StartSession`, with a tag condition), so it is revoked centrally.
* Every session is recorded in CloudTrail.

The trade-off is that the SSM connection plugin is slower per task than pipelined SSH. The collector is therefore kept to about 3 round trips per host, and the controller runs with many forks.

## Why one inventory source per account instead of one source with many roles?

`amazon.aws.aws_ec2` takes one `iam_role_arn` or `profile` per source. The SSM connection plugin also needs credentials for the *same* account in order to start the session, so each host has to carry its account's profile (`ansible_aws_ssm_profile`).

Generating one source and one profile per account keeps the two in step. It also:

* isolates failures (one broken account doesn't break inventory for the rest)
* gives `account_<id>` groups for free

## Why StackSets with auto-deployment?

The baseline (role, instance profile, OAM link, alarm forwarding, backstop alarm) has to exist *before* Ansible can do anything in an account. Service-managed StackSets deploy it automatically when an account joins a target OU. That makes onboarding an acquisition an Organizations operation, not a ticket to the monitoring team.

IAM is global and OAM links are regional, so the baseline is split into two StackSets (03 and 04).

## Why EventBridge for alarm routing instead of SNS actions on each alarm?

* Alarm actions that point at an SNS topic in *another* account need cross-account topic policies to be kept up to date.
* Forwarding `DiskMon-*` state-change events to one central bus (whose policy is scoped by `aws:PrincipalOrgID`) keeps every notification target in one place.
* Adding Slack, PagerDuty, ServiceNow or an AWX remediation webhook means one new rule target, not touching thousands of alarms.

## Onboarding an acquired account that is not yet in the organisation

1. Add it to `static_accounts` in `config/accounts.yml`.
2. Deploy `03-member-account-iam.yml` there with plain `aws cloudformation deploy`. Its trust condition checks the *caller's* org, which is ours, so it works unchanged.
3. Grant the account access to the SSM staging prefix: add its role ARN to the bucket policy, because the org condition won't match it.
4. When the account later joins the org, delete the manual stack. The StackSet takes over.

## Failure modes and how they surface

| Failure | Effect | Where you see it |
|---|---|---|
| SSM agent down, no instance profile, or no route to SSM | Host can't be reached | Report "coverage gaps", SNS digest, `no_instance_profile` group |
| A hung NFS mount | Fact gathering is bounded by `gather_timeout` | The host still reports its other filesystems |
| CloudWatch agent stopped | Per-filesystem alarms get missing data | Hourly report still has the VM. Enrollment re-starts the agent |
| An account's role is missing (StackSet failed) | That account's inventory source fails to load | Ansible inventory warning. The other accounts are unaffected |
| Controller down | Ansible reports stop | CloudWatch alarms and the dashboard keep working |
| VM launched between runs | Has no per-filesystem alarms yet | Fleet backstop alarm covers it |
| Instance terminated | Alarms stuck in INSUFFICIENT_DATA | `prune_alarms.yml` deletes them |

## Scaling notes

* **Controller:** sized for concurrency, not CPU. Each SSM session is a `session-manager-plugin` process, so `forks` is limited by memory. 50–100 forks on a 4 GB instance is a reasonable start.
* **AWX:** use job slicing, or one scheduled job per account group, so execution nodes share the work.
* **API rate limits:** EC2, SSM and CloudWatch limits apply per account and region. Per-account credentials spread the load across those quotas instead of concentrating it.
* **Discovery cost:** inventory caching (`cache_timeout = 600`) stops repeated runs from re-listing every region in every account.
* **CloudWatch cost:** grows linearly with filesystems × metrics. The README lists the levers (fewer measurements, critical-only alarms, enrolling only some tiers).

## How this was validated

* Every YAML file parses, including the CloudFormation templates and their intrinsic tags.
* Every Jinja template and `set_fact` expression has been rendered against synthetic data covering:
  * Linux, including filtered tmpfs and overlay mounts
  * Windows
  * a host that could not be reached
  * a host dropped from the play

  The outputs are in `docs/examples/`.
* CI (`.github/workflows/ci.yml`) runs `yamllint`, `ansible-lint`, `cfn-lint`, `--syntax-check` on every playbook, and the local end-to-end demo with assertions on the report.
* The AWS-facing playbooks (enrollment, alarms, dashboard) and `scripts/deploy.sh` need a sandbox organisation to exercise end to end.
