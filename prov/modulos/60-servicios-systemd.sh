# Prepara el directorio estándar donde systemd busca unidades creadas por el administrador.
install -d -m 0755 /etc/systemd/system

# Convierte la lista configurable en palabras separadas para ExecStart.
# Los nombres ya fueron validados en el módulo de validación previa.
COMPOSE_SERVICE_ARGS="${DOCKER_COMPOSE_SERVICES[*]}"

# Define una unidad oneshot: ejecuta Compose para dejar iniciado el proyecto y luego termina.
cat > "/etc/systemd/system/${DOCKER_SYSTEMD_UNIT}.service" <<EOF
[Unit]
# Nombre descriptivo visible en systemd.
Description=Iniciar el proyecto Compose ${DOCKER_PROJECT_DIR_NAME}
# Espera que Docker esté disponible y que la red esté conectada.
Wants=docker.service
After=docker.service network-online.target

[Service]
# Tipo oneshot porque solo ejecuta un conjunto finito de acciones.
Type=oneshot
# admin es el usuario que tiene acceso al grupo Docker.
User=admin
# Compose se ejecuta desde el directorio del proyecto.
WorkingDirectory=$PROJECT
# $DOCKER_BIN se expande al generar el archivo, no se evalúa dentro de este módulo.
ExecStart=$DOCKER_BIN compose up -d $COMPOSE_SERVICE_ARGS
EOF

# Programa el inicio del proyecto un minuto después de cada arranque del sistema.
cat > "/etc/systemd/system/${DOCKER_SYSTEMD_UNIT}.timer" <<EOF
[Unit]
Description=Iniciar ${DOCKER_PROJECT_DIR_NAME} al arrancar

[Timer]
# Espera un minuto después del arranque antes de intentar levantar los contenedores.
OnBootSec=1min

[Install]
# timers.target carga este temporizador como parte del arranque normal.
WantedBy=timers.target
EOF

# Retira una unidad anterior antes de crear la lista actual de cuentas por eliminar.
OLD_REMOVE_USERS_UNIT="/etc/systemd/system/${REMOVE_USERS_SYSTEMD_UNIT}.service"
if [[ -e "$OLD_REMOVE_USERS_UNIT" || -L "$OLD_REMOVE_USERS_UNIT" ]]; then
	systemctl disable --now "${REMOVE_USERS_SYSTEMD_UNIT}.service"
	rm -f "/etc/systemd/system/${REMOVE_USERS_SYSTEMD_UNIT}.service"
fi

# Programa la eliminación de las cuentas locales normales que pasaron la validación.
if (( ${#REMOVE_USERS[@]} > 0 )); then
	cat > "$OLD_REMOVE_USERS_UNIT" <<EOF
[Unit]
Description=Eliminar cuentas locales normales, excepto root, sudo, admin y logger
DefaultDependencies=no
After=local-fs.target
Before=systemd-user-sessions.service multi-user.target

[Service]
Type=oneshot
EOF
	for remove_user in "${REMOVE_USERS[@]}"; do
		printf 'ExecStart=/usr/sbin/userdel --remove %s\n' "$remove_user" >> "$OLD_REMOVE_USERS_UNIT"
	done
	cat >> "$OLD_REMOVE_USERS_UNIT" <<EOF
ExecStartPost=/usr/bin/systemctl disable ${REMOVE_USERS_SYSTEMD_UNIT}.service

[Install]
WantedBy=multi-user.target
EOF
fi

# Hace que systemd vuelva a leer las unidades recién generadas.
systemctl daemon-reload
# Activa ahora el temporizador y lo deja habilitado para próximos arranques.
systemctl enable --now "${DOCKER_SYSTEMD_UNIT}.timer"

# Informa si se programó la limpieza diferida o si no hay cuentas locales que quitar.
if (( ${#REMOVE_USERS[@]} > 0 )); then
	systemctl enable "${REMOVE_USERS_SYSTEMD_UNIT}.service"
	printf 'Estas cuentas locales se eliminarán en el próximo arranque: %s\n' "${REMOVE_USERS[*]}"
else
	echo "No hay cuentas locales normales para eliminar; root, sudo, admin y logger se conservarán."
fi
echo "admin ya pertenece al grupo docker; cerrá y volvé a iniciar sesión para usar Docker."
