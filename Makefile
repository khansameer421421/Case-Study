.PHONY: deps inventory graph enroll collect alarms prune dashboard site demo lint

deps:            ## install Python deps and Ansible collections
	pip install -r requirements.txt
	ansible-galaxy collection install -r requirements.yml

inventory:       ## discover accounts and regenerate per-account inventory sources
	ansible-playbook playbooks/generate_inventory.yml

graph:           ## show what was discovered (groups: account_*, region_*, env_*, linux, windows)
	ansible-inventory --graph

enroll:          ## install/configure the CloudWatch agent everywhere
	ansible-playbook playbooks/enroll_cloudwatch_agent.yml

collect:         ## Ansible-native collection + JSON/CSV/HTML report
	ansible-playbook playbooks/collect_disk_usage.yml

alarms:          ## per-filesystem CloudWatch alarms
	ansible-playbook playbooks/configure_alarms.yml

prune:           ## delete alarms of terminated instances
	ansible-playbook playbooks/prune_alarms.yml

dashboard:       ## central cross-account CloudWatch dashboard
	ansible-playbook playbooks/deploy_dashboard.yml

site: inventory  ## the scheduled job: inventory, then enroll + collect + alarms + prune
	ansible-playbook playbooks/site.yml

demo:            ## run collection + reporting against this machine, no AWS needed
	ansible-playbook -i inventories/local playbooks/collect_disk_usage.yml
	@echo "Open reports/latest/disk_report.html"

lint:
	yamllint .
	ansible-lint
	cfn-lint cloudformation/*.yml
