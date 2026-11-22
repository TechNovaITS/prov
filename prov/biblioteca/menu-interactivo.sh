# Usa tonos de la paleta de 256 colores para mantenerlos bien en la terminal.
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
	MENU_COLOR_AZUL=$'\033[38;5;60m'
	MENU_COLOR_CELESTE=$'\033[38;5;38m'
	MENU_COLOR_ROJO=$'\033[38;5;167m'
	MENU_COLOR_BLANCO=$'\033[38;5;15m'
	MENU_COLOR_RESET=$'\033[0m'
else
	MENU_COLOR_AZUL=""
	MENU_COLOR_CELESTE=""
	MENU_COLOR_ROJO=""
	MENU_COLOR_BLANCO=""
	MENU_COLOR_RESET=""
fi

# Dibuja el diseño ASCII original usando celeste, rojo y azul oscuro.
menu_mostrar_marca() {
	printf '\n%s%s%s\n' "$MENU_COLOR_CELESTE" '              .....               ' "$MENU_COLOR_RESET"
	printf '%s%s%s\n' "$MENU_COLOR_CELESTE" '         .:------------:.         ' "$MENU_COLOR_RESET"
	printf '%s%s%s\n' "$MENU_COLOR_CELESTE" '      .--------------------.      ' "$MENU_COLOR_RESET"
	printf '%s%s%s\n' "$MENU_COLOR_CELESTE" '     ------------------------     ' "$MENU_COLOR_RESET"
	printf '%s%s%s\n' "$MENU_COLOR_CELESTE" '   :--------------------------:   ' "$MENU_COLOR_RESET"
	printf '%s%s%s\n' "$MENU_COLOR_CELESTE" '  .----------------------------.  ' "$MENU_COLOR_RESET"
	printf '%s%s%s%s%s\n' "$MENU_COLOR_ROJO" '                  ...' "$MENU_COLOR_ROJO" ':::::::::::' "$MENU_COLOR_RESET"
	printf '%s%s%s%s%s%s%s\n' "$MENU_COLOR_ROJO" '          .-===-:      ' "$MENU_COLOR_ROJO" '.-' "$MENU_COLOR_AZUL" '+++++++= ' "$MENU_COLOR_RESET"
	printf '%s%s%s%s%s%s%s\n' "$MENU_COLOR_ROJO" '     -=====-      ' "$MENU_COLOR_ROJO" '-' "$MENU_COLOR_AZUL" '+++++++++++++= ' "$MENU_COLOR_RESET"
	printf '%s%s%s%s%s%s%s\n' "$MENU_COLOR_ROJO" ' -=====-       ' "$MENU_COLOR_ROJO" '-' "$MENU_COLOR_AZUL" '++++++++++++++++= ' "$MENU_COLOR_RESET"
	printf '%s%s%s%s%s%s%s\n' "$MENU_COLOR_ROJO" ' -===.       ' "$MENU_COLOR_ROJO" '=' "$MENU_COLOR_AZUL" '++++++++++++++++++= ' "$MENU_COLOR_RESET"
	printf '%s%s%s%s%s\n' "$MENU_COLOR_ROJO" '  :        :' "$MENU_COLOR_AZUL" '++++++++++++++++++++  ' "$MENU_COLOR_RESET"
	printf '%s%s%s\n' "$MENU_COLOR_AZUL" '          +++++++++++++++++++++:  ' "$MENU_COLOR_RESET"
	printf '%s%s%s\n' "$MENU_COLOR_AZUL" '         +++++++++++++++++++++:   ' "$MENU_COLOR_RESET"
	printf '%s%s%s\n' "$MENU_COLOR_AZUL" '        +++++++++++++++++++++     ' "$MENU_COLOR_RESET"
	printf '%s%s%s\n' "$MENU_COLOR_AZUL" '       :++++++++++++++++++=.      ' "$MENU_COLOR_RESET"
	printf '%s%s%s\n' "$MENU_COLOR_AZUL" '         .=++++++++++++=.         ' "$MENU_COLOR_RESET"
	printf '%s%s%s\n' "$MENU_COLOR_AZUL" '               ....       ' "$MENU_COLOR_RESET"
	printf '  %sAdministracion de servidor - Uruguay%s\n' "$MENU_COLOR_BLANCO" "$MENU_COLOR_RESET"
	printf '\n'
}

# Imprime una opción numerada con el color rojo de acento.
menu_mostrar_opcion() {
	printf '  %s%s)%s %s\n' "$MENU_COLOR_ROJO" "$1" "$MENU_COLOR_RESET" "$2"
}

# Busca el archivo Compose del proyecto seleccionado y carga sus servicios declarados.
menu_cargar_servicios_compose() {
	MENU_ARCHIVO_COMPOSE=""
	MENU_SERVICIOS_COMPOSE=()

	if [[ -f "$PROJECT/compose.yaml" ]]; then
		MENU_ARCHIVO_COMPOSE="$PROJECT/compose.yaml"
	elif [[ -f "$PROJECT/docker-compose.yml" ]]; then
		MENU_ARCHIVO_COMPOSE="$PROJECT/docker-compose.yml"
	else
		echo "No se encontró un archivo Compose en $PROJECT." >&2
		return 1
	fi

	# Lee solo nombres de servicios al nivel superior de la sección services del YAML.
	mapfile -t MENU_SERVICIOS_COMPOSE < <(awk '
		/^services:[[:space:]]*($|#)/ { dentro_servicios = 1; next }
		dentro_servicios && /^[^[:space:]#]/ { dentro_servicios = 0 }
		dentro_servicios && /^  [a-zA-Z0-9][a-zA-Z0-9_-]*:[[:space:]]*($|#)/ {
			nombre = $0
			sub(/^  /, "", nombre)
			sub(/:.*/, "", nombre)
			print nombre
		}
	' "$MENU_ARCHIVO_COMPOSE")

	if (( ${#MENU_SERVICIOS_COMPOSE[@]} == 0 )); then
		echo "No se pudieron leer servicios de $MENU_ARCHIVO_COMPOSE." >&2
		return 1
	fi
}

# Muestra una lista numerada para que se puedan elegir varios elementos por índice.
menu_mostrar_lista() {
	local indice=1
	for elemento in "$@"; do
		printf '  %s%d)%s %s\n' "$MENU_COLOR_ROJO" "$indice" "$MENU_COLOR_RESET" "$elemento"
		((indice += 1))
	done
}

# Permite conservar la selección actual, elegir índices separados por comas o elegir todos.
menu_elegir_elementos() {
	local variable_salida="$1"
	local descripcion="$2"
	shift 2
	local -a opciones=("$@")
	local -n seleccion_actual="$variable_salida"

	if (( ${#opciones[@]} == 0 )); then
		echo "No hay opciones disponibles para: $descripcion."
		return 1
	fi

	echo "$descripcion:"
	menu_mostrar_lista "${opciones[@]}"
	if (( ${#seleccion_actual[@]} == 0 )); then
		echo "Selección actual: todos."
	else
		printf 'Selección actual: %s\n' "${seleccion_actual[*]}"
	fi

	while true; do
		read -r -p "Números separados por coma, 'todos' o Enter para conservar: " respuesta
		case "${respuesta,,}" in
			"")
				return 0
				;;
			todos|todo|all)
				seleccion_actual=("${opciones[@]}")
				return 0
				;;
		esac

		local -a indices=()
		local -A vistos=()
		local indice
		local numero
		local valido=1
		IFS=',' read -r -a indices <<< "$respuesta"

		for indice in "${indices[@]}"; do
			indice="${indice//[[:space:]]/}"
			if [[ ! "$indice" =~ ^[1-9][0-9]*$ ]]; then
				valido=0
				break
			fi
			if (( ${#indice} > 5 )); then
				valido=0
				break
			fi
			numero=$((10#$indice))
			if (( numero > ${#opciones[@]} )) || [[ -n "${vistos[$numero]:-}" ]]; then
				valido=0
				break
			fi
			vistos[$numero]=1
		done

		if (( valido == 1 )); then
			seleccion_actual=()
			for indice in "${indices[@]}"; do
				indice="${indice//[[:space:]]/}"
				numero=$((10#$indice))
				seleccion_actual+=("${opciones[numero - 1]}")
			done
			return 0
		fi

		echo "Selección inválida. Usa números de la lista, separados por comas."
	done
}

# Permite elegir un proyecto existente de /srv que tenga un archivo Compose.
menu_elegir_carpeta_proyecto() {
	local carpeta
	local numero
	local respuesta
	local indice=1
	local -a proyectos=()

	while IFS= read -r -d '' carpeta; do
		if [[ -f "$carpeta/compose.yaml" || -f "$carpeta/docker-compose.yml" ]]; then
			proyectos+=("${carpeta##*/}")
		fi
	done < <(find /srv -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

	if (( ${#proyectos[@]} == 0 )); then
		echo "No hay proyectos Compose disponibles directamente dentro de /srv."
		return 1
	fi

	echo "Carpetas de proyecto disponibles:"
	menu_mostrar_lista "${proyectos[@]}"
	printf 'Selección actual: %s\n' "$DOCKER_PROJECT_DIR_NAME"

	while true; do
		read -r -p "Número de carpeta o Enter para conservar: " respuesta
		[[ -z "$respuesta" ]] && return 0
		if [[ "$respuesta" =~ ^[1-9][0-9]*$ ]] && (( ${#respuesta} <= 5 )); then
			numero=$((10#$respuesta))
			if (( numero <= ${#proyectos[@]} )); then
				DOCKER_PROJECT_DIR_NAME="${proyectos[numero - 1]}"
				PROJECT="/srv/$DOCKER_PROJECT_DIR_NAME"
				return 0
			fi
		fi
		echo "Elige un número de la lista o presiona Enter para conservar la carpeta actual."
	done
}

# Lista las copias existentes en orden cronológico inverso.
menu_cargar_respaldos() {
	MENU_RESPALDOS=()
	[[ -d "$PROJECT/$BACKUP_DIR_NAME" ]] || return 0
	mapfile -t MENU_RESPALDOS < <(
		find "$PROJECT/$BACKUP_DIR_NAME" -mindepth 1 -maxdepth 1 -type f \
			-name 'docker-backup-*.tar.gz' -printf '%f\n' | sort -r
	)
}

# Limpia la selección para que una cancelación nunca deje una restauración pendiente.
menu_cancelar_restauracion() {
	RESTORE_ARCHIVE=""
	RESTORE_TYPE=""
	RESTORE_SQL_SERVICES=()
	RESTORE_CONFIRMED=0
}

# Permite escoger una copia, decidir si se restauran archivos o SQL y confirmar la operación.
menu_elegir_restauracion() {
	local respuesta
	local numero
	local tipo
	local confirmacion
	local miembro
	local nombre_servicio
	local -a servicios_sql=()

	menu_cargar_respaldos
	if (( ${#MENU_RESPALDOS[@]} == 0 )); then
		echo "No hay copias para restaurar en $PROJECT/$BACKUP_DIR_NAME."
		menu_cancelar_restauracion
		return 1
	fi

	echo "Copias disponibles:"
	menu_mostrar_lista "${MENU_RESPALDOS[@]}"
	read -r -p "Número de copia o 0 para cancelar: " respuesta
	if [[ ! "$respuesta" =~ ^[0-9]+$ ]] || (( ${#respuesta} > 5 )); then
		echo "Restauración cancelada."
		menu_cancelar_restauracion
		return 1
	fi
	numero=$((10#$respuesta))
	if (( numero == 0 || numero > ${#MENU_RESPALDOS[@]} )); then
		echo "Restauración cancelada."
		menu_cancelar_restauracion
		return 1
	fi
	RESTORE_ARCHIVE="$PROJECT/$BACKUP_DIR_NAME/${MENU_RESPALDOS[numero - 1]}"

	echo "¿Qué contenido quieres restaurar?"
	echo "  1) Archivos y configuración (sobrescribe coincidencias, no borra archivos nuevos)"
	echo "  2) Datos SQL; luego podrás elegir los servicios MySQL"
	echo "  3) Archivos y SQL"
	read -r -p "Opción (1-3, 0 para cancelar): " tipo
	case "$tipo" in
		1) RESTORE_TYPE="archivos" ;;
		2) RESTORE_TYPE="sql" ;;
		3) RESTORE_TYPE="ambos" ;;
		*)
			echo "Restauración cancelada."
			menu_cancelar_restauracion
			return 1
			;;
	esac

	RESTORE_SQL_SERVICES=()
	if [[ "$RESTORE_TYPE" == "sql" || "$RESTORE_TYPE" == "ambos" ]]; then
		if ! tar -tzf "$RESTORE_ARCHIVE" >/dev/null; then
			echo "No se pudo leer la copia seleccionada." >&2
			menu_cancelar_restauracion
			return 1
		fi
		while IFS= read -r miembro; do
			case "$miembro" in
				mysql/*.sql.gz|./mysql/*.sql.gz)
					nombre_servicio="${miembro#./}"
					nombre_servicio="${nombre_servicio#mysql/}"
					nombre_servicio="${nombre_servicio%.sql.gz}"
					servicios_sql+=("$nombre_servicio")
					;;
			esac
		done < <(tar -tzf "$RESTORE_ARCHIVE")

		if (( ${#servicios_sql[@]} == 0 )); then
			echo "La copia no contiene exportaciones SQL de MySQL." >&2
			menu_cancelar_restauracion
			return 1
		fi
		RESTORE_SQL_SERVICES=("${servicios_sql[0]}")
		menu_elegir_elementos RESTORE_SQL_SERVICES "Servicios MySQL a restaurar" "${servicios_sql[@]}" ||
			{ menu_cancelar_restauracion; return 1; }
	fi

	echo "La restauración puede reemplazar archivos o datos actuales."
	[[ "$RESTORE_TYPE" == "sql" || "$RESTORE_TYPE" == "ambos" ]] &&
		echo "El SQL solo se importará en servicios MySQL que permitan escritura."
	read -r -p "Escribe RESTAURAR para confirmar: " confirmacion
	if [[ "$confirmacion" != "RESTAURAR" ]]; then
		menu_cancelar_restauracion
		echo "Restauración cancelada."
		return 1
	fi

	RESTORE_CONFIRMED=1
	echo "Restauración confirmada: ${MENU_RESPALDOS[numero - 1]} ($RESTORE_TYPE)."
}

# Ofrece un menú interactivo para cambiar opciones sin editar configuracion.sh.
menu_aprovisionamiento_interactivo() {
	local opcion
	local -a servicios_disponibles=()
	local -a servicios_mysql_configurados=("${BACKUP_MYSQL_SERVICES[@]}")

	while true; do
		echo
		menu_mostrar_marca
		printf '%s=== Menú de aprovisionamiento ===%s\n' "$MENU_COLOR_BLANCO" "$MENU_COLOR_RESET"
		printf 'Proyecto: %s%s%s\n' "$MENU_COLOR_AZUL" "$PROJECT" "$MENU_COLOR_RESET"
		printf 'Intervalo de respaldo: %s%s%s\n' "$MENU_COLOR_AZUL" "$BACKUP_INTERVAL" "$MENU_COLOR_RESET"
		menu_mostrar_opcion 1 "Elegir carpeta de proyecto en /srv"
		menu_mostrar_opcion 2 "Elegir servicios Docker que iniciar"
		menu_mostrar_opcion 3 "Elegir servicios MySQL que respaldar"
		menu_mostrar_opcion 4 "Restaurar una copia existente"
		menu_mostrar_opcion 5 "Configurar todo y luego elegir una restauración"
		menu_mostrar_opcion 0 "Continuar con la configuración seleccionada"
		read -r -p "Opción: " opcion

		case "$opcion" in
			1)
				menu_elegir_carpeta_proyecto || true
				;;
			2)
				if menu_cargar_servicios_compose; then
					menu_elegir_elementos DOCKER_COMPOSE_SERVICES \
						"Servicios Docker que iniciar" "${MENU_SERVICIOS_COMPOSE[@]}" || true
				fi
				;;
			3)
				menu_elegir_elementos BACKUP_MYSQL_SERVICES \
					"Servicios MySQL configurados para el respaldo" "${servicios_mysql_configurados[@]}" || true
				;;
			4)
				menu_elegir_restauracion || true
				;;
			5)
				menu_elegir_carpeta_proyecto || true
				if menu_cargar_servicios_compose; then
					servicios_disponibles=("${MENU_SERVICIOS_COMPOSE[@]}")
					menu_elegir_elementos DOCKER_COMPOSE_SERVICES \
						"Servicios Docker que iniciar" "${servicios_disponibles[@]}" || true
					menu_elegir_elementos BACKUP_MYSQL_SERVICES \
						"Servicios MySQL configurados para el respaldo" "${servicios_mysql_configurados[@]}" || true
				fi
				menu_elegir_restauracion || true
				;;
			0)
				return 0
				;;
			*)
				echo "Opción no válida. Elige un número del menú."
				;;
		esac
	done
}
