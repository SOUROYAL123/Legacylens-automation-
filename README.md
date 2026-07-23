
# Legacylens Infrastructure as Code (IaC) - Day 1

Today, I transitioned the core network architecture for the Legacylens project from a manual AWS Web Console deployment into a repeatable, automated Infrastructure as Code (IaC) configuration using Terraform. This foundation establishes a secure, multi-tier cloud environment optimized for scalable container and database components, deployed directly within the `ap-south-1` (Mumbai) region.

The core infrastructure centers around a custom Virtual Private Cloud named `Legacylens-VPC` with a `10.0.0.0/16` CIDR block. To guarantee strict boundary isolation, the space is segmented into three distinct subnets: a public tier (`10.0.1.0/24`) providing inbound/outbound edge routing, a private application tier (`10.0.2.0/24`) allocated for container hosting in availability zone `ap-south-1a`, and a completely isolated private database tier (`10.0.3.0/24`) mapped to `ap-south-1b`. External internet connectivity is mediated through a dedicated Internet Gateway linked via a public route table associated exclusively with the public subnet.

To validate routing compliance, I provisioned an external-facing `t3.micro` EC2 Bastion host running Amazon Linux 2023 inside the perimeter. Verification was successfully completed via native PowerShell SSH sessions using locked-down `.pem` file permissions via Windows Access Control Lists (`icacls.exe`). Diagnostic verification commands—including `ping` and `traceroute google.com` executed directly from the cloud instance shell—confirmed 0% packet loss and clean ICMP edge transit, validating the underlying VPC route tables before sealing the layout permanently in the final declarative configuration.
=======
## Day 2: Subnet Isolation and Networking Port Diagnostics

### Why a Database Must Reside in a Private Subnet

In a production-ready cloud architecture, the database tier represents the critical state engine of the entire system. Placing the database inside a private subnet is a fundamental application of the **Principle of Least Privilege** and the **Defense-in-Depth** security model for several critical reasons:

* **Elimination of Public Attack Surface:** A private subnet does not possess an attached Internet Gateway (IGW) route handler, and resources within it are assigned private IP addresses (`10.0.3.0/24`). This renders the database completely invisible and unreachable from the public internet, preventing automated brute-force attempts and network-level scans.
* **Granular Network Control:** Traffic entering the private database tier is strictly restricted using AWS Stateful Firewalls (Security Groups). In this setup, the database (`Legacylens-DB-SG`) rejects all incoming requests unless they explicitly originate from the Private Application Subnet (`10.0.2.0/24`) over the designated PostgreSQL port (`5432`). 
* **Controlled Isolation:** Even if a public-facing component (like the Bastion host or an ingress proxy) is compromised, an attacker cannot route directly into the data layer without pivoting horizontally through hardened internal application checkpoints.

---

### Port-Binding Diagnostics via `ss -tulpn`

To verify how the operating system manages network sockets inside our secure environment, we used the modern kernel utility `ss -tulpn` (Socket Statistics). 

#### Understanding the Diagnostic Flags
* **`-t`**: Filters for **TCP** stream sockets (reliable connection-oriented traffic).
* **`-u`**: Filters for **UDP** datagram sockets (fast connectionless traffic).
* **`-l`**: Restricts the display to sockets currently in the **LISTEN** state, actively waiting for inbound connection requests.
* **`-p`**: Extracts the specific internal **Process Name** and Process ID (PID) holding the socket open.
* **`-n`**: Forces raw **Numeric** ports and addresses to display instead of translating them to human-readable protocol names (e.g., rendering `22` instead of `ssh`).

#### Live Output Breakdown & Core Takeaways
Running this on our active Ubuntu Bastion Host revealed the following structural mappings:

1. **`tcp LISTEN 0 4096 *:22 *:*`**
   * **Analysis:** The SSH daemon (`sshd`) is listening on port `22`. The wildcard `*` indicates that the socket is bound globally to **all available network interfaces**. This allows external connections coming from our local client through the Internet Gateway to be received successfully.
2. **`udp UNCONN 0 0 127.0.0.53%lo:53 0.0.0.0:*`**
   * **Analysis:** The system local caching DNS resolver (`systemd-resolved`) is bound strictly to the **loopback interface (`lo`)** on IP `127.0.0.53`. 
   * **Strategic Impact:** Because it is bound locally, this service is completely inaccessible to outside network cards, protecting internal lookup mechanisms from external interference.
3. **Strategic Port Binding Configurations:**
   * **`0.0.0.0:3000` or `:::3000` (All Interfaces):** When deploying our Node.js automation bot later, binding to this wildcard tells the application to accept traffic from any network interface card (NIC), making it visible to internal target routing pools or load balancers.
   * **`127.0.0.1:3000` (Loopback Only):** If a service binds to this address, it isolates itself completely to local system inter-process communication. External network devices cannot talk to it, which is ideal for hidden internal system microservices but disastrous for public-facing entry points.

---

### Outbound Network Egress Validation

Running `nslookup google.com` confirmed that our outbound pathing is fully active. The local instance successfully generated a UDP port 53 query, resolved it through the local `127.0.0.53` stub, routed out through the public subnet's default route entry, and mapped its return destination cleanly. This confirms that the VPC networking fabric is perfectly aligned.
### Outbound Data Egress Lifecycle (The NAT Gateway Pipeline)

To protect our internal computing tier while maintaining the ability to pull package updates and connect to external APIs, we engineered a unidirectional outbound traffic system. The diagram below illustrates how data safely exits our private network:

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

## 📅 Day 4: Stateful Firewalls, Bastion Architecture, and Security Group Correlation

### 🎯 Architectural Objective
The core objective of Day 4 was implementing a multi-layered **Chain of Trust** security framework. Instead of exposing our internal application assets directly to the public web, we engineered an isolated perimeter barrier. By separating public access controllers from private core resources and configuring advanced firewall dependencies, we ensured that our multi-tenant backend infrastructure remains completely hidden from external network sweeps while maintaining smooth administrative manageability.

---

### 📚 Core Conceptual Framework (In Plain English)

* **Bastion Host (The Armed Lobby Guard):** A highly hardened, minimal virtual machine deployed explicitly in the public entry network (the front lobby). It serves as the single, tightly monitored digital checkpoint for network management. Administrators cannot access the underlying vault environments directly from home; they must pass this guard first.
* **Security Group (The Stateful Shield):** A dynamic, host-level software firewall that wraps around individual cloud resources. It audits all incoming and outgoing network data packets against a strict access sheet, dropping unauthorized data before it ever hits the operating system layer.
* **Stateful Routing (The Memory Recall Window):** A smart security feature where the firewall automatically remembers any conversation that starts from *inside* the house. If our private application server reaches out to an external web service, the firewall automatically opens a temporary window to let the response back in—meaning we only have to explicitly block *inbound* attacks while outbound utility flows freely without manual configuration.

---

### 🔒 The Power of Security Group Nesting ( Badge-Based Trust )

Instead of traditional firewall rules that force engineers to hardcode easily spoofed or dynamic internal IP ranges (e.g., `10.0.1.X`), we implemented **Security Group Nesting**. We configured the private application firewall to accept incoming traffic **only if it originates from a resource wearing the specific Bastion Security Group Badge (`security_groups = [aws_security_group.bastion_sg.id]`)**.

#### Why this is highly secure:
1. **Dynamic Resiliency:** If the Bastion Host's internal IP address changes due to a machine restart, auto-scaling event, or redeployment, the backend vault doesn't break. The network automatically tracks the identity badge, not the location.
2. **Absolute External Rejection:** Even if an attacker somehow bypasses external gateways and drops onto our internal subnets, any data packet sent to the private application tier will be instantly dropped at the edge unless it carries the verified tracking token of our public guard.

---

### 🧪 System Audits & Diagnostic Telemetry

We verified this locked-door boundary by executing low-level kernel authentication lookups directly inside the isolated terminal:

1. **Direct Internet Attack (Blocked):** Attempting to bridge straight from a personal home network laptop to the vault console (`10.0.2.112`) returned an immediate `Connection refused` network signal.
2. **Chain of Trust Jump (Passed):** Leveraging local `ssh-agent` keys to securely forward credential signatures through the Bastion proxy allowed immediate vault entry.
3. **Session Verification (`w`):** Live telemetry inside the vault verified the source profile:
   * The incoming connection source was explicitly flagged as originating strictly from the Bastion internal identity (`10.0.1.x`), proving our home IP signature was completely masked.
4. **Authentication Audit Logs (`/var/log/auth.log`):** The internal Linux system logs cleanly tracked the secure public-key validation handshakes routed through the internal bridge.

## Day 5: Production Managed Databases & Multi-AZ Network Group Isolation

Today, I expanded the *Legacylens* infrastructure by provisioning a production-ready, fully isolated **AWS RDS PostgreSQL Engine** using declarative Terraform blocks. 

### Core Parameter Breakdown & Operational Engineering Value:

*   `allocated_storage = 20`: Allocates a 20 GB General Purpose SSD storage tier. This baseline configuration satisfies the AWS Free Tier limitations, ensuring zero deployment cost overhead during active sandbox R&D while providing ample baseline performance for application database testing.
*   `engine = "postgres"` & `engine_version = "16.1"`: Installs a clean PostgreSQL 16.1 distribution, keeping the cloud data engine perfectly synchronized with the relational database requirements of the Legacylens backend bot ecosystem.
*   `instance_class = "db.t4g.micro"`: Leverages an ARM-based AWS Graviton4-optimized micro-instance. This selection demonstrates advanced real-world cloud optimization—delivering superior price-to-performance scaling compared to older x86-based instances.
*   `db_subnet_group_name`: **The primary isolation anchor.** By tying the instance explicitly to `aws_db_subnet_group.db_subnet_group.name`, the relational engine is strictly forbidden from spinning up public-facing interfaces. It restricts database deployment to the multi-AZ private subnets across `ap-south-1a` and `ap-south-1b`, completely isolating the data layer from public edge networks.
*   `vpc_security_group_ids`: Enforces microsegmentation boundaries by wrapping the instance inside a dedicated database firewall. This layer rejects all network connection handshakes unless they originate strictly over TCP Port 5432 from the private application server's network profile.
*   `skip_final_snapshot = true`: An intentional developer-velocity optimization. It bypasses the time-consuming 7–10 minute data-backup lifecycle during infrastructure teardowns, allowing me to iterate, destroy, and redeploy modified architecture states rapidly without stalling development pipelines.

## Day 6: Infrastructure Deployment & Secure Inside-VPC Database Handshake Verification

### 🛠️ Tasks Executed
1. **Live RDS Provisioning:** Executed `terraform apply` to deploy a managed Multi-AZ PostgreSQL 16 relational database tier (`db.t4g.micro`) across isolated subnets (`ap-south-1a` and `ap-south-1b`).
2. **Jump Host Tunnel Routing:** Leveraged local SSH Jump tunneling via the public Bastion host gate (`35.154.59.9`) to securely bridge access into the private application instance environment (`10.0.2.128`).
3. **Linux Node Patching & Tooling Deployment:** Updated the internal Linux package manager index and installed native database routing engine utilities:
   ```bash
   sudo apt-get update -y
   sudo apt-get install postgresql-client -y

   psql -h terraform-044b39d4f87acf5e351c17466b.cfew2m0cwv6o.ap-south-1.rds.amazonaws.com -U db_admin_user -d legacylens_prod

  
  
   ## Day 7: Programmatic Node.js Environment Isolation & Database Socket Verification

### 🛠️ Tasks Executed
1. **Runtime Provisioning via NVM:** Installed Node Version Manager (NVM) and provisioned Node.js `v22.23.1` (LTS) along with `npm` on the private application server node (`10.0.2.105`).
2. **Project Workspace & Dependency Management:** Created `~/legacylens-core` workspace and installed `pg` (node-postgres) driver and `dotenv` for secret isolation.
3. **Secrets Decoupling:** Configured `.env` file to hold database host endpoints, credentials, and parameters safely outside application code.
4. **Programmatic Socket Handshake:** Authored `db-test.js` to execute an asynchronous pool connection to the RDS Multi-AZ PostgreSQL 16 cluster (`16.13 aarch64`), validating query execution (`SELECT NOW()`) over TLS.

### 🔒 Security & Architectural Insights
* **Zero Secrets in Version Control:** Decoupling sensitive parameters via `.env` prevents credential exposure in public/private Git repositories. At runtime, `dotenv` loads configuration directly into `process.env` in memory.
* **Non-Blocking Asynchronous I/O & Connection Pooling:** The `pg` driver utilizes Node.js event loops to manage database sockets asynchronously without blocking concurrent HTTP application requests. Connection pooling reuses established TCP sockets, significantly reducing latency and overhead compared to creating fresh handshakes per query.



## Day 8: Multi-Tenant Schema Isolation & Dynamic Search Path Driver

### 🛠️ Tasks Executed
1. **Isolated Schema Creation:** Designed and executed `day8_multitenant.sql` to establish two logical schema boundaries (`tenant_alpha` and `tenant_beta`) inside a shared PostgreSQL RDS database.
2. **Schema-Level Data Segregation:** Provisioned `assets` tables, primary keys, performance indices (`idx_alpha_asset_name`, `idx_beta_asset_name`), and seed records within each independent tenant namespace.
3. **Dynamic Driver Implementation:** Authored `index.js` utilizing `pg.Pool` to execute session-level `SET search_path TO <tenant_schema>` statements before query execution.

### 🔒 Architectural Insights
* **Schema-Based Multi-Tenancy:** Using schema isolation balances resource usage and database cost while providing strict logical data boundaries between different tenants without requiring separate physical database instances.
* **Dynamic Connection Context:** Setting `search_path` per connection checkout allows standard, uniform SQL queries (e.g., `SELECT * FROM assets`) to automatically target the correct tenant's data safely and efficiently.

# Day 9: Private Database Isolation & Multi-Tenant Schema Configuration

## 🎯 Objective
Secure the LegacyLens PostgreSQL database within a private AWS VPC subnet, establish zero-trust access using an EC2 Bastion host via AWS Systems Manager (SSM), and implement a multi-tenant database schema for client data isolation.

## 🛠️ Tech Stack & AWS Services
* **Compute:** AWS EC2 (Ubuntu Bastion Host), AWS Systems Manager (SSM)
* **Database:** Amazon RDS (PostgreSQL 16)
* **Networking:** Amazon VPC (Private Subnets), Security Groups
* **Infrastructure as Code:** Terraform
* **Tools:** `psql`, AWS CLI, Bash/PowerShell

## 🏗️ Architecture & Security Highlights
1. **Zero-Trust Access (No SSH):** Eliminated the need for public IP addresses or opening Port 22. All administrative database access is routed securely through an EC2 Bastion host using AWS SSM Session Manager.
2. **Private Subnet Isolation:** Deployed the RDS instance strictly within private subnets. The database is completely invisible to the public internet.
3. **Security Group Chaining:** Configured the database Security Group to drop all connections except explicitly whitelisted internal VPC traffic (port 5432).
4. **Multi-Tenant Schema Design:** Engineered a highly scalable PostgreSQL architecture using isolated schemas (`tenant_alpha`, `tenant_beta`) and dynamic `search_path` routing to securely separate restaurant data within a single database instance.

## 🧪 Troubleshooting & Debugging Realities
During deployment, I successfully diagnosed and resolved several real-world infrastructure challenges:
* **VPC Firewall Blockages:** Diagnosed a database connection timeout by identifying a missing inbound rule on the RDS Security Group. Successfully modified the SG to allow internal `10.0.0.0/16` traffic.
* **Database Authentication:** Troubleshot and bypassed local tunnel authentication failures, switching to direct Bastion access to successfully authenticate the `db_admin_user`.
* **Connection Monitoring:** Executed administrative SQL queries (`SELECT count(*) FROM pg_stat_activity;`) to monitor connection pool health and prevent exhaustion.

## 💡 Key Takeaways for Cloud Architecture
* **Stateful vs. Stateless:** Security Groups are stateful; allowing inbound port 5432 traffic automatically allows the outbound response, contrasting with stateless Network ACLs.
* **NAT Gateways:** Vital for allowing private subnets to pull required OS updates without exposing the instances to inbound internet traffic.
* **Logical Data Separation:** Utilizing PostgreSQL schemas for multi-tenancy provides a secure, cost-effective alternative to spinning up separate database instances for every client.