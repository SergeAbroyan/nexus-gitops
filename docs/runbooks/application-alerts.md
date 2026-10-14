# Application alert runbooks

Use the alert labels to identify the environment, namespace, pod, and service.
The commands below are read-only unless a mitigation step explicitly says
otherwise.

## NexusTargetDown

Prometheus cannot scrape a Nexus workload. This can mean the pod is unhealthy,
the metrics endpoint is unavailable, or Prometheus cannot reach it.

1. Inspect pod state, recent events, probes, and container restarts:

   ```bash
   kubectl get pods -n nexus -o wide
   kubectl describe pod -n nexus <pod>
   kubectl logs -n nexus <pod> --all-containers --since=15m
   kubectl get events -n nexus --sort-by=.lastTimestamp
   ```

2. If the application is healthy, inspect the PodMonitor and Prometheus target:

   ```bash
   kubectl get podmonitor -n nexus nexus -o yaml
   kubectl get endpointslice -n nexus
   kubectl get peerauthentication -n nexus
   ```

3. Check Argo CD before changing the workload. A degraded or out-of-sync
   application can explain a missing pod or configuration drift.
4. Mitigate only after identifying the cause. A single stuck pod may be
   replaced by its controller; insufficient capacity requires checking
   Karpenter and pending-pod events first.
5. Resolve after the target is healthy and Prometheus has scraped it again.

## NexusHighServerErrorRate

More than the configured proportion of requests returns an HTTP 5xx response.

1. In `Nexus Overview`, identify when the error rate increased and which
   destination service receives the failures.
2. Correlate that interval in Loki and Tempo. Start with application logs, then
   follow trace IDs through API, PostgreSQL, Valkey, and SQS spans.
3. Inspect workload status and recent deployment history:

   ```bash
   kubectl get pods -n nexus
   kubectl logs -n nexus deployment/nexus-api --all-containers --since=15m
   kubectl rollout history deployment/nexus-api -n nexus
   kubectl get application -n argocd nexus-dev -o yaml
   ```

4. Check `Nexus AWS Overview` for simultaneous RDS, Valkey, or SQS pressure.
5. If a new image caused the failures, revert the image tag in Git and let Argo
   CD reconcile it. Do not patch the Deployment directly because GitOps will
   overwrite that change.
6. Resolve after the 5xx ratio remains below the configured threshold for the
   full alert evaluation window.

## NexusHighRequestLatency

The Istio-measured 95th-percentile response time remains above the configured
threshold.

1. In `Nexus Overview`, identify the affected service and compare latency with
   request rate, CPU, memory, and 5xx responses.
2. Use Tempo to find slow traces from the same interval. Compare application
   span duration with PostgreSQL, Valkey, and SQS child spans.
3. Check pod saturation, throttling, replicas, and autoscaling:

   ```bash
   kubectl top pods -n nexus
   kubectl get hpa -n nexus
   kubectl describe hpa -n nexus
   kubectl get pods -n nexus -o wide
   ```

4. Check the AWS dashboard for RDS CPU or storage pressure and Valkey CPU or
   memory pressure. If only one pod is slow, inspect its logs and node events.
5. Prefer a Git change for sustained capacity adjustments. Temporary manual
   scaling is acceptable only as a recorded incident mitigation.
6. Resolve after p95 latency remains below the threshold for the full alert
   evaluation window.
