#!/usr/bin/env bash
# Asistente de configuración para AlmaLinux 9.8. Ejecutar como root tras revisar estos ajustes.
# Termina inmediatamente si ocurre un error, si se usa una variable no definida o si falla una tubería.
set -euo pipefail

# Calcula la ruta real del directorio que contiene este script.
# Permite ejecutar prov.sh desde cualquier directorio sin romper las rutas relativas.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Carga la función común que informa errores y detiene el aprovisionamiento.
source "$SCRIPT_DIR/biblioteca/funciones-comunes.sh"
# Carga nombres de servicios, rutas, frecuencia de respaldo y credenciales.
source "$SCRIPT_DIR/configuracion.sh"
# Carga el menú que permite cambiar carpeta, servicios y restauración en esta ejecución.
source "$SCRIPT_DIR/biblioteca/menu-interactivo.sh"
# Carga la ayuda del procedimiento de recuperación y la verificación de copias.
source "$SCRIPT_DIR/biblioteca/ayuda-recuperacion.sh"

# Opciones que no aprovisionan nada: se atienden antes de cualquier cambio en el sistema.
case "${1:-}" in
	--ayuda|-h|--help)
		mostrar_ayuda_recuperacion
		exit 0
		;;
	--verificar-respaldo)
		verificar_respaldo "${2:-}"
		exit 0
		;;
	"") ;;
	*) finalizar_con_error "Opción desconocida: $1 (usá --ayuda)." ;;
esac

# En ejecuciones con terminal, permite seleccionar opciones; sin terminal se usan los valores configurados.
if [[ -t 0 && -t 1 ]]; then
	menu_aprovisionamiento_interactivo
fi

# Valida permisos, configuración y carpeta Compose antes de modificar el sistema.
source "$SCRIPT_DIR/modulos/00-validacion-previa.sh"
# Cambia el nombre permanente del equipo.
source "$SCRIPT_DIR/modulos/10-nombre-equipo.sh"
# Crea o actualiza las cuentas sudo, admin y logger.
source "$SCRIPT_DIR/modulos/20-cuentas.sh"
# Configura permisos Docker y arranca el servicio Docker.
source "$SCRIPT_DIR/modulos/30-instalacion-docker.sh"
# Configura SSH y los puertos web permitidos en firewalld.
source "$SCRIPT_DIR/modulos/40-cortafuegos.sh"
# Deshabilita SSSD y NIS solo cuando no parecen estar configurados.
source "$SCRIPT_DIR/modulos/50-servicios-opcionales.sh"
# Si se confirmó una restauración, reemplaza archivos o bases antes de volver a levantar el proyecto.
source "$SCRIPT_DIR/modulos/55-restauracion.sh"
# Instala el servicio Compose y desactiva cualquier tarea antigua de eliminación de cuentas.
source "$SCRIPT_DIR/modulos/60-servicios-systemd.sh"
# Instala el servicio y el temporizador para generar respaldos periódicos.
source "$SCRIPT_DIR/modulos/70-respaldos.sh"
