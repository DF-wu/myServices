# myServices
df home lab services 👊😎💥

## note
1. remember to set up enviroment variable when system boot.
   1.  `DF_PASSWORD`
   2.  `IDRAC_PASSWORD`
2. set up `.env.sensitive` or no secret be loaded.
3. `crontab` and `@restart` is a simple way to do it.


## Esxi config
+ for ssd TRIM optimization. set below options to 1 (enable).
  + `HBR.UnmapOptimization`
  + `VMFS3.EnableBlockDelete`

## Configuration for Nvidia driver
**!!Fuck you Nvidia!!**
### New discorvery !!
+ The dkms `nvidia-open-driver` in AUR is working for my system. You can just install by AUR helper easily.


## TODO
+ My CI/CD toolchain  
  + Github/gitlab ci or my jenkins?
+ Discord_CDN dockerize and deploy as a bot for discord.
  1. a bot proxy url and publish proxyed url to target channel.
  2. containerize.



### Proprietary driver.
+ ESXI options
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
  + This step is to update bootloder. It loads kernal module when booting kernal
    + for debian or its series = `sudo update-initramfs -u`
    + for endeavour or arch is = `sudo dracut-rebuild`

+ driver install form Nvidia official binary installer
  + install with `-m=kernel-open` arguments
  + credit: https://forums.developer.nvidia.com/t/solved-rminitadapter-failed-to-load-530-41-03-or-any-nvidia-modules-other-than-450-236-01-linux-via-esxi-7-0u3-passthrough-pci-gtx-1650/253239
