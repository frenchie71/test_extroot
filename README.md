# test_extroot
script to test, fix and mount extroot overlay on OpenWrt routers

What is it?

OpenWrt supports mounting the root overlay drive on an external USB Stick. 
By doing that you may use a newer OpenWrt version with additional software (such as Mosquitto, Fhem or Dovecot) even though your router only has let's say 8 MB Storage.
Another use case (the one I am using) is using the extroot functionality to switch router config.

For example, if you have two active routers - one is your main router and the other one is just an additional WIFI Access point, you might want to have a 3rd device in the drawer as a "cold standby" which you want to pull out in case one of the production routers fails.

Traditionally, you would now have to reinstall everything on the standby router, restore the back up of the config etc.

Using extroot you could just plug in the USB stick of the defective router into the standby router, switch it on (maybe reboot once) and voilà - you have the failed router's config applied to your standby device.

However, there is some caveats which make things not quite sooo easy - hence the reason for this script:

1. OpenWrt writes the UUID of the drive that has been overlayed with the stick into a hidden file on the stick, thus preventing mount on a different device
2. Some devices show up late (e.g. SD cards in Huawei 3G Sticks) as they need e.g. usbmode in order to show up. Usbmode is unfortunately loaded after the extroot check done by OpenWrt
3. The stick might have a corrupt filesystem if it had not been cleanly unmounted. In most cases OpenWrt fixes it, but sometimes it does not.
4. The config on the (builtin MTDBLOCK) overlay needs to be the same as the one on the stick as some things are loaded before extroot
5. In case your hardware changes (i.e. you mount the stick on a different router) the wireless devices might not work anymore because they have the wrong path values. I experienced this between an Archer V1.1, V2.2 and V5

So you may find yourself in a situation where you had a working overlay extroot on USB, you reboot the router and it does not work anymore.

The purpose of this script is to fix some of these conditions

How to use it?

Just copy the script to let's say /usr/bin on your internal AND external overlay (i.e. boot without the stick, copy it into /usr/bin, then mount the stick and copy it to <mountpoint>/upper/usr/bin on the stick)
  
Then add a line to your /etc/rc.local file calling the script, e.g.

# call the extroot check script
/usr/bin/test_extroot.sh

That's it - however be aware that this version contains some specifics such as

1. You need to have rsync installed (at least on the script)
2. The script mounts to /dev/sda2 or /dev/sda1
3. currently it is specific to TP-Link Archer C7 V2 and V5, but if you use it for a different brand, et me know and we can create a new branch

Have fun!
