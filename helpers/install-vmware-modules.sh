#!/usr/bin/env bash

VMWARE_VERSION=""
TMP_GIT_DIR=$(mktemp --directory /tmp/vmware-mods.XXXXXX)

trap cleanup SIGHUP SIGINT SIGTERM EXIT
function cleanup() {
    echo "[*] Removing git directory..."
    rm --recursive --force $TMP_GIT_DIR

    echo "[*] Cleanup finished"
    exit 0
}

function usage() {
    trap - EXIT
    echo "Usage: $(basename $0) -v|--version [vmware version]"
    exit 1
}

while test $# != 0
do
    case "$1" in
    -v|--version)
        VMWARE_VERSION="$2"; shift ;;
    --) shift; break;;
    *)  usage;;
    esac
    shift
done

if [ -z "$VMWARE_VERSION" ]
then
    usage
fi

function run_mod_config() {
    local modconfig_bin=$(compgen -c | grep -m1 vmware-mod)

    sudo $modconfig_bin --console --install-all
    exit_status=$?
    if [ $exit_status -eq 0 ];
    then
        echo "[+] $modconfig_bin run successfuly"
        exit 0
    fi
    echo "[-] Error running '$modconfig_bin'"
}

function run_modprobe() {
    echo "[*] Running modprobe"
    sudo modprobe vmmon vmnet
}

function clone_git_dir() {
    local git_url="https://github.com/mkubecek/vmware-host-modules.git"
    local git_branch="workstation-$VMWARE_VERSION"

    echo "[*] Cloning $git_branch branch to $TMP_GIT_DIR"
    git clone --branch $git_branch --single-branch $git_url $TMP_GIT_DIR

    exit_status=$?
    if [ $exit_status -eq 1 ];
    then
        echo "[-] Error cloning git repository"
        exit 1
    fi
    echo "[+] Cloned git repository"
}

function make_modules() {
    cd $TMP_GIT_DIR
    echo "[*] Patching source files"
    sed -i -e 's/read_lock(&dev_base_lock)/rcu_read_lock()/g' \
        -e 's/read_unlock(&dev_base_lock)/rcu_read_unlock()/g' \
        ./vmnet-only/vmnetInt.h
    echo "[+] Patched source files"
    echo "[*] Running 'make'"
    make
    echo "[*] Running 'make install'"
    sudo make install
}

run_mod_config
clone_git_dir
make_modules
run_modprobe
