# Aplica el nombre configurado en configuracion.sh.
# hostnamectl actualiza el nombre activo y el valor persistente que systemd usa en futuros arranques.
hostnamectl set-hostname "$HOSTNAME_CUTSA"
