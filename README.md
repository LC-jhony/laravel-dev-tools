# Dev Stack Installer for Ubuntu 24.04 LTS v1.0

Script de instalación automatizado y visual para configurar un entorno de desarrollo Laravel/PHP completo en Ubuntu 24.04 LTS y WSL.

## 🚀 Características

- **PHP 8.4** con extensiones completas (FPM, GD, XML, ZIP, MySQL, SQLite3, Intl, Mbstring, etc.)
- **MariaDB** con wizard de seguridad interactivo (root password, remove anon users, etc.)
- **Node.js (Configurable)** via NVM (Node Version Manager). Default: v22.
- **Composer 2.x** instalación global con auto-update.
- **Laravel Valet Linux** (`cpriego/valet-linux`) para desarrollo local con dominios `.test`.
- **Laravel Installer** con sistema de **4 niveles de fallback** para garantizar la instalación.
- **Soporte WSL:** Detección automática y compatibilidad con `service` management.
- **Interfaz Visual:** Dashboard con barras de progreso, colores y logs en tiempo real.

## 📋 Requisitos

- **Ubuntu 24.04 LTS** (preferido), Ubuntu 22.04+ o **WSL2**.
- Acceso sudo.
- Terminal interactiva (soporta bash 4.0+).
- Conexión a internet.

## 🔧 Uso

```bash
git clone https://github.com/LC-jhony/laravel-dev-tools.git
cd laravel-dev-tools
chmod +x install.sh
./install.sh
```

### Flujo del Instalador

El instalador v3.0 utiliza un tablero visual y sigue estos pasos:

| Paso | Descripción |
|------|-------------|
| 1 | **System Check** - Verifica SO, red, y detecta paquetes ya instalados. |
| 2 | **Smart Skip** - Opción para omitir componentes ya presentes en el sistema. |
| 3 | **Configuración** - Permite elegir la versión de Node.js a instalar. |
| 4 | **Confirmación** - Muestra el plan final antes de realizar cambios. |
| 5 | **Instalación** - Ejecución automatizada con barra de progreso y logs. |
| 6 | **Resumen** - Reporte final de versiones instaladas y próximos pasos. |

## 📦 Paquetes y Versiones

| Componente | Versión | Método |
|------------|---------|--------|
| PHP | 8.4.x | PPA ondrej/php |
| MariaDB | Latest | Apt (incluye hardening wizard) |
| Node.js | v22 (def) | NVM (Node Version Manager) |
| Composer | 2.x | Global binary |
| Laravel Valet | Latest | Composer (Valet Linux) |
| Laravel Installer| Latest | Composer / Isolated / PHAR fallback |

## 🎯 Después de la Instalación

1. **Recarga tu configuración de shell:**
   ```bash
   source ~/.zshrc    # si usas Zsh
   source ~/.bashrc   # si usas Bash
   ```

2. **Crea un nuevo proyecto Laravel:**
   ```bash
   cd ~/Sites
   laravel new myapp
   ```

3. **Accede en tu navegador:**
   `http://myapp.test`

## ⚙️ Configuración Automática

El script detecta y configura automáticamente tu `~/.zshrc` o `~/.bashrc`:

```bash
# Composer PATH
export PATH="$HOME/.config/composer/vendor/bin:$PATH"

# NVM - Node Version Manager
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
```

## 📝 Notas e Información Útil

- **Logs de instalación:** `/tmp/dev-stack-<timestamp>.log`
- **Directorio de proyectos:** El instalador crea y configura `~/Sites` automáticamente.
- **WSL:** Si usas WSL, el resumen final te mostrará los comandos para iniciar servicios manualmente si es necesario.

## 🔍 Solución de Problemas

### Error en Laravel Installer
El script intentará 4 métodos diferentes (Normal -> dependencies -> isolated -> PHAR). Si todos fallan, revisa el log.

### Logs detallados
Para ver exactamente qué falló durante la instalación:
```bash
# Ver el log más reciente
ls -lt /tmp/dev-stack-*.log | head -1 | awk '{print $NF}' | xargs cat
```

### Permisos de Valet
El script intenta corregir permisos automáticamente (`chown` al usuario actual) para evitar errores de "Valet home directory is inside /root".

## 📄 Licencia

MIT License
