## Interlude CIDR ( classless inter-Domain Routing )

- An IPv4 address is a 32 bits and formatted as four 8 bit octal number (192.0.2.0).

- It uses the slash character (/) to indicate how many bits of routing must be fixed or allocation for the network identifier.

![alt text](../screenshots/Lab-2/cider.png)

we can say that 2^8 = 256 IP addresses are available for the network raning from 192.0.2.2 to 192.0.2.255

CIDR follows a rule where ``smaller prefix number means a bigger network``

There are 5 reserved IPs per AWS subnet which reduces the IPs by 5

- .0 = network address
- .1 = VPC router
- .2 = Amazone DNS resolver 
- .3 = Reserved for future use
- .225 = Network broadcast address

3 rules of subnets
1. a subnet's CIDR must be a subset of the VPC's,
2. must not overlap any other subnet in that VPC
3. can never be changed after creation.

## DNS support and DNS hostnames


## Interlude two firewalls, and which one to reach for

AWS VPCs provide a defense-in-depth model using two packet filters:
1. Security Groups (SGs) 
2. Network Access Control Lists (NACLs).

- NACLs are stateless it do not track connection states. 

- Allowing inbound traffic on a specific port that requires an explicit outbound rule for the client's ephemeral ports.

- But if an inbound rule allows port 80 but outbound ephemeral ports are blocked, the request reaches the server, but the response packet is dropped. This causes connections to establish and immediately hang.
- Security Groups (Primary Defense) : Use for fine grained instance-level access control (allowing web traffic to web servers, or database traffic only from specific security groups).
- Network ACLs : Use as a coarse subnet-wide safety net (blocking known malicious IP ranges outright or ensuring private subnets never communicate directly with the internet, regardless of Security Group settings).

## Floci Limitation the NAT gateway is an object, not a translator

- API Object vs. Data-Plane Engine: Local emulation tools like Floci model the AWS Control Plane (resource provision, Elastic IP association, status lifecycle pending -> available). Real AWS provisions a fully managed, horizontally scaled Network Address Translation (NAT) cluster behind that API handle.

- Packet Translation: Real AWS NAT Gateways perform active Source IP Address Translation (SNAT). Private IP source addresses (10.0.x.x) are rewritten to the assigned public Elastic IP (EIP) address before leaving the VPC through the Internet Gateway (IGW).

- Connection & Billing Characteristics:

    - Capacity: Supports up to 55,000 concurrent connections per unique destination endpoint.

    - Cost: Billed on a dual metric (fixed hourly fee + variable data transfer fee per gigabyte processed). NAT Gateways are frequently one of the largest single cost items in production AWS networking.

- Asymmetric Network Flow: The ability of a private subnet to initiate connections outward while remaining completely shielded from incoming internet traffic is a function of routing and translation design, not firewall rule configurations.

- Placement Constraint: A NAT Gateway must strictly reside in a Public Subnet (a subnet with an active 0.0.0.0/0 -> igw-xxx route) to complete the packet trajectory outward to the internet.
