# Observability

Prometheus, Grafana, Loki, Tempo, Pyroscope, OpenCost, Sloth, and the
OpenTelemetry collectors are add-ons.
Istio and the API send traces to `otel-traces`, which forwards them to Tempo;
`otel-logs` ships container logs to Loki. `tracing.samplingPercentage` in
`bootstrap/values.yaml` sets the share of traced requests for both the mesh and
the API. The `Nexus Overview` dashboard shows availability, request rate, CPU,
memory, the Istio 5xx ratio, and 95th-percentile latency; `Nexus AWS Overview`
shows the CloudWatch metrics of the region's PostgreSQL, Valkey, and SQS.
Grafana discovers both dashboards automatically. Grafana also has a Pyroscope
data source for continuous profiles, and OpenCost reports the cost of every
namespace and workload from Prometheus data. Prometheus scrapes Argo CD and
alerts when an Application stays degraded, stays out of sync, or fails to sync.
The blackbox exporter loads the public address through CloudFront every
minute, and alerts fire when it fails or when its certificate is close to
expiry. Goldilocks shows CPU and memory recommendations from the VPA
recommender for the `nexus` namespace, so requests can be right-sized from
real usage. Response procedures live in [`docs/runbooks`](runbooks/README.md),
and [`drills.md`](runbooks/drills.md) rehearses them.

Alertmanager sends every alert to the region's SNS topic. Set
`alerting.slack.enabled: true` in `bootstrap/values.yaml` after storing the
webhook URL in the Secrets Manager secret that `nexus-platform` creates, and
warnings and critical alerts also go to `alerting.slack.channel`. The URL is
read by an `ExternalSecret` and mounted into Alertmanager, so it is never in
Git or in Helm values.

Istio's validating webhook is changed by `istiod` at runtime, so `istio-base`
ignores differences in that webhook's `failurePolicy` instead of fighting
`istiod` on every sync.
