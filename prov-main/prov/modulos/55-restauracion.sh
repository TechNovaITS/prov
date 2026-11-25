# ============================================================================
# PROCEDIMIENTO DE RECUPERACIÓN ANTE DESASTRES
# ----------------------------------------------------------------------------
# Este módulo solo actúa si el menú confirmó una restauración (RESTORE_CONFIRMED=1).
# Cómo llegar acá:  sudo bash prov.sh  ->  opción 4 (restaurar) o 5 (configurar todo y restaurar).
# Ayuda completa:   sudo bash prov.sh --ayuda
#
# Tipos de restauración (RESTORE_TYPE):
#   archivos  - compose.yaml, .env, configuración y código del proyecto.
#   sql       - bases de datos MySQL desde los dumps (mysql/<servicio>.sql.gz).
#   ambos     - archivos y SQL.
#   volumenes - volúmenes Docker incluidos en la copia (volumes/<clave>.tar.gz), p. ej. Grafana.
#   completo  - archivos, volúmenes y SQL: recuperación total de un servidor nuevo.
#
# Orden de ejecución: verificar integridad -> detener el proyecto (sin borrar volúmenes)
#   -> archivos -> volúmenes -> levantar MySQL -> importar SQL -> levantar el resto -> verificar.
# ============================================================================

# No realiza ninguna operación si el menú no confirmó una restauración.
if [[ "$RESTORE_CONFIRMED" != "1" ]]; then
	if [[ -n "$RESTORE_ARCHIVE" ]]; then
		finalizar_con_error "Hay una restauración seleccionada sin confirmación explícita."
	fi
	return 0
fi

# Restringe el archivo a una copia generada dentro del directorio privado del proyecto.
case "$RESTORE_ARCHIVE" in
	"$PROJECT/$BACKUP_DIR_NAME"/docker-backup-*.tar.gz) ;;
	*) finalizar_con_error "La ruta de la copia seleccionada no es válida." ;;
esac
[[ -f "$RESTORE_ARCHIVE" && ! -L "$RESTORE_ARCHIVE" ]] ||
	finalizar_con_error "No se encontró la copia seleccionada o no es un archivo regular."
case "$RESTORE_TYPE" in
	archivos|sql|ambos|volumenes|completo) ;;
	*) finalizar_con_error "El tipo de restauración seleccionado no es válido." ;;
esac

# Traduce el tipo elegido a tres decisiones independientes.
RESTORE_FILES=0; RESTORE_SQL=0; RESTORE_VOLS=0
case "$RESTORE_TYPE" in
	archivos)  RESTORE_FILES=1 ;;
	sql)       RESTORE_SQL=1 ;;
	ambos)     RESTORE_FILES=1; RESTORE_SQL=1 ;;
	volumenes) RESTORE_VOLS=1 ;;
	completo)  RESTORE_FILES=1; RESTORE_VOLS=1; RESTORE_SQL=1 ;;
esac

# Comparte el bloqueo con el servicio de respaldo para evitar copiar mientras se restauran datos.
exec 8>"$PROJECT/$BACKUP_DIR_NAME/.backup.lock"
flock -n 8 ||
	finalizar_con_error "Hay un respaldo en ejecución; intenta la restauración nuevamente más tarde."

# Verifica la suma SHA-256 generada al crear la copia: detecta corrupción o manipulación antes de tocar nada.
if [[ -f "$RESTORE_ARCHIVE.sha256" ]]; then
	( cd "$(dirname "$RESTORE_ARCHIVE")" && sha256sum -c "$(basename "$RESTORE_ARCHIVE").sha256" >/dev/null ) ||
		finalizar_con_error "La suma SHA-256 no coincide: la copia está dañada o fue modificada. No se restauró nada."
	echo "Integridad verificada (SHA-256) de $(basename "$RESTORE_ARCHIVE")."
else
	echo "Advertencia: no hay archivo .sha256 para esta copia; solo se comprobará su estructura." >&2
fi

# Comprueba la estructura del archivo antes de modificar el proyecto o sus bases.
tar -tzf "$RESTORE_ARCHIVE" >/dev/null ||
	finalizar_con_error "No se pudo leer la copia seleccionada."
mapfile -t RESTORE_ARCHIVE_MEMBERS < <(tar -tzf "$RESTORE_ARCHIVE")
for miembro in "${RESTORE_ARCHIVE_MEMBERS[@]}"; do
	ruta="${miembro#./}"
	[[ -z "$ruta" || "$ruta" == "." ]] && continue
	[[ "$ruta" != /* && "/$ruta/" != *"/../"* && "/$ruta/" != *"/./"* ]] ||
		finalizar_con_error "La copia contiene una ruta no permitida: $miembro"
done

# Comprueba de antemano que cada exportación elegida exista y esté íntegra.
declare -A RESTORE_DUMP_MEMBERS=()
if (( RESTORE_SQL == 1 )); then
	(( ${#RESTORE_SQL_SERVICES[@]} > 0 )) ||
		finalizar_con_error "No se eligieron servicios MySQL para restaurar."
	for servicio in "${RESTORE_SQL_SERVICES[@]}"; do
		[[ "$servicio" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] ||
			finalizar_con_error "Nombre de servicio MySQL no válido: $servicio"

		miembro="mysql/$servicio.sql.gz"
		if ! printf '%s\n' "${RESTORE_ARCHIVE_MEMBERS[@]}" | grep -Fxq "$miembro"; then
			miembro="./mysql/$servicio.sql.gz"
			printf '%s\n' "${RESTORE_ARCHIVE_MEMBERS[@]}" | grep -Fxq "$miembro" ||
				finalizar_con_error "La copia no contiene la exportación SQL del servicio '$servicio'."
		fi
		tar -xOzf "$RESTORE_ARCHIVE" "$miembro" | gzip -t ||
			finalizar_con_error "La exportación SQL de '$servicio' está dañada."
		RESTORE_DUMP_MEMBERS["$servicio"]="$miembro"
	done
fi

# Lista los volúmenes que contiene la copia y comprueba que cada uno esté íntegro.
RESTORE_VOLUME_MEMBERS=()
if (( RESTORE_VOLS == 1 )); then
	for miembro in "${RESTORE_ARCHIVE_MEMBERS[@]}"; do
		case "$miembro" in
			volumes/*.tar.gz|./volumes/*.tar.gz)
				tar -xOzf "$RESTORE_ARCHIVE" "$miembro" | gzip -t ||
					finalizar_con_error "El volumen '$miembro' de la copia está dañado."
				RESTORE_VOLUME_MEMBERS+=("$miembro")
				;;
		esac
	done
	if (( ${#RESTORE_VOLUME_MEMBERS[@]} == 0 )); then
		if [[ "$RESTORE_TYPE" == "volumenes" ]]; then
			finalizar_con_error "La copia no contiene volúmenes Docker para restaurar."
		fi
		echo "Advertencia: la copia no contiene volúmenes; se restaurará el resto." >&2
	fi
fi

# Selecciona el archivo Compose que corresponda al proyecto configurado.
restauracion_actualizar_compose() {
	if [[ -f "$PROJECT/compose.yaml" ]]; then
		COMPOSE_FILE="$PROJECT/compose.yaml"
	elif [[ -f "$PROJECT/docker-compose.yml" ]]; then
		COMPOSE_FILE="$PROJECT/docker-compose.yml"
	else
		finalizar_con_error "No se encontró un archivo Compose en $PROJECT."
	fi
	COMPOSE_CMD=(docker compose --project-directory "$PROJECT" -f "$COMPOSE_FILE")
}

# Devuelve los servicios declarados en la configuración Compose actual.
restauracion_listar_servicios() {
	local salida
	salida="$("${COMPOSE_CMD[@]}" config --services)" ||
		finalizar_con_error "No se pudieron leer los servicios Compose de $COMPOSE_FILE."
	mapfile -t SERVICIOS_ACTUALES <<< "$salida"
}

# Comprueba que cada servicio elegido exista en el proyecto activo.
restauracion_validar_servicios() {
	local servicio
	local encontrado
	for servicio in "$@"; do
		encontrado=0
		for servicio_actual in "${SERVICIOS_ACTUALES[@]}"; do
			if [[ "$servicio" == "$servicio_actual" ]]; then
				encontrado=1
				break
			fi
		done
		(( encontrado == 1 )) ||
			finalizar_con_error "El servicio '$servicio' no existe en el Compose actual."
	done
}

# Pausa la aplicación y las herramientas mientras se reemplaza una base de datos.
restauracion_pausar_servicios_no_mysql() {
	local servicio
	local es_mysql
	local -a servicios_pausar=()

	restauracion_listar_servicios
	for servicio in "${SERVICIOS_ACTUALES[@]}"; do
		es_mysql=0
		for mysql_service in "${BACKUP_MYSQL_SERVICES[@]}" "${RESTORE_SQL_SERVICES[@]}"; do
			if [[ "$servicio" == "$mysql_service" ]]; then
				es_mysql=1
				break
			fi
		done
		(( es_mysql == 1 )) || servicios_pausar+=("$servicio")
	done

	if (( ${#servicios_pausar[@]} > 0 )); then
		echo "Deteniendo temporalmente los servicios de aplicación y monitoreo..."
		"${COMPOSE_CMD[@]}" stop "${servicios_pausar[@]}"
	fi
}

# Espera a que MySQL responda y rechaza destinos configurados en solo lectura.
restauracion_validar_destino_mysql() {
	local servicio="$1"
	local intento
	local disponible=0
	local modo_solo_lectura

	for ((intento = 1; intento <= 60; intento++)); do
		if "${COMPOSE_CMD[@]}" exec -T "$servicio" sh -ec '
			test -n "${MYSQL_ROOT_PASSWORD:-}"
			export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"
			mysqladmin ping --host=127.0.0.1 --user=root --silent
		' >/dev/null 2>&1; then
			disponible=1
			break
		fi
		sleep 2
	done

	(( disponible == 1 )) ||
		finalizar_con_error "MySQL del servicio '$servicio' no respondió en 120 segundos."

	modo_solo_lectura="$("${COMPOSE_CMD[@]}" exec -T "$servicio" sh -ec '
		test -n "${MYSQL_ROOT_PASSWORD:-}"
		export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"
		mysql --batch --skip-column-names --user=root \
			--execute="SELECT @@GLOBAL.read_only"
	')"
	[[ "$modo_solo_lectura" == "0" ]] ||
		finalizar_con_error "El servicio '$servicio' es de solo lectura y no se puede restaurar allí."
}

# Obtiene el nombre del proyecto Compose; los volúmenes se llaman "<proyecto>_<clave>".
restauracion_nombre_proyecto() {
	local nombre
	nombre="$("${COMPOSE_CMD[@]}" config 2>/dev/null | awk '/^name:/ { print $2; exit }')"
	if [[ -z "$nombre" ]]; then
		nombre="$(basename "$PROJECT" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')"
	fi
	printf '%s' "$nombre"
}

# Reemplaza el contenido de cada volumen de la copia, conservando propietarios numéricos (p. ej. uid 472 de Grafana).
restauracion_volumenes() {
	local miembro clave nombre_proyecto nombre_volumen ruta
	nombre_proyecto="$(restauracion_nombre_proyecto)"
	for miembro in "${RESTORE_VOLUME_MEMBERS[@]}"; do
		clave="${miembro#./}"; clave="${clave#volumes/}"; clave="${clave%.tar.gz}"
		[[ "$clave" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] ||
			finalizar_con_error "Nombre de volumen no válido en la copia: $clave"
		nombre_volumen="${nombre_proyecto}_${clave}"
		# Si el volumen no existe (servidor nuevo), se crea con las mismas etiquetas que usa Compose.
		if ! docker volume inspect "$nombre_volumen" >/dev/null 2>&1; then
			docker volume create \
				--label "com.docker.compose.project=$nombre_proyecto" \
				--label "com.docker.compose.volume=$clave" \
				"$nombre_volumen" >/dev/null
		fi
		ruta="$(docker volume inspect -f '{{.Mountpoint}}' "$nombre_volumen")"
		[[ -d "$ruta" && "$ruta" == /* && "$ruta" != "/" ]] ||
			finalizar_con_error "Ruta de volumen inesperada para $nombre_volumen: $ruta"
		echo "Restaurando el volumen $nombre_volumen..."
		find "$ruta" -mindepth 1 -delete
		tar -xOzf "$RESTORE_ARCHIVE" "$miembro" | tar -xzf - --numeric-owner -C "$ruta"
	done
}

# Detiene el proyecto una sola vez, sin borrar volúmenes. En un servidor nuevo no hay Compose todavía y no hay nada que detener.
RESTORE_PROJECT_STOPPED=0
restauracion_detener_proyecto() {
	(( RESTORE_PROJECT_STOPPED == 0 )) || return 0
	if [[ -f "$PROJECT/compose.yaml" || -f "$PROJECT/docker-compose.yml" ]]; then
		restauracion_actualizar_compose
		echo "Deteniendo el proyecto; los volúmenes no se eliminan."
		"${COMPOSE_CMD[@]}" down
	else
		echo "No hay un proyecto previo en $PROJECT: no hay nada que detener."
	fi
	RESTORE_PROJECT_STOPPED=1
}

# Si se restauran archivos, detiene Compose sin borrar volúmenes y extrae solo el contenido del proyecto.
if (( RESTORE_FILES == 1 )); then
	restauracion_detener_proyecto
	tar -xzf "$RESTORE_ARCHIVE" -C "$PROJECT" \
		--no-same-owner --no-same-permissions \
		--exclude="./$BACKUP_DIR_NAME" \
		--exclude="./backup-info.txt" \
		--exclude="backup-info.txt" \
		--exclude="./mysql/*.sql.gz" \
		--exclude="mysql/*.sql.gz" \
		--exclude="./volumes/*.tar.gz" \
		--exclude="volumes/*.tar.gz"
	restauracion_actualizar_compose
fi

# Si se restauran volúmenes, el proyecto debe estar detenido para no escribir mientras se reemplazan los datos.
if (( RESTORE_VOLS == 1 && ${#RESTORE_VOLUME_MEMBERS[@]} > 0 )); then
	restauracion_actualizar_compose
	restauracion_detener_proyecto
	restauracion_volumenes
fi

# Restaura solo los destinos elegidos; comprueba todos antes de importar el primer dump.
if (( RESTORE_SQL == 1 )); then
	restauracion_actualizar_compose
	restauracion_listar_servicios
	restauracion_validar_servicios "${BACKUP_MYSQL_SERVICES[@]}" "${RESTORE_SQL_SERVICES[@]}"

	echo "Iniciando las instancias MySQL configuradas..."
	"${COMPOSE_CMD[@]}" up -d "${BACKUP_MYSQL_SERVICES[@]}"
	for servicio in "${RESTORE_SQL_SERVICES[@]}"; do
		restauracion_validar_destino_mysql "$servicio"
	done

	# Solo pausa la aplicación después de confirmar que los destinos SQL permiten escritura.
	restauracion_pausar_servicios_no_mysql
	for servicio in "${RESTORE_SQL_SERVICES[@]}"; do
		miembro="${RESTORE_DUMP_MEMBERS[$servicio]}"
		echo "Restaurando los datos SQL en $servicio..."
		tar -xOzf "$RESTORE_ARCHIVE" "$miembro" | gzip -dc |
			"${COMPOSE_CMD[@]}" exec -T "$servicio" sh -ec '
				test -n "${MYSQL_ROOT_PASSWORD:-}"
				export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"
				exec mysql --user=root
			'
	done
fi

# Vuelve a levantar los servicios elegidos; una lista vacía significa iniciar todos.
restauracion_actualizar_compose
echo "Iniciando los servicios Docker configurados..."
"${COMPOSE_CMD[@]}" up -d "${DOCKER_COMPOSE_SERVICES[@]}"
echo "Restauración completada."

# Verificación posterior: estado de los contenedores y cantidad de tablas de usuario en cada base restaurada.
echo "--- Estado de los contenedores ---"
"${COMPOSE_CMD[@]}" ps || true
for servicio in "${RESTORE_SQL_SERVICES[@]}"; do
	tablas="$("${COMPOSE_CMD[@]}" exec -T "$servicio" sh -ec '
		export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"
		mysql --batch --skip-column-names --user=root --execute="SELECT COUNT(*) FROM information_schema.tables WHERE table_schema NOT IN (\"mysql\",\"sys\",\"information_schema\",\"performance_schema\")"
	' 2>/dev/null || echo "?")"
	echo "Tablas de usuario en $servicio: $tablas"
done
echo "Recordatorio: si hay réplicas MySQL, comprobar que sigan sincronizadas (SHOW REPLICA STATUS / estado de Group Replication)."
