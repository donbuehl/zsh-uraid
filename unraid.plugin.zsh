# unraid.plugin.zsh

array_control() {
    local action=$1

    echo "Attempting to $action the array..."
    local csrf_token=$(grep -oP 'csrf_token="\K[^"]+' /var/local/emhttp/var.ini)
    
    if [ -z "$csrf_token" ]; then
        echo "Failed to retrieve CSRF token. Cannot $action the array."
        return 1
    fi

    if curl -s --unix-socket /var/run/emhttpd.socket "http://localhost/update.htm?cmd${action}=apply&csrf_token=$csrf_token" >/dev/null; then
        local target_status=$([ "$action" = "Start" ] && echo "STARTED" || echo "STOPPED")
        local current_status=$(/usr/local/sbin/mdcmd status | grep mdState | cut -d= -f2)
        
        if [[ "$current_status" == "$target_status" ]]; then
            echo "Array ${action}ed successfully."
            return 0
        else
            echo "Array $action command sent. Current status: $current_status"
            echo "Please check the unRAID web interface for further status updates."
            return 0
        fi
    else
        echo "Failed to send $action command to the array. Check system logs for more information."
        return 1
    fi
}

# Aliases for easier access
alias array-start='array_control Start'
alias array-stop='array_control Stop'

# User Scripts (assuming CA User Scripts is installed)
user_scripts_dir="/boot/config/plugins/user.scripts/scripts"
alias list-scripts='ls -l $user_scripts_dir'
alias run-script='bash $user_scripts_dir/$1'

# Docker management shortcuts
alias docker-list='docker ps'
alias docker-start='docker start'
alias docker-stop='docker stop'

# VM management shortcuts
alias vm-list='virsh list --all'
alias vm-start='virsh start'
alias vm-stop='virsh shutdown'

# Quick access to important unRAID directories
alias cdboot='cd /boot'
alias cdextras='cd /boot/extras'
alias cdappdata='cd /mnt/user/appdata'
alias cddomains='cd /mnt/user/domains'
alias cdisos='cd /mnt/user/isos'
alias cdshare='cd /mnt/user/share'
alias cddisks='cd /mnt/disks'

# Functions to quickly change to plugin directories
cdplugin() {
    if [ -z "$1" ]; then
        echo "Please provide a plugin name."
        return 1
    fi
    
    local config_dir="/boot/config/plugins/$1"
    local emhttp_dir="/usr/local/emhttp/plugins/$1"
    
    if [ "$2" = "config" ] && [ -d "$config_dir" ]; then
        cd "$config_dir"
    elif [ "$2" = "emhttp" ] && [ -d "$emhttp_dir" ]; then
        cd "$emhttp_dir"
    elif [ -d "$config_dir" ]; then
        cd "$config_dir"
    elif [ -d "$emhttp_dir" ]; then
        cd "$emhttp_dir"
    else
        echo "Plugin directory not found: $1"
        return 1
    fi
}

cdpluginconf() {
    cdplugin "$1" config
}

cdplugincode() {
    cdplugin "$1" emhttp
}

# Function to show unRAID system info
unraid_info() {
    echo "unRAID Version: $(cat /etc/unraid-version)"
    echo "Array Status:"
    /usr/local/sbin/mdcmd status | grep -E 'mdState|sbState' | sed 's/^/  /'
    echo "Disk Information:"
    /usr/local/sbin/mdcmd status | awk '
        BEGIN {FS="="}
        /^mdNumDisks/ {total=$2}
        /^mdNumDisabled/ {disabled=$2}
        /^diskNumber/ {
            disk_num = $2
            getline
            if ($2 != "") {
                diskName = $2
                getline
                diskSize = $2
                getline
                diskState = $2
                getline
                diskId = $2
                getline
                getline
                rdevStatus = $2
                if (rdevStatus == "DISK_OK") {
                    printf "  Disk %s: %s, Size: %s, State: %s, ID: %s\n", disk_num, diskName, diskSize, diskState, diskId
                    active++
                }
            }
        }
        END {
            printf "Total Disks: %d, Active: %d, Disabled: %d\n", total, active, disabled
        }
    '
    echo "Flash Drive:"
    df -h /boot | awk 'NR==2 {printf "  Device: %s, Size: %s, Used: %s, Available: %s, Use%%: %s\n", $1, $2, $3, $4, $5}'
    echo "Running Docker Containers:"
    docker ps --format "{{.Names}}" | sed 's/^/  /'
    echo "Total Running Docker Containers: $(docker ps -q | wc -l)"
    echo "Running VMs:"
    virsh list --state-running --name | sed '/^$/d' | sed 's/^/  /'
    echo "Total Running VMs: $(virsh list --state-running --name | sed '/^$/d' | wc -l)"
}

# Add unRAID-specific completion
compdef _gnu_generic array-start array-stop flash-backup cdplugincode cdpluginconf

function unraid_omz_update() {
    echo "Updating unraid plugin..."
    # Perform git pull in the unraid plugin directory
    cd "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/unraid" || return
    result=$(git pull)
    echo "unraid: $result"
    
    # Check if the update was successful and not "Already up to date."
    if [[ $result != *"Already up to date."* ]]; then
        echo "New updates found. Reloading zsh configuration..."
        source ~/.zshrc
    fi
}

# Execute update on every start
# unraid_omz_update