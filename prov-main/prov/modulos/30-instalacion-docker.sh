# Confirma que el sistema usa el gestor de paquetes previsto para AlmaLinux.
command -v dnf >/dev/null 2>&1 ||
	finalizar_con_error "Este módulo requiere AlmaLinux 9 y el gestor de paquetes dnf."

# Instala las herramientas necesarias para administrar repositorios de terceros.
dnf install -y dnf-plugins-core

# Docker proporciona el repositorio oficial compatible con sistemas basados en RHEL.
# La comprobación evita recrear el archivo del repositorio cuando el script se ejecuta otra vez.
if [[ ! -f /etc/yum.repos.d/docker-ce.repo ]]; then
	dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
fi

# Instala Docker Engine, el CLI, containerd y los complementos oficiales de Compose y Buildx.
dnf install -y \
	docker-ce \
	docker-ce-cli \
	containerd.io \
	docker-buildx-plugin \
	docker-compose-plugin \
	tar \
	gzip \
	util-linux

# Guarda la ruta de Docker para que el módulo de systemd pueda crear el servicio Compose.
DOCKER_BIN="$(command -v docker)"
[[ -n "$DOCKER_BIN" ]] || finalizar_con_error "Docker se instaló, pero no se encontró el ejecutable docker."

# Crea el grupo compartido o conserva su configuración si ya existe.
groupadd --force dockercutsa
# Otorga a las cuentas administradas acceso de lectura y escritura al proyecto compartido.
for user in sudo admin logger; do
	usermod -aG dockercutsa "$user"
done

# admin puede controlar Docker; pertenecer al grupo docker equivale prácticamente a acceso administrativo.
# Garantiza que el grupo exista incluso si la instalación no lo creó por algún motivo.
groupadd --force docker
usermod -aG docker admin
# Crea el directorio del proyecto con permisos del grupo y el bit setgid.
# setgid hace que los archivos nuevos hereden el grupo dockercutsa.
install -d -o root -g dockercutsa -m 2775 "$PROJECT"
# Arranca Docker ahora y lo habilita para iniciar durante futuros arranques.
systemctl enable --now docker
