# Nombre permanente del servidor. El módulo de nombre de equipo lo aplica con hostnamectl.
HOSTNAME_CUTSA="TechnovaCutsa"
# Carpeta del proyecto, relativa a /srv. Debe contener compose.yaml o docker-compose.yml.
DOCKER_PROJECT_DIR_NAME="Docker-Oficial"
PROJECT="/srv/${DOCKER_PROJECT_DIR_NAME}"
# Lista opcional de servicios Compose que se iniciarán; vacía significa iniciar el proyecto completo.
DOCKER_COMPOSE_SERVICES=()
# Nombre base de las unidades systemd que levantan el proyecto; no incluir la extensión .service o .timer.
DOCKER_SYSTEMD_UNIT="dockercutsa"
# Unidad que programa la eliminación de cuentas locales normales durante el próximo arranque.
REMOVE_USERS_SYSTEMD_UNIT="${DOCKER_SYSTEMD_UNIT}-remove-invoker"

# Horario del respaldo (formato OnCalendar de systemd). Por defecto, todos los días a las 02:30.
# Si se deja vacío, se usa BACKUP_INTERVAL como intervalo fijo desde el arranque.
BACKUP_ONCALENDAR="*-*-* 02:30:00"
# Intervalo entre respaldos cuando BACKUP_ONCALENDAR está vacío. Duración de systemd: 5min, 1h, 1d.
BACKUP_INTERVAL="1d"
# Subcarpeta privada de PROJECT donde se guardan los archivos comprimidos de respaldo.
BACKUP_DIR_NAME="backups"
# Retención escalonada: se conserva la copia más reciente de cada uno de los últimos N días, N semanas y N meses.
BACKUP_KEEP_DAILY=7
BACKUP_KEEP_WEEKLY=4
BACKUP_KEEP_MONTHLY=12
# Servicios Compose de MySQL que se exportan con mysqldump en cada ejecución del temporizador.
BACKUP_MYSQL_SERVICES=("mysql_db" "db_replica" "db_mysql_2")
# Volúmenes Docker (clave tal como aparece en la sección volumes: del Compose) que se copian además de MySQL.
# Grafana guarda ahí sus usuarios y el estado de las alertas; no se reconstruye con docker compose up.
BACKUP_VOLUMES=("grafana_data")
# Carpeta de una copia EXTERNA al servidor (punto de montaje de un NAS o disco USB). Vacío = sin copia externa.
# Si está configurada y no está montada, el servicio de respaldo termina con error para que el fallo se vea.
BACKUP_COPY_DIR=""
# Nombre base de las unidades systemd que ejecutan y programan los respaldos.
BACKUP_SYSTEMD_UNIT="docker-oficial-backup"

# Estado temporal del menú; estos valores solo se completan si se confirma una restauración.
# RESTORE_TYPE: archivos | sql | ambos (archivos + sql) | volumenes | completo (archivos + volúmenes + sql).
RESTORE_ARCHIVE=""
RESTORE_TYPE=""
RESTORE_SQL_SERVICES=()
RESTORE_CONFIRMED=0

# Contraseña de la cuenta sudo; el módulo de cuentas le otorga administración mediante wheel.
PASSWORD_SUDO="sudocutsa"
# Contraseña de la cuenta admin, que se añade al grupo docker para controlar el motor.
PASSWORD_ADMIN="admincutsa"
# Contraseña de la cuenta logger, reservada para tareas relacionadas con registros.
PASSWORD_LOGGER="loggercutsa"
