# Vulnerability scans (Phase 8)

Nmap NSE output from KALI against LNX-TGT (10.10.10.30), on the isolated `soc-lab` network. Each scan is in `.nmap` (readable), `.gnmap` (grep) and `.xml`.

| File | Command | Section |
|---|---|---|
| `p8-01-nse-vuln` | `-sV --script "vuln and safe"` | A1 — TLS findings only |
| `p8-02-backdoors` | `--script ftp-vsftpd-backdoor,distcc-cve2004-2687,irc-unrealircd-backdoor` (`--script-args cmd=id`) | A2 — confirmed backdoors |

Each confirmation script ran `id` as proof of access and stopped. Analysis: [setup/08-vulnerability-assessment.md](../../setup/08-vulnerability-assessment.md).

