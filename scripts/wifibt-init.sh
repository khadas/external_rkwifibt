#!/bin/sh -e

wifi_ready()
{
	grep -wqE "wlan0|p2p0" /proc/net/dev
}

bt_ready()
{
	hciconfig | grep -wqE "hci0"
}

start_bt_brcm()
{
	killall -q -9 brcm_patchram_plus1 || true

	echo 0 > /sys/class/rfkill/rfkill0/state
	echo 0 > /proc/bluetooth/sleep/btwrite
	sleep .5
	echo 1 > /sys/class/rfkill/rfkill0/state
	echo 1 > /proc/bluetooth/sleep/btwrite
	sleep .5

	which brcm_patchram_plus1 >/dev/null
	brcm_patchram_plus1 --enable_hci --no2bytes \
		--use_baudrate_for_download --tosleep 200000 \
		--baudrate 1500000 \
		--patchram ${WIFIBT_FIRMWARE_DIR:-/lib/firmware}/ $WIFIBT_TTY&
}

start_bt_rtk_uart()
{
	killall -q -9 rtk_hciattach || true

	echo 0 > /sys/class/rfkill/rfkill0/state
	echo 0 > /proc/bluetooth/sleep/btwrite
	sleep .5
	echo 1 > /sys/class/rfkill/rfkill0/state
	echo 1 > /proc/bluetooth/sleep/btwrite
	sleep .5

	if ! lsmod | grep -q hci_uart; then
		insmod hci_uart.ko
		sleep .5
	fi

	which rtk_hciattach >/dev/null
	rtk_hciattach -n -s 115200 $WIFIBT_TTY rtk_h5&
}

start_bt_rtk_usb()
{
	lsmod | grep -q rtk_btusb || insmod rtk_btusb.ko
}

start_wifi()
{
	! wifi_ready || return 0

	cd "${WIFIBT_MODULE_DIR:-/lib/modules}"

	if [ "$WIFIBT_VENDOR" = Broadcom -a -f dhd_static_buf.ko ]; then
		insmod dhd_static_buf.ko
	fi

	echo "Installing WiFi/BT module: $WIFIBT_MODULE"
	insmod "$WIFIBT_MODULE"

	for i in `seq 60`; do
		if wifi_ready; then
			if grep -wqE "wlan0" /proc/net/dev; then
				echo "Successfully init WiFi for $WIFIBT_CHIP!"
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
	wifi_ready || return 1
	! bt_ready || return 0

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

	echo "Handling $1 for Wi-Fi/BT chip: $(wifibt-util.sh info)"

	case "$1" in
		start | restart)
			echo "Starting Wifi/BT..."
			start_wifi
			start_bt
			echo "Done"
			;;
		start_wifi)
			echo "Starting Wifi..."
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
		echo "Stopping Wi-Fi/BT..."
		killall -q -9 brcm_patchram_plus1 rtk_hciattach || true
		ifdown wlan0 down 2>/dev/null || true
		ifconfig wlan0 down 2>/dev/null || true
		;;
	*)
		echo "Usage: [start|stop|start_wifi|start_bt|restart]" >&2
		exit 3
		;;
esac

:
