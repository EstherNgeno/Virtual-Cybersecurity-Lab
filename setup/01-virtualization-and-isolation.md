# Phase 1: Virtualization and Network Isolation

| | |
|---|---|
| **Status** | Complete |
| **Date** | 2026-10-08 to 2026-10-09 |
| **Hosts in scope** | Windows 11 host, KALI, LNX-TGT |

## Objective

Prepare the virtualization platform and build an isolated lab network, so that later scanning and attack simulations stay entirely inside the lab.

## Environment

| Component | Detail |
|---|---|
| Host | Windows 11 Pro laptop, 16 GB RAM, 4 cores / 8 threads, SSD |
| Hypervisor | Oracle VirtualBox 7.2.8 |
| Lab network | VirtualBox Internal Network `soc-lab`, 10.10.10.0/24 |

The full design is in [network-plan.md](../architecture/network-plan.md).

## 1. Host virtualization assessment

**Observation:** The host already runs the Windows hypervisor. Virtualization-based security (VBS) is active, with Memory Integrity, System Guard Secure Launch and SMM firmware protection running. The Virtual Machine Platform feature is enabled.

**Evidence:**

```powershell
Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard |
  Select-Object VirtualizationBasedSecurityStatus, SecurityServicesRunning
# VirtualizationBasedSecurityStatus : 2
# SecurityServicesRunning           : {2, 3, 4}
```

**Analysis:** Because Windows already controls the CPU's virtualization extensions, VirtualBox cannot use them directly and instead runs guests through the Windows hypervisor. This is shown by the green turtle icon in the VM status bar.

**Risk:** Disabling VBS would give VirtualBox direct hardware access and better performance, but would remove kernel protections from a daily-use host.

**Decision:** Host protections were kept enabled. Kali was tested under these conditions and performance was acceptable, so no host security features were changed.

## 2. Lab network configuration

### KALI: assessment and capture host

```powershell
VBoxManage modifyvm "kali-linux-2026.1-virtualbox-amd64" --nic1 intnet --intnet1 soc-lab --nic-promisc1 allow-vms
VBoxManage modifyvm "kali-linux-2026.1-virtualbox-amd64" --nic2 nat --cable-connected2 off
VBoxManage modifyvm "kali-linux-2026.1-virtualbox-amd64" --clipboard-mode hosttoguest --drag-and-drop disabled
```

| Setting | Value | Rationale |
|---|---|---|
| Adapter 1 | Internal Network `soc-lab` | Places Kali on the isolated segment |
| Promiscuous mode | Allow VMs | Lets Wireshark observe traffic between other lab hosts |
| Adapter 2 | NAT, cable disconnected | Updates possible only when deliberately reconnected |
| Clipboard | Host to guest | Commands can be pasted in; nothing can be copied out |
| Drag and drop | Disabled | Prevents file transfer to the host |

Static addressing inside Kali, deliberately without a gateway:

```bash
sudo nmcli connection add type ethernet ifname eth0 con-name soc-lab \
  ipv4.method manual ipv4.addresses 10.10.10.50/24 ipv6.method disabled \
  connection.autoconnect-priority 10
sudo nmcli connection up soc-lab
```

### LNX-TGT: Metasploitable 2

```powershell
VBoxManage discardstate "Metasoploitable-2"
VBoxManage modifyvm "Metasoploitable-2" --nic1 intnet --intnet1 soc-lab --cable-connected1 on
```

LNX-TGT is intentionally vulnerable, so it has **no NAT adapter**. Adapters 2–4 are disabled.

Static address in `/etc/network/interfaces`, with no gateway:

```
auto eth0
iface eth0 inet static
    address 10.10.10.30
    netmask 255.255.255.0
```

## 3. Verification

| # | Test | Expected | Result | Evidence |
|---|---|---|---|---|
| 1 | KALI adapter configuration | Internal `soc-lab`, NAT cable disconnected | **Pass** | [Kali adapters](../evidence/screenshots/phase1-kali-adapter-verification.png) |
| 2 | KALI promiscuous mode | `Promisc Policy: allow-vms` on NIC 1 | **Pass** | `showvminfo` output (see Issues: not shown by `--machinereadable`) |
| 3 | LNX-TGT adapter configuration | Internal `soc-lab` only; NIC 2–4 disabled | **Pass** | [LNX-TGT reconfiguration](../evidence/screenshots/phase1-lnx-tgt-reconfigure.png), [LNX-TGT adapters](../evidence/screenshots/phase1-lnx-tgt-adapter-verification.png) |
| 4 | KALI address | `eth0` UP, 10.10.10.50/24; `eth1` (NAT) DOWN | **Pass** | [Kali connectivity and isolation](../evidence/screenshots/phase1-kali-connectivity-and-isolation.png) |
| 5 | KALI route table | Only `10.10.10.0/24`; no `default` route | **Pass** | same screenshot |
| 6 | LNX-TGT address | 10.10.10.30, mask 255.255.255.0 | **Pass** | [LNX-TGT ifconfig](../evidence/screenshots/phase1-lnx-tgt-ifconfig.png) |
| 7 | KALI → LNX-TGT connectivity | `ping -c 4 10.10.10.30`: 0% loss | **Pass**: 4/4 received, avg RTT 2.7 ms, TTL 64 | [Kali connectivity and isolation](../evidence/screenshots/phase1-kali-connectivity-and-isolation.png) |
| 8 | KALI → internet isolation | `ping -c 2 8.8.8.8` fails | **Pass**: `connect: Network is unreachable` | same screenshot |

**Interpretation of test 8:** the ping failed immediately with `Network is unreachable`, not after a timeout. The kernel refused to send the packet because no route matched 8.8.8.8, which confirms the absence of a default route. A timeout would instead have meant the packet left Kali and was dropped somewhere, a weaker form of isolation.

**Interpretation of test 7:** TTL 64 is the default starting value for Linux hosts, unchanged, which confirms that KALI and LNX-TGT sit on the same layer-2 segment with no router in between.

## 4. Findings

### Finding 1.1: intentionally vulnerable host previously had an internet path

**Observation:** Before this phase, the Metasploitable 2 VM was attached to a VirtualBox NAT Network, which provides outbound internet access.

**Evidence:** `showvminfo` before the change reported `nic1="natnetwork"`. After the change it reports `Attachment: Internal Network 'soc-lab'` with NIC 2–4 disabled.

**Analysis:** Metasploitable 2 contains many known vulnerabilities by design. NAT does not accept unsolicited inbound connections, so direct exposure was limited. However, any compromise inside the VM could have reached the internet.

**Risk:** Medium, in a lab context. A vulnerable host with outbound access could be used to download tools or reach external systems.

**Recommendation and status:** Restrict intentionally vulnerable hosts to an isolated segment with no gateway. **Remediated** in this phase.

### Finding 1.2: bidirectional clipboard and drag-and-drop on the assessment host

**Observation:** The Kali VM originally allowed clipboard sharing and drag-and-drop in both directions.

**Analysis:** Two-way sharing creates a path for data or files to move from the lab to the host.

**Recommendation and status:** Limit to host-to-guest clipboard with drag-and-drop disabled. **Remediated** in this phase.

## 5. Issues encountered

| Issue | Cause | Resolution |
|---|---|---|
| Hypervisor already present on host | VBS and Virtual Machine Platform active | Kept protections enabled; confirmed guests run with acceptable performance |
| Duplicate VMs in VirtualBox | Earlier setup attempts; one copy had a blank disk and the wrong OS type | Identified the working copies by disk path and prior run state; duplicates left untouched |
| Promiscuous mode missing from verification output | `showvminfo --machinereadable` does not print it | Verified with plain `showvminfo` (`Promisc Policy: allow-vms`) |
| VM settings could not be changed | Metasploitable was in a saved state | `VBoxManage discardstate` before reconfiguring |

## 6. Lessons learned

- Check what already runs on the host before installing anything. The hypervisor conflict was found before it caused a failure.
- An isolated network is only as isolated as its least-isolated adapter. Audit every adapter, not just the first.
- Test the negative case. Proving that `ping 8.8.8.8` fails is as important as proving the lab hosts can reach each other.

## Next phase

Phase 2: Kali Linux. Baseline checks, update procedure and snapshot strategy.
