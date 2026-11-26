# so-henao — Mi servidor en producción

## Qué es
Servidor Ubuntu (`enfasis`) configurado en producción que ejecuta el servicio web de estado del sistema (`estado.service` en el puerto `8082`), una réplica aislada en contenedor Docker (`estado-c` publicada únicamente en `127.0.0.1:8081`), respaldos incrementales automáticos con enlaces duros sobre LVM (`/srv/respaldos`) y endurecimiento auditado con Lynis. Acceso administrativo mediante `ssh -p 2222 user@127.0.0.1` con autenticación por llave pública.

## Estructura del repositorio
- `config/`: `10-endurecimiento.conf` (SSH), `beto` (`sudoers`) y `hardening.conf` (`systemd` drop-in).
- `docs/`: `lynis-linea-base.txt` y `lynis-final.txt` (evidencias de auditoría antes y después).
- `scripts/`: `contenedor.sh`, `estado.py` y `respaldo.sh`.
- `systemd/`: `estado.service`, `respaldo.service` y `respaldo.timer`.

## Reconstruir desde cero
1. **Instalación y SSH:** Instalar Ubuntu Server actualizado y configurar acceso SSH mediante llaves públicas (`~/.ssh/authorized_keys`).
2. **Usuarios, grupos, permisos y `sudo`:**
   - Crear el grupo colaborativo `proyecto` (`sudo groupadd -f proyecto`) y los usuarios `beto`, `carla` y `elena`, agregando a `beto` y `user` al grupo `proyecto`.
   - Crear `/srv/proyecto/codigo` con propietario `root:proyecto`, permisos `2770` (bit SGID) y ACLs inmediatas y por defecto (`g:proyecto:rwx`, `u:carla:rx`).
   - Copiar `config/beto` a `/etc/sudoers.d/beto`, asignar `sudo chmod 440 /etc/sudoers.d/beto` y validar sintaxis con `sudo visudo -c`.
3. **Servicio `estado` endurecido (`systemd`):**
   - Crear `/opt/estado`, copiar `scripts/estado.py` a `/opt/estado/estado.py` y darle permisos `755`.
   - Copiar `systemd/estado.service` a `/etc/systemd/system/estado.service` y `config/hardening.conf` a `/etc/systemd/system/estado.service.d/hardening.conf`.
   - Recargar y habilitar: `sudo systemctl daemon-reload && sudo systemctl enable --now estado`.
4. **Discos, LVM, `fstab` y respaldos incrementales:**
   - Inicializar los dos discos de 2 GB (`pvcreate /dev/sdb /dev/sdc`), crear el grupo de volúmenes `datos` (`vgcreate datos /dev/sdb /dev/sdc`) y el volumen lógico `respaldos` de 2.5 GB (`lvcreate -L 2.5G -n respaldos datos`), formateado en `ext4` (`mkfs.ext4 /dev/datos/respaldos`).
   - Obtener el UUID con `blkid -s UUID -o value /dev/datos/respaldos` y agregar en `/etc/fstab`:
     `UUID=<UUID> /srv/respaldos ext4 defaults,nodev,nosuid,noexec 0 2`
   - Montar con `sudo mkdir -p /srv/respaldos && sudo mount -a`.
   - Copiar `scripts/respaldo.sh` a `/usr/local/sbin/respaldo.sh` (`sudo chmod 750 /usr/local/sbin/respaldo.sh`) y copiar `systemd/respaldo.service` y `systemd/respaldo.timer` a `/etc/systemd/system/`.
   - Activar programación horaria: `sudo systemctl daemon-reload && sudo systemctl enable --now respaldo.timer`.
5. **Contenedor aislado (`estado-c`):**
   - Ejecutar `sudo bash scripts/contenedor.sh` para desplegar `python:3.12-alpine` como usuario `65534:65534` (`nobody`), sistema de archivos `--read-only`, `--cap-drop=ALL`, `--security-opt=no-new-privileges`, límite `--memory=128m` y puerto `127.0.0.1:8081:8082`.
6. **Hardening:**
   - Instalar `libpam-tmpdir` y `apt-show-versions`.
   - Copiar `config/10-endurecimiento.conf` a `/etc/ssh/sshd_config.d/10-endurecimiento.conf`, validar con `sudo sshd -t` y reiniciar `sudo systemctl restart ssh`.

## Comprobar que funciona
- `sudo -l -U beto` → `(root) NOPASSWD: /usr/bin/systemctl restart ssh`
- `ls -ld /srv/proyecto` → `drwxrws---+` con grupo `proyecto`
- `systemctl is-enabled estado` → `enabled`
- `sudo systemctl kill -s KILL estado && sleep 2 && systemctl is-active estado` → `active`
- `systemd-analyze security estado --no-pager | tail -1` → `4.7 OK` (< 7.0)
- `systemctl show estado -p MemoryMax -p TasksMax` → `MemoryMax=67108864`, `TasksMax=16`
- `sudo lvs datos && sudo vgs datos` → LV `respaldos` en `2,50g` y VG `datos` con `1,49g` libres (`VFree > 0`)
- `findmnt -no OPTIONS /srv/respaldos` → `rw,nosuid,nodev,noexec,relatime`
- `systemctl list-timers respaldo.timer --no-pager` → `respaldo.timer` activo activando `respaldo.service`
- `sudo docker exec estado-c id` → `uid=65534(nobody) gid=65534(nobody)`
- `sudo docker stats --no-stream estado-c` → límite de `128MiB`
- `curl -s http://127.0.0.1:8081/ | head -3` → HTML con `Estado: OK`
- `curl -s http://127.0.0.1:8082/` → HTML de `estado.service` con `Servidor: enfasis` y `Estado: OK`

## SUID encontrados
Al ejecutar `sudo find / -xdev -perm -4000 -type f 2>/dev/null | grep -Ev '^/usr/(bin|lib)/'` no se encontraron binarios SUID fuera de las rutas estándar del sistema (`/usr/bin` y `/usr/lib`).

## Hardening
Auditoría ejecutada con `sudo lynis audit system --quick`. El índice de endurecimiento subió de **59** (`docs/lynis-linea-base.txt`) a **62** (`docs/lynis-final.txt`).

### Cambio 1: DEB-0280 (`libpam-tmpdir`)
- **Qué se cambió:** Instalación del módulo PAM `libpam-tmpdir`.
- **Por qué:** Crea un directorio temporal `/tmp` aislado por cada sesión de usuario, mitigando ataques de lectura no autorizada o condición de carrera sobre archivos temporales compartidos.
- **Cómo se comprobó:** Verificando en `docs/lynis-final.txt` la eliminación de la sugerencia `DEB-0280`.

### Cambio 2: PKGS-7394 (`apt-show-versions`)
- **Qué se cambió:** Instalación de la utilidad `apt-show-versions`.
- **Por qué:** Permite auditar con precisión qué paquetes instalados en el servidor tienen actualizaciones o parches de seguridad pendientes.
- **Cómo se comprobó:** Ejecutando `apt-show-versions` y verificando el cierre de `PKGS-7394` en `docs/lynis-final.txt`.

### Cambio 3: SSH-7408 (Endurecimiento de OpenSSH)
- **Qué se cambió:** Creación de `/etc/ssh/sshd_config.d/10-endurecimiento.conf` (`config/10-endurecimiento.conf`) con `MaxAuthTries 3`, `X11Forwarding no`, `LogLevel VERBOSE` y `ClientAliveCountMax 2`.
- **Por qué:** Limita los intentos de fuerza bruta por conexión, desactiva el reenvío gráfico innecesario en servidor, registra huellas de autenticación detalladas en `auth.log` y cierra sesiones inactivas sin afectar el reenvío de puertos TCP.
- **Cómo se comprobó:** Validando la configuración con `sudo sshd -t`, reiniciando el servicio `ssh` y confirmando el incremento del `hardening_index` de `59` a `62` en `docs/lynis-final.txt`.
