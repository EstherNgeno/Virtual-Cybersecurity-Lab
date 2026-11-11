# Nmap scan results

Phase 7 scans, run from KALI (10.10.10.50) against lab hosts only, on the isolated `soc-lab` network. Each scan is saved in three formats by `-oA`:

- `.nmap`: human-readable output, with the exact command and start time in the header
- `.gnmap`: one line per host, for `grep`
- `.xml`: for other tools

| Scan | Target | Command | Result |
|---|---|---|---|
| `p7-01-discovery` | 10.10.10.0/24 | `-sn` | 2 hosts up (LNX-TGT, KALI) |
| `p7-02-syn` | LNX-TGT | `-sS -p 21,22,80,8888` | 3 open, 1 closed |
| `p7-03-connect` | LNX-TGT | `-sT -p 21,22,80,8888` | 3 open, 1 closed |
| `p7-04-full` | LNX-TGT | `-p- -sV -O` | 30 open ports, versions, Linux 2.6 |
| `p7-05-nse` | LNX-TGT | `-sV -sC -p 21,22,139,445,3306,5900` | Anonymous FTP, Samba 3.0.20, SMB signing off |
| `p7-06-wintgt-known` | WIN-TGT | `-sS` on 10 listening ports + 8888 | All 11 filtered |
| `p7-07-wintgt-top1000` | WIN-TGT | `-sS` top 1000 | All filtered |
| `p7-08-wintgt-audit` | WIN-TGT | `-sT` on the same 11 ports | All filtered; logged as event 5152 with auditing on |

Analysis: [setup/07-nmap-recon.md](../../setup/07-nmap-recon.md).
