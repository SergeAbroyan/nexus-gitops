APPLICATION_CHART := charts/applications/nexus
KARPENTER_CHART := charts/platform/karpenter
KARPENTER_TEST_VALUES := charts/platform/karpenter/test-values.yaml
STORAGE_CHART := charts/platform/storage
STORAGE_TEST_VALUES := charts/platform/storage/test-values.yaml
INGRESS_CHART := charts/platform/ingress
CLOUDBEAVER_CHART := charts/tools/cloudbeaver
ENVIRONMENT ?= dev
ENVIRONMENT_VALUES := environments/$(ENVIRONMENT)/values.yaml
RENDER_DIRECTORY ?= .rendered

.PHONY: lint lint-all template template-all render-all

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

template-all:
	helm template nexus-dev $(APPLICATION_CHART) --namespace nexus --values environments/dev/values.yaml > /dev/null
	helm template nexus-staging $(APPLICATION_CHART) --namespace nexus --values environments/staging/values.yaml > /dev/null
	helm template nexus-production $(APPLICATION_CHART) --namespace nexus --values environments/production/values.yaml > /dev/null
	helm template karpenter-config $(KARPENTER_CHART) --namespace kube-system --values $(KARPENTER_TEST_VALUES) > /dev/null
	helm template storage-config $(STORAGE_CHART) --namespace kube-system --values $(STORAGE_TEST_VALUES) > /dev/null
	helm template ingress-config $(INGRESS_CHART) --namespace istio-ingress > /dev/null
	helm template cloudbeaver $(CLOUDBEAVER_CHART) --namespace cloudbeaver > /dev/null

render-all:
	mkdir -p $(RENDER_DIRECTORY)
	helm template nexus-dev $(APPLICATION_CHART) --namespace nexus --values environments/dev/values.yaml > $(RENDER_DIRECTORY)/nexus-dev.yaml
	helm template nexus-staging $(APPLICATION_CHART) --namespace nexus --values environments/staging/values.yaml > $(RENDER_DIRECTORY)/nexus-staging.yaml
	helm template nexus-production $(APPLICATION_CHART) --namespace nexus --values environments/production/values.yaml > $(RENDER_DIRECTORY)/nexus-production.yaml
	helm template karpenter-config $(KARPENTER_CHART) --namespace kube-system --values $(KARPENTER_TEST_VALUES) > $(RENDER_DIRECTORY)/karpenter.yaml
	helm template storage-config $(STORAGE_CHART) --namespace kube-system --values $(STORAGE_TEST_VALUES) > $(RENDER_DIRECTORY)/storage.yaml
	helm template ingress-config $(INGRESS_CHART) --namespace istio-ingress > $(RENDER_DIRECTORY)/ingress.yaml
	helm template cloudbeaver $(CLOUDBEAVER_CHART) --namespace cloudbeaver > $(RENDER_DIRECTORY)/cloudbeaver.yaml
