# Virtual Cybersecurity Lab

An isolated, self-hosted SOC lab for practising network reconnaissance, endpoint monitoring, threat detection and incident response. Controlled attack simulations are run against lab-owned systems, then investigated from the defender's side using SIEM alerts, endpoint telemetry and packet captures, and mapped to MITRE ATT&CK.

> **Status:** Phases 1 to 6 complete (network isolation, Kali baseline, Windows target with Sysmon, Wazuh SIEM with WIN-TGT enrolled, Sysmon and rule tuning with custom detections in [detections/wazuh/local_rules.xml](detections/wazuh/local_rules.xml)). Phase 6 complete: packet analysis with Wireshark and tcpdump, endpoint-to-network correlation, and captures in [evidence/packet-captures/](evidence/packet-captures/). Phase 7 complete: Nmap reconnaissance of both targets, observed from the defender's side, with scans in [evidence/scans/](evidence/scans/). Phase 8, vulnerability assessment, is next.

## Objectives

- Build a contained lab network that cannot reach the host, the home network or the internet.
- Collect and analyse Windows endpoint telemetry with Sysmon and Wazuh.
- Perform reconnaissance and vulnerability assessment against intentionally vulnerable hosts.
- Simulate common attacker techniques and detect them with custom Wazuh rules.
- Investigate each simulation as a SOC analyst: triage, timeline, IOCs, ATT&CK mapping and an incident report.

## Architecture

Four VMs on a VirtualBox Internal Network (`soc-lab`, 10.10.10.0/24) with no gateway. Full design, addressing and isolation controls: [architecture/network-plan.md](architecture/network-plan.md).

| Host | Role | IP |
|---|---|---|
| WAZUH-SRV | SIEM (Wazuh manager, indexer, dashboard) | 10.10.10.10 |
| WIN-TGT | Windows 11 endpoint with Sysmon and Wazuh agent | 10.10.10.20 |
| LNX-TGT | Metasploitable 2, intentionally vulnerable | 10.10.10.30 |
| KALI | Assessment and packet capture | 10.10.10.50 |

## Technology stack

VirtualBox · Kali Linux · Wazuh · Sysmon · Wireshark · Nmap · Metasploitable 2 · MITRE ATT&CK

## Progress

| Phase | Topic | Status | Write-up |
|---|---|---|---|
| 1 | Virtualization and network isolation | Complete | [setup/01-virtualization-and-isolation.md](setup/01-virtualization-and-isolation.md) |
| 2 | Kali Linux baseline | Complete | [setup/02-kali-linux.md](setup/02-kali-linux.md) |
| 3 | Windows target (including Sysmon install) | Complete | [setup/03-windows-target.md](setup/03-windows-target.md) |
| 4 | Wazuh server and agent | Complete | [setup/04-wazuh-server.md](setup/04-wazuh-server.md) |
| 5 | Sysmon configuration, tuning and log baselining | Complete | [setup/05-sysmon-tuning.md](setup/05-sysmon-tuning.md) |
| 6 | Network fundamentals and Wireshark | Complete | [setup/06-network-wireshark.md](setup/06-network-wireshark.md) |
| 7 | Nmap reconnaissance | Complete | [setup/07-nmap-recon.md](setup/07-nmap-recon.md) |
| 8 | Vulnerability assessment | Planned | |
| 9 | Log analysis and baselining | Merged into Phase 5 | |
| 10 | Attack simulations (three scenarios), detection and investigation | Planned | |
| 11 | Capstone investigation | Planned | |

## Safety and scope

All activity targets only VMs inside the isolated lab network. No real malware, real credentials or personal data are used. See the isolation controls in the [network plan](architecture/network-plan.md#isolation-controls).
