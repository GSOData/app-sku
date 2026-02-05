"""
Configuração do Django Admin para o sistema SKU+.
"""

from django.contrib import admin
from django.contrib.auth.admin import UserAdmin
from .models import (
    Usuario,
    UnidadeNegocio,
    UsuarioUnidade,
    ConfiguracaoAlerta,
    SKU,
    LoteValidade,
    MovimentacaoEstoque,
    LogConsulta
)


class UsuarioUnidadeInline(admin.TabularInline):
    model = UsuarioUnidade
    extra = 1


@admin.register(Usuario)
class UsuarioAdmin(UserAdmin):
    list_display = ['username', 'email', 'first_name', 'last_name', 'cargo', 'is_active']
    list_filter = ['is_active', 'is_staff', 'cargo', 'unidades']
    search_fields = ['username', 'email', 'first_name', 'last_name']
    inlines = [UsuarioUnidadeInline]
    
    fieldsets = UserAdmin.fieldsets + (
        ('Informações Adicionais', {
            'fields': ('telefone', 'cargo')
        }),
    )


@admin.register(UnidadeNegocio)
class UnidadeNegocioAdmin(admin.ModelAdmin):
    list_display = ['codigo_unb', 'nome', 'ativo', 'created_at']
    list_filter = ['ativo']
    search_fields = ['codigo_unb', 'nome']
    ordering = ['nome']


@admin.register(ConfiguracaoAlerta)
class ConfiguracaoAlertaAdmin(admin.ModelAdmin):
    list_display = ['__str__', 'dias_para_critico', 'dias_para_pre_bloqueio', 'ativo']
    list_filter = ['ativo', 'unidade']


@admin.register(SKU)
class SKUAdmin(admin.ModelAdmin):
    list_display = ['codigo_sku', 'nome_produto', 'unidade_negocio', 'categoria', 'unidade_medida', 'ativo']
    list_filter = ['ativo', 'unidade_negocio', 'categoria', 'unidade_medida']
    search_fields = ['codigo_sku', 'nome_produto', 'descricao']
    ordering = ['nome_produto']


@admin.register(LoteValidade)
class LoteValidadeAdmin(admin.ModelAdmin):
    list_display = ['numero_lote', 'sku', 'data_validade', 'qtd_estoque', 'localizacao', 'ativo']
    list_filter = ['ativo', 'data_validade', 'sku__unidade_negocio']
    search_fields = ['numero_lote', 'sku__codigo_sku', 'sku__nome_produto']
    ordering = ['data_validade']
    date_hierarchy = 'data_validade'


@admin.register(MovimentacaoEstoque)
class MovimentacaoEstoqueAdmin(admin.ModelAdmin):
    list_display = ['sku', 'tipo', 'status', 'quantidade', 'data_prevista', 'created_at']
    list_filter = ['tipo', 'status', 'ativo']
    search_fields = ['sku__codigo_sku', 'sku__nome_produto']
    ordering = ['-created_at']


@admin.register(LogConsulta)
class LogConsultaAdmin(admin.ModelAdmin):
    list_display = ['usuario', 'tipo_consulta', 'ip_address', 'created_at']
    list_filter = ['tipo_consulta']
    search_fields = ['usuario__username']
    ordering = ['-created_at']
    readonly_fields = ['usuario', 'tipo_consulta', 'parametros', 'ip_address', 'created_at']
