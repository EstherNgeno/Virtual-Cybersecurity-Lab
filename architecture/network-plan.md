# Network Plan

## Design goals

1. **Containment:** lab traffic, including scans and simulated attacks, can never reach the host, the home network or the internet.
2. **Visibility:** one host can observe all traffic on the lab segment for packet analysis.
3. **Low resource use:** the whole lab runs on a 16 GB RAM laptop, with three VMs running at once.
4. **Reproducibility:** fixed addressing and documented settings, so every log, alert and packet capture can be tied to a known host.

## Topology

```
                     Windows 11 host (VirtualBox 7.2)
              browser → https://127.0.0.1:8443 (Wazuh dashboard)
                                    │
                                    │ NAT + localhost-only port-forward
                                    │
┌─────────────────────┐   ┌─────────┴───────────┐
│ KALI                │   │ WAZUH-SRV           │
│ Kali Linux 2026.1   │   │ Ubuntu 24.04 LTS    │
│ Nmap, Wireshark     │   │ Wazuh all-in-one    │
│ 10.10.10.50         │   │ 10.10.10.10         │
└──────────┬──────────┘   └─────────▲───────────┘
           │                        │ agent telemetry
           │                        │ TCP 1514 / 1515
═══════════╪════ soc-lab 10.10.10.0/24 ═════╪═══════════════
           │   (VirtualBox Internal Network, no gateway)
           │                        │
┌──────────┴──────────┐   ┌─────────┴───────────┐
│ WIN-TGT             │   │ LNX-TGT             │
│ Windows 11 Ent eval │   │ Metasploitable 2    │
│ Sysmon, Wazuh agent │   │ intentionally       │
│ 10.10.10.20         │   │ vulnerable target   │
└─────────────────────┘   │ 10.10.10.30         │
                          └─────────────────────┘
```

## Hosts and addressing

| Host | Role | OS | IP address | RAM / vCPU | Status |
|---|---|---|---|---|---|
| WAZUH-SRV | SIEM: manager, indexer, dashboard | Ubuntu Server 24.04.5 LTS, Wazuh 4.14.9 | 10.10.10.10/24 | 4 GB / 1 ([Finding 4.1](../setup/04-wazuh-server.md#finding-41-guest-instability-with-2-vcpus-on-the-windows-hypervisor)) | Server verified, no agents yet (Phase 4) |
| WIN-TGT | Monitored Windows endpoint | Windows 11 Enterprise evaluation, legacy BIOS firmware ([Finding 3.1](../setup/03-windows-target.md#finding-31-uefi-firmware-hangs-with-more-than-one-virtual-cpu-on-this-host)) | 10.10.10.20/24 | 4 GB / 2 | Baseline verified, Sysmon running (Phase 3) |
| LNX-TGT | Vulnerable Linux target | Metasploitable 2 | 10.10.10.30/24 | 512 MB / 1 | Clean baseline snapshot (Phase 2) |
| KALI | Assessment and packet capture | Kali Linux 2026.1 | 10.10.10.50/24 | 2 GB / 2 | Baseline verified (Phase 2) |

All addresses are static. The `soc-lab` network has no DHCP server, and no host is configured with a default gateway.

## Network segments

| Segment | VirtualBox type | Purpose | Reachable from |
|---|---|---|---|
| `soc-lab` 10.10.10.0/24 | Internal Network | All lab activity and telemetry | Lab VMs only |
| NAT (per VM) | NAT | Outbound updates only | Nothing; inbound blocked by design |

## Adapter configuration

| VM | Adapter 1 | Adapter 2 | Promiscuous mode |
|---|---|---|---|
| KALI | Internal `soc-lab` | NAT, cable **disconnected** except during updates | Allow VMs (capture point) |
| LNX-TGT | Internal `soc-lab` | None; never internet-connected | Deny |
| WIN-TGT | Internal `soc-lab` | NAT, cable disconnected and adapter disabled inside Windows after setup | Deny |
| WAZUH-SRV | Internal `soc-lab` | NAT, connected for updates; port-forwards bound to 127.0.0.1 (8443 → 443, 2222 → 22) | Deny |

## Permitted traffic flows

| Flow | Source → Destination | Protocol / port |
|---|---|---|
| Agent enrollment | WIN-TGT, LNX-TGT → WAZUH-SRV | TCP 1515 |
| Agent event forwarding | WIN-TGT, LNX-TGT → WAZUH-SRV | TCP 1514 |
| Dashboard access | Host browser → WAZUH-SRV | 127.0.0.1:8443 → TCP 443 |
| Server administration | Host terminal → WAZUH-SRV | 127.0.0.1:2222 → TCP 22 (SSH) |
| Assessment and simulation traffic | KALI → WIN-TGT, LNX-TGT | Varies by exercise |
| Ping to WIN-TGT | 10.10.10.0/24 → WIN-TGT | ICMPv4 echo request (type 8), firewall rule `SOC-LAB Allow ICMPv4 Echo from lab` |

## Isolation controls

| # | Control | Threat it addresses |
|---|---|---|
| 1 | No Bridged adapters on any VM | Lab traffic reaching the home network |
| 2 | Internal Network with no gateway | Routing out of the lab |
| 3 | NAT cables disconnected on KALI and targets during exercises | Scans or simulations reaching the internet |
| 4 | LNX-TGT has no NAT adapter at all | An intentionally vulnerable host gaining an internet path |
| 5 | Pre-flight isolation check on KALI before each exercise ([scripts/preflight.sh](../scripts/preflight.sh)) | Human error, such as a NAT cable left connected |
| 6 | Explicit lab IPs only in tool commands | Mistyped targets or hostnames |
| 7 | Clipboard host-to-guest only; drag-and-drop and shared folders disabled | Files or data crossing to the host |
| 8 | Dashboard and SSH port-forwards bound to 127.0.0.1 | Other devices on the home Wi-Fi reaching the SIEM |
| 9 | Snapshots before each simulation phase | Persistent changes from simulations |
| 10 | Dummy data and lab-only credentials; no real malware | Exposure of real data or accounts |
