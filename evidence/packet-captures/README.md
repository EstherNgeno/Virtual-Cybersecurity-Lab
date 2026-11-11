# Packet captures

All captures come from the isolated `soc-lab` network (10.10.10.0/24). They contain only lab traffic and Metasploitable's public lab account or invented credentials.

Verify integrity after download:

```bash
sha256sum -c SHA256SUMS
```

| File | Phase | Captured on | Shows |
|---|---|---|---|
| `phase6-arp-icmp.pcapng` | 6 | KALI | ARP resolution and ICMP echo |
| `phase6-ftp-cleartext.pcapng` | 6 | KALI | TCP handshakes, cleartext FTP login (Finding 6.1) |
| `phase6-http-basic-auth.pcapng` | 6 | KALI | HTTP Basic auth header (Finding 6.2) |
| `phase6-wintgt-chatter.pcapng` | 6 | KALI | Unanswered ARP for the agent's server; LLMNR, NBNS and mDNS fallback (Finding 6.4) |
| `phase6-wintgt-correlation.pcapng` | 6 | KALI | PowerShell connections to port 4444 matched to Sysmon ID 3 |
| `phase6-agent-1514.pcap` | 6 | WAZUH-SRV | Encrypted Wazuh agent channel and the reset when the agent was terminated (Finding 6.6) |
| `phase7-discovery.pcapng` | 7 | KALI | `nmap -sn` host discovery: 516 frames, all ARP |
| `phase7-syn-vs-connect.pcapng` | 7 | KALI | SYN scan vs connect scan of four LNX-TGT ports |
| `phase7-wintgt-scan.pcapng` | 7 | KALI | Scans of WIN-TGT: every probe silently dropped (Finding 7.4) |

Write-ups: [setup/06-network-wireshark.md](../../setup/06-network-wireshark.md), [setup/07-nmap-recon.md](../../setup/07-nmap-recon.md).
