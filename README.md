# LegacyLens Core Infrastructure - 10-Day AWS & DevOps Engineering Log

This repository documents the production-grade deployment of the **LegacyLens** cloud architecture using Infrastructure as Code (IaC) with Terraform, Linux system auditing, PostgreSQL database engineering, and security-first network design in the `ap-south-1` (Mumbai) region.

---

## Day 1: Infrastructure as Code (IaC) Foundation

Today, I transitioned the core network architecture for the LegacyLens project from a manual AWS Web Console deployment into a repeatable, automated Infrastructure as Code (IaC) configuration using Terraform. This foundation establishes a secure, multi-tier cloud environment optimized for scalable container and database components, deployed directly within the `ap-south-1` (Mumbai) region.

The core infrastructure centers around a custom Virtual Private Cloud named `Legacylens-VPC` with a `10.0.0.0/16` CIDR block. To guarantee strict boundary isolation, the space is segmented into three distinct subnets: a public tier (`10.0.1.0/24`) providing inbound/outbound edge routing, a private application tier (`10.0.2.0/24`) allocated for container hosting in availability zone `ap-south-1a`, and a completely isolated private database tier (`10.0.3.0/24`) mapped to `ap-south-1b`. External internet connectivity is mediated through a dedicated Internet Gateway linked via a public route table associated exclusively with the public subnet.

To validate routing compliance, I provisioned an external-facing `t3.micro` EC2 Bastion host running Amazon Linux 2023 inside the perimeter. Verification was successfully completed via native PowerShell SSH sessions using locked-down `.pem` file permissions via Windows Access Control Lists (`icacls.exe`). Diagnostic verification commands—including `ping` and `traceroute google.com` executed directly from the cloud instance shell—confirmed 0% packet loss and clean ICMP edge transit, validating the underlying VPC route tables before sealing the layout permanently in the final declarative configuration.

---

## Day 2: Subnet Isolation and Networking Port Diagnostics

### Why a Database Must Reside in a Private Subnet
In a production-ready cloud architecture, the database tier represents the critical state engine of the entire system. Placing the database inside a private subnet is a fundamental application of the **Principle of Least Privilege** and the **Defense-in-Depth** security model for several critical reasons:

* **Elimination of Public Attack Surface:** A private subnet does not possess an attached Internet Gateway (IGW) route handler, and resources within it are assigned private IP addresses (`10.0.3.0/24`). This renders the database completely invisible and unreachable from the public internet, preventing automated brute-force attempts and network-level scans.
* **Granular Network Control:** Traffic entering the private database tier is strictly restricted using AWS Stateful Firewalls (Security Groups). In this setup, the database (`Legacylens-DB-SG`) rejects all incoming requests unless they explicitly originate from the Private Application Subnet (`10.0.2.0/24`) over the designated PostgreSQL port (`5432`). 
* **Controlled Isolation:** Even if a public-facing component (like the Bastion host or an ingress proxy) is compromised, an attacker cannot route directly into the data layer without pivoting horizontally through hardened internal application checkpoints.

### Port-Binding Diagnostics via `ss -tulpn`
To verify how the operating system manages network sockets inside our secure environment, we used the modern kernel utility `ss -tulpn` (Socket Statistics).

#### Understanding the Diagnostic Flags
* **`-t`**: Filters for TCP stream sockets (reliable connection-oriented traffic).
* **`-u`**: Filters for UDP datagram sockets (fast connectionless traffic).
* **`-l`**: Restricts the display to sockets currently in the LISTEN state.
* **`-p`**: Extracts the specific internal Process Name and Process ID (PID).
* **`-n`**: Forces raw Numeric ports and addresses to display.

#### Live Output Breakdown & Core Takeaways
Running this on our active Ubuntu Bastion Host revealed the following structural mappings:
1. **`tcp LISTEN 0 4096 *:22 *:*`**: The SSH daemon (`sshd`) is listening globally on port `22` across all network interfaces (`*`).
2. **`udp UNCONN 0 0 127.0.0.53%lo:53 0.0.0.0:*`**: The system local caching DNS resolver (`systemd-resolved`) is bound strictly to the loopback interface (`lo`), completely hidden from outside network interface cards.

### Outbound Data Egress Lifecycle (The NAT Gateway Pipeline)
To protect our internal computing tier while maintaining the ability to pull package updates and connect to external APIs, we engineered a unidirectional outbound traffic system:

```text
                      [ Internet ]
                           ^
                           | (Outbound Response)
                   [ Internet Gateway ]
                           ^
                           |
            [ Public Subnet (10.0.1.0/24) ] 
             👉 Hosts: [ NAT Gateway (with Elastic IP) ]
                           ^
                           | (Route: 0.0.0.0/0 -> NAT Gateway)
          [ Private App Subnet (10.0.2.0/24) ]
             👉 Hosts: [ Node.js App Server ]

             Day 3: EC2 Compute Provisioning & Asymmetric Key Cryptography
🎯 Architectural Objective
Bridge the physical VPC networking layout from Day 2 with the robust Bastion security models required for Day 4 by correctly provisioning EC2 compute resources via Terraform and configuring asymmetric cryptography for secure access.

🛠️ Technical Execution
Declarative Compute Deployment: Authored Terraform aws_instance blocks to provision t3.micro EC2 compute nodes. Selected specific Amazon Machine Images (AMIs) aligned with Ubuntu 22.04 LTS to ensure a standardized Linux runtime for backend workloads.

Cryptographic Key Management: Generated local RSA 4096-bit key pairs (.pem / .pub) and utilized the aws_key_pair Terraform resource to inject the public key into the AWS hypervisor instance metadata.

Idempotent State Management: Verified that Terraform tracks the exact state of deployed EC2 compute units, allowing seamless updates and teardowns without leaving orphaned resources in ap-south-1.

Day 4: Stateful Firewalls, Bastion Architecture, and Security Group Correlation
🎯 Architectural Objective
Implementing a multi-layered Chain of Trust security framework. By separating public access controllers from private core resources and configuring advanced firewall dependencies, we ensured that our multi-tenant backend infrastructure remains completely hidden from external network sweeps while maintaining smooth administrative manageability.

📚 Core Conceptual Framework
Bastion Host: A highly hardened virtual machine deployed explicitly in the public entry network serving as the single, tightly monitored digital checkpoint for network management.

Security Group: A dynamic, host-level stateful firewall wrapping individual cloud resources.

Stateful Routing: A smart security feature where the firewall automatically tracks inbound connections and opens response paths automatically without manual outbound rule clutter.

🔒 The Power of Security Group Nesting
Instead of hardcoding easily spoofed IP ranges, we implemented Security Group Nesting. We configured the private application firewall to accept incoming traffic only if it originates from a resource wearing the specific Bastion Security Group Badge (security_groups = [aws_security_group.bastion_sg.id]).

Why this is highly secure:
Dynamic Resiliency: If the Bastion Host's internal IP changes, the backend vault doesn't break—the network tracks the identity badge, not the IP address.

Absolute External Rejection: Any data packet sent to the private application tier is dropped at the edge unless it carries the verified tracking token of our public guard.

🧪 System Audits & Diagnostic Telemetry
Direct Internet Attack (Blocked): Attempting to bridge straight from a home network to the vault console (10.0.2.112) returned an immediate Connection refused.

Chain of Trust Jump (Passed): Leveraging local ssh-agent keys to securely forward credential signatures through the Bastion proxy allowed immediate vault entry.

Session Verification (w): Live telemetry inside the vault verified the source profile originated strictly from the Bastion internal identity (10.0.1.x).

Day 5: Production Managed Databases & Multi-AZ Network Group Isolation
Today, I expanded the LegacyLens infrastructure by provisioning a production-ready, fully isolated AWS RDS PostgreSQL Engine using declarative Terraform blocks.

Core Parameter Breakdown & Operational Engineering Value:
allocated_storage = 20: Allocates a 20 GB General Purpose SSD storage tier.

engine = "postgres" & engine_version = "16.1": Installs a clean PostgreSQL 16.1 distribution.

instance_class = "db.t4g.micro": Leverages an ARM-based AWS Graviton4-optimized micro-instance, delivering superior price-to-performance scaling compared to older x86 instances.

db_subnet_group_name: The primary isolation anchor. Restricts database deployment strictly to multi-AZ private subnets across ap-south-1a and ap-south-1b.

vpc_security_group_ids: Enforces microsegmentation boundaries. Rejects all network connection handshakes unless they originate strictly over TCP Port 5432 from the private application server's security profile.

skip_final_snapshot = true: Developer-velocity optimization to allow fast iteration during sandbox testing.

Day 6: Infrastructure Deployment & Secure Inside-VPC Database Handshake Verification
🛠️ Tasks Executed
Live RDS Provisioning: Executed terraform apply to deploy a managed Multi-AZ PostgreSQL 16 relational database tier across isolated subnets.

Jump Host Tunnel Routing: Leveraged local SSH Jump tunneling via the public Bastion host gate (35.154.59.9) to securely bridge access into the private application instance environment (10.0.2.128).

Linux Node Patching & Tooling Deployment: Updated the internal Linux package manager index and installed native database utilities:

Bash
sudo apt-get update -y
sudo apt-get install postgresql-client -y

psql -h terraform-044b39d4f87acf5e351c17466b.cfew2m0cwv6o.ap-south-1.rds.amazonaws.com -U db_admin_user -d legacylens_prod
Day 7: Programmatic Node.js Environment Isolation & Database Socket Verification
🛠️ Tasks Executed
Runtime Provisioning via NVM: Installed Node Version Manager (NVM) and provisioned Node.js v22.23.1 (LTS) along with npm on the private application server node (10.0.2.105).

Project Workspace & Dependency Management: Created ~/legacylens-core workspace and installed pg (node-postgres) driver and dotenv for secret isolation.

Secrets Decoupling: Configured .env file to hold database host endpoints, credentials, and parameters safely outside application code.

Programmatic Socket Handshake: Authored db-test.js to execute an asynchronous pool connection to the RDS Multi-AZ PostgreSQL cluster, validating query execution (SELECT NOW()) over TLS.

🔒 Security & Architectural Insights
Zero Secrets in Version Control: Decoupling sensitive parameters via .env prevents credential exposure in version control. At runtime, dotenv loads configuration directly into process.env in memory.

Non-Blocking Asynchronous I/O & Connection Pooling: The pg driver utilizes Node.js event loops to manage database sockets asynchronously without blocking concurrent HTTP application requests.

Day 8: Multi-Tenant Schema Isolation & Dynamic Search Path Driver
🛠️ Tasks Executed
Isolated Schema Creation: Designed and executed day8_multitenant.sql to establish two logical schema boundaries (tenant_alpha and tenant_beta) inside a shared PostgreSQL RDS database.

Schema-Level Data Segregation: Provisioned assets tables, primary keys, performance indices (idx_alpha_asset_name, idx_beta_asset_name), and seed records within each independent tenant namespace.

Dynamic Driver Implementation: Authored index.js utilizing pg.Pool to execute session-level SET search_path TO <tenant_schema> statements before query execution.

🔒 Architectural Insights
Schema-Based Multi-Tenancy: Using schema isolation balances resource usage and database cost while providing strict logical data boundaries between different tenants without requiring separate physical database instances.

Dynamic Connection Context: Setting search_path per connection checkout allows standard, uniform SQL queries (e.g., SELECT * FROM assets) to automatically target the correct tenant's data safely and efficiently.

Day 9: Private Database Isolation & Multi-Tenant Schema Configuration
🎯 Objective
Secure the LegacyLens PostgreSQL database within a private AWS VPC subnet, establish zero-trust access using an EC2 Bastion host via AWS Systems Manager (SSM), and implement a multi-tenant database schema for client data isolation.

🛠️ Tech Stack & AWS Services
Compute: AWS EC2 (Ubuntu Bastion Host), AWS Systems Manager (SSM)

Database: Amazon RDS (PostgreSQL 16)

Networking: Amazon VPC (Private Subnets), Security Groups

Infrastructure as Code: Terraform

Tools: psql, AWS CLI, Bash/PowerShell

🏗️ Architecture & Security Highlights
Zero-Trust Access (No SSH): Eliminated the need for public IP addresses or opening Port 22. All administrative database access is routed securely through an EC2 Bastion host using AWS SSM Session Manager.

Private Subnet Isolation: Deployed the RDS instance strictly within private subnets. The database is completely invisible to the public internet.

Security Group Chaining: Configured the database Security Group to drop all connections except explicitly whitelisted internal VPC traffic (port 5432).

Multi-Tenant Schema Design: Engineered a highly scalable PostgreSQL architecture using isolated schemas (tenant_alpha, tenant_beta) and dynamic search_path routing to securely separate restaurant data within a single database instance.

🧪 Troubleshooting & Debugging Realities
VPC Firewall Blockages: Diagnosed a database connection timeout by identifying a missing inbound rule on the RDS Security Group. Successfully modified the SG to allow internal 10.0.0.0/16 traffic.

Database Authentication: Troubleshot and bypassed local tunnel authentication failures, switching to direct Bastion access to successfully authenticate the db_admin_user.

Connection Monitoring: Executed administrative SQL queries (SELECT count(*) FROM pg_stat_activity;) to monitor connection pool health and prevent exhaustion.

Day 10: Linux Network Diagnostics & Automated Database Migrations
🎯 Objective
Perform internal VPC network diagnostics using native Linux tools and deploy an idempotent, multi-tenant database migration script to an AWS RDS PostgreSQL instance via an EC2 Bastion host.

🛠️ Tech Stack & Tools
Compute / OS: AWS EC2, Ubuntu Linux

Database: PostgreSQL 16 (Amazon RDS)

Networking: ss, iproute2, Netcat (nc)

Version Control: Git, GitHub

Scripting: SQL, Bash

🏗️ Technical Execution
1. Advanced Linux Network Auditing
Instead of relying on GUI tools or AWS console dashboards, I utilized native Linux networking commands from inside the Bastion host to audit the environment:

ss -tulpn: Inspected all listening TCP/UDP ports. Verified that SSH and SSM agents were running, while ensuring no rogue database services were running locally.

ip route show: Traced the internal IP routing table to confirm traffic was properly routing through the VPC's implicit router (10.0.1.1).

nc -zv 127.0.0.1 5432: Performed a raw TCP handshake test on the local loopback address. The Connection refused response validated the decoupled architecture: the database is strictly isolated on its own RDS instance.

2. Idempotent Multi-Tenant Migrations
Transitioned from manual SQL queries to an automated, production-ready migration script (day10_schema_migration.sql):

Transactional Safety: Wrapped the execution in a BEGIN; and COMMIT; block to ensure the database would not be left in a corrupted state if the script failed halfway through.

Idempotency: Utilized IF NOT EXISTS clauses for schema and table creation. This ensures the script can be run multiple times without throwing duplication errors or overwriting existing client data.

Data Isolation: Enforced strict logical separation between tenant_alpha and tenant_beta within a shared RDS instance, preparing the architecture for a scalable, multi-tenant application.

💡 Cloud Architecture Takeaways
Infrastructure as Code (IaC) Principles in SQL: Writing database migrations must follow the same idempotent principles as Terraform—describing the desired state rather than just a series of blind commands.

Decoupled Architecture: Proving a port is closed on a Bastion server is just as important as proving it is open on the target database server.