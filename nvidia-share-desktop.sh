#!/usr/bin/env bash
set -o pipefail 
source ~/.bashrc_extended

if [[ $(login_session_type_seat0) == x11 ]]; then 
    # x11: enable x11vnc 
    if ss -ltnp | grep -E "LISTEN.+:5900\b" >/dev/null; then
        echo_in_yellow "X11 desktop has already shared via x11vnc"
    else 
        [[ -z $(which screen) ]] && sudo apt install -y screen 
        [[ -z $(which x11vnc) ]] && sudo apt install -y x11vnc 
        screen -dmS 'x11vnc-server' bash -c 'x11vnc -display :0 -auth guess -forever -loop -shared -noxdamage -repeat >/tmp/x11vnc.log 2>&1' 
        sleep 3
        screen -ls | grep -F x11vnc-server 
        ss -ltnp | grep -E "LISTEN.+:5900\b"
    fi 
else
    # wayland: enable gnome remote desktop
    if sudo ss -ltnp | grep -qE ':3389\b'; then
        echo_in_yellow "Wayland desktop has already shared via GNOME RDP"
    else 
        exit_on_error=
        if [[ $(cat /sys/module/nvidia_drm/parameters/modeset) != Y ]]; then 
            echo_in_red "Error: can't find required kernel param: nvidia-drm.modeset=1 "
            exit_on_error=1
        fi 
        if grep -qE '^[[:space:]]*WaylandEnable[[:space:]]*=[[:space:]]*false[[:space:]]*$' /etc/gdm3/custom.conf; then
            echo_in_red "Edit /etc/gdm3/custom.conf to enable wayland first, then restart gdm3"
            exit_on_error=1
        fi 
        if grep -qE '^[[:space:]]*AutomaticLoginEnable[[:space:]]*=[[:space:]]*true[[:space:]]*$' /etc/gdm3/custom.conf; then
            echo_in_red "Edit /etc/gdm3/custom.conf to disable automatic login first, then restart gdm3"
            exit_on_error=1
        fi 
        if [[ $exit_on_error == 1 ]]; then 
            exit 1
        fi 

        find_or_install gnome-remote-desktop openssl remmina remmina-plugin-rdp freerdp2-x11
        cert_dir=/var/lib/gnome-remote-desktop/.local/share/gnome-remote-desktop
        cert_key=$cert_dir/rdp-tls.key
        cert_crt=$cert_dir/rdp-tls.crt
        sudo install -d -m 0700 $cert_dir
        sudo chown -R gnome-remote-desktop:gnome-remote-desktop /var/lib/gnome-remote-desktop/.local
        if [[ ! -s $cert_key || ! -s $cert_crt ]]; then 
            sudo openssl req -x509 -newkey rsa:2048 -nodes -keyout $cert_key -out $cert_crt -days 3650 -subj "/CN=$(hostname -f)"
            sudo chmod 0600 $cert_key
            sudo chmod 0644 $cert_crt
            sudo chown gnome-remote-desktop:gnome-remote-desktop $cert_key $cert_crt
        fi 
        sudo openssl x509 -in $cert_crt -noout >/dev/null || echo_in_red "Bad certificate"
        sudo openssl pkey -in $cert_key -noout >/dev/null || echo_in_red "Bad certificate key"
        sudo grdctl --system rdp set-tls-key $cert_key
        sudo grdctl --system rdp set-tls-cert $cert_crt
        sudo grdctl --system rdp set-credentials $USER zhujie
        sudo grdctl --system rdp enable
        sudo ufw disable || sudo ufw allow 3389/tcp 
        sudo systemctl daemon-reload
        sudo systemctl restart gnome-remote-desktop.service
        echo_in_cyan "Wait for 3 seconds" && sleep 3
        sudo grdctl --system status
        sudo ss -ltnp | grep -E ':3389\b' || {
            echo_in_red "RDP server is not listening on TCP/3389"
            sudo systemctl status gnome-remote-desktop.service --no-pager
            sudo journalctl -u gnome-remote-desktop.service -b --no-pager | tail -n 120
        }
    fi 
fi 