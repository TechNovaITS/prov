# Instala el guion que genera las copias de seguridad de archivos y bases de datos.
install -d -m 0755 /usr/local/libexec
install -o root -g root -m 0750 \
	"$SCRIPT_DIR/guiones/crear-respaldo.sh" \
	/usr/local/libexec/prov-respaldo-docker.sh

# Protege el destino porque las copias contienen configuración y datos de acceso.
install -d -o root -g root -m 0700 "$PROJECT/$BACKUP_DIR_NAME"

# Entrega al servicio los valores configurados sin depender del entorno de una sesión interactiva.
cat > "/etc/systemd/system/${BACKUP_SYSTEMD_UNIT}.service" <<EOF
[Unit]
Description=Respaldar ${DOCKER_PROJECT_DIR_NAME} y sus bases MySQL
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
User=root
UMask=0077
Environment=PROJECT_DIR=$PROJECT
Environment=BACKUP_DIR=$PROJECT/$BACKUP_DIR_NAME
Environment=BACKUP_DIR_NAME=$BACKUP_DIR_NAME
Environment=BACKUP_RETENTION_COUNT=$BACKUP_RETENTION_COUNT
Environment="BACKUP_MYSQL_SERVICES=${BACKUP_MYSQL_SERVICES[*]}"
ExecStart=/usr/local/libexec/prov-respaldo-docker.sh
EOF

# Ejecuta el primer respaldo tras el intervalo configurado y repite cada vez que vence ese plazo.
cat > "/etc/systemd/system/${BACKUP_SYSTEMD_UNIT}.timer" <<EOF
[Unit]
Description=Respaldar ${DOCKER_PROJECT_DIR_NAME} cada $BACKUP_INTERVAL

[Timer]
OnBootSec=$BACKUP_INTERVAL
OnUnitActiveSec=$BACKUP_INTERVAL
AccuracySec=1s
Unit=${BACKUP_SYSTEMD_UNIT}.service

[Install]
WantedBy=timers.target
EOF

# Recarga systemd, habilita el temporizador y lo reinicia para aplicar cambios de configuración.
systemctl daemon-reload
systemctl enable "${BACKUP_SYSTEMD_UNIT}.timer"
systemctl restart "${BACKUP_SYSTEMD_UNIT}.timer"
