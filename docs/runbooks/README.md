# Nexus operational runbooks

Runbooks turn an alert into a repeatable diagnosis. Start here instead of
changing infrastructure immediately: confirm the affected environment, inspect
the evidence, mitigate customer impact, and only then make a durable change.

## Before responding

1. Confirm that the alert is firing, not an `OK` recovery notification.
2. Confirm the AWS account, region, Kubernetes context, and namespace before
   running a command.
3. Record the alert start time and avoid deleting pods, messages, or data until
   the cause is understood.
4. Use the Grafana `Nexus Overview` and `Nexus AWS Overview` dashboards to
   correlate application symptoms with AWS dependency metrics.

## Runbook index

| Alert | Severity | Runbook |
| --- | --- | --- |
| `NexusTargetDown` | Critical | [Application alerts](application-alerts.md#nexustargetdown) |
| `NexusHighServerErrorRate` | Warning | [Application alerts](application-alerts.md#nexushighservererrorrate) |
| `NexusHighRequestLatency` | Warning | [Application alerts](application-alerts.md#nexushighrequestlatency) |
| `*-rds-high-cpu` | CloudWatch | [AWS dependency alerts](aws-dependency-alerts.md#rds-high-cpu) |
| `*-rds-low-free-storage` | CloudWatch | [AWS dependency alerts](aws-dependency-alerts.md#rds-low-free-storage) |
| `*-valkey-*-high-memory` | CloudWatch | [AWS dependency alerts](aws-dependency-alerts.md#valkey-high-memory) |
| `*-sqs-oldest-message` | CloudWatch | [AWS dependency alerts](aws-dependency-alerts.md#sqs-oldest-message) |
| `*-sqs-dead-letter-messages` | CloudWatch | [AWS dependency alerts](aws-dependency-alerts.md#sqs-dead-letter-messages) |

## Common read-only checks

Replace `<environment>` and `<region>` with the alert's values.

```bash
aws sts get-caller-identity
aws cloudwatch describe-alarms --state-value ALARM --region <region>
kubectl config current-context
kubectl get applications -n argocd
kubectl get pods -A
```

These checks do not modify the platform. Scaling, restarting, redriving, or
purging resources is a mitigation decision and must be recorded with the
incident.
