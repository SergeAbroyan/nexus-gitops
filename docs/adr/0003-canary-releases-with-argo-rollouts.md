# 0003. The API is released as a canary with Argo Rollouts and Istio

Status: accepted

## Context

A rolling update sends all traffic to a new version as soon as its pods are
ready, so a bad release reaches every user before alerts fire.

## Decision

The API runs as an Argo Rollouts `Rollout`. Rollouts shifts the weights of the
`primary` route in the API's `VirtualService` to 20% and 50%, and an
`AnalysisTemplate` aborts the release when the canary's Istio success rate
drops below 95%. The worker keeps a rolling update, because it serves no
traffic to split.

## Consequences

A bad release affects a fifth of requests for about two minutes and rolls back
on its own. The API chart owns its route, Argo CD ignores the weights and
selectors that Rollouts changes, and Kyverno's workload policy covers
`Rollout` objects as well as `Deployment` objects.
