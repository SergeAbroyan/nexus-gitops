# 0008. A GitHub workflow promotes releases instead of Kargo

Status: superseded by `nexus-applications` ADR 0008, which moved deployments
to a `Deploy` workflow in the application repository

## Context

Kargo models stages and freight and promotes them automatically. This project
has three environments, two services, and image tags in plain values files.

## Decision

The `Promote release` workflow copies the tested image tags from the previous
environment, waits for the reviewers of the target GitHub environment, and
commits the change.

## Consequences

Promotions are ordinary commits with an approval, and the history of
`environments/` is the deployment log. There is no automatic promotion on
verification results; Kargo becomes worth its extra controller when there are
more stages or services.
