BASE_CHART := charts/base
RUNTIME_CHART := charts/applications/nexus-runtime
API_CHART := charts/applications/api
WORKER_CHART := charts/applications/worker
KARPENTER_CHART := charts/platform/karpenter
KARPENTER_TEST_VALUES := charts/platform/karpenter/test-values.yaml
STORAGE_CHART := charts/platform/storage
STORAGE_TEST_VALUES := charts/platform/storage/test-values.yaml
INGRESS_CHART := charts/platform/ingress
INGRESS_TEST_VALUES := charts/platform/ingress/test-values.yaml
CLOUDBEAVER_CHART := charts/platform/cloudbeaver
DEPENDENT_CHARTS := $(RUNTIME_CHART) $(API_CHART) $(WORKER_CHART) $(INGRESS_CHART) $(CLOUDBEAVER_CHART)

ENVIRONMENT ?= dev
GLOBAL_VALUES := environments/global-values.yaml
ENVIRONMENT_DIRECTORY := environments/$(ENVIRONMENT)
RENDER_DIRECTORY ?= .rendered

.PHONY: dependencies lint lint-all template render-all

dependencies:
	@set -e; for chart in $(DEPENDENT_CHARTS); do helm dependency build --skip-refresh "$$chart"; done

lint: dependencies
	helm lint $(RUNTIME_CHART) --values $(GLOBAL_VALUES) --values $(ENVIRONMENT_DIRECTORY)/runtime-values.yaml
	helm lint $(API_CHART) --values $(GLOBAL_VALUES) --values $(ENVIRONMENT_DIRECTORY)/api-values.yaml
	helm lint $(WORKER_CHART) --values $(GLOBAL_VALUES) --values $(ENVIRONMENT_DIRECTORY)/worker-values.yaml

lint-all: dependencies
	helm lint $(BASE_CHART)
	@set -e; for environment in dev staging production; do \
		helm lint $(RUNTIME_CHART) --values $(GLOBAL_VALUES) --values environments/$$environment/runtime-values.yaml; \
		helm lint $(API_CHART) --values $(GLOBAL_VALUES) --values environments/$$environment/api-values.yaml; \
		helm lint $(WORKER_CHART) --values $(GLOBAL_VALUES) --values environments/$$environment/worker-values.yaml; \
	done
	helm lint $(KARPENTER_CHART) --values $(KARPENTER_TEST_VALUES)
	helm lint $(STORAGE_CHART) --values $(STORAGE_TEST_VALUES)
	helm lint $(INGRESS_CHART) --values $(INGRESS_TEST_VALUES)
	helm lint $(CLOUDBEAVER_CHART)

template: dependencies
	helm template nexus-runtime $(RUNTIME_CHART) --namespace nexus --values $(GLOBAL_VALUES) --values $(ENVIRONMENT_DIRECTORY)/runtime-values.yaml
	helm template nexus-api $(API_CHART) --namespace nexus --values $(GLOBAL_VALUES) --values $(ENVIRONMENT_DIRECTORY)/api-values.yaml
	helm template nexus-worker $(WORKER_CHART) --namespace nexus --values $(GLOBAL_VALUES) --values $(ENVIRONMENT_DIRECTORY)/worker-values.yaml

render-all: dependencies
	mkdir -p $(RENDER_DIRECTORY)
	@set -e; for environment in dev staging production; do \
		helm template nexus-runtime $(RUNTIME_CHART) --namespace nexus --values $(GLOBAL_VALUES) --values environments/$$environment/runtime-values.yaml > $(RENDER_DIRECTORY)/nexus-runtime-$$environment.yaml; \
		helm template nexus-api $(API_CHART) --namespace nexus --values $(GLOBAL_VALUES) --values environments/$$environment/api-values.yaml > $(RENDER_DIRECTORY)/nexus-api-$$environment.yaml; \
		helm template nexus-worker $(WORKER_CHART) --namespace nexus --values $(GLOBAL_VALUES) --values environments/$$environment/worker-values.yaml > $(RENDER_DIRECTORY)/nexus-worker-$$environment.yaml; \
	done
	helm template karpenter-config $(KARPENTER_CHART) --namespace kube-system --values $(KARPENTER_TEST_VALUES) > $(RENDER_DIRECTORY)/karpenter.yaml
	helm template storage-config $(STORAGE_CHART) --namespace kube-system --values $(STORAGE_TEST_VALUES) > $(RENDER_DIRECTORY)/storage.yaml
	helm template ingress-config $(INGRESS_CHART) --namespace istio-ingress --values $(INGRESS_TEST_VALUES) > $(RENDER_DIRECTORY)/ingress.yaml
	helm template cloudbeaver $(CLOUDBEAVER_CHART) --namespace cloudbeaver > $(RENDER_DIRECTORY)/cloudbeaver.yaml
