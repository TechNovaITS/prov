# Instala el guion que genera las copias de seguridad de archivos, volúmenes y bases de datos.
install -d -m 0755 /usr/local/libexec
install -o root -g root -m 0750 \
	"$SCRIPT_DIR/guiones/crear-respaldo.sh" \
	/usr/local/libexec/prov-respaldo-docker.sh

# Protege el destino porque las copias contienen configuración y datos de acceso (incluido el .env).
install -d -o root -g root -m 0700 "$PROJECT/$BACKUP_DIR_NAME"

# Rutas donde el servicio puede escribir; el guion inicial "-" hace que systemd ignore la copia externa si no existe.
BACKUP_RW_PATHS="$PROJECT/$BACKUP_DIR_NAME"
if [[ -n "$BACKUP_COPY_DIR" ]]; then
	BACKUP_RW_PATHS="$BACKUP_RW_PATHS -$BACKUP_COPY_DIR"
fi

# Entrega al servicio los valores configurados sin depender del entorno de una sesión interactiva.
# El servicio corre con el mínimo de privilegios que le alcanza: sin escalada, /tmp privado y sistema de archivos de solo lectura.
cat > "/etc/systemd/system/${BACKUP_SYSTEMD_UNIT}.service" <<UNIT
[Unit]
Description=Respaldar ${DOCKER_PROJECT_DIR_NAME} (archivos, volumenes y bases MySQL)
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
User=root
UMask=0077
Nice=10
IOSchedulingClass=idle
TimeoutStartSec=2h
NoNewPrivileges=yes
PrivateTmp=yes
ProtectHome=read-only
ProtectSystem=strict
ReadWritePaths=$BACKUP_RW_PATHS
Environment=PROJECT_DIR=$PROJECT
Environment=BACKUP_DIR=$PROJECT/$BACKUP_DIR_NAME
Environment=BACKUP_DIR_NAME=$BACKUP_DIR_NAME
Environment=BACKUP_KEEP_DAILY=$BACKUP_KEEP_DAILY
Environment=BACKUP_KEEP_WEEKLY=$BACKUP_KEEP_WEEKLY
Environment=BACKUP_KEEP_MONTHLY=$BACKUP_KEEP_MONTHLY
Environment="BACKUP_MYSQL_SERVICES=${BACKUP_MYSQL_SERVICES[*]}"
Environment="BACKUP_VOLUMES=${BACKUP_VOLUMES[*]:-}"
Environment="BACKUP_COPY_DIR=$BACKUP_COPY_DIR"
ExecStart=/usr/local/libexec/prov-respaldo-docker.sh
UNIT

# Con calendario: corre a la hora fijada y, si el equipo estaba apagado, recupera la ejecución perdida al encender (Persistent).
# Sin calendario: corre tras el intervalo configurado desde el arranque y repite cada vez que vence ese plazo.
if [[ -n "$BACKUP_ONCALENDAR" ]]; then
	BACKUP_TIMER_DESCRIPTION="Respaldar ${DOCKER_PROJECT_DIR_NAME} (${BACKUP_ONCALENDAR})"
	BACKUP_TIMER_DIRECTIVES="OnCalendar=$BACKUP_ONCALENDAR
RandomizedDelaySec=5min
Persistent=true
AccuracySec=1min"
else
	BACKUP_TIMER_DESCRIPTION="Respaldar ${DOCKER_PROJECT_DIR_NAME} cada $BACKUP_INTERVAL"
	BACKUP_TIMER_DIRECTIVES="OnBootSec=$BACKUP_INTERVAL
OnUnitActiveSec=$BACKUP_INTERVAL
AccuracySec=1s"
fi
cat > "/etc/systemd/system/${BACKUP_SYSTEMD_UNIT}.timer" <<UNIT
[Unit]
Description=$BACKUP_TIMER_DESCRIPTION

[Timer]
$BACKUP_TIMER_DIRECTIVES
Unit=${BACKUP_SYSTEMD_UNIT}.service

[Install]
WantedBy=timers.target
UNIT

# Recarga systemd, habilita el temporizador y lo reinicia para aplicar cambios de configuración.
systemctl daemon-reload
systemctl enable "${BACKUP_SYSTEMD_UNIT}.timer"
systemctl restart "${BACKUP_SYSTEMD_UNIT}.timer"
