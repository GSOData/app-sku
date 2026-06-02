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
    MovimentacaoEstoque,
    LogConsulta,
    HistoricoUpload,
)

Usuario = get_user_model()


# =============================================================================
# CORES PARA STATUS (Hexadecimal para Flutter)
# =============================================================================
STATUS_CORES = {
    'VENCIDO': '#000000',               # Preto
    'EXTREMAMENTE_CRITICO': '#F44336',  # Vermelho (Material Red)
    'BLOQUEADO': '#FF9800',             # Laranja (Material Orange)
    'PRE_BLOQUEIO': '#FFC107',          # Amarelo (Material Amber)
    'OK': '#4CAF50',                    # Verde (Material Green)
    'SEM_ESTOQUE': '#9E9E9E',           # Cinza (Material Grey)
}

STATUS_LABELS = {
    'VENCIDO': 'Vencido',
    'EXTREMAMENTE_CRITICO': 'Extremamente Crítico',
    'BLOQUEADO': 'Bloqueado',
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
    max_papel = serializers.SerializerMethodField()
    
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
            'is_superuser',
            'max_papel',
            'unidades_acesso',
        ]
        read_only_fields = ['id', 'is_active', 'is_superuser']
    
    def get_nome_completo(self, obj) -> str:
        return obj.get_full_name() or obj.username
    
    def get_max_papel(self, obj) -> str:
        """Retorna o papel de maior privilégio do usuário."""
        return obj.get_max_papel()
    
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
            'dias_pre_bloqueio',
            'dias_bloqueado',
            'dias_extremamente_critico',
            'ativo',
            'created_at',
            'updated_at',
        ]
        read_only_fields = ['id', 'created_at', 'updated_at']
    
    def validate(self, attrs):
        """Valida hierarquia: dias_pre_bloqueio > dias_bloqueado > dias_extremamente_critico."""
        # Para updates parciais, recupera os valores atuais como fallback
        instance = self.instance
        dias_pre = attrs.get(
            'dias_pre_bloqueio',
            instance.dias_pre_bloqueio if instance else 60
        )
        dias_bloq = attrs.get(
            'dias_bloqueado',
            instance.dias_bloqueado if instance else 30
        )
        dias_ext = attrs.get(
            'dias_extremamente_critico',
            instance.dias_extremamente_critico if instance else 7
        )
        
        if dias_pre <= dias_bloq:
            raise serializers.ValidationError({
                'dias_pre_bloqueio': 'Dias para pré-bloqueio deve ser maior que dias para bloqueado.'
            })
        if dias_bloq <= dias_ext:
            raise serializers.ValidationError({
                'dias_bloqueado': 'Dias para bloqueado deve ser maior que dias para extremamente crítico.'
            })
        
        return attrs


# =============================================================================
# SKU - COM CAMPOS DE RANGE DE VALIDADE
# =============================================================================
class SKUSerializer(serializers.ModelSerializer):
    """
    Serializer completo para SKU.
    Inclui campos de range e status calculados para o Frontend.
    """
    unidade_negocio = UnidadeNegocioResumoSerializer(read_only=True)
    unidade_negocio_id = serializers.PrimaryKeyRelatedField(
        queryset=UnidadeNegocio.objects.filter(ativo=True),
        source='unidade_negocio',
        write_only=True
    )
    
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
            'qtd_total_020502',
            'qtd_buffer_020304',
            'qtd_disponivel_venda',
            'validade_inicio_range',
            'validade_fim_range',
            'status_texto',
            'status_cor',
            'status_dias_restantes',
            'ativo',
            'created_at',
            'updated_at',
        ]
        read_only_fields = ['id', 'created_at', 'updated_at']
    
    def get_status_texto(self, obj) -> str:
        """Retorna o texto do status para exibição no Frontend."""
        status_info = obj.get_status()
        status = status_info.get('status', 'SEM_ESTOQUE')
        return STATUS_LABELS.get(status, 'Indefinido')
    
    def get_status_cor(self, obj) -> str:
        """Retorna a cor hexadecimal do status para o Frontend."""
        status_info = obj.get_status()
        status = status_info.get('status', 'SEM_ESTOQUE')
        return STATUS_CORES.get(status, '#9E9E9E')
    
    def get_status_dias_restantes(self, obj) -> int | None:
        """
        Retorna quantidade de dias até o vencimento.
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
            # Novos campos do FEFO:
            'qtd_total_020502',
            'qtd_buffer_020304',
            'qtd_disponivel_venda',
            'validade_inicio_range',
            'validade_fim_range',
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
            'imagem_url',
        ]
    
    def get_quantidade_estoque(self, obj) -> int:
        return obj.qtd_total_020502
    
    def get_quantidade_transito(self, obj) -> int:
        return obj.quantidade_em_transito
    
    def get_quantidade_total(self, obj) -> int:
        return obj.qtd_total_020502 + obj.quantidade_em_transito
    
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
    dias_restantes = serializers.SerializerMethodField()
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
            'validade_inicio_range', # FEFO
            'validade_fim_range',    # FEFO
            'dias_restantes',
            'qtd_disponivel_venda',  # FEFO (antigo 'quantidade')
            'status_texto',
            'status_cor',
            'imagem_url',
        ]
    
    def get_dias_restantes(self, obj) -> int | None:
        status_info = obj.get_status()
        return status_info.get('dias_restantes')
    
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


# =============================================================================
# NOTIFICAÇÕES DE ALERTA DE VALIDADE
# =============================================================================
class NotificacaoAlertaSerializer(serializers.Serializer):
    """
    Serializer para notificações de alerta de validade.
    Baseado diretamente nos campos do SKU (sem LoteValidade).
    """
    sku_id = serializers.IntegerField()
    sku_codigo = serializers.CharField()
    sku_nome = serializers.CharField()
    data_validade = serializers.DateField()
    dias_restantes = serializers.IntegerField()
    qtd_estoque = serializers.IntegerField()
    status = serializers.CharField()
    status_label = serializers.CharField()
    status_cor = serializers.CharField()
    unidade_id = serializers.IntegerField()
    unidade_codigo = serializers.CharField()
    unidade_nome = serializers.CharField()


# =============================================================================
# HISTÓRICO DE UPLOAD
# =============================================================================
class HistoricoUploadSerializer(serializers.ModelSerializer):
    """
    Serializer para HistoricoUpload (somente leitura).
    Usado para listar uploads de Grade e Contagem.
    """
    usuario_nome = serializers.SerializerMethodField()
    unidade_codigo = serializers.CharField(source='unidade_negocio.codigo_unb', read_only=True)
    unidade_nome = serializers.CharField(source='unidade_negocio.nome', read_only=True)
    tipo_arquivo_display = serializers.CharField(source='get_tipo_arquivo_display', read_only=True)
    status_display = serializers.CharField(source='get_status_display', read_only=True)
    
    class Meta:
        model = HistoricoUpload
        fields = [
            'id',
            'tipo_arquivo',
            'tipo_arquivo_display',
            'usuario',
            'usuario_nome',
            'unidade_negocio',
            'unidade_codigo',
            'unidade_nome',
            'status',
            'status_display',
            'linhas_processadas',
            'nome_arquivo',
            'mensagem_erro',
            'created_at',
        ]
        read_only_fields = '__all__'
    
    def get_usuario_nome(self, obj):
        if obj.usuario:
            return obj.usuario.get_full_name() or obj.usuario.username
        return 'Sistema'


class HistoricoUploadUltimoSerializer(serializers.ModelSerializer):
    """
    Serializer simplificado para o endpoint /ultimo/.
    Retorna apenas data_upload (created_at) e tipo_arquivo.
    """
    data_upload = serializers.DateTimeField(source='created_at')
    
    class Meta:
        model = HistoricoUpload
        fields = ['data_upload', 'tipo_arquivo']