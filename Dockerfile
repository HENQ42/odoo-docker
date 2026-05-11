FROM ubuntu:24.04

LABEL maintainer="SMD <contato@smdautomacao.com>"

ENV DEBIAN_FRONTEND=noninteractive \
    ODOO_HOME=/opt/odoo \
    ODOO_USER=odoo \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# ------------------------------------------------------
# Dependências de sistema + wkhtmltopdf em uma única camada
# ------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git nano wget \
        python3 python3-dev python3-pip python3-venv \
        libldap2-dev libpq-dev libsasl2-dev \
        libxml2-dev libxslt1-dev \
        libjpeg-dev zlib1g-dev libfreetype6-dev liblcms2-dev \
        libblas-dev libatlas-base-dev libssl-dev libffi-dev \
        build-essential npm postgresql-client node-less \
        fontconfig xfonts-base xfonts-75dpi \
    && wget -q -O /tmp/wkhtmltox.deb \
        https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_amd64.deb \
    && apt-get install -y --no-install-recommends /tmp/wkhtmltox.deb \
    && rm -f /tmp/wkhtmltox.deb \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------
# Usuário Odoo (clones já são feitos como esse usuário,
# eliminando o chown -R sobre dezenas de milhares de arquivos)
# ------------------------------------------------------
RUN groupadd --system ${ODOO_USER} \
    && useradd --system --gid ${ODOO_USER} --home-dir ${ODOO_HOME} --shell /usr/sbin/nologin ${ODOO_USER} \
    && mkdir -p ${ODOO_HOME}/extra-addons /var/log/odoo /opt/odoo/.local/share/Odoo \
    && chown -R ${ODOO_USER}:${ODOO_USER} ${ODOO_HOME} /var/log/odoo

USER odoo
WORKDIR ${ODOO_HOME}

# ------------------------------------------------------
# Clone do Odoo core
# ------------------------------------------------------
RUN git clone --depth 1 --single-branch --branch 18.0 \
        https://github.com/odoo/odoo.git ${ODOO_HOME}/odoo

# ------------------------------------------------------
# Clones OCA em paralelo (xargs -P) — reduz drasticamente o
# tempo deste passo comparado a 31 clones sequenciais
# ------------------------------------------------------
RUN set -eux; cd ${ODOO_HOME}/extra-addons; \
    printf '%s\n' \
        account-analytic account-financial-tools contract crm field-service \
        fleet geospatial helpdesk hr hr-expense iot knowledge l10n-brazil \
        maintenance management-system manufacture mis-builder product-attribute \
        project purchase-workflow repair reporting-engine server-tools server-ux \
        sign stock-logistics-request stock-logistics-warehouse timesheet web website \
    | xargs -n1 -P8 -I{} git clone --quiet --depth 1 --single-branch --branch 18.0 \
        https://github.com/OCA/{}.git {}

# ------------------------------------------------------
# Virtualenv + dependências Python
# ------------------------------------------------------
RUN python3 -m venv ${ODOO_HOME}/venv \
    && ${ODOO_HOME}/venv/bin/pip install --upgrade pip wheel \
    && ${ODOO_HOME}/venv/bin/pip install \
        -r ${ODOO_HOME}/odoo/requirements.txt \
        -r ${ODOO_HOME}/extra-addons/l10n-brazil/requirements.txt \
        packaging

WORKDIR ${ODOO_HOME}/odoo

EXPOSE 8069 8071 8072

CMD ["/opt/odoo/venv/bin/python3", "odoo-bin", "-c", "/etc/odoo/odoo.conf"]
