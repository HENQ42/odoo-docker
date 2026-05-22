#!/usr/bin/env bash
#
# Instala (ou atualiza) o módulo zabbix_helpdesk_bridge em uma base
# específica do Odoo rodando no container deste docker-compose.
#
# Uso:
#   ./scripts/install_zabbix_helpdesk_bridge.sh
#
# Variáveis (podem vir do ambiente, do .env ou ser passadas inline):
#   DB_NAME           obrigatório  nome da base alvo
#   CONTAINER         opcional     default: odoo_app
#   MODULE            opcional     default: zabbix_helpdesk_bridge
#   ACTION            opcional     install | upgrade   (default: auto-detect)
#   ODOO_CONF         opcional     default: /tmp/odoo.conf (gerado pelo entrypoint)
#   DOCKER            opcional     default: "docker" (use "sudo docker" se necessário;
#                                  o script tenta detectar automaticamente)
#
# Exemplos:
#   DB_NAME=producao ./scripts/install_zabbix_helpdesk_bridge.sh
#   DB_NAME=producao ACTION=upgrade ./scripts/install_zabbix_helpdesk_bridge.sh
#   DB_NAME=producao CONTAINER=odoo_app ./scripts/install_zabbix_helpdesk_bridge.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Carrega .env do projeto, mas sem sobrescrever variáveis já definidas
# pelo ambiente (CLI tem precedência sobre o arquivo).
if [[ -f "${PROJECT_DIR}/.env" ]]; then
    while IFS= read -r line || [[ -n "${line}" ]]; do
        # ignora comentários e linhas vazias
        [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
        # precisa ter formato KEY=VALUE
        [[ "${line}" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        # remove aspas externas se houver
        [[ "${value}" =~ ^\"(.*)\"$ ]] && value="${BASH_REMATCH[1]}"
        [[ "${value}" =~ ^\'(.*)\'$ ]] && value="${BASH_REMATCH[1]}"
        # só define se ainda não estiver no ambiente (preserva override de CLI)
        if [[ -z "${!key:-}" ]]; then
            export "${key}=${value}"
        fi
    done < "${PROJECT_DIR}/.env"
fi

: "${DB_NAME:?Defina DB_NAME (nome da base Odoo onde o módulo será instalado)}"

CONTAINER="${CONTAINER:-odoo_app}"
MODULE="${MODULE:-zabbix_helpdesk_bridge}"
ODOO_CONF="${ODOO_CONF:-/tmp/odoo.conf}"
ACTION="${ACTION:-}"

log() { printf '[install_zhb] %s\n' "$*"; }
die() { printf '[install_zhb] ERRO: %s\n' "$*" >&2; exit 1; }

# Resolve o comando docker. Permite override via DOCKER="sudo docker".
# Se não houver override e o usuário atual não puder falar com o daemon,
# tenta automaticamente com sudo.
DOCKER="${DOCKER:-docker}"
if ! ${DOCKER} info >/dev/null 2>&1; then
    if [[ "${DOCKER}" == "docker" ]] && command -v sudo >/dev/null 2>&1; then
        log "sem permissão para o docker daemon, tentando com sudo..."
        if sudo -n docker info >/dev/null 2>&1 || sudo docker info >/dev/null 2>&1; then
            DOCKER="sudo docker"
        else
            die "não consegui falar com o docker daemon, nem com sudo. Adicione seu usuário ao grupo 'docker' ou rode com DOCKER='sudo docker' ./scripts/install_zabbix_helpdesk_bridge.sh"
        fi
    else
        die "não consegui falar com o docker daemon usando '${DOCKER}'. Verifique permissões."
    fi
fi

# Verifica que o container está de pé
if ! ${DOCKER} ps --format '{{.Names}}' | grep -qx "${CONTAINER}"; then
    die "container '${CONTAINER}' não está rodando. Suba com: ${DOCKER} compose up -d"
fi

# Confere se a base existe (psql via container Odoo, que tem postgresql-client instalado)
log "verificando se a base '${DB_NAME}' existe..."
db_exists=$(${DOCKER} exec -e PGPASSWORD="${DB_PASSWORD:-}" "${CONTAINER}" \
    psql -h "${DB_HOST:-localhost}" -p "${DB_PORT:-5432}" -U "${DB_USER:-odoo}" -d postgres -tAc \
    "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" || true)

if [[ "${db_exists}" != "1" ]]; then
    die "base '${DB_NAME}' não encontrada no PostgreSQL (host=${DB_HOST:-localhost})"
fi

# Auto-detect: install se nunca foi instalado, upgrade caso contrário
if [[ -z "${ACTION}" ]]; then
    log "detectando se '${MODULE}' já está instalado em '${DB_NAME}'..."
    installed=$(${DOCKER} exec -e PGPASSWORD="${DB_PASSWORD:-}" "${CONTAINER}" \
        psql -h "${DB_HOST:-localhost}" -p "${DB_PORT:-5432}" -U "${DB_USER:-odoo}" -d "${DB_NAME}" -tAc \
        "SELECT state FROM ir_module_module WHERE name='${MODULE}'" 2>/dev/null || true)

    case "${installed}" in
        installed|"to upgrade"|"to install")
            ACTION="upgrade"
            ;;
        *)
            ACTION="install"
            ;;
    esac
fi

case "${ACTION}" in
    install) FLAG="-i" ;;
    upgrade) FLAG="-u" ;;
    *) die "ACTION inválido: '${ACTION}' (use install ou upgrade)" ;;
esac

log "ação: ${ACTION}  módulo: ${MODULE}  base: ${DB_NAME}  container: ${CONTAINER}"

# Executa o odoo-bin em modo one-shot dentro do container.
# --no-http evita conflito com o worker já rodando na porta 8069.
# --stop-after-init garante que o processo termine após instalar/atualizar.
${DOCKER} exec -i "${CONTAINER}" \
    /opt/odoo/venv/bin/python3 /opt/odoo/odoo/odoo-bin \
        -c "${ODOO_CONF}" \
        -d "${DB_NAME}" \
        "${FLAG}" "${MODULE}" \
        --no-http \
        --stop-after-init

log "concluído. Verifique no Odoo: Configurações → Aplicativos → ${MODULE}"
