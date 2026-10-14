# Phase 3: Windows Target

| | |
|---|---|
| **Status** | Complete |
| **Date** | 2026-10-13 to 2026-10-14 |
| **Hosts in scope** | WIN-TGT, KALI |

## Objective

Build WIN-TGT, the monitored Windows endpoint: a clean Windows 11 install on the isolated lab network, with a local lab-only account, a fixed address, a firewall that allows only what the lab needs, and Sysmon recording detailed endpoint telemetry. Finish with a snapshot that every later phase can roll back to.

## Environment

| Component | Detail |
|---|---|
| WIN-TGT | Windows 11 Enterprise evaluation (26H2 media, build 26100), 10.10.10.20/24, 4 GB RAM / 2 vCPU, **legacy BIOS firmware** (see Finding 3.1) |
| KALI | Kali Linux 2026.1, 10.10.10.50/24, used for connectivity tests |
| Hypervisor | VirtualBox 7.2.8 running on the Windows hypervisor (Hyper-V platform, "NEM" mode) because Virtualization-Based Security is active on the host |
| Network | VirtualBox Internal Network `soc-lab`, no gateway ([network plan](../architecture/network-plan.md)) |

## 1. Installation media

The Windows 11 Enterprise evaluation ISO was downloaded from the Microsoft Evaluation Center and its hash recorded:

```powershell
Get-ChildItem C:\Users\esthe\Downloads\soc-lab-iso\*.iso | Get-FileHash -Algorithm SHA256 | Format-List
# Hash : 1573A94603148E468FB0D8036376283265CD23F3681757895EB80D165B292040
# Path : ...\26300.9457.260913-1737.26h2_ge_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-gb.iso
```

Microsoft does not publish a reference hash for evaluation media, so this value documents exactly which image the lab was built from rather than proving it against an official value.

The browser had saved the ISO inside a folder of personal documents, and it had been opened in File Explorer, which mounted it as drive `D:` and locked the file. It was dismounted with `Dismount-DiskImage` and moved to a dedicated `soc-lab-iso` folder so that lab media and personal files stay apart.

## 2. Virtual machine

```powershell
VBoxManage createvm --name WIN-TGT --ostype Windows11_64 --register --default
VBoxManage modifyvm WIN-TGT --memory 4096 --cpus 2 --nic1 intnet --intnet1 soc-lab --nic-promisc1 deny --nic2 nat --cable-connected2 off --clipboard-mode disabled --drag-and-drop disabled
VBoxManage createmedium disk --filename "C:\Users\esthe\VirtualBox VMs\WIN-TGT\WIN-TGT.vdi" --size 81920 --format VDI --variant Standard
VBoxManage storageattach WIN-TGT --storagectl SATA --port 0 --device 0 --type hdd --medium "...\WIN-TGT.vdi" --nonrotational on
VBoxManage storageattach WIN-TGT --storagectl SATA --port 1 --device 0 --type dvddrive --medium "...\26300.9457...en-gb.iso"
# after troubleshooting (Finding 3.1):
VBoxManage modifyvm WIN-TGT --firmware bios --cpus 2
```

| Setting | Value | Reason |
|---|---|---|
| Firmware | Legacy BIOS (planned: UEFI with Secure Boot) | UEFI with 2 vCPUs hangs on this host; see Finding 3.1 |
| TPM | 2.0 (emulated) | Windows 11 requirement |
| Disk | 80 GB dynamically allocated, SSD flag | Margin above the 64 GB minimum; space is used only as filled |
| Adapter 1 | Internal Network `soc-lab`, Intel 82540EM, promiscuous mode deny, MAC `08:00:27:F9:D5:AD` | Lab segment; this host cannot sniff other VMs' traffic |
| Adapter 2 | NAT, cable disconnected, MAC `08:00:27:76:CD:CC` | Internet path only for a deliberate setup window |
| Clipboard / drag-and-drop | Disabled | No data crosses between host and target |

`showvminfo` in VirtualBox 7.2.8 prints no TPM line; the TPM was confirmed in the VM settings file (`<TrustedPlatformModule type="v2_0"/>`).

## 3. Installation and account

Windows Setup ran with no network. Under BIOS firmware, Setup's requirement check flags the missing Secure Boot, so two lab overrides were set from the installer's command prompt (Shift+F10) before the check ran:

```
reg add HKLM\SYSTEM\Setup\LabConfig /v BypassSecureBootCheck /t REG_DWORD /d 1 /f
reg add HKLM\SYSTEM\Setup\LabConfig /v BypassTPMCheck /t REG_DWORD /d 1 /f
```

These values apply only to the installer session. First-run setup used the "I don't have internet" path to create a **local** account, `labadmin`, with a lab-only password. No Microsoft or work account is linked, and every privacy toggle was turned off. A snapshot, `phase3-fresh-install`, was taken before the VM first touched the internet.

## 4. Controlled internet window

WIN-TGT was connected to the internet once, for three tasks, with Windows Update paused for a week beforehand and no other lab VM running.

| Task | Command | Result |
|---|---|---|
| Activate the evaluation licence | `slmgr /ato` | `LicenseStatus` 5 → 1; `GracePeriodRemaining` 0 → 129600 min (90 days, to about 2027-01-11) |
| Download Sysmon | `curl.exe -LO https://download.sysinternals.com/files/Sysmon.zip` | 2.80 MB |
| Download the Sysmon config | `curl.exe -LO https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml` | Validated by Sysmon at install |

The first download failed on DNS (see Issues). Before installing, the binary's signature was checked:

```powershell
Get-AuthenticodeSignature Sysmon/Sysmon64.exe | Format-List Status,StatusMessage,SignerCertificate
# Status        : Valid
# StatusMessage : Signature verified.
# Subject       : CN=Microsoft Windows Publisher, O=Microsoft Corporation, ...
# Thumbprint    : CDCC1456D261BC0EB00975F46DFFB2E24592EDAD
```

The window was closed from the host with `VBoxManage controlvm WIN-TGT setlinkstate2 off`.

## 5. Network configuration and isolation

```powershell
New-NetIPAddress -InterfaceAlias Ethernet -IPAddress 10.10.10.20 -PrefixLength 24   # no -DefaultGateway
Set-TimeZone -Id "E. Africa Standard Time"
Disable-NetAdapter -Name "Ethernet 2" -Confirm:$false                               # see Finding 3.2
Rename-Computer -NewName WIN-TGT -Restart
```

The lab adapter was identified by MAC address (`08-00-27-F9-D5-AD`, the `soc-lab` adapter in VirtualBox), not by its Windows name. The NAT adapter is now off in two independent places: the virtual cable is unplugged in VirtualBox, and the adapter is disabled inside Windows. After the reboot Windows lists it as `Not Present` rather than `Disabled`; the cause was not investigated, and the adapter has no address and no route in either state.

## 6. Connectivity and firewall

| Test | Before rule | After rule |
|---|---|---|
| KALI → WIN-TGT `ping -c 4 10.10.10.20` | 0 received, 100% loss | 4 received, `ttl=128` |
| WIN-TGT → KALI `ping 10.10.10.50` | 4 replies from 10.10.10.50, `TTL=64` | not re-tested (unchanged by an inbound rule) |
| WIN-TGT → internet `ping 8.8.8.8` | `PING: transmit failed. General failure.`, 100% loss | same |

The lab network has no gateway, so Windows classifies it as `Unidentified network` with the **Public** profile, its strictest. One inbound rule was added (Finding 3.3):

```powershell
New-NetFirewallRule -DisplayName "SOC-LAB Allow ICMPv4 Echo from lab" -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -RemoteAddress 10.10.10.0/24 -Action Allow
```

The reply TTLs are a small operating-system fingerprint: Linux starts packets at 64 (KALI) and Windows at 128 (WIN-TGT).

## 7. Sysmon

```powershell
cd C:\Users\labadmin\Downloads
.\Sysmon\Sysmon64.exe -accepteula -i .\sysmonconfig-export.xml
# System Monitor v15.22 ... Loading configuration file with schema version 4.50
# Configuration file validated. Sysmon64 installed. SysmonDrv installed. ... Sysmon64 started.
```

The first attempt ran in a non-elevated terminal and stopped with `You need to launch Sysmon as an Administrator.` Even for an administrator account, User Account Control runs programs with standard rights unless they are explicitly elevated.

To confirm the telemetry, Notepad was started and its process-creation event read back:

```powershell
Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Sysmon/Operational'; Id=1} -MaxEvents 1 | Format-List TimeCreated,Message
```

| Field | Value | What it shows |
|---|---|---|
| `UtcTime` / `TimeCreated` | `21:33:50` UTC / `00:33:50` local | Sysmon records UTC; Windows displays local time (EAT, UTC+3). Timelines must use one or the other consistently. |
| `Image` | `C:\Program Files\WindowsApps\Microsoft.WindowsNotepad_11.2607.14.0_x64__8wekyb3d8bbwe\Notepad.exe` | Windows 11 runs the Store version of Notepad, not `C:\Windows\System32\notepad.exe`. A rule keyed only on the classic path would miss it. |
| `User` | `DESKTOP-NRHF2SO\labadmin` | The setup-generated hostname, renamed to `WIN-TGT` afterwards so alerts identify the host clearly |
| `IntegrityLevel` | `High` | Notepad inherited elevation from the administrator terminal that started it |
| `Hashes` | `MD5=...`, `SHA256=03745E9E...`, `IMPHASH=...` | File hashes recorded for every process, usable as indicators |

## 8. Baseline snapshots

```powershell
VBoxManage snapshot WIN-TGT take phase3-baseline --description "WIN-TGT hostname, 10.10.10.20/24 no gateway, NAT adapter disabled in guest and cable off, ICMP echo allowed from 10.10.10.0/24, Sysmon 15.22 SwiftOnSecurity config, EAT time zone, activated eval"
```

| Snapshot | State it holds |
|---|---|
| `phase3-fresh-install` | Windows installed, local account, never connected to the internet |
| `phase3-baseline` (current) | Activated, addressed, isolated, firewall rule, Sysmon running, renamed |

## 9. Verification

All checks after the rename were run after a reboot, so they prove the settings persist.

| # | Test | Expected | Result | Evidence |
|---|---|---|---|---|
| 1 | VM hardware | 4 GB, 2 vCPU, `soc-lab` on adapter 1, NAT cable off, clipboard off | **Pass** | [VM config](../evidence/screenshots/phase3-win-tgt-vm-config.png), [storage](../evidence/screenshots/phase3-win-tgt-storage.png) |
| 2 | Local account only | `labadmin`, "Local account" | **Pass** | [Desktop](../evidence/screenshots/phase3-win-tgt-desktop-local-account.png) |
| 3 | Licence activated | `LicenseStatus 1` | **Pass**: 129600 min remaining | [Before](../evidence/screenshots/phase3-win-tgt-licence-before.png), [after](../evidence/screenshots/phase3-win-tgt-licence-after.png) |
| 4 | Sysmon binary genuine | Signature `Valid`, Microsoft | **Pass** | [Signature](../evidence/screenshots/phase3-win-tgt-sysmon-signature.png) |
| 5 | Hostname | `WIN-TGT` | **Pass** | [Post-reboot baseline](../evidence/screenshots/phase3-win-tgt-post-reboot-baseline.png) |
| 6 | Static address | `10.10.10.20/24`, no gateway | **Pass** | same screenshot |
| 7 | No default route | `Get-NetRoute -DestinationPrefix 0.0.0.0/0` finds nothing | **Pass** | same screenshot, [route query](../evidence/screenshots/phase3-win-tgt-no-default-route.png) |
| 8 | Internet unreachable | `ping 8.8.8.8` fails locally | **Pass**: `General failure`, 100% loss | [NAT adapter disabled](../evidence/screenshots/phase3-win-tgt-nat-adapter-disabled.png) |
| 9 | NAT adapter off in guest | `Ethernet 2` not `Up` | **Pass**: `Not Present` | [Post-reboot baseline](../evidence/screenshots/phase3-win-tgt-post-reboot-baseline.png) |
| 10 | Firewall on | Domain, Private, Public `True` | **Pass** | same screenshot |
| 11 | Inbound ping from the lab only | Rule present; KALI receives 4/4 | **Pass**: `ttl=128` | [Rule](../evidence/screenshots/phase3-win-tgt-firewall-icmp-rule.png), [KALI ping](../evidence/screenshots/phase3-kali-ping-win-tgt-allowed.png) |
| 12 | Outbound to the lab | WIN-TGT receives 4/4 from KALI | **Pass** | [Ping KALI](../evidence/screenshots/phase3-win-tgt-ping-kali.png) |
| 13 | Sysmon running and logging | Service `Running` after reboot; Event ID 1 present | **Pass** | [Install](../evidence/screenshots/phase3-win-tgt-sysmon-install.png), [events](../evidence/screenshots/phase3-win-tgt-sysmon-events.png), [Event ID 1](../evidence/screenshots/phase3-win-tgt-sysmon-event1-notepad.png) |
| 14 | Baseline snapshot | `phase3-baseline` listed as current | **Pass** | [Snapshots](../evidence/screenshots/phase3-win-tgt-snapshots.png) |

## 10. Findings

### Finding 3.1: UEFI firmware hangs with more than one virtual CPU on this host

**Observation:** With UEFI firmware and 2 vCPUs, WIN-TGT showed a black screen indefinitely. The same VM with 1 vCPU booted normally. Enabling x2APIC had no effect. Legacy BIOS firmware with 2 vCPUs boots normally.

**Evidence:** In four 2-vCPU boots, `VBox.log` stops after the firmware loads `PciHostBridgeDxe.efi`, immediately after the debug marker `DXE_AP`. The display stays at 0x0 resolution and the VM process holds one host core at 100%. With 1 vCPU the firmware loads 121 modules instead of 51, initialises the display at 1024×768 and loads the Windows boot loader `cdboot.efi`. With x2APIC enabled the log reports `X2APIC - x2APIC support = 0 (1)`: offered by the host, not passed to the guest.

**Analysis:** `DXE_AP` is the stage where UEFI firmware starts the additional ("application") processors. VirtualBox here runs on the Windows hypervisor because Virtualization-Based Security is active on the host (Phase 1), and the hang is consistent with that combination failing to complete second-CPU start-up. This was established by changing one variable at a time; the underlying defect was not identified further. KALI was never affected because it boots with legacy BIOS. A single vCPU was not usable: Windows 11 Setup refuses fewer than two cores, and the `LabConfig` value `BypassCPUCheck` was confirmed present in the installer's registry yet ignored by both the current and the previous version of Setup.

**Risk:** Low for the lab. Under legacy BIOS, WIN-TGT has no Secure Boot, so it would not resist a bootkit, and it differs from a typical managed Windows 11 endpoint. None of the planned simulations depend on boot integrity. The TPM is still present.

**Recommendation and status:** Run WIN-TGT on legacy BIOS with 2 vCPUs and document the deviation from the plan. Revisit only if the host's VBS configuration changes, which was deliberately left on to protect the host. **Accepted.**

### Finding 3.2: stale default route on a disconnected adapter, hidden by a misleading ping summary

**Observation:** After the NAT cable was unplugged, WIN-TGT still held a default route, and a ping to the internet reported `0% loss`.

**Evidence:**

```
Get-NetRoute -DestinationPrefix 0.0.0.0/0
# ifIndex 4   0.0.0.0/0   NextHop 10.0.3.2   (ActiveStore)
ping 8.8.8.8
# Reply from 10.0.3.15: Destination host unreachable.   (x4)
# Packets: Sent = 4, Received = 4, Lost = 0 (0% loss)
```

([screenshot](../evidence/screenshots/phase3-win-tgt-stale-default-route.png)) Interface 4 is `Ethernet 2`, the NAT adapter, which `ipconfig` showed as `Media disconnected`. `10.0.3.2` is the VirtualBox NAT gateway and `10.0.3.15` was WIN-TGT's own NAT address.

**Analysis:** Windows kept the route it learned over DHCP while the cable was connected. The four "replies" were error messages generated by WIN-TGT itself, which the statistics count as received. Nothing left the VM. The danger is two-fold: containment depended on a single control (the virtual cable), and the summary line said the opposite of what happened.

**Risk:** Low while the cable stays unplugged. Medium if the cable is reconnected by mistake, because the VM would immediately have a working route to the internet.

**Recommendation and status:** Disable the NAT adapter inside Windows as a second, independent layer, and re-enable it only for a deliberate update window. Read the text of each ping reply, not only the summary. After `Disable-NetAdapter`, the default route is gone and `ping 8.8.8.8` fails with `General failure` and 100% loss, both before and after a reboot. **Remediated.**

### Finding 3.3: inbound ICMP blocked by default on the lab network

**Observation:** KALI could not ping WIN-TGT (100% loss), while WIN-TGT could ping KALI (4/4).

**Evidence:** `Get-NetConnectionProfile` shows `Ethernet`, `Unidentified network`, `Public`. ([KALI blocked](../evidence/screenshots/phase3-kali-ping-win-tgt-blocked.png), [WIN-TGT to KALI](../evidence/screenshots/phase3-win-tgt-ping-kali.png))

**Analysis:** A network with no gateway cannot be identified, so Windows assigns the Public profile, which blocks unsolicited inbound traffic including echo requests. Outbound pings succeed because the firewall is stateful: replies to connections WIN-TGT started are allowed back in. This is secure default behaviour, but it makes the host invisible to ping-based discovery, so Nmap would report it as down unless forced to scan.

**Risk:** None as a weakness. Opening ICMP slightly increases what the host reveals to lab machines.

**Recommendation and status:** Allow only inbound ICMPv4 echo requests (type 8), only from `10.10.10.0/24`, with the firewall otherwise unchanged and enabled on all profiles. Rule names carry a `SOC-LAB` prefix so lab changes can be audited with `Get-NetFirewallRule -DisplayName "SOC-LAB*"`. **Implemented.**

### Finding 3.4: target not patched

**Observation:** Windows Update was paused before the internet window and no updates have been applied since installation.

**Evidence:** Settings > Windows Update shows updates paused; the VM has had internet access only for activation and two downloads.

**Analysis:** This keeps the baseline fixed and reproducible, and avoids multi-gigabyte downloads on a slow VM. The trade-off is that WIN-TGT carries every vulnerability fixed since its build. For a target in an isolated lab, that is acceptable and partly useful.

**Risk:** Low in isolation. Unacceptable on any routed network.

**Recommendation and status:** Keep WIN-TGT unpatched and isolated. If a later phase needs a patched endpoint, apply updates in a controlled window and take a new snapshot. **Accepted.**

## 11. Issues encountered

| Issue | Cause | Resolution |
|---|---|---|
| `Move-Item` failed: file in use by another process | The ISO was mounted as drive `D:` after being opened in File Explorer | `Dismount-DiskImage`, then moved |
| `showvminfo \| Select-String "SATA \("` printed nothing | VirtualBox 7.2.8 prints attachments as `Port 0, Unit 0:` and `Location:` | Filtered on `Port \d\|Location:` |
| Black screen at power-on | UEFI with 2 vCPUs hangs on this host | Finding 3.1 |
| First power-off saved the hung state, so the next start resumed the hang | Closing the VM window defaults to "Save the machine state" | Use `VBoxManage controlvm WIN-TGT poweroff` for a frozen VM |
| `Cannot disable the APIC for a 64-bit guest` | `modifyvm --x2apic off` also turned off the basic APIC | `modifyvm --apic on`; the x2APIC switch is no longer used |
| Setup: "The processor needs to have two or more cores" with `BypassCPUCheck` set ([new Setup](../evidence/screenshots/phase3-win-tgt-setup-cores-check-failed.png), [previous Setup](../evidence/screenshots/phase3-win-tgt-legacy-setup-refused.png), [key present](../evidence/screenshots/phase3-win-tgt-labconfig-verified.png)) | The value is ignored on this build | Moved to BIOS firmware with 2 vCPUs |
| A `reg add` "completed successfully" but had no effect | Typed `SYSTEM\System\LabConfig` instead of `SYSTEM\Setup\LabConfig` | Corrected, then confirmed with `reg query` |
| Text sent with `keyboardputstring` arrived with `#` instead of `\` | It sends US key codes; the installer was using a UK layout | Typed by hand, or used the UK backslash key code |
| `curl: (6) Could not resolve host`, then `CRYPT_E_REVOCATION_OFFLINE` ([screenshot](../evidence/screenshots/phase3-win-tgt-dns-resolve-failure.png)) | The NAT adapter's DNS server was `192.168.0.1`, which did not exist on the host's current network (`192.168.100.1`); a cached answer made `microsoft.com` appear to resolve | Unplugged and replugged the NAT cable so the VM requested fresh settings |
| `You need to launch Sysmon as an Administrator.` ([screenshot](../evidence/screenshots/phase3-win-tgt-sysmon-not-elevated.png)) | Run in a non-elevated terminal | Re-run in Terminal (Admin) |
| Host commands run inside the VM failed (`$vb` undefined) | Host and guest terminals look alike | Check the prompt: `C:\WINDOWS\System32` or `esthe` is the host; `labadmin` is WIN-TGT |

## 12. Lessons learned

- Change one variable per test. A single-CPU boot turned "black screen" into a specific, confirmed cause in one step.
- Read logs before guessing. The firmware log showed exactly where boot stopped, which no amount of waiting at a black screen would have shown.
- "Completed successfully" means the command did what was typed, not what was intended. Read the result back (`reg query`, `Get-NetRoute`).
- Summary statistics can invert the truth. "0% loss" hid four local error messages.
- Isolation should not rest on one control. The NAT adapter is now off both in VirtualBox and in Windows.
- Verify telemetry against reality before writing rules. Notepad no longer lives where most guides say it does.
- Record UTC and local time explicitly. Sysmon and the Windows event viewer show the same event three hours apart.

## Next phase

Phase 4: Wazuh server and agent. Build WAZUH-SRV at 10.10.10.10 and enrol WIN-TGT as the first agent.
