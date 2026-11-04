# 0001. Terraform hands the cluster to Argo CD through one root Application

Status: accepted

## Context

Add-ons need AWS facts that only Terraform knows: role names, queue URLs, the
VPC, KMS keys. Installing add-ons with the Terraform Helm provider ties every
chart upgrade to a Terraform apply and stores rendered values in state.

## Decision

Terraform installs Argo CD and one `bootstrap` Application, and passes the AWS
facts as its Helm values. Everything that runs in Kubernetes is defined in this
repository. `bootstrap/values.schema.json` is the contract between the two.

## Consequences

Add-on changes are pull requests here, reviewed and rendered by CI, and reach
every cluster without Terraform. A new fact needs a change in both
repositories, and the schema rejects a cluster that does not provide it.
