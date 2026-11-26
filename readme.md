\# so-henao — Mi servidor en producción



\## Qué es

Servidor Ubuntu en producción que ejecuta el servicio web de estado (`estado.service` en el puerto `8082`), una réplica aislada en contenedor Docker (`estado-c` en `127.0.0.1:8081`), respaldos incrementales automáticos sobre LVM (`/srv/respaldos`) y endurecimiento auditado con Lynis. Acceso mediante `ssh user@<IP>` (o alias `ssh srv`).



\## Reconstruir desde cero

1\. \*\*Instalación y SSH con llaves:\*\* Ubuntu Server actualizado con acceso SSH configurado mediante llaves públicas.

2\. \*\*Usuarios, grupos, `/srv/proyecto` y `sudo`:\*\* Creación del grupo `proyecto`, usuarios `beto` y `carla`, regla en `config/beto` (`/etc/sudoers.d/beto`) limitando `sudo` exclusivamente a `/usr/bin/systemctl restart ssh`, y carpeta `/srv/proyecto` con permisos `2770` (SGID) y ACLs por defecto.

3\. \*\*Servicio `estado` endurecido:\*\* Aplicación `scripts/estado.py` en `/opt/estado/estado.py`, unidad `systemd/estado.service` corriendo como `nobody` con reinicio automático (`Restart=always`) y drop-in `config/hardening.conf` (`MemoryMax=64M`, `TasksMax=16`, `ProtectSystem=strict`).

4\. \*\*Discos, LVM, `fstab` y respaldos:\*\* Dos discos de 2 GB (`sdb` y `sdc`) integrados en el VG `datos` con LV `respaldos` (2.5 GB, dejando \~1.49 GB libres en `VFree`), montado en `/srv/respaldos` por UUID con `defaults,nodev,nosuid,noexec`. Respaldo incremental mediante `scripts/respaldo.sh` (`rsync -aAX --link-dest`) programado cada hora con `systemd/respaldo.service` y `systemd/respaldo.timer`.

5\. \*\*Contenedor aislado (`estado-c`):\*\* Desplegado mediante `scripts/contenedor.sh` con `--user 65534:65534`, `--read-only`, `--cap-drop=ALL`, `--security-opt=no-new-privileges`, `--memory=128m` y publicado únicamente en `127.0.0.1:8081`.



\## Comprobar que funciona

\- `sudo -l -U beto` → `(root) NOPASSWD: /usr/bin/systemctl restart ssh`

\- `ls -ld /srv/proyecto` → `drwxrws---+`

\- `systemctl is-enabled estado` → `enabled`

\- `sudo systemctl kill -s KILL estado \&\& sleep 2 \&\& systemctl is-active estado` → `active`

\- `systemd-analyze security estado --no-pager | tail -1` → `4.7 OK` (< 7.0)

\- `systemctl show estado -p MemoryMax -p TasksMax` → `MemoryMax=67108864`, `TasksMax=16`

\- `sudo lvs datos \&\& sudo vgs datos` → LV `respaldos` en `2,50g` y VG `datos` con `VFree` de `1,49g`

\- `findmnt -no OPTIONS /srv/respaldos` → `rw,nosuid,nodev,noexec,relatime`

\- `systemctl list-timers respaldo.timer --no-pager` → Timer activo apuntando a `respaldo.service`

\- `sudo docker exec estado-c id` → `uid=65534(nobody) gid=65534(nobody)`

\- `sudo docker stats --no-stream estado-c` → Límite de `128MiB`

\- `curl -s http://127.0.0.1:8081/ | head -3` → HTML con `Estado: OK`



\## SUID encontrados

Al ejecutar `sudo find / -xdev -perm -4000 -type f 2>/dev/null | grep -Ev '^/usr/(bin|lib)/'` no se encontraron binarios SUID fuera de las rutas estándar del sistema (`/usr/bin` y `/usr/lib`).



\## Hardening

Índice de Lynis: línea base \*\*59\*\* → final \*\*62\*\* (`docs/lynis-linea-base.txt` y `docs/lynis-final.txt`).



\### Cambio 1: DEB-0280 (`libpam-tmpdir`)

\- \*\*Qué se cambió:\*\* Se instaló el paquete `libpam-tmpdir`.

\- \*\*Por qué:\*\* Asigna un directorio `/tmp` privado y aislado por cada sesión de usuario, mitigando ataques de condición de carrera o lectura de archivos temporales compartidos.

\- \*\*Cómo se comprobó:\*\* Verificando que la sugerencia `DEB-0280` desapareció en `docs/lynis-final.txt` y comprobando la variable `$TMPDIR` en sesión.



\### Cambio 2: PKGS-7394 (`apt-show-versions`)

\- \*\*Qué se cambió:\*\* Se instaló `apt-show-versions`.

\- \*\*Por qué:\*\* Permite auditar de forma rápida y precisa qué paquetes instalados tienen actualizaciones de seguridad pendientes.

\- \*\*Cómo se comprobó:\*\* Ejecutando `apt-show-versions -u` y verificando el cierre de `PKGS-7394` en `docs/lynis-final.txt`.



\### Cambio 3: SSH-7408 (Endurecimiento del demonio SSH)

\- \*\*Qué se cambió:\*\* Se creó `/etc/ssh/sshd\_config.d/10-endurecimiento.conf` (`config/10-endurecimiento.conf`) con `MaxAuthTries 3`, `X11Forwarding no`, `LogLevel VERBOSE` y `ClientAliveCountMax 2`.

\- \*\*Por qué:\*\* Reduce la ventana de ataques de fuerza bruta, desactiva el reenvío gráfico innecesario, registra huellas de llaves en los logs de autenticación y cierra sesiones inactivas sin bloquear el reenvío de puertos TCP necesario para la administración.

\- \*\*Cómo se comprobó:\*\* Validando sintaxis con `sudo sshd -t`, reiniciando `ssh` y confirmando el incremento del índice de Lynis a \*\*62\*\*.

