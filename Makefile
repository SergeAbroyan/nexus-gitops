APPLICATION_CHART := charts/applications/nexus
KARPENTER_CHART := charts/platform/karpenter
KARPENTER_TEST_VALUES := charts/platform/karpenter/test-values.yaml
STORAGE_CHART := charts/platform/storage
STORAGE_TEST_VALUES := charts/platform/storage/test-values.yaml
INGRESS_CHART := charts/platform/ingress
CLOUDBEAVER_CHART := charts/tools/cloudbeaver
ENVIRONMENT ?= dev
ENVIRONMENT_VALUES := environments/$(ENVIRONMENT)/values.yaml

.PHONY: lint lint-all template

lint:
	helm lint $(APPLICATION_CHART) --values $(ENVIRONMENT_VALUES)

lint-all:
	helm lint $(APPLICATION_CHART) --values environments/dev/values.yaml
	helm lint $(APPLICATION_CHART) --values environments/staging/values.yaml
	helm lint $(APPLICATION_CHART) --values environments/production/values.yaml
	helm lint $(KARPENTER_CHART) --values $(KARPENTER_TEST_VALUES)
	helm lint $(STORAGE_CHART) --values $(STORAGE_TEST_VALUES)
	helm lint $(INGRESS_CHART)
	helm lint $(CLOUDBEAVER_CHART)

template:
	helm template nexus $(APPLICATION_CHART) --namespace nexus --values $(ENVIRONMENT_VALUES)
