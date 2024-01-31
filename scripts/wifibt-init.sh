#!/bin/sh -e

wifi_ready()
{
	grep -wqE "wlan0|p2p0" /proc/net/dev
}

bt_ready()
{
	hciconfig | grep -wqE "hci0"
}

rfkill_for_type()
{
	grep -rl "^${1:-bluetooth}$" /sys/class/rfkill/*/type | \
		sed 's/type$/state/' 2>/dev/null || true
}

bt_reset()
{
	RFKILL=$(rfkill_for_type bluetooth)
	[ "$RFKILL" ] || return 0

	echo 0 | tee $RFKILL >/dev/null
	echo 0 > /proc/bluetooth/sleep/btwrite
	sleep .5
	echo 1 | tee $RFKILL >/dev/null
	echo 1 > /proc/bluetooth/sleep/btwrite
	sleep .5
}

start_bt_brcm()
{
	killall -q -9 brcm_patchram_plus1 || true
	which brcm_patchram_plus1 >/dev/null

	bt_reset

	brcm_patchram_plus1 --enable_hci --no2bytes \
		--use_baudrate_for_download --tosleep 200000 \
		--baudrate 1500000 \
		--patchram ${WIFIBT_FIRMWARE_DIR:-/lib/firmware}/ $WIFIBT_TTY&
}

start_bt_rtk_uart()
{
	killall -q -9 rtk_hciattach || true
	which rtk_hciattach >/dev/null

	bt_reset

	if ! lsmod | grep -wq hci_uart; then
		if [ -d /sys/module/hci_uart ]; then
			echo "Please disable CONFIG_BT_HCIUART in kernel!"
			return -1
		fi

		insmod hci_uart.ko
		sleep .5
	fi

	rtk_hciattach -n -s 115200 $WIFIBT_TTY rtk_h5&
}

start_bt_rtk_usb()
{
	bt_reset

	if ! lsmod | grep -q rtk_btusb; then
		if [ -d /sys/module/btusb ]; then
			echo "Please disable CONFIG_BT_HCIBTUSB in kernel!"
			return -1
		fi

		insmod rtk_btusb.ko
	fi
}

start_wifi()
{
	if wifi_ready; then
		echo "Wi-Fi is already inited..."
		return 0
	fi

	cd "${WIFIBT_MODULE_DIR:-/lib/modules}"

	if [ "$WIFIBT_VENDOR" = Broadcom -a -f dhd_static_buf.ko ]; then
		insmod dhd_static_buf.ko
	fi

	echo "Installing Wi-Fi/BT module: $WIFIBT_MODULE"
	insmod "$WIFIBT_MODULE"

	for i in `seq 60`; do
		if wifi_ready; then
			if grep -wqE "wlan0" /proc/net/dev; then
				echo "Successfully init Wi-Fi for $WIFIBT_CHIP!"
				ifup wlan0 2>/dev/null || \
					ifconfig wlan0 up || true &
			fi
			return 0
		fi
		sleep .1
	done

	echo "Failed to init Wi-Fi for $WIFIBT_CHIP!"
	return 1
}

do_start_bt()
{
	cd "${WIFIBT_MODULE_DIR:-/lib/modules}"

	case "$WIFIBT_VENDOR" in
		Broadcom) start_bt_brcm;;
		Realtek)
			case "$WIFIBT_BUS" in
				usb) start_bt_rtk_usb;;
				*) start_bt_rtk_uart;;
			esac
			;;
		*)
			echo "Unknown Wi-Fi/BT chip, fallback to Broadcom..."
			start_bt_brcm
			;;
	esac
}

start_bt()
{
	if ! wifi_ready; then
		echo "Wi-Fi is not ready..."
		return 1
	fi

	if bt_ready; then
		echo "BT is already inited..."
		return 0
	fi

	if do_start_bt; then
		for i in `seq 60`; do
			if bt_ready; then
				echo "Successfully init BT for $WIFIBT_CHIP!"
				return 0
			fi
			sleep .1
		done
	fi

	echo "Failed to init BT for $WIFIBT_CHIP!"
	return 1
}

start_wifibt()
{
	WIFIBT_CHIP=$(wifibt-util.sh chip || true)
	if [ -z "$WIFIBT_CHIP" ]; then
		echo "Failed to detect Wi-Fi/BT chip!"
		return 1
	fi

	WIFIBT_VENDOR="$(wifibt-util.sh vendor)"
	WIFIBT_BUS="$(wifibt-util.sh bus)"
	WIFIBT_MODULE="$(wifibt-util.sh module)"
	WIFIBT_TTY=$(wifibt-util.sh tty)

	echo -e "\nHandling $1 for Wi-Fi/BT chip:\n$(wifibt-util.sh info)"

	case "$1" in
		start | restart)
			echo "Starting Wi-Fi/BT..."
			start_wifi
			start_bt
			echo "Done"
			;;
		start_wifi)
			echo "Starting Wi-Fi..."
			start_wifi
			echo "Done"
			;;
		start_bt)
			echo "Starting BT..."
			start_bt
			echo "Done"
			;;
	esac
}

case "$1" in
	start | restart | start_wifi | start_bt | "")
		start_wifibt "${1:-start}" &
		;;
	stop)
		echo -n "Stopping Wi-Fi/BT..."
		killall -q -9 brcm_patchram_plus1 rtk_hciattach || true
		ifdown wlan0 down 2>/dev/null || true
		ifconfig wlan0 down 2>/dev/null || true
		echo "Done"
		;;
	*)
		echo "Usage: [start|stop|start_wifi|start_bt|restart]" >&2
		exit 3
		;;
esac

:
