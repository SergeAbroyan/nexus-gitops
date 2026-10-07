APPLICATION_CHART := charts/applications/nexus
BOOTSTRAP_CHART := bootstrap/root
BOOTSTRAP_TEST_VALUES := bootstrap/root/test-values.yaml
KARPENTER_CHART := charts/platform/karpenter
KARPENTER_TEST_VALUES := charts/platform/karpenter/test-values.yaml
STORAGE_CHART := charts/platform/storage
STORAGE_TEST_VALUES := charts/platform/storage/test-values.yaml
CLOUDBEAVER_CHART := charts/tools/cloudbeaver
ENVIRONMENT ?= dev
ENVIRONMENT_VALUES := environments/$(ENVIRONMENT)/values.yaml

.PHONY: lint lint-all lint-bootstrap template template-bootstrap

lint:
	helm lint $(APPLICATION_CHART) --values $(ENVIRONMENT_VALUES)

lint-all:
	helm lint $(APPLICATION_CHART) --values environments/dev/values.yaml
	helm lint $(APPLICATION_CHART) --values environments/staging/values.yaml
	helm lint $(APPLICATION_CHART) --values environments/production/values.yaml
	helm lint $(BOOTSTRAP_CHART) --values $(BOOTSTRAP_TEST_VALUES)
	helm lint $(KARPENTER_CHART) --values $(KARPENTER_TEST_VALUES)
	helm lint $(STORAGE_CHART) --values $(STORAGE_TEST_VALUES)
	helm lint $(CLOUDBEAVER_CHART)

lint-bootstrap:
	helm lint $(BOOTSTRAP_CHART) --values $(BOOTSTRAP_TEST_VALUES)

template:
	helm template nexus $(APPLICATION_CHART) --namespace nexus --values $(ENVIRONMENT_VALUES)

template-bootstrap:
	helm template nexus-bootstrap $(BOOTSTRAP_CHART) --namespace argocd --values $(BOOTSTRAP_TEST_VALUES)
