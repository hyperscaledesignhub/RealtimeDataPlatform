.PHONY: help init plan apply destroy fmt validate clean

# Variables
TERRAFORM := terraform
AWS_REGION ?= us-west-2
CLUSTER_NAME ?= flink-benchmark-low

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

init: ## Initialize Terraform
	$(TERRAFORM) init

plan: ## Show Terraform plan
	$(TERRAFORM) plan

apply: ## Apply Terraform configuration
	$(TERRAFORM) apply

apply-auto: ## Apply without confirmation
	$(TERRAFORM) apply -auto-approve

destroy: ## Destroy all resources
	@echo "WARNING: This will destroy all resources!"
	@echo "Press Ctrl+C to cancel or Enter to continue..."
	@read
	$(TERRAFORM) destroy

destroy-auto: ## Destroy without confirmation
	$(TERRAFORM) destroy -auto-approve

fmt: ## Format Terraform files
	$(TERRAFORM) fmt -recursive

validate: ## Validate Terraform configuration
	$(TERRAFORM) validate

clean: ## Clean Terraform files
	rm -rf .terraform
	rm -f .terraform.lock.hcl
	rm -f terraform.tfstate*
	rm -f *.backup

output: ## Show Terraform outputs
	$(TERRAFORM) output

output-json: ## Show outputs in JSON format
	$(TERRAFORM) output -json

refresh: ## Refresh Terraform state
	$(TERRAFORM) refresh

show: ## Show Terraform state
	$(TERRAFORM) show

config-kubectl: ## Configure kubectl for the EKS cluster
	@echo "Configuring kubectl..."
	aws eks update-kubeconfig --region $(AWS_REGION) --name $(CLUSTER_NAME)
	kubectl get nodes

cost-estimate: ## Estimate monthly costs
	@echo "Estimated monthly cost for low-cost infrastructure:"
	@echo "  - EKS Control Plane: ~$$73/month"
	@echo "  - t3.medium nodes (2): ~$$60/month ($$30 each, or $$3-9/month with spot)"
	@echo "  - t3.small node (1): ~$$15/month (or $$1.5-4.5/month with spot)"
	@echo "  - NAT Gateway (1): ~$$32/month"
	@echo "  - EBS Storage: ~$$10-20/month"
	@echo "  - Data Transfer: ~$$10/month"
	@echo ""
	@echo "  Total (On-Demand): ~$$200/month"
	@echo "  Total (Spot Instances): ~$$120-140/month"

check: fmt validate ## Run format and validation checks

upgrade: ## Upgrade provider versions
	$(TERRAFORM) init -upgrade

