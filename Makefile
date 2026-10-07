CHART := charts/nexus
BOOTSTRAP_CHART := bootstrap/root
ENVIRONMENT ?= dev
ENVIRONMENT_VALUES := environments/$(ENVIRONMENT)/values.yaml

.PHONY: lint lint-all lint-bootstrap template template-bootstrap package

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
