# myServices
df home lab services 👊😎💥

## note
1. remember to set up enviroment variable when system boot.
2. set up `.env.sensitive` or no secret be loaded.
3. `crontab` and `@restart` is a simple way to do it.

## Configuration for Nvidia driver
**!!Fuck you Nvidia!!**
+ Esxi options
  + hypervisor.cpuid.v0 false
  + isolation.tools.copy.disable false   (for clipboard)
+ modprob.d 
  + for `nouveau` driver
    + make sure `nouveau` driver has set to block.
```
    blacklist nouveau
    options nouveau modeset=0
```
  + for Nvidia driver 
```
options nvidia NVreg_EnablePCIeGen3=1
options nvidia NVreg_EnableGpuFirmware=0
options nvidia NVreg_OpenRmEnableUnsupportedGpus=1
```
+ ***IMPORTANT TO UPDATE INITRAMFS***
  + for debian or its series = `sudo update-initramfs -u`
  + for endeavour or arch is = `sudo dracut-rebuild`

+ driver install form Nvidia official binary installer
  + install with `-m=kernel-open` arguments
  + credit: https://forums.developer.nvidia.com/t/solved-rminitadapter-failed-to-load-530-41-03-or-any-nvidia-modules-other-than-450-236-01-linux-via-esxi-7-0u3-passthrough-pci-gtx-1650/253239
