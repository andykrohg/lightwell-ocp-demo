NAMESPACE ?= lightwell-demo
IMAGE_REGISTRY ?= quay.io/andy_krohg

.PHONY: help setup demo reset build-vulnerable build-remediated hub-build \
        pipeline-vulnerable pipeline-remediated pipeline-logs status

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}'

setup: ## One-time cluster setup (requires demo.env with ROX_API_TOKEN)
	./scripts/setup.sh

demo: ## Run the guided interactive demo
	./scripts/demo.sh

reset: ## Reset demo state (deletes pipeline runs and app deployments)
	./scripts/reset.sh

build-vulnerable: ## Build catalog-app locally with vulnerable profile
	cd catalog-app && mvn -P vulnerable clean package -DskipTests

build-remediated: ## Build catalog-app locally with remediated profile
	cd catalog-app && mvn -P remediated clean package -DskipTests

hub-build: ## Build demo hub container image
	cd demo-hub && podman build -t $(IMAGE_REGISTRY)/lightwell-demo-hub:latest -f Containerfile .

catalog-build-vulnerable: ## Build catalog-app container image (vulnerable)
	cd catalog-app && podman build --build-arg MAVEN_PROFILE=vulnerable -t $(IMAGE_REGISTRY)/lightwell-demo-catalog:vulnerable-latest -f Containerfile .

catalog-build-remediated: ## Build catalog-app container image (remediated)
	cd catalog-app && podman build --build-arg MAVEN_PROFILE=remediated -t $(IMAGE_REGISTRY)/lightwell-demo-catalog:remediated-latest -f Containerfile .

pipeline-vulnerable: ## Trigger the vulnerable build pipeline
	@source ./scripts/resolve-env.sh && \
	sed \
		-e "s|__DEMO_NAMESPACE__|$$DEMO_NAMESPACE|g" \
		-e "s|__TPA_URL__|$$TPA_URL|g" \
		-e "s|__TPA_OIDC_ISSUER_URL__|$$TPA_OIDC_ISSUER_URL|g" \
		-e "s|__TPA_CLIENT_SECRET__|$$TPA_CLIENT_SECRET|g" \
		-e "s|__ROX_CENTRAL_ENDPOINT__|$$ROX_CENTRAL_ENDPOINT|g" \
		-e "s|__ROX_API_TOKEN__|$$ROX_API_TOKEN|g" \
		tekton/pipelinerun-vulnerable.yaml | oc create -n $(NAMESPACE) -f -

pipeline-remediated: ## Trigger the remediated build pipeline
	@source ./scripts/resolve-env.sh && \
	sed \
		-e "s|__DEMO_NAMESPACE__|$$DEMO_NAMESPACE|g" \
		-e "s|__TPA_URL__|$$TPA_URL|g" \
		-e "s|__TPA_OIDC_ISSUER_URL__|$$TPA_OIDC_ISSUER_URL|g" \
		-e "s|__TPA_CLIENT_SECRET__|$$TPA_CLIENT_SECRET|g" \
		-e "s|__ROX_CENTRAL_ENDPOINT__|$$ROX_CENTRAL_ENDPOINT|g" \
		-e "s|__ROX_API_TOKEN__|$$ROX_API_TOKEN|g" \
		tekton/pipelinerun-remediated.yaml | oc create -n $(NAMESPACE) -f -

pipeline-logs: ## Follow the latest pipeline run logs
	tkn pipelinerun logs -f --last -n $(NAMESPACE)

status: ## Show demo deployment status
	@echo "=== Deployments ==="
	@oc get deployments -n $(NAMESPACE) 2>/dev/null || echo "Namespace not found"
	@echo ""
	@echo "=== Routes ==="
	@oc get routes -n $(NAMESPACE) 2>/dev/null || echo "Namespace not found"
	@echo ""
	@echo "=== Pipeline Runs ==="
	@tkn pipelinerun list -n $(NAMESPACE) 2>/dev/null || echo "No pipeline runs"
