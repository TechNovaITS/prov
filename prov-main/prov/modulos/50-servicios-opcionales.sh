# Conserva SSSD cuando hay archivos de configuración o NSS lo utiliza para resolver cuentas.
if [[ ! -s /etc/sssd/sssd.conf ]] &&
	! find /etc/sssd/conf.d -maxdepth 1 -type f -name '*.conf' -print -quit 2>/dev/null | grep -q . &&
	! grep -Eq '^[[:space:]]*(passwd|group|shadow|services|netgroup|automount):.*[[:space:]]sss([[:space:]]|$)' /etc/nsswitch.conf; then
	# En equipos sin configuración SSSD, desactiva el servicio si existe; su ausencia no es un error.
	systemctl disable --now sssd.service >/dev/null 2>&1 || true
fi

# Conserva NIS si hay un dominio, una fuente NSS, configuración de yp.conf o ypbind activo.
if ! grep -Eq '^[[:space:]]*NISDOMAIN=[^[:space:]#]+' /etc/sysconfig/network 2>/dev/null &&
	! grep -Eq '^[[:space:]]*(passwd|group|shadow|hosts|netgroup|automount):.*[[:space:]](nis|yp)([[:space:]]|$)' /etc/nsswitch.conf &&
	! grep -Eq '^[[:space:]]*[^#[:space:]]' /etc/yp.conf 2>/dev/null &&
	! systemctl is-active --quiet ypbind.service; then
	# Deshabilita solo los servicios NIS disponibles; algunas instalaciones no incluyen todos.
	for nis_service in nis-domainname.service ypbind.service yppasswdd.service ypserv.service ypxfrd.service; do
		systemctl disable --now "$nis_service" >/dev/null 2>&1 || true
	done
fi
