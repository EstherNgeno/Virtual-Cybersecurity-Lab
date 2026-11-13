# Phase 9: Log Analysis and Baselining

| | |
|---|---|
| **Status** | Complete — merged into [Phase 5](05-sysmon-tuning.md) |
| **Date** | Decided 2026-11-05 |
| **Hosts in scope** | WIN-TGT, WAZUH-SRV |

## Why this phase has no separate build

Phase 9 was originally planned as a standalone stage: establish a normal baseline for the endpoint logs, then learn to read them and tell routine activity apart from suspicious activity. During Phase 5 it became clear that this work could not be separated from Sysmon tuning — you cannot tune a sensor without first measuring what it normally produces, and you cannot judge a rule without knowing the baseline it fires against. Folding the two together also kept the project inside its agreed ~45-hour budget.

The decision (2026-11-05) was to **merge Phase 9 into Phase 5** and keep Phase 9 as this short record so the numbering stays intact and the baselining work is easy to find. No lab steps were skipped; they were done under Phase 5.

## Where the Phase 9 work actually lives

| Phase 9 objective | Where it was done |
|---|---|
| **Baseline the endpoint logs** — measure normal volume and event mix | [Phase 5, §1 Baseline](05-sysmon-tuning.md#1-baseline): WIN-TGT's Sysmon log over 13–30 Oct — 2,927 events in 4.26 MB of a 64 MB circular log; dominated by ID 1 (process create, 1,711), ID 13 (registry, 764), ID 11 (file create, 255); **zero** ID 3, 7 and 10, which exposed the coverage gaps Phase 5 then closed |
| **Know what each log source contains and omits** | [Phase 5, §2 Configuration review](05-sysmon-tuning.md#2-configuration-review): which Sysmon event IDs were on, off, and deliberately left off for a 2 GB endpoint |
| **Separate routine activity from suspicious** | [Phase 5, Finding 5.7](05-sysmon-tuning.md#finding-57-most-endpoint-alerts-were-proven-noise): most endpoint alerts were traced to the agent's own CIS scan and other benign self-generated activity, and suppressed without hiding the attacks they resembled |
| **Triage real alerts in the SIEM** | [Phase 4](04-wazuh-server.md): first alert triage after WIN-TGT enrolment (SCA `secedit`/`SecEdit.exe` bursts identified as benign) |
| **Understand what is missing from the logs** | [Phase 5, Findings 5.1–5.5](05-sysmon-tuning.md#7-findings): events dropped at boot (5.1), high-value activity with no alert (5.2), LSASS access hidden by LSA protection (5.3), crashes silent in the SIEM (5.5) |
| **Apply log analysis to live evidence** | [Phase 6](06-network-wireshark.md) (endpoint-to-packet correlation) and [Phase 7](07-nmap-recon.md) (what scans do and do not leave in host logs) |

## Baseline summary (for quick reference)

WIN-TGT Sysmon, 13–30 October 2026, from [Phase 5 §1](05-sysmon-tuning.md#1-baseline):

| Measure | Value |
|---|---|
| Total events | 2,927 |
| Log size / cap | 4.26 MB of 64 MB, circular |
| Top event IDs | 1 process create (1,711), 13 registry value set (764), 11 file create (255) |
| Notable absences | ID 3 (network), ID 7 (image load), ID 10 (process access) — all zero before Phase 5 tuning |
| Per-day range | 17–1,118 events/day |

This baseline is the reference the Phase 10 attack scenarios are measured against: an alert matters only when it stands out from the normal volume and mix recorded here.

## Next steps

Phase 10 uses this baseline and the Phase 5 ruleset to detect three attack simulations, building the outstanding detection rules ([6.4](06-network-wireshark.md), [6.6](06-network-wireshark.md), [6.7](06-network-wireshark.md), [7.2](07-nmap-recon.md), [7.5](07-nmap-recon.md)).
