# Requiere ejecutar el aprovisionamiento como root.
# Las operaciones posteriores modifican cuentas, paquetes, firewall y unidades de systemd.
[[ $EUID -eq 0 ]] || finalizar_con_error "Ejecutá como root: sudo bash $0"

# Comprueba que las cuentas que administra el proyecto tengan contraseñas configuradas.
# La expansión con :- permite detectar una variable ausente sin romper set -u.
[[ -n "${PASSWORD_SUDO:-}" && -n "${PASSWORD_ADMIN:-}" && -n "${PASSWORD_LOGGER:-}" ]] ||
	finalizar_con_error "Definí las contraseñas de todas las cuentas en configuracion.sh"

# Lee el límite UID_MIN que distingue a usuarios normales de las cuentas del sistema.
UID_MIN="$(awk '$1 == "UID_MIN" { print $2; exit }' /etc/login.defs)"
[[ "$UID_MIN" =~ ^[0-9]+$ ]] || finalizar_con_error "No se pudo leer UID_MIN de /etc/login.defs."

# Programa la eliminación de las cuentas locales normales, excepto las cuentas protegidas.
mapfile -t REMOVE_USERS < <(awk -F: -v uid_min="$UID_MIN" '
	$3 >= uid_min && $1 != "root" && $1 != "nobody" &&
	$1 != "sudo" && $1 != "admin" && $1 != "logger" { print $1 }
' /etc/passwd)

# Valida los nombres antes de incorporarlos a comandos de systemd.
VALID_REMOVE_USERS=()
for remove_user in "${REMOVE_USERS[@]}"; do
	[[ "$remove_user" =~ ^[a-zA-Z_][a-zA-Z0-9_.-]*$ ]] ||
		finalizar_con_error "El nombre de cuenta indicado para eliminar no es válido: $remove_user"

	case "$remove_user" in
		root|sudo|admin|logger)
			finalizar_con_error "No se permite eliminar root ni las cuentas administradas: $remove_user"
			;;
	esac

	if id "$remove_user" >/dev/null 2>&1; then
		VALID_REMOVE_USERS+=("$remove_user")
	fi
done
REMOVE_USERS=("${VALID_REMOVE_USERS[@]}")

# Rechaza separadores de ruta para limitar el proyecto a una carpeta directa dentro de /srv.
[[ "$DOCKER_PROJECT_DIR_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] ||
	finalizar_con_error "DOCKER_PROJECT_DIR_NAME debe ser un nombre de carpeta válido dentro de /srv."

# Estos valores se incorporan a nombres de archivos y unidades systemd.
[[ "$DOCKER_SYSTEMD_UNIT" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] ||
	finalizar_con_error "DOCKER_SYSTEMD_UNIT contiene caracteres no permitidos."
[[ "$REMOVE_USERS_SYSTEMD_UNIT" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] ||
	finalizar_con_error "REMOVE_USERS_SYSTEMD_UNIT contiene caracteres no permitidos."
[[ "$BACKUP_SYSTEMD_UNIT" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] ||
	finalizar_con_error "BACKUP_SYSTEMD_UNIT contiene caracteres no permitidos."

# El horario puede ser un calendario de systemd (preferido) o, si está vacío, un intervalo simple.
if [[ -n "$BACKUP_ONCALENDAR" ]]; then
	[[ "$BACKUP_ONCALENDAR" =~ ^[A-Za-z0-9*:/,.\ -]+$ ]] ||
		finalizar_con_error "BACKUP_ONCALENDAR contiene caracteres no permitidos."
	if command -v systemd-analyze >/dev/null 2>&1; then
		systemd-analyze calendar "$BACKUP_ONCALENDAR" >/dev/null 2>&1 ||
			finalizar_con_error "BACKUP_ONCALENDAR no es un calendario válido de systemd: $BACKUP_ONCALENDAR"
	fi
else
	# Solo se permiten duraciones simples de systemd para evitar valores ambiguos.
	[[ "$BACKUP_INTERVAL" =~ ^[1-9][0-9]*(s|min|h|d)$ ]] ||
		finalizar_con_error "BACKUP_INTERVAL debe tener formato de duración, por ejemplo 5min o 1h."
	# Separa la parte numérica y acota el valor antes de usarlo en una operación aritmética.
	BACKUP_INTERVAL_VALUE="${BACKUP_INTERVAL//[!0-9]/}"
	(( ${#BACKUP_INTERVAL_VALUE} <= 4 && 10#$BACKUP_INTERVAL_VALUE <= 3650 )) ||
		finalizar_con_error "BACKUP_INTERVAL no puede superar 3650 unidades."
fi

# La carpeta de copias también se limita a un único nombre simple.
[[ "$BACKUP_DIR_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] ||
	finalizar_con_error "BACKUP_DIR_NAME debe ser un nombre de carpeta válido."
# Evita una retención accidental ilimitada o un valor demasiado grande para calcular.
for retencion in BACKUP_KEEP_DAILY BACKUP_KEEP_WEEKLY BACKUP_KEEP_MONTHLY; do
	valor_retencion="${!retencion}"
	[[ "$valor_retencion" =~ ^[1-9][0-9]*$ ]] && (( ${#valor_retencion} <= 4 )) ||
		finalizar_con_error "$retencion debe ser un entero entre 1 y 9999."
done

# Los volúmenes y la copia externa son opcionales, pero si se indican deben tener un formato seguro.
for volumen in "${BACKUP_VOLUMES[@]}"; do
	[[ "$volumen" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] ||
		finalizar_con_error "Nombre de volumen no válido en BACKUP_VOLUMES: $volumen"
done
if [[ -n "$BACKUP_COPY_DIR" ]]; then
	[[ "$BACKUP_COPY_DIR" =~ ^/[a-zA-Z0-9/_.-]+$ ]] &&
		[[ "$BACKUP_COPY_DIR" != "$PROJECT/$BACKUP_DIR_NAME" ]] ||
		finalizar_con_error "BACKUP_COPY_DIR debe ser una ruta absoluta distinta de la carpeta de respaldos local."
fi

# Comprueba los nombres de servicios antes de agregarlos a ExecStart de systemd.
# La lista vacía se permite y significa iniciar todos los servicios del archivo Compose.
for compose_service in "${DOCKER_COMPOSE_SERVICES[@]}"; do
	[[ "$compose_service" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] ||
		finalizar_con_error "Nombre de servicio Compose no válido: $compose_service"
done

# Para que el respaldo incluya datos, debe haber al menos un servicio de MySQL configurado.
(( ${#BACKUP_MYSQL_SERVICES[@]} > 0 )) ||
	finalizar_con_error "Definí al menos un servicio en BACKUP_MYSQL_SERVICES."

# Valida cada nombre usado por docker compose exec y mysqldump.
for mysql_service in "${BACKUP_MYSQL_SERVICES[@]}"; do
	[[ "$mysql_service" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] ||
		finalizar_con_error "Nombre de servicio MySQL no válido: $mysql_service"
done

# Verifica antes de instalar paquetes o cambiar el sistema que el proyecto existe y tiene Compose.
# Excepción: en la recuperación de un servidor nuevo, el propio respaldo trae el Compose (se restaura en el módulo 55).
if [[ "$RESTORE_CONFIRMED" == "1" && ( "$RESTORE_TYPE" == "archivos" || "$RESTORE_TYPE" == "ambos" || "$RESTORE_TYPE" == "completo" ) ]]; then
	echo "Recuperación de archivos solicitada: el Compose se tomará de la copia seleccionada."
else
	[[ -f "$PROJECT/compose.yaml" || -f "$PROJECT/docker-compose.yml" ]] ||
		finalizar_con_error "Colocá compose.yaml o docker-compose.yml en $PROJECT antes de ejecutar este script."
fi
