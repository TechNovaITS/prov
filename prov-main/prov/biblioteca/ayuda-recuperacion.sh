# Ayuda en pantalla: respaldo y procedimiento de recuperación ante desastres.
mostrar_ayuda_recuperacion() {
	cat <<'AYUDA'
PROV.SH - RESPALDO Y RECUPERACIÓN ANTE DESASTRES

Uso:
  sudo bash prov.sh                     Aprovisiona el servidor (con menú si hay terminal).
  sudo bash prov.sh --verificar-respaldo [archivo]
                                        Comprueba la copia más reciente (o la indicada): SHA-256, gzip, tar
                                        y antigüedad. Código de salida distinto de 0 si algo falla.
  sudo bash prov.sh --ayuda             Muestra esta ayuda.

QUÉ SE RESPALDA (automático, systemd timer)
  - Archivos del proyecto (compose.yaml, .env, configuración, código).
  - Volúmenes Docker listados en BACKUP_VOLUMES (por defecto, Grafana).
  - Dump lógico de cada servicio de BACKUP_MYSQL_SERVICES.
  Destino: <proyecto>/backups/docker-backup-AAAAMMDDTHHMMSSZ.tar.gz (+ .sha256), modo 0600.
  Retención: 7 diarias, 4 semanales y 12 mensuales (ver configuracion.sh).
  Copia externa opcional: BACKUP_COPY_DIR (NAS o disco USB montado).

ESCENARIO A - Error de datos o de configuración (el servidor sigue vivo)
  1. sudo bash prov.sh --verificar-respaldo         (confirmar que la copia sirve)
  2. sudo bash prov.sh  ->  opción 4  ->  elegir la copia  ->  tipo 1, 2, 3 o 4  ->  escribir RESTAURAR.
  3. Revisar el estado final que imprime el módulo (contenedores y cantidad de tablas).

ESCENARIO B - Pérdida total del servidor (servidor nuevo)
  1. Instalar AlmaLinux 9 e instalar los scripts de prov (este directorio).
  2. Editar configuracion.sh (mismas contraseñas, nombre del proyecto y servicios que el servidor original).
  3. Crear la carpeta de copias y traer la copia desde el NAS/USB o desde donde esté guardada:
       sudo install -d -m 0700 /srv/<proyecto>/backups
       sudo cp docker-backup-XXXX.tar.gz docker-backup-XXXX.tar.gz.sha256 /srv/<proyecto>/backups/
  4. sudo bash prov.sh  ->  opción 4  ->  elegir la copia  ->  tipo 5 (completo)  ->  escribir RESTAURAR.
     El script instala Docker, cuentas y firewall; restaura archivos, volúmenes y SQL; levanta el stack.
  5. Verificar: aplicación web, Grafana (dashboards y alertas), tablas de MySQL y estado de réplicas.

NOTAS
  - Las copias contienen el .env con contraseñas: guardarlas solo en almacenamiento protegido.
  - Las imágenes Docker no se respaldan: se descargan de nuevo con las versiones fijadas en compose.yaml.
  - La restauración SQL solo se hace en servicios que permiten escritura (nodo principal); las réplicas
    se vuelven a sincronizar solas o, si no, con el procedimiento de réplica del proyecto.
  - Probar la recuperación de punta a punta al menos una vez por trimestre.
AYUDA
}

# Comprueba una copia sin restaurarla: integridad, estructura y antigüedad (alerta si supera 26 horas).
verificar_respaldo() {
	local archivo="${1:-}" directorio="$PROJECT/$BACKUP_DIR_NAME" miembro edad_horas marca
	[[ $EUID -eq 0 ]] || finalizar_con_error "Ejecutá como root: sudo bash $0 --verificar-respaldo"
	if [[ -z "$archivo" ]]; then
		archivo="$(find "$directorio" -mindepth 1 -maxdepth 1 -type f -name 'docker-backup-*.tar.gz' 2>/dev/null | sort | tail -1)"
		[[ -n "$archivo" ]] || finalizar_con_error "No hay copias en $directorio."
	fi
	[[ -f "$archivo" ]] || finalizar_con_error "No existe el archivo $archivo."
	echo "Copia: $archivo"

	if [[ -f "$archivo.sha256" ]]; then
		( cd "$(dirname "$archivo")" && sha256sum -c "$(basename "$archivo").sha256" ) ||
			finalizar_con_error "SHA-256 incorrecto."
	else
		echo "Advertencia: no hay archivo .sha256."
	fi
	gzip -t "$archivo" || finalizar_con_error "El archivo gzip está dañado."
	tar -tzf "$archivo" >/dev/null || finalizar_con_error "El índice tar está dañado."
	while IFS= read -r miembro; do
		case "$miembro" in
			mysql/*.sql.gz|./mysql/*.sql.gz|volumes/*.tar.gz|./volumes/*.tar.gz)
				tar -xOzf "$archivo" "$miembro" | gzip -t || finalizar_con_error "Dañado: $miembro"
				echo "  OK  $miembro"
				;;
		esac
	done < <(tar -tzf "$archivo")

	marca="$(stat -c %Y "$archivo")"
	edad_horas=$(( ( $(date +%s) - marca ) / 3600 ))
	echo "Antigüedad: ${edad_horas} h"
	if (( edad_horas > 26 )); then
		finalizar_con_error "La última copia tiene más de 26 horas: el respaldo diario no se está ejecutando."
	fi
	echo "Verificación correcta."
}
