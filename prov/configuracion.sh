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

# Intervalo entre respaldos. Usa una duración de systemd, por ejemplo 5min, 1h o 1d.
BACKUP_INTERVAL="5min"
# Subcarpeta privada de PROJECT donde se guardan los archivos comprimidos de respaldo.
BACKUP_DIR_NAME="backups"
# Máximo de copias completas que se conservarán; con 5min, 24 copias representan unas 2 horas.
BACKUP_RETENTION_COUNT=24
# Servicios Compose de MySQL que se exportan con mysqldump en cada ejecución del temporizador.
BACKUP_MYSQL_SERVICES=("mysql_db" "db_replica" "db_mysql_2")
# Nombre base de las unidades systemd que ejecutan y programan los respaldos.
BACKUP_SYSTEMD_UNIT="docker-oficial-backup"

# Estado temporal del menú; estos valores solo se completan si se confirma una restauración.
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
