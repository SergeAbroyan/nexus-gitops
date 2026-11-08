# Security

- Kyverno rejects unsigned Nexus images and insecure workloads; Policy Reporter
  shows every policy result in a UI. Kyverno checks the signature of every new
  pod but does not rewrite image references to digests: ECR tags are immutable
  commit SHAs, so a tag already names exactly one image, and Git and the
  cluster stay identical.
- Trivy Operator scans every running image for fixable high and critical
  vulnerabilities, checks workload configuration and RBAC, and looks for
  secrets in images. Results are `VulnerabilityReport` and
  `ConfigAuditReport` objects, metrics in Prometheus, and entries in Policy
  Reporter. It reads private Nexus images with its own Pod Identity.
- Mutual TLS is strict in the `nexus` namespace, and secrets come only from
  Secrets Manager through External Secrets.
