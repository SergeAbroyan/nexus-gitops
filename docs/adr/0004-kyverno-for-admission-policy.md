# 0004. Kyverno enforces workload security and image signatures

Status: accepted

## Context

The cluster must reject workloads that run as root or lack limits, and Nexus
images that CI did not build. OPA Gatekeeper needs Rego and a separate tool to
verify signatures; Kyverno does both with CEL and built-in cosign support.

## Decision

Kyverno runs in every cluster. `require-workload-security` checks Nexus
workloads, and `require-signed-nexus-images` verifies the keyless cosign
signature of every Nexus image against the CI workflow identity. CI applies the
workload policy to every rendered chart with the Kyverno CLI, and Policy
Reporter shows the results in the cluster.

## Consequences

An image pushed outside CI never runs, and a chart that breaks the rules fails
its pull request before it reaches a cluster. Kyverno's webhook fails closed, so
it runs three replicas in staging and production.
