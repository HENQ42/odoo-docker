# Odoo 18 — Deploy

## ⚠️ Pré-requisito: MTU do Docker

Se o host estiver atrás de VPN/encapsulamento (MTU < 1500), o `docker0` padrão
fica com MTU 1500 e **downloads HTTPS grandes travam silenciosamente** dentro do
build/container (GitHub via Azure CDN não responde a ICMP "fragmentation
needed", o que provoca um PMTUD blackhole).


**Ajuste o MTU do daemon para igualar
o MTU do host** (verifique com `ip addr show eth0 | grep mtu`):

```bash
sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{ "mtu": 1400 }
EOF
sudo systemctl restart docker
```
