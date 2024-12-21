# KeenKit
### Multifunctional script that simplifies interaction with the router on the ported KeeneticOS

# Installation
1. Via `SSH` get into the pre-installed [Entware](https://keen-prt.github.io/wiki/helpful/entware)

2. Install the script
```
opkg update && opkg install curl && curl -L -s "https://raw.githubusercontent.com/madcrow/KeenKit/main/install.sh" > /tmp/install.sh && sh /tmp/install.sh
```
Launch via:
>keenkit, KeenKit or /opt/keenkit.sh

# Description of commands
- ## **Update firmware**
    - Searches for a file with the .bin extension on the built-in/external storage device and then installs it on the Firmware or Firmware_1/Firmware_2 partitions
- ## **Backup partitions**
    - Backup partitions/s to the selected drive
- ## **Entware Backup**
    - Creates a full backup of the drive from which the script is launched.
- ## **Replace Partition**
    - Replace a system partition with a partition selected by the user
- ## **OTA Update**
    - Online upgrade/downgrade of ported Keenetic firmware
- ## **Replace service data**
    - Creates a new U-Config with modified service data, and also overwrites the current one
