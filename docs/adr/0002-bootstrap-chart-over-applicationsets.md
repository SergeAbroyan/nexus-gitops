# 0002. A Helm bootstrap chart renders every Application

Status: accepted

## Context

Argo CD can generate Applications with ApplicationSets or with an app-of-apps
chart. Each cluster here has the same Applications with different facts, sync
waves, and a few per-Application options such as `ignoreDifferences`.

## Decision

The `bootstrap` chart turns the catalog in `bootstrap/values.yaml` into
Applications, merging the wiring from `_wiring.tpl`. The ApplicationSet
controller is disabled.

## Consequences

The whole catalog renders with `helm template`, so CI can render every
Application exactly as Argo CD would and validate the result offline. Adding an
Application is one catalog entry. Managing many clusters from one Argo CD would
need a cluster generator, which a later record can introduce.
