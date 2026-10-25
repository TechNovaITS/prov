#!/usr/bin/env bash
# Asistente de configuración para AlmaLinux 9.8. Ejecutar como root tras revisar estos ajustes.
set -euo pipefail

# Completa estas variables antes de ejecutar. Limita la lectura del archivo a root (chmod 600).
# Se guardan en texto plano y se aplican también a las cuentas existentes.
PASSWORD_SUDO="sudocutsa"
PASSWORD_ADMIN="admincutsa"
PASSWORD_LOGGER="loggercutsa"

if [[ $EUID -ne 0 ]]; then
	echo "Ejecutá como root: sudo bash $0" >&2
	exit 1
fi

if [[ -z "$PASSWORD_SUDO" || -z "$PASSWORD_ADMIN" || -z "$PASSWORD_LOGGER" ]]; then
	echo "Definí las contraseñas de todas las cuentas al comienzo de $0 antes de ejecutarlo." >&2
	exit 1
fi

# Usa el umbral local de cuentas normales; conserva root, nobody y los usuarios que requiere CUTSA.
UID_MIN="$(awk '$1 == "UID_MIN" { print $2; exit }' /etc/login.defs)"
if [[ ! "$UID_MIN" =~ ^[0-9]+$ ]]; then
	echo "No se pudo leer UID_MIN de /etc/login.defs." >&2
	exit 1
fi
mapfile -t REMOVE_USERS < <(awk -F: -v uid_min="$UID_MIN" '
	$3 >= uid_min && $1 != "root" && $1 != "nobody" &&
	$1 != "sudo" && $1 != "admin" && $1 != "logger" { print $1 }
' /etc/passwd)
VALID_REMOVE_USERS=()
# Revalida cada nombre y descarta las cuentas que ya no existan antes de crear la tarea diferida.
for remove_user in "${REMOVE_USERS[@]}"; do
	if [[ ! "$remove_user" =~ ^[a-zA-Z_][a-zA-Z0-9_.-]*$ ]]; then
		echo "El nombre de cuenta indicado para eliminar no es válido: $remove_user" >&2
		exit 1
	fi
	case "$remove_user" in
		root|sudo|admin|logger)
			echo "No se permite eliminar root ni las cuentas de servicio administradas: $remove_user" >&2
			exit 1
			;;
	esac
	if id "$remove_user" >/dev/null 2>&1; then
		VALID_REMOVE_USERS+=("$remove_user")
	else
		echo "La cuenta '$remove_user' ya no existe; se omite."
	fi
done
REMOVE_USERS=("${VALID_REMOVE_USERS[@]}")

PROJECT=/srv/Docker-Cutsa
# Verifica Compose y Docker antes de modificar hostname, cuentas, firewall o servicios.
[[ -f "$PROJECT/compose.yaml" || -f "$PROJECT/docker-compose.yml" ]] || {
	echo "Colocá compose.yaml o docker-compose.yml en $PROJECT antes de ejecutar este script." >&2
	exit 1
}
DOCKER_BIN="$(command -v docker || true)"
if [[ -z "$DOCKER_BIN" ]] || ! getent group docker >/dev/null || ! systemctl cat docker.service >/dev/null 2>&1; then
	echo "Primero instalá Docker Engine, el grupo docker y docker.service." >&2
	exit 1
fi

# Establece el nombre de host solicitado.
hostnamectl set-hostname TechnovaCutsa

# Crea cuentas con funciones distintas. La cuenta sudo recibe privilegios de administración.
for user in sudo admin logger; do
	if ! id "$user" >/dev/null 2>&1; then
		useradd --create-home "$user"
	fi
	case "$user" in
		sudo) user_password=$PASSWORD_SUDO ;;
		admin) user_password=$PASSWORD_ADMIN ;;
		logger) user_password=$PASSWORD_LOGGER ;;
	esac
	printf '%s:%s\n' "$user" "$user_password" | chpasswd
done
usermod -aG wheel sudo

# Crea un directorio compartido para el proyecto Docker y las cuentas anteriores.
# El bit setgid hace que los archivos nuevos hereden el grupo dockercutsa.
groupadd --force dockercutsa
for user in sudo admin logger; do
	usermod -aG dockercutsa "$user"
done
# El grupo docker puede controlar el daemon y equivale prácticamente a tener acceso root.
usermod -aG docker admin
install -d -o root -g dockercutsa -m 2775 /srv/Docker-Cutsa

systemctl enable --now docker

# Activa firewalld y abre solo los puertos web estándar y SSH. Grafana (3000) y
# Alertmanager (9093) quedan disponibles solo localmente; expónlos mediante una VPN o proxy confiable.
# Las reglas se agregan de forma permanente y luego se recarga la configuración activa.
systemctl enable --now sshd
systemctl enable --now firewalld
firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload

# Deshabilita servicios opcionales solo cuando no hay configuración que los requiera.
if [[ ! -s /etc/sssd/sssd.conf ]] &&
	! find /etc/sssd/conf.d -maxdepth 1 -type f -name '*.conf' -print -quit 2>/dev/null | grep -q . &&
	! grep -Eq '^[[:space:]]*(passwd|group|shadow|services|netgroup|automount):.*[[:space:]]sss([[:space:]]|$)' /etc/nsswitch.conf; then
	systemctl disable --now sssd.service >/dev/null 2>&1 || true
fi

if ! grep -Eq '^[[:space:]]*NISDOMAIN=[^[:space:]#]+' /etc/sysconfig/network 2>/dev/null &&
	! grep -Eq '^[[:space:]]*(passwd|group|shadow|hosts|netgroup|automount):.*[[:space:]](nis|yp)([[:space:]]|$)' /etc/nsswitch.conf &&
	! grep -Eq '^[[:space:]]*[^#[:space:]]' /etc/yp.conf 2>/dev/null &&
	! systemctl is-active --quiet ypbind.service; then
	for nis_service in nis-domainname.service ypbind.service yppasswdd.service ypserv.service ypxfrd.service; do
		systemctl disable --now "$nis_service" >/dev/null 2>&1 || true
	done
fi

# Instala un temporizador de systemd para iniciar el proyecto Compose al arrancar como admin.
# admin necesita pertenecer al grupo docker y poder leer el directorio del proyecto.
install -d -m 0755 /etc/systemd/system
cat > /etc/systemd/system/dockercutsa.service <<EOF
[Unit]
Description=Iniciar el proyecto Compose de Docker-Cutsa
Wants=docker.service
After=docker.service network-online.target

[Service]
Type=oneshot
User=admin
WorkingDirectory=$PROJECT
ExecStart=$DOCKER_BIN compose up -d
EOF
cat > /etc/systemd/system/dockercutsa.timer <<'EOF'
[Unit]
Description=Iniciar Docker-Cutsa al arrancar

[Timer]
OnBootSec=1min
Persistent=true

[Install]
WantedBy=timers.target
EOF

if (( ${#REMOVE_USERS[@]} > 0 )); then
	# La tarea corre antes de habilitar sesiones y elimina cada cuenta junto con su home.
	cat > /etc/systemd/system/dockercutsa-remove-invoker.service <<EOF
[Unit]
Description=Eliminar las cuentas anteriores y sus directorios personales
DefaultDependencies=no
After=local-fs.target
Before=systemd-user-sessions.service multi-user.target

[Service]
Type=oneshot
EOF
	for remove_user in "${REMOVE_USERS[@]}"; do
		printf 'ExecStart=/usr/sbin/userdel --remove %s\n' "$remove_user" >> /etc/systemd/system/dockercutsa-remove-invoker.service
	done
	cat >> /etc/systemd/system/dockercutsa-remove-invoker.service <<'EOF'
ExecStartPost=/usr/bin/systemctl disable dockercutsa-remove-invoker.service

[Install]
WantedBy=multi-user.target
EOF
	else
	systemctl disable dockercutsa-remove-invoker.service >/dev/null 2>&1 || true
	rm -f /etc/systemd/system/dockercutsa-remove-invoker.service
fi

systemctl daemon-reload
systemctl enable --now dockercutsa.timer
if (( ${#REMOVE_USERS[@]} > 0 )); then
	# El borrado queda programado para el siguiente arranque, no ocurre durante esta sesión.
	systemctl enable dockercutsa-remove-invoker.service
	printf 'Estas cuentas locales y sus directorios personales se eliminarán en el próximo arranque: %s\n' "${REMOVE_USERS[*]}"
else
	echo "No hay cuentas locales normales para eliminar; root y las cuentas de servicio se conservarán."
fi
