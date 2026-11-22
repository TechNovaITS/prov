# Instala OpenSSH y firewalld; una instalación mínima de AlmaLinux podría no incluirlos.
dnf install -y openssh-server firewalld

# Inicia sshd ahora y lo habilita para los siguientes arranques.
systemctl enable --now sshd
# Inicia el cortafuegos antes de aplicar sus reglas.
systemctl enable --now firewalld
# Guarda permanentemente la regla para permitir conexiones SSH.
firewall-cmd --permanent --add-service=ssh
# Permite tráfico web HTTP.
firewall-cmd --permanent --add-service=http
# Permite tráfico web HTTPS.
firewall-cmd --permanent --add-service=https
# Permite las conexiones cliente y administración de ProxySQL.
firewall-cmd --permanent --add-port=6033/tcp
firewall-cmd --permanent --add-port=6034/tcp
# Permite acceso a Grafana, Loki y Prometheus en sus puertos predeterminados.
firewall-cmd --permanent --add-port=3000/tcp
firewall-cmd --permanent --add-port=3100/tcp
firewall-cmd --permanent --add-port=9090/tcp
# Aplica las reglas permanentes sin esperar al próximo reinicio.
firewall-cmd --reload
