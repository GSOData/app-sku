"""
Views do sistema SKU+ para a API REST.

Implementa:
- Autenticação JWT
- CRUD com filtros avançados
- Endpoints customizados para as telas do App
- Controle de acesso por unidade
"""

from rest_framework import viewsets, status, filters
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.permissions import IsAuthenticated, AllowAny
from rest_framework_simplejwt.tokens import RefreshToken
from django.contrib.auth import authenticate
from django.db.models import Q, Sum, Prefetch
from django_filters.rest_framework import DjangoFilterBackend
from datetime import date

from .models import (
    UnidadeNegocio,
    Usuario,
    UsuarioUnidade,
    ConfiguracaoAlerta,
    SKU,
    LoteValidade,
    MovimentacaoEstoque,
    LogConsulta
)
from .serializers import (
    UnidadeNegocioSerializer,
    UnidadeNegocioResumoSerializer,
    UsuarioSerializer,
    UsuarioCreateSerializer,
    LoginSerializer,
    LoginResponseSerializer,
    ConfiguracaoAlertaSerializer,
    SKUSerializer,
    SKUListSerializer,
    SKUEstoqueSerializer,
    SKUCriticidadeSerializer,
    LoteValidadeSerializer,
    LoteValidadeResumoSerializer,
    MovimentacaoEstoqueSerializer,
    LogConsultaSerializer,
    STATUS_CORES,
    STATUS_LABELS,
)


# =============================================================================
# MIXINS E UTILITÁRIOS
# =============================================================================
class UnidadeAccessMixin:
    """
    Mixin para filtrar querysets por unidades que o usuário tem acesso.
    """
    
    def get_user_unidades(self):
        """Retorna IDs das unidades que o usuário pode acessar."""
        user = self.request.user
        if user.is_superuser:
            return UnidadeNegocio.objects.filter(ativo=True).values_list('id', flat=True)
        return user.get_unidades_ids()
    
    def filter_by_unidade(self, queryset, unidade_field='unidade_negocio'):
        """Filtra queryset pelas unidades do usuário."""
        unidades_ids = self.get_user_unidades()
        filter_kwargs = {f'{unidade_field}__id__in': unidades_ids}
        return queryset.filter(**filter_kwargs)


def get_client_ip(request):
    """Extrai IP do cliente da requisição."""
    x_forwarded_for = request.META.get('HTTP_X_FORWARDED_FOR')
    if x_forwarded_for:
        return x_forwarded_for.split(',')[0]
    return request.META.get('REMOTE_ADDR')


def log_consulta(usuario, tipo, parametros, request):
    """Registra log de consulta para auditoria."""
    LogConsulta.objects.create(
        usuario=usuario,
        tipo_consulta=tipo,
        parametros=parametros,
        ip_address=get_client_ip(request)
    )


# =============================================================================
# AUTENTICAÇÃO
# =============================================================================
class LoginView(APIView):
    """
    POST /api/auth/login/
    
    Autentica usuário e retorna tokens JWT.
    """
    permission_classes = [AllowAny]
    
    def post(self, request):
        serializer = LoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        
        username = serializer.validated_data['username']
        password = serializer.validated_data['password']
        
        user = authenticate(username=username, password=password)
        
        if user is None:
            return Response(
                {'detail': 'Credenciais inválidas.'},
                status=status.HTTP_401_UNAUTHORIZED
            )
        
        if not user.is_active:
            return Response(
                {'detail': 'Usuário inativo.'},
                status=status.HTTP_401_UNAUTHORIZED
            )
        
        # Gera tokens JWT
        refresh = RefreshToken.for_user(user)
        
        response_data = {
            'access': str(refresh.access_token),
            'refresh': str(refresh),
            'usuario': UsuarioSerializer(user).data
        }
        
        return Response(response_data, status=status.HTTP_200_OK)


class LogoutView(APIView):
    """
    POST /api/auth/logout/
    
    Invalida o refresh token (blacklist).
    """
    permission_classes = [IsAuthenticated]
    
    def post(self, request):
        try:
            refresh_token = request.data.get('refresh')
            if refresh_token:
                token = RefreshToken(refresh_token)
                token.blacklist()
            return Response(
                {'detail': 'Logout realizado com sucesso.'},
                status=status.HTTP_200_OK
            )
        except Exception:
            return Response(
                {'detail': 'Token inválido.'},
                status=status.HTTP_400_BAD_REQUEST
            )


class MeView(APIView):
    """
    GET /api/auth/me/
    
    Retorna dados do usuário autenticado.
    """
    permission_classes = [IsAuthenticated]
    
    def get(self, request):
        serializer = UsuarioSerializer(request.user)
        return Response(serializer.data)


# =============================================================================
# UNIDADE DE NEGÓCIO
# =============================================================================
class UnidadeNegocioViewSet(viewsets.ModelViewSet):
    """
    ViewSet para UnidadeNegocio.
    
    Usuários só veem unidades que têm acesso.
    Superusuários veem todas.
    """
    serializer_class = UnidadeNegocioSerializer
    permission_classes = [IsAuthenticated]
    filter_backends = [DjangoFilterBackend, filters.SearchFilter, filters.OrderingFilter]
    search_fields = ['codigo_unb', 'nome']
    ordering_fields = ['nome', 'codigo_unb', 'created_at']
    ordering = ['nome']
    
    def get_queryset(self):
        user = self.request.user
        queryset = UnidadeNegocio.objects.filter(ativo=True)
        
        if not user.is_superuser:
            unidades_ids = user.get_unidades_ids()
            queryset = queryset.filter(id__in=unidades_ids)
        
        return queryset
    
    @action(detail=False, methods=['get'])
    def resumo(self, request):
        """
        GET /api/unidades/resumo/
        
        Lista resumida para dropdowns.
        """
        queryset = self.get_queryset()
        serializer = UnidadeNegocioResumoSerializer(queryset, many=True)
        return Response(serializer.data)


# =============================================================================
# SKU - CONSULTA DE VALIDADE
# =============================================================================
class SKUViewSet(UnidadeAccessMixin, viewsets.ModelViewSet):
    """
    ViewSet para SKU com busca avançada.
    
    Implementa:
    - Busca por codigo_sku OU nome_produto (parâmetro 'search')
    - Filtro por unidade_negocio
    - Filtro por categoria
    - Campos calculados de status
    """
    permission_classes = [IsAuthenticated]
    filter_backends = [DjangoFilterBackend, filters.OrderingFilter]
    filterset_fields = ['unidade_negocio', 'categoria', 'ativo']
    ordering_fields = ['nome_produto', 'codigo_sku', 'created_at']
    ordering = ['nome_produto']
    
    def get_serializer_class(self):
        if self.action == 'list':
            return SKUListSerializer
        return SKUSerializer
    
    def get_queryset(self):
        queryset = SKU.objects.filter(ativo=True).select_related(
            'unidade_negocio'
        ).prefetch_related(
            Prefetch(
                'lotes',
                queryset=LoteValidade.objects.filter(
                    ativo=True, 
                    qtd_estoque__gt=0
                ).order_by('data_validade')
            )
        )
        
        # Filtra por unidades do usuário
        queryset = self.filter_by_unidade(queryset)
        
        # Busca por codigo_sku OU nome_produto
        search = self.request.query_params.get('search', None)
        if search:
            queryset = queryset.filter(
                Q(codigo_sku__icontains=search) | 
                Q(nome_produto__icontains=search)
            )
        
        # Filtro por unidade específica (via query param)
        unidade_id = self.request.query_params.get('unidade_id', None)
        if unidade_id:
            queryset = queryset.filter(unidade_negocio_id=unidade_id)
        
        return queryset.distinct()
    
    def retrieve(self, request, *args, **kwargs):
        """Override para logar consulta de validade."""
        instance = self.get_object()
        
        # Log de consulta
        log_consulta(
            usuario=request.user,
            tipo='VALIDADE',
            parametros={'sku_id': instance.id, 'codigo_sku': instance.codigo_sku},
            request=request
        )
        
        serializer = self.get_serializer(instance)
        return Response(serializer.data)
    
    @action(detail=False, methods=['get'])
    def consulta_validade(self, request):
        """
        GET /api/skus/consulta_validade/?search=xxx&unidade_id=1
        
        Endpoint específico para a Tela de Consulta de Validade.
        Busca por código SKU ou nome do produto.
        
        Parâmetros:
        - search: Termo de busca (codigo_sku ou nome_produto)
        - unidade_id: ID da unidade (opcional)
        
        Retorna lista com status calculado.
        """
        search = request.query_params.get('search', None)
        unidade_id = request.query_params.get('unidade_id', None)
        
        if not search:
            return Response(
                {'detail': 'Parâmetro "search" é obrigatório.'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        queryset = self.get_queryset().filter(
            Q(codigo_sku__icontains=search) | 
            Q(nome_produto__icontains=search)
        )
        
        if unidade_id:
            queryset = queryset.filter(unidade_negocio_id=unidade_id)
        
        # Log de consulta
        log_consulta(
            usuario=request.user,
            tipo='VALIDADE',
            parametros={'search': search, 'unidade_id': unidade_id},
            request=request
        )
        
        serializer = SKUSerializer(
            queryset, 
            many=True, 
            context={'request': request}
        )
        return Response(serializer.data)
    
    @action(detail=True, methods=['get'])
    def lotes(self, request, pk=None):
        """
        GET /api/skus/{id}/lotes/
        
        Retorna todos os lotes de um SKU ordenados por validade (FEFO).
        """
        sku = self.get_object()
        lotes = sku.lotes.filter(ativo=True, qtd_estoque__gt=0).order_by('data_validade')
        serializer = LoteValidadeResumoSerializer(lotes, many=True)
        return Response(serializer.data)


# =============================================================================
# RELATÓRIO DE CRITICIDADE
# =============================================================================
class RelatorioCriticidadeView(UnidadeAccessMixin, APIView):
    """
    GET /api/relatorio-criticidade/?unidade_id=1
    
    Endpoint específico para a Tela de Itens em Criticidade.
    
    Retorna JSON separado:
    {
        'bloqueados': [...],   # Vencidos + Críticos
        'pre_bloqueio': [...]  # Pré-bloqueio
    }
    
    Isso evita processamento no app mobile.
    """
    permission_classes = [IsAuthenticated]
    
    def get(self, request):
        unidade_id = request.query_params.get('unidade_id', None)
        codigo_unb = request.query_params.get('codigo_unb', None)
        
        # Busca unidade por ID ou código
        unidade = None
        if unidade_id:
            try:
                unidade = UnidadeNegocio.objects.get(id=unidade_id, ativo=True)
            except UnidadeNegocio.DoesNotExist:
                return Response(
                    {'detail': 'Unidade não encontrada.'},
                    status=status.HTTP_404_NOT_FOUND
                )
        elif codigo_unb:
            try:
                unidade = UnidadeNegocio.objects.get(codigo_unb=codigo_unb, ativo=True)
            except UnidadeNegocio.DoesNotExist:
                return Response(
                    {'detail': 'Unidade não encontrada.'},
                    status=status.HTTP_404_NOT_FOUND
                )
        
        # Verifica permissão do usuário
        if unidade and not request.user.is_superuser:
            if not request.user.tem_acesso_unidade(unidade.id):
                return Response(
                    {'detail': 'Sem permissão para esta unidade.'},
                    status=status.HTTP_403_FORBIDDEN
                )
        
        # Busca configuração de alerta
        config = None
        if unidade:
            config = getattr(unidade, 'configuracao_alerta', None)
        if not config:
            config = ConfiguracaoAlerta.objects.filter(
                unidade__isnull=True, 
                ativo=True
            ).first()
        
        dias_critico = config.dias_para_critico if config else 30
        dias_pre_bloqueio = config.dias_para_pre_bloqueio if config else 45
        
        # Monta queryset base
        queryset = SKU.objects.filter(ativo=True).select_related(
            'unidade_negocio'
        ).prefetch_related(
            Prefetch(
                'lotes',
                queryset=LoteValidade.objects.filter(
                    ativo=True, 
                    qtd_estoque__gt=0
                ).order_by('data_validade')
            )
        )
        
        if unidade:
            queryset = queryset.filter(unidade_negocio=unidade)
        else:
            # Filtra por unidades do usuário
            unidades_ids = request.user.get_unidades_ids()
            queryset = queryset.filter(unidade_negocio_id__in=unidades_ids)
        
        # Classifica SKUs por status
        bloqueados = []
        pre_bloqueio = []
        hoje = date.today()
        
        for sku in queryset:
            status_info = sku.get_status(config)
            status_code = status_info.get('status')
            
            if status_code in ['VENCIDO', 'CRITICO']:
                bloqueados.append(sku)
            elif status_code == 'PRE_BLOQUEIO':
                pre_bloqueio.append(sku)
        
        # Log de consulta
        log_consulta(
            usuario=request.user,
            tipo='CRITICIDADE',
            parametros={
                'unidade_id': unidade.id if unidade else None,
                'codigo_unb': codigo_unb
            },
            request=request
        )
        
        # Serializa
        bloqueados_data = SKUCriticidadeSerializer(
            bloqueados, 
            many=True, 
            context={'request': request}
        ).data
        
        pre_bloqueio_data = SKUCriticidadeSerializer(
            pre_bloqueio, 
            many=True, 
            context={'request': request}
        ).data
        
        return Response({
            'unidade': UnidadeNegocioResumoSerializer(unidade).data if unidade else None,
            'config': {
                'dias_para_critico': dias_critico,
                'dias_para_pre_bloqueio': dias_pre_bloqueio,
            },
            'resumo': {
                'total_bloqueados': len(bloqueados),
                'total_pre_bloqueio': len(pre_bloqueio),
            },
            'bloqueados': bloqueados_data,
            'pre_bloqueio': pre_bloqueio_data,
        })


# =============================================================================
# ESTOQUE INICIAL
# =============================================================================
class EstoqueViewSet(UnidadeAccessMixin, viewsets.ReadOnlyModelViewSet):
    """
    ViewSet para Estoque Inicial (somente leitura).
    
    GET /api/estoque/
    GET /api/estoque/{id}/
    
    Retorna SKUs com:
    - Quantidade total em estoque (soma dos lotes)
    - Quantidade em trânsito
    - Quantidade total (estoque + trânsito)
    """
    serializer_class = SKUEstoqueSerializer
    permission_classes = [IsAuthenticated]
    filter_backends = [DjangoFilterBackend, filters.OrderingFilter]
    filterset_fields = ['unidade_negocio', 'categoria']
    ordering_fields = ['nome_produto', 'codigo_sku']
    ordering = ['nome_produto']
    
    def get_queryset(self):
        queryset = SKU.objects.filter(ativo=True).select_related(
            'unidade_negocio'
        ).prefetch_related(
            Prefetch(
                'lotes',
                queryset=LoteValidade.objects.filter(ativo=True)
            ),
            Prefetch(
                'movimentacoes',
                queryset=MovimentacaoEstoque.objects.filter(
                    ativo=True,
                    tipo='ENTRADA',
                    status='EM_TRANSITO'
                )
            )
        )
        
        # Filtra por unidades do usuário
        queryset = self.filter_by_unidade(queryset)
        
        # Busca por codigo_sku ou nome
        search = self.request.query_params.get('search', None)
        if search:
            queryset = queryset.filter(
                Q(codigo_sku__icontains=search) | 
                Q(nome_produto__icontains=search)
            )
        
        # Filtro por unidade específica
        unidade_id = self.request.query_params.get('unidade_id', None)
        if unidade_id:
            queryset = queryset.filter(unidade_negocio_id=unidade_id)
        
        return queryset.distinct()
    
    def list(self, request, *args, **kwargs):
        """Override para logar consulta de estoque."""
        response = super().list(request, *args, **kwargs)
        
        # Log de consulta
        log_consulta(
            usuario=request.user,
            tipo='ESTOQUE',
            parametros={
                'search': request.query_params.get('search'),
                'unidade_id': request.query_params.get('unidade_id'),
            },
            request=request
        )
        
        return response
    
    @action(detail=False, methods=['get'])
    def resumo_geral(self, request):
        """
        GET /api/estoque/resumo_geral/
        
        Retorna totalizadores do estoque.
        """
        queryset = self.get_queryset()
        
        # Calcula totais
        total_skus = queryset.count()
        
        # Total em estoque
        total_estoque = 0
        total_transito = 0
        skus_sem_estoque = 0
        
        for sku in queryset:
            qtd_estoque = sku.quantidade_total_estoque
            qtd_transito = sku.quantidade_em_transito
            
            total_estoque += qtd_estoque
            total_transito += qtd_transito
            
            if qtd_estoque == 0:
                skus_sem_estoque += 1
        
        return Response({
            'total_skus': total_skus,
            'total_estoque': total_estoque,
            'total_transito': total_transito,
            'total_geral': total_estoque + total_transito,
            'skus_sem_estoque': skus_sem_estoque,
        })


# =============================================================================
# LOTE / VALIDADE
# =============================================================================
class LoteValidadeViewSet(UnidadeAccessMixin, viewsets.ModelViewSet):
    """
    ViewSet para LoteValidade.
    """
    serializer_class = LoteValidadeSerializer
    permission_classes = [IsAuthenticated]
    filter_backends = [DjangoFilterBackend, filters.OrderingFilter]
    filterset_fields = ['sku', 'ativo']
    ordering_fields = ['data_validade', 'numero_lote', 'created_at']
    ordering = ['data_validade']
    
    def get_queryset(self):
        queryset = LoteValidade.objects.filter(ativo=True).select_related(
            'sku', 
            'sku__unidade_negocio'
        )
        
        # Filtra por unidades do usuário
        unidades_ids = self.get_user_unidades()
        queryset = queryset.filter(sku__unidade_negocio_id__in=unidades_ids)
        
        # Filtro por SKU específico
        sku_id = self.request.query_params.get('sku_id', None)
        if sku_id:
            queryset = queryset.filter(sku_id=sku_id)
        
        # Filtro para mostrar apenas vencidos
        vencidos = self.request.query_params.get('vencidos', None)
        if vencidos == 'true':
            queryset = queryset.filter(data_validade__lt=date.today())
        
        # Filtro para mostrar apenas com estoque
        com_estoque = self.request.query_params.get('com_estoque', None)
        if com_estoque == 'true':
            queryset = queryset.filter(qtd_estoque__gt=0)
        
        return queryset


# =============================================================================
# CONFIGURAÇÃO DE ALERTA
# =============================================================================
class ConfiguracaoAlertaViewSet(viewsets.ModelViewSet):
    """
    ViewSet para ConfiguracaoAlerta.
    """
    queryset = ConfiguracaoAlerta.objects.filter(ativo=True)
    serializer_class = ConfiguracaoAlertaSerializer
    permission_classes = [IsAuthenticated]
    filter_backends = [DjangoFilterBackend]
    filterset_fields = ['unidade']


# =============================================================================
# MOVIMENTAÇÃO DE ESTOQUE
# =============================================================================
class MovimentacaoEstoqueViewSet(UnidadeAccessMixin, viewsets.ModelViewSet):
    """
    ViewSet para MovimentacaoEstoque.
    """
    serializer_class = MovimentacaoEstoqueSerializer
    permission_classes = [IsAuthenticated]
    filter_backends = [DjangoFilterBackend, filters.OrderingFilter]
    filterset_fields = ['tipo', 'status', 'sku']
    ordering_fields = ['created_at', 'data_prevista']
    ordering = ['-created_at']
    
    def get_queryset(self):
        queryset = MovimentacaoEstoque.objects.filter(ativo=True).select_related(
            'sku',
            'lote',
            'unidade_origem',
            'unidade_destino',
            'usuario'
        )
        
        # Filtra por unidades do usuário
        unidades_ids = self.get_user_unidades()
        queryset = queryset.filter(
            Q(unidade_origem_id__in=unidades_ids) |
            Q(unidade_destino_id__in=unidades_ids) |
            Q(sku__unidade_negocio_id__in=unidades_ids)
        )
        
        return queryset.distinct()
    
    def perform_create(self, serializer):
        serializer.save(usuario=self.request.user)


# =============================================================================
# LOG DE CONSULTAS (somente leitura)
# =============================================================================
class LogConsultaViewSet(viewsets.ReadOnlyModelViewSet):
    """
    ViewSet para LogConsulta (somente leitura).
    Apenas superusuários podem ver.
    """
    queryset = LogConsulta.objects.all().select_related('usuario')
    serializer_class = LogConsultaSerializer
    permission_classes = [IsAuthenticated]
    filter_backends = [DjangoFilterBackend, filters.OrderingFilter]
    filterset_fields = ['tipo_consulta', 'usuario']
    ordering = ['-created_at']
    
    def get_queryset(self):
        # Apenas superusuários veem todos os logs
        if not self.request.user.is_superuser:
            return LogConsulta.objects.filter(usuario=self.request.user)
        return super().get_queryset()


# =============================================================================
# UPLOAD DE ARQUIVOS
# =============================================================================
class UploadEstoqueView(APIView):
    """
    POST /api/upload/grade-020502/
    
    Upload de planilha de Grade 020502 (Estoque Total Diário).
    
    Form data:
    - file: arquivo .xlsx, .xls ou .csv
    - unidade_negocio_id: ID da unidade de negócio
    """
    permission_classes = [IsAuthenticated]
    
    def post(self, request):
        from .services import EstoqueImportService
        
        file = request.FILES.get('file')
        unidade_negocio_id = request.data.get('unidade_negocio_id')
        
        if not file:
            return Response(
                {'error': 'Arquivo não enviado'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        if not unidade_negocio_id:
            return Response(
                {'error': 'Unidade de negócio não informada'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        # Verifica extensão do arquivo
        allowed_extensions = ['.xlsx', '.xls', '.csv']
        file_ext = '.' + file.name.split('.')[-1].lower()
        if file_ext not in allowed_extensions:
            return Response(
                {'error': f'Formato não permitido. Use: {", ".join(allowed_extensions)}'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        # Verifica acesso à unidade
        user = request.user
        if not user.is_superuser:
            if not user.tem_acesso_unidade(int(unidade_negocio_id)):
                return Response(
                    {'error': 'Sem permissão para esta unidade'},
                    status=status.HTTP_403_FORBIDDEN
                )
        
        try:
            service = EstoqueImportService(int(unidade_negocio_id))
            result = service.processar_grade_020502(file)
            
            if result.get('success'):
                return Response(result, status=status.HTTP_200_OK)
            else:
                return Response(result, status=status.HTTP_400_BAD_REQUEST)
                
        except UnidadeNegocio.DoesNotExist:
            return Response(
                {'error': 'Unidade de negócio não encontrada'},
                status=status.HTTP_404_NOT_FOUND
            )
        except Exception as e:
            return Response(
                {'error': f'Erro ao processar arquivo: {str(e)}'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


class UploadContagensView(APIView):
    """
    POST /api/upload/contagens/
    
    Upload de planilha de Contagens (Conciliação de Validades).
    
    Form data:
    - file: arquivo .xlsx, .xls ou .csv
    - unidade_negocio_id: ID da unidade de negócio
    """
    permission_classes = [IsAuthenticated]
    
    def post(self, request):
        from .services import EstoqueImportService
        
        file = request.FILES.get('file')
        unidade_negocio_id = request.data.get('unidade_negocio_id')
        
        if not file:
            return Response(
                {'error': 'Arquivo não enviado'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        if not unidade_negocio_id:
            return Response(
                {'error': 'Unidade de negócio não informada'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        # Verifica extensão do arquivo
        allowed_extensions = ['.xlsx', '.xls', '.csv']
        file_ext = '.' + file.name.split('.')[-1].lower()
        if file_ext not in allowed_extensions:
            return Response(
                {'error': f'Formato não permitido. Use: {", ".join(allowed_extensions)}'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        # Verifica acesso à unidade
        user = request.user
        if not user.is_superuser:
            if not user.tem_acesso_unidade(int(unidade_negocio_id)):
                return Response(
                    {'error': 'Sem permissão para esta unidade'},
                    status=status.HTTP_403_FORBIDDEN
                )
        
        try:
            service = EstoqueImportService(int(unidade_negocio_id))
            result = service.processar_contagens(file)
            
            if result.get('success'):
                return Response(result, status=status.HTTP_200_OK)
            else:
                return Response(result, status=status.HTTP_400_BAD_REQUEST)
                
        except UnidadeNegocio.DoesNotExist:
            return Response(
                {'error': 'Unidade de negócio não encontrada'},
                status=status.HTTP_404_NOT_FOUND
            )
        except Exception as e:
            return Response(
                {'error': f'Erro ao processar arquivo: {str(e)}'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )
