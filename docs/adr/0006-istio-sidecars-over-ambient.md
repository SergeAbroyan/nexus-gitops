# 0006. Istio keeps sidecars instead of ambient mode

Status: accepted

## Context

Istio's ambient mode removes the per-pod sidecar and saves CPU and memory. Here
the sidecars carry mutual TLS, merged application metrics, tracing, and the
Layer 7 routing that canary releases depend on.

## Decision

Keep sidecar injection. Ambient mode would need waypoint proxies for Layer 7
routing, a different metrics path, and new tests of canary traffic shifting,
for a saving of about 100m CPU and 128 MiB per pod.

## Consequences

Each Nexus pod pays for a sidecar. Revisit when the number of pods makes that
cost significant or when Argo Rollouts documents canary routing through
waypoints.
