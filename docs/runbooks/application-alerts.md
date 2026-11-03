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

## NexusApiAvailabilityBudgetBurn

The API is returning HTTP 5xx responses fast enough to exhaust its 30-day
availability error budget early. Sloth generates the alert from the
`requests-availability` objective in `charts/applications/runtime`: the
critical page fires on a fast burn over the last hour, the warning ticket on a
slow burn over several hours.

1. In `Nexus Overview`, identify when errors started and whether they come from
   the stable or the canary service (`nexus-api` or `nexus-api-canary`).
2. Check whether a canary release is in progress. Argo Rollouts aborts a canary
   whose success rate drops below the analysis threshold, but a release that
   was already promoted stays:

   ```bash
   kubectl get rollout -n nexus nexus-api
   kubectl describe rollout -n nexus nexus-api
   kubectl get analysisrun -n nexus
   ```

3. Correlate the interval in Loki and Tempo. Start with application logs, then
   follow trace IDs through API, PostgreSQL, Valkey, and SQS spans.
4. Check `Nexus AWS Overview` for simultaneous RDS, Valkey, or SQS pressure.
5. If a new image caused the failures, revert the image tag in Git and let Argo
   CD reconcile it. Do not patch the Rollout directly because GitOps will
   overwrite that change.
6. Resolve after the burn rate falls below the alert threshold; the remaining
   budget is shown on the Sloth dashboard in Grafana.

## NexusApiLatencyBudgetBurn

Too many API requests take longer than the latency threshold of the
`requests-latency` objective, measured by Istio at the API pod.

1. In `Nexus Overview`, compare latency with request rate, CPU, memory, and
   5xx responses.
2. Use Tempo to find slow traces from the same interval and compare the API
   span with its PostgreSQL, Valkey, and SQS child spans. Use Pyroscope in
   Grafana to see which functions consume CPU during the slow period.
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
6. Resolve after the burn rate falls below the alert threshold.
