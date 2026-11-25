#!/usr/bin/env bash
# Genera una copia privada del proyecto: archivos, volúmenes Docker elegidos y exportaciones lógicas de MySQL.
# Cada copia lleva su suma SHA-256 y se poda con retención escalonada (diaria, semanal y mensual).
set -euo pipefail
umask 077

# Exige que systemd proporcione todos los valores necesarios para crear la copia.
: "${PROJECT_DIR:?Falta PROJECT_DIR}"
: "${BACKUP_DIR:?Falta BACKUP_DIR}"
: "${BACKUP_DIR_NAME:?Falta BACKUP_DIR_NAME}"
: "${BACKUP_KEEP_DAILY:?Falta BACKUP_KEEP_DAILY}"
: "${BACKUP_KEEP_WEEKLY:?Falta BACKUP_KEEP_WEEKLY}"
: "${BACKUP_KEEP_MONTHLY:?Falta BACKUP_KEEP_MONTHLY}"
: "${BACKUP_MYSQL_SERVICES:?Falta BACKUP_MYSQL_SERVICES}"
# Estas dos variables son opcionales: lista de volúmenes Compose y carpeta de la copia externa (NAS, USB).
BACKUP_VOLUMES="${BACKUP_VOLUMES:-}"
BACKUP_COPY_DIR="${BACKUP_COPY_DIR:-}"

# Informa con claridad si falta una herramienta requerida por el proceso de copia.
for command_name in docker flock find gzip sort tar sha256sum date; do
	command -v "$command_name" >/dev/null 2>&1 || {
		echo "Error: se requiere el comando $command_name para generar respaldos." >&2
		exit 1
	}
done

# Valida un entero positivo acotado para las políticas de retención.
validar_retencion() {
	[[ "$2" =~ ^[1-9][0-9]*$ ]] && (( ${#2} <= 4 )) || {
		echo "Error: $1 debe ser un entero entre 1 y 9999." >&2
		exit 1
	}
}
validar_retencion BACKUP_KEEP_DAILY "$BACKUP_KEEP_DAILY"
validar_retencion BACKUP_KEEP_WEEKLY "$BACKUP_KEEP_WEEKLY"
validar_retencion BACKUP_KEEP_MONTHLY "$BACKUP_KEEP_MONTHLY"

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
if [[ -n "$BACKUP_COPY_DIR" ]]; then
	[[ "$BACKUP_COPY_DIR" =~ ^/[a-zA-Z0-9/_.-]+$ && "$BACKUP_COPY_DIR" != "$BACKUP_DIR" ]] || {
		echo "Error: BACKUP_COPY_DIR no es válido." >&2
		exit 1
	}
fi
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
COMPOSE=(docker compose --project-directory "$PROJECT_DIR" -f "$COMPOSE_FILE")

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
FINAL_NAME="docker-backup-$BACKUP_TIMESTAMP.tar.gz"
FINAL_ARCHIVE="$BACKUP_DIR/$FINAL_NAME"
cleanup() {
	rm -rf -- "$STAGING_DIR"
	rm -f -- "$TEMP_ARCHIVE"
}
trap cleanup EXIT
mkdir -m 0700 "$STAGING_DIR/mysql" "$STAGING_DIR/volumes"

# Conserva, dentro de un directorio, el archivo más reciente de cada día (BACKUP_KEEP_DAILY días),
# de cada semana ISO (BACKUP_KEEP_WEEKLY semanas) y de cada mes (BACKUP_KEEP_MONTHLY meses).
# Borra el resto junto con su archivo .sha256; solo toca nombres con el patrón de este guion.
podar_directorio() {
	local dir="$1" archivo dia mes semana conservar
	local -a archivos=()
	local -A vistos_dia=() vistos_semana=() vistos_mes=()
	local n_dia=0 n_semana=0 n_mes=0

	mapfile -t archivos < <(
		find "$dir" -mindepth 1 -maxdepth 1 -type f -name 'docker-backup-*.tar.gz' -printf '%f\n' | sort -r
	)
	for archivo in "${archivos[@]}"; do
		[[ "$archivo" =~ ^docker-backup-([0-9]{4})([0-9]{2})([0-9]{2})T[0-9]{6}Z\.tar\.gz$ ]] || continue
		dia="${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
		mes="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
		semana="$(date -u -d "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}" +%G-%V)"
		conservar=0

		if [[ -z "${vistos_dia[$dia]:-}" ]]; then
			vistos_dia[$dia]=1
			if (( n_dia < BACKUP_KEEP_DAILY )); then conservar=1; n_dia=$((n_dia + 1)); fi
		fi
		if [[ -z "${vistos_semana[$semana]:-}" ]]; then
			vistos_semana[$semana]=1
			if (( n_semana < BACKUP_KEEP_WEEKLY )); then conservar=1; n_semana=$((n_semana + 1)); fi
		fi
		if [[ -z "${vistos_mes[$mes]:-}" ]]; then
			vistos_mes[$mes]=1
			if (( n_mes < BACKUP_KEEP_MONTHLY )); then conservar=1; n_mes=$((n_mes + 1)); fi
		fi

		if (( conservar == 0 )); then
			echo "Retención: se elimina $dir/$archivo"
			rm -f -- "$dir/$archivo" "$dir/$archivo.sha256"
		fi
	done
}

# Si el guion se invoca con --solo-podar, aplica la retención al directorio indicado y termina (útil para pruebas).
if [[ "${1:-}" == "--solo-podar" ]]; then
	podar_directorio "${2:?Indicá el directorio}"
	exit 0
fi

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
	"${COMPOSE[@]}" exec -T "$mysql_service" sh -ec '
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

# Copia los volúmenes Docker elegidos (por ejemplo, el de Grafana), que no se reconstruyen con docker compose up.
# El nombre real del volumen es "<proyecto>_<clave>"; el proyecto se toma de la salida de "compose config".
PROJECT_NAME="$("${COMPOSE[@]}" config 2>/dev/null | awk '/^name:/ { print $2; exit }')"
if [[ -z "$PROJECT_NAME" ]]; then
	PROJECT_NAME="$(basename "$PROJECT_DIR" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')"
fi
VOLUMES_SAVED=()
VOLUMES_SKIPPED=()
read -r -a VOLUME_KEYS <<< "$BACKUP_VOLUMES"
for volume_key in "${VOLUME_KEYS[@]}"; do
	[[ "$volume_key" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || {
		echo "Error: nombre de volumen no válido: $volume_key." >&2
		exit 1
	}
	volume_name=""
	for candidate in "${PROJECT_NAME}_${volume_key}" "$volume_key"; do
		if docker volume inspect "$candidate" >/dev/null 2>&1; then
			volume_name="$candidate"
			break
		fi
	done
	if [[ -z "$volume_name" ]]; then
		echo "Advertencia: el volumen '$volume_key' no existe; se omite." >&2
		VOLUMES_SKIPPED+=("$volume_key")
		continue
	fi
	volume_path="$(docker volume inspect -f '{{.Mountpoint}}' "$volume_name")"
	echo "Copiando el volumen $volume_name..."
	tar -czf "$STAGING_DIR/volumes/$volume_key.tar.gz" --numeric-owner -C "$volume_path" .
	VOLUMES_SAVED+=("$volume_key")
done

# Incluye un manifiesto con fecha, proyecto, servicios MySQL, volúmenes y límites de esta copia.
{
	printf 'Fecha UTC: %s\n' "$(date -u --iso-8601=seconds)"
	printf 'Proyecto: %s\n' "$PROJECT_DIR"
	printf 'Servicios MySQL exportados: %s\n' "${MYSQL_SERVICES[*]}"
	printf 'Volumenes copiados: %s\n' "${VOLUMES_SAVED[*]:-ninguno}"
	printf 'Volumenes omitidos: %s\n' "${VOLUMES_SKIPPED[*]:-ninguno}"
	printf 'Alcance: archivos del proyecto, volumenes indicados y dumps logicos de MySQL.\n'
	printf 'Los volumenes Docker no incluidos deben protegerse con sus propios mecanismos.\n'
} > "$STAGING_DIR/backup-info.txt"

# Empaqueta los archivos del proyecto, los volúmenes y las exportaciones SQL.
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
	-C "$STAGING_DIR" mysql volumes backup-info.txt

# Comprueba compresión, índice tar y cada dump interno antes de publicar atómicamente el archivo final.
gzip -t "$TEMP_ARCHIVE"
tar -tzf "$TEMP_ARCHIVE" >/dev/null
for dump in "$STAGING_DIR"/mysql/*.sql.gz "$STAGING_DIR"/volumes/*.tar.gz; do
	[[ -e "$dump" ]] && gzip -t "$dump"
done
mv -- "$TEMP_ARCHIVE" "$FINAL_ARCHIVE"
chmod 0600 "$FINAL_ARCHIVE"
# La suma SHA-256 permite detectar corrupción o manipulación antes de restaurar.
(cd "$BACKUP_DIR" && sha256sum "$FINAL_NAME" > "$FINAL_NAME.sha256")
chmod 0600 "$FINAL_ARCHIVE.sha256"
echo "Respaldo creado: $FINAL_ARCHIVE"

# Aplica la retención escalonada en el destino local.
podar_directorio "$BACKUP_DIR"

# Copia externa opcional (NAS, disco USB): sin ella, un incidente en el servidor se lleva también los respaldos.
if [[ -n "$BACKUP_COPY_DIR" ]]; then
	if mountpoint -q "$BACKUP_COPY_DIR" 2>/dev/null || [[ -d "$BACKUP_COPY_DIR" && "${BACKUP_COPY_REQUIRE_MOUNT:-1}" == "0" ]]; then
		cp -- "$FINAL_ARCHIVE" "$BACKUP_COPY_DIR/$FINAL_NAME.partial"
		cp -- "$FINAL_ARCHIVE.sha256" "$BACKUP_COPY_DIR/$FINAL_NAME.sha256"
		(cd "$BACKUP_COPY_DIR" && mv -- "$FINAL_NAME.partial" "$FINAL_NAME" && sha256sum -c "$FINAL_NAME.sha256" >/dev/null) || {
			echo "Error: la copia externa en $BACKUP_COPY_DIR no coincide con el original." >&2
			rm -f -- "$BACKUP_COPY_DIR/$FINAL_NAME" "$BACKUP_COPY_DIR/$FINAL_NAME.partial"
			exit 1
		}
		echo "Copia externa verificada: $BACKUP_COPY_DIR/$FINAL_NAME"
		podar_directorio "$BACKUP_COPY_DIR"
	else
		# El respaldo local es válido, pero el servicio termina con error para que el fallo quede visible.
		echo "Error: $BACKUP_COPY_DIR no está montado; el respaldo quedó solo en el equipo local." >&2
		exit 1
	fi
fi
