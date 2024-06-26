#!/bin/sh
### BEGIN INIT INFO
# Provides:       wifibt-init
# Required-Start: $local_fs $syslog
# Required-Stop:  $local_fs
# Default-Start:  S
# Default-Stop:   K
# Description:    Init Rockchip Wifi/BT
### END INIT INFO

case "$1" in
	start|stop|restart)
		#The rk_demo has already called 'wifibt-init.sh'
		if [ -n "$(pidof rk_demo)" ]; then
			echo "rk_demo running"
			exit
		fi

		/usr/bin/wifibt-init.sh $1
		;;
	*)
		echo "Usage: [start|stop|restart]" >&2
		exit 3
		;;
esac

:
