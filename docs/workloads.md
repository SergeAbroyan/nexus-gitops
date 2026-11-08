# Workloads

## Applications

`api` serves the web page and REST API. It reads its PostgreSQL password
through an `ExternalSecret` and a `SecretStore` named `aws-secrets-manager`
that use the External Secrets controller's EKS Pod Identity, so no credentials
are stored anywhere. In a standby region the database is a read replica of the
primary, so the store reads the secret from the primary region through
`externalSecret.region`, and the API skips schema changes while the database is
read-only. It sends traces to the OpenTelemetry gateway and CPU and memory profiles to
Pyroscope.

The API is released as a canary. Its chart sets `rollout.enabled`, so
`nexus-base` renders an Argo Rollouts `Rollout` instead of a `Deployment`, plus
a `nexus-api-canary` Service. The API chart also owns the public
`VirtualService`; Argo Rollouts shifts its `primary` route from the stable to
the canary Service in the steps of `rollout.steps`, 20% then 50% then all
traffic, and the `nexus-api-success-rate` AnalysisTemplate checks the canary's
Istio success rate every minute from the second step onward. A canary that
fails the analysis is aborted and the stable version keeps serving. The
Application ignores the route weights and the Service selectors, which Argo
Rollouts owns while a release runs.

`worker` scales with KEDA on the depth of its SQS queue, one replica per five
waiting messages between the environment's minimum and maximum, with CPU and
memory as a floor. KEDA reads the queue with its own Pod Identity. The worker
runs on Spot capacity and mounts an `emptyDir` at `/tmp`, because
Spring Boot's embedded Tomcat needs a writable temporary directory while the
root filesystem stays read-only.

Both charts call `nexus-base.application`, so they share the same non-root,
read-only container security, health checks, resource limits, autoscaling,
disruption budgets, zone spreading, and Pod Identity service accounts. DEV runs
one replica of each; staging and production run at least two and three.

The worker also traces each SQS message as a child of the API request that
queued it, and sends profiles to Pyroscope.

`runtime` owns the `nexus` namespace with sidecar injection and the Restricted
Pod Security Standard, a `STRICT` mutual TLS `PeerAuthentication`, a
`PodMonitor`, the Prometheus alerts, the API service level objectives, and the
Grafana dashboards. Istio merges each application's `/metrics` into port
`15020`, so Prometheus scrapes it without weakening mutual TLS.

The API has two objectives over 30 days, defined as a Sloth
`PrometheusServiceLevel`: availability, the share of requests without a 5xx
response, and latency, the share of requests faster than
`slo.latency.thresholdMilliseconds`. Sloth turns them into recording rules and
multi-window burn-rate alerts: a critical page when the error budget burns
fast, a warning ticket when it burns slowly. Objectives are chart values with
stricter production values, and every alert links to its runbook.

## Platform charts

`ingress-config` owns the Istio `Gateway` on port 8443 and a
`TargetGroupBinding`; each application chart owns its own route on that
gateway. CloudFront terminates TLS for the public hostname and
reaches the region's internal Network Load Balancer through a VPC origin;
Terraform creates that load balancer and passes its target group ARN as a
cluster fact, and the binding registers the gateway pods. The gateway
namespace enforces the Restricted Pod Security Standard.

`karpenter-config` defines one EC2 node class and three node pools: `system`
for platform controllers, `general` for the API and the monitoring stack, and a
tainted `spot` pool for tolerant workloads such as the worker. Each pool lists
the capacity types it may use in `capacityTypes`. Staging and production run
`system` and `general` On-Demand; DEV allows Spot and On-Demand, so Karpenter
picks the cheaper Spot capacity and falls back to On-Demand only when Spot is
unavailable. The `spot` pool is Spot everywhere. Karpenter receives AWS
interruption notices through the queue Terraform creates, so it replaces a Spot
node before AWS reclaims it. Karpenter uses only the subnets that Terraform tags
for the environment's workload Availability Zones. Pin `amiAlias` to a tested
release before production.

`storage-config` also defines `nexus-gp3-snapshots`, the VolumeSnapshotClass
that Velero uses, and the `nexus-gp3` StorageClass: encrypted with the
infrastructure EBS key and expandable. In DEV a volume is deleted when its
claim is deleted, so volumes do not pile up while DEV changes; staging and
production retain volumes. Destroying a cluster does not delete claims, so
volumes can outlive a teardown in every environment; the `nexus-platform`
README explains the cleanup. Kubernetes cannot change the reclaim policy of an
existing StorageClass, so changing `reclaimPolicy` later requires deleting and
recreating the `nexus-gp3` StorageClass.

`cloudbeaver` provides an internal database administration UI with a
persistent workspace, exposed only through a `ClusterIP` Service.

`policies` holds the Kyverno admission policies:

- `require-workload-security` rejects Deployments, StatefulSets, DaemonSets,
  and Rollouts in the `nexus` and `cloudbeaver` namespaces that run as root,
  skip the `RuntimeDefault` seccomp profile, allow privilege escalation, keep
  Linux capabilities, or lack CPU and memory requests and limits.
- `require-signed-nexus-images` rejects a pod in the `nexus` namespace whose
  Nexus image from ECR has no keyless cosign signature made by the
  `nexus-applications` CI workflow on `main`. The expected identity is the
  `ciIdentity` cluster fact, and Kyverno reads the signatures from ECR with its
  own Pod Identity.
