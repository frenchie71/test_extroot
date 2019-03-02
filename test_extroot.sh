#!/bin/sh

# #############################################
# #############################################
# extroot und cold standby config check script
# #############################################
# #############################################

EXTROOT_OK=NO
EXTROOTDRIVE_PRESENT=NO
TMPMOUNT_OK=NO
TMPMOUNT_LOCATION=/tmp/extrootmount
EXTROOTDRIVE=/dev/sda2
EXTROOTDRIVE2=/dev/sda1

. /lib/functions.sh

MTDPARTITION=$(find_mtd_part rootfs_data)


# #############################################
# Log function
# #############################################

log_extroot_check() {
    /bin/echo "extroot_check: $1" > /dev/kmsg
}
# #############################################
# tmpmount function
# #############################################

extroot_tmpmount() {
    /bin/mkdir -p $TMPMOUNT_LOCATION
	/bin/mount -t ext4 $EXTROOTDRIVE $TMPMOUNT_LOCATION
	if [ "$(/bin/mount | grep $EXTROOTDRIVE)" ] ; then 
		TMPMOUNT_OK=YES 
		log_extroot_check "extroot $EXTROOTDRIVE temp mounted"
	else
		log_extroot_check "extroot $EXTROOTDRIVE temp mount NOT OK"
	fi
}

# #############################################
# extroot checks
# #############################################


# prüfen ob extroot OK ist

if [ "$(/bin/dmesg | /bin/grep 'mount_root: switched to extroot')" ]  ; then 
	EXTROOT_OK=YES 
	log_extroot_check "extroot OK and mounted"
fi

# extroot ist nicht OK - feststellen warum und ggf fixen


if [ "$EXTROOT_OK" = "NO" ] ; then

	log_extroot_check "extroot seems to be absent, checking..."

	# wir schauen mal ob es überhaupt einen Stick gibt
	# Falls eine Swap Partition existiert, liegt die 
	# extroot Partition auf sda2, sonst auf sda1

	if [ -e $EXTROOTDRIVE ]; then
		EXTROOTDRIVE_PRESENT=YES
		log_extroot_check "$EXTROOTDRIVE exists"
	else
		log_extroot_check "$EXTROOTDRIVE not here, checking $EXTROOTDRIVE2"
		if [ -e $EXTROOTDRIVE2 ]; then
			EXTROOTDRIVE_PRESENT=YES
			log_extroot_check "$EXTROOTDRIVE2 exists"
			EXTROOTDRIVE=$EXTROOTDRIVE2
		else
			log_extroot_check "$EXTROOTDRIVE2 not here, STICKLESS CONFIG"
			exit 0
		fi
	fi

	# an diesem Punkt sind wir sicher, dass ein Device sda1 oder sda2 existiert
	# versuche den Stick in einer temporären Lokation zu mounten

	extroot_tmpmount

	# falls es nicht geklappt hat versuchen wir es mal mit e2fsck

	if [ "$TMPMOUNT_OK" = "NO" ] ; then
		log_extroot_check "running e2fsck on $EXTROOTDRIVE"
		/usr/sbin/e2fsck -p  $EXTROOTDRIVE
		extroot_tmpmount
	fi

	# falls das auch nicht geklappt hat müssen wir erstmal aufgeben

	if [ "$TMPMOUNT_OK" = "NO" ] ; then
		log_extroot_check "could not TMPMOUNT $EXTROOTDRIVE - aborting"
		exit 1
	else
		log_extroot_check "TMPMOUNT $EXTROOTDRIVE OK"
	fi

	# an diesem Punkt sind wir sicher dass das Device an der Temp location 
	# gemounted ist

	# mount_root verweigert den mount wenn die UUID falsch ist
	# was aber bei failover auf das andere Gerät by design so ist

		
#	if [ "$(/bin/dmesg | /bin/grep 'block: extroot: UUID mismatch')" ]  ; then 
		log_extroot_check "fixing UUID"
		if [ -e "$TMPMOUNT_LOCATION/etc/.extroot-uuid" ]; then
			/bin/rm "$TMPMOUNT_LOCATION/etc/.extroot-uuid"
			log_extroot_check "UUID Marker deleted"
		fi
#	fi

	# Wir kopieren die fstab vom Stick auf das Block Overlay

	if [ -e "$TMPMOUNT_LOCATION/upper/etc/config/fstab" ]; then
		log_extroot_check "Copying fstab from extroot to mtd overlay"
		/bin/cp "$TMPMOUNT_LOCATION/upper/etc/config/fstab" /overlay/upper/etc/config/fstab
	fi

	# mehr können wir erstmal nicht machen wir unmounten

	log_extroot_check "unmounting $TMPMOUNT_LOCATION"
	/bin/umount $TMPMOUNT_LOCATION

	# und versuchen nun nochmals den "normalen" mount_root

	log_extroot_check "attempting root mount"
	export PREINIT=1;mount_root

	# hat's geklappt?

	if [ "$(/bin/dmesg | /bin/grep 'mount_root: switched to extroot')" ]  ; then 
			EXTROOT_OK=YES 
			log_extroot_check "extroot OK and mounted"
	else
		log_extroot_check "mount_root seems to have failed, exiting"
		exit 1
	fi
fi

# an diesem Punkt des Scriptes haben wir sicher ein overlay extroot gemounted

# unter bestimmten Voraussetzungen werden wir booten müssen, da zu diesem 
# Zeitpunkt die Config vom MTD geladen ist.
# Sollte sich z.B. die Switch- oder IP Konfiguration unterscheiden,
# ist es sicherer den Rooter einmal zu booten.

# um einen erneuten Reboot zu vermeiden, kopieren wir die Dateien zunächst 
# vom Stick aufs Blockdevice, passen sie an und kopieren sie auch wieder zurück.
# Somit haben wir beim nächsten Boot einen konsistenten Stand.

REBOOTFLAG=NO

# Jetzt folgt die Anpassung der Konfiguration
# ausserdem kopieren wir sicherheitshalber die Config vom
# Stick auf das MTD Laufwerk, so daß auch ohne Stick
# eine halbwegs brauchbare Config vorliegt



# Gibt es einen Unterschied in der Konfiguration?

# zunächst müssen wir das alte Overlay finden
# OpenWRT mounted dieses in /rom/overlay falls wir den
# Stick spät gemounted haben
# ansonsten haben wir den Eintrag in der fstab

/bin/mount | /bin/grep "rom/overlay" && /bin/umount /rom/overlay


MTDMOUNTED=NO
/bin/mount | /bin/grep "$MTDPARTITION" && MTDMOUNTED=YES

if [ "$MTDMOUNTED" = "NO" ] ; then
	/bin/mkdir -p /root_overlay
	/bin/mount -t jffs2 $MTDPARTITION /root_overlay
fi

MTDMOUNTLOCATION=$(/bin/mount | /bin/grep "$MTDPARTITION" | /usr/bin/awk -F ' ' '{print $3}')

log_extroot_check "mtdblock overlay $MTDPARTITION is mounted on $MTDMOUNTLOCATION"

cd "$MTDMOUNTLOCATION/upper/etc"

FILESHAVECHANGED=NO

for i in $(/usr/bin/find *) ; do 
	if [ -f $i ] ; then 
		/usr/bin/cmp "$i" "/overlay/upper/etc/$i"
		rc=$?
		if [[ $rc != 0 ]]; then 
			FILESHAVECHANGED=YES
		fi
	fi
done

# Falls ja, kopiere Stick -> MTD Overlay
# und setze das Reboot Flag


if [ "$FILESHAVECHANGED" = "YES" ] ; then
	log_extroot_check "Files have changed - rsync and reboot..."
	REBOOTFLAG=YES
	/usr/bin/rsync -av --del /overlay/upper/etc/ "$MTDMOUNTLOCATION/upper/etc/"

	# we need to reboot here because otherwise we might have wrong information for the interface
	# cards eth0, eth1 below in case we have a hardware change with late extroot mount

	#/sbin/reboot
else
	log_extroot_check "no Files have changed..."
	REBOOTFLAG=NO
fi


log_extroot_check "now fixing hardware changes..."

# hat sich die Hardware verändert?
# falls ja, patchen, zurückkopieren und REBOOT Flag

HARDWARECHANGED=NO

# Archer C7 V1 und V2 haben einen qca9558

HWID1=qca955
PCI_ID1="pci0000:01/0000:01:00.0"

# V4 und V5 haben einen qca956x

HWID2=qca956
PCI_ID2="pci0000:00/0000:00:00.0"

PCI_ID_WANT=UNKNOWN

# feststellen, auf welcher CPU das System läuft

/bin/grep -i $HWID1 /proc/cpuinfo && HWID=$HWID1 && PCI_ID_WANT=$PCI_ID1
/bin/grep -i $HWID2 /proc/cpuinfo && HWID=$HWID2 && PCI_ID_WANT=$PCI_ID2

PLATFORM_ID_WANT="platform/${HWID}x_wmac"

log_extroot_check "cpu says it is a $HWID..."
log_extroot_check "we want PCI $PCI_ID_WANT and $PLATFORM_ID_WANT..."

# die richtigen wireless PArameter eintragen und ggf. Falsche löschen

/sbin/uci set wireless.radio0.path="$PCI_ID_WANT"
/sbin/uci set wireless.radio1.path="$PLATFORM_ID_WANT"
/sbin/uci delete wireless.radio2
/sbin/uci delete wireless.radio3
/sbin/uci delete wireless.default_radio2
/sbin/uci delete wireless.default_radio3
/sbin/uci commit

/usr/bin/cmp "${MTDMOUNTLOCATION}/upper/etc/config/wireless" "/overlay/upper/etc/config/wireless"
rc=$?
if [[ $rc != 0 ]]; then 
	log_extroot_check "wireless config has changed"
	/bin/cp  "/overlay/upper/etc/config/wireless" "${MTDMOUNTLOCATION}/upper/etc/config/wireless"
else
	log_extroot_check "no change in wireless config"
fi

/sbin/uci show network |grep ifname | grep eth >/tmp/eth.cfg



# jetzt die Netzwerk-Parameter prüfen 
# auf dem V5 gibt es nur eth0
# auf dem V1/V2 gibt es eth1

# In unserem Falle: (muss auf jeden Individualfall angepaßt werden)

# Scenario1 : V5 -> V2 : Im Config gibt es eth0 und wir sind auf V2 HW

CONFIG_IS_V5=NO && grep eth0 /tmp/eth.cfg && CONFIG_IS_V5=YES

[ "$CONFIG_IS_V5" = "YES" ] && [ "$HWID" = "$HWID1" ] && {
	while read line 
	do 
		line=$(echo "$line" | sed -e s/eth1/eth2/g -e s/eth0/eth1/g -e s/\'//g)
   		/sbin/uci set "$line"   		 
	done < /tmp/eth.cfg
	/sbin/uci commit
	/bin/cp  "/overlay/upper/etc/config/network" "${MTDMOUNTLOCATION}/upper/etc/config/network"
	log_extroot_check "updated network config V5 to V2"
}

# Scenario2 : V2 -> V5 

[ "CONFIG_IS_V5" = "NO" ] && [ "$HWID" = "$HWID2" ] && {
	while read line 
	do 
		line=$(echo "$line" | sed -e s/eth1/eth0/g -e s/eth2/eth1/g -e s/\'//g)
   		/sbin/uci set "$line"   		 
	done < /tmp/eth.cfg
	/sbin/uci commit
	/bin/cp  "/overlay/upper/etc/config/network" "${MTDMOUNTLOCATION}/upper/etc/config/network"
	log_extroot_check "updated network config V2 to V5"
}

/etc/init.d/network restart
/sbin/luci-reload

