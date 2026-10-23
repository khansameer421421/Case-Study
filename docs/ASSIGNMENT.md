# Case-Study
Scalable Disk Monitoring Solution for Cloud Environments

Scalable Disk Monitoring Solution for Cloud Environments 
Background: 
You are a Solutions Architect at a large multi-cloud enterprise using services across AWS, Azure, and GCP. The company has grown through acquisitions and now manages multiple AWS Accounts, Azure Subscriptions, and GCP Projects, each containing numerous virtual machines (VMs). 
The CTO has expressed concerns about potential disk space issues across these environments leading to downtime and wants a comprehensive solution to monitor disk utilization. 
Assignment: 
The company currently uses Ansible as its configuration management tool. Before investing in third-party monitoring platforms, leadership prefers to leverage the existing stack or incorporate any cloud-native services only if they provide substantial benefits. 
Your Task: 
Choose one cloud service provider (AWS, Azure, or GCP) and design a solution to monitor disk utilization across all VMs for that provider. The goal is to detect low disk space early and minimize risk of downtime for that provider. 
You are encouraged to choose the provider you are most comfortable with. 
Your solution should cover the following, keeping security and scalability in mind: 
1. Ease of Access & Management 
○ How will you securely manage VMs across multiple accounts/projects? ○ How will Ansible connect or collect data from the VMs reliably and securely? 2. Data Collection & Aggregation 
○ How will you gather disk usage data from all VMs? 
○ How will you centralize and present this data for easy monitoring? 
3. Scalability 
○ How will your solution handle growth as more accounts or VMs are added over time? 
Deliverables: 
1. Provide a high-level architectural diagram of your proposed solution. 2. Provide Ansible playbooks or roles or other artifacts, including those that highlight minimal working of solution(Data collection, aggregation, access management, scalability) 
3. Summarize the key components of your solution, such as: 
● Access management.
● VM Discovery and Enrollment for metric collection 
Submit your code snippets, playbooks, and documentation via a public GitHub repository and include the link in your submission.
