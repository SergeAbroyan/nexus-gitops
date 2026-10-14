# AWS dependency alert runbooks

CloudWatch sends these alarms through the same SNS topic as Alertmanager. Use
the alarm name and dimensions in the notification to identify the environment
and resource. Confirm the active AWS account and region before every command.

## RDS high CPU

1. Open `Nexus AWS Overview` and compare RDS CPU with application request rate
   and latency for the same interval.
2. Inspect database connections and Performance Insights for expensive or
   blocked queries. Check the API traces for slow PostgreSQL spans.
3. Confirm the instance is otherwise healthy:

   ```bash
   aws rds describe-db-instances --db-instance-identifier <identifier> --region <region>
   aws cloudwatch describe-alarms --alarm-name <alarm-name> --region <region>
   ```

4. Reduce abnormal traffic or roll back a query regression first. Change the
   instance class only through Terraform after confirming sustained capacity
   pressure.

## RDS low free storage

1. Confirm the trend in `Nexus AWS Overview`; a slow decline and a sudden drop
   require different responses.
2. Inspect database growth, retained logs, and long-running transactions.
3. Do not delete database data as an alert response. Increase allocated or
   maximum autoscaled storage through Terraform when growth is legitimate.
4. Keep the alarm open until free storage is safely above the threshold and the
   underlying growth is understood.

## Valkey high memory

1. Identify the cache node from the alarm dimension and compare memory with
   engine CPU in `Nexus AWS Overview`.
2. Check whether the application recently changed key volume, value size, or
   expiration behavior. Use traces to identify unusually heavy Valkey calls.
3. Confirm replication-group health:

   ```bash
   aws elasticache describe-replication-groups --replication-group-id <group-id> --region <region>
   ```

4. Do not flush the cache blindly. Correct missing expirations or abnormal key
   creation; resize through Terraform if the working set has legitimately grown.

## SQS oldest message

1. Compare oldest-message age and visible-message count in `Nexus AWS Overview`.
2. Check worker availability, restarts, logs, HPA state, and pending pods:

   ```bash
   kubectl get pods -n nexus -l app.kubernetes.io/component=worker
   kubectl logs -n nexus deployment/nexus-worker --all-containers --since=15m
   kubectl get hpa -n nexus
   kubectl get events -n nexus --sort-by=.lastTimestamp
   ```

3. Inspect worker traces for slow RDS, Valkey, or downstream operations.
4. Restore healthy consumers before increasing concurrency. Make durable replica
   or resource changes in Git so Argo CD preserves them.

## SQS dead-letter messages

1. Treat every message as a failed job that requires investigation. Record the
   queue ARN, approximate count, and alarm time.
2. Inspect worker errors and the source queue's redrive policy. Receive a small
   sample without deleting it:

   ```bash
   aws sqs receive-message --queue-url <dlq-url> --max-number-of-messages 1 --attribute-names All --message-attribute-names All --visibility-timeout 30 --region <region>
   ```

3. Identify and fix the processing failure before redriving. Messages may
   contain sensitive business data; do not paste payloads into public tickets.
4. Redrive only a reviewed, bounded set after the worker fix is deployed. Never
   purge the dead-letter queue as an alert response.
