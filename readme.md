# Aruba Instant AP (IAP) renaming script

This script is used to rename all access points in an Aruba Instant Cluster (IAP) according to a customizable naming scheme.
To allow printed labels to be quickly attached to the correct AP, the AP flashes during renaming until confirmation by the user.

# Functionality

This Powershell script uses the _PowerArubaIAP_ module to query the actively connected access points of an IAP cluster from the master via the REST API.

According to the naming scheme defined in the settings file, the name of all APs in the cluster is then adjusted.

So that labels can be stuck on the APs, the currently renamed AP flashes. The blinking is done via SSH using the _POSH-SSH_ module by issuing the command `ap-leds blink`. If the user confirms that he has stuck the label on the AP, the LED state is reset with `ap leds normal` and the SSH connection is closed.

The numbering/sorting of the APs is based on the serial number.

# Requirements

```Powershell
Install-Module -Name Posh-SSH
Install-Module -Name PowerArubaIAP
```

Enable the REST API on the IAP cluster (can only be enabled via SSH)
```
AP# configure
AP (config) # allow-rest-api
AP (config) # exit
AP# commit apply
```

The script was tested with ArubaOS 8.11.2.0

# Settings


Define the IP address and the admin credentials for the API connection to the IAP Virtual Controller in the config file `settings.json`

```json
{
  "ip": "192.168.3.110",
  "username": "admin",
  "password": "123456"
  ...
}
```

Specify the scheme according to which the APs are to be named. If the first AP should not start at number 1, then this can be specified in `firstnumber`.

If leading zeros are to be used in the numbering, `numberdigits` can be used to specify how many digits the numbering has.

If no leading zeros are to be used, this value can remain at 1.

```json
{
  ...
  "nameprefix": "AP-Test-",
  "firstnumber": 1,
  "numberdigits": 2
}
```

# Usage

Execute the `ap.ps1` script after setting up the parameters in `settings.json`

```Powershell
PS C:\iap-rename> .\renameIAP.ps1
```

Output:

```

PS C:\iap-rename> .\renameIAP.ps1

Name       Ip            Sn
----       --            --
AP-ABCD-01 192.168.3.111 CN12345678
AP-ABCD-02 192.168.3.112 CN23456789


Found 2 active APs
Skip some already renamed APs? (y/n) [n]
y

First AP number to rename?
2

Skipping to AP number 2 of 2
First AP name will be AP-Test-02
Continue? (y/n)
y

----------------------------------------
new name: AP-Test-02

old name: AP-Test-02
IP: 192.168.3.112, SN: CN23456789
----------------------------------------

establishing ssh connection... (1/3)
ssh connection not yet ready, waiting... (1/8)
ssh connection not yet ready, waiting... (2/8)
sending command ap-leds blink (1/3)
AP LEDs set to blink
AP renamed to AP-Test-02
Press enter to continue

sending command ap-leds normal (1/3)
AP LEDs set to normal

Done

```
