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

Write-up: [setup/06-network-wireshark.md](../../setup/06-network-wireshark.md).
