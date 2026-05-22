{
    "name": "Zabbix Helpdesk Bridge",
    "summary": "Campos de correlação entre eventos do Zabbix e tickets do Helpdesk",
    "version": "18.0.1.0.0",
    "license": "LGPL-3",
    "author": "SMD",
    "category": "After-Sales",
    "depends": [
        "helpdesk_mgmt",
    ],
    "data": [
        "views/helpdesk_ticket_views.xml",
    ],
    "installable": True,
    "application": False,
    "auto_install": False,
}
