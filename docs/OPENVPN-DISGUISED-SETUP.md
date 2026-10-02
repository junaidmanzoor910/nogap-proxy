# OpenVPN Disguised HTTPS Architecture & Deployment Guide

This guide details the **pure-software OpenVPN implementation** on AWS EC2, configured to **disguise VPN traffic as normal HTTPS traffic** over **TCP port 443**.

---

## 1. Architecture & Port Disguise Mechanism

In standard VPN deployments, OpenVPN operates over UDP port 1194. This port is immediately blocked or throttled by restrictive firewalls, corporate proxies, coffee shops, and deep packet inspection (DPI) appliances.

This setup achieves **100% traffic disguise** using three synchronized defense-in-depth mechanisms:

```
[ Workstation / Browser ]
           │
           │ TCP Port 443 (Standard HTTPS)
           ▼
[ AWS EC2: OpenVPN Server (TCP 443) ]
           │
           ├── [ Authorized Client with tls-crypt Key ] ──► [ tun0: 10.8.0.0/24 ] ──► [ iptables MASQUERADE ] ──► [ Internet Egress via Elastic IP ]
           │
           └── [ Port Scanner / Firewall Probe / Browser ]
                      │ (tls-crypt check fails; non-OpenVPN packet detected)
                      ▼
               [ port-share 127.0.0.1:8443 ]
                      ▼
               [ Internal Nginx Web Server ] ──► Returns genuine HTTPS 200 OK ("Cloud Gateway" landing page)
```

### 1. Port 443 (Standard HTTPS)
OpenVPN listens directly on **TCP port 443**, the universal port for encrypted web traffic. Almost all network firewalls and middleboxes permit outbound TCP 443.

### 2. `tls-crypt` Signature Obfuscation (Anti-DPI)
Standard OpenVPN packets (even over port 443) exhibit plain-text opcode headers and standard TLS certificate exchanges. 
With `tls-crypt`:
- The entire control channel — including the initial TLS ClientHello — is pre-encrypted with a shared symmetric key (`tls-crypt.key`).
- DPI engines cannot detect any OpenVPN protocol signatures; the packet stream appears as indistinguishable, high-entropy encrypted TLS data.
- Unauthorized packets (which lack the key) are rejected before any cryptographic handshake is attempted.

### 3. Active Probe Resistance (`port-share 127.0.0.1 8443`)
When a port scanner (e.g. Nmap, Shodan, or firewall active prober) attempts an HTTPS connection to `https://<EC2-IP>:443`:
- OpenVPN inspects the initial byte sequence.
- Since it is an HTTP/TLS probe and not a valid `tls-crypt` packet, OpenVPN transparently proxies the connection to `127.0.0.1:8443`.
- Nginx responds with a valid TLS certificate and serves the "Cloud Gateway" web application.
- To any external observer, **port 443 behaves as a standard, legitimate secure web server**.

---

## 2. Software vs. Service

- **Pure Software (Community OpenVPN)**: Uses the open-source `openvpn` package directly on Ubuntu 24.04 and Linux workstations.
- **Zero Commercial Lock-in**: Does not use paid "OpenVPN Access Server" (which has user licensing limits and fees) or AWS Client VPN (which incurs high hourly endpoint and association fees).
- **Direct CLI & Script Control**: Connections are managed directly via `openvpn --config client.ovpn`, automated through local scripts and the interactive UI dashboard.

---

## 3. Quickstart & Workflow

### Step 1: Deploy or Update EC2 Instance
Ensure the EC2 Security Group permits ingress on **TCP 443** (configured automatically in `terraform/main.tf`).

If bootstrapping an existing instance via SSM:
```bash
aws ssm start-session --profile stagging --region ap-south-1 --target <INSTANCE_ID>
sudo /opt/nogap-split-proxy/scripts/bootstrap-host-openvpn.sh
```

### Step 2: Fetch the Standalone Client Profile
The bootstrap process creates a single, self-contained `client.ovpn` profile containing embedded `<ca>`, `<cert>`, `<key>`, and `<tls-crypt>` credentials.

Fetch it directly to your workstation via SSM:
```bash
./run-nogap-vpn.sh fetch
# Or:
./scripts/fetch-client-ovpn.sh
```
*The profile is saved securely to `config/client.ovpn` (chmod 600).*

### Step 3: Connect to OpenVPN
Start the software client:
```bash
./run-nogap-vpn.sh start
# Or:
./scripts/start-vpn.sh
```
The script will:
1. Connect via TCP port 443 using `tls-crypt`.
2. Wait for `tun0` interface creation.
3. Automatically verify and report your new public egress IP (matching the EC2 Elastic IP).

### Step 4: Verify Status
Check connection health, latency to VPN gateway, and transferred bytes:
```bash
./run-nogap-vpn.sh status
# Or:
./scripts/vpn-status.sh
```

### Step 5: Test Port Disguise (Simulate Scanner / Probe)
To verify that external scanners only see a normal HTTPS web server:
```bash
./run-nogap-vpn.sh probe
# Or:
./scripts/verify-disguise.sh <EC2_IP>
```
You will receive an HTTP 200 response from Nginx proving the disguise is active.

### Step 6: Disconnect
To restore standard workstation routing:
```bash
./run-nogap-vpn.sh stop
# Or:
./scripts/stop-vpn.sh
```

---

## 4. Web Dashboard Integration

You can monitor and control the OpenVPN tunnel visually:
```bash
./run-nogap-vpn.sh ui
# Opens http://127.0.0.1:3130
```
The Command Center displays:
- Real-time OpenVPN connection status and `tun0` IP.
- Egress Elastic IP verification and transatlantic RTT latency.
- One-click buttons to Connect OpenVPN, Disconnect, and Probe Port 443 Disguise.
- Integrated EC2 instance power controls (Start / Stop instance).

---

## 5. Adding More Client Profiles

To generate an additional client profile (e.g. for another team member or device):

On the EC2 instance via SSM:
```bash
sudo /opt/nogap-split-proxy/scripts/generate-client-ovpn.sh <client-name>
```
The script outputs `/opt/nogap-openvpn/<client-name>.ovpn` ready for distribution.
