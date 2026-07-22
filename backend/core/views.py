"""
Views do sistema SKU+ para a API REST.

Implementa:
- Autenticação JWT
- CRUD com filtros avançados
- Endpoints customizados para as telas do App
- Controle de acesso por unidade
"""

import pandas as pd
from django.db import transaction
from rest_framework.parsers import MultiPartParser, FormParser

from django.utils import timezone
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

from .permissions import (
    IsVendedor,
    IsGerente,
    IsDiretoria,
    IsAdmin,
    IsGerenteOuDiretoria,
    IsControle,
    CanManageSettings,
    CanReadSKU,
    CanManageUpload,
    ObjectBelongsToUserUnit,
)

from .models import (
    UnidadeNegocio,
    Usuario,
    UsuarioUnidade,
    ConfiguracaoAlerta,
    SKU,
    MovimentacaoEstoque,
    LogConsulta,
    HistoricoUpload,
    ModuloMenu,
    PermissaoMenu,
    LancamentoCriticoManual, # <-- ADICIONADO NOVO MODELO
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
    MovimentacaoEstoqueSerializer,
    LogConsultaSerializer,
    NotificacaoAlertaSerializer,
    HistoricoUploadSerializer,
    HistoricoUploadUltimoSerializer,
    MenuDinamicoSerializer,
    LancamentoCriticoManualSerializer, # <-- ADICIONADO NOVO SERIALIZER
    STATUS_CORES,
    STATUS_LABELS,
)

from .pagination import (
    SKUPagination,
    CriticidadePagination,
    HistoricoUploadPagination,
)


# =============================================================================
# MIXINS E UTILITÁRIOS
# =============================================================================
class UnidadeAccessMixin:
    """
    Mixin para filtrar querysets por unidades que o usuário tem acesso.
    Implementa o padrão "Unidade Ativa" (Multi-tenant).
    """
    
    def get_user_unidades(self):
        """Retorna IDs das unidades que o usuário pode acessar."""
        user = self.request.user
        if user.is_superuser:
            return UnidadeNegocio.objects.filter(ativo=True).values_list('id', flat=True)
        return user.get_unidades_ids()
    
    def get_unidade_ativa(self):
        """
        Retorna o ID da unidade ativa baseado no parâmetro `unidade_id`.
        Valida se o usuário tem acesso à unidade solicitada.
        Retorna None se não tiver acesso ou se não foi fornecido.
        """
        unidade_id = self.request.query_params.get('unidade_id')
        if not unidade_id:
            return None
        
        try:
            unidade_id = int(unidade_id)
        except (ValueError, TypeError):
            return None
        
        # Superusuário tem acesso a todas as unidades
        if self.request.user.is_superuser:
            if UnidadeNegocio.objects.filter(id=unidade_id, ativo=True).exists():
                return unidade_id
            return None
        
        # Usuário comum: verifica se tem acesso
        unidades_permitidas = list(self.get_user_unidades())
        if unidade_id in unidades_permitidas:
            return unidade_id
        
        return None
    
    def is_vendedor_na_unidade_ativa(self):
        """
        Verifica se o usuário é VENDEDOR na unidade ativa.
        Superusuários nunca são considerados vendedores.
        """
        user = self.request.user
        if user.is_superuser:
            return False
        
        unidade_id = self.get_unidade_ativa()
        if unidade_id is None:
            return False
        
        return user.is_vendedor(unidade_id)
    
    def filter_by_unidade(self, queryset, unidade_field='unidade_negocio'):
        """Filtra queryset pelas unidades do usuário."""
        unidades_ids = self.get_user_unidades()
        filter_kwargs = {f'{unidade_field}__id__in': unidades_ids}
        return queryset.filter(**filter_kwargs)
    
    def filter_by_unidade_ativa(self, queryset, unidade_field='unidade_negocio'):
        """
        Filtra queryset pela unidade ativa.
        Se não houver unidade ativa válida, retorna queryset vazio.
        """
        unidade_id = self.get_unidade_ativa()
        if unidade_id is None:
            return queryset.none()
        
        filter_kwargs = {f'{unidade_field}_id': unidade_id}
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
# SKU - CONSULTA DE VALIDADE E BUSCA RÁPIDA
# =============================================================================
class SKUViewSet(UnidadeAccessMixin, viewsets.ModelViewSet):
    """
    ViewSet para SKU com busca avançada.
    """
    permission_classes = [IsAuthenticated, CanReadSKU]
    pagination_class = SKUPagination
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
        )
        
        queryset = self.filter_by_unidade_ativa(queryset)
        
        search = self.request.query_params.get('search', None)
        if search:
            queryset = queryset.filter(
                Q(codigo_sku__icontains=search) |
                Q(nome_produto__icontains=search)
            )
        
        return queryset.distinct()
    
    def retrieve(self, request, *args, **kwargs):
        instance = self.get_object()
        
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
        search = request.query_params.get('search', None)
        
        if not self.get_unidade_ativa():
            return Response(
                {'detail': 'Parâmetro "unidade_id" é obrigatório e deve ser uma unidade válida.'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        if not search:
            return Response(
                {'detail': 'Parâmetro "search" é obrigatório.'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        queryset = self.get_queryset()
        
        log_consulta(
            usuario=request.user,
            tipo='VALIDADE',
            parametros={'search': search, 'unidade_id': self.get_unidade_ativa()},
            request=request
        )
        
        serializer = SKUSerializer(
            queryset,
            many=True,
            context={'request': request}
        )
        return Response(serializer.data)

    @action(detail=False, methods=['get'])
    def buscar_por_codigo(self, request):
        """
        GET /api/skus/buscar_por_codigo/?codigo=xxx&unidade_id=1
        Endpoint rápido para preencher o formulário do Controle.
        """
        codigo = request.query_params.get('codigo')
        unidade_id = self.get_unidade_ativa()

        if not codigo or not unidade_id:
            return Response({'error': 'Parâmetros "codigo" e "unidade_id" são obrigatórios.'}, status=status.HTTP_400_BAD_REQUEST)

        sku = SKU.objects.filter(codigo_sku=codigo, unidade_negocio_id=unidade_id, ativo=True).first()
        if not sku:
            return Response({'error': 'Produto não encontrado no estoque desta unidade.'}, status=status.HTTP_404_NOT_FOUND)

        return Response({
            'id': sku.id,
            'nome_produto': sku.nome_produto,
            'categoria': sku.categoria,
            'unidade_medida': sku.unidade_medida,
            'qtd_estoque_atual': sku.qtd_disponivel_venda
        })

    @action(detail=False, methods=['post'], permission_classes=[IsAuthenticated, IsAdmin])
    def limpar_banco(self, request):
        confirmacao = request.data.get('confirmacao', '')
        if confirmacao != 'CONFIRMAR EXCLUSAO':
            return Response(
                {
                    'detail': 'Confirmação inválida. Envie {"confirmacao": "CONFIRMAR EXCLUSAO"} no body.',
                    'error': 'confirmation_required'
                },
                status=status.HTTP_400_BAD_REQUEST
            )
        
        total_skus = SKU.objects.count()
        SKU.objects.all().delete()
        
        log_consulta(
            usuario=request.user,
            tipo='ADMIN_LIMPAR_BANCO',
            parametros={
                'skus_deletados': total_skus,
                'ip': request.META.get('REMOTE_ADDR'),
            },
            request=request
        )
        
        return Response({
            'success': True,
            'message': 'Banco de dados limpo com sucesso.',
            'skus_deletados': total_skus,
        })


# =============================================================================
# LANÇAMENTOS MANUAIS (CONTROLE)
# =============================================================================
class LancamentoCriticoManualViewSet(viewsets.ModelViewSet):
    """
    CRUD para a equipe de Controle lançar e gerenciar lotes críticos manualmente.
    """
    serializer_class = LancamentoCriticoManualSerializer
    # CORREÇÃO 1: Removido o IsControle daqui para não dar 403 no POST
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        unidade_id = self.request.query_params.get('unidade_id')
        qs = LancamentoCriticoManual.objects.filter(ativo=True)
        if unidade_id:
            qs = qs.filter(unidade_negocio_id=unidade_id)
        
        # Filtra para o usuário só ver lançamentos das lojas que tem acesso
        if not self.request.user.is_superuser:
            unidades_ids = self.request.user.get_unidades_ids()
            qs = qs.filter(unidade_negocio_id__in=unidades_ids)
        return qs

    def perform_create(self, serializer):
        serializer.save(usuario_lancamento=self.request.user)

    def destroy(self, request, *args, **kwargs):
        return Response(
            {'detail': 'A exclusão direta foi desativada por motivos de auditoria. Use a ação de resolução.'}, 
            status=status.HTTP_405_METHOD_NOT_ALLOWED
        )

    @action(detail=True, methods=['post'])
    def resolver(self, request, pk=None):
        lancamento = self.get_object()
        
        # CORREÇÃO 2: Validação manual de permissão blindada
        if not request.user.is_superuser:
            if not request.user.tem_acesso_unidade(lancamento.unidade_negocio_id):
                return Response({'error': 'Você não tem permissão nesta unidade.'}, status=status.HTTP_403_FORBIDDEN)
            
            papel = request.user.get_papel_unidade(lancamento.unidade_negocio_id)
            if papel == 'VENDEDOR':
                return Response({'error': 'Vendedores não podem baixar alertas.'}, status=status.HTTP_403_FORBIDDEN)

        motivo = request.data.get('motivo')
        if not motivo:
            return Response({'error': 'O motivo da baixa é obrigatório.'}, status=status.HTTP_400_BAD_REQUEST)
            
        lancamento.ativo = False 
        lancamento.motivo_resolucao = motivo
        lancamento.data_resolucao = timezone.now()
        lancamento.usuario_resolucao = request.user
        lancamento.save()
        
        log_consulta(
            usuario=request.user, 
            tipo='RESOLUCAO_CRITICO', 
            parametros={'lancamento_id': pk, 'motivo': motivo}, 
            request=request
        )
        
        return Response({'status': 'Resolvido e arquivado com sucesso.'})


# =============================================================================
# ESTOQUE INICIAL
# =============================================================================
class EstoqueViewSet(UnidadeAccessMixin, viewsets.ReadOnlyModelViewSet):
    """
    ViewSet para Estoque Inicial (somente leitura).
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
                'movimentacoes',
                queryset=MovimentacaoEstoque.objects.filter(
                    ativo=True,
                    tipo='ENTRADA',
                    status='EM_TRANSITO'
                )
            )
        )
        
        queryset = self.filter_by_unidade_ativa(queryset)
        
        search = self.request.query_params.get('search', None)
        if search:
            queryset = queryset.filter(
                Q(codigo_sku__icontains=search) |
                Q(nome_produto__icontains=search)
            )
        
        return queryset.distinct()
    
    def list(self, request, *args, **kwargs):
        response = super().list(request, *args, **kwargs)
        
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
        queryset = self.get_queryset()
        
        total_skus = queryset.count()
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
# CONFIGURAÇÃO DE ALERTA
# =============================================================================
class ConfiguracaoAlertaViewSet(viewsets.ModelViewSet):
    """
    ViewSet para ConfiguracaoAlerta.
    """
    queryset = ConfiguracaoAlerta.objects.filter(ativo=True)
    serializer_class = ConfiguracaoAlertaSerializer
    permission_classes = [IsAuthenticated, CanManageSettings]
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
    permission_classes = [IsAuthenticated, CanReadSKU]
    filter_backends = [DjangoFilterBackend, filters.OrderingFilter]
    filterset_fields = ['tipo', 'status', 'sku']
    ordering_fields = ['created_at', 'data_prevista']
    ordering = ['-created_at']
    
    def get_queryset(self):
        queryset = MovimentacaoEstoque.objects.filter(ativo=True).select_related(
            'sku',
            'unidade_origem',
            'unidade_destino',
            'usuario'
        )
        
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
# GESTÃO DE USUÁRIOS
# =============================================================================
class UsuarioViewSet(viewsets.ModelViewSet):
    """
    ViewSet para gestão de Usuários.
    """
    serializer_class = UsuarioSerializer
    permission_classes = [IsAuthenticated, IsGerenteOuDiretoria]
    filter_backends = [DjangoFilterBackend, filters.SearchFilter, filters.OrderingFilter]
    search_fields = ['first_name', 'last_name', 'email', 'username']
    ordering_fields = ['first_name', 'last_name', 'email', 'created_at']
    ordering = ['first_name', 'last_name']
    
    def get_queryset(self):
        user = self.request.user
        
        if user.is_superuser or user.is_diretoria():
            queryset = Usuario.objects.filter(is_active=True)
        else:
            unidades_ids = user.get_unidades_ids()
            queryset = Usuario.objects.filter(
                is_active=True,
                unidades__id__in=unidades_ids
            ).distinct()
        
        unidade_id = self.request.query_params.get('unidade_id')
        if unidade_id:
            queryset = queryset.filter(unidades__id=unidade_id)
        
        return queryset.prefetch_related('unidades')
    
    def get_serializer_class(self):
        if self.action == 'create':
            return UsuarioCreateSerializer
        return UsuarioSerializer
    
    @action(detail=True, methods=['post'])
    def vincular_unidade(self, request, pk=None):
        usuario = self.get_object()
        unidade_id = request.data.get('unidade_id')
        papel = request.data.get('papel', 'VENDEDOR')
        
        if not unidade_id:
            return Response({'error': 'unidade_id é obrigatório'}, status=status.HTTP_400_BAD_REQUEST)
        
        if papel not in ['VENDEDOR', 'GERENTE', 'DIRETORIA', 'CONTROLE']:
            return Response(
                {'error': 'Papel inválido. Use: VENDEDOR, GERENTE, DIRETORIA ou CONTROLE'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        if papel == 'DIRETORIA' and not request.user.is_diretoria():
            return Response(
                {'error': 'Apenas diretoria pode criar usuários DIRETORIA'},
                status=status.HTTP_403_FORBIDDEN
            )
        
        try:
            unidade = UnidadeNegocio.objects.get(id=unidade_id, ativo=True)
            
            if not request.user.is_superuser and not request.user.is_diretoria():
                if not request.user.tem_acesso_unidade(unidade.id):
                    return Response(
                        {'error': 'Você não tem acesso a esta unidade'},
                        status=status.HTTP_403_FORBIDDEN
                    )
            
            vinculo, created = UsuarioUnidade.objects.update_or_create(
                usuario=usuario,
                unidade=unidade,
                defaults={'papel': papel}
            )
            
            return Response({
                'success': True,
                'message': f'Usuário vinculado como {papel}',
                'created': created
            })
            
        except UnidadeNegocio.DoesNotExist:
            return Response({'error': 'Unidade não encontrada'}, status=status.HTTP_404_NOT_FOUND)
    
    @action(detail=True, methods=['post'])
    def desvincular_unidade(self, request, pk=None):
        usuario = self.get_object()
        unidade_id = request.data.get('unidade_id')
        
        if not unidade_id:
            return Response({'error': 'unidade_id é obrigatório'}, status=status.HTTP_400_BAD_REQUEST)
        
        try:
            vinculo = UsuarioUnidade.objects.get(
                usuario=usuario,
                unidade_id=unidade_id
            )
            
            if not request.user.is_superuser and not request.user.is_diretoria():
                if not request.user.tem_acesso_unidade(int(unidade_id)):
                    return Response(
                        {'error': 'Você não tem acesso a esta unidade'},
                        status=status.HTTP_403_FORBIDDEN
                    )
            
            vinculo.delete()
            return Response({'success': True, 'message': 'Vínculo removido com sucesso'})
            
        except UsuarioUnidade.DoesNotExist:
            return Response({'error': 'Vínculo não encontrado'}, status=status.HTTP_404_NOT_FOUND)


# =============================================================================
# LOG DE CONSULTAS (somente leitura)
# =============================================================================
class LogConsultaViewSet(viewsets.ReadOnlyModelViewSet):
    """
    ViewSet para LogConsulta (somente leitura).
    """
    queryset = LogConsulta.objects.all().select_related('usuario')
    serializer_class = LogConsultaSerializer
    permission_classes = [IsAuthenticated]
    filter_backends = [DjangoFilterBackend, filters.OrderingFilter]
    filterset_fields = ['tipo_consulta', 'usuario']
    ordering = ['-created_at']
    
    def get_queryset(self):
        if not self.request.user.is_superuser:
            return LogConsulta.objects.filter(usuario=self.request.user)
        return super().get_queryset()


# =============================================================================
# UPLOAD DE ARQUIVOS - ESTOQUE FEFO
# =============================================================================
ALLOWED_UPLOAD_EXTENSIONS = {'.xlsx', '.xls', '.csv'}

def _validar_extensao_arquivo(file, field_name: str) -> str | None:
    ext = '.' + file.name.rsplit('.', 1)[-1].lower() if '.' in file.name else ''
    if ext not in ALLOWED_UPLOAD_EXTENSIONS:
        allowed = ', '.join(sorted(ALLOWED_UPLOAD_EXTENSIONS))
        return f'"{field_name}": formato "{ext or "sem extensão"}" não permitido. Use: {allowed}.'
    return None

class UploadEstoqueView(APIView):
    """
    POST /api/upload/grade-020502/
    """
    permission_classes = [IsAuthenticated, CanManageUpload]

    def post(self, request):
        from .upload_service import UploadFefoService

        file_020502 = request.FILES.get('file_020502')
        file_020304 = request.FILES.get('file_020304')
        file_nri    = request.FILES.get('file_nri')
        unidade_negocio_id = request.data.get('unidade_negocio_id')

        erros_presenca = {}
        if not file_020502:
            erros_presenca['file_020502'] = 'Arquivo obrigatório não enviado.'
        if not file_020304:
            erros_presenca['file_020304'] = 'Arquivo obrigatório não enviado.'
        if not file_nri:
            erros_presenca['file_nri'] = 'Arquivo obrigatório não enviado.'
        if not unidade_negocio_id:
            erros_presenca['unidade_negocio_id'] = 'Campo obrigatório não informado.'

        if erros_presenca:
            return Response({'errors': erros_presenca}, status=status.HTTP_400_BAD_REQUEST)

        erros_extensao = {}
        for field, file in [
            ('file_020502', file_020502),
            ('file_020304', file_020304),
            ('file_nri',    file_nri),
        ]:
            erro = _validar_extensao_arquivo(file, field)
            if erro:
                erros_extensao[field] = erro

        if erros_extensao:
            return Response({'errors': erros_extensao}, status=status.HTTP_400_BAD_REQUEST)

        user = request.user
        try:
            unidade_negocio_id_int = int(unidade_negocio_id)
        except (ValueError, TypeError):
            return Response(
                {'errors': {'unidade_negocio_id': 'Valor inválido; esperado um inteiro.'}},
                status=status.HTTP_400_BAD_REQUEST
            )

        if not user.is_superuser:
            if not user.tem_acesso_unidade(unidade_negocio_id_int):
                return Response({'error': 'Sem permissão para esta unidade.'}, status=status.HTTP_403_FORBIDDEN)

        nome_arquivos = ' | '.join([file_020502.name, file_020304.name, file_nri.name])

        try:
            unidade = UnidadeNegocio.objects.get(id=unidade_negocio_id_int)
            result = UploadFefoService.processar_estoque_fefo(
                file_020502=file_020502,
                file_020304=file_020304,
                file_nri=file_nri,
                unidade_negocio_id=unidade_negocio_id_int,
            )

            skus_atualizados = result.get('skus_atualizados', 0)

            HistoricoUpload.objects.create(
                tipo_arquivo='FEFO',
                usuario=user,
                unidade_negocio=unidade,
                status='SUCESSO' if result.get('success') else 'ERRO',
                linhas_processadas=skus_atualizados,
                nome_arquivo=nome_arquivos,
                mensagem_erro=result.get('error') if not result.get('success') else None,
            )

            if result.get('success'):
                return Response(result, status=status.HTTP_200_OK)
            else:
                return Response(result, status=status.HTTP_400_BAD_REQUEST)

        except UnidadeNegocio.DoesNotExist:
            return Response({'error': 'Unidade de negócio não encontrada.'}, status=status.HTTP_404_NOT_FOUND)
        except Exception as e:
            try:
                unidade = UnidadeNegocio.objects.get(id=unidade_negocio_id_int)
                HistoricoUpload.objects.create(
                    tipo_arquivo='FEFO',
                    usuario=user,
                    unidade_negocio=unidade,
                    status='ERRO',
                    linhas_processadas=0,
                    nome_arquivo=nome_arquivos,
                    mensagem_erro=str(e),
                )
            except Exception:
                pass

            return Response({'error': f'Erro ao processar arquivos: {str(e)}'}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# =============================================================================
# HISTÓRICO DE UPLOAD
# =============================================================================
class HistoricoUploadViewSet(UnidadeAccessMixin, viewsets.ReadOnlyModelViewSet):
    """
    ViewSet somente leitura para HistoricoUpload.
    """
    serializer_class = HistoricoUploadSerializer
    permission_classes = [IsAuthenticated]
    pagination_class = HistoricoUploadPagination
    filter_backends = [DjangoFilterBackend, filters.OrderingFilter]
    filterset_fields = ['tipo_arquivo', 'status', 'unidade_negocio']
    ordering_fields = ['created_at']
    ordering = ['-created_at']
    
    def get_queryset(self):
        queryset = HistoricoUpload.objects.filter(ativo=True).select_related('usuario', 'unidade_negocio')
        
        unidade_id = self.get_unidade_ativa()
        if unidade_id:
            queryset = queryset.filter(unidade_negocio_id=unidade_id)
        else:
            unidades_ids = self.get_user_unidades()
            queryset = queryset.filter(unidade_negocio_id__in=unidades_ids)
        
        return queryset
    
    @action(detail=False, methods=['get'])
    def ultimo(self, request):
        unidade_id = self.get_unidade_ativa()
        if unidade_id is None:
            return Response({'error': 'Parâmetro unidade_id é obrigatório'}, status=status.HTTP_400_BAD_REQUEST)
        
        ultimo_upload = HistoricoUpload.objects.filter(
            ativo=True,
            unidade_negocio_id=unidade_id,
            status='SUCESSO'
        ).order_by('-created_at').first()
        
        if ultimo_upload:
            return Response({
                'data_upload': ultimo_upload.created_at,
                'tipo_arquivo': ultimo_upload.tipo_arquivo,
                'tipo_arquivo_display': ultimo_upload.get_tipo_arquivo_display(),
            })
        else:
            return Response({
                'data_upload': None,
                'tipo_arquivo': None,
                'tipo_arquivo_display': None,
            })


# =============================================================================
# RELATÓRIO DE CRITICIDADE (LIDO EXCLUSIVAMENTE DOS LANÇAMENTOS MANUAIS)
# =============================================================================
class RelatorioCriticidadeView(UnidadeAccessMixin, APIView):
    """
    GET /api/relatorio-criticidade/?unidade_id=1
    Retorna os itens críticos gerenciados estritamente pelo Controle.
    """
    permission_classes = [IsAuthenticated]
    
    def get(self, request):
        unidade_id = self.get_unidade_ativa()
        if not unidade_id:
            return Response({'detail': 'Parâmetro unidade_id é obrigatório.'}, status=status.HTTP_400_BAD_REQUEST)

        user = request.user
        is_vendedor = False
        if not user.is_superuser:
            is_vendedor = user.is_vendedor(unidade_id)

        try:
            unidade = UnidadeNegocio.objects.get(id=unidade_id, ativo=True)
            config = getattr(unidade, 'configuracao_alerta', None)
        except Exception:
            config = None

        if not config:
            config = ConfiguracaoAlerta.objects.filter(unidade__isnull=True, ativo=True).first()
        
        dias_bloqueado = config.dias_bloqueado if config else 30

        lancamentos = LancamentoCriticoManual.objects.filter(
            unidade_negocio_id=unidade_id,
            ativo=True
        ).select_related('sku', 'unidade_negocio')

        bloqueados_list = []
        risco_vencimento_list = []
        pre_bloqueio_list = []

        hoje = date.today()

        for item in lancamentos:
            dias_restantes = (item.data_validade - hoje).days
            
            if dias_restantes <= 0:
                status_texto = 'Bloqueado'
                status_color = '#000000'
                categoria_destino = 'BLOQUEADO'
            elif dias_restantes <= dias_bloqueado:
                status_texto = 'Risco de Vencimento'
                status_color = '#F44336'
                categoria_destino = 'RISCO_VENCIMENTO'
            else:
                status_texto = 'Pré-Bloqueio'
                status_color = '#FFC107'
                categoria_destino = 'PRE_BLOQUEIO'

            # Injetamos campos zerados para satisfazer o Flutter!
            sku_data = {
                'id': item.id,  # ID do Lancamento
                'codigo_sku': item.sku.codigo_sku,
                'nome_produto': item.sku.nome_produto,
                'categoria': item.sku.categoria,
                'unidade_medida': item.sku.unidade_medida,
                'fator_conversao': item.sku.fator_conversao,
                'qtd_total_020502': 0,
                'qtd_buffer_020304': 0,
                'qtd_disponivel_venda': item.quantidade_critica, 
                'validade_inicio_range': item.data_validade.strftime('%Y-%m-%d'),
                'validade_fim_range': item.data_validade.strftime('%Y-%m-%d'),
                'dias_restantes': dias_restantes,
                'status_texto': status_texto,
                'status_color': status_color,
                'imagem_url': None,
                'unidade_codigo': item.unidade_negocio.codigo_unb,
            }

            if categoria_destino == 'BLOQUEADO':
                if not is_vendedor:
                    bloqueados_list.append(sku_data)
            elif categoria_destino == 'RISCO_VENCIMENTO':
                risco_vencimento_list.append(sku_data)
            elif categoria_destino == 'PRE_BLOQUEIO':
                pre_bloqueio_list.append(sku_data)

        log_consulta(usuario=request.user, tipo='CRITICIDADE', parametros={'unidade_id': unidade_id}, request=request)

        return Response({
            'resumo': {
                'total_bloqueados': len(bloqueados_list),
                'total_pre_bloqueio': len(pre_bloqueio_list),
            },
            'bloqueados': bloqueados_list,
            'risco_vencimento': risco_vencimento_list,
            'pre_bloqueio': pre_bloqueio_list,
        })


# =============================================================================
# NOTIFICAÇÕES DE ALERTA DE VALIDADE (SININHO ALINHADO)
# =============================================================================
class NotificacoesAlertaView(UnidadeAccessMixin, APIView):
    """
    GET /api/notificacoes/
    Lê os lançamentos estritamente manuais para exibir no sininho.
    """
    permission_classes = [IsAuthenticated]
    
    def get(self, request):
        unidade_id = self.get_unidade_ativa()
        if unidade_id is None:
            return Response({'error': 'Parâmetro unidade_id é obrigatório'}, status=status.HTTP_400_BAD_REQUEST)
        
        try:
            unidade = UnidadeNegocio.objects.get(id=unidade_id, ativo=True)
            config = getattr(unidade, 'configuracao_alerta', None)
        except Exception:
            config = None
        
        if not config:
            config = ConfiguracaoAlerta.objects.filter(unidade__isnull=True, ativo=True).first()
        
        dias_pre_bloqueio = config.dias_pre_bloqueio if config else 60
        dias_bloqueado = config.dias_bloqueado if config else 30
        dias_extremamente_critico = config.dias_extremamente_critico if config else 7
        
        hoje = date.today()
        
        lancamentos = LancamentoCriticoManual.objects.filter(
            ativo=True,
            unidade_negocio_id=unidade_id,
        ).select_related('sku', 'unidade_negocio').order_by('data_validade')
        
        notificacoes = []
        for item in lancamentos:
            dias_restantes = (item.data_validade - hoje).days
            
            if dias_restantes > dias_pre_bloqueio:
                continue

            if dias_restantes <= 0:
                status_val = 'VENCIDO'
            elif dias_restantes <= dias_extremamente_critico:
                status_val = 'EXTREMAMENTE_CRITICO'
            elif dias_restantes <= dias_bloqueado:
                status_val = 'BLOQUEADO'
            else:
                status_val = 'PRE_BLOQUEIO'
            
            notificacoes.append({
                'sku_id': item.sku.id,
                'sku_codigo': item.sku.codigo_sku,
                'sku_nome': item.sku.nome_produto,
                'data_validade': item.data_validade.strftime('%Y-%m-%d'), # Formato de string blindado
                'dias_restantes': dias_restantes,
                'qtd_estoque': item.quantidade_critica,
                'status': status_val,
                'status_label': STATUS_LABELS.get(status_val, 'Indefinido'),
                'status_cor': STATUS_CORES.get(status_val, '#9E9E9E'),
                'unidade_id': item.unidade_negocio.id,
                'unidade_codigo': item.unidade_negocio.codigo_unb,
                'unidade_nome': item.unidade_negocio.nome,
            })
        
        resumo = {
            'extremamente_critico': sum(1 for n in notificacoes if n['status'] in ['EXTREMAMENTE_CRITICO', 'VENCIDO']),
            'bloqueado': sum(1 for n in notificacoes if n['status'] == 'BLOQUEADO'),
            'pre_bloqueio': sum(1 for n in notificacoes if n['status'] == 'PRE_BLOQUEIO'),
            'total': len(notificacoes),
        }
        
        # Enviamos o dicionário puro, fugindo da censura do Serializer
        return Response({
            'resumo': resumo,
            'notificacoes': notificacoes, 
        })


# =============================================================================
# UPLOAD DE PLANILHA DE ITENS CRÍTICOS (AUTOMATIZADO)
# =============================================================================
class UploadPlanilhaCriticosView(APIView):
    """
    POST /api/upload-criticos/
    Recebe a planilha, faz a varredura atômica linha a linha e aplica o Ground Zero.
    """
    permission_classes = [IsAuthenticated, CanManageUpload]
    parser_classes = (MultiPartParser, FormParser)

    def post(self, request):
        arquivo = request.FILES.get('file')
        unidade_id = request.data.get('unidade_id')

        if not arquivo or not unidade_id:
            return Response({'error': 'Arquivo de planilha e Unidade são obrigatórios.'}, status=status.HTTP_400_BAD_REQUEST)

        try:
            unidade = UnidadeNegocio.objects.get(id=unidade_id, ativo=True)
        except UnidadeNegocio.DoesNotExist:
            return Response({'error': 'Unidade de Negócio não encontrada.'}, status=status.HTTP_404_NOT_FOUND)

        if not request.user.is_superuser:
            if not request.user.tem_acesso_unidade(unidade.id):
                return Response({'error': 'Sem permissão para importar nesta unidade.'}, status=status.HTTP_403_FORBIDDEN)

        try:
            # Lê o Excel para a memória
            df = pd.read_excel(arquivo)
            
            # Validação dos cabeçalhos exigidos
            colunas_esperadas = ['Cod produto', 'Qtd', 'Data Vencto', 'Data Recebimento']
            colunas_planilha = [str(col).strip() for col in df.columns]
            
            for col in colunas_esperadas:
                if col not in colunas_planilha:
                    return Response({'error': f'A coluna obrigatória "{col}" não foi encontrada na planilha.'}, status=status.HTTP_400_BAD_REQUEST)

            erros = []
            novos_lancamentos = []
            
            with transaction.atomic():
                for index, row in df.iterrows():
                    linha_real = index + 2 
                    
                    cod_produto = str(row.get('Cod produto', '')).strip()
                    if pd.isna(row.get('Cod produto')) or not cod_produto:
                        continue 
                        
                    qtd = row.get('Qtd')
                    dt_venc = row.get('Data Vencto')
                    dt_rec = row.get('Data Recebimento')

                    sku = SKU.objects.filter(codigo_sku=cod_produto, unidade_negocio=unidade, ativo=True).first()
                    if not sku:
                        erros.append(f"Linha {linha_real}: SKU {cod_produto} não encontrado nesta unidade.")
                        continue
                        
                    try:
                        qtd_int = int(qtd)
                        if qtd_int <= 0: raise ValueError
                    except (ValueError, TypeError):
                        erros.append(f"Linha {linha_real}: Quantidade inválida.")
                        continue

                    try:
                        # CORREÇÃO DA DATA: Forçando a leitura no padrão Brasileiro (Dia/Mês/Ano)
                        dt_venc_obj = pd.to_datetime(dt_venc, dayfirst=True).date()
                    except Exception:
                        erros.append(f"Linha {linha_real}: Data de Vencimento com formato inválido.")
                        continue
                        
                    dt_rec_obj = None
                    if pd.notna(dt_rec):
                        try:
                            dt_rec_obj = pd.to_datetime(dt_rec, dayfirst=True).date()
                        except Exception:
                            erros.append(f"Linha {linha_real}: Data de Recebimento com formato inválido.")
                            continue

                    novos_lancamentos.append(
                        LancamentoCriticoManual(
                            sku=sku,
                            unidade_negocio=unidade,
                            quantidade_critica=qtd_int,
                            data_validade=dt_venc_obj,
                            origem='PLANILHA',
                            data_recebimento=dt_rec_obj,
                            usuario_lancamento=request.user,
                            ativo=True
                        )
                    )

                if erros:
                    raise ValueError("Erros de validação")

                lancamentos_antigos = LancamentoCriticoManual.objects.filter(
                    unidade_negocio=unidade, 
                    ativo=True
                )
                lancamentos_antigos.update(
                    ativo=False,
                    motivo_resolucao='Sobrescrito por Upload de Planilha',
                    data_resolucao=timezone.now(),
                    usuario_resolucao=request.user
                )

                LancamentoCriticoManual.objects.bulk_create(novos_lancamentos)

                log_consulta(
                    usuario=request.user, 
                    tipo='UPLOAD_CRITICOS', 
                    parametros={'unidade_id': unidade.id, 'qtd_linhas': len(novos_lancamentos)}, 
                    request=request
                )

            return Response({
                'success': True, # <--- A MÁGICA ESTÁ AQUI: O Flutter agora vai reconhecer o sucesso!
                'status': 'Upload concluído com sucesso.',
                'linhas_processadas': len(novos_lancamentos)
            }, status=status.HTTP_201_CREATED)

        except ValueError as e:
            if str(e) == "Erros de validação":
                return Response({'error': 'A importação foi abortada.', 'detalhes': erros}, status=status.HTTP_400_BAD_REQUEST)
            return Response({'error': 'Erro no processamento dos dados.'}, status=status.HTTP_400_BAD_REQUEST)
        except Exception as e:
            return Response({'error': f'Erro inesperado na leitura da planilha: {str(e)}'}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# =============================================================================
# MENUS DINÂMICOS (CONTROLE DE ACESSO)
# =============================================================================
class MeusMenusView(APIView):
    """
    GET /api/menus/meus-menus/?unidade_id=X
    """
    permission_classes = [IsAuthenticated]

    def get(self, request, *args, **kwargs):
        unidade_id = request.query_params.get('unidade_id')
        if not unidade_id:
            return Response({'error': 'Parâmetro unidade_id é obrigatório.'}, status=status.HTTP_400_BAD_REQUEST)
            
        try:
            unidade_id = int(unidade_id)
        except ValueError:
            return Response({'error': 'unidade_id inválido.'}, status=status.HTTP_400_BAD_REQUEST)
            
        usuario = request.user
        papel = usuario.get_papel_unidade(unidade_id)
        
        if usuario.is_superuser:
            modulos = ModuloMenu.objects.filter(globalmente_ativo=True)
        else:
            if not papel:
                return Response([]) 
                
            modulos_permitidos_ids = PermissaoMenu.objects.filter(
                papel=papel,
                visivel=True,
                modulo__globalmente_ativo=True
            ).values_list('modulo_id', flat=True)
            
            modulos = ModuloMenu.objects.filter(id__in=modulos_permitidos_ids)
            
        serializer = MenuDinamicoSerializer(modulos, many=True)
        return Response(serializer.data)