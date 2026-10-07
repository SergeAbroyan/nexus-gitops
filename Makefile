CHART := charts/nexus
BOOTSTRAP_CHART := bootstrap/root
ENVIRONMENT ?= dev
ENVIRONMENT_VALUES := environments/$(ENVIRONMENT)/values.yaml
ARGO_CD_CHART_VERSION := 10.9.6

.PHONY: lint lint-all lint-bootstrap template template-bootstrap package bootstrap-argocd bootstrap-root

lint:
	helm lint $(CHART) --values $(ENVIRONMENT_VALUES)

lint-all:
	helm lint $(CHART) --values environments/dev/values.yaml
	helm lint $(CHART) --values environments/staging/values.yaml
	helm lint $(CHART) --values environments/production/values.yaml
	helm lint $(BOOTSTRAP_CHART)

lint-bootstrap:
	helm lint $(BOOTSTRAP_CHART)

template:
	helm template nexus $(CHART) --namespace nexus --values $(ENVIRONMENT_VALUES)

template-bootstrap:
	helm template nexus-bootstrap $(BOOTSTRAP_CHART) --namespace argocd

package:
	helm package $(CHART) --destination charts

bootstrap-argocd:
	helm upgrade --install argocd argo-cd \
		--repo https://argoproj.github.io/argo-helm \
		--version $(ARGO_CD_CHART_VERSION) \
		--namespace argocd \
		--create-namespace \
		--values bootstrap/argocd/values.yaml \
		--wait

bootstrap-root:
	helm upgrade --install nexus-bootstrap $(BOOTSTRAP_CHART) \
		--namespace argocd \
		--wait
