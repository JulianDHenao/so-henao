#!/usr/bin/env bash
set -euo pipefail

ORIGEN="/srv/proyecto/"
DESTINO_BASE="/srv/respaldos"
FECHA="$(date +%Y-%m-%d_%H-%M-%S)"
DESTINO="$DESTINO_BASE/$FECHA"
ACTUAL="$DESTINO_BASE/actual"

mkdir -p "$DESTINO_BASE"

# Si existe un respaldo previo, usamos --link-dest para crear enlaces duros
if [ -L "$ACTUAL" ] && [ -d "$(readlink -f "$ACTUAL")" ]; then
    rsync -aAX --delete --link-dest="$(readlink -f "$ACTUAL")" "$ORIGEN" "$DESTINO/"
else
    rsync -aAX --delete "$ORIGEN" "$DESTINO/"
fi

# Actualizamos el enlace simbólico 'actual' al respaldo recién creado
ln -sfn "$DESTINO" "$ACTUAL"

# Retención: conservar solo las últimas 7 instantáneas
ls -1dt "$DESTINO_BASE"/20* 2>/dev/null | tail -n +8 | xargs -r rm -rf
