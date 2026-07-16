
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
