# Resilience drills

Each drill causes one planned failure, says what the platform should do, and
lists what to check. Run them in DEV or staging, one at a time, with the
`Nexus Overview` dashboard and the Argo CD UI open. Record the start time, what
happened, and any gap you found; a gap becomes a fix in Git or a change to a
runbook.

## 1. A Spot node is reclaimed

Start the `spot_interruption` FIS experiment from the `nexus-platform` README.

Expected: Karpenter receives the two-minute notice from its queue, starts a
replacement node, and drains the old one. The worker moves, the API keeps
serving, and no SLO alert fires.

Check `kubectl get nodeclaims -w`, the Karpenter logs, and the API error rate.

## 2. Half of the system nodes fail

Start the `system_node_failure` FIS experiment.

Expected: EKS replaces the terminated nodes. Controllers reschedule, and Argo CD
reports every Application healthy again within about ten minutes.

Check `kubectl get nodes -w` and `kubectl get applications -n argocd`.

## 3. A bad release reaches the canary

Point DEV at an image that fails requests: run the `ci.yaml` workflow on a
branch where `/api/items` returns `500`, then set that SHA in
`environments/dev/api-values.yaml`.

Expected: Argo Rollouts sends 20% of traffic to the canary, the
`nexus-api-success-rate` analysis fails twice, and the rollout aborts. The
stable version keeps serving, and `ArgoCDApplicationDegraded` fires after 15
minutes. Revert the commit to recover.

Check `kubectl argo rollouts get rollout nexus-api -n nexus --watch`.

## 4. Someone deploys an unsigned image

Apply a pod that uses a Nexus image pushed without CI, for example a tag pushed
from a laptop:

```bash
kubectl run unsigned -n nexus --image=<registry>/nexus/api:<unsigned tag>
```

Expected: Kyverno rejects the pod with the `require-signed-nexus-images`
message, and Policy Reporter lists the failure.

## 5. The queue backs up

Pause the worker with `kubectl scale deployment nexus-worker -n nexus --replicas=0`
after temporarily disabling self-heal, or queue many notifications with the k6
test, then watch the worker scale.

Expected: KEDA reads the queue depth and scales the worker up to
`autoscaling.maxReplicas`, one replica per `messagesPerReplica` messages, and
back down when the queue drains. The `sqs-oldest-message` CloudWatch alarm fires
only if the backlog outlasts its threshold.

Check `kubectl get scaledobject,hpa -n nexus`.

## 6. Restore a namespace from Velero

```bash
velero backup get
velero restore create --from-backup <latest velero-daily backup> \
  --include-namespaces cloudbeaver --namespace-mappings cloudbeaver:cloudbeaver-restore
```

Expected: the restore completes, the CloudBeaver workspace volume is recreated
from its snapshot in `cloudbeaver-restore`, and the original namespace is
untouched. Delete the restored namespace afterwards.

## 7. Restore the database from AWS Backup

In the AWS Backup console, restore the latest recovery point of
`<name>-database` to a new instance named `<name>-postgres-restore`, then
connect with `psql` and count the rows in `items`.

Expected: the restored instance contains the data from the backup time. Delete
it afterwards. A real recovery points the API at the restored instance through
the `database` facts in `nexus-platform`.

## 8. The public address is down

Scale the Istio ingress gateway to zero after temporarily disabling self-heal
on `istio-ingress`.

Expected: `NexusPublicEndpointDown` fires within about six minutes and links
to its runbook. Re-enable self-heal; Argo CD restores the gateway.
