#!/usr/bin/env bash

# Ugly code. Made in a few hours. Tested. It works.

CURRENT_HOSTNAME=$(hostname)

function usage() {
    trap - EXIT
    cat << EOF
Usage: $(basename $0) ARGS

ARGS:
    --new-hostname [new hostname]
    --old-hostname [old hostname]
EOF
    exit 1
}

function confirm_or_die() {
    echo "[!] $1"
    read -p "Continue? [yes/no] "
    if [ "$REPLY" != "yes" ]; then
        echo "[-] Exiting"
        exit 1
    fi
}

while test $# != 0
do
    case "$1" in
    --new-hostname)
        NEW_HOSTNAME="$2"; shift ;;
    --old-hostname)
        OLD_HOSTNAME="$2"; shift ;;
    --) shift; break;;
    *)  usage;;
    esac
    shift
done

if [ -z "$NEW_HOSTNAME" ]
then
    usage
fi

function pre_reboot() {
	if [ "$OLD_HOSTNAME" != "$CURRENT_HOSTNAME" ]; then
	  echo "[-] Old hostname doesn't match with $CURRENT_HOSTNAME"
      exit 1
	fi

    confirm_or_die "The hostname of this node will change from '$CURRENT_HOSTNAME' to '$NEW_HOSTNAME'"

    # Update hosts file
    echo "[+] Updating /etc/hosts file"
    sed --in-place --expression "s/$CURRENT_HOSTNAME/$NEW_HOSTNAME/g" /etc/hosts

    # Update hostname file
    echo "[+] Updating /etc/hostname file"
    sed --in-place --expression "s/$CURRENT_HOSTNAME/$NEW_HOSTNAME/g" /etc/hostname

    echo "[+] Modifying rrdcached directories"
    cp "/var/lib/rrdcached/db/pve2-node/$CURRENT_HOSTNAME" "/var/lib/rrdcached/db/pve2-node/$NEW_HOSTNAME"
    cp --recursive "/var/lib/rrdcached/db/pve2-storage/$CURRENT_HOSTNAME" "/var/lib/rrdcached/db/pve2-storage/$NEW_HOSTNAME"
}

function post_reboot() {
    echo "[*] Running post reboot..."

    local nodes_dir="/etc/pve/nodes"
    local old_node_dir=$nodes_dir/$(ls --ignore "$NEW_HOSTNAME" $nodes_dir)
    echo "[*] Moving $old_node_dir/lxc/* to $nodes_dir/$NEW_HOSTNAME/lxc/"
    cp --no-clobber --recursive $old_node_dir/lxc/* "$nodes_dir/$NEW_HOSTNAME/lxc/"
    echo "[*] Moving $old_node_dir/qemu-server/* to $nodes_dir/$NEW_HOSTNAME/qemu-server/"
    cp --no-clobber --recursive $old_node_dir/qemu-server/* "$nodes_dir/$NEW_HOSTNAME/qemu-server/"
    #echo "[*] Removing old node"
    #rm -r $old_node_dir
}

function cleanup() {
    echo "[*] Cleaning up..."
    return
    rm --verbose "/var/lib/rrdcached/db/pve2-node/$OLD_HOSTNAME"
    rm --verbose --recursive "/var/lib/rrdcached/db/pve2-storage/$OLD_HOSTNAME"
}

function is_first_time() {
    if ! grep -Fq "$NEW_HOSTNAME" /etc/hosts || ! grep -Fq "$NEW_HOSTNAME" /etc/hostname
    then
        return 1
    fi

    if [ `ls -1 /var/lib/rrdcached/db/pve2-*/$NEW_HOSTNAME 2>/dev/null | wc -l` -eq 0 ]
    then
        return 1
    fi
    return 0
}

is_first_time
first_time=$?
if [[ $first_time -eq 1 ]]
then
    pre_reboot
    confirm_or_die "The host must reboot for the changes to take effect. It must be run again after the reboot"
    reboot now
fi

post_reboot
cleanup

echo "[+] All done"
