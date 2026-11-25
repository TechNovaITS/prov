# Recorre las tres cuentas administradas para aplicarles el mismo flujo de creación y contraseña.
for user in sudo admin logger; do
	# Crea la cuenta y su directorio personal únicamente cuando aún no existe.
	if ! id "$user" >/dev/null 2>&1; then
		useradd --create-home "$user"
	fi

	# Asocia cada nombre de cuenta con la contraseña cargada desde configuracion.sh.
	case "$user" in
		sudo) user_password=$PASSWORD_SUDO ;;
		admin) user_password=$PASSWORD_ADMIN ;;
		logger) user_password=$PASSWORD_LOGGER ;;
	esac
	# chpasswd lee la contraseña por stdin para no incluirla como argumento visible del proceso.
	printf '%s:%s\n' "$user" "$user_password" | chpasswd
done

# wheel es el grupo administrativo que habilita el uso de sudo en AlmaLinux.
usermod -aG wheel sudo
