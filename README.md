# Dev Stack Installer for Ubuntu 24.04 LTS

Script de instalación automatizado para configurar un entorno de desarrollo Laravel/PHP completo en Ubuntu 24.04 LTS.

## 🚀 Características

- **PHP 8.4** con extensiones completas (FPM, GD, XML, ZIP, MySQL, Curl, Intl, Mbstring)
- **MariaDB** con wizard de seguridad interactivo
- **Node.js v24** via NVM (Node Version Manager)
- **Composer** global para gestión de dependencias PHP
- **Laravel Valet Linux** para desarrollo local con dominios `.test`
- **Laravel Installer** para crear proyectos rápidamente

## 📋 Requisitos

- Ubuntu 24.04 LTS (preferido) o Ubuntu 22.04+
- Acceso sudo
- Terminal interactiva (no funciona en modo no-interactivo)
- Mínimo 2GB de espacio en disco

## 🔧 Uso

```bash
git clone https://github.com/LC-jhony/laravel-dev-tools.git
chmod +x install.sh
./install.sh
```

### Flujo del Instalador

El instalador te guiará a través de 6 pasos:

| Step | Descripción |
|------|-------------|
| 1 | **System Check** - Verifica SO, red, disco y detecta paquetes ya instalados |
| 2 | **Select Components** - Muestra componentes a instalar |
| 3 | **Configuration** - Configura versión de Node.js |
| 4 | **Installation Plan** - Muestra plan de instalación y confirma |
| 5 | **Installing** - Ejecuta instalación de todos los componentes |
| 6 | **Summary** - Muestra resumen final con próximos pasos |

## 📦 Paquetes Instalados

| Paquete | Versión | Notas |
|---------|---------|-------|
| PHP | 8.4.x | via ondrej/php PPA |
| MariaDB | latest | incluye secure setup wizard |
| Node.js | 24.x | via NVM (Node Version Manager) |
| Composer | 2.x | instalación global |
| Laravel Valet | latest | cpriego/valet-linux |
| Laravel Installer | latest | via Composer |

## 📁 Estructura del Proyecto

```
install-laravel/
├── install.sh          # Script principal de instalación
└── README.md           # Este archivo
```

## 🎯 Después de la Instalación

1. **Recarga tu shell:**
   ```bash
   source ~/.zshrc    # o source ~/.bashrc
   ```

2. **Crea un nuevo proyecto Laravel:**
   ```bash
   cd ~/Sites
   laravel new myapp
   ```

3. **Accede en tu navegador:**
   ```
   http://myapp.test
   ```

## ⚙️ Configuración de Entorno

El instalador agrega automáticamente a tu `~/.zshrc` o `~/.bashrc`:

```bash
# Composer PATH
export PATH="$HOME/.config/composer/vendor/bin:$PATH"

# NVM - Node Version Manager
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
```

## 📝 Notas

- **Logs de instalación:** `/tmp/ubuntu-dev-installer-<timestamp>.log`
- **Directorio de proyectos Valet:** `~/Sites`
- **Dominios locales:** `*.test`

## 🔍 Solución de Problemas

### Error: "Valet home directory is inside /root"
Esto ocurre cuando Valet se ejecuta con sudo y HOME cambia a /root.
**Solución:** El script usa `sudo -E HOME="$HOME"` para preservar el HOME del usuario.

### Error: "setlocale: LC_ALL: cannot change locale"
Advertencia inofensiva, el instalador funciona correctamente.

### Ver logs de instalación
```bash
# Ver último log
ls -lt /tmp/ubuntu-dev-installer-*.log | head -1

# Ver contenido
tail -f /tmp/ubuntu-dev-installer-<timestamp>.log
```

### Reinstalar componentes específicos
```bash
# Composer
composer global require cpriego/valet-linux

# Laravel Valet
cd ~/Sites
valet install
valet park

# Laravel Installer
composer global require laravel/installer
```

## 📄 Licencia

MIT License
