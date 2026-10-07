CHART := charts/nexus
BOOTSTRAP_CHART := bootstrap/root
BOOTSTRAP_TEST_VALUES := bootstrap/root/test-values.yaml
KARPENTER_CONFIG_CHART := platform/karpenter
KARPENTER_TEST_VALUES := platform/karpenter/test-values.yaml
ENVIRONMENT ?= dev
ENVIRONMENT_VALUES := environments/$(ENVIRONMENT)/values.yaml

.PHONY: lint lint-all lint-bootstrap template template-bootstrap package

lint:
	helm lint $(CHART) --values $(ENVIRONMENT_VALUES)

lint-all:
	helm lint $(CHART) --values environments/dev/values.yaml
	helm lint $(CHART) --values environments/staging/values.yaml
	helm lint $(CHART) --values environments/production/values.yaml
	helm lint $(BOOTSTRAP_CHART) --values $(BOOTSTRAP_TEST_VALUES)
	helm lint $(KARPENTER_CONFIG_CHART) --values $(KARPENTER_TEST_VALUES)
	helm lint platform/storage --values platform/storage/test-values.yaml
	helm lint platform/cloudbeaver

lint-bootstrap:
	helm lint $(BOOTSTRAP_CHART) --values $(BOOTSTRAP_TEST_VALUES)

template:
	helm template nexus $(CHART) --namespace nexus --values $(ENVIRONMENT_VALUES)

template-bootstrap:
	helm template nexus-bootstrap $(BOOTSTRAP_CHART) --namespace argocd --values $(BOOTSTRAP_TEST_VALUES)

package:
	helm package $(CHART) --destination charts
