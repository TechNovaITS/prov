#!/usr/bin/env bash
# Genera una copia privada de los archivos del proyecto y exportaciones lógicas de MySQL.
set -euo pipefail
umask 077https://www.youtube.com/watch?v=2cmt_KDxCGQ

# Exige que systemd proporcione todos los valores necesarios para crear la copia.
: "${PROJECT_DIR:?Falta PROJECT_DIR}"
: "${BACKUP_DIR:?Falta BACKUP_DIR}"
: "${BACKUP_DIR_NAME:?Falta BACKUP_DIR_NAME}"
: "${BACKUP_RETENTION_COUNT:?Falta BACKUP_RETENTION_COUNT}"
: "${BACKUP_MYSQL_SERVICES:?Falta BACKUP_MYSQL_SERVICES}"

# Informa con claridad si falta una herramienta requerida por el proceso de copia.
for command_name in docker flock find gzip sort tar; do
	command -v "$command_name" >/dev/null 2>&1 || {
		echo "Error: se requiere el comando $command_name para generar respaldos." >&2
		exit 1
	}
done

# Limita el proyecto a una carpeta directa de /srv y el destino a una subcarpeta del proyecto.
[[ "$PROJECT_DIR" =~ ^/srv/[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || {
	echo "Error: PROJECT_DIR debe ser una carpeta directa dentro de /srv." >&2
	exit 1
}
[[ "$BACKUP_DIR_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || {
	echo "Error: BACKUP_DIR_NAME no es válido." >&2
	exit 1
}
[[ "$BACKUP_DIR" == "$PROJECT_DIR/$BACKUP_DIR_NAME" ]] || {
	echo "Error: BACKUP_DIR debe ser una subcarpeta directa del proyecto." >&2
	exit 1
}
[[ "$BACKUP_RETENTION_COUNT" =~ ^[1-9][0-9]*$ ]] || {
	echo "Error: BACKUP_RETENTION_COUNT debe ser un entero positivo." >&2
	exit 1
}
(( ${#BACKUP_RETENTION_COUNT} <= 5 && 10#$BACKUP_RETENTION_COUNT <= 10000 )) || {
	echo "Error: BACKUP_RETENTION_COUNT no puede superar 10000." >&2
	exit 1
}
[[ -d "$PROJECT_DIR" ]] || {
	echo "Error: no existe el proyecto $PROJECT_DIR." >&2
	exit 1
}
[[ -f "$PROJECT_DIR/compose.yaml" || -f "$PROJECT_DIR/docker-compose.yml" ]] || {
	echo "Error: no se encontró un archivo Compose en $PROJECT_DIR." >&2
	exit 1
}
if [[ -f "$PROJECT_DIR/compose.yaml" ]]; then
	COMPOSE_FILE="$PROJECT_DIR/compose.yaml"
else
	COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
fi

# Crea el destino con permisos privados y evita dos copias simultáneas del mismo proyecto.
mkdir -p -m 0700 "$BACKUP_DIR"
chmod 0700 "$BACKUP_DIR"
exec 9>"$BACKUP_DIR/.backup.lock"
flock -n 9 || {
	echo "Error: ya hay otro respaldo en ejecución." >&2
	exit 1
}

# Prepara archivos temporales privados; el archivo final no aparecerá hasta que pase las verificaciones.
STAGING_DIR="$(mktemp -d "$BACKUP_DIR/.backup-stage.XXXXXX")"
BACKUP_TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
TEMP_ARCHIVE="$BACKUP_DIR/.docker-backup-$BACKUP_TIMESTAMP.tar.gz"
FINAL_ARCHIVE="$BACKUP_DIR/docker-backup-$BACKUP_TIMESTAMP.tar.gz"
cleanup() {
	rm -rf -- "$STAGING_DIR"
	rm -f -- "$TEMP_ARCHIVE"
}
trap cleanup EXIT
mkdir -m 0700 "$STAGING_DIR/mysql"

# Exporta cada instancia configurada; si una falla, se cancela toda la copia para no ocultar datos faltantes.
read -r -a MYSQL_SERVICES <<< "$BACKUP_MYSQL_SERVICES"
(( ${#MYSQL_SERVICES[@]} > 0 )) || {
	echo "Error: no se configuraron servicios MySQL para el respaldo." >&2
	exit 1
}
for mysql_service in "${MYSQL_SERVICES[@]}"; do
	[[ "$mysql_service" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || {
		echo "Error: nombre de servicio MySQL no válido: $mysql_service." >&2
		exit 1
	}

	echo "Exportando MySQL del servicio $mysql_service..."
	docker compose --project-directory "$PROJECT_DIR" -f "$COMPOSE_FILE" \
		exec -T "$mysql_service" sh -ec '
			test -n "${MYSQL_ROOT_PASSWORD:-}" || {
				echo "Falta MYSQL_ROOT_PASSWORD en el contenedor." >&2
				exit 1
			}
			export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"
			exec mysqldump --user=root --all-databases --single-transaction \
				--routines --events --triggers --hex-blob --set-gtid-purged=OFF
		' > "$STAGING_DIR/mysql/$mysql_service.sql"
	gzip -9 "$STAGING_DIR/mysql/$mysql_service.sql"
done

# Incluye un manifiesto con fecha, proyecto, servicios MySQL y límites de esta copia.
{
	printf 'Fecha UTC: %s\n' "$(date -u --iso-8601=seconds)"
	printf 'Proyecto: %s\n' "$PROJECT_DIR"
	printf 'Servicios MySQL exportados: %s\n' "${MYSQL_SERVICES[*]}"
	printf 'Alcance: archivos del proyecto y dumps lógicos de MySQL.\n'
	printf 'Los volúmenes Docker no incluidos deben protegerse con sus propios mecanismos.\n'
} > "$STAGING_DIR/backup-info.txt"

# Empaqueta los archivos del proyecto y las exportaciones SQL.
# Omite copias previas, Git y dependencias que se pueden volver a instalar.
docker_files=(
	--exclude="./$BACKUP_DIR_NAME"
	--exclude="./.git"
	--exclude="./web/vendor"
	--exclude="./web/node_modules"
	--exclude="./grafana/plugins"
)
tar -czf "$TEMP_ARCHIVE" \
	-C "$PROJECT_DIR" "${docker_files[@]}" . \
	-C "$STAGING_DIR" mysql backup-info.txt

# Comprueba compresión e índice tar antes de publicar atómicamente el archivo final.
gzip -t "$TEMP_ARCHIVE"
tar -tzf "$TEMP_ARCHIVE" >/dev/null
mv -- "$TEMP_ARCHIVE" "$FINAL_ARCHIVE"
chmod 0600 "$FINAL_ARCHIVE"
echo "Respaldo creado: $FINAL_ARCHIVE"

# Conserva las copias más recientes y elimina solo archivos con el patrón que genera este guion.
mapfile -t BACKUP_FILES < <(
	find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type f \
		-name 'docker-backup-*.tar.gz' -printf '%f\n' | sort -r
)
for ((index = BACKUP_RETENTION_COUNT; index < ${#BACKUP_FILES[@]}; index++)); do
	rm -f -- "$BACKUP_DIR/${BACKUP_FILES[index]}"
done
