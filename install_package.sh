#!/bin/sh
set -e

PKG_MANAGER=""

check_root() {
    if [ "$(id -u)" -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

install_dependencies() {
    if command -v sudo >/dev/null 2>&1 \
        && command -v curl >/dev/null 2>&1 \
        && command -v unzip >/dev/null 2>&1 \
        && command -v bash >/dev/null 2>&1; then
        return 0
    fi
    case $PKG_MANAGER in
        "pacman")
            pacman -Sy
            pacman -S --noconfirm sudo
            sudo pacman -S --noconfirm curl unzip bash
            ;;
        "apt")
            apt update
            apt install -y sudo
            sudo apt install -y curl unzip bash
            ;;
        "dnf")
            dnf install -y sudo
            enable_epel
            sudo dnf install -y curl unzip bash
            ;;
        "yum")
            yum install -y sudo
            enable_epel
            sudo yum install -y curl unzip bash
            ;;
        "zypper")
            zypper install -y sudo
            sudo zypper install -y curl unzip bash
            ;;
        
        "eopkg")
            eopkg update-repo
            eopkg install -y sudo
            sudo eopkg install -y curl unzip bash
            ;;
    esac
}

sync_system_time() {
    case $PKG_MANAGER in
        "pacman")
            sudo pacman -S --noconfirm chrony
            ;;
        "apt")
            sudo apt install -y chrony
            ;;
        "dnf")
            sudo dnf install -y chrony
            ;;
        "yum")
            sudo yum install -y chrony
            ;;
        "zypper")
            sudo zypper install -y chrony
            ;;
        "eopkg")
            sudo eopkg install -y chrony
            ;;
    esac

    if command -v systemctl >/dev/null 2>&1; then
        if sudo systemctl enable --now chronyd >/dev/null 2>&1 || sudo systemctl enable --now chrony >/dev/null 2>&1; then
            return 0
        fi
    elif command -v rc-service >/dev/null 2>&1; then
        if sudo rc-update add chronyd default >/dev/null 2>&1 || sudo rc-update add chrony default >/dev/null 2>&1; then
            sudo rc-service chronyd start >/dev/null 2>&1 || sudo rc-service chrony start >/dev/null 2>&1
            return 0
        fi
    fi

    echo "Warning: Failed to start chrony service"
    return 1
}

detect_package_manager() {
    if command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    elif command -v apt >/dev/null 2>&1; then
        echo "apt"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v zypper >/dev/null 2>&1; then
        echo "zypper"
    elif command -v eopkg >/dev/null 2>&1; then
        echo "eopkg"
    else
        echo "unknown package manager"
        exit
    fi
}

init_package_manager() {
    case $PKG_MANAGER in
        "pacman")
            sudo pacman -Sy
            ;;
        "apt")
            sudo apt update
            sudo apt install -y gdebi synaptic
            ;;
        "dnf")
            sudo dnf makecache --refresh -y
            ;;
        "yum")
            sudo yum makecache -y
            ;;
        "zypper")
            sudo zypper refresh
            ;;
        
        "eopkg")
            sudo eopkg update-repo
            ;;
    esac
}

configure_flatpak_env() {
    shell_config=""
    if [ -n "$BASH_VERSION" ] && [ -f "$HOME/.bashrc" ]; then
        shell_config="$HOME/.bashrc"
    elif [ -n "$ZSH_VERSION" ] && [ -f "$HOME/.zshrc" ]; then
        shell_config="$HOME/.zshrc"
    elif [ -f "$HOME/.profile" ]; then
        shell_config="$HOME/.profile"
    else
        shell_config="$HOME/.profile"
        touch "$shell_config"
    fi

    if check_root; then
        if ! echo "$XDG_DATA_DIRS" | grep -q '/var/lib/flatpak/exports/share'; then
            printf '%s\n' "export XDG_DATA_DIRS=\$XDG_DATA_DIRS:/var/lib/flatpak/exports/share:/root/.local/share/flatpak/exports/share" >> "$shell_config"
            export XDG_DATA_DIRS="$XDG_DATA_DIRS:/var/lib/flatpak/exports/share:/root/.local/share/flatpak/exports/share"
        fi
    else
        if ! echo "$XDG_DATA_DIRS" | grep -q '/var/lib/flatpak/exports/share'; then
            printf '%s\n' "export XDG_DATA_DIRS=\$XDG_DATA_DIRS:/var/lib/flatpak/exports/share:\$HOME/.local/share/flatpak/exports/share" >> "$shell_config"
            export XDG_DATA_DIRS="$XDG_DATA_DIRS:/var/lib/flatpak/exports/share:$HOME/.local/share/flatpak/exports/share"
        fi
    fi
}

install_flatpak() {
    sync_system_time
    
    case $PKG_MANAGER in
        "pacman")
            sudo pacman -S --noconfirm flatpak
            ;;
        "apt")
            sudo apt install -y flatpak
            if grep -q "ubuntu" /etc/os-release; then
            	# sudo apt install -y software-properties-common
            	# sudo add-apt-repository ppa:appimagelauncher-team/stable -y
            	# sudo apt update
            	# sudo apt install -y appimagelauncher
                if dpkg -l | grep -q appimagelauncher; then
                    sudo apt remove -y appimagelauncher
                    sudo add-apt-repository --remove ppa:appimagelauncher-team/stable -y
                fi
            fi
                            
            ;;
        "dnf")
            sudo dnf install -y flatpak
            ;;
        "yum")
            sudo yum install -y flatpak
            ;;
        "zypper")
            sudo zypper install -y flatpak
            ;;
        
        "eopkg")
            sudo eopkg install -y flatpak
            ;;
        *)
            echo "Cannot install Flatpak, unsupported package manager"
            return 1
            ;;
    esac
    
    if ! flatpak remote-list | grep -q "^flathub\b"; then
        flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    fi
    flatpak remote-modify --system flathub --url=https://mirrors.ustc.edu.cn/flathub 2>/dev/null || flatpak remote-modify --user flathub --url=https://mirrors.ustc.edu.cn/flathub

    configure_flatpak_env

    flatpak update --appstream
    flatpak install -y io.github.prateekmedia.appimagepool
    flatpak install -y it.mijorus.gearlever
    if flatpak list | grep -q "com.github.ryonakano.pinit"; then
        flatpak uninstall -y flathub com.github.ryonakano.pinit
    fi
}

main() {
    PKG_MANAGER=$(detect_package_manager)
    install_dependencies
    init_package_manager
    install_flatpak
}

main "$@"
