# Virtual Cybersecurity Lab

An isolated, self-hosted SOC lab for practising network reconnaissance, endpoint monitoring, threat detection and incident response. Controlled attack simulations are run against lab-owned systems, then investigated from the defender's side using SIEM alerts, endpoint telemetry and packet captures, and mapped to MITRE ATT&CK.

> **Status:** Phases 1 to 4 complete (network isolation, Kali baseline, Windows target with Sysmon, Wazuh SIEM with WIN-TGT enrolled and its first endpoint alerts triaged). Phase 5, Sysmon configuration and tuning, is next.

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
| 5 | Sysmon configuration and tuning | Planned | |
| 6 | Network fundamentals and Wireshark | Planned | |
| 7 | Nmap reconnaissance | Planned | |
| 8 | Vulnerability assessment | Planned | |
| 9 | Log analysis and baselining | Planned | |
| 10 | Attack simulations, detection and investigation | Planned | |
| 11 | Capstone investigation | Planned | |

## Safety and scope

All activity targets only VMs inside the isolated lab network. No real malware, real credentials or personal data are used. See the isolation controls in the [network plan](architecture/network-plan.md#isolation-controls).
