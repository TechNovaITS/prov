# Cambios respecto a prov-main original

## Corrección crítica
- `prov/guiones/crear-respaldo.sh`: la línea 4 tenía una URL pegada (`umask 077https://...`) y el script
  terminaba con error antes de crear cualquier copia. Corregido.

## Respaldo
- Horario fijo diario (`BACKUP_ONCALENDAR`, 02:30) con `Persistent=true`, en lugar de cada 5 minutos.
- Retención escalonada: 7 diarias, 4 semanales, 12 mensuales (antes: 24 copias = 2 horas de historia).
- Copia de volúmenes Docker (`BACKUP_VOLUMES`, por defecto `grafana_data`).
- Suma SHA-256 por copia (`.sha256`) y verificación de cada dump/volumen interno antes de publicar.
- Copia externa opcional verificada (`BACKUP_COPY_DIR`: NAS o USB). Si se configura y no está montada, el servicio falla.
- Servicio systemd endurecido (NoNewPrivileges, ProtectSystem=strict, PrivateTmp, límites de tiempo y prioridad).

## Recuperación
- Nuevos tipos de restauración: `volumenes` y `completo` (servidor nuevo).
- Verifica el SHA-256 antes de tocar nada.
- Recuperación de un servidor sin proyecto previo: el Compose se toma de la propia copia.
- Verificación posterior (estado de contenedores y tablas por base).
- `prov.sh --ayuda`: procedimiento completo de recuperación (escenarios A y B).
- `prov.sh --verificar-respaldo [archivo]`: comprueba integridad y antigüedad (falla si > 26 h).

## Sin cambios
- Cuentas, firewall (módulo 40), servicios opcionales y servicio/timer de arranque del stack.
