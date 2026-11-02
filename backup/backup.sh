#!/bin/sh
# Backup diário da VPS (container db-backup, cron às 06:00 UTC). À mão: docker exec db-backup backup.sh
#
# 1. pg_dump -Fc de cada container em BACKUP_POSTGRES, pelo docker exec (usa o usuário e o banco do
#    próprio container, sem senha aqui). Cada dump passa no pg_restore --list antes de valer.
# 2. Volume da sessão da Evolution (/sources/evolution-instances) e os .env de /opt/* (/sources/opt).
# 3. Guarda em /backups/daily/AAAA-MM-DD; no domingo, uma cópia em /backups/weekly. Retenção:
#    BACKUP_KEEP_DAILY dias e BACKUP_KEEP_WEEKLY semanas.
# 4. Copia daily/ e weekly/ para BACKUP_REMOTE (remote crypt do rclone: tudo sobe criptografado) e
#    apaga lá o que passou da retenção. Sem remote configurado: backup.offsite_skipped.
#
# Logs em JSON no stdout (backup.done, backup.failed, backup.offsite, backup.offsite_skipped,
# backup.finished), base dos alertas em grafana/provisioning/alerting/backup.yml.
set -u

ROOT=/backups
DAY=$(date -u +%Y-%m-%d)
DIR=$ROOT/daily/$DAY
KEEP_DAILY=${BACKUP_KEEP_DAILY:-7}
KEEP_WEEKLY=${BACKUP_KEEP_WEEKLY:-4}
RCLONE_CONFIG=/config/rclone/rclone.conf
export RCLONE_CONFIG
ERRDIR=$(mktemp -d)
trap 'rm -rf "$ERRDIR"' EXIT
failures=0
started=$(date +%s)

log() { # nível, evento, contexto em JSON
    printf '{"datetime":"%s","channel":"backup","level_name":"%s","message":"%s","context":%s}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$3"
}

fail() { # alvo, arquivo com o erro
    err=$(head -c 300 "$2" 2>/dev/null | tr '\n"\\\t' '    ')
    failures=$((failures + 1))
    log ERROR backup.failed "{\"target\":\"$1\",\"error\":\"$err\"}"
}

done_ok() { # alvo, tipo, arquivo, início
    log INFO backup.done "{\"target\":\"$1\",\"kind\":\"$2\",\"bytes\":$(stat -c %s "$3"),\"s\":$(($(date +%s) - $4))}"
}

dump_postgres() {
    c=$1
    out=$DIR/$c.dump
    err=$ERRDIR/$c.err
    t=$(date +%s)
    if docker exec "$c" sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$out.tmp" 2> "$err" \
        && [ -s "$out.tmp" ] && pg_restore --list "$out.tmp" > /dev/null 2>> "$err"; then
        mv "$out.tmp" "$out"
        done_ok "$c" postgres "$out" "$t"
    else
        rm -f "$out.tmp"
        fail "$c" "$err"
    fi
    rm -f "$err"
}

archive() { # alvo, arquivo de saída, diretório base, caminhos...
    target=$1 out=$2 base=$3
    shift 3
    err=$ERRDIR/$target.err
    t=$(date +%s)
    if tar -czf "$out" -C "$base" "$@" 2> "$err"; then
        done_ok "$target" files "$out" "$t"
    else
        rm -f "$out"
        fail "$target" "$err"
    fi
    rm -f "$err"
}

prune() { # pasta, quantos ficam
    ls -1d "$1"/*/ 2>/dev/null | sort -r | tail -n +$(($2 + 1)) | while read -r old; do rm -rf "$old"; done
}

prune_remote() { # pasta no remote, idade mínima
    # weekly/ só existe depois do primeiro domingo: pasta que não existe não tem o que apagar.
    rclone lsf "$BACKUP_REMOTE/$1" --max-depth 1 > /dev/null 2>&1 || return 0
    rclone delete "$BACKUP_REMOTE/$1" --min-age "$2"
}

mkdir -p "$DIR"
chmod 700 "$ROOT"

for c in ${BACKUP_POSTGRES:-}; do
    dump_postgres "$c"
done

if [ -d /sources/evolution-instances ]; then
    archive evolution-instances "$DIR/evolution-instances.tar.gz" /sources evolution-instances
fi

if [ -d /sources/opt ]; then
    envs=$(cd /sources/opt && ls -1 ./*/.env 2>/dev/null)
    # shellcheck disable=SC2086
    [ -n "$envs" ] && archive env-files "$DIR/env-files.tar.gz" /sources/opt $envs
fi

chmod -R go-rwx "$DIR"

if [ "$(date -u +%u)" = 7 ]; then
    mkdir -p "$ROOT/weekly"
    rm -rf "$ROOT/weekly/$DAY"
    cp -r "$DIR" "$ROOT/weekly/$DAY"
fi
prune "$ROOT/daily" "$KEEP_DAILY"
prune "$ROOT/weekly" "$KEEP_WEEKLY"

offsite=false
if [ -n "${BACKUP_REMOTE:-}" ] && [ -s "$RCLONE_CONFIG" ]; then
    t=$(date +%s)
    err=$ERRDIR/offsite.err
    if rclone copy "$ROOT" "$BACKUP_REMOTE" --include '/daily/**' --include '/weekly/**' 2> "$err" \
        && prune_remote daily "$((KEEP_DAILY + 1))d" 2>> "$err" \
        && prune_remote weekly "$((KEEP_WEEKLY * 7 + 8))d" 2>> "$err"; then
        rclone rmdirs "$BACKUP_REMOTE" --leave-root 2> /dev/null
        offsite=true
        log INFO backup.offsite "{\"remote\":\"${BACKUP_REMOTE%%:*}\",\"s\":$(($(date +%s) - t))}"
    else
        fail offsite "$err"
    fi
    rm -f "$err"
else
    log WARNING backup.offsite_skipped '{"reason":"sem BACKUP_REMOTE ou rclone.conf"}'
fi

log INFO backup.finished "{\"day\":\"$DAY\",\"failures\":$failures,\"offsite\":$offsite,\"s\":$(($(date +%s) - started))}"
[ "$failures" -eq 0 ]
