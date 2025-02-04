# myServices
Personal Home Lab Services Configuration 👊😎💥

Master branch is development branch = production environment (YOLO)

## Setup Notes
### Environment Variables
1. Required environment variables at system boot:
   - `DF_PASSWORD`
   - `IDRAC_PASSWORD`
2. Source them in `.bashrc`
3. Note: MariaDB is installed on VM home disk

### Cron Jobs
```bash
# MariaDB backup every Sunday at 2 AM
0 2 * * 0 /home/df/_serverDataAndScript/crontab/mariadb-backup.sh
# Auto-sign script every 6 hours
0 */6 * * * /home/df/workspace/myServices/_CRONJOBS/tsdm-autosign/tsdm-work.sh
```

## System Configuration Guide

### TrueNAS Notes
⚠️ Do not enable SMB audit log. Known bug causes oversized logs affecting service integrity.

### ESXi Optimization
For SSD TRIM optimization, set these options to 1:
- `HBR.UnmapOptimization`
- `VMFS3.EnableBlockDelete`

### NVIDIA Driver Configuration

**!!Fuck you Nvidia!!**

#### Open Source Driver
- The DKMS `nvidia-open-driver` in AUR is working properly. Install directly via AUR helper.

#### Proprietary Driver Setup
1. ESXi Options:
   - `hypervisor.cpuid.v0 false`
   - `isolation.tools.copy.disable false` (for clipboard functionality)

2. Modprobe Configuration:
   - Blocking nouveau driver:
     ```bash
     blacklist nouveau
     options nouveau modeset=0
     ```
   - NVIDIA driver options:
     ```bash
     options nvidia NVreg_EnablePCIeGen3=1
     options nvidia NVreg_EnableGpuFirmware=0
     options nvidia NVreg_OpenRmEnableUnsupportedGpus=1
     ```

3. Update Initramfs (Important):
   - Debian-based: `sudo update-initramfs -u`
   - Arch/Endeavour: `sudo dracut-rebuild`

4. NVIDIA Official Installer:
   - Install with `-m=kernel-open` parameter
   - Reference: [NVIDIA Forum Solution](https://forums.developer.nvidia.com/t/solved-rminitadapter-failed-to-load-530-41-03-or-any-nvidia-modules-other-than-450-236-01-linux-via-esxi-7-0u3-passthrough-pci-gtx-1650/253239)

## TODO
- [ ] CI/CD Toolchain
  - Choose between GitHub/GitLab CI or self-hosted Jenkins
- [ ] Discord_CDN Dockerization
  1. Implement bot proxy URL functionality
  2. Containerize service
