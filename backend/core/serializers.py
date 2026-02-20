"""
Serializers do sistema SKU+ para a API REST.

Inclui campos calculados para status de validade,
permitindo que o Frontend apenas renderize as informações.
"""

from rest_framework import serializers
from django.contrib.auth import get_user_model
from .models import (
    UnidadeNegocio,
    UsuarioUnidade,
    ConfiguracaoAlerta,
    SKU,
    LoteValidade,
    MovimentacaoEstoque,
    LogConsulta
)

Usuario = get_user_model()


# =============================================================================
# CORES PARA STATUS (Hexadecimal para Flutter)
# =============================================================================
STATUS_CORES = {
    'VENCIDO': '#000000',       # Preto
    'CRITICO': '#F44336',       # Vermelho (Material Red)
    'PRE_BLOQUEIO': '#FFC107',  # Amarelo (Material Amber)
    'OK': '#4CAF50',            # Verde (Material Green)
    'SEM_ESTOQUE': '#9E9E9E',   # Cinza (Material Grey)
}

STATUS_LABELS = {
    'VENCIDO': 'Vencido',
    'CRITICO': 'Crítico',
    'PRE_BLOQUEIO': 'Pré-Bloqueio',
    'OK': 'OK',
    'SEM_ESTOQUE': 'Sem Estoque',
}


# =============================================================================
# UNIDADE DE NEGÓCIO
# =============================================================================
class UnidadeNegocioSerializer(serializers.ModelSerializer):
    """Serializer para UnidadeNegocio."""
    
    class Meta:
        model = UnidadeNegocio
        fields = [
            'id',
            'codigo_unb',
            'nome',
            'endereco',
            'ativo',
            'created_at',
            'updated_at',
        ]
        read_only_fields = ['id', 'created_at', 'updated_at']


class UnidadeNegocioResumoSerializer(serializers.ModelSerializer):
    """Serializer resumido para uso em relacionamentos."""
    
    class Meta:
        model = UnidadeNegocio
        fields = ['id', 'codigo_unb', 'nome']


# =============================================================================
# USUÁRIO
# =============================================================================
class UsuarioUnidadeSerializer(serializers.ModelSerializer):
    """Serializer para o vínculo Usuário-Unidade."""
    unidade = UnidadeNegocioResumoSerializer(read_only=True)
    unidade_id = serializers.PrimaryKeyRelatedField(
        queryset=UnidadeNegocio.objects.filter(ativo=True),
        source='unidade',
        write_only=True
    )
    
    class Meta:
        model = UsuarioUnidade
        fields = ['id', 'unidade', 'unidade_id', 'papel', 'data_vinculo']
        read_only_fields = ['id', 'data_vinculo']


class UsuarioSerializer(serializers.ModelSerializer):
    """Serializer completo para Usuário."""
    unidades_acesso = serializers.SerializerMethodField()
    nome_completo = serializers.SerializerMethodField()
    
    class Meta:
        model = Usuario
        fields = [
            'id',
            'username',
            'email',
            'first_name',
            'last_name',
            'nome_completo',
            'telefone',
            'cargo',
            'is_active',
            'unidades_acesso',
        ]
        read_only_fields = ['id', 'is_active']
    
    def get_nome_completo(self, obj) -> str:
        return obj.get_full_name() or obj.username
    
    def get_unidades_acesso(self, obj) -> list:
        vinculos = UsuarioUnidade.objects.filter(usuario=obj).select_related('unidade')
        return UsuarioUnidadeSerializer(vinculos, many=True).data


class UsuarioCreateSerializer(serializers.ModelSerializer):
    """Serializer para criação de Usuário com senha."""
    password = serializers.CharField(write_only=True, min_length=8)
    password_confirm = serializers.CharField(write_only=True, min_length=8)
    
    class Meta:
        model = Usuario
        fields = [
            'id',
            'username',
            'email',
            'password',
            'password_confirm',
            'first_name',
            'last_name',
            'telefone',
            'cargo',
        ]
        read_only_fields = ['id']
    
    def validate(self, attrs):
        if attrs['password'] != attrs.pop('password_confirm'):
            raise serializers.ValidationError({
                'password_confirm': 'As senhas não conferem.'
            })
        return attrs
    
    def create(self, validated_data):
        password = validated_data.pop('password')
        usuario = Usuario(**validated_data)
        usuario.set_password(password)
        usuario.save()
        return usuario


class LoginSerializer(serializers.Serializer):
    """Serializer para login (entrada)."""
    username = serializers.CharField(max_length=150)
    password = serializers.CharField(max_length=128, write_only=True)


class LoginResponseSerializer(serializers.Serializer):
    """Serializer para resposta de login."""
    access = serializers.CharField()
    refresh = serializers.CharField()
    usuario = UsuarioSerializer()


# =============================================================================
# CONFIGURAÇÃO DE ALERTA
# =============================================================================
class ConfiguracaoAlertaSerializer(serializers.ModelSerializer):
    """Serializer para ConfiguracaoAlerta."""
    unidade = UnidadeNegocioResumoSerializer(read_only=True)
    unidade_id = serializers.PrimaryKeyRelatedField(
        queryset=UnidadeNegocio.objects.filter(ativo=True),
        source='unidade',
        write_only=True,
        required=False,
        allow_null=True
    )
    
    class Meta:
        model = ConfiguracaoAlerta
        fields = [
            'id',
            'unidade',
            'unidade_id',
            'dias_para_critico',
            'dias_para_pre_bloqueio',
            'ativo',
            'created_at',
            'updated_at',
        ]
        read_only_fields = ['id', 'created_at', 'updated_at']
    
    def validate(self, attrs):
        dias_critico = attrs.get('dias_para_critico', 30)
        dias_pre_bloqueio = attrs.get('dias_para_pre_bloqueio', 45)
        
        if dias_pre_bloqueio <= dias_critico:
            raise serializers.ValidationError({
                'dias_para_pre_bloqueio': 
                'Dias para pré-bloqueio deve ser maior que dias para crítico.'
            })
        return attrs


# =============================================================================
# LOTE / VALIDADE
# =============================================================================
class LoteValidadeSerializer(serializers.ModelSerializer):
    """Serializer completo para LoteValidade."""
    dias_ate_vencimento = serializers.ReadOnlyField()
    esta_vencido = serializers.ReadOnlyField()
    sku_codigo = serializers.CharField(source='sku.codigo_sku', read_only=True)
    sku_nome = serializers.CharField(source='sku.nome_produto', read_only=True)
    
    class Meta:
        model = LoteValidade
        fields = [
            'id',
            'sku',
            'sku_codigo',
            'sku_nome',
            'numero_lote',
            'data_validade',
            'data_fabricacao',
            'qtd_estoque',
            'estoque_display',
            'localizacao',
            'custo_unitario',
            'fornecedor',
            'dias_ate_vencimento',
            'esta_vencido',
            'ativo',
            'created_at',
            'updated_at',
        ]
        read_only_fields = ['id', 'created_at', 'updated_at']


class LoteValidadeResumoSerializer(serializers.ModelSerializer):
    """Serializer resumido para uso em SKU."""
    dias_ate_vencimento = serializers.ReadOnlyField()
    
    class Meta:
        model = LoteValidade
        fields = [
            'id',
            'numero_lote',
            'data_validade',
            'qtd_estoque',
            'dias_ate_vencimento',
        ]


# =============================================================================
# SKU - COM CAMPOS CALCULADOS DE STATUS
# =============================================================================
class SKUSerializer(serializers.ModelSerializer):
    """
    Serializer completo para SKU.
    Inclui campos calculados de status para o Frontend.
    """
    unidade_negocio = UnidadeNegocioResumoSerializer(read_only=True)
    unidade_negocio_id = serializers.PrimaryKeyRelatedField(
        queryset=UnidadeNegocio.objects.filter(ativo=True),
        source='unidade_negocio',
        write_only=True
    )
    
    # Campos calculados
    quantidade_total = serializers.SerializerMethodField()
    quantidade_transito = serializers.SerializerMethodField()
    lote_mais_proximo = LoteValidadeResumoSerializer(read_only=True)
    
    # Status calculados - VITAL PARA O FRONTEND
    status_texto = serializers.SerializerMethodField()
    status_cor = serializers.SerializerMethodField()
    status_dias_restantes = serializers.SerializerMethodField()
    
    # URL completa da imagem
    imagem_url = serializers.SerializerMethodField()
    
    class Meta:
        model = SKU
        fields = [
            'id',
            'codigo_sku',
            'nome_produto',
            'unidade_negocio',
            'unidade_negocio_id',
            'categoria',
            'unidade_medida',
            'fator_conversao',
            'descricao',
            'imagem',
            'imagem_url',
            'quantidade_total',
            'quantidade_transito',
            'lote_mais_proximo',
            'status_texto',
            'status_cor',
            'status_dias_restantes',
            'ativo',
            'created_at',
            'updated_at',
        ]
        read_only_fields = ['id', 'created_at', 'updated_at']
    
    def get_quantidade_total(self, obj) -> int:
        """Retorna soma de todos os lotes."""
        return obj.quantidade_total_estoque
    
    def get_quantidade_transito(self, obj) -> int:
        """Retorna quantidade em trânsito."""
        return obj.quantidade_em_transito
    
    def get_status_texto(self, obj) -> str:
        """
        Retorna o texto do status para exibição no Frontend.
        Ex: 'Crítico', 'OK', 'Pré-Bloqueio'
        """
        status_info = obj.get_status()
        status = status_info.get('status', 'SEM_ESTOQUE')
        return STATUS_LABELS.get(status, 'Indefinido')
    
    def get_status_cor(self, obj) -> str:
        """
        Retorna a cor hexadecimal do status para o Frontend.
        O Flutter deve usar essa cor diretamente sem lógica adicional.
        """
        status_info = obj.get_status()
        status = status_info.get('status', 'SEM_ESTOQUE')
        return STATUS_CORES.get(status, '#9E9E9E')
    
    def get_status_dias_restantes(self, obj) -> int | None:
        """
        Retorna quantidade de dias até o vencimento do lote mais próximo.
        Valores negativos indicam produto vencido.
        """
        status_info = obj.get_status()
        return status_info.get('dias_restantes')
    
    def get_imagem_url(self, obj) -> str | None:
        """Retorna URL completa da imagem."""
        if obj.imagem:
            request = self.context.get('request')
            if request:
                return request.build_absolute_uri(obj.imagem.url)
            return obj.imagem.url
        return None


class SKUListSerializer(serializers.ModelSerializer):
    """
    Serializer otimizado para listagem de SKUs.
    Menos campos, mais performático.
    """
    unidade_codigo = serializers.CharField(
        source='unidade_negocio.codigo_unb', 
        read_only=True
    )
    status_texto = serializers.SerializerMethodField()
    status_cor = serializers.SerializerMethodField()
    quantidade_total = serializers.SerializerMethodField()
    valor_estoque = serializers.SerializerMethodField()
    imagem_url = serializers.SerializerMethodField()
    
    class Meta:
        model = SKU
        fields = [
            'id',
            'codigo_sku',
            'nome_produto',
            'unidade_codigo',
            'categoria',
            'unidade_medida',
            'status_texto',
            'status_cor',
            'quantidade_total',
            'valor_estoque',
            'imagem_url',
        ]
    
    def get_status_texto(self, obj) -> str:
        status_info = obj.get_status()
        status = status_info.get('status', 'SEM_ESTOQUE')
        return STATUS_LABELS.get(status, 'Indefinido')
    
    def get_status_cor(self, obj) -> str:
        status_info = obj.get_status()
        status = status_info.get('status', 'SEM_ESTOQUE')
        return STATUS_CORES.get(status, '#9E9E9E')
    
    def get_quantidade_total(self, obj) -> int:
        return obj.quantidade_total_estoque
    
    def get_valor_estoque(self, obj) -> float:
        """Retorna o valor total do estoque (qtd * custo)."""
        return obj.valor_total_estoque
    
    def get_imagem_url(self, obj) -> str | None:
        if obj.imagem:
            request = self.context.get('request')
            if request:
                return request.build_absolute_uri(obj.imagem.url)
            return obj.imagem.url
        return None


class SKUEstoqueSerializer(serializers.ModelSerializer):
    """
    Serializer para Tela de Estoque Inicial.
    Agrupa informações de estoque + trânsito.
    """
    unidade_negocio = UnidadeNegocioResumoSerializer(read_only=True)
    quantidade_estoque = serializers.SerializerMethodField()
    quantidade_transito = serializers.SerializerMethodField()
    quantidade_total = serializers.SerializerMethodField()
    qtd_lotes = serializers.SerializerMethodField()
    imagem_url = serializers.SerializerMethodField()
    
    class Meta:
        model = SKU
        fields = [
            'id',
            'codigo_sku',
            'nome_produto',
            'unidade_negocio',
            'unidade_medida',
            'quantidade_estoque',
            'quantidade_transito',
            'quantidade_total',
            'qtd_lotes',
            'imagem_url',
        ]
    
    def get_quantidade_estoque(self, obj) -> int:
        return obj.quantidade_total_estoque
    
    def get_quantidade_transito(self, obj) -> int:
        return obj.quantidade_em_transito
    
    def get_quantidade_total(self, obj) -> int:
        return obj.quantidade_total_estoque + obj.quantidade_em_transito
    
    def get_qtd_lotes(self, obj) -> int:
        return obj.lotes.filter(ativo=True, qtd_estoque__gt=0).count()
    
    def get_imagem_url(self, obj) -> str | None:
        if obj.imagem:
            request = self.context.get('request')
            if request:
                return request.build_absolute_uri(obj.imagem.url)
            return obj.imagem.url
        return None


class SKUCriticidadeSerializer(serializers.ModelSerializer):
    """
    Serializer para Relatório de Criticidade.
    Usado nas abas Bloqueados e Pré-Bloqueio.
    """
    unidade_codigo = serializers.CharField(
        source='unidade_negocio.codigo_unb', 
        read_only=True
    )
    lote_critico = serializers.SerializerMethodField()
    data_validade = serializers.SerializerMethodField()
    dias_restantes = serializers.SerializerMethodField()
    quantidade = serializers.SerializerMethodField()
    status_texto = serializers.SerializerMethodField()
    status_cor = serializers.SerializerMethodField()
    imagem_url = serializers.SerializerMethodField()
    
    class Meta:
        model = SKU
        fields = [
            'id',
            'codigo_sku',
            'nome_produto',
            'unidade_codigo',
            'lote_critico',
            'data_validade',
            'dias_restantes',
            'quantidade',
            'status_texto',
            'status_cor',
            'imagem_url',
        ]
    
    def get_lote_critico(self, obj) -> str | None:
        lote = obj.lote_mais_proximo
        return lote.numero_lote if lote else None
    
    def get_data_validade(self, obj) -> str | None:
        lote = obj.lote_mais_proximo
        return lote.data_validade.isoformat() if lote else None
    
    def get_dias_restantes(self, obj) -> int | None:
        status_info = obj.get_status()
        return status_info.get('dias_restantes')
    
    def get_quantidade(self, obj) -> int:
        lote = obj.lote_mais_proximo
        return lote.qtd_estoque if lote else 0
    
    def get_status_texto(self, obj) -> str:
        status_info = obj.get_status()
        status = status_info.get('status', 'SEM_ESTOQUE')
        return STATUS_LABELS.get(status, 'Indefinido')
    
    def get_status_cor(self, obj) -> str:
        status_info = obj.get_status()
        status = status_info.get('status', 'SEM_ESTOQUE')
        return STATUS_CORES.get(status, '#9E9E9E')
    
    def get_imagem_url(self, obj) -> str | None:
        if obj.imagem:
            request = self.context.get('request')
            if request:
                return request.build_absolute_uri(obj.imagem.url)
            return obj.imagem.url
        return None


# =============================================================================
# MOVIMENTAÇÃO DE ESTOQUE
# =============================================================================
class MovimentacaoEstoqueSerializer(serializers.ModelSerializer):
    """Serializer para MovimentacaoEstoque."""
    sku_codigo = serializers.CharField(source='sku.codigo_sku', read_only=True)
    sku_nome = serializers.CharField(source='sku.nome_produto', read_only=True)
    lote_numero = serializers.CharField(source='lote.numero_lote', read_only=True)
    unidade_origem_nome = serializers.CharField(
        source='unidade_origem.nome', 
        read_only=True
    )
    unidade_destino_nome = serializers.CharField(
        source='unidade_destino.nome', 
        read_only=True
    )
    usuario_nome = serializers.CharField(
        source='usuario.get_full_name', 
        read_only=True
    )
    
    class Meta:
        model = MovimentacaoEstoque
        fields = [
            'id',
            'sku',
            'sku_codigo',
            'sku_nome',
            'lote',
            'lote_numero',
            'tipo',
            'status',
            'quantidade',
            'unidade_origem',
            'unidade_origem_nome',
            'unidade_destino',
            'unidade_destino_nome',
            'data_prevista',
            'data_efetiva',
            'observacao',
            'usuario',
            'usuario_nome',
            'ativo',
            'created_at',
            'updated_at',
        ]
        read_only_fields = ['id', 'created_at', 'updated_at', 'usuario']


# =============================================================================
# LOG DE CONSULTA
# =============================================================================
class LogConsultaSerializer(serializers.ModelSerializer):
    """Serializer para LogConsulta (somente leitura)."""
    usuario_nome = serializers.CharField(
        source='usuario.get_full_name', 
        read_only=True
    )
    
    class Meta:
        model = LogConsulta
        fields = [
            'id',
            'usuario',
            'usuario_nome',
            'tipo_consulta',
            'parametros',
            'ip_address',
            'created_at',
        ]
        read_only_fields = '__all__'
