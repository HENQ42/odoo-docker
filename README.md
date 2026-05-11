# Odoo 18 — Deploy

## ⚠️ Pré-requisito 1: MTU do Docker

Se o host estiver atrás de VPN/encapsulamento (MTU < 1500), o `docker0` padrão
fica com MTU 1500 e **downloads HTTPS grandes travam silenciosamente** dentro do
build/container (GitHub via Azure CDN não responde a ICMP "fragmentation
needed", o que provoca um PMTUD blackhole).

**Ajuste o MTU do daemon para igualar o MTU do host**
(verifique com `ip addr show eth0 | grep mtu`):

```bash
sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{ "mtu": 1400 }
EOF
sudo systemctl restart docker
```

## ⚠️ Pré-requisito 2: SELinux (RHEL/Rocky/Alma)

Em hosts com SELinux *enforcing*, bind mounts precisam de label
`container_file_t`, senão o processo dentro do container recebe
`Permission denied` ao ler arquivos do host (ex.: `sed: can't read
/etc/odoo/odoo.conf`).

O `docker-compose.yml` já usa a flag `:z` nos volumes (`./config:/etc/odoo:z`,
`./logs:/var/log/odoo:z`), que faz o Docker relabelar automaticamente. Apenas
garanta permissão de leitura no host:

```bash
chmod a+r config/odoo.conf
chmod a+rx config logs
```

## ⚠️ Pré-requisito 3: PostgreSQL externo

O Odoo conecta em um Postgres já existente (definido em `.env` →
`DB_HOST`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`). No servidor PG é preciso:

**1. Liberar acesso no `pg_hba.conf`**

Descubra o caminho com `sudo -u postgres psql -c "SHOW hba_file;"`. Adicione
uma regra `host all <user> <ip_da_vm_odoo>/32 scram-sha-256`:

```bash
echo "host    all    odoo    172.19.67.8/32    scram-sha-256" \
  | sudo tee -a /var/lib/pgsql/18/data/pg_hba.conf
sudo systemctl reload postgresql-18
```

> Importante: use `database all` (não apenas `odoo`). Na primeira
> inicialização, o Odoo conecta na DB de manutenção `postgres` para checar
> existência da DB alvo — se o pg_hba só liberar `odoo`, ele falha com
> `no pg_hba.conf entry for host "X.X.X.X", user "odoo", database "postgres"`.

Confirme que a regra está ativa:

```bash
sudo -u postgres psql -c \
  "SELECT type,database,user_name,address,auth_method
     FROM pg_hba_file_rules
    WHERE '172.19.67.8'::inet <<= address;"
```

**2. Criar role e database**

```sql
CREATE USER odoo WITH PASSWORD 'odoo';
CREATE DATABASE odoo OWNER odoo;
```

**3. Validar do host Odoo, antes de subir o container:**

```bash
PGPASSWORD=odoo psql -h <DB_HOST> -U odoo -d odoo     -c "SELECT 1;"
PGPASSWORD=odoo psql -h <DB_HOST> -U odoo -d postgres -c "SELECT 1;"
```

Ambos precisam retornar `1`.

## ⚠️ Pré-requisito 4: SELinux libera nginx → upstream local

Em RHEL/Rocky com SELinux, o nginx é bloqueado de abrir conexões de rede
(`nginx error.log`: `connect() to 127.0.0.1:8069 failed (13: Permission
denied)`, resultado HTTP 502). Habilite o boolean:

```bash
sudo setsebool -P httpd_can_network_connect 1
```

## Inicialização da database

Após criar a DB vazia no Postgres, o Odoo precisa instalar o módulo `base`
(senão toda request retorna 500 com `KeyError: 'ir.http'`). Faça uma execução
one-shot antes do primeiro `up`:

```bash
sudo docker compose stop odoo

sudo docker compose run --rm --no-deps odoo bash -c '
  set -e
  sed \
    -e "s|__DB_HOST__|$DB_HOST|g" \
    -e "s|__DB_PORT__|$DB_PORT|g" \
    -e "s|__DB_USER__|$DB_USER|g" \
    -e "s|__DB_PASSWORD__|$DB_PASSWORD|g" \
    -e "s|__DB_NAME__|$DB_NAME|g" \
    -e "s|__ADMIN_PASSWD__|$ADMIN_PASSWD|g" \
    /etc/odoo/odoo.conf > /tmp/odoo.conf
  exec /opt/odoo/venv/bin/python3 /opt/odoo/odoo/odoo-bin \
       -c /tmp/odoo.conf --without-demo=all -i base --stop-after-init
'
```

## Build & up

```bash
cp .env.example .env       # ajuste os valores
tmux new -s odoo           # SSH-resiliente
sudo docker compose up -d --build
sudo docker compose logs -f odoo
```

`Ctrl+B, D` desanexa o tmux; `tmux attach -t odoo` volta.

## Verificação

```bash
sudo docker compose ps                  # healthy após ~1-2 min
sudo ss -ltnp | grep -E '8069|8072'     # Odoo escutando em 127.0.0.1
curl -H "Host: odoo-sefaz-al.brisanet.net.br" http://127.0.0.1/web/login
```
