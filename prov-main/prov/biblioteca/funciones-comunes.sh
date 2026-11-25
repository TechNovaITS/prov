# Muestra un error en stderr y finaliza el aprovisionamiento con estado de fallo.
# Recibe el mensaje completo para que los módulos informen claramente por qué se detienen.
finalizar_con_error() {
	echo "Error: $*" >&2
	exit 1
}
