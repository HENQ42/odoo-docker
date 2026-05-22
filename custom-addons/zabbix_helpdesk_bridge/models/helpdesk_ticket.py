from odoo import fields, models


class HelpdeskTicket(models.Model):
    _inherit = "helpdesk.ticket"

    x_zbx_event_id = fields.Char(
        string="Zabbix Event ID",
        index=True,
        copy=False,
        help="Identificador do evento original no Zabbix. Usado para correlacionar "
             "atualizações e recovery ao ticket já existente.",
    )
    x_zbx_trigger_id = fields.Char(
        string="Zabbix Trigger ID",
        index=True,
        copy=False,
        help="Identificador do trigger no Zabbix. Permite agrupar tickets recorrentes "
             "do mesmo trigger ao longo do tempo.",
    )
    x_zbx_host = fields.Char(
        string="Zabbix Host",
        index=True,
        copy=False,
        help="Nome do host monitorado no Zabbix.",
    )
    x_zbx_severity = fields.Char(
        string="Zabbix Severity",
        copy=False,
        help="Severidade textual original do Zabbix (Disaster, High, Average, etc).",
    )
