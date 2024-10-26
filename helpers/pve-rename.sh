#!/usr/bin/env bash

# Ugly code, but it works

CURRENT_HOSTNAME=$(hostname)

function usage() {
    trap - EXIT
    echo "Usage: $(basename $0) -H|--hostname [new hostname]"
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

function pre_reboot() {
    local new_hostname="$1"
    # Update hosts file
    echo "[+] Updating /etc/hosts file"
    sed -i -e "s/$CURRENT_HOSTNAME/$new_hostname/g" /etc/hosts

    # Update hostname file
    echo "[+] Updating /etc/hostname file"
    sed -i -e "s/$CURRENT_HOSTNAME/$new_hostname/g" /etc/hostname

    echo "[+] Modifying rrdcached directories"
    cp /var/lib/rrdcached/db/pve2-node/$CURRENT_HOSTNAME /var/lib/rrdcached/db/pve2-node/$new_hostname
    cp -r /var/lib/rrdcached/db/pve2-storage/$CURRENT_HOSTNAME /var/lib/rrdcached/db/pve2-storage/$new_hostname
    echo "[+] Deleting old rrdcached directories"
    rm /var/lib/rrdcached/db/pve2-node/$CURRENT_HOSTNAME
    rm -r /var/lib/rrdcached/db/pve2-storage/$CURRENT_HOSTNAME
}

function post_reboot() {
    echo "post reboot"
    local nodes_dir="/etc/pve/nodes"
    local old_node_dir=$nodes_dir/$(ls --ignore "$NEW_HOSTNAME" $nodes_dir)
    echo "[*] Moving $old_node_dir/lxc/* to $nodes_dir/$NEW_HOSTNAME/lxc/"
    mv  $old_node_dir/lxc/* "$nodes_dir/$NEW_HOSTNAME/lxc/"
    echo "[*] Moving $old_node_dir/qemu-server/* to $nodes_dir/$NEW_HOSTNAME/qemu-server/"
    mv $old_node_dir/qemu-server/* "$nodes_dir/$NEW_HOSTNAME/qemu-server/"
    echo "[*] Removing old node"
    #rm -r $old_node_dir
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

function is_post_reboot() {
    if [ `ls -1 /etc/pve/nodes/$NEW_HOSTNAME 2>/dev/null | wc -l` -eq 0 ]
    then
        return 1
    fi
    return 0
}

while test $# != 0
do
    case "$1" in
    -H|--hostname)
        NEW_HOSTNAME="$2"; shift ;;
    --) shift; break;;
    *)  usage;;
    esac
    shift
done

if [ -z "$NEW_HOSTNAME" ]
then
    usage
fi


is_first_time
first_time=$?
if [[ $first_time -eq 1 ]]
then
    confirm_or_die "The hostname of this node will change from '$CURRENT_HOSTNAME' to '$NEW_HOSTNAME'"
    pre_reboot $NEW_HOSTNAME
    confirm_or_die "The host must reboot for the changes to take effect. It must be run again after the reboot"
    reboot now
fi

is_post_reboot
post_reboot=$?
if [[ $post_reboot -eq 0 ]]
then
    post_reboot 
fi

echo "[+] All done"
