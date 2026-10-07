CHART := charts/nexus
ENVIRONMENT ?= dev
ENVIRONMENT_VALUES := environments/$(ENVIRONMENT)/values.yaml

.PHONY: lint lint-all template package

lint:
	helm lint $(CHART) --values $(ENVIRONMENT_VALUES)

lint-all:
	helm lint $(CHART) --values environments/dev/values.yaml
	helm lint $(CHART) --values environments/staging/values.yaml
	helm lint $(CHART) --values environments/production/values.yaml

template:
	helm template nexus $(CHART) --namespace nexus --values $(ENVIRONMENT_VALUES)

package:
	helm package $(CHART) --destination charts
