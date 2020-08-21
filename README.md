# check-ping

## Script for using more then one WAN in OpenWrt with really fast switching
Tested on OpenWrt OpenWrt 19.07.3, r11063-85e04e9f46, BusyBox v1.30.1 () built-in shell (ash)

## Usage

1. Place this script to /root
2. Change IPs and IDs with your own
3. Install dependencies  
`opkg update && opkg install coreutils-stat curl findutils-find fping`
4. Add this line to crontab  
`* * * * * /root/check-ping.sh`
